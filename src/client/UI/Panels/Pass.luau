-- Season pass: free + premium tracks, XP bar, premium / skip upsells
local Pass = { Title = "🎫 SEASON PASS", Color = Color3.fromRGB(255, 120, 60) }

function Pass.Build(content, ctx)
	local Lib, State, Net, Config, Util = ctx.Lib, ctx.State, ctx.Net, ctx.Config, ctx.Util
	local New, C = Lib.New, Lib.Colors
	local T = Lib.T

	local title = Lib.Text({
		Text = Config.Season.Name,
		Size = UDim2.new(0.5, 0, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 22,
		Parent = content,
	})
	local tierText = Lib.Text({
		Text = "",
		Size = UDim2.new(0.5, 0, 0, 26),
		Position = UDim2.fromScale(0.5, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		MaxTextSize = 22,
		Parent = content,
	})
	local _, setXp = Lib.Bar({ Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 30), Color = C.Gold, Parent = content })

	local actions = New("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 58),
		Size = UDim2.new(1, 0, 0, 44),
		Parent = content,
	}, { Lib.List(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center) })
	local premiumButton = Lib.Button({
		Size = UDim2.fromOffset(230, 42),
		Color = C.Gold,
		LayoutOrder = 1,
		Parent = actions,
		OnClick = function()
			Net.Fire("BuyProduct", "SeasonPremium")
		end,
	})
	local skipButton = Lib.Button({
		Size = UDim2.fromOffset(200, 42),
		Color = C.Purple,
		LayoutOrder = 2,
		Parent = actions,
		OnClick = function()
			Net.Fire("BuyProduct", "SkipTiers")
		end,
	})
	Lib.Button({
		Text = "✅ Claim All",
		Size = UDim2.fromOffset(150, 42),
		Color = C.Green,
		LayoutOrder = 3,
		Parent = actions,
		OnClick = function()
			Net.Fire("ClaimAllTiers")
		end,
	})

	local lanes =
		New("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 108), Size = UDim2.new(1, 0, 1, -108), Parent = content })
	Lib.Text({
		Text = "FREE",
		TextColor3 = C.Sub,
		Size = UDim2.fromOffset(70, 20),
		Position = UDim2.fromOffset(0, 70),
		MaxTextSize = 16,
		Parent = lanes,
	})
	Lib.Text({
		Text = "PREMIUM",
		TextColor3 = C.Gold,
		Size = UDim2.fromOffset(70, 20),
		Position = UDim2.fromOffset(0, 190),
		MaxTextSize = 16,
		Parent = lanes,
	})
	local scroll = Lib.Scroll({ Horizontal = true, Position = UDim2.fromOffset(74, 0), Size = UDim2.new(1, -74, 1, 0), Parent = lanes })
	Lib.List(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left).Parent = scroll

	local columns = {}
	local function rewardBox(parent, y, reward, onClick)
		local box = New("TextButton", {
			Text = "",
			AutoButtonColor = true,
			BackgroundColor3 = C.Card,
			Size = UDim2.fromOffset(104, 104),
			Position = UDim2.fromOffset(0, y),
			Parent = parent,
		}, { Lib.Corner(12), Lib.Stroke(C.Gray, 2, 0) })
		Lib.Text({
			Text = Util.RewardText(reward, T),
			Size = UDim2.new(1, -8, 1, -30),
			Position = UDim2.fromOffset(4, 4),
			TextWrapped = true,
			MaxTextSize = 16,
			Parent = box,
		})
		local status = Lib.Text({
			Name = "Status",
			Text = "",
			Size = UDim2.new(1, -8, 0, 20),
			Position = UDim2.new(0, 4, 1, -24),
			MaxTextSize = 14,
			Parent = box,
		})
		box.Activated:Connect(onClick)
		return box, status
	end

	for tier, def in Config.SeasonTiers do
		local column = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(104, 250), LayoutOrder = tier, Parent = scroll })
		Lib.Text({ Text = T("Tier %d", tier), Size = UDim2.new(1, 0, 0, 22), MaxTextSize = 18, Parent = column })
		local freeBox, freeStatus = rewardBox(column, 26, def.Free, function()
			Net.Fire("ClaimTier", tier, "Free")
		end)
		local premiumBox, premiumStatus = rewardBox(column, 140, def.Premium, function()
			Net.Fire("ClaimTier", tier, "Premium")
		end)
		columns[tier] = { FreeBox = freeBox, FreeStatus = freeStatus, PremiumBox = premiumBox, PremiumStatus = premiumStatus }
	end

	local function styleBox(box, status, claimed, unlocked, locked)
		local stroke = box:FindFirstChildOfClass("UIStroke")
		if claimed then
			status.Text = "✅"
			stroke.Color = C.Green
			box.BackgroundColor3 = Color3.fromRGB(40, 80, 55)
		elseif locked then
			status.Text = "🔒"
			stroke.Color = C.Gold
			box.BackgroundColor3 = Color3.fromRGB(60, 52, 30)
		elseif unlocked then
			status.Text = T("CLAIM!")
			stroke.Color = C.Gold
			box.BackgroundColor3 = Color3.fromRGB(110, 85, 30)
		else
			status.Text = ""
			stroke.Color = C.Gray
			box.BackgroundColor3 = C.Card
		end
	end

	local function refresh()
		local data = State.Data
		if not data then
			return
		end
		local season = data.Season
		local perTier = Config.Season.XPPerTier
		local tier = math.min(#Config.SeasonTiers, math.floor(season.XP / perTier))
		tierText.Text = T("Tier %d / %d", tier, #Config.SeasonTiers)
		if tier >= #Config.SeasonTiers then
			setXp(1, T("SEASON COMPLETE!"))
		else
			local into = season.XP - tier * perTier
			setXp(into / perTier, string.format("%s / %s XP", Util.Comma(into), Util.Comma(perTier)))
		end
		if Config.Season.EndsAt > 0 then
			title.Text = T("%s  •  ends in %s", Config.Season.Name, Util.FormatTime(Config.Season.EndsAt - State.Now()))
		end
		premiumButton.Visible = not season.Premium
		Lib.SetButton(premiumButton, T("🎫 Unlock Premium  R$%s", Lib.Price("Product", "SeasonPremium")), C.Gold)
		Lib.SetButton(skipButton, T("⏩ Skip 5 tiers  R$%s", Lib.Price("Product", "SkipTiers")), C.Purple)
		for t, column in columns do
			local unlocked = tier >= t
			styleBox(column.FreeBox, column.FreeStatus, season.ClaimedFree[tostring(t)] == true, unlocked, false)
			styleBox(column.PremiumBox, column.PremiumStatus, season.ClaimedPremium[tostring(t)] == true, unlocked, not season.Premium)
		end
	end

	return { Refresh = refresh }
end

return Pass
