--[[
	Zone ambience: entering a zone tints the screen to its mood, shows a big
	zone title (sense of progress/exploration) and switches background music
	if you set music ids in Config.Music.
]]
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)

local Client = script.Parent.Parent
local Lib = require(Client.UI.Lib)
local Root = require(Client.UI.Root)

local player = Players.LocalPlayer

local MOODS = {
	[0] = { Title = "🏠 HUB", Tint = Color3.fromRGB(255, 255, 255) },
	[1] = { Title = "🌿 MEADOW MINE", Tint = Color3.fromRGB(245, 255, 235) },
	[2] = { Title = "❄️ FROST CAVERN", Tint = Color3.fromRGB(215, 235, 255) },
	[3] = { Title = "🔥 LAVA DEPTHS", Tint = Color3.fromRGB(255, 222, 200) },
	[4] = { Title = "🔮 CRYSTAL VOID", Tint = Color3.fromRGB(232, 215, 255) },
	[5] = { Title = "⚔️ STAR CRATER", Tint = Color3.fromRGB(255, 210, 232) },
}

local tint = Instance.new("ColorCorrectionEffect")
tint.Name = "ZoneTint"
tint.Parent = Lighting

-- big zone title
local cluster = Root.Cluster("ZoneTitle", Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.22), UDim2.fromOffset(600, 80))
local title = Lib.Text({ Text = "", Size = UDim2.fromScale(1, 1), MaxTextSize = 60, Visible = false, Parent = cluster })
local titleToken = 0
local function showTitle(text: string, color: Color3)
	titleToken += 1
	local token = titleToken
	title.Text = text
	title.TextColor3 = color
	title.TextTransparency = 0
	title.Visible = true
	Lib.Pop(title)
	task.delay(1.8, function()
		if token ~= titleToken then
			return
		end
		local tween = TweenService:Create(title, TweenInfo.new(0.6), { TextTransparency = 1 })
		tween:Play()
		tween.Completed:Wait()
		if token == titleToken then
			title.Visible = false
		end
	end)
end

-- optional music
local music = Instance.new("Sound")
music.Name = "BGM"
music.Looped = true
music.Volume = 0
music.Parent = SoundService
local currentTrack = ""
local function playTrack(id: string)
	if id == currentTrack then
		return
	end
	currentTrack = id
	TweenService:Create(music, TweenInfo.new(0.8), { Volume = 0 }):Play()
	task.delay(0.8, function()
		if currentTrack ~= id then
			return
		end
		if id == "" then
			music:Stop()
			return
		end
		music.SoundId = id
		music:Play()
		TweenService:Create(music, TweenInfo.new(1.2), { Volume = Config.Music.Volume or 0.3 }):Play()
	end)
end

local currentZone = -1
task.spawn(function()
	while true do
		task.wait(0.5)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart
		if root then
			local zone = Util.ZoneAt(Config, root.Position)
			if zone and zone ~= currentZone then
				local first = currentZone == -1
				currentZone = zone
				local mood = MOODS[zone] or MOODS[0]
				TweenService:Create(tint, TweenInfo.new(1.2), { TintColor = mood.Tint }):Play()
				if not first then
					local zoneConfig = Config.Zones[zone]
					showTitle(mood.Title, if zoneConfig then zoneConfig.Accent else Color3.fromRGB(255, 230, 120))
				end
			end
			local meteorActive = workspace:GetAttribute("MeteorState") == "Active"
			local wanted = if meteorActive and Config.Music.Meteor ~= ""
				then Config.Music.Meteor
				elseif currentZone == 0 then Config.Music.Hub
				else Config.Music.Mine
			playTrack(wanted or "")
		end
	end
end)

return {}
