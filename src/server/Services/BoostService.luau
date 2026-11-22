--[[
	BoostService: personal timed boosts (tick only while online, stack time)
	and server-wide boosts bought by one player for everyone (Server Luck).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = require(Shared.Util)
local Net = require(script.Parent.Net)

local Boosts = {}
local Data

local serverBoosts = {} -- [key] = unix end time

function Boosts:IsActive(player: Player, key: string): boolean
	local data = Data:Get(player)
	return data ~= nil and (data.Boosts[key] or 0) > 0
end

function Boosts:Add(player: Player, key: string, seconds: number)
	local data = Data:Get(player)
	if not data then
		return
	end
	data.Boosts[key] = (data.Boosts[key] or 0) + seconds
	Net:Notify(player, "⏫ %s boost +%s!", Color3.fromRGB(120, 255, 170), Util.BoostNames[key] or key, Util.FormatTime(seconds))
	Data:MarkDirty(player)
end

function Boosts:ServerActive(key: string): boolean
	return (serverBoosts[key] or 0) > os.time()
end

function Boosts:AddServer(key: string, seconds: number, buyer: Player?)
	local now = os.time()
	serverBoosts[key] = math.max(serverBoosts[key] or 0, now) + seconds
	workspace:SetAttribute("Server_" .. key, serverBoosts[key])
	if buyer then
		Net:Announce(
			"🌟 %s activated SERVER LUCK for everyone! (+%d min)",
			Color3.fromRGB(255, 230, 90),
			buyer.DisplayName,
			math.floor(seconds / 60)
		)
	end
	for _, player in Players:GetPlayers() do
		Data:MarkDirty(player)
	end
end

function Boosts:Init(services)
	Data = services.DataService
end

function Boosts:Start()
	task.spawn(function()
		local tick = 0
		local function step()
			tick += 1
			for _, player in Data:LoadedPlayers() do
				local data = Data:Get(player)
				if data then
					local changed = false
					for key, remaining in data.Boosts do
						if remaining > 0 then
							data.Boosts[key] = math.max(0, remaining - 1)
							if data.Boosts[key] == 0 then
								changed = true
								Net:Notify(player, "%s boost ended", nil, Util.BoostNames[key] or key)
							end
						end
					end
					if changed or tick % 15 == 0 then
						Data:MarkDirty(player)
					end
				end
			end
			for key, endTime in serverBoosts do
				if endTime > 0 and endTime <= os.time() then
					serverBoosts[key] = 0
					workspace:SetAttribute("Server_" .. key, 0)
					for _, player in Players:GetPlayers() do
						Data:MarkDirty(player)
					end
				end
			end
		end
		while true do
			task.wait(1)
			local ok, err = pcall(step)
			if not ok then
				warn("[Boosts] tick error: " .. tostring(err))
			end
		end
	end)
end

return Boosts
