--!strict
--[[
	Queries and edits over a player's placed machines. Pure, zero requires.

	This is where every rule about slots lives, so the server handler stays a thin shell
	that looks up config, calls in here, and applies the answer. That split is the only
	reason placement rules are testable at all: the rules have no Roblox dependency and
	the handler is almost entirely Roblox.

	The types below restate shapes owned by Lib/ProfileSchema and Config/Machines. They
	are restated rather than imported because the purity rule forbids requires here, and
	Luau is structurally typed so the real tables satisfy them with no nominal link. Same
	trade-off Lib/UpgradeCurve makes, for the same reason.

	DENSE ARRAY, ALWAYS. `machines` is an array whose records each carry their own `slot`,
	never a table indexed by slot. ProfileStore silently truncates a gapped numeric table
	at the first hole and reports nothing, so a player owning slots 1 and 5 would lose the
	slot 5 machine on every save. `insert` appends and `removeSlot` uses table.remove for
	exactly this reason. See src/server/Packages/README.md.
]]

export type MachineRecord = {
	slot: number,
	typeId: string,
	level: number,
	lastCollectAt: number,
}

--- The slice of saved data these rules read. Lib/ProfileSchema.Data satisfies it.
export type State = {
	coins: number,
	machines: { MachineRecord },
	slotsUnlocked: number,
}

--- The slice of a machine config these rules read. Config/Machines.Machine satisfies it.
export type Priced = {
	id: string,
	cost: number,
}

local PlotState = {}

--[[
	Rejection codes. Stable identifiers rather than sentences, so the wording lives on the
	client and can change without a server deploy.
]]
PlotState.Rejection = {
	slotOutOfRange = "slot_out_of_range",
	slotLocked = "slot_locked",
	slotTaken = "slot_taken",
	machineNotFound = "machine_not_found",
	levelMismatch = "level_mismatch",
	maxLevel = "max_level",
	insufficientFunds = "insufficient_funds",
}

--- Position of the record occupying a slot, for callers that need to remove or replace it.
function PlotState.indexOfSlot(machines: { MachineRecord }, slot: number): number?
	for index, record in machines do
		if record.slot == slot then
			return index
		end
	end
	return nil
end

function PlotState.atSlot(machines: { MachineRecord }, slot: number): MachineRecord?
	local index = PlotState.indexOfSlot(machines, slot)
	if index == nil then
		return nil
	end
	return machines[index]
end

function PlotState.isSlotFree(machines: { MachineRecord }, slot: number): boolean
	return PlotState.indexOfSlot(machines, slot) == nil
end

--[[
	Lowest unlocked slot with nothing on it, or nil when the plot is full.

	Clamped by `slotCount` as well as by `slotsUnlocked`, so a config change that unlocks
	more slots than the plot physically has cannot hand out a slot with no anchor in the
	world.
]]
function PlotState.firstFreeSlot(state: State, slotCount: number): number?
	local limit = math.min(state.slotsUnlocked, slotCount)
	for slot = 1, limit do
		if PlotState.isSlotFree(state.machines, slot) then
			return slot
		end
	end
	return nil
end

--[[
	Why this purchase is not allowed, or nil when it is.

	Named for the failure rather than the success on purpose. A `validate` that returns nil
	for valid inverts the truthiness a reader expects, and `if purchaseRejection(...) then`
	reads correctly with no comment.

	Order is most structural failure first. A slot that does not exist is reported as such
	even when the player also cannot afford the machine, because that combination means the
	client sent something impossible and the funds message would send the player chasing the
	wrong problem.
]]
function PlotState.purchaseRejection(
	state: State,
	machine: Priced,
	slot: number,
	slotCount: number
): string?
	-- Catches fractions and NaN as well as out-of-bounds: NaN % 1 is NaN, which fails
	-- the equality. Non-number input is the caller's job to reject at the remote boundary.
	if slot % 1 ~= 0 or slot < 1 or slot > slotCount then
		return PlotState.Rejection.slotOutOfRange
	end
	if slot > state.slotsUnlocked then
		return PlotState.Rejection.slotLocked
	end
	if not PlotState.isSlotFree(state.machines, slot) then
		return PlotState.Rejection.slotTaken
	end
	if state.coins < machine.cost then
		return PlotState.Rejection.insufficientFunds
	end
	return nil
end

--[[
	Why an upgrade is not allowed, or nil when it is.

	`expectedLevel` is the level the client saw when it asked. Matching it prevents two
	queued clicks from buying two upgrades against one displayed price: the first succeeds
	and advances the record, then the second is rejected as stale.

	The caller derives `upgradeCost` and `maxLevel` from UpgradeCurve. Passing those values
	in keeps this module pure while leaving all state-dependent rules in one testable place.
]]
function PlotState.upgradeRejection(
	state: State,
	slot: number,
	expectedLevel: number,
	slotCount: number,
	upgradeCost: number,
	maxLevel: number
): string?
	if slot % 1 ~= 0 or slot < 1 or slot > slotCount then
		return PlotState.Rejection.slotOutOfRange
	end

	local record = PlotState.atSlot(state.machines, slot)
	if record == nil then
		return PlotState.Rejection.machineNotFound
	end

	if expectedLevel % 1 ~= 0 or expectedLevel ~= record.level then
		return PlotState.Rejection.levelMismatch
	end
	if record.level >= maxLevel then
		return PlotState.Rejection.maxLevel
	end
	if state.coins < upgradeCost then
		return PlotState.Rejection.insufficientFunds
	end
	return nil
end

--[[
	Appends a machine record.

	Throws when the slot is already taken. That is an invariant violation rather than a
	player mistake: the caller is required to have run `purchaseRejection` first, and two
	records claiming one slot would give the plot a machine no code can address, since
	every lookup here returns the first match.
]]
function PlotState.insert(machines: { MachineRecord }, record: MachineRecord): ()
	if not PlotState.isSlotFree(machines, record.slot) then
		error(`slot {record.slot} is already occupied`, 2)
	end
	table.insert(machines, record)
end

--- Removes the machine on a slot and returns it, or nil if there was none.
function PlotState.removeSlot(machines: { MachineRecord }, slot: number): MachineRecord?
	local index = PlotState.indexOfSlot(machines, slot)
	if index == nil then
		return nil
	end
	-- table.remove rather than assigning nil, so the array stays dense and saveable.
	return table.remove(machines, index)
end

return PlotState
