--[[
	DecorModel: procedural decorations for player bases (no assets needed).
	DecorModel.Build(config, id) -> Model whose pivot is the footprint's
	bottom center. PrimaryPart "Footprint" is an invisible plate matching the
	grid footprint (used for selection in build mode).
	Everything is anchored and non-colliding (decor never blocks anyone);
	functional items expose a "Trigger" part that can be touched.
]]
local DecorModel = {}

local function part(
	model: Model,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	extra: { [string]: any }?
)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if extra then
		for key, value in extra do
			(p :: any)[key] = value
		end
	end
	p.Parent = model
	return p
end

local function cylinder(
	model: Model,
	name: string,
	height: number,
	diameter: number,
	y: number,
	color: Color3,
	material: Enum.Material,
	extra
)
	return part(
		model,
		name,
		Vector3.new(height, diameter, diameter),
		CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90)),
		color,
		material,
		extra
	)
end

local function light(parent: BasePart, color: Color3, range: number, brightness: number?)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness or 1.5
	l.Parent = parent
end

local WOOD = Color3.fromRGB(150, 105, 65)
local DARK_WOOD = Color3.fromRGB(105, 70, 45)
local LEAF = Color3.fromRGB(80, 170, 75)
local STONE = Color3.fromRGB(150, 150, 160)
local GOLD = Color3.fromRGB(255, 200, 50)

local BUILDERS = {}

BUILDERS.Pedestal = function(m)
	cylinder(m, "Base", 2.4, 3.8, 1.2, Color3.fromRGB(235, 235, 245), Enum.Material.Marble)
	cylinder(m, "Ring", 0.3, 4.1, 2.45, Color3.fromRGB(120, 220, 255), Enum.Material.Neon)
	local top = part(m, "Top", Vector3.one * 0.2, CFrame.new(0, 2.6, 0), Color3.new(), Enum.Material.SmoothPlastic, { Transparency = 1 })
	top:SetAttribute("IsTop", true)
end

BUILDERS.Trap = function(m)
	part(m, "Plate", Vector3.new(3.6, 0.3, 3.6), CFrame.new(0, 0.15, 0), Color3.fromRGB(60, 60, 75), Enum.Material.Metal)
	local trigger = part(
		m,
		"Trigger",
		Vector3.new(3.2, 0.35, 3.2),
		CFrame.new(0, 0.2, 0),
		Color3.fromRGB(255, 230, 60),
		Enum.Material.Neon,
		{ CanTouch = true, Transparency = 0.2 }
	)
	light(trigger, Color3.fromRGB(255, 230, 60), 8, 1)
end

BUILDERS.JumpPad = function(m)
	part(m, "Plate", Vector3.new(3.6, 0.3, 3.6), CFrame.new(0, 0.15, 0), Color3.fromRGB(50, 50, 70), Enum.Material.Metal)
	local trigger = part(
		m,
		"Trigger",
		Vector3.new(3, 0.4, 3),
		CFrame.new(0, 0.25, 0),
		Color3.fromRGB(110, 255, 140),
		Enum.Material.Neon,
		{ CanTouch = true }
	)
	light(trigger, Color3.fromRGB(110, 255, 140), 8, 1)
end

BUILDERS.Tree = function(m)
	part(m, "Trunk", Vector3.new(1, 5, 1), CFrame.new(0, 2.5, 0), WOOD, Enum.Material.Wood)
	part(m, "Leaves", Vector3.one * 5, CFrame.new(0, 6, 0), LEAF, Enum.Material.LeafyGrass, { Shape = Enum.PartType.Ball })
	part(m, "Leaves2", Vector3.one * 3.4, CFrame.new(1.2, 7.4, 0.6), LEAF:Lerp(Color3.new(1, 1, 1), 0.1), Enum.Material.LeafyGrass, {
		Shape = Enum.PartType.Ball,
	})
end

BUILDERS.Pine = function(m)
	part(m, "Trunk", Vector3.new(0.9, 3, 0.9), CFrame.new(0, 1.5, 0), DARK_WOOD, Enum.Material.Wood)
	for i, size in { 4.4, 3.4, 2.4 } do
		part(
			m,
			"Needles",
			Vector3.new(size, 2.2, size),
			CFrame.new(0, 2.4 + i * 1.6, 0) * CFrame.Angles(0, math.rad(45 * i), 0),
			Color3.fromRGB(40, 120, 70),
			Enum.Material.Grass
		)
	end
end

BUILDERS.Bush = function(m)
	part(m, "Bush", Vector3.new(1.9, 1.5, 1.9), CFrame.new(0, 0.75, 0), LEAF, Enum.Material.LeafyGrass, { Shape = Enum.PartType.Ball })
end

BUILDERS.Flowers = function(m)
	part(m, "Bed", Vector3.new(3.8, 0.5, 1.8), CFrame.new(0, 0.25, 0), Color3.fromRGB(120, 80, 50), Enum.Material.Ground)
	local colors = { Color3.fromRGB(255, 90, 140), Color3.fromRGB(255, 220, 80), Color3.fromRGB(170, 110, 255) }
	for i = 1, 5 do
		part(
			m,
			"Flower",
			Vector3.one * 0.6,
			CFrame.new(-1.6 + i * 0.55, 0.8, if i % 2 == 0 then 0.35 else -0.35),
			colors[i % 3 + 1],
			Enum.Material.SmoothPlastic,
			{ Shape = Enum.PartType.Ball }
		)
	end
end

BUILDERS.Rock = function(m)
	part(m, "Rock", Vector3.new(1.8, 1.2, 1.6), CFrame.new(0, 0.6, 0) * CFrame.Angles(0.2, 0.7, 0.1), STONE, Enum.Material.Rock)
end

BUILDERS.Bench = function(m)
	part(m, "Seat", Vector3.new(3.6, 0.3, 1.2), CFrame.new(0, 1.2, 0), WOOD, Enum.Material.WoodPlanks)
	part(m, "Back", Vector3.new(3.6, 1, 0.2), CFrame.new(0, 1.9, 0.55), WOOD, Enum.Material.WoodPlanks)
	for _, x in { -1.5, 1.5 } do
		part(m, "Leg", Vector3.new(0.25, 1.1, 1), CFrame.new(x, 0.55, 0), Color3.fromRGB(50, 50, 55), Enum.Material.Metal)
	end
end

BUILDERS.Table = function(m)
	part(m, "Top", Vector3.new(3.4, 0.3, 3.4), CFrame.new(0, 2.2, 0), WOOD, Enum.Material.WoodPlanks)
	part(m, "Leg", Vector3.new(0.5, 2.1, 0.5), CFrame.new(0, 1.05, 0), DARK_WOOD, Enum.Material.Wood)
	part(m, "Foot", Vector3.new(1.6, 0.2, 1.6), CFrame.new(0, 0.1, 0), DARK_WOOD, Enum.Material.Wood)
end

BUILDERS.Chair = function(m)
	part(m, "Seat", Vector3.new(1.4, 0.25, 1.4), CFrame.new(0, 1.2, 0), Color3.fromRGB(220, 80, 80), Enum.Material.Fabric)
	part(m, "Back", Vector3.new(1.4, 1.4, 0.2), CFrame.new(0, 2, 0.6), Color3.fromRGB(220, 80, 80), Enum.Material.Fabric)
	part(m, "Leg", Vector3.new(0.3, 1.1, 0.3), CFrame.new(0, 0.55, 0), Color3.fromRGB(50, 50, 55), Enum.Material.Metal)
end

BUILDERS.Sofa = function(m)
	local color = Color3.fromRGB(90, 120, 220)
	part(m, "Seat", Vector3.new(5.6, 1, 1.8), CFrame.new(0, 0.7, 0), color, Enum.Material.Fabric)
	part(m, "Back", Vector3.new(5.6, 1.4, 0.5), CFrame.new(0, 1.6, 0.65), color, Enum.Material.Fabric)
	for _, x in { -2.6, 2.6 } do
		part(m, "Arm", Vector3.new(0.5, 1.1, 1.8), CFrame.new(x, 1.15, 0), color:Lerp(Color3.new(0, 0, 0), 0.15), Enum.Material.Fabric)
	end
end

BUILDERS.Fence = function(m)
	for _, x in { -1.7, 1.7 } do
		part(m, "Post", Vector3.new(0.4, 2.4, 0.4), CFrame.new(x, 1.2, 0), Color3.fromRGB(240, 240, 240), Enum.Material.WoodPlanks)
	end
	for _, y in { 0.9, 1.8 } do
		part(m, "Rail", Vector3.new(3.8, 0.3, 0.2), CFrame.new(0, y, 0), Color3.fromRGB(240, 240, 240), Enum.Material.WoodPlanks)
	end
end

BUILDERS.Lantern = function(m)
	part(m, "Post", Vector3.new(0.3, 2.2, 0.3), CFrame.new(0, 1.1, 0), Color3.fromRGB(40, 40, 45), Enum.Material.Metal)
	local lamp = part(m, "Lamp", Vector3.new(0.9, 1, 0.9), CFrame.new(0, 2.6, 0), Color3.fromRGB(255, 200, 120), Enum.Material.Neon)
	light(lamp, Color3.fromRGB(255, 200, 120), 12, 1.2)
end

BUILDERS.LampPost = function(m)
	part(m, "Post", Vector3.new(0.4, 6, 0.4), CFrame.new(0, 3, 0), Color3.fromRGB(40, 40, 45), Enum.Material.Metal)
	local bulb = part(m, "Bulb", Vector3.one * 1.2, CFrame.new(0, 6.3, 0), Color3.fromRGB(255, 240, 200), Enum.Material.Neon, {
		Shape = Enum.PartType.Ball,
	})
	light(bulb, Color3.fromRGB(255, 230, 180), 18, 1.4)
end

BUILDERS.Crystal = function(m)
	local color = Color3.fromRGB(170, 110, 255)
	for i, h in { 3, 2.2, 1.6 } do
		local angle = i * 2.1
		part(
			m,
			"Crystal",
			Vector3.new(0.6, h, 0.6),
			CFrame.new(math.cos(angle) * 0.35, h / 2, math.sin(angle) * 0.35)
				* CFrame.Angles(math.cos(angle) * 0.3, 0, math.sin(angle) * 0.3),
			color,
			Enum.Material.Neon
		)
	end
	light(m:FindFirstChild("Crystal") :: BasePart, color, 14, 2)
end

BUILDERS.Statue = function(m)
	part(m, "Plinth", Vector3.new(3, 1.2, 3), CFrame.new(0, 0.6, 0), Color3.fromRGB(235, 235, 245), Enum.Material.Marble)
	local star = part(
		m,
		"Star",
		Vector3.new(1.6, 3.2, 1.6),
		CFrame.new(0, 3, 0) * CFrame.Angles(0, math.rad(45), math.rad(15)),
		GOLD,
		Enum.Material.Foil
	)
	part(m, "Star2", Vector3.new(1.2, 2.4, 1.2), CFrame.new(0, 3, 0) * CFrame.Angles(math.rad(70), 0, 0), GOLD, Enum.Material.Foil)
	light(star, GOLD, 12, 1.5)
end

BUILDERS.Fountain = function(m)
	cylinder(m, "Basin", 1.2, 5.6, 0.6, Color3.fromRGB(235, 235, 245), Enum.Material.Marble)
	cylinder(m, "Water", 0.2, 5, 1.15, Color3.fromRGB(90, 190, 255), Enum.Material.Glass, { Transparency = 0.25 })
	cylinder(m, "Pillar", 2.4, 0.8, 1.8, Color3.fromRGB(235, 235, 245), Enum.Material.Marble)
	cylinder(m, "Bowl", 0.4, 2.2, 3, Color3.fromRGB(235, 235, 245), Enum.Material.Marble)
	local spout = part(m, "Spout", Vector3.one * 0.8, CFrame.new(0, 3.5, 0), Color3.fromRGB(140, 220, 255), Enum.Material.Neon, {
		Shape = Enum.PartType.Ball,
	})
	light(spout, Color3.fromRGB(140, 220, 255), 10, 1)
end

BUILDERS.Trophy = function(m)
	part(m, "Base", Vector3.new(1.4, 0.6, 1.4), CFrame.new(0, 0.3, 0), Color3.fromRGB(60, 40, 30), Enum.Material.Wood)
	part(m, "Stem", Vector3.new(0.4, 1, 0.4), CFrame.new(0, 1.1, 0), GOLD, Enum.Material.Foil)
	local cup = part(m, "Cup", Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, 2.1, 0), GOLD, Enum.Material.Foil, { Shape = Enum.PartType.Ball })
	light(cup, GOLD, 8, 1)
end

BUILDERS.Flag = function(m)
	part(m, "Pole", Vector3.new(0.25, 6, 0.25), CFrame.new(0, 3, 0), Color3.fromRGB(220, 220, 225), Enum.Material.Metal)
	part(m, "Cloth", Vector3.new(2.2, 1.4, 0.1), CFrame.new(1.2, 5.2, 0), Color3.fromRGB(255, 70, 90), Enum.Material.Fabric)
end

local function floorTile(m, color: Color3, material: Enum.Material)
	part(m, "Tile", Vector3.new(4, 0.2, 4), CFrame.new(0, 0.1, 0), color, material)
end
BUILDERS.WoodFloor = function(m)
	floorTile(m, Color3.fromRGB(165, 120, 75), Enum.Material.WoodPlanks)
end
BUILDERS.StoneFloor = function(m)
	floorTile(m, Color3.fromRGB(200, 200, 205), Enum.Material.Cobblestone)
end
BUILDERS.GrassFloor = function(m)
	floorTile(m, Color3.fromRGB(95, 170, 80), Enum.Material.Grass)
end
BUILDERS.Carpet = function(m)
	floorTile(m, Color3.fromRGB(190, 40, 55), Enum.Material.Fabric)
end

BUILDERS.Throne = function(m)
	local color = Color3.fromRGB(60, 30, 120)
	part(m, "Seat", Vector3.new(2.6, 1.4, 2.4), CFrame.new(0, 0.7, 0), color, Enum.Material.Glass)
	part(m, "Back", Vector3.new(2.6, 3.6, 0.5), CFrame.new(0, 2.6, 1), color, Enum.Material.Glass)
	part(
		m,
		"Gem",
		Vector3.one * 0.9,
		CFrame.new(0, 4.2, 1),
		Color3.fromRGB(120, 230, 255),
		Enum.Material.Neon,
		{ Shape = Enum.PartType.Ball }
	)
	for _, x in { -1.4, 1.4 } do
		local glow = part(m, "Arm", Vector3.new(0.4, 1.6, 2.4), CFrame.new(x, 1.5, 0), Color3.fromRGB(255, 120, 230), Enum.Material.Neon)
		light(glow, Color3.fromRGB(255, 120, 230), 10, 1.2)
	end
end

BUILDERS.RainbowFountain = function(m)
	BUILDERS.Fountain(m)
	local colors = {
		Color3.fromRGB(255, 80, 80),
		Color3.fromRGB(255, 200, 60),
		Color3.fromRGB(90, 230, 110),
		Color3.fromRGB(80, 170, 255),
		Color3.fromRGB(190, 100, 255),
	}
	for i, color in colors do
		local angle = (i / #colors) * math.pi * 2
		part(
			m,
			"Rainbow",
			Vector3.new(0.5, 2.4, 0.5),
			CFrame.new(math.cos(angle) * 2.2, 2.2, math.sin(angle) * 2.2),
			color,
			Enum.Material.Neon
		)
	end
	m:SetAttribute("Rainbow", true)
end

BUILDERS.NeonArch = function(m)
	local color = Color3.fromRGB(80, 240, 255)
	for _, x in { -2.6, 2.6 } do
		part(m, "Pillar", Vector3.new(0.6, 5, 0.6), CFrame.new(x, 2.5, 0), color, Enum.Material.Neon)
	end
	local top = part(m, "Top", Vector3.new(5.8, 0.6, 0.6), CFrame.new(0, 5.2, 0), color, Enum.Material.Neon)
	light(top, color, 14, 1.5)
end

function DecorModel.Has(id: string): boolean
	return BUILDERS[id] ~= nil
end

-- footprint in studs for a rotation (R odd swaps width/depth)
function DecorModel.Footprint(config, id: string, rotation: number): (number, number)
	local def = config.Decor[id]
	local cell = config.Base.Cell
	local w, d = def.Size[1] * cell, def.Size[2] * cell
	if rotation % 2 == 1 then
		return d, w
	end
	return w, d
end

---------------------------------------------------------------------------
-- placement rules (shared by the server and the build-mode preview)
---------------------------------------------------------------------------
-- snap a center to the grid so the footprint lines up with cells
function DecorModel.Snap(config, id: string, x: number, z: number, rotation: number): (number, number)
	local cell = config.Base.Cell
	local w, d = DecorModel.Footprint(config, id, rotation)
	local function snap(value: number, size: number)
		return math.floor((value - size / 2) / cell + 0.5) * cell + size / 2
	end
	return snap(x, w), snap(z, d)
end

local function rect(config, id: string, x: number, z: number, rotation: number)
	local w, d = DecorModel.Footprint(config, id, rotation)
	return x - w / 2, x + w / 2, z - d / 2, z + d / 2
end

local function layerOf(config, id: string): string
	local def = config.Decor[id]
	return def and def.Layer or "Object"
end

function DecorModel.Count(items, id: string): number
	local count = 0
	for _, item in items do
		if item.Id == id then
			count += 1
		end
	end
	return count
end

-- currency, amount (pedestals get pricier the more you own)
function DecorModel.Price(config, id: string, items): (string, number)
	local def = config.Decor[id]
	if def.Function == "Pedestal" then
		local costs = config.Base.PedestalCosts
		return "Coins", costs[DecorModel.Count(items, id) + 1] or math.huge
	end
	if def.Gems then
		return "Gems", def.Gems
	end
	return "Coins", def.Price or 0
end

-- ok, reason (English text key) - ignoreUid lets an item be moved onto itself
function DecorModel.Validate(config, items, id: string, x: number, z: number, rotation: number, ignoreUid: number?): (boolean, string?)
	local def = config.Decor[id]
	if not def then
		return false, "Unknown item"
	end
	local bounds = config.Base.Build
	local minX, maxX, minZ, maxZ = rect(config, id, x, z, rotation)
	local eps = 0.01
	if minX < bounds.MinX - eps or maxX > bounds.MaxX + eps or minZ < bounds.MinZ - eps or maxZ > bounds.MaxZ + eps then
		return false, "Out of bounds"
	end
	local layer = layerOf(config, id)
	for _, other in items do
		if other.Uid ~= ignoreUid and config.Decor[other.Id] and layerOf(config, other.Id) == layer then
			local oMinX, oMaxX, oMinZ, oMaxZ = rect(config, other.Id, other.X, other.Z, other.R)
			if minX < oMaxX - eps and maxX > oMinX + eps and minZ < oMaxZ - eps and maxZ > oMinZ + eps then
				return false, "Something is already there"
			end
		end
	end
	if not ignoreUid then
		if #items >= config.Base.MaxItems then
			return false, "Your base is full of decorations!"
		end
		local count = DecorModel.Count(items, id)
		local limit = if def.Function == "Pedestal" then config.Base.MaxPedestals else def.Limit
		if limit and count >= limit then
			return false, "Limit reached for this item"
		end
	end
	return true, nil
end

function DecorModel.Build(config, id: string): Model
	local model = Instance.new("Model")
	model.Name = id
	local cell = config.Base.Cell
	local def = config.Decor[id]
	local footprint = Instance.new("Part")
	footprint.Name = "Footprint"
	footprint.Anchored = true
	footprint.CanCollide = false
	footprint.CanTouch = false
	footprint.Transparency = 1
	footprint.Size = Vector3.new(def.Size[1] * cell, 0.2, def.Size[2] * cell)
	footprint.CFrame = CFrame.new(0, 0.1, 0)
	footprint.Parent = model
	model.PrimaryPart = footprint
	local builder = BUILDERS[id]
	if builder then
		builder(model)
	end
	return model
end

return DecorModel
