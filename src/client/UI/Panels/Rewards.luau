-- One place for every free reward (instead of 4 separate menu buttons)
local Rewards = { Title = "🎁 REWARDS", Color = Color3.fromRGB(255, 90, 160) }

function Rewards.Build(content, ctx)
	local Lib, State = ctx.Lib, ctx.State
	local New, C, T = Lib.New, Lib.Colors, Lib.T

	local grid = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = content }, {
		Lib.Grid(UDim2.fromOffset(315, 190), 14),
	})
	local tiles = {}
	local DEFS = {
		{ "Quests", "📅", "Daily & Quests", Color3.fromRGB(90, 160, 255) },
		{ "Gifts", "🎁", "Free Gifts", Color3.fromRGB(255, 90, 160) },
		{ "Spin", "🎡", "Prize Wheel", Color3.fromRGB(255, 170, 40) },
		{ "Codes", "🎟", "Codes", Color3.fromRGB(120, 200, 90) },
	}
	for order, def in DEFS do
		local tile = New("TextButton", {
			Text = "",
			AutoButtonColor = true,
			BackgroundColor3 = def[4],
			LayoutOrder = order,
			Parent = grid,
		}, { Lib.Corner(18), Lib.Stroke(Color3.new(0, 0, 0), 3, 0.3), Lib.Gradient(Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 170)) })
		Lib.Text({
			Text = def[2],
			Size = UDim2.new(1, 0, 0, 70),
			Position = UDim2.fromOffset(0, 12),
			MaxTextSize = 60,
			Outline = false,
			Parent = tile,
		})
		Lib.Text({ Text = def[3], Size = UDim2.new(1, -16, 0, 36), Position = UDim2.fromOffset(8, 86), MaxTextSize = 28, Parent = tile })
		local status = Lib.Text({
			Text = "",
			Font = Lib.BodyFont,
			Size = UDim2.new(1, -16, 0, 26),
			Position = UDim2.fromOffset(8, 128),
			MaxTextSize = 18,
			Parent = tile,
		})
		local badge = New("Frame", {
			BackgroundColor3 = C.Red,
			Size = UDim2.fromOffset(30, 30),
			Position = UDim2.new(1, -24, 0, -8),
			Visible = false,
			ZIndex = 3,
			Parent = tile,
		}, { Lib.Corner(15), Lib.Stroke(Color3.new(1, 1, 1), 2, 0) })
		Lib.Text({ Text = "!", Size = UDim2.fromScale(1, 1), MaxTextSize = 22, ZIndex = 4, Parent = badge })
		tile.Activated:Connect(function()
			Lib.PlaySound("UI")
			ctx.Panels.Open(def[1])
		end)
		tiles[def[1]] = { Status = status, Badge = badge }
	end

	local function refresh()
		local data = State.Data
		local hud = ctx.HUD
		if not data or not hud then
			return
		end
		local ready = hud.RewardsReady()
		tiles.Quests.Badge.Visible = ready.Quests == true
		tiles.Quests.Status.Text = if ready.Quests then T("Rewards ready to claim!") else T("Come back tomorrow")
		tiles.Gifts.Badge.Visible = ready.Gifts == true
		tiles.Gifts.Status.Text = if ready.Gifts then T("A gift is ready!") else T("Stay online for gifts")
		tiles.Spin.Badge.Visible = ready.Spin == true
		local left = (data.FreeSpinAt or 0) - State.Now()
		tiles.Spin.Status.Text = if left <= 0 then T("Free spin ready!") else T("Next free spin in %s", ctx.Util.FormatTime(left))
		tiles.Codes.Status.Text = T("Enter codes for free rewards")
	end

	return { Refresh = refresh, Tick = refresh }
end

return Rewards
