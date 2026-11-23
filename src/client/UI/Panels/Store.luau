-- Robux store: game passes, consumables (gems/boosts/server luck/meteor),
-- Miner Club subscription, Roblox Premium and rewarded video ads.
local Store = { Title = "🛒 STORE", Color = Color3.fromRGB(70, 210, 120) }

function Store.Build(content, ctx)
	local Lib, State, Net, Config, Util = ctx.Lib, ctx.State, ctx.Net, ctx.Config, ctx.Util
	local New, C = Lib.New, Lib.Colors
	local T = Lib.T
	local tab = "Passes"

	local tabs = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), Parent = content }, {
		Lib.List(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Left),
	})
	local pages = {}
	local tabButtons = {}
	local refresh

	for i, name in { "Passes", "Items", "Club" } do
		local labels = { Passes = "⭐ Game Passes", Items = "💎 Items & Boosts", Club = "👑 Club & Free" }
		tabButtons[name] = Lib.Button({
			Text = labels[name],
			Size = UDim2.fromOffset(200, 40),
			LayoutOrder = i,
			Parent = tabs,
			OnClick = function()
				tab = name
				refresh()
			end,
		})
		local page = Lib.Scroll({ Position = UDim2.fromOffset(0, 52), Size = UDim2.new(1, 0, 1, -52), Parent = content })
		page.Visible = false
		Lib.Padding(4).Parent = page
		pages[name] = page
	end
	Lib.Grid(UDim2.fromOffset(205, 170), 10).Parent = pages.Passes
	Lib.Grid(UDim2.fromOffset(205, 150), 10).Parent = pages.Items
	Lib.List(Enum.FillDirection.Vertical, 10).Parent = pages.Club

	local function card(parent, order, icon, name, description, tag)
		local frame = New(
			"Frame",
			{ BackgroundColor3 = C.Card, LayoutOrder = order, Parent = parent },
			{ Lib.Corner(14), Lib.Stroke(C.Gold, 2, 0.4) }
		)
		Lib.Text({ Text = icon, Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(8, 8), MaxTextSize = 38, Parent = frame })
		Lib.Text({
			Text = name,
			Size = UDim2.new(1, -60, 0, 26),
			Position = UDim2.fromOffset(56, 10),
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxTextSize = 20,
			Parent = frame,
		})
		if tag then
			New(
				"Frame",
				{ BackgroundColor3 = C.Red, Size = UDim2.fromOffset(90, 20), Position = UDim2.new(1, -94, 0, -8), Parent = frame },
				{
					Lib.Corner(8),
					Lib.Text({ Text = tag, Size = UDim2.fromScale(1, 1), MaxTextSize = 13 }),
				}
			)
		end
		Lib.Text({
			Text = description or "",
			Font = Lib.BodyFont,
			TextColor3 = C.Sub,
			Size = UDim2.new(1, -16, 0, 50),
			Position = UDim2.fromOffset(8, 54),
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			MaxTextSize = 14,
			Parent = frame,
		})
		return frame
	end

	-- passes
	local passButtons = {}
	for order, key in Config.GamePassOrder do
		local pass = Config.GamePasses[key]
		local frame = card(pages.Passes, order, pass.Icon or "⭐", pass.Name, pass.Description, if key == "VIP" then "BEST" else nil)
		passButtons[key] = Lib.Button({
			Size = UDim2.new(1, -16, 0, 42),
			Position = UDim2.new(0, 8, 1, -50),
			Parent = frame,
			OnClick = function()
				Net.Fire("BuyPass", key)
			end,
		})
	end

	-- items
	local itemCards = {}
	local itemButtons = {}
	for order, key in Config.StoreOrder do
		local product = Config.Products[key]
		local description = product.Description
		if product.Kind == "Gems" then
			description = "Spend on Gem Eggs and more"
		elseif product.Kind == "Boost" then
			description = "Stacks with every other boost"
		end
		local frame = card(pages.Items, order, product.Icon or "💎", product.Name, description, product.Tag)
		itemCards[key] = frame
		itemButtons[key] = Lib.Button({
			Size = UDim2.new(1, -16, 0, 40),
			Position = UDim2.new(0, 8, 1, -48),
			Parent = frame,
			OnClick = function()
				Net.Fire("BuyProduct", key)
			end,
		})
	end

	-- club & free
	local function wideCard(order, icon, title, description, buttonText, color, onClick)
		local frame = New(
			"Frame",
			{ BackgroundColor3 = C.Card, Size = UDim2.new(1, -12, 0, 96), LayoutOrder = order, Parent = pages.Club },
			{
				Lib.Corner(14),
				Lib.Stroke(color, 2, 0.2),
			}
		)
		Lib.Text({ Text = icon, Size = UDim2.fromOffset(60, 60), Position = UDim2.fromOffset(10, 18), MaxTextSize = 48, Parent = frame })
		Lib.Text({
			Text = title,
			Size = UDim2.new(1, -310, 0, 30),
			Position = UDim2.fromOffset(80, 12),
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxTextSize = 24,
			Parent = frame,
		})
		Lib.Text({
			Text = description,
			Font = Lib.BodyFont,
			TextColor3 = C.Sub,
			Size = UDim2.new(1, -310, 0, 40),
			Position = UDim2.fromOffset(80, 44),
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			MaxTextSize = 15,
			Parent = frame,
		})
		local button = Lib.Button({
			Text = buttonText,
			Color = color,
			Size = UDim2.fromOffset(210, 50),
			Position = UDim2.new(1, -220, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Parent = frame,
			OnClick = onClick,
		})
		return frame, button
	end

	local sub = Config.Subscription
	local _, clubButton = wideCard(
		1,
		"👑",
		T("%s (subscription)", sub.Name),
		sub.Description,
		T("Join %s", sub.PriceText),
		C.Cyan,
		function()
			Net.Fire("BuySubscription")
		end
	)
	local premiumCard = wideCard(
		2,
		"⭐",
		"Roblox Premium bonus",
		"Premium members get +10% coins in this game, forever.",
		"Get Premium",
		C.Purple,
		function()
			Net.Fire("BuyPremium")
		end
	)
	local adCard, adButton = wideCard(
		3,
		"📺",
		"Free 2x Coins",
		"Watch a short video for a free 10 minute 2x Coins boost.",
		"Watch",
		C.Green,
		function()
			local ok, message = Net.Invoke("WatchAd")
			if ctx.Toast and message then
				ctx.Toast(message, if ok then C.Green else C.Red)
			end
		end
	)
	local _, goldenButton = wideCard(
		4,
		"🥚",
		"Golden Egg",
		"Exclusive golden pets. Odds are shown before you buy.",
		"View odds",
		C.Gold,
		function()
			ctx.Panels.Open("Egg", "Golden")
		end
	)

	refresh = function()
		local data, derived = State.Data, State.Derived
		if not data then
			return
		end
		for name, page in pages do
			page.Visible = name == tab
			Lib.SetButton(tabButtons[name], nil, if name == tab then C.Gold else C.Gray)
		end
		for key, button in passButtons do
			if State.HasPass(key) then
				Lib.SetButton(button, "✅ OWNED", C.Gray)
			else
				Lib.SetButton(button, "R$ " .. Lib.Price("Pass", key), C.Green)
			end
		end
		for key, button in itemButtons do
			Lib.SetButton(button, "R$ " .. Lib.Price("Product", key), C.Green)
		end
		local starterOpen = not data.Flags.StarterPack and State.Now() < data.FirstJoin + Config.StarterPack.OfferHours * 3600
		itemCards.StarterPack.Visible = starterOpen
		Lib.SetButton(
			clubButton,
			if derived.Subscribed then "✅ MEMBER" else T("Join %s", sub.PriceText),
			if derived.Subscribed then C.Gray else C.Cyan
		)
		premiumCard.Visible = not derived.Premium
		adCard.Visible = derived.AdsEnabled == true
		local remaining = Config.RewardedAds.CooldownSeconds - (State.Now() - (data.LastAdTime or 0))
		Lib.SetButton(adButton, if remaining > 0 and data.LastAdTime > 0 then Util.FormatTime(remaining) else "📺 Watch", C.Green)
		goldenButton.Visible = not derived.PaidRandomRestricted
	end

	return {
		OnOpen = function(arg)
			if arg == "Passes" or arg == "Items" or arg == "Club" then
				tab = arg
			end
		end,
		Refresh = refresh,
		Tick = refresh,
	}
end

return Store
