--[[
	EventService: short random server events between meteors
	(Ore Frenzy, Lucky Rush, Gem Storm, Double Ore). Every few minutes there
	is something new happening -> players stay longer and talk about it.
	Other services read multipliers with Events:Get(key, default).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(script.Parent.Net)

local Events = {}

local settings = Config.Events
local current = nil
local endsAt = 0
local nextAt = os.time() + 90 -- first event shortly after the server starts
local lastId = nil

local function setAttributes()
	workspace:SetAttribute("EventId", if current then current.Id else "")
	workspace:SetAttribute("EventEnd", endsAt)
end

function Events:Active()
	return current
end

function Events:Get(key: string, default: number): number
	if current and type(current[key]) == "number" then
		return current[key]
	end
	return default
end

-- start a specific event (id) or a random one different from the last
function Events:Trigger(id: string?)
	local def = nil
	for _, candidate in settings.List do
		if candidate.Id == id then
			def = candidate
		end
	end
	if not def then
		local pool = {}
		for _, candidate in settings.List do
			if candidate.Id ~= lastId then
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
	endsAt = os.time() + settings.DurationSeconds
	setAttributes()
	Net:Announce("%s! %s (%ds)", def.Color, def.Name, def.Description, settings.DurationSeconds)
	Net:Broadcast("EventStarted", def.Id)
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

function Events:Start()
	setAttributes()
	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(function()
				local now = os.time()
				if current and now >= endsAt then
					stop()
				elseif not current and now >= nextAt then
					self:Trigger()
				end
			end)
			if not ok then
				warn("[Events] loop error: " .. tostring(err))
				current = nil
				nextAt = os.time() + settings.IntervalSeconds
				setAttributes()
			end
		end
	end)
end

return Events
