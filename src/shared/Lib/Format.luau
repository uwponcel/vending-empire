--!strict
--[[
	Display formatting. Pure, zero requires.

	Every function here truncates rather than rounds. For a currency that is the
	correct direction: a player who owns 1999 coins should never see "2K" and then
	find they cannot afford a 2000 coin machine. Showing slightly less than the truth
	is always safe; showing slightly more produces a bug report.
]]

local Format = {}

--- Suffix per 1000x step. Stops at Dc (1e33), far past anything a V1 balance can
--- reach, and past the 2^53 point where float64 stops holding exact integers anyway.
local SUFFIXES = {
	"",
	"K",
	"M",
	"B",
	"T",
	"Qa",
	"Qi",
	"Sx",
	"Sp",
	"Oc",
	"No",
	"Dc",
}

--[[
	Parallel to SUFFIXES. Written as literals rather than computed with `1000 ^ n`
	because pow can land a bit off the corresponding literal, and an off-by-one-ULP
	threshold puts exact boundary values in the wrong bucket.

	Dividing repeatedly by 1000 instead of once by a threshold has the same problem
	from the other direction: the error compounds per step, so 1e33 walks down to
	999.99... and renders as "999No" rather than "1Dc".
]]
local THRESHOLDS = {
	1,
	1e3,
	1e6,
	1e9,
	1e12,
	1e15,
	1e18,
	1e21,
	1e24,
	1e27,
	1e30,
	1e33,
}

--- Truncates toward zero at `places` decimals, then strips trailing zeros and any
--- orphaned decimal point, so 1.00 renders as "1" and 1.20 renders as "1.2".
local function truncateToString(value: number, places: number): string
	local scale = 10 ^ places
	local truncated = math.floor(value * scale) / scale
	local text = string.format(`%.{places}f`, truncated)

	if string.find(text, "%.") then
		text = string.gsub(text, "0+$", "")
		text = string.gsub(text, "%.$", "")
	end

	return text
end

--[[
	Compact currency display: 1234 -> "1.23K", 12345 -> "12.3K", 123456 -> "123K".

	Holds three significant digits so the width stays roughly stable in a HUD, which
	matters more than precision for a number that changes every second.
]]
function Format.short(value: number): string
	local sign = if value < 0 then "-" else ""
	local magnitude = math.abs(value)

	if magnitude < 1000 then
		return sign .. tostring(math.floor(magnitude))
	end

	-- Pick the bucket by comparison, then divide exactly once. Anything at or above the
	-- largest threshold stays in the last bucket and simply renders a bigger mantissa,
	-- so a runaway value reads as "1000Dc" instead of indexing past the table.
	local index = 1
	while index < #THRESHOLDS and magnitude >= THRESHOLDS[index + 1] do
		index += 1
	end

	local scaled = magnitude / THRESHOLDS[index]
	local places = if scaled < 10 then 2 elseif scaled < 100 then 1 else 0
	return sign .. truncateToString(scaled, places) .. SUFFIXES[index]
end

--[[
	Exact display with thousands separators, for tooltips and confirmation dialogs
	where the player is about to spend and needs the real number.
]]
function Format.comma(value: number): string
	local sign = if value < 0 then "-" else ""
	local digits = tostring(math.floor(math.abs(value)))

	local grouped = digits
	while true do
		local replaced: string, count: number = string.gsub(grouped, "^(%d+)(%d%d%d)", "%1,%2")
		grouped = replaced
		if count == 0 then
			break
		end
	end

	return sign .. grouped
end

--[[
	Short duration, for "full in 2m 30s" on a machine billboard.

	Shows at most two units, because a third is noise at a glance. Anything at or
	below zero reads "0s" rather than a negative, since the only way to get a negative
	here is clock skew and a player should never see it.
]]
function Format.duration(seconds: number): string
	if seconds <= 0 then
		return "0s"
	end

	local total = math.floor(seconds)

	local days = total // 86400
	local hours = (total % 86400) // 3600
	local minutes = (total % 3600) // 60
	local secs = total % 60

	if days > 0 then
		return if hours > 0 then `{days}d {hours}h` else `{days}d`
	end
	if hours > 0 then
		return if minutes > 0 then `{hours}h {minutes}m` else `{hours}h`
	end
	if minutes > 0 then
		return if secs > 0 then `{minutes}m {secs}s` else `{minutes}m`
	end
	return `{secs}s`
end

return Format
