--[[
	StatsService: single source of truth for every multiplier
	(damage, coins, luck, capacity, pet slots) + social bonuses.
	Also builds the "Derived" block that is synced to the client UI.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)

local Stats = {}
local Services
local Data

local friendCache = {} -- ["a:b"] = bool
local serverRank

local function has(player, key)
	return Services.MonetizationService:HasPass(player, key)
end

local function boost(player, key)
	return Services.BoostService:IsActive(player, key)
end

function Stats:PetPower(_player, data): number
	local equipped = {}
	for _, id in data.Equipped do
		equipped[id] = true
	end
	local total = 0
	for _, pet in data.Pets do
		if equipped[pet.Id] then
			total += Util.PetPower(Config, pet.Name, pet.Variant)
		end
	end
	return total
end

function Stats:PetSlots(player, data): number
	local slots = Config.BasePetSlots + math.floor(data.Rebirths / Config.Rebirth.ExtraPetSlotEvery)
	if has(player, "ExtraPets") then
		slots += 3
	end
	if has(player, "VIP") then
		slots += 1
	end
	return math.min(slots, Config.MaxPetSlots)
end

function Stats:Damage(player, data): number
	local pickaxe = Config.Pickaxes[data.PickaxeTier] or Config.Pickaxes[1]
	local mult = 1 + self:PetPower(player, data)
	if has(player, "MegaPower") then
		mult *= 2
	end
	if boost(player, "Power2x") then
		mult *= 2
	end
	return pickaxe.Power * mult
end

function Stats:SwingCooldown(player, data): number
	local pickaxe = Config.Pickaxes[data.PickaxeTier] or Config.Pickaxes[1]
	local mining = Services.MiningService
	if mining and mining:IsFever(player) then
		return pickaxe.Cooldown * Config.Fever.CooldownMult
	end
	return pickaxe.Cooldown
end

function Stats:SocialBonus(player): (number, number, boolean, boolean)
	local friends = player:GetAttribute("FriendsInServer") or 0
	local friendBonus = math.min(Config.Social.FriendBonusMax, friends * Config.Social.FriendBonusPer)
	local inGroup = player:GetAttribute("InGroup") == true
	local premium = player.MembershipType == Enum.MembershipType.Premium
	local bonus = friendBonus
	if inGroup then
		bonus += Config.Social.GroupBonus
	end
	if premium then
		bonus += Config.Social.PremiumBonus
	end
	return bonus, friendBonus, inGroup, premium
end

function Stats:CoinMultiplier(player, data): number
	local mult = 1 + data.Rebirths * Config.Rebirth.CoinBonusPer
	if has(player, "DoubleCoins") then
		mult *= 2
	end
	if boost(player, "Coins2x") then
		mult *= 2
	end
	local bonus = self:SocialBonus(player)
	bonus += (data.Level - 1) * Config.Levels.CoinBonusPer
	if has(player, "VIP") then
		bonus += Config.Social.VipCoinBonus
	end
	if Services.MonetizationService:IsSubscribed(player) then
		bonus += Config.Subscription.CoinBonus
	end
	return mult * (1 + bonus)
end

function Stats:Luck(player, _data): number
	local luck = 1
	if has(player, "Lucky") then
		luck *= 1.5
	end
	if boost(player, "Luck2x") then
		luck *= 2
	end
	if Services.BoostService:ServerActive("ServerLuck") then
		luck *= 2
	end
	return luck
end

-- weekly-points standing among players in THIS server (+ who to beat next)
serverRank = function(player: Player, data)
	local list = {}
	for _, other in Data:LoadedPlayers() do
		local otherData = Data:Get(other)
		if otherData then
			table.insert(list, { Player = other, Points = otherData.Weekly.Points })
		end
	end
	table.sort(list, function(a, b)
		return a.Points > b.Points
	end)
	for place, entry in list do
		if entry.Player == player then
			local ahead = list[place - 1]
			return {
				Place = place,
				Count = #list,
				NextName = ahead and ahead.Player.DisplayName or nil,
				NextGap = ahead and (ahead.Points - data.Weekly.Points + 1) or nil,
			}
		end
	end
	return { Place = 1, Count = 1 }
end

function Stats:BuildDerived(player)
	local data = Data:Get(player)
	if not data then
		return {}
	end
	local bonus, friendBonus, inGroup, premium = self:SocialBonus(player)
	local rank, rankIndex = Util.RankFor(Config, data.Weekly.Points)
	local progression = Services.ProgressionService
	return {
		Damage = self:Damage(player, data),
		CoinMult = self:CoinMultiplier(player, data),
		Luck = self:Luck(player, data),
		Cooldown = (Config.Pickaxes[data.PickaxeTier] or Config.Pickaxes[1]).Cooldown, -- client applies FEVER itself
		PetSlots = self:PetSlots(player, data),
		PetPower = self:PetPower(player, data),
		Passes = Services.MonetizationService:OwnedPasses(player),
		Subscribed = Services.MonetizationService:IsSubscribed(player),
		RebirthCost = Util.RebirthCost(Config, data.Rebirths),
		SocialBonus = bonus,
		FriendBonus = friendBonus,
		InGroup = inGroup,
		Premium = premium,
		Rank = rank.Name,
		RankIndex = rankIndex,
		Week = Util.WeekNumber(),
		Today = Util.DayNumber(),
		SessionStart = progression and progression:SessionStart(player) or os.time(),
		GiftsClaimed = progression and progression:GiftsClaimed(player) or {},
		PaidRandomRestricted = player:GetAttribute("PaidRandomRestricted") == true,
		AdsEnabled = Config.RewardedAds.Enabled,
		XPNeeded = Util.XPForLevel(Config, data.Level),
		SpinCooldown = if Services.MonetizationService:HasPass(player, "VIP")
			then Config.Spin.VipCooldownSeconds
			else Config.Spin.CooldownSeconds,
		ServerRank = serverRank(player, data),
		ServerTime = os.time(),
	}
end

-- social -------------------------------------------------------------------
local function areFriends(a: Player, b: Player): boolean
	local low, high = math.min(a.UserId, b.UserId), math.max(a.UserId, b.UserId)
	local key = low .. ":" .. high
	if friendCache[key] == nil then
		local ok, result = pcall(a.IsFriendsWith, a, b.UserId)
		friendCache[key] = ok and result == true
	end
	return friendCache[key]
end

local function recountFriends()
	local players = Players:GetPlayers()
	for _, player in players do
		local count = 0
		for _, other in players do
			if other ~= player and areFriends(player, other) then
				count += 1
			end
		end
		if player:GetAttribute("FriendsInServer") ~= count then
			player:SetAttribute("FriendsInServer", count)
			Data:MarkDirty(player)
		end
	end
end

function Stats:Init(services)
	Services = services
	Data = services.DataService
	Data.BuildDerived = function(player)
		return Stats:BuildDerived(player)
	end
end

function Stats:Start()
	local function onPlayer(player: Player)
		if Config.GroupId ~= 0 then
			task.spawn(function()
				local ok, inGroup = pcall(player.IsInGroup, player, Config.GroupId)
				player:SetAttribute("InGroup", ok and inGroup == true)
				Data:MarkDirty(player)
			end)
		end
		task.spawn(recountFriends)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function()
		task.defer(recountFriends)
	end)
	Players.PlayerMembershipChanged:Connect(function(player)
		Data:MarkDirty(player)
	end)
	task.spawn(recountFriends)
end

return Stats
