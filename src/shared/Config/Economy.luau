--!strict
--[[
	Global economy tuning. Data only, zero requires, so the test runner can load it
	with no Roblox environment. See CLAUDE.md for the purity rule.

	Everything here is a knob. If a number needs a comment to justify it, the comment
	belongs next to the number.
]]

export type UpgradeParams = {
	--- Rate and capacity are both multiplied by this per level, which is what keeps
	--- fill time constant as a machine levels up.
	rateGrowth: number,
	--- Upgrade cost multiplier per level. Above `rateGrowth` on purpose, so upgrades
	--- have falling returns and buying the next tier stays the better deal while a
	--- player still has empty slots.
	costGrowth: number,
	--- Level 1 -> 2 costs this fraction of the machine's purchase price.
	costFactor: number,
	maxLevel: number,
}

local Economy = {
	--- Enough to buy the tier 1 machine (50) and still have change, so the first
	--- decision a new player makes is a purchase rather than a wait.
	startingCoins = 100,

	--- Slots are the scarce resource. While a player has spare slots, buying the next
	--- machine always beats upgrading. Once slots run out, upgrades become the only
	--- sink, which is what gives the upgrade curve a job.
	baseSlots = 3,
	maxSlots = 12,

	--[[
		rateGrowth and maxLevel are constrained by each other, not chosen freely.

		A machine at max level reaches rateGrowth^(maxLevel-1) times its base rate. That
		total has to stay below the rate jump between tiers, which is about 3.75x at the
		tightest point in Config/Machines. Otherwise a maxed cheap machine out-produces a
		fresh machine from the tier above, replacing it becomes a downgrade in output, and
		the shop reads as broken.

		1.18^7 = 3.19, which clears 3.75 with room to spare. A test asserts this against
		every adjacent tier pair rather than trusting the arithmetic here.

		Eight levels rather than ten is also the better ladder: a player can realistically
		finish it, instead of stalling at level 8 of 10 forever.
	]]
	upgrade = {
		rateGrowth = 1.18,
		costGrowth = 1.4,
		costFactor = 0.75,
		maxLevel = 8,
	} :: UpgradeParams,

	collect = {
		--- Server-side distance check on the collect remote, in studs. Generous enough
		--- to not fight network jitter, tight enough that it cannot be used remotely.
		rangeStuds = 12,
		--- Anti-spam floor between two collects on the same machine. Collecting more
		--- often than this is never profitable anyway, because unpaid fractions carry
		--- forward rather than being lost. See Lib/Accrual.
		cooldownSeconds = 0.35,
	},
}

return Economy
