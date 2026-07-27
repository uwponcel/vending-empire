--!strict
--[[
	Owns player persistence. The only place ProfileStore is touched.

	Other services ask for a profile through `get` or `waitFor` and never load one
	themselves, so there is exactly one session per player and one place where the
	version guard runs.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProfileStore = require(script.Parent.Parent.Packages.ProfileStore)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local ProfileSchema = require(Shared.Lib.ProfileSchema)

--[[
	Renaming this orphans every existing profile, so it does not carry a version. Schema
	changes are handled by ProfileSchema.migrate instead.
]]
local STORE_NAME = "PlayerData"

--[[
	Set true to run against ProfileStore's in-memory mock instead of the real DataStore.

	Left false even in Studio on purpose. A mock only survives inside one Studio session,
	so stopping and restarting play would wipe the data, and the one thing most worth
	verifying by hand is that a profile survives exactly that. The cost is that testing
	in Studio writes a real profile for the tester's own user id.
]]
local USE_MOCK = false

export type Profile = typeof(ProfileStore.New(STORE_NAME, {}):StartSessionAsync(""))

local DataService = {}

local store: any = nil
local profiles: { [Player]: any } = {}
--- os.time() when each session began, so playtime can be accumulated on the way out.
local sessionStartedAt: { [Player]: number } = {}

--- Returns the loaded profile, or nil if it is still loading or the player has left.
function DataService.get(player: Player): any?
	return profiles[player]
end

--[[
	Yields until the player's profile is loaded. Returns nil if they leave first or the
	timeout elapses, so every caller has to handle a missing profile rather than assuming
	one always arrives.
]]
function DataService.waitFor(player: Player, timeoutSeconds: number?): any?
	-- os.clock is correct here. The rule against it applies to timestamps that get
	-- persisted, where surviving a rejoin matters. This one never leaves the frame.
	local deadline = os.clock() + (timeoutSeconds or 30)

	while profiles[player] == nil do
		if player.Parent ~= Players then
			return nil
		end
		if os.clock() >= deadline then
			warn(`[DataService] timed out waiting for {player.Name}'s profile`)
			return nil
		end
		task.wait(0.1)
	end

	return profiles[player]
end

local function onPlayerAdded(player: Player): ()
	local profile = store:StartSessionAsync(`Player_{player.UserId}`, {
		-- Stop retrying a session conflict if the player already gave up and left.
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if profile == nil then
		if player.Parent == Players then
			player:Kick("Could not load your data. Please rejoin.")
		end
		return
	end

	-- The player can leave during the session start, which yields.
	if player.Parent ~= Players then
		profile:EndSession()
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()

	--[[
		Refuse data written by a newer build rather than migrating or saving over it.

		Nothing is mutated on this path, so the save that EndSession performs writes back
		byte-identical data. That is the closest thing to a read-only open that
		ProfileStore offers, and it is why the guard has to run before anything else
		touches Profile.Data.
	]]
	if ProfileSchema.isNewerThanSupported(profile.Data) then
		warn(
			`[DataService] {player.Name} has data version {profile.Data.version}, `
				.. `newer than supported {ProfileSchema.VERSION}. Refusing to write.`
		)
		profile:EndSession()
		player:Kick("Your save is from a newer version of the game. Please rejoin later.")
		return
	end

	local applied = ProfileSchema.migrate(profile.Data)
	if applied > 0 then
		print(
			`[DataService] migrated {player.Name} through {applied} version(s) `
				.. `to {profile.Data.version}`
		)
	end

	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		sessionStartedAt[player] = nil
		if player.Parent == Players then
			-- Reached when another server steals the session, so this server's copy is
			-- no longer authoritative and must stop being used.
			player:Kick("Your session was opened elsewhere. Please rejoin.")
		end
	end)

	sessionStartedAt[player] = os.time()
	profiles[player] = profile

	print(
		`[DataService] loaded {player.Name}, coins={profile.Data.coins}, `
			.. `machines={#profile.Data.machines}, playtime={profile.Data.stats.playtimeSeconds}s`
	)
end

local function onPlayerRemoving(player: Player): ()
	local profile = profiles[player]
	if profile == nil then
		return
	end

	-- Wall clock on both ends, so a session that spans a server restart still measures
	-- real elapsed time rather than resetting.
	local startedAt = sessionStartedAt[player]
	if startedAt ~= nil then
		profile.Data.stats.playtimeSeconds += math.max(0, os.time() - startedAt)
	end

	profiles[player] = nil
	sessionStartedAt[player] = nil
	profile:EndSession()
end

function DataService.start(): ()
	local template = ProfileSchema.template(Economy.startingCoins, Economy.baseSlots)
	store = ProfileStore.New(STORE_NAME, template)

	if USE_MOCK then
		warn("[DataService] using the ProfileStore mock, nothing will persist")
		store = store.Mock
	end

	-- Surfaces a misconfigured place immediately. "NoAccess" means Studio API access is
	-- off, which otherwise looks like saves silently doing nothing.
	task.spawn(function()
		while ProfileStore.DataStoreState == "NotReady" do
			task.wait(0.25)
		end
		print(`[DataService] DataStore state: {ProfileStore.DataStoreState}`)
		if ProfileStore.DataStoreState == "NoAccess" then
			warn(
				"[DataService] no DataStore access. In Studio, enable "
					.. "Game Settings -> Security -> Enable Studio Access to API Services."
			)
		end
	end)

	ProfileStore.OnError:Connect(function(message, storeName, key)
		warn(`[DataService] ProfileStore error in {storeName}/{key}: {message}`)
	end)

	ProfileStore.OnOverwrite:Connect(function(storeName, key)
		warn(`[DataService] {storeName}/{key} held data that was not a ProfileStore profile`)
	end)

	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
	end)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Players can already be in the server when a script starts, especially in Studio.
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return DataService
