--[[
	Trading glue: incoming request popup + keeps the live trade state for
	the Trade panel (UI/Panels/Trade.luau). The server does all the checks.
]]
local Client = script.Parent.Parent
local Net = require(Client.Net)
local Lib = require(Client.UI.Lib)
local Root = require(Client.UI.Root)
local Panels = require(Client.UI.Panels)

local New, C, T = Lib.New, Lib.Colors, Lib.T
local TradeUI = { State = nil }

-- request popup ------------------------------------------------------------
local cluster = Root.Cluster("TradeRequest", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 120), UDim2.fromOffset(440, 130), Root.Overlay)
local popup = New("Frame", {
	BackgroundColor3 = C.Panel,
	Size = UDim2.fromScale(1, 1),
	Visible = false,
	Parent = cluster,
}, { Lib.Corner(16), Lib.Stroke(C.Cyan, 3, 0) })
local popupText = Lib.Text({
	Text = "",
	Size = UDim2.new(1, -20, 0, 44),
	Position = UDim2.fromOffset(10, 8),
	MaxTextSize = 24,
	Parent = popup,
})
local requestFrom = nil
local requestToken = 0
local function hidePopup()
	popup.Visible = false
	requestFrom = nil
end
Lib.Button({
	Text = "✅ Accept",
	Color = C.Green,
	Size = UDim2.fromOffset(190, 54),
	Position = UDim2.new(0.5, -200, 1, -66),
	TextSize = 22,
	Parent = popup,
	OnClick = function()
		if requestFrom then
			Net.Fire("TradeRespond", true)
		end
		hidePopup()
	end,
})
Lib.Button({
	Text = "X Decline",
	Color = C.Red,
	Size = UDim2.fromOffset(190, 54),
	Position = UDim2.new(0.5, 10, 1, -66),
	TextSize = 22,
	Parent = popup,
	OnClick = function()
		if requestFrom then
			Net.Fire("TradeRespond", false)
		end
		hidePopup()
	end,
})

Net.On("TradeRequested", function(userId, name)
	requestFrom = userId
	requestToken += 1
	local token = requestToken
	popupText.Text = T("🤝 %s wants to trade!", tostring(name))
	popup.Visible = true
	Lib.Pop(popup)
	Lib.PlaySound("Reward")
	task.delay(20, function()
		if token == requestToken then
			hidePopup()
		end
	end)
end)

-- live trade ---------------------------------------------------------------------
Net.On("TradeState", function(state)
	TradeUI.State = state
	if Panels.Current == "Trade" then
		Panels.RefreshCurrent()
	else
		Panels.Open("Trade")
	end
end)

Net.On("TradeClosed", function(reason)
	TradeUI.State = nil
	if Panels.Current == "Trade" then
		Panels.Close()
	end
	local hud = TradeUI.HUD
	if hud and type(reason) == "string" then
		hud.Toast(reason, C.Red)
	end
end)

Net.On("TradeDone", function(partner)
	Lib.PlaySound("Legendary")
	local hud = TradeUI.HUD
	if hud and hud.Celebrate then
		hud.Celebrate(T("🤝 TRADE COMPLETE!"), T("with %s", tostring(partner)), C.Cyan, true)
	end
end)

Panels.Provide("TradeUI", TradeUI)

return TradeUI
