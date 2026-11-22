-- Free prize wheel: one spin every few hours (VIP: faster). The server picks
-- the prize; the wheel animation reveals it. Odds are always visible.
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Spin = { Title = "🎡 PRIZE WHEEL", Color = Color3.fromRGB(255, 170, 40) }

local BOOST_ICON = { Coins2x = "2x🪙", Luck2x = "2x🍀", Power2x = "2x💥" }

local function short(Util, reward): string
	if reward.Gems then
		return Util.Format(reward.Gems) .. "💎"
	elseif reward.Stardust then
		return Util.Format(reward.Stardust) .. "✨"
	elseif reward.Boost then
		return (BOOST_ICON[reward.Boost[1]] or "Boost") .. "\n" .. math.floor(reward.Boost[2] / 60) .. "m"
	elseif reward.Pet then
		return "🐾 " .. reward.Pet
	end
	return "?"
end

function Spin.Build(content, ctx)
	local Lib, State, Net, Config, Util = ctx.Lib, ctx.State, ctx.Net, ctx.Config, ctx.Util
	local New, C = Lib.New, Lib.Colors
	local rewards = Config.Spin.Rewards
	local count = #rewards
	local step = 360 / count
	local spinning = false

	-- wheel ------------------------------------------------------------------
	local holder = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(340, 340), Position = UDim2.fromOffset(6, 40), Parent = content })
	local wheel = New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(34, 36, 58),
		Parent = holder,
	}, {
		New("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		Lib.Stroke(C.Gold, 5, 0),
	})
	for i = 1, count / 2 do
		New("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, 3, 1, -10),
			Rotation = (i - 1) * step + step / 2,
			BackgroundColor3 = Color3.fromRGB(70, 72, 100),
			BorderSizePixel = 0,
			Parent = wheel,
		})
	end
	for i, entry in rewards do
		local angle = math.rad((i - 1) * step)
		local radius = 0.34
		New("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 + math.sin(angle) * radius, 0.5 - math.cos(angle) * radius),
			Size = UDim2.fromOffset(84, 52),
			Rotation = (i - 1) * step,
			BackgroundColor3 = entry.Color or C.Blue,
			Parent = wheel,
		}, {
			Lib.Corner(12),
			Lib.Stroke(if entry.Jackpot then Color3.new(1, 1, 1) else Color3.new(0, 0, 0), if entry.Jackpot then 3 else 2, 0.2),
			Lib.Gradient(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190)),
			Lib.Text({ Text = short(Util, entry.Reward), Size = UDim2.new(1, -6, 1, -4), Position = UDim2.fromOffset(3, 2), MaxTextSize = 20 }),
		})
	end
	New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(54, 54),
		BackgroundColor3 = C.Gold,
		Parent = wheel,
	}, { New("UICorner", { CornerRadius = UDim.new(0.5, 0) }), Lib.Stroke(Color3.new(0, 0, 0), 3, 0.2) })
	Lib.Text({ Text = "▼", TextColor3 = C.Gold, Size = UDim2.fromOffset(50, 44), Position = UDim2.new(0.5, -25, 0, -36), MaxTextSize = 44, Parent = holder })

	-- info -------------------------------------------------------------------
	local right = New("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(362, 0), Size = UDim2.new(1, -362, 1, 0), Parent = content })
	local result = Lib.Text({ Text = "Spin for free prizes!", Size = UDim2.new(1, 0, 0, 44), MaxTextSize = 30, Parent = right })
	local oddsLines = {}
	local total = 0
	for _, entry in rewards do
		total += entry.Weight
	end
	for i, entry in rewards do
		local text = Util.RewardText(entry.Reward)
		table.insert(oddsLines, string.format("%s  <font color='#BBBBBB'>%s</font>", text, Util.FormatPercent(entry.Weight / total * 100)))
		if entry.Jackpot then
			oddsLines[i] ..= "  🎰 JACKPOT"
		end
	end
	Lib.Text({
		Text = table.concat(oddsLines, "\n"),
		Font = Lib.BodyFont,
		Size = UDim2.new(1, 0, 0, 200),
		Position = UDim2.fromOffset(0, 50),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		MaxTextSize = 15,
		Parent = right,
	})
	local vipHint = Lib.Text({
		Text = "👑 VIP spins every 2 hours",
		Font = Lib.BodyFont,
		TextColor3 = C.Gold,
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.fromOffset(0, 258),
		MaxTextSize = 14,
		Parent = right,
	})
	local spinButton = Lib.Button({
		Text = "🎡 SPIN!",
		Size = UDim2.new(1, -10, 0, 64),
		Position = UDim2.fromOffset(0, 290),
		TextSize = 30,
		Color = C.Gold,
		Parent = right,
	})

	local function readyIn(): number
		local data = State.Data
		if not data then
			return math.huge
		end
		return (data.FreeSpinAt or 0) - State.Now()
	end

	local function refresh()
		if spinning then
			return
		end
		local remaining = readyIn()
		if remaining <= 0 then
			Lib.SetButton(spinButton, "🎡 SPIN!", C.Gold)
		else
			Lib.SetButton(spinButton, "Free spin in " .. Util.FormatTime(remaining), C.Gray)
		end
		vipHint.Visible = not State.HasPass("VIP")
	end

	local function animateTo(index: number, text: string)
		spinning = true
		local start = wheel.Rotation
		local jitter = math.random(-math.floor(step * 0.3), math.floor(step * 0.3))
		local landing = (-(index - 1) * step) % 360
		local final = math.ceil(start / 360) * 360 + 360 * 5 + landing + jitter
		local tween = TweenService:Create(wheel, TweenInfo.new(4.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Rotation = final })
		local lastSlot = math.floor((start + step / 2) / step)
		local ticker = RunService.RenderStepped:Connect(function()
			local slot = math.floor((wheel.Rotation + step / 2) / step)
			if slot ~= lastSlot then
				lastSlot = slot
				Lib.PlaySound("SpinTick")
			end
		end)
		tween:Play()
		tween.Completed:Wait()
		ticker:Disconnect()
		wheel.Rotation = final % 360
		local entry = rewards[index]
		result.Text = "🎉 " .. text
		result.TextColor3 = if entry.Jackpot then C.Gold else C.Green
		Lib.Pop(result)
		Lib.PlaySound(if entry.Jackpot then "Legendary" else "Reward")
		if ctx.Toast then
			ctx.Toast("🎡 Prize: " .. text, C.Gold)
		end
		spinning = false
		refresh()
	end

	spinButton.Activated:Connect(function()
		if spinning then
			return
		end
		if readyIn() > 0 then
			if not State.HasPass("VIP") and ctx.Upsell then
				ctx.Upsell.Pass("VIP", true)
			end
			return
		end
		spinning = true
		Lib.SetButton(spinButton, "...", C.Gray)
		local res = Net.Invoke("Spin")
		if type(res) ~= "table" or not res.Index then
			spinning = false
			if ctx.Toast then
				ctx.Toast((type(res) == "table" and res.Error) or "Try again in a moment", C.Red)
			end
			refresh()
			return
		end
		animateTo(res.Index, res.Text or "")
	end)

	return { Refresh = refresh, Tick = refresh }
end

return Spin
