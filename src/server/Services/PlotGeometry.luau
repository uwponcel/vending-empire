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
--- Uppercase, matching every other title in the game.
local UNCLAIMED_LABEL = "UNCLAIMED"

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
--- The dark outline every label in the interface wears, screen or world.
local SIGN_OUTLINE = Color3.fromRGB(24, 27, 35)

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
		SIZED IN PIXELS, NOT STUDS, so it occupies the same amount of screen at any distance.

		Stud sizing was tried twice and is wrong for this label both ways. At 10 studs it
		swallowed a quarter of the screen when walking past a neighbouring plot; at 5 studs it
		still filled the bottom third when the camera sat a few studs behind a sign, which is
		exactly where it sits when a player stands on the plot in front of that one. Shrinking
		it far enough to survive that made it unreadable from across the map, which defeats the
		point of a sign.

		Distance falloff is the wrong behaviour for an identity label that is meant to be read
		from anywhere. There are only ever twelve of these, so a constant screen size cannot
		add up to clutter. Machine labels keep stud sizing on purpose: there can be 144 of
		those, and their falloff is what stops a neighbour's plot becoming a wall of text.
	]]
	billboard.Size = UDim2.fromOffset(260, 62)
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
	text.Font = Enum.Font.GothamBlack
	text.TextScaled = true
	text.TextColor3 = Color3.fromRGB(236, 239, 244)
	text.Text = UNCLAIMED_LABEL
	text.Parent = billboard

	--[[
		A real UIStroke here, unlike the machine labels, because this billboard is sized in pixels
		and so holds one constant glyph size at every distance. A fixed thickness therefore stays
		correct, and it gives the chunky outline the screen UI uses.
	]]
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = SIGN_OUTLINE
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = text

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

	-- Walked with FindFirstChild rather than dot access at every step. Dot access on a
	-- runtime-built Model is both untypeable and a hard error if a child is ever missing,
	-- where this path just does nothing.
	local sign = model:FindFirstChild("Sign")
	local billboard = sign and sign:FindFirstChild("Label")
	local label = billboard and billboard:FindFirstChild("Owner")

	if label and label:IsA("TextLabel") then
		label.Text = if ownerName then string.upper(`{ownerName}'s Empire`) else UNCLAIMED_LABEL
	end
end

return PlotGeometry
