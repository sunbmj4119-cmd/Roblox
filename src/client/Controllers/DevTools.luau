-- Studio-only dev buttons (hidden in live servers). Pairs with DevService.
local RunService = game:GetService("RunService")

local Client = script.Parent.Parent
local Net = require(Client.Net)
local Lib = require(Client.UI.Lib)
local Root = require(Client.UI.Root)

if not RunService:IsStudio() then
	return {}
end

local C = Lib.Colors
local cluster = Root.Cluster("Dev", Vector2.new(0, 1), UDim2.new(0, 12, 1, -12), UDim2.fromOffset(150, 330))
local list = Lib.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -40), Visible = false, Parent = cluster }, {
	Lib.List(Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Bottom),
})
for order, command in { "Coins", "Gems", "Stardust", "Points", "XP", "Meteor", "Fill", "Reset" } do
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

return {}
