--!strict

local harness = require("../harness")
local Economy = require("../../src/shared/Config/Economy")
local UpgradeCurve = require("../../src/shared/Lib/UpgradeCurve")

local describe = harness.describe
local it = harness.it
local expect = harness.expect

local params = Economy.upgrade
local sampleMachine = { baseRate = 10, fillSeconds = 30 }

describe("UpgradeCurve.growthAt", function()
	it("is exactly 1 at level 1, so base stats are never rounded off", function()
		expect(UpgradeCurve.growthAt(1, params)).toBe(1)
	end)

	it("increases strictly with level", function()
		for level = 2, params.maxLevel do
			expect(UpgradeCurve.growthAt(level, params)).toBeGreaterThan(
				UpgradeCurve.growthAt(level - 1, params)
			)
		end
	end)

	it("rejects levels outside the valid range", function()
		expect(function()
			UpgradeCurve.growthAt(0, params)
		end).toThrow("outside")
		expect(function()
			UpgradeCurve.growthAt(params.maxLevel + 1, params)
		end).toThrow("outside")
		expect(function()
			UpgradeCurve.growthAt(1.5, params)
		end).toThrow("integer")
	end)
end)

describe("UpgradeCurve.effective", function()
	it("returns the authored base stats at level 1 with no multiplier", function()
		local stats = UpgradeCurve.effective(sampleMachine, 1, params)
		expect(stats.rate).toBe(10)
		expect(stats.capacity).toBe(300)
	end)

	it("holds fill time constant across every level", function()
		-- The invariance Config/Machines depends on. Capacity is derived from rate, so
		-- no level can turn a machine into one that needs a different collect cadence.
		for level = 1, params.maxLevel do
			local stats = UpgradeCurve.effective(sampleMachine, level, params)
			expect(stats.capacity / stats.rate).toBeCloseTo(sampleMachine.fillSeconds, 1e-9)
		end
	end)

	it("holds fill time constant across prestige multipliers too", function()
		for _, multiplier in { 1, 2, 7.5, 1000 } do
			local stats = UpgradeCurve.effective(sampleMachine, 4, params, multiplier)
			expect(stats.capacity / stats.rate).toBeCloseTo(sampleMachine.fillSeconds, 1e-9)
		end
	end)

	it("scales rate by both level growth and multiplier", function()
		local base = UpgradeCurve.effective(sampleMachine, 1, params, 1)
		local doubled = UpgradeCurve.effective(sampleMachine, 1, params, 2)
		expect(doubled.rate).toBeCloseTo(base.rate * 2, 1e-9)

		local levelled = UpgradeCurve.effective(sampleMachine, 3, params, 1)
		expect(levelled.rate).toBeCloseTo(10 * params.rateGrowth ^ 2, 1e-9)
	end)
end)

describe("UpgradeCurve.upgradeCost", function()
	it("charges costFactor of the purchase price for the first upgrade", function()
		expect(UpgradeCurve.upgradeCost(100, 1, params)).toBe(math.floor(100 * params.costFactor))
	end)

	it("increases strictly with level", function()
		for level = 2, params.maxLevel - 1 do
			expect(UpgradeCurve.upgradeCost(1000, level, params)).toBeGreaterThan(
				UpgradeCurve.upgradeCost(1000, level - 1, params)
			)
		end
	end)

	it("errors at max level instead of returning a sentinel", function()
		-- A caller that skips canUpgrade should fail loudly rather than charge a player
		-- for an upgrade that cannot happen.
		expect(function()
			UpgradeCurve.upgradeCost(1000, params.maxLevel, params)
		end).toThrow("already at max")
	end)

	it("returns whole coins", function()
		local cost = UpgradeCurve.upgradeCost(137, 3, params)
		expect(cost % 1).toBe(0)
	end)
end)

describe("UpgradeCurve.canUpgrade", function()
	it("is true below max level and false at it", function()
		expect(UpgradeCurve.canUpgrade(1, params)).toBe(true)
		expect(UpgradeCurve.canUpgrade(params.maxLevel - 1, params)).toBe(true)
		expect(UpgradeCurve.canUpgrade(params.maxLevel, params)).toBe(false)
	end)
end)

describe("UpgradeCurve.totalUpgradeCost", function()
	it("is zero when there is nothing to buy", function()
		expect(UpgradeCurve.totalUpgradeCost(1000, 3, 3, params)).toBe(0)
	end)

	it("sums the individual steps", function()
		local expected = UpgradeCurve.upgradeCost(1000, 1, params)
			+ UpgradeCurve.upgradeCost(1000, 2, params)
		expect(UpgradeCurve.totalUpgradeCost(1000, 1, 3, params)).toBe(expected)
	end)

	it("rejects a backwards range", function()
		expect(function()
			UpgradeCurve.totalUpgradeCost(1000, 5, 2, params)
		end).toThrow("below")
	end)
end)

describe("upgrade versus tier pacing", function()
	it("keeps maxing a machine more expensive per unit of output than a tier jump", function()
		-- This is the intended pressure, not an accident. While a player has an empty
		-- slot, buying the next machine should beat pouring coins into an old one.
		-- Upgrades earn their place only once slots run out, which is why slots are
		-- capped in Config/Economy.
		local baseCost = 1000
		local maxOutputGain = UpgradeCurve.growthAt(params.maxLevel, params)
		local maxUpgradeSpend = UpgradeCurve.totalUpgradeCost(baseCost, 1, params.maxLevel, params)

		local costPerUnitViaUpgrade = maxUpgradeSpend / (maxOutputGain - 1)
		-- A tier jump is roughly 5x the cost for roughly 4x the output.
		local costPerUnitViaTier = (baseCost * 5) / 4

		expect(costPerUnitViaUpgrade).toBeGreaterThan(costPerUnitViaTier)
	end)

	it("still makes the first upgrade affordable before the next tier is reachable", function()
		-- Onboarding matters: after buying the 50 coin tier 1 machine, the player needs
		-- something to spend on well before 250 coins.
		local firstUpgrade = UpgradeCurve.upgradeCost(50, 1, params)
		expect(firstUpgrade).toBeLessThan(250)
	end)
end)
