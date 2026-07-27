--!strict
--[[
	Client bootstrap.

	The client renders and sends intent. It never computes balance, never sends an
	amount, and never expects its own arithmetic to be authoritative.

	Collect and upgrade still activate engine ProximityPrompts, and the server handles them
	through their authoritative paths. MachinePromptController only replaces Roblox's default
	prompt cards with one compact visual surface; it never computes or sends a payout.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Version = require(Shared:WaitForChild("Version"))

local Controllers = script:WaitForChild("Controllers")
local HudController = require(Controllers.HudController)
local MachineDisplayController = require(Controllers.MachineDisplayController)
local MachinePromptController = require(Controllers.MachinePromptController)
local ShopController = require(Controllers.ShopController)
local UpgradeController = require(Controllers.UpgradeController)

local function start(): ()
	print(`[VendingEmpire] client booting, version {Version.toString(Version.current)}`)

	-- ShopController first: it builds the ScreenGui and connects the snapshot listener, so a
	-- snapshot arriving during startup has somewhere to land.
	ShopController.start()
	HudController.start()
	MachineDisplayController.start()
	UpgradeController.start()
	MachinePromptController.start()

	print("[VendingEmpire] client ready")
end

start()
