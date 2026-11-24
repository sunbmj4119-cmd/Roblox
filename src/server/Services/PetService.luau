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
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Net = require(script.Parent.Net)

local PetService = {}
local Services
local Data

local CURRENCY_NAMES = { Coins = "coins", Gems = "gems", Stardust = "stardust" }

-- serial numbers (#1, #2, ...) for huge and exclusive pets: one global counter
-- per pet. Cloud tests (not a live server) count in a separate store.
local serialStore = nil
pcall(function()
	local name = "MeteorMiners_Serials_v1" .. (if RunService:IsRunning() then "" else "_Test")
	serialStore = DataStoreService:GetDataStore(name)
end)

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

-- where a new pet ended up: shown on the hatch card so players always know
-- ("🔒 in your vault", "🏠 on display +💰/s", "📦 in storage", "⭐ follows you")
local function describe(player: Player, data, pet, isNew: boolean?)
	local where, rate = "Storage", 0
	local base = Services.BaseService
	if base then
		local vault, display = Util.ArrangePets(Config, data)
		if table.find(vault, pet) then
			where, rate = "Vault", base:PetRate(player, data, pet, true)
		elseif table.find(display, pet) then
			where, rate = "Display", base:PetRate(player, data, pet, false)
		end
	end
	return {
		Id = pet.Id,
		Name = pet.Name,
		Variant = pet.Variant,
		Where = where,
		Rate = rate,
		New = isNew == true,
		Follow = table.find(data.Equipped, pet.Id) ~= nil,
	}
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

local function addPet(data, name: string, variant: string?, serial: number?)
	local pet = { Id = data.NextPetUid, Name = name, Variant = variant, Serial = serial }
	data.NextPetUid += 1
	table.insert(data.Pets, pet)
	data.PetIndex[name] = true
	return pet
end

local function nextSerial(key: string): number?
	if not serialStore then
		return nil
	end
	local value = nil
	local ok = pcall(function()
		value = serialStore:UpdateAsync(key, function(old)
			return (tonumber(old) or 0) + 1
		end)
	end)
	return if ok then tonumber(value) else nil
end

-- number a new huge / exclusive pet (async); then(serial?) runs afterwards
-- (the pet can't be traded / stolen / sold while it waits: no number gets lost)
local function giveSerial(player: Player, data, pet, andThen)
	pet.SerialPending = true
	task.spawn(function()
		local key = (if pet.Variant == "Huge" then "Huge|" else "") .. pet.Name
		local serial = nextSerial(key)
		pet.SerialPending = nil
		if serial and table.find(data.Pets, pet) and not pet.Serial then
			pet.Serial = serial
			Data:MarkDirty(player)
		end
		if player.Parent then
			PetService:Changed(player)
		end
		if andThen then
			andThen(serial)
		end
	end)
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
		local precious = pet.Serial ~= nil or pet.SerialPending or Util.IsExclusive(Config, pet)
		if not pet.Away and not precious and (not weakest or income(pet) < income(weakest)) then
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

-- "1 in 12.5K" for the announcement (base odds, no luck)
local function oddsText(eggId: string?, name: string, variant: string?): string
	local chance = eggId and Util.HatchChance(Config, eggId, name, variant)
	if not chance or chance <= 0 then
		return ""
	end
	return " (1/" .. Util.Format(math.max(1, math.floor(1 / chance + 0.5))) .. ")"
end

local function announceIfRare(player: Player, name: string, variant: string?, eggId: string?, serial: number?)
	local info = Config.Pets[name]
	local rarity = info and Config.Rarities[info.Rarity]
	if not rarity then
		return
	end
	local eggName = eggId and Config.Eggs[eggId] and Config.Eggs[eggId].Name or ""
	-- big moments: a beam of light on the player for everyone in the server
	if variant == "Huge" or variant == "Titanic" or rarity.Order >= 7 then
		Net:Broadcast("BigHatch", player.UserId, variant or info.Rarity)
	end
	if variant == "Titanic" then
		-- shouted in EVERY server
		Services.EventService:GlobalAnnounce(
			"🗿 %s hatched a TITANIC %s%s!%s",
			Color3.fromRGB(255, 120, 60),
			player.DisplayName,
			name,
			if serial then " #" .. serial else "",
			oddsText(eggId, name, variant)
		)
	elseif variant == "Huge" then
		Net:Announce(
			"🐘 %s hatched a HUGE %s%s!%s",
			Color3.fromRGB(255, 200, 60),
			player.DisplayName,
			name,
			if serial then " #" .. serial else "",
			oddsText(eggId, name, variant)
		)
	elseif rarity.Order >= Config.AnnounceRarity or variant == "Rainbow" or variant == "Galaxy" then
		Net:Announce(
			"🥚 %s hatched a %s %s %s from the %s!%s",
			if variant == "Rainbow" then Color3.fromRGB(255, 120, 230) else rarity.Color,
			player.DisplayName,
			variant or "",
			info.Rarity,
			name,
			eggName,
			oddsText(eggId, name, variant)
		)
	end
end

-- roll `count` pets from an egg; extraLuck multiplies the player's luck
local function roll(player: Player, data, eggId: string, count: number, extraLuck: number?)
	local egg = Config.Eggs[eggId]
	local luck = Services.StatsService:Luck(player, data) * (extraLuck or 1)
	local fn = luckFn(luck)
	local made = {}
	for _ = 1, count do
		local name = Util.WeightedPick(egg.Pets, fn)
		local variant = rollVariant(luck)
		local isNew = not data.PetIndex[name]
		local ok, coins = makeRoom(player, data, name, variant)
		local pet = if ok then addPet(data, name, variant) else nil
		table.insert(made, { Pet = pet, Name = name, Variant = variant, New = isNew, Coins = if ok then nil else coins })
		if variant == "Huge" then
			data.Stats.HugesFound = (data.Stats.HugesFound or 0) + 1
		elseif variant == "Titanic" then
			data.Stats.TitanicsFound = (data.Stats.TitanicsFound or 0) + 1
		end
		if pet and Util.WantsSerial(Config, name, variant) then
			giveSerial(player, data, pet, function(serial)
				announceIfRare(player, name, variant, eggId, serial)
			end)
		else
			announceIfRare(player, name, variant, eggId, nil)
		end
	end
	data.Stats.EggsHatched += count
	Services.ProgressionService:TutorialEvent(player, "Hatch", count)
	Services.ProgressionService:AddQuest(player, "Hatch", count)
	Services.ProgressionService:AddSeasonXP(player, 25 * count)
	PetService:Changed(player)
	local results = {}
	for _, entry in made do
		if entry.Pet then
			table.insert(results, describe(player, data, entry.Pet, entry.New))
		else
			-- storage was full and the new pet was the weakest: sold right away
			table.insert(results, { Name = entry.Name, Variant = entry.Variant, Where = "Sold", Coins = entry.Coins, New = entry.New })
		end
	end
	return results
end

function PetService:GrantPet(player: Player, name: string, variant: string?)
	local data = Data:Get(player)
	if not data or not Config.Pets[name] then
		return
	end
	local isNew = not data.PetIndex[name]
	local ok, coins = makeRoom(player, data, name, variant)
	local pet = nil
	if ok then
		pet = addPet(data, name, variant)
		if Util.WantsSerial(Config, name, variant) then
			giveSerial(player, data, pet, nil)
		end
	end
	self:Changed(player)
	local result = if pet
		then describe(player, data, pet, isNew)
		else { Name = name, Variant = variant, Where = "Sold", Coins = coins, New = isNew }
	Net:Send(player, "HatchResult", { result }, nil)
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
	return { Name = pet.Name, Variant = pet.Variant, Serial = pet.Serial }
end

-- numbered pets keep their number when they change owners
function PetService:GivePet(player: Player, name: string, variant: string?, serial: number?)
	local data = Data:Get(player)
	if not data or not Config.Pets[name] then
		return
	end
	local isNew = not data.PetIndex[name]
	local pet = nil
	if makeRoom(player, data, name, variant) then
		pet = addPet(data, name, variant, serial)
	end
	self:Changed(player)
	return pet, isNew
end

-- (used to show a stolen pet with the same "where did it go" card)
function PetService:Describe(player: Player, pet, isNew: boolean?)
	local data = Data:Get(player)
	return data and describe(player, data, pet, isNew) or nil
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

-- egg stands: hold "Hatch" to hatch one without opening the shop
local quickHatchAt = {}
function PetService:QuickHatch(player: Player, eggId: string)
	if os.clock() - (quickHatchAt[player] or 0) < 0.6 then
		return
	end
	quickHatchAt[player] = os.clock()
	local result = hatch(player, eggId, 1)
	if type(result) ~= "table" then
		return
	end
	if result.Error then
		Net:Send(player, "Notify", result.Error, Color3.fromRGB(255, 110, 110))
		return
	end
	Net:Send(player, "HatchResult", result.Pets, eggId)
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
			pet.SerialPending = nil
		end
		-- numbered pets whose number never arrived (DataStore hiccup): try again
		for _, pet in data.Pets do
			if not pet.Serial and Util.WantsSerial(Config, pet.Name, pet.Variant) then
				giveSerial(player, data, pet, nil)
			end
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
		if not pet or pet.Away or pet.SerialPending then
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
