--!strict
--[[
	Client bootstrap.

	The client renders and sends intent. It never computes balance, never sends an
	amount, and never expects its own arithmetic to be authoritative.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Version = require(Shared:WaitForChild("Version"))

local function start(): ()
	print(`[VendingEmpire] client booting, version {Version.toString(Version.current)}`)

	-- Phase 3 registers CollectController and PlacementController here.
	-- Phase 4 registers HudController.

	print("[VendingEmpire] client ready")
end

start()
