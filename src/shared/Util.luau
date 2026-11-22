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

-- Human readable reward text: { Gems = 10, Boost = {"Coins2x", 600} } -> "10 💎 + 2x💰 10m"
-- tr(text, ...) is an optional translator (server: Net:L for the player)
local BOOST_NAMES = {
	Coins2x = "2x Coins",
	Luck2x = "2x Luck",
	Power2x = "2x Power",
}
Util.BoostNames = BOOST_NAMES
local BOOST_ICONS = { Coins2x = "2x💰", Luck2x = "2x🍀", Power2x = "2x💥" }
Util.BoostIcons = BOOST_ICONS

function Util.RewardText(reward, tr): string
	if not reward then
		return ""
	end
	local translate = tr or function(text, ...)
		if select("#", ...) > 0 then
			return string.format(text, ...)
		end
		return text
	end
	local parts = {}
	if reward.Gems then
		table.insert(parts, Util.Format(reward.Gems) .. " 💎")
	end
	if reward.Coins then
		table.insert(parts, Util.Format(reward.Coins) .. " 💰")
	end
	if reward.Stardust then
		table.insert(parts, Util.Format(reward.Stardust) .. " ✨")
	end
	if reward.Boost then
		local icon = BOOST_ICONS[reward.Boost[1]] or reward.Boost[1]
		table.insert(parts, icon .. " " .. translate("%dm", math.floor(reward.Boost[2] / 60)))
	end
	if reward.Pet then
		table.insert(parts, "🐾 " .. translate(reward.Pet))
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

-- true for the experience owner (user-owned) or the group owner (rank 255)
function Util.IsOwner(player: Player): boolean
	if game.CreatorId == 0 then
		return false
	end
	if game.CreatorType == Enum.CreatorType.User then
		return player.UserId == game.CreatorId
	elseif game.CreatorType == Enum.CreatorType.Group then
		local ok, rank = pcall(player.GetRankInGroup, player, game.CreatorId)
		return ok and rank == 255
	end
	return false
end

-- test features (DEV panel, simulated purchases) are allowed in Studio, or
-- for the owner in live servers while Config.OwnerTestMode is on
function Util.CanTest(config, player: Player): boolean
	if game:GetService("RunService"):IsStudio() then
		return true
	end
	return config.OwnerTestMode == true and Util.IsOwner(player)
end

-- XP needed to go from `level` to `level + 1`
function Util.XPForLevel(config, level: number): number
	return math.max(1, math.floor(config.Levels.XPBase * level ^ config.Levels.XPExponent))
end

function Util.VariantDef(config, variant: string?)
	if not variant then
		return nil
	end
	for _, def in config.PetVariants do
		if def.Id == variant then
			return def
		end
	end
	return nil
end

-- pet power including Golden / Rainbow multiplier
function Util.PetPower(config, petName: string, variant: string?): number
	local info = config.Pets[petName]
	if not info then
		return 0
	end
	local def = Util.VariantDef(config, variant)
	return info.Power * (if def then def.PowerMult else 1)
end

function Util.PetDisplayName(petName: string, variant: string?): string
	return if variant then variant .. " " .. petName else petName
end

-- 0 = hub, 1..n = zone index, nil = outside (mirrors WorldService layout)
-- the base district (south of the hub) counts as hub (zone 0)
function Util.InBases(config, position: Vector3): boolean
	local bases = config.World.Bases
	return math.abs(position.X) <= bases.HalfX and position.Z <= bases.ZStart + 8 and position.Z >= bases.ZEnd
end

-- weighted shard rarity roll; luck > 1 shifts weight toward rarer shards
function Util.RollShard(config, luck: number?, rng: Random?, minIndex: number?): string
	local order = config.Shards.Order
	local entries = {}
	for index, id in order do
		if index >= (minIndex or 1) then
			table.insert(entries, { id, config.Shards.Rarities[id].Weight * (luck or 1) ^ ((index - 1) / 2) })
		end
	end
	return Util.WeightedPick(entries, nil, rng)
end

function Util.ShardIndex(config, id: string): number
	return table.find(config.Shards.Order, id) or 1
end

-- coins per second of one shard for an owner at this zone level (before coin multiplier)
function Util.ShardIncome(config, id: string, zoneLevel: number): number
	local def = config.Shards.Rarities[id]
	if not def then
		return 0
	end
	local mult = config.Shards.ZoneMult
	return def.Income * (mult[math.clamp(zoneLevel, 1, #mult)] or 1)
end

function Util.ZoneAt(config, position: Vector3): number?
	local layout = config.World.Layout
	if math.abs(position.X) <= layout.HubHalf and math.abs(position.Z) <= layout.HubHalf then
		return 0
	end
	if Util.InBases(config, position) then
		return 0
	end
	if math.abs(position.X) > layout.ZoneWidth / 2 + 1 then
		return nil
	end
	for index = 1, #config.Zones do
		local zStart = layout.FirstZ + (index - 1) * (layout.ZoneLength + layout.Gap)
		if position.Z >= zStart and position.Z <= zStart + layout.ZoneLength then
			return index
		end
	end
	return nil
end

return Util
