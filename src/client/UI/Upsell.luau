--[[
	Contextual upsell popup ("Backpack full? Get Auto Sell!"). Shown at the
	exact moment a pass would help - far better conversion than a store page.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Lib = require(script.Parent.Lib)
local Root = require(script.Parent.Root)
local Net = require(script.Parent.Parent.Net)
local State = require(script.Parent.Parent.State)

local New, C = Lib.New, Lib.Colors
local Upsell = {}

local cluster = Root.Cluster("Upsell", Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(420, 300))
cluster.ZIndex = 50
local frame = New("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = C.Panel,
	Visible = false,
	ZIndex = 50,
	Parent = cluster,
}, { Lib.Corner(20), Lib.Stroke(C.Gold, 3, 0) })
local icon = Lib.Text({ Text = "⭐", Size = UDim2.fromOffset(80, 80), Position = UDim2.new(0.5, -40, 0, 12), MaxTextSize = 70, ZIndex = 51, Parent = frame })
local title = Lib.Text({ Text = "", Size = UDim2.new(1, -30, 0, 34), Position = UDim2.fromOffset(15, 96), MaxTextSize = 30, ZIndex = 51, Parent = frame })
local description = Lib.Text({
	Text = "",
	Font = Lib.BodyFont,
	TextColor3 = C.Sub,
	Size = UDim2.new(1, -40, 0, 60),
	Position = UDim2.fromOffset(20, 134),
	TextWrapped = true,
	MaxTextSize = 18,
	ZIndex = 51,
	Parent = frame,
})
local current = nil

local buy = Lib.Button({
	Size = UDim2.fromOffset(200, 54),
	Position = UDim2.new(0.5, -205, 1, -70),
	ZIndex = 52,
	TextSize = 26,
	Parent = frame,
	OnClick = function()
		if current then
			Net.Fire(if current.Kind == "Pass" then "BuyPass" else "BuyProduct", current.Key)
		end
		frame.Visible = false
	end,
})
Lib.Button({
	Text = "No thanks",
	Color = C.Gray,
	Size = UDim2.fromOffset(180, 54),
	Position = UDim2.new(0.5, 15, 1, -70),
	ZIndex = 52,
	Parent = frame,
	OnClick = function()
		frame.Visible = false
	end,
})

local lastShown = {}
local function show(kind: string, key: string, entry)
	if not entry then
		return
	end
	-- don't nag: same offer at most once per 90 seconds
	local id = kind .. key
	if lastShown[id] and os.clock() - lastShown[id] < 90 then
		return
	end
	lastShown[id] = os.clock()
	current = { Kind = kind, Key = key }
	icon.Text = entry.Icon or "⭐"
	title.Text = entry.Name
	description.Text = entry.Description or ""
	Lib.SetButton(buy, "R$ " .. Lib.Price(kind, key), C.Green)
	frame.Visible = true
	Lib.Pop(frame)
end

function Upsell.Pass(key: string)
	if State.HasPass(key) then
		return
	end
	show("Pass", key, Config.GamePasses[key])
end

function Upsell.Product(key: string)
	show("Product", key, Config.Products[key])
end

function Upsell.Hide()
	frame.Visible = false
end

Net.On("Upsell", Upsell.Pass)
Net.On("UpsellProduct", Upsell.Product)

return Upsell
