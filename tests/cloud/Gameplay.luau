-- Cloud gameplay test: boots the real server services on a Roblox server and
-- plays the core loop with stand-in players (no real clients needed):
-- hatch (cost + stock), vault / display pedestals + income, collect,
-- decorate + house level + paint + sets, every theft protection (lock,
-- newbie shield, vault, fair-size rule, theft shield), a real steal, revenge,
-- bounty, star egg, trade (serial kept), exclusive pets, huge pets, house
-- name / skins and titles, homes safe outside 🌙 Thief Night, the ☄️ meteor
-- round (sites, marker, GO, smash, egg burst, coin chunks, index) and the
-- new first minute (tutorial meteor -> egg -> home).
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local results = { errors = {}, passed = 0 }
local function fail(message)
	table.insert(results.errors, message)
end
local function check(ok, message)
	if ok then
		results.passed += 1
	else
		fail(message)
	end
end

-- boot (same order as Main.server.luau)
local folder = ServerScriptService.Server.Services
local ORDER = {
	"Analytics",
	"DataService",
	"StatsService",
	"MonetizationService",
	"BoostService",
	"EventService",
	"WorldService",
	"CharacterService",
	"EconomyService",
	"PetService",
	"MiningService",
	"BaseService",
	"ShardService",
	"TradeService",
	"MeteorService",
	"LuckyService",
	"RivalService",
	"ProgressionService",
	"LeaderboardService",
	"DevService",
}
local S = {}
for _, name in ORDER do
	local ok, mod = pcall(require, folder[name])
	if ok then
		S[name] = mod
	else
		fail("require " .. name .. ": " .. tostring(mod))
	end
end
for _, name in ORDER do
	if S[name] and S[name].Init then
		local ok, err = pcall(S[name].Init, S[name], S)
		if not ok then
			fail("init " .. name .. ": " .. tostring(err))
		end
	end
end
for _, name in ORDER do
	if S[name] and name ~= "DataService" and S[name].Start then
		local ok, err = pcall(S[name].Start, S[name])
		if not ok then
			fail("start " .. name .. ": " .. tostring(err))
		end
	end
end
pcall(S.DataService.Start, S.DataService)
task.wait(1)

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Net = require(folder.Net)
local Data = S.DataService
local Base = S.BaseService

-- stand-in players -----------------------------------------------------------------
local function fakePlayer(id: number, name: string)
	local attrs = {}
	local character = Instance.new("Model")
	character.Name = name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Anchored = true
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(0, 3, -60)
	root.Parent = character
	Instance.new("Humanoid").Parent = character
	character.PrimaryPart = root
	character.Parent = workspace
	local fake = {
		UserId = id,
		Name = name,
		DisplayName = name,
		Parent = game:GetService("Players"),
		Character = character,
		MembershipType = Enum.MembershipType.None,
		LocaleId = "en-us",
	}
	function fake:GetAttribute(key)
		return attrs[key]
	end
	function fake:SetAttribute(key, value)
		attrs[key] = value
	end
	function fake:FindFirstChildOfClass()
		return nil
	end
	function fake:FindFirstChild()
		return nil -- no leaderstats folder for stand-ins
	end
	return fake, root
end

local A, rootA = fakePlayer(1001, "Alice")
local B, rootB = fakePlayer(1002, "Bob")
local Cp = fakePlayer(1003, "Carol")
for _, pair in { { A, 50000 }, { B, 50000 }, { Cp, 50000 } } do
	local data = Util.DeepCopy(Data.Template)
	data.Coins = pair[2]
	data.Gems = 1000
	data.Tutorial.Done = true
	data.Flags.HowToSeen = true
	data.Flags.NewbieOff = true -- veterans (the newbie shield is tested on its own)
	data.Stats.PlaySeconds = 100000
	local errors = Data:InjectForTest(pair[1], data)
	for _, err in errors do
		fail("OnLoaded for " .. pair[1].Name .. ": " .. err)
	end
end
task.wait(0.5)
local dataA, dataB, dataC = Data:Get(A), Data:Get(B), Data:Get(Cp)
local plotA, plotB = Base:PlotOf(A), Base:PlotOf(B)
local function unprotect(plot)
	plot.LockedUntil = 0
	plot.LockReadyAt = 0
	plot.ShieldUntil = 0
end

-- 1) bases assigned (each starts locked), starter layout with a vault
check(A:GetAttribute("BaseIndex") ~= nil and B:GetAttribute("BaseIndex") ~= nil, "players got no base")
check(plotA and plotA.LockedUntil > workspace:GetServerTimeNow(), "a base should start locked when you join")
local displayItems, vaultItems = Util.Pedestals(Config, dataA.Base.Items)
check(#displayItems >= Config.Base.StartPedestals, "starter pedestals not seeded")
check(#vaultItems == 1, "starter vault not seeded")
for _, plot in { plotA, plotB, Base:PlotOf(Cp) } do
	unprotect(plot)
end

-- 2) hatch a Meadow egg through the real request handler
local coinsBefore = dataA.Coins
local result = Net:CallForTest("Hatch", A, "Meadow", 1)
check(type(result) == "table" and result.Pets and #result.Pets == 1, "hatch failed: " .. HttpService:JSONEncode(result or {}))
check(dataA.Coins == coinsBefore - Config.Eggs.Meadow.Price, "hatch did not charge the price")
check(#dataA.Pets == 1, "pet not added")
local card = type(result) == "table" and result.Pets and result.Pets[1]
local places = { Vault = true, Display = true, Storage = true, Sold = true }
check(card and places[card.Where] == true, "hatch card does not say where the pet went")
check(card and card.New == true, "first pet of a kind should be NEW")
check((dataA.Shop.Bought.Meadow or 0) == 1, "stock purchase not counted")
results.firstPet = dataA.Pets[1] and dataA.Pets[1].Name

for _ = 1, 3 do
	S.PetService:GrantPet(A, "Fox", nil)
end
check(#dataA.Pets == 4, "GrantPet failed")

-- 3) the best pet is safe in the vault, the rest stand on display and earn
local vault, shown = Util.ArrangePets(Config, dataA)
check(#vault == 1, "best pet should be in the vault")
check(#shown == math.min(#displayItems, #dataA.Pets - #vault), string.format("displayed %d pets", #shown))
local rate = Base:IncomeRate(A, dataA)
check(rate > 0, "base earns nothing")
local fullRate = 0
for _, pet in shown do
	fullRate += Base:PetRate(A, dataA, pet, false)
end
local vaultRate = Base:PetRate(A, dataA, vault[1], true)
check(math.abs(rate - fullRate - vaultRate) < 1e-6, "income should be display + vault")
check(math.abs(vaultRate - Base:PetRate(A, dataA, vault[1], false) * Config.Base.VaultIncome) < 1e-6, "vault pets should earn VaultIncome")
results.baseRate = rate
local displays = plotA.Displays:GetChildren()
check(#displays == #shown + #vault, "pedestal pet models missing: " .. #displays)
check(#dataA.Equipped >= 1, "no pet follows the player")

-- 4) collect the bank
dataA.Base.Bank = 1234
local beforeCollect = dataA.Coins
Base:Collect(A)
check(dataA.Coins == beforeCollect + 1234 and dataA.Base.Bank < 1, "collect failed")

-- 5) decorate: place + remove with refund, bounds by house level, paint, upgrade
local ok, message = Net:CallForTest("BasePlace", A, "Tree", 0, 14, 0)
check(ok == true, "place tree failed: " .. tostring(message))
local placed = dataA.Base.Items[#dataA.Base.Items]
local coinsAfterPlace = dataA.Coins
local ok2 = Net:CallForTest("BaseRemove", A, placed.Uid)
check(ok2 == true and dataA.Coins == coinsAfterPlace + Config.Decor.Tree.Price, "remove/refund failed")
check(Net:CallForTest("BasePlace", A, "Tree", 999, 999, 0) ~= true, "out-of-bounds placement was accepted")
check(Net:CallForTest("BasePlace", A, "Tree", 0, 14, math.huge) ~= true, "infinite rotation was accepted (NaN in saves)")
check(Net:CallForTest("BasePlace", A, "Tree", 0 / 0, 14, 0) ~= true, "NaN position was accepted")
check(Net:CallForTest("BasePlace", A, "Tree", 18, 0, 0) ~= true, "level 1 house should not reach x=18")
check(Net:CallForTest("BasePlace", A, "Windmill", -6, -14, 0) ~= true, "level-locked item was placed")
local coinsBeforeUpgrade = dataA.Coins
check(Net:CallForTest("HouseUpgrade", A) == true, "house upgrade failed")
check(Util.HouseLevel(Config, dataA) == 2, "house level did not go up")
check(dataA.Coins == coinsBeforeUpgrade - Config.Base.Levels[2].Cost, "house upgrade did not charge")
check(Net:CallForTest("BasePlace", A, "Tree", 18, 0, 0) == true, "level 2 house should reach x=18")
local tree = dataA.Base.Items[#dataA.Base.Items]
check(Net:CallForTest("BasePaint", A, tree.Uid, 3) == true and tree.Paint == 3, "paint failed")
local painted = plotA.ItemModels[tree.Uid]
local leaves = painted and painted:FindFirstChild("Leaves")
check(leaves and leaves.Color == Config.Paint[3], "painted model has the wrong colour")
check(Net:CallForTest("BasePaint", A, tree.Uid, 0) == true and tree.Paint == nil, "unpaint failed")
check(Net:CallForTest("BasePaint", A, tree.Uid, 0 / 0) ~= true and tree.Paint == nil, "NaN paint was accepted")
Net:CallForTest("BaseRemove", A, tree.Uid)

-- 6) protection --------------------------------------------------------------
local victim = shown[1]
local function tryTake(thief, owner, petId): boolean
	Base:TrySteal(thief, owner, petId)
	local carrying = S.ShardService:IsCarrying(thief)
	if carrying then
		-- undo: put it back
		local info = S.ShardService
		info:Confiscate(thief, owner)
	end
	return carrying
end
-- 🏠 homes are safe unless it's 🌙 Thief Night (the only raid time)
check(Base:Protection(A) == "safe", "a home should be safe outside Thief Night: " .. tostring(Base:Protection(A)))
check(not tryTake(B, A, victim.Id), "stole from a home outside Thief Night")
Base:Lock(A)
check(plotA.LockedUntil <= workspace:GetServerTimeNow(), "the lock was used up outside Thief Night")
S.EventService:Trigger("ThiefNight")
check(S.EventService:RaidActive() and workspace:GetAttribute("RaidActive") == true, "Thief Night is not a raid")
-- a) locked
Base:Lock(A)
check(Base:Protection(A) == "locked", "lock not active")
check(not tryTake(B, A, victim.Id), "stole from a locked base")
unprotect(plotA)
-- b) newbie shield
dataA.Flags.NewbieOff = false
dataA.Stats.PlaySeconds = 0
check(Base:Protection(A) == "newbie", "newbie shield not active")
check(not tryTake(B, A, victim.Id), "stole from a newbie")
dataA.Flags.NewbieOff = true
dataA.Stats.PlaySeconds = 100000
-- c) vault pets can never be stolen
check(not tryTake(B, A, vault[1].Id), "stole a vault pet")
-- d) fair-size rule: a much richer thief can't rob a small base
S.PetService:GivePet(B, "Black Hole Kitty", nil)
check(not tryTake(B, A, victim.Id), "a giant stole from a tiny base")
for index, pet in dataB.Pets do
	if pet.Name == "Black Hole Kitty" then
		table.remove(dataB.Pets, index)
		break
	end
end
S.PetService:Changed(B)
check(Base:Protection(A) == nil, "base should be open now: " .. tostring(Base:Protection(A)))

-- e) a real steal: Bob runs Alice's pet home
local victimName = victim.Name
local bobPetsBefore = #dataB.Pets
Base:TrySteal(B, A, victim.Id)
check(S.ShardService:IsCarrying(B), "steal did not start carrying")
check(victim.Away == true, "stolen pet not marked away")
check(Base:Protection(A) == "robbing", "a base being robbed should block other thieves")
rootB.CFrame = Base:HomeCFrame(B) * CFrame.new(0, 0, 6)
task.wait(0.6)
check(not S.ShardService:IsCarrying(B), "stolen pet not delivered")
check(#dataB.Pets == bobPetsBefore + 1, "Bob did not get the pet")
local stolen = nil
for _, pet in dataB.Pets do
	if pet.Name == victimName then
		stolen = pet
	end
end
check(stolen ~= nil, "Bob got the wrong pet")
local aliceStillHas = false
for _, pet in dataA.Pets do
	if pet.Id == victim.Id then
		aliceStillHas = true
	end
end
check(not aliceStillHas, "Alice still owns the stolen pet (duplicate!)")
check(Base:Protection(A) == "shield", "theft shield not active after a theft")
check(Base:HasRevenge(A, B), "victim did not get revenge")
-- a freshly stolen pet can't hide in the thief's vault (so revenge can win it back)
check(stolen ~= nil and type(stolen.HotUntil) == "number", "stolen pet not marked hot")
local _, bobDisplay = Util.ArrangePets(Config, dataB)
check(stolen ~= nil and table.find(bobDisplay, stolen) ~= nil, "a hot pet went into the vault")

-- f) revenge: even a locked base can't stop it
if stolen then
	Net:CallForTest("PetShow", B, stolen.Id, true) -- Bob shows it off (otherwise it hides in his vault)
end
check(stolen ~= nil and stolen.Show == true, "PetShow did not mark the pet")
plotB.LockReadyAt = 0
Base:Lock(B)
check(Base:Protection(B) == "locked", "Bob's base should be locked")
rootA.CFrame = CFrame.new(0, 3, -60)
Base:TrySteal(A, B, stolen and stolen.Id or -1)
check(S.ShardService:IsCarrying(A), "revenge did not get through the lock")
rootA.CFrame = Base:HomeCFrame(A) * CFrame.new(0, 0, 6)
task.wait(0.6)
check(not S.ShardService:IsCarrying(A), "revenge pet not delivered")
local back = false
for _, pet in dataA.Pets do
	if pet.Name == victimName then
		back = true
	end
end
check(back, "Alice did not get a pet back with revenge")
check(not Base:HasRevenge(A, B), "revenge should be used up")
unprotect(plotA)
unprotect(plotB)

-- g) bounty: Bob robs two different players -> Alice bonks him and wins it
Base:StealDelivered(A, B, {}, { Name = "Owl" })
Base:StealDelivered(Cp, B, {}, { Name = "Owl" })
local bounty = Base:Bounty(B)
check(bounty > 0 and B:GetAttribute("Bounty") == bounty, "bounty not set: " .. tostring(bounty))
local coinsBeforeBounty = dataA.Coins
Base:ThiefCaught(A, B)
check(dataA.Coins == coinsBeforeBounty + bounty, "bounty not paid")
check(Base:Bounty(B) == 0, "bounty not cleared")
check((dataA.Stats.ThievesCaught or 0) >= 1, "catch not counted")
results.bounty = bounty
for _, plot in { plotA, plotB, Base:PlotOf(Cp) } do
	unprotect(plot)
end

-- 7) a star egg carried home hatches into a pet
local alicePets = #dataA.Pets
S.ShardService:StartCarry(A, { Kind = "Egg", Rarity = "Epic", Egg = "Meadow" }, nil)
check(S.ShardService:IsCarrying(A), "star egg carry failed")
rootA.CFrame = Base:HomeCFrame(A) * CFrame.new(0, 0, 6)
task.wait(0.6)
check(not S.ShardService:IsCarrying(A), "star egg not delivered")
check(#dataA.Pets == alicePets + 1, "star egg did not hatch a pet")

-- 8) trade: Alice gives one pet (numbered), Bob gives one pet
S.PetService:GrantPet(B, "Puppy", nil) -- (Bob lost his pet to Alice's revenge)
S.TradeService:BeginForTest(A, B)
local giveA = dataA.Pets[1]
local giveB = dataB.Pets[1]
giveA.Serial = 77
Net:CallForTest("TradeSetOffer", A, { giveA.Id })
Net:CallForTest("TradeSetOffer", B, { giveB.Id })
Net:CallForTest("TradeReady", A, true)
Net:CallForTest("TradeReady", B, true)
task.wait(S.TradeService.Settings.Countdown + 0.5)
local function owns(data, name, variant, serial)
	for _, pet in data.Pets do
		if pet.Name == name and pet.Variant == variant and (serial == nil or pet.Serial == serial) then
			return true
		end
	end
	return false
end
check(owns(dataA, giveB.Name, giveB.Variant), "trade: Alice did not receive Bob's pet")
check(owns(dataB, giveA.Name, giveA.Variant, 77), "trade: Bob did not receive Alice's pet (with its #77)")
check(not S.TradeService:IsTrading(A) and not S.TradeService:IsTrading(B), "trade session not closed")

-- 9) sold out: buy the whole Meadow stock, the next one must be refused
local stockLeft = S.PetService:StockLeft(dataB, "Meadow")
dataB.Coins = 1e9
for _ = 1, stockLeft do
	Net:CallForTest("Hatch", B, "Meadow", 1)
end
local soldOut = Net:CallForTest("Hatch", B, "Meadow", 1)
check(type(soldOut) == "table" and soldOut.Error ~= nil, "sold-out egg was still sold")
results.soldOutMessage = soldOut and soldOut.Error

-- 10) exclusive (Robux) pets stand on display but can never be stolen
unprotect(plotA)
S.PetService:GrantPet(A, "Golden Pup", nil)
local golden = nil
for _, pet in dataA.Pets do
	if pet.Name == "Golden Pup" then
		golden = pet
	end
end
local onDisplay = false
for _, pet in Base.DisplayedPets(dataA) do
	onDisplay = onDisplay or pet == golden
end
check(onDisplay, "exclusive pet should be on display")
check(golden and not tryTake(B, A, golden.Id), "stole an exclusive pet")

-- 11) huge pets: bigger, counted, numbered (the number needs DataStores)
S.PetService:GrantPet(A, "Bunny", "Huge")
local huge = nil
for _, pet in dataA.Pets do
	if pet.Variant == "Huge" then
		huge = pet
	end
end
check(huge ~= nil, "huge pet not granted")
for _ = 1, 20 do
	if huge and huge.Serial then
		break
	end
	task.wait(0.25)
end
results.hugeSerial = huge and huge.Serial
local hugeModel = require(Shared.PetModel).Build("Bunny", "Huge")
local plainModel = require(Shared.PetModel).Build("Bunny", nil)
local _, hugeSize = hugeModel:GetBoundingBox()
local _, plainSize = plainModel:GetBoundingBox()
check(hugeSize.Y > plainSize.Y * 1.6, "huge pet model is not bigger")

-- 12) house name (filtered by Roblox; stand-ins may not be filterable)
local nameOk, nameMessage = Base:SetName(A, "Sunny Garden")
results.houseName = if nameOk then plotA.Model:GetAttribute("HouseName") else tostring(nameMessage)
check(Base:SetName(A, string.rep("x", 40)) == false, "an overlong house name was accepted")
local started = os.clock()
check(Base:SetName(A, "a" .. string.rep(" ", 200000) .. "b") == false, "a huge house name was accepted")
check(os.clock() - started < 0.2, "a huge house name took too long (server stall)")

-- 13) skins: gems skin, VIP-only skin, back to the level style
local gemsBefore = dataA.Gems
check(Base:SetSkin(A, "Sakura") == true, "gem skin purchase failed")
check(dataA.Gems == gemsBefore - 600 and dataA.Base.Skins.Sakura == true and dataA.Base.Skin == "Sakura", "gem skin not charged/owned")
check(Base:SetSkin(A, "Royal") == false, "VIP skin used without VIP")
check(Base:SetSkin(A, "Galaxy") == false, "galaxy skin used below level 5")
check(Base:SetSkin(A, "Auto") == true and dataA.Base.Skin == "Auto", "back to level style failed")
check(Base:SetSkin(A, "Sakura") == true and dataA.Gems == gemsBefore - 600, "owned skin charged twice")

-- 14) decoration sets: complete the garden set -> bonus income
local rateBefore = Base:IncomeRate(A, dataA)
for _, spot in { { "Flowers", -14, -16 }, { "Bush", -6, -16 }, { "Pond", 6, -16 } } do
	local placedOk, why = Net:CallForTest("BasePlace", A, spot[1], spot[2], spot[3], 0)
	check(placedOk == true, "set item " .. spot[1] .. " not placed: " .. tostring(why))
end
local bonus = Util.SetBonus(Config, dataA.Base.Items)
check(math.abs(bonus - 0.05) < 1e-9, "garden set not complete: " .. bonus)
check(Base:IncomeRate(A, dataA) > rateBefore * 1.04, "set bonus did not raise income")

-- 15) titles: unlocked ones can be worn, locked ones can't
dataA.Level = 12
Net:CallForTest("SetTitle", A, "Miner")
check(dataA.Title == "Miner", "could not wear an unlocked title")
Net:CallForTest("SetTitle", A, "Palace")
check(dataA.Title == "Miner", "wore a locked title")
check(Util.CurrentTitle(Config, dataA, function()
	return false
end).Id == "Miner", "current title wrong")

-- 16) tidy up: every pedestal lines up in rows (vaults at the back)
check(Base:ArrangePedestals(A) == true, "auto-arrange failed")
local rows, vaultZ, displayZ = {}, -math.huge, math.huge
for _, item in dataA.Base.Items do
	local def = Config.Decor[item.Id]
	if def and (def.Function == "Pedestal" or def.Function == "Vault") then
		rows[item.Z] = true
		check(item.R == 0, "arranged pedestal is rotated")
		if def.Function == "Vault" then
			vaultZ = math.max(vaultZ, item.Z)
		else
			displayZ = math.min(displayZ, item.Z)
		end
	end
end
local rowCount = 0
for _ in rows do
	rowCount += 1
end
check(rowCount <= 3, "pedestals are not in neat rows: " .. rowCount)
check(vaultZ >= displayZ, "vaults should stand at the back")

-- 17) your house: roof colour, a real building, a prank pet
check(Base:SetRoof(A, 2) == true and dataA.Base.Roof == 2, "roof colour not saved")
local roof = plotA.Shell:FindFirstChild("Roof")
check(plotA.Shell:FindFirstChild("House") ~= nil and roof and roof.Color == Config.Paint[2], "house / roof missing")
check(Base:SetRoof(A, 0 / 0) ~= true, "NaN roof colour accepted")
local decoyOk, decoyWhy = Net:CallForTest("BasePlace", A, "Decoy", -14, -20, 0)
check(decoyOk == true, "prank pet not placed: " .. tostring(decoyWhy))
local decoyItem = dataA.Base.Items[#dataA.Base.Items]
check(plotA.Displays:FindFirstChild("Decoy_" .. decoyItem.Uid) ~= nil, "prank pet model missing")
Base:SpringDecoy(A, B, plotA.ItemModels[decoyItem.Uid])
check((dataA.Stats.Pranks or 0) == 1, "prank not counted")
Base:SpringDecoy(A, B, plotA.ItemModels[decoyItem.Uid])
check((dataA.Stats.Pranks or 0) == 1, "prank pet fired twice in a row")

-- 18) pets in storage wander in the yard (published for clients)
local okYard, yard = pcall(HttpService.JSONDecode, HttpService, plotA.Model:GetAttribute("Yard") or "")
check(okYard and type(yard) == "table" and #yard >= 1, "no yard pets published")

-- 19) lucky blocks: spawn, open 30 (every outcome must work)
local block = S.LuckyService:Spawn(nil)
check(block ~= nil and block.Parent ~= nil, "lucky block did not spawn")
local kinds = {}
for _ = 1, 30 do
	local okOpen, kind = pcall(S.LuckyService.Open, S.LuckyService, A, Vector3.new(0, 0, 0))
	check(okOpen, "lucky block failed: " .. tostring(kind))
	if okOpen and kind then
		kinds[kind] = true
	end
	if S.ShardService:IsCarrying(A) then
		S.ShardService:Drop(A)
	end
end
check((dataA.Stats.LuckyBlocks or 0) >= 30, "lucky blocks not counted")
results.luckyKinds = kinds

-- 20) events: thief night bonus, party (2x luck + rain)
S.EventService:Trigger("ThiefNight")
check(S.EventService:Get("StealBonus", 0) > 0, "thief night has no steal bonus")
S.EventService:StartParty(1)
check(S.EventService:PartyActive() and (workspace:GetAttribute("PartyEnd") or 0) > os.time(), "party did not start")
check(S.EventService:RaidActive(), "the party cancelled a running Thief Night")

-- 21) the most liked house wears the crown
dataA.Base.Likes = 50
task.wait(5.5)
check(plotA.Model:GetAttribute("BestHouse") == true, "best house has no crown")
check(plotB.Model:GetAttribute("BestHouse") ~= true, "two crowns")

-- 22) titanic pets are huge-er
local PetModelModule = require(Shared.PetModel)
local _, titanicSize = PetModelModule.Build("Bunny", "Titanic"):GetBoundingBox()
check(titanicSize.Y > hugeSize.Y * 1.5, "titanic pet is not bigger than a huge one")

-- 23) old saves: items where the house now stands move back onto the land
local D = fakePlayer(1004, "Dave")
local old = Util.DeepCopy(Data.Template)
old.Tutorial.Done = true
old.Base.Seeded = true
old.Base.LayoutV = 2
old.Base.Level = 4
old.Base.NextUid = 4
old.Base.Items = {
	{ Uid = 1, Id = "Pedestal", X = 0, Z = 2, R = 0, Paid = 0, Cur = "Coins" },
	{ Uid = 2, Id = "Pedestal", X = 0, Z = 30, R = 0, Paid = 0, Cur = "Coins" },
	{ Uid = 3, Id = "Tree", X = 10, Z = 30, R = 0, Paid = 120, Cur = "Coins" },
}
for _, err in Data:InjectForTest(D, old) do
	fail("OnLoaded for Dave: " .. err)
end
local dataD = Data:Get(D)
local daveBounds = require(Shared.DecorModel).Bounds(Config, Util.HouseLevel(Config, dataD))
local allInside = #dataD.Base.Items == 3
for _, item in dataD.Base.Items do
	if item.Z + 2 > daveBounds.MaxZ + 0.01 then
		allInside = false
	end
end
check(allInside and dataD.Base.LayoutV == 3, "old items behind the house were not moved onto the land")

-- 24) quick hatch at the egg stand (no menu) hatches and charges like the shop
dataA.Shop.Bought = {}
local before = #dataA.Pets
local coinsQuick = dataA.Coins
S.PetService:QuickHatch(A, "Meadow")
check(#dataA.Pets == before + 1 or dataA.Coins > coinsQuick - Config.Eggs.Meadow.Price, "quick hatch did nothing")
check(dataA.Coins <= coinsQuick - Config.Eggs.Meadow.Price + 1e6, "quick hatch did not charge")

-- 25) ☄️ METEOR RUSH: sites, warning marker, GO, smash, egg burst, coin chunks, index
local Meteor = S.MeteorService
for _, siteType in { "Hub", "Avenue", "Zone" } do
	local site = Meteor:PickSite(siteType)
	check(site.Type == siteType and typeof(site.Position) == "Vector3", "bad meteor site for " .. siteType)
	if siteType == "Avenue" then
		check(Util.InBases(Config, site.Position + Vector3.new(0, 3, 0)), "avenue meteor outside the base district")
	elseif siteType == "Zone" then
		check(Util.ZoneAt(Config, site.Position + Vector3.new(0, 3, 0)) == site.SiteZone, "zone meteor outside its zone")
	else
		check(Util.ZoneAt(Config, site.Position + Vector3.new(0, 3, 0)) == 0, "hub meteor inside a mine")
	end
end
for _, player in { A, B } do
	if S.ShardService:IsCarrying(player) then
		S.ShardService:Drop(player)
	end
end
local site = Meteor:LaunchForTest("Avenue")
local drops = workspace.Map.Drops
check(Meteor:StateForTest() == "Warning" and drops:FindFirstChild("MeteorMarker") ~= nil, "no landing marker during the warning")
check(workspace:GetAttribute("MeteorSite") ~= "" and workspace:GetAttribute("MeteorKind") ~= "", "meteor site / kind not published")
rootA.CFrame = CFrame.new(0, 3, -60)
Net:CallForTest("GoToMeteor", A)
check((rootA.Position - Vector3.new(0, 4, Config.World.Bases.ZStart - 12)).Magnitude < 1, "GO did not take Alice to the avenue")
-- now let it fall
site = Meteor:LaunchForTest("Hub", true)
for _ = 1, 30 do
	if Meteor:StateForTest() == "Active" then
		break
	end
	task.wait(0.25)
end
check(Meteor:StateForTest() == "Active", "meteor did not land: " .. Meteor:StateForTest())
local meteorPart = drops:FindFirstChild("Meteor")
check(meteorPart ~= nil and math.abs(meteorPart.Size.X / 2 - site.Size.Radius) < 0.01, "meteor has the wrong size")
check(Meteor:InRange(site.Position + Vector3.new(site.Size.Radius + 2, 3, 0)), "meteor reach ignores its size")
local shardsBefore = #workspace.Map.Shards:GetChildren()
local joinsBefore = dataA.Stats.MeteorJoins
for _ = 1, 3000 do
	if Meteor:StateForTest() ~= "Active" then
		break
	end
	Meteor:Hit(A, 50, 0.4)
	Meteor:Hit(B, 20, 0.5)
end
check(Meteor:StateForTest() == "Idle", "meteor not smashed: " .. Meteor:StateForTest())
local eggsSpilled = #workspace.Map.Shards:GetChildren() - shardsBefore
check(eggsSpilled >= Config.Meteor.Spill.Base + 2, "too few star eggs spilled: " .. eggsSpilled)
check(dataA.Stats.MeteorJoins == joinsBefore + 1, "meteor participation not counted")
check((dataA.MeteorIndex[tostring(site.Kind)] or 0) >= 1, "meteor index not filled")
local chunkCount = 0
local someChunk = nil
for part in Meteor:ChunksForTest() do
	chunkCount += 1
	someChunk = part
end
check(chunkCount >= Config.Meteor.Chunks.Count, "coin chunks missing: " .. chunkCount)
check(someChunk == nil or Meteor:ClaimChunk(B, someChunk) == nil, "a coin chunk paid a player far away")
if someChunk then
	rootB.CFrame = CFrame.new(someChunk.Position)
end
local coinsBeforeChunk = dataB.Coins
local chunkPaid = someChunk and Meteor:ClaimChunk(B, someChunk)
check(chunkPaid ~= nil and dataB.Coins == coinsBeforeChunk + chunkPaid and chunkPaid >= Config.Meteor.Chunks.Min, "coin chunk did not pay")
check(someChunk == nil or Meteor:ClaimChunk(A, someChunk) == nil, "a coin chunk paid twice")
results.meteor = { Site = site.SiteName, Kind = site.Kind, Size = site.Size.Id, Eggs = eggsSpilled, Chunk = chunkPaid }

-- 26) a new player's first minute: own meteor -> egg pops out -> grab -> home
local E, rootE = fakePlayer(1005, "Eve")
local fresh = Util.DeepCopy(Data.Template)
fresh.Flags.HowToSeen = true
for _, err in Data:InjectForTest(E, fresh) do
	fail("OnLoaded for Eve: " .. err)
end
local dataE = Data:Get(E)
check(dataE.Tutorial.Step == 1 and dataE.Tutorial.Version == Config.Tutorial.Version, "new tutorial not started")
Meteor:TutorialMeteor(E)
task.wait(1.8)
local tutorialPart = drops:FindFirstChild("TutorialMeteor_" .. E.UserId)
check(tutorialPart ~= nil, "no tutorial meteor for the new player")
if tutorialPart then
	rootE.CFrame = CFrame.new(tutorialPart.Position.X + 5, 3, tutorialPart.Position.Z)
	local eggsBefore = #workspace.Map.Shards:GetChildren()
	for _ = 1, Config.Meteor.Tutorial.Hits do
		Meteor:TutorialHit(E, rootE.Position)
	end
	check(tutorialPart.Parent == nil, "tutorial meteor not cracked")
	check(dataE.Tutorial.Step == 2, "tutorial did not move to Grab: " .. dataE.Tutorial.Step)
	check(#workspace.Map.Shards:GetChildren() == eggsBefore + 1, "no star egg popped out of the tutorial meteor")
end
S.ProgressionService:TutorialEvent(E, "Grab", 1)
check(dataE.Tutorial.Step == 3, "tutorial did not move to Shard")
S.ShardService:StartCarry(E, { Kind = "Egg", Rarity = "Rare", Egg = "Meadow" }, nil)
rootE.CFrame = Base:HomeCFrame(E) * CFrame.new(0, 0, 6)
task.wait(0.6)
check(dataE.Tutorial.Step == 4 and #dataE.Pets >= 1, "carrying the egg home did not hatch it / finish the step")
-- bought the pickaxe early (during "mine"): the pickaxe step completes by itself
dataE.PickaxeTier = 2
for _ = 1, Config.Tutorial.Steps[4].Target do
	S.ProgressionService:TutorialEvent(E, "Mine", 1)
end
check(dataE.Tutorial.Done == true, "tutorial stuck at the pickaxe step after an early pickaxe: step " .. dataE.Tutorial.Step)

-- 27) an old save mid-tutorial restarts with the meteor steps
local F = fakePlayer(1006, "Finn")
local oldTutorial = Util.DeepCopy(Data.Template)
oldTutorial.Tutorial = { Step = 3, Progress = 2, Done = false }
for _, err in Data:InjectForTest(F, oldTutorial) do
	fail("OnLoaded for Finn: " .. err)
end
local dataF = Data:Get(F)
check(dataF.Tutorial.Step == 1 and dataF.Tutorial.Version == Config.Tutorial.Version, "old tutorial save not restarted")

-- 28) 🐾 following pets help mine ores next to you (only while you play)
local oreNear = nil
for _, ore in workspace.Map.Ores:GetChildren() do
	if ore:GetAttribute("Zone") == 1 then
		oreNear = ore
		break
	end
end
check(oreNear ~= nil and #dataA.Equipped >= 1, "pet help test setup")
if oreNear then
	if S.ShardService:IsCarrying(A) then
		S.ShardService:Drop(A)
	end
	rootA.CFrame = CFrame.new(oreNear.Position + Vector3.new(0, 0, 5))
	local hpBefore = oreNear:GetAttribute("HP")
	S.MiningService:PetHelpForTest(A, 30) -- swung 30s ago: pets don't help AFK players
	check(oreNear.Parent ~= nil and oreNear:GetAttribute("HP") == hpBefore, "pets helped an AFK player")
	S.MiningService:PetHelpForTest(A, 0)
	check(oreNear.Parent == nil or oreNear:GetAttribute("HP") < hpBefore, "following pets did not hit the ore next to Alice")
end

-- 29) rival players: join small servers, look like players, smash meteors,
-- grab eggs and run home, get bonked, bonk players carrying eggs
local Rival = S.RivalService
Rival:ForceForTest(2)
for _ = 1, 20 do
	if #Rival:RecordsForTest() == 2 then
		break
	end
	task.wait(0.25)
end
local bots = Rival:RecordsForTest()
check(#bots == 2, "rivals did not show up: " .. #bots)
if #bots == 2 then
	local look = bots[1].Model
	check(
		look:FindFirstChildOfClass("Humanoid") ~= nil and look:FindFirstChild("Pickaxe") ~= nil,
		"a rival should be a humanoid with a pickaxe"
	)
	check(look:FindFirstChildOfClass("Shirt") ~= nil and look:FindFirstChildOfClass("Pants") ~= nil, "a rival should wear clothes")
	local head = look:FindFirstChild("Head")
	check(head and head:FindFirstChild("Overhead") ~= nil, "a rival needs a name tag like players")
	local okPets, petList = pcall(HttpService.JSONDecode, HttpService, look:GetAttribute("Pets") or "")
	check(okPets and type(petList) == "table" and #petList >= 2, "rivals should have pets following them")
	check(bots[1].Name ~= bots[2].Name, "two rivals with the same name")

	local rush = Meteor:LaunchForTest("Hub", true)
	for _ = 1, 30 do
		if Meteor:StateForTest() == "Active" then
			break
		end
		task.wait(0.25)
	end
	for i, bot in bots do
		Rival:PlaceForTest(bot, rush.Position + Vector3.new(rush.Size.Radius + 2, 0, (i - 1.5) * 4))
	end
	task.wait(3)
	check(Meteor:ScoreOf(bots[1].Entity) > 0, "rivals did not smash the meteor")
	for _ = 1, 3000 do
		if Meteor:StateForTest() ~= "Active" then
			break
		end
		Meteor:Hit(A, 50, 0.4)
	end
	check(Meteor:StateForTest() == "Idle", "rush meteor not smashed")
	-- eggs nobody picked up: a rival grabs one
	task.wait(Config.Rivals.GrabDelay + 0.5)
	local carrier = nil
	for attempt = 1, 3 do
		-- (rivals never take eggs in the base district; characters don't walk in
		-- cloud tests, so put the rival right on a public egg)
		local bot = bots[attempt % 2 + 1]
		local spot = nil
		for _, entry in S.ShardService:RivalTargets(bot.Entity.UserId, Config.Rivals.GrabDelay) do
			if not Util.InBases(Config, entry.Position + Vector3.new(0, 3, 0)) then
				spot = entry.Position
			end
		end
		if spot then
			Rival:PlaceForTest(bot, spot)
		end
		for _ = 1, 8 do
			for _, bot in bots do
				if bot.Carry then
					carrier = bot
				end
			end
			if carrier then
				break
			end
			task.wait(0.25)
		end
		if carrier then
			break
		end
	end
	check(carrier ~= nil, "no rival grabbed a star egg")
	if carrier then
		check(carrier.Model:GetAttribute("Carrying") == true, "a carrying rival should show it")
		local coinsBeforeBonk = dataA.Coins
		rootA.CFrame = CFrame.new(carrier.Root.Position + Vector3.new(3, 0, 0))
		check(Rival:Bonk(A, carrier.Model) == true, "bonking a rival failed")
		check(carrier.Carry == nil, "the bonked rival kept the egg")
		check(dataA.Coins > coinsBeforeBonk, "no coins for bonking a rival")
		check(Rival:Bonk(A, carrier.Model) == false, "a stunned rival could be bonked again")
		local reGrab = false
		for _, entry in S.ShardService:RivalTargets(carrier.Entity.UserId, 0) do
			local here = carrier.Root.Position
			if (Vector3.new(entry.Position.X, 0, entry.Position.Z) - Vector3.new(here.X, 0, here.Z)).Magnitude < 2 then
				reGrab = true
			end
		end
		check(not reGrab, "rivals could grab the bonked egg right back (coin farming)")
	end
	-- a rival bonks a player carrying an egg (not near the spawn / homes)
	if S.ShardService:IsCarrying(A) then
		S.ShardService:Drop(A)
	end
	rootA.CFrame = CFrame.new(30, 3, 30)
	S.ShardService:StartCarry(A, { Kind = "Egg", Rarity = "Rare", Egg = "Meadow" }, nil)
	Rival:PlaceForTest(bots[2], Vector3.new(33, 0, 30))
	S.MiningService:NpcBonk(bots[2].Root, bots[2].Name, A)
	check(not S.ShardService:IsCarrying(A), "a rival could not bonk a player carrying an egg")
	results.rivals = { Names = bots[1].Name .. "," .. bots[2].Name, Carrier = carrier ~= nil }
end
Rival:ForceForTest(0)
task.wait(1)
check(#Rival:RecordsForTest() == 0, "rivals did not leave")

-- 30) 🌱 growth: feed, level up, ⭐ evolve with 2 copies, growth survives a steal
for _ = 1, 3 do
	S.PetService:GrantPet(A, "Chick", nil)
end
local chicks = {}
for _, pet in dataA.Pets do
	if pet.Name == "Chick" and not pet.Serial then
		table.insert(chicks, pet)
	end
end
check(#chicks >= 3, "growth test setup")
local main = chicks[1]
dataA.Stardust = 1e7
local fed = S.PetService.FeedForTest(A, main.Id)
check(type(fed) == "table" and fed.Ok, "feeding failed: " .. HttpService:JSONEncode(fed or {}))
check(Util.PetLevel(main) > 1 or (main.XP or 0) > 0, "feeding gave no xp")
S.PetService:AddXP(A, { main }, 1e7)
check(Util.PetLevel(main) == Config.Growth.MaxLevel, "pet did not reach the max level")
local expected = Util.PetIncome(Config, "Chick", main.Variant) * (1 + Config.Growth.LevelBonus * (Config.Growth.MaxLevel - 1))
check(math.abs(Util.PetIncomeOf(Config, main) - expected) < 1e-6, "level bonus not applied to income")
local petsBeforeEvolve = #dataA.Pets
local evolved = S.PetService.EvolveForTest(A, main.Id)
check(type(evolved) == "table" and evolved.Ok and Util.PetStars(main) == 1, "evolve failed: " .. HttpService:JSONEncode(evolved or {}))
check(#dataA.Pets == petsBeforeEvolve - Config.Growth.Evolve.Copies, "evolve did not use the copies")
check(Util.PetLevel(main) == 1, "an evolved pet should start at level 1 again")
local again = S.PetService.EvolveForTest(A, main.Id)
check(type(again) == "table" and again.Error ~= nil, "evolved again without growing / copies")
local taken = S.PetService:TakePet(A, main.Id)
local given = taken and S.PetService:GivePet(B, taken.Name, taken.Variant, taken.Serial, taken)
check(given ~= nil and Util.PetStars(given) == 1, "a stolen / traded pet lost its stars")
pcall(S.PetService.HomeXP, S.PetService, A)

-- 31) 📖 index milestones + ☄️ meteor pets
local found = Util.IndexCount(dataA)
local gemsBeforeIndex = dataA.Gems
local claimedIndex = S.PetService.ClaimIndexForTest(A, 1)
if found >= Config.Index.Milestones[1].Count then
	check(
		type(claimedIndex) == "table" and claimedIndex.Ok and dataA.Gems == gemsBeforeIndex + Config.Index.Milestones[1].Gems,
		"index milestone not paid"
	)
	local twice = S.PetService.ClaimIndexForTest(A, 1)
	check(type(twice) == "table" and twice.Error ~= nil, "index milestone paid twice")
else
	check(type(claimedIndex) == "table" and claimedIndex.Error ~= nil, "index milestone paid too early")
end
local meteorPet = Config.Meteor.MeteorPets[1]
for _ = 1, 30 do
	if dataA.PetIndex[meteorPet] then
		break
	end
	S.PetService:HatchStarEgg(A, "Meadow", 1, { Kind = 1, Golden = true, Rarity = "Secret" })
end
check(dataA.PetIndex[meteorPet] == true, "no meteor pet from meteor star eggs")
results.growth = { Stars = Util.PetStars(main), Index = Util.IndexCount(dataA), IndexBonus = Util.IndexBonus(Config, dataA) }

results.alicePets = #dataA.Pets
results.bobPets = #dataB.Pets
results.carolPets = dataC and #dataC.Pets
if #results.errors > 0 then
	error("GAMEPLAY TEST FAILED: " .. HttpService:JSONEncode(results))
end
return HttpService:JSONEncode(results)
