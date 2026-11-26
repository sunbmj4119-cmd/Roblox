--[[
	RivalService: 🤖 rival robots for small servers (solo play).

	With only 1-2 real players a server feels empty, so two cheeky hover
	robots join in:
	  * when a meteor warning starts they race to the landing spot,
	  * they smash the meteor too (a bit slower than a real player) and show
	    up in the live ranking - beat them for 1st place!
	  * after the burst they go for star eggs nobody has picked up yet and
	    try to fly away with them (they beam up after a few seconds),
	  * bonk a robot (swing at it) to stun it: if it carries an egg, the egg
	    drops and you get a few coins.
	They never take eggs reserved for someone (tutorial / top 3), guarded
	ones or eggs in the base district, never flee out of the area they grabbed
	the egg in (no escaping through walls / into locked zones), and leave
	once the server fills up.
	(Only the root part is anchored and moved - the rest is welded to it, so
	one CFrame per robot replicates, ~20 times a second.)
]]
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
local rivals = {} -- [model] = record
local forcedCount: number? = nil -- cloud tests
local nextId = 0

local function now(): number
	return workspace:GetServerTimeNow()
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- the walkable area around a position: the hub or one mine zone (x/z limits)
local function areaBounds(position: Vector3)
	local zone = Util.ZoneAt(Config, Vector3.new(position.X, 3, position.Z))
	local layout = Config.World.Layout
	local margin = 6
	if zone and zone > 0 and World.Zones[zone] then
		local info = World.Zones[zone]
		local half = layout.ZoneWidth / 2 - margin
		return { MinX = -half, MaxX = half, MinZ = info.ZStart + margin, MaxZ = info.ZEnd - margin }
	end
	local half = layout.HubHalf - margin
	return { MinX = -half, MaxX = half, MinZ = -half, MaxZ = half }
end

local function clampTo(bounds, position: Vector3): Vector3
	return Vector3.new(math.clamp(position.X, bounds.MinX, bounds.MaxX), position.Y, math.clamp(position.Z, bounds.MinZ, bounds.MaxZ))
end

---------------------------------------------------------------------------
-- the robot
---------------------------------------------------------------------------
local function buildRobot(name: string, color: Color3): (Model, BasePart, BasePart, TextLabel)
	local model = Instance.new("Model")
	model.Name = "RivalBot"
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2.6, 3, 2.6)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Parent = model
	local function piece(partName: string, size: Vector3, offset: CFrame, partColor: Color3, material: Enum.Material, shape)
		local p = Instance.new("Part")
		p.Name = partName
		p.Size = size
		p.CFrame = root.CFrame * offset
		p.Color = partColor
		p.Material = material
		p.Anchored = false -- welded to the anchored root (one CFrame replicates)
		p.Massless = true
		p.CanCollide = false
		p.CanQuery = false -- (only a robot carrying an egg can be tapped)
		p.CanTouch = false
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		if shape then
			p.Shape = shape
		end
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = p
		weld.Parent = p
		p.Parent = model
		return p
	end
	piece("Body", Vector3.new(2.4, 1.9, 2), CFrame.new(0, 0, 0), color, Enum.Material.SmoothPlastic)
	piece("Head", Vector3.one * 2, CFrame.new(0, 1.55, 0), Color3.fromRGB(225, 230, 240), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	piece("Visor", Vector3.new(1.5, 0.5, 0.3), CFrame.new(0, 1.6, -0.85), Color3.fromRGB(40, 45, 60), Enum.Material.SmoothPlastic)
	for _, x in { -0.35, 0.35 } do
		piece("Eye", Vector3.new(0.28, 0.28, 0.1), CFrame.new(x, 1.62, -1.02), Color3.fromRGB(120, 255, 230), Enum.Material.Neon)
	end
	piece("Antenna", Vector3.new(0.12, 0.9, 0.12), CFrame.new(0, 2.85, 0), Color3.fromRGB(90, 95, 110), Enum.Material.Metal)
	piece("AntennaTip", Vector3.one * 0.38, CFrame.new(0, 3.35, 0), color, Enum.Material.Neon, Enum.PartType.Ball)
	for _, x in { -1.45, 1.45 } do
		piece(
			"Arm",
			Vector3.new(0.45, 1.2, 0.45),
			CFrame.new(x, -0.1, 0) * CFrame.Angles(0, 0, math.rad(x * 12)),
			color,
			Enum.Material.SmoothPlastic
		)
	end
	local ring = piece(
		"Hover",
		Vector3.new(0.2, 2.6, 2.6),
		CFrame.new(0, -1.3, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(120, 230, 255),
		Enum.Material.Neon,
		Enum.PartType.Cylinder
	)
	ring.Transparency = 0.45
	local egg = piece(
		"CarriedEgg",
		Vector3.new(1.2, 1.5, 1.2),
		CFrame.new(0, 4.3, 0),
		Color3.new(1, 1, 1),
		Enum.Material.SmoothPlastic,
		Enum.PartType.Ball
	)
	egg.Transparency = 1
	model.PrimaryPart = root

	local gui = Instance.new("BillboardGui")
	gui.Name = "Tag"
	gui.Size = UDim2.new(7, 0, 1.4, 0)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 4.2, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 140
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = Color3.fromRGB(150, 235, 255)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = text
	text.Parent = gui
	gui.Parent = root
	World.SetText(text, "🤖 %s", name)
	return model, root, egg, text
end

local function spawnRival(index: number)
	nextId += 1
	local name = SETTINGS.Names[((nextId - 1) % #SETTINGS.Names) + 1]
	local color = SETTINGS.Colors[((nextId - 1) % #SETTINGS.Colors) + 1]
	local model, root, egg, tag = buildRobot(name, color)
	local dock = SETTINGS.Dock + Vector3.new((index - 1.5) * 6, 0, 0)
	local record = {
		Model = model,
		Root = root,
		Egg = egg,
		Tag = tag,
		Name = name,
		Index = index,
		Position = Vector3.new(dock.X, SETTINGS.HoverY, dock.Z),
		Facing = -Vector3.zAxis,
		Destination = dock,
		Dock = dock,
		Speed = SETTINGS.Speed,
		StunnedUntil = 0,
		NextHit = 0,
		Carry = nil,
		CarryUntil = 0,
		TargetEgg = nil,
		-- identity in the meteor ranking (looks enough like a player there)
		-- (ids far below Studio's test players -1, -2, ...)
		Entity = { DisplayName = "🤖 " .. name, Name = name, UserId = -1000000 - nextId, Parent = workspace, IsRival = true },
	}
	root.CFrame = CFrame.new(record.Position)
	model.Parent = World:Folder("Shards")
	rivals[model] = record
	return record
end

local function despawn(record)
	rivals[record.Model] = nil
	if record.Carry then
		-- (never take an egg with you when leaving: drop it)
		local spot = clampTo(areaBounds(record.GrabSpot or record.Position), flat(record.Position))
		Services.ShardService:SpawnGround(record.Carry, spot, nil, { Beacon = true, RivalBlockSeconds = 20 })
		record.Carry = nil
	end
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

local function setCarry(record, item)
	record.Carry = item
	if item then
		record.Egg.Color = Services.ShardService.ItemColor(item)
		record.Egg.Transparency = 0
		record.CarryUntil = now() + SETTINGS.EscapeSeconds
		record.Model:SetAttribute("Carrying", true)
		World.SetText(record.Tag, "🤖 %s 🥚!", record.Name)
	else
		record.Egg.Transparency = 1
		record.Model:SetAttribute("Carrying", nil)
		World.SetText(record.Tag, "🤖 %s", record.Name)
	end
	-- taps go through robots unless they carry an egg (then: bonk it!)
	for _, part in record.Model:GetDescendants() do
		if part:IsA("BasePart") and part ~= record.Root then
			part.CanQuery = item ~= nil and part.Transparency < 1
		end
	end
end

---------------------------------------------------------------------------
-- brains
---------------------------------------------------------------------------
-- how a robot smashes: a bit slower than the average real player here
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

local function nearestRealPlayer(position: Vector3): (Player?, number)
	local best, bestDistance = nil, math.huge
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local distance = (flat(root.Position) - flat(position)).Magnitude
			if distance < bestDistance then
				best, bestDistance = player, distance
			end
		end
	end
	return best, bestDistance
end

local function think(record)
	local t = now()
	if record.StunnedUntil > t then
		record.Destination = flat(record.Position)
		return
	end
	local meteor = Services.MeteorService
	local current = meteor:Current()
	local state = workspace:GetAttribute("MeteorState")

	-- 1) carrying an egg: fly away from the closest player, beam up in time
	if record.Carry then
		if t >= record.CarryUntil then
			local item = record.Carry
			setCarry(record, nil)
			Net:Broadcast("RivalEscape", record.Position)
			Net:Announce(
				"🤖 %s flew away with a %s! Bonk robots before they escape!",
				Color3.fromRGB(150, 235, 255),
				record.Name,
				Services.ShardService.ItemName(item)
			)
			record.Destination = record.Dock
			return
		end
		local player = nearestRealPlayer(record.Position)
		local away = -Vector3.zAxis
		if player and player.Character and player.Character.PrimaryPart then
			local diff = flat(record.Position - player.Character.PrimaryPart.Position)
			if diff.Magnitude > 0.5 then
				away = diff.Unit
			end
		end
		-- stay in the area where it grabbed the egg (slides along walls,
		-- never through gates into locked zones / out over the void)
		local bounds = areaBounds(record.GrabSpot or record.Position)
		local destination = clampTo(bounds, flat(record.Position) + away * 20)
		if Util.InBases(Config, destination + Vector3.new(0, 3, 0)) then
			destination = flat(record.GrabSpot or record.Dock)
		end
		record.Destination = destination
		record.Speed = SETTINGS.CarrySpeed
		return
	end
	record.Speed = SETTINGS.Speed

	-- 2) a meteor is coming / being smashed: go there and help... themselves
	if current and (state == "Warning" or state == "Falling" or state == "Active") then
		local radius = current.Size.Radius
		local angle = record.Index * 2.4 + 0.6
		local spot = current.Position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * (radius + 3.5)
		record.Destination = spot
		if state == "Active" and (flat(record.Position) - flat(current.Position)).Magnitude <= radius + 7 and t >= record.NextHit then
			local damage, cooldown = rivalPace()
			record.NextHit = t + cooldown
			meteor:Hit(record.Entity, damage, cooldown)
			record.Bob = 0.25
		end
		return
	end

	-- 3) star eggs nobody picked up: go get one
	local shards = Services.ShardService
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
				local distance = (flat(entry.Position) - flat(record.Position)).Magnitude
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
			record.Destination = flat(position)
			if (flat(position) - flat(record.Position)).Magnitude <= SETTINGS.GrabRange then
				local item = shards:TakeForRival(target)
				record.TargetEgg = nil
				if item then
					record.GrabSpot = flat(position)
					setCarry(record, item)
				end
			end
			return
		end
	end

	-- 4) nothing to do: hover at the dock in the hub
	record.Destination = record.Dock
end

local function move(record, dt: number)
	local target = Vector3.new(record.Destination.X, SETTINGS.HoverY, record.Destination.Z)
	local diff = flat(target - record.Position)
	local distance = diff.Magnitude
	local stunned = record.StunnedUntil > now()
	local moved = false
	if distance > 0.3 and not stunned then
		local step = math.min(distance, record.Speed * dt)
		record.Facing = diff.Unit
		record.Position += record.Facing * step
		moved = true
	end
	local dip = 0
	if record.Bob and record.Bob > 0 then
		record.Bob -= dt
		dip = -0.4 -- a little "smash" dip
		moved = true
	end
	if not moved and not stunned and not record.Dirty then
		return -- hovering still: nothing to send
	end
	record.Dirty = stunned or dip ~= 0 -- (one more update after a wobble / dip)
	local at = Vector3.new(record.Position.X, SETTINGS.HoverY + dip, record.Position.Z)
	local cf = CFrame.lookAt(at, at + record.Facing)
	if stunned then
		cf *= CFrame.Angles(0, 0, math.sin(os.clock() * 20) * 0.25) -- dizzy
	end
	record.Root.CFrame = cf
end

---------------------------------------------------------------------------
-- public
---------------------------------------------------------------------------
function Rival:IsRival(model: Instance?): boolean
	return model ~= nil and rivals[model] ~= nil
end

-- the closest robot carrying an egg within range of a position
function Rival:NearestCarrying(position: Vector3, range: number): Model?
	local best, bestDistance = nil, range
	for model, record in rivals do
		if record.Carry then
			local distance = (record.Position - position).Magnitude
			if distance <= bestDistance then
				best, bestDistance = model, distance
			end
		end
	end
	return best
end

-- a player swung at a robot: stun it; if it carried an egg, the egg drops
function Rival:Bonk(player: Player, model: Model): boolean
	local record = rivals[model]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not record or not root or not root:IsA("BasePart") then
		return false
	end
	if (root.Position - record.Position).Magnitude > Config.PvP.BonkRange + 3 then
		return false
	end
	local t = now()
	if record.StunnedUntil > t then
		return false
	end
	record.StunnedUntil = t + SETTINGS.StunSeconds
	local push = flat(record.Position - root.Position)
	push = if push.Magnitude > 0.1 then push.Unit else Vector3.zAxis
	local pushed = clampTo(areaBounds(record.GrabSpot or record.Position), record.Position + push * 5)
	record.Position = Vector3.new(pushed.X, record.Position.Y, pushed.Z)
	Net:Send(player, "BonkHit", record.Position)
	local item = record.Carry
	if not item then
		Net:Notify(player, "💥 %s is dizzy!", Color3.fromRGB(150, 235, 255), record.Name)
		return true
	end
	setCarry(record, nil)
	-- the egg drops: the bonker gets the first grab, robots keep off it for a while
	Services.ShardService:SpawnGround(item, flat(record.Position), nil, {
		Beacon = true,
		PriorityUser = player.UserId,
		PriorityUntil = t + 4,
		RivalBlockSeconds = SETTINGS.DropBlockSeconds,
	})
	-- reward only the first time an egg is knocked off a robot (no farming)
	local data = Data:Get(player)
	if not data or item.RivalBonked then
		Net:Notify(player, "💥 You bonked %s! It dropped the egg - grab it!", Color3.fromRGB(150, 235, 255), record.Name)
		return true
	end
	item.RivalBonked = true
	local coins = math.max(SETTINGS.BonkMinCoins, math.floor(Services.BaseService:IncomeRate(player, data) * SETTINGS.BonkIncomeSeconds))
	data.Coins += coins
	data.Stats.LifetimeCoins += coins
	data.Stats.ThievesCaught = (data.Stats.ThievesCaught or 0) + 1
	Services.Analytics:Economy(player, "Source", "Coins", coins, data.Coins, "Gameplay", "RivalBonk")
	Net:Send(player, "Sold", coins)
	Data:MarkDirty(player)
	Net:Notify(
		player,
		"💥 You bonked %s! It dropped the egg - grab it! +💰%s",
		Color3.fromRGB(150, 235, 255),
		record.Name,
		Util.Format(coins)
	)
	return true
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
	record.Position = Vector3.new(position.X, SETTINGS.HoverY, position.Z)
	record.Root.CFrame = CFrame.new(record.Position)
end

---------------------------------------------------------------------------
function Rival:Init(services)
	Services = services
	Data = services.DataService
	World = services.WorldService
end

function Rival:Start()
	-- decisions 4x a second
	task.spawn(function()
		while true do
			task.wait(0.25)
			local ok, err = pcall(function()
				-- join / leave (only between meteors, never while carrying)
				local wanted = self:Wanted()
				local idle = workspace:GetAttribute("MeteorState") == "Idle"
				if count() < wanted and idle then
					if count() == 0 then
						Net:Announce(
							"🤖 Rival robots are here! Beat them to the meteor - and don't let them fly off with your eggs!",
							Color3.fromRGB(150, 235, 255)
						)
					end
					local used = {}
					for _, record in rivals do
						used[record.Index] = true
					end
					for index = 1, wanted do
						if not used[index] and count() < wanted then
							spawnRival(index)
						end
					end
				elseif count() > wanted and idle then
					for _, record in rivals do
						if count() > wanted then
							despawn(record)
						end
					end
				end
				for _, record in rivals do
					think(record)
				end
			end)
			if not ok then
				warn("[Rival] " .. tostring(err))
			end
		end
	end)
	-- movement ~20 times a second (only while robots exist, only when they move)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		if next(rivals) == nil then
			return
		end
		acc += dt
		if acc < 0.05 then
			return
		end
		local step = acc
		acc = 0
		for _, record in rivals do
			local ok, err = pcall(move, record, step)
			if not ok then
				warn("[Rival] move: " .. tostring(err))
			end
		end
	end)
end

return Rival
