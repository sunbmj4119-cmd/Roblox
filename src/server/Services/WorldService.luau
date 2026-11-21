--[[
	WorldService: builds the whole map procedurally (no assets required):
	hub plaza, shops, egg stands, sell pad, meteor crater, leaderboards and
	five mining zones separated by gates. Swap any part for a real model later.
]]
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Net = require(script.Parent.Net)

local World = {}
local Services

local HUB_HALF = 80
local ZONE_W = 100
local ZONE_L = 100
local GAP = 10
local FIRST_Z = 90
local CORRIDOR_W = 24
local WALL_H = 16

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

local function billboard(adornee: BasePart, text: string, color: Color3, offsetY: number, width: number?, height: number?)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromOffset(width or 260, height or 70)
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
	label.Text = text
	label.RichText = true
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
	billboard(base, title, Color3.new(1, 1, 1), 13, 300, 70)
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
		local icon = if egg.Currency == "Gems" then "💎" elseif egg.Currency == "Stardust" then "✨" else "🪙"
		priceText = icon .. " " .. Util.Format(egg.Price)
	end
	billboard(eggPart, egg.Name .. "\n" .. priceText, Color3.new(1, 1, 1), 6, 220, 80)
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
	wall(CFrame.new(0, WALL_H / 2, -half - 1), Vector3.new(half * 2 + 4, WALL_H, 2), wallColor, hub)
	local segment = half - CORRIDOR_W / 2
	wall(CFrame.new(-(CORRIDOR_W / 2 + segment / 2), WALL_H / 2, half + 1), Vector3.new(segment + 2, WALL_H, 2), wallColor, hub)
	wall(CFrame.new(CORRIDOR_W / 2 + segment / 2, WALL_H / 2, half + 1), Vector3.new(segment + 2, WALL_H, 2), wallColor, hub)

	-- spawn
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(0, 0.5, -60)
	spawn.Color = Color3.fromRGB(255, 220, 120)
	spawn.Material = Enum.Material.Neon
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = hub
	billboard(spawn, Config.GameName, Color3.fromRGB(255, 230, 120), 14, 360, 80)

	-- sell pad
	local sell = newPart({
		Name = "SellPad",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 16, 16),
		CFrame = CFrame.new(0, 0.2, -25) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(60, 255, 120),
		Material = Enum.Material.Neon,
		CanCollide = false,
	}, hub)
	billboard(sell, "💰 SELL ORE", Color3.fromRGB(120, 255, 150), 6, 260, 70)
	World.SellPad = sell

	-- meteor crater
	local crater = newPart({
		Name = "MeteorCrater",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 44, 44),
		CFrame = CFrame.new(Config.Meteor.Position + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(60, 45, 40),
		Material = Enum.Material.CrackedLava,
	}, hub)
	billboard(crater, "☄️ METEOR CRATER", Color3.fromRGB(255, 150, 80), 4, 300, 60)
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
	local bag = booth(Vector3.new(56, 0, -20), "🎒 BACKPACKS", Color3.fromRGB(80, 170, 255), shops)
	prompt(bag, "Open", "Backpack Shop", openPanel("Shop", "Backpacks"))
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

	-- decor
	for _, pos in { Vector3.new(-70, 0, -70), Vector3.new(70, 0, -70), Vector3.new(-72, 0, 62), Vector3.new(72, 0, 62), Vector3.new(-30, 0, -72), Vector3.new(30, 0, -72) } do
		tree(pos, hub)
	end
	for z = -60, 60, 30 do
		lamp(Vector3.new(-11, 0, z), Color3.fromRGB(255, 220, 160), hub)
		lamp(Vector3.new(11, 0, z), Color3.fromRGB(255, 220, 160), hub)
	end
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
		wall(CFrame.new(side * (CORRIDOR_W / 2 + 1), WALL_H / 2, HUB_HALF + GAP / 2), Vector3.new(2, WALL_H, GAP + 2), wallColor, zonesFolder)
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
		for _, pos in { Vector3.new(-44, 0, zStart + 6), Vector3.new(44, 0, zStart + 6), Vector3.new(-44, 0, zEnd - 6), Vector3.new(44, 0, zEnd - 6) } do
			lamp(pos, zone.Accent, zf)
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
		local subtitle = if zone.PvP then "\n<font color='#FF5A7A'>⚔️ PVP ZONE - bonk players to steal ore!</font>" else ""
		billboard(titleAnchor, string.upper(zone.Name) .. subtitle, zone.Accent, 0, 520, if zone.PvP then 110 else 70)

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
			local gateLabel = billboard(gate, "🔒 " .. zone.Name .. "\n🪙 " .. Util.Format(zone.Cost), Color3.new(1, 1, 1), -1, 300, 90)
			gateLabel.StudsOffsetWorldSpace = Vector3.new(0, -1, -2) -- in front of the forcefield, facing the approach
			prompt(gate, "Unlock", zone.Name .. " (" .. Util.Format(zone.Cost) .. ")", function(player)
				Services.EconomyService:UnlockZone(player, index)
			end).MaxActivationDistance = 14
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
	cc.Saturation = 0.15
	cc.Contrast = 0.05
	cc.Parent = Lighting
end

function World:Init(services)
	Services = services
	local old = workspace:FindFirstChild("Map")
	if old then
		old:Destroy()
	end
	buildHub()
	buildZones()
	folder("Ores", map)
	folder("Drops", map)
	map.Parent = workspace
	setupLighting()
end

function World:Folder(name: string): Folder
	return map:FindFirstChild(name) :: Folder
end

return World
