--[[
	MonetizationService
	  * Game passes (ownership cache + purchase prompts + instant effects)
	  * Developer products via ProcessReceipt (idempotent: PurchaseId stored in data)
	  * Experience subscription (Miner Club)
	  * Roblox Premium upsell
	  * Native rewarded video ads (AdService) - disabled until you enable it
	  * PolicyService compliance: paid random items (Golden Egg) are hidden for
	    players where they are restricted, and odds are always shown before buying.

	Studio testing: any pass/product whose Id is 0 is granted instantly in
	Studio ("[TEST]") so the full flow can be tested before IDs exist.
]]
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(script.Parent.Net)

local Monetization = {}
local Services
local Data

local owned = {} -- [player] = { [passKey] = true }
local subscribed = {} -- [player] = bool
local passById = {}
local productById = {}

for key, pass in Config.GamePasses do
	if pass.Id ~= 0 then
		passById[pass.Id] = key
	end
end
for key, product in Config.Products do
	if product.Id ~= 0 then
		productById[product.Id] = key
	end
end

local GOLD = Color3.fromRGB(255, 210, 70)

function Monetization:HasPass(player: Player, key: string): boolean
	local list = owned[player]
	return list ~= nil and list[key] == true
end

function Monetization:OwnedPasses(player: Player)
	return owned[player] or {}
end

function Monetization:IsSubscribed(player: Player): boolean
	return subscribed[player] == true
end

local function applyPass(player: Player, key: string, isNewPurchase: boolean)
	local list = owned[player]
	if not list then
		list = {}
		owned[player] = list
	end
	if list[key] then
		return
	end
	list[key] = true
	player:SetAttribute("Pass_" .. key, true)
	if key == "VIP" then
		player:SetAttribute("VIP", true)
	end
	local character = Services.CharacterService
	if key == "Speed" then
		character:ApplyWalkSpeed(player)
	end
	character:RefreshOverhead(player)
	Services.PetService:RefreshEquipped(player)
	Data:MarkDirty(player)

	if isNewPurchase then
		local pass = Config.GamePasses[key]
		Net:Notify(player, "🎉 Unlocked " .. pass.Name .. "!", GOLD)
		-- social proof: everyone sees supporters
		Net:Announce(string.format("%s %s just got %s!", pass.Icon or "⭐", player.DisplayName, pass.Name), GOLD)
	end
end

local function refreshSubscription(player: Player)
	local sub = Config.Subscription
	if sub.Id == "" then
		return
	end
	local ok, status = pcall(function()
		return MarketplaceService:GetUserSubscriptionStatusAsync(player, sub.Id)
	end)
	if ok and type(status) == "table" and player.Parent then
		local wasSubscribed = subscribed[player] == true
		subscribed[player] = status.IsSubscribed == true
		player:SetAttribute("Club", subscribed[player])
		if subscribed[player] and not wasSubscribed then
			Services.ProgressionService:CheckClubDaily(player)
		end
		Services.CharacterService:RefreshOverhead(player)
		Data:MarkDirty(player)
	end
end

local function checkPolicy(player: Player)
	for _ = 1, 3 do
		local ok, policy = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, player)
		if ok and type(policy) == "table" then
			player:SetAttribute("PaidRandomRestricted", policy.ArePaidRandomItemsRestricted == true)
			Data:MarkDirty(player)
			return
		end
		task.wait(2)
	end
	-- unknown policy: be safe and treat paid random items as restricted
	player:SetAttribute("PaidRandomRestricted", true)
	Data:MarkDirty(player)
end

local function onPlayerAdded(player: Player)
	owned[player] = owned[player] or {}
	for key, pass in Config.GamePasses do
		if pass.Id ~= 0 then
			task.spawn(function()
				local ok, result = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.Id)
				if ok and result and player.Parent then
					applyPass(player, key, false)
				end
			end)
		end
	end
	task.spawn(checkPolicy, player)
	task.spawn(refreshSubscription, player)
end

---------------------------------------------------------------------------
-- product granting
---------------------------------------------------------------------------
local function canBuy(player: Player, key: string, data): (boolean, string?)
	local product = Config.Products[key]
	if product.Kind == "StarterPack" and data.Flags.StarterPack then
		return false, "You already own the Starter Pack!"
	end
	if product.Kind == "SeasonPremium" and data.Season.Premium then
		return false, "You already own the Premium Pass!"
	end
	if product.Kind == "PaidEgg" then
		if player:GetAttribute("PaidRandomRestricted") ~= false then
			return false, "This item isn't available in your region."
		end
		if #data.Pets + product.Count > Config.MaxPets then
			return false, "Your pet inventory is full!"
		end
	end
	if key == "AdReward" then
		return false, "Watch an ad to get this reward."
	end
	return true
end

local function grantProduct(player: Player, key: string, data)
	local product = Config.Products[key]
	local kind = product.Kind
	local stats = Services.StatsService

	if kind == "Gems" then
		data.Gems += product.Amount
		Net:Notify(player, string.format("💎 +%d Gems! Thank you!", product.Amount), GOLD)
	elseif kind == "CoinPack" then
		local amount = math.max(2500, math.floor(stats:Capacity(player, data) * 15 * stats:CoinMultiplier(player, data)))
		data.Coins += amount
		data.Stats.LifetimeCoins += amount
		Net:Send(player, "Sold", amount)
	elseif kind == "Boost" then
		Services.BoostService:Add(player, product.Boost, product.Seconds)
	elseif kind == "ServerBoost" then
		Services.BoostService:AddServer(product.Boost, product.Seconds, player)
	elseif kind == "SummonMeteor" then
		Services.MeteorService:Summon(player)
	elseif kind == "SeasonPremium" then
		data.Season.Premium = true
		Net:Notify(player, "🎫 Premium Pass unlocked! Claim your rewards.", GOLD)
		Net:Announce("🎫 " .. player.DisplayName .. " unlocked the Premium Season Pass!", GOLD)
	elseif kind == "SkipTiers" then
		Services.ProgressionService:AddSeasonXP(player, Config.Season.XPPerTier * product.Amount)
	elseif kind == "StarterPack" then
		data.Flags.StarterPack = true
		Services.ProgressionService:GrantReward(player, Config.StarterPack.Reward, "Starter Pack")
	elseif kind == "PaidEgg" then
		Services.PetService:PaidHatch(player, product.Egg, product.Count)
	else
		error("Unknown product kind " .. tostring(kind))
	end
	data.Stats.Purchases += 1
	Data:MarkDirty(player)
end

local function processReceipt(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local data = Data:WaitFor(player, 20)
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(receipt.PurchaseId)
	if Data:HasReceipt(player, purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local key = productById[receipt.ProductId]
	if not key then
		warn("[Monetization] unknown product id " .. tostring(receipt.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, err = pcall(grantProduct, player, key, data)
	if not ok then
		warn("[Monetization] grant failed: " .. tostring(err))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	Data:AddReceipt(player, purchaseId)
	Data:Save(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

---------------------------------------------------------------------------
-- rewarded video ads (native Roblox AdService)
---------------------------------------------------------------------------
local function watchAd(player: Player)
	local settings = Config.RewardedAds
	if not settings.Enabled then
		return false, "Ads are not available."
	end
	local data = Data:Get(player)
	if not data then
		return false, "Loading..."
	end
	local remaining = settings.CooldownSeconds - (os.time() - data.LastAdTime)
	if remaining > 0 then
		return false, string.format("Next free reward in %d min", math.ceil(remaining / 60))
	end
	local product = Config.Products.AdReward
	if product.Id == 0 then
		if RunService:IsStudio() then
			data.LastAdTime = os.time()
			grantProduct(player, "AdReward", data)
			return true, "[TEST] Ad reward granted"
		end
		return false, "Ad reward is not configured."
	end
	-- NOTE: verify method names against the current AdService docs before enabling.
	local ok, result = pcall(function()
		local AdService = game:GetService("AdService")
		local availability = AdService:GetAdAvailabilityNowAsync(Enum.AdFormat.RewardedVideo)
		if availability.AdAvailabilityResult ~= Enum.AdAvailabilityResult.IsAvailable then
			return "unavailable"
		end
		local reward = AdService:CreateAdRewardFromDevProductId(product.Id)
		AdService:ShowRewardedVideoAdAsync(player, reward)
		return "shown"
	end)
	if not ok then
		warn("[Monetization] ad failed: " .. tostring(result))
		return false, "No ad available right now."
	end
	if result ~= "shown" then
		return false, "No ad available right now."
	end
	-- the reward itself arrives through ProcessReceipt
	data.LastAdTime = os.time()
	Data:MarkDirty(player)
	return true, "Thanks for watching!"
end

---------------------------------------------------------------------------
function Monetization:Init(services)
	Services = services
	Data = services.DataService
end

function Monetization:Start()
	MarketplaceService.ProcessReceipt = processReceipt

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		owned[player] = nil
		subscribed[player] = nil
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if purchased then
			local key = passById[passId]
			if key then
				applyPass(player, key, true)
			end
		end
	end)

	pcall(function()
		(Players :: any).UserSubscriptionStatusChanged:Connect(function(player, subscriptionId)
			if subscriptionId == Config.Subscription.Id then
				refreshSubscription(player)
			end
		end)
	end)

	Net:On("BuyPass", 0.5, function(player, key)
		local pass = type(key) == "string" and Config.GamePasses[key]
		if not pass then
			return
		end
		if self:HasPass(player, key) then
			Net:Notify(player, "You already own " .. pass.Name .. "!")
			return
		end
		if pass.Id == 0 then
			if RunService:IsStudio() then
				applyPass(player, key, true)
				Net:Notify(player, "[TEST] Simulated purchase: " .. pass.Name)
			else
				Net:Notify(player, "Coming soon!")
			end
			return
		end
		MarketplaceService:PromptGamePassPurchase(player, pass.Id)
	end)

	Net:On("BuyProduct", 0.5, function(player, key)
		local product = type(key) == "string" and Config.Products[key]
		local data = Data:Get(player)
		if not product or not data then
			return
		end
		local ok, reason = canBuy(player, key, data)
		if not ok then
			Net:Notify(player, reason or "Not available")
			return
		end
		if product.Id == 0 then
			if RunService:IsStudio() then
				grantProduct(player, key, data)
				Net:Notify(player, "[TEST] Simulated purchase: " .. product.Name)
			else
				Net:Notify(player, "Coming soon!")
			end
			return
		end
		MarketplaceService:PromptProductPurchase(player, product.Id)
	end)

	Net:On("BuySubscription", 1, function(player)
		local sub = Config.Subscription
		if self:IsSubscribed(player) then
			Net:Notify(player, "You're already in the " .. sub.Name .. "!")
			return
		end
		if sub.Id == "" then
			if RunService:IsStudio() then
				subscribed[player] = true
				player:SetAttribute("Club", true)
				Services.ProgressionService:CheckClubDaily(player)
				Services.CharacterService:RefreshOverhead(player)
				Data:MarkDirty(player)
				Net:Notify(player, "[TEST] Simulated subscription: " .. sub.Name)
			else
				Net:Notify(player, "Coming soon!")
			end
			return
		end
		local ok, err = pcall(function()
			MarketplaceService:PromptSubscriptionPurchase(player, sub.Id)
		end)
		if not ok then
			warn("[Monetization] subscription prompt failed: " .. tostring(err))
		end
	end)

	Net:On("BuyPremium", 1, function(player)
		if player.MembershipType ~= Enum.MembershipType.Premium then
			pcall(MarketplaceService.PromptPremiumPurchase, MarketplaceService, player)
		end
	end)

	Net:OnRequest("WatchAd", 2, function(player)
		return watchAd(player)
	end)
end

return Monetization
