--[[
	Trade panel.
	* Not trading yet: pick a player in this server to send a request.
	* Trading: tap your pets below to offer up to 4, check what you get,
	  press READY. When both are ready a 3 second countdown swaps the pets.
	  Any change resets READY for both (so nobody can switch at the last second).
]]
local Players = game:GetService("Players")

local Trade = { Title = "🤝 TRADE", Color = Color3.fromRGB(60, 190, 220) }

function Trade.Build(content, ctx)
	local Lib, State, Net, Config, Util = ctx.Lib, ctx.State, ctx.Net, ctx.Config, ctx.Util
	local New, C, T = Lib.New, Lib.Colors, Lib.T
	local player = Players.LocalPlayer

	local status = Lib.Text({
		Text = "",
		Size = UDim2.new(1, 0, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 20,
		Parent = content,
	})

	-- picking a partner -------------------------------------------------------
	local pickList = Lib.Scroll({ Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 1, -34), Parent = content })
	Lib.List(Enum.FillDirection.Vertical, 8).Parent = pickList
	Lib.Padding(4).Parent = pickList

	-- trading ----------------------------------------------------------------
	local tradeView = New("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 1, -34),
		Visible = false,
		Parent = content,
	})
	local function offerRow(y: number, title: string)
		Lib.Text({
			Text = title,
			Size = UDim2.new(0, 130, 0, 30),
			Position = UDim2.fromOffset(0, y + 14),
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxTextSize = 18,
			Parent = tradeView,
		})
		local row = New("Frame", {
			BackgroundColor3 = C.PanelLight,
			Size = UDim2.new(1, -140, 0, 56),
			Position = UDim2.fromOffset(136, y),
			Parent = tradeView,
		}, {
			Lib.Corner(12),
			Lib.Padding(6),
			Lib.List(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center),
		})
		return row
	end
	local myRow = offerRow(0, "You give")
	local theirRow = offerRow(64, "You get")
	local readyButton = Lib.Button({
		Text = "✅ READY",
		Color = C.Green,
		Size = UDim2.fromOffset(170, 46),
		Position = UDim2.fromOffset(136, 128),
		TextSize = 20,
		Parent = tradeView,
	})
	Lib.Button({
		Text = "X Cancel",
		Color = C.Red,
		Size = UDim2.fromOffset(150, 46),
		Position = UDim2.fromOffset(316, 128),
		TextSize = 20,
		Parent = tradeView,
		OnClick = function()
			Net.Fire("TradeCancel")
		end,
	})
	local inventory = Lib.Scroll({ Position = UDim2.fromOffset(0, 184), Size = UDim2.new(1, 0, 1, -184), Parent = tradeView })
	Lib.Grid(UDim2.fromOffset(118, 64), 6).Parent = inventory
	Lib.Padding(4).Parent = inventory

	local myReady = false
	readyButton.Activated:Connect(function()
		Net.Fire("TradeReady", not myReady)
	end)

	local function chip(parent: Instance, pet, order: number)
		local info = Config.Pets[pet.Name]
		local rarity = info and Config.Rarities[info.Rarity] or Config.Rarities.Common
		local frame = New("Frame", {
			BackgroundColor3 = C.Card,
			Size = UDim2.fromOffset(110, 44),
			LayoutOrder = order,
			Parent = parent,
		}, { Lib.Corner(10), Lib.Stroke(rarity.Color, 2.5, 0) })
		Lib.Text({
			Text = (if pet.Variant then T(pet.Variant) .. " " else "") .. T(pet.Name),
			Size = UDim2.new(1, -8, 0, 22),
			Position = UDim2.fromOffset(4, 2),
			MaxTextSize = 14,
			Parent = frame,
		})
		Lib.Text({
			Text = "💰" .. Util.Format(Util.PetIncome(Config, pet.Name, pet.Variant)) .. "/s",
			TextColor3 = C.Coins,
			Size = UDim2.new(1, -8, 0, 16),
			Position = UDim2.fromOffset(4, 24),
			MaxTextSize = 12,
			Parent = frame,
		})
		return frame
	end

	local signature = ""
	local function refresh()
		local data = State.Data
		local state = ctx.TradeUI and ctx.TradeUI.State
		if not data then
			return
		end
		-- only rebuild when something on screen changes (no lost taps mid-press)
		local parts = {}
		if state then
			for _, list in { state.Mine, state.Theirs } do
				for _, pet in list do
					table.insert(parts, tostring(pet.Id))
				end
				table.insert(parts, "|")
			end
			table.insert(parts, tostring(state.MyReady) .. tostring(state.TheirReady) .. tostring(state.Countdown))
			if state.Countdown then
				table.insert(parts, tostring(math.ceil(state.Countdown - State.Now())))
			end
			for _, pet in data.Pets do
				table.insert(parts, pet.Id .. (if pet.Away then "!" else ""))
			end
		else
			for _, other in Players:GetPlayers() do
				table.insert(parts, tostring(other.UserId))
			end
		end
		local sig = (if state then "T" else "P") .. table.concat(parts, ",")
		if sig == signature then
			return
		end
		signature = sig
		if not state then
			-- choose someone
			pickList.Visible = true
			tradeView.Visible = false
			status.Text = T("Pick a player in this server to trade pets with")
			Lib.Clear(pickList)
			local count = 0
			for _, other in Players:GetPlayers() do
				if other ~= player then
					count += 1
					local row = New("Frame", {
						BackgroundColor3 = C.Card,
						Size = UDim2.new(1, -12, 0, 54),
						LayoutOrder = count,
						Parent = pickList,
					}, { Lib.Corner(12) })
					Lib.Text({
						Text = other.DisplayName,
						Size = UDim2.new(1, -190, 1, -10),
						Position = UDim2.fromOffset(14, 5),
						TextXAlignment = Enum.TextXAlignment.Left,
						MaxTextSize = 22,
						Parent = row,
					})
					Lib.Button({
						Text = "🤝 Trade",
						Color = C.Cyan,
						Size = UDim2.fromOffset(150, 42),
						Position = UDim2.new(1, -160, 0.5, 0),
						AnchorPoint = Vector2.new(0, 0.5),
						TextSize = 20,
						Parent = row,
						OnClick = function()
							Net.Fire("TradeRequest", other.UserId)
						end,
					})
				end
			end
			if count == 0 then
				status.Text = T("Nobody else is in this server yet")
			end
			return
		end

		pickList.Visible = false
		tradeView.Visible = true
		myReady = state.MyReady == true
		local text = T("Trading with %s", state.Partner)
		if state.Countdown then
			local left = math.max(0, math.ceil(state.Countdown - State.Now()))
			text ..= "  •  " .. T("Swapping in %ds...", left)
		elseif state.TheirReady then
			text ..= "  •  " .. T("They are READY")
		end
		status.Text = text
		Lib.SetButton(readyButton, if myReady then T("✅ READY!") else T("Press READY"), if myReady then C.Green else C.Gray)

		for _, row in { myRow, theirRow } do
			for _, child in row:GetChildren() do
				if child:IsA("Frame") then
					child:Destroy()
				end
			end
		end
		local offered = {}
		for i, pet in state.Mine do
			offered[pet.Id] = true
			chip(myRow, pet, i)
		end
		for i, pet in state.Theirs do
			chip(theirRow, pet, i)
		end

		-- my pets: tap to add / remove from the offer
		Lib.Clear(inventory)
		local pets = table.clone(data.Pets)
		table.sort(pets, function(a, b)
			return Util.PetIncome(Config, a.Name, a.Variant) > Util.PetIncome(Config, b.Name, b.Variant)
		end)
		for order, pet in pets do
			if not pet.Away and Config.Pets[pet.Name] then
				local card = chip(inventory, pet, order)
				if offered[pet.Id] then
					card.BackgroundColor3 = Color3.fromRGB(40, 90, 60)
				end
				local button = New("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = card })
				button.Activated:Connect(function()
					local ids = {}
					for _, mine in state.Mine do
						if mine.Id ~= pet.Id then
							table.insert(ids, mine.Id)
						end
					end
					if not offered[pet.Id] then
						if #ids >= 4 then
							ctx.Toast(T("You can offer up to 4 pets"), C.Red)
							return
						end
						table.insert(ids, pet.Id)
					end
					Net.Fire("TradeSetOffer", ids)
				end)
			end
		end
	end

	-- keep the partner list fresh while the panel is open
	Players.PlayerAdded:Connect(function()
		refresh()
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(refresh)
	end)

	return {
		Refresh = refresh,
		Tick = function()
			local state = ctx.TradeUI and ctx.TradeUI.State
			if state and state.Countdown then
				refresh()
			end
		end,
		OnOpen = function()
			refresh()
		end,
	}
end

return Trade
