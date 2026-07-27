--!strict
--[[
	Server bootstrap.

	Services are required in dependency order and each exposes a single `start`
	function. Nothing runs at require time, so require order stays independent of
	start order and a service can be unit-tested by calling `start` directly.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Version = require(Shared:WaitForChild("Version"))

local function start(): ()
	print(`[VendingEmpire] server booting, version {Version.toString(Version.current)}`)

	-- Phase 2 registers DataService and PlotService here.
	-- Phase 3 registers EconomyService, MachineService, and CollectService.

	print("[VendingEmpire] server ready")
end

start()
