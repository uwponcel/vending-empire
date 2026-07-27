--!strict

local harness = require("../harness")
local Economy = require("../../src/shared/Config/Economy")
local ProfileSchema = require("../../src/shared/Lib/ProfileSchema")

local describe = harness.describe
local it = harness.it
local expect = harness.expect

describe("ProfileSchema.template", function()
	it("stamps the current version", function()
		local data = ProfileSchema.template(100, 3)
		expect(data.version).toBe(ProfileSchema.VERSION)
	end)

	it("uses the values it is given rather than requiring config", function()
		local data = ProfileSchema.template(250, 5)
		expect(data.coins).toBe(250)
		expect(data.slotsUnlocked).toBe(5)
	end)

	it("matches the real economy defaults when wired up", function()
		local data = ProfileSchema.template(Economy.startingCoins, Economy.baseSlots)
		expect(data.coins).toBe(Economy.startingCoins)
		expect(data.slotsUnlocked).toBe(Economy.baseSlots)
	end)

	it("starts with no machines, no receipts, and a neutral prestige", function()
		local data = ProfileSchema.template(100, 3)
		expect(#data.machines).toBe(0)
		-- Extra parentheses are load-bearing. `next` returns two values, and without them
		-- both get spread into `expect`, which then compares the wrong one. It happened to
		-- pass here only because both were nil.
		expect((next(data.receipts))).toBe(nil)
		expect(data.prestige.count).toBe(0)
		expect(data.prestige.multiplier).toBe(1)
		expect(data.stats.totalEarned).toBe(0)
	end)

	it("returns an independent table each call", function()
		-- A shared default would let one player's first mutation become every future
		-- player's starting state.
		local first = ProfileSchema.template(100, 3)
		local second = ProfileSchema.template(100, 3)
		expect(first).toNotBe(second)

		first.coins = 999
		table.insert(first.machines, { slot = 1, typeId = "x", level = 1, lastCollectAt = 0 })
		first.prestige.count = 7

		expect(second.coins).toBe(100)
		expect(#second.machines).toBe(0)
		expect(second.prestige.count).toBe(0)
	end)

	it("keeps machines as a dense array, not indexed by slot", function()
		-- ProfileStore errors outright on gapped numeric tables, which is exactly what
		-- machines[slot] would produce for a player owning slots 1 and 5. Records carry
		-- their own slot instead.
		local data = ProfileSchema.template(100, 3)
		table.insert(
			data.machines,
			{ slot = 5, typeId = "drink_water", level = 1, lastCollectAt = 0 }
		)
		table.insert(
			data.machines,
			{ slot = 1, typeId = "drink_soda", level = 2, lastCollectAt = 0 }
		)

		expect(#data.machines).toBe(2)
		expect(data.machines[1].slot).toBe(5)
		expect(data.machines[2].slot).toBe(1)
	end)
end)

describe("ProfileSchema.isNewerThanSupported", function()
	it("is false for current and older data", function()
		expect(ProfileSchema.isNewerThanSupported({ version = ProfileSchema.VERSION } :: any)).toBe(
			false
		)
		expect(ProfileSchema.isNewerThanSupported({ version = 3 } :: any, 5)).toBe(false)
	end)

	it("is true for data from a newer build", function()
		expect(ProfileSchema.isNewerThanSupported({ version = 9 } :: any)).toBe(true)
		expect(ProfileSchema.isNewerThanSupported({ version = 6 } :: any, 5)).toBe(true)
	end)
end)

describe("ProfileSchema.migrate", function()
	it("does nothing when already at the target version", function()
		local data = ProfileSchema.template(100, 3)
		expect(ProfileSchema.migrate(data)).toBe(0)
		expect(data.version).toBe(ProfileSchema.VERSION)
	end)

	it("runs each step in order and lands on the target version", function()
		-- Drives the machinery with an injected chain, so it is verified now rather than
		-- the first time a real version 2 ships against live player data.
		local trace = {}
		local chain = {
			[1] = function(data: any)
				table.insert(trace, "1to2")
				data.addedInV2 = true
			end,
			[2] = function(data: any)
				table.insert(trace, "2to3")
				data.addedInV3 = data.addedInV2 and "saw v2" or "missed v2"
			end,
		}

		local data: any = ProfileSchema.template(100, 3)
		data.version = 1
		local applied = ProfileSchema.migrate(data, chain, 3)

		expect(applied).toBe(2)
		expect(data.version).toBe(3)
		expect(trace).toEqual({ "1to2", "2to3" })
		-- Proves the steps ran in sequence rather than concurrently or backwards.
		expect(data.addedInV3).toBe("saw v2")
	end)

	it("unlocks every visible slot through the real migration chain", function()
		local data = ProfileSchema.template(100, 12)
		data.version = 1
		data.slotsUnlocked = 3

		expect(ProfileSchema.migrate(data)).toBe(2)
		expect(data.version).toBe(ProfileSchema.VERSION)
		expect(data.slotsUnlocked).toBe(12)
	end)

	it("unlocks version 2 profiles that already received the first-row migration", function()
		local data = ProfileSchema.template(100, 12)
		data.version = 2
		data.slotsUnlocked = 4

		expect(ProfileSchema.migrate(data)).toBe(1)
		expect(data.slotsUnlocked).toBe(12)
	end)

	it("does not relock a profile that already had more slots", function()
		local data = ProfileSchema.template(100, 12)
		data.version = 2
		data.slotsUnlocked = 16

		ProfileSchema.migrate(data)
		expect(data.slotsUnlocked).toBe(16)
	end)

	it("runs only the remaining steps when data is partway up the chain", function()
		local trace = {}
		local chain = {
			[1] = function()
				table.insert(trace, "1to2")
			end,
			[2] = function()
				table.insert(trace, "2to3")
			end,
		}

		local data: any = ProfileSchema.template(100, 3)
		data.version = 2

		expect(ProfileSchema.migrate(data, chain, 3)).toBe(1)
		expect(trace).toEqual({ "2to3" })
	end)

	it("errors on a gap in the chain instead of skipping it", function()
		-- Silently skipping would leave data in a shape no code expects, which is worse
		-- than refusing to load.
		local chain = {
			[1] = function() end,
			-- no [2]
		}
		local data: any = ProfileSchema.template(100, 3)
		data.version = 1

		expect(function()
			ProfileSchema.migrate(data, chain, 4)
		end).toThrow("no migration from version 2")
	end)

	it("refuses data from a newer build rather than downgrading it", function()
		-- The failure this prevents: an old server saving over data written by a newer
		-- one, destroying whatever the newer version added, with no undo.
		local data: any = ProfileSchema.template(100, 3)
		data.version = 5

		expect(function()
			ProfileSchema.migrate(data, {}, 2)
		end).toThrow("newer than supported")
	end)

	it("errors when version is missing rather than guessing", function()
		local data: any = ProfileSchema.template(100, 3)
		data.version = nil

		expect(function()
			ProfileSchema.migrate(data)
		end).toThrow("no numeric version")
	end)

	it("preserves untouched fields across a migration", function()
		local chain = {
			[1] = function(data: any)
				data.newField = 1
			end,
		}
		local data: any = ProfileSchema.template(100, 3)
		data.version = 1
		data.coins = 4321
		table.insert(
			data.machines,
			{ slot = 2, typeId = "drink_soda", level = 3, lastCollectAt = 99 }
		)

		ProfileSchema.migrate(data, chain, 2)

		expect(data.coins).toBe(4321)
		expect(#data.machines).toBe(1)
		expect(data.machines[1].lastCollectAt).toBe(99)
	end)
end)

return {}
