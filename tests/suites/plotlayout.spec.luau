--!strict

local harness = require("../harness")
local Plots = require("../../src/shared/Config/Plots")
local Economy = require("../../src/shared/Config/Economy")
local PlotLayout = require("../../src/shared/Lib/PlotLayout")

local describe = harness.describe
local it = harness.it
local expect = harness.expect

describe("PlotLayout counts", function()
	it("derives plot and slot counts from the grid", function()
		expect(PlotLayout.plotCount(Plots)).toBe(12)
		expect(PlotLayout.slotCount(Plots)).toBe(12)
	end)

	it("agrees with Economy.maxSlots", function()
		-- Config/Plots and Config/Economy cannot require each other, both being pure
		-- data. This is the only thing keeping them consistent, so if a plot ever gains
		-- a slot row without maxSlots following, this is what catches it.
		expect(PlotLayout.slotCount(Plots)).toBe(Economy.maxSlots)
	end)
end)

describe("PlotLayout.plotCenter", function()
	it("centres the whole grid on the origin", function()
		-- Averaging every plot centre must land on zero on both axes, otherwise the map
		-- drifts off origin whenever the column or row count changes.
		local sumX, sumZ = 0, 0
		for index = 1, PlotLayout.plotCount(Plots) do
			local center = PlotLayout.plotCenter(index, Plots)
			sumX += center.x
			sumZ += center.z
		end
		expect(sumX).toBeCloseTo(0, 1e-9)
		expect(sumZ).toBeCloseTo(0, 1e-9)
	end)

	it("places every plot at the pad surface height", function()
		for index = 1, PlotLayout.plotCount(Plots) do
			expect(PlotLayout.plotCenter(index, Plots).y).toBe(Plots.surfaceY)
		end
	end)

	it("fills left to right, then front to back", function()
		local first = PlotLayout.plotCenter(1, Plots)
		local second = PlotLayout.plotCenter(2, Plots)
		local nextRow = PlotLayout.plotCenter(Plots.columns + 1, Plots)

		expect(second.x).toBeGreaterThan(first.x)
		expect(second.z).toBe(first.z)
		expect(nextRow.x).toBe(first.x)
		expect(nextRow.z).toBeGreaterThan(first.z)
	end)

	it("separates adjacent plots by exactly size plus spacing", function()
		local first = PlotLayout.plotCenter(1, Plots)
		local second = PlotLayout.plotCenter(2, Plots)
		expect(second.x - first.x).toBeCloseTo(Plots.size + Plots.spacing, 1e-9)
	end)

	it("gives every plot a distinct centre", function()
		local seen = {}
		for index = 1, PlotLayout.plotCount(Plots) do
			local center = PlotLayout.plotCenter(index, Plots)
			local key = `{center.x}:{center.z}`
			expect(seen[key]).toBe(nil)
			seen[key] = true
		end
	end)

	it("rejects an out of range or fractional plot index", function()
		expect(function()
			PlotLayout.plotCenter(0, Plots)
		end).toThrow("outside")
		expect(function()
			PlotLayout.plotCenter(13, Plots)
		end).toThrow("outside")
		expect(function()
			PlotLayout.plotCenter(2.5, Plots)
		end).toThrow("outside")
	end)
end)

describe("PlotLayout.slotOffset", function()
	it("centres slots within their plot", function()
		local sumX, sumZ = 0, 0
		for index = 1, PlotLayout.slotCount(Plots) do
			local offset = PlotLayout.slotOffset(index, Plots)
			sumX += offset.x
			sumZ += offset.z
		end
		expect(sumX).toBeCloseTo(0, 1e-9)
		expect(sumZ).toBeCloseTo(0, 1e-9)
	end)

	it("is independent of which plot it is on", function()
		for slot = 1, PlotLayout.slotCount(Plots) do
			local offset = PlotLayout.slotOffset(slot, Plots)
			for plot = 1, PlotLayout.plotCount(Plots) do
				local center = PlotLayout.plotCenter(plot, Plots)
				local absolute = PlotLayout.slotPosition(plot, slot, Plots)
				expect(absolute.x - center.x).toBeCloseTo(offset.x, 1e-9)
				expect(absolute.z - center.z).toBeCloseTo(offset.z, 1e-9)
			end
		end
	end)

	it("rejects an out of range slot index", function()
		expect(function()
			PlotLayout.slotOffset(0, Plots)
		end).toThrow("outside")
		expect(function()
			PlotLayout.slotOffset(13, Plots)
		end).toThrow("outside")
	end)
end)

describe("PlotLayout.slotPosition", function()
	it("keeps every slot on its own plot's pad", function()
		-- A slot that fell outside its pad would leave a machine floating over a
		-- walkway, and would break the server's placement bounds check.
		for plot = 1, PlotLayout.plotCount(Plots) do
			for slot = 1, PlotLayout.slotCount(Plots) do
				local position = PlotLayout.slotPosition(plot, slot, Plots)
				expect(PlotLayout.isWithinPlot(plot, position.x, position.z, Plots)).toBe(true)
			end
		end
	end)

	it("keeps slots off every other plot's pad", function()
		-- Confirms the walkways are real. If plots overlapped, one player's machine
		-- could land inside a neighbour's bounds and pass their ownership check.
		for plot = 1, PlotLayout.plotCount(Plots) do
			for slot = 1, PlotLayout.slotCount(Plots) do
				local position = PlotLayout.slotPosition(plot, slot, Plots)
				for other = 1, PlotLayout.plotCount(Plots) do
					if other ~= plot then
						expect(PlotLayout.isWithinPlot(other, position.x, position.z, Plots)).toBe(
							false
						)
					end
				end
			end
		end
	end)

	it("leaves walking room between adjacent slots", function()
		local a = PlotLayout.slotPosition(1, 1, Plots)
		local b = PlotLayout.slotPosition(1, 2, Plots)
		expect(math.abs(b.x - a.x)).toBeCloseTo(Plots.slotSpacing, 1e-9)
	end)
end)

describe("PlotLayout.spawnPosition", function()
	it("puts the player above the pad so the character drops onto it", function()
		for index = 1, PlotLayout.plotCount(Plots) do
			local spawn = PlotLayout.spawnPosition(index, Plots)
			expect(spawn.y).toBeGreaterThan(Plots.surfaceY)
		end
	end)

	it("stays on the player's own pad", function()
		for index = 1, PlotLayout.plotCount(Plots) do
			local spawn = PlotLayout.spawnPosition(index, Plots)
			expect(PlotLayout.isWithinPlot(index, spawn.x, spawn.z, Plots)).toBe(true)
		end
	end)

	it("does not drop the player on top of a machine slot", function()
		-- Spawning inside a placed machine would either shove the player or wedge them.
		for plot = 1, PlotLayout.plotCount(Plots) do
			local spawn = PlotLayout.spawnPosition(plot, Plots)
			for slot = 1, PlotLayout.slotCount(Plots) do
				local slotPosition = PlotLayout.slotPosition(plot, slot, Plots)
				local distance =
					math.sqrt((spawn.x - slotPosition.x) ^ 2 + (spawn.z - slotPosition.z) ^ 2)
				expect(distance).toBeGreaterThan(5)
			end
		end
	end)
end)

describe("PlotLayout.gridHalfExtents", function()
	it("covers every plot pad", function()
		local halfX, halfZ = PlotLayout.gridHalfExtents(Plots)
		for index = 1, PlotLayout.plotCount(Plots) do
			local center = PlotLayout.plotCenter(index, Plots)
			expect(math.abs(center.x) + Plots.size / 2).toBeLessThan(halfX + 1e-6)
			expect(math.abs(center.z) + Plots.size / 2).toBeLessThan(halfZ + 1e-6)
		end
	end)

	it("fits inside the default 512 stud baseplate", function()
		-- The plot grid is generated on top of the existing baseplate rather than
		-- replacing it, so it has to actually fit.
		local halfX, halfZ = PlotLayout.gridHalfExtents(Plots)
		expect(halfX).toBeLessThan(256)
		expect(halfZ).toBeLessThan(256)
	end)
end)
