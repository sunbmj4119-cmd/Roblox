--[[
	WorldService: builds the whole map procedurally (no assets required):
	hub plaza, shops, egg stands, sell pad, meteor crater, leaderboards and
	five mining zones separated by gates. Swap any part for a real model later.
]]
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Net = require(script.Parent.Net)

local World = {}
local Services

local LAYOUT = Config.World.Layout
local HUB_HALF = LAYOUT.HubHalf
local ZONE_W = LAYOUT.ZoneWidth
local ZONE_L = LAYOUT.ZoneLength
local GAP = LAYOUT.Gap
local FIRST_Z = LAYOUT.FirstZ
local CORRIDOR_W = 24
local WALL_H = 16

-- per-zone ambient particles (index = zone)
local AMBIENCE = {
	{ -- Meadow: fireflies
		Color = Color3.fromRGB(220, 255, 120),
		Light = 1,
		Size = 0.25,
		Life = { 3, 5 },
		Rate = 14,
		Speed = { 0.4, 1.2 },
		Acceleration = Vector3.new(0, 0.3, 0),
		Direction = Enum.NormalId.Top,
		Height = 4,
	},
	{ -- Frost: snow
		Color = Color3.fromRGB(240, 250, 255),
		Light = 0.3,
		Size = 0.35,
		Life = { 7, 9 },
		Rate = 45,
		Speed = { 2, 4 },
		Acceleration = Vector3.new(0.5, -1, 0),
		Direction = Enum.NormalId.Bottom,
		Height = 30,
	},
	{ -- Lava: rising embers
		Color = Color3.fromRGB(255, 130, 40),
		Light = 1,
		Size = 0.3,
		Life = { 3, 5 },
		Rate = 35,
		Speed = { 3, 6 },
		Acceleration = Vector3.new(0, 2, 0),
		Direction = Enum.NormalId.Top,
		Height = 0.6,
	},
	{ -- Void: drifting motes
		Color = Color3.fromRGB(190, 120, 255),
		Light = 1,
		Size = 0.4,
		Life = { 4, 6 },
		Rate = 22,
		Speed = { 0.5, 1.5 },
		Acceleration = Vector3.new(0, 0.5, 0),
		Direction = Enum.NormalId.Top,
		Height = 6,
	},
	{ -- Star Crater: falling stars
		Color = Color3.fromRGB(255, 140, 220),
		Light = 1,
		Size = 0.5,
		Life = { 4, 6 },
		Rate = 28,
		Speed = { 6, 10 },
		Acceleration = Vector3.new(1, -2, 0),
		Direction = Enum.NormalId.Bottom,
		Height = 45,
	},
}

World.Zones = {}
World.OreSlots = {}
World.Boards = {}
World.PvPZone = 0
World.HubSpawn = CFrame.new(0, 4, -60)

local map = Instance.new("Folder")
map.Name = "Map"

local function folder(name: string, parent: Instance)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function newPart(props, parent: Instance?)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent or map
	return p
end

-- marks a world TextLabel for client-side translation (LangFmt + JSON args)
function World.SetText(label: TextLabel, fmt: string, ...)
	local args = { ... }
	for i, v in args do
		if type(v) ~= "string" then
			args[i] = tostring(v)
		end
	end
	label:SetAttribute("LangFmt", fmt)
	label:SetAttribute("LangArgs", HttpService:JSONEncode(args))
	local ok, text = pcall(string.format, fmt, table.unpack(args))
	label.Text = if ok then text else fmt
end

-- width / height are in STUDS so labels shrink with distance like real signs
local function billboard(adornee: BasePart, fmt: string, color: Color3, offsetY: number, width: number?, height: number?, ...)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.new(width or 12, 0, height or 3, 0)
	gui.StudsOffsetWorldSpace = Vector3.new(0, offsetY, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 160
	gui.AlwaysOnTop = false
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	label.RichText = true
	World.SetText(label, fmt, ...)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = adornee
	return gui, label
end

local function prompt(parent: BasePart, actionText: string, objectText: string, handler)
	local p = Instance.new("ProximityPrompt")
	p.ActionText = actionText
	p.ObjectText = objectText
	p.HoldDuration = 0
	p.MaxActivationDistance = 12
	p.RequiresLineOfSight = false
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.Parent = parent
	p.Triggered:Connect(function(player)
		local ok, err = pcall(handler, player)
		if not ok then
			warn("[World] prompt failed: " .. tostring(err))
		end
	end)
	return p
end

local function openPanel(panel: string, arg: any?)
	return function(player)
		Net:Send(player, "OpenPanel", panel, arg)
	end
end

function World.ZoneStart(index: number): number
	return FIRST_Z + (index - 1) * (ZONE_L + GAP)
end

-- 0 = hub, 1..n = zone index, nil = outside
function World:ZoneAt(position: Vector3): number?
	if math.abs(position.X) <= HUB_HALF and math.abs(position.Z) <= HUB_HALF then
		return 0
	end
	if Util.InBases(Config, position) then
		return 0
	end
	if math.abs(position.X) > ZONE_W / 2 + 1 then
		return nil
	end
	for index, zone in self.Zones do
		if position.Z >= zone.ZStart and position.Z <= zone.ZEnd then
			return index
		end
	end
	return nil
end

function World:SpawnFor(index: number): CFrame
	if index == 0 or not self.Zones[index] then
		return self.HubSpawn
	end
	return self.Zones[index].Spawn
end

---------------------------------------------------------------------------
-- builders
---------------------------------------------------------------------------
local function wall(cf: CFrame, size: Vector3, color: Color3, parent)
	return newPart({
		Name = "Wall",
		CFrame = cf,
		Size = size,
		Color = color,
		Material = Enum.Material.Rock,
	}, parent)
end

local function tree(position: Vector3, parent)
	newPart({
		Name = "Trunk",
		Size = Vector3.new(2, 8, 2),
		CFrame = CFrame.new(position + Vector3.new(0, 4, 0)),
		Color = Color3.fromRGB(110, 75, 45),
		Material = Enum.Material.Wood,
	}, parent)
	newPart({
		Name = "Leaves",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 9,
		CFrame = CFrame.new(position + Vector3.new(0, 10, 0)),
		Color = Color3.fromRGB(70, 160, 70),
		Material = Enum.Material.LeafyGrass,
	}, parent)
end

local function lamp(position: Vector3, color: Color3, parent)
	newPart({
		Name = "LampPost",
		Size = Vector3.new(0.8, 10, 0.8),
		CFrame = CFrame.new(position + Vector3.new(0, 5, 0)),
		Color = Color3.fromRGB(40, 40, 45),
		Material = Enum.Material.Metal,
	}, parent)
	local bulb = newPart({
		Name = "Bulb",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 2,
		CFrame = CFrame.new(position + Vector3.new(0, 10.5, 0)),
		Color = color,
		Material = Enum.Material.Neon,
		CanCollide = false,
	}, parent)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 22
	light.Brightness = 1.2
	light.Parent = bulb
end

local function booth(position: Vector3, title: string, color: Color3, parent)
	local base = newPart({
		Name = "BoothBase",
		Size = Vector3.new(14, 1, 14),
		CFrame = CFrame.new(position + Vector3.new(0, 0.5, 0)),
		Color = Color3.fromRGB(60, 60, 70),
		Material = Enum.Material.WoodPlanks,
	}, parent)
	for _, offset in { Vector3.new(-6, 0, -6), Vector3.new(6, 0, -6), Vector3.new(-6, 0, 6), Vector3.new(6, 0, 6) } do
		newPart({
			Name = "Pillar",
			Size = Vector3.new(1, 9, 1),
			CFrame = CFrame.new(position + offset + Vector3.new(0, 5.5, 0)),
			Color = Color3.fromRGB(240, 240, 240),
			Material = Enum.Material.SmoothPlastic,
		}, parent)
	end
	newPart({
		Name = "Roof",
		Size = Vector3.new(16, 1.2, 16),
		CFrame = CFrame.new(position + Vector3.new(0, 10.6, 0)),
		Color = color,
		Material = Enum.Material.SmoothPlastic,
	}, parent)
	local counter = newPart({
		Name = "Counter",
		Size = Vector3.new(8, 3.5, 3),
		CFrame = CFrame.new(position + Vector3.new(0, 2.75, 0)),
		Color = color:Lerp(Color3.new(1, 1, 1), 0.25),
		Material = Enum.Material.SmoothPlastic,
	}, parent)
	billboard(base, title, Color3.new(1, 1, 1), 13, 13, 3)
	return counter
end

local function eggStand(position: Vector3, eggId: string, parent)
	local egg = Config.Eggs[eggId]
	newPart({
		Name = "Pedestal",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, 10, 10),
		CFrame = CFrame.new(position + Vector3.new(0, 1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(235, 235, 240),
		Material = Enum.Material.Marble,
	}, parent)
	local eggPart = newPart({
		Name = eggId .. "Egg",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(6, 6, 6),
		CFrame = CFrame.new(position + Vector3.new(0, 5.5, 0)),
		Color = egg.Color,
		Material = if egg.Currency == "Robux" then Enum.Material.Foil else Enum.Material.SmoothPlastic,
	}, parent)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1.3, 1)
	mesh.Parent = eggPart
	local light = Instance.new("PointLight")
	light.Color = egg.Color
	light.Range = 12
	light.Parent = eggPart

	local priceText
	if egg.Currency == "Robux" then
		priceText = "<font color='#7CFF8A'>R$ " .. tostring(Config.Products[egg.ProductSingle].Price) .. "</font>"
	else
		local icon = if egg.Currency == "Gems" then "💎" elseif egg.Currency == "Stardust" then "✨" else "💰"
		priceText = icon .. " " .. Util.Format(egg.Price)
	end
	billboard(eggPart, "%s\n%s", Color3.new(1, 1, 1), 6, 9, 3.4, egg.Name, priceText)
	prompt(eggPart, "Open", egg.Name, openPanel("Egg", eggId))
	eggPart:SetAttribute("EggId", eggId)
	return eggPart
end

local function leaderboard(cf: CFrame, size: Vector3, key: string, title: string, parent)
	local board = newPart({
		Name = "Leaderboard_" .. key,
		Size = size,
		CFrame = cf,
		Color = Color3.fromRGB(25, 25, 35),
		Material = Enum.Material.SmoothPlastic,
	}, parent)
	local frame = newPart({
		Name = "Frame",
		Size = size + Vector3.new(1, 1, -0.4),
		CFrame = cf * CFrame.new(0, 0, 0.4),
		Color = Color3.fromRGB(255, 200, 60),
		Material = Enum.Material.Neon,
	}, parent)
	frame.CanCollide = false
	board:SetAttribute("Title", title)
	World.Boards[key] = board
	return board
end

-- big gate arch with a sign, spanning a corridor
local function arch(position: Vector3, text: string, color: Color3, parent)
	for _, side in { -1, 1 } do
		newPart({
			Name = "ArchPillar",
			Size = Vector3.new(3, 22, 3),
			CFrame = CFrame.new(position + Vector3.new(side * (CORRIDOR_W / 2 + 1.5), 11, 0)),
			Color = Color3.fromRGB(45, 45, 60),
			Material = Enum.Material.Slate,
		}, parent)
		newPart({
			Name = "ArchGlow",
			Size = Vector3.new(3.4, 1, 3.4),
			CFrame = CFrame.new(position + Vector3.new(side * (CORRIDOR_W / 2 + 1.5), 21.5, 0)),
			Color = color,
			Material = Enum.Material.Neon,
			CanCollide = false,
		}, parent)
	end
	local beam = newPart({
		Name = "ArchBeam",
		Size = Vector3.new(CORRIDOR_W + 8, 5, 2),
		CFrame = CFrame.new(position + Vector3.new(0, 24, 0)),
		Color = Color3.fromRGB(30, 30, 44),
		Material = Enum.Material.Slate,
	}, parent)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 30
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = color
		World.SetText(label, text)
		label.Parent = gui
		gui.Parent = beam
	end
end

World.SpeedPads = {}
-- neon dash pad: touching it gives a short burst of speed (see CharacterService)
local function speedPad(position: Vector3, yaw: number, parent)
	local pad = newPart({
		Name = "SpeedPad",
		Size = Vector3.new(9, 0.3, 9),
		CFrame = CFrame.new(position + Vector3.new(0, 0.16, 0)) * CFrame.Angles(0, yaw, 0),
		Color = Color3.fromRGB(60, 230, 255),
		Material = Enum.Material.Neon,
		CanCollide = false,
	}, parent)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Text = "⏫"
	label.Parent = gui
	gui.Parent = pad
	local light = Instance.new("PointLight")
	light.Color = pad.Color
	light.Range = 12
	light.Brightness = 1.5
	light.Parent = pad
	table.insert(World.SpeedPads, pad)
	return pad
end

---------------------------------------------------------------------------
-- hub
---------------------------------------------------------------------------
local function buildHub()
	local hub = folder("Hub", map)

	newPart({
		Name = "Floor",
		Size = Vector3.new(HUB_HALF * 2, 4, HUB_HALF * 2),
		CFrame = CFrame.new(0, -2, 0),
		Color = Color3.fromRGB(110, 175, 90),
		Material = Enum.Material.Grass,
	}, hub)
	newPart({
		Name = "Path",
		Size = Vector3.new(18, 0.2, HUB_HALF * 2),
		CFrame = CFrame.new(0, 0.05, 0),
		Color = Color3.fromRGB(215, 200, 170),
		Material = Enum.Material.Cobblestone,
	}, hub)
	newPart({
		Name = "Plaza",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, 46, 46),
		CFrame = CFrame.new(0, 0.08, -25) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(225, 215, 190),
		Material = Enum.Material.Cobblestone,
	}, hub)

	local wallColor = Color3.fromRGB(120, 115, 110)
	local half = HUB_HALF
	wall(CFrame.new(-half - 1, WALL_H / 2, 0), Vector3.new(2, WALL_H, half * 2 + 4), wallColor, hub)
	wall(CFrame.new(half + 1, WALL_H / 2, 0), Vector3.new(2, WALL_H, half * 2 + 4), wallColor, hub)
	local segment = half - CORRIDOR_W / 2
	wall(CFrame.new(-(CORRIDOR_W / 2 + segment / 2), WALL_H / 2, -half - 1), Vector3.new(segment + 2, WALL_H, 2), wallColor, hub)
	wall(CFrame.new(CORRIDOR_W / 2 + segment / 2, WALL_H / 2, -half - 1), Vector3.new(segment + 2, WALL_H, 2), wallColor, hub)
	wall(CFrame.new(-(CORRIDOR_W / 2 + segment / 2), WALL_H / 2, half + 1), Vector3.new(segment + 2, WALL_H, 2), wallColor, hub)
	wall(CFrame.new(CORRIDOR_W / 2 + segment / 2, WALL_H / 2, half + 1), Vector3.new(segment + 2, WALL_H, 2), wallColor, hub)

	-- spawn
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(0, 0.5, -60) * CFrame.Angles(0, math.pi, 0) -- face the mines
	spawn.Color = Color3.fromRGB(255, 220, 120)
	spawn.Material = Enum.Material.Neon
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = hub
	billboard(spawn, "%s", Color3.fromRGB(255, 230, 120), 14, 18, 4, Config.GameName)

	-- signs facing the spawn: the core hooks + "like & favorite" (algorithm signal)
	local function sign(position: Vector3, text: string, color: Color3)
		local board = newPart({
			Name = "Sign",
			Size = Vector3.new(16, 7, 0.6),
			CFrame = CFrame.new(position),
			Color = Color3.fromRGB(25, 25, 38),
			Material = Enum.Material.SmoothPlastic,
		}, hub)
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 30
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = color
		World.SetText(label, text)
		label.Parent = gui
		gui.Parent = board
		for _, x in { -7.6, 7.6 } do
			newPart({
				Name = "Post",
				Size = Vector3.new(0.6, 6, 0.6),
				CFrame = CFrame.new(position + Vector3.new(x, -6, 0.4)),
				Color = Color3.fromRGB(60, 60, 70),
				Material = Enum.Material.Metal,
			}, hub)
		end
	end
	sign(Vector3.new(-18, 9, -46), "👍 LIKE + ⭐ FAVORITE\nfor new CODES & updates!", Color3.fromRGB(255, 220, 90))
	sign(Vector3.new(18, 9, -46), "⛏️ Tap ore = 💰 coins\n🌠 Carry stars home = 💰 every second", Color3.fromRGB(120, 230, 255))

	-- plaza centerpiece: star fountain (ore pays coins directly, no selling)
	newPart({
		Name = "FountainBasin",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, 15, 15),
		CFrame = CFrame.new(0, 1, -25) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(235, 235, 245),
		Material = Enum.Material.Marble,
	}, hub)
	newPart({
		Name = "FountainWater",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 13, 13),
		CFrame = CFrame.new(0, 2.05, -25) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(90, 190, 255),
		Material = Enum.Material.Glass,
		Transparency = 0.25,
		CanCollide = false,
	}, hub)
	local statue = newPart({
		Name = "FountainStar",
		Size = Vector3.new(2.4, 5, 2.4),
		CFrame = CFrame.new(0, 6, -25) * CFrame.Angles(0, math.rad(45), math.rad(15)),
		Color = Color3.fromRGB(120, 220, 255),
		Material = Enum.Material.Neon,
		CanCollide = false,
	}, hub)
	local glow = Instance.new("PointLight")
	glow.Color = statue.Color
	glow.Range = 18
	glow.Brightness = 2
	glow.Parent = statue

	-- meteor crater
	local crater = newPart({
		Name = "MeteorCrater",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 44, 44),
		CFrame = CFrame.new(Config.Meteor.Position + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(60, 45, 40),
		Material = Enum.Material.CrackedLava,
	}, hub)
	billboard(crater, "☄️ METEOR CRATER", Color3.fromRGB(255, 150, 80), 4, 14, 2.8)
	local rng = Random.new(7)
	for i = 1, 14 do
		local angle = (i / 14) * math.pi * 2
		local r = 23 + rng:NextNumber(-1, 1)
		local size = rng:NextNumber(2.5, 5)
		newPart({
			Name = "CraterRock",
			Size = Vector3.new(size, size * 0.8, size),
			CFrame = CFrame.new(Config.Meteor.Position + Vector3.new(math.cos(angle) * r, size * 0.3, math.sin(angle) * r))
				* CFrame.Angles(rng:NextNumber(0, 1), rng:NextNumber(0, 6), rng:NextNumber(0, 1)),
			Color = Color3.fromRGB(90, 80, 75),
			Material = Enum.Material.Basalt,
		}, hub)
	end

	-- shops (east)
	local shops = folder("Shops", hub)
	local pick = booth(Vector3.new(56, 0, -45), "⛏️ PICKAXES", Color3.fromRGB(255, 170, 60), shops)
	prompt(pick, "Open", "Pickaxe Shop", openPanel("Shop", "Pickaxes"))
	local rebirth = booth(Vector3.new(56, 0, 5), "♻️ REBIRTH", Color3.fromRGB(190, 90, 255), shops)
	prompt(rebirth, "Open", "Rebirth Altar", openPanel("Rebirth"))
	local store = booth(Vector3.new(56, 0, 30), "🛒 STORE", Color3.fromRGB(80, 220, 120), shops)
	prompt(store, "Open", "Store", openPanel("Store"))

	-- eggs (west)
	local eggs = folder("Eggs", hub)
	eggStand(Vector3.new(-56, 0, -45), "Meadow", eggs)
	eggStand(Vector3.new(-56, 0, -20), "Gem", eggs)
	eggStand(Vector3.new(-56, 0, 5), "Cosmic", eggs)
	eggStand(Vector3.new(-56, 0, 30), "Golden", eggs)

	-- leaderboards (facing the spawn)
	local boards = folder("Leaderboards", hub)
	local defs = Config.Leaderboards.Boards
	if defs[1] then
		leaderboard(CFrame.new(0, 27, HUB_HALF - 1), Vector3.new(30, 20, 1), defs[1].Key, defs[1].Title, boards)
	end
	if defs[2] then
		leaderboard(CFrame.new(-50, 11, HUB_HALF - 2), Vector3.new(24, 18, 1), defs[2].Key, defs[2].Title, boards)
	end
	if defs[3] then
		leaderboard(CFrame.new(50, 11, HUB_HALF - 2), Vector3.new(24, 18, 1), defs[3].Key, defs[3].Title, boards)
	end

	-- hall of fame: statues of the all-time richest players (LeaderboardService)
	local fame = folder("HallOfFame", hub)
	World.StatueSpots = {}
	for rank, spot in { { -30, 4 }, { -42, 3 }, { -18, 2.2 } } do
		local position = Vector3.new(spot[1], spot[2] / 2, -8)
		local plinth = newPart({
			Name = "Plinth" .. rank,
			Size = Vector3.new(7, spot[2], 7),
			CFrame = CFrame.lookAt(position, Vector3.new(0, position.Y, -60)),
			Color = ({ Color3.fromRGB(255, 205, 60), Color3.fromRGB(210, 215, 225), Color3.fromRGB(215, 140, 80) })[rank],
			Material = Enum.Material.Marble,
		}, fame)
		World.StatueSpots[rank] = plinth.CFrame * CFrame.new(0, spot[2] / 2, 0)
	end
	billboard(fame:FindFirstChild("Plinth1") :: BasePart, "🏆 HALL OF FAME", Color3.fromRGB(255, 220, 90), 13, 16, 3)

	-- gates: mines to the north, bases to the south
	arch(Vector3.new(0, 0, HUB_HALF - 2), "⛏️ MINES", Color3.fromRGB(255, 200, 80), hub)
	arch(Vector3.new(0, 0, -HUB_HALF + 2), "🏠 BASES", Color3.fromRGB(120, 230, 255), hub)
	-- dash pads along the main road (point toward the mines / the bases)
	speedPad(Vector3.new(0, 0, -45), 0, hub)
	speedPad(Vector3.new(0, 0, 8), 0, hub)
	speedPad(Vector3.new(0, 0, 66), 0, hub)
	speedPad(Vector3.new(0, 0, -72), math.pi, hub)

	-- decor
	for _, pos in
		{
			Vector3.new(-70, 0, -70),
			Vector3.new(70, 0, -70),
			Vector3.new(-72, 0, 62),
			Vector3.new(72, 0, 62),
			Vector3.new(-30, 0, -72),
			Vector3.new(30, 0, -72),
		}
	do
		tree(pos, hub)
	end
	for z = -60, 60, 30 do
		lamp(Vector3.new(-11, 0, z), Color3.fromRGB(255, 220, 160), hub)
		lamp(Vector3.new(11, 0, z), Color3.fromRGB(255, 220, 160), hub)
	end
end

---------------------------------------------------------------------------
-- base district (south): gardens, avenue, walls; the territories themselves
-- come from BaseService (Util.PlotLayout: two rows facing the avenue)
---------------------------------------------------------------------------
local function buildBaseDistrict()
	local district = folder("District", map)
	local bases = Config.World.Bases
	local halfX = bases.HalfX
	local length = bases.ZStart - bases.ZEnd
	local centerZ = (bases.ZStart + bases.ZEnd) / 2
	local wallColor = Color3.fromRGB(70, 72, 92)
	local base = Config.Base
	local half = base.PlotSize / 2
	local layout = base.Layout
	local avenueZ = Util.AvenueZ(Config)
	local northZ = bases.ZStart - layout.Margin - half
	local southZ = avenueZ - layout.Avenue / 2 - half

	-- corridor from the hub's south gate
	newPart({
		Name = "Corridor",
		Size = Vector3.new(CORRIDOR_W, 4, -HUB_HALF - bases.ZStart + 2),
		CFrame = CFrame.new(0, -2, (-HUB_HALF + bases.ZStart) / 2),
		Color = Color3.fromRGB(150, 140, 130),
		Material = Enum.Material.Cobblestone,
	}, district)
	for _, side in { -1, 1 } do
		wall(
			CFrame.new(side * (CORRIDOR_W / 2 + 1), WALL_H / 2, (-HUB_HALF + bases.ZStart) / 2),
			Vector3.new(2, WALL_H, -HUB_HALF - bases.ZStart + 2),
			wallColor,
			district
		)
	end

	-- soft grass everywhere between the houses
	newPart({
		Name = "Floor",
		Size = Vector3.new(halfX * 2, 4, length),
		CFrame = CFrame.new(0, -2, centerZ),
		Color = Color3.fromRGB(85, 145, 80),
		Material = Enum.Material.Grass,
	}, district)

	-- entrance lane: gate -> avenue (between the two inner houses)
	local laneLength = bases.ZStart - (avenueZ + layout.Avenue / 2)
	newPart({
		Name = "Lane",
		Size = Vector3.new(layout.EntranceGap - 6, 0.2, laneLength),
		CFrame = CFrame.new(0, 0.05, bases.ZStart - laneLength / 2),
		Color = Color3.fromRGB(205, 195, 175),
		Material = Enum.Material.Cobblestone,
	}, district)
	speedPad(Vector3.new(0, 0, bases.ZStart - 14), math.pi, district)

	-- the avenue every house faces
	newPart({
		Name = "Avenue",
		Size = Vector3.new(halfX * 2 - 6, 0.2, layout.Avenue),
		CFrame = CFrame.new(0, 0.06, avenueZ),
		Color = Color3.fromRGB(205, 195, 175),
		Material = Enum.Material.Cobblestone,
	}, district)
	for _, side in { -1, 1 } do
		newPart({
			Name = "AvenueLine",
			Size = Vector3.new(halfX * 2 - 6, 0.25, 0.6),
			CFrame = CFrame.new(0, 0.09, avenueZ + side * (layout.Avenue / 2 - 0.5)),
			Color = Color3.fromRGB(120, 230, 255),
			Material = Enum.Material.Neon,
			CanCollide = false,
		}, district)
	end
	-- dash pads pointing to the outer houses, lamps along the avenue
	for _, x in { 34, 120 } do
		speedPad(Vector3.new(x, 0, avenueZ), -math.pi / 2, district)
		speedPad(Vector3.new(-x, 0, avenueZ), math.pi / 2, district)
	end
	for x = -halfX + 20, halfX - 20, 40 do
		lamp(Vector3.new(x, 0, avenueZ - layout.Avenue / 2 - 1.5), Color3.fromRGB(255, 220, 160), district)
		lamp(Vector3.new(x, 0, avenueZ + layout.Avenue / 2 + 1.5), Color3.fromRGB(255, 220, 160), district)
	end

	-- gardens between neighbours: a row of trees in every gap
	local gapX = layout.EntranceGap / 2 + half * 2 + layout.Gap / 2
	for _, rowZ in { northZ, southZ } do
		for _, x in { -gapX, gapX } do
			for dz = -half + 6, half - 6, 12 do
				tree(Vector3.new(x, 0, rowZ + dz), district)
			end
		end
	end

	-- a little park between the far houses
	newPart({
		Name = "Park",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, layout.EntranceGap - 6, layout.EntranceGap - 6),
		CFrame = CFrame.new(0, 0.07, southZ) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(215, 205, 180),
		Material = Enum.Material.Cobblestone,
	}, district)
	newPart({
		Name = "ParkFountain",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.6, 12, 12),
		CFrame = CFrame.new(0, 0.8, southZ) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(235, 235, 245),
		Material = Enum.Material.Marble,
	}, district)
	newPart({
		Name = "ParkWater",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 10.5, 10.5),
		CFrame = CFrame.new(0, 1.65, southZ) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(90, 190, 255),
		Material = Enum.Material.Glass,
		Transparency = 0.25,
		CanCollide = false,
	}, district)
	local parkStar = newPart({
		Name = "ParkStar",
		Size = Vector3.new(1.8, 3.6, 1.8),
		CFrame = CFrame.new(0, 4.4, southZ) * CFrame.Angles(0, math.rad(45), math.rad(15)),
		Color = Color3.fromRGB(255, 210, 110),
		Material = Enum.Material.Neon,
		CanCollide = false,
	}, district)
	local glow = Instance.new("PointLight")
	glow.Color = parkStar.Color
	glow.Range = 16
	glow.Brightness = 1.5
	glow.Parent = parkStar
	for _, corner in { { -14, -14 }, { 14, -14 }, { -14, 14 }, { 14, 14 } } do
		tree(Vector3.new(corner[1], 0, southZ + corner[2]), district)
	end

	-- walls around the district (gap for the corridor)
	for _, side in { -1, 1 } do
		wall(CFrame.new(side * (halfX + 1), WALL_H / 2, centerZ), Vector3.new(2, WALL_H, length + 2), wallColor, district)
		local segment = halfX - CORRIDOR_W / 2
		wall(
			CFrame.new(side * (CORRIDOR_W / 2 + segment / 2), WALL_H / 2, bases.ZStart + 1),
			Vector3.new(segment + 2, WALL_H, 2),
			wallColor,
			district
		)
	end
	wall(CFrame.new(0, WALL_H / 2, bases.ZEnd - 1), Vector3.new(halfX * 2 + 4, WALL_H, 2), wallColor, district)

	-- twinkling stars above the district (it's where the pets live)
	local sky = newPart({
		Name = "Ambience",
		Size = Vector3.new(halfX * 2, 1, length),
		CFrame = CFrame.new(0, 26, centerZ),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	}, district)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(150, 220, 255))
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new(0.35)
	emitter.Lifetime = NumberRange.new(3, 5)
	emitter.Rate = 24
	emitter.Speed = NumberRange.new(0.3, 1)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = sky
end

---------------------------------------------------------------------------
-- zones
---------------------------------------------------------------------------
local function buildZones()
	local zonesFolder = folder("Zones", map)
	local gates = folder("Gates", map)
	local wallColor = Color3.fromRGB(95, 90, 90)

	-- corridor from the hub into zone 1
	newPart({
		Name = "Corridor",
		Size = Vector3.new(CORRIDOR_W, 4, GAP + 2),
		CFrame = CFrame.new(0, -2, HUB_HALF + GAP / 2),
		Color = Color3.fromRGB(150, 140, 130),
		Material = Enum.Material.Cobblestone,
	}, zonesFolder)
	for _, side in { -1, 1 } do
		wall(
			CFrame.new(side * (CORRIDOR_W / 2 + 1), WALL_H / 2, HUB_HALF + GAP / 2),
			Vector3.new(2, WALL_H, GAP + 2),
			wallColor,
			zonesFolder
		)
	end

	for index, zone in Config.Zones do
		local zStart = World.ZoneStart(index)
		local zEnd = zStart + ZONE_L
		local zf = folder(string.format("%d_%s", index, zone.Name), zonesFolder)
		local isLast = index == #Config.Zones

		newPart({
			Name = "Floor",
			Size = Vector3.new(ZONE_W, 4, ZONE_L),
			CFrame = CFrame.new(0, -2, zStart + ZONE_L / 2),
			Color = zone.FloorColor,
			Material = zone.Floor,
		}, zf)

		local color = wallColor:Lerp(zone.Accent, 0.25)
		wall(CFrame.new(-ZONE_W / 2 - 1, WALL_H / 2, zStart + ZONE_L / 2), Vector3.new(2, WALL_H, ZONE_L + 2), color, zf)
		wall(CFrame.new(ZONE_W / 2 + 1, WALL_H / 2, zStart + ZONE_L / 2), Vector3.new(2, WALL_H, ZONE_L + 2), color, zf)
		local seg = ZONE_W / 2 - CORRIDOR_W / 2
		for _, side in { -1, 1 } do
			wall(CFrame.new(side * (CORRIDOR_W / 2 + seg / 2), WALL_H / 2, zStart - 1), Vector3.new(seg + 2, WALL_H, 2), color, zf)
			if not isLast then
				wall(CFrame.new(side * (CORRIDOR_W / 2 + seg / 2), WALL_H / 2, zEnd + 1), Vector3.new(seg + 2, WALL_H, 2), color, zf)
			end
		end
		if isLast then
			wall(CFrame.new(0, WALL_H / 2, zEnd + 1), Vector3.new(ZONE_W + 4, WALL_H, 2), color, zf)
		else
			newPart({
				Name = "Corridor",
				Size = Vector3.new(CORRIDOR_W, 4, GAP + 2),
				CFrame = CFrame.new(0, -2, zEnd + GAP / 2),
				Color = Color3.fromRGB(120, 115, 110),
				Material = Enum.Material.Cobblestone,
			}, zf)
			for _, side in { -1, 1 } do
				wall(CFrame.new(side * (CORRIDOR_W / 2 + 1), WALL_H / 2, zEnd + GAP / 2), Vector3.new(2, WALL_H, GAP + 2), color, zf)
			end
		end

		-- accent lights in the corners
		for _, pos in
			{ Vector3.new(-44, 0, zStart + 6), Vector3.new(44, 0, zStart + 6), Vector3.new(-44, 0, zEnd - 6), Vector3.new(44, 0, zEnd - 6) }
		do
			lamp(pos, zone.Accent, zf)
		end

		-- ambient particles: every zone has its own mood
		local mood = AMBIENCE[index]
		if mood then
			local emitterPart = newPart({
				Name = "Ambience",
				Size = Vector3.new(ZONE_W - 4, 1, ZONE_L - 4),
				CFrame = CFrame.new(0, mood.Height, zStart + ZONE_L / 2),
				Transparency = 1,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
			}, zf)
			local emitter = Instance.new("ParticleEmitter")
			emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			emitter.Color = ColorSequence.new(mood.Color)
			emitter.LightEmission = mood.Light
			emitter.Size = NumberSequence.new(mood.Size)
			emitter.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.2, 0.15),
				NumberSequenceKeypoint.new(0.8, 0.3),
				NumberSequenceKeypoint.new(1, 1),
			})
			emitter.Lifetime = NumberRange.new(mood.Life[1], mood.Life[2])
			emitter.Rate = mood.Rate
			emitter.Speed = NumberRange.new(mood.Speed[1], mood.Speed[2])
			emitter.Acceleration = mood.Acceleration
			emitter.EmissionDirection = mood.Direction
			emitter.SpreadAngle = Vector2.new(25, 25)
			emitter.Parent = emitterPart
		end

		-- glowing crystal clusters along the walls
		local crystalRng = Random.new(500 + index)
		for i = 1, 8 do
			local side = if i % 2 == 0 then 1 else -1
			local base = Vector3.new(side * 47, 0, zStart + 10 + (i - 1) * 11)
			for _ = 1, 3 do
				local height = crystalRng:NextNumber(3, 7)
				newPart({
					Name = "WallCrystal",
					Size = Vector3.new(1.4, height, 1.4),
					CFrame = CFrame.new(
						base + Vector3.new(crystalRng:NextNumber(-1.5, 1.5), height / 2 - 0.5, crystalRng:NextNumber(-1.5, 1.5))
					)
						* CFrame.Angles(crystalRng:NextNumber(-0.35, 0.35), crystalRng:NextNumber(0, 3), crystalRng:NextNumber(-0.35, 0.35)),
					Color = zone.Accent,
					Material = Enum.Material.Neon,
					Transparency = 0.15,
					CanCollide = false,
					CanQuery = false,
					CastShadow = false,
				}, zf)
			end
		end

		-- floating zone title
		local titleAnchor = newPart({
			Name = "TitleAnchor",
			Size = Vector3.new(1, 1, 1),
			CFrame = CFrame.new(0, 20, zStart + 4),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
		}, zf)
		if zone.PvP then
			billboard(
				titleAnchor,
				"%s\n<font color='#FF5A7A'>⚔️ PVP ZONE - bonk players to steal ore!</font>",
				zone.Accent,
				0,
				30,
				7,
				zone.Name
			)
		else
			billboard(titleAnchor, "%s", zone.Accent, 0, 26, 4, zone.Name)
		end

		World.Zones[index] = {
			ZStart = zStart,
			ZEnd = zEnd,
			Spawn = CFrame.new(0, 4, zStart + 6),
			Name = zone.Name,
		}
		if zone.PvP then
			World.PvPZone = index
		end

		-- gate (zone 2+)
		if index > 1 then
			local gate = newPart({
				Name = "Gate_" .. index,
				Size = Vector3.new(CORRIDOR_W, WALL_H, 1),
				CFrame = CFrame.new(0, WALL_H / 2, zStart - GAP / 2),
				Color = zone.Accent,
				Material = Enum.Material.ForceField,
				Transparency = 0.1,
			}, gates)
			gate:SetAttribute("ZoneIndex", index)
			local gateLabel = billboard(gate, "🔒 %s\n💰 %s", Color3.new(1, 1, 1), -1, 14, 4.2, zone.Name, Util.Format(zone.Cost))
			gateLabel.StudsOffsetWorldSpace = Vector3.new(0, -1, -2) -- in front of the forcefield, facing the approach
			prompt(gate, "Unlock", zone.Name, function(player)
				Services.EconomyService:UnlockZone(player, index)
			end).MaxActivationDistance =
				14
			World.Zones[index].Gate = gate
		end

		-- zone egg
		for eggId, egg in Config.Eggs do
			if egg.Zone == index and index > 1 then
				eggStand(Vector3.new(-28, 0, zStart + 6), eggId, zf)
			end
		end

		-- ore slots
		local slots = {}
		local rng = Random.new(1000 + index)
		local spacing = Config.World.OreSpacing
		local half = Config.World.OreSize / 2
		for x = -42, 42, spacing do
			if math.abs(x) > 4 then
				for z = zStart + 14, zEnd - 8, spacing do
					if rng:NextNumber() > 0.12 then
						table.insert(slots, {
							Zone = index,
							Position = Vector3.new(x, half, z),
						})
					end
				end
			end
		end
		World.OreSlots[index] = slots
	end
end

local function setupLighting()
	Lighting.ClockTime = 14.5
	Lighting.Brightness = 2.2
	Lighting.GlobalShadows = true
	Lighting.OutdoorAmbient = Color3.fromRGB(140, 140, 150)
	Lighting.Ambient = Color3.fromRGB(70, 70, 80)

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = 0.28
	atmosphere.Haze = 1
	atmosphere.Color = Color3.fromRGB(200, 215, 255)
	atmosphere.Decay = Color3.fromRGB(120, 110, 160)
	atmosphere.Parent = Lighting

	local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
	bloom.Intensity = 0.6
	bloom.Size = 30
	bloom.Threshold = 1.2
	bloom.Parent = Lighting

	local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect") or Instance.new("ColorCorrectionEffect")
	cc.Saturation = 0.22
	cc.Contrast = 0.08
	cc.Parent = Lighting

	local rays = Lighting:FindFirstChildOfClass("SunRaysEffect") or Instance.new("SunRaysEffect")
	rays.Intensity = 0.06
	rays.Spread = 0.6
	rays.Parent = Lighting

	-- shinier materials (metal ores, neon, glass) without extra parts
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 1
end

function World:Init(services)
	Services = services
	local old = workspace:FindFirstChild("Map")
	if old then
		old:Destroy()
	end
	buildHub()
	buildBaseDistrict()
	buildZones()
	folder("Ores", map)
	folder("Drops", map)
	folder("Shards", map)
	folder("Bases", map)
	map.Parent = workspace
	setupLighting()
end

function World:Folder(name: string): Folder
	return map:FindFirstChild(name) :: Folder
end

return World
