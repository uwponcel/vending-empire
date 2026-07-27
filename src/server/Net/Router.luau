--!strict
--[[
	The boundary where client input stops being client input.

	Every remote handler in the game is registered here, and each one does the same three
	things in the same order before any service sees the request: rate limit the player,
	check the payload is actually the shape it claims to be, then hand a typed value to a
	service.

	The type annotations in shared/Net/Remotes describe the intended payload. They are
	documentation, not enforcement: a remote argument arrives as whatever the client sent,
	including a table with the right field names and wrong types, or a userdata, or nothing.
	Every field is therefore re-checked at runtime here, and the `any` in these signatures is
	deliberate and honest rather than a gap.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MachineService = require(script.Parent.Parent.Services.MachineService)
local Sync = require(script.Parent.Sync)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Net.Remotes)

--[[
	A player may send this many requests per window before the rest are dropped.

	Sized well above anything a human hitting a shop button can produce and well below what
	an automated loop would, so it never inconveniences a real player and never lets one
	client make the server do unbounded work.
]]
local RATE_LIMIT_REQUESTS = 15
local RATE_LIMIT_WINDOW_SECONDS = 5

--- Rejects absurd strings before they reach a table lookup or a log line.
local MAX_STRING_LENGTH = 64

local Router = {}

type Bucket = {
	count: number,
	windowStart: number,
	--- Whether the player is currently over the limit, so the log records the transition
	--- rather than one line per dropped request.
	limited: boolean,
}

local buckets: { [Player]: Bucket } = {}

--[[
	Fixed window rather than a token bucket. A fixed window lets through up to twice the
	nominal rate across a window boundary, which for a shop button is irrelevant, and it costs
	two numbers and no arithmetic per request instead of a refill calculation.
]]
local function allow(player: Player, remoteName: string): boolean
	-- os.clock, not os.time: this is a duration within a session and never persisted, and
	-- os.time has one second resolution which is far too coarse for a five second window.
	local now = os.clock()
	local bucket = buckets[player]

	if bucket == nil or now - bucket.windowStart >= RATE_LIMIT_WINDOW_SECONDS then
		buckets[player] = { count = 1, windowStart = now, limited = false }
		return true
	end

	bucket.count += 1
	if bucket.count <= RATE_LIMIT_REQUESTS then
		return true
	end

	if not bucket.limited then
		bucket.limited = true
		warn(
			`[Router] rate limiting {player.Name}: more than {RATE_LIMIT_REQUESTS} `
				.. `requests in {RATE_LIMIT_WINDOW_SECONDS}s, most recently {remoteName}`
		)
	end
	return false
end

--[[
	Narrows an arbitrary remote argument to a BuyMachine payload, or nil.

	Returns nil rather than erroring. An error here would be raised inside the remote's
	handler thread on behalf of a client that can send anything it likes, which turns a
	malformed packet into a stack trace in the server log for every packet.
]]
local function readBuyMachine(payload: any): Remotes.BuyMachine?
	if type(payload) ~= "table" then
		return nil
	end

	local typeId = payload.typeId
	if type(typeId) ~= "string" or #typeId == 0 or #typeId > MAX_STRING_LENGTH then
		return nil
	end

	local slot = payload.slot
	if slot ~= nil and type(slot) ~= "number" then
		return nil
	end

	-- Range and integrality of `slot` are Lib/PlotState's job, and it is tested on exactly
	-- these cases. Only the type is settled here.
	return { typeId = typeId, slot = slot }
end

local function onBuyMachine(player: Player, payload: any): ()
	if not allow(player, Remotes.names.buyMachine) then
		return
	end

	local request = readBuyMachine(payload)
	if request == nil then
		warn(`[Router] discarded a malformed {Remotes.names.buyMachine} from {player.Name}`)
		return
	end

	local outcome = MachineService.buy(player, request.typeId, request.slot)
	if outcome.tag == "err" then
		--[[
			The reason goes back to the client so the shop can say why. Safe to disclose: every
			code describes state the player already owns, and a client that lies to itself
			about them still cannot buy anything, because this answer is the only one the
			server acts on.
		]]
		Sync.notice(player, outcome.reason)
	end
end

--- Requires `Remotes.build()` to have run, which the bootstrap does before any service starts.
function Router.start(): ()
	Remotes.get(Remotes.names.buyMachine).OnServerEvent:Connect(onBuyMachine)

	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)
end

return Router
