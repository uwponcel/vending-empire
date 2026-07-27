--!strict
--[[
	Plot ownership for the length of a session.

	A plot index is deliberately not persisted. Machines are saved, the plot they sat on
	is not, so a returning player gets whatever plot is free and their machines are rebuilt
	onto it. Persisting the index would mean a player could be locked out of their own save
	because a stranger is standing on plot 7.

	Ownership lives here rather than on the Instance, because an attribute on a Model is
	replicated to clients and a client must never be the source of truth for who owns what.
	The attribute is written anyway, but only so the client can render labels.
]]

local Players = game:GetService("Players")

local PlotGeometry = require(script.Parent.PlotGeometry)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Plots = require(Shared.Config.Plots)
local PlotLayout = require(Shared.Lib.PlotLayout)

local PlotService = {}

-- Optional value types, because absence is the normal case for both of these and the
-- lookups are compared against nil. Declaring them non-optional makes strict mode treat
-- `ownerByPlot[i] == nil` as comparing two incompatible types.
local ownerByPlot: { [number]: Player? } = {}
local plotByOwner: { [Player]: number? } = {}

function PlotService.getPlot(player: Player): number?
	return plotByOwner[player]
end

function PlotService.getOwner(plotIndex: number): Player?
	return ownerByPlot[plotIndex]
end

--- Lowest free plot, so occupied plots stay clustered rather than scattered across the map.
local function findFreePlot(): number?
	for index = 1, PlotLayout.plotCount(Plots) do
		if ownerByPlot[index] == nil then
			return index
		end
	end
	return nil
end

--[[
	Moves a character onto its plot, facing inward toward the slot grid.

	Runs on every spawn rather than only on claim, so a respawn does not dump the player
	back at the default SpawnLocation on the far side of the map.
]]
local function placeCharacter(player: Player, character: Model, plotIndex: number): ()
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil then
		local found = character:WaitForChild("HumanoidRootPart", 5)
		if found == nil then
			warn(`[PlotService] {player.Name}'s character never got a root part`)
			return
		end
	end

	local spawn = PlotLayout.spawnPosition(plotIndex, Plots)
	local center = PlotLayout.plotCenter(plotIndex, Plots)

	character:PivotTo(CFrame.lookAt(
		Vector3.new(spawn.x, spawn.y, spawn.z),
		-- Look at the plot centre at the player's own height, so the camera starts level
		-- instead of angled at the floor.
		Vector3.new(center.x, spawn.y, center.z)
	))
end

local function onPlayerAdded(player: Player): ()
	local plotIndex = findFreePlot()

	if plotIndex == nil then
		-- Only reachable if the place allows more players than there are plots, which is
		-- a place configuration mistake rather than a runtime condition.
		warn(
			`[PlotService] no free plot for {player.Name}; `
				.. `MaxPlayers exceeds the {PlotLayout.plotCount(Plots)} plots in Config/Plots`
		)
		player:Kick("This server is full. Please try another.")
		return
	end

	ownerByPlot[plotIndex] = player
	plotByOwner[player] = plotIndex

	local model = PlotGeometry.getPlotModel(plotIndex)
	if model then
		model:SetAttribute("OwnerUserId", player.UserId)
	end
	PlotGeometry.setOwnerLabel(plotIndex, player.Name)

	player.CharacterAdded:Connect(function(character)
		-- Re-read rather than closing over plotIndex: by the time a later respawn fires,
		-- ownership could in principle have changed.
		local current = plotByOwner[player]
		if current then
			placeCharacter(player, character, current)
		end
	end)

	if player.Character then
		placeCharacter(player, player.Character, plotIndex)
	end

	print(`[PlotService] {player.Name} claimed plot {plotIndex}`)
end

local function onPlayerRemoving(player: Player): ()
	local plotIndex = plotByOwner[player]
	if plotIndex == nil then
		return
	end

	plotByOwner[player] = nil
	ownerByPlot[plotIndex] = nil

	local model = PlotGeometry.getPlotModel(plotIndex)
	if model then
		model:SetAttribute("OwnerUserId", 0)
	end
	PlotGeometry.setOwnerLabel(plotIndex, nil)

	print(`[PlotService] released plot {plotIndex} from {player.Name}`)
end

function PlotService.start(): ()
	PlotGeometry.build()

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	print(`[PlotService] built {PlotLayout.plotCount(Plots)} plots`)
end

return PlotService
