--[[
	📖 Index: every pet in the game, egg by egg. Discovered pets show their
	colour and name, missing ones are "?" - so you always know what to hunt.
	Milestones (5, 10, 15 ... pets) pay gems and a PERMANENT home income
	bonus; completing an egg's set adds a little more.
]]
local Index = { Title = "📖 INDEX", Color = Color3.fromRGB(110, 190, 255) }

local EGG_ICONS = {
	Meadow = "🌿",
	Gem = "💎",
	Cosmic = "🌌",
	Frost = "❄️",
	Lava = "🔥",
	Void = "🔮",
	Meteor = "☄️",
}

function Index.Build(content, ctx)
	local Lib, State, Net, Config, Util = ctx.Lib, ctx.State, ctx.Net, ctx.Config, ctx.Util
	local New, C, T = Lib.New, Lib.Colors, Lib.T

	local header = Lib.Text({
		Text = "",
		Size = UDim2.new(1, 0, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 20,
		Parent = content,
	})
	-- milestones: a row of reward chips
	local milestones = Lib.Scroll({
		Horizontal = true,
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 0, 74),
		Parent = content,
	})
	Lib.List(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left).Parent = milestones
	local list = Lib.Scroll({ Position = UDim2.fromOffset(0, 110), Size = UDim2.new(1, 0, 1, -110), Parent = content })
	Lib.List(Enum.FillDirection.Vertical, 10).Parent = list
	Lib.Padding(4).Parent = list

	local function claim(index: number)
		local result = Net.Invoke("IndexClaim", index)
		if type(result) == "table" and result.Ok then
			Lib.PlaySound("Fanfare")
			ctx.Toast(
				if (result.Bonus or 0) > 0
					then T("📖 +%s 💎 and +%d%% home income forever!", Util.Format(result.Gems), math.floor(result.Bonus * 100))
					else T("📖 +%s 💎!", Util.Format(result.Gems)),
				C.Gold
			)
		elseif type(result) == "table" and result.Error then
			Lib.PlaySound("Error")
			ctx.Toast(result.Error, C.Red)
		end
	end

	local function setPets(eggId: string): { string }
		if eggId == "Meteor" then
			return Config.Meteor.MeteorPets
		end
		local names = {}
		for _, entry in Config.Eggs[eggId].Pets do
			table.insert(names, entry[1])
		end
		return names
	end

	local signature = ""
	local function refresh()
		local data = State.Data
		if not data then
			return
		end
		local count = Util.IndexCount(data)
		local claimed = data.IndexClaimed or {}
		local sets = Util.IndexSets(Config, data)
		local parts = { tostring(count) }
		for key in claimed do
			table.insert(parts, key)
		end
		for name in data.PetIndex do
			table.insert(parts, name)
		end
		table.sort(parts)
		local sig = table.concat(parts, ",")
		if sig == signature then
			return
		end
		signature = sig
		local total = 0
		for _ in Config.Pets do
			total += 1
		end
		header.Text = T(
			"📖 %d/%d pets discovered  •  🏠 +%d%% income forever",
			count,
			total,
			math.floor(Util.IndexBonus(Config, data) * 100 + 0.5)
		)

		Lib.Clear(milestones)
		for i, milestone in Config.Index.Milestones do
			local done = claimed[tostring(i)] == true
			local ready = not done and count >= milestone.Count
			local chip = New("Frame", {
				BackgroundColor3 = if done then Color3.fromRGB(40, 70, 55) elseif ready then Color3.fromRGB(90, 70, 20) else C.Card,
				Size = UDim2.fromOffset(122, 68),
				LayoutOrder = i,
				Parent = milestones,
			}, { Lib.Corner(12), Lib.Stroke(if ready then C.Gold elseif done then C.Green else C.Sub, 2, if ready then 0 else 0.5) })
			Lib.Text({
				Text = T("🐾 %d pets", milestone.Count),
				Size = UDim2.new(1, -8, 0, 22),
				Position = UDim2.fromOffset(4, 4),
				MaxTextSize = 16,
				Parent = chip,
			})
			Lib.Text({
				Text = "💎" .. Util.Format(milestone.Gems or 0) .. (if milestone.Bonus
					then "  🏠+" .. math.floor(milestone.Bonus * 100) .. "%"
					else ""),
				TextColor3 = C.Gold,
				Size = UDim2.new(1, -8, 0, 18),
				Position = UDim2.fromOffset(4, 26),
				MaxTextSize = 14,
				Parent = chip,
			})
			if ready then
				local button = New("TextButton", {
					Text = "",
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 1),
					Parent = chip,
				})
				button.Activated:Connect(function()
					claim(i)
				end)
			end
			Lib.Text({
				Text = if done
					then T("✅ claimed")
					elseif ready then T("👆 CLAIM!")
					else string.format("%d/%d", math.min(count, milestone.Count), milestone.Count),
				TextColor3 = if done then C.Green elseif ready then C.Gold else C.Sub,
				Size = UDim2.new(1, -8, 0, 18),
				Position = UDim2.fromOffset(4, 46),
				MaxTextSize = 14,
				Parent = chip,
			})
		end

		Lib.Clear(list)
		for order, set in sets do
			local section = New("Frame", {
				BackgroundColor3 = C.Card,
				BackgroundTransparency = 0.2,
				Size = UDim2.new(1, -8, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = order,
				Parent = list,
			}, { Lib.Corner(12), Lib.Padding(6) })
			Lib.List(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Left).Parent = section
			local eggName = if set.Egg == "Meteor" then T("☄️ Meteor pets (only from meteors)") else T(Config.Eggs[set.Egg].Name)
			Lib.Text({
				Text = string.format("%s %s  %d/%d", EGG_ICONS[set.Egg] or "🥚", eggName, set.Have, set.Total)
					.. (if set.Done then "  ✅ +" .. math.floor(Config.Index.SetBonus * 100) .. "%" else ""),
				TextColor3 = if set.Done then C.Green else C.Text,
				Size = UDim2.new(1, 0, 0, 24),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 18,
				LayoutOrder = 1,
				Parent = section,
			})
			local grid = New("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = 2,
				Parent = section,
			})
			local layout = Lib.Grid(UDim2.fromOffset(92, 78), 6)
			layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
			layout.Parent = grid
			for i, name in setPets(set.Egg) do
				local info = Config.Pets[name]
				local found = data.PetIndex[name] == true
				local rarity = info and Config.Rarities[info.Rarity]
				local tile = New("Frame", {
					BackgroundColor3 = if found then Color3.fromRGB(34, 38, 54) else Color3.fromRGB(22, 24, 32),
					LayoutOrder = i,
					Parent = grid,
				}, { Lib.Corner(10), Lib.Stroke(if found and rarity then rarity.Color else Color3.fromRGB(70, 70, 85), 2, 0) })
				New("Frame", {
					Size = UDim2.fromOffset(34, 34),
					Position = UDim2.new(0.5, 0, 0, 6),
					AnchorPoint = Vector2.new(0.5, 0),
					BackgroundColor3 = if found and info then info.Color else Color3.fromRGB(45, 45, 55),
					Parent = tile,
				}, {
					Lib.Corner(17),
					Lib.Text({ Text = if found then "" else "?", Size = UDim2.fromScale(1, 1), MaxTextSize = 22 }),
				})
				Lib.Text({
					Text = if found then T(name) else "???",
					Size = UDim2.new(1, -6, 0, 16),
					Position = UDim2.fromOffset(3, 42),
					MaxTextSize = 12,
					Parent = tile,
				})
				Lib.Text({
					Text = if info then T(info.Rarity) else "",
					Font = Lib.BodyFont,
					TextColor3 = if rarity then rarity.Color else C.Sub,
					Size = UDim2.new(1, -6, 0, 14),
					Position = UDim2.fromOffset(3, 58),
					MaxTextSize = 11,
					Parent = tile,
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

return Index
