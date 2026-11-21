local Util = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

-- 1234567 -> "1.23M"
function Util.Format(n: number?): string
	local value = tonumber(n) or 0
	local negative = value < 0
	value = math.abs(value)
	local text
	if value < 1000 then
		if value == math.floor(value) then
			text = tostring(math.floor(value))
		else
			text = string.format("%.1f", value)
		end
	else
		local index = 1
		while value >= 1000 and index < #SUFFIXES do
			value /= 1000
			index += 1
		end
		local pattern = if value >= 100 then "%.0f%s" elseif value >= 10 then "%.1f%s" else "%.2f%s"
		text = string.format(pattern, value, SUFFIXES[index])
	end
	return if negative then "-" .. text else text
end

-- 1234567 -> "1,234,567"
function Util.Comma(n: number?): string
	local s = tostring(math.floor(tonumber(n) or 0))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return formatted
end

-- 3725 -> "1h 02m", 125 -> "2:05"
function Util.FormatTime(seconds: number?): string
	local s = math.max(0, math.floor(tonumber(seconds) or 0))
	local days = math.floor(s / 86400)
	local hours = math.floor((s % 86400) / 3600)
	local minutes = math.floor((s % 3600) / 60)
	local secs = s % 60
	if days > 0 then
		return string.format("%dd %02dh", days, hours)
	elseif hours > 0 then
		return string.format("%dh %02dm", hours, minutes)
	end
	return string.format("%d:%02d", minutes, secs)
end

function Util.DeepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = Util.DeepCopy(v)
	end
	return copy
end

-- Fills keys missing from target with copies of template values (in place).
function Util.Reconcile(target, template)
	for key, value in template do
		if target[key] == nil then
			target[key] = Util.DeepCopy(value)
		elseif type(value) == "table" and type(target[key]) == "table" and next(value) ~= nil then
			-- only recurse into dictionaries that define structure
			if #value == 0 then
				Util.Reconcile(target[key], value)
			end
		end
	end
	return target
end

-- entries = { {key, weight}, ... }; weightFn(key, weight) can modify weights (luck)
function Util.WeightedPick(entries, weightFn, rng)
	local total = 0
	local weights = table.create(#entries)
	for i, entry in entries do
		local w = entry[2]
		if weightFn then
			w = weightFn(entry[1], w)
		end
		weights[i] = w
		total += w
	end
	local roll = (if rng then rng:NextNumber() else math.random()) * total
	for i, entry in entries do
		roll -= weights[i]
		if roll <= 0 then
			return entry[1]
		end
	end
	return entries[#entries][1]
end

-- Returns { [key] = percent } for display, after luck is applied.
function Util.Odds(entries, weightFn)
	local total = 0
	local weights = {}
	for i, entry in entries do
		local w = entry[2]
		if weightFn then
			w = weightFn(entry[1], w)
		end
		weights[i] = w
		total += w
	end
	local odds = {}
	for i, entry in entries do
		odds[entry[1]] = if total > 0 then weights[i] / total * 100 else 0
	end
	return odds
end

function Util.FormatPercent(p: number): string
	if p >= 10 then
		return string.format("%.0f%%", p)
	elseif p >= 1 then
		return string.format("%.1f%%", p)
	elseif p >= 0.1 then
		return string.format("%.2f%%", p)
	end
	return string.format("%.3f%%", p)
end

-- Day / week numbers (UTC). Weeks start on Monday 00:00 UTC.
local WEEK_OFFSET = 4 * 86400 -- 1970-01-01 was a Thursday
function Util.DayNumber(t: number?): number
	return math.floor((t or os.time()) / 86400)
end

function Util.WeekNumber(t: number?): number
	return math.floor(((t or os.time()) - WEEK_OFFSET) / 604800)
end

function Util.SecondsUntilNextDay(t: number?): number
	local now = t or os.time()
	return (Util.DayNumber(now) + 1) * 86400 - now
end

function Util.SecondsUntilNextWeek(t: number?): number
	local now = t or os.time()
	return (Util.WeekNumber(now) + 1) * 604800 + WEEK_OFFSET - now
end

-- Human readable reward text: { Gems = 10, Boost = {"Coins2x", 600} } -> "10 Gems, 2x Coins 10:00"
local BOOST_NAMES = {
	Coins2x = "2x Coins",
	Luck2x = "2x Luck",
	Power2x = "2x Power",
}
Util.BoostNames = BOOST_NAMES

function Util.RewardText(reward): string
	if not reward then
		return ""
	end
	local parts = {}
	if reward.Gems then
		table.insert(parts, Util.Format(reward.Gems) .. " 💎")
	end
	if reward.Coins then
		table.insert(parts, Util.Format(reward.Coins) .. " 🪙")
	end
	if reward.Stardust then
		table.insert(parts, Util.Format(reward.Stardust) .. " ✨")
	end
	if reward.Boost then
		local name = BOOST_NAMES[reward.Boost[1]] or reward.Boost[1]
		table.insert(parts, string.format("%s %dm", name, math.floor(reward.Boost[2] / 60)))
	end
	if reward.Pet then
		table.insert(parts, "🐾 " .. reward.Pet)
	end
	return table.concat(parts, " + ")
end

function Util.RebirthCost(config, rebirths: number): number
	return math.floor(config.Rebirth.BaseCost * (rebirths + 1) ^ config.Rebirth.Exponent)
end

function Util.RankFor(config, points: number)
	local index = 1
	for i, rank in config.Ranks do
		if points >= rank.Min then
			index = i
		end
	end
	return config.Ranks[index], index
end

return Util
