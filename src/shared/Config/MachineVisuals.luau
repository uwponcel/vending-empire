--!strict
--[[
	Cosmetic mesh registry. Data only, zero requires and zero Roblox API usage.

	The natural size is the imported MeshPart bounding box recorded in Studio. `scale`
	is uniform so the authored proportions stay intact. `yawDegrees` normalizes each
	mesh's authored front onto +Z before MachineModel turns it toward the plot spawn.

	The authoritative machine remains the server-built Body part. These assets never
	control placement, collision, prompts, ownership, or economy state.
]]

export type Axis = {
	x: number,
	y: number,
	z: number,
}

export type Visual = {
	meshId: string,
	textureId: string,
	naturalSize: Axis,
	scale: number,
	yawDegrees: number,
	offset: Axis,
}

local ZERO_OFFSET: Axis = {
	x = 0,
	y = 0,
	z = 0,
}

local byId: { [string]: Visual } = {
	drink_water = {
		meshId = "rbxassetid://134541962022801",
		textureId = "rbxassetid://131421470447409",
		naturalSize = { x = 2.5666, y = 8, z = 2.5515 },
		scale = 0.95,
		yawDegrees = 180,
		offset = ZERO_OFFSET,
	},
	drink_soda = {
		meshId = "rbxassetid://103965973868647",
		textureId = "rbxassetid://74931958974390",
		naturalSize = { x = 3.6877, y = 6.2724, z = 3 },
		scale = 1.12,
		yawDegrees = 180,
		offset = ZERO_OFFSET,
	},
	drink_energy = {
		meshId = "rbxassetid://97442694550002",
		textureId = "rbxassetid://80487649859704",
		naturalSize = { x = 3.3065, y = 8, z = 2.0028 },
		scale = 0.95,
		yawDegrees = 180,
		offset = ZERO_OFFSET,
	},
	snack_chips = {
		meshId = "rbxassetid://116305385975270",
		textureId = "rbxassetid://84592344463057",
		naturalSize = { x = 4.1431, y = 6.993, z = 3 },
		scale = 1.03,
		yawDegrees = 180,
		offset = ZERO_OFFSET,
	},
	snack_candy = {
		meshId = "rbxassetid://75776814346420",
		textureId = "rbxassetid://130960672390541",
		naturalSize = { x = 2.8718, y = 7.8857, z = 3 },
		scale = 0.94,
		yawDegrees = 0,
		offset = ZERO_OFFSET,
	},
	snack_sandwich = {
		meshId = "rbxassetid://86397303181534",
		textureId = "rbxassetid://133725079796060",
		naturalSize = { x = 3.3785, y = 6.424, z = 3 },
		scale = 1.1,
		yawDegrees = 180,
		offset = ZERO_OFFSET,
	},
	elec_phone = {
		meshId = "rbxassetid://109034841160005",
		textureId = "rbxassetid://103905763821692",
		naturalSize = { x = 5, y = 3.7355, z = 2.3759 },
		scale = 1.45,
		yawDegrees = 0,
		offset = ZERO_OFFSET,
	},
	elec_console = {
		meshId = "rbxassetid://115892345875122",
		textureId = "rbxassetid://73786209548601",
		naturalSize = { x = 3.9704, y = 5.7624, z = 3 },
		scale = 1.18,
		yawDegrees = 180,
		offset = ZERO_OFFSET,
	},
	elec_drone = {
		meshId = "rbxassetid://138674598214709",
		textureId = "rbxassetid://85346661988459",
		naturalSize = { x = 3.5544, y = 5.2327, z = 3 },
		scale = 1.28,
		yawDegrees = 180,
		offset = ZERO_OFFSET,
	},
}

return {
	byId = byId,
}
