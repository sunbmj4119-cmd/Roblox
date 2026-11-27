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
local Vector3 = roblox.Vector3

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
	Collect = true,
	Hatch = true,
	MeteorJoin = true,
	MeteorTop3 = true,
	Bonk = true,
	PlayMinutes = true,
	Upgrade = true,
	Shard = true,
	Steal = true,
	Decorate = true,
	Like = true,
}
local PRODUCT_KINDS = {
	HouseSkin = true,
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
	check(type(pet.Income) == "number" and pet.Income > 0, "pet " .. name .. " needs Income > 0")
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
for _, list in { "Pickaxes" } do
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
local EVENT_IDS = {}
for _, event in Config.Events.List do
	EVENT_IDS[event.Id] = true
end
for _, def in Config.PetVariants do
	local chance = math.max(def.Chance or 0, def.EventChance or 0)
	check(chance > 0 and chance < 1 and def.PowerMult > 1, "bad pet variant " .. tostring(def.Id))
	check(type(def.IncomeMult) == "number" and def.IncomeMult > 1, "variant " .. tostring(def.Id) .. " needs IncomeMult > 1")
	check(def.Event == nil or EVENT_IDS[def.Event], "variant " .. tostring(def.Id) .. " uses unknown event " .. tostring(def.Event))
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
-- egg shop: stock is deterministic, in range, and coin eggs pay back in minutes
for _, zoneEgg in Config.Shards.ZoneEggs do
	check(Config.Eggs[zoneEgg] ~= nil, "Shards.ZoneEggs has unknown egg " .. zoneEgg)
end
check(#Config.Shards.ZoneEggs == #Config.Zones, "Shards.ZoneEggs needs one egg per zone")
for eggId, egg in Config.Eggs do
	if egg.Stock then
		check(egg.Currency == "Coins", "only coin eggs restock (" .. eggId .. ")")
		local inStock, minSeen, maxSeen = 0, math.huge, 0
		for slot = 5000000, 5000999 do
			local stock = Util.EggStock(Config, eggId, slot)
			check(stock == Util.EggStock(Config, eggId, slot), "stock not deterministic for " .. eggId)
			if stock > 0 then
				inStock += 1
				minSeen = math.min(minSeen, stock)
				maxSeen = math.max(maxSeen, stock)
			end
		end
		local share = inStock / 1000
		check(math.abs(share - egg.Stock.Chance) < 0.08, string.format("%s in stock %.2f vs Chance %.2f", eggId, share, egg.Stock.Chance))
		check(minSeen >= egg.Stock.Min and maxSeen <= egg.Stock.Max, eggId .. " stock outside Min/Max")
		-- expected income of one hatch vs price: payback should be a few minutes
		local total, expected = 0, 0
		for _, entry in egg.Pets do
			total += entry[2]
		end
		for _, entry in egg.Pets do
			expected += Config.Pets[entry[1]].Income * entry[2] / total
		end
		local payback = egg.Price / expected
		check(payback > 60 and payback < 900, string.format("%s payback %.0fs is off (60-900s)", eggId, payback))
		print(
			string.format(
				"Egg %-7s price %-9s EV income %8.1f/s  payback %4.0fs  in stock %2.0f%%",
				eggId,
				Util.Format(egg.Price),
				expected,
				payback,
				share * 100
			)
		)
	else
		check(Util.EggStock(Config, eggId, 1) == nil, eggId .. " has no stock rule but returned stock")
	end
end
check(Util.PetIncome(Config, "Fox", "Golden") > Util.PetIncome(Config, "Fox", nil), "golden pets must earn more")
check(Util.ShopRestockIn(Config, 600) == Config.Shop.RestockSeconds, "restock timer wrong at slot start")

local TUTORIAL_EVENTS = { Meteor = true, Grab = true, Mine = true, Pickaxe = true, Hatch = true, Shard = true }
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

-- ☄️ meteor rush
do
	local m = Config.Meteor
	check(m.Tutorial ~= nil and m.Tutorial.Hits >= 3, "meteor tutorial needs a few hits")
	check(Config.Tutorial.Steps[1].Id == "Meteor", "the tutorial must start with the meteor")
	check(#m.Kinds == #Config.Zones, "Meteor.Kinds needs one kind per zone")
	for index, kind in m.Kinds do
		check(Config.Eggs[kind.Egg] ~= nil, "meteor kind " .. index .. " has unknown egg " .. tostring(kind.Egg))
		check(kind.Color ~= nil and kind.Icon ~= nil and kind.Name ~= nil, "meteor kind " .. index .. " incomplete")
	end
	local siteWeight = 0
	for _, site in m.Sites do
		check(site.Kind == "Hub" or site.Kind == "Avenue" or site.Kind == "Zone", "bad meteor site " .. tostring(site.Kind))
		siteWeight += site.Weight
	end
	check(siteWeight > 0, "meteor sites need weight")
	check(#m.HubSpots >= 3 and #m.AvenueX >= 3, "meteor needs several hub / avenue spots")
	for _, size in m.Sizes do
		check(size.Radius >= 5 and size.Radius <= 14, "meteor size " .. size.Id .. " radius out of range")
		check(size.HP > 0 and size.Eggs >= 0, "meteor size " .. size.Id .. " bad HP / eggs")
	end
	check(m.GoldenChance > 0 and m.GoldenChance < 0.3, "golden meteor chance out of range")
	check(m.Spill.Base + m.Spill.PerParticipant >= 3, "a meteor must spill a few eggs even with one player")
	check(m.Chunks.Count >= 1 and m.Chunks.Min > 0, "meteor coin chunks")
	-- avenue sites sit between the two rows of homes, inside the base district
	local z = Util.AvenueZ(Config)
	for _, x in m.AvenueX do
		check(Util.InBases(Config, Vector3.new(x, 3, z)), "avenue meteor spot x=" .. x .. " is outside the base district")
		check(Util.ZoneAt(Config, Vector3.new(x, 3, z)) == 0, "avenue meteor spot x=" .. x .. " is inside a mine")
	end
	for _, spot in m.HubSpots do
		check(Util.ZoneAt(Config, spot + Vector3.new(0, 3, 0)) == 0, "hub meteor spot inside a mine")
		check(not Util.InBases(Config, spot + Vector3.new(0, 3, 0)), "hub meteor spot inside the base district")
	end
	local cycle = m.IntervalSeconds + m.WarningSeconds + m.DurationSeconds
	print(
		string.format(
			"Meteor cycle: max %ds (rest %ds + warning %ds + smash <= %ds)",
			cycle,
			m.IntervalSeconds,
			m.WarningSeconds,
			m.DurationSeconds
		)
	)
	check(cycle <= 240, "a meteor round should come at least every 4 minutes")
	local raid = nil
	for _, event in Config.Events.List do
		if event.Raid then
			raid = event
		end
	end
	check(raid ~= nil and raid.NoRandom == true and (raid.Warn or 0) >= 10, "Thief Night must be a warned, scheduled raid event")
	check(Config.Events.RaidEvery >= 2, "raids must not be every event")
end

-- 🌱 growth / 📖 index / ☄️ meteor pets / rivals
do
	local growth = Config.Growth
	check(growth.MaxLevel >= 5 and growth.LevelBonus > 0, "growth levels")
	local last = 0
	for _, stage in growth.Stages do
		check(stage.Min > last and stage.Scale > 0, "growth stages must go up")
		last = stage.Min
	end
	check(growth.Evolve.Copies >= 1 and growth.Evolve.MaxStars >= 1 and growth.Evolve.StarMult > 1, "evolve settings")
	check(#growth.StarColors >= growth.Evolve.MaxStars, "a star colour per star")
	local need = Util.PetXPNeed(Config, { Name = "Bunny", Level = 1 })
	local needTop = Util.PetXPNeed(Config, { Name = "Black Hole Kitty", Level = growth.MaxLevel - 1 })
	check(need > 0 and needTop > need, "xp needs must grow with level and rarity")
	local cost, xp = Util.PetFeed(Config, { Name = "Bunny", Level = 1 })
	check(cost > 0 and xp > 0, "feeding cost")
	local total = 0
	for level = 1, growth.MaxLevel - 1 do
		total += Util.PetXPNeed(Config, { Name = "Fox", Level = level })
	end
	print(
		string.format(
			"Growth: a Rare pet needs %d xp for Lv%d (~%d min of pet help)",
			total,
			growth.MaxLevel,
			math.floor(total / (growth.HelpXP / Config.PetHelp.Interval * 60))
		)
	)
	local lastCount = 0
	for _, milestone in Config.Index.Milestones do
		check(milestone.Count > lastCount and (milestone.Gems or 0) >= 0, "index milestones must go up")
		lastCount = milestone.Count
	end
	local petCount = 0
	for _ in Config.Pets do
		petCount += 1
	end
	check(lastCount <= petCount, "the last index milestone needs more pets than exist")
	check(#Config.Meteor.MeteorPets == #Config.Meteor.Kinds, "one meteor pet per meteor kind")
	for _, name in Config.Meteor.MeteorPets do
		check(Config.Pets[name] ~= nil and Config.Pets[name].Meteor == true, "meteor pet " .. name .. " missing")
	end
	for id in Config.Meteor.MeteorPetChance do
		check(Config.Shards.Rarities[id] ~= nil, "meteor pet chance for unknown star egg " .. id)
	end
	local look = Config.Rivals.Look
	check(#look.Hair > 0 and #look.Shirts > 0 and #look.Pants > 0 and #look.Skins > 0, "rival looks")
	check(#Config.Rivals.Names >= Config.Rivals.Count * 2, "enough rival names")
end

-- star shards + bases
do
	local shards = Config.Shards
	check(#shards.ZoneMult == #Config.Zones, "Shards.ZoneMult needs one entry per zone")
	check(#shards.Points == #shards.Order, "Shards.Points needs one entry per rarity")
	for index, id in shards.Order do
		local def = shards.Rarities[id]
		check(def ~= nil, "shard rarity " .. id .. " missing")
		if def then
			check(type(def.Name) == "string" and def.Name ~= "", "shard " .. id .. " missing Name")
			check(def.Income > 0 and def.Weight > 0, "shard " .. id .. " bad Income/Weight")
			check(def.Speed > 0.3 and def.Speed <= 1, "shard " .. id .. " Speed out of range")
			local prev = shards.Rarities[shards.Order[index - 1] or ""]
			if prev then
				check(def.Income > prev.Income, "shard " .. id .. " should earn more than " .. shards.Order[index - 1])
				check(def.Weight < prev.Weight, "shard " .. id .. " should be rarer than " .. shards.Order[index - 1])
			end
		end
	end
	local base = Config.Base
	check(#base.PedestalCosts == base.MaxPedestals, "Base.PedestalCosts needs MaxPedestals entries")
	local district = Config.World.Bases
	local half = base.PlotSize / 2
	-- territories: inside the district, no overlap, a clear lane from the gate
	local layout = Util.PlotLayout(Config)
	check(#layout == base.Plots, "PlotLayout must place every plot")
	for i, spot in layout do
		local c = spot.Center
		check(math.abs(c.X) + half + 2 <= district.HalfX, "plot " .. i .. " sticks out of the district (HalfX)")
		check(c.Z + half <= district.ZStart and c.Z - half >= district.ZEnd, "plot " .. i .. " sticks out of the district (Z)")
		check(math.abs(c.X) - half >= 18, "plot " .. i .. " blocks the entrance lane")
		for j = i + 1, #layout do
			local o = layout[j].Center
			local apart = math.abs(c.X - o.X) >= base.PlotSize + 10 or math.abs(c.Z - o.Z) >= base.PlotSize + 10
			check(apart, string.format("plots %d and %d are too close (need room for gardens)", i, j))
		end
	end
	-- house levels: every level bigger than the last and inside the walls
	local prevArea, prevItems = 0, 0
	for level, def in base.Levels do
		local b = def.Build
		check(b.MinX >= -half + 2 and b.MaxX <= half - 2 and b.MaxZ <= half - 2, "level " .. level .. " build area hits the walls")
		check(b.MinZ >= -half + 9, "level " .. level .. " build area covers the collect/lock pads")
		local area = (b.MaxX - b.MinX) * (b.MaxZ - b.MinZ)
		check(area > prevArea and def.MaxItems > prevItems, "level " .. level .. " must be bigger than the one before")
		check(def.Vaults >= 1 and def.Vaults <= #base.VaultCosts, "level " .. level .. " vault count out of range")
		check(Config.HouseStyles[def.Style] ~= nil, "level " .. level .. " has unknown Style " .. tostring(def.Style))
		check(level == 1 or def.Cost > base.Levels[level - 1].Cost, "level " .. level .. " must cost more")
		prevArea, prevItems = area, def.MaxItems
	end
	check(base.Levels[1].Cost == 0, "house level 1 must be free")
	for _, skin in Config.HouseSkins do
		check(skin.Id == "Auto" or Config.HouseStyles[skin.Id] ~= nil, "skin " .. skin.Id .. " has no HouseStyle")
		if skin.Product then
			check(
				Config.Products[skin.Product] and Config.Products[skin.Product].Kind == "HouseSkin",
				"skin " .. skin.Id .. " product missing"
			)
		end
		if skin.Pass then
			check(Config.GamePasses[skin.Pass] ~= nil, "skin " .. skin.Id .. " pass missing")
		end
	end
	for _, set in Config.DecorSets do
		for _, id in set.Items do
			check(Config.Decor[id] ~= nil, "decor set " .. set.Id .. " lists unknown item " .. id)
		end
		check(set.Bonus > 0 and set.Bonus <= 0.2, "decor set " .. set.Id .. " bonus out of range")
	end
	local seenTitles = {}
	for _, title in Config.Titles do
		check(not seenTitles[title.Id], "duplicate title " .. title.Id)
		seenTitles[title.Id] = true
		check(typeof(title.Color) == "Color3" and type(title.Need) == "table", "title " .. title.Id .. " needs Color + Need")
	end
	check(#Config.Paint >= 6, "Config.Paint needs colours")
	-- decorations: every catalog item has a model, a valid category and fits the build area
	local DecorModel = load("src/shared/DecorModel.luau")
	local categories = {}
	for _, cat in Config.DecorCategories do
		categories[cat.Id] = true
	end
	local listed = {}
	for _, id in Config.DecorOrder do
		listed[id] = true
		check(Config.Decor[id] ~= nil, "DecorOrder lists unknown item " .. id)
	end
	for id, def in Config.Decor do
		check(listed[id] == true, "decor " .. id .. " missing from DecorOrder")
		check(categories[def.Category] == true, "decor " .. id .. " has unknown category")
		check(DecorModel.Has(id), "decor " .. id .. " has no model builder")
		check(type(def.Size) == "table" and def.Size[1] >= 1 and def.Size[2] >= 1, "decor " .. id .. " bad Size")
		check(
			(def.Price ~= nil) ~= (def.Gems ~= nil) or def.Function == "Pedestal" or def.Function == "Vault",
			"decor " .. id .. " needs Price or Gems"
		)
	end
	-- the starter layout is valid and placement rules work
	local items = {}
	for i, entry in Config.StarterBase do
		local x, z = DecorModel.Snap(Config, entry.Id, entry.X, entry.Z, entry.R)
		local ok, reason = DecorModel.Validate(Config, items, entry.Id, x, z, entry.R, nil, { Level = 1 })
		check(ok, "StarterBase item " .. i .. " (" .. entry.Id .. ") invalid: " .. tostring(reason))
		table.insert(items, { Uid = i, Id = entry.Id, X = x, Z = z, R = entry.R })
	end
	local first = items[1]
	check(not DecorModel.Validate(Config, items, first.Id, first.X, first.Z, 0, nil), "overlap not detected")
	check(DecorModel.Validate(Config, items, first.Id, first.X, first.Z, 0, first.Uid), "moving onto itself should be allowed")
	check(not DecorModel.Validate(Config, items, "Tree", 999, 0, 0, nil), "out of bounds not detected")
	-- bigger houses have more room; level-locked items stay locked
	check(not DecorModel.Validate(Config, items, "Tree", 26, 0, 0, nil, { Level = 1 }), "level 1 should not reach x=26")
	check(DecorModel.Validate(Config, items, "Tree", 26, 0, 0, nil, { Level = 5 }), "level 5 should reach x=26")
	check(not DecorModel.Validate(Config, items, "Windmill", -10, -14, 0, nil, { Level = 1 }), "Windmill needs a higher level")
	check(not DecorModel.Validate(Config, items, "Vault", -10, -14, 0, nil, { Level = 1, Vaults = 1 }), "vault limit not enforced")
	check(DecorModel.Validate(Config, items, "Vault", -10, -14, 0, nil, { Level = 1, Vaults = 2 }), "VIP vault should be allowed")
	check(select(2, DecorModel.Price(Config, "Vault", items)) == base.VaultCosts[2], "2nd vault price wrong")
	-- who stands where: best pet goes to the vault, show-off pets stay out, exclusive skip it
	local data = {
		Base = { Items = items },
		Pets = {
			{ Id = 1, Name = "Owl" },
			{ Id = 2, Name = "Fox" },
			{ Id = 3, Name = "Bunny" },
			{ Id = 4, Name = "Kitty" },
			{ Id = 5, Name = "Golden Pup" },
		},
	}
	local vault, display = Util.ArrangePets(Config, data)
	check(#vault == 1 and vault[1].Name == "Owl", "the best normal pet should be in the vault")
	check(display[1].Name == "Golden Pup", "exclusive pets should be on display (they're safe anyway)")
	data.Pets[1].Show = true
	vault, display = Util.ArrangePets(Config, data)
	check(vault[1].Name == "Fox", "a show-off pet must stay out of the vault")
	local shownOwl = false
	for _, pet in display do
		shownOwl = shownOwl or pet.Name == "Owl"
	end
	check(shownOwl, "the show-off pet should be on display")
	check(Util.SetBonus(Config, items) == 0, "starter base should not complete a set")
	local garden = { { Id = "Tree" }, { Id = "Flowers" }, { Id = "Bush" }, { Id = "Pond" } }
	check(math.abs(Util.SetBonus(Config, garden) - 0.05) < 1e-9, "garden set bonus wrong")
	local huge = Util.HatchChance(Config, "Meadow", "Bunny", "Huge")
	check(huge and huge > 0 and huge < 1 / 500, "huge odds wrong")
	check(Util.WantsSerial(Config, "Bunny", "Huge") and Util.WantsSerial(Config, "Midas King", nil), "serial rules wrong")
	check(not Util.WantsSerial(Config, "Bunny", "Golden"), "golden pets don't need serials")
	local sx, sz = DecorModel.Snap(Config, "Sofa", 0.7, 0.3, 1) -- 3x1 rotated: odd/even cells
	check(sx % 1 == 0 and sz % 1 == 0, "snap produced off-grid values")
	local currency, price = DecorModel.Price(Config, "Pedestal", items)
	check(currency == "Coins" and price == base.PedestalCosts[4], "4th pedestal price wrong")
	check(select(1, DecorModel.Price(Config, "Throne", items)) == "Gems", "gem decor should cost gems")
	local w, d = DecorModel.Footprint(Config, "Bench", 1)
	check(w == base.Cell and d == base.Cell * 2, "rotated footprint wrong")
	check(base.StartPedestals >= 1 and base.StartPedestals <= base.MaxPedestals, "Base.StartPedestals out of range")
	for i = 2, #base.PedestalCosts do
		check(base.PedestalCosts[i] >= base.PedestalCosts[i - 1], "pedestal costs must not go down")
	end
	-- rolls: luck must shift odds toward rarer shards, min index respected
	math.randomseed(3)
	local rng = nil -- Util falls back to math.random (no Random in Lune)
	local function shareOfRare(luck)
		local rare = 0
		for _ = 1, 4000 do
			if Util.ShardIndex(Config, Util.RollShard(Config, luck, rng)) >= 3 then
				rare += 1
			end
		end
		return rare / 4000
	end
	local plain, lucky = shareOfRare(1), shareOfRare(3)
	check(lucky > plain * 1.5, string.format("shard luck has little effect (%.3f vs %.3f)", plain, lucky))
	for _ = 1, 200 do
		check(Util.ShardIndex(Config, Util.RollShard(Config, 1, rng, 3)) >= 3, "RollShard ignored minIndex")
	end
	check(Util.ShardIncome(Config, "Rare", 2) == shards.Rarities.Rare.Income * shards.ZoneMult[2], "ShardIncome wrong")
	print(string.format("Shard odds: Epic+ %.1f%% normal, %.1f%% with meteor luck", plain * 100, lucky * 100))
end
check(Config.Fever.Combo > 1 and Config.Fever.Duration > 0 and Config.Fever.MaxDuration >= Config.Fever.Duration, "Fever config")

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
