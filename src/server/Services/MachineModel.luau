--!strict
--[[
	Assembles the world representation of a placed machine.

	The Body part remains the invisible authoritative collider and prompt host. A separate,
	non-colliding visual loads the machine-specific mesh and texture IDs from pure config.
	Keeping the assets as source-controlled IDs avoids opaque place-only models while making
	the art replaceable without touching gameplay state.

	THE MODEL CARRIES ITS NUMBERS AS ATTRIBUTES, AND THAT IS THE POINT.

	Rate, capacity and lastCollectAt are written onto the Model, which replicates. The
	client reads them and animates the pending counter locally, so a filling machine costs
	the server nothing and sends no traffic between collects. The server writes them only
	when something actually changes: placement, collect, upgrade. That is what keeps the
	no-tick rule intact all the way out to the display.

	Attributes are also the one channel that crosses script contexts, which is what makes
	live state readable through the Studio MCP tools at all. See the MCP notes in CLAUDE.md.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotGeometry = require(script.Parent.PlotGeometry)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local MachineVisuals = require(Shared.Config.MachineVisuals)
local Machines = require(Shared.Config.Machines)
local Plots = require(Shared.Config.Plots)
local Format = require(Shared.Lib.Format)
local PlotLayout = require(Shared.Lib.PlotLayout)
local UpgradeCurve = require(Shared.Lib.UpgradeCurve)

--- Body dimensions in studs. Narrower than the 14 stud slot spacing so two neighbouring
--- machines leave a gap wide enough to walk between.
local BODY_SIZE = Vector3.new(5, 8, 3)
local PANEL_DEPTH = 0.3

--[[
	Category colour is how a player reads their plot at a glance, so the three categories
	have to be separable at distance rather than merely different. Nord palette, matching
	the plot pads and signs.
]]
local CATEGORY_COLOR: { [Machines.Category]: Color3 } = {
	drinks = Color3.fromRGB(94, 129, 172),
	snacks = Color3.fromRGB(208, 135, 112),
	electronics = Color3.fromRGB(180, 142, 173),
}

local PANEL_COLOR = Color3.fromRGB(46, 52, 64)
local TEXT_COLOR = Color3.fromRGB(236, 239, 244)
local READY_COLOR = Color3.fromRGB(163, 190, 140)
--- The dark outline every label in the interface wears, screen or world.
local LABEL_OUTLINE = Color3.fromRGB(24, 27, 35)

local MachineModel = {}

export type Spec = {
	config: Machines.Machine,
	plotIndex: number,
	slot: number,
	level: number,
	--- Effective coins per second, already scaled by level and prestige.
	rate: number,
	capacity: number,
	lastCollectAt: number,
	ownerUserId: number,
}

local function modelName(slot: number): string
	return `Machine{slot}`
end

function MachineModel.find(plotIndex: number, slot: number): Model?
	local plot = PlotGeometry.getPlotModel(plotIndex)
	if plot == nil then
		return nil
	end
	local found = plot:FindFirstChild(modelName(slot))
	if found == nil or not found:IsA("Model") then
		return nil
	end
	return found
end

--- The prompt a collect arrives on. Walked with FindFirstChild, never dot access.
function MachineModel.prompt(model: Model): ProximityPrompt?
	local body = model:FindFirstChild("Body")
	if body == nil then
		return nil
	end
	local prompt = body:FindFirstChild("CollectPrompt")
	if prompt == nil or not prompt:IsA("ProximityPrompt") then
		return nil
	end
	return prompt
end

local function configureUpgradePrompt(
	prompt: ProximityPrompt,
	config: Machines.Machine,
	level: number
): ()
	prompt.ObjectText = config.displayName

	if not UpgradeCurve.canUpgrade(level, Economy.upgrade) then
		prompt.ActionText = "Max level"
		prompt.Enabled = false
		return
	end

	local cost = UpgradeCurve.upgradeCost(config.cost, level, Economy.upgrade)
	prompt.ActionText = `Upgrade {Format.short(cost)}`
	prompt.Enabled = true
end

--[[
	Writes the live numbers onto the model.

	Split out from `build` because collect and upgrade both need it, and because a collect
	must not rebuild the model: destroying and recreating a machine under a player's cursor
	would cancel the ProximityPrompt they are standing at.
]]
function MachineModel.applyState(
	model: Model,
	level: number,
	rate: number,
	capacity: number,
	lastCollectAt: number
): ()
	model:SetAttribute("Level", level)
	model:SetAttribute("Rate", rate)
	model:SetAttribute("Capacity", capacity)
	model:SetAttribute("LastCollectAt", lastCollectAt)

	local typeId = model:GetAttribute("TypeId")
	local config = if type(typeId) == "string" then Machines.byId[typeId] else nil
	if config == nil then
		return
	end

	local body = model:FindFirstChild("Body")
	local upgradePrompt = body and body:FindFirstChild("UpgradePrompt")
	if upgradePrompt and upgradePrompt:IsA("ProximityPrompt") then
		configureUpgradePrompt(upgradePrompt, config, level)
	end

	local billboard = body and body:FindFirstChild("Label")
	local name = billboard and billboard:FindFirstChild("MachineName")
	if name and name:IsA("TextLabel") then
		name.Text = string.upper(`{config.displayName} · Lv. {level}`)
	end
end

local function buildBody(spec: Spec): Part
	local position = PlotLayout.slotPosition(spec.plotIndex, spec.slot, Plots)

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Anchored = true
	body.Size = BODY_SIZE
	body.Position = Vector3.new(position.x, position.y + BODY_SIZE.Y / 2, position.z)
	body.Color = CATEGORY_COLOR[spec.config.category]
	body.Material = Enum.Material.SmoothPlastic
	body.TopSurface = Enum.SurfaceType.Smooth
	body.BottomSurface = Enum.SurfaceType.Smooth

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CollectPrompt"
	prompt.ActionText = "Collect"
	prompt.ObjectText = spec.config.displayName
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	-- Tap to collect. A hold duration on the single most repeated action in the game turns
	-- the core loop into a chore.
	prompt.HoldDuration = 0
	--[[
		The same range the server validates against, so the prompt disappearing and the
		server refusing happen at the same distance. A prompt that is reachable but rejected
		reads as the game being broken.

		This is a client-side convenience, not the check. `Triggered` can be fired by a
		client at any distance, so MachineService measures it again server-side.
	]]
	prompt.MaxActivationDistance = Economy.collect.rangeStuds
	-- Machines stand in a grid and shadow each other from most angles.
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.Parent = body

	local upgradePrompt = Instance.new("ProximityPrompt")
	upgradePrompt.Name = "UpgradePrompt"
	upgradePrompt.KeyboardKeyCode = Enum.KeyCode.Q
	upgradePrompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	upgradePrompt.HoldDuration = 0
	upgradePrompt.MaxActivationDistance = Economy.collect.rangeStuds
	upgradePrompt.RequiresLineOfSight = false
	upgradePrompt.Style = Enum.ProximityPromptStyle.Custom
	configureUpgradePrompt(upgradePrompt, spec.config, spec.level)
	upgradePrompt.Parent = body

	return body
end

local function buildVisual(spec: Spec, body: Part): Part?
	local config = MachineVisuals.byId[spec.config.id]
	if config == nil then
		return nil
	end

	local scaledHeight = config.naturalSize.y * config.scale
	local groundY = body.Position.Y - BODY_SIZE.Y / 2
	local spawn = PlotLayout.spawnPosition(spec.plotIndex, Plots)
	local basePosition = Vector3.new(body.Position.X, groundY + scaledHeight / 2, body.Position.Z)
	local spawnFacing = CFrame.lookAt(basePosition, Vector3.new(spawn.x, basePosition.Y, spawn.z))
		* CFrame.Angles(0, math.rad(180), 0)
	local position = spawnFacing:PointToWorldSpace(
		Vector3.new(config.offset.x, config.offset.y, config.offset.z)
	)

	local visual = Instance.new("Part")
	visual.Name = "Visual"
	visual.Anchored = true
	visual.CanCollide = false
	visual.CanQuery = false
	visual.CanTouch = false
	visual.CastShadow = true
	visual.Size = Vector3.one
	visual.Color = Color3.new(1, 1, 1)
	visual.CFrame = CFrame.new(position)
		* spawnFacing.Rotation
		* CFrame.Angles(0, math.rad(config.yawDegrees), 0)

	local mesh = Instance.new("SpecialMesh")
	mesh.Name = "Mesh"
	mesh.MeshType = Enum.MeshType.FileMesh
	mesh.MeshId = config.meshId
	mesh.TextureId = config.textureId
	mesh.Scale = Vector3.new(config.scale, config.scale, config.scale)
	mesh.Parent = visual

	return visual
end

--- Dark inset panel on the +Z face, which is the side a player approaches from.
local function buildPanel(body: Part): Part
	local panel = Instance.new("Part")
	panel.Name = "Panel"
	panel.Anchored = true
	panel.CanCollide = false
	panel.CanQuery = false
	panel.Size = Vector3.new(BODY_SIZE.X - 1, BODY_SIZE.Y - 2, PANEL_DEPTH)
	-- Spawns sit at plotCenter.z + spawnForwardOffset, so +Z is the walkway side.
	panel.Position = body.Position + Vector3.new(0, 0.5, BODY_SIZE.Z / 2 + PANEL_DEPTH / 2)
	panel.Color = PANEL_COLOR
	panel.Material = Enum.Material.Glass
	panel.Transparency = 0.25

	return panel
end

local function buildLabel(spec: Spec, body: Part): BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	--[[
		Studs, so it scales with distance. That is the right choice here and not for the plot
		signs: there can be 144 of these, and the falloff is what stops a neighbour's plot
		becoming a wall of text. Sized against a 5 stud body.
	]]
	billboard.Size = UDim2.fromScale(7.5, 2.5)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, BODY_SIZE.Y / 2 + 2.2, 0)
	billboard.AlwaysOnTop = false
	--[[
		Short, and it has to be short now that the labels are large.

		Twelve machines in a 4 by 3 grid stack vertically on screen, so at 120 studs every label
		on the plot was drawn at once and the enlarged text collided three deep. Reading a
		neighbour's stock level was never the point; reading the machine you are standing at is.
		At 45 the labels drop away roughly a row behind the player, which is what keeps the ones
		that matter legible.

		The plot signs stay long-range on purpose. Those are the cross-map comparison.
	]]
	billboard.MaxDistance = 45
	billboard.Parent = body

	--[[
		THE LEGACY TEXT STROKE, NOT A UIStroke, AND THAT IS DELIBERATE.

		Both of these are `TextScaled` inside a stud-sized billboard, so their glyphs shrink as
		the player walks away. `UIStroke.Thickness` is a fixed pixel count and would not shrink
		with them, so a stroke tuned to look right up close swallows the text at distance. The
		legacy stroke is drawn as part of the glyph and scales with it.

		The screen UI is the opposite case and uses UIStroke, because those labels are a constant
		pixel size. See the BillboardGui note in CLAUDE.md.
	]]
	local name = Instance.new("TextLabel")
	name.Name = "MachineName"
	name.Size = UDim2.fromScale(1, 0.44)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.GothamBlack
	name.TextScaled = true
	name.TextColor3 = TEXT_COLOR
	name.TextStrokeColor3 = LABEL_OUTLINE
	name.TextStrokeTransparency = 0
	name.Text = string.upper(`{spec.config.displayName} · Lv. {spec.level}`)
	name.Parent = billboard

	local pending = Instance.new("TextLabel")
	pending.Name = "Pending"
	pending.Size = UDim2.fromScale(1, 0.56)
	pending.Position = UDim2.fromScale(0, 0.44)
	pending.BackgroundTransparency = 1
	pending.Font = Enum.Font.GothamBlack
	pending.TextScaled = true
	pending.TextColor3 = READY_COLOR
	pending.TextStrokeColor3 = LABEL_OUTLINE
	pending.TextStrokeTransparency = 0
	-- Filled in by the client from the model's attributes. The server never writes it, so
	-- a counter that ticks up costs no traffic.
	pending.Text = ""
	pending.Parent = billboard

	return billboard
end

--[[
	Builds the machine and parents it to its plot. Returns nil when the plot is not in the
	world, which happens if this is called before PlotGeometry.build.

	Replaces any existing model on the slot, so a rebuild after a rejoin cannot stack two
	machines on one anchor.
]]
function MachineModel.build(spec: Spec): Model?
	local plot = PlotGeometry.getPlotModel(spec.plotIndex)
	if plot == nil then
		warn(`[MachineModel] plot {spec.plotIndex} is not built; cannot place slot {spec.slot}`)
		return nil
	end

	local existing = plot:FindFirstChild(modelName(spec.slot))
	if existing then
		existing:Destroy()
	end

	local model = Instance.new("Model")
	model.Name = modelName(spec.slot)
	model:SetAttribute("Slot", spec.slot)
	model:SetAttribute("TypeId", spec.config.id)
	model:SetAttribute("OwnerUserId", spec.ownerUserId)

	local body = buildBody(spec)
	body.Parent = model
	model.PrimaryPart = body

	local visual = buildVisual(spec, body)
	if visual then
		body.Transparency = 1
		body.CastShadow = false
		visual.Parent = model
	else
		buildPanel(body).Parent = model
	end

	buildLabel(spec, body)
	MachineModel.applyState(model, spec.level, spec.rate, spec.capacity, spec.lastCollectAt)

	model.Parent = plot
	return model
end

function MachineModel.destroy(plotIndex: number, slot: number): ()
	local model = MachineModel.find(plotIndex, slot)
	if model then
		model:Destroy()
	end
end

--- Removes every machine on a plot, for when its owner leaves and the plot is released.
function MachineModel.clearPlot(plotIndex: number): ()
	local plot = PlotGeometry.getPlotModel(plotIndex)
	if plot == nil then
		return
	end

	for _, child in plot:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("Slot") ~= nil then
			child:Destroy()
		end
	end
end

return MachineModel
