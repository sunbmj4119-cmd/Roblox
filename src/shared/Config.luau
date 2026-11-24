--[[
	Meteor Miners - central game configuration.

	Every number that matters for balance and monetization lives here so you can
	tune the game without touching gameplay code.

	BEFORE PUBLISHING:
	  1. Create the Game Passes / Developer Products on the Creator Dashboard and
	     paste their IDs into Config.GamePasses / Config.Products below.
	  2. (Optional) Put your Roblox Group ID into Config.GroupId.
	  3. (Optional) Create an experience Subscription and paste its ID.
	  While an ID is 0 the purchase is SIMULATED inside Roblox Studio so you can
	  test every flow, and shown as "coming soon" in a live server.
]]

local Config = {}

Config.GameName = "Meteor Miners"
Config.DataStoreName = "MeteorMiners_PlayerData_v1"
Config.LeaderboardPrefix = "MeteorMiners_LB_v1_"
Config.GroupId = 0 -- your Roblox group id (0 = disabled)

---------------------------------------------------------------------------
-- Rarities
---------------------------------------------------------------------------
Config.Rarities = {
	Common = { Order = 1, Color = Color3.fromRGB(200, 200, 200) },
	Uncommon = { Order = 2, Color = Color3.fromRGB(95, 215, 115) },
	Rare = { Order = 3, Color = Color3.fromRGB(70, 155, 255) },
	Epic = { Order = 4, Color = Color3.fromRGB(175, 95, 255) },
	Legendary = { Order = 5, Color = Color3.fromRGB(255, 175, 40) },
	Mythic = { Order = 6, Color = Color3.fromRGB(255, 70, 115) },
	Secret = { Order = 7, Color = Color3.fromRGB(40, 255, 230) },
}
Config.RarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" }
Config.AnnounceRarity = 5 -- server-wide announcement for Legendary and above
Config.LuckAffectsFromRarity = 3 -- luck multiplies weights of Rare and above

---------------------------------------------------------------------------
-- Zones (linear progression)
---------------------------------------------------------------------------
Config.Zones = {
	{
		Name = "Meadow Mine",
		Cost = 0,
		Floor = Enum.Material.Grass,
		FloorColor = Color3.fromRGB(90, 160, 75),
		Accent = Color3.fromRGB(130, 200, 100),
		Ores = { { "Stone", 50 }, { "Coal", 28 }, { "Copper", 15 }, { "Iron", 7 } },
	},
	{
		Name = "Frost Cavern",
		Cost = 5000,
		Floor = Enum.Material.Snow,
		FloorColor = Color3.fromRGB(225, 240, 255),
		Accent = Color3.fromRGB(130, 200, 255),
		Ores = { { "Ice", 55 }, { "Silver", 32 }, { "Sapphire", 13 } },
	},
	{
		Name = "Lava Depths",
		Cost = 75000,
		Floor = Enum.Material.Basalt,
		FloorColor = Color3.fromRGB(60, 45, 45),
		Accent = Color3.fromRGB(255, 110, 40),
		Ores = { { "Obsidian", 55 }, { "Gold", 32 }, { "Ruby", 13 } },
	},
	{
		Name = "Crystal Void",
		Cost = 1200000,
		Floor = Enum.Material.Slate,
		FloorColor = Color3.fromRGB(45, 35, 75),
		Accent = Color3.fromRGB(180, 110, 255),
		Ores = { { "Amethyst", 55 }, { "Emerald", 32 }, { "Diamond", 13 } },
	},
	{
		Name = "Star Crater",
		Cost = 15000000,
		Floor = Enum.Material.CrackedLava,
		FloorColor = Color3.fromRGB(70, 30, 60),
		Accent = Color3.fromRGB(255, 60, 120),
		Ores = { { "Meteorite", 55 }, { "StardustOre", 32 }, { "CosmicCrystal", 13 } },
	},
}

---------------------------------------------------------------------------
-- Ores: HP = hits needed * damage, Value = ore points added to backpack
---------------------------------------------------------------------------
Config.Ores = {
	Stone = { Name = "Stone", HP = 3, Value = 1, Color = Color3.fromRGB(140, 140, 140), Material = Enum.Material.Rock },
	Coal = { Name = "Coal", HP = 5, Value = 2, Color = Color3.fromRGB(45, 45, 50), Material = Enum.Material.Slate },
	Copper = { Name = "Copper", HP = 9, Value = 4, Color = Color3.fromRGB(200, 115, 60), Material = Enum.Material.Metal },
	Iron = { Name = "Iron", HP = 15, Value = 7, Color = Color3.fromRGB(205, 190, 175), Material = Enum.Material.Metal },

	Ice = { Name = "Ice", HP = 25, Value = 12, Color = Color3.fromRGB(170, 220, 255), Material = Enum.Material.Ice },
	Silver = { Name = "Silver", HP = 45, Value = 20, Color = Color3.fromRGB(215, 220, 230), Material = Enum.Material.Foil },
	Sapphire = {
		Name = "Sapphire",
		HP = 90,
		Value = 40,
		Color = Color3.fromRGB(40, 90, 255),
		Material = Enum.Material.Glass,
		Glow = true,
		GemChance = 0.05,
		Gems = 1,
	},

	Obsidian = { Name = "Obsidian", HP = 200, Value = 90, Color = Color3.fromRGB(35, 20, 45), Material = Enum.Material.Glass },
	Gold = { Name = "Gold", HP = 340, Value = 150, Color = Color3.fromRGB(255, 200, 40), Material = Enum.Material.Foil },
	Ruby = {
		Name = "Ruby",
		HP = 700,
		Value = 300,
		Color = Color3.fromRGB(230, 30, 60),
		Material = Enum.Material.Glass,
		Glow = true,
		GemChance = 0.08,
		Gems = 2,
	},

	Amethyst = { Name = "Amethyst", HP = 1600, Value = 700, Color = Color3.fromRGB(160, 90, 230), Material = Enum.Material.Glass },
	Emerald = { Name = "Emerald", HP = 2800, Value = 1200, Color = Color3.fromRGB(40, 210, 110), Material = Enum.Material.Glass },
	Diamond = {
		Name = "Diamond",
		HP = 6000,
		Value = 2500,
		Color = Color3.fromRGB(190, 250, 255),
		Material = Enum.Material.Glass,
		Glow = true,
		GemChance = 0.12,
		Gems = 4,
	},

	Meteorite = { Name = "Meteorite", HP = 14000, Value = 6000, Color = Color3.fromRGB(80, 50, 45), Material = Enum.Material.Basalt },
	StardustOre = {
		Name = "Stardust Ore",
		HP = 24000,
		Value = 10000,
		Color = Color3.fromRGB(255, 120, 230),
		Material = Enum.Material.Neon,
		Glow = true,
		Stardust = 3,
	},
	CosmicCrystal = {
		Name = "Cosmic Crystal",
		HP = 50000,
		Value = 20000,
		Color = Color3.fromRGB(60, 255, 230),
		Material = Enum.Material.Neon,
		Glow = true,
		GemChance = 0.25,
		Gems = 8,
	},
}

Config.World = {
	-- map geometry (shared by WorldService and client zone detection)
	Layout = { HubHalf = 80, ZoneWidth = 100, ZoneLength = 100, Gap = 10, FirstZ = 90 },
	OreRespawnSeconds = 4,
	OreSize = 5,
	OreSpacing = 7,
	Reach = 13, -- studs from character to the target
	WalkSpeed = 22,
	-- base district south of the hub (see BaseService)
	Bases = { ZStart = -88, ZEnd = -278, HalfX = 200 },
	SpawnSafeRadius = 24, -- nobody can be bonked near the spawn
}

---------------------------------------------------------------------------
-- Upgrades
---------------------------------------------------------------------------
Config.Pickaxes = {
	{ Name = "Wooden Pickaxe", Power = 1, Cooldown = 0.36, Cost = 0, Color = Color3.fromRGB(150, 105, 60) },
	{ Name = "Stone Pickaxe", Power = 2, Cooldown = 0.34, Cost = 150, Color = Color3.fromRGB(130, 130, 130) },
	{ Name = "Copper Pickaxe", Power = 4, Cooldown = 0.32, Cost = 800, Color = Color3.fromRGB(200, 115, 60) },
	{ Name = "Iron Pickaxe", Power = 8, Cooldown = 0.3, Cost = 3500, Color = Color3.fromRGB(205, 190, 175) },
	{ Name = "Gold Pickaxe", Power = 15, Cooldown = 0.29, Cost = 15000, Color = Color3.fromRGB(255, 200, 40) },
	{ Name = "Diamond Pickaxe", Power = 30, Cooldown = 0.28, Cost = 60000, Color = Color3.fromRGB(150, 240, 255) },
	{ Name = "Obsidian Pickaxe", Power = 60, Cooldown = 0.27, Cost = 250000, Color = Color3.fromRGB(60, 30, 80) },
	{ Name = "Frost Fang", Power = 120, Cooldown = 0.26, Cost = 1000000, Color = Color3.fromRGB(120, 200, 255) },
	{ Name = "Magma Breaker", Power = 250, Cooldown = 0.25, Cost = 4500000, Color = Color3.fromRGB(255, 90, 30) },
	{ Name = "Void Splitter", Power = 550, Cooldown = 0.24, Cost = 20000000, Color = Color3.fromRGB(170, 90, 255) },
	{ Name = "Starforged", Power = 1200, Cooldown = 0.23, Cost = 90000000, Color = Color3.fromRGB(255, 90, 200) },
	{ Name = "Galaxy Crusher", Power = 2600, Cooldown = 0.22, Cost = 400000000, Color = Color3.fromRGB(60, 255, 230) },
}

Config.Rebirth = {
	BaseCost = 50000,
	Exponent = 2.2, -- cost = BaseCost * (rebirths + 1) ^ Exponent
	CoinBonusPer = 0.5, -- +50% coins per rebirth (additive)
	GemsPer = 50, -- gems = GemsPer * (rebirths + 1)
	ExtraPetSlotEvery = 5, -- +1 pet slot every N rebirths
}

---------------------------------------------------------------------------
-- Pets & eggs
---------------------------------------------------------------------------
Config.BasePetSlots = 3
Config.MaxPetSlots = 12
Config.MaxPets = 60 -- pet storage (the best ones go on your pedestals)
Config.PetSellSeconds = 60 -- selling a pet pays this many seconds of its income

-- Pets live in your base: the best ones sit on your pedestals and earn
-- Income (coins per second). Your top pets also follow you around and add
-- their Power to your mining damage (automatic, no equipping needed).
Config.Pets = {
	-- Meadow
	Bunny = { Rarity = "Common", Power = 0.1, Income = 0.6, Color = Color3.fromRGB(245, 245, 245), Shape = "Ball", Ears = true },
	Chick = { Rarity = "Common", Power = 0.15, Income = 0.9, Color = Color3.fromRGB(255, 230, 90), Shape = "Ball" },
	Puppy = { Rarity = "Uncommon", Power = 0.3, Income = 1.8, Color = Color3.fromRGB(190, 140, 90), Shape = "Block", Ears = true },
	Kitty = { Rarity = "Uncommon", Power = 0.35, Income = 2.1, Color = Color3.fromRGB(255, 160, 80), Shape = "Block", Ears = true },
	Fox = { Rarity = "Rare", Power = 0.8, Income = 4.8, Color = Color3.fromRGB(255, 110, 30), Shape = "Block", Ears = true },
	Owl = { Rarity = "Epic", Power = 2, Income = 12, Color = Color3.fromRGB(150, 110, 80), Shape = "Ball", Wings = true },
	["Golden Bunny"] = { Rarity = "Legendary", Power = 6, Income = 36, Color = Color3.fromRGB(255, 205, 50), Shape = "Ball", Ears = true },
	-- Frost
	Penguin = { Rarity = "Common", Power = 0.6, Income = 24, Color = Color3.fromRGB(40, 45, 60), Shape = "Ball", Wings = true },
	["Snow Fox"] = { Rarity = "Uncommon", Power = 1.2, Income = 48, Color = Color3.fromRGB(235, 245, 255), Shape = "Block", Ears = true },
	["Polar Bear"] = { Rarity = "Rare", Power = 2.5, Income = 100, Color = Color3.fromRGB(250, 250, 250), Shape = "Block", Ears = true },
	["Ice Owl"] = { Rarity = "Epic", Power = 6, Income = 240, Color = Color3.fromRGB(150, 220, 255), Shape = "Ball", Wings = true },
	["Frost Wolf"] = { Rarity = "Legendary", Power = 18, Income = 720, Color = Color3.fromRGB(110, 180, 255), Shape = "Block", Ears = true },
	Yeti = { Rarity = "Mythic", Power = 50, Income = 2000, Color = Color3.fromRGB(200, 240, 255), Shape = "Block", Horns = true },
	-- Lava
	["Magma Slime"] = { Rarity = "Common", Power = 3, Income = 510, Color = Color3.fromRGB(255, 90, 30), Shape = "Ball" },
	["Fire Fox"] = { Rarity = "Uncommon", Power = 6, Income = 1000, Color = Color3.fromRGB(255, 60, 20), Shape = "Block", Ears = true },
	["Lava Golem"] = { Rarity = "Rare", Power = 12, Income = 2000, Color = Color3.fromRGB(90, 40, 30), Shape = "Block", Horns = true },
	["Phoenix Chick"] = { Rarity = "Epic", Power = 30, Income = 5100, Color = Color3.fromRGB(255, 150, 30), Shape = "Ball", Wings = true },
	["Inferno Dragon"] = {
		Rarity = "Legendary",
		Power = 90,
		Income = 15000,
		Color = Color3.fromRGB(200, 30, 20),
		Shape = "Block",
		Wings = true,
		Horns = true,
	},
	["Sun Serpent"] = { Rarity = "Mythic", Power = 250, Income = 42000, Color = Color3.fromRGB(255, 220, 60), Shape = "Ball", Horns = true },
	-- Void
	["Void Bat"] = { Rarity = "Common", Power = 15, Income = 6000, Color = Color3.fromRGB(70, 40, 110), Shape = "Ball", Wings = true },
	["Shadow Cat"] = { Rarity = "Uncommon", Power = 30, Income = 12000, Color = Color3.fromRGB(35, 25, 50), Shape = "Block", Ears = true },
	["Nebula Fox"] = { Rarity = "Rare", Power = 60, Income = 24000, Color = Color3.fromRGB(150, 80, 255), Shape = "Block", Ears = true },
	["Rift Owl"] = { Rarity = "Epic", Power = 150, Income = 60000, Color = Color3.fromRGB(90, 60, 200), Shape = "Ball", Wings = true },
	["Galaxy Dragon"] = {
		Rarity = "Legendary",
		Power = 450,
		Income = 180000,
		Color = Color3.fromRGB(60, 40, 160),
		Shape = "Block",
		Wings = true,
		Horns = true,
	},
	["Void Emperor"] = {
		Rarity = "Mythic",
		Power = 1200,
		Income = 480000,
		Color = Color3.fromRGB(20, 10, 40),
		Shape = "Block",
		Horns = true,
	},
	["Black Hole Kitty"] = {
		Rarity = "Secret",
		Power = 5000,
		Income = 2000000,
		Color = Color3.fromRGB(10, 10, 15),
		Shape = "Ball",
		Ears = true,
	},
	-- Gem egg
	["Gem Pup"] = { Rarity = "Uncommon", Power = 2, Income = 30, Color = Color3.fromRGB(80, 230, 255), Shape = "Block", Ears = true },
	["Crystal Cat"] = { Rarity = "Rare", Power = 5, Income = 75, Color = Color3.fromRGB(170, 240, 255), Shape = "Block", Ears = true },
	["Prism Owl"] = { Rarity = "Epic", Power = 15, Income = 220, Color = Color3.fromRGB(255, 150, 255), Shape = "Ball", Wings = true },
	["Diamond Dragon"] = {
		Rarity = "Legendary",
		Power = 60,
		Income = 900,
		Color = Color3.fromRGB(190, 250, 255),
		Shape = "Block",
		Wings = true,
		Horns = true,
	},
	["Jewel Phoenix"] = {
		Rarity = "Mythic",
		Power = 200,
		Income = 3000,
		Color = Color3.fromRGB(255, 80, 200),
		Shape = "Ball",
		Wings = true,
	},
	-- Cosmic egg (stardust only - earned in meteor events)
	["Comet Pup"] = { Rarity = "Rare", Power = 20, Income = 80, Color = Color3.fromRGB(120, 200, 255), Shape = "Block", Ears = true },
	["Meteor Cat"] = { Rarity = "Epic", Power = 60, Income = 240, Color = Color3.fromRGB(255, 120, 60), Shape = "Block", Ears = true },
	["Star Owl"] = { Rarity = "Legendary", Power = 200, Income = 800, Color = Color3.fromRGB(255, 240, 120), Shape = "Ball", Wings = true },
	["Supernova Dragon"] = {
		Rarity = "Mythic",
		Power = 800,
		Income = 3200,
		Color = Color3.fromRGB(255, 60, 160),
		Shape = "Block",
		Wings = true,
		Horns = true,
	},
	["Celestial Titan"] = {
		Rarity = "Secret",
		Power = 3000,
		Income = 12000,
		Color = Color3.fromRGB(60, 255, 230),
		Shape = "Block",
		Horns = true,
	},
	-- Golden egg (Robux)
	["Golden Pup"] = {
		Exclusive = true,
		Rarity = "Epic",
		Power = 50,
		Income = 1500,
		Color = Color3.fromRGB(255, 210, 60),
		Shape = "Block",
		Ears = true,
	},
	["Golden Cat"] = {
		Exclusive = true,
		Rarity = "Legendary",
		Power = 150,
		Income = 4500,
		Color = Color3.fromRGB(255, 190, 30),
		Shape = "Block",
		Ears = true,
	},
	["Golden Dragon"] = {
		Exclusive = true,
		Rarity = "Mythic",
		Power = 600,
		Income = 18000,
		Color = Color3.fromRGB(255, 170, 0),
		Shape = "Block",
		Wings = true,
		Horns = true,
	},
	["Midas King"] = {
		Exclusive = true,
		Rarity = "Secret",
		Power = 2500,
		Income = 75000,
		Color = Color3.fromRGB(255, 230, 120),
		Shape = "Ball",
		Horns = true,
	},
	-- Rewards-only pets
	["Starter Dino"] = { Rarity = "Epic", Power = 4, Income = 160, Color = Color3.fromRGB(90, 220, 120), Shape = "Block", Horns = true },
	["Rookie Rock"] = { Rarity = "Rare", Power = 5, Income = 100, Color = Color3.fromRGB(120, 120, 130), Shape = "Block" },
	["Impact Wolf"] = {
		Rarity = "Mythic",
		Power = 400,
		Income = 8000,
		Color = Color3.fromRGB(255, 80, 60),
		Shape = "Block",
		Ears = true,
		Horns = true,
	},
	["Champion Griffin"] = {
		Rarity = "Legendary",
		Power = 120,
		Income = 2400,
		Color = Color3.fromRGB(255, 215, 0),
		Shape = "Ball",
		Wings = true,
	},
}

-- Currency: "Coins" | "Gems" | "Stardust" | "Robux" (Robux eggs use Products below)
Config.Eggs = {
	Meadow = {
		Name = "Meadow Egg",
		Currency = "Coins",
		Stock = { Chance = 1, Min = 4, Max = 6 }, -- per 5-min restock
		Price = 250,
		Zone = 1,
		Color = Color3.fromRGB(150, 230, 120),
		Pets = {
			{ "Bunny", 40 },
			{ "Chick", 30 },
			{ "Puppy", 15 },
			{ "Kitty", 10 },
			{ "Fox", 4 },
			{ "Owl", 0.9 },
			{ "Golden Bunny", 0.1 },
		},
	},
	Frost = {
		Name = "Frost Egg",
		Currency = "Coins",
		Stock = { Chance = 0.85, Min = 2, Max = 4 }, -- per 5-min restock
		Price = 15000,
		Zone = 2,
		Color = Color3.fromRGB(150, 210, 255),
		Pets = {
			{ "Penguin", 45 },
			{ "Snow Fox", 33 },
			{ "Polar Bear", 15 },
			{ "Ice Owl", 6 },
			{ "Frost Wolf", 0.9 },
			{ "Yeti", 0.1 },
		},
	},
	Lava = {
		Name = "Lava Egg",
		Currency = "Coins",
		Stock = { Chance = 0.6, Min = 1, Max = 3 }, -- per 5-min restock
		Price = 400000,
		Zone = 3,
		Color = Color3.fromRGB(255, 110, 40),
		Pets = {
			{ "Magma Slime", 45 },
			{ "Fire Fox", 33 },
			{ "Lava Golem", 15 },
			{ "Phoenix Chick", 6 },
			{ "Inferno Dragon", 0.9 },
			{ "Sun Serpent", 0.1 },
		},
	},
	Void = {
		Name = "Void Egg",
		Currency = "Coins",
		Stock = { Chance = 0.4, Min = 1, Max = 2 }, -- per 5-min restock
		Price = 6000000,
		Zone = 4,
		Color = Color3.fromRGB(130, 80, 220),
		Pets = {
			{ "Void Bat", 45 },
			{ "Shadow Cat", 33 },
			{ "Nebula Fox", 15 },
			{ "Rift Owl", 6 },
			{ "Galaxy Dragon", 0.89 },
			{ "Void Emperor", 0.1 },
			{ "Black Hole Kitty", 0.01 },
		},
	},
	Gem = {
		Name = "Gem Egg",
		Currency = "Gems",
		Price = 400,
		Zone = 1,
		Color = Color3.fromRGB(80, 230, 255),
		Pets = {
			{ "Gem Pup", 50 },
			{ "Crystal Cat", 30 },
			{ "Prism Owl", 15 },
			{ "Diamond Dragon", 4.5 },
			{ "Jewel Phoenix", 0.5 },
		},
	},
	Cosmic = {
		Name = "Cosmic Egg",
		Currency = "Stardust",
		Price = 1500,
		Zone = 1,
		Color = Color3.fromRGB(255, 100, 220),
		Pets = {
			{ "Comet Pup", 55 },
			{ "Meteor Cat", 30 },
			{ "Star Owl", 12 },
			{ "Supernova Dragon", 2.9 },
			{ "Celestial Titan", 0.1 },
		},
	},
	Golden = {
		Name = "Golden Egg",
		Currency = "Robux",
		Zone = 1,
		Color = Color3.fromRGB(255, 205, 40),
		ProductSingle = "GoldenEgg1",
		ProductTriple = "GoldenEgg3",
		Pets = {
			{ "Golden Pup", 60 },
			{ "Golden Cat", 30 },
			{ "Golden Dragon", 9.5 },
			{ "Midas King", 0.5 },
		},
	},
}
-- coin eggs restock every 5 minutes (same stock in every server)
Config.Shop = { RestockSeconds = 300 }
Config.EggOrder = { "Meadow", "Gem", "Cosmic", "Golden", "Frost", "Lava", "Void" }

---------------------------------------------------------------------------
-- MONETIZATION
-- Price = suggested Robux price (display fallback; real price is read from Roblox)
---------------------------------------------------------------------------
Config.GamePasses = {
	VIP = {
		Id = 0,
		Name = "VIP",
		Price = 299,
		Icon = "👑",
		Description = "+25% coins, +1 pet slot, +1 vault, +10s base lock, Royal house skin, gold [VIP] tag, daily chest (100 gems)",
	},
	DoubleCoins = { Id = 0, Name = "2x Coins", Price = 249, Icon = "💰", Description = "Permanently double all coins" },
	MegaPower = { Id = 0, Name = "2x Mining Power", Price = 199, Icon = "💥", Description = "Permanently double your mining damage" },
	AutoMine = { Id = 0, Name = "Auto Mine", Price = 149, Icon = "🤖", Description = "Mine automatically while holding your pickaxe" },
	FastCarry = { Id = 0, Name = "Fast Carry", Price = 129, Icon = "🏃", Description = "+35% run speed while carrying a shard" },
	ExtraPets = { Id = 0, Name = "+3 Pet Slots", Price = 199, Icon = "🐾", Description = "3 more pets follow you and boost mining" },
	Lucky = { Id = 0, Name = "Lucky Hatch", Price = 179, Icon = "🍀", Description = "+50% luck on every egg" },
	TripleHatch = { Id = 0, Name = "Triple Hatch", Price = 149, Icon = "🥚", Description = "Hatch 3 eggs at once" },
	DoubleBase = { Id = 0, Name = "2x Base Income", Price = 199, Icon = "🏠", Description = "Your base earns double coins" },
	Speed = { Id = 0, Name = "Rocket Boots", Price = 79, Icon = "👟", Description = "+50% walk speed" },
}
Config.GamePassOrder =
	{ "VIP", "DoubleCoins", "DoubleBase", "MegaPower", "AutoMine", "FastCarry", "ExtraPets", "Lucky", "TripleHatch", "Speed" }

-- Kind decides how the product is granted (see MonetizationService)
Config.Products = {
	Gems100 = { Id = 0, Name = "100 Gems", Price = 39, Icon = "💎", Kind = "Gems", Amount = 100 },
	Gems550 = { Id = 0, Name = "550 Gems", Price = 179, Icon = "💎", Kind = "Gems", Amount = 550, Tag = "+10%" },
	Gems1200 = { Id = 0, Name = "1,200 Gems", Price = 349, Icon = "💎", Kind = "Gems", Amount = 1200, Tag = "POPULAR" },
	Gems3500 = { Id = 0, Name = "3,500 Gems", Price = 899, Icon = "💎", Kind = "Gems", Amount = 3500, Tag = "BEST VALUE" },
	CoinPack = {
		Id = 0,
		Name = "Coin Crate",
		Price = 49,
		Icon = "💰",
		Kind = "CoinPack",
		Description = "A big pile of coins (scales with you)",
	},
	CoinBoost = { Id = 0, Name = "2x Coins (30m)", Price = 79, Icon = "⏫", Kind = "Boost", Boost = "Coins2x", Seconds = 1800 },
	LuckBoost = { Id = 0, Name = "2x Luck (30m)", Price = 69, Icon = "🍀", Kind = "Boost", Boost = "Luck2x", Seconds = 1800 },
	PowerBoost = { Id = 0, Name = "2x Power (30m)", Price = 69, Icon = "💥", Kind = "Boost", Boost = "Power2x", Seconds = 1800 },
	ServerLuck = {
		Id = 0,
		Name = "Server Luck (15m)",
		Price = 149,
		Icon = "🌟",
		Kind = "ServerBoost",
		Boost = "ServerLuck",
		Seconds = 900,
		Description = "2x luck for EVERYONE in the server",
	},
	SummonMeteor = {
		Id = 0,
		Name = "Summon Meteor",
		Price = 99,
		Icon = "☄️",
		Kind = "SummonMeteor",
		Description = "Start a meteor event now - you get 2x stardust",
	},
	SeasonPremium = { Id = 0, Name = "Premium Pass", Price = 399, Icon = "🎫", Kind = "SeasonPremium" },
	SkipTiers = { Id = 0, Name = "Skip 5 Tiers", Price = 149, Icon = "⏩", Kind = "SkipTiers", Amount = 5 },
	StarterPack = {
		Id = 0,
		Name = "Starter Pack",
		Price = 99,
		Icon = "🎁",
		Kind = "StarterPack",
		OneTime = true,
		Description = "500 gems + Starter Dino (Epic) + 2x Coins 1h",
	},
	GoldenEgg1 = { Id = 0, Name = "Golden Egg x1", Price = 79, Icon = "🥚", Kind = "PaidEgg", Egg = "Golden", Count = 1 },
	GoldenEgg3 = { Id = 0, Name = "Golden Egg x3", Price = 199, Icon = "🥚", Kind = "PaidEgg", Egg = "Golden", Count = 3 },
	HouseSkinNeon = {
		Id = 0,
		Name = "Neon City House",
		Price = 149,
		Icon = "🌃",
		Kind = "HouseSkin",
		Skin = "Neon",
		OneTime = true,
		Description = "Glowing neon walls for your house (looks only)",
	},
	-- Rewarded video ad reward (Robux price is irrelevant; Roblox grants it via ProcessReceipt)
	AdReward = { Id = 0, Name = "Free 2x Coins (10m)", Price = 0, Icon = "📺", Kind = "Boost", Boost = "Coins2x", Seconds = 600 },
}
Config.StoreOrder = {
	"StarterPack",
	"Gems100",
	"Gems550",
	"Gems1200",
	"Gems3500",
	"CoinPack",
	"CoinBoost",
	"LuckBoost",
	"PowerBoost",
	"ServerLuck",
	"SummonMeteor",
}

Config.StarterPack = {
	OfferHours = 48, -- only offered during the first 48 hours (urgency)
	Reward = { Gems = 500, Pet = "Starter Dino", Boost = { "Coins2x", 3600 } },
}

-- Roblox experience subscription (monthly). Leave Id = "" to disable.
Config.Subscription = {
	Id = "", -- e.g. "EXP-1234567890"
	Name = "Miner Club",
	PriceText = "Monthly",
	CoinBonus = 0.2,
	DailyGems = 150,
	Description = "+20% coins, 150 gems every day, [CLUB] tag",
}

-- Native Roblox rewarded video ads (AdService). Requires eligibility on the
-- Creator Hub and a developer product used as the reward (Products.AdReward).
-- OWNER TEST MODE: while true, the game's owner (you) also gets the DEV panel
-- and simulated purchases for products whose Id is still 0 in LIVE servers,
-- so you can test everything on a phone. Owner scores are kept off the global
-- leaderboards. >>> Set to false before the real public launch. <<<
Config.OwnerTestMode = true

Config.RewardedAds = {
	Enabled = false,
	CooldownSeconds = 900,
}

---------------------------------------------------------------------------
-- Social bonuses (viral loop + Creator Rewards engagement)
---------------------------------------------------------------------------
Config.Social = {
	FriendBonusPer = 0.1, -- +10% coins per friend in server
	FriendBonusMax = 0.5,
	GroupBonus = 0.1,
	GroupJoinGems = 100,
	PremiumBonus = 0.1,
	VipCoinBonus = 0.25,
	VipDailyGems = 100,
}

---------------------------------------------------------------------------
-- COMPETITION
---------------------------------------------------------------------------
Config.Meteor = {
	IntervalSeconds = 420, -- a meteor every 7 minutes
	WarningSeconds = 30,
	SummonWarningSeconds = 10,
	DurationSeconds = 90,
	BaseHP = 60, -- score points
	SecondsPerParticipant = 40, -- each new hitter adds ~40s of their own hitting to the HP
	Position = Vector3.new(0, 0, 40),
	Radius = 9,
	-- Rank rewards (index = placement)
	PlaceRewards = {
		{ Stardust = 400, Gems = 100, Points = 300 },
		{ Stardust = 250, Gems = 60, Points = 200 },
		{ Stardust = 150, Gems = 40, Points = 150 },
	},
	ParticipationStardust = 30,
	ShareStardust = 300, -- + share of total score * this
	ParticipationPoints = 50,
	PassXP = 150,
	FailedMultiplier = 0.5, -- rewards when the meteor wasn't destroyed in time
}

-- bonking: only players carrying a star shard can be bonked (they drop it)
Config.PvP = {
	BonkRange = 10,
	ImmunitySeconds = 4,
	PointsPerBonk = 10,
	Knockback = 55,
	CarrySpeedPass = 1.35, -- Fast Carry game pass
}

-- Weekly ranked ladder (points come from activity, not wealth -> fair competition)
Config.Ranks = {
	{ Name = "Bronze", Icon = "🥉", Min = 0, Color = Color3.fromRGB(205, 127, 50), RewardGems = 0 },
	{ Name = "Silver", Icon = "🥈", Min = 500, Color = Color3.fromRGB(200, 210, 220), RewardGems = 50 },
	{ Name = "Gold", Icon = "🥇", Min = 2000, Color = Color3.fromRGB(255, 205, 50), RewardGems = 150 },
	{ Name = "Platinum", Icon = "💠", Min = 6000, Color = Color3.fromRGB(110, 230, 210), RewardGems = 400 },
	{ Name = "Diamond", Icon = "💎", Min = 15000, Color = Color3.fromRGB(120, 190, 255), RewardGems = 1000 },
	{ Name = "Master", Icon = "👑", Min = 35000, Color = Color3.fromRGB(255, 80, 160), RewardGems = 2500 },
}
Config.PointsPerBlock = { 1, 2, 3, 4, 6 } -- by zone index

Config.Leaderboards = {
	RefreshSeconds = 90,
	Boards = {
		{ Key = "Weekly", Title = "🏆 WEEKLY RANKED", Weekly = true },
		{ Key = "LifetimeCoins", Title = "💰 RICHEST MINERS" },
		{ Key = "Likes", Title = "❤️ BEST BASES" },
	},
	WeeklyTopReward = { 5000, 3000, 2000, 1000, 1000, 500, 500, 500, 500, 500 }, -- gems for global top 10
}

-- titles: earned by playing, shown above your head (choose one in 👑 Titles).
-- Need: Level / Index (pets discovered) / Steals / Catches (thieves bonked) /
-- HouseLevel / Likes / Rebirths / Huge (huge pets found) / LifetimeCoins / Pass
Config.Titles = {
	{ Id = "Newcomer", Name = "🌱 Newcomer", Color = Color3.fromRGB(170, 230, 150), Need = {} },
	{ Id = "Miner", Name = "⛏️ Miner", Color = Color3.fromRGB(255, 200, 120), Need = { Level = 10 } },
	{ Id = "Collector", Name = "📖 Collector", Color = Color3.fromRGB(140, 220, 255), Need = { Index = 15 } },
	{ Id = "Thief", Name = "🦹 Sneaky Thief", Color = Color3.fromRGB(255, 150, 90), Need = { Steals = 10 } },
	{ Id = "Guard", Name = "🛡️ Guardian", Color = Color3.fromRGB(120, 230, 255), Need = { Catches = 10 } },
	{ Id = "Architect", Name = "🏗️ Architect", Color = Color3.fromRGB(255, 220, 120), Need = { HouseLevel = 3 } },
	{ Id = "Popular", Name = "❤️ Popular", Color = Color3.fromRGB(255, 120, 170), Need = { Likes = 50 } },
	{ Id = "Reborn", Name = "♻️ Reborn", Color = Color3.fromRGB(200, 130, 255), Need = { Rebirths = 3 } },
	{ Id = "HugeHunter", Name = "🐘 Huge Hunter", Color = Color3.fromRGB(255, 180, 60), Need = { Huge = 1 } },
	{ Id = "MasterThief", Name = "🦹 Master Thief", Color = Color3.fromRGB(255, 90, 60), Need = { Steals = 50 } },
	{ Id = "LegendCollector", Name = "🌟 Legend Collector", Color = Color3.fromRGB(255, 230, 90), Need = { Index = 35 } },
	{ Id = "Palace", Name = "🏰 Palace Owner", Color = Color3.fromRGB(210, 140, 255), Need = { HouseLevel = 5 } },
	{ Id = "Tycoon", Name = "💰 Tycoon", Color = Color3.fromRGB(255, 215, 60), Need = { LifetimeCoins = 1000000000 } },
	{ Id = "VIP", Name = "👑 VIP", Color = Color3.fromRGB(255, 200, 60), Need = { Pass = "VIP" } },
}

-- statues of the all-time richest players stand in the hub (global leaderboard)
Config.Statues = { Board = "LifetimeCoins", Count = 3, Scale = 1.6 }

---------------------------------------------------------------------------
-- RETENTION
---------------------------------------------------------------------------
Config.DailyRewards = {
	{ Gems = 20 },
	{ Boost = { "Coins2x", 600 } },
	{ Gems = 40 },
	{ Boost = { "Luck2x", 900 } },
	{ Gems = 80 },
	{ Stardust = 150 },
	{ Gems = 250, Pet = "Champion Griffin" },
}

Config.PlaytimeGifts = {
	{ Minutes = 2, Reward = { Gems = 10 } },
	{ Minutes = 5, Reward = { Boost = { "Coins2x", 300 } } },
	{ Minutes = 10, Reward = { Gems = 25 } },
	{ Minutes = 15, Reward = { Boost = { "Luck2x", 600 } } },
	{ Minutes = 25, Reward = { Gems = 50 } },
	{ Minutes = 40, Reward = { Stardust = 100 } },
	{ Minutes = 60, Reward = { Gems = 120 } },
}

Config.DailyQuestCount = 3
Config.Quests = {
	{ Id = "Mine100", Type = "MineBlocks", Target = 100, Text = "Mine 100 blocks", Reward = { Gems = 25 }, XP = 150, Points = 100 },
	{ Id = "Mine300", Type = "MineBlocks", Target = 300, Text = "Mine 300 blocks", Reward = { Gems = 50 }, XP = 250, Points = 200 },
	{
		Id = "Collect5",
		Type = "Collect",
		Target = 5,
		Text = "Collect coins at your base 5 times",
		Reward = { Gems = 25 },
		XP = 150,
		Points = 100,
	},
	{ Id = "Hatch5", Type = "Hatch", Target = 5, Text = "Hatch 5 eggs", Reward = { Gems = 30 }, XP = 150, Points = 100 },
	{ Id = "Meteor1", Type = "MeteorJoin", Target = 1, Text = "Join a meteor event", Reward = { Stardust = 50 }, XP = 200, Points = 150 },
	{
		Id = "MeteorTop3",
		Type = "MeteorTop3",
		Target = 1,
		Text = "Finish top 3 in a meteor event",
		Reward = { Gems = 80 },
		XP = 300,
		Points = 250,
	},
	{ Id = "Bonk5", Type = "Bonk", Target = 5, Text = "Bonk 5 players", Reward = { Gems = 60 }, XP = 250, Points = 200 },
	{ Id = "Shard3", Type = "Shard", Target = 3, Text = "Bring 3 shards to your base", Reward = { Gems = 60 }, XP = 250, Points = 200 },
	{ Id = "Steal1", Type = "Steal", Target = 1, Text = "Steal a pet from another base", Reward = { Gems = 80 }, XP = 300, Points = 250 },
	{
		Id = "Decorate5",
		Type = "Decorate",
		Target = 5,
		Text = "Place 5 decorations in your base",
		Reward = { Gems = 40 },
		XP = 200,
		Points = 150,
	},
	{ Id = "Like3", Type = "Like", Target = 3, Text = "Like 3 other bases", Reward = { Gems = 30 }, XP = 150, Points = 100 },
	{ Id = "Play20", Type = "PlayMinutes", Target = 20, Text = "Play for 20 minutes", Reward = { Gems = 30 }, XP = 200, Points = 150 },
	{ Id = "Upgrade1", Type = "Upgrade", Target = 1, Text = "Buy any upgrade", Reward = { Gems = 20 }, XP = 100, Points = 80 },
}

-- Season pass (battle pass). Change SeasonId to start a new season (progress resets).
Config.Season = {
	Id = 1,
	Name = "Season 1: First Impact",
	EndsAt = 0, -- unix time shown as countdown (0 = hidden)
	XPPerTier = 2000,
	XPPerBlock = 1,
}
Config.SeasonTiers = {}
for tier = 1, 30 do
	local free, premium
	if tier % 5 == 0 then
		free = { Gems = math.floor(25 * tier / 5) * 2 }
		premium = { Gems = math.floor(60 * tier / 5) * 2 }
	elseif tier % 3 == 0 then
		free = { Boost = { "Coins2x", 600 } }
		premium = { Stardust = 100 + tier * 10 }
	else
		free = { Gems = 10 }
		premium = { Gems = 30 }
	end
	Config.SeasonTiers[tier] = { Free = free, Premium = premium }
end
Config.SeasonTiers[10].Premium = { Boost = { "Luck2x", 3600 }, Gems = 150 }
Config.SeasonTiers[15].Free = { Pet = "Rookie Rock" }
Config.SeasonTiers[20].Premium = { Pet = "Champion Griffin" }
Config.SeasonTiers[30].Free = { Gems = 300 }
Config.SeasonTiers[30].Premium = { Pet = "Impact Wolf", Gems = 500 }

---------------------------------------------------------------------------
-- JUICE & DOPAMINE: crits, combos, lucky ores, pet variants, levels
---------------------------------------------------------------------------
-- crits send a shockwave that also damages nearby blocks (chain breaks!)
Config.Crit = { Chance = 0.12, Multiplier = 3, SplashRadius = 9, SplashDamage = 0.5 }

-- FEVER: reach a combo of 12 -> 8s of double ore, faster swings, every hit
-- shockwaves, +20% speed. Each break while in fever adds a little time.
Config.Fever = {
	Combo = 12,
	Duration = 8,
	Extend = 0.35,
	MaxDuration = 14,
	ValueMult = 2,
	CooldownMult = 0.65,
	SpeedMult = 1.2,
	SplashRadius = 11,
	SplashDamage = 0.6,
}

-- neon dash pads on the main roads
Config.SpeedPads = { Mult = 1.7, Seconds = 2.5 }

-- breaking blocks quickly in a row builds a combo: +2% ore per step (max +60%)
Config.Combo = { Window = 2.5, BonusPer = 0.02, MaxBonus = 0.6 }

-- any ore can spawn as a lucky variant (rarest first)
Config.LuckyOres = {
	{ Id = "Rainbow", Chance = 1 / 1500, ValueMult = 50, Gems = 15, HPMult = 3, Announce = true },
	{ Id = "Golden", Chance = 1 / 120, ValueMult = 10, Gems = 1, HPMult = 2 },
}

-- hatched pets can be Golden / Rainbow (luck increases the chance, max x4)
-- mutations: rolled on every hatch (rarest first). Event-only ones need
-- that weather event to be active (see Config.Events).
Config.PetVariants = {
	{ Id = "Galaxy", Chance = 1 / 1000, Event = "Starfall", EventChance = 1 / 60, PowerMult = 8, IncomeMult = 12 },
	-- HUGE: twice the size, numbered (#1, #2, ...) and announced to the whole server
	{ Id = "Huge", Chance = 1 / 500, PowerMult = 5, IncomeMult = 6, Scale = 2, Serial = true },
	{ Id = "Rainbow", Chance = 1 / 300, PowerMult = 6, IncomeMult = 8 },
	{ Id = "Molten", Chance = 0, Event = "HeatWave", EventChance = 1 / 5, PowerMult = 2.5, IncomeMult = 3 },
	{ Id = "Frozen", Chance = 0, Event = "Blizzard", EventChance = 1 / 5, PowerMult = 2, IncomeMult = 2.5 },
	{ Id = "Golden", Chance = 1 / 25, PowerMult = 2.5, IncomeMult = 3 },
}

-- player level: XP from every block, fast early levels, coin bonus per level
Config.Levels = {
	XPBase = 12,
	XPExponent = 1.55, -- XP to reach the next level = XPBase * level ^ XPExponent
	CoinBonusPer = 0.02, -- +2% coins per level
	GemsPerLevel = 5,
	MilestoneEvery = 10,
	MilestoneGems = 100,
}

-- random mini events between meteors keep every few minutes exciting
Config.Events = {
	IntervalSeconds = 300,
	DurationSeconds = 75,
	List = {
		{
			Id = "Frenzy",
			Name = "⚡ ORE FRENZY",
			Description = "Ores respawn 4x faster!",
			Color = Color3.fromRGB(255, 220, 80),
			RespawnMult = 0.25,
		},
		{
			Id = "LuckyRush",
			Name = "🍀 LUCKY RUSH",
			Description = "Golden & Rainbow ores are 5x more common!",
			Color = Color3.fromRGB(120, 255, 140),
			LuckyMult = 5,
		},
		{
			Id = "GemStorm",
			Name = "💎 GEM STORM",
			Description = "Every ore can drop gems!",
			Color = Color3.fromRGB(80, 220, 255),
			GemChance = 0.15,
		},
		{
			Id = "Blizzard",
			Name = "❄️ BLIZZARD",
			Description = "Hatched pets can be FROZEN (2.5x income)!",
			Color = Color3.fromRGB(150, 220, 255),
		},
		{
			Id = "HeatWave",
			Name = "🔥 HEAT WAVE",
			Description = "Hatched pets can be MOLTEN (3x income)!",
			Color = Color3.fromRGB(255, 120, 50),
		},
		{
			Id = "Starfall",
			Name = "🌌 STARFALL",
			Description = "Stars fall 3x faster + GALAXY pets!",
			Color = Color3.fromRGB(170, 120, 255),
			StarMult = 3,
		},
		{
			Id = "DoubleOre",
			Name = "💰 DOUBLE ORE",
			Description = "All ore is worth 2x!",
			Color = Color3.fromRGB(255, 170, 60),
			ValueMult = 2,
		},
	},
}

-- first-time tutorial: one clear goal at a time, small reward per step
Config.Tutorial = {
	Steps = {
		{ Id = "Mine", Target = 8, Text = "Tap ore blocks to mine them", Reward = { Coins = 150 } },
		{ Id = "Pickaxe", Target = 1, Text = "Buy a better pickaxe at the shop", Reward = { Coins = 300 } },
		{ Id = "Hatch", Target = 1, Text = "Hatch your first pet from the Meadow Egg", Reward = { Gems = 30 } },
		{ Id = "Shard", Target = 1, Text = "Grab the falling star 🌠 and carry it to your base 🏠", Reward = { Gems = 50 } },
	},
	FinalReward = { Gems = 100, Boost = { "Coins2x", 600 } },
}

---------------------------------------------------------------------------
-- Star Shards + Bases (the signature loop)
-- Falling stars and meteors drop shards. Carry one home (you're slower and
-- anyone can bonk you to make you drop it) and put it on a pedestal in your
-- base: it earns coins every second, even while you're offline. Other players
-- can sneak in and steal shards from your base - bonk them to get it back.
---------------------------------------------------------------------------
Config.Shards = {
	Order = { "Common", "Rare", "Epic", "Legendary", "Mythic", "Secret" },
	Rarities = {
		Common = { Name = "Star Egg", Luck = 1, Income = 0.5, Weight = 55, Speed = 0.92, Color = Color3.fromRGB(190, 230, 255) },
		Rare = { Name = "Comet Egg", Luck = 2, Income = 1.5, Weight = 26, Speed = 0.88, Color = Color3.fromRGB(70, 160, 255) },
		Epic = { Name = "Nebula Egg", Luck = 4, Income = 5, Weight = 12, Speed = 0.82, Color = Color3.fromRGB(185, 80, 255) },
		Legendary = { Name = "Solar Egg", Luck = 8, Income = 15, Weight = 5, Speed = 0.76, Color = Color3.fromRGB(255, 195, 40) },
		Mythic = { Name = "Supernova Egg", Luck = 16, Income = 50, Weight = 1.6, Speed = 0.7, Color = Color3.fromRGB(255, 70, 150) },
		Secret = { Name = "Black Hole Egg", Luck = 40, Income = 200, Weight = 0.4, Speed = 0.62, Color = Color3.fromRGB(120, 40, 255) },
	},
	-- the egg a falling star carries depends on where it lands (hub = zone 1)
	ZoneEggs = { "Meadow", "Frost", "Lava", "Void", "Cosmic" },
	-- (legacy) shard income scaling - shards are star eggs now
	ZoneMult = { 1, 8, 60, 500, 4000 },
	SellSeconds = 120, -- selling a shard pays this many seconds of its income
	Points = { 10, 20, 45, 100, 250, 600 }, -- weekly ranked points per delivery, by rarity
	GroundLifetime = 90,
	ReturnSeconds = 10, -- a dropped STOLEN shard flies home if nobody grabs it
	RegrabDelay = 1.5, -- the player who dropped it can't grab it back instantly
	FallingStar = { MinInterval = 40, MaxInterval = 70, HubChance = 0.25, LuckPerZone = 0.6 },
	Meteor = { Count = 4, PerParticipant = 1, Max = 10, Luck = 3, TopPriority = 5 },
}

Config.Base = {
	-- one base per player: the place's server size is set to the same number
	-- (8 like the big steal games: everyone gets a roomy territory, phones stay smooth)
	Plots = 8,
	PlotSize = 72, -- studs: the whole territory (fence to fence)
	-- territories: two rows facing a central avenue, wide gardens in between
	Layout = { Columns = 4, Gap = 26, EntranceGap = 44, Avenue = 30, Margin = 8 },
	StartPedestals = 3, -- placed for free in every new base
	MaxPedestals = 12,
	-- price of the Nth pedestal (first 3 are free)
	PedestalCosts = { 0, 0, 0, 500, 3000, 15000, 75000, 400000, 2000000, 10000000, 50000000, 250000000 },
	-- vault pedestals: pets on them can NEVER be stolen, but earn less
	VaultIncome = 0.5,
	VaultCosts = { 0, 2500, 40000, 600000, 8000000, 90000000 },
	VipVaults = 1, -- VIP: +1 vault pedestal
	StorageMax = 10, -- (legacy)
	Cell = 2, -- placement grid in studs
	-- house levels: bigger land, more decorations, more vaults, fancier walls.
	-- Build = buildable area in plot space (the entrance strip stays clear)
	Levels = {
		{
			Name = "Cozy Cottage",
			Cost = 0,
			Build = { MinX = -16, MaxX = 16, MinZ = -20, MaxZ = 16 },
			MaxItems = 45,
			Vaults = 1,
			Style = "Wood",
		},
		{
			Name = "Stone Villa",
			Cost = 2500,
			Build = { MinX = -20, MaxX = 20, MinZ = -22, MaxZ = 20 },
			MaxItems = 60,
			Vaults = 2,
			Style = "Stone",
		},
		{
			Name = "Golden Manor",
			Cost = 60000,
			Build = { MinX = -24, MaxX = 24, MinZ = -24, MaxZ = 24 },
			MaxItems = 80,
			Vaults = 2,
			Style = "Gold",
		},
		{
			Name = "Crystal Palace",
			Cost = 1500000,
			Build = { MinX = -28, MaxX = 28, MinZ = -26, MaxZ = 28 },
			MaxItems = 100,
			Vaults = 3,
			Style = "Crystal",
		},
		{
			Name = "Galaxy Castle",
			Cost = 40000000,
			Build = { MinX = -32, MaxX = 32, MinZ = -26, MaxZ = 32 },
			MaxItems = 120,
			Vaults = 4,
			Style = "Galaxy",
		},
	},
	NameMax = 20, -- custom house name length (filtered by Roblox)
	OfflineRate = 0.5, -- offline earnings = 50% of the normal rate
	OfflineMaxSeconds = 7200, -- ... for up to 2 hours
	-- protection: nobody can rob you while you're offline, and while online
	-- you can never lose everything
	LockSeconds = 60,
	LockPerRebirth = 10, -- +10s lock per rebirth ...
	LockMaxBonus = 120, -- ... up to +2 minutes
	LockVipBonus = 10,
	LockCooldown = 150,
	JoinLockSeconds = 60, -- your base starts locked when you join
	NewbieShieldSeconds = 1200, -- first 20 minutes of play: can't be robbed (stealing ends it)
	TheftShieldSeconds = 180, -- after a theft your base is protected for 3 minutes
	StealGap = 3, -- you can't rob someone whose pets are worth less than 1/3 of yours
	StealGapMinWorth = 60, -- (tiny bases don't count toward the gap rule)
	RevengeSeconds = 300, -- the victim may raid the thief's base for 5 min (locks don't stop them)
	-- serial thieves get a bounty: rob 2+ different players within 15 min
	Bounty = { MinVictims = 2, WindowSeconds = 900, IncomeSeconds = 60 },
	StealHold = 1.2,
	TrapStun = 2.5, -- seconds a trap freezes a thief
	TrapCooldown = 6,
	LikePoints = 15, -- weekly ranked points per like received
	LikeGems = 2, -- the owner gets a few gems per like (max per day below)
	LikeGemsDaily = 40,
}

-- house wall styles: the level decides the default look, skins override it
Config.HouseStyles = {
	Wood = {
		Wall = Color3.fromRGB(170, 120, 75),
		WallMaterial = "WoodPlanks",
		Trim = Color3.fromRGB(255, 210, 140),
		Ground = Color3.fromRGB(105, 160, 80),
		GroundMaterial = "Grass",
		Pillar = Color3.fromRGB(120, 85, 55),
	},
	Stone = {
		Wall = Color3.fromRGB(165, 165, 175),
		WallMaterial = "Cobblestone",
		Trim = Color3.fromRGB(140, 220, 255),
		Ground = Color3.fromRGB(95, 155, 85),
		GroundMaterial = "Grass",
		Pillar = Color3.fromRGB(120, 120, 135),
	},
	Gold = {
		Wall = Color3.fromRGB(235, 225, 205),
		WallMaterial = "Marble",
		Trim = Color3.fromRGB(255, 205, 60),
		Ground = Color3.fromRGB(90, 165, 95),
		GroundMaterial = "Grass",
		Pillar = Color3.fromRGB(255, 200, 60),
		Aura = Color3.fromRGB(255, 220, 120),
	},
	Crystal = {
		Wall = Color3.fromRGB(170, 230, 255),
		WallMaterial = "Glass",
		WallTransparency = 0.35,
		Trim = Color3.fromRGB(120, 240, 255),
		Ground = Color3.fromRGB(200, 235, 255),
		GroundMaterial = "Ice",
		Pillar = Color3.fromRGB(140, 220, 255),
		Aura = Color3.fromRGB(150, 230, 255),
	},
	Galaxy = {
		Wall = Color3.fromRGB(40, 25, 80),
		WallMaterial = "Glass",
		WallTransparency = 0.2,
		Trim = Color3.fromRGB(200, 110, 255),
		Ground = Color3.fromRGB(35, 30, 70),
		GroundMaterial = "Slate",
		Pillar = Color3.fromRGB(150, 80, 255),
		Aura = Color3.fromRGB(210, 140, 255),
	},
	-- skins
	Sakura = {
		Wall = Color3.fromRGB(255, 205, 220),
		WallMaterial = "WoodPlanks",
		Trim = Color3.fromRGB(255, 120, 170),
		Ground = Color3.fromRGB(255, 225, 235),
		GroundMaterial = "Grass",
		Pillar = Color3.fromRGB(200, 90, 120),
		Aura = Color3.fromRGB(255, 170, 200),
	},
	Candy = {
		Wall = Color3.fromRGB(255, 240, 245),
		WallMaterial = "SmoothPlastic",
		Trim = Color3.fromRGB(255, 90, 120),
		Ground = Color3.fromRGB(150, 230, 200),
		GroundMaterial = "SmoothPlastic",
		Pillar = Color3.fromRGB(255, 120, 200),
		Stripes = Color3.fromRGB(255, 90, 120),
	},
	Royal = {
		Wall = Color3.fromRGB(90, 40, 140),
		WallMaterial = "Fabric",
		Trim = Color3.fromRGB(255, 200, 60),
		Ground = Color3.fromRGB(70, 35, 110),
		GroundMaterial = "Carpet",
		Pillar = Color3.fromRGB(255, 200, 60),
		Aura = Color3.fromRGB(255, 210, 90),
	},
	Neon = {
		Wall = Color3.fromRGB(20, 20, 30),
		WallMaterial = "Metal",
		Trim = Color3.fromRGB(60, 255, 230),
		Ground = Color3.fromRGB(25, 25, 40),
		GroundMaterial = "Metal",
		Pillar = Color3.fromRGB(60, 255, 230),
		Aura = Color3.fromRGB(60, 255, 230),
	},
}
-- skins: "Auto" follows your house level. Need: Gems price, VIP pass,
-- a house level, or a Robux product (Products.HouseSkinNeon)
Config.HouseSkins = {
	{ Id = "Auto", Name = "Level Style", Icon = "🏠" },
	{ Id = "Sakura", Name = "Sakura", Icon = "🌸", Gems = 600 },
	{ Id = "Candy", Name = "Candy", Icon = "🍬", Gems = 900 },
	{ Id = "Royal", Name = "Royal", Icon = "👑", Pass = "VIP" },
	{ Id = "Neon", Name = "Neon City", Icon = "🌃", Product = "HouseSkinNeon" },
	{ Id = "Galaxy", Name = "Galaxy", Icon = "🌌", Level = 5 },
}

-- paint: tap a decoration in build mode -> 🎨 cycles these colors (free)
Config.Paint = {
	Color3.fromRGB(255, 90, 90),
	Color3.fromRGB(255, 160, 60),
	Color3.fromRGB(255, 225, 80),
	Color3.fromRGB(120, 220, 90),
	Color3.fromRGB(60, 200, 170),
	Color3.fromRGB(80, 170, 255),
	Color3.fromRGB(120, 110, 255),
	Color3.fromRGB(200, 110, 255),
	Color3.fromRGB(255, 130, 200),
	Color3.fromRGB(250, 250, 250),
	Color3.fromRGB(70, 70, 80),
	Color3.fromRGB(150, 100, 60),
}

-- decoration sets: own at least one of every item -> bonus base income
Config.DecorSets = {
	{ Id = "Garden", Name = "Garden Set", Icon = "🌷", Items = { "Tree", "Flowers", "Bush", "Pond" }, Bonus = 0.05 },
	{ Id = "Cozy", Name = "Cozy Set", Icon = "🛋️", Items = { "Sofa", "Table", "Chair", "Lantern" }, Bonus = 0.05 },
	{ Id = "Camp", Name = "Camping Set", Icon = "🏕️", Items = { "Campfire", "Pine", "Mushroom", "Rock" }, Bonus = 0.05 },
	{ Id = "Party", Name = "Party Set", Icon = "🎉", Items = { "Swing", "Gnome", "Flag", "Fountain" }, Bonus = 0.08 },
	{ Id = "Royal", Name = "Royal Set", Icon = "👑", Items = { "Throne", "Trophy", "Statue", "Carpet" }, Bonus = 0.1 },
	{ Id = "Neon", Name = "Neon Set", Icon = "🌀", Items = { "NeonArch", "Crystal", "LampPost", "Windmill" }, Bonus = 0.1 },
}

-- Decorations: buy & place anything in your base. All refundable (100%),
-- so redecorating is free. Size is the footprint in grid cells (2 studs).
-- Layer "Floor" items sit under everything else.
Config.DecorCategories = {
	{ Id = "Base", Name = "Base", Icon = "🏠" },
	{ Id = "Nature", Name = "Nature", Icon = "🌳" },
	{ Id = "Furniture", Name = "Furniture", Icon = "🪑" },
	{ Id = "Lights", Name = "Lights", Icon = "💡" },
	{ Id = "Fun", Name = "Fun", Icon = "🗿" },
	{ Id = "Floor", Name = "Floors", Icon = "🟫" },
	{ Id = "Premium", Name = "Premium", Icon = "💎" },
}
Config.Decor = {
	-- base (functional)
	Pedestal = { Name = "Pet Pedestal", Category = "Base", Icon = "🌠", Size = { 2, 2 }, Price = 0, Function = "Pedestal" },
	Vault = { Name = "Vault Pedestal", Category = "Base", Icon = "🔒", Size = { 2, 2 }, Price = 0, Function = "Vault" },
	Trap = { Name = "Stun Trap", Category = "Base", Icon = "⚡", Size = { 2, 2 }, Price = 2500, Limit = 4, Function = "Trap" },
	JumpPad = { Name = "Jump Pad", Category = "Base", Icon = "🦘", Size = { 2, 2 }, Price = 800, Limit = 4, Function = "Jump" },
	-- nature
	Tree = { Name = "Tree", Category = "Nature", Icon = "🌳", Size = { 2, 2 }, Price = 120 },
	Pine = { Name = "Pine Tree", Category = "Nature", Icon = "🌲", Size = { 2, 2 }, Price = 150 },
	Bush = { Name = "Bush", Category = "Nature", Icon = "🌿", Size = { 1, 1 }, Price = 40 },
	Flowers = { Name = "Flower Bed", Category = "Nature", Icon = "🌷", Size = { 2, 1 }, Price = 60 },
	Rock = { Name = "Rock", Category = "Nature", Icon = "🪨", Size = { 1, 1 }, Price = 30 },
	Hedge = { Name = "Hedge", Category = "Nature", Icon = "🟩", Size = { 2, 1 }, Price = 50 },
	Mushroom = { Name = "Mushroom", Category = "Nature", Icon = "🍄", Size = { 1, 1 }, Price = 90 },
	Pond = { Name = "Pond", Category = "Nature", Icon = "🐟", Size = { 3, 2 }, Price = 600 },
	-- furniture
	Bench = { Name = "Bench", Category = "Furniture", Icon = "🪑", Size = { 2, 1 }, Price = 100 },
	Table = { Name = "Table", Category = "Furniture", Icon = "🍽️", Size = { 2, 2 }, Price = 150 },
	Chair = { Name = "Chair", Category = "Furniture", Icon = "💺", Size = { 1, 1 }, Price = 60 },
	Sofa = { Name = "Sofa", Category = "Furniture", Icon = "🛋️", Size = { 3, 1 }, Price = 300 },
	Fence = { Name = "Fence", Category = "Furniture", Icon = "🚧", Size = { 2, 1 }, Price = 25 },
	-- lights
	Lantern = { Name = "Lantern", Category = "Lights", Icon = "🏮", Size = { 1, 1 }, Price = 80 },
	LampPost = { Name = "Lamp Post", Category = "Lights", Icon = "💡", Size = { 1, 1 }, Price = 140 },
	Crystal = { Name = "Glow Crystal", Category = "Lights", Icon = "🔮", Size = { 1, 1 }, Price = 400 },
	-- fun
	Statue = { Name = "Star Statue", Category = "Fun", Icon = "⭐", Size = { 2, 2 }, Price = 1500 },
	Fountain = { Name = "Fountain", Category = "Fun", Icon = "⛲", Size = { 3, 3 }, Price = 2500 },
	Trophy = { Name = "Trophy", Category = "Fun", Icon = "🏆", Size = { 1, 1 }, Price = 5000 },
	Flag = { Name = "Flag", Category = "Fun", Icon = "🚩", Size = { 1, 1 }, Price = 200 },
	Gnome = { Name = "Garden Gnome", Category = "Fun", Icon = "🧙", Size = { 1, 1 }, Price = 350 },
	Campfire = { Name = "Campfire", Category = "Fun", Icon = "🔥", Size = { 2, 2 }, Price = 450 },
	Swing = { Name = "Swing", Category = "Fun", Icon = "🎠", Size = { 3, 2 }, Price = 1200, MinLevel = 2 },
	Windmill = { Name = "Windmill", Category = "Fun", Icon = "🌬️", Size = { 3, 3 }, Price = 8000, MinLevel = 3 },
	-- floors (4x4 tiles)
	WoodFloor = { Name = "Wood Floor", Category = "Floor", Icon = "🟫", Size = { 2, 2 }, Price = 20, Layer = "Floor" },
	StoneFloor = { Name = "Stone Floor", Category = "Floor", Icon = "⬜", Size = { 2, 2 }, Price = 20, Layer = "Floor" },
	GrassFloor = { Name = "Grass Floor", Category = "Floor", Icon = "🟩", Size = { 2, 2 }, Price = 15, Layer = "Floor" },
	Carpet = { Name = "Red Carpet", Category = "Floor", Icon = "🟥", Size = { 2, 2 }, Price = 40, Layer = "Floor" },
	-- premium (gems)
	Throne = { Name = "Galaxy Throne", Category = "Premium", Icon = "👑", Size = { 2, 2 }, Gems = 250 },
	RainbowFountain = { Name = "Rainbow Fountain", Category = "Premium", Icon = "🌈", Size = { 3, 3 }, Gems = 500 },
	NeonArch = { Name = "Neon Arch", Category = "Premium", Icon = "🌀", Size = { 3, 1 }, Gems = 150 },
}
-- display order inside each category
Config.DecorOrder = {
	"Pedestal",
	"Vault",
	"Trap",
	"JumpPad",
	"Tree",
	"Pine",
	"Bush",
	"Flowers",
	"Rock",
	"Hedge",
	"Mushroom",
	"Pond",
	"Bench",
	"Table",
	"Chair",
	"Sofa",
	"Fence",
	"Lantern",
	"LampPost",
	"Crystal",
	"Statue",
	"Fountain",
	"Trophy",
	"Flag",
	"Gnome",
	"Campfire",
	"Swing",
	"Windmill",
	"WoodFloor",
	"StoneFloor",
	"GrassFloor",
	"Carpet",
	"Throne",
	"RainbowFountain",
	"NeonArch",
}
-- what a brand-new base starts with (plot space, studs)
Config.StarterBase = {
	{ Id = "Pedestal", X = -6, Z = 2, R = 0 },
	{ Id = "Pedestal", X = 0, Z = 2, R = 0 },
	{ Id = "Pedestal", X = 6, Z = 2, R = 0 },
	{ Id = "Vault", X = 0, Z = 10, R = 0 },
	{ Id = "Tree", X = -12, Z = 12, R = 0 },
	{ Id = "Tree", X = 12, Z = 12, R = 0 },
	{ Id = "Lantern", X = -9, Z = -9, R = 0 },
	{ Id = "Lantern", X = 9, Z = -9, R = 0 },
}

-- running speed upgrades: faster = steal more, escape guardians and thieves
Config.Boots = {
	{ Name = "Sneakers", Bonus = 0, Cost = 0 },
	{ Name = "Runner Shoes", Bonus = 0.08, Cost = 400 },
	{ Name = "Sprint Shoes", Bonus = 0.16, Cost = 2500 },
	{ Name = "Turbo Boots", Bonus = 0.25, Cost = 15000 },
	{ Name = "Jet Boots", Bonus = 0.35, Cost = 90000 },
	{ Name = "Comet Boots", Bonus = 0.45, Cost = 600000 },
	{ Name = "Warp Boots", Bonus = 0.55, Cost = 4000000 },
	{ Name = "Lightspeed Boots", Bonus = 0.7, Cost = 30000000 },
}

-- star guardians: rock golems that protect fallen stars and chase whoever grabs one
Config.Guardian = {
	MinRarity = 2, -- Rare+ stars get a guardian
	Speed = 16, -- + per rarity step
	SpeedPerRarity = 0.8,
	ChaseSeconds = 12,
	ChaseRange = 140, -- gives up beyond this distance from its star
	CatchRange = 4.5,
	StunSeconds = 2.5, -- bonking a guardian stuns it
}

-- free prize wheel (retention): one free spin every few hours
Config.Spin = {
	CooldownSeconds = 4 * 3600,
	VipCooldownSeconds = 2 * 3600,
	Rewards = {
		{ Weight = 28, Reward = { Gems = 30 }, Color = Color3.fromRGB(80, 200, 255) },
		{ Weight = 20, Reward = { Gems = 75 }, Color = Color3.fromRGB(60, 150, 255) },
		{ Weight = 16, Reward = { Boost = { "Coins2x", 900 } }, Color = Color3.fromRGB(255, 200, 60) },
		{ Weight = 14, Reward = { Boost = { "Luck2x", 900 } }, Color = Color3.fromRGB(90, 220, 110) },
		{ Weight = 10, Reward = { Stardust = 200 }, Color = Color3.fromRGB(255, 110, 220) },
		{ Weight = 7, Reward = { Boost = { "Power2x", 1200 } }, Color = Color3.fromRGB(255, 100, 80) },
		{ Weight = 4, Reward = { Gems = 400 }, Color = Color3.fromRGB(170, 90, 255) },
		{ Weight = 1, Reward = { Gems = 2000 }, Color = Color3.fromRGB(255, 230, 120), Jackpot = true },
	},
}

-- promo codes: post them on YouTube / TikTok / Discord / group wall.
-- Players search "Meteor Miners codes" -> free marketing. ExpiresAt = unix time (0 = never)
Config.Codes = {
	RELEASE = { Reward = { Gems = 250 }, ExpiresAt = 0 },
	METEOR = { Reward = { Stardust = 200 }, ExpiresAt = 0 },
	LUCKY = { Reward = { Boost = { "Luck2x", 900 } }, ExpiresAt = 0 },
}

---------------------------------------------------------------------------
-- Sounds: Ids (one picked at random), Volume, Pitch, random pitch Variance.
-- Built-in classic Roblox sounds work with zero uploads. To upgrade, pick
-- sounds in Studio Toolbox -> Audio (Creator Store) and paste "rbxassetid://123".
---------------------------------------------------------------------------
Config.Sounds = {
	UI = { Ids = { "rbxasset://sounds/snap.mp3" }, Volume = 0.35, Pitch = 1.6, Variance = 0.05 },
	Swing = { Ids = { "rbxasset://sounds/swordslash.mp3" }, Volume = 0.15, Pitch = 1.25, Variance = 0.12 },
	HitStone = {
		Ids = { "rbxasset://sounds/stone.mp3", "rbxasset://sounds/stone2.mp3", "rbxasset://sounds/stone3.mp3" },
		Volume = 0.55,
		Pitch = 1,
		Variance = 0.15,
	},
	HitMetal = {
		Ids = { "rbxasset://sounds/metal.mp3", "rbxasset://sounds/metal2.mp3", "rbxasset://sounds/metal3.mp3" },
		Volume = 0.45,
		Pitch = 1.1,
		Variance = 0.15,
	},
	HitIce = {
		Ids = { "rbxasset://sounds/ice.mp3", "rbxasset://sounds/ice2.mp3", "rbxasset://sounds/ice3.mp3" },
		Volume = 0.45,
		Pitch = 1.1,
		Variance = 0.15,
	},
	Break = { Ids = { "rbxasset://sounds/collide.mp3" }, Volume = 0.22, Pitch = 1.7, Variance = 0.2 },
	Crit = { Ids = { "rbxasset://sounds/bass.mp3" }, Volume = 0.55, Pitch = 1.5, Variance = 0.05 },
	Coin = { Ids = { "rbxasset://sounds/electronicpingshort.mp3" }, Volume = 0.4, Pitch = 1.3, Variance = 0.05 },
	Lucky = { Ids = { "rbxasset://sounds/victory.mp3" }, Volume = 0.7, Pitch = 1.3, Variance = 0 },
	LevelUp = { Ids = { "rbxasset://sounds/victory.mp3" }, Volume = 0.6, Pitch = 1, Variance = 0 },
	Hatch = { Ids = { "rbxasset://sounds/snap.mp3" }, Volume = 0.6, Pitch = 0.9, Variance = 0.1 },
	Legendary = { Ids = { "rbxasset://sounds/victory.mp3" }, Volume = 0.9, Pitch = 1.15, Variance = 0 },
	MeteorWarn = { Ids = { "rbxasset://sounds/bass.mp3" }, Volume = 0.8, Pitch = 0.6, Variance = 0 },
	Impact = { Ids = { "rbxasset://sounds/collide.mp3" }, Volume = 1, Pitch = 0.55, Variance = 0.05 },
	Bonked = { Ids = { "rbxasset://sounds/uuhhh.mp3" }, Volume = 0.6, Pitch = 1, Variance = 0.1 },
	SpinTick = { Ids = { "rbxasset://sounds/snap.mp3" }, Volume = 0.3, Pitch = 2, Variance = 0.05 },
	Reward = { Ids = { "rbxasset://sounds/electronicpingshort.mp3" }, Volume = 0.6, Pitch = 1.6, Variance = 0 },
	RankUp = { Ids = { "rbxasset://sounds/victory.mp3" }, Volume = 0.7, Pitch = 1.25, Variance = 0 },
	Event = { Ids = { "rbxasset://sounds/bass.mp3" }, Volume = 0.6, Pitch = 1.2, Variance = 0 },
}

-- optional looping background music (Creator Store audio ids, "" = off)
Config.Music = { Hub = "", Mine = "", Meteor = "", Volume = 0.3 }

return Config
