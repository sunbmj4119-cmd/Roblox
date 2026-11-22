-- Promo codes: free rewards for players who find codes on YouTube / TikTok /
-- Discord / the group wall. Cheap, proven growth loop on Roblox.
local Codes = { Title = "🎟 CODES", Color = Color3.fromRGB(120, 200, 90) }

function Codes.Build(content, ctx)
	local Lib, State, Net = ctx.Lib, ctx.State, ctx.Net
	local New, C = Lib.New, Lib.Colors
	local T = Lib.T

	Lib.Text({
		Text = "Enter a code for free rewards!",
		Size = UDim2.new(1, 0, 0, 36),
		Position = UDim2.fromOffset(0, 20),
		MaxTextSize = 30,
		Parent = content,
	})
	local box = New("TextBox", {
		PlaceholderText = T("Type code here..."),
		Text = "",
		ClearTextOnFocus = false,
		Font = Lib.Font,
		TextScaled = true,
		TextColor3 = Color3.new(1, 1, 1),
		PlaceholderColor3 = Color3.fromRGB(150, 150, 170),
		BackgroundColor3 = C.Card,
		Size = UDim2.new(0.8, 0, 0, 64),
		Position = UDim2.new(0.1, 0, 0, 80),
		Parent = content,
	}, { Lib.Corner(14), Lib.Stroke(C.Gold, 2, 0.2), Lib.Padding(10) })
	local status = Lib.Text({
		Text = "",
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.fromOffset(0, 230),
		MaxTextSize = 24,
		Parent = content,
	})
	local busy = false
	Lib.Button({
		Text = "🎁 REDEEM",
		Color = C.Green,
		Size = UDim2.fromOffset(260, 60),
		Position = UDim2.new(0.5, -130, 0, 160),
		TextSize = 28,
		Parent = content,
		OnClick = function()
			if busy then
				return
			end
			busy = true
			local ok, message = Net.Invoke("RedeemCode", box.Text)
			busy = false
			status.Text = (if ok then "✅ " else "❌ ") .. tostring(message or T("Try again"))
			status.TextColor3 = if ok then C.Green else C.Red
			Lib.Pop(status)
			if ok then
				box.Text = ""
				Lib.PlaySound("Reward")
			end
		end,
	})
	Lib.Text({
		Text = "👍 Like & ⭐ favorite the game - new codes at like milestones!\nFind codes on our group, YouTube and TikTok.",
		Font = Lib.BodyFont,
		TextColor3 = C.Sub,
		TextWrapped = true,
		Size = UDim2.new(1, -40, 0, 60),
		Position = UDim2.fromOffset(20, 290),
		MaxTextSize = 16,
		Parent = content,
	})
	local redeemed = Lib.Text({
		Text = "",
		Font = Lib.BodyFont,
		TextColor3 = C.Sub,
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.fromOffset(0, 360),
		MaxTextSize = 14,
		Parent = content,
	})

	return {
		Refresh = function()
			local data = State.Data
			if data and data.Codes then
				local n = 0
				for _ in data.Codes do
					n += 1
				end
				redeemed.Text = T("Codes redeemed: %d", n)
			end
		end,
	}
end

return Codes
