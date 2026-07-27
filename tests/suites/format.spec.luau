--!strict

local harness = require("../harness")
local Format = require("../../src/shared/Lib/Format")

local describe = harness.describe
local it = harness.it
local expect = harness.expect

describe("Format.short", function()
	it("leaves values under a thousand as plain integers", function()
		expect(Format.short(0)).toBe("0")
		expect(Format.short(7)).toBe("7")
		expect(Format.short(999)).toBe("999")
	end)

	it("switches to a suffix at exactly one thousand", function()
		expect(Format.short(1000)).toBe("1K")
	end)

	it("truncates instead of rounding, so a balance is never overstated", function()
		-- The bug this guards: showing "2K" for 1999 and then refusing a 2000 purchase.
		expect(Format.short(1999)).toBe("1.99K")
		expect(Format.short(1049)).toBe("1.04K")
		expect(Format.short(999999)).toBe("999K")
	end)

	it("holds three significant digits as magnitude grows", function()
		expect(Format.short(1234)).toBe("1.23K")
		expect(Format.short(12345)).toBe("12.3K")
		expect(Format.short(123456)).toBe("123K")
	end)

	it("strips trailing zeros rather than padding decimals", function()
		expect(Format.short(1200)).toBe("1.2K")
		expect(Format.short(2000000)).toBe("2M")
	end)

	it("lands on the right suffix at exact powers of a thousand", function()
		-- Computing the bucket with log(n, 1000) misplaces these because of float
		-- error, producing "1000K" instead of "1M".
		expect(Format.short(1e6)).toBe("1M")
		expect(Format.short(1e9)).toBe("1B")
		expect(Format.short(1e12)).toBe("1T")
		expect(Format.short(1e15)).toBe("1Qa")
	end)

	it("clamps at the largest known suffix rather than indexing past the table", function()
		expect(Format.short(1e33)).toBe("1Dc")
		expect(Format.short(1e36)).toBe("1000Dc")
	end)

	it("keeps the sign on negative values", function()
		expect(Format.short(-1500)).toBe("-1.5K")
		expect(Format.short(-42)).toBe("-42")
	end)
end)

describe("Format.comma", function()
	it("groups thousands", function()
		expect(Format.comma(0)).toBe("0")
		expect(Format.comma(999)).toBe("999")
		expect(Format.comma(1000)).toBe("1,000")
		expect(Format.comma(1234567)).toBe("1,234,567")
		expect(Format.comma(1000000000)).toBe("1,000,000,000")
	end)

	it("keeps the sign and drops the fraction", function()
		expect(Format.comma(-1234567)).toBe("-1,234,567")
		expect(Format.comma(1234.99)).toBe("1,234")
	end)
end)

describe("Format.duration", function()
	it("reads zero and below as 0s, because only clock skew produces a negative", function()
		expect(Format.duration(0)).toBe("0s")
		expect(Format.duration(-5)).toBe("0s")
	end)

	it("shows seconds under a minute", function()
		expect(Format.duration(1)).toBe("1s")
		expect(Format.duration(59)).toBe("59s")
	end)

	it("shows at most two units", function()
		expect(Format.duration(60)).toBe("1m")
		expect(Format.duration(150)).toBe("2m 30s")
		expect(Format.duration(3600)).toBe("1h")
		expect(Format.duration(3900)).toBe("1h 5m")
		expect(Format.duration(86400)).toBe("1d")
		expect(Format.duration(97200)).toBe("1d 3h")
	end)

	it("omits a trailing zero unit", function()
		expect(Format.duration(120)).toBe("2m")
		expect(Format.duration(7200)).toBe("2h")
	end)
end)

return {}
