--!strict
--[[
	Client bootstrap.

	The client renders and sends intent. It never computes balance, never sends an
	amount, and never expects its own arithmetic to be authoritative.

	There is no collect controller. Collect is a ProximityPrompt, which the engine renders and
	activates on its own, and the server handles `PromptTriggered` directly. The client's only
	part in the most repeated action in the game is drawing the prompt, which means there is no
	client code on that path to get wrong or to exploit.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Version = require(Shared:WaitForChild("Version"))

local Controllers = script:WaitForChild("Controllers")
local MachineDisplayController = require(Controllers.MachineDisplayController)
local ShopController = require(Controllers.ShopController)

local function start(): ()
	print(`[VendingEmpire] client booting, version {Version.toString(Version.current)}`)

	-- ShopController first: it builds the ScreenGui and connects the snapshot listener, so a
	-- snapshot arriving during startup has somewhere to land.
	ShopController.start()
	MachineDisplayController.start()

	-- Phase 4 registers the real coin HUD, the floating +N, and the collect sound.

	print("[VendingEmpire] client ready")
end

start()
