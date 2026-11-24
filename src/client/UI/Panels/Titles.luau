--[[
	Titles: earned by playing, shown above your head for everyone to see.
	Pick one to wear, or "Auto" to always wear your best one.
]]
local Titles = { Title = "👑 TITLES", Color = Color3.fromRGB(230, 170, 40) }

function Titles.Build(content, ctx)
	local Lib, State, Net, Config, Util = ctx.Lib, ctx.State, ctx.Net, ctx.Config, ctx.Util
	local New, C, T = Lib.New, Lib.Colors, Lib.T

	local header = Lib.Text({
		Text = "",
		Size = UDim2.new(1, 0, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 20,
		Parent = content,
	})
	local list = Lib.Scroll({ Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 1, -32), Parent = content })
	Lib.List(Enum.FillDirection.Vertical, 8).Parent = list
	Lib.Padding(4).Parent = list

	local function countOf(t): number
		local n = 0
		for _ in t or {} do
			n += 1
		end
		return n
	end

	-- requirement text + progress ("3/10")
	local function requirement(title, data): (string, string)
		local need = title.Need or {}
		local stats = data.Stats or {}
		if need.Level then
			return T("Reach level %d", need.Level), string.format("%d/%d", math.min(data.Level, need.Level), need.Level)
		elseif need.Index then
			local have = countOf(data.PetIndex)
			return T("Discover %d different pets", need.Index), string.format("%d/%d", math.min(have, need.Index), need.Index)
		elseif need.Steals then
			local have = stats.ShardsStolen or 0
			return T("Steal %d pets", need.Steals), string.format("%d/%d", math.min(have, need.Steals), need.Steals)
		elseif need.Catches then
			local have = stats.ThievesCaught or 0
			return T("Stop %d thieves (bonk or trap)", need.Catches), string.format("%d/%d", math.min(have, need.Catches), need.Catches)
		elseif need.HouseLevel then
			local have = Util.HouseLevel(Config, data)
			return T("Grow your house to level %d", need.HouseLevel),
				string.format("%d/%d", math.min(have, need.HouseLevel), need.HouseLevel)
		elseif need.Likes then
			local have = data.Base and data.Base.Likes or 0
			return T("Get %d likes on your house", need.Likes), string.format("%d/%d", math.min(have, need.Likes), need.Likes)
		elseif need.Rebirths then
			return T("Rebirth %d times", need.Rebirths), string.format("%d/%d", math.min(data.Rebirths or 0, need.Rebirths), need.Rebirths)
		elseif need.Huge then
			return T("Find a HUGE pet"), string.format("%d/%d", math.min(stats.HugesFound or 0, need.Huge), need.Huge)
		elseif need.LifetimeCoins then
			return T("Earn %s coins in total", Util.Format(need.LifetimeCoins)), ""
		elseif need.Titanic then
			return T("Find a TITANIC pet"), string.format("%d/%d", math.min(stats.TitanicsFound or 0, need.Titanic), need.Titanic)
		elseif need.Pranks then
			local have = stats.Pranks or 0
			return T("Prank %d thieves with a 🎭 Prank Pet", need.Pranks),
				string.format("%d/%d", math.min(have, need.Pranks), need.Pranks)
		elseif need.Lucky then
			local have = stats.LuckyBlocks or 0
			return T("Open %d lucky blocks", need.Lucky), string.format("%d/%d", math.min(have, need.Lucky), need.Lucky)
		elseif need.Pass then
			return T("Own the VIP pass"), ""
		end
		return T("Everyone starts here"), ""
	end

	local signature = ""
	local function refresh()
		local data = State.Data
		if not data then
			return
		end
		local current = Util.CurrentTitle(Config, data, State.HasPass)
		local unlocked = {}
		local parts = { data.Title or "", current and current.Id or "" }
		local count = 0
		for _, title in Config.Titles do
			local ok = Util.TitleUnlocked(Config, title, data, State.HasPass)
			unlocked[title.Id] = ok
			if ok then
				count += 1
			end
			local _, progress = requirement(title, data)
			table.insert(parts, title.Id .. tostring(ok) .. progress)
		end
		header.Text = T("👑 %d/%d titles unlocked  •  everyone sees the one you wear", count, #Config.Titles)
		local sig = table.concat(parts, ",")
		if sig == signature then
			return
		end
		signature = sig
		Lib.Clear(list)

		-- auto: always wear the best one
		local auto = New("Frame", { BackgroundColor3 = C.Card, Size = UDim2.new(1, -12, 0, 54), LayoutOrder = 0, Parent = list }, {
			Lib.Corner(12),
		})
		Lib.Text({
			Text = "✨ " .. T("Auto: always wear my best title"),
			Size = UDim2.new(1, -190, 1, -10),
			Position = UDim2.fromOffset(12, 5),
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxTextSize = 18,
			Parent = auto,
		})
		Lib.Button({
			Text = if (data.Title or "") == "" then "✅" else "Wear",
			Color = if (data.Title or "") == "" then C.Green else C.Blue,
			Size = UDim2.fromOffset(150, 42),
			Position = UDim2.new(1, -160, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			TextSize = 18,
			Parent = auto,
			OnClick = function()
				Net.Fire("SetTitle", "")
			end,
		})

		for order, title in Config.Titles do
			local ok = unlocked[title.Id]
			local wearing = current and current.Id == title.Id and (data.Title or "") ~= ""
			local row = New("Frame", {
				BackgroundColor3 = if ok then C.Card else Color3.fromRGB(40, 40, 52),
				Size = UDim2.new(1, -12, 0, 62),
				LayoutOrder = order,
				Parent = list,
			}, { Lib.Corner(12), Lib.Stroke(if ok then title.Color else Color3.new(0, 0, 0), 2, if ok then 0.1 else 0.6) })
			Lib.Text({
				Text = (if ok then "" else "🔒 ") .. T(title.Name),
				TextColor3 = if ok then title.Color else C.Sub,
				Size = UDim2.new(1, -190, 0, 28),
				Position = UDim2.fromOffset(12, 4),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 21,
				Parent = row,
			})
			local text, progress = requirement(title, data)
			Lib.Text({
				Text = text .. (if progress ~= "" and not ok then "  (" .. progress .. ")" else ""),
				Font = Lib.BodyFont,
				TextColor3 = C.Sub,
				Size = UDim2.new(1, -190, 0, 20),
				Position = UDim2.fromOffset(12, 36),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 14,
				Parent = row,
			})
			if ok then
				Lib.Button({
					Text = if wearing then "✅" else "Wear",
					Color = if wearing then C.Green else C.Blue,
					Size = UDim2.fromOffset(150, 42),
					Position = UDim2.new(1, -160, 0.5, 0),
					AnchorPoint = Vector2.new(0, 0.5),
					TextSize = 18,
					Parent = row,
					OnClick = function()
						Lib.PlaySound("UI")
						Net.Fire("SetTitle", title.Id)
					end,
				})
			end
		end
	end

	return {
		Refresh = refresh,
		OnOpen = function()
			signature = ""
			refresh()
		end,
	}
end

return Titles
