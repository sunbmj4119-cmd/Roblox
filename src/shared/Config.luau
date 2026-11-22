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
-- Zones (linear progression, last zone is the PvP "Star Crater")
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
		PvP = true,
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
	OreRespawnSeconds = 7,
	OreSize = 5,
	OreSpacing = 7,
	Reach = 13, -- studs from character to the target
}

---------------------------------------------------------------------------
-- Upgrades
---------------------------------------------------------------------------
Config.Pickaxes = {
	{ Name = "Wooden Pickaxe", Power = 1, Cooldown = 0.5, Cost = 0, Color = Color3.fromRGB(150, 105, 60) },
	{ Name = "Stone Pickaxe", Power = 2, Cooldown = 0.48, Cost = 150, Color = Color3.fromRGB(130, 130, 130) },
	{ Name = "Copper Pickaxe", Power = 4, Cooldown = 0.46, Cost = 800, Color = Color3.fromRGB(200, 115, 60) },
	{ Name = "Iron Pickaxe", Power = 8, Cooldown = 0.44, Cost = 3500, Color = Color3.fromRGB(205, 190, 175) },
	{ Name = "Gold Pickaxe", Power = 15, Cooldown = 0.42, Cost = 15000, Color = Color3.fromRGB(255, 200, 40) },
	{ Name = "Diamond Pickaxe", Power = 30, Cooldown = 0.4, Cost = 60000, Color = Color3.fromRGB(150, 240, 255) },
	{ Name = "Obsidian Pickaxe", Power = 60, Cooldown = 0.38, Cost = 250000, Color = Color3.fromRGB(60, 30, 80) },
	{ Name = "Frost Fang", Power = 120, Cooldown = 0.36, Cost = 1000000, Color = Color3.fromRGB(120, 200, 255) },
	{ Name = "Magma Breaker", Power = 250, Cooldown = 0.34, Cost = 4500000, Color = Color3.fromRGB(255, 90, 30) },
	{ Name = "Void Splitter", Power = 550, Cooldown = 0.32, Cost = 20000000, Color = Color3.fromRGB(170, 90, 255) },
	{ Name = "Starforged", Power = 1200, Cooldown = 0.3, Cost = 90000000, Color = Color3.fromRGB(255, 90, 200) },
	{ Name = "Galaxy Crusher", Power = 2600, Cooldown = 0.28, Cost = 400000000, Color = Color3.fromRGB(60, 255, 230) },
}

Config.Backpacks = {
	{ Name = "Pouch", Capacity = 50, Cost = 0 },
	{ Name = "Sack", Capacity = 150, Cost = 200 },
	{ Name = "Satchel", Capacity = 500, Cost = 1000 },
	{ Name = "Explorer Pack", Capacity = 1500, Cost = 4000 },
	{ Name = "Duffel", Capacity = 5000, Cost = 18000 },
	{ Name = "Ore Crate", Capacity = 15000, Cost = 75000 },
	{ Name = "Vault Pack", Capacity = 50000, Cost = 300000 },
	{ Name = "Titan Pack", Capacity = 150000, Cost = 1200000 },
	{ Name = "Galaxy Pack", Capacity = 500000, Cost = 5000000 },
	{ Name = "Nebula Pack", Capacity = 2000000, Cost = 22000000 },
	{ Name = "Black Hole", Capacity = 8000000, Cost = 100000000 },
	{ Name = "Infinity Core", Capacity = 30000000, Cost = 450000000 },
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
Config.MaxPets = 60

-- Power: equipped pets add their power to the mining damage multiplier.
Config.Pets = {
	-- Meadow
	Bunny = { Rarity = "Common", Power = 0.1, Color = Color3.fromRGB(245, 245, 245), Shape = "Ball", Ears = true },
	Chick = { Rarity = "Common", Power = 0.15, Color = Color3.fromRGB(255, 230, 90), Shape = "Ball" },
	Puppy = { Rarity = "Uncommon", Power = 0.3, Color = Color3.fromRGB(190, 140, 90), Shape = "Block", Ears = true },
	Kitty = { Rarity = "Uncommon", Power = 0.35, Color = Color3.fromRGB(255, 160, 80), Shape = "Block", Ears = true },
	Fox = { Rarity = "Rare", Power = 0.8, Color = Color3.fromRGB(255, 110, 30), Shape = "Block", Ears = true },
	Owl = { Rarity = "Epic", Power = 2, Color = Color3.fromRGB(150, 110, 80), Shape = "Ball", Wings = true },
	["Golden Bunny"] = { Rarity = "Legendary", Power = 6, Color = Color3.fromRGB(255, 205, 50), Shape = "Ball", Ears = true },
	-- Frost
	Penguin = { Rarity = "Common", Power = 0.6, Color = Color3.fromRGB(40, 45, 60), Shape = "Ball", Wings = true },
	["Snow Fox"] = { Rarity = "Uncommon", Power = 1.2, Color = Color3.fromRGB(235, 245, 255), Shape = "Block", Ears = true },
	["Polar Bear"] = { Rarity = "Rare", Power = 2.5, Color = Color3.fromRGB(250, 250, 250), Shape = "Block", Ears = true },
	["Ice Owl"] = { Rarity = "Epic", Power = 6, Color = Color3.fromRGB(150, 220, 255), Shape = "Ball", Wings = true },
	["Frost Wolf"] = { Rarity = "Legendary", Power = 18, Color = Color3.fromRGB(110, 180, 255), Shape = "Block", Ears = true },
	Yeti = { Rarity = "Mythic", Power = 50, Color = Color3.fromRGB(200, 240, 255), Shape = "Block", Horns = true },
	-- Lava
	["Magma Slime"] = { Rarity = "Common", Power = 3, Color = Color3.fromRGB(255, 90, 30), Shape = "Ball" },
	["Fire Fox"] = { Rarity = "Uncommon", Power = 6, Color = Color3.fromRGB(255, 60, 20), Shape = "Block", Ears = true },
	["Lava Golem"] = { Rarity = "Rare", Power = 12, Color = Color3.fromRGB(90, 40, 30), Shape = "Block", Horns = true },
	["Phoenix Chick"] = { Rarity = "Epic", Power = 30, Color = Color3.fromRGB(255, 150, 30), Shape = "Ball", Wings = true },
	["Inferno Dragon"] = { Rarity = "Legendary", Power = 90, Color = Color3.fromRGB(200, 30, 20), Shape = "Block", Wings = true, Horns = true },
	["Sun Serpent"] = { Rarity = "Mythic", Power = 250, Color = Color3.fromRGB(255, 220, 60), Shape = "Ball", Horns = true },
	-- Void
	["Void Bat"] = { Rarity = "Common", Power = 15, Color = Color3.fromRGB(70, 40, 110), Shape = "Ball", Wings = true },
	["Shadow Cat"] = { Rarity = "Uncommon", Power = 30, Color = Color3.fromRGB(35, 25, 50), Shape = "Block", Ears = true },
	["Nebula Fox"] = { Rarity = "Rare", Power = 60, Color = Color3.fromRGB(150, 80, 255), Shape = "Block", Ears = true },
	["Rift Owl"] = { Rarity = "Epic", Power = 150, Color = Color3.fromRGB(90, 60, 200), Shape = "Ball", Wings = true },
	["Galaxy Dragon"] = { Rarity = "Legendary", Power = 450, Color = Color3.fromRGB(60, 40, 160), Shape = "Block", Wings = true, Horns = true },
	["Void Emperor"] = { Rarity = "Mythic", Power = 1200, Color = Color3.fromRGB(20, 10, 40), Shape = "Block", Horns = true },
	["Black Hole Kitty"] = { Rarity = "Secret", Power = 5000, Color = Color3.fromRGB(10, 10, 15), Shape = "Ball", Ears = true },
	-- Gem egg
	["Gem Pup"] = { Rarity = "Uncommon", Power = 2, Color = Color3.fromRGB(80, 230, 255), Shape = "Block", Ears = true },
	["Crystal Cat"] = { Rarity = "Rare", Power = 5, Color = Color3.fromRGB(170, 240, 255), Shape = "Block", Ears = true },
	["Prism Owl"] = { Rarity = "Epic", Power = 15, Color = Color3.fromRGB(255, 150, 255), Shape = "Ball", Wings = true },
	["Diamond Dragon"] = { Rarity = "Legendary", Power = 60, Color = Color3.fromRGB(190, 250, 255), Shape = "Block", Wings = true, Horns = true },
	["Jewel Phoenix"] = { Rarity = "Mythic", Power = 200, Color = Color3.fromRGB(255, 80, 200), Shape = "Ball", Wings = true },
	-- Cosmic egg (stardust only - earned in meteor events)
	["Comet Pup"] = { Rarity = "Rare", Power = 20, Color = Color3.fromRGB(120, 200, 255), Shape = "Block", Ears = true },
	["Meteor Cat"] = { Rarity = "Epic", Power = 60, Color = Color3.fromRGB(255, 120, 60), Shape = "Block", Ears = true },
	["Star Owl"] = { Rarity = "Legendary", Power = 200, Color = Color3.fromRGB(255, 240, 120), Shape = "Ball", Wings = true },
	["Supernova Dragon"] = { Rarity = "Mythic", Power = 800, Color = Color3.fromRGB(255, 60, 160), Shape = "Block", Wings = true, Horns = true },
	["Celestial Titan"] = { Rarity = "Secret", Power = 3000, Color = Color3.fromRGB(60, 255, 230), Shape = "Block", Horns = true },
	-- Golden egg (Robux)
	["Golden Pup"] = { Rarity = "Epic", Power = 50, Color = Color3.fromRGB(255, 210, 60), Shape = "Block", Ears = true },
	["Golden Cat"] = { Rarity = "Legendary", Power = 150, Color = Color3.fromRGB(255, 190, 30), Shape = "Block", Ears = true },
	["Golden Dragon"] = { Rarity = "Mythic", Power = 600, Color = Color3.fromRGB(255, 170, 0), Shape = "Block", Wings = true, Horns = true },
	["Midas King"] = { Rarity = "Secret", Power = 2500, Color = Color3.fromRGB(255, 230, 120), Shape = "Ball", Horns = true },
	-- Rewards-only pets
	["Starter Dino"] = { Rarity = "Epic", Power = 4, Color = Color3.fromRGB(90, 220, 120), Shape = "Block", Horns = true },
	["Rookie Rock"] = { Rarity = "Rare", Power = 5, Color = Color3.fromRGB(120, 120, 130), Shape = "Block" },
	["Impact Wolf"] = { Rarity = "Mythic", Power = 400, Color = Color3.fromRGB(255, 80, 60), Shape = "Block", Ears = true, Horns = true },
	["Champion Griffin"] = { Rarity = "Legendary", Power = 120, Color = Color3.fromRGB(255, 215, 0), Shape = "Ball", Wings = true },
}

-- Currency: "Coins" | "Gems" | "Stardust" | "Robux" (Robux eggs use Products below)
Config.Eggs = {
	Meadow = {
		Name = "Meadow Egg",
		Currency = "Coins",
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
		Description = "+25% coins, +1 pet slot, [VIP] chat tag, daily VIP chest (100 gems)",
	},
	DoubleCoins = { Id = 0, Name = "2x Coins", Price = 249, Icon = "🪙", Description = "Permanently double all coins from selling" },
	MegaPower = { Id = 0, Name = "2x Mining Power", Price = 199, Icon = "💥", Description = "Permanently double your mining damage" },
	AutoMine = { Id = 0, Name = "Auto Mine", Price = 149, Icon = "🤖", Description = "Mine automatically while holding your pickaxe" },
	AutoSell = { Id = 0, Name = "Auto Sell", Price = 129, Icon = "💰", Description = "Sell automatically when full + sell from anywhere" },
	ExtraPets = { Id = 0, Name = "+3 Pet Slots", Price = 199, Icon = "🐾", Description = "Equip 3 more pets at once" },
	Lucky = { Id = 0, Name = "Lucky Hatch", Price = 179, Icon = "🍀", Description = "+50% luck on every egg" },
	TripleHatch = { Id = 0, Name = "Triple Hatch", Price = 149, Icon = "🥚", Description = "Hatch 3 eggs at once" },
	BigBackpack = { Id = 0, Name = "2x Backpack", Price = 99, Icon = "🎒", Description = "Double backpack capacity" },
	Speed = { Id = 0, Name = "Rocket Boots", Price = 79, Icon = "👟", Description = "+50% walk speed" },
}
Config.GamePassOrder = { "VIP", "DoubleCoins", "MegaPower", "AutoMine", "AutoSell", "ExtraPets", "Lucky", "TripleHatch", "BigBackpack", "Speed" }

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
		Icon = "🪙",
		Kind = "CoinPack",
		Description = "Coins = 15 full backpacks (scales with you)",
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

Config.PvP = {
	BonkRange = 10,
	DropPercent = 0.25,
	ImmunitySeconds = 4,
	OrbLifetime = 25,
	PointsPerBonk = 10,
	Knockback = 55,
}

-- Weekly ranked ladder (points come from activity, not wealth -> fair competition)
Config.Ranks = {
	{ Name = "Bronze", Min = 0, Color = Color3.fromRGB(205, 127, 50), RewardGems = 0 },
	{ Name = "Silver", Min = 500, Color = Color3.fromRGB(200, 210, 220), RewardGems = 50 },
	{ Name = "Gold", Min = 2000, Color = Color3.fromRGB(255, 205, 50), RewardGems = 150 },
	{ Name = "Platinum", Min = 6000, Color = Color3.fromRGB(110, 230, 210), RewardGems = 400 },
	{ Name = "Diamond", Min = 15000, Color = Color3.fromRGB(120, 190, 255), RewardGems = 1000 },
	{ Name = "Master", Min = 35000, Color = Color3.fromRGB(255, 80, 160), RewardGems = 2500 },
}
Config.PointsPerBlock = { 1, 2, 3, 4, 6 } -- by zone index

Config.Leaderboards = {
	RefreshSeconds = 90,
	Boards = {
		{ Key = "Weekly", Title = "🏆 WEEKLY RANKED", Weekly = true },
		{ Key = "LifetimeCoins", Title = "🪙 RICHEST MINERS" },
		{ Key = "Rebirths", Title = "♻️ MOST REBIRTHS" },
	},
	WeeklyTopReward = { 5000, 3000, 2000, 1000, 1000, 500, 500, 500, 500, 500 }, -- gems for global top 10
}

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
	{ Id = "Sell10", Type = "Sell", Target = 10, Text = "Sell your ore 10 times", Reward = { Gems = 25 }, XP = 150, Points = 100 },
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
	{ Id = "Bonk5", Type = "Bonk", Target = 5, Text = "Bonk 5 players in Star Crater", Reward = { Gems = 60 }, XP = 250, Points = 200 },
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
		free = { Gems = 25 * tier // 5 * 2 }
		premium = { Gems = 60 * tier // 5 * 2 }
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
Config.Crit = { Chance = 0.1, Multiplier = 3 }

-- breaking blocks quickly in a row builds a combo: +2% ore per step (max +60%)
Config.Combo = { Window = 2.5, BonusPer = 0.02, MaxBonus = 0.6 }

-- any ore can spawn as a lucky variant (rarest first)
Config.LuckyOres = {
	{ Id = "Rainbow", Chance = 1 / 1500, ValueMult = 50, Gems = 15, HPMult = 3, Announce = true },
	{ Id = "Golden", Chance = 1 / 120, ValueMult = 10, Gems = 1, HPMult = 2 },
}

-- hatched pets can be Golden / Rainbow (luck increases the chance, max x4)
Config.PetVariants = {
	{ Id = "Rainbow", Chance = 1 / 300, PowerMult = 6 },
	{ Id = "Golden", Chance = 1 / 25, PowerMult = 2.5 },
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
			Id = "DoubleOre",
			Name = "🪙 DOUBLE ORE",
			Description = "All ore is worth 2x!",
			Color = Color3.fromRGB(255, 170, 60),
			ValueMult = 2,
		},
	},
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
