--!strict
--[[
	Test entry point. Run with:

		lune run tests/run

	Suites are listed explicitly rather than globbed so the order is deterministic
	and adding a suite shows up in the diff.

	Each suite registers its tests as a side effect of being required and then returns an
	empty table. The return is not decoration: a module that returns nothing is not
	requireable under strict analysis, so without it `luau-lsp analyze` rejects every line
	below. Requiring a suite twice will not re-run it, since require caches.
]]

local harness = require("./harness")

require("./suites/version.spec")
require("./suites/format.spec")
require("./suites/result.spec")
require("./suites/accrual.spec")
require("./suites/upgradecurve.spec")
require("./suites/machines.spec")
require("./suites/plotlayout.spec")
require("./suites/plotstate.spec")
require("./suites/profileschema.spec")

harness.finish()
