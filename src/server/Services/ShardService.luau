--[[
	ShardService: star shards in the world.

	* Falling stars crash every ~40-70s somewhere players can reach (hub or an
	  unlocked mine) and leave a shard with a tall light beacon.
	* A destroyed meteor spills a burst of better shards (the top hitter gets
	  an Epic+ one reserved for a few seconds).
	* Touch a shard to pick it up: it floats over your head, you're slower,
	  and ANYONE can bonk you (anywhere but the spawn) to make you drop it.
	* Walk into your own base to put it on a pedestal (BaseService).
	* Stolen shards remember their owner: if dropped and nobody grabs them
	  they fly home; the owner can touch them to get them back instantly.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local ShardModel = require(Shared.ShardModel)
local Net = require(script.Parent.Net)

local Shards = {}
local Services
local Data
local World

local SETTINGS = Config.Shards
local rng = Random.new()

local carrying = {} -- [player] = { Id, Meta, Model }
local ground = {} -- [model] = record

local HUB_SPOTS = {
	Vector3.new(-30, 0, -10),
	Vector3.new(30, 0, -10),
	Vector3.new(-32, 0, 55),
	Vector3.new(32, 0, 55),
	Vector3.new(-20, 0, 20),
	Vector3.new(22, 0, 18),
	Vector3.new(0, 0, -5),
	Vector3.new(-40, 0, -60),
	Vector3.new(40, 0, -60),
}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart
end

local function rarityName(id: string): string
	local def = SETTINGS.Rarities[id]
	return if def then def.Name else id
end

---------------------------------------------------------------------------
-- carrying
---------------------------------------------------------------------------
function Shards:IsCarrying(player: Player): boolean
	return carrying[player] ~= nil
end

-- walk speed multiplier while carrying (heavier = rarer = slower)
function Shards:SpeedMult(player: Player): number
	local info = carrying[player]
	local def = info and SETTINGS.Rarities[info.Id]
	if not def then
		return 1
	end
	local mult = def.Speed
	if Services.MonetizationService:HasPass(player, "FastCarry") then
		mult *= Config.PvP.CarrySpeedPass
	end
	return mult
end

local function attachModel(player: Player, id: string): Model?
	local root = rootOf(player)
	if not root then
		return nil
	end
	local model = ShardModel.Build(Config, id, 0.8)
	model.Name = "CarriedShard"
	ShardModel.SetAnchored(model, false)
	model:PivotTo(root.CFrame * CFrame.new(0, 5.2, 0))
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = model.PrimaryPart
	weld.Parent = model.PrimaryPart
	local highlight = Instance.new("Highlight")
	highlight.Name = "CarrierGlow"
	highlight.FillTransparency = 1
	highlight.OutlineColor = SETTINGS.Rarities[id].Color
	highlight.OutlineTransparency = 0.1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model
	model.Parent = player.Character
	-- the highlight outlines the whole character so hunters can spot carriers
	highlight.Adornee = player.Character
	return model
end

local function endCarry(player: Player)
	local info = carrying[player]
	carrying[player] = nil
	if info and info.Model then
		info.Model:Destroy()
	end
	player:SetAttribute("Carrying", nil)
	player:SetAttribute("CarryStolen", nil)
	Services.CharacterService:ApplyWalkSpeed(player)
	return info
end

function Shards:StartCarry(player: Player, id: string, meta)
	if carrying[player] then
		return false
	end
	local model = attachModel(player, id)
	if not model then
		return false
	end
	carrying[player] = { Id = id, Meta = meta or {}, Model = model }
	player:SetAttribute("Carrying", id)
	player:SetAttribute("CarryStolen", meta ~= nil and meta.From ~= nil)
	Services.CharacterService:ApplyWalkSpeed(player)
	local fromName = if meta and meta.From then meta.From.DisplayName else nil
	Net:Send(player, "CarryStart", id, fromName)
	return true
end

-- the shard flies back to the base it was stolen from
local function returnHome(meta, message: boolean)
	local owner = meta and meta.From
	if not owner or not owner.Parent or not meta.Entry then
		return
	end
	Services.BaseService:SetAway(owner, meta.Entry, false)
	if message then
		Net:Notify(owner, "🛡️ Your %s flew back home!", Color3.fromRGB(120, 230, 255), rarityName(meta.Entry.Id))
	end
end

---------------------------------------------------------------------------
-- shards on the ground
---------------------------------------------------------------------------
local function destroyGround(model: Model)
	ground[model] = nil
	if model.Parent then
		model:Destroy()
	end
end

local tryPickup -- forward declaration

---------------------------------------------------------------------------
-- star guardians: rock golems that protect a fallen star and chase the
-- player who grabs it. If they catch you, they take the shard back to the
-- crash site. Bonk one (swing at it) to stun it - friends can cover you!
---------------------------------------------------------------------------
local GUARDIAN = Config.Guardian
local GUARDIAN_Y = 1.7 -- root height: the golem hovers just above the ground
local guardians = {} -- [model] = guardian record

local function buildGuardian(color: Color3): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "StarGuardian"
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.Parent = model
	local function limb(name: string, size: Vector3, offset: CFrame, partColor: Color3, material: Enum.Material)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = root.CFrame * offset
		p.Color = partColor
		p.Material = material
		p.Anchored = true -- moved by the server every frame (no physics needed)
		p.CanCollide = false
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end
	local rock = Color3.fromRGB(85, 80, 95)
	limb("Torso", Vector3.new(3.4, 3.2, 2.4), CFrame.new(0, 0.6, 0), rock, Enum.Material.Basalt)
	limb("Head", Vector3.new(2.4, 2, 2.2), CFrame.new(0, 3.2, 0), rock, Enum.Material.Basalt)
	for _, x in { -0.55, 0.55 } do
		limb("Eye", Vector3.new(0.5, 0.35, 0.2), CFrame.new(x, 3.4, -1.1), color, Enum.Material.Neon)
	end
	for _, x in { -2.3, 2.3 } do
		limb("Arm", Vector3.new(1.2, 3.4, 1.3), CFrame.new(x, 0.2, 0) * CFrame.Angles(0, 0, math.rad(x * 3)), rock, Enum.Material.Basalt)
	end
	local crystal =
		limb("Crystal", Vector3.new(0.9, 2.4, 0.9), CFrame.new(0, 2.6, 1.2) * CFrame.Angles(0.5, 0, 0), color, Enum.Material.Neon)
	local glow = Instance.new("PointLight")
	glow.Color = color
	glow.Range = 14
	glow.Brightness = 2
	glow.Parent = crystal

	model.PrimaryPart = root

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(7, 0, 1.6, 0)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 5.5, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 120
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = color
	World.SetText(text, "🗿 STAR GUARDIAN")
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = text
	text.Parent = gui
	gui.Parent = root
	return model, root
end

local function spawnGuardian(id: string, home: Vector3)
	local def = SETTINGS.Rarities[id]
	local index = Util.ShardIndex(Config, id)
	local model, root = buildGuardian(def.Color)
	local start = Vector3.new(home.X + 6, GUARDIAN_Y, home.Z)
	model:PivotTo(CFrame.new(start))
	model.Parent = World:Folder("Shards")
	local record = {
		Model = model,
		Root = root,
		Home = home,
		Position = start,
		Facing = Vector3.zAxis,
		Destination = start,
		Speed = GUARDIAN.Speed + (index - 1) * GUARDIAN.SpeedPerRarity,
		Target = nil,
		ChaseUntil = 0,
		StunnedUntil = 0,
		ShardId = id,
	}
	guardians[model] = record
	return record
end

local function despawnGuardian(record)
	if not record then
		return
	end
	guardians[record.Model] = nil
	if record.Model.Parent then
		record.Model:Destroy()
	end
end

function Shards:IsGuardian(model: Instance?): boolean
	return model ~= nil and guardians[model] ~= nil
end

-- a bonk stuns the guardian for a moment
function Shards:HitGuardian(player: Player, model: Model): boolean
	local record = guardians[model]
	if not record then
		return false
	end
	record.StunnedUntil = os.clock() + GUARDIAN.StunSeconds
	Net:Notify(player, "💥 Guardian stunned!", Color3.fromRGB(255, 200, 90))
	Net:Send(player, "BonkHit", record.Root.Position)
	return true
end

function Shards:NearestGuardian(position: Vector3, range: number): Model?
	local best, bestDistance = nil, range
	for model, record in guardians do
		local distance = (record.Root.Position - position).Magnitude
		if distance <= bestDistance then
			best, bestDistance = model, distance
		end
	end
	return best
end

-- opts: Beacon (bool), PriorityUser/PriorityUntil, BlockUser/BlockUntil, Lifetime
function Shards:SpawnGround(id: string, position: Vector3, meta, opts)
	opts = opts or {}
	local def = SETTINGS.Rarities[id]
	local model = ShardModel.Build(Config, id, 1.15)
	ShardModel.SetAnchored(model, true)
	model:PivotTo(CFrame.new(position + Vector3.new(0, 7.5, 0)))
	model:SetAttribute("Spin", true)
	model:SetAttribute("Stolen", meta ~= nil and meta.From ~= nil)

	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = Vector3.new(7, 13, 7)
	hitbox.CFrame = CFrame.new(position + Vector3.new(0, 5.5, 0))
	hitbox.Anchored = true
	hitbox.CanCollide = false
	hitbox.CanQuery = true -- so taps on it walk you there
	hitbox.Transparency = 1
	hitbox.Parent = model

	if opts.Beacon ~= false then
		local index = Util.ShardIndex(Config, id)
		local beacon = Instance.new("Part")
		beacon.Name = "Beacon"
		beacon.Shape = Enum.PartType.Cylinder
		beacon.Size = Vector3.new(180, 1 + index * 0.5, 1 + index * 0.5)
		beacon.CFrame = CFrame.new(position + Vector3.new(0, 90, 0)) * CFrame.Angles(0, 0, math.rad(90))
		beacon.Color = def.Color
		beacon.Material = Enum.Material.Neon
		beacon.Transparency = 0.45
		beacon.Anchored = true
		beacon.CanCollide = false
		beacon.CanQuery = false
		beacon.CanTouch = false
		beacon.CastShadow = false
		beacon.Parent = model
	end

	local label = Instance.new("BillboardGui")
	label.Name = "Label"
	label.Size = UDim2.new(8, 0, 2, 0)
	label.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	label.LightInfluence = 0
	label.MaxDistance = 220
	label.AlwaysOnTop = true
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = def.Color
	World.SetText(text, if meta and meta.From then "⚠️ %s" else "🌠 %s", def.Name)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Parent = text
	text.Parent = label
	label.Parent = model.PrimaryPart

	model.Parent = World:Folder("Shards")
	local record = {
		Id = id,
		Meta = meta,
		PriorityUser = opts.PriorityUser,
		PriorityUntil = opts.PriorityUntil or 0,
		BlockUser = opts.BlockUser,
		BlockUntil = opts.BlockUntil or 0,
	}
	ground[model] = record
	if opts.Guardian then
		record.Guardian = opts.Guardian
	elseif opts.WithGuardian and Util.ShardIndex(Config, id) >= GUARDIAN.MinRarity then
		record.Guardian = spawnGuardian(id, position)
	end

	hitbox.Touched:Connect(function(hit)
		if ground[model] then
			tryPickup(model, record, hit)
		end
	end)

	-- stolen shards fly home if nobody grabs them; others fade out eventually
	local lifetime = if meta and meta.From then SETTINGS.ReturnSeconds else (opts.Lifetime or SETTINGS.GroundLifetime)
	task.delay(lifetime, function()
		if ground[model] then
			destroyGround(model)
			returnHome(meta, true)
			if record.Guardian and not record.Guardian.Target then
				despawnGuardian(record.Guardian)
			end
		end
	end)
	return model
end

tryPickup = function(model: Model, record, hit: BasePart)
	local character = hit:FindFirstAncestorOfClass("Model")
	local player = character and Players:GetPlayerFromCharacter(character)
	if not player or carrying[player] then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or not Data:Get(player) then
		return
	end
	local t = now()
	if record.BlockUser == player.UserId and t < record.BlockUntil then
		return
	end
	if record.PriorityUser and record.PriorityUser ~= player.UserId and t < record.PriorityUntil then
		return
	end
	local meta = record.Meta
	-- the owner of a stolen shard gets it back instantly
	if meta and meta.From == player then
		destroyGround(model)
		Services.BaseService:SetAway(player, meta.Entry, false)
		Net:Notify(player, "🛡️ You got your %s back!", Color3.fromRGB(120, 230, 255), rarityName(record.Id))
		Net:Send(player, "ShardRecovered", record.Id)
		return
	end
	if not Services.BaseService:HasBase(player) then
		Net:Notify(player, "All bases are taken - you'll get one when someone leaves.")
		return
	end
	destroyGround(model)
	if Shards:StartCarry(player, record.Id, meta) and record.Guardian then
		local guardian = record.Guardian
		guardian.Target = player
		guardian.ChaseUntil = os.clock() + GUARDIAN.ChaseSeconds
		carrying[player].Guardian = guardian
		Net:Send(player, "GuardianChase", GUARDIAN.ChaseSeconds)
	end
end

-- stun traps: a thief carrying a shard stolen from `owner` loses it instantly
function Shards:Confiscate(player: Player, owner: Player): boolean
	local info = carrying[player]
	if not info or not info.Meta or info.Meta.From ~= owner then
		return false
	end
	endCarry(player)
	returnHome(info.Meta, false)
	Net:Send(player, "CarryLost", info.Id, owner.DisplayName)
	return true
end

-- drop whatever the player carries (bonked / died / left)
function Shards:Drop(player: Player, attacker: Player?)
	local info = carrying[player]
	if not info then
		return
	end
	local root = rootOf(player)
	local position = if root then root.Position else nil
	endCarry(player)
	if not position then
		returnHome(info.Meta, true)
		return
	end
	local angle = rng:NextNumber(0, math.pi * 2)
	local spot = Vector3.new(position.X + math.cos(angle) * 5, 0, position.Z + math.sin(angle) * 5)
	local meta = if info.Meta and info.Meta.From then info.Meta else nil
	self:SpawnGround(info.Id, spot, meta, {
		Beacon = true,
		BlockUser = player.UserId,
		BlockUntil = now() + SETTINGS.RegrabDelay,
	})
	Net:Send(player, "CarryLost", info.Id, if attacker then attacker.DisplayName else nil)
	if attacker then
		Net:Notify(attacker, "💥 %s dropped a %s - grab it!", Color3.fromRGB(255, 170, 80), player.DisplayName, rarityName(info.Id))
	end
end

---------------------------------------------------------------------------
-- delivery
---------------------------------------------------------------------------
local function deliver(player: Player)
	local info = endCarry(player)
	if not info then
		return
	end
	local id = info.Id
	local meta = info.Meta
	local data = Data:Get(player)
	if meta and meta.From then
		local owner = meta.From
		if owner.Parent and meta.Entry then
			Services.BaseService:RemoveEntry(owner, meta.Entry)
			Net:Notify(owner, "💔 %s stole your %s!", Color3.fromRGB(255, 90, 90), player.DisplayName, rarityName(id))
		end
		if data then
			data.Stats.ShardsStolen += 1
		end
		Services.ProgressionService:AddQuest(player, "Steal", 1)
	end
	local result, coins = Services.BaseService:AddShard(player, id)
	Services.ProgressionService:AddQuest(player, "Shard", 1)
	Services.ProgressionService:TutorialEvent(player, "Shard", 1)
	local index = Util.ShardIndex(Config, id)
	Services.ProgressionService:AddPoints(player, SETTINGS.Points[index] or 10)
	Net:Send(player, "ShardDelivered", id, result, coins)
	if index >= 4 then
		Net:Announce("🌟 %s brought a %s home!", SETTINGS.Rarities[id].Color, player.DisplayName, rarityName(id))
	end
end

---------------------------------------------------------------------------
-- falling stars + meteor spill
---------------------------------------------------------------------------
local function maxZoneInServer(): number
	local best = 1
	for _, player in Data:LoadedPlayers() do
		local data = Data:Get(player)
		if data then
			best = math.max(best, data.ZoneLevel)
		end
	end
	return math.min(best, #Config.Zones)
end

function Shards:FallingStar(forcedZone: number?)
	local zone = forcedZone
	if not zone then
		zone = if rng:NextNumber() < SETTINGS.FallingStar.HubChance then 0 else rng:NextInteger(1, maxZoneInServer())
	end
	local position
	if zone == 0 then
		local spot = HUB_SPOTS[rng:NextInteger(1, #HUB_SPOTS)]
		position = spot + Vector3.new(rng:NextNumber(-4, 4), 0, rng:NextNumber(-4, 4))
	else
		local info = World.Zones[zone]
		position = Vector3.new(rng:NextNumber(-36, 36), 0, rng:NextNumber(info.ZStart + 18, info.ZEnd - 10))
	end
	local luck = 1 + math.max(0, zone - 1) * SETTINGS.FallingStar.LuckPerZone
	local id = Util.RollShard(Config, luck, rng)
	local flight = 1.8
	Net:Broadcast("StarFall", position, id, flight)
	task.delay(flight, function()
		self:SpawnGround(id, position, nil, { Beacon = true, WithGuardian = true })
		local where = if zone == 0 then "Hub" else Config.Zones[zone].Name
		Net:Announce("🌠 A falling star crashed in %s! Grab the %s!", SETTINGS.Rarities[id].Color, where, rarityName(id))
	end)
	return id
end

-- tutorial: a guaranteed star just for this player, landing in the hub
local tutorialStars = {} -- [player] = ground model
function Shards:TutorialStar(player: Player)
	local existing = tutorialStars[player]
	if existing and existing.Parent then
		return
	end
	if carrying[player] then
		return
	end
	local position = Vector3.new(-30, 0, -38) + Vector3.new(rng:NextNumber(-4, 4), 0, rng:NextNumber(-4, 4))
	local flight = 1.6
	Net:Send(player, "StarFall", position, "Rare", flight)
	task.delay(flight, function()
		if not player.Parent then
			return
		end
		tutorialStars[player] = self:SpawnGround("Rare", position, nil, {
			Beacon = true,
			PriorityUser = player.UserId,
			PriorityUntil = now() + 300,
			Lifetime = 600,
		})
		Net:Notify(player, "🌠 A star fell just for you! Grab it!", Color3.fromRGB(120, 230, 255))
	end)
end

-- ranking = { { Player = p, Score = n }, ... } best first
function Shards:SpillMeteor(position: Vector3, ranking)
	local settings = SETTINGS.Meteor
	local count = math.clamp(settings.Count + settings.PerParticipant * #ranking, 1, settings.Max)
	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local radius = rng:NextNumber(11, 19)
		local spot = Vector3.new(position.X + math.cos(angle) * radius, 0, position.Z + math.sin(angle) * radius)
		local top = ranking[1] and ranking[1].Player
		if i == 1 and top then
			-- the winner's prize: Epic or better, reserved for them for a moment
			local id = Util.RollShard(Config, settings.Luck, rng, 3)
			self:SpawnGround(id, spot, nil, {
				Beacon = true,
				PriorityUser = top.UserId,
				PriorityUntil = now() + settings.TopPriority,
			})
			Net:Notify(top, "🥇 Your %s prize shard is waiting - grab it!", Color3.fromRGB(255, 220, 90), rarityName(id))
		else
			self:SpawnGround(Util.RollShard(Config, settings.Luck, rng), spot, nil, { Beacon = true })
		end
	end
end

---------------------------------------------------------------------------
function Shards:Init(services)
	Services = services
	Data = services.DataService
	World = services.WorldService
end

-- move one guardian toward its destination (anchored + server-driven)
local function moveGuardian(g, dt: number)
	local flat = (g.Destination - g.Position) * Vector3.new(1, 0, 1)
	local distance = flat.Magnitude
	if distance > 0.3 then
		local stepLength = math.min(distance, g.Speed * dt)
		g.Facing = flat.Unit
		g.Position += g.Facing * stepLength
	end
	local bob = math.sin(os.clock() * 6 + g.Home.X) * 0.25
	local at = Vector3.new(g.Position.X, GUARDIAN_Y + bob, g.Position.Z)
	g.Model:PivotTo(CFrame.lookAt(at, at + g.Facing))
end

local function stepGuardians(dt: number)
	local clock = os.clock()
	for model, g in guardians do
		if not model.Parent then
			guardians[model] = nil
		elseif g.StunnedUntil > clock then
			-- dazed: wobble in place
			local at = Vector3.new(g.Position.X, GUARDIAN_Y, g.Position.Z)
			g.Model:PivotTo(CFrame.lookAt(at, at + g.Facing) * CFrame.Angles(0, 0, math.sin(clock * 20) * 0.15))
		else
			if g.Target then
				local target = g.Target
				local info = carrying[target]
				local root = rootOf(target)
				local giveUp = not target.Parent
					or not info
					or info.Guardian ~= g
					or not root
					or clock > g.ChaseUntil
					or (g.Position - g.Home).Magnitude > GUARDIAN.ChaseRange
					or Util.InBases(Config, root.Position)
				if giveUp then
					g.Target = nil
					g.Done = true -- the shard is gone: walk back and vanish
					if info and info.Guardian == g then
						info.Guardian = nil
					end
					g.Destination = g.Home
				elseif root then
					g.Destination = root.Position
					local gap = ((root.Position - g.Position) * Vector3.new(1, 0, 1)).Magnitude
					if gap <= GUARDIAN.CatchRange then
						-- caught! the guardian takes the shard back to the crash site
						local id = info.Id
						endCarry(target)
						Services.CharacterService:Stun(target, 1.2)
						local push = (root.Position - g.Position) * Vector3.new(1, 0, 1)
						push = if push.Magnitude > 0.01 then push.Unit else Vector3.zAxis
						Net:Send(target, "Knockback", push * 45 + Vector3.new(0, 30, 0))
						Net:Send(target, "CaughtByGuardian", id)
						g.Target = nil
						g.Done = false
						Shards:SpawnGround(id, g.Home, nil, {
							Beacon = true,
							Guardian = g,
							BlockUser = target.UserId,
							BlockUntil = now() + 2,
						})
						g.Destination = g.Home + Vector3.new(6, 0, 0)
					end
				end
			else
				local homeSpot = g.Home + Vector3.new(6, 0, 0)
				local distance = ((g.Position - homeSpot) * Vector3.new(1, 0, 1)).Magnitude
				if g.Done and distance < 3 then
					despawnGuardian(g)
					continue
				end
				g.Destination = homeSpot
			end
			moveGuardian(g, dt)
		end
	end
end

-- test hook (cloud tests): the live guardian records
function Shards:GuardiansForTest()
	return guardians
end

function Shards:Start()
	RunService.Heartbeat:Connect(function(dt)
		if next(guardians) == nil then
			return
		end
		local ok, err = pcall(stepGuardians, math.min(dt, 0.1))
		if not ok then
			warn("[Shards] guardian step failed: " .. tostring(err))
		end
	end)
	-- delivery + safety checks
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.15 then
			return
		end
		accumulator = 0
		for player, info in carrying do
			local root = rootOf(player)
			if not root or not info.Model or not info.Model.Parent then
				-- character vanished (respawn/reset): the shard drops where it was
				if root then
					self:Drop(player)
				else
					endCarry(player)
					returnHome(info.Meta, true)
				end
			elseif Services.BaseService:InOwnPlot(player, root.Position) then
				local ok, err = pcall(deliver, player)
				if not ok then
					warn("[Shards] delivery failed: " .. tostring(err))
				end
			end
		end
	end)

	local function onCharacter(player: Player, character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if humanoid then
			humanoid.Died:Connect(function()
				if carrying[player] then
					self:Drop(player)
				end
			end)
		end
	end
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
		if player.Character then
			task.spawn(onCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		local star = tutorialStars[player]
		tutorialStars[player] = nil
		if star and ground[star] then
			destroyGround(star)
		end
		local info = carrying[player]
		if info then
			endCarry(player)
			returnHome(info.Meta, true) -- a thief who leaves gives the shard back
		end
		-- the owner left: shards stolen from them vanish (they keep theirs)
		for carrier, other in carrying do
			if other.Meta and other.Meta.From == player then
				endCarry(carrier)
				Net:Notify(carrier, "The owner left - the shard vanished!")
			end
		end
		for model, record in ground do
			if record.Meta and record.Meta.From == player then
				destroyGround(model)
			end
		end
	end)

	-- falling stars
	task.spawn(function()
		task.wait(25)
		while true do
			local star = SETTINGS.FallingStar
			task.wait(rng:NextNumber(star.MinInterval, star.MaxInterval))
			if #Players:GetPlayers() > 0 then
				local ok, err = pcall(self.FallingStar, self)
				if not ok then
					warn("[Shards] falling star failed: " .. tostring(err))
				end
			end
		end
	end)
end

return Shards
