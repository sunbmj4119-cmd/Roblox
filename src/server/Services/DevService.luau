--[[
	DevService: Studio-only cheats for fast testing (never active in a live
	server - every handler checks RunService:IsStudio()).
]]
local RunService = game:GetService("RunService")

local Net = require(script.Parent.Net)

local Dev = {}
local Services

function Dev:Init(services)
	Services = services
end

function Dev:Start()
	if not RunService:IsStudio() then
		return
	end
	local Data = Services.DataService
	Net:On("Dev", 0.2, function(player, command)
		if not RunService:IsStudio() then
			return
		end
		local data = Data:Get(player)
		if not data then
			return
		end
		if command == "Coins" then
			local amount = math.max(1000000, data.Coins * 10)
			data.Coins += amount
			data.Stats.LifetimeCoins += amount
		elseif command == "Gems" then
			data.Gems += 10000
		elseif command == "Stardust" then
			data.Stardust += 5000
		elseif command == "Points" then
			Services.ProgressionService:AddPoints(player, 2500)
		elseif command == "XP" then
			Services.ProgressionService:AddSeasonXP(player, 5 * 2000)
		elseif command == "Meteor" then
			Services.MeteorService:Summon(player)
		elseif command == "Fill" then
			data.Backpack = Services.StatsService:Capacity(player, data)
		elseif command == "Reset" then
			local Util = require(game:GetService("ReplicatedStorage").Shared.Util)
			local fresh = Util.DeepCopy(Data.Template)
			fresh.FirstJoin = os.time()
			for key in data do
				data[key] = nil
			end
			for key, value in fresh do
				data[key] = value
			end
			Services.CharacterService:GivePickaxe(player)
			Services.PetService:RefreshEquipped(player)
		end
		Net:Notify(player, "[DEV] " .. tostring(command))
		Data:MarkDirty(player)
	end)
end

return Dev
