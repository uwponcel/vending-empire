--!strict
--[[
	The single source of truth for remote names and payload shapes.

	Lives under `shared/Net` rather than `shared/Lib`, so the purity rule does not apply
	here and this module may touch the Roblox API. Nothing in it is unit tested, because
	there is nothing to test: it is names and instance plumbing.

	THE REMOTES ARE DECLARED IN `default.project.json`, NOT CREATED HERE.

	The first version built them at server boot with `Instance.new`, which cost nothing and
	meant adding a remote was a plain source edit. It also lost one. Measured in a live
	session: the server held all three, and the client had `BuyMachine` and `Notice` but not
	`Sync`, so the shop never received a snapshot. Re-parenting `Sync` on the server made it
	appear on the client immediately, which rules out the instance being wrong and leaves the
	initial replication of it never arriving.

	A client's first snapshot of ReplicatedStorage is taken as it joins, and a server that is
	still populating a folder at that moment is racing it. In a Studio play session the local
	player joins at the same instant the server boots, so the race is close to guaranteed
	there, and in production it is whatever a join during server startup is worth. Either way
	the failure is a client that silently never updates, which is the worst shape a bug can
	take.

	Declaring them in the manifest puts them in the place file, so they are part of the
	initial snapshot and there is no window to race. The cost is real and accepted: Rojo reads
	the manifest only at startup, so adding a remote now means restarting `rojo serve` and
	reconnecting the plugin.

	THREE PAYLOAD RULES, all of them security rather than style:

	1. Client to server carries intent only. `BuyMachine` names a machine type and a slot.
	   It never carries a price, a rate, or a balance.
	2. There is no collect remote at all. Collect runs off `ProximityPrompt.Triggered`,
	   which the engine fires on the server with the triggering player, so there is no
	   payload for an exploiter to forge. The server still validates distance and cooldown,
	   because a client can spam the activation.
	3. Server to client is a whole snapshot, not a delta. Deltas need the client to have
	   applied every previous one, and a single dropped message leaves it permanently wrong
	   with nothing to detect it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"
--- Long enough to cover a slow server boot, short enough to fail rather than hang forever.
local WAIT_TIMEOUT = 30

local Remotes = {}

--[[
	Annotated rather than inferred so a typo in `Remotes.names.snyc` is a type error at the
	call site instead of a nil remote name that only fails at runtime.

	`build` lists these one by one rather than iterating them. Generalized iteration over a
	table type whose fields are named yields `unknown` values under this analyzer, so the
	loop version cannot assign `event.Name`. Listing them is the honest fix: adding a remote
	means touching both places, and they are ten lines apart.
]]
export type Names = {
	--- Client to server: `BuyMachine`. A nil slot means "pick the lowest free one for me".
	buyMachine: string,
	--- Client to server: `UpgradeMachine`. Carries a slot and the level the client saw.
	upgradeMachine: string,
	--- Server to client: `Snapshot`.
	sync: string,
	--- Server to client: `Notice`. A rejection code, for the client to turn into copy.
	notice: string,
}

local names: Names = {
	buyMachine = "BuyMachine",
	upgradeMachine = "UpgradeMachine",
	sync = "Sync",
	notice = "Notice",
}

Remotes.names = names

export type BuyMachine = {
	typeId: string,
	slot: number?,
}

export type UpgradeMachine = {
	slot: number,
	--- Current level from the client's replicated model, used as a stale-request guard.
	level: number,
}

--[[
	What the client is told about one placed machine.

	`rate` and `capacity` are included so the client can render a live pending counter with
	no per-machine traffic: it has the same three numbers the server would use and can
	interpolate between collects. The server's own recomputation on collect is the only
	figure that touches a balance, so an edited client only lies to itself.
]]
export type MachineView = {
	slot: number,
	typeId: string,
	level: number,
	lastCollectAt: number,
	rate: number,
	capacity: number,
}

export type Snapshot = {
	coins: number,
	slotsUnlocked: number,
	--- Physical slots on a plot, so the client can show locked slots as locked.
	slotCount: number,
	--[[
		Carried so the shop can quote the rate a machine would actually produce for this
		player rather than its unmultiplied base. It is 1 for everyone until prestige ships,
		which is exactly why it belongs here now: a shop that quotes base rates looks correct
		right up to the release that makes it wrong.
	]]
	prestigeMultiplier: number,
	machines: { MachineView },
}

export type Notice = {
	code: string,
}

local function expectRemote(folder: Folder, name: string): ()
	local event = folder:FindFirstChild(name)
	if event == nil or not event:IsA("RemoteEvent") then
		error(
			`[Remotes] {FOLDER_NAME}.{name} is missing from default.project.json. `
				.. "Add it there, then restart rojo serve.",
			3
		)
	end
end

--[[
	Checks that every remote this module names actually exists. Server only.

	Deliberately does not create anything. Creating a missing remote here would silently
	reintroduce the join race this design exists to avoid, and it would hide the actual
	mistake, which is that `names` and the manifest disagree. Failing at boot puts the error
	in front of whoever just added a remote, which is the only moment it is cheap to fix.
]]
function Remotes.verify(): Folder
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if folder == nil or not folder:IsA("Folder") then
		error(
			`[Remotes] ReplicatedStorage.{FOLDER_NAME} does not exist. `
				.. "It is declared in default.project.json; if you just added it, restart rojo serve.",
			2
		)
	end

	expectRemote(folder, names.buyMachine)
	expectRemote(folder, names.upgradeMachine)
	expectRemote(folder, names.sync)
	expectRemote(folder, names.notice)

	return folder
end

--[[
	Resolves a remote by name. Yields on the client until the server has built it.

	Errors on the server when the folder is missing, rather than yielding. A server that
	reaches for a remote before `build` has run is a bootstrap ordering mistake, and
	yielding there would deadlock the very code that was supposed to create it.
]]
function Remotes.get(name: string): RemoteEvent
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)

	if folder == nil then
		if RunService:IsServer() then
			error(`[Remotes] {FOLDER_NAME} does not exist; see Remotes.verify()`, 2)
		end
		folder = ReplicatedStorage:WaitForChild(FOLDER_NAME, WAIT_TIMEOUT)
		if folder == nil then
			error(`[Remotes] {FOLDER_NAME} never replicated after {WAIT_TIMEOUT}s`, 2)
		end
	end

	local event = folder:FindFirstChild(name)
	if event == nil and not RunService:IsServer() then
		event = folder:WaitForChild(name, WAIT_TIMEOUT)
	end

	if event == nil or not event:IsA("RemoteEvent") then
		error(`[Remotes] {name} is missing or is not a RemoteEvent`, 2)
	end

	return event
end

return Remotes
