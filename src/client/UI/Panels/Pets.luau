-- Pet inventory: equip / unequip / equip best / delete, slot upsell
local Pets = { Title = "🐾 PETS", Color = Color3.fromRGB(120, 200, 90) }

function Pets.Build(content, ctx)
	local Lib, State, Net, Config, Util = ctx.Lib, ctx.State, ctx.Net, ctx.Config, ctx.Util
	local New, C = Lib.New, Lib.Colors

	local header = Lib.Text({
		Text = "",
		Size = UDim2.new(1, 0, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 20,
		Parent = content,
	})
	local actions = New("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 0, 40),
		Parent = content,
	}, { Lib.List(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left) })
	Lib.Button({ Text = "⭐ Equip Best", Color = C.Green, Size = UDim2.fromOffset(140, 38), LayoutOrder = 1, Parent = actions, OnClick = function()
		Net.Fire("EquipBest")
	end })
	Lib.Button({ Text = "🗑 Commons", Color = C.Red, Size = UDim2.fromOffset(130, 38), LayoutOrder = 2, Parent = actions, OnClick = function()
		Net.Fire("DeleteRarity", "Common")
	end })
	Lib.Button({ Text = "🗑 Uncommons", Color = C.Red, Size = UDim2.fromOffset(140, 38), LayoutOrder = 3, Parent = actions, OnClick = function()
		Net.Fire("DeleteRarity", "Uncommon")
	end })
	local slotsButton = Lib.Button({ Text = "🐾 +3 Slots", Color = C.Gold, Size = UDim2.fromOffset(130, 38), LayoutOrder = 4, Parent = actions, OnClick = function()
		if ctx.Upsell then
			ctx.Upsell.Pass("ExtraPets", true)
		end
	end })

	local grid = Lib.Scroll({ Position = UDim2.fromOffset(0, 78), Size = UDim2.new(1, 0, 1, -78), Parent = content })
	Lib.Grid(UDim2.fromOffset(118, 120), 8).Parent = grid
	Lib.Padding(4).Parent = grid

	local signature = ""
	local confirmDelete = {} -- [petId] = os.clock()

	local function power(name)
		local info = Config.Pets[name]
		return if info then info.Power else 0
	end

	local function rebuild(data)
		Lib.Clear(grid)
		local equipped = {}
		for _, id in data.Equipped do
			equipped[id] = true
		end
		local pets = table.clone(data.Pets)
		table.sort(pets, function(a, b)
			local ea, eb = equipped[a.Id] and 1 or 0, equipped[b.Id] and 1 or 0
			if ea ~= eb then
				return ea > eb
			end
			if power(a.Name) ~= power(b.Name) then
				return power(a.Name) > power(b.Name)
			end
			return a.Id < b.Id
		end)
		for order, pet in pets do
			local info = Config.Pets[pet.Name]
			if info then
				local rarity = Config.Rarities[info.Rarity]
				local isEquipped = equipped[pet.Id] == true
				local card = New("TextButton", {
					Text = "",
					AutoButtonColor = true,
					BackgroundColor3 = if isEquipped then Color3.fromRGB(45, 95, 60) else C.Card,
					LayoutOrder = order,
					Parent = grid,
				}, { Lib.Corner(12), Lib.Stroke(rarity.Color, 3, 0) })
				local swatch = New("Frame", {
					Size = UDim2.fromOffset(42, 42),
					Position = UDim2.new(0.5, 0, 0, 8),
					AnchorPoint = Vector2.new(0.5, 0),
					BackgroundColor3 = info.Color,
					Parent = card,
				}, { Lib.Corner(if info.Shape == "Ball" then 21 else 8), Lib.Stroke(Color3.new(0, 0, 0), 2, 0.3) })
				Lib.Text({ Text = "• •", TextColor3 = Color3.new(0, 0, 0), Outline = false, Size = UDim2.fromScale(1, 0.5), Position = UDim2.fromScale(0, 0.15), Parent = swatch })
				Lib.Text({ Text = pet.Name, Size = UDim2.new(1, -6, 0, 20), Position = UDim2.fromOffset(3, 54), MaxTextSize = 15, Parent = card })
				Lib.Text({
					Text = "+" .. Util.Format(info.Power) .. "x",
					TextColor3 = rarity.Color,
					Size = UDim2.new(1, -6, 0, 18),
					Position = UDim2.fromOffset(3, 74),
					MaxTextSize = 15,
					Parent = card,
				})
				Lib.Text({
					Text = if isEquipped then "EQUIPPED" else "tap to equip",
					Font = Lib.BodyFont,
					TextColor3 = if isEquipped then C.Green else C.Sub,
					Size = UDim2.new(1, -30, 0, 16),
					Position = UDim2.fromOffset(3, 98),
					MaxTextSize = 12,
					Parent = card,
				})
				card.Activated:Connect(function()
					Net.Fire(if isEquipped then "UnequipPet" else "EquipPet", pet.Id)
				end)
				if not isEquipped then
					local del = New("TextButton", {
						Text = "🗑",
						TextScaled = true,
						BackgroundColor3 = C.Red,
						Size = UDim2.fromOffset(24, 24),
						Position = UDim2.new(1, -28, 1, -28),
						Parent = card,
					}, { Lib.Corner(6) })
					del.Activated:Connect(function()
						local last = confirmDelete[pet.Id]
						if last and os.clock() - last < 2.5 then
							Net.Fire("DeletePet", pet.Id)
						else
							confirmDelete[pet.Id] = os.clock()
							del.Text = "?"
							task.delay(2.5, function()
								if del.Parent then
									del.Text = "🗑"
								end
							end)
						end
					end)
				end
			end
		end
	end

	local function refresh()
		local data, derived = State.Data, State.Derived
		if not data then
			return
		end
		local indexCount, totalPets = 0, 0
		for _ in data.PetIndex do
			indexCount += 1
		end
		for _ in Config.Pets do
			totalPets += 1
		end
		header.Text = string.format(
			"Equipped %d/%d  •  Power +%sx  •  Pets %d/%d  •  Index %d/%d",
			#data.Equipped,
			derived.PetSlots or 3,
			Util.Format(derived.PetPower or 0),
			#data.Pets,
			Config.MaxPets,
			indexCount,
			totalPets
		)
		slotsButton.Visible = not State.HasPass("ExtraPets")
		local parts = {}
		for _, pet in data.Pets do
			table.insert(parts, pet.Id)
		end
		local sig = table.concat(parts, ",") .. "|" .. table.concat(data.Equipped, ",")
		if sig ~= signature then
			signature = sig
			rebuild(data)
		end
	end

	return { Refresh = refresh }
end

return Pets
