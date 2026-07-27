--!strict
--[[
	Guards the tuning table itself.

	These are not tests of code so much as tests of game design intent. The whole point
	of Phase 1 landing before any gameplay is that bad curves are expensive to fix after
	players have banked progress against them. Encoding the pacing intent here means a
	later "quick tuning tweak" that breaks the shape of progression fails CI instead of
	shipping.
]]

local harness = require("../harness")
local Machines = require("../../src/shared/Config/Machines")
local Economy = require("../../src/shared/Config/Economy")
local UpgradeCurve = require("../../src/shared/Lib/UpgradeCurve")

local describe = harness.describe
local it = harness.it
local expect = harness.expect

local function paybackSeconds(machine): number
	return machine.cost / machine.baseRate
end

describe("Machines table integrity", function()
	it("has machines", function()
		expect(#Machines.list).toBeGreaterThan(0)
	end)

	it("has unique ids", function()
		local seen = {}
		for _, machine in Machines.list do
			expect(seen[machine.id]).toBe(nil)
			seen[machine.id] = true
		end
	end)

	it("indexes every machine by id", function()
		for _, machine in Machines.list do
			expect(Machines.byId[machine.id]).toBe(machine)
		end
	end)

	it("has tiers numbered contiguously from 1 in array order", function()
		for index, machine in Machines.list do
			expect(machine.tier).toBe(index)
		end
	end)

	it("has positive cost, rate, and fill time everywhere", function()
		for _, machine in Machines.list do
			expect(machine.cost).toBeGreaterThan(0)
			expect(machine.baseRate).toBeGreaterThan(0)
			expect(machine.fillSeconds).toBeGreaterThan(0)
		end
	end)

	it("uses only known categories", function()
		local valid = { drinks = true, snacks = true, electronics = true }
		for _, machine in Machines.list do
			expect(valid[machine.category]).toBe(true)
		end
	end)

	it("has a non-empty display name for every machine", function()
		for _, machine in Machines.list do
			expect(#machine.displayName).toBeGreaterThan(0)
		end
	end)
end)

describe("Machines progression shape", function()
	it("increases cost strictly with tier", function()
		for index = 2, #Machines.list do
			expect(Machines.list[index].cost).toBeGreaterThan(Machines.list[index - 1].cost)
		end
	end)

	it("increases rate strictly with tier", function()
		for index = 2, #Machines.list do
			expect(Machines.list[index].baseRate).toBeGreaterThan(Machines.list[index - 1].baseRate)
		end
	end)

	it("increases fill time with tier, so late game is less clicky", function()
		for index = 2, #Machines.list do
			expect(Machines.list[index].fillSeconds).toBeGreaterThan(
				Machines.list[index - 1].fillSeconds
			)
		end
	end)

	it("grows payback time with tier, so progression decelerates", function()
		-- Cost climbing faster than rate is what eventually makes prestige more
		-- attractive than grinding one more tier. If this ever inverts, the game has
		-- no reason to ever reset and the retention hook dies.
		for index = 2, #Machines.list do
			expect(paybackSeconds(Machines.list[index])).toBeGreaterThan(
				paybackSeconds(Machines.list[index - 1])
			)
		end
	end)

	it("keeps each tier jump within a sane cost multiple", function()
		-- Too small and tiers feel meaningless, too large and progression walls.
		for index = 2, #Machines.list do
			local ratio = Machines.list[index].cost / Machines.list[index - 1].cost
			expect(ratio).toBeGreaterThan(3)
			expect(ratio).toBeLessThan(8)
		end
	end)

	it("keeps each tier jump within a sane rate multiple", function()
		for index = 2, #Machines.list do
			local ratio = Machines.list[index].baseRate / Machines.list[index - 1].baseRate
			expect(ratio).toBeGreaterThan(2.5)
			expect(ratio).toBeLessThan(6)
		end
	end)

	it("never lets payback time run past the patience of a session", function()
		-- The slowest machine must still pay for itself inside roughly ten minutes at
		-- level 1, before any prestige multiplier.
		for _, machine in Machines.list do
			expect(paybackSeconds(machine)).toBeLessThan(600)
		end
	end)
end)

describe("Machines onboarding", function()
	it("lets a new player afford the tier 1 machine immediately", function()
		expect(Economy.startingCoins).toBeGreaterThan(Machines.list[1].cost)
	end)

	it("shows a new player the whole loop inside the first minute", function()
		-- Buy, fill, collect. If the first machine took several minutes to fill, the
		-- tutorial moment would be a player standing still wondering if it is broken.
		expect(Machines.list[1].fillSeconds).toBeLessThan(30)
	end)

	it("needs only a few collects to afford the second machine", function()
		local first = Machines.list[1]
		local second = Machines.list[2]
		local perCollect = first.baseRate * first.fillSeconds
		local collectsNeeded = math.ceil((second.cost - Economy.startingCoins) / perCollect)
		expect(collectsNeeded).toBeLessThan(15)
	end)
end)

describe("Machines against the upgrade curve", function()
	it("derives capacity from rate for every machine at every level", function()
		-- Fill time is the design knob. Capacity is derived, never authored, so it
		-- cannot drift away from rate for any machine in the table.
		for _, machine in Machines.list do
			for level = 1, Economy.upgrade.maxLevel do
				local stats = UpgradeCurve.effective(machine, level, Economy.upgrade)
				expect(stats.capacity / stats.rate).toBeCloseTo(machine.fillSeconds, 1e-6)
			end
		end
	end)

	it("keeps a maxed machine below the next tier at level 1", function()
		-- Otherwise a fully upgraded low tier would obsolete the tier above it and the
		-- shop would stop mattering.
		local maxLevel = Economy.upgrade.maxLevel
		for index = 1, #Machines.list - 1 do
			local maxed = UpgradeCurve.effective(Machines.list[index], maxLevel, Economy.upgrade)
			local nextTierBase =
				UpgradeCurve.effective(Machines.list[index + 1], 1, Economy.upgrade)
			expect(maxed.rate).toBeLessThan(nextTierBase.rate)
		end
	end)

	it("keeps total offline earnings modest against active play", function()
		-- Every slot full of the best machine, all capped out, is the maximum a player
		-- can bank while away. It should read as a nice welcome back, not as a reason
		-- to stop playing.
		local best = Machines.list[#Machines.list]
		local stats = UpgradeCurve.effective(best, 1, Economy.upgrade)
		local maxOffline = stats.capacity * Economy.maxSlots
		local activeEarningsPerHour = stats.rate * Economy.maxSlots * 3600

		expect(maxOffline).toBeLessThan(activeEarningsPerHour)
	end)
end)
