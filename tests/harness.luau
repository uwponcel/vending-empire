--!nonstrict
--[[
	Minimal test harness for Lune.

	Deliberately dependency-free. Suites call `describe`/`it`/`expect`, then
	`run.luau` calls `finish()` which prints a report and sets the exit code.

	Only modules with zero Roblox API usage can be tested here, which is why
	`shared/Lib` and `shared/Config` are kept free of `script` and `game`.
]]

local stdio = require("@lune/stdio")
local process = require("@lune/process")

local harness = {}

local state = {
	currentSuite = nil :: string?,
	passed = 0,
	failures = {} :: { { suite: string, name: string, message: string } },
}

--- Narrowed to the colours stdio actually accepts, rather than `string`, so a typo is a
--- type error instead of a runtime one.
type Color = "black" | "blue" | "cyan" | "green" | "purple" | "red" | "white" | "yellow"

local function color(name: Color, text: string): string
	return stdio.color(name) .. text .. stdio.color("reset")
end

local function describeValue(value: any): string
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

local function deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for key, value in a do
		if not deepEqual(value, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

--[[
	Fluent assertion object. Every matcher raises a plain Luau error on failure,
	which `it` catches and records with the suite and test name attached.
]]
function harness.expect(actual: any)
	local matchers = {}

	function matchers.toBe(expected: any)
		if actual ~= expected then
			error(`expected {describeValue(expected)} but got {describeValue(actual)}`, 2)
		end
	end

	function matchers.toNotBe(expected: any)
		if actual == expected then
			error(`expected something other than {describeValue(expected)}`, 2)
		end
	end

	function matchers.toEqual(expected: any)
		if not deepEqual(actual, expected) then
			error(
				`expected deep equality with {describeValue(expected)}, got {describeValue(actual)}`,
				2
			)
		end
	end

	function matchers.toBeCloseTo(expected: number, tolerance: number?)
		local limit = tolerance or 1e-9
		if math.abs(actual - expected) > limit then
			error(`expected {expected} within {limit} but got {actual}`, 2)
		end
	end

	function matchers.toBeGreaterThan(limit: number)
		if not (actual > limit) then
			error(`expected a value greater than {limit} but got {actual}`, 2)
		end
	end

	function matchers.toBeLessThan(limit: number)
		if not (actual < limit) then
			error(`expected a value less than {limit} but got {actual}`, 2)
		end
	end

	function matchers.toBeTruthy()
		if not actual then
			error(`expected a truthy value but got {describeValue(actual)}`, 2)
		end
	end

	function matchers.toThrow(substring: string?)
		if type(actual) ~= "function" then
			error("toThrow expects a function", 2)
		end
		local ok, err = pcall(actual)
		if ok then
			error("expected the call to throw, but it returned normally", 2)
		end
		if substring ~= nil and not string.find(tostring(err), substring, 1, true) then
			error(
				`expected the error to contain {describeValue(substring)}, got {describeValue(err)}`,
				2
			)
		end
	end

	return matchers
end

function harness.describe(name: string, body: () -> ()): ()
	local previous = state.currentSuite
	state.currentSuite = name
	body()
	state.currentSuite = previous
end

function harness.it(name: string, body: () -> ()): ()
	local suite = state.currentSuite or "(root)"
	local ok, err = pcall(body)
	if ok then
		state.passed += 1
	else
		table.insert(state.failures, { suite = suite, name = name, message = tostring(err) })
	end
end

--[[
	Prints the report and exits. Non-zero exit on any failure is what makes this
	usable as a CI gate.
]]
function harness.finish(): ()
	local failed = #state.failures

	if failed > 0 then
		print("")
		for _, failure in state.failures do
			print(color("red", `FAIL  {failure.suite} > {failure.name}`))
			print(`      {failure.message}`)
		end
	end

	print("")
	if failed == 0 then
		print(color("green", `{state.passed} passed`))
		process.exit(0)
	else
		print(color("red", `{failed} failed`) .. `, {state.passed} passed`)
		process.exit(1)
	end
end

return harness
