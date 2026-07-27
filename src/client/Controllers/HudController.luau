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
local ShopController = require(script.Parent.ShopController)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Icons = require(Shared.Config.Icons)
local Format = require(Shared.Lib.Format)
local Remotes = require(Shared.Net.Remotes)

local INK = Color3.fromRGB(46, 52, 64)
local MUTED = Color3.fromRGB(180, 190, 205)
local COIN = Color3.fromRGB(235, 203, 139)

local HudController = {}

local gui: ScreenGui? = nil
local amountLabel: TextLabel? = nil
local amountScale: UIScale? = nil
local collectSound: Sound? = nil
local previousCoins: number? = nil

local function corner(radius: number): Instance
	return create("UICorner", { CornerRadius = UDim.new(0, radius) })
end

local function showGain(amount: number): ()
	local root = gui
	local sound = collectSound
	if root == nil or sound == nil then
		return
	end

	sound:Play()

	local label = create("TextLabel", {
		Name = "CoinGain",
		Size = UDim2.fromOffset(180, 28),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 70),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = COIN,
		TextStrokeTransparency = 0.55,
		Text = `+{Format.short(amount)}`,
		Parent = root,
	}) :: TextLabel

	TweenService
		:Create(label, TweenInfo.new(0.65, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Position = UDim2.new(1, -16, 0, 42),
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
		:Play()

	task.delay(0.7, function()
		label:Destroy()
	end)

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
	gui = root

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

	local counter = create("Frame", {
		Name = "Coins",
		Size = UDim2.fromOffset(190, 52),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 14),
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.06,
		BorderSizePixel = 0,
		Parent = root,
	}, {
		corner(10),
		scale,
		create("ImageLabel", {
			Name = "Icon",
			Size = UDim2.fromOffset(32, 32),
			Position = UDim2.fromOffset(10, 10),
			BackgroundTransparency = 1,
			Image = Icons.currency,
			ScaleType = Enum.ScaleType.Fit,
		}),
		create("TextLabel", {
			Name = "Caption",
			Size = UDim2.new(1, -58, 0, 16),
			Position = UDim2.fromOffset(48, 6),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamMedium,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = MUTED,
			Text = "COINS",
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
