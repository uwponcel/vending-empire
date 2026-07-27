--!strict
--[[
	A live 3D preview of a machine, for shop cards.

	The card shows the actual mesh the player will get, not a stand-in glyph. That matters more
	here than anywhere else in the UI: the shop is the one screen where a player is deciding
	between nine things they have never seen, and a row of identical category icons tells them
	nothing. It also means adding a machine to `Config/Machines` plus `Config/MachineVisuals`
	puts its portrait in the shop with no new artwork.

	Uses the same Part-plus-SpecialMesh pair as the world machine rather than
	`AssetService:CreateMeshPartAsync`. SpecialMesh is synchronous, so a card is complete the
	moment it is built, where the async path would need every card to handle a pending state and
	a failure.

	ViewportFrames are not free. Roblox renders a separate pass per visible one, which is fine
	because the shop shows one category at a time and the whole panel is closed by default, so
	at most three exist on screen. Do not put one in a list that can grow.
]]

local create = require(script.Parent.create)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local MachineVisuals = require(Shared.Config.MachineVisuals)

--[[
	Narrow enough that perspective distortion stays mild, so a tall fridge and a squat kiosk
	both read as themselves rather than as wide-angle caricatures.
]]
local FIELD_OF_VIEW = 26
--- Slack around the mesh's bounding sphere, so nothing touches the frame edge.
local FRAMING_PADDING = 1.18

--[[
	Three-quarter view. Off to one side and slightly above, which shows the front face plus
	enough of the depth to read as an object rather than a flat card.
]]
local VIEW_DIRECTION = Vector3.new(0.55, 0.34, 1).Unit

--- Flat and bright. A shop portrait wants the texture legible, not dramatic shading.
local AMBIENT = Color3.fromRGB(235, 238, 245)

local MachineThumbnail = {}

--[[
	A ViewportFrame previewing `machineId`, or nil when that machine has no mesh registered.

	Returning nil rather than an empty frame lets the caller fall back to a flat icon, so a
	machine added to the tuning table before its art exists still gets a usable card.
]]
function MachineThumbnail.create(machineId: string): ViewportFrame?
	local visual = MachineVisuals.byId[machineId]
	if visual == nil then
		return nil
	end

	local part = create("Part", {
		Name = "Preview",
		Anchored = true,
		CanCollide = false,
		--[[
			OPAQUE, and it has to be. A SpecialMesh set to FileMesh replaces the Part's geometry,
			so nothing box-shaped is drawn, but the mesh still inherits the Part's Transparency.

			The first version copied `Transparency = 1` from MachineModel, where that value hides
			the invisible collision body standing behind the mesh. Here there is no separate body,
			so it made every thumbnail render a fully transparent mesh: nine blank cards.
		]]
		Transparency = 0,
		Size = Vector3.new(visual.naturalSize.x, visual.naturalSize.y, visual.naturalSize.z),
		-- The same yaw normalisation the world machine applies, so the mesh's authored front
		-- points at +Z and the camera below is looking at the front of every machine.
		CFrame = CFrame.Angles(0, math.rad(visual.yawDegrees), 0),
	}) :: Part

	create("SpecialMesh", {
		Name = "Mesh",
		MeshType = Enum.MeshType.FileMesh,
		MeshId = visual.meshId,
		TextureId = visual.textureId,
		Scale = Vector3.new(visual.scale, visual.scale, visual.scale),
		Parent = part,
	})

	--[[
		Framed against the bounding sphere rather than the height alone.

		A SpecialMesh renders at its natural size times `scale`, ignoring the Part's size, so the
		rendered extent is the natural bounding box scaled. Using the largest dimension means the
		wide drone bay and the tall water cooler are both fully in frame without a per-machine
		tuning number.
	]]
	local extent = math.max(visual.naturalSize.x, visual.naturalSize.y, visual.naturalSize.z)
		* visual.scale
	local distance = (extent * 0.5) / math.tan(math.rad(FIELD_OF_VIEW * 0.5)) * FRAMING_PADDING

	local camera = create("Camera", {
		Name = "ThumbnailCamera",
		FieldOfView = FIELD_OF_VIEW,
		CFrame = CFrame.lookAt(VIEW_DIRECTION * distance, Vector3.zero),
	}) :: Camera

	-- Annotated: a mixed instance array infers from its first element, so this would be a
	-- `{Camera}` and the Part would be rejected.
	local contents: { Instance } = { camera, part }

	local viewport = create("ViewportFrame", {
		Name = "Thumbnail",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Ambient = AMBIENT,
		LightColor = AMBIENT,
		CurrentCamera = camera,
	}, contents) :: ViewportFrame

	return viewport
end

return MachineThumbnail
