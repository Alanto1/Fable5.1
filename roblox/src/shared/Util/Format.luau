--!nonstrict
-- Format: numbers and durations the way Roblox players expect to read them.

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

-- 1234 -> "1.23K", 999 -> "999", 1500000 -> "1.5M"
function Format.short(n: number): string
	if n ~= n or n == math.huge then
		return "∞"
	end
	local negative = n < 0
	n = math.abs(n)
	if n < 1000 then
		return (negative and "-" or "") .. tostring(math.floor(n))
	end
	local tier = math.min(math.floor(math.log10(n) / 3), #SUFFIXES - 1)
	local scaled = n / (1000 ^ tier)
	local text
	if scaled >= 100 then
		text = string.format("%d", math.floor(scaled))
	elseif scaled >= 10 then
		text = string.format("%.1f", math.floor(scaled * 10) / 10)
	else
		text = string.format("%.2f", math.floor(scaled * 100) / 100)
	end
	text = text:gsub("%.?0+$", "")
	return (negative and "-" or "") .. text .. SUFFIXES[tier + 1]
end

-- 1234567 -> "1,234,567"
function Format.commas(n: number): string
	local text = tostring(math.floor(n))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return formatted
end

-- 65 -> "1:05", 3700 -> "1:01:40"
function Format.clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = seconds // 3600
	local m = (seconds % 3600) // 60
	local s = seconds % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

-- 5400 -> "1h 30m", 90 -> "1m 30s"
function Format.duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	if seconds < 60 then
		return seconds .. "s"
	end
	local d = seconds // 86400
	local h = (seconds % 86400) // 3600
	local m = (seconds % 3600) // 60
	local s = seconds % 60
	if d > 0 then
		return string.format("%dd %dh", d, h)
	elseif h > 0 then
		return string.format("%dh %dm", h, m)
	end
	return string.format("%dm %ds", m, s)
end

function Format.percent(fraction: number, decimals: number?): string
	return string.format("%." .. (decimals or 0) .. "f%%", fraction * 100)
end

-- "1 in 250" style odds from a probability
function Format.odds(probability: number): string
	if probability <= 0 then
		return "1 in ∞"
	end
	return "1 in " .. Format.commas(math.floor(1 / probability + 0.5))
end

return Format
