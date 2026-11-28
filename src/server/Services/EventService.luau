--[[
	EventService: short random server events between meteors
	(Ore Frenzy, Lucky Rush, Gem Storm, Double Ore, Lucky Block Rain ...).
	Every few minutes there is something new happening -> players stay longer
	and talk about it.
	Every RaidEvery-th event is 🌙 THIEF NIGHT (announced 20s early): the
	only time other players' homes can be raided. Homes are safe otherwise.
	Other services read multipliers with Events:Get(key, default).

	Also:
	  * 🎉 weekly PARTY (Config.WeeklyParty): lucky block rain + starfall +
	    2x luck in every server at the same time, like the big games' weekly
	    admin events. The owner can start one everywhere from the DEV panel.
	  * global announcements (MessagingService): a TITANIC hatch is shouted
	    in every server.
]]
local MessagingService = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(script.Parent.Net)

local Events = {}
local Services

local TOPIC = "MeteorMiners_Global"
local settings = Config.Events
local PARTY = Config.WeeklyParty
local listeners = {}
local partyEnds = 0
local lastPartyDay = -1
local warnedDay = -1
local current = nil
local endsAt = 0
local nextAt = os.time() + 90 -- first event shortly after the server starts
local lastId = nil
local eventCount = 0
local raidAt = 0 -- 🌙 a raid was announced and starts at this time

local function setAttributes()
	workspace:SetAttribute("EventId", if current then current.Id else "")
	workspace:SetAttribute("EventEnd", endsAt)
	workspace:SetAttribute("RaidActive", current ~= nil and current.Raid == true)
	workspace:SetAttribute("RaidAt", raidAt)
end

local function find(id: string?)
	for _, candidate in settings.List do
		if candidate.Id == id then
			return candidate
		end
	end
	return nil
end

function Events:Active()
	return current
end

-- 🏠 homes are safe - except during a raid event (🌙 Thief Night)
function Events:RaidActive(): boolean
	return current ~= nil and current.Raid == true
end

function Events:Get(key: string, default: number): number
	if current and type(current[key]) == "number" then
		return current[key]
	end
	return default
end

-- start a specific event (id) or a random one different from the last
-- (random picks never choose NoRandom events: raids come every RaidEvery-th time)
function Events:Trigger(id: string?)
	local def = find(id)
	-- an announced or running 🌙 raid is never replaced (party / DEV events wait)
	if (raidAt > 0 or (current ~= nil and current.Raid)) and not (def and def.Raid) then
		return
	end
	if not def then
		local pool = {}
		for _, candidate in settings.List do
			if candidate.Id ~= lastId and not candidate.NoRandom then
				table.insert(pool, candidate)
			end
		end
		if #pool == 0 then
			return
		end
		def = pool[math.random(1, #pool)]
	end
	current = def
	lastId = def.Id
	raidAt = 0
	local duration = def.Duration or settings.DurationSeconds
	endsAt = os.time() + duration
	setAttributes()
	Net:Announce("%s! %s (%ds)", def.Color, def.Name, def.Description, duration)
	Net:Broadcast("EventStarted", def.Id)
	for _, listener in listeners do
		task.spawn(listener, def)
	end
end

-- the next scheduled event: every RaidEvery-th one is a raid, announced early
local function nextEvent()
	eventCount += 1
	local raid = nil
	if settings.RaidEvery and eventCount % settings.RaidEvery == 0 then
		for _, candidate in settings.List do
			if candidate.Raid then
				raid = candidate
			end
		end
	end
	if raid and (raid.Warn or 0) > 0 then
		raidAt = os.time() + raid.Warn
		nextAt = raidAt
		setAttributes()
		Net:Announce("🌙 THIEF NIGHT in %ds! Put your best pets in 🔒 vaults!", raid.Color, raid.Warn)
		Net:Broadcast("RaidWarning", raidAt)
	else
		Events:Trigger(if raid then raid.Id else nil)
	end
end

-- other services react to events (LuckyService: lucky block rain)
function Events:OnStart(callback)
	table.insert(listeners, callback)
end

---------------------------------------------------------------------------
-- every server at once (MessagingService)
---------------------------------------------------------------------------
local function publish(message)
	message.Job = game.JobId
	pcall(MessagingService.PublishAsync, MessagingService, TOPIC, message)
end

-- shout in this server + every other server (each player in their language)
function Events:GlobalAnnounce(fmt: string, color: Color3, ...)
	Net:Announce(fmt, color, ...)
	local args = { ... }
	for i, value in args do
		args[i] = tostring(value)
	end
	publish({ Kind = "Announce", Fmt = fmt, Args = args, Color = { color.R, color.G, color.B } })
end

function Events:PartyActive(): boolean
	return partyEnds > os.time()
end

-- 🎉 party: lucky block rain every few minutes, a starfall and 2x luck
function Events:StartParty(minutes: number): boolean
	if self:PartyActive() then
		return false
	end
	minutes = math.clamp(minutes, 1, 60)
	partyEnds = os.time() + minutes * 60
	workspace:SetAttribute("PartyEnd", partyEnds)
	Net:Announce("🎉 PARTY TIME! Lucky blocks, a starfall, a GIANT GOLDEN meteor and 2x luck!", Color3.fromRGB(255, 200, 80))
	Net:Broadcast("Party", partyEnds)
	if Services and Services.BoostService then
		Services.BoostService:AddServer("ServerLuck", minutes * 60)
	end
	self:Trigger("Starfall")
	-- ✨ and the next meteor is a GIANT GOLDEN one
	if Services and Services.MeteorService then
		Services.MeteorService:QueueSpecial("Giant", true)
	end
	task.spawn(function()
		while os.time() < partyEnds do
			local lucky = Services and Services.LuckyService
			if lucky then
				pcall(lucky.Rain, lucky, 8)
			end
			task.wait(PARTY.RainEvery)
		end
		workspace:SetAttribute("PartyEnd", 0)
	end)
	return true
end

-- the owner's "admin event": a party in EVERY server
function Events:GlobalParty(minutes: number)
	self:StartParty(minutes)
	if not RunService:IsStudio() then -- (a Studio test must never start a party in live servers)
		publish({ Kind = "Party", Minutes = minutes })
	end
end

local function onMessage(message)
	local data = message and message.Data
	if type(data) ~= "table" or data.Job == game.JobId then
		return
	end
	if data.Kind == "Announce" and type(data.Fmt) == "string" and type(data.Args) == "table" then
		local c = type(data.Color) == "table" and data.Color or { 1, 1, 1 }
		Net:Announce(data.Fmt, Color3.new(tonumber(c[1]) or 1, tonumber(c[2]) or 1, tonumber(c[3]) or 1), table.unpack(data.Args))
	elseif data.Kind == "Party" then
		Events:StartParty(tonumber(data.Minutes) or 10)
	end
end

-- the weekly party starts by itself (same UTC time in every server)
local function checkWeekly()
	local t = os.date("!*t")
	local day = math.floor(os.time() / 86400)
	if t.wday == PARTY.WeekDay and t.hour == PARTY.HourUTC and t.min < PARTY.Minutes and lastPartyDay ~= day then
		-- (if another party is still running, try again next second)
		if Events:StartParty(PARTY.Minutes - t.min) then
			lastPartyDay = day
		end
	elseif t.wday == PARTY.WeekDay and t.hour == PARTY.HourUTC - 1 and t.min >= 50 and warnedDay ~= day then
		warnedDay = day
		Net:Announce("🎉 The weekly PARTY starts in 10 minutes! Lucky blocks + 2x luck!", Color3.fromRGB(255, 200, 80))
	end
end

local function stop()
	if current then
		Net:Broadcast("EventEnded", current.Id)
	end
	current = nil
	endsAt = 0
	nextAt = os.time() + settings.IntervalSeconds
	setAttributes()
end

-- cloud tests: end the current event now
function Events:EndForTest()
	assert(not RunService:IsRunning(), "test hook used on a live server")
	stop()
	raidAt = 0
	setAttributes()
end

function Events:Init(services)
	Services = services
end

function Events:Start()
	setAttributes()
	workspace:SetAttribute("PartyEnd", 0)
	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:SubscribeAsync(TOPIC, onMessage)
		end)
		if not ok then
			warn("[Events] global messages unavailable: " .. tostring(err))
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(function()
				local now = os.time()
				checkWeekly()
				if current and now >= endsAt then
					stop()
				elseif not current and raidAt > 0 and now >= raidAt then
					local raid = nil
					for _, candidate in settings.List do
						if candidate.Raid then
							raid = candidate
						end
					end
					raidAt = 0
					self:Trigger(raid and raid.Id)
				elseif not current and raidAt == 0 and now >= nextAt then
					nextEvent()
				end
			end)
			if not ok then
				warn("[Events] loop error: " .. tostring(err))
				current = nil
				raidAt = 0
				nextAt = os.time() + settings.IntervalSeconds
				setAttributes()
			end
		end
	end)
end

return Events
