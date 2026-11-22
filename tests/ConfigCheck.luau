--[[
	Config sanity test - run with Lune (https://lune-org.github.io/docs):
	    lune run tests/ConfigCheck.luau

	Loads src/shared/Config.luau + Util.luau outside Roblox (with Roblox
	datatypes from @lune/roblox) and checks that every reference in the
	config points at something that exists, so a typo in a pet/ore/product
	name is caught before you publish.
]]
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local process = require("@lune/process")

local env = {
	Color3 = roblox.Color3,
	Vector3 = roblox.Vector3,
	Vector2 = roblox.Vector2,
	CFrame = roblox.CFrame,
	UDim2 = roblox.UDim2,
	Enum = roblox.Enum,
}

local function load(path: string, extraEnv)
	local source = fs.readFile(path)
	local chunkEnv = table.clone(env)
	for k, v in extraEnv or {} do
		chunkEnv[k] = v
	end
	return luau.load(source, { debugName = path, environment = chunkEnv })()
end

local Config = load("src/shared/Config.luau")
local Util = load("src/shared/Util.luau")

local failures = 0
local function check(condition: any, message: string)
	if not condition then
		failures += 1
		print("❌ " .. message)
	end
end

local BOOSTS = { Coins2x = true, Luck2x = true, Power2x = true }
local QUEST_TYPES = {
	MineBlocks = true,
	Sell = true,
	Hatch = true,
	MeteorJoin = true,
	MeteorTop3 = true,
	Bonk = true,
	PlayMinutes = true,
	Upgrade = true,
}
local PRODUCT_KINDS = {
	Gems = true,
	CoinPack = true,
	Boost = true,
	ServerBoost = true,
	SummonMeteor = true,
	SeasonPremium = true,
	SkipTiers = true,
	StarterPack = true,
	PaidEgg = true,
}

local function checkReward(reward, where: string)
	check(type(reward) == "table", where .. ": reward missing")
	if type(reward) ~= "table" then
		return
	end
	if reward.Pet then
		check(Config.Pets[reward.Pet] ~= nil, where .. ": unknown pet " .. tostring(reward.Pet))
	end
	if reward.Boost then
		check(BOOSTS[reward.Boost[1]], where .. ": unknown boost " .. tostring(reward.Boost[1]))
		check(type(reward.Boost[2]) == "number" and reward.Boost[2] > 0, where .. ": bad boost seconds")
	end
	check(Util.RewardText(reward) ~= "", where .. ": empty reward")
end

-- pets
for name, pet in Config.Pets do
	check(Config.Rarities[pet.Rarity] ~= nil, "pet " .. name .. " has unknown rarity " .. tostring(pet.Rarity))
	check(type(pet.Power) == "number" and pet.Power > 0, "pet " .. name .. " needs Power > 0")
end

-- zones & ores
for index, zone in Config.Zones do
	check(Config.PointsPerBlock[index] ~= nil, "PointsPerBlock missing for zone " .. index)
	for _, entry in zone.Ores do
		check(Config.Ores[entry[1]] ~= nil, "zone " .. zone.Name .. " uses unknown ore " .. entry[1])
	end
	if index > 1 then
		check(zone.Cost > Config.Zones[index - 1].Cost, "zone costs must increase (" .. zone.Name .. ")")
	end
end

-- eggs
for _, id in Config.EggOrder do
	check(Config.Eggs[id] ~= nil, "EggOrder has unknown egg " .. id)
end
for id, egg in Config.Eggs do
	check(table.find(Config.EggOrder, id) ~= nil, "egg " .. id .. " missing from EggOrder")
	check(Config.Zones[egg.Zone] ~= nil, "egg " .. id .. " has invalid zone")
	local total = 0
	for _, entry in egg.Pets do
		check(Config.Pets[entry[1]] ~= nil, "egg " .. id .. " has unknown pet " .. entry[1])
		total += entry[2]
	end
	check(math.abs(total - 100) < 0.001, string.format("egg %s weights sum to %.3f (expected 100)", id, total))
	if egg.Currency == "Robux" then
		for _, key in { egg.ProductSingle, egg.ProductTriple } do
			local product = Config.Products[key]
			check(
				product ~= nil and product.Kind == "PaidEgg" and product.Egg == id,
				"egg " .. id .. " product " .. tostring(key) .. " invalid"
			)
		end
	else
		check(egg.Currency == "Coins" or egg.Currency == "Gems" or egg.Currency == "Stardust", "egg " .. id .. " bad currency")
		check(type(egg.Price) == "number", "egg " .. id .. " needs a Price")
	end
end

-- monetization
for _, key in Config.GamePassOrder do
	check(Config.GamePasses[key] ~= nil, "GamePassOrder has unknown pass " .. key)
end
for key in Config.GamePasses do
	check(table.find(Config.GamePassOrder, key) ~= nil, "pass " .. key .. " missing from GamePassOrder")
end
for _, key in Config.StoreOrder do
	check(Config.Products[key] ~= nil, "StoreOrder has unknown product " .. key)
end
for key, product in Config.Products do
	check(PRODUCT_KINDS[product.Kind], "product " .. key .. " has unknown Kind " .. tostring(product.Kind))
	if product.Kind == "Boost" or product.Kind == "ServerBoost" then
		check(BOOSTS[product.Boost] or product.Boost == "ServerLuck", "product " .. key .. " unknown boost")
	end
	if product.Kind == "PaidEgg" then
		check(Config.Eggs[product.Egg] ~= nil, "product " .. key .. " unknown egg")
	end
end
checkReward(Config.StarterPack.Reward, "StarterPack")

-- upgrades
for _, list in { "Pickaxes", "Backpacks" } do
	for tier = 2, #Config[list] do
		check(Config[list][tier].Cost > Config[list][tier - 1].Cost, list .. " costs must increase at tier " .. tier)
	end
end

-- retention
for i, reward in Config.DailyRewards do
	checkReward(reward, "DailyRewards[" .. i .. "]")
end
for i, gift in Config.PlaytimeGifts do
	checkReward(gift.Reward, "PlaytimeGifts[" .. i .. "]")
	if i > 1 then
		check(gift.Minutes > Config.PlaytimeGifts[i - 1].Minutes, "PlaytimeGifts minutes must increase")
	end
end
local questIds = {}
for _, quest in Config.Quests do
	check(QUEST_TYPES[quest.Type], "quest " .. quest.Id .. " unknown type " .. tostring(quest.Type))
	check(not questIds[quest.Id], "duplicate quest id " .. quest.Id)
	questIds[quest.Id] = true
	checkReward(quest.Reward, "quest " .. quest.Id)
end
check(#Config.Quests >= Config.DailyQuestCount, "need at least DailyQuestCount quests")
for tier = 1, #Config.SeasonTiers do
	local def = Config.SeasonTiers[tier]
	check(def ~= nil, "season tier " .. tier .. " missing")
	if def then
		checkReward(def.Free, "SeasonTiers[" .. tier .. "].Free")
		checkReward(def.Premium, "SeasonTiers[" .. tier .. "].Premium")
	end
end
-- new systems: spin, codes, events, variants, lucky ores, sounds
local spinWeight = 0
for i, entry in Config.Spin.Rewards do
	checkReward(entry.Reward, "Spin.Rewards[" .. i .. "]")
	check(type(entry.Weight) == "number" and entry.Weight > 0, "Spin weight must be > 0")
	spinWeight += entry.Weight
end
check(spinWeight > 0, "Spin needs rewards")
for code, def in Config.Codes do
	check(code == string.upper(code), "code " .. code .. " must be UPPERCASE")
	checkReward(def.Reward, "Codes." .. code)
end
for _, def in Config.Events.List do
	check(type(def.Id) == "string" and type(def.Name) == "string" and def.Description, "event needs Id/Name/Description")
end
for _, def in Config.PetVariants do
	check(def.Chance > 0 and def.Chance < 1 and def.PowerMult > 1, "bad pet variant " .. tostring(def.Id))
end
for _, def in Config.LuckyOres do
	check(def.Chance > 0 and def.Chance < 1 and def.ValueMult > 1, "bad lucky ore " .. tostring(def.Id))
end
for name, def in Config.Sounds do
	check(type(def) == "table" and type(def.Ids) == "table" and #def.Ids > 0, "sound " .. name .. " needs Ids")
end
check(Util.XPForLevel(Config, 1) >= 1 and Util.XPForLevel(Config, 50) > Util.XPForLevel(Config, 10), "XP curve must grow")
check(Util.PetPower(Config, "Fox", "Golden") > Util.PetPower(Config, "Fox", nil), "golden pets must be stronger")
check(Util.ZoneAt(Config, roblox.Vector3.new(0, 3, -60)) == 0, "spawn must be in the hub")
check(Util.ZoneAt(Config, roblox.Vector3.new(0, 3, Config.World.Layout.FirstZ + 20)) == 1, "zone 1 detection")

for i = 2, #Config.Ranks do
	check(Config.Ranks[i].Min > Config.Ranks[i - 1].Min, "rank thresholds must increase")
end

-- util
check(Util.Format(999) == "999", "Format 999 -> " .. Util.Format(999))
check(Util.Format(1500) == "1.50K", "Format 1500 -> " .. Util.Format(1500))
check(Util.Format(2500000) == "2.50M", "Format 2.5M -> " .. Util.Format(2500000))
check(Util.Comma(1234567) == "1,234,567", "Comma -> " .. Util.Comma(1234567))
check(Util.FormatTime(125) == "2:05", "FormatTime 125 -> " .. Util.FormatTime(125))
check(Util.FormatTime(3725) == "1h 02m", "FormatTime 3725 -> " .. Util.FormatTime(3725))
-- 2026-11-23 is a Monday: week number must change exactly at 00:00 UTC
local monday = 1795392000 -- 2026-11-23T00:00:00Z
check(Util.WeekNumber(monday) == Util.WeekNumber(monday - 1) + 1, "week must roll over on Monday 00:00 UTC")
check(Util.WeekNumber(monday + 6 * 86400) == Util.WeekNumber(monday), "week must last 7 days")
check(Util.SecondsUntilNextWeek(monday) == 604800, "SecondsUntilNextWeek at Monday 00:00")

local odds = Util.Odds(Config.Eggs.Meadow.Pets)
local sum = 0
for _, p in odds do
	sum += p
end
check(math.abs(sum - 100) < 0.001, "odds must sum to 100")

-- luck should raise rare odds and lower common odds
local luckFn = function(name, weight)
	if Config.Rarities[Config.Pets[name].Rarity].Order >= Config.LuckAffectsFromRarity then
		return weight * 3
	end
	return weight
end
local lucky = Util.Odds(Config.Eggs.Meadow.Pets, luckFn)
check(lucky["Golden Bunny"] > odds["Golden Bunny"], "luck must raise legendary odds")
check(lucky.Bunny < odds.Bunny, "luck must lower common odds")

local counts = {}
math.randomseed(42)
for _ = 1, 20000 do
	local name = Util.WeightedPick(Config.Eggs.Meadow.Pets, nil)
	counts[name] = (counts[name] or 0) + 1
end
check(math.abs(counts.Bunny / 20000 - 0.40) < 0.02, "WeightedPick distribution off: Bunny " .. tostring(counts.Bunny))

-- tutorial: valid steps, and a brand-new player (0 coins) can always afford
-- the pickaxe and the first egg from the step rewards alone (no dead end)
local TUTORIAL_EVENTS = { Mine = true, Sell = true, Pickaxe = true, Hatch = true }
for i, step in Config.Tutorial.Steps do
	check(TUTORIAL_EVENTS[step.Id] == true, "tutorial step " .. i .. " has unknown Id " .. tostring(step.Id))
	check(type(step.Target) == "number" and step.Target >= 1, "tutorial step " .. i .. " bad Target")
	check(type(step.Text) == "string" and step.Text ~= "", "tutorial step " .. i .. " missing Text")
	checkReward(step.Reward, "tutorial step " .. i)
end
checkReward(Config.Tutorial.FinalReward, "tutorial final reward")
do
	local coins = 0
	for _, step in Config.Tutorial.Steps do
		if step.Id == "Pickaxe" then
			check(coins >= Config.Pickaxes[2].Cost, "tutorial: can't afford the 2nd pickaxe at its step")
			coins -= Config.Pickaxes[2].Cost
		elseif step.Id == "Hatch" then
			local egg = Config.Eggs[Config.EggOrder[1]]
			check(egg.Currency ~= "Coins" or coins >= egg.Price, "tutorial: can't afford the first egg at its step")
		end
		coins += step.Reward.Coins or 0
	end
end

-- economy pacing printout
local costs = {}
for r = 0, 9 do
	table.insert(costs, string.format("R%d %s", r + 1, Util.Format(Util.RebirthCost(Config, r))))
end
print("Rebirth costs: " .. table.concat(costs, "  "))

if failures > 0 then
	print(string.format("\n%d config check(s) FAILED", failures))
	process.exit(1)
end
print("✅ All config checks passed")
