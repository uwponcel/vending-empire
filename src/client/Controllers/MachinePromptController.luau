--!strict
--[[
	Renders one compact action panel for a nearby owned machine.

	Both engine prompts use Custom style, so Roblox still owns distance checks, keyboard and
	gamepad activation, while this controller replaces the two oversized default cards with a
	single visual surface. Buttons call the prompts rather than the services, preserving the
	same production paths for touch and mouse input.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Workspace = game:GetService("Workspace")

local create = require(script.Parent.Parent.UI.create)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Icons = require(Shared.Config.Icons)

local INK = Color3.fromRGB(46, 52, 64)
local SURFACE = Color3.fromRGB(59, 66, 82)
local OUTLINE = Color3.fromRGB(94, 129, 172)
local SNOW = Color3.fromRGB(236, 239, 244)

local PANEL_WIDTH = 228
local ROW_HEIGHT = 36
local ROW_GAP = 5
local PANEL_PADDING = 7

local MachinePromptController = {}

type PromptInput = {
	prompt: ProximityPrompt,
	inputType: Enum.ProximityPromptInputType,
}

type ModelState = {
	shown: { [ProximityPrompt]: Enum.ProximityPromptInputType? },
	gui: BillboardGui?,
}

local states: { [Model]: ModelState? } = {}

local ICON_BY_PROMPT: { [string]: string } = {
	CollectPrompt = Icons.currency,
	UpgradePrompt = Icons.upgrade,
}

local function corner(radius: number): Instance
	return create("UICorner", { CornerRadius = UDim.new(0, radius) })
end

local function modelFor(prompt: ProximityPrompt): Model?
	if prompt.Name ~= "CollectPrompt" and prompt.Name ~= "UpgradePrompt" then
		return nil
	end
	return prompt:FindFirstAncestorOfClass("Model")
end

local function stateFor(model: Model): ModelState
	local current = states[model]
	if current then
		return current
	end

	local created: ModelState = {
		shown = {},
		gui = nil,
	}
	states[model] = created
	return created
end

local function badgeText(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): string
	if inputType == Enum.ProximityPromptInputType.Touch then
		return "TAP"
	end

	local name = if inputType == Enum.ProximityPromptInputType.Gamepad
		then prompt.GamepadKeyCode.Name
		else prompt.KeyboardKeyCode.Name
	return string.gsub(name, "^Button", "")
end

local function activate(prompt: ProximityPrompt): ()
	if not prompt.Enabled then
		return
	end
	prompt:InputHoldBegin()
	prompt:InputHoldEnd()
end

local function buildRow(input: PromptInput, order: number): TextButton
	local prompt = input.prompt
	local button = create("TextButton", {
		Name = prompt.Name,
		Size = UDim2.new(1, -PANEL_PADDING * 2, 0, ROW_HEIGHT),
		BackgroundColor3 = SURFACE,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		LayoutOrder = order,
		AutoButtonColor = true,
		Text = "",
	}, {
		corner(7),
		create("TextLabel", {
			Name = "Key",
			Size = UDim2.fromOffset(34, 24),
			Position = UDim2.fromOffset(6, 6),
			BackgroundColor3 = OUTLINE,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBold,
			TextSize = 11,
			TextColor3 = SNOW,
			Text = badgeText(prompt, input.inputType),
		}, { corner(6) }),
		create("ImageLabel", {
			Name = "Icon",
			Size = UDim2.fromOffset(26, 26),
			Position = UDim2.fromOffset(46, 5),
			BackgroundTransparency = 1,
			Image = ICON_BY_PROMPT[prompt.Name],
			ScaleType = Enum.ScaleType.Fit,
		}),
		create("TextLabel", {
			Name = "Action",
			Size = UDim2.new(1, -84, 1, 0),
			Position = UDim2.fromOffset(80, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamMedium,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = SNOW,
			Text = prompt.ActionText,
		}),
	}) :: TextButton

	button.Activated:Connect(function()
		activate(prompt)
	end)
	return button
end

local function destroyGui(state: ModelState): ()
	if state.gui then
		state.gui:Destroy()
		state.gui = nil
	end
end

local function refresh(model: Model): ()
	local state = states[model]
	if state == nil then
		return
	end

	local inputs: { PromptInput } = {}
	for prompt, inputType in state.shown do
		if inputType and prompt.Enabled and prompt.Parent ~= nil then
			table.insert(inputs, { prompt = prompt, inputType = inputType })
		end
	end
	table.sort(inputs, function(left, right)
		return left.prompt.Name < right.prompt.Name
	end)

	destroyGui(state)
	if #inputs == 0 then
		return
	end

	local body = model:FindFirstChild("Body")
	if body == nil or not body:IsA("BasePart") then
		return
	end

	local height = PANEL_PADDING * 2 + #inputs * ROW_HEIGHT + (#inputs - 1) * ROW_GAP
	local children: { Instance } = {
		corner(10),
		create("UIStroke", {
			Color = OUTLINE,
			Transparency = 0.45,
			Thickness = 1,
		}),
		create("UIListLayout", {
			Padding = UDim.new(0, ROW_GAP),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for order, input in inputs do
		table.insert(children, buildRow(input, order))
	end

	local panel = create("Frame", {
		Name = "Panel",
		Size = UDim2.fromOffset(PANEL_WIDTH, height),
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
	}, children)

	local gui = create("BillboardGui", {
		Name = "MachineActions",
		Adornee = body,
		Size = UDim2.fromOffset(PANEL_WIDTH, height),
		StudsOffsetWorldSpace = Vector3.new(0, -0.4, 2.2),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 50,
		ResetOnSpawn = false,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	}, { panel }) :: BillboardGui
	state.gui = gui
end

local function wireCollectOwnership(prompt: ProximityPrompt, model: Model): ()
	local function refreshOwnership(): ()
		prompt.Enabled = model:GetAttribute("OwnerUserId") == Players.LocalPlayer.UserId
	end

	model:GetAttributeChangedSignal("OwnerUserId"):Connect(refreshOwnership)
	refreshOwnership()
end

local function wirePrompt(prompt: ProximityPrompt): ()
	local model = modelFor(prompt)
	if model == nil then
		return
	end

	if prompt.Name == "CollectPrompt" then
		wireCollectOwnership(prompt, model)
	end

	prompt:GetPropertyChangedSignal("ActionText"):Connect(function()
		refresh(model)
	end)
	prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
		refresh(model)
	end)
end

function MachinePromptController.start(): ()
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("ProximityPrompt") then
			wirePrompt(descendant)
		end
	end

	Workspace.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("ProximityPrompt") then
			wirePrompt(descendant)
		end
	end)

	ProximityPromptService.PromptShown:Connect(
		function(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
			local model = modelFor(prompt)
			if model == nil or model:GetAttribute("OwnerUserId") ~= Players.LocalPlayer.UserId then
				return
			end

			stateFor(model).shown[prompt] = inputType
			refresh(model)
		end
	)

	ProximityPromptService.PromptHidden:Connect(function(prompt: ProximityPrompt)
		local model = modelFor(prompt)
		if model == nil then
			return
		end

		local state = states[model]
		if state == nil then
			return
		end
		state.shown[prompt] = nil
		refresh(model)
	end)
end

return MachinePromptController
