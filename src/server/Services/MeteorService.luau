--[[
	MeteorService: ☄️ METEOR RUSH - the heart of the game (docs/METEOR_RUSH.md).

	Every ~3 minutes:
	  1) WARNING (20s): a landing marker (red ring + light pillar + countdown)
	     appears at a random site - the hub, the base avenue or a mine zone.
	     "GO" (only now) teleports you to that area's entrance.
	  2) FALLING: the meteor crashes in (camera shake).
	  3) ACTIVE: everyone smashes it; score per hit = 1 + log10(damage), the
	     HP grows with every new participant so a crack takes ~30-40s.
	  4) BURST: star eggs of the meteor's kind (the top 3 get a head start,
	     the best eggs get a guardian), coin chunks, sometimes a lucky block.
	  Then the race home: carriers can be bonked and drop their egg.

	Meteor kind = a zone's eggs (🌿 Meadow ... 🌌 Cosmic); size Small / Big /
	Giant; 8% are ✨ GOLDEN (2x egg luck, 3x coin chunks). Cracking a kind for
	the first time fills the meteor index (+💎).

	New players get a small TUTORIAL meteor of their own next to the spawn.
]]
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Net = require(script.Parent.Net)

local Meteor = {}
local Services
local Data
local World

local settings = Config.Meteor
local rng = Random.new()
local state = "Idle" -- Idle | Warning | Falling | Active | Ending
local nextAt = os.time() + (settings.FirstSeconds or settings.IntervalSeconds)
local warnEnd = 0
local endsAt = 0
local hp, maxHp = 0, 0
local scores = {} -- [player] = score
local meteorPart: BasePart? = nil
local marker: Model? = nil
local summoner: Player? = nil
local summonQueue = {}
local special = nil -- forced size / golden for the next meteor (party "mega meteor")
local current = nil -- the meteor of this round (site, kind, size, golden)
local tutorialMeteors = {} -- [player] = { Part, Hits, Label }
local chunks = {} -- [part] = { Golden = bool }

local SITE_NAMES = { Hub = "Hub", Avenue = "Base Avenue" }

local function setAttributes()
	workspace:SetAttribute("MeteorState", state)
	workspace:SetAttribute("MeteorNext", nextAt)
	workspace:SetAttribute("MeteorWarnEnd", warnEnd)
	workspace:SetAttribute("MeteorEnd", endsAt)
	workspace:SetAttribute("MeteorHP", hp)
	workspace:SetAttribute("MeteorMaxHP", maxHp)
	workspace:SetAttribute("MeteorKind", if current then settings.Kinds[current.Kind].Name else "")
	workspace:SetAttribute("MeteorIcon", if current then settings.Kinds[current.Kind].Icon else "")
	workspace:SetAttribute("MeteorSize", if current then current.Size.Name else "")
	workspace:SetAttribute("MeteorGolden", current ~= nil and current.Golden)
	workspace:SetAttribute("MeteorSite", if current then current.SiteName else "")
	workspace:SetAttribute("MeteorSiteZone", if current then current.SiteZone else 0)
	workspace:SetAttribute("MeteorPos", if current then current.Position else Vector3.zero)
	workspace:SetAttribute("MeteorRadius", if current then current.Size.Radius else settings.Radius)
end

function Meteor:IsActive(): boolean
	return state == "Active"
end

function Meteor:Current()
	return current
end

function Meteor:InRange(position: Vector3): boolean
	if not meteorPart or not current then
		return false
	end
	return (position - meteorPart.Position).Magnitude <= current.Size.Radius + Config.World.Reach + 2
end

local function ranking()
	local list = {}
	for player, score in scores do
		if player.Parent then
			table.insert(list, { Player = player, Score = score })
		end
	end
	table.sort(list, function(a, b)
		return a.Score > b.Score
	end)
	return list
end

local function maxZoneInServer(): number
	local best = 1
	for _, player in Data:LoadedPlayers() do
		local data = Data:Get(player)
		if data then
			best = math.max(best, data.ZoneLevel)
		end
	end
	return math.clamp(best, 1, math.min(#Config.Zones, #settings.Kinds))
end

local function weighted(list)
	local entries = {}
	for index, entry in list do
		table.insert(entries, { index, entry.Weight })
	end
	return list[Util.WeightedPick(entries, nil, rng)]
end

-- where (and what) the next meteor is
function Meteor:PickSite(forceType: string?, forceZone: number?)
	local maxZone = maxZoneInServer()
	local siteType = forceType or weighted(settings.Sites).Kind
	local position, siteName, siteZone, lootZone
	if siteType == "Zone" and World.Zones[1] then
		siteZone = if forceZone and World.Zones[forceZone] then forceZone else rng:NextInteger(1, maxZone)
		local info = World.Zones[siteZone]
		position = Vector3.new(rng:NextNumber(-30, 30), 0, rng:NextNumber(info.ZStart + 22, info.ZEnd - 16))
		siteName = Config.Zones[siteZone].Name
		lootZone = siteZone
	elseif siteType == "Avenue" then
		local xs = settings.AvenueX
		position = Vector3.new(xs[rng:NextInteger(1, #xs)], 0, Util.AvenueZ(Config))
		siteName = SITE_NAMES.Avenue
		siteZone = 0
		lootZone = rng:NextInteger(1, maxZone)
	else
		siteType = "Hub"
		local spots = settings.HubSpots
		position = spots[rng:NextInteger(1, #spots)]
		siteName = SITE_NAMES.Hub
		siteZone = 0
		lootZone = rng:NextInteger(1, maxZone)
	end
	local size = weighted(settings.Sizes)
	return {
		Type = siteType,
		SiteName = siteName,
		SiteZone = siteZone,
		Position = position,
		Kind = lootZone,
		Size = size,
		Golden = rng:NextNumber() < settings.GoldenChance,
	}
end

---------------------------------------------------------------------------
-- models
---------------------------------------------------------------------------
local function buildMeteor(radius: number, color: Color3, golden: boolean): BasePart
	local part = Instance.new("Part")
	part.Name = "Meteor"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * radius * 2
	part.Material = if golden then Enum.Material.Foil else Enum.Material.Basalt
	part.Color = if golden then Color3.fromRGB(255, 200, 60) else Color3.fromRGB(70, 50, 45)
	part.Anchored = true
	part.CanCollide = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part:SetAttribute("Radius", radius)

	-- ☄️ a rough space rock: boulders on the surface, glowing lava veins and
	-- molten patches, all welded to the round core (that's the hit target)
	local veinColor = if golden then Color3.fromRGB(255, 225, 110) else color:Lerp(Color3.fromRGB(255, 150, 40), 0.55)
	local function stuck(name: string, size: Vector3, cf: CFrame, partColor: Color3, material: Enum.Material, shape)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Color = partColor
		p.Material = material
		p.Anchored = false
		p.Massless = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		if shape then
			p.Shape = shape
		end
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = part
		weld.Part1 = p
		weld.Parent = p
		p.Parent = part
		return p
	end
	local rockRng = Random.new()
	local origin = part.CFrame
	for i = 1, 14 do
		-- spread directions over the sphere (golden angle spiral)
		local y = 1 - (i - 0.5) / 14 * 2
		local ring = math.sqrt(1 - y * y)
		local theta = i * 2.39996
		local direction = Vector3.new(math.cos(theta) * ring, y, math.sin(theta) * ring)
		local size = radius * rockRng:NextNumber(0.45, 0.8)
		stuck(
			"Shell",
			Vector3.new(size, size * rockRng:NextNumber(0.6, 0.9), size * rockRng:NextNumber(0.8, 1.1)),
			CFrame.new(origin.Position + direction * radius * 0.78)
				* CFrame.Angles(rockRng:NextNumber(0, 6.2), rockRng:NextNumber(0, 6.2), rockRng:NextNumber(0, 6.2)),
			if golden
				then Color3.fromRGB(230, 180, 60):Lerp(Color3.new(0, 0, 0), rockRng:NextNumber(0, 0.25))
				else Color3.fromRGB(62, 48, 44):Lerp(Color3.fromRGB(20, 16, 16), rockRng:NextNumber(0, 0.6)),
			if golden then Enum.Material.Foil elseif i % 3 == 0 then Enum.Material.Slate else Enum.Material.Basalt
		)
	end
	for i = 1, 8 do
		-- glowing cracks running over the surface
		local direction = Vector3.new(rockRng:NextNumber(-1, 1), rockRng:NextNumber(-1, 1), rockRng:NextNumber(-1, 1)).Unit
		stuck(
			"Vein",
			Vector3.new(0.35, radius * rockRng:NextNumber(0.7, 1.2), 0.35),
			CFrame.lookAt(origin.Position + direction * radius * 0.98, origin.Position + direction * radius * 2)
				* CFrame.Angles(math.rad(90), 0, rockRng:NextNumber(0, 6.2)),
			veinColor,
			Enum.Material.Neon
		)
		if i <= 4 then
			stuck(
				"Molten",
				Vector3.one * radius * rockRng:NextNumber(0.35, 0.55),
				CFrame.new(origin.Position + direction * radius * 0.82),
				veinColor,
				Enum.Material.CrackedLava,
				Enum.PartType.Ball
			)
		end
	end
	local core = stuck("Core", part.Size * 0.6, origin, veinColor, Enum.Material.Neon, Enum.PartType.Ball)
	core.Transparency = 0.5
	-- smoke + embers + a fiery tail while it falls
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "Smoke"
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(90, 80, 80), Color3.fromRGB(40, 36, 36))
	smoke.Size = NumberSequence.new(radius * 0.6, radius * 1.6)
	smoke.Transparency = NumberSequence.new(0.35, 1)
	smoke.Lifetime = NumberRange.new(1.5, 2.5)
	smoke.Rate = 12
	smoke.Speed = NumberRange.new(1, 3)
	smoke.SpreadAngle = Vector2.new(40, 40)
	smoke.Parent = part
	local embers = Instance.new("ParticleEmitter")
	embers.Name = "Embers"
	embers.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	embers.Color = ColorSequence.new(veinColor)
	embers.LightEmission = 1
	embers.Size = NumberSequence.new(0.5, 0)
	embers.Lifetime = NumberRange.new(0.8, 1.6)
	embers.Rate = 25
	embers.Speed = NumberRange.new(3, 8)
	embers.SpreadAngle = Vector2.new(180, 180)
	embers.Acceleration = Vector3.new(0, 6, 0)
	embers.Parent = part
	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, radius * 0.6, 0)
	top.Parent = part
	local bottom = Instance.new("Attachment")
	bottom.Position = Vector3.new(0, -radius * 0.6, 0)
	bottom.Parent = part
	local trail = Instance.new("Trail")
	trail.Name = "Tail"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Color = ColorSequence.new(veinColor, Color3.fromRGB(255, 90, 40))
	trail.LightEmission = 0.8
	trail.Lifetime = 0.9
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.WidthScale = NumberSequence.new(1, 0.2)
	trail.FaceCamera = true
	trail.Parent = part

	local light = Instance.new("PointLight")
	light.Color = veinColor
	light.Range = 40
	light.Brightness = 2.5
	light.Parent = part

	local fire = Instance.new("Fire")
	fire.Size = radius * 1.6
	fire.Heat = 12
	fire.Color = color
	fire.SecondaryColor = Color3.fromRGB(255, 220, 80)
	fire.Parent = part

	local gui = Instance.new("BillboardGui")
	gui.Name = "HPBar"
	gui.Size = UDim2.new(18, 0, 2, 0)
	gui.StudsOffsetWorldSpace = Vector3.new(0, radius + 5, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 250
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(30, 20, 20)
	back.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = back
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = core.Color
	fill.BorderSizePixel = 0
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.5, 0)
	fillCorner.Parent = fill
	fill.Parent = back
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.Text = "☄️ METEOR"
	text.ZIndex = 2
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = text
	text.Parent = back
	back.Parent = gui
	gui.Parent = part
	return part
end

-- the landing marker everybody runs to: red ring, light pillar, countdown
local function buildMarker(site): Model
	local model = Instance.new("Model")
	model.Name = "MeteorMarker"
	local color = if site.Golden then Color3.fromRGB(255, 210, 70) else settings.Kinds[site.Kind].Color
	local diameter = site.Size.Radius * 2 + 8
	local ring = Instance.new("Part")
	ring.Name = "Ring"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 70, 60)
	ring.Transparency = 0.35
	ring.Size = Vector3.new(0.3, diameter, diameter)
	ring.CFrame = CFrame.new(site.Position + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = model
	local pillar = Instance.new("Part")
	pillar.Name = "Pillar"
	pillar.Shape = Enum.PartType.Cylinder
	pillar.Anchored = true
	pillar.CanCollide = false
	pillar.CanQuery = false
	pillar.CanTouch = false
	pillar.Material = Enum.Material.Neon
	pillar.Color = color
	pillar.Transparency = 0.55
	pillar.Size = Vector3.new(220, 3, 3)
	pillar.CFrame = CFrame.new(site.Position + Vector3.new(0, 110, 0)) * CFrame.Angles(0, 0, math.rad(90))
	pillar.Parent = model
	local gui = Instance.new("BillboardGui")
	gui.Name = "Countdown"
	gui.Size = UDim2.fromOffset(230, 56)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 12, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 1500
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = ring
	model.PrimaryPart = ring
	model.Parent = World:Folder("Drops")
	return model
end

local function updateMarker()
	local gui = marker and marker.PrimaryPart and marker.PrimaryPart:FindFirstChild("Countdown")
	local label = gui and gui:FindFirstChild("Text")
	if label and current then
		local kind = settings.Kinds[current.Kind]
		World.SetText(label, "☄️ %s %s  %ds", kind.Icon, kind.Name, math.max(0, warnEnd - os.time()))
	end
end

local function updateBar()
	if not meteorPart then
		return
	end
	local gui = meteorPart:FindFirstChild("HPBar")
	local back = gui and gui:FindFirstChildOfClass("Frame")
	if back then
		local ratio = if maxHp > 0 then math.clamp(hp / maxHp, 0, 1) else 0
		(back :: any).Fill.Size = UDim2.fromScale(ratio, 1)
		World.SetText((back :: any).Text, "☄️ METEOR  %s%%", math.ceil(ratio * 100))
	end
end

local function shatter(position: Vector3, color: Color3?)
	local folder = World:Folder("Drops")
	for _ = 1, 14 do
		local chunk = Instance.new("Part")
		chunk.Name = "MeteorChunk"
		chunk.Size = Vector3.one * math.random(15, 35) / 10
		chunk.Material = Enum.Material.Basalt
		chunk.Color = color or Color3.fromRGB(80, 55, 45)
		chunk.CanCollide = false
		chunk.CanQuery = false
		chunk.Position = position + Vector3.new(math.random(-4, 4), math.random(0, 4), math.random(-4, 4))
		chunk.AssemblyLinearVelocity = Vector3.new(math.random(-40, 40), math.random(40, 80), math.random(-40, 40))
		chunk.Parent = folder
		Debris:AddItem(chunk, 3)
	end
	local explosion = Instance.new("Explosion")
	explosion.Position = position
	explosion.BlastPressure = 0
	explosion.BlastRadius = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.Parent = workspace
end

---------------------------------------------------------------------------
-- coin chunks: walk over them for instant coins (scaled to your base)
---------------------------------------------------------------------------
function Meteor:ClaimChunk(player: Player, part: BasePart): number?
	local info = chunks[part]
	local data = Data:Get(player)
	if not info or not data then
		return nil
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") or (root.Position - part.Position).Magnitude > 14 then
		return nil -- (touches are reported by clients: you must really be there)
	end
	chunks[part] = nil
	part:Destroy()
	local cfg = settings.Chunks
	local rate = Services.BaseService:IncomeRate(player, data)
	local amount = math.max(cfg.Min, math.floor(rate * cfg.Seconds))
	if info.Golden then
		amount *= cfg.GoldenMult
	end
	data.Coins += amount
	data.Stats.LifetimeCoins += amount
	Services.Analytics:Economy(player, "Source", "Coins", amount, data.Coins, "Gameplay", "MeteorChunk")
	Net:Send(player, "Sold", amount)
	Data:MarkDirty(player)
	return amount
end

local function spawnChunks(position: Vector3, count: number, golden: boolean, narrow: boolean?)
	local folder = World:Folder("Drops")
	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local radius = rng:NextNumber(5, 13)
		local squash = if narrow then 0.6 else 1
		local part = Instance.new("Part")
		part.Name = "CoinChunk"
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.one * 1.6
		part.Material = Enum.Material.Neon
		part.Color = if golden then Color3.fromRGB(255, 235, 120) else Color3.fromRGB(255, 200, 60)
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = true
		part.CFrame = CFrame.new(position.X + math.cos(angle) * radius, 1, position.Z + math.sin(angle) * radius * squash)
		local sparkle = Instance.new("Sparkles")
		sparkle.SparkleColor = part.Color
		sparkle.Parent = part
		part.Parent = folder
		chunks[part] = { Golden = golden }
		part.Touched:Connect(function(hit)
			local character = hit:FindFirstAncestorOfClass("Model")
			local player = character and Players:GetPlayerFromCharacter(character)
			if player then
				Meteor:ClaimChunk(player, part)
			end
		end)
		task.delay(settings.Chunks.Lifetime, function()
			if chunks[part] then
				chunks[part] = nil
				part:Destroy()
			end
		end)
	end
end
Meteor.SpawnChunks = spawnChunks

function Meteor:ChunksForTest()
	assert(not RunService:IsRunning(), "test hook used on a live server")
	return chunks
end

---------------------------------------------------------------------------
-- the round
---------------------------------------------------------------------------
local function finish(destroyed: boolean)
	if state ~= "Active" then
		return
	end
	state = "Ending"
	local list = ranking()
	local total = 0 -- (real players only: 🤖 robots don't shrink anyone's share)
	for _, entry in list do
		if not entry.Player.IsRival then
			total += entry.Score
		end
	end
	local mult = if destroyed then 1 else settings.FailedMultiplier
	local progression = Services.ProgressionService
	local topNames = {}
	local kind = current and settings.Kinds[current.Kind]

	for place, entry in list do
		local player = entry.Player
		local data = if player.IsRival then nil else Data:Get(player)
		if player.IsRival and settings.PlaceRewards[place] then
			table.insert(topNames, player.DisplayName) -- 🤖 robots can win places too
		end
		if data then
			local share = if total > 0 then entry.Score / total else 0
			local stardust = settings.ParticipationStardust + math.floor(share * settings.ShareStardust)
			local gems = 0
			local points = settings.ParticipationPoints
			local placeReward = settings.PlaceRewards[place]
			if placeReward then
				stardust += placeReward.Stardust
				gems += placeReward.Gems
				points = placeReward.Points
				table.insert(topNames, player.DisplayName)
			end
			stardust = math.floor(stardust * mult)
			gems = math.floor(gems * mult)
			if player == summoner then
				stardust *= 2
			end
			-- ☄️ meteor index: first crack of a kind pays extra
			local firstCrack = false
			if destroyed and current then
				local key = tostring(current.Kind)
				firstCrack = (data.MeteorIndex[key] or 0) == 0
				data.MeteorIndex[key] = (data.MeteorIndex[key] or 0) + 1
				if firstCrack then
					gems += settings.FirstCrackGems
				end
			end
			data.Stardust += stardust
			data.Gems += gems
			data.Stats.MeteorJoins += 1
			if destroyed then
				-- 🌱 the pets that helped grow
				pcall(Services.PetService.AddFollowXP, Services.PetService, player, Config.Growth.MeteorXP)
			end
			if place == 1 and destroyed then
				data.Stats.MeteorWins += 1
			end
			progression:AddQuest(player, "MeteorJoin", 1)
			if place <= 3 then
				progression:AddQuest(player, "MeteorTop3", 1)
			end
			progression:AddPoints(player, points)
			progression:AddSeasonXP(player, settings.PassXP)
			Net:Send(player, "MeteorResult", {
				Place = place,
				Total = #list,
				Stardust = stardust,
				Gems = gems,
				Points = points,
				Destroyed = destroyed,
				Kind = kind and kind.Name,
				Icon = kind and kind.Icon,
				FirstCrack = firstCrack,
			})
			Data:MarkDirty(player)
		end
	end

	local medals = { "🥇", "🥈", "🥉" }
	local parts = {}
	for i, name in topNames do
		table.insert(parts, medals[i] .. " " .. name)
	end
	local headline = if destroyed then "☄️ Meteor smashed! Grab the star eggs! %s" else "☄️ The meteor escaped! %s"
	Net:Announce(headline, Color3.fromRGB(255, 170, 80), table.concat(parts, "  "))

	local ground = if current then current.Position else settings.Position
	if meteorPart then
		local position = meteorPart.Position
		meteorPart:Destroy()
		meteorPart = nil
		shatter(position, kind and kind.Color)
	end
	if destroyed and current then
		local spill = settings.Spill
		-- the big payoff: star eggs to race for, coin chunks, maybe a lucky block
		local ok, err = pcall(function()
			Services.ShardService:SpillMeteor(Vector3.new(ground.X, 0, ground.Z), list, {
				Egg = kind.Egg,
				Kind = current.Kind,
				Golden = current.Golden,
				Luck = spill.Luck * (if current.Golden then spill.GoldenLuck else 1),
				Extra = current.Size.Eggs,
				Narrow = current.Type == "Avenue",
			})
		end)
		if not ok then
			warn("[Meteor] egg spill failed: " .. tostring(err))
		end
		local narrow = current.Type == "Avenue"
		spawnChunks(Vector3.new(ground.X, 0, ground.Z), settings.Chunks.Count, current.Golden, narrow)
		if rng:NextNumber() < spill.LuckyChance and Services.LuckyService then
			local offset = if narrow then Vector3.new(16, 0, 0) else Vector3.new(rng:NextNumber(-8, 8), 0, 14)
			pcall(Services.LuckyService.Spawn, Services.LuckyService, Vector3.new(ground.X, 0, ground.Z) + offset)
		end
		workspace:SetAttribute("MeteorLootUntil", os.time() + 25)
	end
	scores = {}
	summoner = nil
	hp, maxHp = 0, 0
	current = nil
	state = "Idle"
	nextAt = os.time() + settings.IntervalSeconds
	setAttributes()
	Net:Broadcast("MeteorRank", {})
end

-- back to a clean idle state so a failure never stops future events
local function resetToIdle()
	if meteorPart then
		meteorPart:Destroy()
		meteorPart = nil
	end
	if marker then
		marker:Destroy()
		marker = nil
	end
	scores = {}
	summoner = nil
	hp, maxHp = 0, 0
	current = nil
	state = "Idle"
	nextAt = os.time() + settings.IntervalSeconds
	setAttributes()
	Net:Broadcast("MeteorRank", {})
end

local function safeFinish(destroyed: boolean)
	local ok, err = pcall(finish, destroyed)
	if not ok then
		warn("[Meteor] finish failed: " .. tostring(err))
		resetToIdle()
	end
end

-- cooldown is the attacker's swing cooldown, used to size the meteor so the
-- event lasts about SecondsPerParticipant no matter how strong players are
function Meteor:Hit(player: Player, damage: number, cooldown: number?)
	if state ~= "Active" or not current then
		return
	end
	local score = 1 + math.log10(math.max(1, damage))
	if not scores[player] then
		-- each new participant makes the meteor tougher by ~N seconds of their own hitting
		local extra = settings.SecondsPerParticipant * current.Size.HP * score / math.max(0.2, cooldown or 0.5)
		maxHp += extra
		hp += extra
		workspace:SetAttribute("MeteorMaxHP", maxHp)
	end
	scores[player] = (scores[player] or 0) + score
	hp = math.max(0, hp - score)
	workspace:SetAttribute("MeteorHP", hp)
	updateBar()
	Net:Send(player, "MeteorHit", score)
	if hp <= 0 then
		safeFinish(true)
	end
end

-- a rival robot left: drop its score
function Meteor:Forget(entity)
	scores[entity] = nil
end

function Meteor:ScoreOf(who): number
	return scores[who] or 0
end

-- 🐾 following pets add score for a player who is already smashing
function Meteor:PetHit(player: Player, pets: number, damage: number): boolean
	if state ~= "Active" or not scores[player] or pets <= 0 then
		return false
	end
	local score = pets * Config.PetHelp.MeteorShare * (1 + math.log10(math.max(1, damage)))
	scores[player] += score
	hp = math.max(0, hp - score)
	workspace:SetAttribute("MeteorHP", hp)
	updateBar()
	if hp <= 0 then
		safeFinish(true)
	end
	return true
end

function Meteor:Position(): Vector3?
	return if meteorPart then meteorPart.Position else nil
end

function Meteor:Summon(player: Player)
	table.insert(summonQueue, player)
	if state == "Idle" then
		Net:Notify(player, "☄️ Your meteor is on its way!", Color3.fromRGB(255, 170, 80))
	else
		Net:Notify(player, "☄️ Your meteor will fall right after the current one!", Color3.fromRGB(255, 170, 80))
	end
end

-- the party's MEGA meteor: the next one is giant + golden, and comes soon
function Meteor:QueueSpecial(sizeId: string, golden: boolean)
	special = { Size = sizeId, Golden = golden }
	if state == "Idle" then
		nextAt = math.min(nextAt, os.time() + 10)
		setAttributes()
	end
end

local function startWarning(forced)
	local summoned = table.remove(summonQueue, 1)
	if summoned and not summoned.Parent then
		summoned = nil
	end
	summoner = summoned
	if summoned and not forced then
		-- a summoned meteor lands where its summoner is (hub / avenue / their mine)
		local character = summoned.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local position = if root and root:IsA("BasePart") then root.Position else nil
		local zone = position and Util.ZoneAt(Config, position)
		if zone and zone > 0 then
			forced = Meteor:PickSite("Zone", zone)
		elseif position and Util.InBases(Config, position) then
			forced = Meteor:PickSite("Avenue")
		else
			forced = Meteor:PickSite("Hub")
		end
	end
	current = forced or Meteor:PickSite()
	if special then
		for _, size in settings.Sizes do
			if size.Id == special.Size then
				current.Size = size
			end
		end
		current.Golden = current.Golden or special.Golden
		special = nil
	end
	state = "Warning"
	warnEnd = os.time() + (if summoned then settings.SummonWarningSeconds else settings.WarningSeconds)
	if marker then
		marker:Destroy()
	end
	marker = buildMarker(current)
	updateMarker()
	setAttributes()
	local kind = settings.Kinds[current.Kind]
	local seconds = warnEnd - os.time()
	if summoned then
		Net:Announce(
			"☄️ %s SUMMONED A METEOR! It lands on %s! (%ds)",
			Color3.fromRGB(255, 150, 60),
			summoned.DisplayName,
			current.SiteName,
			seconds
		)
	elseif current.Golden then
		Net:Announce("✨ A GOLDEN %s is falling on %s! (%ds)", Color3.fromRGB(255, 215, 80), kind.Name, current.SiteName, seconds)
	else
		Net:Announce("☄️ A %s %s is falling on %s! (%ds)", kind.Color, current.Size.Name, kind.Name, current.SiteName, seconds)
	end
end

local function startFalling()
	state = "Falling"
	setAttributes()
	local kind = settings.Kinds[current.Kind]
	local radius = current.Size.Radius
	local final = current.Position + Vector3.new(0, radius * 0.6, 0)
	local part = buildMeteor(radius, kind.Color, current.Golden)
	part:PivotTo(CFrame.new(final + Vector3.new(60, 320, 40)))
	part.Parent = World:Folder("Drops")
	meteorPart = part
	local info = TweenInfo.new(2.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	-- (tweening the anchored core's CFrame carries the welded rock with it)
	TweenService:Create(part, info, { CFrame = CFrame.new(final) * CFrame.Angles(1.2, 0.8, 0.4) }):Play()
	task.wait(2.25)
	-- calmer once it has landed: less smoke, no tail
	local tail = part:FindFirstChild("Tail")
	if tail then
		tail.Enabled = false
	end
	local smokeAfter = part:FindFirstChild("Smoke")
	if smokeAfter and smokeAfter:IsA("ParticleEmitter") then
		smokeAfter.Rate = 4
	end
	-- a scorched crater with rubble around the impact
	local crater = Instance.new("Model")
	crater.Name = "Crater"
	local scorch = Instance.new("Part")
	scorch.Name = "Scorch"
	scorch.Shape = Enum.PartType.Cylinder
	scorch.Anchored = true
	scorch.CanCollide = false
	scorch.CanQuery = false
	scorch.CanTouch = false
	scorch.Size = Vector3.new(0.2, radius * 3.2, radius * 3.2)
	scorch.CFrame = CFrame.new(current.Position + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90))
	scorch.Color = Color3.fromRGB(35, 28, 26)
	scorch.Material = Enum.Material.Basalt
	scorch.Parent = crater
	local rubbleRng = Random.new()
	for i = 1, 12 do
		local angle = i / 12 * math.pi * 2 + rubbleRng:NextNumber(-0.2, 0.2)
		local size = rubbleRng:NextNumber(1.2, 2.6)
		local rubble = Instance.new("Part")
		rubble.Name = "Rubble"
		rubble.Anchored = true
		rubble.CanCollide = false
		rubble.CanQuery = false
		rubble.CanTouch = false
		rubble.Size = Vector3.new(size, size * 0.7, size)
		rubble.CFrame = CFrame.new(
			current.Position
				+ Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius * rubbleRng:NextNumber(1.25, 1.55)
				+ Vector3.new(0, size * 0.25, 0)
		) * CFrame.Angles(rubbleRng:NextNumber(0, 3), rubbleRng:NextNumber(0, 3), rubbleRng:NextNumber(0, 3))
		rubble.Color = Color3.fromRGB(70, 58, 52)
		rubble.Material = Enum.Material.Basalt
		rubble.Parent = crater
	end
	crater.Parent = World:Folder("Drops")
	Debris:AddItem(crater, settings.DurationSeconds + 40)
	if marker then
		marker:Destroy()
		marker = nil
	end
	local explosion = Instance.new("Explosion")
	explosion.Position = final
	explosion.BlastPressure = 0
	explosion.BlastRadius = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.Parent = workspace
	Net:Broadcast("MeteorImpact", final)

	maxHp = settings.BaseHP * current.Size.HP
	hp = maxHp
	scores = {}
	endsAt = os.time() + settings.DurationSeconds
	state = "Active"
	setAttributes()
	updateBar()
end

---------------------------------------------------------------------------
-- tutorial: a small meteor just for one player, next to the spawn
---------------------------------------------------------------------------
function Meteor:TutorialMeteor(player: Player)
	if tutorialMeteors[player] then
		return
	end
	local cfg = settings.Tutorial
	local position = cfg.Position + Vector3.new(rng:NextNumber(-5, 5), 0, rng:NextNumber(-4, 4))
	local entry = { Hits = 0 }
	tutorialMeteors[player] = entry
	Net:Send(player, "StarFall", position, "Epic", 1.4)
	task.delay(1.4, function()
		if tutorialMeteors[player] ~= entry or not player.Parent then
			return
		end
		local kind = settings.Kinds[1]
		local part = buildMeteor(cfg.Radius, kind.Color, false)
		part.Name = "TutorialMeteor_" .. tostring(player.UserId)
		part:SetAttribute("OwnerId", player.UserId)
		part:PivotTo(CFrame.new(position + Vector3.new(0, cfg.Radius * 0.6, 0)))
		local tail = part:FindFirstChild("Tail")
		if tail then
			tail.Enabled = false
		end
		part.Parent = World:Folder("Drops")
		entry.Part = part
		local gui = part:FindFirstChild("HPBar")
		local back = gui and gui:FindFirstChildOfClass("Frame")
		entry.Back = back
		if back then
			World.SetText((back :: any).Text, "☄️ %d", cfg.Hits)
		end
		Net:Send(player, "MeteorImpact", part.Position)
		Net:Notify(player, "☄️ A meteor fell just for you! Smash it!", Color3.fromRGB(255, 170, 80))
	end)
end

-- returns true when the swing hit the player's tutorial meteor
function Meteor:TutorialHit(player: Player, position: Vector3): boolean
	local entry = tutorialMeteors[player]
	local part = entry and entry.Part
	if not part or not part.Parent then
		return false
	end
	local cfg = settings.Tutorial
	if (position - part.Position).Magnitude > cfg.Radius + Config.World.Reach + 2 then
		return false
	end
	entry.Hits += 1
	local left = cfg.Hits - entry.Hits
	Net:Send(player, "MeteorHit", 1)
	if entry.Back then
		(entry.Back :: any).Fill.Size = UDim2.fromScale(math.max(0, left / cfg.Hits), 1)
		World.SetText((entry.Back :: any).Text, "☄️ %d", math.max(0, left))
	end
	if left > 0 then
		return true
	end
	-- cracked! a star egg (only you can grab it first) + a few coin chunks
	tutorialMeteors[player] = nil
	local ground = Vector3.new(part.Position.X, 0, part.Position.Z)
	part:Destroy()
	shatter(ground + Vector3.new(0, 2, 0), settings.Kinds[1].Color)
	Net:Send(player, "MeteorImpact", ground)
	spawnChunks(ground, 3, false)
	-- the next tutorial step ("Grab") drops the star egg right here
	Services.ProgressionService:TutorialEvent(player, "Meteor", 1, { Position = ground + Vector3.new(0, 0, 7) })
	return true
end

function Meteor:HasTutorialMeteor(player: Player): boolean
	return tutorialMeteors[player] ~= nil
end

---------------------------------------------------------------------------
-- cloud tests only
---------------------------------------------------------------------------
-- start a meteor at a site type now; skipWarning = it falls right away
function Meteor:LaunchForTest(siteType: string?, skipWarning: boolean?)
	assert(not RunService:IsRunning(), "test hook used on a live server")
	resetToIdle()
	startWarning(self:PickSite(siteType))
	if skipWarning then
		warnEnd = os.time()
	else
		warnEnd = os.time() + 60
	end
	setAttributes()
	return current
end

function Meteor:StateForTest(): string
	return state
end

---------------------------------------------------------------------------
function Meteor:Init(services)
	Services = services
	Data = services.DataService
	World = services.WorldService
end

function Meteor:Start()
	setAttributes()
	workspace:SetAttribute("MeteorLootUntil", 0)
	task.spawn(function()
		local lastRankPush = 0
		local lastMarker = 0
		local function step()
			local now = os.time()
			if state == "Idle" then
				if now >= nextAt or #summonQueue > 0 then
					startWarning(nil)
				end
			elseif state == "Warning" then
				if now ~= lastMarker then
					lastMarker = now
					updateMarker()
				end
				if now >= warnEnd then
					startFalling()
				end
			elseif state == "Active" then
				if now >= endsAt then
					safeFinish(false)
				elseif os.clock() - lastRankPush >= 1 then
					lastRankPush = os.clock()
					local list = ranking()
					local top = {}
					for i = 1, math.min(5, #list) do
						table.insert(top, { Name = list[i].Player.DisplayName, Score = math.floor(list[i].Score) })
					end
					for place, entry in list do
						Net:Send(entry.Player, "MeteorRank", top, place, math.floor(entry.Score))
					end
					for _, player in Players:GetPlayers() do
						if not scores[player] then
							Net:Send(player, "MeteorRank", top, nil, 0)
						end
					end
				end
			end
		end
		while true do
			task.wait(0.25)
			local ok, err = pcall(step)
			if not ok then
				warn("[Meteor] loop error: " .. tostring(err))
				resetToIdle()
			elseif state == "Ending" then
				-- finish() never got back to Idle: recover
				resetToIdle()
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		scores[player] = nil
		local entry = tutorialMeteors[player]
		tutorialMeteors[player] = nil
		if entry and entry.Part then
			entry.Part:Destroy()
		end
	end)

	-- "GO": during the warning only, to the entrance of the landing area
	-- (you still have to run the last bit - that's the rush)
	Net:On("GoToMeteor", 2, function(player)
		local character = player.Character
		local data = Data:Get(player)
		if not character or not data or not current or state ~= "Warning" then
			return
		end
		if Services.ShardService:IsCarrying(player) then
			Net:Notify(player, "Run! You can't teleport while carrying a shard.")
			return
		end
		local destination
		if current.Type == "Zone" then
			if data.ZoneLevel < current.SiteZone then
				Net:Notify(player, "Unlock %s first!", nil, Config.Zones[current.SiteZone].Name)
				return
			end
			destination = World:SpawnFor(current.SiteZone)
		elseif current.Type == "Avenue" then
			destination = CFrame.new(0, 4, Config.World.Bases.ZStart - 12)
		else
			destination = World.HubSpawn
		end
		character:PivotTo(destination)
	end)
end

return Meteor
