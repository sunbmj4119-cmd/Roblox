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

-- coins per second a pet earns on a pedestal (mutation included, before boosts)
function Util.PetIncome(config, petName: string, variant: string?): number
	local info = config.Pets[petName]
	if not info then
		return 0
	end
	local def = Util.VariantDef(config, variant)
	return (info.Income or 0) * (if def then def.IncomeMult or 1 else 1)
end

-- the egg shop restocks every RestockSeconds; slot = which restock we're in
function Util.ShopSlot(config, serverTime: number): number
	return math.floor(serverTime / config.Shop.RestockSeconds)
end

-- seconds until the next restock
function Util.ShopRestockIn(config, serverTime: number): number
	local period = config.Shop.RestockSeconds
	return period - (serverTime % period)
end

-- how many of an egg are in stock this slot (same in every server: seeded).
-- nil = not a restocking egg (always available)
function Util.EggStock(config, eggId: string, slot: number): number?
	local egg = config.Eggs[eggId]
	local rule = egg and egg.Stock
	if not rule then
		return nil
	end
	-- small deterministic hash of (slot, eggId) -> 0..1. Every product stays
	-- below 2^53 so it's exact on every machine (server and phones agree).
	local m = 4294967296
	local h = (slot % 1000003) * 2654435761 % m
	for i = 1, #eggId do
		h = (h * 31 + string.byte(eggId, i)) % m
	end
	for _ = 1, 3 do
		h = (h * 69069 + 1) % m
	end
	local roll = h / m
	if roll >= rule.Chance then
		return 0
	end
	local span = rule.Max - rule.Min + 1
	local pick = math.floor((roll / rule.Chance) * span)
	return rule.Min + math.min(pick, span - 1)
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

---------------------------------------------------------------------------
-- houses (shared by the server, the build mode and the panels)
---------------------------------------------------------------------------
-- territory centers: two rows facing a central avenue (local -Z faces the avenue)
function Util.PlotLayout(config): { { Center: Vector3, Facing: Vector3 } }
	local base = config.Base
	local layout = base.Layout
	local half = base.PlotSize / 2
	local bases = config.World.Bases
	local rows = { -- north row (next to the hub gate) faces south, the far row faces north
		{ Z = bases.ZStart - layout.Margin - half, Facing = Vector3.new(0, 0, -1) },
		{ Z = bases.ZStart - layout.Margin - half * 2 - layout.Avenue - half, Facing = Vector3.new(0, 0, 1) },
	}
	local columns = {}
	local x = layout.EntranceGap / 2 + half
	for _ = 1, layout.Columns / 2 do
		table.insert(columns, -x)
		table.insert(columns, x)
		x += half * 2 + layout.Gap
	end
	table.sort(columns, function(a, b)
		-- nearest to the entrance first
		if math.abs(a) == math.abs(b) then
			return a < b
		end
		return math.abs(a) < math.abs(b)
	end)
	local list = {}
	for _, row in rows do
		for _, cx in columns do
			if #list < base.Plots then
				table.insert(list, { Center = Vector3.new(cx, 0, row.Z), Facing = row.Facing })
			end
		end
	end
	return list
end

-- z of the avenue center line
function Util.AvenueZ(config): number
	local layout = config.Base.Layout
	return config.World.Bases.ZStart - layout.Margin - config.Base.PlotSize - layout.Avenue / 2
end

function Util.HouseLevel(config, data): number
	local level = data and data.Base and tonumber(data.Base.Level) or 1
	return math.clamp(math.floor(level), 1, #config.Base.Levels)
end

function Util.HouseDef(config, level: number)
	return config.Base.Levels[math.clamp(level, 1, #config.Base.Levels)]
end

-- how many vault pedestals this player may own
function Util.VaultLimit(config, data, hasVip: boolean?): number
	return Util.HouseDef(config, Util.HouseLevel(config, data)).Vaults + (if hasVip then config.Base.VipVaults else 0)
end

-- the wall style of a house: its skin, or the style of its level
function Util.HouseStyle(config, data): (string, any)
	local skin = data and data.Base and data.Base.Skin
	if type(skin) == "string" and skin ~= "Auto" and config.HouseStyles[skin] then
		return skin, config.HouseStyles[skin]
	end
	local style = Util.HouseDef(config, Util.HouseLevel(config, data)).Style
	return style, config.HouseStyles[style]
end

function Util.IsExclusive(config, pet): boolean
	local info = pet and config.Pets[pet.Name]
	return info ~= nil and info.Exclusive == true
end

-- pets carry a serial number when they're huge or exclusive
function Util.WantsSerial(config, name: string, variant: string?): boolean
	local info = config.Pets[name]
	local def = Util.VariantDef(config, variant)
	return (info ~= nil and info.Exclusive == true) or (def ~= nil and def.Serial == true)
end

-- total income of every pet you own (used by the fair-stealing rule)
function Util.PetWorth(config, data): number
	local total = 0
	for _, pet in data.Pets do
		total += Util.PetIncome(config, pet.Name, pet.Variant)
	end
	return total
end

-- pedestal + vault items, oldest first (stable order)
function Util.Pedestals(config, items)
	local display, vault = {}, {}
	for _, item in items do
		local def = config.Decor[item.Id]
		if def and def.Function == "Pedestal" then
			table.insert(display, item)
		elseif def and def.Function == "Vault" then
			table.insert(vault, item)
		end
	end
	local function byUid(a, b)
		return a.Uid < b.Uid
	end
	table.sort(display, byUid)
	table.sort(vault, byUid)
	return display, vault
end

-- who stands where. Vaults get your BEST pets (safe by default) unless you
-- marked a pet "show off" (pet.Show = true). Exclusive pets can't be stolen
-- anyway, so they skip the vault and earn full income on display.
-- returns vaultPets, displayPets (same order as the pedestal items)
function Util.ArrangePets(config, data)
	local displayItems, vaultItems = Util.Pedestals(config, data.Base.Items)
	local list = {}
	for _, pet in data.Pets do
		if not pet.Away and config.Pets[pet.Name] then
			table.insert(list, pet)
		end
	end
	table.sort(list, function(a, b)
		local ia = Util.PetIncome(config, a.Name, a.Variant)
		local ib = Util.PetIncome(config, b.Name, b.Variant)
		if ia == ib then
			return a.Id < b.Id
		end
		return ia > ib
	end)
	local vault, display, used = {}, {}, {}
	for _, pet in list do
		if #vault >= #vaultItems then
			break
		end
		-- freshly stolen pets ("hot") can't hide in a vault yet
		local hot = type(pet.HotUntil) == "number" and pet.HotUntil > os.time()
		if not pet.Show and not hot and not Util.IsExclusive(config, pet) then
			table.insert(vault, pet)
			used[pet] = true
		end
	end
	for _, pet in list do
		if #display >= #displayItems then
			break
		end
		if not used[pet] then
			table.insert(display, pet)
		end
	end
	return vault, display
end

-- decoration sets: total income bonus + which sets are complete
function Util.SetBonus(config, items): (number, { [string]: boolean })
	local have = {}
	for _, item in items do
		have[item.Id] = true
	end
	local total, done = 0, {}
	for _, set in config.DecorSets do
		local complete = true
		for _, id in set.Items do
			if not have[id] then
				complete = false
				break
			end
		end
		if complete then
			total += set.Bonus
			done[set.Id] = true
		end
	end
	return total, done
end

-- probability of hatching this exact pet (+ mutation) from an egg, base luck
function Util.HatchChance(config, eggId: string, petName: string, variant: string?): number?
	local egg = config.Eggs[eggId]
	if not egg then
		return nil
	end
	local total, weight = 0, 0
	for _, entry in egg.Pets do
		total += entry[2]
		if entry[1] == petName then
			weight = entry[2]
		end
	end
	if total <= 0 or weight <= 0 then
		return nil
	end
	local chance = weight / total
	local def = Util.VariantDef(config, variant)
	if def and (def.Chance or 0) > 0 then
		chance *= def.Chance
	end
	return chance
end

-- titles: which ones a player has unlocked
function Util.TitleUnlocked(config, title, data, hasPass): boolean
	local need = title.Need or {}
	local stats = data.Stats or {}
	local function count(t)
		local n = 0
		for _ in t or {} do
			n += 1
		end
		return n
	end
	if need.Level and (data.Level or 1) < need.Level then
		return false
	end
	if need.Index and count(data.PetIndex) < need.Index then
		return false
	end
	if need.Steals and (stats.ShardsStolen or 0) < need.Steals then
		return false
	end
	if need.Catches and (stats.ThievesCaught or 0) < need.Catches then
		return false
	end
	if need.HouseLevel and Util.HouseLevel(config, data) < need.HouseLevel then
		return false
	end
	if need.Likes and (data.Base and data.Base.Likes or 0) < need.Likes then
		return false
	end
	if need.Rebirths and (data.Rebirths or 0) < need.Rebirths then
		return false
	end
	if need.Huge and (stats.HugesFound or 0) < need.Huge then
		return false
	end
	if need.LifetimeCoins and (stats.LifetimeCoins or 0) < need.LifetimeCoins then
		return false
	end
	if need.Meteors and (stats.MeteorJoins or 0) < need.Meteors then
		return false
	end
	if need.Delivered and (stats.ShardsDelivered or 0) < need.Delivered then
		return false
	end
	if need.Titanic and (stats.TitanicsFound or 0) < need.Titanic then
		return false
	end
	if need.Pranks and (stats.Pranks or 0) < need.Pranks then
		return false
	end
	if need.Lucky and (stats.LuckyBlocks or 0) < need.Lucky then
		return false
	end
	if need.Pass and not (hasPass and hasPass(need.Pass)) then
		return false
	end
	return true
end

-- the title a player wears: their pick if unlocked, else the best unlocked one
function Util.CurrentTitle(config, data, hasPass)
	local best = config.Titles[1]
	for _, title in config.Titles do
		if Util.TitleUnlocked(config, title, data, hasPass) then
			best = title
			if data.Title == title.Id then
				return title
			end
		end
	end
	-- nothing picked (or the pick isn't unlocked any more): the best one
	return best
end

return Util
