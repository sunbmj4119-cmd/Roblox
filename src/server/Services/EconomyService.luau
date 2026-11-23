--[[
	EconomyService: pickaxe upgrades, zone unlocks, rebirths and teleports.
	(Ore pays coins the moment it breaks - see MiningService.)
	All prices are validated on the server.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Net = require(script.Parent.Net)

local Economy = {}
local Services
local Data

local RED = Color3.fromRGB(255, 110, 110)
local REBIRTH_ANNOUNCE = { [1] = true, [5] = true, [10] = true, [25] = true, [50] = true, [100] = true }

local function notEnough(player: Player, need: number, have: number, currency: string)
	Net:Notify(player, "Not enough %s! Need %s more.", RED, currency, Util.Format(need - have))
end

function Economy:UnlockZone(player: Player, index: number)
	local data = Data:Get(player)
	local zone = Config.Zones[index]
	if not data or not zone then
		return
	end
	if data.ZoneLevel >= index then
		return
	end
	if data.ZoneLevel + 1 < index then
		Net:Notify(player, "Unlock %s first!", RED, Config.Zones[data.ZoneLevel + 1].Name)
		return
	end
	if data.Coins < zone.Cost then
		notEnough(player, zone.Cost, data.Coins, "coins")
		return
	end
	data.Coins -= zone.Cost
	data.ZoneLevel = index
	Net:Send(player, "ZoneUnlocked", index)
	Net:Notify(player, "🔓 %s unlocked!", Color3.fromRGB(120, 255, 170), zone.Name)
	if zone.PvP then
		Net:Announce("⚔️ %s entered the Star Crater!", Color3.fromRGB(255, 90, 120), player.DisplayName)
	end
	Services.ProgressionService:AddQuest(player, "Upgrade", 1)
	Data:MarkDirty(player)
end

local function buyUpgrade(player: Player, listName: string, field: string)
	local data = Data:Get(player)
	if not data then
		return
	end
	local list = Config[listName]
	local nextTier = data[field] + 1
	local item = list[nextTier]
	if not item then
		Net:Notify(player, "You already own the best one!")
		return
	end
	if data.Coins < item.Cost then
		notEnough(player, item.Cost, data.Coins, "coins")
		return
	end
	data.Coins -= item.Cost
	data[field] = nextTier
	if field == "PickaxeTier" then
		Services.CharacterService:GivePickaxe(player)
		Services.ProgressionService:TutorialEvent(player, "Pickaxe", 1)
	end
	Services.ProgressionService:AddQuest(player, "Upgrade", 1)
	Net:Notify(player, "✅ Bought %s!", Color3.fromRGB(120, 255, 170), item.Name)
	Data:MarkDirty(player)
end

function Economy:Rebirth(player: Player)
	local data = Data:Get(player)
	if not data then
		return
	end
	local cost = Util.RebirthCost(Config, data.Rebirths)
	if data.Coins < cost then
		notEnough(player, cost, data.Coins, "coins")
		return
	end
	data.Rebirths += 1
	data.Coins = 0
	data.PickaxeTier = 1
	local gems = Config.Rebirth.GemsPer * data.Rebirths
	data.Gems += gems
	Services.CharacterService:GivePickaxe(player)
	Services.CharacterService:RefreshOverhead(player)
	Services.PetService:RefreshEquipped(player)
	Net:Send(player, "Rebirthed", data.Rebirths, gems)
	if REBIRTH_ANNOUNCE[data.Rebirths] then
		Net:Announce("♻️ %s reached Rebirth %d!", Color3.fromRGB(200, 130, 255), player.DisplayName, data.Rebirths)
	end
	Data:MarkDirty(player)
end

function Economy:Init(services)
	Services = services
	Data = services.DataService
end

function Economy:Start()
	local world = Services.WorldService

	Net:On("BuyPickaxe", 0.25, function(player)
		buyUpgrade(player, "Pickaxes", "PickaxeTier")
	end)
	Net:On("BuyBoots", 0.25, function(player)
		buyUpgrade(player, "Boots", "SpeedTier")
		Services.CharacterService:ApplyWalkSpeed(player)
	end)
	Net:On("UnlockZone", 0.5, function(player, index)
		if type(index) == "number" then
			self:UnlockZone(player, math.floor(index))
		end
	end)
	Net:On("Rebirth", 1, function(player)
		self:Rebirth(player)
	end)
	Net:On("Teleport", 1, function(player, index)
		local data = Data:Get(player)
		local character = player.Character
		if not data or not character or type(index) ~= "number" then
			return
		end
		index = math.floor(index)
		if index ~= 0 and (index < 1 or index > data.ZoneLevel) then
			Net:Notify(player, "Unlock that zone first!", RED)
			return
		end
		character:PivotTo(world:SpawnFor(index))
	end)
end

return Economy
