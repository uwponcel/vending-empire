--!strict
--[[
	Plot grid geometry. Data only, zero requires.

	Twelve plots in a 4x3 arrangement, one per player, sized so a player can walk
	between their machines rather than standing in a wall of them. Plots are visible to
	each other on purpose: seeing someone else's fuller plot is the comparison that
	drives the genre, so the walkways between plots are a feature and not filler.

	Slot count here must equal Economy.maxSlots. The two cannot reference each other
	because both are pure data with no requires, so a test asserts they agree.

	No Vector3 anywhere. Plot and slot positions are plain numbers and are turned into
	Vector3 at build time, because ProfileStore refuses to save Roblox userdata and
	anything that touches saved data has to stay serialisable.
]]

local Plots = {
	--- 4 x 3 = 12 plots, matching a comfortable shared server population.
	columns = 4,
	rows = 3,

	--- Studs per side of a square plot pad.
	size = 64,
	--- Walkway between adjacent pads, so plots read as separate properties.
	spacing = 8,
	--- Pad thickness. Sits on top of the baseplate rather than replacing it.
	padThickness = 1,
	--- Y coordinate of the pad's top surface, which is what machines stand on.
	surfaceY = 1,

	--- 4 x 3 = 12 machine slots per plot, matching Economy.maxSlots.
	slotColumns = 4,
	slotRows = 3,
	--- Studs between slot centres. Wide enough to walk between two machines.
	slotSpacing = 14,

	--- How far in front of the plot centre a player appears when they claim it, and how
	--- high above the pad, so a character drops onto the pad instead of clipping it.
	spawnForwardOffset = 22,
	spawnHeightOffset = 4,
}

return Plots
