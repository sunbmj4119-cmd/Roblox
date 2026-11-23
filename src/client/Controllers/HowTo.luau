--[[
	"How to play" card: three big pictures, one line each, one button.
	Shown once on a player's first visit (server remembers it), and any time
	from Settings -> ❓ How to play.
]]
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Client = script.Parent.Parent
local Net = require(Client.Net)
local State = require(Client.State)
local Lib = require(Client.UI.Lib)
local Root = require(Client.UI.Root)

local New, C = Lib.New, Lib.Colors
local HowTo = {}

local STEPS = {
	{
		Icon = "⛏️",
		Title = "MINE",
		Text = "Tap ore (or hold ⛏️) to mine.\nCoins come instantly!",
		Color = Color3.fromRGB(255, 190, 70),
	},
	{
		Icon = "🥚",
		Title = "HATCH PETS",
		Text = "Pets stand in your 🏠 base\nand earn 💰 every second.",
		Color = Color3.fromRGB(120, 220, 120),
	},
	{
		Icon = "🌠",
		Title = "STEAL & PROTECT",
		Text = "Carry stars and other players'\npets home. Bonk thieves!",
		Color = Color3.fromRGB(170, 130, 255),
	},
}

local screen = New("TextButton", {
	Name = "HowToPlay",
	Text = "",
	AutoButtonColor = false,
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.35,
	Size = UDim2.fromScale(1, 1),
	Visible = false,
	ZIndex = 50,
	Parent = Root.Overlay,
})
local outer = Root.Cluster("HowToCards", Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(820, 400), screen)
-- inner frame: its own UIScale for the pop animation (the cluster's UIScale fits the screen)
local cluster = New("Frame", {
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	Parent = outer,
})
Lib.Text({
	Text = "HOW TO PLAY",
	TextColor3 = Color3.fromRGB(255, 230, 120),
	Size = UDim2.new(1, 0, 0, 56),
	MaxTextSize = 46,
	ZIndex = 51,
	Parent = cluster,
})
local row = New("Frame", {
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 250),
	Position = UDim2.fromOffset(0, 64),
	ZIndex = 51,
	Parent = cluster,
}, { Lib.List(Enum.FillDirection.Horizontal, 16, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })

for order, step in STEPS do
	local card = New("Frame", {
		BackgroundColor3 = C.Panel,
		Size = UDim2.fromOffset(250, 240),
		LayoutOrder = order,
		ZIndex = 51,
		Parent = row,
	}, { Lib.Corner(20), Lib.Stroke(step.Color, 4, 0) })
	Lib.Text({
		Text = tostring(order),
		TextColor3 = step.Color,
		Size = UDim2.fromOffset(40, 40),
		Position = UDim2.fromOffset(10, 6),
		MaxTextSize = 30,
		ZIndex = 52,
		Parent = card,
	})
	Lib.Text({
		Text = step.Icon,
		Size = UDim2.new(1, 0, 0, 90),
		Position = UDim2.fromOffset(0, 16),
		MaxTextSize = 80,
		Outline = false,
		ZIndex = 52,
		Parent = card,
	})
	Lib.Text({
		Text = step.Title,
		TextColor3 = step.Color,
		Size = UDim2.new(1, -16, 0, 36),
		Position = UDim2.fromOffset(8, 112),
		MaxTextSize = 30,
		ZIndex = 52,
		Parent = card,
	})
	Lib.Text({
		Text = step.Text,
		Font = Lib.BodyFont,
		Size = UDim2.new(1, -20, 0, 70),
		Position = UDim2.fromOffset(10, 154),
		MaxTextSize = 20,
		ZIndex = 52,
		Parent = card,
	})
end

local goButton = Lib.Button({
	Text = "LET'S GO!",
	Color = C.Green,
	Size = UDim2.fromOffset(260, 64),
	Position = UDim2.new(0.5, 0, 1, -66),
	AnchorPoint = Vector2.new(0.5, 0),
	TextSize = 32,
	ZIndex = 52,
	Parent = cluster,
	OnClick = function()
		HowTo.Hide()
	end,
})
local scale = New("UIScale", { Parent = cluster })

function HowTo.Show()
	screen.Visible = true
	scale.Scale = 0.6
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	Lib.PlaySound("Reward")
end

function HowTo.Hide()
	if not screen.Visible then
		return
	end
	screen.Visible = false
	Net.Fire("SeenHowTo")
	Lib.Pop(goButton)
end

-- first visit: show it once the save has loaded
local shownOnce = false
State.OnChanged(function()
	local data = State.Data
	if shownOnce or not data or not data.Flags then
		return
	end
	shownOnce = true
	if not data.Flags.HowToSeen then
		task.delay(1.5, function()
			if Players.LocalPlayer.Parent then
				HowTo.Show()
			end
		end)
	end
end)

return HowTo
