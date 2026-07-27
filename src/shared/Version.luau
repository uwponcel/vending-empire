--!strict
--[[
	Build identity, readable from both the server and the client.

	This module has zero requires on purpose. Everything under `shared/Lib` and
	`shared/Config` follows that rule so it can be required directly by the Lune
	test runner, which has no Roblox `script` global. See CLAUDE.md.
]]

export type Version = {
	major: number,
	minor: number,
	patch: number,
}

local Version = {
	current = { major = 0, minor = 1, patch = 0 } :: Version,
}

function Version.toString(version: Version): string
	return string.format("%d.%d.%d", version.major, version.minor, version.patch)
end

return Version
