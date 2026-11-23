--[[
	PetService: eggs, hatching, mutations and the pet inventory.

	* Pets live in your base: the best ones sit on pedestals and earn coins
	  every second (BaseService). Your strongest pets also follow you around
	  and add their power to your mining damage - chosen automatically.
	* Coin eggs restock every 5 minutes (same stock in every server, see
	  Util.EggStock); each player can buy up to the stock per restock.
	* Mutations (Golden, Rainbow, Galaxy + weather-only Frozen / Molten) are
	  rolled on every hatch.
	* Star eggs from falling stars / meteors hatch when carried home.
	* Selling a pet pays one minute of its income.
]]
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Net = require(script.Parent.Net)

local PetService = {}
local Services
local Data

local CURRENCY_NAMES = { Coins = "coins", Gems = "gems", Stardust = "stardust" }

local function luckFn(luck: number)
	return function(name: string, weight: number): number
		local info = Config.Pets[name]
		local rarity = info and Config.Rarities[info.Rarity]
		if rarity and rarity.Order >= Config.LuckAffectsFromRarity then
			return weight * luck
		end
		return weight
	end
end
PetService.LuckFn = luckFn

local function power(pet): number
	return Util.PetPower(Config, pet.Name, pet.Variant)
end

local function income(pet): number
	return Util.PetIncome(Config, pet.Name, pet.Variant)
end
PetService.Income = income

function PetService:SellValue(name: string, variant: string?): number
	return math.max(1, math.floor(Util.PetIncome(Config, name, variant) * Config.PetSellSeconds))
end

local function activeEventId(): string?
	local event = Services.EventService:Active()
	return event and event.Id or nil
end

-- mutation roll (rarest first); weather events unlock / boost some of them
local function rollVariant(luck: number): string?
	local mult = math.clamp(luck, 1, 4)
	local event = activeEventId()
	for _, def in Config.PetVariants do
		local chance = def.Chance or 0
		if def.Event and def.Event == event then
			chance = math.max(chance, def.EventChance or 0)
		end
		if chance > 0 and math.random() < chance * mult then
			return def.Id
		end
	end
	return nil
end
PetService.RollVariant = rollVariant

-- the strongest pets follow you (no equipping needed)
function PetService:RefreshEquipped(player: Player)
	local data = Data:Get(player)
	if not data then
		return
	end
	local sorted = {}
	for _, pet in data.Pets do
		if not pet.Away and Config.Pets[pet.Name] then
			table.insert(sorted, pet)
		end
	end
	table.sort(sorted, function(a, b)
		return power(a) > power(b)
	end)
	local slots = Services.StatsService:PetSlots(player, data)
	local ids, names = {}, {}
	for i = 1, math.min(slots, #sorted) do
		table.insert(ids, sorted[i].Id)
		-- "Variant|Name" so every client can render golden/rainbow pets
		table.insert(names, (sorted[i].Variant or "") .. "|" .. sorted[i].Name)
	end
	data.Equipped = ids
	player:SetAttribute("Pets", HttpService:JSONEncode(names))
	Data:MarkDirty(player)
end

-- call after any change to the pet list
function PetService:Changed(player: Player)
	self:RefreshEquipped(player)
	local base = Services.BaseService
	if base then
		base:RenderDisplays(player)
	end
end

local function findPet(data, petId)
	for index, pet in data.Pets do
		if pet.Id == petId then
			return pet, index
		end
	end
	return nil, nil
end
PetService.FindPet = findPet

local function addPet(data, name: string, variant: string?)
	local pet = { Id = data.NextPetUid, Name = name, Variant = variant }
	data.NextPetUid += 1
	table.insert(data.Pets, pet)
	data.PetIndex[name] = true
	return pet
end

-- inventory full: keep the better of (new pet, weakest pet) and sell the other.
-- Returns true when the new pet may be added, plus coins paid for a sold pet.
local function makeRoom(player: Player, data, name: string, variant: string?): (boolean, number)
	data.PetIndex[name] = true -- discovered, even if it gets sold right away
	if #data.Pets < Config.MaxPets then
		return true, 0
	end
	local weakest, weakestIndex = nil, nil
	for index, pet in data.Pets do
		if not pet.Away and (not weakest or income(pet) < income(weakest)) then
			weakest, weakestIndex = pet, index
		end
	end
	if weakest and Util.PetIncome(Config, name, variant) > income(weakest) then
		local coins = PetService:SellValue(weakest.Name, weakest.Variant)
		table.remove(data.Pets, weakestIndex)
		data.Coins += coins
		data.Stats.LifetimeCoins += coins
		Net:Notify(
			player,
			"Pet storage full - sold your weakest %s for 💰%s",
			Color3.fromRGB(255, 220, 120),
			weakest.Name,
			Util.Format(coins)
		)
		return true, coins
	end
	local coins = PetService:SellValue(name, variant)
	data.Coins += coins
	data.Stats.LifetimeCoins += coins
	Net:Notify(player, "Pet storage full - sold the new %s for 💰%s", Color3.fromRGB(255, 220, 120), name, Util.Format(coins))
	return false, coins
end

local function announceIfRare(player: Player, name: string, variant: string?, eggName: string)
	local info = Config.Pets[name]
	local rarity = info and Config.Rarities[info.Rarity]
	if not rarity then
		return
	end
	if rarity.Order >= Config.AnnounceRarity or variant == "Rainbow" or variant == "Galaxy" then
		Net:Announce(
			"🥚 %s hatched a %s %s %s from the %s!",
			if variant == "Rainbow" then Color3.fromRGB(255, 120, 230) else rarity.Color,
			player.DisplayName,
			variant or "",
			info.Rarity,
			name,
			eggName
		)
	end
end

-- roll `count` pets from an egg; extraLuck multiplies the player's luck
local function roll(player: Player, data, eggId: string, count: number, extraLuck: number?)
	local egg = Config.Eggs[eggId]
	local luck = Services.StatsService:Luck(player, data) * (extraLuck or 1)
	local fn = luckFn(luck)
	local results = {}
	for _ = 1, count do
		local name = Util.WeightedPick(egg.Pets, fn)
		local variant = rollVariant(luck)
		local ok = makeRoom(player, data, name, variant)
		if ok then
			addPet(data, name, variant)
		end
		table.insert(results, { Name = name, Variant = variant })
		announceIfRare(player, name, variant, egg.Name)
	end
	data.Stats.EggsHatched += count
	Services.ProgressionService:TutorialEvent(player, "Hatch", count)
	Services.ProgressionService:AddQuest(player, "Hatch", count)
	Services.ProgressionService:AddSeasonXP(player, 25 * count)
	PetService:Changed(player)
	return results
end

function PetService:GrantPet(player: Player, name: string, variant: string?)
	local data = Data:Get(player)
	if not data or not Config.Pets[name] then
		return
	end
	if makeRoom(player, data, name, variant) then
		addPet(data, name, variant)
	end
	self:Changed(player)
	Net:Send(player, "HatchResult", { { Name = name, Variant = variant } }, nil)
end

function PetService:PaidHatch(player: Player, eggId: string, count: number)
	local data = Data:Get(player)
	if not data or not Config.Eggs[eggId] then
		error("invalid paid hatch")
	end
	local results = roll(player, data, eggId, count)
	Net:Send(player, "HatchResult", results, eggId)
end

-- a star egg carried home hatches (luck from the star's rarity)
function PetService:HatchStarEgg(player: Player, eggId: string, luck: number)
	local data = Data:Get(player)
	if not data or not Config.Eggs[eggId] then
		return nil
	end
	local results = roll(player, data, eggId, 1, luck)
	Net:Send(player, "HatchResult", results, eggId)
	return results[1]
end

-- stealing: take a pet out of one inventory and put it into another
function PetService:TakePet(player: Player, petId: number)
	local data = Data:Get(player)
	local pet, index = nil, nil
	if data then
		pet, index = findPet(data, petId)
	end
	if not pet then
		return nil
	end
	table.remove(data.Pets, index)
	self:Changed(player)
	return { Name = pet.Name, Variant = pet.Variant }
end

function PetService:GivePet(player: Player, name: string, variant: string?)
	local data = Data:Get(player)
	if not data or not Config.Pets[name] then
		return
	end
	if makeRoom(player, data, name, variant) then
		addPet(data, name, variant)
	end
	self:Changed(player)
end

---------------------------------------------------------------------------
-- egg shop stock (coin eggs restock every few minutes)
---------------------------------------------------------------------------
-- how many of this egg the player can still buy in the current restock (nil = unlimited)
function PetService:StockLeft(data, eggId: string): number?
	local slot = Util.ShopSlot(Config, workspace:GetServerTimeNow())
	local stock = Util.EggStock(Config, eggId, slot)
	if stock == nil then
		return nil
	end
	local shop = data.Shop
	if shop.Slot ~= slot then
		shop.Slot = slot
		shop.Bought = {}
	end
	return math.max(0, stock - (shop.Bought[eggId] or 0))
end

local function hatch(player: Player, eggId, count)
	local data = Data:Get(player)
	local egg = type(eggId) == "string" and Config.Eggs[eggId]
	if not data or not egg or egg.Currency == "Robux" then
		return { Error = Net:L(player, "Invalid egg") }
	end
	count = if count == 3 then 3 else 1
	if count == 3 and not Services.MonetizationService:HasPass(player, "TripleHatch") then
		return { Error = Net:L(player, "Triple Hatch requires the gamepass!"), Upsell = "TripleHatch" }
	end
	if data.ZoneLevel < egg.Zone then
		return { Error = Net:L(player, "Unlock %s first!", Config.Zones[egg.Zone].Name) }
	end
	local left = PetService:StockLeft(data, eggId)
	if left ~= nil and left < count then
		local wait = Util.ShopRestockIn(Config, workspace:GetServerTimeNow())
		if left == 0 then
			return { Error = Net:L(player, "Sold out! New stock in %s", Util.FormatTime(wait)) }
		end
		return { Error = Net:L(player, "Only %d left until the restock!", left) }
	end
	local cost = egg.Price * count
	local balance = data[egg.Currency] or 0
	if balance < cost then
		return { Error = Net:L(player, "Not enough %s! Need %s more.", CURRENCY_NAMES[egg.Currency], Util.Format(cost - balance)) }
	end
	data[egg.Currency] -= cost
	Services.Analytics:Economy(player, "Sink", egg.Currency, cost, data[egg.Currency], "Shop", "Egg_" .. eggId)
	if left ~= nil then
		data.Shop.Bought[eggId] = (data.Shop.Bought[eggId] or 0) + count
	end
	local results = roll(player, data, eggId, count)
	return { Pets = results, Egg = eggId }
end

---------------------------------------------------------------------------
-- old saves: star shards (before pets earned money) become pets
---------------------------------------------------------------------------
local function migrate(player: Player, data)
	local shards = data.Base and data.Base.Shards
	if type(shards) ~= "table" or #shards == 0 then
		return
	end
	-- same rules as a star egg carried home: the player's zone egg, luck by rarity
	local zoneEgg = Config.Shards.ZoneEggs[math.clamp(data.ZoneLevel, 1, #Config.Shards.ZoneEggs)] or "Meadow"
	local pool = Config.Eggs[zoneEgg].Pets
	for _, entry in shards do
		local rarity = Config.Shards.Rarities[entry.Id]
		local luck = if rarity then rarity.Luck or 1 else 1
		local name = Util.WeightedPick(pool, luckFn(luck))
		if makeRoom(player, data, name, nil) then
			addPet(data, name, nil)
		end
	end
	data.Base.Shards = {}
	Net:Notify(player, "Your star shards hatched into pets! 🐾", Color3.fromRGB(150, 230, 255))
end

function PetService:Init(services)
	Services = services
	Data = services.DataService
end

function PetService:Start()
	Data:OnLoaded(function(player, data)
		for _, pet in data.Pets do
			pet.Away = nil -- a theft interrupted by a server shutdown never happened
		end
		migrate(player, data)
		self:RefreshEquipped(player)
	end)

	Net:OnRequest("Hatch", 0.35, hatch)

	-- restock announcements (every server sees the same stock at the same time)
	task.spawn(function()
		local lastSlot = Util.ShopSlot(Config, workspace:GetServerTimeNow())
		while true do
			task.wait(1)
			local slot = Util.ShopSlot(Config, workspace:GetServerTimeNow())
			if slot ~= lastSlot then
				lastSlot = slot
				Net:Broadcast("Restock", slot)
				-- the rarest egg in stock gets a shout-out
				local best = nil
				for _, eggId in Config.EggOrder do
					local egg = Config.Eggs[eggId]
					local stock = Util.EggStock(Config, eggId, slot)
					if stock and stock > 0 and egg.Stock.Chance < 0.7 and (not best or egg.Price > Config.Eggs[best].Price) then
						best = eggId
					end
				end
				if best then
					Net:Announce("🥚 Egg restock! %s is in stock!", Config.Eggs[best].Color, Config.Eggs[best].Name)
				else
					Net:Announce("🥚 The egg shops just restocked!", Color3.fromRGB(150, 230, 120))
				end
			end
		end
	end)

	-- sell one pet for a minute of its income
	Net:On("SellPet", 0.1, function(player, petId)
		local data = Data:Get(player)
		if not data or type(petId) ~= "number" then
			return
		end
		local pet, index = findPet(data, petId)
		if not pet or pet.Away then
			return
		end
		local coins = self:SellValue(pet.Name, pet.Variant)
		table.remove(data.Pets, index)
		data.Coins += coins
		data.Stats.LifetimeCoins += coins
		Net:Notify(player, "Sold %s for 💰%s", Color3.fromRGB(255, 220, 120), pet.Name, Util.Format(coins))
		self:Changed(player)
	end)

	-- quick cleanup: sell every plain pet of a low rarity (keeps your best ones)
	Net:On("SellRarity", 1, function(player, rarity)
		local data = Data:Get(player)
		if not data or (rarity ~= "Common" and rarity ~= "Uncommon") then
			return
		end
		local kept, coins, removed = {}, 0, 0
		for _, pet in data.Pets do
			local info = Config.Pets[pet.Name]
			-- mutated pets are never bulk-sold
			if info and info.Rarity == rarity and not pet.Variant and not pet.Away then
				removed += 1
				coins += self:SellValue(pet.Name, nil)
			else
				table.insert(kept, pet)
			end
		end
		data.Pets = kept
		data.Coins += coins
		data.Stats.LifetimeCoins += coins
		self:Changed(player)
		Net:Notify(player, "Sold %d %s pets for 💰%s", Color3.fromRGB(255, 220, 120), removed, rarity, Util.Format(coins))
	end)
end

return PetService
