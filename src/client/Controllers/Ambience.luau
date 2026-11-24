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
local State = require(Client.State)
local Root = require(Client.UI.Root)

local player = Players.LocalPlayer

local MOODS = {
	[0] = { Title = "🏠 HUB", Tint = Color3.fromRGB(255, 255, 255) },
	[1] = { Title = "🌿 MEADOW MINE", Tint = Color3.fromRGB(245, 255, 235) },
	[2] = { Title = "❄️ FROST CAVERN", Tint = Color3.fromRGB(215, 235, 255) },
	[3] = { Title = "🔥 LAVA DEPTHS", Tint = Color3.fromRGB(255, 222, 200) },
	[4] = { Title = "🔮 CRYSTAL VOID", Tint = Color3.fromRGB(232, 215, 255) },
	[5] = { Title = "⚔️ STAR CRATER", Tint = Color3.fromRGB(255, 210, 232) },
	[-2] = { Title = "🏠 BASES", Tint = Color3.fromRGB(225, 235, 255) }, -- base district
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

-- background music: two players that crossfade, a track for every situation
-- (meteor fight > party > Thief Night > carrying a stolen pet / star >
-- your own house > the base avenue > hub > mines > deep mines). Big
-- fanfares duck the music for a moment (Lib.DuckMusic).
local musicGroup = Instance.new("SoundGroup")
musicGroup.Name = "Music"
musicGroup.Volume = 1
musicGroup.Parent = SoundService
local players = {}
for i = 1, 2 do
	local sound = Instance.new("Sound")
	sound.Name = "BGM" .. i
	sound.Looped = true
	sound.Volume = 0
	sound.SoundGroup = musicGroup
	sound.Parent = musicGroup
	players[i] = sound
end
local active = 1
local currentTrack = ""
local duckUntil = 0
local MUSIC = Config.Music

local function targetVolume(): number
	if Lib.MusicOff then
		return 0
	end
	local volume = MUSIC.Volume or 0.3
	if os.clock() < duckUntil then
		volume *= 0.25
	end
	return volume
end

local function playTrack(id: string)
	if id == currentTrack then
		return
	end
	currentTrack = id
	local old = players[active]
	active = 3 - active
	local nextSound = players[active]
	TweenService:Create(old, TweenInfo.new(1.2), { Volume = 0 }):Play()
	task.delay(1.3, function()
		if players[active] ~= old then
			old:Stop()
		end
	end)
	if id == "" then
		return
	end
	nextSound.SoundId = id
	nextSound.TimePosition = 0
	nextSound.Volume = 0
	nextSound:Play()
	TweenService:Create(nextSound, TweenInfo.new(1.5), { Volume = targetVolume() }):Play()
end

-- big moments: the music steps back so the fanfare shines
Lib.DuckMusic = function(seconds: number)
	duckUntil = math.max(duckUntil, os.clock() + seconds)
	local sound = players[active]
	TweenService:Create(sound, TweenInfo.new(0.25), { Volume = targetVolume() }):Play()
	task.delay(seconds + 0.05, function()
		if os.clock() >= duckUntil then
			TweenService:Create(players[active], TweenInfo.new(1), { Volume = targetVolume() }):Play()
		end
	end)
end

-- (Settings toggles music on/off)
function Lib.SetMusic(on: boolean)
	Lib.MusicOff = not on
	TweenService:Create(players[active], TweenInfo.new(0.5), { Volume = targetVolume() }):Play()
end

-- remembered sound / music settings
local appliedSettings = false
State.OnChanged(function()
	local settings = State.Data and State.Data.Settings
	if settings and not appliedSettings then
		appliedSettings = true
		Lib.Muted = settings.Sfx == false
		Lib.SetMusic(settings.Music ~= false)
	end
end)

local function inOwnPlot(position: Vector3): boolean
	local index = player:GetAttribute("BaseIndex")
	local map = workspace:FindFirstChild("Map")
	local plot = index and map and map:FindFirstChild("Bases") and map.Bases:FindFirstChild("Plot_" .. tostring(index))
	local floor = plot and plot:FindFirstChild("Floor")
	if not floor or not floor:IsA("BasePart") then
		return false
	end
	local p = floor.CFrame:PointToObjectSpace(position)
	local half = Config.Base.PlotSize / 2
	return math.abs(p.X) <= half and math.abs(p.Z) <= half
end

local currentZone = -1

local function wantedTrack(position: Vector3): string
	local now = workspace:GetServerTimeNow()
	if workspace:GetAttribute("MeteorState") == "Active" then
		return MUSIC.Meteor
	end
	if (workspace:GetAttribute("PartyEnd") or 0) > now then
		return MUSIC.Party
	end
	if workspace:GetAttribute("EventId") == "ThiefNight" then
		return MUSIC.Night
	end
	if player:GetAttribute("Carrying") ~= nil and (player:GetAttribute("CarryStolen") or (player:GetAttribute("CarryTier") or 0) >= 3) then
		return MUSIC.Chase
	end
	if currentZone == -2 then
		return if inOwnPlot(position) then MUSIC.Home else MUSIC.Bases
	end
	if currentZone == 0 then
		return MUSIC.Hub
	end
	return if (currentZone or 1) >= 4 then MUSIC.DeepMine else MUSIC.Mine
end

task.spawn(function()
	while true do
		task.wait(0.5)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart
		if root then
			local zone = Util.ZoneAt(Config, root.Position)
			if zone == 0 and Util.InBases(Config, root.Position) then
				zone = -2
			end
			if zone and zone ~= currentZone then
				local first = currentZone == -1
				currentZone = zone
				local mood = MOODS[zone] or MOODS[0]
				TweenService:Create(tint, TweenInfo.new(1.2), { TintColor = mood.Tint }):Play()
				if not first then
					local zoneConfig = Config.Zones[zone]
					showTitle(Lib.T(mood.Title), if zoneConfig then zoneConfig.Accent else Color3.fromRGB(255, 230, 120))
				end
			end
			local ok, track = pcall(wantedTrack, root.Position)
			if ok then
				playTrack(track or "")
			end
		end
	end
end)

return {}
