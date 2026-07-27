--!strict
--[[
	The slowly rotating aura behind a product card's artwork.

	Purely decorative, and it earns its place by doing one job: it puts a moving bright centre
	behind the product so the eye lands on the thing being sold rather than on the card's edges.
	Every storefront in the genre uses it for exactly that reason.

	Built from rotated rectangles rather than an image, because there is no sunburst in the icon
	pack and inventing an asset id is worse than drawing it.

	RAYS EMANATE FROM THE CENTRE, THEY DO NOT CROSS IT.

	The first version used full-length rectangles through the middle, so eight rays at 55%
	transparency overlapped eight deep at the centre. Transparency composites, so the middle
	went nearly opaque: a hard white star sitting on the card instead of a glow behind the
	product. Anchoring each ray at its base and pointing it outward means rays only meet at a
	single point, and the centre stays as light as one ray.

	CONTAINMENT IS GEOMETRIC, NOT CLIPPED, AND IT HAS TO BE.

	`ClipsDescendants` does not clip a rotated descendant, and every ray here is rotated, so a
	clip on the container is silently ignored. Instead every ray is at most `radius` long and
	pinned to the centre, which keeps its tip inside the circle of that radius at any rotation,
	including the container's own. **The caller must give this a container that fits inside its
	card**, because nothing here can stop a ray leaving a container that is already too big.

	The rays are a lightened version of the card's own colour, never a fixed white. On a
	saturated card a white ray reads as a hole punched through it; a lightened one reads as light
	coming from behind the product.
]]

local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")

local create = require(script.Parent.create)

--[[
	Twelve spokes rather than eight. Each covers one direction now instead of two, so the same
	visual density needs more of them, and thinner rays read as a burst where fat ones read as a
	pinwheel.
]]
local RAY_COUNT = 12
--- Fraction of the container's width taken by one ray.
local RAY_WIDTH_SCALE = 0.1
--[[
	Half the container, so a ray reaches from the centre to the edge and no further. This is the
	bound that keeps a rotated ray inside the container; raising it puts rays outside the card,
	where nothing will clip them.
]]
local RAY_LENGTH_SCALE = 0.5
local RAY_LIGHTEN = 0.3
--- High, because the eye should read a glow rather than count spokes.
local RAY_TRANSPARENCY = 0.72

--- Degrees per second. Slow enough to feel like ambience, not slow enough to look frozen.
local SPIN_DEGREES_PER_SECOND = 18

local Sunburst = {}

--[[
	One shared spin loop for every burst on screen.

	A connection per card would be nine connections doing one float add each, which is cheap but
	pointless when a single pass over a list does the same work and cannot leak a connection when
	a card is destroyed.
]]
local spinning: { Frame } = {}
local spinConnection: RBXScriptConnection? = nil

local function ensureSpinning(): ()
	if spinConnection ~= nil then
		return
	end

	spinConnection = RunService.Heartbeat:Connect(function(delta: number)
		--[[
			Checked every frame rather than once at creation, because it is a live accessibility
			setting the player can change without rejoining. The burst simply stops where it is.
		]]
		if GuiService.ReducedMotionEnabled then
			return
		end

		local step = SPIN_DEGREES_PER_SECOND * delta

		-- Backwards, so removing a destroyed entry cannot skip the next one.
		for index = #spinning, 1, -1 do
			local frame = spinning[index]
			if frame.Parent == nil then
				table.remove(spinning, index)
			else
				-- Wrapped, so Rotation never grows without bound over a long session.
				frame.Rotation = (frame.Rotation + step) % 360
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
	local rays: { Instance } = {}

	for index = 1, RAY_COUNT do
		table.insert(
			rays,
			create("Frame", {
				Name = `Ray{index}`,
				--[[
					Anchored at the base and placed at the centre. Roblox rotates a GuiObject about
					its AnchorPoint, so each ray pivots around the centre of the burst and sweeps
					outward rather than spinning about its own middle.
				]]
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(RAY_WIDTH_SCALE, RAY_LENGTH_SCALE),
				-- Full circle, because a ray now covers one direction rather than two.
				Rotation = (index - 1) * (360 / RAY_COUNT),
				BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), RAY_LIGHTEN),
				BackgroundTransparency = RAY_TRANSPARENCY,
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

	table.insert(spinning, frame)
	ensureSpinning()

	return frame
end

return Sunburst
