-- Playtime gifts: claimable after N minutes in this session (session length)
local Gifts = { Title = "🎁 FREE GIFTS", Color = Color3.fromRGB(255, 90, 160) }

function Gifts.Build(content, ctx)
	local Lib, State, Net, Config, Util = ctx.Lib, ctx.State, ctx.Net, ctx.Config, ctx.Util
	local New, C = Lib.New, Lib.Colors

	Lib.Text({
		Text = "Stay in the game to unlock free gifts!",
		Font = Lib.BodyFont,
		TextColor3 = C.Sub,
		Size = UDim2.new(1, 0, 0, 22),
		MaxTextSize = 18,
		Parent = content,
	})
	local grid = New("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 1, -32), Parent = content }, {
		Lib.Grid(UDim2.fromOffset(150, 160), 12),
	})
	local boxes = {}
	for i, gift in Config.PlaytimeGifts do
		local box = New("Frame", { BackgroundColor3 = C.Card, LayoutOrder = i, Parent = grid }, { Lib.Corner(14), Lib.Stroke(C.Pink, 2, 0.2) })
		Lib.Text({ Text = "🎁", Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 6), MaxTextSize = 40, Parent = box })
		Lib.Text({
			Text = Util.RewardText(gift.Reward),
			Size = UDim2.new(1, -10, 0, 40),
			Position = UDim2.fromOffset(5, 52),
			TextWrapped = true,
			MaxTextSize = 18,
			Parent = box,
		})
		local button = Lib.Button({
			Size = UDim2.new(1, -16, 0, 44),
			Position = UDim2.new(0, 8, 1, -52),
			Parent = box,
			OnClick = function()
				Net.Fire("ClaimGift", i)
			end,
		})
		boxes[i] = { Button = button, Gift = gift }
	end

	local function refresh()
		local derived = State.Derived
		if not derived then
			return
		end
		local elapsed = State.Now() - (derived.SessionStart or State.Now())
		local claimed = {}
		for _, index in derived.GiftsClaimed or {} do
			claimed[index] = true
		end
		for i, box in boxes do
			local remaining = box.Gift.Minutes * 60 - elapsed
			if claimed[i] then
				Lib.SetButton(box.Button, "✔ Claimed", C.Gray)
			elseif remaining <= 0 then
				Lib.SetButton(box.Button, "CLAIM!", C.Green)
			else
				Lib.SetButton(box.Button, Util.FormatTime(remaining), Color3.fromRGB(70, 72, 92))
			end
		end
	end

	return { Refresh = refresh, Tick = refresh }
end

return Gifts
