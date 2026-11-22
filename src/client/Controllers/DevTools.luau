--[[
	DEV buttons: visible in Studio, and for the game owner in live servers
	while Config.OwnerTestMode is on (so you can test from a phone).
	The server re-checks permission for every command (DevService).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)

local Client = script.Parent.Parent
local Net = require(Client.Net)
local Lib = require(Client.UI.Lib)
local Root = require(Client.UI.Root)

local C = Lib.Colors

local function build()
	local cluster = Root.Cluster("Dev", Vector2.new(0, 1), UDim2.new(0, 12, 1, -12), UDim2.fromOffset(150, 470))
	local list = Lib.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -40), Visible = false, Parent = cluster }, {
		Lib.List(Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Bottom),
	})
	for order, command in { "Coins", "Gems", "Level", "Points", "Star", "Shard", "Event", "Rainbow", "Spin", "Meteor", "Fill", "Reset" } do
		Lib.Button({
			Text = command,
			Color = if command == "Reset" then C.Red else C.Gray,
			Size = UDim2.fromOffset(140, 30),
			LayoutOrder = order,
			TextSize = 16,
			Parent = list,
			OnClick = function()
				Net.Fire("Dev", command)
			end,
		})
	end
	Lib.Button({
		Text = "🛠 DEV",
		Color = Color3.fromRGB(60, 60, 70),
		Size = UDim2.fromOffset(100, 34),
		Position = UDim2.new(0, 0, 1, -34),
		TextSize = 16,
		Parent = cluster,
		OnClick = function()
			list.Visible = not list.Visible
		end,
	})
end

-- Util.CanTest may do a web call (group rank), so check off the main thread
task.spawn(function()
	if Util.CanTest(Config, Players.LocalPlayer) then
		build()
	end
end)

return {}
