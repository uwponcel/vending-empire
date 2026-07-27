--!strict
--[[
	Owns placed machines: buying them, rebuilding them on join, and paying out collects.

	COLLECT HAS NO REMOTE. It runs off `ProximityPromptService.PromptTriggered`, which the
	engine raises on the server with the prompt and the player who activated it. There is no
	payload, so there is nothing for a client to forge: the most repeated action in the game
	cannot be sent a coin amount, a machine it does not own, or a machine that does not exist.

	What a client CAN do is activate a prompt it should not be able to reach, or activate one
	repeatedly, because `MaxActivationDistance` is enforced client-side and activation is a
	network message. So every trigger is re-checked here for ownership, distance, and
	cooldown. The prompt's range is a convenience that keeps the button from appearing where
	the server would refuse; it is not the check.

	Nothing in here ticks. A machine's pending coins are derived from `lastCollectAt` at the
	moment they are asked for, and the model's attributes are rewritten only when that
	timestamp actually moves. See Lib/Accrual for the two rules that make the arithmetic
	safe.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnalyticsService = require(script.Parent.AnalyticsService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local MachineModel = require(script.Parent.MachineModel)
local PlotService = require(script.Parent.PlotService)
local Sync = require(script.Parent.Parent.Net.Sync)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Machines = require(Shared.Config.Machines)
local Plots = require(Shared.Config.Plots)
local Accrual = require(Shared.Lib.Accrual)
local PlotLayout = require(Shared.Lib.PlotLayout)
local PlotState = require(Shared.Lib.PlotState)
local ProfileSchema = require(Shared.Lib.ProfileSchema)
local Result = require(Shared.Lib.Result)
local UpgradeCurve = require(Shared.Lib.UpgradeCurve)

--[[
	Slack on the server's distance check, in studs.

	The prompt measures from the character to the prompt's parent using the engine's own
	rule; this measures from HumanoidRootPart to the body's centre. Those differ by roughly a
	character's half-height, and the position the server holds lags the client's by whatever
	the player's ping is. Without slack, a player standing exactly at the edge of a prompt
	that is visibly lit would be refused, which reads as the game being broken. Four studs
	covers both effects and is still nowhere near remote-collect range.
]]
local DISTANCE_TOLERANCE_STUDS = 4

--- How long to wait for a plot claim before giving up on rebuilding a player's machines.
local PLOT_WAIT_TIMEOUT = 30

local MachineService = {}

MachineService.Rejection = {
	noProfile = "no_profile",
	noPlot = "no_plot",
	unknownMachine = "unknown_machine",
	plotFull = "plot_full",
	notOwner = "not_owner",
	tooFar = "too_far",
	nothingToCollect = "nothing_to_collect",
	upgradeCooldown = "upgrade_cooldown",
}

--[[
	Which plot each player's machines were built onto.

	Tracked here rather than read from PlotService on the way out. PlotService clears its own
	ownership in its `PlayerRemoving` handler, and connection order between the two services
	is not something to depend on, so by the time this one ran the plot index could already
	be gone and the models would be left standing on a plot the next player claims.
]]
local builtOnPlot: { [Player]: number? } = {}

--- Last collect per machine, keyed by player then slot. os.clock, never persisted.
local lastCollectClock: { [Player]: { [number]: number } } = {}
--- Last upgrade attempt per machine, keyed by player then slot. os.clock, never persisted.
local lastUpgradeClock: { [Player]: { [number]: number } } = {}

local function slotCount(): number
	return PlotLayout.slotCount(Plots)
end

--[[
	Rebuilds every machine in a profile onto a plot.

	Records whose type no longer exists in config are skipped rather than fatal, matching
	Sync: retiring a machine should be a content decision, not an outage for everyone who
	owns one.
]]
local function rebuild(player: Player, data: ProfileSchema.Data, plotIndex: number): number
	local built = 0

	for _, record in data.machines do
		local config = Machines.byId[record.typeId]
		local effective = Sync.effectiveFor(record, data.prestige.multiplier)
		if config == nil or effective == nil then
			warn(`[MachineService] {player.Name} owns unknown machine type {record.typeId}`)
			continue
		end

		local model = MachineModel.build({
			config = config,
			plotIndex = plotIndex,
			slot = record.slot,
			level = record.level,
			rate = effective.rate,
			capacity = effective.capacity,
			lastCollectAt = record.lastCollectAt,
			ownerUserId = player.UserId,
		})

		if model then
			built += 1
		end
	end

	return built
end

--[[
	Buys a machine and puts it in the world.

	Every rule is checked before any coin moves, so there is no path that debits and then
	fails. Nothing between the debit and the insert yields, which is what makes two purchases
	arriving in the same frame safe.
]]
function MachineService.buy(
	player: Player,
	typeId: string,
	requestedSlot: number?
): Result.Result<ProfileSchema.MachineRecord>
	local profile = DataService.get(player)
	if profile == nil then
		return Result.err(MachineService.Rejection.noProfile)
	end

	local plotIndex = builtOnPlot[player]
	if plotIndex == nil then
		return Result.err(MachineService.Rejection.noPlot)
	end

	local config = Machines.byId[typeId]
	if config == nil then
		return Result.err(MachineService.Rejection.unknownMachine)
	end

	local data: ProfileSchema.Data = profile.Data
	local slot = requestedSlot or PlotState.firstFreeSlot(data, slotCount())
	if slot == nil then
		return Result.err(MachineService.Rejection.plotFull)
	end

	local rejection = PlotState.purchaseRejection(data, config, slot, slotCount())
	if rejection then
		return Result.err(rejection)
	end

	local debited = EconomyService.debit(player, config.cost, `buy:{typeId}`)
	if debited.tag == "err" then
		return Result.err(debited.reason)
	end

	local record: ProfileSchema.MachineRecord = {
		slot = slot,
		typeId = typeId,
		level = 1,
		--[[
			Starts accruing from now, so a machine is never bought already full. Wall clock,
			because this value has to survive a rejoin for offline earnings to work at all.
		]]
		lastCollectAt = os.time(),
	}
	PlotState.insert(data.machines, record)

	local effective = Sync.effectiveFor(record, data.prestige.multiplier)
	if effective then
		MachineModel.build({
			config = config,
			plotIndex = plotIndex,
			slot = slot,
			level = record.level,
			rate = effective.rate,
			capacity = effective.capacity,
			lastCollectAt = record.lastCollectAt,
			ownerUserId = player.UserId,
		})
	end

	print(`[MachineService] {player.Name} bought {typeId} on slot {slot} of plot {plotIndex}`)
	Sync.push(player)
	AnalyticsService.machineBought(player)

	return Result.ok(record)
end

--- Distance from the player's character to a machine, or nil if they have no character yet.
local function distanceTo(player: Player, model: Model): number?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local body = model.PrimaryPart

	if root == nil or not root:IsA("BasePart") or body == nil then
		return nil
	end

	return (root.Position - body.Position).Magnitude
end

--[[
	Upgrades one owned machine by one level.

	The client sends the level it saw, not the level it wants. PlotState compares that value
	to the saved record so two queued requests cannot both spend against one displayed price.
	All checks and the mutation are synchronous, matching the purchase transaction.
]]
function MachineService.upgrade(
	player: Player,
	slot: number,
	expectedLevel: number
): Result.Result<ProfileSchema.MachineRecord>
	local profile = DataService.get(player)
	if profile == nil then
		return Result.err(MachineService.Rejection.noProfile)
	end

	local plotIndex = builtOnPlot[player]
	if plotIndex == nil then
		return Result.err(MachineService.Rejection.noPlot)
	end

	local data: ProfileSchema.Data = profile.Data
	local record = PlotState.atSlot(data.machines, slot)
	local config = record and Machines.byId[record.typeId]
	if record == nil or config == nil then
		local rejection = PlotState.upgradeRejection(
			data,
			slot,
			expectedLevel,
			slotCount(),
			0,
			Economy.upgrade.maxLevel
		)
		return Result.err(rejection or MachineService.Rejection.unknownMachine)
	end

	local canUpgrade = UpgradeCurve.canUpgrade(record.level, Economy.upgrade)
	local cost = if canUpgrade
		then UpgradeCurve.upgradeCost(config.cost, record.level, Economy.upgrade)
		else 0
	local rejection = PlotState.upgradeRejection(
		data,
		slot,
		expectedLevel,
		slotCount(),
		cost,
		Economy.upgrade.maxLevel
	)
	if rejection then
		return Result.err(rejection)
	end

	local model = MachineModel.find(plotIndex, slot)
	if model == nil then
		return Result.err(MachineService.Rejection.unknownMachine)
	end

	local distance = distanceTo(player, model)
	if distance == nil or distance > Economy.collect.rangeStuds + DISTANCE_TOLERANCE_STUDS then
		return Result.err(MachineService.Rejection.tooFar)
	end

	local clocks = lastUpgradeClock[player]
	if clocks == nil then
		clocks = {}
		lastUpgradeClock[player] = clocks
	end

	local now = os.clock()
	local previous = clocks[slot]
	if previous ~= nil and now - previous < Economy.upgrade.cooldownSeconds then
		return Result.err(MachineService.Rejection.upgradeCooldown)
	end
	clocks[slot] = now

	local upgradedLevel = record.level + 1
	local currentEffective =
		UpgradeCurve.effective(config, record.level, Economy.upgrade, data.prestige.multiplier)
	local effective =
		UpgradeCurve.effective(config, upgradedLevel, Economy.upgrade, data.prestige.multiplier)
	local rebasedLastCollectAt = Accrual.rebaseLastCollectAt(
		currentEffective.rate,
		currentEffective.capacity,
		record.lastCollectAt,
		effective.rate,
		os.time()
	)

	local debited =
		EconomyService.debit(player, cost, `upgrade:{record.typeId}:level:{upgradedLevel}`)
	if debited.tag == "err" then
		return Result.err(debited.reason)
	end

	record.lastCollectAt = rebasedLastCollectAt
	record.level = upgradedLevel
	MachineModel.applyState(
		model,
		record.level,
		effective.rate,
		effective.capacity,
		record.lastCollectAt
	)

	print(
		`[MachineService] {player.Name} upgraded {record.typeId} on slot {slot} `
			.. `to level {record.level}`
	)
	Sync.push(player)
	AnalyticsService.upgraded(player)

	return Result.ok(record)
end

local function onCollect(player: Player, model: Model): Result.Result<number>
	local slot = model:GetAttribute("Slot")
	if type(slot) ~= "number" then
		return Result.err(MachineService.Rejection.unknownMachine)
	end

	-- Ownership from the server's own table, never from the model's OwnerUserId attribute.
	-- That attribute exists so clients can render labels, which means it replicates, which
	-- means it is not evidence of anything.
	local plotIndex = builtOnPlot[player]
	if plotIndex == nil or MachineModel.find(plotIndex, slot) ~= model then
		return Result.err(MachineService.Rejection.notOwner)
	end

	local distance = distanceTo(player, model)
	if distance == nil or distance > Economy.collect.rangeStuds + DISTANCE_TOLERANCE_STUDS then
		return Result.err(MachineService.Rejection.tooFar)
	end

	local profile = DataService.get(player)
	if profile == nil then
		return Result.err(MachineService.Rejection.noProfile)
	end

	local data: ProfileSchema.Data = profile.Data
	local record = PlotState.atSlot(data.machines, slot)
	if record == nil then
		return Result.err(MachineService.Rejection.unknownMachine)
	end

	local effective = Sync.effectiveFor(record, data.prestige.multiplier)
	if effective == nil then
		return Result.err(MachineService.Rejection.unknownMachine)
	end

	local collected =
		Accrual.collect(effective.rate, effective.capacity, record.lastCollectAt, os.time())

	if collected.amount <= 0 then
		--[[
			Not an error, and deliberately does not move the timestamp. Accrual only advances
			`lastCollectAt` by the time it actually paid for, so a player mashing E on a slow
			machine loses nothing: the fraction of a coin is still there next time.
		]]
		return Result.err(MachineService.Rejection.nothingToCollect)
	end

	local credited = EconomyService.credit(player, collected.amount, "collect")
	if credited.tag == "err" then
		return Result.err(credited.reason)
	end

	record.lastCollectAt = collected.lastCollectAt
	MachineModel.applyState(
		model,
		record.level,
		effective.rate,
		effective.capacity,
		record.lastCollectAt
	)
	Sync.push(player)
	AnalyticsService.collected(player)

	return Result.ok(collected.amount)
end

--[[
	Server-side handler for every prompt in the game.

	One connection rather than one per machine, so nothing has to be disconnected when a
	machine is destroyed and a leaked connection cannot hold a reference to a removed model.
]]
local function onPromptTriggered(prompt: ProximityPrompt, player: Player): ()
	if prompt.Name ~= "CollectPrompt" then
		return
	end

	local model = prompt:FindFirstAncestorOfClass("Model")
	if model == nil then
		return
	end

	local slot = model:GetAttribute("Slot")
	if type(slot) ~= "number" then
		return
	end

	--[[
		Cooldown before anything else, and silent. This is the only rate limit on a path with
		no remote to throttle, so it has to be cheap enough to survive being spammed, and it
		must not answer: replying to a flood is how a flood becomes an amplifier.
	]]
	local clocks = lastCollectClock[player]
	if clocks == nil then
		clocks = {}
		lastCollectClock[player] = clocks
	end

	local now = os.clock()
	local previous = clocks[slot]
	if previous ~= nil and now - previous < Economy.collect.cooldownSeconds then
		return
	end
	clocks[slot] = now

	local outcome = onCollect(player, model)
	if outcome.tag == "err" and outcome.reason ~= MachineService.Rejection.nothingToCollect then
		-- A legitimate client cannot produce these, so they are worth seeing in the log.
		warn(`[MachineService] rejected collect from {player.Name}: {outcome.reason}`)
	end
end

--[[
	Yields until the player has a plot, or nil if they leave or it never arrives.

	Polled rather than driven by a PlotService callback. PlotService claims plots from its own
	PlayerAdded connection, and the order two connections on the same signal run in is not a
	contract worth building on.

	Split into its own function so the result narrows. A `while plotIndex == nil` loop that
	reassigns the variable it tests leaves it `number?` afterwards as far as the analyzer is
	concerned, and every use downstream then needs a cast.
]]
local function waitForPlot(player: Player): number?
	local deadline = os.clock() + PLOT_WAIT_TIMEOUT

	while true do
		local plotIndex = PlotService.getPlot(player)
		if plotIndex ~= nil then
			return plotIndex
		end
		if player.Parent ~= Players or os.clock() >= deadline then
			return nil
		end
		task.wait(0.1)
	end
end

--- Waits for both the profile and the plot claim, then rebuilds the player's machines.
local function onPlayerAdded(player: Player): ()
	local profile = DataService.waitFor(player)
	if profile == nil then
		return
	end

	local plotIndex = waitForPlot(player)
	if plotIndex == nil then
		warn(`[MachineService] {player.Name} never got a plot; machines not rebuilt`)
		return
	end

	builtOnPlot[player] = plotIndex

	local built = rebuild(player, profile.Data, plotIndex)
	print(`[MachineService] rebuilt {built} machine(s) for {player.Name} on plot {plotIndex}`)

	Sync.push(player)
end

local function onPlayerRemoving(player: Player): ()
	local plotIndex = builtOnPlot[player]
	if plotIndex then
		MachineModel.clearPlot(plotIndex)
	end

	builtOnPlot[player] = nil
	lastCollectClock[player] = nil
	lastUpgradeClock[player] = nil
end

function MachineService.start(): ()
	ProximityPromptService.PromptTriggered:Connect(onPromptTriggered)

	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
	end)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return MachineService
