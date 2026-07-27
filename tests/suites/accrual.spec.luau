--!strict

local harness = require("../harness")
local Accrual = require("../../src/shared/Lib/Accrual")

local describe = harness.describe
local it = harness.it
local expect = harness.expect

-- 1 coin/sec, holds 60. Fills in a minute.
local RATE = 1
local CAPACITY = 60

describe("Accrual.pending", function()
	it("accrues linearly below capacity", function()
		expect(Accrual.pending(RATE, CAPACITY, 0)).toBe(0)
		expect(Accrual.pending(RATE, CAPACITY, 30)).toBe(30)
		expect(Accrual.pending(RATE, CAPACITY, 59)).toBe(59)
	end)

	it("clamps at capacity no matter how long it sat", function()
		expect(Accrual.pending(RATE, CAPACITY, 60)).toBe(60)
		expect(Accrual.pending(RATE, CAPACITY, 600)).toBe(60)
		-- The clamp is the whole anti-exploit story for offline earnings. A day away
		-- pays exactly the same as a minute past full.
		expect(Accrual.pending(RATE, CAPACITY, 86400)).toBe(60)
	end)

	it("floors to whole coins", function()
		expect(Accrual.pending(RATE, CAPACITY, 30.9)).toBe(30)
		expect(Accrual.pending(0.5, CAPACITY, 3)).toBe(1)
	end)

	it("returns zero for non-positive elapsed instead of a negative", function()
		-- Reachable through clock adjustment between servers.
		expect(Accrual.pending(RATE, CAPACITY, -100)).toBe(0)
	end)

	it("rejects a non-positive rate as a config bug", function()
		expect(function()
			Accrual.pending(0, CAPACITY, 10)
		end).toThrow("rate must be positive")
	end)
end)

describe("Accrual.collect", function()
	it("pays the accrued amount and advances the timestamp", function()
		local result = Accrual.collect(RATE, CAPACITY, 1000, 1030)
		expect(result.amount).toBe(30)
		expect(result.lastCollectAt).toBe(1030)
	end)

	it("carries the unpaid fraction of a coin forward", function()
		-- Rule 1. Without this, spamming collect faster than one coin accrues would
		-- pay floor(0.4) = 0 every time while resetting the clock, and the machine
		-- would earn nothing at all.
		local first = Accrual.collect(RATE, CAPACITY, 1000, 1000.4)
		expect(first.amount).toBe(0)
		expect(first.lastCollectAt).toBe(1000)

		-- Timestamp did not move, so the accrued time is still there a moment later.
		local second = Accrual.collect(RATE, CAPACITY, first.lastCollectAt, 1001)
		expect(second.amount).toBe(1)
	end)

	it("does not lose value across many partial collects", function()
		-- Ten collects at 0.3s each on a 1/sec machine must still total 3 coins.
		local last = 0
		local total = 0
		for step = 1, 10 do
			local result = Accrual.collect(RATE, CAPACITY, last, step * 0.3)
			total += result.amount
			last = result.lastCollectAt
		end
		expect(total).toBe(3)
	end)

	it("restarts accrual at now when the machine was full", function()
		-- Rule 2, and the reason it exists. Advancing only by capacity/rate would
		-- leave lastCollectAt an hour in the past on a machine that sat overnight, so
		-- it would read as full again immediately and could be drained repeatedly in
		-- a single second. That is infinite money, not a rounding detail.
		local result = Accrual.collect(RATE, CAPACITY, 0, 86400)
		expect(result.amount).toBe(60)
		expect(result.lastCollectAt).toBe(86400)

		-- Immediately collecting again pays nothing.
		local again = Accrual.collect(RATE, CAPACITY, result.lastCollectAt, 86400)
		expect(again.amount).toBe(0)
	end)

	it("discards overflow rather than banking it", function()
		local result = Accrual.collect(RATE, CAPACITY, 0, 3600)
		-- An hour on a machine holding 60 pays 60, not 3600.
		expect(result.amount).toBe(60)
	end)

	it("pays nothing and holds the timestamp when the clock goes backwards", function()
		local result = Accrual.collect(RATE, CAPACITY, 5000, 4000)
		expect(result.amount).toBe(0)
		expect(result.lastCollectAt).toBe(5000)
	end)

	it("treats reaching capacity exactly as full", function()
		local result = Accrual.collect(RATE, CAPACITY, 0, 60)
		expect(result.amount).toBe(60)
		expect(result.lastCollectAt).toBe(60)
	end)
end)

describe("Accrual.secondsUntilFull", function()
	it("counts down toward the fill time", function()
		expect(Accrual.secondsUntilFull(RATE, CAPACITY, 0, 0)).toBe(60)
		expect(Accrual.secondsUntilFull(RATE, CAPACITY, 0, 45)).toBe(15)
	end)

	it("reports zero once full instead of going negative", function()
		expect(Accrual.secondsUntilFull(RATE, CAPACITY, 0, 60)).toBe(0)
		expect(Accrual.secondsUntilFull(RATE, CAPACITY, 0, 9999)).toBe(0)
	end)
end)
