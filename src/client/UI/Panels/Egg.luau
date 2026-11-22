-- Egg shop: shows exact odds (incl. your luck) BEFORE buying - required for
-- paid random items and good for trust. Golden Egg is hidden where restricted.
local Egg = { Title = "🥚 EGG", Color = Color3.fromRGB(255, 200, 70) }

local CURRENCY_ICON = { Coins = "💰", Gems = "💎", Stardust = "✨" }

function Egg.Build(content, ctx)
	local Lib, State, Net, Config, Util = ctx.Lib, ctx.State, ctx.Net, ctx.Config, ctx.Util
	local New, C = Lib.New, Lib.Colors
	local T = Lib.T
	local eggId = "Meadow"
	local hatching = false

	local info = Lib.Text({
		Text = "",
		Size = UDim2.new(1, 0, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 22,
		Parent = content,
	})
	local luckLabel = Lib.Text({
		Text = "",
		Font = Lib.BodyFont,
		TextColor3 = C.Green,
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.fromOffset(0, 28),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 16,
		Parent = content,
	})
	local grid = Lib.Scroll({ Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, 0, 1, -122), Parent = content })
	Lib.Grid(UDim2.fromOffset(150, 96), 8).Parent = grid
	Lib.Padding(4).Parent = grid

	local buttons = New("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 1, -58),
		Size = UDim2.new(1, 0, 0, 56),
		Parent = content,
	}, { Lib.List(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })

	local function hatch(count: number)
		if hatching then
			return
		end
		local egg = Config.Eggs[eggId]
		if egg.Currency == "Robux" then
			Net.Fire("BuyProduct", if count == 3 then egg.ProductTriple else egg.ProductSingle)
			return
		end
		if count == 3 and not State.HasPass("TripleHatch") then
			if ctx.Upsell then
				ctx.Upsell.Pass("TripleHatch", true)
			end
			return
		end
		hatching = true
		local result = Net.Invoke("Hatch", eggId, count)
		hatching = false
		if type(result) ~= "table" then
			return
		end
		if result.Error then
			ctx.Toast(result.Error, C.Red)
			if result.Upsell and ctx.Upsell then
				ctx.Upsell.Pass(result.Upsell, true)
			end
			return
		end
		if ctx.Hatch then
			ctx.Hatch.Play(result.Pets, eggId)
		end
	end

	local single = Lib.Button({
		Size = UDim2.fromOffset(190, 50),
		LayoutOrder = 1,
		Parent = buttons,
		OnClick = function()
			hatch(1)
		end,
	})
	local triple = Lib.Button({
		Size = UDim2.fromOffset(190, 50),
		LayoutOrder = 2,
		Color = C.Purple,
		Parent = buttons,
		OnClick = function()
			hatch(3)
		end,
	})
	local lucky = Lib.Button({
		Text = "🍀 Lucky Hatch",
		Size = UDim2.fromOffset(170, 50),
		LayoutOrder = 3,
		Color = C.Gold,
		Parent = buttons,
		OnClick = function()
			if ctx.Upsell then
				ctx.Upsell.Pass("Lucky", true)
			end
		end,
	})

	local builtFor = nil
	local cards = {}

	local function buildCards()
		Lib.Clear(grid)
		cards = {}
		local egg = Config.Eggs[eggId]
		for i, entry in egg.Pets do
			local petName = entry[1]
			local pet = Config.Pets[petName]
			local rarity = Config.Rarities[pet.Rarity]
			local card = New("Frame", {
				BackgroundColor3 = C.Card,
				LayoutOrder = i,
				Parent = grid,
			}, { Lib.Corner(12), Lib.Stroke(rarity.Color, 3, 0) })
			local name = Lib.Text({
				Text = petName,
				Size = UDim2.new(1, -8, 0, 24),
				Position = UDim2.fromOffset(4, 4),
				MaxTextSize = 18,
				Parent = card,
			})
			Lib.Text({
				Text = string.upper(T(pet.Rarity)),
				TextColor3 = rarity.Color,
				Size = UDim2.new(1, -8, 0, 18),
				Position = UDim2.fromOffset(4, 28),
				MaxTextSize = 14,
				Parent = card,
			})
			local chance =
				Lib.Text({ Text = "", Size = UDim2.new(1, -8, 0, 22), Position = UDim2.fromOffset(4, 48), MaxTextSize = 20, Parent = card })
			Lib.Text({
				Text = "💥 +" .. Util.Format(pet.Power) .. "x",
				Font = Lib.BodyFont,
				TextColor3 = C.Sub,
				Size = UDim2.new(1, -8, 0, 18),
				Position = UDim2.fromOffset(4, 72),
				MaxTextSize = 14,
				Parent = card,
			})
			cards[petName] = { Chance = chance, Name = name }
		end
	end

	local function refresh()
		local data, derived = State.Data, State.Derived
		if not data then
			return
		end
		luckLabel.TextColor3 = C.Green
		local egg = Config.Eggs[eggId]
		if builtFor ~= eggId then
			builtFor = eggId
			buildCards()
		end
		local luck = derived.Luck or 1
		local odds = Util.Odds(egg.Pets, function(name, weight)
			local rarity = Config.Rarities[Config.Pets[name].Rarity]
			if rarity.Order >= Config.LuckAffectsFromRarity then
				return weight * luck
			end
			return weight
		end)
		for petName, card in cards do
			card.Chance.Text = Util.FormatPercent(odds[petName] or 0)
			local discovered = data.PetIndex[petName] == true
			card.Name.Text = (if discovered then "✔ " else "") .. T(petName)
		end

		local luckText = T("🍀 Your luck: x%s", string.format("%.2f", luck))
		if (workspace:GetAttribute("Server_ServerLuck") or 0) > State.Now() then
			luckText ..= "  •  " .. T("🌟 SERVER LUCK ACTIVE!")
		end
		luckLabel.Text = luckText
		lucky.Visible = not State.HasPass("Lucky")

		if egg.Currency == "Robux" then
			local restricted = derived.PaidRandomRestricted
			info.Text = T("%s  •  exclusive pets, only from this egg", egg.Name)
			single.Visible = not restricted
			triple.Visible = not restricted
			Lib.SetButton(single, T("Hatch 1  R$%s", Lib.Price("Product", egg.ProductSingle)), C.Green)
			Lib.SetButton(triple, T("Hatch 3  R$%s", Lib.Price("Product", egg.ProductTriple)), C.Purple)
			if restricted then
				luckLabel.Text = T("This egg is not available in your region.")
				luckLabel.TextColor3 = C.Red
			else
				luckLabel.TextColor3 = C.Green
			end
		else
			local icon = CURRENCY_ICON[egg.Currency]
			local locked = data.ZoneLevel < egg.Zone
			info.Text = T("%s  •  %s %s each", egg.Name, icon, Util.Format(egg.Price))
			single.Visible = true
			triple.Visible = true
			local balance = data[egg.Currency] or 0
			Lib.SetButton(
				single,
				if locked then "🔒 Unlock zone" else T("Hatch 1  %s", icon .. Util.Format(egg.Price)),
				if balance >= egg.Price then C.Green else C.Red
			)
			local tripleText = if State.HasPass("TripleHatch") then T("Hatch 3  %s", icon .. Util.Format(egg.Price * 3)) else "🔒 Hatch 3"
			Lib.SetButton(triple, tripleText, C.Purple)
		end
	end

	return {
		OnOpen = function(arg)
			if type(arg) == "string" and Config.Eggs[arg] then
				eggId = arg
			end
			local window = content.Parent
			local title = window and window:FindFirstChild("Header") and window.Header:FindFirstChild("Title")
			if title then
				title.Text = "🥚 " .. string.upper(T(Config.Eggs[eggId].Name))
			end
		end,
		Refresh = refresh,
	}
end

return Egg
