--!strict
--[[
	The only place a coin balance changes.

	Every credit and debit goes through here and every one of them logs with a source tag.
	That single funnel is what makes an economy bug findable: when balances drift, the
	question is always "which source", and there is exactly one file to read to know that
	the list of sources is complete.

	Amounts are always server-computed, never taken from a client. A non-integer, negative,
	or non-finite amount is therefore a programming error rather than player input, and this
	module throws on one instead of returning a rejection. A player asking for something they
	cannot afford is the opposite: normal, expected, and returned as a reason.
]]

local DataService = require(script.Parent.DataService)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Result = require(Shared.Lib.Result)

--[[
	Past 2^53 a float64 can no longer represent every integer, so coins would start
	silently rounding. Warned rather than clamped: clamping quietly changes the economy,
	while a warning gives a real signal before any player is affected. If this ever fires,
	the fix is a big-number representation, which the plan defers until prestige tuning.
]]
local MAX_EXACT_COINS = 2 ^ 53

local EconomyService = {}

EconomyService.Rejection = {
	noProfile = "no_profile",
	insufficientFunds = "insufficient_funds",
}

local function assertAmount(amount: number, action: string): ()
	if amount ~= amount or amount == math.huge then
		error(`[EconomyService] {action} amount is not a finite number: {amount}`, 3)
	end
	if amount % 1 ~= 0 then
		error(`[EconomyService] {action} amount must be a whole number, got {amount}`, 3)
	end
	if amount <= 0 then
		error(`[EconomyService] {action} amount must be positive, got {amount}`, 3)
	end
end

--- Current balance, or nil when the profile is not loaded.
function EconomyService.balance(player: Player): number?
	local profile = DataService.get(player)
	if profile == nil then
		return nil
	end
	return profile.Data.coins
end

--[[
	Adds coins and records them against lifetime earnings. Returns the new balance.

	`source` is a short tag such as "collect" or "prestige_grant". It ends up in the log and
	in Phase 4's analytics funnel, so it should identify the code path rather than the
	player.
]]
function EconomyService.credit(
	player: Player,
	amount: number,
	source: string
): Result.Result<number>
	assertAmount(amount, "credit")

	local profile = DataService.get(player)
	if profile == nil then
		return Result.err(EconomyService.Rejection.noProfile)
	end

	local data = profile.Data
	data.coins += amount
	-- Lifetime earnings only ever grow, so it is credited here and never touched by debit.
	data.stats.totalEarned += amount

	if data.coins > MAX_EXACT_COINS then
		warn(
			`[EconomyService] {player.Name} passed 2^53 coins ({data.coins}); `
				.. "integer precision is no longer exact"
		)
	end

	print(`[EconomyService] {player.Name} +{amount} ({source}) -> {data.coins}`)
	return Result.ok(data.coins)
end

--[[
	Removes coins if the player has them. Returns the new balance.

	Reads and writes in one synchronous block with no yield between the check and the
	subtraction, which is what makes it safe against two purchases arriving in the same
	frame. Nothing in here may ever be made to yield.
]]
function EconomyService.debit(player: Player, amount: number, source: string): Result.Result<number>
	assertAmount(amount, "debit")

	local profile = DataService.get(player)
	if profile == nil then
		return Result.err(EconomyService.Rejection.noProfile)
	end

	local data = profile.Data
	if data.coins < amount then
		return Result.err(EconomyService.Rejection.insufficientFunds)
	end

	data.coins -= amount

	print(`[EconomyService] {player.Name} -{amount} ({source}) -> {data.coins}`)
	return Result.ok(data.coins)
end

return EconomyService
