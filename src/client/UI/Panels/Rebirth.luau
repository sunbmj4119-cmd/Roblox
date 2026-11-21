-- Rebirth: reset coins/upgrades for a permanent coin multiplier + gems
local Rebirth = { Title = "♻️ REBIRTH", Color = Color3.fromRGB(170, 90, 255) }

function Rebirth.Build(content, ctx)
	local Lib, State, Net, Config, Util = ctx.Lib, ctx.State, ctx.Net, ctx.Config, ctx.Util
	local C = Lib.Colors

	local big = Lib.Text({ Text = "", Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 10), MaxTextSize = 40, Parent = content })
	local mult = Lib.Text({ Text = "", Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 62), MaxTextSize = 30, TextColor3 = C.Gold, Parent = content })
	local perks = Lib.Text({
		Text = "",
		Font = Lib.BodyFont,
		Size = UDim2.new(1, -40, 0, 60),
		Position = UDim2.fromOffset(20, 104),
		TextWrapped = true,
		MaxTextSize = 18,
		Parent = content,
	})
	local _, setBar = Lib.Bar({ Size = UDim2.new(1, -80, 0, 30), Position = UDim2.fromOffset(40, 176), Color = C.Purple, TextSize = 20, Parent = content })
	Lib.Text({
		Text = "⚠️ Resets: coins, pickaxe, backpack.  Keeps: pets, zones, gems, stardust, passes.",
		Font = Lib.BodyFont,
		TextColor3 = C.Sub,
		Size = UDim2.new(1, -40, 0, 22),
		Position = UDim2.fromOffset(20, 218),
		MaxTextSize = 15,
		Parent = content,
	})
	local button = Lib.Button({
		Size = UDim2.fromOffset(300, 64),
		Position = UDim2.new(0.5, 0, 0, 256),
		AnchorPoint = Vector2.new(0.5, 0),
		TextSize = 30,
		Parent = content,
		OnClick = function()
			Net.Fire("Rebirth")
		end,
	})

	local function refresh()
		local data, derived = State.Data, State.Derived
		if not data then
			return
		end
		local r = data.Rebirths
		local per = Config.Rebirth.CoinBonusPer
		local cost = derived.RebirthCost or Util.RebirthCost(Config, r)
		big.Text = "Rebirths: " .. r
		mult.Text = string.format("🪙 x%s  ➜  x%s coins", Util.Format(1 + r * per), Util.Format(1 + (r + 1) * per))
		local nextSlot = Config.Rebirth.ExtraPetSlotEvery - (r % Config.Rebirth.ExtraPetSlotEvery)
		perks.Text = string.format(
			"Reward: +%s 💎 gems  •  +1 pet slot every %d rebirths (next in %d)",
			Util.Format(Config.Rebirth.GemsPer * (r + 1)),
			Config.Rebirth.ExtraPetSlotEvery,
			nextSlot
		)
		setBar(data.Coins / cost, string.format("🪙 %s / %s", Util.Format(data.Coins), Util.Format(cost)))
		local ready = data.Coins >= cost
		Lib.SetButton(button, if ready then "♻️ REBIRTH NOW" else "Need " .. Util.Format(cost - data.Coins) .. " more", if ready then C.Purple else C.Gray)
	end

	return { Refresh = refresh }
end

return Rebirth
