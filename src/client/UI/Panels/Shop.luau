-- Pickaxe + running-speed upgrades (coins sink, sequential tiers)
local Shop = { Title = "⛏️ UPGRADES", Color = Color3.fromRGB(255, 160, 50) }

function Shop.Build(content, ctx)
	local Lib, State, Net, Config, Util = ctx.Lib, ctx.State, ctx.Net, ctx.Config, ctx.Util
	local New, C = Lib.New, Lib.Colors
	local T = Lib.T
	local tab = "Pickaxes"

	local tabs = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), Parent = content }, {
		Lib.List(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Left),
	})
	local scroll = Lib.Scroll({ Position = UDim2.fromOffset(0, 52), Size = UDim2.new(1, 0, 1, -52), Parent = content })
	Lib.List(Enum.FillDirection.Vertical, 8).Parent = scroll
	Lib.Padding(4).Parent = scroll

	local rows = {}
	local refresh

	local tabButtons = {}
	local TABS = {
		Pickaxes = { Label = "⛏️ Pickaxes", Field = "PickaxeTier", Buy = "BuyPickaxe", Icon = "⛏️" },
		Boots = { Label = "👟 Speed", Field = "SpeedTier", Buy = "BuyBoots", Icon = "👟" },
	}
	for i, name in { "Pickaxes", "Boots" } do
		local button = Lib.Button({
			Text = TABS[name].Label,
			Color = C.Blue,
			Size = UDim2.fromOffset(170, 40),
			LayoutOrder = i,
			Parent = tabs,
			OnClick = function()
				tab = name
				refresh()
			end,
		})
		tabButtons[name] = button
	end

	local function buildRows()
		Lib.Clear(scroll)
		rows = {}
		local list = Config[tab]
		for tier, item in list do
			local row = New("Frame", {
				Size = UDim2.new(1, -12, 0, 64),
				BackgroundColor3 = C.Card,
				LayoutOrder = tier,
				Parent = scroll,
			}, { Lib.Corner(12) })
			local swatch = New("Frame", {
				Size = UDim2.fromOffset(44, 44),
				Position = UDim2.fromOffset(10, 10),
				BackgroundColor3 = item.Color or Color3.fromRGB(150, 110, 70),
				Parent = row,
			}, { Lib.Corner(10), Lib.Stroke(Color3.new(0, 0, 0), 2, 0.4) })
			Lib.Text({
				Text = TABS[tab].Icon,
				Size = UDim2.fromScale(0.8, 0.8),
				Position = UDim2.fromScale(0.1, 0.1),
				Parent = swatch,
			})
			Lib.Text({
				Text = item.Name,
				Size = UDim2.new(0.5, 0, 0, 28),
				Position = UDim2.fromOffset(64, 6),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 24,
				Parent = row,
			})
			local statText = if tab == "Boots"
				then T("👟 +%s%% running speed", tostring(math.floor(item.Bonus * 100 + 0.5)))
				else T("💥 Power %s  •  ⚡ %ss swing", Util.Format(item.Power), string.format("%.2f", item.Cooldown))
			Lib.Text({
				Text = statText,
				Font = Lib.BodyFont,
				TextColor3 = C.Sub,
				Size = UDim2.new(0.55, 0, 0, 20),
				Position = UDim2.fromOffset(64, 36),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 16,
				Parent = row,
			})
			local button = Lib.Button({
				Size = UDim2.fromOffset(170, 46),
				Position = UDim2.new(1, -180, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				Parent = row,
				OnClick = function()
					Net.Fire(TABS[tab].Buy)
				end,
			})
			rows[tier] = { Button = button, Item = item }
		end
	end

	local builtFor = nil
	refresh = function()
		local data = State.Data
		if not data then
			return
		end
		if builtFor ~= tab then
			builtFor = tab
			buildRows()
		end
		for name, button in tabButtons do
			Lib.SetButton(button, nil, if name == tab then C.Gold else C.Gray)
		end
		local current = data[TABS[tab].Field] or 1
		for tier, row in rows do
			if tier <= current then
				Lib.SetButton(row.Button, if tier == current then "EQUIPPED" else "OWNED", C.Gray)
			elseif tier == current + 1 then
				local affordable = data.Coins >= row.Item.Cost
				Lib.SetButton(row.Button, "💰 " .. Util.Format(row.Item.Cost), if affordable then C.Green else C.Red)
			else
				Lib.SetButton(row.Button, "🔒 " .. Util.Format(row.Item.Cost), Color3.fromRGB(70, 72, 92))
			end
		end
	end

	return {
		OnOpen = function(arg)
			tab = if arg == "Boots" then "Boots" else "Pickaxes"
		end,
		Refresh = refresh,
	}
end

return Shop
