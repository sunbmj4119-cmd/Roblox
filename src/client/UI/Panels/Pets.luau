--[[
	Pet collection: every pet you own, best earners first.
	🔒 = in a VAULT (can never be stolen, 50% income)
	🏠 = on display (full income, thieves can try to take it)
	💎 = exclusive (never stolen)   ⭐ = following you   📦 = storage
	Tap 🔒/🏠 on a card to choose: keep it safe in a vault, or show it off.
	Tap 💰 twice to sell a pet (pays one minute of its income).
	Tap a card: 🌱 grow it (level, ✨ feed) and ⭐ evolve it (Lv10 + 2 copies).
]]
local PetModel = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("PetModel"))

local Pets = { Title = "🐾 PETS", Color = Color3.fromRGB(120, 200, 90) }

local MAX_VIEWPORTS = 24 -- 3D previews for the best pets (keeps phones smooth)

local function viewport(parent: GuiObject, petName: string, variant: string?, growth)
	local frame = Instance.new("ViewportFrame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromOffset(64, 56)
	frame.Position = UDim2.new(0.5, 0, 0, 4)
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Ambient = Color3.fromRGB(200, 200, 210)
	frame.LightColor = Color3.new(1, 1, 1)
	frame.Parent = parent
	local model = PetModel.Build(petName, variant, growth)
	model.Parent = frame
	local camera = Instance.new("Camera")
	local _, size = model:GetBoundingBox()
	local pivot = model:GetPivot()
	local center = pivot.Position + Vector3.new(0, size.Y * 0.45, 0)
	local distance = math.max(size.X, size.Y) * 1.55
	camera.CFrame = CFrame.lookAt(center + pivot.LookVector * distance + Vector3.new(0, size.Y * 0.15, 0), center)
	camera.FieldOfView = 40
	camera.Parent = frame
	frame.CurrentCamera = camera
	return frame
end

function Pets.Build(content, ctx)
	local Lib, State, Net, Config, Util = ctx.Lib, ctx.State, ctx.Net, ctx.Config, ctx.Util
	local New, C = Lib.New, Lib.Colors
	local T = Lib.T

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

	local confirmBulk = {}
	local function bulkButton(rarity: string, text: string, order: number)
		local button
		button = Lib.Button({
			Text = text,
			Color = C.Gold,
			Size = UDim2.fromOffset(150, 38),
			LayoutOrder = order,
			TextSize = 16,
			Parent = actions,
			OnClick = function()
				local last = confirmBulk[rarity]
				if last and os.clock() - last < 2.5 then
					confirmBulk[rarity] = nil
					Net.Fire("SellRarity", rarity)
					Lib.SetButton(button, text)
				else
					confirmBulk[rarity] = os.clock()
					Lib.SetButton(button, T("Tap again to sell"))
					task.delay(2.5, function()
						if button.Parent then
							Lib.SetButton(button, text)
						end
					end)
				end
			end,
		})
		return button
	end
	bulkButton("Common", "💰 Sell Commons", 1)
	bulkButton("Uncommon", "💰 Sell Uncommons", 2)
	Lib.Button({
		Text = "📖 Index",
		Color = Color3.fromRGB(110, 190, 255),
		Size = UDim2.fromOffset(104, 38),
		LayoutOrder = 5,
		TextSize = 16,
		Parent = actions,
		OnClick = function()
			ctx.Panels.Open("Index")
		end,
	})
	Lib.Button({
		Text = "🤝 Trade",
		Color = C.Cyan,
		Size = UDim2.fromOffset(104, 38),
		LayoutOrder = 4,
		TextSize = 16,
		Parent = actions,
		OnClick = function()
			ctx.Panels.Open("Trade")
		end,
	})
	local slotsButton = Lib.Button({
		Text = "🐾 +3 Helpers",
		Color = C.Purple,
		Size = UDim2.fromOffset(150, 38),
		LayoutOrder = 3,
		TextSize = 16,
		Parent = actions,
		OnClick = function()
			if ctx.Upsell then
				ctx.Upsell.Pass("ExtraPets", true)
			end
		end,
	})

	-- how following works (people asked: "who decides which pets follow me?")
	local followInfo = Lib.Text({
		Text = "",
		Font = Lib.BodyFont,
		TextColor3 = C.Sub,
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.fromOffset(0, 74),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 14,
		Parent = content,
	})
	local grid = Lib.Scroll({ Position = UDim2.fromOffset(0, 96), Size = UDim2.new(1, 0, 1, -96), Parent = content })
	Lib.Grid(UDim2.fromOffset(122, 136), 8).Parent = grid
	Lib.Padding(4).Parent = grid

	local signature = ""
	local confirmSell = {} -- [petId] = os.clock()
	local xpBars = {} -- [petId] = fill frame (updated in place)

	local function income(pet)
		return Util.PetIncomeOf(Config, pet)
	end

	-- 🌱 pet detail: grow (feed ✨) and ⭐ evolve -------------------------------
	local selectedId = nil
	local detail = New("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(16, 18, 28),
		BackgroundTransparency = 0.05,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 30,
		Visible = false,
		Parent = content,
	}, { Lib.Corner(14) })
	local detailView = Instance.new("Frame")
	detailView.BackgroundTransparency = 1
	detailView.Size = UDim2.fromOffset(170, 170)
	detailView.Position = UDim2.fromOffset(10, 10)
	detailView.ZIndex = 31
	detailView.Parent = detail
	local function line(y: number, height: number, size: number, color: Color3?)
		return Lib.Text({
			Text = "",
			TextColor3 = color or C.Text,
			Size = UDim2.new(1, -200, 0, height),
			Position = UDim2.fromOffset(190, y),
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxTextSize = size,
			ZIndex = 31,
			Parent = detail,
		})
	end
	local dName = line(10, 30, 26)
	local dStage = line(42, 24, 20, C.Gold)
	local dIncome = line(68, 22, 18, C.Coins)
	local xpBack = New("Frame", {
		BackgroundColor3 = Color3.fromRGB(40, 44, 60),
		Size = UDim2.new(1, -200, 0, 16),
		Position = UDim2.fromOffset(190, 96),
		ZIndex = 31,
		Parent = detail,
	}, { Lib.Corner(8) })
	local xpFill = New("Frame", {
		BackgroundColor3 = C.Green,
		Size = UDim2.fromScale(0, 1),
		ZIndex = 32,
		Parent = xpBack,
	}, { Lib.Corner(8) })
	local xpText = Lib.Text({ Text = "", Size = UDim2.fromScale(1, 1), MaxTextSize = 12, ZIndex = 33, Parent = xpBack })
	local dHelp = Lib.Text({
		Text = "",
		Font = Lib.BodyFont,
		TextColor3 = C.Sub,
		TextWrapped = true,
		Size = UDim2.new(1, -200, 0, 54),
		Position = UDim2.fromOffset(190, 116),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		MaxTextSize = 13,
		ZIndex = 31,
		Parent = detail,
	})
	local feedButton, evolveButton
	local evolveConfirm = 0
	local function act(name: string)
		if not selectedId then
			return
		end
		if name == "PetEvolve" and os.clock() - evolveConfirm > 2.5 then
			-- (evolving uses up copies: tap twice)
			evolveConfirm = os.clock()
			ctx.Toast(T("⭐ Tap again to evolve - it uses %d plain copies of this pet", Config.Growth.Evolve.Copies), C.Purple)
			return
		end
		evolveConfirm = 0
		local result = Net.Invoke(name, selectedId)
		if type(result) == "table" and result.Error then
			Lib.PlaySound("Error")
			ctx.Toast(result.Error, C.Red)
		elseif type(result) == "table" and result.Ok then
			Lib.PlaySound(if name == "PetEvolve" then "Fanfare" elseif result.Up then "LevelUp" else "Pop")
		end
	end
	feedButton = Lib.Button({
		Text = "🍖 Feed",
		Color = C.Green,
		Size = UDim2.new(0.5, -110, 0, 46),
		Position = UDim2.new(0, 190, 1, -58),
		TextSize = 17,
		ZIndex = 31,
		Parent = detail,
		OnClick = function()
			act("PetFeed")
		end,
	})
	evolveButton = Lib.Button({
		Text = "⭐ Evolve",
		Color = C.Purple,
		Size = UDim2.new(0.5, -110, 0, 46),
		Position = UDim2.new(0.5, 90, 1, -58),
		TextSize = 17,
		ZIndex = 31,
		Parent = detail,
		OnClick = function()
			act("PetEvolve")
		end,
	})
	Lib.Button({
		Text = "✕",
		Color = C.Gray,
		Size = UDim2.fromOffset(40, 40),
		Position = UDim2.new(1, -46, 0, 6),
		TextSize = 20,
		ZIndex = 32,
		Parent = detail,
		OnClick = function()
			selectedId = nil
			detail.Visible = false
		end,
	})
	local detailKey = ""
	local function showDetail(data)
		local pet = nil
		for _, p in data.Pets do
			if p.Id == selectedId then
				pet = p
			end
		end
		if not pet or not Config.Pets[pet.Name] then
			detail.Visible = false
			selectedId = nil
			return
		end
		detail.Visible = true
		local growth = Config.Growth
		local level, stars = Util.PetLevel(pet), Util.PetStars(pet)
		local stage = Util.PetStage(Config, level)
		local key = pet.Id .. "|" .. level .. "|" .. stars .. "|" .. tostring(pet.Variant)
		if key ~= detailKey then
			detailKey = key
			Lib.Clear(detailView)
			local vp = viewport(detailView, pet.Name, pet.Variant, { Level = level, Stars = stars })
			vp.Size = UDim2.fromScale(1, 1)
			vp.Position = UDim2.fromScale(0.5, 0)
			vp.ZIndex = 31
		end
		local name = T(pet.Name)
		if pet.Variant then
			name = T(pet.Variant) .. " " .. name
		end
		dName.Text = name .. (if stars > 0 then "  " .. string.rep("★", stars) else "")
		dStage.Text = T("%s %s  •  Level %d/%d", stage.Icon, T(stage.Id), level, growth.MaxLevel)
		dIncome.Text = T("💰 %s/s  •  ⚡ x%s", Util.Format(income(pet)), string.format("%.2f", Util.PetGrowthMult(Config, pet)))
		local maxed = level >= growth.MaxLevel
		if maxed then
			xpFill.Size = UDim2.fromScale(1, 1)
			xpText.Text = T("👑 MAX LEVEL")
		else
			local need = Util.PetXPNeed(Config, pet)
			local xp = tonumber(pet.XP) or 0
			xpFill.Size = UDim2.fromScale(math.clamp(xp / need, 0, 1), 1)
			xpText.Text = string.format("%d / %d XP", xp, need)
		end
		-- copies available for evolving (plain, not more evolved - same rule as the server)
		local copies = #Util.EvolveCopies(Config, data, pet)
		local need = growth.Evolve.Copies
		if stars >= growth.Evolve.MaxStars then
			dHelp.Text = T("★★★ Fully evolved! The best version of this pet.")
		elseif maxed then
			dHelp.Text = T(
				"⭐ Evolve: this pet + %d more %s (you have %d) -> ★%d, x%d income! (back to level 1)",
				need,
				T(pet.Name),
				copies,
				stars + 1,
				growth.Evolve.StarMult
			)
		else
			dHelp.Text = T(
				"🌱 Grows while it follows you and helps, while it stands in your home, and when you feed it ✨ stardust. At level %d it can ⭐ evolve.",
				growth.MaxLevel
			)
		end
		local cost, xp = Util.PetFeed(Config, pet)
		Lib.SetButton(feedButton, if maxed then T("👑 Max") else T("🍖 +%d XP  ✨%s", xp, Util.Format(cost)))
		Lib.SetButton(
			evolveButton,
			if stars >= growth.Evolve.MaxStars then "★★★" else T("⭐ Evolve (%d/%d)", math.min(copies, need), need)
		)
		evolveButton.BackgroundColor3 = if maxed and copies >= need and stars < growth.Evolve.MaxStars then C.Purple else C.Gray
		feedButton.BackgroundColor3 = if maxed then C.Gray elseif (data.Stardust or 0) >= cost then C.Green else C.Gray
	end

	local function pedestalKey(data): string
		local display, vault = Util.Pedestals(Config, data.Base and data.Base.Items or {})
		return #display .. "/" .. #vault
	end

	local function rebuild(data, derived)
		Lib.Clear(grid)
		xpBars = {}
		local following = {}
		for _, id in data.Equipped do
			following[id] = true
		end
		local pets = {}
		for _, pet in data.Pets do
			if Config.Pets[pet.Name] then
				table.insert(pets, pet)
			end
		end
		-- same order as the server uses for pedestals: best income first
		table.sort(pets, function(a, b)
			if income(a) == income(b) then
				return a.Id < b.Id
			end
			return income(a) > income(b)
		end)
		-- same rules as the server (Util.ArrangePets)
		local vaultPets, displayPets = Util.ArrangePets(Config, data)
		local where = {}
		for _, pet in vaultPets do
			where[pet.Id] = "vault"
		end
		for _, pet in displayPets do
			where[pet.Id] = "display"
		end
		local mult = (derived.CoinMult or 1)
			* (if State.HasPass("DoubleBase") then 2 else 1)
			* (1 + Util.SetBonus(Config, data.Base.Items))
			* (1 + Util.IndexBonus(Config, data))
		for order, pet in pets do
			local info = Config.Pets[pet.Name]
			local rarity = Config.Rarities[info.Rarity]
			local place = where[pet.Id]
			local onDisplay = place ~= nil
			local exclusive = info.Exclusive == true
			local card = New("Frame", {
				BackgroundColor3 = if place == "vault"
					then Color3.fromRGB(45, 55, 85)
					elseif onDisplay then Color3.fromRGB(40, 70, 60)
					else C.Card,
				LayoutOrder = order,
				Parent = grid,
			}, {
				Lib.Corner(12),
				Lib.Stroke(if pet.Variant then Color3.fromRGB(255, 210, 60) else rarity.Color, if pet.Variant then 4 else 3, 0),
			})
			-- tap the card: grow / evolve this pet
			local open = New("TextButton", {
				Text = "",
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Parent = card,
			})
			open.Activated:Connect(function()
				Lib.PlaySound("UI")
				selectedId = pet.Id
				detailKey = ""
				showDetail(State.Data)
			end)
			if order <= MAX_VIEWPORTS then
				viewport(card, pet.Name, pet.Variant, { Level = Util.PetLevel(pet), Stars = Util.PetStars(pet) })
			else
				New("Frame", {
					Size = UDim2.fromOffset(44, 44),
					Position = UDim2.new(0.5, 0, 0, 10),
					AnchorPoint = Vector2.new(0.5, 0),
					BackgroundColor3 = info.Color,
					Parent = card,
				}, { Lib.Corner(22), Lib.Stroke(Color3.new(0, 0, 0), 2, 0.3) })
			end
			local name = T(pet.Name)
			if pet.Variant then
				name = T(pet.Variant) .. " " .. name
			end
			if pet.Serial then
				name ..= " #" .. tostring(pet.Serial)
			end
			Lib.Text({
				Text = name,
				Size = UDim2.new(1, -6, 0, 20),
				Position = UDim2.fromOffset(3, 62),
				MaxTextSize = 14,
				Parent = card,
			})
			-- 🌱 level / ★ badge + xp bar
			New("Frame", {
				BackgroundColor3 = Color3.fromRGB(20, 22, 34),
				BackgroundTransparency = 0.2,
				Size = UDim2.fromOffset(58, 20),
				Position = UDim2.new(1, -62, 0, 34),
				ZIndex = 2,
				Parent = card,
			}, {
				Lib.Corner(10),
				Lib.Text({
					Text = Util.PetBadge(Config, pet),
					TextColor3 = C.Gold,
					Size = UDim2.fromScale(1, 1),
					MaxTextSize = 13,
					ZIndex = 3,
				}),
			})
			local level = Util.PetLevel(pet)
			local xpShare = if level >= Config.Growth.MaxLevel
				then 1
				else math.clamp((tonumber(pet.XP) or 0) / Util.PetXPNeed(Config, pet), 0, 1)
			local bar = New("Frame", {
				BackgroundColor3 = Color3.fromRGB(40, 44, 60),
				Size = UDim2.new(1, -10, 0, 4),
				Position = UDim2.fromOffset(5, 104),
				Parent = card,
			}, { Lib.Corner(2) })
			xpBars[pet.Id] = New("Frame", {
				BackgroundColor3 = if level >= Config.Growth.MaxLevel then C.Gold else C.Green,
				Size = UDim2.fromScale(xpShare, 1),
				Parent = bar,
			}, { Lib.Corner(2) })
			local petMult = if place == "vault" then mult * Config.Base.VaultIncome else mult
			Lib.Text({
				Text = "💰" .. Util.Format(income(pet) * petMult) .. "/s",
				TextColor3 = C.Coins,
				Size = UDim2.new(1, -6, 0, 18),
				Position = UDim2.fromOffset(3, 84),
				MaxTextSize = 15,
				Parent = card,
			})
			local status
			if pet.Away then
				status = T("🏃 being stolen!")
			elseif place == "vault" then
				status = T("🔒 safe")
			elseif type(pet.HotUntil) == "number" and pet.HotUntil > os.time() and onDisplay then
				status = T("🔥 just stolen")
			elseif onDisplay and exclusive then
				status = T("💎 safe")
			elseif onDisplay then
				status = T("🏠 on display")
			else
				status = T("📦 storage")
			end
			if following[pet.Id] then
				status = "⭐ " .. status
			end
			Lib.Text({
				Text = status,
				Font = Lib.BodyFont,
				TextColor3 = if onDisplay then C.Green else C.Sub,
				Size = UDim2.new(1, -34, 0, 16),
				Position = UDim2.fromOffset(4, 110),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 11,
				Parent = card,
			})
			if State.NewPets and State.NewPets[pet.Id] then
				New("Frame", {
					BackgroundColor3 = C.Pink,
					Size = UDim2.fromOffset(46, 20),
					Position = UDim2.new(1, -50, 0, 4),
					ZIndex = 3,
					Parent = card,
				}, { Lib.Corner(10), Lib.Text({ Text = "NEW", Size = UDim2.fromScale(1, 1), MaxTextSize = 13, ZIndex = 4 }) })
			end
			-- vault or show off? (exclusive pets are always safe)
			if not pet.Away and not exclusive then
				local toggle = New("TextButton", {
					Text = if pet.Show then "🏠" else "🔒",
					TextScaled = true,
					BackgroundColor3 = if pet.Show then C.Green else C.Blue,
					Size = UDim2.fromOffset(26, 26),
					Position = UDim2.new(0, 4, 0, 4),
					Parent = card,
				}, { Lib.Corner(6) })
				toggle.Activated:Connect(function()
					Lib.PlaySound("UI")
					Net.Fire("PetShow", pet.Id, not pet.Show)
					ctx.Toast(
						if pet.Show
							then T("🔒 This pet may go into a vault again (safe)")
							else T("🏠 This pet stays on display: full income, but it can be stolen!"),
						if pet.Show then C.Blue else C.Gold
					)
				end)
			end
			if not pet.Away then
				local sell = New("TextButton", {
					Text = "💰",
					TextScaled = true,
					BackgroundColor3 = C.Gold,
					Size = UDim2.fromOffset(26, 26),
					Position = UDim2.new(1, -30, 1, -30),
					Parent = card,
				}, { Lib.Corner(6) })
				sell.Activated:Connect(function()
					local last = confirmSell[pet.Id]
					if last and os.clock() - last < 2.5 then
						Net.Fire("SellPet", pet.Id)
					else
						confirmSell[pet.Id] = os.clock()
						sell.Text = "?"
						ctx.Toast(
							T("Tap again to sell for 💰%s", Util.Format(math.max(1, math.floor(income(pet) * Config.PetSellSeconds)))),
							C.Gold
						)
						task.delay(2.5, function()
							if sell.Parent then
								sell.Text = "💰"
							end
						end)
					end
				end)
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
		local player = game:GetService("Players").LocalPlayer
		header.Text = T(
			"🏠 Base 💰%s/s  •  Pets %d/%d  •  Index %d/%d",
			Util.Format(player:GetAttribute("BaseRate") or 0),
			#data.Pets,
			Config.MaxPets,
			indexCount,
			totalPets
		)
		local derivedNow = State.Derived or {}
		followInfo.Text = T(
			"⭐ Your %d strongest pets follow you and help you mine & smash meteors (+%s%% power)",
			derivedNow.PetSlots or Config.BasePetSlots,
			Util.Format(math.floor((derivedNow.PetPower or 0) * 100))
		)
		slotsButton.Visible = not State.HasPass("ExtraPets")
		local parts = {}
		for _, pet in data.Pets do
			table.insert(
				parts,
				pet.Id
					.. (pet.Variant or "")
					.. (if pet.Away then "!" else "")
					.. (if pet.Show then "s" else "")
					.. (pet.Serial or "")
					.. (if type(pet.HotUntil) == "number" and pet.HotUntil > os.time() then "h" else "")
					.. "L"
					.. Util.PetLevel(pet)
					.. "s"
					.. Util.PetStars(pet)
			)
		end
		local newCount = 0
		for _ in State.NewPets or {} do
			newCount += 1
		end
		local sig = table.concat(parts, ",")
			.. "|new"
			.. newCount
			.. "|"
			.. table.concat(data.Equipped, ",")
			.. "|"
			.. tostring(derived.CoinMult)
			.. "|"
			.. pedestalKey(data)
			.. "|"
			.. tostring(Util.SetBonus(Config, data.Base.Items))
			.. "|"
			.. tostring(State.HasPass("DoubleBase"))
		if sig ~= signature then
			signature = sig
			rebuild(data, derived)
		end
		-- xp bars move without rebuilding the grid
		for _, pet in data.Pets do
			local fill = xpBars[pet.Id]
			if fill and Util.PetLevel(pet) < Config.Growth.MaxLevel then
				fill.Size = UDim2.fromScale(math.clamp((tonumber(pet.XP) or 0) / Util.PetXPNeed(Config, pet), 0, 1), 1)
			end
		end
		if selectedId then
			showDetail(data)
		end
	end

	return { Refresh = refresh }
end

return Pets
