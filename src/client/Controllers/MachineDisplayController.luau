--!strict
--[[
	Animates the pending-coin counter on every machine in the world.

	THIS IS WHY THE SERVER DOES NOT TICK. Each machine model carries `Rate`, `Capacity` and
	`LastCollectAt` as replicated attributes, written only when one of them actually changes.
	Those three numbers are everything needed to know what a machine holds at any instant, so
	the counter is computed here, locally, from the same formula the server uses. A machine
	filling up costs the server nothing and sends no traffic between collects.

	The number shown is an estimate and is allowed to be slightly wrong: it depends on this
	machine's clock agreeing with the server's to within a second or so. Nothing is paid out
	from it. The server recomputes the amount from scratch when a collect arrives, and that
	answer is the only one that touches a balance.

	Every machine is animated, not only the local player's. Seeing a neighbour's plot sitting
	full is the comparison the design rests on, and `MaxDistance` on the billboard already
	keeps a whole map of them from being drawn at once.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Accrual = require(Shared.Lib.Accrual)
local Format = require(Shared.Lib.Format)

--[[
	Four updates a second. Fast enough that a tier 1 machine at 1 coin/sec looks like it is
	counting rather than stepping, slow enough that a full server of 12 plots is a few hundred
	text assignments a second rather than a few thousand. Any faster is wasted: the value only
	changes once a second on the cheapest machine in the game.
]]
local INTERVAL_SECONDS = 0.25

local PLOTS_FOLDER = "Plots"
local READY_COLOR = Color3.fromRGB(163, 190, 140)
local FILLING_COLOR = Color3.fromRGB(216, 222, 233)

local MachineDisplayController = {}

--- The pending label on a machine, or nil if the model is not shaped like one.
local function pendingLabel(model: Model): TextLabel?
	local body = model:FindFirstChild("Body")
	local billboard = body and body:FindFirstChild("Label")
	local label = billboard and billboard:FindFirstChild("Pending")

	if label == nil or not label:IsA("TextLabel") then
		return nil
	end
	return label
end

local function updateMachine(model: Model, now: number): ()
	local rate = model:GetAttribute("Rate")
	local capacity = model:GetAttribute("Capacity")
	local lastCollectAt = model:GetAttribute("LastCollectAt")

	-- Attributes replicate independently of the model, so a machine can exist for a frame
	-- with only some of them set. Checked rather than assumed.
	if type(rate) ~= "number" or type(capacity) ~= "number" or type(lastCollectAt) ~= "number" then
		return
	end
	if rate <= 0 then
		return
	end

	local label = pendingLabel(model)
	if label == nil then
		return
	end

	local pending = Accrual.pending(rate, capacity, now - lastCollectAt)

	if pending <= 0 then
		label.Text = ""
		return
	end

	local full = pending >= math.floor(capacity)
	label.Text = if full then `FULL {Format.short(pending)}` else Format.short(pending)
	label.TextColor3 = if full then READY_COLOR else FILLING_COLOR
end

local function updateAll(): ()
	local plots = Workspace:FindFirstChild(PLOTS_FOLDER)
	if plots == nil then
		return
	end

	-- os.time once per pass rather than per machine, so every counter on screen agrees.
	-- Wall clock, matching what the server wrote into LastCollectAt.
	local now = os.time()

	for _, plot in plots:GetChildren() do
		for _, child in plot:GetChildren() do
			-- The Slot attribute is what distinguishes a machine from the pad and the sign.
			if child:IsA("Model") and child:GetAttribute("Slot") ~= nil then
				updateMachine(child, now)
			end
		end
	end
end

--[[
	Walks the plot folder every pass rather than keeping a cached registry.

	Twelve plots of at most twelve machines is under 200 children to look at four times a
	second, which is cheaper than the bookkeeping a registry would need to stay correct across
	machines being bought, destroyed, and rebuilt on rejoin. Revisit if plot counts grow by an
	order of magnitude.
]]
function MachineDisplayController.start(): ()
	task.spawn(function()
		while true do
			updateAll()
			task.wait(INTERVAL_SECONDS)
		end
	end)
end

return MachineDisplayController
