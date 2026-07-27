--!strict
--[[
	The persistent coin HUD and gain feedback.

	The displayed balance is copied from whole server snapshots. A positive difference between
	two snapshots drives presentation only: the server already decided and applied the amount.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local create = require(script.Parent.Parent.UI.create)
local FloatingGain = require(script.Parent.Parent.UI.FloatingGain)
local ShopController = require(script.Parent.ShopController)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Icons = require(Shared.Config.Icons)
local Format = require(Shared.Lib.Format)
local Remotes = require(Shared.Net.Remotes)

local INK = Color3.fromRGB(46, 52, 64)
local MUTED = Color3.fromRGB(180, 190, 205)
local COIN = Color3.fromRGB(235, 203, 139)

local HudController = {}

local amountLabel: TextLabel? = nil
local amountScale: UIScale? = nil
local collectSound: Sound? = nil
local previousCoins: number? = nil

local function corner(radius: number): Instance
	return create("UICorner", { CornerRadius = UDim.new(0, radius) })
end

local function showGain(amount: number): ()
	local sound = collectSound
	if sound == nil then
		return
	end

	sound:Play()

	--[[
		The gain erupts off the character, not out of the HUD corner. The bank in the corner
		still pops, so the two together say "this much, and it went there", which is the whole
		job of the feedback.
	]]
	FloatingGain.show(Players.LocalPlayer.Character, Icons.money, `+{Format.short(amount)}`)

	local scale = amountScale
	if scale then
		TweenService:Create(
			scale,
			TweenInfo.new(0.12, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ Scale = 1.08 }
		):Play()
		task.delay(0.12, function()
			TweenService:Create(
				scale,
				TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
				{ Scale = 1 }
			):Play()
		end)
	end
end

local function applySnapshot(payload: Remotes.Snapshot): ()
	local previous = previousCoins
	previousCoins = payload.coins

	if amountLabel then
		-- Preserve exact small balances, then switch before comma formatting outgrows the
		-- icon-narrowed label. Shop affordability still uses the exact snapshot value.
		amountLabel.Text = if payload.coins >= 1_000_000
			then Format.short(payload.coins)
			else Format.comma(payload.coins)
	end

	if previous ~= nil and payload.coins > previous then
		showGain(payload.coins - previous)
	end
end

local function build(): ()
	local root = create("ScreenGui", {
		Name = "VendingEmpireHud",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 10,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	}) :: ScreenGui

	local scale = create("UIScale", { Scale = 1 }) :: UIScale
	amountScale = scale

	local label = create("TextLabel", {
		Name = "Amount",
		Size = UDim2.new(1, -58, 0, 26),
		Position = UDim2.fromOffset(48, 20),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COIN,
		Text = "0",
	}) :: TextLabel
	amountLabel = label

	--[[
		Bottom right, matching where a simulator player already looks for their balance, and
		diagonally opposite the launcher column at bottom left so neither crowds the other.

		Top centre and top right both belong to Roblox: the chat and player list live up there
		and can push a banner around or sit on top of it.
	]]
	local counter = create("Frame", {
		Name = "Coins",
		Size = UDim2.fromOffset(190, 52),
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -16),
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.06,
		BorderSizePixel = 0,
		Parent = root,
	}, {
		corner(10),
		scale,
		create("UIStroke", {
			Thickness = 3,
			Color = Color3.fromRGB(30, 34, 44),
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		create("ImageLabel", {
			Name = "Icon",
			Size = UDim2.fromOffset(32, 32),
			Position = UDim2.fromOffset(10, 10),
			BackgroundTransparency = 1,
			Image = Icons.money,
			ScaleType = Enum.ScaleType.Fit,
		}),
		-- Uppercase black with an outline, the same voice as every other label in the interface.
		create("TextLabel", {
			Name = "Caption",
			Size = UDim2.new(1, -58, 0, 16),
			Position = UDim2.fromOffset(48, 5),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBlack,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = MUTED,
			Text = "COINS",
		}, {
			create("UIStroke", {
				Thickness = 2,
				Color = Color3.fromRGB(30, 34, 44),
				ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
			}),
		}),
		label,
	})
	counter.Parent = root

	local sound = Instance.new("Sound")
	sound.Name = "Collect"
	sound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
	sound.Volume = 0.35
	sound.Parent = SoundService
	collectSound = sound
end

function HudController.start(): ()
	build()

	Remotes.get(Remotes.names.sync).OnClientEvent:Connect(applySnapshot)

	-- ShopController connects first during bootstrap. If the initial snapshot arrived in
	-- between the two starts, seed from its copy rather than leaving the HUD at zero.
	local current = ShopController.snapshot()
	if current and previousCoins == nil then
		applySnapshot(current)
	end
end

return HudController
