--!strict
--[[
	Builds the plot grid in the world from Config/Plots.

	Generated at runtime rather than authored in Studio so the layout lives in source
	control and a config change reshapes the map with no manual rebuilding. It also means
	the same numbers drive both the geometry and the server's placement bounds check, so
	the two cannot disagree.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Plots = require(Shared.Config.Plots)
local PlotLayout = require(Shared.Lib.PlotLayout)

local CONTAINER_NAME = "Plots"
local UNCLAIMED_LABEL = "Unclaimed"

--[[
	Pads are deliberately much darker than the light grey baseplate they sit on.

	The first build used a mid grey-blue and the pads were nearly invisible from any
	distance, because they were the same value as the ground. Being able to pick out
	another player's plot from across the map is not decoration here, it is the comparison
	mechanic the whole design rests on, so pad contrast is a functional requirement.
]]
local PAD_COLOR = Color3.fromRGB(52, 58, 72)
local SLOT_COLOR = Color3.fromRGB(136, 192, 208)
local SIGN_COLOR = Color3.fromRGB(94, 129, 172)

local PlotGeometry = {}

local function buildPad(plotIndex: number): Part
	local center = PlotLayout.plotCenter(plotIndex, Plots)

	local pad = Instance.new("Part")
	pad.Name = "Pad"
	pad.Anchored = true
	pad.Size = Vector3.new(Plots.size, Plots.padThickness, Plots.size)
	-- Offset by half the thickness so the pad's TOP sits at surfaceY, which is the height
	-- every machine and spawn position is computed against.
	pad.Position = Vector3.new(center.x, Plots.surfaceY - Plots.padThickness / 2, center.z)
	pad.Color = PAD_COLOR
	pad.Material = Enum.Material.SmoothPlastic
	pad.TopSurface = Enum.SurfaceType.Smooth
	pad.BottomSurface = Enum.SurfaceType.Smooth

	return pad
end

local function buildSlotMarker(plotIndex: number, slotIndex: number): Part
	local position = PlotLayout.slotPosition(plotIndex, slotIndex, Plots)

	local marker = Instance.new("Part")
	marker.Name = `Slot{slotIndex}`
	marker.Anchored = true
	-- Non-colliding so a player can walk over an empty slot instead of tripping on it.
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.Size = Vector3.new(6, 0.2, 6)
	marker.Position = Vector3.new(position.x, position.y + 0.1, position.z)
	marker.Color = SLOT_COLOR
	marker.Material = Enum.Material.SmoothPlastic
	marker.Transparency = 0.55
	marker:SetAttribute("SlotIndex", slotIndex)

	return marker
end

local function buildSign(plotIndex: number): Part
	local center = PlotLayout.plotCenter(plotIndex, Plots)

	local post = Instance.new("Part")
	post.Name = "Sign"
	post.Anchored = true
	post.CanCollide = false
	post.Size = Vector3.new(4, 5, 0.5)
	-- Just behind the plot, so it reads as belonging to this plot from the walkway in
	-- front without blocking the slot grid.
	post.Position = Vector3.new(center.x, Plots.surfaceY + 2.5, center.z - Plots.size / 2 + 1)
	post.Color = SIGN_COLOR
	post.Material = Enum.Material.SmoothPlastic

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	--[[
		Sized in studs, so a BillboardGui grows as you approach it. At 10 studs wide the
		label swallowed a quarter of the screen when walking past a neighbouring plot.
		5 studs stays readable across the map while staying out of the way up close.
	]]
	billboard.Size = UDim2.fromScale(5, 1.25)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.5, 0)
	billboard.AlwaysOnTop = false
	--[[
		Has to exceed the diagonal of the whole grid, otherwise a player standing on one
		corner plot cannot read the sign on the opposite corner. The first value was 220
		against a grid 280 studs wide, so the labels cut out exactly where the comparison
		between plots is supposed to happen.
	]]
	billboard.MaxDistance = 500
	billboard.Parent = post

	local text = Instance.new("TextLabel")
	text.Name = "Owner"
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamMedium
	text.TextScaled = true
	text.TextColor3 = Color3.fromRGB(236, 239, 244)
	text.TextStrokeTransparency = 0.4
	text.Text = UNCLAIMED_LABEL
	text.Parent = billboard

	return post
end

--[[
	Rebuilds the whole grid, replacing any previous one.

	Idempotent on purpose: `rojo serve` restarts the server script on every sync, so a
	non-destructive build would stack a second grid on top of the first.
]]
function PlotGeometry.build(): Folder
	local existing = Workspace:FindFirstChild(CONTAINER_NAME)
	if existing then
		existing:Destroy()
	end

	local container = Instance.new("Folder")
	container.Name = CONTAINER_NAME

	for plotIndex = 1, PlotLayout.plotCount(Plots) do
		local model = Instance.new("Model")
		model.Name = `Plot{plotIndex}`
		model:SetAttribute("PlotIndex", plotIndex)
		model:SetAttribute("OwnerUserId", 0)

		local pad = buildPad(plotIndex)
		pad.Parent = model
		model.PrimaryPart = pad

		local slots = Instance.new("Folder")
		slots.Name = "Slots"
		slots.Parent = model

		for slotIndex = 1, PlotLayout.slotCount(Plots) do
			buildSlotMarker(plotIndex, slotIndex).Parent = slots
		end

		buildSign(plotIndex).Parent = model
		model.Parent = container
	end

	container.Parent = Workspace
	return container
end

function PlotGeometry.getPlotModel(plotIndex: number): Model?
	local container = Workspace:FindFirstChild(CONTAINER_NAME)
	if container == nil then
		return nil
	end
	return container:FindFirstChild(`Plot{plotIndex}`) :: Model?
end

--- Anchor part for a slot, which is what a machine's position is derived from.
function PlotGeometry.getSlotMarker(plotIndex: number, slotIndex: number): BasePart?
	local model = PlotGeometry.getPlotModel(plotIndex)
	if model == nil then
		return nil
	end
	local slots = model:FindFirstChild("Slots")
	if slots == nil then
		return nil
	end
	return slots:FindFirstChild(`Slot{slotIndex}`) :: BasePart?
end

--- Pass nil to reset the sign to unclaimed.
function PlotGeometry.setOwnerLabel(plotIndex: number, ownerName: string?): ()
	local model = PlotGeometry.getPlotModel(plotIndex)
	if model == nil then
		return
	end

	local label = model:FindFirstChild("Sign")
		and model.Sign:FindFirstChild("Label")
		and model.Sign.Label:FindFirstChild("Owner")

	if label and label:IsA("TextLabel") then
		label.Text = if ownerName then `{ownerName}'s Empire` else UNCLAIMED_LABEL
	end
end

return PlotGeometry
