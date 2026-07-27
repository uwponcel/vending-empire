--!strict
--[[
	Builds and sends the client's mirror of a player's authoritative state.

	One snapshot, whole, on every change. See the payload rules in shared/Net/Remotes for
	why this is not a delta stream.

	Nothing here is called automatically. Services mutate, then publish once the whole
	operation is consistent. A purchase debits coins and inserts a machine; publishing
	between those two would send the client a snapshot with the coins gone and no machine
	to show for them, which reads as a bug even though it lasts one frame.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(script.Parent.Parent.Services.DataService)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Machines = require(Shared.Config.Machines)
local Plots = require(Shared.Config.Plots)
local PlotLayout = require(Shared.Lib.PlotLayout)
local ProfileSchema = require(Shared.Lib.ProfileSchema)
local UpgradeCurve = require(Shared.Lib.UpgradeCurve)
local Remotes = require(Shared.Net.Remotes)

local Sync = {}

--[[
	Effective rate and capacity for one saved record, or nil if its type no longer exists.

	A missing type is survivable rather than fatal on purpose. Retiring a machine from
	Config/Machines would otherwise break the snapshot for every player who owns one, which
	turns a content decision into an outage.
]]
function Sync.effectiveFor(
	record: ProfileSchema.MachineRecord,
	multiplier: number
): UpgradeCurve.Effective?
	local config = Machines.byId[record.typeId]
	if config == nil then
		return nil
	end
	return UpgradeCurve.effective(config, record.level, Economy.upgrade, multiplier)
end

function Sync.snapshot(data: ProfileSchema.Data): Remotes.Snapshot
	local views: { Remotes.MachineView } = {}

	for _, record in data.machines do
		local effective = Sync.effectiveFor(record, data.prestige.multiplier)
		if effective == nil then
			warn(`[Sync] skipping unknown machine type {record.typeId} in slot {record.slot}`)
			continue
		end

		table.insert(views, {
			slot = record.slot,
			typeId = record.typeId,
			level = record.level,
			lastCollectAt = record.lastCollectAt,
			rate = effective.rate,
			capacity = effective.capacity,
		})
	end

	return {
		coins = data.coins,
		slotsUnlocked = data.slotsUnlocked,
		slotCount = PlotLayout.slotCount(Plots),
		prestigeMultiplier = data.prestige.multiplier,
		machines = views,
	}
end

--- Sends the current snapshot. Does nothing if the profile is not loaded yet.
function Sync.push(player: Player): ()
	local profile = DataService.get(player)
	if profile == nil then
		return
	end

	Remotes.get(Remotes.names.sync):FireClient(player, Sync.snapshot(profile.Data))
end

--[[
	Tells the client why something it asked for did not happen.

	A code, never a sentence. Wording lives on the client so it can be reworded or
	translated without a server deploy.
]]
function Sync.notice(player: Player, code: string): ()
	Remotes.get(Remotes.names.notice):FireClient(player, { code = code } :: Remotes.Notice)
end

return Sync
