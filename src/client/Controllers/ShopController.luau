--!strict
--[[
	The category shop and rejection toast.

	Sends intent and nothing else. A Buy button fires the machine's type id, with no slot, so
	the server picks the lowest free one. Prices, rates, and affordability are mirrors of the
	last authoritative snapshot and config; editing them only makes this client lie to itself.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local create = require(script.Parent.Parent.UI.create)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Machines = require(Shared.Config.Machines)
local Format = require(Shared.Lib.Format)
local Remotes = require(Shared.Net.Remotes)

local MESSAGES: { [string]: string } = {
	insufficient_funds = "Not enough coins.",
	slot_taken = "That slot already has a machine.",
	slot_locked = "That slot is locked.",
	slot_out_of_range = "That slot does not exist.",
	plot_full = "Your plot is full.",
	unknown_machine = "That machine is not available.",
	machine_not_found = "That machine is no longer there.",
	level_mismatch = "That machine changed. Try again.",
	max_level = "That machine is already max level.",
	upgrade_cooldown = "Wait a moment before upgrading again.",
	no_plot = "Your plot is still loading.",
	no_profile = "Your data is still loading.",
	too_far = "Move closer to the machine.",
	nothing_to_collect = "Nothing to collect yet.",
}

local INK = Color3.fromRGB(46, 52, 64)
local SURFACE = Color3.fromRGB(59, 66, 82)
local MUTED = Color3.fromRGB(76, 86, 106)
local QUIET_TEXT = Color3.fromRGB(180, 190, 205)
local SNOW = Color3.fromRGB(236, 239, 244)
local GREEN = Color3.fromRGB(163, 190, 140)
local RED = Color3.fromRGB(191, 97, 106)

local CATEGORY_LABEL: { [Machines.Category]: string } = {
	drinks = "Drinks",
	snacks = "Snacks",
	electronics = "Tech",
}
local CATEGORY_COLOR: { [Machines.Category]: Color3 } = {
	drinks = Color3.fromRGB(94, 129, 172),
	snacks = Color3.fromRGB(208, 135, 112),
	electronics = Color3.fromRGB(180, 142, 173),
}

local TOAST_SECONDS = 2.5

local ShopController = {}

type Row = {
	frame: Frame,
	button: TextButton,
	detail: TextLabel,
	category: Machines.Category,
}

local snapshot: Remotes.Snapshot? = nil
local rows: { [string]: Row } = {}
local tabs: { [Machines.Category]: TextButton } = {}
local activeCategory: Machines.Category = "drinks"
local list: ScrollingFrame? = nil
local toast: TextLabel? = nil
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
		if token == toastToken then
			label.Visible = false
		end
	end)
end

local function selectCategory(category: Machines.Category): ()
	activeCategory = category

	for _, row in rows do
		row.frame.Visible = row.category == category
	end

	local function updateTab(tabCategory: Machines.Category): ()
		local tab = tabs[tabCategory]
		local selected = tabCategory == category
		tab.BackgroundColor3 = if selected then CATEGORY_COLOR[tabCategory] else SURFACE
		tab.TextColor3 = if selected then SNOW else QUIET_TEXT
	end
	updateTab("drinks")
	updateTab("snacks")
	updateTab("electronics")

	if list then
		list.CanvasPosition = Vector2.zero
	end
end

local function refresh(): ()
	local current = snapshot
	if current == nil then
		return
	end

	for _, config in Machines.list do
		local row = rows[config.id]
		if row == nil then
			continue
		end

		local affordable = current.coins >= config.cost
		row.button.Text = `Buy {Format.short(config.cost)}`
		row.button.BackgroundColor3 = if affordable then CATEGORY_COLOR[config.category] else MUTED
		row.button.TextTransparency = if affordable then 0 else 0.35
		row.button.Active = affordable
		row.button.AutoButtonColor = affordable

		local rate = config.baseRate * current.prestigeMultiplier
		row.detail.Text =
			`{Format.short(rate)}/s  ·  {Format.short(rate * config.fillSeconds)} capacity`
	end
end

local function buildRow(config: Machines.Machine): Frame
	local name = create("TextLabel", {
		Size = UDim2.new(1, -112, 0, 22),
		Position = UDim2.fromOffset(12, 8),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = SNOW,
		Text = config.displayName,
	})

	local detail = create("TextLabel", {
		Size = UDim2.new(1, -112, 0, 18),
		Position = UDim2.fromOffset(12, 31),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = QUIET_TEXT,
		Text = "",
	}) :: TextLabel

	local button = create("TextButton", {
		Size = UDim2.fromOffset(92, 34),
		Position = UDim2.new(1, -104, 0, 13),
		BackgroundColor3 = CATEGORY_COLOR[config.category],
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = SNOW,
		Text = `Buy {Format.short(config.cost)}`,
		AutoButtonColor = true,
	}, { corner(7) }) :: TextButton

	button.Activated:Connect(function()
		Remotes.get(Remotes.names.buyMachine)
			:FireServer({ typeId = config.id } :: Remotes.BuyMachine)
	end)

	local frame = create("Frame", {
		Name = config.id,
		Size = UDim2.new(1, -8, 0, 60),
		BackgroundColor3 = SURFACE,
		BorderSizePixel = 0,
		LayoutOrder = config.tier,
		Visible = config.category == activeCategory,
	}, { corner(9), name, detail, button }) :: Frame

	rows[config.id] = {
		frame = frame,
		button = button,
		detail = detail,
		category = config.category,
	}
	return frame
end

local function buildTabs(): Frame
	local bar = create("Frame", {
		Size = UDim2.new(1, -16, 0, 34),
		Position = UDim2.fromOffset(8, 42),
		BackgroundTransparency = 1,
	}) :: Frame

	local layout = create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	layout.Parent = bar

	local function addTab(category: Machines.Category, order: number): ()
		local tab = create("TextButton", {
			Name = CATEGORY_LABEL[category],
			Size = UDim2.new(1 / 3, -4, 1, 0),
			BackgroundColor3 = SURFACE,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBold,
			TextSize = 12,
			TextColor3 = QUIET_TEXT,
			Text = CATEGORY_LABEL[category],
			LayoutOrder = order,
			AutoButtonColor = true,
		}, { corner(7) }) :: TextButton

		tab.Activated:Connect(function()
			selectCategory(category)
		end)
		tab.Parent = bar
		tabs[category] = tab
	end
	addTab("drinks", 1)
	addTab("snacks", 2)
	addTab("electronics", 3)

	return bar
end

local function buildPanel(): Frame
	local machineList = create("ScrollingFrame", {
		Size = UDim2.new(1, -16, 1, -86),
		Position = UDim2.fromOffset(8, 80),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}) :: ScrollingFrame
	list = machineList

	create("UIListLayout", {
		Padding = UDim.new(0, 7),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = machineList,
	})

	for _, config in Machines.list do
		buildRow(config).Parent = machineList
	end

	local title = create("TextLabel", {
		Size = UDim2.new(1, -24, 0, 28),
		Position = UDim2.fromOffset(12, 8),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = SNOW,
		Text = "Machine Shop",
	})

	local panel = create("Frame", {
		Name = "ShopPanel",
		Size = UDim2.fromOffset(336, 290),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -72),
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.06,
		BorderSizePixel = 0,
		Visible = false,
	}, { corner(12), title, buildTabs(), machineList }) :: Frame

	selectCategory(activeCategory)
	return panel
end

local function build(): ()
	local gui = create("ScreenGui", {
		Name = "VendingEmpire",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})

	local shopPanel = buildPanel()
	shopPanel.Parent = gui

	local toggle = create("TextButton", {
		Name = "ShopToggle",
		Size = UDim2.fromOffset(120, 44),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -16),
		BackgroundColor3 = CATEGORY_COLOR[activeCategory],
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

	toast = create("TextLabel", {
		Name = "Toast",
		Size = UDim2.fromOffset(320, 34),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.08,
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

function ShopController.snapshot(): Remotes.Snapshot?
	return snapshot
end

return ShopController
