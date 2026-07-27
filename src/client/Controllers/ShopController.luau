--!strict
--[[
	The category shop and rejection toast.

	Sends intent and nothing else. A Buy button fires the machine's type id, with no slot, so
	the server picks the lowest free one. Prices, rates, and affordability are mirrors of the
	last authoritative snapshot and config; editing them only makes this client lie to itself.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local create = require(script.Parent.Parent.UI.create)
local MachineThumbnail = require(script.Parent.Parent.UI.MachineThumbnail)
local MenuButton = require(script.Parent.Parent.UI.MenuButton)
local Sunburst = require(script.Parent.Parent.UI.Sunburst)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Icons = require(Shared.Config.Icons)
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

--[[
	Card colours are the category colour shifted per tier within the category.

	Storefronts in this genre give every card its own colour, which makes a grid scannable. Doing
	that with nine unrelated hues would throw away the category language the rest of the game
	teaches, so instead each card keeps its category hue and separates on brightness. Cards are
	individually distinct, and a Snacks card still reads as a Snacks card.

	Tier is 1-based across all nine machines, so it is reduced to a position within its own
	category first.
]]
local TIER_SHIFTS = { -0.12, 0.06, 0.24 }

local function cardColor(config: Machines.Machine): Color3
	local base = CATEGORY_COLOR[config.category]
	local shift = TIER_SHIFTS[(config.tier - 1) % #TIER_SHIFTS + 1]

	if shift < 0 then
		return base:Lerp(Color3.fromRGB(24, 27, 35), -shift)
	end
	return base:Lerp(Color3.new(1, 1, 1), shift)
end

--- Dark outline shared by every card, pill, and close button. The genre's whole look rests on it.
local OUTLINE = Color3.fromRGB(24, 27, 35)
--- Saturated price pill. Deliberately louder than any other green in the interface.
local PRICE_GREEN = Color3.fromRGB(88, 176, 96)
local LOCKED_GREY = Color3.fromRGB(88, 95, 112)

local CARD_WIDTH = 150
local CARD_HEIGHT = 202
local CARD_GAP = 10

--- Artwork band inside a card. The sunburst centres on this, not on the card.
local ART_TOP = 44
local ART_HEIGHT = 92
--[[
	Must not exceed the card's narrow dimension, and must fit around its centre. Sunburst rays are
	bounded by their container rather than clipped, because Roblox will not clip a rotated child,
	so an oversized value here puts rays outside the card with nothing to stop them.
]]
local SUNBURST_DIAMETER = 140

local TOAST_SECONDS = 2.5

local ShopController = {}

type Card = {
	frame: TextButton,
	pill: Frame,
	pillIcon: ImageLabel,
	price: TextLabel,
	detail: TextLabel,
	category: Machines.Category,
}

type Toast = {
	frame: Frame,
	icon: ImageLabel,
	label: TextLabel,
}

local snapshot: Remotes.Snapshot? = nil
local cards: { [string]: Card } = {}
local tabs: { [Machines.Category]: TextButton } = {}
local activeCategory: Machines.Category = "drinks"
local toast: Toast? = nil
local toastToken = 0

local function corner(radius: number): Instance
	return create("UICorner", { CornerRadius = UDim.new(0, radius) })
end

local function showToast(message: string, isError: boolean): ()
	local current = toast
	if current == nil then
		return
	end

	toastToken += 1
	local token = toastToken

	current.label.Text = message
	current.label.TextColor3 = if isError then RED else GREEN
	current.icon.Image = if isError then Icons.error else Icons.success
	current.frame.Visible = true

	task.delay(TOAST_SECONDS, function()
		if token == toastToken then
			current.frame.Visible = false
		end
	end)
end

local function selectCategory(category: Machines.Category): ()
	activeCategory = category

	-- Roblox layouts skip invisible children, so hiding the other categories is all the
	-- filtering the grid needs.
	for _, card in cards do
		card.frame.Visible = card.category == category
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
end

local function refresh(): ()
	local current = snapshot
	if current == nil then
		return
	end

	for _, config in Machines.list do
		local card = cards[config.id]
		if card == nil then
			continue
		end

		local affordable = current.coins >= config.cost

		--[[
			Affordability is carried by the word as well as the colour. "Buy" versus "Need" says
			which state this is without relying on green against grey, which is the one thing
			PRODUCT.md's accessibility section rules out.
		]]
		card.price.Text = if affordable
			then `Buy {Format.short(config.cost)}`
			else `Need {Format.short(config.cost)}`
		card.pill.BackgroundColor3 = if affordable then PRICE_GREEN else LOCKED_GREY
		card.pillIcon.ImageTransparency = if affordable then 0 else 0.4
		card.frame.Active = affordable
		card.frame.AutoButtonColor = affordable

		local rate = config.baseRate * current.prestigeMultiplier
		card.detail.Text =
			`{Format.short(rate)}/s  ·  {Format.short(rate * config.fillSeconds)} cap`
	end
end

--- Thick dark outline. Every card, pill, and title in the shop wears one; it is the whole look.
local function outline(thickness: number): Instance
	return create("UIStroke", {
		Thickness = thickness,
		Color = OUTLINE,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

--[[
	One product card: title, live 3D portrait over a sunburst, stats, and a price pill.

	THE WHOLE CARD IS THE BUTTON, not just the pill. The pill is where the eye goes and reads as
	the call to action, but a 150 by 202 target beats a 130 by 32 one on a phone, and there is
	nothing else on a card to click.
]]
local function buildCard(config: Machines.Machine): TextButton
	local color = cardColor(config)

	local title = create("TextLabel", {
		Name = "Title",
		Size = UDim2.new(1, -16, 0, 34),
		Position = UDim2.fromOffset(8, 8),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextSize = 14,
		TextWrapped = true,
		TextColor3 = SNOW,
		Text = config.displayName,
	}, {
		-- Contextual, not Border: this strokes the glyphs so the name stays legible over a
		-- bright sunburst, which a border around the label would not do.
		create("UIStroke", {
			Thickness = 2,
			Color = OUTLINE,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		}),
	})

	--[[
		The live mesh preview, or a flat money icon when the machine has no art registered yet.
		A machine can reach the tuning table before its mesh does, and a card with a blank hole
		in it looks broken in a way a placeholder does not.
	]]
	local art: Instance = MachineThumbnail.create(config.id)
		or create("ImageLabel", {
			Name = "Thumbnail",
			BackgroundTransparency = 1,
			Image = Icons.money,
			ScaleType = Enum.ScaleType.Fit,
		})
	local artFrame = art :: GuiObject
	artFrame.Size = UDim2.new(1, -20, 0, ART_HEIGHT)
	artFrame.Position = UDim2.fromOffset(10, ART_TOP)

	local detail = create("TextLabel", {
		Name = "Detail",
		Size = UDim2.new(1, -16, 0, 14),
		Position = UDim2.fromOffset(8, 138),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		TextColor3 = SNOW,
		TextTransparency = 0.15,
		Text = "",
	}) :: TextLabel

	local pillIcon = create("ImageLabel", {
		Name = "Icon",
		Size = UDim2.fromOffset(22, 22),
		Position = UDim2.new(0, 8, 0.5, -11),
		BackgroundTransparency = 1,
		Image = Icons.money,
		ScaleType = Enum.ScaleType.Fit,
	}) :: ImageLabel

	local price = create("TextLabel", {
		Name = "Price",
		Size = UDim2.new(1, -34, 1, 0),
		Position = UDim2.fromOffset(32, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextSize = 14,
		TextColor3 = SNOW,
		Text = `Buy {Format.short(config.cost)}`,
	}, {
		create("UIStroke", {
			Thickness = 2,
			Color = OUTLINE,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		}),
	}) :: TextLabel

	local pill = create("Frame", {
		Name = "Pill",
		Size = UDim2.new(1, -20, 0, 36),
		Position = UDim2.new(0, 10, 1, -46),
		BackgroundColor3 = PRICE_GREEN,
		BorderSizePixel = 0,
	}, { corner(10), outline(2), pillIcon, price }) :: Frame

	local scale = create("UIScale", { Scale = 1 }) :: UIScale

	local frame = create("TextButton", {
		Name = config.id,
		Size = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = true,
		LayoutOrder = config.tier,
		Visible = config.category == activeCategory,
	}, {
		corner(14),
		outline(3),
		scale,
		-- Sunburst first, so everything else draws over it. Centred on the artwork band so the
		-- light reads as coming from behind the product.
		Sunburst.create(
			color,
			SUNBURST_DIAMETER,
			Vector2.new(CARD_WIDTH / 2, ART_TOP + ART_HEIGHT / 2)
		),
		title,
		art,
		detail,
		pill,
	}) :: TextButton

	frame.MouseEnter:Connect(function()
		TweenService
			:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
				Scale = 1.04,
			})
			:Play()
	end)
	frame.MouseLeave:Connect(function()
		TweenService
			:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
				Scale = 1,
			})
			:Play()
	end)

	frame.Activated:Connect(function()
		Remotes.get(Remotes.names.buyMachine)
			:FireServer({ typeId = config.id } :: Remotes.BuyMachine)
	end)

	cards[config.id] = {
		frame = frame,
		pill = pill,
		pillIcon = pillIcon,
		price = price,
		detail = detail,
		category = config.category,
	}
	return frame
end

local function buildTabs(): Frame
	local bar = create("Frame", {
		Size = UDim2.new(1, -28, 0, 34),
		Position = UDim2.fromOffset(14, 48),
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
			Font = Enum.Font.GothamBlack,
			TextSize = 14,
			TextColor3 = QUIET_TEXT,
			Text = CATEGORY_LABEL[category],
			LayoutOrder = order,
			AutoButtonColor = true,
		}, { corner(9), outline(2) }) :: TextButton

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

--[[
	The panel shell.

	Kept on the dark Nord surface rather than the light sheet the reference storefronts use. The
	bank, the launcher, and the toast are all dark, and a white panel would read as a different
	application dropped on top of the game. Saturated cards on a dark shell also carry more
	contrast than the same cards on white, which is the part that actually draws the eye.

	Sized to the grid instead of the reverse: exactly three machines per category, so one row of
	three cards fits with no scrolling and no partly visible fourth card teasing the edge.
]]
local function buildPanel(onClose: () -> ()): Frame
	local grid = create("Frame", {
		Name = "Cards",
		Size = UDim2.fromOffset(CARD_WIDTH * 3 + CARD_GAP * 2, CARD_HEIGHT),
		Position = UDim2.fromOffset(14, 88),
		BackgroundTransparency = 1,
	}, {
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, CARD_GAP),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}) :: Frame

	for _, config in Machines.list do
		buildCard(config).Parent = grid
	end

	local title = create("TextLabel", {
		Size = UDim2.new(1, -110, 0, 32),
		Position = UDim2.fromOffset(52, 10),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = SNOW,
		Text = "MACHINE SHOP",
	}, {
		create("UIStroke", {
			Thickness = 2,
			Color = OUTLINE,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		}),
	})

	--[[
		Oversized circular close, top right, as loud as the reference.

		A panel this big needs an exit that is found without looking, and the launcher toggling it
		shut is not discoverable once the panel has covered the launcher's corner of the eye.
	]]
	local close = create("TextButton", {
		Name = "Close",
		Size = UDim2.fromOffset(38, 38),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 8),
		BackgroundColor3 = RED,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBlack,
		TextSize = 20,
		TextColor3 = SNOW,
		Text = "X",
		AutoButtonColor = true,
	}, {
		-- Half the height, so the corner radius makes it an actual circle.
		create("UICorner", { CornerRadius = UDim.new(0, 19) }),
		outline(3),
	}) :: TextButton
	close.Activated:Connect(onClose)

	local panel = create("Frame", {
		Name = "ShopPanel",
		Size = UDim2.fromOffset(CARD_WIDTH * 3 + CARD_GAP * 2 + 28, CARD_HEIGHT + 102),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -104),
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		Visible = false,
	}, {
		corner(16),
		outline(3),
		create("ImageLabel", {
			Name = "ShopIcon",
			Size = UDim2.fromOffset(32, 32),
			Position = UDim2.fromOffset(14, 10),
			BackgroundTransparency = 1,
			Image = Icons.shop,
			ScaleType = Enum.ScaleType.Fit,
		}),
		title,
		close,
		buildTabs(),
		grid,
	}) :: Frame

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

	--[[
		Panel visibility and launcher state move together, always, through one function. Two call
		sites toggle the shop (the launcher and the close button) and the launcher's open look has
		to survive both, which it will not if each site sets visibility itself.
	]]
	local shopButton: MenuButton.Handle? = nil
	local panel: Frame? = nil

	local function setPanelOpen(open: boolean): ()
		if panel then
			panel.Visible = open
		end
		if shopButton then
			shopButton.setOpen(open)
		end
	end

	local shopPanel = buildPanel(function()
		setPanelOpen(false)
	end)
	shopPanel.Parent = gui
	panel = shopPanel

	--[[
		The launcher column. One button today; Phase 5 adds prestige beside it, which is why
		the layout exists now rather than a single absolutely positioned button.
	]]
	local launchers = create("Frame", {
		Name = "Launchers",
		Size = UDim2.fromOffset(76, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -16),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		create("UIListLayout", {
			Padding = UDim.new(0, 10),
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}) :: Frame

	-- Bound to a non-optional local as well, because `shopButton` has to be declared ahead of
	-- `setPanelOpen` and so stays `Handle?` for the analyzer.
	local created = MenuButton.create({
		icon = Icons.shop,
		color = CATEGORY_COLOR[activeCategory],
		tooltip = "Machine Shop",
		order = 1,
		onActivated = function()
			setPanelOpen(not shopPanel.Visible)
		end,
	})
	shopButton = created
	created.button.Parent = launchers

	local toastIcon = create("ImageLabel", {
		Name = "Icon",
		Size = UDim2.fromOffset(24, 24),
		Position = UDim2.fromOffset(9, 5),
		BackgroundTransparency = 1,
		Image = Icons.error,
		ScaleType = Enum.ScaleType.Fit,
	}) :: ImageLabel

	local toastLabel = create("TextLabel", {
		Name = "Message",
		Size = UDim2.new(1, -46, 1, 0),
		Position = UDim2.fromOffset(42, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = RED,
		Text = "",
	}) :: TextLabel

	local toastFrame = create("Frame", {
		Name = "Toast",
		Size = UDim2.fromOffset(320, 36),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Visible = false,
		Parent = gui,
	}, { corner(8), toastIcon, toastLabel }) :: Frame
	toast = {
		frame = toastFrame,
		icon = toastIcon,
		label = toastLabel,
	}
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
