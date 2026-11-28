--[[
	RivalHomes: rival players own a home too - a real estate in the base
	district with a house and pets on display.

	  * 🌙 Thief Night (or revenge): you can steal a rival's displayed pet and
	    run it home. The rival runs after you (they may bonk you even inside
	    the base district - it's their pet). One theft per rival home per
	    few minutes (like players' theft shield).
	  * 🌙 Thief Night: a rival may sneak into YOUR home and grab a pet from a
	    display pedestal (never a vault / exclusive pet, never through locks
	    or shields). You get an alarm - bonk them before they get home! If
	    they make it, the pet stands in their home: steal it back (revenge
	    for 5 minutes, or the next Thief Night). When a rival leaves the
	    server, pets they took go back to their owners.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local PetModel = require(Shared.PetModel)
local DecorModel = require(Shared.DecorModel)
local Net = require(script.Parent.Net)

local Homes = {}
local Services
local Data
local World

local SETTINGS = Config.Base
local SLOTS = { { -12, 4 }, { -6, 2 }, { 0, 2 }, { 6, 2 }, { 12, 4 } }
local rng = Random.new()
local byIndex = {} -- [plot index] = rival record
local byUser = {} -- [rival UserId] = rival record
local nextUid = 0

local function newPet(fields)
	nextUid += 1
	fields.Uid = nextUid
	return fields
end

local function findPet(record, uid)
	for index, pet in record.HomePets or {} do
		if pet.Uid == uid then
			return pet, index
		end
	end
	return nil, nil
end

-- the weakest pet that may make room (not away, not a player's)
local function weakestIndex(record)
	local best, bestIndex = nil, nil
	for index, pet in record.HomePets do
		if not pet.Away and not pet.FromUserId and (not best or Util.PetIncomeOf(Config, pet) < Util.PetIncomeOf(Config, best)) then
			best, bestIndex = pet, index
		end
	end
	return best, bestIndex
end

local function now(): number
	return workspace:GetServerTimeNow()
end

local function internal()
	return Services.BaseService.Internal
end

local function raidActive(): boolean
	local events = Services.EventService
	return events ~= nil and events:RaidActive()
end

-- someone is carrying one of this home's pets right now
local function beingRobbed(record): boolean
	for _, pet in record.HomePets or {} do
		if pet.Away then
			return true
		end
	end
	return false
end

-- may this player steal from this rival right now?
local function canRaid(player: Player, record): boolean
	if (record.HomeShieldUntil or 0) > now() or beingRobbed(record) then
		return false
	end
	if raidActive() then
		return true
	end
	return player:GetAttribute("RevengeTarget") == record.Entity.UserId and (player:GetAttribute("RevengeUntil") or 0) > now()
end

-- a fresh set of pets for a new rival (from the server's eggs, a little grown)
local function startingPets(zone: number)
	local pool = Config.Eggs[Config.Shards.ZoneEggs[math.clamp(zone, 1, #Config.Shards.ZoneEggs)]].Pets
	local pets = {}
	for _ = 1, rng:NextInteger(3, 5) do
		local name = Util.WeightedPick(pool, nil, rng)
		table.insert(
			pets,
			newPet({
				Name = name,
				Variant = if rng:NextNumber() < 0.08 then "Golden" else nil,
				Level = rng:NextInteger(1, 8),
				Stars = if rng:NextNumber() < 0.15 then 1 else 0,
			})
		)
	end
	return pets
end

local function homeRate(record): number
	local total = 0
	for _, pet in record.HomePets do
		if not pet.Away then
			total += Util.PetIncomeOf(Config, pet)
		end
	end
	return total
end

local function refreshSign(record)
	local plot = internal().Plots[record.HomeIndex]
	if not plot then
		return
	end
	local shielded = (record.HomeShieldUntil or 0) > now() or beingRobbed(record)
	local open = raidActive() and not shielded
	local status = if open then "🔓 OPEN" elseif shielded then "🛡️ THEFT SHIELD" else "🏠 SAFE"
	plot.Model:SetAttribute("Protection", if open then "" else "safe")
	-- (hides the steal prompts even for revenge while shielded / being robbed)
	plot.Model:SetAttribute("Robbing", shielded)
	plot.Model:SetAttribute("Rate", homeRate(record))
	local key = status .. "|" .. math.floor(homeRate(record))
	if key ~= record.SignKey then
		record.SignKey = key
		World.SetText(
			plot.Sign,
			"🏠 %s's HOUSE\n💰 %s/s  ❤️ %s  ⭐ Lv.%s\n%s",
			record.Name,
			Util.Format(homeRate(record)),
			tostring(record.Likes),
			tostring(record.HouseLevel),
			status
		)
	end
end

function Homes:Render(record)
	local plot = internal().Plots[record.HomeIndex]
	if not plot then
		return
	end
	plot.Displays:ClearAllChildren()
	for slot, pet in record.HomePets do
		local spot = SLOTS[slot]
		if spot then
			local cf = plot.CFrame * CFrame.new(spot[1], 0.52, spot[2])
			local pedestal = DecorModel.Build(Config, "Pedestal", nil)
			pedestal:PivotTo(cf)
			pedestal.Parent = plot.Displays
			if not pet.Away then
				local top = pedestal:FindFirstChild("Top")
				local petModel = PetModel.Build(pet.Name, pet.Variant, { Level = pet.Level, Stars = pet.Stars })
				petModel.Name = "RivalPet_" .. slot
				local base = if top and top:IsA("BasePart") then top.Position else cf.Position + Vector3.new(0, 2.6, 0)
				petModel:PivotTo(CFrame.new(base + Vector3.new(0, 1.6, 0)) * (cf - cf.Position))
				local box, size = petModel:GetBoundingBox()
				local lift = (base.Y + 0.2) - (box.Position.Y - size.Y / 2)
				if lift > 0 then
					petModel:PivotTo(petModel:GetPivot() + Vector3.new(0, lift, 0))
				end
				petModel:SetAttribute("Spin", true)
				petModel:SetAttribute("PetId", -1000 - slot)
				petModel.Parent = plot.Displays
				local info = Config.Pets[pet.Name]
				local rarity = info and Config.Rarities[info.Rarity] or Config.Rarities.Common
				local anchor = petModel.PrimaryPart :: BasePart
				local label = internal().Billboard(anchor, 5.5, 1.7, size.Y + 1, rarity.Color, 40)
				World.SetText(
					label,
					"%s %s%s\n%s  💰 %s/s",
					"🌠",
					if pet.Variant then pet.Variant .. " " else "",
					pet.Name,
					Util.PetBadge(Config, pet),
					Util.Format(Util.PetIncomeOf(Config, pet))
				)
				local uid = pet.Uid
				internal().SetPrompt(anchor, "Steal", pet.Name, "Thief", SETTINGS.StealHold, function(thief)
					Homes:StealFrom(thief, record, uid)
				end)
			end
		end
	end
	record.SignKey = nil
	refreshSign(record)
end

-- a rival moves into a free plot (never one a player could need: see BaseService assign)
function Homes:Claim(record): boolean
	local plot = nil
	for _, candidate in internal().Plots do
		if not candidate.Owner and not candidate.Rival then
			plot = candidate
		end
	end
	if not plot then
		return false
	end
	local zone = 1
	for _, player in Data:LoadedPlayers() do
		local data = Data:Get(player)
		if data then
			zone = math.max(zone, data.ZoneLevel or 1)
		end
	end
	plot.Rival = record
	record.HomeIndex = plot.Index
	record.HouseLevel = rng:NextInteger(1, 3)
	record.Likes = rng:NextInteger(0, 25)
	record.HomePets = startingPets(zone)
	byIndex[plot.Index] = record
	byUser[record.Entity.UserId] = record
	local fake = { Base = { Level = record.HouseLevel, Skin = "Auto", Roof = rng:NextInteger(0, #Config.Paint), Items = {}, Skins = {} } }
	internal().ApplyStyle(plot, fake)
	plot.Model:SetAttribute("OwnerId", record.Entity.UserId)
	plot.Model:SetAttribute("OwnerName", record.Name)
	plot.Model:SetAttribute("HouseLevel", record.HouseLevel)
	plot.Model:SetAttribute("Likes", record.Likes)
	self:Render(record)
	return true
end

-- leaving: pets taken from players go back to them, the plot is free again
function Homes:Release(record)
	local plot = record.HomeIndex and internal().Plots[record.HomeIndex]
	for _, pet in record.HomePets or {} do
		if pet.FromUserId and pet.OwnPetId then
			for _, owner in Data:LoadedPlayers() do
				if owner.UserId == pet.FromUserId then
					Homes:GiveBack(owner, pet.OwnPetId)
					Net:Notify(owner, "🛡️ %s left - your %s came back home!", Color3.fromRGB(120, 230, 255), record.Name, pet.Name)
				end
			end
		end
	end
	record.Home = nil
	if plot then
		byIndex[plot.Index] = nil
		plot.Rival = nil
		internal().ClearPlot(plot)
	end
	byUser[record.Entity.UserId] = nil
	record.HomeIndex = nil
	record.HomePets = {}
end

-- a player needs this plot: the rival moves out (keeps playing without a home)
function Homes:EvictFor(plot)
	local record = byIndex[plot.Index]
	if record then
		self:Release(record)
	end
end

function Homes:HomeSpot(record): Vector3?
	local plot = record.HomeIndex and internal().Plots[record.HomeIndex]
	return plot and (plot.CFrame * CFrame.new(0, 3, -4)).Position
end

function Homes:IsHomeOf(record, position: Vector3): boolean
	local plot = record.HomeIndex and internal().Plots[record.HomeIndex]
	if not plot then
		return false
	end
	local localPos = plot.CFrame:PointToObjectSpace(position)
	local half = internal().PlotHalf
	return math.abs(localPos.X) <= half and math.abs(localPos.Z) <= half + 1
end

---------------------------------------------------------------------------
-- players steal from rivals
---------------------------------------------------------------------------
function Homes:StealFrom(thief: Player, record, uid: number)
	local pet = findPet(record, uid)
	if not pet or pet.Away or not record.HomeIndex then
		return
	end
	local shards = Services.ShardService
	if shards:IsCarrying(thief) then
		Net:Notify(thief, "Your hands are full!")
		return
	end
	if not Services.BaseService:HasBase(thief) then
		Net:Notify(thief, "You need a base to steal pets!")
		return
	end
	if not canRaid(thief, record) then
		Net:Notify(thief, "🏠 Homes are safe! Raids only happen on 🌙 Thief Night.")
		return
	end
	if pet.FromUserId and pet.FromUserId ~= thief.UserId then
		Net:Notify(thief, "That's someone else's pet - only its owner can take it back.")
		return
	end
	local item = { Kind = "Pet", Name = pet.Name, Variant = pet.Variant }
	local meta = {
		RivalFrom = record.Entity.UserId,
		RivalSlot = uid,
		Growth = { Level = pet.Level, Stars = pet.Stars, XP = pet.XP },
		OwnPetId = pet.OwnPetId, -- (the thief's own pet, held by the rival)
		Thief = thief,
		Deadline = os.clock() + SETTINGS.StolenCarrySeconds,
	}
	pet.Away = true
	if not shards:StartCarry(thief, item, meta) then
		pet.Away = nil
		return
	end
	self:Render(record)
	-- the owner runs after you
	Services.RivalService:Defend(record, thief)
	Net:Notify(thief, "🦹 You grabbed %s's %s - run home!", Color3.fromRGB(255, 170, 90), record.Name, pet.Name)
end

-- the stolen pet made it to the thief's home
function Homes:PetGone(rivalId: number, uid: number)
	local record = byUser[rivalId]
	if not record then
		return
	end
	local _, index = findPet(record, uid)
	if not index then
		return
	end
	table.remove(record.HomePets, index)
	record.HomeShieldUntil = now() + SETTINGS.TheftShieldSeconds
	self:Render(record)
end

-- dropped / too slow: the pet runs back to the rival's home
function Homes:PetBack(rivalId: number, uid: number)
	local record = byUser[rivalId]
	local pet = if record then findPet(record, uid) else nil
	if pet then
		pet.Away = nil
		self:Render(record)
	end
end

---------------------------------------------------------------------------
-- rivals steal from players (🌙 Thief Night only)
---------------------------------------------------------------------------
-- a pet on display in an unprotected home (owner, pet, position of the pet)
function Homes:RaidTarget(record)
	if not raidActive() then
		return nil
	end
	local base = Services.BaseService
	local options = {}
	for _, player in Data:LoadedPlayers() do
		local data = Data:Get(player)
		local plot = base:PlotOf(player)
		if data and plot and base:Protection(player) == nil then
			for _, pet in base.DisplayedPets(data) do
				if not pet.Away and not pet.SerialPending and not pet.Serial and not Util.IsExclusive(Config, pet) then
					local model = plot.Displays:FindFirstChild("Pet_" .. pet.Id)
					if model and model:IsA("Model") then
						table.insert(options, { Owner = player, Pet = pet, Position = model:GetPivot().Position })
					end
				end
			end
		end
	end
	if #options == 0 or not record then
		return nil
	end
	return options[rng:NextInteger(1, #options)]
end

-- grab it (the owner gets an alarm); returns the carried item + meta
function Homes:TakeFromPlayer(record, owner: Player, petId: number)
	local base = Services.BaseService
	local data = Data:Get(owner)
	local pet = data and Services.PetService.FindPet(data, petId)
	if not pet or pet.Away or base:Protection(owner) ~= nil then
		return nil
	end
	local onDisplay = false
	for _, shown in base.DisplayedPets(data) do
		onDisplay = onDisplay or shown == pet
	end
	if not onDisplay or Util.IsExclusive(Config, pet) or pet.Serial then
		return nil
	end
	base:SetAway(owner, petId, true)
	Net:Notify(owner, "🚨 %s is stealing your %s! Bonk them before they get home!", Color3.fromRGB(255, 90, 90), record.Name, pet.Name)
	Net:Send(owner, "RaidAlarm", record.Name)
	return { Kind = "Pet", Name = pet.Name, Variant = pet.Variant }, {
		From = owner,
		PetId = petId,
		RivalThief = record.Entity.UserId,
		Deadline = os.clock() + SETTINGS.StolenCarrySeconds,
	}
end

-- the rival brought a star egg home: it hatches on their display
function Homes:EggHome(record, item)
	if not record.HomeIndex or not item or not item.Egg or not Config.Eggs[item.Egg] then
		return
	end
	local name = Util.WeightedPick(Config.Eggs[item.Egg].Pets, nil, rng)
	if #record.HomePets >= #SLOTS then
		-- keep the best ones
		local weakest, index = weakestIndex(record)
		if not weakest or Util.PetIncome(Config, name, nil) <= Util.PetIncomeOf(Config, weakest) then
			return
		end
		table.remove(record.HomePets, index)
	end
	table.insert(record.HomePets, newPet({ Name = name, Level = 1, Stars = 0 }))
	self:Render(record)
end

-- a held pet comes back to its owner (it never left their save)
function Homes:GiveBack(owner: Player, petId: number)
	local data = Data:Get(owner)
	local pet = data and Services.PetService.FindPet(data, petId)
	if pet then
		pet.HeldBy = nil
		Services.BaseService:SetAway(owner, petId, false)
	end
end

-- the rival made it home with a player's pet: it stands on their display
-- now. (The pet stays in the owner's save, marked held: it can never be
-- lost - leaving / rejoining / the rival leaving brings it back.)
function Homes:Delivered(record, meta)
	local owner = meta and meta.From
	if not owner or not owner.Parent or not meta.PetId then
		return
	end
	local data = Data:Get(owner)
	local pet = data and Services.PetService.FindPet(data, meta.PetId)
	if not pet then
		return
	end
	if not record.HomeIndex then
		self:GiveBack(owner, meta.PetId)
		return
	end
	if #record.HomePets >= #SLOTS then
		local _, index = weakestIndex(record)
		if not index then
			self:GiveBack(owner, meta.PetId) -- (no room on their display)
			return
		end
		table.remove(record.HomePets, index)
	end
	pet.Away = true
	pet.HeldBy = record.Entity.UserId
	table.insert(
		record.HomePets,
		newPet({
			Name = pet.Name,
			Variant = pet.Variant,
			Level = pet.Level,
			Stars = pet.Stars,
			FromUserId = owner.UserId,
			OwnPetId = pet.Id,
		})
	)
	local taken = pet
	self:Render(record)
	-- revenge: steal it back for 5 minutes (even outside Thief Night) -
	-- unless a revenge on a real player is still running
	local running = (owner:GetAttribute("RevengeUntil") or 0) > now() and (owner:GetAttribute("RevengeTarget") or 0) > 0
	if not running then
		owner:SetAttribute("RevengeTarget", record.Entity.UserId)
		owner:SetAttribute("RevengeUntil", now() + SETTINGS.RevengeSeconds)
		Net:Send(owner, "Revenge", record.Entity.UserId, record.Name, now() + SETTINGS.RevengeSeconds)
	end
	Net:Notify(
		owner,
		"💔 %s stole your %s! Get it back from their house - revenge for 5 minutes!",
		Color3.fromRGB(255, 90, 90),
		record.Name,
		taken.Name
	)
end

function Homes:Init(services)
	Services = services
	Data = services.DataService
	World = services.WorldService
end

function Homes:Start()
	-- a player left: pets a rival took from them go home with their save
	Players.PlayerRemoving:Connect(function(player)
		for _, record in byIndex do
			local changed = false
			for index = #record.HomePets, 1, -1 do
				if record.HomePets[index].FromUserId == player.UserId and not record.HomePets[index].Away then
					table.remove(record.HomePets, index)
					changed = true
				end
			end
			if changed then
				pcall(Homes.Render, Homes, record)
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			for _, record in byIndex do
				pcall(refreshSign, record)
			end
		end
	end)
end

return Homes
