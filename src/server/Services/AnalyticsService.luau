--!strict
--[[
	The first-loop analytics funnel.

	A funnel begins on the first machine purchase in a server session. Existing players who
	only collect are not silently counted as having bought, and an upgrade made before the
	first collect is remembered until step two lands rather than asking Roblox to auto-fill a
	skipped step.
]]

local RobloxAnalytics = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local FUNNEL_NAME = "CoreLoop"

local AnalyticsService = {}

type FunnelState = {
	sessionId: string,
	step: number,
	upgraded: boolean,
}

local states: { [Player]: FunnelState? } = {}

local function logStep(player: Player, state: FunnelState, step: number, name: string): ()
	state.step = step

	-- Funnel events are only accepted from published servers. Keeping the state progression
	-- in Studio still exercises the call order without filling the output with API warnings.
	if RunService:IsStudio() then
		return
	end

	task.defer(function()
		RobloxAnalytics:LogFunnelStepEvent(player, FUNNEL_NAME, state.sessionId, step, name)
	end)
end

function AnalyticsService.machineBought(player: Player): ()
	if states[player] ~= nil then
		return
	end

	local state: FunnelState = {
		sessionId = HttpService:GenerateGUID(false),
		step = 0,
		upgraded = false,
	}
	states[player] = state
	logStep(player, state, 1, "First machine bought")
end

function AnalyticsService.collected(player: Player): ()
	local state = states[player]
	if state == nil or state.step ~= 1 then
		return
	end

	logStep(player, state, 2, "First collect")
	if state.upgraded then
		logStep(player, state, 3, "First upgrade")
	end
end

function AnalyticsService.upgraded(player: Player): ()
	local state = states[player]
	if state == nil or state.step >= 3 then
		return
	end

	if state.step < 2 then
		state.upgraded = true
		return
	end

	logStep(player, state, 3, "First upgrade")
end

function AnalyticsService.start(): ()
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
end

return AnalyticsService
