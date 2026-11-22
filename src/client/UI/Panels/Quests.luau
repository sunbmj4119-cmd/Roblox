-- Daily login streak, daily quests, weekly ranked ladder, VIP chest, group reward
local Quests = { Title = "📜 DAILY & RANKED", Color = Color3.fromRGB(90, 160, 255) }

function Quests.Build(content, ctx)
	local Lib, State, Net, Config, Util = ctx.Lib, ctx.State, ctx.Net, ctx.Config, ctx.Util
	local New, C = Lib.New, Lib.Colors
	local T = Lib.T

	local scroll = Lib.Scroll({ Parent = content })
	Lib.List(Enum.FillDirection.Vertical, 10).Parent = scroll
	Lib.Padding(4).Parent = scroll

	local function section(title: string, order: number, height: number)
		local frame = New("Frame", {
			BackgroundColor3 = C.PanelLight,
			Size = UDim2.new(1, -12, 0, height),
			LayoutOrder = order,
			Parent = scroll,
		}, { Lib.Corner(14) })
		Lib.Text({
			Text = title,
			Size = UDim2.new(1, -20, 0, 28),
			Position = UDim2.fromOffset(12, 6),
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxTextSize = 22,
			Parent = frame,
		})
		return frame
	end

	-- daily login -----------------------------------------------------------
	local login = section("📅 Daily Login Streak", 1, 150)
	local days = New("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 38),
		Size = UDim2.new(1, -20, 0, 62),
		Parent = login,
	}, { Lib.List(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center) })
	local dayBoxes = {}
	for i, reward in Config.DailyRewards do
		local box = New("Frame", {
			BackgroundColor3 = C.Card,
			Size = UDim2.fromOffset(84, 62),
			LayoutOrder = i,
			Parent = days,
		}, { Lib.Corner(10), Lib.Stroke(C.Gray, 2, 0) })
		Lib.Text({
			Text = T("Day %d", i),
			Size = UDim2.new(1, -4, 0, 18),
			Position = UDim2.fromOffset(2, 3),
			MaxTextSize = 15,
			Parent = box,
		})
		Lib.Text({
			Text = Util.RewardText(reward, T),
			Font = Lib.BodyFont,
			Size = UDim2.new(1, -6, 0, 36),
			Position = UDim2.fromOffset(3, 22),
			MaxTextSize = 12,
			TextWrapped = true,
			Parent = box,
		})
		dayBoxes[i] = box
	end
	local claimDaily = Lib.Button({
		Text = "CLAIM",
		Size = UDim2.fromOffset(200, 38),
		Position = UDim2.new(0.5, 0, 0, 106),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = login,
		OnClick = function()
			Net.Fire("ClaimDaily")
		end,
	})

	-- daily quests ------------------------------------------------------------
	local questFrame = section("🎯 Daily Quests", 2, 40 + Config.DailyQuestCount * 64)
	local questTimer = Lib.Text({
		Text = "",
		Font = Lib.BodyFont,
		TextColor3 = C.Sub,
		Size = UDim2.new(0.5, 0, 0, 20),
		Position = UDim2.new(0.5, -12, 0, 10),
		TextXAlignment = Enum.TextXAlignment.Right,
		MaxTextSize = 14,
		Parent = questFrame,
	})
	local questRows = {}
	for i = 1, Config.DailyQuestCount do
		local row = New("Frame", {
			BackgroundColor3 = C.Card,
			Size = UDim2.new(1, -20, 0, 56),
			Position = UDim2.fromOffset(10, 38 + (i - 1) * 64),
			Parent = questFrame,
		}, { Lib.Corner(10) })
		local text = Lib.Text({
			Text = "",
			Size = UDim2.new(0.62, 0, 0, 22),
			Position = UDim2.fromOffset(10, 4),
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxTextSize = 18,
			Parent = row,
		})
		local bar, setBar = Lib.Bar({ Size = UDim2.new(0.62, 0, 0, 18), Position = UDim2.fromOffset(10, 32), Color = C.Blue, Parent = row })
		local button = Lib.Button({
			Size = UDim2.fromOffset(180, 42),
			Position = UDim2.new(1, -188, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Parent = row,
			OnClick = function()
				Net.Fire("ClaimQuest", i)
			end,
		})
		questRows[i] = { Text = text, SetBar = setBar, Button = button, Bar = bar }
	end

	-- weekly ranked -------------------------------------------------------------
	local ranked = section("🏆 Weekly Ranked", 3, 190)
	local rankText = Lib.Text({
		Text = "",
		Size = UDim2.new(1, -20, 0, 30),
		Position = UDim2.fromOffset(12, 36),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 26,
		Parent = ranked,
	})
	local _, setRankBar = Lib.Bar({ Size = UDim2.new(1, -24, 0, 22), Position = UDim2.fromOffset(12, 70), Color = C.Gold, Parent = ranked })
	local rankInfo = Lib.Text({
		Text = "",
		Font = Lib.BodyFont,
		TextColor3 = C.Sub,
		Size = UDim2.new(1, -24, 0, 40),
		Position = UDim2.fromOffset(12, 98),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		MaxTextSize = 14,
		Parent = ranked,
	})
	local tiers = {}
	for _, rank in Config.Ranks do
		table.insert(
			tiers,
			string.format("<font color='#%s'>%s</font> %s💎", rank.Color:ToHex(), T(rank.Name), Util.Format(rank.RewardGems))
		)
	end
	Lib.Text({
		Text = table.concat(tiers, "  ") .. "  •  " .. T("Global Top 10: up to 5K💎"),
		Font = Lib.BodyFont,
		Size = UDim2.new(1, -24, 0, 36),
		Position = UDim2.fromOffset(12, 146),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		MaxTextSize = 13,
		Parent = ranked,
	})

	-- perks -----------------------------------------------------------------------
	local perks = section("🎁 Free Perks", 4, 150)
	local perkRow = New("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 40),
		Size = UDim2.new(1, -20, 0, 104),
		Parent = perks,
	}, { Lib.Grid(UDim2.fromOffset(300, 46), 10) })
	local vipButton = Lib.Button({
		Color = C.Gold,
		LayoutOrder = 1,
		Parent = perkRow,
		OnClick = function()
			Net.Fire("ClaimVip")
		end,
	})
	local groupButton = Lib.Button({
		Color = C.Blue,
		LayoutOrder = 2,
		Parent = perkRow,
		OnClick = function()
			Net.Fire("ClaimGroup")
		end,
	})
	local premiumButton = Lib.Button({
		Color = C.Purple,
		LayoutOrder = 3,
		Parent = perkRow,
		OnClick = function()
			Net.Fire("BuyPremium")
		end,
	})
	-- viral loop: every friend in the server = +10% coins for both of you
	Lib.Button({
		Text = "📨 Invite friends: +10% each",
		Color = C.Green,
		LayoutOrder = 4,
		Parent = perkRow,
		OnClick = function()
			local SocialService = game:GetService("SocialService")
			local player = game:GetService("Players").LocalPlayer
			local ok, canInvite = pcall(SocialService.CanSendGameInviteAsync, SocialService, player)
			if ok and canInvite then
				pcall(SocialService.PromptGameInvite, SocialService, player)
			elseif ctx.Toast then
				ctx.Toast("Invites aren't available right now.", C.Red)
			end
		end,
	})

	local function refresh()
		local data, derived = State.Data, State.Derived
		if not data then
			return
		end
		local today = derived.Today or Util.DayNumber(math.floor(State.Now()))
		-- login
		local claimedToday = data.Daily.LastClaimDay == today
		local streak = data.Daily.Streak
		local nextStreak = if claimedToday then streak else (if data.Daily.LastClaimDay == today - 1 then streak + 1 else 1)
		local currentIndex = ((nextStreak - 1) % #Config.DailyRewards) + 1
		for i, box in dayBoxes do
			local stroke = box:FindFirstChildOfClass("UIStroke")
			if i == currentIndex then
				stroke.Color = if claimedToday then C.Green else C.Gold
				box.BackgroundColor3 = if claimedToday then Color3.fromRGB(45, 95, 60) else Color3.fromRGB(110, 85, 30)
			elseif i < currentIndex then
				stroke.Color = C.Green
				box.BackgroundColor3 = Color3.fromRGB(45, 95, 60)
			else
				stroke.Color = C.Gray
				box.BackgroundColor3 = C.Card
			end
		end
		if claimedToday then
			Lib.SetButton(claimDaily, T("Next in %s", Util.FormatTime(Util.SecondsUntilNextDay(math.floor(State.Now())))), C.Gray)
		else
			Lib.SetButton(claimDaily, T("🎁 CLAIM DAY %d", currentIndex), C.Green)
		end

		-- quests
		questTimer.Text = T("New quests in %s", Util.FormatTime(Util.SecondsUntilNextDay(math.floor(State.Now()))))
		for i, row in questRows do
			local quest = data.Daily.Quests[i]
			local def
			for _, q in Config.Quests do
				if quest and q.Id == quest.Id then
					def = q
				end
			end
			if quest and def then
				row.Text.Text = T(def.Text)
				row.SetBar(quest.Progress / def.Target, string.format("%d / %d", quest.Progress, def.Target))
				if quest.Claimed then
					Lib.SetButton(row.Button, "✔ DONE", C.Gray)
				elseif quest.Progress >= def.Target then
					Lib.SetButton(row.Button, T("CLAIM %s", Util.RewardText(def.Reward, T)), C.Green)
				else
					Lib.SetButton(row.Button, Util.RewardText(def.Reward, T), Color3.fromRGB(70, 72, 92))
				end
			else
				row.Text.Text = "-"
			end
		end

		-- ranked
		local points = data.Weekly.Points
		local rank, index = Util.RankFor(Config, points)
		local nextRank = Config.Ranks[index + 1]
		rankText.Text = T("<font color='#%s'>%s</font>  •  %s pts", rank.Color:ToHex(), string.upper(T(rank.Name)), Util.Comma(points))
		if nextRank then
			setRankBar(
				(points - rank.Min) / (nextRank.Min - rank.Min),
				T("%s / %s to %s", Util.Comma(points), Util.Comma(nextRank.Min), nextRank.Name),
				rank.Color
			)
		else
			setRankBar(1, T("MAX RANK!"), rank.Color)
		end
		rankInfo.Text = T(
			"Earn points by mining, meteor events, quests and PvP. Season resets in %s - rewards are paid when it ends!",
			Util.FormatTime(Util.SecondsUntilNextWeek(math.floor(State.Now())))
		)

		-- perks
		if State.HasPass("VIP") then
			local claimed = data.Daily.VipChestDay == today
			Lib.SetButton(vipButton, if claimed then "👑 VIP chest ✔" else "👑 VIP chest 100💎", if claimed then C.Gray else C.Gold)
		else
			Lib.SetButton(vipButton, "👑 VIP: daily 100💎", C.Gold)
		end
		groupButton.Visible = Config.GroupId ~= 0
		Lib.SetButton(
			groupButton,
			if data.Flags.GroupReward then "👥 Group bonus +10% ✔" else T("👥 Join group: %s💎", Config.Social.GroupJoinGems),
			if data.Flags.GroupReward then C.Gray else C.Blue
		)
		premiumButton.Visible = not derived.Premium
		Lib.SetButton(premiumButton, "⭐ Premium: +10% coins", C.Purple)
	end

	return { Refresh = refresh, Tick = refresh }
end

return Quests
