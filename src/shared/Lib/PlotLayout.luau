--!strict
--[[
	Plot and slot placement math. Pure, zero requires.

	Returns plain `{ x, y, z }` tables rather than Vector3, for two reasons. Vector3 is a
	Roblox userdata type, so using it here would break the purity rule and make this
	untestable. And any position that ever reaches saved data has to be serialisable,
	because ProfileStore rejects userdata outright.

	The grid is centred on the world origin so the map stays symmetric no matter how the
	column and row counts change.
]]

export type Config = {
	columns: number,
	rows: number,
	size: number,
	spacing: number,
	surfaceY: number,
	slotColumns: number,
	slotRows: number,
	slotSpacing: number,
	spawnForwardOffset: number,
	spawnHeightOffset: number,
}

export type Position = {
	x: number,
	y: number,
	z: number,
}

local PlotLayout = {}

--- Centre-to-centre distance between adjacent plots.
local function pitch(config: Config): number
	return config.size + config.spacing
end

--[[
	Converts a 1-based index into 1-based column and row, filling left to right then
	front to back. Shared by plots and slots because the math is identical.
]]
local function gridCell(index: number, columns: number): (number, number)
	local zeroBased = index - 1
	return zeroBased % columns + 1, zeroBased // columns + 1
end

--- Offset of a cell centre from the centre of the whole grid.
local function centredOffset(cell: number, count: number, step: number): number
	return (cell - (count + 1) / 2) * step
end

function PlotLayout.plotCount(config: Config): number
	return config.columns * config.rows
end

function PlotLayout.slotCount(config: Config): number
	return config.slotColumns * config.slotRows
end

local function assertPlotIndex(plotIndex: number, config: Config): ()
	local count = PlotLayout.plotCount(config)
	if plotIndex % 1 ~= 0 or plotIndex < 1 or plotIndex > count then
		error(`plot index {plotIndex} is outside 1..{count}`, 3)
	end
end

local function assertSlotIndex(slotIndex: number, config: Config): ()
	local count = PlotLayout.slotCount(config)
	if slotIndex % 1 ~= 0 or slotIndex < 1 or slotIndex > count then
		error(`slot index {slotIndex} is outside 1..{count}`, 3)
	end
end

--- Centre of a plot pad's top surface.
function PlotLayout.plotCenter(plotIndex: number, config: Config): Position
	assertPlotIndex(plotIndex, config)
	local column, row = gridCell(plotIndex, config.columns)

	return {
		x = centredOffset(column, config.columns, pitch(config)),
		y = config.surfaceY,
		z = centredOffset(row, config.rows, pitch(config)),
	}
end

--- Slot offset relative to its plot centre, so slot layout is independent of plot index.
function PlotLayout.slotOffset(slotIndex: number, config: Config): Position
	assertSlotIndex(slotIndex, config)
	local column, row = gridCell(slotIndex, config.slotColumns)

	return {
		x = centredOffset(column, config.slotColumns, config.slotSpacing),
		y = 0,
		z = centredOffset(row, config.slotRows, config.slotSpacing),
	}
end

--- Where a machine in this slot on this plot stands, in world space.
function PlotLayout.slotPosition(plotIndex: number, slotIndex: number, config: Config): Position
	local center = PlotLayout.plotCenter(plotIndex, config)
	local offset = PlotLayout.slotOffset(slotIndex, config)

	return {
		x = center.x + offset.x,
		y = center.y + offset.y,
		z = center.z + offset.z,
	}
end

--[[
	Where a player appears when they claim a plot: near the front edge, facing in, and
	slightly above the pad so the character falls onto it rather than spawning inside it.
]]
function PlotLayout.spawnPosition(plotIndex: number, config: Config): Position
	local center = PlotLayout.plotCenter(plotIndex, config)

	return {
		x = center.x,
		y = center.y + config.spawnHeightOffset,
		z = center.z + config.spawnForwardOffset,
	}
end

--[[
	Half-extent of the whole grid, for sanity checks and for sizing anything that needs
	to contain every plot. Returns half-width on x and half-depth on z.
]]
function PlotLayout.gridHalfExtents(config: Config): (number, number)
	local step = pitch(config)
	return (config.columns * step - config.spacing) / 2, (config.rows * step - config.spacing) / 2
end

--[[
	True when a point lies on a given plot's pad. The server uses this to reject a
	placement request that names a slot but sits outside the plot it claims to be on.
]]
function PlotLayout.isWithinPlot(plotIndex: number, x: number, z: number, config: Config): boolean
	local center = PlotLayout.plotCenter(plotIndex, config)
	local half = config.size / 2
	return math.abs(x - center.x) <= half and math.abs(z - center.z) <= half
end

return PlotLayout
