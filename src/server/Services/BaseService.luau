--[[
	BaseService: every player owns a walled territory in the base district.

	* YOUR HOUSE: a 72x72 lot with its own fence, gate and name sign. The
	  house LEVEL (🏗️ expand) grows the buildable land, the decoration limit
	  and the number of vaults, and upgrades the walls (wood -> stone -> gold
	  -> crystal -> galaxy). Skins (Sakura, Candy, Royal VIP, Neon, Galaxy)
	  change the look. Name your house (filtered by Roblox).
	* DECORATE: buy anything from the build menu and place it on the grid;
	  🎨 paint it in 12 colours. Removing refunds 100%. Complete a decor SET
	  for bonus income.
	* PEDESTALS: your pets stand on them and earn coins every second into the
	  bank (green pad), even offline (50%, 2h).
	  - 🔒 VAULT pedestals hold your best pets: they can NEVER be stolen but
	    earn 50%. Mark a pet "show off" to keep it out of the vault.
	  - display pedestals earn 100% and can be robbed.
	  - 💎 exclusive pets can never be stolen.
	* FAIR STEALING (you never lose everything):
	  - nobody can rob you while you're offline; your base starts locked
	  - newbie shield for the first 20 minutes (stealing yourself ends it)
	  - one theft at a time, then a 3 minute shield
	  - you can't rob a base worth less than 1/3 of yours
	  - the victim gets 5 minutes of REVENGE (locks don't stop them)
	  - serial thieves get a 💰 bounty: bonk them to claim it
	* SHOW OFF: visitors ❤️ like your house (gems + ranked points), every
	  house is in the 🏘️ Houses list with a visit button.

	data.Base.Items = { { Uid, Id, X, Z, R, Paid, Cur, Paint? }, ... } (plot space)
	data.Pets entries get Away = true while a thief carries them
]]
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local PetModel = require(Shared.PetModel)
local DecorModel = require(Shared.DecorModel)
local Net = require(script.Parent.Net)

local Base = {}
local Services
local Data
local World

local SETTINGS = Config.Base
local PLOT_HALF = SETTINGS.PlotSize / 2
local WALL_HEIGHT = 5.5 -- (a low garden wall: the camera never hides behind it)
local FLOOR_Y = 0.42 -- top of the plot floor
local GATE_HALF = 6 -- the entrance is 12 studs wide

local plots = {} -- [index] = plot record
local plotOf = {} -- [player] = plot record
local waiting = {} -- players without a plot yet (server fuller than Plots)
local touchDebounce = {} -- ["userId:what"] = os.clock()
local trapReady = {} -- [trap model] = os.clock() when it can fire again
local revenge = {} -- [victim] = { Target = thief, Until = server time }
local thefts = {} -- [thief] = { { Victim = userId, Time, Value }, ... } (bounty)
local houseNames = {} -- [player] = filtered custom house name

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------
local function part(props, parent: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

local function billboard(adornee: BasePart, width: number, height: number, offsetY: number, color: Color3, maxDistance: number?): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.new(width, 0, height, 0)
	gui.StudsOffsetWorldSpace = Vector3.new(0, offsetY, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = maxDistance or 140
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.RichText = true
	label.TextColor3 = color
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = adornee
	return label
end

local function now(): number
	return workspace:GetServerTimeNow()
end

local function playerFromHit(hit: BasePart): Player?
	local model = hit:FindFirstAncestorOfClass("Model")
	return model and Players:GetPlayerFromCharacter(model)
end

local function debounced(player: Player, what: string, seconds: number): boolean
	local key = player.UserId .. ":" .. what
	local last = touchDebounce[key]
	if last and os.clock() - last < seconds then
		return true
	end
	touchDebounce[key] = os.clock()
	return false
end

local function setPrompt(parent: BasePart, action: string, object: string, role: string, hold: number, handler, distance: number?)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.HoldDuration = hold
	prompt.MaxActivationDistance = distance or 9
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	-- the client shows Owner prompts only to the owner, Thief/Visitor ones to others
	prompt:SetAttribute("Role", role)
	prompt.Parent = parent
	prompt.Triggered:Connect(function(player)
		local ok, err = pcall(handler, player)
		if not ok then
			warn("[Base] prompt failed: " .. tostring(err))
		end
	end)
	return prompt
end

local function material(name: string?): Enum.Material
	local ok, value = pcall(function()
		return (Enum.Material :: any)[name or "SmoothPlastic"]
	end)
	return if ok and value then value else Enum.Material.SmoothPlastic
end

local function hasVip(player: Player): boolean
	return Services.MonetizationService:HasPass(player, "VIP")
end

local function houseLevel(data): number
	return Util.HouseLevel(Config, data)
end

local function validateOpts(player: Player, data)
	return { Level = houseLevel(data), Vaults = Util.VaultLimit(Config, data, hasVip(player)) }
end

---------------------------------------------------------------------------
-- building the plots (static parts once, styled walls per owner)
---------------------------------------------------------------------------
local tryLike -- forward declaration

local function buildPlot(index: number, center: Vector3, facing: Vector3): any
	-- local -Z (LookVector) faces the avenue
	local cf = CFrame.lookAt(center, center + facing)
	local model = Instance.new("Model")
	model.Name = "Plot_" .. index
	model:SetAttribute("OwnerId", 0)
	model:SetAttribute("LockedUntil", 0)
	model:SetAttribute("ShieldUntil", 0)
	model:SetAttribute("Protection", "")
	model:SetAttribute("HouseName", "")
	model:SetAttribute("OwnerName", "")
	model:SetAttribute("HouseLevel", 1)
	model:SetAttribute("Likes", 0)
	model:SetAttribute("Rate", 0)

	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end

	local floor = part({
		Name = "Floor",
		Size = Vector3.new(PLOT_HALF * 2, 0.4, PLOT_HALF * 2),
		CFrame = at(0, 0.2, 0),
		Color = Color3.fromRGB(90, 150, 80),
		Material = Enum.Material.Grass,
	}, model)
	-- the land you can build on (grows with the house level)
	local buildArea = part({
		Name = "BuildArea",
		Size = Vector3.new(32, 0.42, 36),
		CFrame = at(0, 0.21, 0),
		Color = Color3.fromRGB(110, 170, 95),
		Material = Enum.Material.Grass,
		CanCollide = false,
	}, model)

	local shell = Instance.new("Folder")
	shell.Name = "Shell"
	shell.Parent = model

	-- lock forcefield in the entrance (only blocks while locked)
	local shield = part({
		Name = "Shield",
		Size = Vector3.new(GATE_HALF * 2, WALL_HEIGHT, 0.6),
		CFrame = at(0, WALL_HEIGHT / 2, -PLOT_HALF),
		Color = Color3.fromRGB(255, 80, 90),
		Material = Enum.Material.ForceField,
		Transparency = 1,
		CanCollide = false,
	}, model)

	-- nameplate on the front wall: owner's avatar + house name, facing the
	-- avenue (a real sign, so it never covers the owner's own screen)
	local signBoard = part({
		Name = "SignBoard",
		Size = Vector3.new(17, 7, 0.6),
		CFrame = at(-GATE_HALF - 11, 5.2, -PLOT_HALF - 0.9),
		Color = Color3.fromRGB(30, 32, 46),
		Material = Enum.Material.SmoothPlastic,
	}, model)
	local signGui = Instance.new("SurfaceGui")
	signGui.Name = "Sign"
	signGui.Face = Enum.NormalId.Front
	signGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	signGui.PixelsPerStud = 30
	signGui.LightInfluence = 0
	signGui.MaxDistance = 220
	local avatar = Instance.new("ImageLabel")
	avatar.Name = "Avatar"
	avatar.BackgroundColor3 = Color3.fromRGB(60, 64, 90)
	avatar.Size = UDim2.new(0, 170, 0, 170)
	avatar.Position = UDim2.new(0, 20, 0.5, 0)
	avatar.AnchorPoint = Vector2.new(0, 0.5)
	avatar.Image = ""
	local avatarCorner = Instance.new("UICorner")
	avatarCorner.CornerRadius = UDim.new(0.5, 0)
	avatarCorner.Parent = avatar
	avatar.Parent = signGui
	local sign = Instance.new("TextLabel")
	sign.Name = "Text"
	sign.BackgroundTransparency = 1
	sign.Size = UDim2.new(1, -220, 1, -20)
	sign.Position = UDim2.fromOffset(205, 10)
	sign.Font = Enum.Font.FredokaOne
	sign.TextScaled = true
	sign.RichText = true
	sign.TextColor3 = Color3.new(1, 1, 1)
	sign.TextXAlignment = Enum.TextXAlignment.Left
	local signStroke = Instance.new("UIStroke")
	signStroke.Thickness = 2
	signStroke.Parent = sign
	sign.Parent = signGui
	signGui.Parent = signBoard
	for _, x in { -GATE_HALF - 18.5, -GATE_HALF - 3.5 } do
		part({
			Name = "SignPost",
			Size = Vector3.new(0.6, 8.6, 0.6),
			CFrame = at(x, 4.3, -PLOT_HALF - 1.1),
			Color = Color3.fromRGB(70, 72, 92),
			Material = Enum.Material.Metal,
		}, model)
	end

	-- 👑 floating crown over the gate of the most liked house in the server
	local crown = Instance.new("Model")
	crown.Name = "Crown"
	local crownBase = part({
		Name = "CrownBase",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.2, 6, 6),
		CFrame = at(0, 24, -PLOT_HALF) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(255, 205, 60),
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
		Transparency = 1,
	}, crown)
	for i = 1, 5 do
		local angle = i / 5 * math.pi * 2
		part({
			Name = "CrownSpike",
			Size = Vector3.new(1, 2.4, 1),
			CFrame = at(math.cos(angle) * 2.5, 25.6, -PLOT_HALF + math.sin(angle) * 2.5) * CFrame.Angles(0, angle, 0),
			Color = Color3.fromRGB(255, 205, 60),
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanQuery = false,
			Transparency = 1,
		}, crown)
	end
	crown.PrimaryPart = crownBase
	crown.Parent = model

	-- like post on the avenue side of the gate
	local heart = part({
		Name = "LikeHeart",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 2.2,
		CFrame = at(GATE_HALF + 4, 4.4, -PLOT_HALF - 1.6),
		Color = Color3.fromRGB(255, 80, 120),
		Material = Enum.Material.Neon,
		CanCollide = false,
	}, model)
	part({
		Name = "LikePost",
		Size = Vector3.new(0.4, 3.4, 0.4),
		CFrame = at(GATE_HALF + 4, 1.7, -PLOT_HALF - 1.6),
		Color = Color3.fromRGB(240, 240, 245),
		Material = Enum.Material.Metal,
		CanCollide = false,
	}, model)
	setPrompt(heart, "❤️ Like", "House", "Visitor", 0, function(visitor)
		tryLike(visitor, index)
	end, 12)

	-- pads: collect (green) and lock (red), just inside the gate
	local collect = part({
		Name = "CollectPad",
		Size = Vector3.new(7, 0.4, 7),
		CFrame = at(-14, 0.45, -PLOT_HALF + 5),
		Color = Color3.fromRGB(70, 255, 130),
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		CanCollide = false,
	}, model)
	local bankLabel = billboard(collect, 6.5, 2.2, 3, Color3.fromRGB(140, 255, 170), 40)
	local lockPad = part({
		Name = "LockPad",
		Size = Vector3.new(7, 0.4, 7),
		CFrame = at(14, 0.45, -PLOT_HALF + 5),
		Color = Color3.fromRGB(255, 80, 90),
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		CanCollide = false,
	}, model)
	local lockLabel = billboard(lockPad, 6.5, 1.8, 2.8, Color3.fromRGB(255, 150, 150), 35)

	-- expand board (owner only): grow the house
	local board = part({
		Name = "ExpandBoard",
		Size = Vector3.new(5, 3.4, 0.4),
		CFrame = at(26, 3.2, -PLOT_HALF + 3),
		Color = Color3.fromRGB(120, 85, 55),
		Material = Enum.Material.WoodPlanks,
	}, model)
	part({
		Name = "ExpandPost",
		Size = Vector3.new(0.4, 1.6, 0.4),
		CFrame = at(26, 0.8, -PLOT_HALF + 3),
		Color = Color3.fromRGB(100, 70, 45),
		Material = Enum.Material.Wood,
	}, model)
	local expandLabel = billboard(board, 6, 2.2, 3, Color3.fromRGB(255, 220, 120), 30)

	model.Parent = World:Folder("Bases")
	local items = Instance.new("Folder")
	items.Name = "Items"
	items.Parent = model
	local displays = Instance.new("Folder")
	displays.Name = "Displays"
	displays.Parent = model

	return {
		Index = index,
		Model = model,
		CFrame = cf,
		Owner = nil,
		Floor = floor,
		BuildArea = buildArea,
		Shell = shell,
		Sign = sign,
		Avatar = avatar,
		Crown = crown,
		BankLabel = bankLabel,
		LockLabel = lockLabel,
		ExpandBoard = board,
		ExpandLabel = expandLabel,
		Shield = shield,
		CollectPad = collect,
		LockPad = lockPad,
		Items = items,
		Displays = displays,
		ItemModels = {}, -- [uid] = Model
		LockedUntil = 0,
		LockReadyAt = 0,
		ShieldUntil = 0,
		LastLabel = "",
		StyleKey = "",
	}
end

local HOUSE_PARTS = {
	House = true,
	Roof = true,
	Door = true,
	DoorKnob = true,
	Window = true,
	HouseTower = true,
	TowerRoof = true,
	Chimney = true,
	FlagPole = true,
	Flag = true,
}

-- walls, gate, border and aura in the owner's style
local function applyStyle(plot, data)
	local styleId, style = Util.HouseStyle(Config, data)
	local level = houseLevel(data)
	local roofIndex = tonumber(data.Base.Roof) or 0
	local key = styleId .. ":" .. level .. ":" .. roofIndex
	if plot.StyleKey == key then
		return
	end
	plot.StyleKey = key
	local shell = plot.Shell
	shell:ClearAllChildren()
	local cf = plot.CFrame
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end

	plot.Floor.Color = style.Ground
	plot.Floor.Material = material(style.GroundMaterial)
	local bounds = DecorModel.Bounds(Config, level)
	local w, d = bounds.MaxX - bounds.MinX, bounds.MaxZ - bounds.MinZ
	plot.BuildArea.Size = Vector3.new(w, 0.42, d)
	plot.BuildArea.CFrame = at((bounds.MinX + bounds.MaxX) / 2, 0.21, (bounds.MinZ + bounds.MaxZ) / 2)
	plot.BuildArea.Color = style.Ground:Lerp(Color3.new(1, 1, 1), 0.12)
	plot.BuildArea.Material = material(style.GroundMaterial)

	-- walls with a gap for the gate
	local wallMaterial = material(style.WallMaterial)
	local function wallSegment(x: number, z: number, sizeX: number, sizeZ: number)
		part({
			Name = "Wall",
			Size = Vector3.new(sizeX, WALL_HEIGHT, sizeZ),
			CFrame = at(x, WALL_HEIGHT / 2, z),
			Color = style.Wall,
			Material = wallMaterial,
			Transparency = style.WallTransparency or 0,
		}, shell)
		part({
			Name = "WallTrim",
			Size = Vector3.new(sizeX + 0.3, 0.6, sizeZ + 0.3),
			CFrame = at(x, WALL_HEIGHT + 0.3, z),
			Color = style.Trim,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
		}, shell)
		if style.Stripes then
			part({
				Name = "Stripe",
				Size = Vector3.new(sizeX + 0.1, 1.2, sizeZ + 0.1),
				CFrame = at(x, WALL_HEIGHT * 0.55, z),
				Color = style.Stripes,
				Material = Enum.Material.SmoothPlastic,
				CanCollide = false,
			}, shell)
		end
	end
	local side = PLOT_HALF - GATE_HALF
	wallSegment(0, PLOT_HALF, PLOT_HALF * 2, 1) -- back
	wallSegment(-PLOT_HALF, 0, 1, PLOT_HALF * 2) -- sides
	wallSegment(PLOT_HALF, 0, 1, PLOT_HALF * 2)
	wallSegment(-(GATE_HALF + side / 2), -PLOT_HALF, side, 1) -- front, gate in the middle
	wallSegment(GATE_HALF + side / 2, -PLOT_HALF, side, 1)

	-- corner towers + gate pillars and arch (taller with every level)
	local towerHeight = WALL_HEIGHT + 1.5 + level * 0.8
	for _, corner in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		part({
			Name = "Tower",
			Size = Vector3.new(2, towerHeight, 2),
			CFrame = at(corner[1] * PLOT_HALF, towerHeight / 2, corner[2] * PLOT_HALF),
			Color = style.Pillar,
			Material = wallMaterial,
		}, shell)
		part({
			Name = "TowerCap",
			Size = Vector3.new(3, 0.8, 3),
			CFrame = at(corner[1] * PLOT_HALF, towerHeight + 0.4, corner[2] * PLOT_HALF),
			Color = style.Trim,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
		}, shell)
	end
	local gateHeight = WALL_HEIGHT + 4 + level
	for _, x in { -GATE_HALF - 0.9, GATE_HALF + 0.9 } do
		part({
			Name = "GatePillar",
			Size = Vector3.new(1.8, gateHeight, 1.8),
			CFrame = at(x, gateHeight / 2, -PLOT_HALF),
			Color = style.Pillar,
			Material = wallMaterial,
		}, shell)
	end
	part({
		Name = "GateArch",
		Size = Vector3.new(GATE_HALF * 2 + 3.6, 1.2, 1.4),
		CFrame = at(0, gateHeight - 0.6, -PLOT_HALF),
		Color = style.Trim,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
	}, shell)

	-- the house itself at the back of the land (grows with the level)
	local roofColor = Config.Paint[roofIndex] or style.Trim
	local width = 13 + level * 3
	local depth = 10
	local height = if level >= 4 then 12 else 7.5
	local cz = PLOT_HALF - 1.5 - depth / 2
	local houseMaterial = if (style.WallTransparency or 0) > 0.2 then Enum.Material.SmoothPlastic else wallMaterial
	part({
		Name = "House",
		Size = Vector3.new(width, height, depth),
		CFrame = at(0, height / 2, cz),
		Color = style.Wall,
		Material = houseMaterial,
	}, shell)
	for i = 0, 3 do -- stepped roof in your colour
		part({
			Name = "Roof",
			Size = Vector3.new(width + 1.6 - i * 0.8, 1, depth + 1.6 - i * 2.8),
			CFrame = at(0, height + 0.5 + i, cz),
			Color = roofColor,
			Material = Enum.Material.SmoothPlastic,
		}, shell)
	end
	local front = cz - depth / 2 - 0.15
	part({
		Name = "Door",
		Size = Vector3.new(3.4, 5.6, 0.3),
		CFrame = at(0, 2.8, front),
		Color = Color3.fromRGB(110, 70, 45),
		Material = Enum.Material.WoodPlanks,
	}, shell)
	part({
		Name = "DoorKnob",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 0.45,
		CFrame = at(1.1, 2.8, front - 0.25),
		Color = Color3.fromRGB(255, 210, 90),
		Material = Enum.Material.Neon,
		CanCollide = false,
	}, shell)
	local floors = if level >= 4 then { 3.8, 8.8 } else { 3.8 }
	for _, y in floors do
		for _, x in { -width / 2 + 3, width / 2 - 3, -width / 4 - 0.5, width / 4 + 0.5 } do
			if math.abs(x) > 3 or y > 5 then
				part({
					Name = "Window",
					Size = Vector3.new(2.4, 2.2, 0.3),
					CFrame = at(x, y, front),
					Color = Color3.fromRGB(255, 225, 150),
					Material = Enum.Material.Neon,
					Transparency = 0.15,
					CanCollide = false,
				}, shell)
			end
		end
	end
	if level >= 4 then
		-- castle towers
		for _, side in { -1, 1 } do
			local towerH = height + 5
			part({
				Name = "HouseTower",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(towerH, 4.4, 4.4),
				CFrame = at(side * (width / 2 + 1.6), towerH / 2, cz) * CFrame.Angles(0, 0, math.rad(90)),
				Color = style.Pillar,
				Material = houseMaterial,
			}, shell)
			for i = 0, 2 do
				part({
					Name = "TowerRoof",
					Size = Vector3.new(4.6 - i * 1.4, 1.2, 4.6 - i * 1.4),
					CFrame = at(side * (width / 2 + 1.6), towerH + 0.6 + i * 1.2, cz) * CFrame.Angles(0, math.rad(45), 0),
					Color = roofColor,
					Material = Enum.Material.SmoothPlastic,
				}, shell)
			end
		end
	else
		part({
			Name = "Chimney",
			Size = Vector3.new(1.6, 3.2, 1.6),
			CFrame = at(width / 2 - 3, height + 2.6, cz + 2),
			Color = style.Pillar,
			Material = houseMaterial,
		}, shell)
	end
	-- a flag in your roof colour on top
	part({
		Name = "FlagPole",
		Size = Vector3.new(0.3, 5, 0.3),
		CFrame = at(0, height + 6.5, cz),
		Color = Color3.fromRGB(235, 235, 240),
		Material = Enum.Material.Metal,
		CanCollide = false,
	}, shell)
	part({
		Name = "Flag",
		Size = Vector3.new(2.8, 1.6, 0.15),
		CFrame = at(1.5, height + 8, cz),
		Color = roofColor,
		Material = Enum.Material.Fabric,
		CanCollide = false,
	}, shell)

	-- the house can't be tapped through in build mode (taps reach the yard)
	for _, child in shell:GetChildren() do
		if child:IsA("BasePart") and HOUSE_PARTS[child.Name] then
			child.CanQuery = false
		end
	end

	-- border of the buildable land
	local edge = Color3.new(1, 1, 1):Lerp(style.Trim, 0.5)
	for _, strip in
		{
			{ (bounds.MinX + bounds.MaxX) / 2, bounds.MinZ, w, 0.3 },
			{ (bounds.MinX + bounds.MaxX) / 2, bounds.MaxZ, w, 0.3 },
			{ bounds.MinX, (bounds.MinZ + bounds.MaxZ) / 2, 0.3, d },
			{ bounds.MaxX, (bounds.MinZ + bounds.MaxZ) / 2, 0.3, d },
		}
	do
		part({
			Name = "Border",
			Size = Vector3.new(strip[3], 0.1, strip[4]),
			CFrame = at(strip[1], FLOOR_Y + 0.02, strip[2]),
			Color = edge,
			Material = Enum.Material.Neon,
			Transparency = 0.6,
			CanCollide = false,
			CanQuery = false,
		}, shell)
	end

	-- aura: fancy houses sparkle
	if style.Aura then
		local auraPart = part({
			Name = "Aura",
			Size = Vector3.new(PLOT_HALF * 2, 1, PLOT_HALF * 2),
			CFrame = at(0, WALL_HEIGHT + 3, 0),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		}, shell)
		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		emitter.Color = ColorSequence.new(style.Aura)
		emitter.LightEmission = 1
		emitter.Size = NumberSequence.new(0.45)
		emitter.Lifetime = NumberRange.new(2, 4)
		emitter.Rate = 4 + level * 3
		emitter.Speed = NumberRange.new(0.5, 1.5)
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Parent = auraPart
	end
end

---------------------------------------------------------------------------
-- pets on pedestals
---------------------------------------------------------------------------
local function arrange(data)
	return Util.ArrangePets(Config, data)
end

-- pets on display pedestals (the ones thieves can try to take)
function Base.DisplayedPets(data)
	local _, display = arrange(data)
	return display
end

function Base.VaultPets(data)
	local vault = arrange(data)
	return vault
end

-- coins per second of one pet for its owner (boosts included)
function Base:PetRate(player: Player, data, pet, inVault: boolean?): number
	local rate = Util.PetIncomeOf(Config, pet) * Services.StatsService:CoinMultiplier(player, data)
	if Services.MonetizationService:HasPass(player, "DoubleBase") then
		rate *= 2
	end
	rate *= 1 + Util.SetBonus(Config, data.Base.Items)
	rate *= 1 + Util.IndexBonus(Config, data) -- 📖 collection milestones + egg sets
	if inVault then
		rate *= SETTINGS.VaultIncome
	end
	return rate
end

function Base:IncomeRate(player: Player, data): number
	local total = 0
	local vault, display = arrange(data)
	for _, pet in vault do
		total += self:PetRate(player, data, pet, true)
	end
	for _, pet in display do
		total += self:PetRate(player, data, pet, false)
	end
	return total
end

---------------------------------------------------------------------------
-- rendering
---------------------------------------------------------------------------
local function itemCFrame(plot, item): CFrame
	return plot.CFrame * CFrame.new(item.X, FLOOR_Y + 0.1, item.Z) * CFrame.Angles(0, (item.R or 0) * math.pi / 2, 0)
end

local onTrap, onJump -- forward declarations

local function renderItem(plot, item)
	local existing = plot.ItemModels[item.Uid]
	if existing then
		existing:Destroy()
	end
	local model = DecorModel.Build(Config, item.Id, item.Paint)
	model:PivotTo(itemCFrame(plot, item))
	model:SetAttribute("Uid", item.Uid)
	model:SetAttribute("DecorId", item.Id)
	model.Parent = plot.Items
	plot.ItemModels[item.Uid] = model
	local def = Config.Decor[item.Id]
	local trigger = model:FindFirstChild("Trigger")
	if trigger and trigger:IsA("BasePart") and def then
		trigger.Touched:Connect(function(hit)
			local player = playerFromHit(hit)
			if not player then
				return
			end
			if def.Function == "Trap" then
				onTrap(plot, model, player)
			elseif def.Function == "Jump" then
				onJump(player, model)
			end
		end)
	end
end

-- level-ups: new numbers on the pedestal labels, no re-render (a re-render
-- would also cancel steals in progress)
function Base:RefreshPetLabels(player: Player)
	local plot = plotOf[player]
	local data = Data:Get(player)
	if not plot or not data then
		return
	end
	for _, petModel in plot.Displays:GetChildren() do
		local id = petModel:GetAttribute("PetId")
		local pet = type(id) == "number" and id > 0 and Services.PetService.FindPet(data, id)
		local anchor = petModel:IsA("Model") and petModel.PrimaryPart
		local gui = anchor and anchor:FindFirstChildOfClass("BillboardGui")
		local label = gui and gui:FindFirstChildOfClass("TextLabel")
		if pet and label then
			local inVault = petModel:GetAttribute("Vault") == true
			local info = Config.Pets[pet.Name]
			local icon = if inVault then "🔒" elseif info and info.Exclusive then "💎" else "🌠"
			local serial = if pet.Serial then " #" .. tostring(pet.Serial) else ""
			local rate = Util.Format(self:PetRate(player, data, pet, inVault))
			local badge = Util.PetBadge(Config, pet)
			if pet.Variant then
				World.SetText(label, "%s %s %s%s\n%s  💰 %s/s", icon, pet.Variant, pet.Name, serial, badge, rate)
			else
				World.SetText(label, "%s %s%s\n%s  💰 %s/s", icon, pet.Name, serial, badge, rate)
			end
		end
	end
	self:RefreshLabels(player)
end

function Base:RenderDisplays(player: Player)
	local plot = plotOf[player]
	local data = Data:Get(player)
	if not plot or not data then
		return
	end
	plot.Displays:ClearAllChildren()
	local vault, display = arrange(data)
	local displayItems, vaultItems = Util.Pedestals(Config, data.Base.Items)
	local function put(pedestal, pet, inVault: boolean)
		local model = plot.ItemModels[pedestal.Uid]
		local top = model and model:FindFirstChild("Top")
		if not top or not top:IsA("BasePart") or not pet then
			return
		end
		local info = Config.Pets[pet.Name]
		local rarity = Config.Rarities[info.Rarity] or Config.Rarities.Common
		local exclusive = info.Exclusive == true
		local petModel = PetModel.Build(pet.Name, pet.Variant, { Level = Util.PetLevel(pet), Stars = Util.PetStars(pet) })
		petModel.Name = "Pet_" .. pet.Id
		petModel:PivotTo(CFrame.new(top.Position + Vector3.new(0, 1.6, 0)) * (top.CFrame - top.Position))
		-- big (huge) pets stand on the pedestal instead of sinking into it
		local boxCFrame, boxSize = petModel:GetBoundingBox()
		local lift = (top.Position.Y + 0.2) - (boxCFrame.Position.Y - boxSize.Y / 2)
		if lift > 0 then
			petModel:PivotTo(petModel:GetPivot() + Vector3.new(0, lift, 0))
		end
		petModel:SetAttribute("Spin", true)
		petModel:SetAttribute("PetId", pet.Id)
		petModel:SetAttribute("Vault", inVault)
		petModel.Parent = plot.Displays
		local anchor = petModel.PrimaryPart :: BasePart
		local _, size = petModel:GetBoundingBox()
		local label = billboard(anchor, 5.5, 1.7, size.Y + 1, rarity.Color, 40)
		local rate = Util.Format(self:PetRate(player, data, pet, inVault))
		local icon = if inVault then "🔒" elseif exclusive then "💎" else "🌠"
		local serial = if pet.Serial then " #" .. tostring(pet.Serial) else ""
		local badge = Util.PetBadge(Config, pet)
		if pet.Variant then
			World.SetText(label, "%s %s %s%s\n%s  💰 %s/s", icon, pet.Variant, pet.Name, serial, badge, rate)
		else
			World.SetText(label, "%s %s%s\n%s  💰 %s/s", icon, pet.Name, serial, badge, rate)
		end
		local petId = pet.Id
		if not inVault and not exclusive then
			setPrompt(anchor, "Steal", pet.Name, "Thief", SETTINGS.StealHold, function(thief)
				Base:TrySteal(thief, player, petId)
			end)
		end
		setPrompt(anchor, "Sell", pet.Name, "Owner", 0.6, function(who)
			if who == player then
				Base:SellPet(player, petId)
			end
		end)
	end
	for slot, pedestal in vaultItems do
		put(pedestal, vault[slot], true)
	end
	for slot, pedestal in displayItems do
		put(pedestal, display[slot], false)
	end
	-- 🎭 prank pets: they look like a jackpot, but grabbing one is a trap
	for _, item in data.Base.Items do
		local def = Config.Decor[item.Id]
		local model = def and def.Function == "Decoy" and plot.ItemModels[item.Uid]
		local top = model and model:FindFirstChild("Top")
		if top and top:IsA("BasePart") then
			local fake = def.Fake
			-- (looks grown like real pets: no giveaway)
			local fakeGrowth = { Level = 4 + item.Uid % 7, Stars = if item.Uid % 3 == 0 then 1 else 0 }
			local petModel = PetModel.Build(fake.Name, fake.Variant, fakeGrowth)
			petModel.Name = "Decoy_" .. item.Uid
			petModel:PivotTo(CFrame.new(top.Position + Vector3.new(0, 1.6, 0)) * (top.CFrame - top.Position))
			local boxCFrame, boxSize = petModel:GetBoundingBox()
			local lift = (top.Position.Y + 0.2) - (boxCFrame.Position.Y - boxSize.Y / 2)
			if lift > 0 then
				petModel:PivotTo(petModel:GetPivot() + Vector3.new(0, lift, 0))
			end
			petModel:SetAttribute("Spin", true)
			petModel:SetAttribute("PetId", -item.Uid) -- bounces like a real pet (no giveaway)
			petModel.Parent = plot.Displays
			local anchor = petModel.PrimaryPart :: BasePart
			local info = Config.Pets[fake.Name]
			local rarity = Config.Rarities[info.Rarity] or Config.Rarities.Common
			local label = billboard(anchor, 5.5, 1.7, boxSize.Y + 1, rarity.Color, 40)
			local fakePet = { Name = fake.Name, Variant = fake.Variant, Level = fakeGrowth.Level, Stars = fakeGrowth.Stars }
			local fakeRate = Util.Format(Util.PetIncomeOf(Config, fakePet))
			World.SetText(label, "%s %s %s%s\n%s  💰 %s/s", "🌠", fake.Variant, fake.Name, "", Util.PetBadge(Config, fakePet), fakeRate)
			local decoyModel = model
			setPrompt(anchor, "Steal", fake.Name, "Thief", SETTINGS.StealHold, function(thief)
				Base:SpringDecoy(player, thief, decoyModel)
			end)
		end
	end
	-- pets in storage walk around the yard (clients render them, see YardPets)
	local yard, shown = {}, {}
	for _, pet in vault do
		shown[pet] = true
	end
	for _, pet in display do
		shown[pet] = true
	end
	local storage = {}
	for _, pet in data.Pets do
		if not shown[pet] and not pet.Away and Config.Pets[pet.Name] then
			table.insert(storage, pet)
		end
	end
	table.sort(storage, function(a, b)
		return Util.PetIncomeOf(Config, a) > Util.PetIncomeOf(Config, b)
	end)
	for i = 1, math.min(SETTINGS.YardPets, #storage) do
		table.insert(yard, (storage[i].Variant or "") .. "|" .. storage[i].Name)
	end
	plot.Model:SetAttribute("Yard", HttpService:JSONEncode(yard))
	self:RefreshLabels(player, true)
end

-- a thief grabbed a prank pet: confetti, a launch, a short stun, a laugh
local decoyReady = {} -- [model] = os.clock()
local prankCounted = {} -- ["thief:owner"] = os.clock() (one counted prank per pair per 5 min)
function Base:SpringDecoy(owner: Player, thief: Player, model: Model)
	if thief == owner or not owner.Parent or not model.Parent then
		return
	end
	-- same rules as a real steal: protected houses can't be "robbed" at all
	if not plotOf[thief] or Services.ShardService:IsCarrying(thief) or self:Protection(owner) ~= nil then
		return
	end
	if (decoyReady[model] or 0) > os.clock() then
		return
	end
	decoyReady[model] = os.clock() + 6
	model.AncestryChanged:Once(function()
		decoyReady[model] = nil
	end)
	Services.CharacterService:Stun(thief, 2)
	Net:Send(thief, "Stunned", 2)
	Net:Send(thief, "Launch", Vector3.new(0, 120, 0))
	Net:Broadcast("Confetti", model:GetPivot().Position)
	Net:Notify(thief, "🎭 It was a PRANK PET! 😂", Color3.fromRGB(255, 170, 90))
	Net:Notify(owner, "😂 %s fell for your prank pet!", Color3.fromRGB(255, 200, 90), thief.DisplayName)
	local key = thief.UserId .. ":" .. owner.UserId
	if os.clock() - (prankCounted[key] or -1e9) < 300 then
		return
	end
	prankCounted[key] = os.clock()
	local data = Data:Get(owner)
	if data then
		data.Stats.Pranks = (data.Stats.Pranks or 0) + 1
		Data:MarkDirty(owner)
	end
	Net:Announce("🎭 %s got pranked by %s's fake pet!", Color3.fromRGB(255, 190, 90), thief.DisplayName, owner.DisplayName)
end

function Base:Render(player: Player)
	local plot = plotOf[player]
	local data = Data:Get(player)
	if not plot or not data then
		return
	end
	applyStyle(plot, data)
	for _, model in plot.ItemModels do
		model:Destroy()
	end
	plot.ItemModels = {}
	for _, item in data.Base.Items do
		if Config.Decor[item.Id] then
			renderItem(plot, item)
		end
	end
	self:RenderDisplays(player)
end

---------------------------------------------------------------------------
-- protection
---------------------------------------------------------------------------
-- seconds of newbie shield left (0 = none)
function Base:NewbieShield(player: Player, data): number
	data = data or Data:Get(player)
	if not data or data.Flags.NewbieOff then
		return 0
	end
	return math.max(0, SETTINGS.NewbieShieldSeconds - (data.Stats.PlaySeconds or 0))
end

local function beingRobbed(data): boolean
	for _, pet in data.Pets do
		if pet.Away then
			return true
		end
	end
	return false
end

-- why this base can't be robbed right now (nil = it can)
function Base:Protection(owner: Player): string?
	local plot = plotOf[owner]
	local data = Data:Get(owner)
	if not plot or not data then
		return "none"
	end
	local t = now()
	if beingRobbed(data) then
		return "robbing"
	end
	-- 🏠 homes are safe - raids only happen on 🌙 Thief Night
	-- (a thief's own home stays open to their victim's revenge for a while)
	local events = Services.EventService
	if not (events and events:RaidActive()) then
		for _, entry in revenge do
			if entry.Target == owner and entry.Until > t then
				return "revenge"
			end
		end
		return "safe"
	end
	if plot.LockedUntil > t then
		return "locked"
	end
	if self:NewbieShield(owner, data) > 0 then
		return "newbie"
	end
	if plot.ShieldUntil > t then
		return "shield"
	end
	return nil
end

function Base:IsLocked(owner: Player): boolean
	local plot = plotOf[owner]
	return plot ~= nil and plot.LockedUntil > now()
end

function Base:LockSeconds(player: Player, data): number
	local bonus = math.min((data.Rebirths or 0) * SETTINGS.LockPerRebirth, SETTINGS.LockMaxBonus)
	if hasVip(player) then
		bonus += SETTINGS.LockVipBonus
	end
	return SETTINGS.LockSeconds + bonus
end

-- active revenge of `victim` against `target`?
function Base:HasRevenge(victim: Player, target: Player): boolean
	local entry = revenge[victim]
	return entry ~= nil and entry.Target == target and entry.Until > now()
end

-- current bounty on a thief (coins), pruning old thefts
function Base:Bounty(thief: Player): number
	local log = thefts[thief]
	if not log then
		return 0
	end
	local t = now()
	local kept, victims, value = {}, {}, 0
	for _, entry in log do
		if t - entry.Time <= SETTINGS.Bounty.WindowSeconds then
			table.insert(kept, entry)
			victims[entry.Victim] = true
			value += entry.Value
		end
	end
	thefts[thief] = if #kept > 0 then kept else nil
	local distinct = 0
	for _ in victims do
		distinct += 1
	end
	return if distinct >= SETTINGS.Bounty.MinVictims then math.floor(value) else 0
end

local STATUS_TEXT = {
	safe = "🏠 SAFE",
	revenge = "🎯 REVENGE TARGET",
	locked = "🔒 LOCKED",
	newbie = "🛡️ NEWBIE SHIELD",
	shield = "🛡️ THEFT SHIELD",
	robbing = "🚨 BEING ROBBED!",
}

function Base:RefreshLabels(player: Player, force: boolean?)
	local plot = plotOf[player]
	local data = Data:Get(player)
	if not plot or not data then
		return
	end
	local rate = self:IncomeRate(player, data)
	local vault, display = arrange(data)
	local stored = math.max(0, #data.Pets - #vault - #display)
	local level = houseLevel(data)
	local protection = self:Protection(player)
	local status = STATUS_TEXT[protection or ""] or "🔓 OPEN"
	local customName = houseNames[player]
	local signText = table.concat({ Util.Format(rate), data.Base.Likes, level, status, customName or "" }, "|")
	if force or signText ~= plot.LastLabel then
		plot.LastLabel = signText
		local _, style = Util.HouseStyle(Config, data)
		plot.Sign.TextColor3 = Color3.new(1, 1, 1):Lerp(style.Trim, 0.35)
		if customName and customName ~= "" then
			World.SetText(
				plot.Sign,
				"🏠 %s\n💰 %s/s  ❤️ %s  ⭐ Lv.%s\n%s",
				customName,
				Util.Format(rate),
				tostring(data.Base.Likes),
				tostring(level),
				status
			)
		else
			World.SetText(
				plot.Sign,
				"🏠 %s's HOUSE\n💰 %s/s  ❤️ %s  ⭐ Lv.%s\n%s",
				player.DisplayName,
				Util.Format(rate),
				tostring(data.Base.Likes),
				tostring(level),
				status
			)
		end
		local nextLevel = SETTINGS.Levels[level + 1]
		if nextLevel then
			World.SetText(plot.ExpandLabel, "🏗️ EXPAND\nLv.%s 💰%s", tostring(level + 1), Util.Format(nextLevel.Cost))
		else
			World.SetText(plot.ExpandLabel, "🏰 MAX LEVEL")
		end
		local model = plot.Model
		model:SetAttribute("HouseName", customName or "")
		model:SetAttribute("OwnerName", player.DisplayName)
		model:SetAttribute("HouseLevel", level)
		model:SetAttribute("Likes", data.Base.Likes)
		model:SetAttribute("Rate", math.floor(rate))
	end
	World.SetText(plot.BankLabel, "💰 %s\nSTEP TO COLLECT", Util.Format(math.floor(data.Base.Bank)))
	local t = now()
	if plot.LockedUntil > t then
		World.SetText(plot.LockLabel, "🔒 LOCKED %ds", math.ceil(plot.LockedUntil - t))
	elseif plot.LockReadyAt > t then
		World.SetText(plot.LockLabel, "⏳ %ds", math.ceil(plot.LockReadyAt - t))
	else
		World.SetText(plot.LockLabel, "🔒 LOCK BASE")
	end
	-- shield bubble: red = locked (blocks the gate), blue = protected
	if protection == "locked" then
		plot.Shield.Color = Color3.fromRGB(255, 80, 90)
		plot.Shield.Transparency = 0.3
		plot.Shield.CanCollide = true -- the owner's client turns this off locally
	elseif protection == "newbie" or protection == "shield" then
		plot.Shield.Color = Color3.fromRGB(90, 190, 255)
		plot.Shield.Transparency = 0.55
		plot.Shield.CanCollide = false
	else
		plot.Shield.Transparency = 1
		plot.Shield.CanCollide = false
	end
	plot.Model:SetAttribute("Protection", protection or "")
	plot.Model:SetAttribute("Robbing", beingRobbed(data))
	player:SetAttribute("BaseRate", rate)
	player:SetAttribute("BaseBank", math.floor(data.Base.Bank))
	player:SetAttribute("BaseStored", stored)
	player:SetAttribute("BaseProtection", protection or "")
	player:SetAttribute("NewbieShield", self:NewbieShield(player, data))
	player:SetAttribute("ShieldUntil", plot.ShieldUntil)
	player:SetAttribute("LockedUntil", plot.LockedUntil)
	local bounty = self:Bounty(player)
	if (player:GetAttribute("Bounty") or 0) ~= bounty then
		player:SetAttribute("Bounty", if bounty > 0 then bounty else nil)
	end
end

local function clearPlot(plot)
	plot.Owner = nil
	plot.Avatar.Image = ""
	plot.Model:SetAttribute("Yard", "[]")
	plot.Model:SetAttribute("BestHouse", false)
	for _, crownPart in plot.Crown:GetChildren() do
		if crownPart:IsA("BasePart") then
			crownPart.Transparency = 1
		end
	end
	for _, model in plot.ItemModels do
		model:Destroy()
	end
	plot.ItemModels = {}
	plot.Displays:ClearAllChildren()
	plot.Shell:ClearAllChildren()
	plot.StyleKey = ""
	local model = plot.Model
	model:SetAttribute("OwnerId", 0)
	model:SetAttribute("LockedUntil", 0)
	model:SetAttribute("ShieldUntil", 0)
	model:SetAttribute("Protection", "")
	model:SetAttribute("HouseName", "")
	model:SetAttribute("OwnerName", "")
	model:SetAttribute("Likes", 0)
	model:SetAttribute("Rate", 0)
	plot.LockedUntil = 0
	plot.LockReadyAt = 0
	plot.ShieldUntil = 0
	plot.Shield.Transparency = 1
	plot.Shield.CanCollide = false
	plot.LastLabel = ""
	plot.Floor.Color = Color3.fromRGB(90, 150, 80)
	plot.Floor.Material = Enum.Material.Grass
	World.SetText(plot.Sign, "🏠 FREE LAND")
	World.SetText(plot.BankLabel, "")
	World.SetText(plot.LockLabel, "")
	World.SetText(plot.ExpandLabel, "")
end

---------------------------------------------------------------------------
-- public API (used by ShardService / MiningService / UI)
---------------------------------------------------------------------------
function Base:PlotOf(player: Player)
	return plotOf[player]
end

-- (RivalHomes builds rival players' homes with the same parts)
Base.Internal = {
	Plots = plots,
	ApplyStyle = applyStyle,
	SetPrompt = setPrompt,
	Billboard = billboard,
	ClearPlot = clearPlot,
	PlotHalf = PLOT_HALF,
}

function Base:HasBase(player: Player): boolean
	return plotOf[player] ~= nil
end

-- is this position inside the player's own territory?
function Base:InOwnPlot(player: Player, position: Vector3): boolean
	local plot = plotOf[player]
	if not plot then
		return false
	end
	local localPos = plot.CFrame:PointToObjectSpace(position)
	return math.abs(localPos.X) <= PLOT_HALF and math.abs(localPos.Z) <= PLOT_HALF + 1
end

function Base:HomeCFrame(player: Player): CFrame?
	local plot = plotOf[player]
	return plot and (plot.CFrame * CFrame.new(0, 3, -PLOT_HALF + 5))
end

-- just outside the gate, looking in (for visitors)
function Base:GateCFrame(owner: Player): CFrame?
	local plot = plotOf[owner]
	if not plot then
		return nil
	end
	local spot = plot.CFrame * CFrame.new(0, 3, -PLOT_HALF - 8)
	return CFrame.lookAt(spot.Position, (plot.CFrame * CFrame.new(0, 3, 0)).Position)
end

-- a pet is being carried away by a thief (or came back)
function Base:SetAway(owner: Player, petId: number, away: boolean)
	local data = Data:Get(owner)
	local pet = data and Services.PetService.FindPet(data, petId)
	if not pet then
		return
	end
	pet.Away = if away then true else nil
	if owner.Parent then
		Services.PetService:Changed(owner)
	end
end

function Base:SellPet(player: Player, petId: number)
	local data = Data:Get(player)
	local pet, index = nil, nil
	if data then
		pet, index = Services.PetService.FindPet(data, petId)
	end
	if not pet or pet.Away or pet.SerialPending then
		return
	end
	local coins = Services.PetService:SellValueOf(pet)
	table.remove(data.Pets, index)
	data.Coins += coins
	data.Stats.LifetimeCoins += coins
	Net:Notify(player, "Sold %s for 💰%s", Color3.fromRGB(255, 220, 120), pet.Name, Util.Format(coins))
	Services.PetService:Changed(player)
end

local PROTECTION_MESSAGES = {
	safe = "🏠 Homes are safe! Raids only happen on 🌙 Thief Night.",
	revenge = "🏠 Homes are safe! Raids only happen on 🌙 Thief Night.",
	locked = "🔒 This base is locked!",
	newbie = "🛡️ This player is new - their base is protected for now.",
	shield = "🛡️ This base was just robbed - it's protected for a few minutes.",
	robbing = "Someone is already stealing from this base!",
	none = "You can't steal here.",
}

function Base:TrySteal(thief: Player, owner: Player, petId: number)
	if thief == owner or not owner.Parent then
		return
	end
	local shards = Services.ShardService
	if shards:IsCarrying(thief) then
		Net:Notify(thief, "Your hands are full!")
		return
	end
	if not plotOf[thief] then
		Net:Notify(thief, "You need a base to steal pets!")
		return
	end
	local data = Data:Get(owner)
	local thiefData = Data:Get(thief)
	local pet = data and Services.PetService.FindPet(data, petId)
	if not pet or pet.Away or not thiefData then
		return
	end
	local isRevenge = self:HasRevenge(thief, owner)
	-- one theft at a time, always (revenge too)
	if beingRobbed(data) then
		Net:Notify(thief, PROTECTION_MESSAGES.robbing)
		return
	end
	-- revenge ignores locks and shields
	local protection = self:Protection(owner)
	if protection and not (isRevenge and protection ~= "none") then
		Net:Notify(thief, PROTECTION_MESSAGES[protection] or PROTECTION_MESSAGES.none)
		return
	end
	if pet.SerialPending then
		return -- (numbering a brand-new pet takes a second)
	end
	if Util.IsExclusive(Config, pet) then
		Net:Notify(thief, "💎 Exclusive pets can't be stolen!")
		return
	end
	local onDisplay = false
	for _, shown in self.DisplayedPets(data) do
		if shown.Id == petId then
			onDisplay = true
		end
	end
	if not onDisplay then
		Net:Notify(thief, "🔒 Pets in a vault can't be stolen!")
		return
	end
	-- fair play: big players can't farm tiny bases
	if not isRevenge then
		local thiefWorth = Util.PetWorth(Config, thiefData)
		local victimWorth = Util.PetWorth(Config, data)
		if thiefWorth >= SETTINGS.StealGapMinWorth and thiefWorth > victimWorth * SETTINGS.StealGap then
			Net:Notify(thief, "This base is too small for you - pick on someone your size!")
			return
		end
	end
	self:SetAway(owner, petId, true)
	local item = { Kind = "Pet", Name = pet.Name, Variant = pet.Variant, Serial = pet.Serial }
	local meta = {
		From = owner,
		PetId = petId,
		Thief = thief,
		Revenge = isRevenge,
		-- nobody can hold a stolen pet forever (that would block the base)
		Deadline = os.clock() + SETTINGS.StolenCarrySeconds,
	}
	if not shards:StartCarry(thief, item, meta) then
		self:SetAway(owner, petId, false)
		return
	end
	-- stealing ends your own newbie shield
	if self:NewbieShield(thief, thiefData) > 0 then
		thiefData.Flags.NewbieOff = true
		Net:Notify(thief, "🛡️ You stole - your newbie shield is now off.", Color3.fromRGB(150, 200, 255))
	end
	local display = pet.Name
	Net:Send(owner, "BaseAlarm", thief.DisplayName, display)
	Net:Notify(owner, "🚨 %s is stealing your %s! Bonk them!", Color3.fromRGB(255, 80, 80), thief.DisplayName, display)
	Net:Notify(thief, "🏃 You stole a %s! Run to your base!", Color3.fromRGB(255, 170, 80), display)
	self:RefreshLabels(owner, true)
end

-- a stolen pet reached the thief's base (called by ShardService)
function Base:StealDelivered(owner: Player, thief: Player, meta, pet)
	local plot = plotOf[owner]
	if plot then
		plot.ShieldUntil = now() + SETTINGS.TheftShieldSeconds
		plot.Model:SetAttribute("ShieldUntil", plot.ShieldUntil)
	end
	if meta and meta.Revenge and meta.Thief == thief then
		revenge[thief] = nil
		thief:SetAttribute("RevengeTarget", nil)
		thief:SetAttribute("RevengeUntil", nil)
		Net:Notify(thief, "🎯 Revenge complete!", Color3.fromRGB(255, 210, 90))
	else
		-- the victim may strike back
		if owner.Parent then
			revenge[owner] = { Target = thief, Until = now() + SETTINGS.RevengeSeconds }
			owner:SetAttribute("RevengeTarget", thief.UserId)
			owner:SetAttribute("RevengeUntil", now() + SETTINGS.RevengeSeconds)
			Net:Send(owner, "Revenge", thief.UserId, thief.DisplayName, now() + SETTINGS.RevengeSeconds)
			Net:Notify(
				owner,
				"🎯 REVENGE! For 5 minutes you can raid %s's base - locks can't stop you!",
				Color3.fromRGB(255, 210, 90),
				thief.DisplayName
			)
		end
		-- serial thieves get a bounty
		local before = self:Bounty(thief)
		thefts[thief] = thefts[thief] or {}
		local value = Util.PetIncomeOf(Config, pet) * SETTINGS.Bounty.IncomeSeconds
		table.insert(thefts[thief], { Victim = owner.UserId, Time = now(), Value = value })
		local after = self:Bounty(thief)
		if after > 0 then
			thief:SetAttribute("Bounty", after)
			if before == 0 then
				Net:Announce(
					"💰 BOUNTY! %s robbed too many houses - bonk them while they carry a pet to win 💰%s!",
					Color3.fromRGB(255, 200, 60),
					thief.DisplayName,
					Util.Format(after)
				)
			end
		end
	end
	if owner.Parent then
		self:RefreshLabels(owner, true)
	end
end

-- someone stopped a thief (bonk or trap): count it + pay the bounty
function Base:ThiefCaught(hunter: Player, thief: Player, count: boolean?)
	if hunter == thief then
		return
	end
	local data = Data:Get(hunter)
	if not data then
		return
	end
	if count ~= false then
		data.Stats.ThievesCaught = (data.Stats.ThievesCaught or 0) + 1
	end
	local bounty = self:Bounty(thief)
	if bounty > 0 then
		thefts[thief] = nil
		thief:SetAttribute("Bounty", nil)
		data.Coins += bounty
		data.Stats.LifetimeCoins += bounty
		Services.Analytics:Economy(hunter, "Source", "Coins", bounty, data.Coins, "Gameplay", "Bounty")
		Net:Send(hunter, "Sold", bounty)
		Net:Announce(
			"💰 %s caught %s and won the 💰%s bounty!",
			Color3.fromRGB(255, 200, 60),
			hunter.DisplayName,
			thief.DisplayName,
			Util.Format(bounty)
		)
	end
	Data:MarkDirty(hunter)
end

function Base:Collect(player: Player)
	local data = Data:Get(player)
	if not data then
		return
	end
	local amount = math.floor(data.Base.Bank)
	if amount <= 0 then
		return
	end
	data.Base.Bank -= amount
	data.Coins += amount
	data.Stats.LifetimeCoins += amount
	Services.ProgressionService:AddQuest(player, "Collect", 1)
	Services.Analytics:Economy(player, "Source", "Coins", amount, data.Coins, "Gameplay", "BaseCollect")
	Net:Send(player, "BaseCollected", amount)
	Data:MarkDirty(player)
	self:RefreshLabels(player)
end

local function lockFor(plot, seconds: number)
	plot.LockedUntil = now() + seconds
	plot.LockReadyAt = plot.LockedUntil
	plot.Model:SetAttribute("LockedUntil", plot.LockedUntil)
end

function Base:Lock(player: Player)
	local plot = plotOf[player]
	local data = Data:Get(player)
	if not plot or not data then
		return
	end
	local t = now()
	if plot.LockedUntil > t or plot.LockReadyAt > t then
		return
	end
	local events = Services.EventService
	if not (events and events:RaidActive()) then
		-- (don't waste the lock: homes can only be raided on Thief Night)
		if debounced(player, "lockhint", 8) then
			return
		end
		Net:Notify(player, "🏠 Your home is safe right now - save the lock for 🌙 Thief Night!", Color3.fromRGB(150, 230, 160))
		return
	end
	local seconds = self:LockSeconds(player, data)
	lockFor(plot, seconds)
	plot.LockReadyAt = plot.LockedUntil + SETTINGS.LockCooldown
	Net:Notify(player, "🔒 Base locked for %ds!", Color3.fromRGB(255, 150, 150), seconds)
	self:RefreshLabels(player, true)
end

---------------------------------------------------------------------------
-- decorating
---------------------------------------------------------------------------
local function findItem(data, uid)
	for index, item in data.Base.Items do
		if item.Uid == uid then
			return item, index
		end
	end
	return nil, nil
end

local function finite(value): boolean
	return type(value) == "number" and value == value and math.abs(value) < 1e6
end

local function cleanTransform(x, z, r): (number?, number?, number?)
	-- NaN / inf would end up in the save (DataStores can't store them)
	if not finite(x) or not finite(z) or not finite(r) then
		return nil, nil, nil
	end
	local rotation = math.floor(r) % 4
	if rotation ~= rotation then
		return nil, nil, nil
	end
	return x, z, rotation
end

local function isPedestal(id: string): boolean
	local def = Config.Decor[id]
	return def ~= nil and (def.Function == "Pedestal" or def.Function == "Vault" or def.Function == "Decoy")
end

-- returns ok, message
function Base:Place(player: Player, id, x, z, r): (boolean, string?)
	local data = Data:Get(player)
	local plot = plotOf[player]
	local def = type(id) == "string" and Config.Decor[id]
	x, z, r = cleanTransform(x, z, r)
	if not data or not plot or not def or not x then
		return false, "Can't place that here"
	end
	x, z = DecorModel.Snap(Config, id, x, z, r)
	local items = data.Base.Items
	local ok, reason = DecorModel.Validate(Config, items, id, x, z, r, nil, validateOpts(player, data))
	if not ok then
		return false, reason
	end
	local currency, price = DecorModel.Price(Config, id, items)
	local have = if currency == "Gems" then data.Gems else data.Coins
	if have < price then
		return false, if currency == "Gems" then "Not enough gems!" else "Not enough coins!"
	end
	if currency == "Gems" then
		data.Gems -= price
	else
		data.Coins -= price
	end
	local item = { Uid = data.Base.NextUid, Id = id, X = x, Z = z, R = r, Paid = price, Cur = currency }
	data.Base.NextUid += 1
	table.insert(items, item)
	renderItem(plot, item)
	if isPedestal(id) then
		self:RenderDisplays(player)
	end
	Services.ProgressionService:AddQuest(player, "Decorate", 1)
	Data:MarkDirty(player)
	self:RefreshLabels(player, true)
	return true, nil
end

function Base:Move(player: Player, uid, x, z, r): (boolean, string?)
	local data = Data:Get(player)
	local plot = plotOf[player]
	local item = data and type(uid) == "number" and findItem(data, uid)
	x, z, r = cleanTransform(x, z, r)
	if not item or not plot or not x then
		return false, "Can't move that"
	end
	x, z = DecorModel.Snap(Config, item.Id, x, z, r)
	local ok, reason = DecorModel.Validate(Config, data.Base.Items, item.Id, x, z, r, item.Uid, validateOpts(player, data))
	if not ok then
		return false, reason
	end
	item.X, item.Z, item.R = x, z, r
	renderItem(plot, item)
	if isPedestal(item.Id) then
		self:RenderDisplays(player)
	end
	Data:MarkDirty(player)
	return true, nil
end

function Base:Remove(player: Player, uid): (boolean, string?)
	local data = Data:Get(player)
	local plot = plotOf[player]
	local item, index = nil, nil
	if data and type(uid) == "number" then
		item, index = findItem(data, uid)
	end
	if not item or not plot then
		return false, "Can't remove that"
	end
	local def = Config.Decor[item.Id]
	if def and def.Function == "Pedestal" and DecorModel.Count(data.Base.Items, "Pedestal") <= 1 then
		return false, "Keep at least one pedestal!"
	end
	table.remove(data.Base.Items, index)
	local refund = math.max(0, math.floor(item.Paid or 0))
	if item.Cur == "Gems" then
		data.Gems += refund
	else
		data.Coins += refund
	end
	local model = plot.ItemModels[item.Uid]
	plot.ItemModels[item.Uid] = nil
	if model then
		model:Destroy()
	end
	if isPedestal(item.Id) then
		self:RenderDisplays(player)
	end
	Data:MarkDirty(player)
	self:RefreshLabels(player, true)
	return true, nil
end

-- 🎨 paint: 0 = original colours, 1..#Config.Paint = palette colour (free)
function Base:Paint(player: Player, uid, color): (boolean, string?)
	local data = Data:Get(player)
	local plot = plotOf[player]
	local item = data and type(uid) == "number" and findItem(data, uid)
	if not item or not plot or not finite(color) then
		return false, "Can't paint that"
	end
	color = math.floor(color)
	if color < 0 or color > #Config.Paint or not DecorModel.CanPaint(item.Id) then
		return false, "Can't paint that"
	end
	item.Paint = if color == 0 then nil else color
	renderItem(plot, item)
	if isPedestal(item.Id) then
		self:RenderDisplays(player)
	end
	Data:MarkDirty(player)
	return true, nil
end

-- 🐾 tidy up: all pedestals line up in neat rows (vaults at the back near the
-- house, display pedestals in front). Nothing else moves; all or nothing.
function Base:ArrangePedestals(player: Player): (boolean, string?)
	local data = Data:Get(player)
	local plot = plotOf[player]
	if not data or not plot then
		return false, "You need a base first!"
	end
	local items = data.Base.Items
	local others, peds = {}, {}
	for _, item in items do
		local def = Config.Decor[item.Id]
		if def and (def.Function == "Pedestal" or def.Function == "Vault" or def.Function == "Decoy") then
			table.insert(peds, item)
		else
			table.insert(others, item)
		end
	end
	-- (decoys mix in with the real display pedestals: no giveaway)
	local order = { Vault = 1, Pedestal = 2, Decoy = 2 }
	table.sort(peds, function(a, b)
		local oa, ob = order[Config.Decor[a.Id].Function], order[Config.Decor[b.Id].Function]
		if oa ~= ob then
			return oa < ob
		end
		return a.Uid < b.Uid
	end)
	local level = houseLevel(data)
	local bounds = DecorModel.Bounds(Config, level)
	local opts = validateOpts(player, data)
	local spacing = 6
	local width = bounds.MaxX - bounds.MinX
	local columns = math.max(1, math.floor(width / spacing))
	local startX = bounds.MinX + (width - (columns - 1) * spacing) / 2
	local saved = {}
	for _, item in peds do
		saved[item] = { item.X, item.Z, item.R }
	end
	local placed = table.clone(others)
	local index = 1
	local z = bounds.MaxZ - 3
	while index <= #peds and z - 2 >= bounds.MinZ do
		for column = 0, columns - 1 do
			local item = peds[index]
			if not item then
				break
			end
			local x, sz = DecorModel.Snap(Config, item.Id, startX + column * spacing, z, 0)
			if DecorModel.Validate(Config, placed, item.Id, x, sz, 0, item.Uid, opts) then
				item.X, item.Z, item.R = x, sz, 0
				table.insert(placed, item)
				index += 1
			end
		end
		z -= spacing
	end
	if index <= #peds then
		for item, transform in saved do
			item.X, item.Z, item.R = transform[1], transform[2], transform[3]
		end
		return false, "Not enough free room - move some decorations first!"
	end
	for _, item in peds do
		renderItem(plot, item)
	end
	self:RenderDisplays(player)
	Data:MarkDirty(player)
	return true, nil
end

-- 🎨 roof + flag colour (0 = the style's colour)
function Base:SetRoof(player: Player, color): (boolean, string?)
	local data = Data:Get(player)
	local plot = plotOf[player]
	if not data or not plot or not finite(color) then
		return false, "Can't paint that"
	end
	color = math.floor(color)
	if color < 0 or color > #Config.Paint then
		return false, "Can't paint that"
	end
	data.Base.Roof = color
	local styleId, style = Util.HouseStyle(Config, data)
	local prefix = styleId .. ":" .. houseLevel(data) .. ":"
	if string.sub(plot.StyleKey, 1, #prefix) == prefix then
		-- same house: just repaint (no rebuild)
		plot.StyleKey = prefix .. color
		local roofColor = Config.Paint[color] or style.Trim
		for _, child in plot.Shell:GetChildren() do
			if child:IsA("BasePart") and (child.Name == "Roof" or child.Name == "TowerRoof" or child.Name == "Flag") then
				child.Color = roofColor
			end
		end
	else
		applyStyle(plot, data)
	end
	Data:MarkDirty(player)
	return true, nil
end

---------------------------------------------------------------------------
-- house: level, name, skin
---------------------------------------------------------------------------
function Base:Upgrade(player: Player): (boolean, string?)
	local data = Data:Get(player)
	local plot = plotOf[player]
	if not data or not plot then
		return false, "You need a base first!"
	end
	local level = houseLevel(data)
	local nextDef = SETTINGS.Levels[level + 1]
	if not nextDef then
		return false, "Your house is already max level!"
	end
	if data.Coins < nextDef.Cost then
		return false, "Not enough coins!"
	end
	data.Coins -= nextDef.Cost
	data.Base.Level = level + 1
	Services.Analytics:Economy(player, "Sink", "Coins", nextDef.Cost, data.Coins, "Upgrade", "House" .. (level + 1))
	Services.Analytics:Custom(player, "HouseLevel", level + 1)
	applyStyle(plot, data)
	self:RefreshLabels(player, true)
	Net:Notify(player, "🏗️ Your house grew into a %s!", Color3.fromRGB(255, 220, 120), nextDef.Name)
	Net:Send(player, "HouseUpgraded", level + 1)
	if level + 1 >= 4 then
		Net:Announce("🏰 %s upgraded their house to a %s!", Color3.fromRGB(210, 150, 255), player.DisplayName, nextDef.Name)
	end
	Data:MarkDirty(player)
	return true, nil
end

local function filterName(player: Player, text: string): string?
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(text, player.UserId, Enum.TextFilterContext.PublicChat)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if ok and type(result) == "string" then
		return result
	end
	return nil
end

function Base:SetName(player: Player, text): (boolean, string?)
	local data = Data:Get(player)
	if not data or type(text) ~= "string" then
		return false, "Invalid name"
	end
	-- cap first: pattern matching a huge string would stall the server
	if #text > SETTINGS.NameMax * 4 then
		return false, "That name is too long!"
	end
	text = string.gsub(text, "[%c]", "")
	text = string.gsub(text, "^%s+", "")
	text = string.gsub(text, "%s+$", "")
	local length = utf8.len(text)
	if not length or length > SETTINGS.NameMax then
		return false, "That name is too long!"
	end
	if length == 0 then
		data.Base.Name = ""
		houseNames[player] = nil
		self:RefreshLabels(player, true)
		Data:MarkDirty(player)
		return true, nil
	end
	local filtered = filterName(player, text)
	if not filtered then
		return false, "Couldn't check that name - try again later."
	end
	data.Base.Name = text -- the raw text is re-filtered every time it's shown again
	houseNames[player] = filtered
	self:RefreshLabels(player, true)
	Data:MarkDirty(player)
	return true, nil
end

local function skinDef(id)
	for _, def in Config.HouseSkins do
		if def.Id == id then
			return def
		end
	end
	return nil
end

function Base:GrantSkin(player: Player, id: string)
	local data = Data:Get(player)
	if not data or not skinDef(id) then
		return
	end
	data.Base.Skins[id] = true
	data.Base.Skin = id
	local plot = plotOf[player]
	if plot then
		applyStyle(plot, data)
		self:RefreshLabels(player, true)
	end
	Net:Notify(player, "🎨 New house skin: %s!", Color3.fromRGB(255, 200, 120), skinDef(id).Name)
	Data:MarkDirty(player)
end

function Base:SetSkin(player: Player, id): (boolean, string?)
	local data = Data:Get(player)
	local def = type(id) == "string" and skinDef(id)
	if not data or not def then
		return false, "Unknown skin"
	end
	local base = data.Base
	if def.Id ~= "Auto" and not base.Skins[def.Id] then
		if def.Pass then
			if not Services.MonetizationService:HasPass(player, def.Pass) then
				return false, "VIP only! 👑"
			end
		elseif def.Level then
			if houseLevel(data) < def.Level then
				return false, Net:L(player, "Reach house level %d first!", def.Level)
			end
		elseif def.Gems then
			if data.Gems < def.Gems then
				return false, "Not enough gems!"
			end
			data.Gems -= def.Gems
			base.Skins[def.Id] = true
			Services.Analytics:Economy(player, "Sink", "Gems", def.Gems, data.Gems, "Cosmetic", "Skin" .. def.Id)
		elseif def.Product then
			return false, "Buy this skin in the store!"
		end
	end
	base.Skin = def.Id
	local plot = plotOf[player]
	if plot then
		applyStyle(plot, data)
		self:RefreshLabels(player, true)
	end
	Data:MarkDirty(player)
	return true, nil
end

-- traps: freeze intruders; a stolen pet from this base goes straight home
onTrap = function(plot, model: Model, player: Player)
	local owner = plot.Owner
	if not owner or owner == player then
		return
	end
	local ready = trapReady[model] or 0
	if os.clock() < ready then
		return
	end
	trapReady[model] = os.clock() + SETTINGS.TrapCooldown
	model.AncestryChanged:Once(function()
		trapReady[model] = nil
	end)
	Services.CharacterService:Stun(player, SETTINGS.TrapStun)
	local recovered = Services.ShardService:Confiscate(player, owner)
	Net:Send(player, "Stunned", SETTINGS.TrapStun)
	Net:Notify(player, "⚡ You stepped on a trap!", Color3.fromRGB(255, 230, 80))
	if recovered then
		Net:Notify(owner, "⚡ Your trap caught %s - pet saved!", Color3.fromRGB(255, 230, 80), player.DisplayName)
		Base:ThiefCaught(owner, player)
	else
		Net:Notify(owner, "⚡ Your trap stunned %s!", Color3.fromRGB(255, 230, 80), player.DisplayName)
	end
end

onJump = function(player: Player, model: Model)
	if debounced(player, "jump", 0.8) then
		return
	end
	local look = model:GetPivot().LookVector * Vector3.new(1, 0, 1)
	Net:Send(player, "Launch", Vector3.new(0, 95, 0) + look * 25)
end

---------------------------------------------------------------------------
-- likes
---------------------------------------------------------------------------
tryLike = function(visitor: Player, plotIndex: number)
	local plot = plots[plotIndex]
	local owner = plot and plot.Owner
	if not owner or owner == visitor then
		return
	end
	local data = Data:Get(owner)
	if not data then
		return
	end
	local base = data.Base
	local key = tostring(visitor.UserId)
	local today = Util.DayNumber()
	if base.LikedBy[key] == today then
		Net:Notify(visitor, "You already liked this base today ❤️")
		return
	end
	base.LikedBy[key] = today
	base.Likes += 1
	local week = Util.WeekNumber()
	if base.LikeWeek ~= week then
		base.LikeWeek = week
		base.WeeklyLikes = 0
	end
	base.WeeklyLikes += 1
	-- a few gems for the owner (capped per day): decorating pays off
	if base.LikeGemsDay ~= today then
		base.LikeGemsDay = today
		base.LikeGemsToday = 0
	end
	local gems = math.min(SETTINGS.LikeGems, SETTINGS.LikeGemsDaily - base.LikeGemsToday)
	if gems > 0 then
		base.LikeGemsToday += gems
		data.Gems += gems
	end
	Services.ProgressionService:AddPoints(owner, SETTINGS.LikePoints)
	Services.ProgressionService:AddQuest(visitor, "Like", 1)
	if gems > 0 then
		Net:Notify(owner, "❤️ %s liked your house! +💎%d", Color3.fromRGB(255, 120, 160), visitor.DisplayName, gems)
	else
		Net:Notify(owner, "❤️ %s liked your base!", Color3.fromRGB(255, 120, 160), visitor.DisplayName)
	end
	Net:Notify(visitor, "❤️ You liked %s's base!", Color3.fromRGB(255, 120, 160), owner.DisplayName)
	Net:Send(owner, "BaseLiked", visitor.DisplayName)
	Data:MarkDirty(owner)
	Base:RefreshLabels(owner, true)
end

---------------------------------------------------------------------------
-- plot assignment
---------------------------------------------------------------------------
local function addItem(base, id: string, x: number, z: number, r: number, level: number): boolean
	x, z = DecorModel.Snap(Config, id, x, z, r)
	if DecorModel.Validate(Config, base.Items, id, x, z, r, nil, { Level = level, Vaults = 99 }) then
		table.insert(base.Items, { Uid = base.NextUid, Id = id, X = x, Z = z, R = r, Paid = 0, Cur = "Coins" })
		base.NextUid += 1
		return true
	end
	return false
end

-- first visit: starter layout. Older saves move into the new territories.
-- items outside the buildable land (layouts from older versions) move to a
-- free spot inside it, or are refunded if there is no room
local function rehome(data)
	local base = data.Base
	local level = houseLevel(data)
	local bounds = DecorModel.Bounds(Config, level)
	local opts = { Level = level, Vaults = 99 }
	local kept = {}
	local outside = {}
	for _, item in base.Items do
		local def = Config.Decor[item.Id]
		if def then
			local w, d = DecorModel.Footprint(Config, item.Id, item.R or 0)
			local inside = item.X - w / 2 >= bounds.MinX - 0.01
				and item.X + w / 2 <= bounds.MaxX + 0.01
				and item.Z - d / 2 >= bounds.MinZ - 0.01
				and item.Z + d / 2 <= bounds.MaxZ + 0.01
			table.insert(if inside then kept else outside, item)
		end
	end
	for _, item in outside do
		local placed = false
		local z = bounds.MaxZ - 2
		while not placed and z >= bounds.MinZ + 1 do
			local x = bounds.MinX + 2
			while not placed and x <= bounds.MaxX - 1 do
				local sx, sz = DecorModel.Snap(Config, item.Id, x, z, 0)
				if DecorModel.Validate(Config, kept, item.Id, sx, sz, 0, item.Uid, opts) then
					item.X, item.Z, item.R = sx, sz, 0
					table.insert(kept, item)
					placed = true
				end
				x += 2
			end
			z -= 2
		end
		if not placed then
			local refund = math.max(0, math.floor(item.Paid or 0))
			if item.Cur == "Gems" then
				data.Gems += refund
			else
				data.Coins += refund
			end
		end
	end
	base.Items = kept
end

local function seed(data)
	local base = data.Base
	if not base.Seeded then
		base.Seeded = true
		base.LayoutV = 3
		for _, entry in Config.StarterBase do
			addItem(base, entry.Id, entry.X, entry.Z, entry.R, 1)
		end
		-- pedestals bought before decorating existed are kept
		local extra = math.max(0, (base.Pedestals or 0) - SETTINGS.StartPedestals)
		for i = 1, extra do
			addItem(base, "Pedestal", -12 + ((i - 1) % 5) * 6, -6 - math.floor((i - 1) / 5) * 6, 0, 1)
		end
		return
	end
	if (base.LayoutV or 0) < 2 then
		-- saves from the 44x44 bases: their layout fits house level 2
		base.LayoutV = 2
		-- big enough for everything they already placed
		local level = math.max(houseLevel(data), 2)
		while level < #SETTINGS.Levels and SETTINGS.Levels[level].MaxItems <= #base.Items do
			level += 1
		end
		base.Level = level
		if DecorModel.Count(base.Items, "Vault") == 0 then
			for _, spot in { { 0, 14 }, { -10, 14 }, { 10, 14 }, { 0, -16 }, { -16, -16 }, { 16, -16 } } do
				if addItem(base, "Vault", spot[1], spot[2], 0, base.Level) then
					break
				end
			end
		end
	end
	if (base.LayoutV or 0) < 3 then
		-- v16: the house stands behind z = 22 now
		base.LayoutV = 3
		rehome(data)
	end
end

local function sendHome(player: Player)
	local home = Base:HomeCFrame(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if home and root and not Services.ShardService:IsCarrying(player) then
		character:PivotTo(home)
	end
end

local function assign(player: Player, data)
	if plotOf[player] then
		return
	end
	local plot = nil
	for _, candidate in plots do
		if not candidate.Owner and not candidate.Rival then
			plot = candidate
			break
		end
	end
	if not plot then
		-- a rival player lives here: they move out for a real player
		for _, candidate in plots do
			if not candidate.Owner and candidate.Rival and Services.RivalHomes then
				Services.RivalHomes:EvictFor(candidate)
				plot = candidate
				break
			end
		end
	end
	if not plot then
		if not table.find(waiting, player) then
			table.insert(waiting, player)
		end
		Net:Notify(player, "All bases are taken - you'll get one when someone leaves.")
		return
	end
	plot.Owner = player
	plotOf[player] = plot
	plot.Model:SetAttribute("OwnerId", player.UserId)
	plot.Avatar.Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(player.UserId) .. "&w=150&h=150"
	player:SetAttribute("BaseIndex", plot.Index)
	-- nobody can rob you the moment you arrive
	lockFor(plot, SETTINGS.JoinLockSeconds)

	-- offline earnings (lower rate, capped)
	local base = data.Base
	if base.LastOnline > 0 then
		local away = math.clamp(os.time() - base.LastOnline, 0, SETTINGS.OfflineMaxSeconds)
		local earned = math.floor(Base:IncomeRate(player, data) * away * SETTINGS.OfflineRate)
		if earned > 0 and away >= 60 then
			base.Bank += earned
			task.delay(6, function()
				if player.Parent then
					Net:Send(player, "OfflineEarnings", earned, away)
				end
			end)
		end
	end
	base.LastOnline = os.time()
	Base:Render(player)
	-- your custom house name (filtered again every session)
	if type(base.Name) == "string" and base.Name ~= "" then
		task.spawn(function()
			local filtered = filterName(player, base.Name)
			if filtered and plotOf[player] == plot then
				houseNames[player] = filtered
				Base:RefreshLabels(player, true)
			end
		end)
	end
	-- returning players start at home (like Adopt Me / Steal a Brainrot)
	if data.Tutorial.Done then
		task.delay(1.5, function()
			if plotOf[player] == plot and player.Parent then
				sendHome(player)
			end
		end)
	end
end

local function release(player: Player)
	local plot = plotOf[player]
	plotOf[player] = nil
	houseNames[player] = nil
	revenge[player] = nil
	thefts[player] = nil
	for victim, entry in revenge do
		if entry.Target == player then
			revenge[victim] = nil
			victim:SetAttribute("RevengeTarget", nil)
			victim:SetAttribute("RevengeUntil", nil)
		end
	end
	local index = table.find(waiting, player)
	if index then
		table.remove(waiting, index)
	end
	if not plot then
		return
	end
	clearPlot(plot)
	-- give the plot to someone who's waiting
	while #waiting > 0 do
		local nextPlayer = table.remove(waiting, 1)
		local data = nextPlayer.Parent and Data:Get(nextPlayer)
		if data then
			assign(nextPlayer, data)
			break
		end
	end
end

---------------------------------------------------------------------------
function Base:Init(services)
	Services = services
	Data = services.DataService
	World = services.WorldService
end

function Base:Start()
	for index, spot in Util.PlotLayout(Config) do
		local plot = buildPlot(index, spot.Center, spot.Facing)
		plots[index] = plot
		clearPlot(plot)
		plot.CollectPad.Touched:Connect(function(hit)
			local player = playerFromHit(hit)
			if player and plot.Owner == player and not debounced(player, "collect", 0.6) then
				Base:Collect(player)
			end
		end)
		plot.LockPad.Touched:Connect(function(hit)
			local player = playerFromHit(hit)
			if player and plot.Owner == player and not debounced(player, "lock", 0.6) then
				Base:Lock(player)
			end
		end)
		setPrompt(plot.ExpandBoard, "Expand", "House", "Owner", 0.4, function(player)
			if plot.Owner == player then
				local ok, message = Base:Upgrade(player)
				if not ok and message then
					Net:Notify(player, message, Color3.fromRGB(255, 120, 120))
				end
			end
		end, 12)
	end

	Data:OnLoaded(function(player, data)
		local base = data.Base
		-- forget likes older than yesterday (keeps the save small)
		local today = Util.DayNumber()
		for key, day in base.LikedBy do
			if type(day) ~= "number" or day < today - 1 then
				base.LikedBy[key] = nil
			end
		end
		seed(data)
		assign(player, data)
	end)
	Data:OnLeaving(function(_player, data)
		data.Base.LastOnline = os.time()
		for _, pet in data.Pets do
			pet.Away = nil
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		release(player)
		for key in touchDebounce do
			if string.sub(key, 1, #tostring(player.UserId) + 1) == player.UserId .. ":" then
				touchDebounce[key] = nil
			end
		end
	end)
	-- respawning puts you back home (only real players have characters that respawn)
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function()
			local data = Data:Get(player)
			if data and data.Tutorial.Done and plotOf[player] then
				task.wait(0.5)
				sendHome(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end

	-- 👑 the most liked house in the server wears a crown
	local function updateCrown()
		local best, bestLikes = nil, 0
		for owner, plot in plotOf do
			local data = Data:Get(owner)
			local likes = data and data.Base.Likes or 0
			if likes > bestLikes then
				best, bestLikes = plot, likes
			end
		end
		for _, plot in plots do
			local isBest = plot == best
			plot.Model:SetAttribute("BestHouse", isBest)
			for _, crownPart in plot.Crown:GetChildren() do
				if crownPart:IsA("BasePart") then
					crownPart.Transparency = if isBest then 0 else 1
				end
			end
		end
	end

	-- someone walks onto your land: you get a heads-up (once a minute per visitor)
	local visiting = {} -- [visitor] = plot index they're standing in
	local visitNotified = {} -- ["visitor:owner"] = os.clock()
	local function checkVisitors()
		for _, visitor in Players:GetPlayers() do
			local root = visitor.Character and visitor.Character:FindFirstChild("HumanoidRootPart")
			local inside = nil
			if root and root:IsA("BasePart") then
				for _, plot in plots do
					local owner = plot.Owner
					if owner and owner ~= visitor then
						local p = plot.CFrame:PointToObjectSpace(root.Position)
						if math.abs(p.X) <= PLOT_HALF and math.abs(p.Z) <= PLOT_HALF then
							inside = plot
						end
					end
				end
			end
			local index = inside and inside.Index or nil
			if index ~= visiting[visitor] then
				visiting[visitor] = index
				if inside and inside.Owner then
					local key = visitor.UserId .. ":" .. inside.Owner.UserId
					if os.clock() - (visitNotified[key] or -999) > 60 then
						visitNotified[key] = os.clock()
						Net:Notify(inside.Owner, "👀 %s walked onto your land!", Color3.fromRGB(150, 220, 255), visitor.DisplayName)
					end
				end
			end
		end
		for visitor in visiting do
			if not visitor.Parent then
				visiting[visitor] = nil
			end
		end
	end

	-- income tick
	task.spawn(function()
		local ticks = 0
		while true do
			task.wait(1)
			ticks += 1
			pcall(checkVisitors)
			if ticks % 5 == 0 then
				pcall(updateCrown)
			end
			for player, plot in plotOf do
				local data = Data:Get(player)
				if data and player.Parent then
					data.Base.Bank += self:IncomeRate(player, data)
					data.Base.LastOnline = os.time()
					if plot.LockedUntil > 0 and plot.LockedUntil <= now() then
						plot.LockedUntil = 0
						plot.Model:SetAttribute("LockedUntil", 0)
					end
					local entry = revenge[player]
					if entry and entry.Until <= now() then
						revenge[player] = nil
						-- (a newer revenge on a rival keeps its attributes)
						if player:GetAttribute("RevengeTarget") == entry.Target.UserId then
							player:SetAttribute("RevengeTarget", nil)
							player:SetAttribute("RevengeUntil", nil)
						end
					end
					local ok, err = pcall(self.RefreshLabels, self, player)
					if not ok then
						warn("[Base] label refresh failed: " .. tostring(err))
					end
				end
			end
		end
	end)

	Net:On("GoBase", 1, function(player)
		if Services.ShardService:IsCarrying(player) then
			Net:Notify(player, "Run! You can't teleport while carrying a shard.")
			return
		end
		sendHome(player)
	end)

	-- visit someone's house (you arrive outside their gate)
	Net:On("VisitBase", 1, function(player, userId)
		local target = type(userId) == "number" and Players:GetPlayerByUserId(userId)
		if not target and type(userId) == "number" and userId < 0 then
			-- a rival's house
			for _, plot in plots do
				if plot.Rival and plot.Model:GetAttribute("OwnerId") == userId then
					local character = player.Character
					if character and not Services.ShardService:IsCarrying(player) then
						character:PivotTo(plot.CFrame * CFrame.new(0, 3, -PLOT_HALF - 6) * CFrame.Angles(0, math.pi, 0))
					end
				end
			end
			return
		end
		if not target or target == player then
			return
		end
		if Services.ShardService:IsCarrying(player) then
			Net:Notify(player, "Run! You can't teleport while carrying a shard.")
			return
		end
		local gate = self:GateCFrame(target)
		local character = player.Character
		if gate and character and character:FindFirstChild("HumanoidRootPart") then
			character:PivotTo(gate)
			Net:Notify(
				player,
				"🏘️ Welcome to %s's house! Tap ❤️ if you like it.",
				Color3.fromRGB(255, 160, 200),
				target.DisplayName
			)
		end
	end)

	-- build mode requests answer with ok, translated message
	local function reply(player: Player, ok: boolean, message: string?)
		return ok, if message then Net:L(player, message) else nil
	end
	Net:OnRequest("BasePlace", 0.15, function(player, id, x, z, r)
		return reply(player, self:Place(player, id, x, z, r))
	end)
	Net:OnRequest("BaseMove", 0.15, function(player, uid, x, z, r)
		return reply(player, self:Move(player, uid, x, z, r))
	end)
	Net:OnRequest("BaseRemove", 0.15, function(player, uid)
		return reply(player, self:Remove(player, uid))
	end)
	Net:OnRequest("BasePaint", 0.1, function(player, uid, color)
		return reply(player, self:Paint(player, uid, color))
	end)
	Net:OnRequest("BaseArrange", 1, function(player)
		return reply(player, self:ArrangePedestals(player))
	end)
	Net:OnRequest("HouseRoof", 0.5, function(player, color)
		return reply(player, self:SetRoof(player, color))
	end)
	Net:OnRequest("HouseUpgrade", 0.5, function(player)
		return reply(player, self:Upgrade(player))
	end)
	Net:OnRequest("HouseName", 5, function(player, text)
		return reply(player, self:SetName(player, text))
	end)
	Net:OnRequest("HouseSkin", 0.5, function(player, id)
		return reply(player, self:SetSkin(player, id))
	end)
	-- choose which pets may go into the vault ("show off" keeps a pet on display)
	Net:On("PetShow", 0.15, function(player, petId, show)
		local data = Data:Get(player)
		local pet = data and type(petId) == "number" and Services.PetService.FindPet(data, petId)
		if not pet then
			return
		end
		pet.Show = if show == true then true else nil
		Services.PetService:Changed(player)
	end)
end

return Base
