-- Cloud gameplay test: boots the real server services on a Roblox server and
-- plays the core loop with stand-in players (no real clients needed):
-- hatch (cost + stock), vault / display pedestals + income, collect,
-- decorate + house level + paint + sets, every theft protection (lock,
-- newbie shield, vault, fair-size rule, theft shield), a real steal, revenge,
-- bounty, star egg, trade (serial kept), exclusive pets, huge pets, house
-- name / skins and titles.
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

results.alicePets = #dataA.Pets
results.bobPets = #dataB.Pets
results.carolPets = dataC and #dataC.Pets
if #results.errors > 0 then
	error("GAMEPLAY TEST FAILED: " .. HttpService:JSONEncode(results))
end
return HttpService:JSONEncode(results)
