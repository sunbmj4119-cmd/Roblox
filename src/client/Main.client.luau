--[[
	Client entry point: wires state sync and loads every controller.
]]
local Client = script.Parent

local Net = require(Client:WaitForChild("Net"))
local State = require(Client:WaitForChild("State"))

Net.On("Data", function(payload)
	State.Set(payload)
end)

-- language: saved preference (Settings) or the player's Roblox language
local Players = game:GetService("Players")
local LocalizationService = game:GetService("LocalizationService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lang = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Lang"))
local player = Players.LocalPlayer
local deadline = os.clock() + 8
while player:GetAttribute("Lang") == nil and os.clock() < deadline do
	task.wait(0.1)
end
local forced = player:GetAttribute("Lang")
if forced == "ko" or forced == "en" then
	Lang.SetLocale(forced)
else
	local ok, locale = pcall(function()
		return LocalizationService.RobloxLocaleId
	end)
	Lang.SetLocale(if ok then locale else player.LocaleId)
end

-- the default tool bar would cover our buttons; the pickaxe auto-equips
pcall(function()
	game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

local UI = Client:WaitForChild("UI")
local Controllers = Client:WaitForChild("Controllers")

local Panels = require(UI:WaitForChild("Panels"))
local Hatch = require(UI:WaitForChild("Hatch"))
Panels.Provide("Hatch", Hatch)

local HUD = require(Controllers:WaitForChild("HUD"))
local Mining = require(Controllers:WaitForChild("Mining"))
Mining.HUD = HUD
require(Controllers:WaitForChild("PetFollow"))
require(Controllers:WaitForChild("WorldFX"))
require(Controllers:WaitForChild("MeteorUI"))
require(Controllers:WaitForChild("DevTools"))
require(Controllers:WaitForChild("Guide"))
require(Controllers:WaitForChild("Ambience"))
require(Controllers:WaitForChild("Shards")).HUD = HUD
require(Controllers:WaitForChild("Build")).HUD = HUD
Panels.Provide("HowTo", require(Controllers:WaitForChild("HowTo")))
require(Controllers:WaitForChild("TradeUI")).HUD = HUD

-- ask for a fresh snapshot in case the first one arrived before we listened
Net.Fire("Sync")
task.delay(3, function()
	if not State.Ready() then
		Net.Fire("Sync")
	end
end)
