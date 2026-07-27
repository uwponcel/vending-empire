--!strict
--[[
	Proves the harness works and that shared modules really are requireable from
	Lune. If this suite ever fails to require, a Roblox API call has leaked into a
	module that is supposed to stay pure.
]]

local harness = require("../harness")
local Version = require("../../src/shared/Version")

local describe = harness.describe
local it = harness.it
local expect = harness.expect

describe("Version", function()
	it("formats a version as major.minor.patch", function()
		expect(Version.toString({ major = 1, minor = 2, patch = 3 })).toBe("1.2.3")
	end)

	it("exposes a current version", function()
		expect(type(Version.current.major)).toBe("number")
		expect(Version.toString(Version.current)).toBe("0.1.0")
	end)
end)
