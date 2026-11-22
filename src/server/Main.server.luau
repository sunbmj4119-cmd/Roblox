--[[
	Server entry point. Services are initialised in dependency order:
	Init() wires references, Start() connects events and starts loops.
]]
local servicesFolder = script.Parent:WaitForChild("Services")

local ORDER = {
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
	"MeteorService",
	"ProgressionService",
	"LeaderboardService",
	"DevService",
}

local Services = {}
for _, name in ORDER do
	Services[name] = require(servicesFolder:WaitForChild(name))
end

for _, name in ORDER do
	local service = Services[name]
	if service.Init then
		service:Init(Services)
	end
end

-- Start everything except DataService first, so every OnLoaded/PlayerAdded hook
-- is registered before players' data begins loading.
for _, name in ORDER do
	local service = Services[name]
	if name ~= "DataService" and service.Start then
		local ok, err = pcall(service.Start, service)
		if not ok then
			warn(string.format("[Main] %s failed to start: %s", name, tostring(err)))
		end
	end
end
Services.DataService:Start()

print("[Meteor Miners] server ready")
