-- Cloud test: boot the real server services (like Main.server.luau) on a
-- Roblox server, then check the world, decorations, plots and guardians.
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local results = { errors = {} }
local function fail(message)
	table.insert(results.errors, message)
end

-- boot (same order as Main.server.luau)
local folder = ServerScriptService.Server.Services
local ORDER = {
	"DataService", "StatsService", "MonetizationService", "BoostService", "EventService", "WorldService",
	"CharacterService", "EconomyService", "PetService", "MiningService", "BaseService", "ShardService",
	"MeteorService", "ProgressionService", "LeaderboardService", "DevService",
}
local Services = {}
for _, name in ORDER do
	local ok, mod = pcall(require, folder[name])
	if ok then
		Services[name] = mod
	else
		fail("require " .. name .. ": " .. tostring(mod))
	end
end
for _, name in ORDER do
	local service = Services[name]
	if service and service.Init then
		local ok, err = pcall(service.Init, service, Services)
		if not ok then
			fail("init " .. name .. ": " .. tostring(err))
		end
	end
end
for _, name in ORDER do
	local service = Services[name]
	if service and name ~= "DataService" and service.Start then
		local ok, err = pcall(service.Start, service)
		if not ok then
			fail("start " .. name .. ": " .. tostring(err))
		end
	end
end
pcall(Services.DataService.Start, Services.DataService)
task.wait(2)

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local DecorModel = require(Shared.DecorModel)

-- world
local map = workspace:FindFirstChild("Map")
results.map = map ~= nil
if map then
	results.ores = #map.Ores:GetChildren()
	results.plots = #map.Bases:GetChildren()
	local parts = 0
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	results.mapParts = parts
end

-- every decoration builds into real parts
local decorParts = {}
for id in Config.Decor do
	local ok, model = pcall(DecorModel.Build, Config, id)
	if not ok then
		fail("decor " .. id .. ": " .. tostring(model))
	else
		local n = 0
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				n += 1
			end
		end
		decorParts[id] = n
		if n < 2 then
			fail("decor " .. id .. " has no visible parts")
		end
		model:Destroy()
	end
end
results.decorBuilt = 0
for _ in decorParts do
	results.decorBuilt += 1
end

-- plots: inside the district, not overlapping each other or a street
local layout = Services.BaseService.PlotLayout()
local half = Config.Base.PlotSize / 2
local bases = Config.World.Bases
for i, a in layout do
	local c = a.Center
	if math.abs(c.X) + half > bases.HalfX or c.Z + half > bases.ZStart or c.Z - half < bases.ZEnd then
		fail("plot " .. i .. " outside district")
	end
	for _, x in Config.Base.Streets do
		if math.abs(c.X - x) < half + 10 then
			fail("plot " .. i .. " overlaps street at x=" .. x)
		end
	end
	for j, b in layout do
		if j > i and math.abs(a.Center.X - b.Center.X) < half * 2 and math.abs(a.Center.Z - b.Center.Z) < half * 2 then
			fail(string.format("plots %d and %d overlap", i, j))
		end
	end
end

-- shards + guardian: spawn an Epic star with a guardian in the hub
local shards = Services.ShardService
local spot = Vector3.new(-30, 0, 10)
local ok, err = pcall(function()
	shards:SpawnGround("Epic", spot, nil, { Beacon = true, WithGuardian = true })
end)
if not ok then
	fail("spawn star: " .. tostring(err))
end
task.wait(0.5)
local guardian = map and map.Shards:FindFirstChild("StarGuardian")
results.guardianSpawned = guardian ~= nil
if guardian then
	-- push it 30 studs away from its star: it must walk back on its own
	local record = shards:GuardiansForTest()[guardian]
	record.Position = record.Home + Vector3.new(36, 0, 0)
	local startGap = (record.Position - record.Home).Magnitude
	task.wait(1.5)
	local root = guardian:FindFirstChild("HumanoidRootPart")
	local endGap = ((root.Position - record.Home) * Vector3.new(1, 0, 1)).Magnitude
	results.guardianWalked = math.floor((startGap - endGap) * 10) / 10
	results.guardianY = math.floor(root.Position.Y * 10) / 10
	if results.guardianWalked < 15 then
		fail("guardian did not walk home: " .. results.guardianWalked)
	end
	if root.Position.Y < 0.5 or root.Position.Y > 4 then
		fail("guardian height looks wrong: " .. root.Position.Y)
	end
	-- a bonk stuns it: it must stand still
	record.StunnedUntil = os.clock() + 1
	local before = record.Position
	record.Position = record.Home + Vector3.new(30, 0, 0)
	before = record.Position
	task.wait(0.6)
	results.guardianStunMoved = math.floor((record.Position - before).Magnitude * 10) / 10
	if results.guardianStunMoved > 0.1 then
		fail("stunned guardian kept moving")
	end
end

-- a falling star picks a valid spot and lands
local ok2, err2 = pcall(function()
	shards:FallingStar(1)
end)
if not ok2 then
	fail("falling star: " .. tostring(err2))
end
task.wait(2.5)
results.groundShards = 0
for _, child in map.Shards:GetChildren() do
	if child.Name:sub(1, 6) == "Shard_" then
		results.groundShards += 1
	end
end
if #results.errors > 0 then
	-- fail the task so tools/release.sh refuses to go live
	error("BOOT TEST FAILED: " .. HttpService:JSONEncode(results))
end
return HttpService:JSONEncode(results)
