--!strict
--[[
	Upgrade level math. Pure, zero requires.

	The types below are structural duplicates of shapes owned by Config/Economy and
	Config/Machines. They are restated rather than imported because the purity rule
	forbids requires here, and Luau is structurally typed so the real config tables
	satisfy them without a nominal link. Duplicating four field names is the price of
	keeping this module loadable by the test runner.
]]

export type Params = {
	rateGrowth: number,
	costGrowth: number,
	costFactor: number,
	maxLevel: number,
}

--- The subset of a Machine this module needs. Config/Machines.Machine satisfies it.
export type Stats = {
	baseRate: number,
	fillSeconds: number,
}

export type Effective = {
	--- Coins per second.
	rate: number,
	--- Maximum coins the machine can hold before overflow is wasted.
	capacity: number,
}

local UpgradeCurve = {}

local function assertLevel(level: number, params: Params): ()
	if level < 1 or level > params.maxLevel then
		error(`level {level} is outside 1..{params.maxLevel}`, 3)
	end
	if level % 1 ~= 0 then
		error(`level {level} must be an integer`, 3)
	end
end

--[[
	Growth factor applied at a given level. Level 1 is exactly 1, so a level 1 machine
	always performs exactly at its authored baseRate with no rounding drift.
]]
function UpgradeCurve.growthAt(level: number, params: Params): number
	assertLevel(level, params)
	return params.rateGrowth ^ (level - 1)
end

--[[
	Effective rate and capacity for a machine at a level, with a prestige multiplier.

	Rate and capacity are multiplied by the same factor, which is what holds fill time
	at exactly `fillSeconds` regardless of level or multiplier. Config/Machines explains
	why that invariance matters; a test asserts it holds.
]]
function UpgradeCurve.effective(
	stats: Stats,
	level: number,
	params: Params,
	multiplier: number?
): Effective
	local scale = UpgradeCurve.growthAt(level, params) * (multiplier or 1)
	local rate = stats.baseRate * scale

	return {
		rate = rate,
		capacity = rate * stats.fillSeconds,
	}
end

--[[
	Cost to go from `level` to `level + 1`. Errors at max level rather than returning a
	sentinel, so a caller that forgets to check `canUpgrade` fails loudly in tests
	instead of charging a player for nothing.
]]
function UpgradeCurve.upgradeCost(baseCost: number, level: number, params: Params): number
	assertLevel(level, params)
	if level >= params.maxLevel then
		error(`level {level} is already at max {params.maxLevel}`, 2)
	end

	return math.floor(baseCost * params.costFactor * params.costGrowth ^ (level - 1))
end

function UpgradeCurve.canUpgrade(level: number, params: Params): boolean
	return level >= 1 and level < params.maxLevel
end

--[[
	Total cost of every upgrade from `fromLevel` to `toLevel`. Used by the shop to show
	the full price of maxing a machine, and by tuning tests to compare the value of
	upgrading against the value of buying the next tier.
]]
function UpgradeCurve.totalUpgradeCost(
	baseCost: number,
	fromLevel: number,
	toLevel: number,
	params: Params
): number
	assertLevel(fromLevel, params)
	assertLevel(toLevel, params)
	if toLevel < fromLevel then
		error(`toLevel {toLevel} is below fromLevel {fromLevel}`, 2)
	end

	local total = 0
	for level = fromLevel, toLevel - 1 do
		total += UpgradeCurve.upgradeCost(baseCost, level, params)
	end
	return total
end

return UpgradeCurve
