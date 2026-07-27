--!strict
--[[
	The shop panel, the coin readout, and the rejection toast.

	Sends intent and nothing else. A Buy button fires the machine's type id, with no slot, so
	the server picks the lowest free one. No price, no rate, no balance ever leaves here: the
	numbers on screen are a mirror of the last snapshot the server sent, and if this client
	were edited to show a different one it would only be lying to itself.

	The whole panel is rebuilt from `Config/Machines` rather than listing tiers by hand, so
	adding a machine to the tuning table adds it to the shop with no UI change. Categories and
	upgrade buttons are Phase 4; this shows the flat tier ladder.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local create = require(script.Parent.Parent.UI.create)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Machines = require(Shared.Config.Machines)
local Format = require(Shared.Lib.Format)
local Remotes = require(Shared.Net.Remotes)

--[[
	Wording for every rejection code the server can send.

	The codes are the contract, the sentences are not, which is why they live on this side.
	`too_far` and `nothing_to_collect` come from the collect path, which has no remote to
	report through, so they are only reachable when the server logs one; they are listed for
	completeness and so a stray one is legible rather than raw.
]]
local MESSAGES: { [string]: string } = {
	insufficient_funds = "Not enough coins.",
	slot_taken = "That slot already has a machine.",
	slot_locked = "That slot is locked.",
	slot_out_of_range = "That slot does not exist.",
	plot_full = "Your plot is full.",
	unknown_machine = "That machine is not available.",
	no_plot = "Your plot is still loading.",
	no_profile = "Your data is still loading.",
	too_far = "Move closer to the machine.",
	nothing_to_collect = "Nothing to collect yet.",
}

local INK = Color3.fromRGB(46, 52, 64)
local SNOW = Color3.fromRGB(236, 239, 244)
local FROST = Color3.fromRGB(94, 129, 172)
local MUTED = Color3.fromRGB(76, 86, 106)
local GREEN = Color3.fromRGB(163, 190, 140)
local RED = Color3.fromRGB(191, 97, 106)

local TOAST_SECONDS = 2.5

local ShopController = {}

type Row = {
	button: TextButton,
	detail: TextLabel,
}

local snapshot: Remotes.Snapshot? = nil
local rows: { [string]: Row } = {}
local coinsLabel: TextLabel? = nil
local toast: TextLabel? = nil
local panel: Frame? = nil
--- Incremented on every toast, so an earlier timer cannot hide a later message.
local toastToken = 0

local function corner(radius: number): Instance
	return create("UICorner", { CornerRadius = UDim.new(0, radius) })
end

local function showToast(message: string, isError: boolean): ()
	local label = toast
	if label == nil then
		return
	end

	toastToken += 1
	local token = toastToken

	label.Text = message
	label.TextColor3 = if isError then RED else GREEN
	label.Visible = true

	task.delay(TOAST_SECONDS, function()
		-- Only the most recent toast may hide the label. Without the token, two messages
		-- 0.2s apart would leave the second one visible for 0.2s instead of its full time.
		if token == toastToken then
			label.Visible = false
		end
	end)
end

--- Refreshes affordability styling. Called on every snapshot, which is every balance change.
local function refresh(): ()
	local current = snapshot
	if current == nil then
		return
	end

	if coinsLabel then
		coinsLabel.Text = Format.comma(current.coins)
	end

	for _, config in Machines.list do
		local row = rows[config.id]
		if row == nil then
			continue
		end

		local affordable = current.coins >= config.cost
		row.button.Text = Format.short(config.cost)
		row.button.BackgroundColor3 = if affordable then FROST else MUTED
		row.button.TextTransparency = if affordable then 0 else 0.4

		local rate = config.baseRate * current.prestigeMultiplier
		row.detail.Text = `{Format.short(rate)}/s, holds {Format.short(rate * config.fillSeconds)}`
	end
end

local function buildRow(config: Machines.Machine, order: number): Instance
	local name = create("TextLabel", {
		Size = UDim2.new(1, -84, 0, 20),
		Position = UDim2.fromOffset(10, 6),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = SNOW,
		Text = `{config.tier}. {config.displayName}`,
	})

	local detail = create("TextLabel", {
		Size = UDim2.new(1, -84, 0, 16),
		Position = UDim2.fromOffset(10, 26),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(180, 190, 205),
		-- Filled in by `refresh`, which knows the prestige multiplier.
		Text = "",
	}) :: TextLabel

	local button = create("TextButton", {
		Size = UDim2.fromOffset(68, 30),
		Position = UDim2.new(1, -78, 0, 9),
		BackgroundColor3 = FROST,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = SNOW,
		Text = Format.short(config.cost),
		AutoButtonColor = true,
	}, { corner(6) }) :: TextButton

	button.Activated:Connect(function()
		-- Intent only: a type id, and no slot, so the server chooses where it goes.
		Remotes.get(Remotes.names.buyMachine)
			:FireServer({ typeId = config.id } :: Remotes.BuyMachine)
	end)

	rows[config.id] = { button = button, detail = detail }

	return create("Frame", {
		Name = config.id,
		Size = UDim2.new(1, -8, 0, 48),
		BackgroundColor3 = Color3.fromRGB(59, 66, 82),
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, { corner(8), name, detail, button })
end

local function buildPanel(): Frame
	local list = create("ScrollingFrame", {
		Size = UDim2.new(1, -16, 1, -52),
		Position = UDim2.fromOffset(8, 44),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	})

	create("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = list,
	})

	for order, config in Machines.list do
		buildRow(config, order).Parent = list
	end

	local title = create("TextLabel", {
		Size = UDim2.new(1, -16, 0, 30),
		Position = UDim2.fromOffset(12, 8),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = SNOW,
		Text = "Machines",
	})

	return create("Frame", {
		Name = "ShopPanel",
		Size = UDim2.fromOffset(320, 340),
		Position = UDim2.new(0, 16, 1, -404),
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Visible = false,
	}, { corner(12), title, list }) :: Frame
end

local function build(): ()
	local player = Players.LocalPlayer
	local gui = create("ScreenGui", {
		Name = "VendingEmpire",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})

	local shopPanel = buildPanel()
	shopPanel.Parent = gui
	panel = shopPanel

	local toggle = create("TextButton", {
		Name = "ShopToggle",
		Size = UDim2.fromOffset(120, 44),
		Position = UDim2.new(0, 16, 1, -60),
		BackgroundColor3 = FROST,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextColor3 = SNOW,
		Text = "Shop",
		Parent = gui,
	}, { corner(10) }) :: TextButton

	toggle.Activated:Connect(function()
		shopPanel.Visible = not shopPanel.Visible
	end)

	--[[
		A minimal coin readout, not the Phase 4 HUD. It exists now because the Phase 3 gate is
		"walk up, press E, get coins", and coins that are not on screen cannot be seen to
		arrive. Phase 4 replaces this with the real counter and the floating +N.
	]]
	local coins = create("Frame", {
		Name = "Coins",
		Size = UDim2.fromOffset(160, 40),
		Position = UDim2.new(0.5, -80, 0, 12),
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Parent = gui,
	}, { corner(10) })

	coinsLabel = create("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 18,
		TextColor3 = GREEN,
		Text = "0",
		Parent = coins,
	}) :: TextLabel

	toast = create("TextLabel", {
		Name = "Toast",
		Size = UDim2.fromOffset(320, 32),
		Position = UDim2.new(0.5, -160, 1, -110),
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		TextColor3 = RED,
		Text = "",
		Visible = false,
		Parent = gui,
	}, { corner(8) }) :: TextLabel
end

function ShopController.start(): ()
	build()

	Remotes.get(Remotes.names.sync).OnClientEvent:Connect(function(payload: Remotes.Snapshot)
		snapshot = payload
		refresh()
	end)

	Remotes.get(Remotes.names.notice).OnClientEvent:Connect(function(payload: Remotes.Notice)
		local code = payload.code
		showToast(MESSAGES[code] or `Request refused ({code}).`, true)
	end)
end

--- The current snapshot, for other controllers. Nil until the first one arrives.
function ShopController.snapshot(): Remotes.Snapshot?
	return snapshot
end

--- Closes the panel, for anything that needs the screen. Unused in Phase 3.
function ShopController.close(): ()
	if panel then
		panel.Visible = false
	end
end

return ShopController
