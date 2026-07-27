--!strict
--[[
	Connects the local player's per-machine upgrade prompts.

	The prompt sends a slot and the level currently replicated on the model. It never sends
	a price, target level, rate, or balance. The server derives all of those and rejects a
	stale level, so a queued double activation cannot buy two upgrades at one displayed cost.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local UpgradeCurve = require(Shared.Lib.UpgradeCurve)
local Remotes = require(Shared.Net.Remotes)

local UpgradeController = {}

local function wirePrompt(prompt: ProximityPrompt): ()
	if prompt.Name ~= "UpgradePrompt" then
		return
	end

	local model = prompt:FindFirstAncestorOfClass("Model")
	if model == nil then
		return
	end

	local triggerConnected = false

	local function sendUpgrade(): ()
		local slot = model:GetAttribute("Slot")
		local level = model:GetAttribute("Level")
		if type(slot) ~= "number" or type(level) ~= "number" then
			return
		end

		Remotes.get(Remotes.names.upgradeMachine):FireServer({
			slot = slot,
			level = level,
		} :: Remotes.UpgradeMachine)
	end

	local function refreshOwnership(): ()
		local ownerUserId = model:GetAttribute("OwnerUserId")
		local level = model:GetAttribute("Level")
		local owned = ownerUserId == Players.LocalPlayer.UserId

		-- Attributes replicate independently. Keep the prompt hidden until both ownership and
		-- level are known, then derive the local affordance from the same shared curve.
		prompt.Enabled = owned
			and type(level) == "number"
			and UpgradeCurve.canUpgrade(level, Economy.upgrade)

		if owned and not triggerConnected then
			triggerConnected = true
			prompt.Triggered:Connect(sendUpgrade)
		end
	end

	model:GetAttributeChangedSignal("OwnerUserId"):Connect(refreshOwnership)
	model:GetAttributeChangedSignal("Level"):Connect(refreshOwnership)
	prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
		if model:GetAttribute("OwnerUserId") ~= Players.LocalPlayer.UserId and prompt.Enabled then
			prompt.Enabled = false
		end
	end)

	refreshOwnership()
end

function UpgradeController.start(): ()
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("ProximityPrompt") then
			wirePrompt(descendant)
		end
	end

	Workspace.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("ProximityPrompt") then
			wirePrompt(descendant)
		end
	end)
end

return UpgradeController
