--[[
	Client entry point: wires state sync and loads every controller.
]]
local Client = script.Parent

local Net = require(Client:WaitForChild("Net"))
local State = require(Client:WaitForChild("State"))

Net.On("Data", function(payload)
	State.Set(payload)
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

-- ask for a fresh snapshot in case the first one arrived before we listened
Net.Fire("Sync")
task.delay(3, function()
	if not State.Ready() then
		Net.Fire("Sync")
	end
end)
