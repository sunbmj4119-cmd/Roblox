--[[
	Main HUD - designed for phones first and to reveal things gradually:
	  * objective: top center during the tutorial, then a small card in the
	    right column (nothing big in the middle of the screen)
	  * top left: money, level, and a menu that grows with progress
	  * right: server event, boosts, your rank in this server
	  * bottom: auto mine / starter pack (after tutorial)
	Plus toasts, announcements and celebrations (level up, rank up, tutorial).
]]
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
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

local New, C, T = Lib.New, Lib.Colors, Lib.T
local HUD = {}
local player = Players.LocalPlayer

local DARK = Color3.fromRGB(20, 22, 34)

---------------------------------------------------------------------------
-- toasts & announcements
---------------------------------------------------------------------------
local toastCluster = Root.Cluster("Toasts", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 110), UDim2.fromOffset(480, 130), Root.Overlay)
toastCluster.ZIndex = 40
Lib.List(Enum.FillDirection.Vertical, 6).Parent = toastCluster

local toastOrder = 0
function HUD.Toast(text: string, color: Color3?)
	toastOrder += 1
	if color == C.Red then
		Lib.PlaySound("Error")
	end
	local toast = New("Frame", {
		BackgroundColor3 = DARK,
		BackgroundTransparency = 0.15,
		Size = UDim2.fromOffset(470, 36),
		LayoutOrder = toastOrder,
		ZIndex = 40,
		Parent = toastCluster,
	}, { Lib.Corner(12), Lib.Stroke(color or C.Blue, 2, 0.2) })
	Lib.Text({
		Text = text,
		TextColor3 = color or C.Text,
		Size = UDim2.new(1, -16, 1, -8),
		Position = UDim2.fromOffset(8, 4),
		MaxTextSize = 18,
		ZIndex = 41,
		Parent = toast,
	})
	Lib.Pop(toast)
	local toasts = {}
	for _, child in toastCluster:GetChildren() do
		if child:IsA("Frame") then
			table.insert(toasts, child)
		end
	end
	if #toasts > 2 then
		table.sort(toasts, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		toasts[1]:Destroy()
	end
	task.delay(3, function()
		if toast.Parent then
			TweenService:Create(toast, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
			task.wait(0.3)
			toast:Destroy()
		end
	end)
end

local bannerCluster = Root.Cluster("Banner", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 56), UDim2.fromOffset(680, 44))
bannerCluster.ZIndex = 45
local banner = New("Frame", {
	BackgroundColor3 = Color3.fromRGB(15, 15, 25),
	BackgroundTransparency = 0.1,
	Size = UDim2.fromScale(1, 1),
	Visible = false,
	ZIndex = 45,
	Parent = bannerCluster,
}, { Lib.Corner(16), Lib.Stroke(C.Gold, 3, 0) })
local bannerText = Lib.Text({
	Text = "",
	Size = UDim2.new(1, -20, 1, -10),
	Position = UDim2.fromOffset(10, 5),
	MaxTextSize = 22,
	ZIndex = 46,
	Parent = banner,
})
local bannerQueue = {}
local bannerBusy = false

function HUD.Announce(text: string, color: Color3?)
	if #bannerQueue >= 3 then
		table.remove(bannerQueue, 1) -- never fall minutes behind
	end
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
			task.wait(if #bannerQueue > 2 then 2 else 3.2)
		end
		banner.Visible = false
		bannerBusy = false
	end)
end

---------------------------------------------------------------------------
-- objective card (top center, under the meteor timer)
---------------------------------------------------------------------------
local objectiveCluster = Root.Cluster("Objective", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 56), UDim2.fromOffset(430, 42))
local objective = New("Frame", {
	BackgroundColor3 = DARK,
	BackgroundTransparency = 0.1,
	Size = UDim2.fromScale(1, 1),
	Parent = objectiveCluster,
}, { Lib.Corner(14), Lib.Stroke(C.Gold, 2.5, 0) })
local objectiveText =
	Lib.Text({ Text = "", Size = UDim2.new(1, -16, 1, -12), Position = UDim2.fromOffset(8, 3), MaxTextSize = 18, Parent = objective })
local objectiveFill = New("Frame", {
	BackgroundColor3 = C.Gold,
	Size = UDim2.new(0, 0, 0, 5),
	Position = UDim2.new(0, 12, 1, -9),
	Parent = objective,
}, { Lib.Corner(3) })

-- top center stack: meteor timer -> (tutorial objective) -> announcement -> toasts.
-- Offsets don't shrink with the UI scale, so they are recomputed for phones.
local objectiveOnTop = true
local function layoutTop()
	local s = Root.Scale()
	local y = 8 + 48 * s
	objectiveCluster.Position = UDim2.new(0.5, 0, 0, y)
	if objectiveOnTop then
		y += 46 * s
	end
	bannerCluster.Position = UDim2.new(0.5, 0, 0, y)
	-- toasts live in the overlay (it ignores the top bar inset, the rest doesn't)
	local inset = GuiService:GetGuiInset().Y
	toastCluster.Position = UDim2.new(0.5, 0, 0, y + 48 * s + inset)
end
layoutTop()
task.defer(function()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(layoutTop)
	end
end)

---------------------------------------------------------------------------
-- top left: money, level, menu
---------------------------------------------------------------------------
local topLeft = Root.Cluster("TopLeft", Vector2.zero, UDim2.fromOffset(12, 12), UDim2.fromOffset(260, 520))
Lib.List(Enum.FillDirection.Vertical, 5, Enum.HorizontalAlignment.Left).Parent = topLeft

local function pill(order: number, icon: string, color: Color3)
	local frame = New("Frame", {
		BackgroundColor3 = DARK,
		BackgroundTransparency = 0.1,
		Size = UDim2.fromOffset(210, 36),
		LayoutOrder = order,
		Parent = topLeft,
	}, { Lib.Corner(18), Lib.Stroke(color, 2.5, 0) })
	Lib.Text({
		Text = icon,
		Size = UDim2.fromOffset(30, 30),
		Position = UDim2.fromOffset(4, 3),
		MaxTextSize = 26,
		Outline = false,
		Parent = frame,
	})
	local label = Lib.Text({
		Text = "0",
		TextColor3 = color,
		Size = UDim2.new(1, -48, 1, -6),
		Position = UDim2.fromOffset(38, 3),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 24,
		Parent = frame,
	})
	return frame, label
end

local coinPill, coinLabel = pill(1, "💰", C.Coins)
local _, gemLabel = pill(2, "💎", C.Gems)
local dustPill, dustLabel = pill(3, "✨", C.Stardust)

local levelRow = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(210, 24), LayoutOrder = 4, Parent = topLeft })
local levelBadge = Lib.Text({ Text = "Lv.1", TextColor3 = C.Gold, Size = UDim2.fromOffset(54, 24), MaxTextSize = 20, Parent = levelRow })
local _, setLevel =
	Lib.Bar({ Size = UDim2.fromOffset(152, 18), Position = UDim2.fromOffset(56, 3), Color = C.Gold, TextSize = 12, Parent = levelRow })

-- menu that grows as the player progresses (no wall of buttons on day one).
-- Only the main buttons stay on screen; the rest live behind ⋯ MORE.
local menu =
	New("Frame", { Name = "Menu", BackgroundTransparency = 1, Size = UDim2.fromOffset(268, 64), LayoutOrder = 6, Parent = topLeft })
local menuGrid = Lib.Grid(UDim2.fromOffset(62, 62), 6)
menuGrid.HorizontalAlignment = Enum.HorizontalAlignment.Left
menuGrid.Parent = menu
local moreMenu = New("Frame", {
	Name = "MoreMenu",
	BackgroundColor3 = DARK,
	BackgroundTransparency = 0.2,
	Size = UDim2.fromOffset(268, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	LayoutOrder = 7,
	Visible = false,
	Parent = topLeft,
}, { Lib.Corner(14), Lib.Padding(5) })
local moreGrid = Lib.Grid(UDim2.fromOffset(60, 60), 6)
moreGrid.HorizontalAlignment = Enum.HorizontalAlignment.Left
moreGrid.Parent = moreMenu
local PRIMARY = { Shop = true, Pets = true, Rewards = true }

local function tutorialAt(data, step: number): boolean
	return data.Tutorial == nil or data.Tutorial.Done or data.Tutorial.Step >= step
end
local function tutorialDone(data): boolean
	return data.Tutorial == nil or data.Tutorial.Done == true
end

local MENU = {
	{
		"Shop",
		"⛏️",
		"Upgrade",
		C.Gold,
		function(d)
			return tutorialAt(d, 4) -- (step 4+: mine, then buy a pickaxe)
		end,
	},
	{
		"Pets",
		"🐾",
		"Pets",
		C.Green,
		function(d)
			return tutorialAt(d, 4) -- (the first egg hatched at home)
		end,
	},
	{ "Rewards", "🎁", "Rewards", C.Pink, tutorialDone },
	{
		"Pass",
		"🎫",
		"Pass",
		Color3.fromRGB(255, 120, 60),
		function(d)
			return tutorialDone(d) and (d.Level or 1) >= 3
		end,
	},
	{
		"Teleport",
		"🌀",
		"Zones",
		C.Cyan,
		function(d)
			return tutorialDone(d) and d.ZoneLevel >= 2
		end,
	},
	{
		"Rebirth",
		"♻️",
		"Rebirth",
		C.Purple,
		function(d, derived)
			return d.Rebirths > 0 or d.Coins >= (derived.RebirthCost or math.huge) * 0.5
		end,
	},
	{ "Houses", "🏘️", "Houses", Color3.fromRGB(255, 130, 170), tutorialDone },
	{
		"Titles",
		"👑",
		"Titles",
		Color3.fromRGB(230, 170, 40),
		function(d)
			-- only once there is something to choose
			local unlocked = 0
			for _, title in Config.Titles do
				if Util.TitleUnlocked(Config, title, d, State.HasPass) then
					unlocked += 1
				end
			end
			return tutorialDone(d) and unlocked >= 2
		end,
	},
	{ "Store", "🛒", "Store", Color3.fromRGB(60, 200, 110), tutorialDone },
	{
		"Settings",
		"⚙️",
		"Settings",
		C.Gray,
		function()
			return true
		end,
	},
}
local menuButtons = {}
local badges = {}
table.insert(MENU, {
	"More",
	"⋯",
	"More",
	Color3.fromRGB(90, 95, 120),
	function()
		return true -- (Settings lives in here, needed from the first minute)
	end,
})
for order, item in MENU do
	local button = New("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = item[4],
		LayoutOrder = if item[1] == "More" then 99 else order,
		Visible = false,
		Parent = if PRIMARY[item[1]] or item[1] == "More" then menu else moreMenu,
	}, { Lib.Corner(14), Lib.Stroke(Color3.new(0, 0, 0), 2.5, 0.25), Lib.Gradient(Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 170)) })
	Lib.Text({
		Text = item[2],
		Size = UDim2.new(1, 0, 0.6, 0),
		Position = UDim2.fromScale(0, 0.04),
		MaxTextSize = 32,
		Outline = false,
		Parent = button,
	})
	Lib.Text({ Text = item[3], Size = UDim2.new(1, -4, 0.3, 0), Position = UDim2.fromScale(0.02, 0.66), MaxTextSize = 14, Parent = button })
	local badge = New("Frame", {
		BackgroundColor3 = C.Red,
		Size = UDim2.fromOffset(20, 20),
		Position = UDim2.new(1, -13, 0, -7),
		Visible = false,
		ZIndex = 3,
		Parent = button,
	}, { Lib.Corner(10), Lib.Stroke(Color3.new(1, 1, 1), 2, 0) })
	Lib.Text({ Text = "!", Size = UDim2.fromScale(1, 1), MaxTextSize = 16, ZIndex = 4, Parent = badge })
	badges[item[1]] = badge
	menuButtons[item[1]] = button
	local scale = New("UIScale", { Parent = button })
	button.Activated:Connect(function()
		scale.Scale = 0.9
		TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		Lib.PlaySound("UI")
		if item[1] == "More" then
			moreMenu.Visible = not moreMenu.Visible
			return
		end
		moreMenu.Visible = false
		Panels.Toggle(item[1])
	end)
end

---------------------------------------------------------------------------
-- right side: event, boosts, server rank
---------------------------------------------------------------------------
local right = Root.Cluster("RightColumn", Vector2.new(1, 0), UDim2.new(1, -12, 0, 60), UDim2.fromOffset(250, 520))
HUD.RightColumn = right -- MeteorUI adds its live ranking here
Lib.List(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Right).Parent = right
-- 🎉 party countdown (weekly party / admin event)
local partyChip = New("Frame", {
	BackgroundColor3 = DARK,
	BackgroundTransparency = 0.12,
	Size = UDim2.fromOffset(240, 30),
	LayoutOrder = -2,
	Visible = false,
	Parent = right,
}, { Lib.Corner(12), Lib.Stroke(Color3.fromRGB(255, 200, 80), 2.5, 0) })
local partyText = Lib.Text({
	Text = "",
	TextColor3 = Color3.fromRGB(255, 210, 100),
	Size = UDim2.new(1, -12, 1, -4),
	Position = UDim2.fromOffset(6, 2),
	MaxTextSize = 16,
	Parent = partyChip,
})
task.spawn(function()
	while true do
		task.wait(1)
		local left = (workspace:GetAttribute("PartyEnd") or 0) - State.Now()
		partyChip.Visible = left > 0
		if left > 0 then
			partyText.Text = T("🎉 PARTY %s  •  🍀 + 2x luck", Util.FormatTime(left))
		end
	end
end)

-- after the tutorial the objective is a small card here (not in the middle)
local objectiveSlot = New("Frame", {
	Name = "ObjectiveSlot",
	BackgroundTransparency = 1,
	Size = UDim2.fromOffset(240, 46),
	LayoutOrder = -1,
	Parent = right,
})

local function chip(order: number, height: number, strokeColor: Color3)
	return New("Frame", {
		BackgroundColor3 = DARK,
		BackgroundTransparency = 0.12,
		Size = UDim2.fromOffset(240, height),
		LayoutOrder = order,
		Visible = false,
		Parent = right,
	}, { Lib.Corner(12), Lib.Stroke(strokeColor, 2.5, 0) })
end

local eventChip = chip(0, 52, C.Gold)
local eventTitle =
	Lib.Text({ Text = "", Size = UDim2.new(1, -12, 0, 24), Position = UDim2.fromOffset(6, 3), MaxTextSize = 19, Parent = eventChip })
local eventDesc = Lib.Text({
	Text = "",
	Font = Lib.BodyFont,
	TextColor3 = C.Sub,
	Size = UDim2.new(1, -12, 0, 18),
	Position = UDim2.fromOffset(6, 29),
	MaxTextSize = 13,
	Parent = eventChip,
})

local rankChip = chip(5, 48, Color3.fromRGB(255, 215, 80))
local rankTitle = Lib.Text({
	Text = "",
	TextColor3 = C.Gold,
	Size = UDim2.new(1, -12, 0, 23),
	Position = UDim2.fromOffset(6, 3),
	MaxTextSize = 18,
	Parent = rankChip,
})
local rankSub = Lib.Text({
	Text = "",
	Font = Lib.BodyFont,
	TextColor3 = C.Sub,
	Size = UDim2.new(1, -12, 0, 17),
	Position = UDim2.fromOffset(6, 27),
	MaxTextSize = 13,
	Parent = rankChip,
})

-- base chip: income per second + bank; tap to go home
local baseChip = chip(6, 48, Color3.fromRGB(120, 230, 255))
local baseTitle = Lib.Text({
	Text = "",
	TextColor3 = Color3.fromRGB(140, 235, 255),
	Size = UDim2.new(1, -12, 0, 23),
	Position = UDim2.fromOffset(6, 3),
	MaxTextSize = 18,
	Parent = baseChip,
})
local baseSub = Lib.Text({
	Text = "",
	Font = Lib.BodyFont,
	TextColor3 = C.Sub,
	Size = UDim2.new(1, -12, 0, 17),
	Position = UDim2.fromOffset(6, 27),
	MaxTextSize = 13,
	Parent = baseChip,
})
local baseButton = New("TextButton", {
	BackgroundTransparency = 1,
	Text = "",
	Size = UDim2.fromScale(1, 1),
	ZIndex = 5,
	Parent = baseChip,
})
baseButton.Activated:Connect(function()
	Lib.PlaySound("UI")
	Net.Fire("GoBase")
end)
-- is my house safe right now? (shown under the base chip)
local function protectionText(): (string, Color3)
	local protection = player:GetAttribute("BaseProtection") or ""
	local t = State.Now()
	if protection == "locked" then
		return T("🔒 Locked %s", Util.FormatTime(math.max(0, (player:GetAttribute("LockedUntil") or 0) - t))),
			Color3.fromRGB(255, 150, 150)
	elseif protection == "newbie" then
		return T("🛡️ Newbie shield %s", Util.FormatTime(player:GetAttribute("NewbieShield") or 0)), Color3.fromRGB(140, 200, 255)
	elseif protection == "shield" then
		return T("🛡️ Protected %s", Util.FormatTime(math.max(0, (player:GetAttribute("ShieldUntil") or 0) - t))),
			Color3.fromRGB(140, 200, 255)
	elseif protection == "robbing" then
		return T("🚨 Being robbed! Bonk the thief!"), C.Red
	elseif protection == "safe" then
		local raidAt = workspace:GetAttribute("RaidAt") or 0
		if raidAt > t then
			return T("🌙 Thief Night in %ds - vault your best pets!", math.ceil(raidAt - t)), Color3.fromRGB(200, 170, 255)
		end
		return T("🏠 Safe - raids only on 🌙 Thief Night"), Color3.fromRGB(150, 230, 160)
	end
	return T("🌙 Thief Night! 🔒 vault pets are safe"), Color3.fromRGB(200, 170, 255)
end

local function refreshBaseChip()
	local data = State.Data
	local hasBase = player:GetAttribute("BaseIndex") ~= nil
	baseChip.Visible = hasBase and data ~= nil and (data.Tutorial == nil or data.Tutorial.Done == true)
	if baseChip.Visible then
		baseTitle.Text = T(
			"🏠 %s/s  •  Bank 💰%s",
			Util.Format(player:GetAttribute("BaseRate") or 0),
			Util.Format(player:GetAttribute("BaseBank") or 0)
		)
		local text, color = protectionText()
		baseSub.Text = text
		baseSub.TextColor3 = color
	end
end
player:GetAttributeChangedSignal("BaseBank"):Connect(refreshBaseChip)
player:GetAttributeChangedSignal("BaseIndex"):Connect(refreshBaseChip)
player:GetAttributeChangedSignal("BaseProtection"):Connect(refreshBaseChip)
State.OnChanged(refreshBaseChip)

-- revenge: 5 minutes to raid the thief's house (tap to go there)
local revengeChip = chip(7, 48, Color3.fromRGB(255, 200, 60))
local revengeTitle = Lib.Text({
	Text = "",
	TextColor3 = Color3.fromRGB(255, 210, 90),
	Size = UDim2.new(1, -12, 0, 23),
	Position = UDim2.fromOffset(6, 3),
	MaxTextSize = 18,
	Parent = revengeChip,
})
local revengeSub = Lib.Text({
	Text = "",
	Font = Lib.BodyFont,
	TextColor3 = C.Sub,
	Size = UDim2.new(1, -12, 0, 17),
	Position = UDim2.fromOffset(6, 27),
	MaxTextSize = 13,
	Parent = revengeChip,
})
local revengeButton =
	New("TextButton", { BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = revengeChip })
revengeButton.Activated:Connect(function()
	local target = player:GetAttribute("RevengeTarget")
	if type(target) == "number" then
		Lib.PlaySound("UI")
		Net.Fire("VisitBase", target)
	end
end)
-- a bounty on me: everyone can bonk me for coins
local bountyChip = chip(8, 30, C.Red)
local bountyText = Lib.Text({
	Text = "",
	TextColor3 = Color3.fromRGB(255, 140, 120),
	Size = UDim2.new(1, -12, 1, -4),
	Position = UDim2.fromOffset(6, 2),
	MaxTextSize = 16,
	Parent = bountyChip,
})
local revengeName = ""
Net.On("Revenge", function(_userId, name)
	revengeName = tostring(name)
	Lib.PlaySound("Event")
end)
task.spawn(function()
	while true do
		task.wait(1)
		local untilTime = player:GetAttribute("RevengeUntil")
		local left = if type(untilTime) == "number" then untilTime - State.Now() else 0
		revengeChip.Visible = left > 0
		if left > 0 then
			revengeTitle.Text = T("🎯 REVENGE on %s", revengeName)
			revengeSub.Text = T("%s left - locks can't stop you • tap to go", Util.FormatTime(left))
		end
		local bounty = player:GetAttribute("Bounty")
		bountyChip.Visible = type(bounty) == "number" and bounty > 0
		if bountyChip.Visible then
			bountyText.Text = T("💰 Bounty on you: %s - don't get bonked!", Util.Format(bounty))
		end
		if baseChip.Visible then
			refreshBaseChip()
		end
	end
end)

local boostRows = {}
local BOOSTS = {
	{ "Coins2x", "2x💰", C.Coins },
	{ "Luck2x", "2x🍀", C.Green },
	{ "Power2x", "2x💥", C.Red },
	{ "ServerLuck", "🌟", C.Gold },
}
for order, def in BOOSTS do
	local row = chip(order, 30, def[3])
	local label = Lib.Text({
		Text = "",
		TextColor3 = def[3],
		Size = UDim2.new(1, -12, 1, -6),
		Position = UDim2.fromOffset(6, 3),
		MaxTextSize = 17,
		Parent = row,
	})
	boostRows[def[1]] = { Row = row, Label = label, Name = def[2] }
end

---------------------------------------------------------------------------
-- bottom: auto mine, starter pack
---------------------------------------------------------------------------
local bottom = Root.Cluster("Bottom", Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -12), UDim2.fromOffset(640, 116))
local bottomRow = New(
	"Frame",
	{ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 50), Position = UDim2.new(0, 0, 1, -50), Parent = bottom },
	{
		Lib.List(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
	}
)
local autoButton = Lib.Button({
	Size = UDim2.fromOffset(190, 46),
	Color = C.Gray,
	LayoutOrder = 1,
	TextSize = 20,
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
	Size = UDim2.fromOffset(230, 46),
	Color = C.Pink,
	LayoutOrder = 2,
	TextSize = 20,
	Parent = bottomRow,
	OnClick = function()
		Upsell.Product("StarterPack", true)
	end,
})
---------------------------------------------------------------------------
-- objective logic
---------------------------------------------------------------------------
-- ☄️ what the meteor of this round wants from us (nil when there is none)
local function meteorGoal(data): string?
	local state = workspace:GetAttribute("MeteorState")
	local site = workspace:GetAttribute("MeteorSiteZone") or 0
	local siteName = workspace:GetAttribute("MeteorSite") or ""
	local kind = workspace:GetAttribute("MeteorKind") or ""
	if state == "Warning" or state == "Falling" then
		if site > data.ZoneLevel then
			return T("☄️ A %s is falling on %s (locked for you) - mine and get ready!", kind, siteName)
		end
		return T("☄️ A %s is falling on %s - run there!", kind, siteName)
	elseif state == "Active" and site <= data.ZoneLevel then
		return T("☄️ Smash the meteor with everyone - top 3 get the best egg!")
	end
	return nil
end

local function nextGoal(data, derived): string
	if player:GetAttribute("Carrying") then
		return T("Run home 🏠 with the egg - don't get bonked!")
	end
	local meteor = meteorGoal(data)
	if meteor then
		return meteor
	end
	-- a star egg on the ground we can reach?
	local map = workspace:FindFirstChild("Map")
	local stars = map and map:FindFirstChild("Shards")
	if stars then
		for _, model in stars:GetChildren() do
			local hitbox = model:FindFirstChild("Hitbox")
			local zone = hitbox and hitbox:IsA("BasePart") and Util.ZoneAt(Config, hitbox.Position)
			if zone and zone <= data.ZoneLevel and model:GetAttribute("Stolen") ~= true then
				return T("Grab a star egg 🥚 - carry it home and it hatches!")
			end
		end
	end
	local pets = #data.Pets
	if pets == 0 then
		return T("Wait for the next meteor ☄️ - its star eggs become your pets!")
	end
	local bank = player:GetAttribute("BaseBank") or 0
	if bank >= math.max(100, data.Coins * 0.25) then
		return T("Collect 💰%s at your base 🏠", Util.Format(bank))
	end
	local pedestals = 0
	for _, item in data.Base and data.Base.Items or {} do
		local def = Config.Decor[item.Id]
		if def and (def.Function == "Pedestal" or def.Function == "Vault") then
			pedestals += 1
		end
	end
	if pets < pedestals and data.Coins >= Config.Eggs.Meadow.Price then
		return T("You have empty pedestals - hatch more pets 🥚")
	end
	local pick = Config.Pickaxes[data.PickaxeTier + 1]
	local zone = Config.Zones[data.ZoneLevel + 1]
	if data.Coins >= (derived.RebirthCost or math.huge) then
		return T("You can REBIRTH for a permanent coin boost!")
	end
	if zone and data.Coins >= zone.Cost then
		return T("Unlock %s at the gate!", zone.Name)
	end
	if pick and data.Coins >= pick.Cost then
		return T("Buy the %s!", pick.Name)
	end
	local cheapest = math.huge
	for _, cost in { pick and pick.Cost, zone and zone.Cost } do
		if cost then
			cheapest = math.min(cheapest, cost)
		end
	end
	if cheapest < math.huge then
		return T("Mine until the next meteor: %s / %s coins for an upgrade", Util.Format(data.Coins), Util.Format(cheapest))
	end
	return T("Climb the weekly ☄️ meteor hunter leaderboard!")
end

-- returns text, progress (0-1 or nil)
local function currentObjective(data, derived)
	local tutorial = data.Tutorial
	if tutorial and not tutorial.Done then
		local steps = Config.Tutorial.Steps
		local step = steps[tutorial.Step]
		if step then
			local text = T(step.Text)
			local progress = tutorial.Progress / step.Target
			if step.Id == "Mine" then
				text = string.format("%s  (%d/%d)", text, tutorial.Progress, step.Target)
			elseif step.Id == "Pickaxe" and data.Coins < Config.Pickaxes[2].Cost then
				text = T("Mine ore until you have %s coins", Util.Format(Config.Pickaxes[2].Cost))
				progress = data.Coins / Config.Pickaxes[2].Cost
			elseif step.Id == "Hatch" and data.Coins < Config.Eggs.Meadow.Price then
				text = T("Mine ore until you have %s coins", Util.Format(Config.Eggs.Meadow.Price))
				progress = data.Coins / Config.Eggs.Meadow.Price
			elseif step.Id == "Shard" and player:GetAttribute("Carrying") then
				text = T("Run home 🏠 with the egg - don't get bonked!")
			elseif step.Id == "Mine" or step.Id == "Pickaxe" then
				-- a real meteor beats the tutorial: go join it
				local meteor = meteorGoal(data)
				if meteor then
					return "🎯 " .. meteor, nil
				end
			end
			return string.format("📘 %d/%d  %s", tutorial.Step, #steps, text), progress
		end
	end
	return "🎯 " .. nextGoal(data, derived), nil
end
HUD.CurrentObjective = currentObjective

---------------------------------------------------------------------------
-- badge helpers
---------------------------------------------------------------------------
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

function HUD.RewardsReady()
	local data, derived = State.Data, State.Derived
	if not data or not derived then
		return {}
	end
	return {
		Quests = anyQuestClaimable(data),
		Gifts = anyGiftClaimable(derived),
		Spin = (data.FreeSpinAt or 0) <= State.Now(),
	}
end

---------------------------------------------------------------------------
-- refresh
---------------------------------------------------------------------------
local lastCoins = nil
local coinValue = Instance.new("NumberValue")
coinValue.Changed:Connect(function(value)
	coinLabel.Text = Util.Format(math.floor(value))
end)
local eventDefs = {}
for _, def in Config.Events.List do
	eventDefs[def.Id] = def
end
local revealed = {}
local firstRefresh = true

function HUD.Refresh()
	local data, derived = State.Data, State.Derived
	if not data then
		return
	end
	-- money (numbers roll up instead of jumping)
	if lastCoins == nil then
		coinValue.Value = data.Coins
	elseif data.Coins ~= lastCoins then
		TweenService:Create(coinValue, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = data.Coins }):Play()
		if data.Coins > lastCoins then
			Lib.Pop(coinPill)
		end
	end
	lastCoins = data.Coins
	gemLabel.Text = Util.Format(data.Gems)
	dustLabel.Text = Util.Format(data.Stardust)
	dustPill.Visible = data.Stardust > 0

	local need = derived.XPNeeded or 1
	levelBadge.Text = "Lv." .. (data.Level or 1)
	setLevel((data.XP or 0) / need, string.format("%s / %s XP", Util.Format(data.XP or 0), Util.Format(need)))

	-- objective
	local text, progress = currentObjective(data, derived)
	if objectiveText.Text ~= text and not firstRefresh then
		Lib.Pop(objective)
	end
	objectiveText.Text = text
	objectiveFill.Visible = progress ~= nil
	if progress then
		objectiveFill.Size = UDim2.new(math.clamp(progress, 0, 1), -24, 0, 5)
	end

	-- menu reveal
	for _, item in MENU do
		local id = item[1]
		local show = item[5](data, derived) == true
		local button = menuButtons[id]
		if show and not revealed[id] then
			revealed[id] = true
			button.Visible = true
			if not firstRefresh then
				Lib.Pop(button)
				HUD.Toast(T("New menu unlocked: %s", item[3]), C.Gold)
			end
		elseif not show and revealed[id] then
			revealed[id] = nil
			button.Visible = false
		end
	end
	firstRefresh = false
	local ready = HUD.RewardsReady()
	badges.Rewards.Visible = ready.Quests or ready.Gifts or ready.Spin
	badges.Pass.Visible = anyTierClaimable(data)
	badges.Rebirth.Visible = data.Coins >= (derived.RebirthCost or math.huge)
	local hiddenBadge = false
	for id, badge in badges do
		if not PRIMARY[id] and id ~= "More" and badge.Visible and menuButtons[id].Visible then
			hiddenBadge = true
		end
	end
	badges.More.Visible = hiddenBadge and not moreMenu.Visible
	-- the objective moves out of the way once the tutorial is done
	local onTop = not tutorialDone(data)
	if onTop ~= objectiveOnTop then
		objectiveOnTop = onTop
		objective.Parent = if onTop then objectiveCluster else objectiveSlot
		layoutTop()
	end
	objectiveSlot.Visible = not onTop

	-- server event chip
	local eventId = workspace:GetAttribute("EventId")
	local eventDef = type(eventId) == "string" and eventDefs[eventId]
	local eventLeft = (workspace:GetAttribute("EventEnd") or 0) - State.Now()
	eventChip.Visible = eventDef ~= nil and eventLeft > 0
	if eventChip.Visible and eventDef then
		eventTitle.Text = T(eventDef.Name) .. "  " .. Util.FormatTime(eventLeft)
		eventTitle.TextColor3 = eventDef.Color
		eventDesc.Text = T(eventDef.Description)
		eventChip:FindFirstChildOfClass("UIStroke").Color = eventDef.Color
	end

	-- rank in this server
	local sr = derived.ServerRank
	rankChip.Visible = type(sr) == "table" and (sr.Count or 0) >= 2
	if rankChip.Visible then
		rankTitle.Text = T("🏆 #%d of %d in server", sr.Place, sr.Count)
		rankSub.Text = if sr.NextName
			then T("+%s pts to pass %s", Util.Comma(sr.NextGap or 0), sr.NextName)
			else T("You're #1 here - defend it!")
	end

	for key, row in boostRows do
		local remaining
		if key == "ServerLuck" then
			remaining = (workspace:GetAttribute("Server_ServerLuck") or 0) - State.Now()
		else
			remaining = State.BoostRemaining(key)
		end
		row.Row.Visible = remaining > 0
		if remaining > 0 then
			local name = if key == "ServerLuck" then T("🌟 Server Luck") else row.Name
			row.Label.Text = name .. "  " .. Util.FormatTime(remaining)
		end
	end

	-- bottom buttons only after the tutorial
	local done = tutorialDone(data)
	autoButton.Visible = done and State.HasPass("AutoMine")
	if State.HasPass("AutoMine") then
		Lib.SetButton(autoButton, if State.AutoMine then "🤖 AUTO: ON" else "🤖 AUTO: OFF", if State.AutoMine then C.Green else C.Gray)
	else
		Lib.SetButton(autoButton, "🤖 AUTO 🔒", C.Gray)
	end
	local remainingOffer = data.FirstJoin + Config.StarterPack.OfferHours * 3600 - State.Now()
	starterButton.Visible = done and not data.Flags.StarterPack and remainingOffer > 0
	if starterButton.Visible then
		Lib.SetButton(starterButton, "🎁 " .. T("STARTER PACK") .. " " .. Util.FormatTime(remainingOffer), C.Pink)
	end
end

---------------------------------------------------------------------------
-- effects
---------------------------------------------------------------------------
local function flyCoins(amount: number)
	local inset = GuiService:GetGuiInset()
	local target = coinPill.AbsolutePosition + coinPill.AbsoluteSize / 2 + inset
	local camera = workspace.CurrentCamera
	local center = if camera then camera.ViewportSize / 2 else Vector2.new(640, 380)
	local n = math.clamp(math.floor(math.log10(math.max(10, amount)) * 2), 3, 12)
	for i = 1, n do
		local icon = Lib.Text({
			Text = "💰",
			Size = UDim2.fromOffset(34, 34),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(center.X + math.random(-80, 80), center.Y + math.random(-60, 60)),
			MaxTextSize = 30,
			Outline = false,
			ZIndex = 60,
			Parent = Root.Overlay,
		})
		task.delay(i * 0.04, function()
			local tween = TweenService:Create(icon, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.fromOffset(target.X, target.Y),
			})
			tween:Play()
			tween.Completed:Once(function()
				icon:Destroy()
				Lib.PlaySound("Coin", 0.35, i * 0.04)
			end)
		end)
	end
end

local function confetti()
	local camera = workspace.CurrentCamera
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 760)
	local colors = { C.Gold, C.Pink, C.Cyan, C.Green, C.Purple }
	for _ = 1, 36 do
		local piece = New("Frame", {
			BackgroundColor3 = colors[math.random(1, #colors)],
			Size = UDim2.fromOffset(math.random(8, 14), math.random(14, 22)),
			Position = UDim2.fromOffset(size.X / 2, size.Y * 0.4),
			Rotation = math.random(0, 360),
			ZIndex = 70,
			Parent = Root.Overlay,
		}, { Lib.Corner(3) })
		TweenService:Create(piece, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(size.X / 2 + math.random(-450, 450), size.Y * 0.4 + math.random(-250, 350)),
			Rotation = piece.Rotation + math.random(-360, 360),
			BackgroundTransparency = 1,
		}):Play()
		task.delay(1.5, function()
			piece:Destroy()
		end)
	end
end

local celebration = Root.Cluster("Celebration", Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.36), UDim2.fromOffset(560, 120), Root.Overlay)
local celebrationTitle =
	Lib.Text({ Text = "", TextColor3 = C.Gold, Size = UDim2.fromScale(1, 0.62), MaxTextSize = 60, Visible = false, Parent = celebration })
local celebrationSub = Lib.Text({
	Text = "",
	Size = UDim2.fromScale(1, 0.34),
	Position = UDim2.fromScale(0, 0.64),
	MaxTextSize = 28,
	Visible = false,
	Parent = celebration,
})
local celebrationToken = 0
local function celebrate(title: string, sub: string, color: Color3, withConfetti: boolean?)
	celebrationToken += 1
	local token = celebrationToken
	celebrationTitle.Text = title
	celebrationTitle.TextColor3 = color
	celebrationSub.Text = sub
	celebrationTitle.Visible = true
	celebrationSub.Visible = true
	Lib.Pop(celebrationTitle)
	if withConfetti ~= false then
		confetti()
	end
	task.delay(2.4, function()
		if token == celebrationToken then
			celebrationTitle.Visible = false
			celebrationSub.Visible = false
		end
	end)
end
HUD.Celebrate = celebrate

-- new pets fly into the 🐾 Pets button (+N badge until you open it), with a
-- one-line summary of where they went
State.NewPets = State.NewPets or {} -- [petId] = true (NEW tags in the Pets panel)
local newPetCount = 0
local petsBadgeText = badges.Pets and badges.Pets:FindFirstChildWhichIsA("TextLabel")
local function refreshPetsBadge()
	if badges.Pets then
		badges.Pets.Visible = newPetCount > 0
		if petsBadgeText then
			petsBadgeText.Text = if newPetCount > 9 then "9+" else tostring(newPetCount)
		end
	end
end
local PLACE_ICONS = { Vault = "🔒", Display = "🏠", Storage = "📦", Sold = "💰" }
function HUD.PetsLanded(entries)
	local button = menuButtons.Pets
	local targetGui = if button and button.Visible then button else coinPill
	local inset = GuiService:GetGuiInset()
	local target = targetGui.AbsolutePosition + targetGui.AbsoluteSize / 2 + inset
	local camera = workspace.CurrentCamera
	local center = if camera then camera.ViewportSize / 2 else Vector2.new(640, 380)
	local counts = { Vault = 0, Display = 0, Storage = 0, Sold = 0 }
	for i, entry in entries do
		local where = entry.Where or "Storage"
		counts[where] = (counts[where] or 0) + 1
		if entry.Id and where ~= "Sold" then
			State.NewPets[entry.Id] = true
		end
		local icon = Lib.Text({
			Text = PLACE_ICONS[where] or "🐾",
			Size = UDim2.fromOffset(46, 46),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(center.X + (i - (#entries + 1) / 2) * 70, center.Y),
			MaxTextSize = 40,
			Outline = false,
			ZIndex = 60,
			Parent = Root.Overlay,
		})
		task.delay((i - 1) * 0.12, function()
			Lib.PlaySound("Fly", 0.8, (i - 1) * 0.05)
			local tween = TweenService:Create(icon, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.fromOffset(target.X, target.Y),
				Size = UDim2.fromOffset(20, 20),
			})
			tween:Play()
			tween.Completed:Once(function()
				icon:Destroy()
				Lib.PlaySound(if where == "Sold" then "CoinBig" else "Store", 0.8)
				Lib.Pop(targetGui)
				if where ~= "Sold" then
					newPetCount += 1
					refreshPetsBadge()
				end
			end)
		end)
	end
	-- "where did they go?" in one short line
	local parts = {}
	if counts.Vault > 0 then
		table.insert(parts, T("🔒 vault %d", counts.Vault))
	end
	if counts.Display > 0 then
		table.insert(parts, T("🏠 display %d", counts.Display))
	end
	if counts.Storage > 0 then
		table.insert(parts, T("📦 storage %d", counts.Storage))
	end
	if counts.Sold > 0 then
		table.insert(parts, T("💰 sold %d", counts.Sold))
	end
	if #parts > 0 then
		HUD.Toast(T("🐾 Your new pets: %s", table.concat(parts, "  •  ")), Color3.fromRGB(150, 230, 160))
	end
end
-- opening the Pets panel clears the +N badge (NEW tags clear when it closes)
task.spawn(function()
	local wasOpen = false
	while true do
		task.wait(0.5)
		local open = Panels.Current == "Pets"
		if open and newPetCount > 0 then
			newPetCount = 0
			refreshPetsBadge()
		end
		if wasOpen and not open then
			State.NewPets = {}
		end
		wasOpen = open
	end
end)
HUD.FlyCoins = flyCoins

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
	Lib.PlaySound("Reward")
end)
-- coins granted all at once (coin crate purchase)
Net.On("Sold", function(coins)
	Lib.PlaySound("Coin")
	flyCoins(coins)
end)
-- egg shops restocked (the banner comes from the server announcement)
Net.On("Restock", function()
	Lib.PlaySound("Event", 0.6)
	if Panels.Current == "Egg" then
		Panels.RefreshCurrent()
	end
end)
Net.On("LevelUp", function(level, gems)
	Lib.PlaySound("LevelUp")
	celebrate(T("⭐ LEVEL %s!", tostring(level)), T("+%s 💎  •  +2%% coins forever", tostring(gems)), C.Gold)
end)
Net.On("RankUp", function(rankName)
	Lib.PlaySound("RankUp")
	celebrate(T("🏅 %s RANK!", tostring(rankName)), T("Weekly ranked - keep climbing!"), C.Cyan)
end)
Net.On("TutorialStep", function(_, rewardText)
	Lib.PlaySound("Reward")
	local text = tostring(rewardText or "")
	celebrate(T("✅ Step complete!"), if text ~= "" then "+" .. text else "", C.Green, false)
end)
Net.On("TutorialDone", function(rewardText)
	Lib.PlaySound("Legendary")
	celebrate(T("🎉 Tutorial complete!"), "+" .. tostring(rewardText), C.Gold)
	HUD.Toast(T("All menus unlocked - have fun!"), C.Gold)
end)
Net.On("EventStarted", function()
	Lib.PlaySound("Event")
end)
Net.On("Rebirthed", function(count, gems)
	HUD.Announce(T("♻️ REBIRTH %s!  +%s 💎", tostring(count), Util.Format(gems)), C.Purple)
end)
Net.On("ZoneUnlocked", function(index)
	local zone = Config.Zones[index]
	if zone then
		HUD.Announce(T("🔓 %s unlocked!", zone.Name), zone.Accent)
	end
end)
Net.On("OpenPanel", function(panel, arg)
	if panel == "Daily" then
		local data = State.Data
		if data and tutorialDone(data) then
			HUD.Toast(T("🎁 Your daily reward is ready - tap 🎁 Rewards!"), C.Gold)
		end
	else
		Panels.Open(panel, arg)
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
Panels.Provide("HUD", HUD)

return HUD
