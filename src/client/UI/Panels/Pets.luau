--[[
	Pet collection: every pet you own, best earners first.
	🔒 = in a VAULT (can never be stolen, 50% income)
	🏠 = on display (full income, thieves can try to take it)
	💎 = exclusive (never stolen)   ⭐ = following you   📦 = storage
	Tap 🔒/🏠 on a card to choose: keep it safe in a vault, or show it off.
	Tap 💰 twice to sell a pet (pays one minute of its income).
]]
local PetModel = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("PetModel"))

local Pets = { Title = "🐾 PETS", Color = Color3.fromRGB(120, 200, 90) }

local MAX_VIEWPORTS = 24 -- 3D previews for the best pets (keeps phones smooth)

local function viewport(parent: GuiObject, petName: string, variant: string?)
	local frame = Instance.new("ViewportFrame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromOffset(64, 56)
	frame.Position = UDim2.new(0.5, 0, 0, 4)
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Ambient = Color3.fromRGB(200, 200, 210)
	frame.LightColor = Color3.new(1, 1, 1)
	frame.Parent = parent
	local model = PetModel.Build(petName, variant)
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
			Size = UDim2.fromOffset(170, 38),
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
		Text = "🤝 Trade",
		Color = C.Cyan,
		Size = UDim2.fromOffset(120, 38),
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

	local grid = Lib.Scroll({ Position = UDim2.fromOffset(0, 78), Size = UDim2.new(1, 0, 1, -78), Parent = content })
	Lib.Grid(UDim2.fromOffset(122, 136), 8).Parent = grid
	Lib.Padding(4).Parent = grid

	local signature = ""
	local confirmSell = {} -- [petId] = os.clock()

	local function income(pet)
		return Util.PetIncome(Config, pet.Name, pet.Variant)
	end

	local function pedestalKey(data): string
		local display, vault = Util.Pedestals(Config, data.Base and data.Base.Items or {})
		return #display .. "/" .. #vault
	end

	local function rebuild(data, derived)
		Lib.Clear(grid)
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
		local mult = (derived.CoinMult or 1) * (if State.HasPass("DoubleBase") then 2 else 1) * (1 + Util.SetBonus(Config, data.Base.Items))
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
			if order <= MAX_VIEWPORTS then
				viewport(card, pet.Name, pet.Variant)
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
							then T("🔒 This pet may go into a vault again (safe, half income)")
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
						ctx.Toast(T("Tap again to sell for 💰%s", Util.Format(math.floor(income(pet) * Config.PetSellSeconds))), C.Gold)
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
		slotsButton.Visible = not State.HasPass("ExtraPets")
		local parts = {}
		for _, pet in data.Pets do
			table.insert(
				parts,
				pet.Id .. (pet.Variant or "") .. (if pet.Away then "!" else "") .. (if pet.Show then "s" else "") .. (pet.Serial or "")
			)
		end
		local sig = table.concat(parts, ",")
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
	end

	return { Refresh = refresh }
end

return Pets
