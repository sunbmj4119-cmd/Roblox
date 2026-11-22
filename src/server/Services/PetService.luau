--[[
	PetService: eggs (coins / gems / stardust / Robux), luck, inventory,
	equip/unequip, and server-wide hatch announcements for rare pets.
	Equipped pet names are replicated through a player attribute so every
	client can render everyone's pets locally (cheap on the server).
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

-- Golden / Rainbow roll; luck raises the chance (capped at x4)
local function rollVariant(luck: number): string?
	local mult = math.clamp(luck, 1, 4)
	for _, def in Config.PetVariants do
		if math.random() < def.Chance * mult then
			return def.Id
		end
	end
	return nil
end

function PetService:RefreshEquipped(player: Player)
	local data = Data:Get(player)
	if not data then
		return
	end
	local byId = {}
	for _, pet in data.Pets do
		byId[pet.Id] = pet
	end
	local slots = Services.StatsService:PetSlots(player, data)
	local valid, names = {}, {}
	for _, id in data.Equipped do
		if byId[id] and not table.find(valid, id) and #valid < slots then
			table.insert(valid, id)
			-- "Variant|Name" so every client can render golden/rainbow pets
			table.insert(names, (byId[id].Variant or "") .. "|" .. byId[id].Name)
		end
	end
	data.Equipped = valid
	player:SetAttribute("Pets", HttpService:JSONEncode(names))
	Data:MarkDirty(player)
end

local function addPet(player: Player, data, name: string, variant: string?)
	local pet = { Id = data.NextPetUid, Name = name, Variant = variant }
	data.NextPetUid += 1
	table.insert(data.Pets, pet)
	data.PetIndex[name] = true
	if #data.Equipped < Services.StatsService:PetSlots(player, data) then
		table.insert(data.Equipped, pet.Id)
	end
	return pet
end

local function announceIfRare(player: Player, name: string, variant: string?, eggName: string)
	local info = Config.Pets[name]
	local rarity = info and Config.Rarities[info.Rarity]
	if not rarity then
		return
	end
	if rarity.Order >= Config.AnnounceRarity or variant == "Rainbow" then
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

local function roll(player: Player, data, eggId: string, count: number)
	local egg = Config.Eggs[eggId]
	local luck = Services.StatsService:Luck(player, data)
	local fn = luckFn(luck)
	local results = {}
	for _ = 1, count do
		local name = Util.WeightedPick(egg.Pets, fn)
		local variant = rollVariant(luck)
		addPet(player, data, name, variant)
		table.insert(results, { Name = name, Variant = variant })
		announceIfRare(player, name, variant, egg.Name)
	end
	data.Stats.EggsHatched += count
	Services.ProgressionService:TutorialEvent(player, "Hatch", count)
	Services.ProgressionService:AddQuest(player, "Hatch", count)
	Services.ProgressionService:AddSeasonXP(player, 25 * count)
	PetService:RefreshEquipped(player)
	return results
end

function PetService:GrantPet(player: Player, name: string, variant: string?)
	local data = Data:Get(player)
	if not data or not Config.Pets[name] then
		return
	end
	addPet(player, data, name, variant)
	self:RefreshEquipped(player)
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
	if #data.Pets + count > Config.MaxPets then
		return { Error = Net:L(player, "Pet inventory full! Delete some pets first.") }
	end
	local cost = egg.Price * count
	local balance = data[egg.Currency] or 0
	if balance < cost then
		return { Error = Net:L(player, "Not enough %s! Need %s more.", CURRENCY_NAMES[egg.Currency], Util.Format(cost - balance)) }
	end
	data[egg.Currency] -= cost
	local results = roll(player, data, eggId, count)
	return { Pets = results, Egg = eggId }
end

local function findPet(data, petId)
	for index, pet in data.Pets do
		if pet.Id == petId then
			return pet, index
		end
	end
	return nil, nil
end

function PetService:Init(services)
	Services = services
	Data = services.DataService
end

function PetService:Start()
	Data:OnLoaded(function(player)
		self:RefreshEquipped(player)
	end)

	Net:OnRequest("Hatch", 0.35, hatch)

	Net:On("EquipPet", 0.1, function(player, petId)
		local data = Data:Get(player)
		if not data or type(petId) ~= "number" or not findPet(data, petId) or table.find(data.Equipped, petId) then
			return
		end
		if #data.Equipped >= Services.StatsService:PetSlots(player, data) then
			Net:Notify(player, "All pet slots are full! Unequip one or get more slots.")
			Net:Send(player, "Upsell", "ExtraPets")
			return
		end
		table.insert(data.Equipped, petId)
		self:RefreshEquipped(player)
	end)

	Net:On("UnequipPet", 0.1, function(player, petId)
		local data = Data:Get(player)
		if not data then
			return
		end
		local index = table.find(data.Equipped, petId)
		if index then
			table.remove(data.Equipped, index)
			self:RefreshEquipped(player)
		end
	end)

	Net:On("EquipBest", 0.5, function(player)
		local data = Data:Get(player)
		if not data then
			return
		end
		local sorted = table.clone(data.Pets)
		table.sort(sorted, function(a, b)
			return power(a) > power(b)
		end)
		local slots = Services.StatsService:PetSlots(player, data)
		data.Equipped = {}
		for i = 1, math.min(slots, #sorted) do
			table.insert(data.Equipped, sorted[i].Id)
		end
		self:RefreshEquipped(player)
	end)

	Net:On("DeletePet", 0.1, function(player, petId)
		local data = Data:Get(player)
		if not data then
			return
		end
		local _, index = findPet(data, petId)
		if index then
			table.remove(data.Pets, index)
			local equippedIndex = table.find(data.Equipped, petId)
			if equippedIndex then
				table.remove(data.Equipped, equippedIndex)
			end
			self:RefreshEquipped(player)
		end
	end)

	-- quick cleanup: delete every unequipped pet of a low rarity
	Net:On("DeleteRarity", 1, function(player, rarity)
		local data = Data:Get(player)
		if not data or (rarity ~= "Common" and rarity ~= "Uncommon") then
			return
		end
		local kept = {}
		local removed = 0
		for _, pet in data.Pets do
			local info = Config.Pets[pet.Name]
			-- golden / rainbow pets are never bulk-deleted
			if info and info.Rarity == rarity and not pet.Variant and not table.find(data.Equipped, pet.Id) then
				removed += 1
			else
				table.insert(kept, pet)
			end
		end
		data.Pets = kept
		self:RefreshEquipped(player)
		Net:Notify(player, "Deleted %d %s pets", nil, removed, rarity)
	end)
end

return PetService
