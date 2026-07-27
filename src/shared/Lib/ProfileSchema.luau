--!strict
--[[
	Saved data shape and its migration chain. Pure, zero requires.

	Lives here rather than inside DataService so the migration machinery is testable with
	no DataStore and no Roblox environment. Migrations are the one part of persistence
	that is genuinely dangerous to get wrong, because a bug rewrites real player data and
	there is no undo.

	The chain exists and is exercised by tests while it is still empty, because the plan
	calls for it now: retrofitting versioning after launch means writing a migration for
	data that was saved without a version, which is far worse than carrying an unused
	hook.

	Shape constraints come from ProfileStore and are not stylistic. See
	src/server/Packages/README.md. In short: no gapped numeric tables, no mixed tables,
	no userdata. That is why `machines` is a dense array whose records each carry their
	own `slot`, rather than a table indexed by slot number, which would be gapped the
	moment a player owned slots 1 and 5 and would fail to save.
]]

export type MachineRecord = {
	--- Which slot on the plot this machine occupies. Carried in the record because the
	--- array is dense and its index is meaningless.
	slot: number,
	--- Key into Config/Machines.byId.
	typeId: string,
	level: number,
	--- os.time() of the last collect. Wall clock, so it survives a rejoin.
	lastCollectAt: number,
}

export type Data = {
	version: number,
	coins: number,
	prestige: {
		count: number,
		multiplier: number,
	},
	machines: { MachineRecord },
	slotsUnlocked: number,
	stats: {
		totalEarned: number,
		playtimeSeconds: number,
	},
	--- Processed developer product receipt ids, so a retried purchase grants once.
	--- String-keyed on purpose: receipt ids are strings, and a numeric key set would be
	--- a gapped array.
	receipts: { [string]: boolean },
}

--- A function that transforms data at version N in place into version N + 1.
export type Migration = (Data) -> ()

local ProfileSchema = {
	VERSION = 1,
}

--[[
	migrations[n] upgrades version n to version n + 1.

	Empty while VERSION is 1. When adding one, never mutate an existing entry: a
	migration that has already run against live data is history, not code.
]]
local migrations: { [number]: Migration } = {}

--[[
	A fresh default profile.

	Returns a new table every call rather than a shared constant, so a caller cannot
	accidentally mutate the default for every future player. Starting values are passed
	in rather than required from Config/Economy, because the purity rule forbids requires
	here and dependency injection is how these modules compose.
]]
function ProfileSchema.template(startingCoins: number, baseSlots: number): Data
	return {
		version = ProfileSchema.VERSION,
		coins = startingCoins,
		prestige = {
			count = 0,
			multiplier = 1,
		},
		machines = {},
		slotsUnlocked = baseSlots,
		stats = {
			totalEarned = 0,
			playtimeSeconds = 0,
		},
		receipts = {},
	}
end

--[[
	True when this data was written by a build newer than this one.

	Callers must check this before migrating or writing. A server running an older build
	that happily saved would silently downgrade a player who had already played on a
	newer one, destroying whatever the newer version added. Opening read-only and
	refusing to write is the only safe response.
]]
function ProfileSchema.isNewerThanSupported(data: Data, targetVersion: number?): boolean
	return data.version > (targetVersion or ProfileSchema.VERSION)
end

--[[
	Upgrades `data` in place to `targetVersion`, returning how many migrations ran.

	`chain` and `targetVersion` are injectable so tests can drive the machinery without
	waiting for the game to actually need a version 2.

	Fails loudly in both directions rather than guessing. Data from the future is an
	error because the caller should have checked `isNewerThanSupported`. A missing step in
	the chain is an error because skipping it would leave data in a shape no code expects.
]]
function ProfileSchema.migrate(
	data: Data,
	chain: { [number]: Migration }?,
	targetVersion: number?
): number
	local steps = chain or migrations
	local target = targetVersion or ProfileSchema.VERSION

	if type(data.version) ~= "number" then
		error(`data has no numeric version, got {typeof(data.version)}`, 2)
	end

	if data.version > target then
		error(
			`data version {data.version} is newer than supported {target}; `
				.. `callers must check isNewerThanSupported first`,
			2
		)
	end

	local applied = 0
	while data.version < target do
		local step = steps[data.version]
		if step == nil then
			error(`no migration from version {data.version} to {data.version + 1}`, 2)
		end

		step(data)
		data.version += 1
		applied += 1
	end

	return applied
end

return ProfileSchema
