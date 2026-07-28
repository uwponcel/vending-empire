--!strict
--[[
	Named interface sounds, in one place.

	Every sound the interface makes is declared here with its volume, so the mix is one table to
	read rather than a Sound instance built inline in whichever controller happened to need it.
	Before this, the collect sound was constructed in HudController and a second one would have
	meant a second copy of the same six lines.

	Every id is a `rbxasset://` built-in, so nothing here depends on an upload and nothing can
	fail to load for a player. All of them were checked in-engine for a non-zero `TimeLength`
	rather than assumed to exist.

	Parented to SoundService, so these play flat at the same volume wherever the player is. That
	is right for interface feedback and wrong for anything diegetic: a sound that should come from
	a machine belongs on the machine's part, not here.
]]

local SoundService = game:GetService("SoundService")

export type Name = "collect" | "purchase"

type Definition = {
	id: string,
	volume: number,
}

local DEFINITIONS: { [Name]: Definition } = {
	--- Short and bright. It fires on the most repeated action in the game, so it has to not grate.
	collect = {
		id = "rbxasset://sounds/electronicpingshort.wav",
		volume = 0.35,
	},
	--[[
		A mechanical clunk, for a vending machine being installed. Louder than collect on purpose:
		buying happens rarely and is the decision worth confirming.
	]]
	purchase = {
		id = "rbxasset://sounds/switch3.wav",
		volume = 0.5,
	},
}

local Sfx = {}

--- Optional value type, because absence is the normal case until a sound is first played.
local cache: { [Name]: Sound? } = {}

--[[
	Its own function so it returns a non-optional Sound.

	Building into the cached local instead leaves it `Sound?` for the analyzer even on the branch
	that just assigned it, and every use afterwards needs a cast.
]]
local function build(name: Name): Sound
	local definition = DEFINITIONS[name]

	local sound = Instance.new("Sound")
	sound.Name = `Sfx_{name}`
	sound.SoundId = definition.id
	sound.Volume = definition.volume
	sound.Parent = SoundService

	return sound
end

--[[
	Plays a named sound, creating it on first use.

	Replaying while already playing restarts from the beginning, which is what a burst of collects
	should sound like. If a sound ever needs to overlap itself, clone it per play instead.
]]
function Sfx.play(name: Name): ()
	local existing = cache[name]
	if existing ~= nil then
		existing:Play()
		return
	end

	local created = build(name)
	cache[name] = created
	created:Play()
end

return Sfx
