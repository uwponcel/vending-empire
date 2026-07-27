--!strict
--[[
	A one-function declarative Instance builder, for UI written in code.

	UI is generated rather than authored in Studio so it lives in git as text. A `.rbxmx`
	blob cannot be reviewed, cannot be diffed, and cannot be merged, which for the layer
	that changes most often is the wrong trade in every direction.

	No Fusion and no Roact in V1. Both are good, and both are a dependency plus a reactive
	model to learn before there is any UI complex enough to need one. Revisit around Phase 4
	if the plain builder starts fighting back; until then this is 30 lines with no upstream.

	THE ONE UNCHECKED SPOT IN THE PROJECT. Property names are strings in a table, so a typo
	is a runtime error rather than a type error, and the property values are `any`. That is
	unavoidable without a per-class typed overload for every Roblox class. It is confined to
	this file on purpose, and the error Roblox raises names both the class and the property,
	so a typo fails immediately and legibly on first render rather than silently.
]]

export type Props = { [string]: any }

--[[
	Creates an instance, assigns properties, parents children, then parents itself.

	`Parent` is applied after the children rather than with the other properties. Parenting
	a UI element before its contents exist makes the engine lay out the tree twice, and on a
	panel built in a loop that shows up as a visible pop-in.
]]
local function create(className: string, props: Props, children: { Instance }?): Instance
	local instance = Instance.new(className)

	for key, value in props do
		if key ~= "Parent" then
			(instance :: any)[key] = value
		end
	end

	if children then
		for _, child in children do
			child.Parent = instance
		end
	end

	if props.Parent ~= nil then
		instance.Parent = props.Parent
	end

	return instance
end

return create
