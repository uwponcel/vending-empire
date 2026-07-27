--!strict
--[[
	A static starburst that sits behind a product card's artwork to highlight it.

	Purely decorative, and it earns its place by doing one job: it puts a bright point behind the
	product so the eye lands on the thing being sold rather than on the card's edges.

	Built from rectangles rather than an image, because there is no sunburst in the icon pack and
	inventing an asset id is worse than drawing it.

	IT DOES NOT ROTATE, AND IT DOES NOT ORBIT.

	A spinning version read as a fan wheel turning next to the machine rather than light behind
	it, which is worse than no effect at all. The rays hold their angles; what animates is their
	brightness, as a wave travelling around the ring so rays fade up and down in succession.

	The wave is a transparency ramp rather than toggling `Visible`. Flicking rays on and off is a
	rapid flash, which the accessibility rules in PRODUCT.md rule out, and it strobes where a ramp
	shimmers. Under `GuiService.ReducedMotionEnabled` the rays hold a steady mid brightness.

	THERE IS A HOLE IN THE MIDDLE, AND IT IS LOAD BEARING.

	Rays start at `INNER_RADIUS_SCALE` of the radius, not at the centre. Sixteen semi-transparent
	rays meeting at one point still composite sixteen deep across those few pixels, which put a
	hard bright dot over the very thing the burst is meant to highlight. Starting them out from
	the centre means no ray overlaps another anywhere, and the product sits in clear space.

	EVERY RAY'S CENTRE IS PLACED WITH TRIG, NOT WITH AN ANCHOR PLUS A ROTATION.

	The orbiting version anchored each ray at its base and leaned on `Rotation` pivoting about
	`AnchorPoint`. It does not reliably, so the rays swept around a point that was not the centre
	of the burst and the whole thing sat off to one side of the artwork.

	Each ray now has `AnchorPoint` at its own centre, and that centre is positioned half a ray
	length out along its angle. With the anchor at the centre, both possible pivot rules agree, so
	the inner end of every ray lands on the burst's centre no matter how Roblox interprets it.

	CONTAINMENT IS GEOMETRIC, NOT CLIPPED, AND IT HAS TO BE.

	`ClipsDescendants` does not clip a rotated descendant, and every ray here is rotated, so a
	clip on the container is silently ignored. Instead no ray reaches further than `radius` from
	the centre. **The caller must give this a container that fits inside its card**, because
	nothing here can stop a ray leaving a container that is already too big.

	The rays are a lightened version of the card's own colour, never a fixed white. On a saturated
	card a white ray reads as a hole punched through it; a lightened one reads as light coming
	from behind the product.
]]

local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")

local create = require(script.Parent.create)

--- Rays alternate long and short, so this is even.
local RAY_COUNT = 16
--- Fraction of the container's width taken by one ray.
local RAY_WIDTH_SCALE = 0.075
--[[
	Alternating lengths as a fraction of the radius. A burst of equal-length spokes reads as a
	mechanical fan; uneven ones read as light. The longer value is 1, meaning a ray reaches the
	container edge and no further, which is what bounds the whole thing.
]]
local RAY_LONG = 1
local RAY_SHORT = 0.62

--- Where a ray starts, as a fraction of the radius. Keeps the centre clear. See the header.
local INNER_RADIUS_SCALE = 0.2

local RAY_LIGHTEN = 0.34
--- Dimmest and brightest points of the sparkle. Both high: a glow, not countable spokes.
local TRANSPARENCY_DIM = 0.9
local TRANSPARENCY_BRIGHT = 0.56
--- Held when the player has asked for reduced motion.
local TRANSPARENCY_STILL = 0.76

--- Full trips of the wave around the ring per second. Slow enough to shimmer, not blink.
local WAVE_CYCLES_PER_SECOND = 0.45

local Sunburst = {}

--[[
	One shared sparkle loop for every burst on screen.

	A connection per card would be nine connections doing the same trig, and each would have to be
	disconnected when its card died. One pass over a list cannot leak.
]]
local sparkling: { Frame } = {}
local sparkleConnection: RBXScriptConnection? = nil

local function ensureSparkling(): ()
	if sparkleConnection ~= nil then
		return
	end

	sparkleConnection = RunService.Heartbeat:Connect(function()
		--[[
			Checked every frame rather than once at creation, because it is a live accessibility
			setting the player can change without rejoining.
		]]
		local reduced = GuiService.ReducedMotionEnabled
		-- os.clock is right here: this drives one frame of animation and is never persisted.
		local phase = os.clock() * WAVE_CYCLES_PER_SECOND * math.pi * 2

		for index = #sparkling, 1, -1 do
			local frame = sparkling[index]
			if frame.Parent == nil then
				table.remove(sparkling, index)
				continue
			end

			for rayIndex, ray in frame:GetChildren() do
				if not ray:IsA("Frame") then
					continue
				end

				if reduced then
					ray.BackgroundTransparency = TRANSPARENCY_STILL
					continue
				end

				-- One full wave spread across the ring, so brightness travels around it.
				local offset = (rayIndex - 1) / RAY_COUNT * math.pi * 2
				local brightness = 0.5 + 0.5 * math.sin(phase + offset)
				ray.BackgroundTransparency = TRANSPARENCY_DIM
					+ (TRANSPARENCY_BRIGHT - TRANSPARENCY_DIM) * brightness
			end
		end
	end)
end

--[[
	A transparent square of rays, `diameter` pixels across, centred on `center` of its parent.

	Positioned by offset within the parent so a card can put the burst behind its artwork rather
	than at its own centre. The caller owns containment: see the note at the top of this file.

	`ZIndex` is left at the default and the caller is expected to parent this first. Sunburst has
	no idea what it sits behind, and a hardcoded negative ZIndex here would fight whatever the
	card decides.
]]
function Sunburst.create(color: Color3, diameter: number, center: Vector2): Frame
	local radius = diameter / 2
	local width = diameter * RAY_WIDTH_SCALE
	local rayColor = color:Lerp(Color3.new(1, 1, 1), RAY_LIGHTEN)

	local rays: { Instance } = {}

	local inner = radius * INNER_RADIUS_SCALE

	for index = 1, RAY_COUNT do
		local degrees = (index - 1) * (360 / RAY_COUNT)
		local outer = radius * (if index % 2 == 1 then RAY_LONG else RAY_SHORT)
		local length = outer - inner

		--[[
			Centred at the midpoint between the inner and outer ends along the ray's own angle, so
			the ray spans exactly `inner` to `outer` from the burst centre.

			Screen y grows downward, hence the negated cosine. Zero degrees points straight up,
			which only matters for reading the code; the result is symmetric either way.
		]]
		local radians = math.rad(degrees)
		local distance = inner + length / 2
		local offsetX = math.sin(radians) * distance
		local offsetY = -math.cos(radians) * distance

		table.insert(
			rays,
			create("Frame", {
				Name = `Ray{index}`,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, offsetX, 0.5, offsetY),
				Size = UDim2.fromOffset(width, length),
				Rotation = degrees,
				BackgroundColor3 = rayColor,
				BackgroundTransparency = TRANSPARENCY_STILL,
				BorderSizePixel = 0,
			})
		)
	end

	local frame = create("Frame", {
		Name = "Sunburst",
		Size = UDim2.fromOffset(diameter, diameter),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(center.X, center.Y),
		BackgroundTransparency = 1,
	}, rays) :: Frame

	table.insert(sparkling, frame)
	ensureSparkling()

	return frame
end

return Sunburst
