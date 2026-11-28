-- Zone list: teleport to unlocked zones, unlock the next one
local Teleport = { Title = "🌀 ZONES", Color = Color3.fromRGB(60, 200, 220) }

function Teleport.Build(content, ctx)
	local Lib, State, Net, Config, Util = ctx.Lib, ctx.State, ctx.Net, ctx.Config, ctx.Util
	local New, C = Lib.New, Lib.Colors
	local T = Lib.T

	local scroll = Lib.Scroll({ Parent = content })
	Lib.List(Enum.FillDirection.Vertical, 8).Parent = scroll
	Lib.Padding(4).Parent = scroll

	local rows = {}
	local entries = { { Index = 0, Name = "🏠 Hub (shops, eggs, sell, meteor)", Color = C.Gold } }
	for index, zone in Config.Zones do
		table.insert(
			entries,
			{ Index = index, Name = T(zone.Name) .. (if zone.PvP then "  ⚔️ PVP" else ""), Color = zone.Accent, Zone = zone }
		)
	end
	for order, entry in entries do
		local row = New("Frame", { BackgroundColor3 = C.Card, Size = UDim2.new(1, -12, 0, 60), LayoutOrder = order, Parent = scroll }, {
			Lib.Corner(12),
			Lib.Stroke(entry.Color, 2, 0.2),
		})
		Lib.Text({
			Text = entry.Name,
			TextColor3 = entry.Color,
			Size = UDim2.new(0.6, 0, 0, 30),
			Position = UDim2.fromOffset(14, 15),
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxTextSize = 24,
			Parent = row,
		})
		local button = Lib.Button({
			Size = UDim2.fromOffset(200, 44),
			Position = UDim2.new(1, -210, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Parent = row,
			OnClick = function()
				local data = State.Data
				if not data then
					return
				end
				if entry.Index == 0 or entry.Index <= data.ZoneLevel then
					Net.Fire("Teleport", entry.Index)
					ctx.Panels.Close()
				elseif entry.Index == data.ZoneLevel + 1 then
					Net.Fire("UnlockZone", entry.Index)
				end
			end,
		})
		rows[entry.Index] = { Button = button, Entry = entry }
	end

	local function refresh()
		local data = State.Data
		if not data then
			return
		end
		for index, row in rows do
			if index == 0 or index <= data.ZoneLevel then
				Lib.SetButton(row.Button, "🌀 Teleport", C.Blue)
			elseif index == data.ZoneLevel + 1 then
				local cost = row.Entry.Zone.Cost
				local need = row.Entry.Zone.Strength or 0
				if (data.Strength or 0) < need then
					Lib.SetButton(row.Button, T("💪 Need %s strength", Util.Format(need)), C.Red)
				else
					Lib.SetButton(row.Button, T("🔓 Unlock 💰%s", Util.Format(cost)), if data.Coins >= cost then C.Green else C.Red)
				end
			else
				Lib.SetButton(row.Button, "🔒 " .. Util.Format(row.Entry.Zone.Cost), Color3.fromRGB(70, 72, 92))
			end
		end
	end

	return { Refresh = refresh }
end

return Teleport
