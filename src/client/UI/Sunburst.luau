--!strict
--[[
	The radiating rays behind a product card's artwork.

	Purely decorative, and it earns its place by doing one job: it puts a bright centre behind
	the product so the eye lands on the thing being sold rather than on the card's edges. Every
	storefront in the genre uses it for exactly that reason.

	Built from rotated rectangles rather than an image, because there is no sunburst in the
	icon pack and inventing an asset id is worse than drawing it. A rectangle through the centre
	shows up as two opposing spokes, so `RAY_COUNT` rays produce twice that many visible ones,
	which is why eight is enough.

	CONTAINMENT IS GEOMETRIC, NOT CLIPPED, AND IT HAS TO BE.

	`ClipsDescendants` does not clip a rotated descendant. The first version set it on the
	container and every ray was rotated, so the clip was ignored entirely and the rays sprayed
	out across the world past the edge of the shop panel.

	So the rays are bounded by construction instead. Each is exactly as long as the container is
	tall and pinned to its centre, which keeps every ray inside the circle of that diameter no
	matter how it is rotated. **The caller must give this a square container that fits inside its
	card**, because nothing here can stop a ray leaving a container that is already too big.

	The rays are a lightened version of the card's own colour, never a fixed white. On a
	saturated card a white ray reads as a hole punched through it; a lightened one reads as
	light coming from behind the product.
]]

local create = require(script.Parent.create)

--- Spokes are drawn in opposing pairs, so this is half the visible count.
local RAY_COUNT = 8
--- Fraction of the container's width taken by one ray.
local RAY_WIDTH_SCALE = 0.16
--[[
	Exactly the container's height, never more. This is the bound that keeps a rotated ray inside
	the container's circle; raising it puts rays outside the card, where nothing will clip them.
]]
local RAY_LENGTH_SCALE = 1
local RAY_LIGHTEN = 0.22
local RAY_TRANSPARENCY = 0.55

local Sunburst = {}

--[[
	A transparent square of rays, `diameter` pixels across, centred on `center` of its parent.

	Positioned by scale on the parent so a card can put the burst behind its artwork rather than
	at its own centre. The caller owns containment: see the note at the top of this file.

	`ZIndex` is left at the default and the caller is expected to parent this first. Sunburst
	has no idea what it sits behind, and a hardcoded negative ZIndex here would fight whatever
	the card decides.
]]
function Sunburst.create(color: Color3, diameter: number, center: Vector2): Frame
	local rays: { Instance } = {}

	for index = 1, RAY_COUNT do
		table.insert(
			rays,
			create("Frame", {
				Name = `Ray{index}`,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(RAY_WIDTH_SCALE, RAY_LENGTH_SCALE),
				-- Spread over 180 degrees, not 360: each rectangle already covers both sides of
				-- the centre, so going the full circle would draw every ray twice.
				Rotation = (index - 1) * (180 / RAY_COUNT),
				BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), RAY_LIGHTEN),
				BackgroundTransparency = RAY_TRANSPARENCY,
				BorderSizePixel = 0,
			})
		)
	end

	return create("Frame", {
		Name = "Sunburst",
		Size = UDim2.fromOffset(diameter, diameter),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(center.X, center.Y),
		BackgroundTransparency = 1,
	}, rays) :: Frame
end

return Sunburst
