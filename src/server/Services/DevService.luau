--[[
	DevService: test cheats. Allowed in Studio, and for the game owner in live
	servers while Config.OwnerTestMode is true (see Util.CanTest).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Util = require(ReplicatedStorage.Shared.Util)

local Net = require(script.Parent.Net)

local Dev = {}
local Services

function Dev:Init(services)
	Services = services
end

function Dev:Start()
	local Data = Services.DataService
	Net:On("Dev", 0.2, function(player, command)
		if not Util.CanTest(Config, player) then
			return
		end
		local data = Data:Get(player)
		if not data then
			return
		end
		if command == "Coins" then
			local amount = math.max(1000000, data.Coins * 10)
			data.Coins += amount
			data.Stats.LifetimeCoins += amount
		elseif command == "Gems" then
			data.Gems += 10000
		elseif command == "Stardust" then
			data.Stardust += 5000
		elseif command == "Points" then
			Services.ProgressionService:AddPoints(player, 2500)
		elseif command == "XP" then
			Services.ProgressionService:AddSeasonXP(player, 5 * 2000)
		elseif command == "Meteor" then
			Services.MeteorService:Summon(player)
		elseif command == "Level" then
			Services.ProgressionService:AddXP(player, 2000)
		elseif command == "Event" then
			Services.EventService:Trigger()
		elseif command == "Rainbow" then
			Services.MiningService:DevRainbow(player)
		elseif command == "Spin" then
			data.FreeSpinAt = 0
		elseif command == "Star" then
			-- a falling star in the zone you're standing in (hub if outside the mines)
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart
			local zone = root and Services.WorldService:ZoneAt(root.Position) or 0
			Services.ShardService:FallingStar(math.min(zone, data.ZoneLevel))
		elseif command == "Shard" then
			local id = Util.RollShard(Config, 4)
			Services.ShardService:StartCarry(player, { Kind = "Egg", Rarity = id, Egg = "Meadow" }, nil)
		elseif command == "Huge" then
			-- a random huge pet from your best unlocked coin egg
			local zoneEgg = Config.Shards.ZoneEggs[math.clamp(data.ZoneLevel, 1, #Config.Shards.ZoneEggs)] or "Meadow"
			local pick = Util.WeightedPick(Config.Eggs[zoneEgg].Pets)
			Services.PetService:GrantPet(player, pick, "Huge")
		elseif command == "House" then
			-- free house level up (test the land / wall styles)
			data.Coins += (Config.Base.Levels[Util.HouseLevel(Config, data) + 1] or { Cost = 0 }).Cost
			Services.BaseService:Upgrade(player)
		elseif command == "Lucky" then
			Services.LuckyService:Rain(6)
		elseif command == "Party" then
			-- "admin event": a 10 minute party in EVERY server
			Services.EventService:GlobalParty(10)
		elseif command == "Titanic" then
			local zoneEgg = Config.Shards.ZoneEggs[math.clamp(data.ZoneLevel, 1, #Config.Shards.ZoneEggs)] or "Meadow"
			Services.PetService:GrantPet(player, Util.WeightedPick(Config.Eggs[zoneEgg].Pets), "Titanic")
		elseif command == "Reset" then
			local fresh = Util.DeepCopy(Data.Template)
			fresh.FirstJoin = os.time()
			for key in data do
				data[key] = nil
			end
			for key, value in fresh do
				data[key] = value
			end
			Services.CharacterService:GivePickaxe(player)
			Services.PetService:RefreshEquipped(player)
		end
		Net:Notify(player, "[DEV] " .. tostring(command))
		Data:MarkDirty(player)
	end)
end

return Dev
