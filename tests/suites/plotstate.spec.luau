--!strict

local harness = require("../harness")
local PlotState = require("../../src/shared/Lib/PlotState")

local describe = harness.describe
local it = harness.it
local expect = harness.expect

--- The physical slots a plot has, matching Config/Plots slotColumns * slotRows.
local SLOT_COUNT = 12

local WATER: PlotState.Priced = { id = "drink_water", cost = 50 }

local function record(slot: number, typeId: string?): PlotState.MachineRecord
	return {
		slot = slot,
		typeId = typeId or "drink_water",
		level = 1,
		lastCollectAt = 1_000,
	}
end

local function state(coins: number, slotsUnlocked: number, slots: { number }): PlotState.State
	local machines: { PlotState.MachineRecord } = {}
	for _, slot in slots do
		table.insert(machines, record(slot))
	end
	return { coins = coins, machines = machines, slotsUnlocked = slotsUnlocked }
end

describe("PlotState lookups", function()
	it("finds a record by slot regardless of array order", function()
		-- Array order is insertion order, not slot order, because records are appended.
		-- Nothing may assume index equals slot.
		local machines = { record(5), record(1), record(9) }

		expect(PlotState.indexOfSlot(machines, 5)).toBe(1)
		expect(PlotState.indexOfSlot(machines, 1)).toBe(2)
		expect(PlotState.indexOfSlot(machines, 9)).toBe(3)
		expect(PlotState.indexOfSlot(machines, 3)).toBe(nil)
	end)

	it("returns the record itself through atSlot", function()
		local machines = { record(4, "drink_soda") }
		local found = PlotState.atSlot(machines, 4)

		expect(found).toBeTruthy()
		expect((found :: PlotState.MachineRecord).typeId).toBe("drink_soda")
		expect(PlotState.atSlot(machines, 6)).toBe(nil)
	end)

	it("reports free slots", function()
		local machines = { record(2) }

		expect(PlotState.isSlotFree(machines, 2)).toBe(false)
		expect(PlotState.isSlotFree(machines, 1)).toBe(true)
	end)
end)

describe("PlotState.firstFreeSlot", function()
	it("returns the lowest free slot so machines cluster instead of scattering", function()
		expect(PlotState.firstFreeSlot(state(0, 3, { 1, 3 }), SLOT_COUNT)).toBe(2)
	end)

	it("returns nil once every unlocked slot is taken", function()
		expect(PlotState.firstFreeSlot(state(0, 3, { 1, 2, 3 }), SLOT_COUNT)).toBe(nil)
	end)

	it("never returns a locked slot even though the plot has the anchor for it", function()
		-- Slot 4 exists in the world but is not unlocked yet, so the answer is nil.
		expect(PlotState.firstFreeSlot(state(0, 3, { 1, 2, 3 }), SLOT_COUNT)).toBe(nil)
		expect(PlotState.firstFreeSlot(state(0, 4, { 1, 2, 3 }), SLOT_COUNT)).toBe(4)
	end)

	it("clamps to the physical slot count when config unlocks more than the plot has", function()
		-- Guards a config drift where Economy.maxSlots outgrows Config/Plots. Handing out
		-- slot 13 would place a machine at a slot with no anchor part.
		expect(PlotState.firstFreeSlot(state(0, 99, {}), SLOT_COUNT)).toBe(1)
		local full = {}
		for slot = 1, SLOT_COUNT do
			table.insert(full, slot)
		end
		expect(PlotState.firstFreeSlot(state(0, 99, full), SLOT_COUNT)).toBe(nil)
	end)
end)

describe("PlotState.purchaseRejection", function()
	it("allows a legal purchase", function()
		expect(PlotState.purchaseRejection(state(50, 3, {}), WATER, 1, SLOT_COUNT)).toBe(nil)
	end)

	it("allows spending down to exactly zero", function()
		-- The check is `coins < cost`, not `<=`. A player able to afford a machine to the
		-- coin must be able to buy it.
		expect(PlotState.purchaseRejection(state(50, 3, {}), WATER, 1, SLOT_COUNT)).toBe(nil)
		expect(PlotState.purchaseRejection(state(49, 3, {}), WATER, 1, SLOT_COUNT)).toBe(
			PlotState.Rejection.insufficientFunds
		)
	end)

	it("rejects a slot outside the plot", function()
		local empty = state(1_000, 12, {})
		expect(PlotState.purchaseRejection(empty, WATER, 0, SLOT_COUNT)).toBe(
			PlotState.Rejection.slotOutOfRange
		)
		expect(PlotState.purchaseRejection(empty, WATER, 13, SLOT_COUNT)).toBe(
			PlotState.Rejection.slotOutOfRange
		)
		expect(PlotState.purchaseRejection(empty, WATER, -3, SLOT_COUNT)).toBe(
			PlotState.Rejection.slotOutOfRange
		)
	end)

	it("rejects a fractional or NaN slot, which a crafted remote can send", function()
		local empty = state(1_000, 12, {})
		expect(PlotState.purchaseRejection(empty, WATER, 1.5, SLOT_COUNT)).toBe(
			PlotState.Rejection.slotOutOfRange
		)
		expect(PlotState.purchaseRejection(empty, WATER, 0 / 0, SLOT_COUNT)).toBe(
			PlotState.Rejection.slotOutOfRange
		)
		expect(PlotState.purchaseRejection(empty, WATER, math.huge, SLOT_COUNT)).toBe(
			PlotState.Rejection.slotOutOfRange
		)
	end)

	it("rejects a slot that exists but is not unlocked", function()
		expect(PlotState.purchaseRejection(state(1_000, 3, {}), WATER, 4, SLOT_COUNT)).toBe(
			PlotState.Rejection.slotLocked
		)
		-- The boundary is inclusive: the last unlocked slot is buyable.
		expect(PlotState.purchaseRejection(state(1_000, 3, {}), WATER, 3, SLOT_COUNT)).toBe(nil)
	end)

	it("rejects a slot that already holds a machine", function()
		expect(PlotState.purchaseRejection(state(1_000, 3, { 2 }), WATER, 2, SLOT_COUNT)).toBe(
			PlotState.Rejection.slotTaken
		)
	end)

	it("reports the most structural failure first", function()
		-- Broke on every count: slot does not exist, is not unlocked, and no coins. A player
		-- told they cannot afford it would go grind, then hit the same wall.
		local broke = state(0, 1, {})
		expect(PlotState.purchaseRejection(broke, WATER, 99, SLOT_COUNT)).toBe(
			PlotState.Rejection.slotOutOfRange
		)
		expect(PlotState.purchaseRejection(broke, WATER, 5, SLOT_COUNT)).toBe(
			PlotState.Rejection.slotLocked
		)
	end)
end)

describe("PlotState mutations keep the array dense", function()
	it("appends rather than indexing by slot", function()
		local machines: { PlotState.MachineRecord } = {}
		PlotState.insert(machines, record(5))
		PlotState.insert(machines, record(1))

		-- If this were slot-indexed, #machines would read 1 and the slot 5 record would be
		-- dropped by ProfileStore's serialiser with no error. See Packages/README.md.
		expect(#machines).toBe(2)
		expect(machines[1].slot).toBe(5)
		expect(machines[2].slot).toBe(1)
	end)

	it("refuses a second machine on one slot, because lookups only see the first", function()
		local machines = { record(3) }
		expect(function()
			PlotState.insert(machines, record(3))
		end).toThrow("already occupied")
	end)

	it("closes the gap on removal", function()
		local machines = { record(1), record(5), record(9) }
		local removed = PlotState.removeSlot(machines, 5)

		expect(removed).toBeTruthy()
		expect((removed :: PlotState.MachineRecord).slot).toBe(5)

		-- The regression that matters. A hole here saves as a truncated array and silently
		-- deletes every machine past it.
		expect(#machines).toBe(2)
		expect(machines[1].slot).toBe(1)
		expect(machines[2].slot).toBe(9)

		local counted = 0
		for _ in machines do
			counted += 1
		end
		expect(counted).toBe(2)
	end)

	it("returns nil when removing from an empty slot", function()
		local machines = { record(1) }
		expect(PlotState.removeSlot(machines, 7)).toBe(nil)
		expect(#machines).toBe(1)
	end)

	it("frees the slot for reuse after removal", function()
		local machines = { record(2) }
		PlotState.removeSlot(machines, 2)
		expect(PlotState.isSlotFree(machines, 2)).toBe(true)
		PlotState.insert(machines, record(2, "drink_soda"))
		expect(#machines).toBe(1)
	end)
end)

return {}
