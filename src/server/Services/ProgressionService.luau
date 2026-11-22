--[[
	ProgressionService: everything that brings players back every day/week.
	  * Daily login streak (7-day calendar, streak breaks if you miss a day)
	  * 3 random daily quests
	  * Playtime gifts (10+ min sessions -> Creator Rewards daily engagement)
	  * Weekly ranked points + tier rewards on week rollover (+ global top 10)
	  * Season pass (free + premium track)
	  * VIP daily chest, Miner Club daily gems, one-time group reward
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Net = require(script.Parent.Net)

local Progression = {}
local Services
local Data

local sessionStart = {} -- [player] = unix time
local overtakeCooldown = {} -- ["a>b"] = os.clock()
local giftsClaimed = {} -- [player] = { [index] = true }
local questById = {}
for _, quest in Config.Quests do
	questById[quest.Id] = quest
end

local GREEN = Color3.fromRGB(120, 255, 170)
local GOLD = Color3.fromRGB(255, 210, 70)

local function tierOf(xp: number): number
	return math.min(#Config.SeasonTiers, math.floor(xp / Config.Season.XPPerTier))
end
Progression.TierOf = tierOf

function Progression:SessionStart(player: Player): number
	return sessionStart[player] or os.time()
end

function Progression:GiftsClaimed(player: Player)
	local list = {}
	for index in giftsClaimed[player] or {} do
		table.insert(list, index)
	end
	return list
end

function Progression:GrantReward(player: Player, reward, source: string?, silent: boolean?)
	local data = Data:Get(player)
	if not data or not reward then
		return
	end
	if reward.Gems then
		data.Gems += reward.Gems
	end
	if reward.Coins then
		data.Coins += reward.Coins
		data.Stats.LifetimeCoins += reward.Coins
	end
	if reward.Stardust then
		data.Stardust += reward.Stardust
	end
	if reward.Boost then
		Services.BoostService:Add(player, reward.Boost[1], reward.Boost[2])
	end
	if reward.Pet then
		Services.PetService:GrantPet(player, reward.Pet, reward.Variant)
	end
	Data:MarkDirty(player)
	if not silent then
		Net:Send(player, "Reward", Util.RewardText(reward), source)
	end
end

-- player level: every block gives XP; level-ups give gems + a permanent coin bonus
function Progression:AddXP(player: Player, amount: number)
	local data = Data:Get(player)
	if not data or amount <= 0 then
		return
	end
	data.XP += amount
	local levels = Config.Levels
	local guard = 0
	while data.XP >= Util.XPForLevel(Config, data.Level) and guard < 50 do
		guard += 1
		data.XP -= Util.XPForLevel(Config, data.Level)
		data.Level += 1
		local gems = levels.GemsPerLevel
		if data.Level % levels.MilestoneEvery == 0 then
			gems += levels.MilestoneGems
			Net:Announce(string.format("⭐ %s reached LEVEL %d!", player.DisplayName, data.Level), Color3.fromRGB(255, 220, 90))
		end
		data.Gems += gems
		Net:Send(player, "LevelUp", data.Level, gems)
		Services.CharacterService:RefreshOverhead(player)
	end
	Data:MarkDirty(player)
end

function Progression:AddQuest(player: Player, questType: string, amount: number)
	local data = Data:Get(player)
	if not data then
		return
	end
	for _, quest in data.Daily.Quests do
		local def = questById[quest.Id]
		if def and def.Type == questType and not quest.Claimed and quest.Progress < def.Target then
			quest.Progress = math.min(def.Target, quest.Progress + amount)
			if quest.Progress >= def.Target then
				Net:Notify(player, "✅ Quest complete: " .. def.Text .. " - claim it!", GREEN)
			end
			Data:MarkDirty(player)
		end
	end
end

function Progression:AddPoints(player: Player, amount: number)
	local data = Data:Get(player)
	if not data then
		return
	end
	local _, before = Util.RankFor(Config, data.Weekly.Points)
	local oldPoints = data.Weekly.Points
	data.Weekly.Points += amount
	-- in-server rivalry: tell both players when someone overtakes
	local now = os.clock()
	for _, other in Data:LoadedPlayers() do
		local otherData = other ~= player and Data:Get(other)
		if otherData then
			local theirs = otherData.Weekly.Points
			if oldPoints <= theirs and data.Weekly.Points > theirs and theirs > 0 then
				local key = player.UserId .. ">" .. other.UserId
				if not overtakeCooldown[key] or now - overtakeCooldown[key] > 90 then
					overtakeCooldown[key] = now
					Net:Notify(player, "⬆️ You passed " .. other.DisplayName .. " in the weekly ranking!", Color3.fromRGB(120, 255, 170))
					Net:Notify(other, "⬇️ " .. player.DisplayName .. " just passed you! Take it back!", Color3.fromRGB(255, 120, 120))
				end
			end
		end
	end
	local rank, after = Util.RankFor(Config, data.Weekly.Points)
	if after > before then
		Net:Send(player, "RankUp", rank.Name)
		if after >= 5 then
			Net:Announce(string.format("🏅 %s reached %s rank this week!", player.DisplayName, string.upper(rank.Name)), rank.Color)
		end
		Services.CharacterService:RefreshOverhead(player)
	end
	Data:MarkDirty(player)
end

function Progression:AddSeasonXP(player: Player, amount: number)
	local data = Data:Get(player)
	if not data then
		return
	end
	local before = tierOf(data.Season.XP)
	data.Season.XP += amount
	local after = tierOf(data.Season.XP)
	if after > before then
		Net:Notify(player, "🎫 Season Pass tier " .. after .. " reached! Claim your rewards.", GOLD)
	end
	Data:MarkDirty(player)
end

function Progression:OnBlockMined(player: Player, zone: number)
	self:AddQuest(player, "MineBlocks", 1)
	self:AddSeasonXP(player, Config.Season.XPPerBlock * zone)
	self:AddPoints(player, Config.PointsPerBlock[zone] or 1)
end

function Progression:CheckClubDaily(player: Player)
	local data = Data:Get(player)
	if not data or not Services.MonetizationService:IsSubscribed(player) then
		return
	end
	local today = Util.DayNumber()
	if data.Daily.ClubDay ~= today then
		data.Daily.ClubDay = today
		self:GrantReward(player, { Gems = Config.Subscription.DailyGems }, Config.Subscription.Name .. " daily gems")
	end
end

local function rollQuests(data)
	local indices = {}
	for i = 1, #Config.Quests do
		indices[i] = i
	end
	for i = #indices, 2, -1 do
		local j = math.random(1, i)
		indices[i], indices[j] = indices[j], indices[i]
	end
	data.Daily.Quests = {}
	for i = 1, math.min(Config.DailyQuestCount, #indices) do
		local def = Config.Quests[indices[i]]
		table.insert(data.Daily.Quests, { Id = def.Id, Progress = 0, Claimed = false })
	end
end

local function checkRollovers(player: Player, data, isLoad: boolean)
	-- daily
	local today = Util.DayNumber()
	if data.Daily.Day ~= today then
		data.Daily.Day = today
		rollQuests(data)
		if not isLoad then
			Net:Notify(player, "📜 New daily quests are available!", GREEN)
		end
	end
	-- season
	if data.Season.Id ~= Config.Season.Id then
		data.Season = { Id = Config.Season.Id, XP = 0, Premium = false, ClaimedFree = {}, ClaimedPremium = {} }
	end
	-- weekly ranked
	local week = Util.WeekNumber()
	if data.Weekly.Week ~= week then
		local lastWeek, lastPoints = data.Weekly.Week, data.Weekly.Points
		data.Weekly.Week = week
		data.Weekly.Points = 0
		if lastWeek ~= 0 and lastPoints > 0 then
			local rank = Util.RankFor(Config, lastPoints)
			local gems = rank.RewardGems
			task.spawn(function()
				local placement = Services.LeaderboardService:GetWeeklyPlacement(lastWeek, player.UserId)
				local topReward = placement and Config.Leaderboards.WeeklyTopReward[placement] or 0
				local total = gems + topReward
				if total > 0 and player.Parent then
					local text = string.format("Last week: %s rank", string.upper(rank.Name))
					if placement then
						text ..= string.format(" + GLOBAL #%d", placement)
					end
					Progression:GrantReward(player, { Gems = total }, text)
				end
			end)
		end
		Services.CharacterService:RefreshOverhead(player)
	end
	Progression:CheckClubDaily(player)
	Data:MarkDirty(player)
end

function Progression:Init(services)
	Services = services
	Data = services.DataService
end

function Progression:Start()
	Data:OnLoaded(function(player, data)
		sessionStart[player] = os.time()
		giftsClaimed[player] = {}
		checkRollovers(player, data, true)
		-- daily reward reminder
		if data.Daily.LastClaimDay ~= Util.DayNumber() then
			task.delay(4, function()
				Net:Send(player, "OpenPanel", "Daily")
			end)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		sessionStart[player] = nil
		giftsClaimed[player] = nil
	end)

	-- minute ticker: play-time quests, rollovers
	task.spawn(function()
		while true do
			task.wait(60)
			for _, player in Data:LoadedPlayers() do
				local data = Data:Get(player)
				if data then
					local ok, err = pcall(function()
						data.Stats.PlaySeconds += 60
						self:AddQuest(player, "PlayMinutes", 1)
						checkRollovers(player, data, false)
					end)
					if not ok then
						warn("[Progression] tick error: " .. tostring(err))
					end
				end
			end
		end
	end)

	Net:On("ClaimDaily", 1, function(player)
		local data = Data:Get(player)
		if not data then
			return
		end
		local today = Util.DayNumber()
		if data.Daily.LastClaimDay == today then
			Net:Notify(player, "Come back tomorrow for your next reward!")
			return
		end
		if data.Daily.LastClaimDay == today - 1 then
			data.Daily.Streak += 1
		else
			data.Daily.Streak = 1
		end
		data.Daily.LastClaimDay = today
		local index = ((data.Daily.Streak - 1) % #Config.DailyRewards) + 1
		self:GrantReward(player, Config.DailyRewards[index], "Day " .. index .. " login reward")
	end)

	Net:On("ClaimQuest", 0.3, function(player, index)
		local data = Data:Get(player)
		local quest = data and type(index) == "number" and data.Daily.Quests[index]
		local def = quest and questById[quest.Id]
		if not def or quest.Claimed or quest.Progress < def.Target then
			return
		end
		quest.Claimed = true
		self:GrantReward(player, def.Reward, "Quest: " .. def.Text)
		self:AddSeasonXP(player, def.XP)
		self:AddPoints(player, def.Points)
	end)

	Net:On("ClaimGift", 0.3, function(player, index)
		local gift = type(index) == "number" and Config.PlaytimeGifts[index]
		local claimed = giftsClaimed[player]
		if not gift or not claimed or claimed[index] then
			return
		end
		if os.time() - (sessionStart[player] or os.time()) < gift.Minutes * 60 then
			return
		end
		claimed[index] = true
		self:GrantReward(player, gift.Reward, "Playtime gift")
	end)

	local function claimTier(player: Player, data, tier: number, track: string): boolean
		local tierDef = Config.SeasonTiers[tier]
		if not tierDef or tierOf(data.Season.XP) < tier then
			return false
		end
		local key = tostring(tier)
		local claimed = if track == "Premium" then data.Season.ClaimedPremium else data.Season.ClaimedFree
		if claimed[key] then
			return false
		end
		if track == "Premium" and not data.Season.Premium then
			return false
		end
		claimed[key] = true
		self:GrantReward(player, tierDef[track], "Season tier " .. tier)
		return true
	end

	Net:On("ClaimTier", 0.15, function(player, tier, track)
		local data = Data:Get(player)
		if not data or type(tier) ~= "number" or (track ~= "Free" and track ~= "Premium") then
			return
		end
		if track == "Premium" and not data.Season.Premium then
			Net:Send(player, "UpsellProduct", "SeasonPremium")
			return
		end
		claimTier(player, data, math.floor(tier), track)
	end)

	Net:On("ClaimAllTiers", 1, function(player)
		local data = Data:Get(player)
		if not data then
			return
		end
		for tier = 1, tierOf(data.Season.XP) do
			claimTier(player, data, tier, "Free")
			if data.Season.Premium then
				claimTier(player, data, tier, "Premium")
			end
		end
	end)

	Net:On("ClaimVip", 1, function(player)
		local data = Data:Get(player)
		if not data then
			return
		end
		if not Services.MonetizationService:HasPass(player, "VIP") then
			Net:Send(player, "Upsell", "VIP")
			return
		end
		local today = Util.DayNumber()
		if data.Daily.VipChestDay == today then
			Net:Notify(player, "VIP chest already claimed today!")
			return
		end
		data.Daily.VipChestDay = today
		self:GrantReward(player, { Gems = Config.Social.VipDailyGems }, "VIP daily chest")
	end)

	-- promo codes ---------------------------------------------------------
	Net:OnRequest("RedeemCode", 1, function(player, code)
		local data = Data:Get(player)
		if not data or type(code) ~= "string" then
			return false, "Enter a code"
		end
		code = string.upper((code:gsub("%s+", "")))
		local def = Config.Codes[code]
		if not def then
			return false, "Invalid code"
		end
		if def.ExpiresAt and def.ExpiresAt > 0 and os.time() > def.ExpiresAt then
			return false, "This code has expired"
		end
		if data.Codes[code] then
			return false, "Already redeemed"
		end
		data.Codes[code] = true
		self:GrantReward(player, def.Reward, "Code " .. code)
		return true, "Redeemed: " .. Util.RewardText(def.Reward)
	end)

	-- free prize wheel ------------------------------------------------------
	Net:OnRequest("Spin", 1, function(player)
		local data = Data:Get(player)
		if not data then
			return nil
		end
		local now = os.time()
		if data.FreeSpinAt > now then
			return { Error = "Next free spin in " .. Util.FormatTime(data.FreeSpinAt - now) }
		end
		local cooldown = if Services.MonetizationService:HasPass(player, "VIP")
			then Config.Spin.VipCooldownSeconds
			else Config.Spin.CooldownSeconds
		data.FreeSpinAt = now + cooldown
		local entries = {}
		for i, entry in Config.Spin.Rewards do
			entries[i] = { i, entry.Weight }
		end
		local index = Util.WeightedPick(entries)
		local entry = Config.Spin.Rewards[index]
		-- granted now, revealed by the wheel animation on the client
		self:GrantReward(player, entry.Reward, "Spin", true)
		if entry.Jackpot then
			Net:Announce("🎡 " .. player.DisplayName .. " hit the JACKPOT on the prize wheel!", Color3.fromRGB(255, 230, 120))
		end
		Data:MarkDirty(player)
		return { Index = index, Text = Util.RewardText(entry.Reward) }
	end)

	Net:On("ClaimGroup", 2, function(player)
		local data = Data:Get(player)
		if not data or Config.GroupId == 0 or data.Flags.GroupReward then
			return
		end
		local ok, inGroup = pcall(player.IsInGroup, player, Config.GroupId)
		if ok and inGroup then
			data.Flags.GroupReward = true
			player:SetAttribute("InGroup", true)
			self:GrantReward(player, { Gems = Config.Social.GroupJoinGems }, "Thanks for joining the group!")
		else
			Net:Notify(player, "Join our Roblox group first, then claim again!")
		end
	end)
end

return Progression
