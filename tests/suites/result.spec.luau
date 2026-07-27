--!strict

local harness = require("../harness")
local Result = require("../../src/shared/Lib/Result")

local describe = harness.describe
local it = harness.it
local expect = harness.expect

describe("Result", function()
	it("carries the value through ok", function()
		local result = Result.ok(42)
		expect(result.tag).toBe("ok")
		expect(result.value).toBe(42)
	end)

	it("carries the code through err", function()
		local result = Result.err("slot_taken")
		expect(result.tag).toBe("err")
		expect(result.reason).toBe("slot_taken")
	end)

	it("accepts an err where any Result is expected, with nothing to annotate", function()
		-- The reason `err` returns the unparameterised `Err` rather than `Result<T>`. If this
		-- assignment ever needed a cast, every server handler would need one too.
		local failure: Result.Result<number> = Result.err("slot_locked")
		expect(failure.tag).toBe("err")
	end)

	it("narrows on the tag, which is the whole point of tagging with a string", function()
		-- Written the way callers are expected to write it. If Luau ever stopped narrowing
		-- here this still passes at runtime, but the type check gate fails, which is the
		-- signal we want.
		local results: { Result.Result<number> } = { Result.ok(7), Result.err("nope") }

		local total = 0
		local reasons = 0
		for _, result in results do
			if result.tag == "ok" then
				total += result.value
			else
				reasons += 1
			end
		end

		expect(total).toBe(7)
		expect(reasons).toBe(1)
	end)

	it("reports a reason only for failures", function()
		local failure: Result.Result<string> = Result.err("too_far")
		local success: Result.Result<string> = Result.ok("anything")

		expect(Result.reason(failure)).toBe("too_far")
		expect(Result.reason(success)).toBe(nil)
	end)

	it("unwraps a success", function()
		local success: Result.Result<string> = Result.ok("value")
		expect(Result.expect(success)).toBe("value")
	end)

	it("throws on unwrapping a failure, with the code in the message", function()
		local failure: Result.Result<string> = Result.err("insufficient_funds")
		expect(function()
			Result.expect(failure)
		end).toThrow("insufficient_funds")
	end)
end)

return {}
