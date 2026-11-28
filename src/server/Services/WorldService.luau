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

-- a fuller tree: trunk + a few overlapping leaf clumps (varied size / colour)
local treeRng = Random.new(77)
local function tree(position: Vector3, parent, scale: number?)
	local k = (scale or 1) * treeRng:NextNumber(0.85, 1.25)
	local trunkH = 7 * k
	newPart({
		Name = "Trunk",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(trunkH, 1.6 * k, 1.6 * k),
		CFrame = CFrame.new(position + Vector3.new(0, trunkH / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(105, 72, 48),
		Material = Enum.Material.Wood,
	}, parent)
	local green = Color3.fromRGB(70, 150, 70):Lerp(Color3.fromRGB(110, 180, 80), treeRng:NextNumber())
	for i = 1, 4 do
		local angle = i * 1.7 + treeRng:NextNumber(0, 1)
		local r = if i == 1 then 0 else 2.2 * k
		local size = (if i == 1 then 8 else 5.5) * k * treeRng:NextNumber(0.9, 1.1)
		newPart({
			Name = "Leaves",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * size,
			CFrame = CFrame.new(position + Vector3.new(math.cos(angle) * r, trunkH + (if i == 1 then 1.5 else 0) * k, math.sin(angle) * r)),
			Color = green:Lerp(Color3.new(0, 0, 0), if i == 1 then 0 else 0.08 * i),
			Material = Enum.Material.Grass,
			CanCollide = false,
		}, parent)
	end
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
		Size = Vector3.one * 1.6,
		CFrame = CFrame.new(position + Vector3.new(0, 10.3, 0)),
		Color = color,
		Material = Enum.Material.Glass,
		Transparency = 0.2,
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
	if egg.Currency ~= "Robux" then
		-- quick hatch right at the stand (no menu needed)
		local quick = prompt(eggPart, "Hatch x1", egg.Name, function(player)
			Services.PetService:QuickHatch(player, eggId)
		end)
		quick.KeyboardKeyCode = Enum.KeyCode.F
		quick.HoldDuration = 0.25
		quick.UIOffset = Vector2.new(0, 70)
	end
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
	sign(Vector3.new(18, 9, -46), "☄️ Smash meteors together\n🥚 Grab a star egg & run home!", Color3.fromRGB(120, 230, 255))

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

	-- gardens between neighbours: two staggered tree lines in every gap
	local gapX = layout.EntranceGap / 2 + half * 2 + layout.Gap / 2
	for _, rowZ in { northZ, southZ } do
		for _, x in { -gapX, gapX } do
			for dz = -half + 6, half - 6, 13 do
				tree(Vector3.new(x - 9, 0, rowZ + dz), district, 1.1)
				tree(Vector3.new(x + 9, 0, rowZ + dz + 6), district, 1.1)
			end
		end
	end
	-- and along the outer edges of the far houses
	local outerX = layout.EntranceGap / 2 + half * 4 + layout.Gap + 8
	for _, rowZ in { northZ, southZ } do
		for _, x in { -outerX, outerX } do
			for dz = -half + 8, half - 8, 16 do
				tree(Vector3.new(x, 0, rowZ + dz), district, 1.2)
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

		-- ore slots: natural clusters (veins) with paths between them, instead
		-- of a dense grid of blocks
		local slots = {}
		local rng = Random.new(1000 + index)
		local half = Config.World.OreSize / 2
		local minGap = Config.World.OreSpacing
		local function free(position: Vector3): boolean
			if math.abs(position.X) < 6 or math.abs(position.X) > ZONE_W / 2 - 7 then
				return false
			end
			if position.Z < zStart + 16 or position.Z > zEnd - 7 then
				return false
			end
			for _, other in slots do
				if (other.Position - position).Magnitude < minGap then
					return false
				end
			end
			return true
		end
		for _ = 1, Config.World.OreClusters do
			local center = Vector3.new(rng:NextNumber(-34, 34), half, rng:NextNumber(zStart + 24, zEnd - 14))
			local placed = 0
			for _ = 1, 24 do
				local angle = rng:NextNumber(0, math.pi * 2)
				local position = center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * rng:NextNumber(0, 13)
				if placed < 8 and free(position) then
					placed += 1
					table.insert(slots, { Zone = index, Position = position })
				end
			end
		end
		World.OreSlots[index] = slots
	end
end

---------------------------------------------------------------------------
-- 🌄 landscape: real terrain instead of flat plates - grass / snow / basalt /
-- slate / lava ground, rocky cliffs instead of walls, hills on the horizon
---------------------------------------------------------------------------
local TERRAIN = {
	[Enum.Material.Grass] = Enum.Material.Grass,
	[Enum.Material.LeafyGrass] = Enum.Material.LeafyGrass,
	[Enum.Material.Snow] = Enum.Material.Snow,
	[Enum.Material.Ice] = Enum.Material.Glacier,
	[Enum.Material.Basalt] = Enum.Material.Basalt,
	[Enum.Material.Slate] = Enum.Material.Slate,
	[Enum.Material.CrackedLava] = Enum.Material.CrackedLava,
	[Enum.Material.Cobblestone] = Enum.Material.Cobblestone,
	[Enum.Material.Sand] = Enum.Material.Sand,
	[Enum.Material.Rock] = Enum.Material.Rock,
	[Enum.Material.Ground] = Enum.Material.Ground,
	[Enum.Material.Pavement] = Enum.Material.Pavement,
}
-- cliff rock per zone (hub = grassy rock)
local CLIFF = {
	[0] = { Rock = Enum.Material.Rock, Top = Enum.Material.Grass },
	[1] = { Rock = Enum.Material.Rock, Top = Enum.Material.Grass },
	[2] = { Rock = Enum.Material.Glacier, Top = Enum.Material.Snow },
	[3] = { Rock = Enum.Material.Basalt, Top = Enum.Material.CrackedLava },
	[4] = { Rock = Enum.Material.Slate, Top = Enum.Material.Slate },
	[5] = { Rock = Enum.Material.Basalt, Top = Enum.Material.Rock },
}

local function landscape()
	local terrain = workspace.Terrain
	local rng = Random.new(2024)
	pcall(function()
		terrain.Decoration = true -- (animated grass where supported)
	end)
	pcall(function()
		terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(106, 170, 82))
		terrain:SetMaterialColor(Enum.Material.LeafyGrass, Color3.fromRGB(96, 156, 74))
		terrain:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(128, 122, 114))
		terrain:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(122, 96, 70))
		terrain:SetMaterialColor(Enum.Material.Cobblestone, Color3.fromRGB(186, 172, 150))
	end)
	if not terrain:FindFirstChildOfClass("Clouds") then
		local clouds = Instance.new("Clouds")
		clouds.Cover = 0.55
		clouds.Density = 0.6
		clouds.Color = Color3.fromRGB(255, 255, 255)
		clouds.Parent = terrain
	end

	local function zoneOf(position: Vector3): number
		return Util.ZoneAt(Config, Vector3.new(position.X, 3, position.Z)) or 0
	end

	-- floors and corridors become terrain (the parts stay as invisible floors)
	for _, part in map:GetDescendants() do
		if part:IsA("BasePart") and (part.Name == "Floor" or part.Name == "Corridor") and part.Size.Y >= 2 then
			local material = TERRAIN[part.Material] or Enum.Material.Ground
			-- (a hair lower, so paths / plazas lying on the floor stay visible)
			terrain:FillBlock(part.CFrame * CFrame.new(0, -0.3, 0), part.Size, material)
			terrain:FillBlock(
				part.CFrame * CFrame.new(0, -part.Size.Y / 2 - 4, 0),
				Vector3.new(part.Size.X, 8, part.Size.Z),
				Enum.Material.Rock
			)
			part.Transparency = 1
		end
	end

	-- where people walk: the hub, the mines, the base district and the corridors
	-- (terrain hills / spires must never cover these)
	local layout = Config.World.Layout
	local half = layout.HubHalf
	local bases = Config.World.Bases
	local lastZone = World.Zones[#Config.Zones]
	local playRects = {
		{ -half, half, -half, half }, -- hub (minX, maxX, minZ, maxZ)
		{ -bases.HalfX, bases.HalfX, bases.ZEnd, bases.ZStart }, -- homes
		{ -CORRIDOR_W / 2, CORRIDOR_W / 2, bases.ZStart, -half }, -- hub -> homes corridor
	}
	local previousEnd = half
	for index in Config.Zones do
		local info = World.Zones[index]
		if info then
			-- the corridor into this mine, then the mine itself
			table.insert(playRects, { -CORRIDOR_W / 2, CORRIDOR_W / 2, previousEnd, info.ZStart })
			table.insert(playRects, { -layout.ZoneWidth / 2, layout.ZoneWidth / 2, info.ZStart, info.ZEnd })
			previousEnd = info.ZEnd
		end
	end
	local function inPlay(position: Vector3, margin: number): boolean
		for _, r in playRects do
			if
				position.X >= r[1] - margin
				and position.X <= r[2] + margin
				and position.Z >= r[3] - margin
				and position.Z <= r[4] + margin
			then
				return true
			end
		end
		return false
	end
	-- a hill's footprint on the ground must stay clear of the play areas
	local function hill(center: Vector3, radius: number, material: Enum.Material): boolean
		local footprint = if center.Y < radius then math.sqrt(radius * radius - center.Y * center.Y) else 0
		if footprint <= 0 or inPlay(center, footprint + 6) then
			return false
		end
		terrain:FillBall(center, radius, material)
		return true
	end

	-- walls become rocky cliffs OUTSIDE the play area (the wall parts stay as
	-- invisible borders, made tall so nobody walks over the cliff tops)
	for _, part in map:GetDescendants() do
		if part:IsA("BasePart") and part.Name == "Wall" then
			local cliff = CLIFF[zoneOf(part.Position)] or CLIFF[0]
			local size = part.Size
			local alongX = size.X >= size.Z
			local long = if alongX then Vector3.xAxis else Vector3.zAxis
			local normal = if alongX then Vector3.zAxis else Vector3.xAxis
			local length = math.max(size.X, size.Z)
			-- the outside is the side that isn't walkable (walls with people
			-- on both sides stay plain invisible borders, no cliff)
			local probe = part.Position * Vector3.new(1, 0, 1)
			local plus, minus = inPlay(probe + normal * 6, -1), inPlay(probe - normal * 6, -1)
			local outward = if plus then -normal else normal
			if plus and minus then
				outward = nil
			end
			local thickness = 10
			local height = size.Y + 4
			if outward then
				terrain:FillBlock(
					CFrame.new(probe + outward * (thickness / 2 + 0.5) + Vector3.new(0, height / 2 - 1, 0)),
					if alongX then Vector3.new(size.X + 4, height, thickness) else Vector3.new(thickness, height, size.Z + 4),
					cliff.Rock
				)
				-- an uneven top: boulders along the ridge, leaning outward
				for d = -length / 2, length / 2, 9 do
					local center = probe
						+ long * (d + rng:NextNumber(-2, 2))
						+ outward * (thickness / 2 + 3)
						+ Vector3.new(0, size.Y + rng:NextNumber(0, 3), 0)
					terrain:FillBall(center, rng:NextNumber(4, 6), cliff.Rock)
					if rng:NextNumber() < 0.5 then
						terrain:FillBall(center + Vector3.new(0, 2.5, 0), rng:NextNumber(2.5, 4), cliff.Top)
					end
				end
			end
			part.Transparency = if outward then 1 else part.Transparency
			-- taller than any cliff top: no walking along the ridges
			part.Size = Vector3.new(size.X, 70, size.Z)
			part.CFrame = part.CFrame + Vector3.new(0, 35 - size.Y / 2, 0)
		end
	end
	-- zone gates get an invisible cap too (no hopping over a locked gate)
	for _, zone in World.Zones do
		local gate = zone.Gate
		if gate then
			newPart({
				Name = "GateCap",
				Size = Vector3.new(gate.Size.X, 54, gate.Size.Z),
				CFrame = gate.CFrame + Vector3.new(0, gate.Size.Y / 2 + 27, 0),
				Transparency = 1,
				CanQuery = false,
			}, gate.Parent)
		end
	end

	-- the horizon: rolling grassy hills all around (never on the play areas)
	local placed = 0
	for _ = 1, 400 do
		if placed >= 46 then
			break
		end
		local center = Vector3.new(
			rng:NextNumber(-bases.HalfX - 140, bases.HalfX + 140),
			rng:NextNumber(-10, 2),
			rng:NextNumber(bases.ZEnd - 120, (if lastZone then lastZone.ZEnd else half) + 40)
		)
		if hill(center, rng:NextNumber(24, 40), Enum.Material.Grass) then
			placed += 1
		end
	end
	if not lastZone then
		warn("[World] no zones for the landscape")
	end
	-- low grassy mounds in the gardens between homes (estates, not a grid)
	local baseLayout = Config.Base.Layout
	local plotHalf = Config.Base.PlotSize / 2
	local avenueZ = Util.AvenueZ(Config)
	local northZ = bases.ZStart - baseLayout.Margin - plotHalf
	local southZ = avenueZ - baseLayout.Avenue / 2 - plotHalf
	local gapX = baseLayout.EntranceGap / 2 + plotHalf * 2 + baseLayout.Gap / 2
	for _, rowZ in { northZ, southZ } do
		for _, x in { -gapX, gapX } do
			for dz = -plotHalf + 4, plotHalf - 4, 10 do
				terrain:FillBall(Vector3.new(x + rng:NextNumber(-3, 3), -3.5, rowZ + dz), rng:NextNumber(6, 8), Enum.Material.Grass)
			end
		end
	end
	-- mines: rock spires beyond the cliffs
	for index in Config.Zones do
		local info = World.Zones[index]
		local cliff = CLIFF[index] or CLIFF[0]
		if info then
			for _, side in { -1, 1 } do
				for z = info.ZStart + 10, info.ZEnd - 10, 22 do
					local center = Vector3.new(side * (layout.ZoneWidth / 2 + rng:NextNumber(22, 34)), rng:NextNumber(4, 14), z)
					hill(center, rng:NextNumber(10, 16), cliff.Rock)
				end
			end
		end
	end
	-- trees on the hills outside the hub
	local nature = folder("Nature", map)
	for _ = 1, 40 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = half + rng:NextNumber(8, 40)
		local position = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		if not inPlay(position, 4) then
			local hit = workspace:Raycast(position + Vector3.new(0, 80, 0), Vector3.new(0, -160, 0))
			if hit and hit.Instance == terrain then
				tree(hit.Position - Vector3.new(0, 0.5, 0), nature, rng:NextNumber(1, 1.5))
			end
		end
	end
end

local function setupLighting()
	Lighting.ClockTime = 14.5
	-- (tuned for phones: bright and colourful but nothing glares - white
	-- pets / marble / gold must stay readable in the sun)
	Lighting.Brightness = 1.9
	Lighting.ExposureCompensation = -0.15
	Lighting.GlobalShadows = true
	Lighting.OutdoorAmbient = Color3.fromRGB(140, 140, 150)
	Lighting.Ambient = Color3.fromRGB(70, 70, 80)

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = 0.28
	atmosphere.Haze = 0.5
	atmosphere.Color = Color3.fromRGB(200, 215, 255)
	atmosphere.Decay = Color3.fromRGB(120, 110, 160)
	atmosphere.Parent = Lighting

	local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
	bloom.Intensity = 0.3
	bloom.Size = 18
	bloom.Threshold = 2 -- only real light sources glow, not white surfaces
	bloom.Parent = Lighting

	local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect") or Instance.new("ColorCorrectionEffect")
	cc.Saturation = 0.22
	cc.Contrast = 0.08
	cc.Parent = Lighting

	local rays = Lighting:FindFirstChildOfClass("SunRaysEffect") or Instance.new("SunRaysEffect")
	rays.Intensity = 0.03
	rays.Spread = 0.6
	rays.Parent = Lighting

	-- shinier materials (metal ores, neon, glass) without extra parts
	Lighting.EnvironmentDiffuseScale = 0.5
	Lighting.EnvironmentSpecularScale = 0.45 -- (foil / gold reflections were blinding)
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
	local ok, err = pcall(landscape)
	if not ok then
		warn("[World] landscape failed: " .. tostring(err))
	end
end

function World:Folder(name: string): Folder
	return map:FindFirstChild(name) :: Folder
end

return World
