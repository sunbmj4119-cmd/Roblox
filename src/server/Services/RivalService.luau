--[[
	RivalService: rival players for small servers (solo play).

	With only 1-2 real players a server feels empty, so two rivals join in -
	regular-looking avatars (official Roblox catalog items), with a name,
	level, title, pickaxe and pets following them, who play the game like
	anybody else:
	  * between meteors they mine ores in the mines (or hang around the hub),
	  * a meteor warning sends them running to the landing spot (far away:
	    they "teleport" to the area entrance, like the GO button),
	  * they smash the meteor (a bit slower than a real player) and show up
	    in the live ranking - beat them for 1st place!
	  * after the burst they grab star eggs nobody picked up and run home
	    with them (to the base district) - bonk them to make them drop it,
	  * now and then they try to bonk YOU when you carry an egg (never a new
	    player's first egg, never near the spawn or in the base district).
	They never take reserved eggs (tutorial / top 3) or guarded ones, never
	enter people's homes, and leave once the server fills up. They are game
	characters: no fake chat, no fake join messages, no real user accounts.
]]
local HttpService = game:GetService("HttpService")
local PathfindingService = game:GetService("PathfindingService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Net = require(script.Parent.Net)

local Rival = {}
local Services
local Data
local World

local SETTINGS = Config.Rivals
local rng = Random.new()
local rivals = {} -- [model] = record
local forcedCount: number? = nil -- cloud tests
local nextId = 0
local usedNames = {}
local spawning = false
local spawnRetryAt = 0

local GROUP = "Rivals"
local GATE_GROUP = "ZoneGates"
local PLAYER_GROUP = "PlayerCharacters"
local ANIMS = {
	Idle = "rbxassetid://507766388",
	Run = "rbxassetid://913376220",
	Jump = "rbxassetid://507765000",
	Fall = "rbxassetid://507767968",
	Slash = "rbxassetid://522635514",
}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function pick(list)
	return list[rng:NextInteger(1, #list)]
end

-- which area a position is in: 0 = hub, 1..n = mine zone, -1 = bases, nil = elsewhere
local function areaOf(position: Vector3): number?
	local probe = Vector3.new(position.X, 3, position.Z)
	if Util.InBases(Config, probe) then
		return -1
	end
	return Util.ZoneAt(Config, probe)
end

local function areaEntrance(area: number): Vector3
	-- (a few studs beside the spawn point, never right on it)
	local side = Vector3.new(if rng:NextNumber() < 0.5 then -1 else 1, 0, 0) * rng:NextNumber(7, 12)
	if area > 0 and World.Zones[area] then
		return World:SpawnFor(area).Position + side + Vector3.new(0, 0, 6)
	elseif area == -1 then
		return Vector3.new(0, 4, Config.World.Bases.ZStart - 12) + side
	end
	return World.HubSpawn.Position + side + Vector3.new(0, 0, rng:NextNumber(4, 10))
end

local function homeSpot(): Vector3
	return Vector3.new(rng:NextNumber(-6, 6), 3, Util.AvenueZ(Config))
end

---------------------------------------------------------------------------
-- the character
---------------------------------------------------------------------------
local function describe()
	local look = SETTINGS.Look
	local desc = Instance.new("HumanoidDescription")
	local skin = pick(look.Skins)
	desc.HeadColor = skin
	desc.TorsoColor = skin
	desc.LeftArmColor = skin
	desc.RightArmColor = skin
	desc.LeftLegColor = skin
	desc.RightLegColor = skin
	desc.HairAccessory = tostring(pick(look.Hair))
	if rng:NextNumber() < look.HatChance then
		desc.HatAccessory = tostring(pick(look.Hats))
	end
	desc.Shirt = pick(look.Shirts)
	desc.Pants = pick(look.Pants)
	return desc
end

-- the same overhead tag players have (title / name / level + rank)
local function overhead(model: Model, name: string, level: number, title, rank)
	local head = model:FindFirstChild("Head")
	if not head then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "Overhead"
	gui.Size = UDim2.new(7, 0, 2.6, 0)
	gui.StudsOffset = Vector3.new(0, 3.4, 0)
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = gui
	for i, row in { "Bounty", "Title", "Tags", "Name", "Rank" } do
		local label = Instance.new("TextLabel")
		label.Name = row
		label.LayoutOrder = i
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, if row == "Name" then 0.26 else 0.18, 0)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.RichText = true
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Visible = row == "Name" or row == "Rank" or (row == "Title" and title ~= nil)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Parent = label
		label.Parent = gui
	end
	(gui:FindFirstChild("Name") :: TextLabel).Text = name
	local rankLabel = gui:FindFirstChild("Rank") :: TextLabel
	rankLabel.Text = string.format("Lv.%d %s", level, rank.Icon or "")
	rankLabel.TextColor3 = rank.Color
	if title then
		local titleLabel = gui:FindFirstChild("Title") :: TextLabel
		titleLabel.Text = title.Name
		titleLabel.TextColor3 = title.Color
		titleLabel:SetAttribute("LangFmt", "%s")
		titleLabel:SetAttribute("LangArgs", HttpService:JSONEncode({ title.Name }))
	end
	gui.Parent = head
end

local function serverPeers()
	local level, tier, zone, n = 0, 0, 1, 0
	for _, player in Data:LoadedPlayers() do
		local data = Data:Get(player)
		if data then
			level += data.Level or 1
			tier += data.PickaxeTier or 1
			zone = math.max(zone, data.ZoneLevel or 1)
			n += 1
		end
	end
	if n == 0 then
		return 3, 2, 1
	end
	return math.floor(level / n + 0.5), math.floor(tier / n + 0.5), zone
end

local function playAnim(record, name: string, speed: number?)
	local track = record.Tracks[name]
	if not track then
		return
	end
	if name == "Slash" then
		track:Play(0.05)
		return
	end
	if record.Playing ~= name then
		if record.Playing and record.Tracks[record.Playing] then
			record.Tracks[record.Playing]:Stop(0.2)
		end
		record.Playing = name
		track:Play(0.2)
	end
	if speed then
		track:AdjustSpeed(speed)
	end
end

local function spawnRival(index: number)
	nextId += 1
	local name
	for _ = 1, 20 do
		name = pick(SETTINGS.Names)
		if not usedNames[name] then
			break
		end
	end
	local peerLevel, peerTier, peerZone = serverPeers()
	local level = math.max(1, peerLevel + rng:NextInteger(-2, 3))
	local model = Players:CreateHumanoidModelFromDescription(describe(), Enum.HumanoidRigType.R15)
	model.Name = name
	model:SetAttribute("Rival", true)
	local animate = model:FindFirstChild("Animate")
	if animate then
		animate:Destroy() -- (animations are played by the server)
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.WalkSpeed = SETTINGS.Speed
	humanoid.BreakJointsOnDeath = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = GROUP
		end
	end
	-- a title like the ones players earn, a weekly rank
	local titles = {}
	for _, title in Config.Titles do
		local need = title.Need or {}
		if title.Id ~= "Newcomer" and need.Level and need.Level <= level then
			table.insert(titles, title)
		end
	end
	local title = if #titles > 0 and rng:NextNumber() < 0.6 then pick(titles) else nil
	local rank = Config.Ranks[rng:NextInteger(1, math.min(3, #Config.Ranks))]
	overhead(model, name, level, title, rank)
	local spawnAt = areaEntrance(0)
	model:PivotTo(CFrame.new(spawnAt + Vector3.new(0, 2, 0)))
	-- a pickaxe like everyone else's (a tier near the server's players)
	local tier = math.clamp(peerTier + rng:NextInteger(0, 1), 1, #Config.Pickaxes)
	local tool = Services.CharacterService.BuildPickaxe(tier)
	tool.Parent = model
	-- 2-3 pets following (rendered by every client, like players' pets)
	local pets = {}
	local pool = Config.Eggs[Config.Shards.ZoneEggs[math.clamp(peerZone, 1, #Config.Shards.ZoneEggs)]].Pets
	for _ = 1, rng:NextInteger(2, 3) do
		local entry = pick(pool)
		table.insert(pets, "|" .. entry[1] .. "|" .. rng:NextInteger(1, 8) .. "|0")
	end
	model:SetAttribute("Pets", HttpService:JSONEncode(pets))

	-- (animations need the character in the world; an error from here on
	-- removes the half-built rival again)
	model.Parent = workspace
	local okBuild, buildErr = pcall(function()
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
		pcall(function()
			humanoid:EquipTool(tool)
		end)
	end)
	if not okBuild then
		model:Destroy()
		error(buildErr)
	end
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	local tracks = {}
	for animName, id in ANIMS do
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local ok, track = pcall(animator.LoadAnimation, animator, animation)
		if ok and track then
			track.Priority = if animName == "Slash" then Enum.AnimationPriority.Action else Enum.AnimationPriority.Movement
			track.Looped = animName == "Idle" or animName == "Run"
			tracks[animName] = track
		end
	end
	local record = {
		Model = model,
		Humanoid = humanoid,
		Root = root,
		Tracks = tracks,
		Name = name,
		Index = index,
		Level = level,
		Tier = tier,
		StunnedUntil = 0,
		NextHit = 0,
		NextBonk = now() + rng:NextNumber(10, 30),
		NextPlan = 0,
		Aggression = rng:NextNumber(0.25, 0.7),
		Carry = nil,
		Task = "Idle",
		-- identity in the meteor ranking
		Entity = { DisplayName = name, Name = name, UserId = -1000000 - nextId, Parent = workspace, IsRival = true },
	}
	humanoid.Running:Connect(function(speed)
		if speed > 1 then
			playAnim(record, "Run", math.clamp(speed / 16, 0.6, 1.4))
		else
			playAnim(record, "Idle")
		end
	end)
	humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Jumping then
			local track = tracks.Jump
			if track then
				track:Play(0.1)
			end
		end
	end)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = GROUP
		end
	end
	playAnim(record, "Idle")
	usedNames[name] = true
	rivals[model] = record
	-- 🏠 a home of their own in the base district (pets on display)
	local okHome, homeErr = pcall(Services.RivalHomes.Claim, Services.RivalHomes, record)
	if not okHome then
		warn("[Rival] home failed: " .. tostring(homeErr))
	end
	return record
end

local function setCarry(record, item, meta)
	record.CarryMeta = if item then meta else nil
	if record.CarryModel then
		record.CarryModel:Destroy()
		record.CarryModel = nil
	end
	record.Carry = item
	local shards = Services.ShardService
	if item then
		-- the egg above the head, like players carrying one
		local head = record.Model:FindFirstChild("Head") :: BasePart
		local egg = shards.BuildItemModel(item, 1)
		for _, part in egg:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = false
				part.CanCollide = false
				part.Massless = true
				part.CollisionGroup = GROUP
			end
		end
		egg:PivotTo(head.CFrame * CFrame.new(0, 3, 0))
		for _, part in egg:GetDescendants() do
			if part:IsA("BasePart") then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = head
				weld.Part1 = part
				weld.Parent = part
			end
		end
		egg.Parent = record.Model
		record.CarryModel = egg
		record.Model:SetAttribute("Carrying", true)
		record.CarryUntil = os.clock() + SETTINGS.CarrySeconds
		local def = Config.Shards.Rarities[item.Rarity]
		record.Humanoid.WalkSpeed = SETTINGS.Speed * (if def then def.Speed else 0.85)
	else
		record.Model:SetAttribute("Carrying", nil)
		record.Humanoid.WalkSpeed = SETTINGS.Speed
	end
end

local function despawn(record)
	rivals[record.Model] = nil
	usedNames[record.Name] = nil
	if record.Carry then
		-- (never take an egg / a stolen pet away when leaving: drop it)
		local item, meta = record.Carry, record.CarryMeta
		setCarry(record, nil)
		Services.ShardService:SpawnGround(item, flat(record.Root.Position), meta, { Beacon = true, RivalBlockSeconds = 20 })
	end
	pcall(Services.RivalHomes.Release, Services.RivalHomes, record)
	Services.MeteorService:Forget(record.Entity)
	if record.Model.Parent then
		record.Model:Destroy()
	end
end

local function count(): number
	local n = 0
	for _ in rivals do
		n += 1
	end
	return n
end

---------------------------------------------------------------------------
-- walking: pathfinding, area changes ("teleport" like the GO / zone buttons)
---------------------------------------------------------------------------
local function teleport(record, position: Vector3)
	record.Model:PivotTo(CFrame.new(position + Vector3.new(0, 3, 0)))
	record.Waypoints = nil
	record.Goal = nil
	record.Stuck = 0
end

local function walkTo(record, goal: Vector3, allowTeleport: boolean?)
	local root = record.Root
	local here = root.Position
	local hereArea, goalArea = areaOf(here), areaOf(goal)
	-- far away in another area: take the shortcut (players use GO / the zone teleport)
	if allowTeleport ~= false and not record.Carry and hereArea ~= goalArea and (flat(goal - here)).Magnitude > 140 then
		if not record.TeleportAt then
			record.TeleportAt = os.clock() + rng:NextNumber(0.6, 2.5) -- (a human needs a moment to press it)
		elseif os.clock() >= record.TeleportAt then
			record.TeleportAt = nil
			teleport(record, areaEntrance(goalArea or 0))
		end
		return
	end
	record.TeleportAt = nil
	local distance = (flat(goal - here)).Magnitude
	if distance <= 3 then
		return -- (there)
	end
	if distance <= 14 then
		-- close: straight there, no path needed
		record.Waypoints = nil
		record.Goal = goal
		record.Humanoid:MoveTo(goal)
		return
	end
	if not record.Goal or (record.Goal - goal).Magnitude > 10 or os.clock() - (record.PathAt or 0) > 4 then
		record.Goal = goal
		record.PathAt = os.clock()
		record.Waypoints = nil
		local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 6 })
		local ok = pcall(path.ComputeAsync, path, here, goal)
		if ok and path.Status == Enum.PathStatus.Success then
			record.Waypoints = path:GetWaypoints()
			record.WaypointIndex = 2
		end
	end
	local target = goal
	if record.Waypoints then
		local waypoint = record.Waypoints[record.WaypointIndex]
		while waypoint and (flat(waypoint.Position - here)).Magnitude < 3 do
			record.WaypointIndex += 1
			waypoint = record.Waypoints[record.WaypointIndex]
		end
		if waypoint then
			target = waypoint.Position
			if waypoint.Action == Enum.PathWaypointAction.Jump then
				record.Humanoid.Jump = true
			end
		end
	end
	record.Humanoid:MoveTo(target)
	-- stuck? jump, then re-plan, then hop closer
	local moved = if record.LastPos then (flat(here - record.LastPos)).Magnitude else 99
	if os.clock() - (record.LastCheck or 0) > 1.5 then
		record.LastCheck = os.clock()
		record.LastPos = here
		if moved < 1.2 and (flat(goal - here)).Magnitude > 5 then
			record.Stuck = (record.Stuck or 0) + 1
			record.Humanoid.Jump = true
			record.PathAt = 0
			if
				record.Stuck >= 4
				and not record.Carry
				and allowTeleport ~= false
				and not Util.InBases(Config, goal + Vector3.new(0, 3, 0))
			then
				teleport(record, goal + Vector3.new(rng:NextNumber(-4, 4), 0, rng:NextNumber(-4, 4)))
			end
		else
			record.Stuck = 0
		end
	end
end

local function stop(record)
	record.Humanoid:MoveTo(record.Root.Position)
	record.Goal = nil
	record.Waypoints = nil
end

local function face(record, position: Vector3)
	local root = record.Root
	local look = flat(position - root.Position)
	if look.Magnitude > 0.5 then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + look)
	end
end

---------------------------------------------------------------------------
-- brains
---------------------------------------------------------------------------
-- how a rival smashes: a bit slower than the average real player here
local function rivalPace(): (number, number)
	local damage, cooldown, n = 0, 0, 0
	for _, player in Data:LoadedPlayers() do
		local data = Data:Get(player)
		if data then
			damage += Services.StatsService:Damage(player, data)
			cooldown += Services.StatsService:SwingCooldown(player, data)
			n += 1
		end
	end
	if n == 0 then
		return 10, 0.5 / SETTINGS.Pace
	end
	return damage / n, (cooldown / n) / SETTINGS.Pace
end

-- a real player carrying an egg that this rival could try to bonk
local function bonkTarget(record): Player?
	if record.Carry or now() < record.NextBonk then
		return nil
	end
	local best, bestDistance = nil, SETTINGS.Bonk.ChaseRange
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and Services.ShardService:IsCarrying(player) then
			local distance = (root.Position - record.Root.Position).Magnitude
			if distance < bestDistance and Services.MiningService:CanNpcBonk(player) then
				best, bestDistance = player, distance
			end
		end
	end
	return best
end

local function think(record)
	local t = now()
	local root = record.Root
	if not root.Parent or not record.Model.Parent or root.Position.Y < -40 then
		-- (fell out of the world somehow: leave; a new rival joins later)
		despawn(record)
		return
	end
	if record.StunnedUntil > t then
		stop(record)
		return
	end
	local meteor = Services.MeteorService
	local shards = Services.ShardService
	local current = meteor:Current()
	local state = workspace:GetAttribute("MeteorState")

	-- 1) carrying an egg / a stolen pet: run home with it (like everybody)
	local homes = Services.RivalHomes
	if record.Carry and os.clock() > (record.CarryUntil or math.huge) then
		-- couldn't make it home in time: drop it here
		local item, meta = record.Carry, record.CarryMeta
		setCarry(record, nil)
		record.Home = nil
		shards:SpawnGround(item, flat(root.Position), meta, { Beacon = true, RivalBlockSeconds = SETTINGS.DropBlockSeconds })
	end
	if record.Carry then
		record.Task = "Home"
		local home = record.Home or homes:HomeSpot(record) or homeSpot()
		record.Home = home
		walkTo(record, home, false)
		local arrived = (flat(home - root.Position)).Magnitude <= 8 or homes:IsHomeOf(record, root.Position)
		if arrived then
			local item, meta = record.Carry, record.CarryMeta
			setCarry(record, nil)
			record.Home = nil
			if item.Kind == "Pet" then
				homes:Delivered(record, meta)
			else
				homes:EggHome(record, item)
				if Util.ShardIndex(Config, item.Rarity) >= 4 then
					Net:Announce("🌟 %s brought a %s home!", shards.ItemColor(item), record.Name, shards.ItemName(item))
				end
			end
		end
		return
	end

	-- 2) chasing a player who carries an egg (now and then)
	local chase = record.ChaseTarget
	-- (gives up at once near the spawn / in the base district / on a new player)
	local defendId = if record.Defending then record.Entity.UserId else nil
	if chase and (not chase.Parent or t > record.ChaseUntil or not Services.MiningService:CanNpcBonk(chase, defendId)) then
		record.ChaseTarget = nil
		record.Defending = nil
		chase = nil
	end
	if not chase then
		local target = bonkTarget(record)
		if target and rng:NextNumber() < record.Aggression then
			record.ChaseTarget = target
			record.ChaseUntil = t + SETTINGS.Bonk.ChaseSeconds
			chase = target
		elseif target then
			record.NextBonk = t + 6 -- (decided not to, this time)
		end
	end
	if chase then
		record.Task = "Chase"
		local victimRoot = chase.Character and chase.Character:FindFirstChild("HumanoidRootPart")
		if victimRoot and victimRoot:IsA("BasePart") then
			walkTo(record, victimRoot.Position, false)
			if (victimRoot.Position - root.Position).Magnitude <= SETTINGS.Bonk.Range then
				face(record, victimRoot.Position)
				playAnim(record, "Slash")
				Services.MiningService:NpcBonk(root, record.Name, chase, defendId)
				record.ChaseTarget = nil
				record.Defending = nil
				record.NextBonk = t + SETTINGS.Bonk.Cooldown
			end
		end
		return
	end

	-- 🌙 Thief Night: sneak into a player's home and grab a pet from display
	if workspace:GetAttribute("RaidActive") == true and record.HomeIndex then
		if not record.RaidPlan and (record.RaidsTonight or 0) < SETTINGS.RaidsPerNight and rng:NextNumber() < SETTINGS.RaidChance then
			record.RaidPlan = homes:RaidTarget(record)
		end
		local plan = record.RaidPlan
		if plan then
			if not plan.Owner.Parent or plan.Pet.Away then
				record.RaidPlan = nil
			else
				record.Task = "Raid"
				walkTo(record, plan.Position)
				if (flat(plan.Position - root.Position)).Magnitude <= 6 then
					face(record, plan.Position)
					local item, meta = homes:TakeFromPlayer(record, plan.Owner, plan.Pet.Id)
					record.RaidPlan = nil
					record.RaidsTonight = (record.RaidsTonight or 0) + 1
					if item then
						setCarry(record, item, meta)
					end
				end
				return
			end
		end
	else
		record.RaidPlan = nil
		record.RaidsTonight = 0
	end

	-- 3) a meteor is coming / being smashed: go there and smash it
	if current and (state == "Warning" or state == "Falling" or state == "Active") then
		record.Task = "Meteor"
		local radius = current.Size.Radius
		local angle = record.Index * 2.4 + 0.6
		local spot = current.Position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * (radius + 3)
		local close = (flat(root.Position) - flat(current.Position)).Magnitude <= radius + 7
		if close and state == "Active" then
			stop(record)
			face(record, current.Position)
			if t >= record.NextHit then
				local damage, cooldown = rivalPace()
				record.NextHit = t + cooldown * rng:NextNumber(0.85, 1.2)
				playAnim(record, "Slash")
				meteor:Hit(record.Entity, damage, cooldown)
			end
		else
			walkTo(record, spot)
		end
		return
	end

	-- 4) star eggs nobody picked up: go get one
	local target = record.TargetEgg
	if target and not shards:IsOnGround(target) then
		target = nil
	end
	if not target then
		local taken = {}
		for _, other in rivals do
			if other ~= record and other.TargetEgg then
				taken[other.TargetEgg] = true
			end
		end
		local best, bestDistance = nil, SETTINGS.SearchRange
		for _, entry in shards:RivalTargets(record.Entity.UserId, SETTINGS.GrabDelay) do
			if not taken[entry.Model] and not Util.InBases(Config, entry.Position + Vector3.new(0, 3, 0)) then
				local distance = (flat(entry.Position) - flat(root.Position)).Magnitude
				if distance < bestDistance then
					best, bestDistance = entry.Model, distance
				end
			end
		end
		target = best
	end
	record.TargetEgg = target
	if target then
		local position = shards:GroundPosition(target)
		if position then
			record.Task = "Egg"
			walkTo(record, position, false)
			if (flat(position) - flat(root.Position)).Magnitude <= SETTINGS.GrabRange then
				local item = shards:TakeForRival(target)
				record.TargetEgg = nil
				if item then
					setCarry(record, item)
				end
			end
			return
		end
	end

	-- 5) between meteors: mine for a while, sometimes hang around the hub
	if t >= record.NextPlan then
		record.NextPlan = t + rng:NextNumber(40, 90)
		local _, _, maxZone = serverPeers()
		if rng:NextNumber() < 0.75 then
			record.Task = "Mine"
			record.MineZone = rng:NextInteger(1, math.min(maxZone, 3))
		else
			record.Task = "Hub"
			record.HubSpot = World.HubSpawn.Position + Vector3.new(rng:NextNumber(-40, 40), 0, rng:NextNumber(10, 50))
		end
		record.Ore = nil
	end
	if record.Task == "Mine" and record.MineZone then
		local ore = record.Ore
		if not ore or not ore.Parent then
			ore = Services.MiningService:NearestOreIn(record.MineZone, root.Position)
			record.Ore = ore
		end
		if not ore then
			walkTo(record, areaEntrance(record.MineZone))
			return
		end
		local reach = Config.World.Reach + ore.Size.Magnitude / 2 - 1
		if (ore.Position - root.Position).Magnitude <= reach then
			stop(record)
			face(record, ore.Position)
			if t >= record.NextHit then
				local damage = rivalPace()
				record.NextHit = t + rng:NextNumber(0.7, 1.2)
				playAnim(record, "Slash")
				Services.MiningService:NpcHit(ore, damage)
			end
		else
			walkTo(record, ore.Position)
		end
		return
	end
	walkTo(record, record.HubSpot or World.HubSpawn.Position)
end

---------------------------------------------------------------------------
-- public
---------------------------------------------------------------------------
function Rival:IsRival(model: Instance?): boolean
	return model ~= nil and rivals[model] ~= nil
end

-- the closest rival carrying an egg within range of a position
function Rival:NearestCarrying(position: Vector3, range: number): Model?
	local best, bestDistance = nil, range
	for model, record in rivals do
		if record.Carry then
			local distance = (record.Root.Position - position).Magnitude
			if distance <= bestDistance then
				best, bestDistance = model, distance
			end
		end
	end
	return best
end

-- a player swung at a rival: knock them back; if they carried an egg it drops
function Rival:Bonk(player: Player, model: Model): boolean
	local record = rivals[model]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not record or not root or not root:IsA("BasePart") then
		return false
	end
	if (root.Position - record.Root.Position).Magnitude > Config.PvP.BonkRange + 3 then
		return false
	end
	local t = now()
	if record.StunnedUntil > t then
		return false
	end
	record.StunnedUntil = t + SETTINGS.StunSeconds
	local push = flat(record.Root.Position - root.Position)
	push = if push.Magnitude > 0.1 then push.Unit else Vector3.zAxis
	record.Root.AssemblyLinearVelocity = push * 45 + Vector3.new(0, 30, 0)
	Net:Send(player, "BonkHit", record.Root.Position)
	local item = record.Carry
	local carriedMeta = record.CarryMeta
	if not item then
		return true
	end
	setCarry(record, nil)
	record.Home = nil
	-- the egg drops: the bonker gets the first grab, rivals keep off it for a while
	local firstGrab = if carriedMeta and carriedMeta.From then carriedMeta.From.UserId else player.UserId
	Services.ShardService:SpawnGround(item, flat(record.Root.Position), carriedMeta, {
		Beacon = true,
		PriorityUser = firstGrab,
		PriorityUntil = t + 4,
		RivalBlockSeconds = SETTINGS.DropBlockSeconds,
	})
	local data = Data:Get(player)
	if not data or item.RivalBonked then
		Net:Notify(
			player,
			"💥 %s dropped a %s - grab it!",
			Color3.fromRGB(255, 170, 80),
			record.Name,
			Services.ShardService.ItemName(item)
		)
		return true
	end
	-- (a reward only the first time an egg is knocked loose: no farming)
	item.RivalBonked = true
	local coins = math.max(SETTINGS.BonkMinCoins, math.floor(Services.BaseService:IncomeRate(player, data) * SETTINGS.BonkIncomeSeconds))
	data.Coins += coins
	data.Stats.LifetimeCoins += coins
	data.Stats.Bonks += 1
	Services.Analytics:Economy(player, "Source", "Coins", coins, data.Coins, "Gameplay", "RivalBonk")
	Services.ProgressionService:AddQuest(player, "Bonk", 1)
	Net:Send(player, "Sold", coins)
	Data:MarkDirty(player)
	Net:Notify(
		player,
		"💥 %s dropped a %s - grab it! +💰%s",
		Color3.fromRGB(255, 170, 80),
		record.Name,
		Services.ShardService.ItemName(item),
		Util.Format(coins)
	)
	return true
end

-- someone grabbed a pet from this rival's home: run after them
function Rival:Defend(record, thief: Player)
	if not rivals[record.Model] or record.Carry then
		return
	end
	record.ChaseTarget = thief
	record.ChaseUntil = now() + SETTINGS.DefendSeconds
	record.Defending = true
	record.RaidPlan = nil
end

function Rival:Wanted(): number
	if forcedCount then
		return forcedCount
	end
	local real = #Players:GetPlayers()
	return if real >= 1 and real <= SETTINGS.MaxRealPlayers then SETTINGS.Count else 0
end

-- cloud tests ---------------------------------------------------------------
function Rival:ForceForTest(n: number?)
	assert(not RunService:IsRunning(), "test hook used on a live server")
	forcedCount = n
end

function Rival:RecordsForTest()
	assert(not RunService:IsRunning(), "test hook used on a live server")
	local list = {}
	for _, record in rivals do
		table.insert(list, record)
	end
	table.sort(list, function(a, b)
		return a.Index < b.Index
	end)
	return list
end

function Rival:PlaceForTest(record, position: Vector3)
	assert(not RunService:IsRunning(), "test hook used on a live server")
	teleport(record, Vector3.new(position.X, 0, position.Z))
end

---------------------------------------------------------------------------
function Rival:Init(services)
	Services = services
	Data = services.DataService
	World = services.WorldService
end

function Rival:Start()
	-- rivals walk through the zone gates (they "unlocked" them); players
	-- still see and bump into the gates of zones they haven't unlocked
	pcall(function()
		PhysicsService:RegisterCollisionGroup(GROUP)
		PhysicsService:RegisterCollisionGroup(GATE_GROUP)
		PhysicsService:CollisionGroupSetCollidable(GROUP, GATE_GROUP, false)
	end)
	pcall(function()
		PhysicsService:RegisterCollisionGroup(PLAYER_GROUP)
		PhysicsService:CollisionGroupSetCollidable(GROUP, PLAYER_GROUP, false)
	end)
	local function groupCharacter(character: Model)
		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") then
				part.CollisionGroup = PLAYER_GROUP
			end
		end
		character.DescendantAdded:Connect(function(part)
			if part:IsA("BasePart") then
				part.CollisionGroup = PLAYER_GROUP
			end
		end)
	end
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(groupCharacter)
		if player.Character then
			groupCharacter(player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	for _, zone in World.Zones do
		if zone.Gate then
			zone.Gate.CollisionGroup = GATE_GROUP
			local modifier = Instance.new("PathfindingModifier")
			modifier.PassThrough = true
			modifier.Parent = zone.Gate
		end
	end

	task.spawn(function()
		while true do
			task.wait(0.25)
			local ok, err = pcall(function()
				-- join / leave (only between meteors, never while carrying)
				local wanted = self:Wanted()
				local idle = workspace:GetAttribute("MeteorState") == "Idle"
				if count() < wanted and idle then
					local used = {}
					for _, record in rivals do
						used[record.Index] = true
					end
					for index = 1, wanted do
						if not used[index] and count() < wanted and not spawning and os.clock() >= spawnRetryAt then
							-- (building an avatar downloads its items: off the brain loop)
							spawning = true
							task.spawn(function()
								local ok, err = pcall(spawnRival, index)
								spawning = false
								if not ok then
									warn("[Rival] spawn failed: " .. tostring(err))
									spawnRetryAt = os.clock() + 30
									-- (nothing half-built stays in the world)
									for _, child in workspace:GetChildren() do
										if child:IsA("Model") and child:GetAttribute("Rival") == true and not rivals[child] then
											child:Destroy()
										end
									end
								end
							end)
						end
					end
				elseif count() > wanted and idle then
					for _, record in rivals do
						if count() > wanted then
							despawn(record)
						end
					end
				end
			end)
			if not ok then
				warn("[Rival] " .. tostring(err))
			end
			for _, record in rivals do
				local okThink, errThink = pcall(think, record)
				if not okThink then
					warn("[Rival] think: " .. tostring(errThink))
				end
			end
		end
	end)
end

return Rival
