--[[
	DataService: loads/saves player data with a lightweight session lock so a
	player who server-hops quickly can't duplicate purchases or items.

	* UpdateAsync + _lock { JobId, Time } on load, refreshed on every save.
	* Saves are serialized per player, autosaved, and flushed on BindToClose.
	* In Studio without "Enable Studio Access to API Services" the game still
	  runs with temporary data (never saved) so you can test immediately.
]]
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Net = require(script.Parent.Net)

local DataService = {}

local LOCK_EXPIRE = 300
local AUTOSAVE_SECONDS = 120
local SYNC_INTERVAL = 0.2
local MAX_RECEIPTS = 100

local TEMPLATE = {
	Version = 1,
	Coins = 0,
	Gems = 0,
	Stardust = 0,
	Backpack = 0,
	PickaxeTier = 1,
	BackpackTier = 1,
	ZoneLevel = 1,
	Rebirths = 0,
	Pets = {}, -- { { Id = 1, Name = "Bunny" }, ... }
	Equipped = {}, -- { petId, ... }
	NextPetUid = 1,
	PetIndex = {}, -- [petName] = true
	Boosts = { Coins2x = 0, Luck2x = 0, Power2x = 0 }, -- remaining seconds
	Stats = {
		BlocksMined = 0,
		LifetimeCoins = 0,
		EggsHatched = 0,
		MeteorWins = 0,
		MeteorJoins = 0,
		Bonks = 0,
		PlaySeconds = 0,
		Purchases = 0,
	},
	Daily = { Day = 0, Quests = {}, Streak = 0, LastClaimDay = 0, VipChestDay = 0, ClubDay = 0 },
	Season = { Id = 0, XP = 0, Premium = false, ClaimedFree = {}, ClaimedPremium = {} },
	Weekly = { Week = 0, Points = 0 },
	Flags = { StarterPack = false, GroupReward = false },
	Receipts = {},
	FirstJoin = 0,
	LastAdTime = 0,
}
DataService.Template = TEMPLATE

local profiles = {} -- [player] = { Data, CanSave, Dirty, Saving }
local loadedCallbacks = {}
local leavingCallbacks = {}
local store = nil

do
	local ok, err = pcall(function()
		store = DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if not ok then
		warn("[DataService] DataStore unavailable: " .. tostring(err))
	end
end

local function keyFor(userId: number): string
	return "Player_" .. userId
end

local function isAccessError(err): boolean
	local text = tostring(err)
	return string.find(text, "StudioAccessToApisNotAllowed", 1, true) ~= nil
		or string.find(text, "403", 1, true) ~= nil
		or string.find(text, "not allowed", 1, true) ~= nil
end

-- returns data, canSave, fatal
local function loadAsync(player: Player, sessionId: string)
	if not store then
		return nil, false, false
	end
	local key = keyFor(player.UserId)
	for attempt = 1, 8 do
		local locked = false
		local result = nil
		local ok, err = pcall(function()
			store:UpdateAsync(key, function(old)
				local data = if type(old) == "table" then old else {}
				local lock = data._lock
				if
					type(lock) == "table"
					and lock.Session ~= sessionId
					and os.time() - (tonumber(lock.Time) or 0) < LOCK_EXPIRE
					and attempt < 6
				then
					locked = true
					return nil -- cancel, another server still owns this session
				end
				data._lock = { Session = sessionId, JobId = game.JobId, Time = os.time() }
				result = data
				return data
			end)
		end)
		if ok and result then
			return result, true, false
		end
		if not ok then
			warn(string.format("[DataService] load attempt %d for %s failed: %s", attempt, player.Name, tostring(err)))
			if isAccessError(err) then
				return nil, false, false
			end
		end
		if not player.Parent then
			return nil, false, true
		end
		task.wait(if locked then 5 else 1.5 * attempt)
	end
	return nil, false, true
end

-- returns true only when the data was actually written (or saving is disabled)
local function saveAsync(player: Player, release: boolean): boolean
	local profile = profiles[player]
	if not profile or not profile.CanSave or not store then
		return true
	end
	if profile.Released then
		return false -- the leave save already released the session; never re-take the lock
	end
	while profile.Saving do
		task.wait(0.1)
	end
	if profile.Released then
		return false
	end
	if release then
		profile.Released = true
	end
	profile.Saving = true
	local data = profile.Data
	local sessionId = profile.SessionId
	local wrote = false
	local ok, err = pcall(function()
		store:UpdateAsync(keyFor(player.UserId), function(old)
			if type(old) == "table" and type(old._lock) == "table" and old._lock.Session ~= sessionId then
				wrote = false
				return nil -- session was taken over by another server; never overwrite it
			end
			data._lock = if release then nil else { Session = sessionId, JobId = game.JobId, Time = os.time() }
			wrote = true
			return data
		end)
	end)
	profile.Saving = false
	if not ok then
		warn(string.format("[DataService] save for %s failed: %s", player.Name, tostring(err)))
	elseif not wrote then
		warn(string.format("[DataService] save for %s skipped: session owned elsewhere", player.Name))
	end
	return ok and wrote
end

local function setupLeaderstats(player: Player)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Parent = folder
	local coins = Instance.new("StringValue")
	coins.Name = "Coins"
	coins.Parent = folder
	local rank = Instance.new("StringValue")
	rank.Name = "Rank"
	rank.Parent = folder
	folder.Parent = player
end

local function updateLeaderstats(player: Player, data)
	local folder = player:FindFirstChild("leaderstats")
	if not folder then
		return
	end
	local rebirths = folder:FindFirstChild("Rebirths") :: IntValue
	local coins = folder:FindFirstChild("Coins") :: StringValue
	local rank = folder:FindFirstChild("Rank") :: StringValue
	if rebirths then
		rebirths.Value = data.Rebirths
	end
	if coins then
		coins.Value = Util.Format(data.Coins)
	end
	if rank then
		local r = Util.RankFor(Config, data.Weekly.Points)
		rank.Value = r.Name
	end
end

local function snapshot(player: Player, profile)
	local out = {}
	for k, v in profile.Data do
		if k ~= "Receipts" and k ~= "_lock" then
			out[k] = v
		end
	end
	local derived = {}
	if DataService.BuildDerived then
		local ok, result = pcall(DataService.BuildDerived, player)
		if ok then
			derived = result
		else
			warn("[DataService] BuildDerived failed: " .. tostring(result))
		end
	end
	derived.CanSave = profile.CanSave
	return { Data = out, Derived = derived }
end

local function onPlayerAdded(player: Player)
	local sessionId = HttpService:GenerateGUID(false)
	local data, canSave, fatal = loadAsync(player, sessionId)
	if not player.Parent then
		-- left while loading: release the session lock we just took
		if data and canSave and store then
			pcall(function()
				store:UpdateAsync(keyFor(player.UserId), function(old)
					if type(old) == "table" and type(old._lock) == "table" and old._lock.Session == sessionId then
						old._lock = nil
						return old
					end
					return nil
				end)
			end)
		end
		return
	end
	if fatal then
		player:Kick("Your data could not be loaded. Please rejoin in a moment!")
		return
	end
	if not data then
		data = {}
		canSave = false
		task.delay(6, function()
			Net:Notify(player, "⚠ Data is not saving (Studio API access is off).", Color3.fromRGB(255, 170, 60))
		end)
	end
	data._lock = nil
	Util.Reconcile(data, TEMPLATE)
	if data.FirstJoin == 0 then
		data.FirstJoin = os.time()
	end

	profiles[player] = { Data = data, CanSave = canSave, Dirty = true, Saving = false, Released = false, SessionId = sessionId }
	setupLeaderstats(player)
	updateLeaderstats(player, data)
	player:SetAttribute("DataLoaded", true)

	for _, callback in loadedCallbacks do
		task.spawn(callback, player, data)
	end
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	for _, callback in leavingCallbacks do
		local ok, err = pcall(callback, player, profile.Data)
		if not ok then
			warn("[DataService] leaving callback failed: " .. tostring(err))
		end
	end
	saveAsync(player, true)
	profiles[player] = nil
end

-- PUBLIC API ---------------------------------------------------------------

function DataService:Get(player: Player)
	local profile = profiles[player]
	return profile and profile.Data
end

function DataService:WaitFor(player: Player, timeout: number?)
	local deadline = os.clock() + (timeout or 30)
	while player.Parent and not profiles[player] and os.clock() < deadline do
		task.wait(0.1)
	end
	return self:Get(player)
end

function DataService:OnLoaded(callback)
	table.insert(loadedCallbacks, callback)
	for player, profile in profiles do
		task.spawn(callback, player, profile.Data)
	end
end

function DataService:OnLeaving(callback)
	table.insert(leavingCallbacks, callback)
end

function DataService:MarkDirty(player: Player)
	local profile = profiles[player]
	if profile then
		profile.Dirty = true
	end
end

function DataService:Save(player: Player)
	return saveAsync(player, false)
end

function DataService:LoadedPlayers()
	local list = {}
	for player in profiles do
		table.insert(list, player)
	end
	return list
end

function DataService:HasReceipt(player: Player, purchaseId: string): boolean
	local data = self:Get(player)
	if not data then
		return false
	end
	return table.find(data.Receipts, purchaseId) ~= nil
end

function DataService:AddReceipt(player: Player, purchaseId: string)
	local data = self:Get(player)
	if not data then
		return
	end
	table.insert(data.Receipts, purchaseId)
	while #data.Receipts > MAX_RECEIPTS do
		table.remove(data.Receipts, 1)
	end
end

function DataService:Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	Net:On("Sync", 2, function(player)
		self:MarkDirty(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- push state to clients
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < SYNC_INTERVAL then
			return
		end
		accumulator = 0
		for player, profile in profiles do
			if profile.Dirty then
				profile.Dirty = false
				updateLeaderstats(player, profile.Data)
				Net:Send(player, "Data", snapshot(player, profile))
			end
		end
	end)

	-- autosave
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_SECONDS)
			for player in profiles do
				task.spawn(saveAsync, player, false)
				task.wait(0.5)
			end
		end
	end)

	game:BindToClose(function()
		if RunService:IsStudio() and not store then
			return
		end
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				saveAsync(player, true)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService
