--!strict
--[[
	Server bootstrap.

	Services are required in dependency order and each exposes a single `start` function.
	Nothing runs at require time, so require order stays independent of start order and a
	service can be exercised by calling `start` directly.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net").Remotes)
local Version = require(Shared:WaitForChild("Version"))

local Net = script:WaitForChild("Net")
local Services = script:WaitForChild("Services")
local AnalyticsService = require(Services.AnalyticsService)
local DataService = require(Services.DataService)
local MachineService = require(Services.MachineService)
local PlotService = require(Services.PlotService)
local Router = require(Net.Router)

local function start(): ()
	print(`[VendingEmpire] server booting, version {Version.toString(Version.current)}`)

	--[[
		Remotes are declared in default.project.json, so this only checks they are there.

		Done before any service starts, so a manifest that has drifted from the name table
		fails here with a message naming the missing remote, rather than later inside whichever
		handler happened to reach for it first.
	]]
	Remotes.verify()

	AnalyticsService.start()
	-- DataService first: it connects PlayerAdded, and anything that needs a profile waits
	-- on it rather than loading its own session.
	DataService.start()
	-- PlotService before MachineService: it builds the plot geometry that machine models are
	-- parented to, and claims the plot a rebuild needs to know about.
	PlotService.start()
	MachineService.start()
	-- Router last. Once it connects, clients can send requests, so every service a request
	-- reaches has to already be running.
	Router.start()

	print("[VendingEmpire] server ready")
end

start()
