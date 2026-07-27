--!strict
--[[
	A large, icon-only launcher button for the side menu.

	Icon only, no caption. The icon has to carry the whole meaning, so only use this with a
	glyph a player reads instantly (a storefront, a coin). See the accessibility note at the
	bottom of this comment for what that costs and how it is covered.

	EVERY ANIMATION GOES THROUGH UIScale, NEVER Size. Tweening `Size` on a button inside a
	UIListLayout re-runs layout on every frame of the tween and shoves its neighbours around.
	A UIScale scales the rendered result and leaves the layout box alone, so a button can
	overshoot past its own bounds without moving anything else.

	The attention bounce is deliberate noise, and it is rationed:

	  - It only plays while the button is idle. Not while hovered, not while pressed, and not
	    while its panel is open, because drawing the eye to something the player is already
	    looking at is just jitter.
	  - The interval is jittered per button. Phase 5 adds more launchers, and a fixed interval
	    would sync them into a metronome, which reads as a broken UI rather than a nudge.
	  - It is skipped entirely under `GuiService.ReducedMotionEnabled`. The bounce carries no
	    information, so it is exactly the motion that should be droppable.

	ACCESSIBILITY. Removing the caption removes the only text affordance, so the icon is the
	single cue and there is no label for a player who does not recognise it. Covered on desktop
	by a hover tooltip, which is not reachable on touch or gamepad. If that turns out to matter,
	the fix is a caption under the icon rather than beside it, which keeps the button square.
]]

local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")

local create = require(script.Parent.create)

--- Studs are meaningless here; this is a square pixel button sized for a thumb on mobile.
local BUTTON_SIZE = 76
local CORNER_RADIUS = 18
local ICON_INSET = 14
local OUTLINE_THICKNESS = 3

local OUTLINE_COLOR = Color3.fromRGB(30, 34, 44)
local TOOLTIP_INK = Color3.fromRGB(30, 34, 44)
local TOOLTIP_TEXT = Color3.fromRGB(236, 239, 244)

local HOVER_SCALE = 1.06
local PRESS_SCALE = 0.92

--- Seconds between attention bounces, before jitter.
local IDLE_INTERVAL = 5
--- Random spread added to the interval so two launchers never settle into lockstep.
local IDLE_JITTER = 2.5

local MenuButton = {}

export type Config = {
	icon: string,
	color: Color3,
	--- Shown on hover. The button has no caption, so this is the only text form of its name.
	tooltip: string,
	order: number?,
	onActivated: () -> (),
}

export type Handle = {
	button: TextButton,
	--- Call with true while the button's panel is open. Suppresses the attention bounce and
	--- holds the pressed-in look, so the button reads as the thing that is currently open.
	setOpen: (boolean) -> (),
}

local function tween(instance: Instance, seconds: number, goal: { [string]: any }): Tween
	return TweenService:Create(
		instance,
		TweenInfo.new(seconds, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		goal
	)
end

--[[
	Squash, overshoot, settle. Back easing on the way out is what makes it read as a physical
	pop rather than a size change, and the return leg is longer than the departure so it lands
	softly instead of snapping.
]]
local function bounce(scale: UIScale, target: TextButton): ()
	TweenService
		:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Scale = 1.16,
		})
		:Play()
	TweenService
		:Create(target, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Rotation = -5,
		})
		:Play()

	task.delay(0.12, function()
		if scale.Parent == nil then
			return
		end
		TweenService
			:Create(scale, TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Scale = 1,
			})
			:Play()
		TweenService
			:Create(target, TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Rotation = 0,
			})
			:Play()
	end)
end

function MenuButton.create(config: Config): Handle
	local scale = create("UIScale", { Scale = 1 }) :: UIScale

	local icon = create("ImageLabel", {
		Name = "Icon",
		Size = UDim2.new(1, -ICON_INSET * 2, 1, -ICON_INSET * 2),
		Position = UDim2.fromOffset(ICON_INSET, ICON_INSET),
		BackgroundTransparency = 1,
		Image = config.icon,
		ScaleType = Enum.ScaleType.Fit,
	})

	local outline = create("UIStroke", {
		Thickness = OUTLINE_THICKNESS,
		Color = OUTLINE_COLOR,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}) :: UIStroke

	local button = create("TextButton", {
		Name = "MenuButton",
		Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE),
		BackgroundColor3 = config.color,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		LayoutOrder = config.order or 1,
		Text = "",
	}, {
		create("UICorner", { CornerRadius = UDim.new(0, CORNER_RADIUS) }),
		outline,
		scale,
		icon,
	}) :: TextButton

	local tooltip = create("TextLabel", {
		Name = "Tooltip",
		--- Sized to its own text so a longer future label does not need a new number here.
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 26),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(1, 10, 0.5, 0),
		BackgroundColor3 = TOOLTIP_INK,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = TOOLTIP_TEXT,
		Text = config.tooltip,
		Visible = false,
		Parent = button,
	}, {
		create("UICorner", { CornerRadius = UDim.new(0, 7) }),
		create("UIPadding", {
			PaddingLeft = UDim.new(0, 10),
			PaddingRight = UDim.new(0, 10),
		}),
	}) :: TextLabel

	local hovered = false
	local pressed = false
	local open = false

	local function restScale(): number
		if pressed then
			return PRESS_SCALE
		end
		if hovered then
			return HOVER_SCALE
		end
		return 1
	end

	local function settle(): ()
		tween(scale, 0.12, { Scale = restScale() }):Play()
	end

	button.MouseEnter:Connect(function()
		hovered = true
		tooltip.Visible = true
		settle()
	end)

	button.MouseLeave:Connect(function()
		hovered = false
		-- Also clears `pressed`: a button released outside its own bounds never raises
		-- MouseButton1Up, so without this the button stays visually held down forever.
		pressed = false
		tooltip.Visible = false
		settle()
	end)

	button.MouseButton1Down:Connect(function()
		pressed = true
		settle()
	end)

	button.MouseButton1Up:Connect(function()
		pressed = false
		settle()
	end)

	button.Activated:Connect(config.onActivated)

	--[[
		One loop per button rather than a shared scheduler. There will be a handful of these,
		and a loop that reads its own state needs no bookkeeping to stay correct when a panel
		opens mid-wait.
	]]
	task.spawn(function()
		while button.Parent ~= nil do
			task.wait(IDLE_INTERVAL + math.random() * IDLE_JITTER)

			if GuiService.ReducedMotionEnabled then
				continue
			end
			if open or hovered or pressed then
				continue
			end
			bounce(scale, button)
		end
	end)

	local function setOpen(isOpen: boolean): ()
		open = isOpen
		outline.Color = if isOpen
			then config.color:Lerp(Color3.new(1, 1, 1), 0.4)
			else OUTLINE_COLOR
		outline.Thickness = if isOpen then OUTLINE_THICKNESS + 1 else OUTLINE_THICKNESS
		settle()
	end

	return {
		button = button,
		setOpen = setOpen,
	}
end

return MenuButton
