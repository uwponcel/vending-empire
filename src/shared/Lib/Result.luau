--!strict
--[[
	A success-or-reason wrapper for validation. Pure, zero requires.

	Every rule the server enforces on a player's request has to produce two things: a
	yes/no answer, and a reason the client can turn into a message. Returning
	`(boolean, string?)` would do it, but multi-return values are exactly what bit this
	project once already (see the typing notes in CLAUDE.md), and they cannot be stored
	or passed around as a single value.

	Tagged with a string rather than a boolean field. Luau narrows a union on a string
	singleton comparison reliably, so `if result.tag == "ok" then` gives the caller
	`result.value` with no cast.

	There is no `isOk` narrowing helper on purpose. Luau has no user-defined type guards,
	so a helper returning `boolean` would answer the question without narrowing the type,
	and the caller would still need the inline comparison. Compare the tag directly.
]]

export type Ok<T> = {
	tag: "ok",
	value: T,
}

export type Err = {
	--- A stable machine-readable code, not a sentence. The client maps it to copy so
	--- wording can change without touching the server.
	tag: "err",
	reason: string,
}

export type Result<T> = Ok<T> | Err

local Result = {}

function Result.ok<T>(value: T): Ok<T>
	return { tag = "ok", value = value }
end

--[[
	Returns `Err` rather than `Result<T>` deliberately. `Err` carries no type parameter,
	so it is assignable to `Result<T>` for every T, and a caller can `return Result.err(...)`
	from a function declared to return `Result<SomethingSpecific>` with nothing to annotate.
]]
function Result.err(reason: string): Err
	return { tag = "err", reason = reason }
end

--- The failure code, or nil on success. For logging, where narrowing is not wanted.
function Result.reason<T>(result: Result<T>): string?
	if result.tag == "err" then
		return result.reason
	end
	return nil
end

--[[
	Unwraps or throws. For tests and for genuine invariant violations only.

	Never call this on a path that handles player input. Player input failing validation
	is the normal case, not an error, and turning it into a thrown error means one bad
	request kills the handler thread.
]]
function Result.expect<T>(result: Result<T>): T
	if result.tag == "ok" then
		return result.value
	end
	error(`expected ok, got err: {result.reason}`, 2)
end

return Result
