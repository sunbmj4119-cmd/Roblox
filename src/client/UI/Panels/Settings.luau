-- Settings: language (auto / 한국어 / English), sound, how to play
local TeleportService = game:GetService("TeleportService")

local Settings = { Title = "⚙️ SETTINGS", Color = Color3.fromRGB(110, 115, 140) }

function Settings.Build(content, ctx)
	local Lib, State, Net = ctx.Lib, ctx.State, ctx.Net
	local New, C, T = Lib.New, Lib.Colors, Lib.T

	Lib.Text({
		Text = "🌐 Language",
		Size = UDim2.new(1, 0, 0, 34),
		Position = UDim2.fromOffset(0, 10),
		MaxTextSize = 28,
		Parent = content,
	})
	local row = New(
		"Frame",
		{ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 60), Position = UDim2.fromOffset(0, 54), Parent = content },
		{
			Lib.List(Enum.FillDirection.Horizontal, 12, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
		}
	)
	local note = Lib.Text({
		Text = "",
		Font = Lib.BodyFont,
		TextColor3 = C.Sub,
		Size = UDim2.new(1, -40, 0, 24),
		Position = UDim2.fromOffset(20, 122),
		MaxTextSize = 16,
		Parent = content,
	})
	local buttons = {}
	local OPTIONS = { { "auto", "Auto" }, { "ko", "한국어" }, { "en", "English" } }
	for order, option in OPTIONS do
		buttons[option[1]] = Lib.Button({
			Text = option[2],
			Size = UDim2.fromOffset(180, 54),
			LayoutOrder = order,
			TextSize = 26,
			Parent = row,
			OnClick = function()
				local current = State.Data and State.Data.Settings and State.Data.Settings.Lang or "auto"
				if current == option[1] then
					return
				end
				Net.Fire("SetLanguage", option[1])
				note.Text = T("Changing language... rejoining")
				-- the whole UI is built in one language, so rejoin to switch cleanly
				task.delay(1.5, function()
					pcall(function()
						TeleportService:Teleport(game.PlaceId)
					end)
				end)
			end,
		})
	end

	Lib.Text({ Text = "🔊 Sound", Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 170), MaxTextSize = 28, Parent = content })
	local function saveAudio()
		Net.Fire("SetAudio", not Lib.Muted, not Lib.MusicOff)
	end
	local soundButton = Lib.Button({
		Size = UDim2.fromOffset(200, 54),
		Position = UDim2.new(0.5, -316, 0, 214),
		TextSize = 22,
		Parent = content,
		OnClick = function()
			Lib.Muted = not Lib.Muted
			saveAudio()
			ctx.Panels.RefreshCurrent()
		end,
	})
	local musicButton = Lib.Button({
		Size = UDim2.fromOffset(200, 54),
		Position = UDim2.new(0.5, -100, 0, 214),
		TextSize = 22,
		Parent = content,
		OnClick = function()
			if Lib.SetMusic then
				Lib.SetMusic(Lib.MusicOff == true)
			else
				Lib.MusicOff = not Lib.MusicOff
			end
			saveAudio()
			ctx.Panels.RefreshCurrent()
		end,
	})
	Lib.Button({
		Text = "❓ How to play",
		Color = C.Blue,
		Size = UDim2.fromOffset(200, 54),
		Position = UDim2.new(0.5, 116, 0, 214),
		TextSize = 24,
		Parent = content,
		OnClick = function()
			ctx.Panels.Close()
			if ctx.HowTo then
				ctx.HowTo.Show()
			end
		end,
	})

	local function refresh()
		local current = State.Data and State.Data.Settings and State.Data.Settings.Lang or "auto"
		for id, button in buttons do
			Lib.SetButton(button, nil, if id == current then C.Gold else C.Gray)
		end
		Lib.SetButton(soundButton, if Lib.Muted then "🔇 Sound: OFF" else "🔊 Sound: ON", if Lib.Muted then C.Gray else C.Green)
		Lib.SetButton(musicButton, if Lib.MusicOff then "🎵 Music: OFF" else "🎵 Music: ON", if Lib.MusicOff then C.Gray else C.Green)
	end

	return { Refresh = refresh }
end

return Settings
