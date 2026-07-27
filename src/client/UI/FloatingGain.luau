--!strict
--[[
	A money icon and a large outlined amount that floats up off the player's character.

	World-space, attached to the character, not a screen overlay. A number that appears in a
	corner of the screen has to be found; a number that erupts off the thing you just did reads
	without looking for it. That is the whole reason this is a BillboardGui on the character
	rather than a label in the HUD.

	PRESENTATION ONLY. The amount here was already decided, applied, and saved by the server
	before the snapshot that triggered it arrived. Nothing in this file can change a balance,
	and a client that edited the number would be lying to nobody but itself.

	Sized in studs, so it shrinks with distance like anything else in the world. That is
	correct here even though plot signs deliberately use pixels: a sign is an identity label
	meant to be read from across the map, while this is a reaction to something that happened
	under your own feet. If you are far enough away for it to be small, it is not yours.

	Several can be in flight at once. Each gets a fresh instance and a random lateral kick, so
	a burst of collects scatters instead of stacking into one illegible smear.
]]

local TweenService = game:GetService("TweenService")

local create = require(script.Parent.create)

local SNOW = Color3.fromRGB(255, 255, 255)
local OUTLINE = Color3.fromRGB(24, 27, 35)

--- Studs. Wide enough for "+1.23M" beside the icon without the text auto-shrinking to mush.
local BILLBOARD_SIZE = Vector2.new(5.5, 2)
local RISE_STUDS = 4.5
local LIFETIME = 1.1
--- Lateral scatter, in studs, so simultaneous gains do not overlap exactly.
local SPREAD_STUDS = 1.6

local FloatingGain = {}

--[[
	The part a billboard should hang off, or nil if the character is not assembled yet.

	HumanoidRootPart rather than Head: it exists on every rig, it is the part that survives
	accessories and animations, and a billboard anchored to it does not jitter when the head
	turns.
]]
local function anchorFor(character: Model?): BasePart?
	if character == nil then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return nil
	end
	return root
end

--[[
	Shows `+text` with `icon` rising off the character. Safe to call again immediately.

	Does nothing when the character is missing, which happens between death and respawn. A
	gain that lands in that window is not worth queueing: by the time there is somewhere to
	draw it, the moment it was reacting to has passed.
]]
function FloatingGain.show(character: Model?, icon: string, text: string): ()
	local anchor = anchorFor(character)
	if anchor == nil then
		return
	end

	local label = create("TextLabel", {
		Name = "Amount",
		Size = UDim2.new(1, -44, 1, 0),
		Position = UDim2.fromOffset(44, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = SNOW,
		Text = text,
	}, {
		-- UIStroke rather than TextStrokeTransparency: the built-in stroke is one pixel and
		-- vanishes against a bright plot, where this is the thick cartoon outline that keeps
		-- the number legible over any background.
		create("UIStroke", {
			Thickness = 3,
			Color = OUTLINE,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		}),
	}) :: TextLabel

	local image = create("ImageLabel", {
		Name = "Icon",
		Size = UDim2.fromOffset(40, 40),
		Position = UDim2.new(0, 0, 0.5, -20),
		BackgroundTransparency = 1,
		Image = icon,
		ScaleType = Enum.ScaleType.Fit,
	}) :: ImageLabel

	local sideways = (math.random() - 0.5) * 2 * SPREAD_STUDS

	-- Annotated, because a mixed array of instances infers as the type of its first element and
	-- the TextLabel then fails to fit a `{ImageLabel}`.
	local children: { Instance } = { image, label }

	local billboard = create("BillboardGui", {
		Name = "FloatingGain",
		Size = UDim2.fromScale(BILLBOARD_SIZE.X, BILLBOARD_SIZE.Y),
		StudsOffsetWorldSpace = Vector3.new(sideways, 2.5, 0),
		-- On top, because the point of this is that it cannot be missed, and a machine body
		-- sits between the character and the camera often enough to matter.
		AlwaysOnTop = true,
		--- Only ever the local player's own gain, so it never needs to carry across the map.
		MaxDistance = 90,
		Parent = anchor,
	}, children) :: BillboardGui

	local rise = TweenInfo.new(LIFETIME, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	TweenService:Create(billboard, rise, {
		StudsOffsetWorldSpace = Vector3.new(sideways, 2.5 + RISE_STUDS, 0),
	}):Play()

	--[[
		Fade starts late rather than running the whole rise. Fading from the first frame means
		the number is already half gone by the time the eye reaches it, so it holds full opacity
		while it travels and then leaves.
	]]
	local fade = TweenInfo.new(LIFETIME * 0.45, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
	task.delay(LIFETIME * 0.55, function()
		if billboard.Parent == nil then
			return
		end
		TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
		TweenService:Create(image, fade, { ImageTransparency = 1 }):Play()

		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
		end
	end)

	task.delay(LIFETIME + 0.1, function()
		billboard:Destroy()
	end)
end

return FloatingGain
