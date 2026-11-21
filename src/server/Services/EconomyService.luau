--[[
	EconomyService: selling ore, pickaxe/backpack upgrades, zone unlocks,
	rebirths and teleports. All prices are validated on the server.
]]
local Players = game:GetService("Players")
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
	Net:Notify(player, string.format("Not enough %s! Need %s more.", currency, Util.Format(need - have)), RED)
end

function Economy:Sell(player: Player, silent: boolean?): number
	local data = Data:Get(player)
	if not data then
		return 0
	end
	if data.Backpack <= 0 then
		if not silent then
			Net:Notify(player, "Your backpack is empty - go mine some ore!")
		end
		return 0
	end
	local coins = math.floor(data.Backpack * Services.StatsService:CoinMultiplier(player, data))
	data.Coins += coins
	data.Stats.LifetimeCoins += coins
	data.Backpack = 0
	Services.ProgressionService:AddQuest(player, "Sell", 1)
	Net:Send(player, "Sold", coins)
	Data:MarkDirty(player)
	return coins
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
		Net:Notify(player, "Unlock " .. Config.Zones[data.ZoneLevel + 1].Name .. " first!", RED)
		return
	end
	if data.Coins < zone.Cost then
		notEnough(player, zone.Cost, data.Coins, "coins")
		return
	end
	data.Coins -= zone.Cost
	data.ZoneLevel = index
	Net:Send(player, "ZoneUnlocked", index)
	Net:Notify(player, "🔓 " .. zone.Name .. " unlocked!", Color3.fromRGB(120, 255, 170))
	if zone.PvP then
		Net:Announce("⚔️ " .. player.DisplayName .. " entered the Star Crater!", Color3.fromRGB(255, 90, 120))
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
	end
	Services.ProgressionService:AddQuest(player, "Upgrade", 1)
	Net:Notify(player, "✅ Bought " .. item.Name .. "!", Color3.fromRGB(120, 255, 170))
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
	data.Backpack = 0
	data.PickaxeTier = 1
	data.BackpackTier = 1
	local gems = Config.Rebirth.GemsPer * data.Rebirths
	data.Gems += gems
	Services.CharacterService:GivePickaxe(player)
	Services.CharacterService:RefreshOverhead(player)
	Services.PetService:RefreshEquipped(player)
	Net:Send(player, "Rebirthed", data.Rebirths, gems)
	if REBIRTH_ANNOUNCE[data.Rebirths] then
		Net:Announce(string.format("♻️ %s reached Rebirth %d!", player.DisplayName, data.Rebirths), Color3.fromRGB(200, 130, 255))
	end
	Data:MarkDirty(player)
end

function Economy:Init(services)
	Services = services
	Data = services.DataService
end

function Economy:Start()
	local world = Services.WorldService

	-- sell pad
	local debounce = {}
	world.SellPad.Touched:Connect(function(hit)
		local character = hit:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player then
			return
		end
		local now = os.clock()
		if debounce[player] and now - debounce[player] < 1 then
			return
		end
		debounce[player] = now
		self:Sell(player, true)
	end)
	Players.PlayerRemoving:Connect(function(player)
		debounce[player] = nil
	end)

	Net:On("SellAnywhere", 0.5, function(player)
		if Services.MonetizationService:HasPass(player, "AutoSell") then
			self:Sell(player)
		else
			Net:Send(player, "Upsell", "AutoSell")
		end
	end)
	Net:On("BuyPickaxe", 0.25, function(player)
		buyUpgrade(player, "Pickaxes", "PickaxeTier")
	end)
	Net:On("BuyBackpack", 0.25, function(player)
		buyUpgrade(player, "Backpacks", "BackpackTier")
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
