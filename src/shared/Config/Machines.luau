--!strict
--[[
	The machine tuning table. Data only, zero requires.

	Two authored knobs per machine, and one derived value:

	  baseRate     coins per second at level 1
	  fillSeconds  how long it takes to reach capacity, at any level
	  capacity     DERIVED as baseRate * fillSeconds, never authored

	Capacity is derived rather than authored so that fill time stays exactly
	`fillSeconds` at every upgrade level and every prestige multiplier. Both rate and
	capacity scale by the same growth factor, so the ratio between them cannot drift.
	That means the collect cadence a player learns at tier 1 is the cadence they keep,
	and no combination of level and multiplier can silently turn a machine into one
	that needs 20 trips a minute. Lib/UpgradeCurve enforces the scaling; a test
	asserts the invariance.

	Pacing intent, verified by tests rather than trusted:

	  cost   grows about 5x per tier
	  rate   grows about 4x per tier
	  so payback time (cost / rate) grows slowly, from 50s at tier 1 to about 420s at
	  tier 9. Progression decelerates, which is what eventually makes prestige the
	  attractive move instead of grinding one more tier.

	fillSeconds climbs with tier on purpose. Tier 1 fills in 20s so a new player sees
	the whole loop inside their first minute. Late tiers fill in several minutes so the
	endgame is less clicky, which is also what makes the auto-collect pass worth buying
	rather than a tax on something that was never annoying.
]]

export type Category = "drinks" | "snacks" | "electronics"

export type Machine = {
	id: string,
	displayName: string,
	category: Category,
	--- Unlock order and the sort order in the shop. Contiguous from 1.
	tier: number,
	--- Purchase price at level 1.
	cost: number,
	--- Coins per second at level 1.
	baseRate: number,
	--- Seconds from empty to full, invariant across level and prestige.
	fillSeconds: number,
}

--[[
	Ordered by tier. Kept as an array rather than a dictionary so the shop can render
	it directly and so the tier sequence is visible in the source.
]]
local list: { Machine } = {
	{
		id = "drink_water",
		displayName = "Water Cooler",
		category = "drinks",
		tier = 1,
		cost = 50,
		baseRate = 1,
		fillSeconds = 20,
	},
	{
		id = "drink_soda",
		displayName = "Soda Machine",
		category = "drinks",
		tier = 2,
		cost = 250,
		baseRate = 4,
		fillSeconds = 40,
	},
	{
		id = "drink_energy",
		displayName = "Energy Drink Fridge",
		category = "drinks",
		tier = 3,
		cost = 1200,
		baseRate = 15,
		fillSeconds = 60,
	},
	{
		id = "snack_chips",
		displayName = "Chip Dispenser",
		category = "snacks",
		tier = 4,
		cost = 6000,
		baseRate = 60,
		fillSeconds = 90,
	},
	{
		id = "snack_candy",
		displayName = "Candy Tower",
		category = "snacks",
		tier = 5,
		cost = 30000,
		baseRate = 240,
		fillSeconds = 120,
	},
	{
		id = "snack_sandwich",
		displayName = "Fresh Sandwich Unit",
		category = "snacks",
		tier = 6,
		cost = 150000,
		baseRate = 900,
		fillSeconds = 150,
	},
	{
		id = "elec_phone",
		displayName = "Phone Accessory Kiosk",
		category = "electronics",
		tier = 7,
		cost = 800000,
		baseRate = 3600,
		fillSeconds = 200,
	},
	{
		id = "elec_console",
		displayName = "Handheld Console Vendor",
		category = "electronics",
		tier = 8,
		cost = 4500000,
		baseRate = 15000,
		fillSeconds = 260,
	},
	{
		id = "elec_drone",
		displayName = "Drone Vending Bay",
		category = "electronics",
		tier = 9,
		cost = 25000000,
		baseRate = 60000,
		fillSeconds = 320,
	},
}

--- Index by id, built once at require time. Lookup by id is the hot path on every
--- collect, so it must not be a linear scan.
local byId: { [string]: Machine } = {}
for _, machine in list do
	byId[machine.id] = machine
end

local Machines = {
	list = list,
	byId = byId,
}

return Machines
