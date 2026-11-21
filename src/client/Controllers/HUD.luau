--[[
	Main HUD: currencies, backpack, next-goal hint, menu buttons with
	notification badges, active boosts, starter-pack timer, auto-mine toggle,
	toasts and server-wide announcements.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)

local Client = script.Parent.Parent
local Net = require(Client.Net)
local State = require(Client.State)
local Lib = require(Client.UI.Lib)
local Root = require(Client.UI.Root)
local Panels = require(Client.UI.Panels)
local Upsell = require(Client.UI.Upsell)

local New, C = Lib.New, Lib.Colors
local HUD = {}

---------------------------------------------------------------------------
-- toasts & announcements
---------------------------------------------------------------------------
local toastCluster = Root.Cluster("Toasts", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 120), UDim2.fromOffset(520, 260))
toastCluster.ZIndex = 40
Lib.List(Enum.FillDirection.Vertical, 6).Parent = toastCluster

local toastOrder = 0
function HUD.Toast(text: string, color: Color3?)
	toastOrder += 1
	local toast = New("Frame", {
		BackgroundColor3 = Color3.fromRGB(20, 22, 34),
		BackgroundTransparency = 0.15,
		Size = UDim2.fromOffset(500, 40),
		LayoutOrder = toastOrder,
		ZIndex = 40,
		Parent = toastCluster,
	}, { Lib.Corner(12), Lib.Stroke(color or C.Blue, 2, 0.2) })
	Lib.Text({ Text = text, TextColor3 = color or C.Text, Size = UDim2.new(1, -16, 1, -8), Position = UDim2.fromOffset(8, 4), MaxTextSize = 20, ZIndex = 41, Parent = toast })
	Lib.Pop(toast)
	local toasts = {}
	for _, child in toastCluster:GetChildren() do
		if child:IsA("Frame") then
			table.insert(toasts, child)
		end
	end
	if #toasts > 4 then
		table.sort(toasts, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		toasts[1]:Destroy()
	end
	task.delay(3.5, function()
		if toast.Parent then
			TweenService:Create(toast, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
			task.wait(0.3)
			toast:Destroy()
		end
	end)
end

local bannerCluster = Root.Cluster("Banner", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 60), UDim2.fromOffset(820, 56))
bannerCluster.ZIndex = 45
local banner = New("Frame", {
	BackgroundColor3 = Color3.fromRGB(15, 15, 25),
	BackgroundTransparency = 0.1,
	Size = UDim2.fromScale(1, 1),
	Visible = false,
	ZIndex = 45,
	Parent = bannerCluster,
}, { Lib.Corner(16), Lib.Stroke(C.Gold, 3, 0) })
local bannerText = Lib.Text({ Text = "", Size = UDim2.new(1, -20, 1, -10), Position = UDim2.fromOffset(10, 5), MaxTextSize = 28, ZIndex = 46, Parent = banner })
local bannerQueue = {}
local bannerBusy = false

function HUD.Announce(text: string, color: Color3?)
	table.insert(bannerQueue, { Text = text, Color = color or C.Gold })
	if bannerBusy then
		return
	end
	bannerBusy = true
	task.spawn(function()
		while #bannerQueue > 0 do
			local item = table.remove(bannerQueue, 1)
			bannerText.Text = item.Text
			bannerText.TextColor3 = item.Color
			banner:FindFirstChildOfClass("UIStroke").Color = item.Color
			banner.Visible = true
			Lib.Pop(banner)
			task.wait(if #bannerQueue > 2 then 2.5 else 4.5)
		end
		banner.Visible = false
		bannerBusy = false
	end)
end

---------------------------------------------------------------------------
-- top left: currencies, backpack, goal
---------------------------------------------------------------------------
local topLeft = Root.Cluster("TopLeft", Vector2.zero, UDim2.fromOffset(12, 12), UDim2.fromOffset(360, 460))
Lib.List(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Left).Parent = topLeft

local function pill(order: number, icon: string, color: Color3)
	local frame = New("Frame", {
		BackgroundColor3 = Color3.fromRGB(20, 22, 34),
		BackgroundTransparency = 0.1,
		Size = UDim2.fromOffset(250, 42),
		LayoutOrder = order,
		Parent = topLeft,
	}, { Lib.Corner(21), Lib.Stroke(color, 2.5, 0) })
	Lib.Text({ Text = icon, Size = UDim2.fromOffset(36, 36), Position = UDim2.fromOffset(4, 3), MaxTextSize = 30, Parent = frame })
	local label = Lib.Text({ Text = "0", TextColor3 = color, Size = UDim2.new(1, -54, 1, -8), Position = UDim2.fromOffset(44, 4), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 28, Parent = frame })
	return frame, label
end

local coinPill, coinLabel = pill(1, "🪙", C.Coins)
local _, gemLabel = pill(2, "💎", C.Gems)
local _, dustLabel = pill(3, "✨", C.Stardust)

local backpackRow = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(290, 36), LayoutOrder = 4, Parent = topLeft })
local _, setBackpack = Lib.Bar({ Size = UDim2.fromOffset(200, 32), Position = UDim2.fromOffset(0, 2), Color = C.Blue, TextSize = 18, Parent = backpackRow })
Lib.Button({
	Text = "💰 Sell",
	Color = C.Green,
	Size = UDim2.fromOffset(80, 34),
	Position = UDim2.fromOffset(206, 1),
	TextSize = 18,
	Parent = backpackRow,
	OnClick = function()
		if State.HasPass("AutoSell") then
			Net.Fire("SellAnywhere")
		else
			Upsell.Pass("AutoSell", true)
			HUD.Toast("Sell at the 💰 pad in the hub - or sell anywhere with Auto Sell!", C.Green)
		end
	end,
})

local statsLabel = Lib.Text({
	Text = "",
	Font = Lib.BodyFont,
	Size = UDim2.fromOffset(290, 20),
	LayoutOrder = 5,
	TextXAlignment = Enum.TextXAlignment.Left,
	MaxTextSize = 15,
	Parent = topLeft,
})

local goal = New("Frame", {
	BackgroundColor3 = Color3.fromRGB(20, 22, 34),
	BackgroundTransparency = 0.2,
	Size = UDim2.fromOffset(290, 46),
	LayoutOrder = 6,
	Parent = topLeft,
}, { Lib.Corner(12), Lib.Stroke(C.Gold, 2, 0.3) })
local goalText = Lib.Text({
	Text = "",
	Size = UDim2.new(1, -14, 1, -8),
	Position = UDim2.fromOffset(7, 4),
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	MaxTextSize = 16,
	Parent = goal,
})

---------------------------------------------------------------------------
-- left menu
---------------------------------------------------------------------------
-- the menu flows right under the info box (same UIScale), so they never overlap
local menu = New("Frame", { Name = "Menu", BackgroundTransparency = 1, Size = UDim2.fromOffset(352, 172), LayoutOrder = 7, Parent = topLeft })
local menuGrid = Lib.Grid(UDim2.fromOffset(82, 82), 8)
menuGrid.HorizontalAlignment = Enum.HorizontalAlignment.Left
menuGrid.Parent = menu
local badges = {}
local MENU = {
	{ "Shop", "⛏️", "Upgrade", C.Gold },
	{ "Pets", "🐾", "Pets", C.Green },
	{ "Quests", "📜", "Daily", C.Blue },
	{ "Pass", "🎫", "Pass", Color3.fromRGB(255, 120, 60) },
	{ "Gifts", "🎁", "Gifts", C.Pink },
	{ "Rebirth", "♻️", "Rebirth", C.Purple },
	{ "Teleport", "🌀", "Zones", C.Cyan },
	{ "Store", "🛒", "Store", Color3.fromRGB(60, 200, 110) },
}
for order, item in MENU do
	local button = New("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = item[4],
		LayoutOrder = order,
		Parent = menu,
	}, { Lib.Corner(16), Lib.Stroke(Color3.new(0, 0, 0), 2.5, 0.25), Lib.Gradient(Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 170)) })
	Lib.Text({ Text = item[2], Size = UDim2.new(1, 0, 0.62, 0), Position = UDim2.fromScale(0, 0.04), MaxTextSize = 40, Parent = button })
	Lib.Text({ Text = item[3], Size = UDim2.new(1, -4, 0.3, 0), Position = UDim2.fromScale(0.02, 0.66), MaxTextSize = 17, Parent = button })
	local badge = New("Frame", {
		BackgroundColor3 = C.Red,
		Size = UDim2.fromOffset(24, 24),
		Position = UDim2.new(1, -16, 0, -8),
		Visible = false,
		ZIndex = 3,
		Parent = button,
	}, { Lib.Corner(12), Lib.Stroke(Color3.new(1, 1, 1), 2, 0) })
	Lib.Text({ Text = "!", Size = UDim2.fromScale(1, 1), MaxTextSize = 18, ZIndex = 4, Parent = badge })
	badges[item[1]] = badge
	local scale = New("UIScale", { Parent = button })
	button.Activated:Connect(function()
		scale.Scale = 0.9
		TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		Lib.PlaySound(Config.Sounds.UI, 0.35)
		Panels.Toggle(item[1])
	end)
end

---------------------------------------------------------------------------
-- right side: boosts
---------------------------------------------------------------------------
local right = Root.Cluster("RightColumn", Vector2.new(1, 0), UDim2.new(1, -12, 0, 70), UDim2.fromOffset(250, 520))
HUD.RightColumn = right -- boosts + meteor live ranking stack here
Lib.List(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Right).Parent = right
local boostRows = {}
local BOOSTS = {
	{ "Coins2x", "⏫ 2x Coins", C.Coins },
	{ "Luck2x", "🍀 2x Luck", C.Green },
	{ "Power2x", "💥 2x Power", C.Red },
	{ "ServerLuck", "🌟 Server Luck", C.Gold },
}
for order, def in BOOSTS do
	local row = New("Frame", {
		BackgroundColor3 = Color3.fromRGB(20, 22, 34),
		BackgroundTransparency = 0.15,
		Size = UDim2.fromOffset(220, 34),
		LayoutOrder = order,
		Visible = false,
		Parent = right,
	}, { Lib.Corner(10), Lib.Stroke(def[3], 2, 0.2) })
	local label = Lib.Text({ Text = "", TextColor3 = def[3], Size = UDim2.new(1, -12, 1, -6), Position = UDim2.fromOffset(6, 3), MaxTextSize = 18, Parent = row })
	boostRows[def[1]] = { Row = row, Label = label, Name = def[2] }
end

---------------------------------------------------------------------------
-- bottom: auto mine, starter pack, backpack full helper
---------------------------------------------------------------------------
local bottom = Root.Cluster("Bottom", Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -14), UDim2.fromOffset(700, 120))
local bottomRow = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 54), Position = UDim2.new(0, 0, 1, -54), Parent = bottom }, {
	Lib.List(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
})
local autoButton = Lib.Button({
	Size = UDim2.fromOffset(200, 50),
	Color = C.Gray,
	LayoutOrder = 1,
	Parent = bottomRow,
	OnClick = function()
		if State.HasPass("AutoMine") then
			State.AutoMine = not State.AutoMine
			HUD.Refresh()
		else
			Upsell.Pass("AutoMine", true)
		end
	end,
})
local starterButton = Lib.Button({
	Size = UDim2.fromOffset(260, 50),
	Color = C.Pink,
	LayoutOrder = 2,
	Parent = bottomRow,
	OnClick = function()
		Upsell.Product("StarterPack", true)
	end,
})
local fullFrame = New("Frame", {
	BackgroundColor3 = Color3.fromRGB(60, 20, 25),
	BackgroundTransparency = 0.1,
	Size = UDim2.fromOffset(560, 56),
	Position = UDim2.new(0.5, 0, 0, 0),
	AnchorPoint = Vector2.new(0.5, 0),
	Visible = false,
	Parent = bottom,
}, { Lib.Corner(14), Lib.Stroke(C.Red, 2.5, 0) })
Lib.Text({ Text = "🎒 BACKPACK FULL!", TextColor3 = C.Red, Size = UDim2.fromOffset(200, 40), Position = UDim2.fromOffset(10, 8), MaxTextSize = 24, Parent = fullFrame })
Lib.Button({ Text = "🏠 Sell at Hub", Color = C.Green, Size = UDim2.fromOffset(160, 42), Position = UDim2.fromOffset(214, 7), Parent = fullFrame, OnClick = function()
	if State.HasPass("AutoSell") then
		Net.Fire("SellAnywhere")
	else
		Net.Fire("Teleport", 0)
	end
end })
Lib.Button({ Text = "🎒 Upgrade", Color = C.Blue, Size = UDim2.fromOffset(170, 42), Position = UDim2.fromOffset(382, 7), Parent = fullFrame, OnClick = function()
	Panels.Open("Shop", "Backpacks")
end })

---------------------------------------------------------------------------
-- refresh
---------------------------------------------------------------------------
local function nextGoal(data, derived): string
	local capacity = derived.Capacity or 1
	if data.Backpack >= capacity then
		return "🎯 Sell your ore at the 💰 SELL pad in the hub!"
	end
	local pick = Config.Pickaxes[data.PickaxeTier + 1]
	local bag = Config.Backpacks[data.BackpackTier + 1]
	local zone = Config.Zones[data.ZoneLevel + 1]
	local rebirthCost = derived.RebirthCost or math.huge
	if data.Coins >= rebirthCost then
		return "🎯 You can REBIRTH for a permanent coin boost!"
	end
	if zone and data.Coins >= zone.Cost then
		return "🎯 Unlock " .. zone.Name .. " at the gate!"
	end
	if pick and data.Coins >= pick.Cost then
		return "🎯 Buy the " .. pick.Name .. "!"
	end
	if bag and data.Coins >= bag.Cost then
		return "🎯 Buy the " .. bag.Name .. "!"
	end
	if data.Stats.EggsHatched == 0 and data.Coins >= Config.Eggs.Meadow.Price then
		return "🎯 Hatch your first pet at the Meadow Egg!"
	end
	local cheapest = math.huge
	for _, cost in { pick and pick.Cost, bag and bag.Cost, zone and zone.Cost } do
		if cost then
			cheapest = math.min(cheapest, cost)
		end
	end
	if cheapest < math.huge then
		return string.format("🎯 Mine & sell ore: %s / %s coins for your next upgrade", Util.Format(data.Coins), Util.Format(cheapest))
	end
	return "🎯 Climb the weekly ranked leaderboard!"
end

local function anyQuestClaimable(data): boolean
	if data.Daily.LastClaimDay ~= (State.Derived.Today or -1) then
		return true
	end
	for _, quest in data.Daily.Quests do
		for _, def in Config.Quests do
			if def.Id == quest.Id and not quest.Claimed and quest.Progress >= def.Target then
				return true
			end
		end
	end
	return false
end

local function anyTierClaimable(data): boolean
	local tier = math.min(#Config.SeasonTiers, math.floor(data.Season.XP / Config.Season.XPPerTier))
	for t = 1, tier do
		if not data.Season.ClaimedFree[tostring(t)] then
			return true
		end
		if data.Season.Premium and not data.Season.ClaimedPremium[tostring(t)] then
			return true
		end
	end
	return false
end

local function anyGiftClaimable(derived): boolean
	local claimed = {}
	for _, index in derived.GiftsClaimed or {} do
		claimed[index] = true
	end
	local elapsed = State.Now() - (derived.SessionStart or State.Now())
	for i, gift in Config.PlaytimeGifts do
		if not claimed[i] and elapsed >= gift.Minutes * 60 then
			return true
		end
	end
	return false
end

local lastCoins = nil
function HUD.Refresh()
	local data, derived = State.Data, State.Derived
	if not data then
		return
	end
	coinLabel.Text = Util.Format(data.Coins)
	gemLabel.Text = Util.Format(data.Gems)
	dustLabel.Text = Util.Format(data.Stardust)
	if lastCoins and data.Coins > lastCoins then
		Lib.Pop(coinPill)
	end
	lastCoins = data.Coins

	local capacity = derived.Capacity or 1
	local full = data.Backpack >= capacity
	setBackpack(data.Backpack / capacity, string.format("🎒 %s / %s", Util.Format(data.Backpack), Util.Format(capacity)), if full then C.Red else C.Blue)
	fullFrame.Visible = full
	statsLabel.Text = string.format("🪙 x%s   💥 %s   🍀 x%.1f", Util.Format(derived.CoinMult or 1), Util.Format(derived.Damage or 1), derived.Luck or 1)
	goalText.Text = nextGoal(data, derived)

	badges.Quests.Visible = anyQuestClaimable(data)
	badges.Pass.Visible = anyTierClaimable(data)
	badges.Gifts.Visible = anyGiftClaimable(derived)
	badges.Rebirth.Visible = data.Coins >= (derived.RebirthCost or math.huge)

	for key, row in boostRows do
		local remaining
		if key == "ServerLuck" then
			remaining = (workspace:GetAttribute("Server_ServerLuck") or 0) - State.Now()
		else
			remaining = State.BoostRemaining(key)
		end
		row.Row.Visible = remaining > 0
		if remaining > 0 then
			row.Label.Text = row.Name .. "  " .. Util.FormatTime(remaining)
		end
	end

	if State.HasPass("AutoMine") then
		Lib.SetButton(autoButton, if State.AutoMine then "🤖 AUTO MINE: ON" else "🤖 AUTO MINE: OFF", if State.AutoMine then C.Green else C.Gray)
	else
		Lib.SetButton(autoButton, "🤖 AUTO MINE 🔒", C.Gray)
	end

	local offerEnds = data.FirstJoin + Config.StarterPack.OfferHours * 3600
	local remainingOffer = offerEnds - State.Now()
	starterButton.Visible = not data.Flags.StarterPack and remainingOffer > 0
	if starterButton.Visible then
		Lib.SetButton(starterButton, "🎁 STARTER PACK  " .. Util.FormatTime(remainingOffer), C.Pink)
	end
end

---------------------------------------------------------------------------
-- server messages
---------------------------------------------------------------------------
Net.On("Notify", function(text, color)
	HUD.Toast(text, color)
end)
Net.On("Announce", function(text, color)
	HUD.Announce(text, color)
end)
Net.On("Reward", function(text, source)
	HUD.Toast("🎁 " .. (if source then source .. ": " else "") .. text, C.Gold)
	Lib.PlaySound(Config.Sounds.Coins, 0.6)
end)
Net.On("Sold", function(coins)
	Lib.PlaySound(Config.Sounds.Coins, 0.5)
	local popup = Lib.Text({
		Text = "+" .. Util.Format(coins) .. " 🪙",
		TextColor3 = C.Coins,
		Size = UDim2.fromOffset(200, 36),
		Position = UDim2.fromOffset(260, 4),
		MaxTextSize = 30,
		ZIndex = 10,
		Parent = topLeft.Parent,
	})
	popup.Position = UDim2.fromOffset(topLeft.AbsolutePosition.X + 200, topLeft.AbsolutePosition.Y)
	TweenService:Create(popup, TweenInfo.new(1.2), {
		Position = popup.Position - UDim2.fromOffset(0, 40),
		TextTransparency = 1,
	}):Play()
	task.delay(1.2, function()
		popup:Destroy()
	end)
end)
Net.On("Rebirthed", function(count, gems)
	HUD.Announce(string.format("♻️ REBIRTH %d!  +%s 💎", count, Util.Format(gems)), C.Purple)
end)
Net.On("ZoneUnlocked", function(index)
	local zone = Config.Zones[index]
	if zone then
		HUD.Announce("🔓 " .. zone.Name .. " unlocked!", zone.Accent)
	end
end)
Net.On("OpenPanel", function(panel, arg)
	if panel == "Daily" then
		Panels.Open("Quests")
	else
		Panels.Open(panel, arg)
	end
end)
Net.On("BackpackFull", function()
	if not State.HasPass("AutoSell") then
		Upsell.Pass("AutoSell")
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Q then
		Panels.Toggle("Pets")
	elseif input.KeyCode == Enum.KeyCode.Escape and Panels.Current then
		Panels.Close()
	end
end)

State.OnChanged(HUD.Refresh)
task.spawn(function()
	while true do
		task.wait(1)
		local ok, err = pcall(HUD.Refresh)
		if not ok then
			warn("[HUD] refresh failed: " .. tostring(err))
		end
	end
end)

Panels.Provide("Toast", HUD.Toast)
Panels.Provide("Upsell", Upsell)

return HUD
