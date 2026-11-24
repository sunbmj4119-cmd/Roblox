--[[
	Houses: every house in this server, most liked first.
	Visit one (you arrive at its gate), tap the ❤️ post there to like it -
	the owner gets gems + ranked points. Your own house: "Go home".
]]
local Players = game:GetService("Players")

local Houses = { Title = "🏘️ HOUSES", Color = Color3.fromRGB(255, 130, 170) }

local LEVEL_ICONS = { "🏡", "🏘️", "🏛️", "🏰", "🌌" }

function Houses.Build(content, ctx)
	local Lib, Net, Util = ctx.Lib, ctx.Net, ctx.Util
	local New, C, T = Lib.New, Lib.Colors, Lib.T
	local player = Players.LocalPlayer

	Lib.Text({
		Text = "Visit houses in this server • tap ❤️ at their gate to like them",
		Font = Lib.BodyFont,
		TextColor3 = C.Sub,
		Size = UDim2.new(1, 0, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 15,
		Parent = content,
	})
	local list = Lib.Scroll({ Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 1, -30), Parent = content })
	Lib.List(Enum.FillDirection.Vertical, 8).Parent = list
	Lib.Padding(4).Parent = list

	local function houses()
		local result = {}
		local map = workspace:FindFirstChild("Map")
		local bases = map and map:FindFirstChild("Bases")
		for _, plot in (bases and bases:GetChildren() or {}) do
			local ownerId = plot:GetAttribute("OwnerId")
			if type(ownerId) == "number" and ownerId ~= 0 then
				table.insert(result, {
					OwnerId = ownerId,
					Name = plot:GetAttribute("HouseName") or "",
					Owner = plot:GetAttribute("OwnerName") or "?",
					Level = plot:GetAttribute("HouseLevel") or 1,
					Likes = plot:GetAttribute("Likes") or 0,
					Rate = plot:GetAttribute("Rate") or 0,
					Protection = plot:GetAttribute("Protection") or "",
				})
			end
		end
		table.sort(result, function(a, b)
			if a.Likes ~= b.Likes then
				return a.Likes > b.Likes
			end
			if a.Level ~= b.Level then
				return a.Level > b.Level
			end
			return a.OwnerId < b.OwnerId
		end)
		return result
	end

	local signature = ""
	local function refresh()
		local entries = houses()
		local parts = {}
		for _, h in entries do
			table.insert(parts, table.concat({ h.OwnerId, h.Name, h.Level, h.Likes, h.Rate, h.Protection }, ":"))
		end
		local sig = table.concat(parts, ",")
		if sig == signature then
			return
		end
		signature = sig
		Lib.Clear(list)
		for order, h in entries do
			local mine = h.OwnerId == player.UserId
			local row = New("Frame", {
				BackgroundColor3 = if mine then Color3.fromRGB(45, 70, 60) else C.Card,
				Size = UDim2.new(1, -12, 0, 64),
				LayoutOrder = order,
				Parent = list,
			}, { Lib.Corner(12), Lib.Stroke(if order == 1 then C.Gold else Color3.new(0, 0, 0), 2, if order == 1 then 0 else 0.5) })
			local medal = if order == 1 then "🥇 " elseif order == 2 then "🥈 " elseif order == 3 then "🥉 " else ""
			local title = if h.Name ~= "" then h.Name else T("%s's House", h.Owner)
			Lib.Text({
				Text = medal .. (LEVEL_ICONS[h.Level] or "🏠") .. " " .. title,
				Size = UDim2.new(1, -200, 0, 30),
				Position = UDim2.fromOffset(12, 4),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 21,
				Parent = row,
			})
			local shield = if h.Protection == "locked"
				then "🔒"
				elseif h.Protection == "newbie" or h.Protection == "shield" then "🛡️"
				else ""
			Lib.Text({
				Text = T("by %s  •  Lv.%d  •  ❤️ %s  •  💰%s/s", h.Owner, h.Level, Util.Comma(h.Likes), Util.Format(h.Rate))
					.. " "
					.. shield,
				Font = Lib.BodyFont,
				TextColor3 = C.Sub,
				Size = UDim2.new(1, -200, 0, 20),
				Position = UDim2.fromOffset(12, 36),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 14,
				Parent = row,
			})
			Lib.Button({
				Text = if mine then "🏠 Go home" else "🚪 Visit",
				Color = if mine then C.Green else C.Pink,
				Size = UDim2.fromOffset(170, 46),
				Position = UDim2.new(1, -180, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				TextSize = 19,
				Parent = row,
				OnClick = function()
					if mine then
						Net.Fire("GoBase")
					else
						Net.Fire("VisitBase", h.OwnerId)
					end
					ctx.Panels.Close()
				end,
			})
		end
		if #entries == 0 then
			Lib.Text({ Text = T("No houses yet"), Size = UDim2.new(1, 0, 0, 40), Parent = list })
		end
	end

	return {
		Refresh = refresh,
		Tick = refresh,
		OnOpen = function()
			signature = ""
			refresh()
		end,
	}
end

return Houses
