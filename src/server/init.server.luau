--!strict
--[[
	Server bootstrap.

	Services are required in dependency order and each exposes a single `start` function.
	Nothing runs at require time, so require order stays independent of start order and a
	service can be exercised by calling `start` directly.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Version = require(Shared:WaitForChild("Version"))

local Services = script:WaitForChild("Services")
local DataService = require(Services.DataService)
local PlotService = require(Services.PlotService)

local function start(): ()
	print(`[VendingEmpire] server booting, version {Version.toString(Version.current)}`)

	-- DataService first: it connects PlayerAdded, and anything that needs a profile waits
	-- on it rather than loading its own session.
	DataService.start()
	PlotService.start()

	-- Phase 3 registers EconomyService, MachineService, and CollectService.

	print("[VendingEmpire] server ready")
end

start()
