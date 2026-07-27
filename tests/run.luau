--!strict
--[[
	Test entry point. Run with:

		lune run tests/run

	Suites are listed explicitly rather than globbed so the order is deterministic
	and adding a suite shows up in the diff.
]]

local harness = require("./harness")

require("./suites/version.spec")
require("./suites/format.spec")
require("./suites/accrual.spec")
require("./suites/upgradecurve.spec")
require("./suites/machines.spec")

harness.finish()
