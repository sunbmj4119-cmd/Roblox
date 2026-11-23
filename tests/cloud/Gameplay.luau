-- Cloud gameplay test: boots the real server services on a Roblox server and
-- plays the core loop with two stand-in players (no real clients needed):
-- hatch (cost + stock), pets on pedestals + income, collect, decorate,
-- steal a pet + carry it home, star egg hatches at home, trade, sold out.
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
for _, pair in { { A, 50000 }, { B, 50000 } } do
	local data = Util.DeepCopy(Data.Template)
	data.Coins = pair[2]
	data.Gems = 1000
	data.Tutorial.Done = true
	data.Flags.HowToSeen = true
	local errors = Data:InjectForTest(pair[1], data)
	for _, err in errors do
		fail("OnLoaded for " .. pair[1].Name .. ": " .. err)
	end
end
task.wait(0.5)
local dataA, dataB = Data:Get(A), Data:Get(B)

-- 1) bases assigned, starter layout seeded
check(A:GetAttribute("BaseIndex") ~= nil and B:GetAttribute("BaseIndex") ~= nil, "players got no base")
check(dataA and #dataA.Base.Items >= Config.Base.StartPedestals, "starter layout not seeded")

-- 2) hatch a Meadow egg through the real request handler
local coinsBefore = dataA.Coins
local result = Net:CallForTest("Hatch", A, "Meadow", 1)
check(type(result) == "table" and result.Pets and #result.Pets == 1, "hatch failed: " .. HttpService:JSONEncode(result or {}))
check(dataA.Coins == coinsBefore - Config.Eggs.Meadow.Price, "hatch did not charge the price")
check(#dataA.Pets == 1, "pet not added")
check((dataA.Shop.Bought.Meadow or 0) == 1, "stock purchase not counted")
results.firstPet = dataA.Pets[1] and dataA.Pets[1].Name

-- give A a few more pets so pedestals fill up
for _ = 1, 3 do
	S.PetService:GrantPet(A, "Fox", nil)
end
check(#dataA.Pets == 4, "GrantPet failed")

-- 3) the best pets stand on pedestals and earn
local shown = S.BaseService.DisplayedPets(dataA)
local pedestals = 0
for _, item in dataA.Base.Items do
	if Config.Decor[item.Id] and Config.Decor[item.Id].Function == "Pedestal" then
		pedestals += 1
	end
end
check(#shown == math.min(pedestals, #dataA.Pets), string.format("displayed %d pets for %d pedestals", #shown, pedestals))
local rate = S.BaseService:IncomeRate(A, dataA)
check(rate > 0, "base earns nothing")
results.baseRate = rate
local plotA = S.BaseService:PlotOf(A)
local displays = plotA and plotA.Displays:GetChildren() or {}
check(#displays == #shown, "pedestal pet models missing: " .. #displays)
check(#dataA.Equipped >= 1, "no pet follows the player")

-- 4) collect the bank
dataA.Base.Bank = 1234
local beforeCollect = dataA.Coins
S.BaseService:Collect(A)
check(dataA.Coins == beforeCollect + 1234 and dataA.Base.Bank < 1, "collect failed")

-- 5) decorate: place + remove with refund
local ok, message = Net:CallForTest("BasePlace", A, "Tree", 0, 14, 0)
check(ok == true, "place tree failed: " .. tostring(message))
local placed = dataA.Base.Items[#dataA.Base.Items]
local coinsAfterPlace = dataA.Coins
local ok2 = Net:CallForTest("BaseRemove", A, placed.Uid)
check(ok2 == true and dataA.Coins == coinsAfterPlace + Config.Decor.Tree.Price, "remove/refund failed")
local okBad = Net:CallForTest("BasePlace", A, "Tree", 999, 999, 0)
check(okBad ~= true, "out-of-bounds placement was accepted")

-- 6) Bob steals one of Alice's pets and runs home with it
local victim = shown[1]
local victimName = victim.Name
local bobPetsBefore = #dataB.Pets
S.BaseService:TrySteal(B, A, victim.Id)
check(S.ShardService:IsCarrying(B), "steal did not start carrying")
check(victim.Away == true, "stolen pet not marked away")
check(#S.BaseService.DisplayedPets(dataA) <= #shown, "stolen pet still displayed")
-- walk Bob into his own base: the delivery loop hands the pet over
rootB.CFrame = S.BaseService:HomeCFrame(B) * CFrame.new(0, 0, 6)
task.wait(0.6)
check(not S.ShardService:IsCarrying(B), "stolen pet not delivered")
check(#dataB.Pets == bobPetsBefore + 1, "Bob did not get the pet")
local bobHasIt = false
for _, pet in dataB.Pets do
	if pet.Name == victimName then
		bobHasIt = true
	end
end
check(bobHasIt, "Bob got the wrong pet")
local aliceStillHas = false
for _, pet in dataA.Pets do
	if pet.Id == victim.Id then
		aliceStillHas = true
	end
end
check(not aliceStillHas, "Alice still owns the stolen pet (duplicate!)")

-- 7) a star egg carried home hatches into a pet
local alicePets = #dataA.Pets
S.ShardService:StartCarry(A, { Kind = "Egg", Rarity = "Epic", Egg = "Meadow" }, nil)
check(S.ShardService:IsCarrying(A), "star egg carry failed")
rootA.CFrame = S.BaseService:HomeCFrame(A) * CFrame.new(0, 0, 6)
task.wait(0.6)
check(not S.ShardService:IsCarrying(A), "star egg not delivered")
check(#dataA.Pets == alicePets + 1, "star egg did not hatch a pet")

-- 8) trade: Alice gives one pet, Bob gives one pet
S.TradeService:BeginForTest(A, B)
local giveA = dataA.Pets[1]
local giveB = dataB.Pets[1]
Net:CallForTest("TradeSetOffer", A, { giveA.Id })
Net:CallForTest("TradeSetOffer", B, { giveB.Id })
Net:CallForTest("TradeReady", A, true)
Net:CallForTest("TradeReady", B, true)
task.wait(S.TradeService.Settings.Countdown + 0.5)
local function owns(data, name, variant)
	for _, pet in data.Pets do
		if pet.Name == name and pet.Variant == variant then
			return true
		end
	end
	return false
end
check(owns(dataA, giveB.Name, giveB.Variant), "trade: Alice did not receive Bob's pet")
check(owns(dataB, giveA.Name, giveA.Variant), "trade: Bob did not receive Alice's pet")
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

results.alicePets = #dataA.Pets
results.bobPets = #dataB.Pets
if #results.errors > 0 then
	error("GAMEPLAY TEST FAILED: " .. HttpService:JSONEncode(results))
end
return HttpService:JSONEncode(results)
