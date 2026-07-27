--!strict
--[[
	Lazy coin accrual. Pure, zero requires.

	Machines never tick. A machine stores only `lastCollectAt`, a wall-clock second
	from os.time(), and everything else is derived on demand:

		pending = min(capacity, rate * (now - lastCollectAt))

	That costs nothing while idle, scales to any machine count, and makes offline
	earnings fall out for free with the capacity clamp as their natural ceiling.

	Two rules in `collect` are not obvious and both are money bugs if changed:

	1. UNDERPAYMENT CARRIES FORWARD.
	   Coins are integers, so a collect pays floor(raw). If `lastCollectAt` were reset
	   to `now` regardless, a player collecting a 1 coin/sec machine every 0.4s would
	   be paid floor(0.4) = 0 every time, forever, while the clock kept resetting. The
	   machine would earn nothing. So the timestamp only advances by the time actually
	   paid for: amount / rate.

	2. OVERFLOW IS LOST, AND THE CLOCK RESTARTS AT NOW.
	   When a machine has been full, the excess is discarded and `lastCollectAt` becomes
	   `now`. Advancing it by only capacity/rate instead would leave the timestamp hours
	   in the past on a machine that sat overnight, so it would read as full again
	   immediately and could be drained repeatedly in one second. That is an infinite
	   money exploit, not a rounding detail.
]]

local Accrual = {}

local LOG_2 = math.log(2)

export type Collected = {
	--- Whole coins to credit. Always an integer, never negative.
	amount: number,
	--- The value to persist as the machine's new lastCollectAt.
	lastCollectAt: number,
}

local function assertRate(rate: number): ()
	if rate <= 0 then
		error(`rate must be positive, got {rate}`, 3)
	end
end

--[[
	Whole coins currently waiting on a machine.

	Non-positive elapsed yields 0 rather than a negative. Elapsed can go non-positive
	from clock adjustment between servers, and a negative balance change is worse than
	a player waiting a moment longer.
]]
function Accrual.pending(rate: number, capacity: number, elapsedSeconds: number): number
	assertRate(rate)
	if elapsedSeconds <= 0 then
		return 0
	end
	return math.floor(math.min(capacity, rate * elapsedSeconds))
end

--[[
	Resolves a collect. Returns the amount to credit and the timestamp to persist.

	Never mutates anything and never reads a clock itself, so a test can drive it
	through any timeline. The caller supplies `now`, which on the server is os.time().
]]
function Accrual.collect(
	rate: number,
	capacity: number,
	lastCollectAt: number,
	now: number
): Collected
	assertRate(rate)

	local elapsed = now - lastCollectAt
	if elapsed <= 0 then
		return { amount = 0, lastCollectAt = lastCollectAt }
	end

	local raw = rate * elapsed

	if raw >= capacity then
		-- Rule 2: overflow is gone, but a fractional capacity is still earned value. Carry
		-- that fraction into the next cycle while paying only whole coins now.
		local amount = math.floor(capacity)
		local remainder = capacity - amount
		return { amount = amount, lastCollectAt = now - remainder / rate }
	end

	-- Rule 1: advance only by the time actually paid for, so the unpaid fraction of a
	-- coin is still there on the next collect.
	local amount = math.floor(raw)
	return { amount = amount, lastCollectAt = lastCollectAt + amount / rate }
end

local function timestampQuantum(value: number): number
	local magnitude = math.max(1, math.abs(value))
	local exponent = math.floor(math.log(magnitude) / LOG_2)
	return 2 ^ (exponent - 52)
end

--[[
	Moves an accrual timestamp from one rate to another without changing the coins already
	waiting.

	An upgrade must not apply its higher rate to time that elapsed before the purchase. The
	timestamp may be fractional, just like the value returned by `collect`, so both whole
	coins and the unpaid fraction carry across exactly.
]]
function Accrual.rebaseLastCollectAt(
	oldRate: number,
	oldCapacity: number,
	lastCollectAt: number,
	newRate: number,
	now: number
): number
	assertRate(oldRate)
	assertRate(newRate)

	local elapsed = math.max(0, now - lastCollectAt)
	local accrued = math.min(oldCapacity, oldRate * elapsed)
	if accrued <= 0 then
		return now
	end

	-- At epoch-sized timestamps, adding a fixed epsilon smaller than the float spacing does
	-- nothing. Keep the reconstructed value safely inside the same whole-coin interval by a
	-- margin derived from the timestamp's actual representable quantum.
	local whole = math.floor(accrued)
	local margin = newRate * timestampQuantum(now) * 2
	if margin >= 0.5 then
		error(`rate {newRate} is too large to preserve whole-coin accrual at timestamp {now}`, 2)
	end

	local fraction = accrued - whole
	local preserved = whole + math.clamp(fraction, margin, 1 - margin)
	return now - preserved / newRate
end

--[[
	Seconds until a machine reaches capacity, for the "full in 2m 30s" billboard.
	Returns 0 once it is already full.
]]
function Accrual.secondsUntilFull(
	rate: number,
	capacity: number,
	lastCollectAt: number,
	now: number
): number
	assertRate(rate)
	local remaining = capacity / rate - (now - lastCollectAt)
	return math.max(0, remaining)
end

return Accrual
