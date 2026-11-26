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
local PetModel = require(Shared.PetModel)
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

--[[ carried / dropped items:
	{ Kind = "Egg", Rarity = "Rare", Egg = "Meadow" }  -- a star egg (hatches at home)
	{ Kind = "Pet", Name = "Fox", Variant = "Golden"? } -- a stolen pet ]]
local function itemName(item): string
	if item.Kind == "Pet" then
		return item.Name -- plain species name: translates on every client
	end
	return rarityName(item.Rarity)
end

local function itemColor(item): Color3
	if item.Kind == "Pet" then
		local info = Config.Pets[item.Name]
		local rarity = info and Config.Rarities[info.Rarity]
		return if rarity then rarity.Color else Color3.new(1, 1, 1)
	end
	local def = SETTINGS.Rarities[item.Rarity]
	return if def then def.Color else Color3.new(1, 1, 1)
end

-- 1..7: how valuable the item is (speed penalty, guardian, points)
local function itemTier(item): number
	if item.Kind == "Pet" then
		local info = Config.Pets[item.Name]
		local rarity = info and Config.Rarities[info.Rarity]
		return if rarity then rarity.Order else 1
	end
	return Util.ShardIndex(Config, item.Rarity)
end

local function buildItemModel(item, scale: number): Model
	if item.Kind == "Pet" then
		return PetModel.Build(item.Name, item.Variant)
	end
	return ShardModel.Build(Config, item.Rarity, scale)
end

---------------------------------------------------------------------------
-- carrying
---------------------------------------------------------------------------
-- the theft record of whatever the player carries (nil = nothing / not stolen)
function Shards:CarryMeta(player: Player)
	local info = carrying[player]
	return info and info.Meta or nil
end

function Shards:IsCarrying(player: Player): boolean
	return carrying[player] ~= nil
end

-- walk speed multiplier while carrying (heavier = rarer = slower)
function Shards:SpeedMult(player: Player): number
	local info = carrying[player]
	if not info then
		return 1
	end
	local mult = 0.95 - itemTier(info.Item) * 0.045 -- 0.9 (common) .. 0.64 (secret)
	if Services.MonetizationService:HasPass(player, "FastCarry") then
		mult *= Config.PvP.CarrySpeedPass
	end
	return mult
end

local function attachModel(player: Player, item): Model?
	local root = rootOf(player)
	if not root then
		return nil
	end
	local model = buildItemModel(item, 0.8)
	model.Name = "CarriedShard"
	-- weld every part to the main one so the whole model rides along
	local primary = model.PrimaryPart :: BasePart
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= primary then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = primary
			weld.Part1 = d
			weld.Parent = d
			d.Massless = true
		end
	end
	primary.Massless = true
	ShardModel.SetAnchored(model, false)
	model:PivotTo(root.CFrame * CFrame.new(0, 5.2, 0))
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = model.PrimaryPart
	weld.Parent = model.PrimaryPart
	local highlight = Instance.new("Highlight")
	highlight.Name = "CarrierGlow"
	highlight.FillTransparency = 1
	highlight.OutlineColor = itemColor(item)
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
	player:SetAttribute("CarryTier", nil)
	player:SetAttribute("CarryStolen", nil)
	Services.CharacterService:ApplyWalkSpeed(player)
	return info
end

function Shards:StartCarry(player: Player, item, meta)
	if carrying[player] or type(item) ~= "table" then
		return false
	end
	local model = attachModel(player, item)
	if not model then
		return false
	end
	carrying[player] = { Item = item, Meta = meta or {}, Model = model }
	player:SetAttribute("Carrying", itemName(item))
	player:SetAttribute("CarryTier", itemTier(item))
	player:SetAttribute("CarryStolen", meta ~= nil and meta.From ~= nil)
	Services.CharacterService:ApplyWalkSpeed(player)
	local fromName = if meta and meta.From then meta.From.DisplayName else nil
	Net:Send(player, "CarryStart", itemName(item), fromName, itemTier(item))
	return true
end

-- a stolen pet runs back to the base it was taken from
local function returnHome(meta, message: boolean)
	local owner = meta and meta.From
	if not owner or not owner.Parent or not meta.PetId then
		return
	end
	Services.BaseService:SetAway(owner, meta.PetId, false)
	if message then
		Net:Notify(owner, "🛡️ Your pet ran back home!", Color3.fromRGB(120, 230, 255))
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

local function spawnGuardian(item, home: Vector3)
	local index = itemTier(item)
	local model, root = buildGuardian(itemColor(item))
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
		Item = item,
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
function Shards:SpawnGround(item, position: Vector3, meta, opts)
	opts = opts or {}
	local color = itemColor(item)
	local model = buildItemModel(item, 1.15)
	model.Name = if item.Kind == "Pet" then "Shard_Pet" else "Shard_" .. item.Rarity
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
		local index = itemTier(item)
		local beacon = Instance.new("Part")
		beacon.Name = "Beacon"
		beacon.Shape = Enum.PartType.Cylinder
		beacon.Size = Vector3.new(180, 1 + index * 0.5, 1 + index * 0.5)
		beacon.CFrame = CFrame.new(position + Vector3.new(0, 90, 0)) * CFrame.Angles(0, 0, math.rad(90))
		beacon.Color = color
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
	text.TextColor3 = color
	World.SetText(text, if meta and meta.From then "⚠️ %s" else "🌠 %s", itemName(item))
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Parent = text
	text.Parent = label
	label.Parent = model.PrimaryPart

	model.Parent = World:Folder("Shards")
	local record = {
		Item = item,
		Meta = meta,
		PriorityUser = opts.PriorityUser,
		PriorityUntil = opts.PriorityUntil or 0,
		BlockUser = opts.BlockUser,
		BlockUntil = opts.BlockUntil or 0,
	}
	ground[model] = record
	if opts.Guardian then
		record.Guardian = opts.Guardian
	elseif opts.WithGuardian and itemTier(item) >= GUARDIAN.MinRarity then
		record.Guardian = spawnGuardian(item, position)
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
	-- the owner of a stolen pet gets it back instantly
	if meta and meta.From == player then
		destroyGround(model)
		Services.BaseService:SetAway(player, meta.PetId, false)
		Net:Notify(player, "🛡️ You got your %s back!", Color3.fromRGB(120, 230, 255), itemName(record.Item))
		Net:Send(player, "ShardRecovered", itemName(record.Item))
		return
	end
	if not Services.BaseService:HasBase(player) then
		Net:Notify(player, "All bases are taken - you'll get one when someone leaves.")
		return
	end
	-- start carrying first; only then remove it from the ground (if carrying
	-- fails, e.g. no character yet, the item simply stays where it is)
	ground[model] = nil
	if not Shards:StartCarry(player, record.Item, meta) then
		ground[model] = record
		return
	end
	destroyGround(model)
	Services.ProgressionService:TutorialEvent(player, "Grab", 1)
	if record.Guardian then
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
	Net:Send(player, "CarryLost", itemName(info.Item), owner.DisplayName)
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
	self:SpawnGround(info.Item, spot, meta, {
		Beacon = true,
		BlockUser = player.UserId,
		BlockUntil = now() + SETTINGS.RegrabDelay,
	})
	Net:Send(player, "CarryLost", itemName(info.Item), if attacker then attacker.DisplayName else nil)
	if attacker then
		Net:Notify(attacker, "💥 %s dropped a %s - grab it!", Color3.fromRGB(255, 170, 80), player.DisplayName, itemName(info.Item))
	end
end

---------------------------------------------------------------------------
-- delivery
---------------------------------------------------------------------------
local nightBonusPaid = {} -- ["thief:owner"] = os.clock() (no passing one pet back and forth)
local function deliver(player: Player)
	local info = endCarry(player)
	if not info then
		return
	end
	local item = info.Item
	local meta = info.Meta
	local data = Data:Get(player)
	local tier = itemTier(item)
	local pets = Services.PetService
	if item.Kind == "Pet" then
		-- a stolen pet: it leaves the owner's base and joins ours
		local owner = meta and meta.From
		local taken = owner and owner.Parent and meta.PetId and pets:TakePet(owner, meta.PetId)
		if not taken then
			Net:Notify(player, "The owner left - the pet vanished!")
			return
		end
		local given, isNew = pets:GivePet(player, taken.Name, taken.Variant, taken.Serial)
		-- a freshly stolen pet can't hide in the thief's vault yet: revenge can win it back
		if given and not (meta.Revenge and meta.Thief == player) then
			given.HotUntil = os.time() + Config.Base.HotSeconds
		end
		-- save both right away so a crash can't leave the pet in two places
		task.spawn(Data.Save, Data, owner)
		task.spawn(Data.Save, Data, player)
		-- theft shield for the victim, revenge window, bounty on serial thieves
		Services.BaseService:StealDelivered(owner, player, meta, taken)
		-- 🌙 Thief Night: delivered steals pay a bonus
		local bonusSeconds = Services.EventService:Get("StealBonus", 0)
		local pairKey = player.UserId .. ":" .. owner.UserId
		local repeatPair = os.clock() - (nightBonusPaid[pairKey] or -1e9) < 600
		if bonusSeconds > 0 and data and not meta.Revenge and not repeatPair then
			nightBonusPaid[pairKey] = os.clock()
			local bonus = math.floor(Util.PetIncome(Config, taken.Name, taken.Variant) * bonusSeconds)
			if bonus > 0 then
				data.Coins += bonus
				data.Stats.LifetimeCoins += bonus
				Net:Send(player, "Sold", bonus)
				Net:Notify(player, "🌙 Thief Night bonus: +💰%s!", Color3.fromRGB(170, 140, 255), Util.Format(bonus))
			end
		end
		local display = taken.Name
		Net:Notify(owner, "💔 %s stole your %s!", Color3.fromRGB(255, 90, 90), player.DisplayName, display)
		if data then
			data.Stats.ShardsStolen += 1
		end
		Services.ProgressionService:AddQuest(player, "Steal", 1)
		Services.Analytics:Custom(player, "PetStolen", tier)
		Net:Send(player, "ShardDelivered", display, "Stolen", 0)
		-- the same "where did it go" card as a hatch (no egg)
		local card = given and pets:Describe(player, given, isNew)
		if card then
			card.Stolen = true
			Net:Send(player, "HatchResult", { card }, nil, "Stolen")
		end
		if tier >= 5 then
			Net:Announce("🦹 %s stole a %s from %s!", itemColor(item), player.DisplayName, display, owner.DisplayName)
		end
	else
		-- a star egg: it hatches right here
		local def = SETTINGS.Rarities[item.Rarity]
		local result = pets:HatchStarEgg(player, item.Egg, if def then def.Luck or 1 else 1)
		if data then
			data.Stats.ShardsDelivered = (data.Stats.ShardsDelivered or 0) + 1
		end
		Services.Analytics:Custom(player, "StarEggHatched", tier)
		Net:Send(player, "ShardDelivered", rarityName(item.Rarity), "Hatched", 0, result and result.Name)
		if tier >= 4 then
			Net:Announce("🌟 %s brought a %s home!", itemColor(item), player.DisplayName, rarityName(item.Rarity))
		end
	end
	Services.ProgressionService:AddQuest(player, "Shard", 1)
	Services.ProgressionService:TutorialEvent(player, "Shard", 1)
	Services.ProgressionService:AddPoints(player, SETTINGS.Points[math.clamp(tier, 1, #SETTINGS.Points)] or 10)
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
	local item = { Kind = "Egg", Rarity = id, Egg = SETTINGS.ZoneEggs[math.max(zone, 1)] or "Meadow" }
	local flight = 1.8
	Net:Broadcast("StarFall", position, id, flight)
	task.delay(flight, function()
		self:SpawnGround(item, position, nil, { Beacon = true, WithGuardian = true })
		local where = if zone == 0 then "Hub" else Config.Zones[zone].Name
		Net:Announce("🌠 A falling star crashed in %s! Grab the %s!", SETTINGS.Rarities[id].Color, where, rarityName(id))
	end)
	return id
end

-- tutorial: a guaranteed star egg just for this player (popped out of their
-- tutorial meteor at `position`, or falling into the hub after a rejoin)
local tutorialStars = {} -- [player] = ground model
function Shards:TutorialStar(player: Player, position: Vector3?)
	local existing = tutorialStars[player]
	if existing and existing.Parent then
		return
	end
	if carrying[player] then
		return
	end
	local function spawn(at: Vector3)
		tutorialStars[player] = self:SpawnGround({ Kind = "Egg", Rarity = "Rare", Egg = "Meadow" }, at, nil, {
			Beacon = true,
			PriorityUser = player.UserId,
			PriorityUntil = now() + 600,
			Lifetime = 900,
		})
	end
	if position then
		spawn(position)
		Net:Notify(player, "🥚 A star egg popped out! Grab it!", Color3.fromRGB(120, 230, 255))
		return
	end
	local spot = Config.Meteor.Tutorial.Position + Vector3.new(rng:NextNumber(-4, 4), 0, rng:NextNumber(-4, 4))
	local flight = 1.6
	Net:Send(player, "StarFall", spot, "Rare", flight)
	task.delay(flight, function()
		if not player.Parent then
			return
		end
		spawn(spot)
		Net:Notify(player, "🌠 A star fell just for you! Grab it!", Color3.fromRGB(120, 230, 255))
	end)
end

-- ☄️ the meteor bursts: star eggs of its kind scatter around the crater.
-- ranking = { { Player = p, Score = n }, ... } best first
-- info = { Egg = "Lava", Luck = 2.5, Extra = 0..3, Narrow = avenue? } (from MeteorService)
function Shards:SpillMeteor(position: Vector3, ranking, info)
	info = info or {}
	local spill = Config.Meteor.Spill
	local count = math.min(spill.Base + spill.PerParticipant * #ranking, spill.Max) + (info.Extra or 0)
	count = math.max(count, 1)
	local egg = info.Egg or "Cosmic"
	local luck = info.Luck or spill.Luck
	local priority = SETTINGS.Meteor.TopPriority
	-- roll everything first: the top 3 get one reserved egg each (1st: Epic+)
	local eggs = {}
	for i = 1, count do
		local reserved = ranking[i] and i <= 3 and ranking[i].Player or nil
		local id = Util.RollShard(Config, luck, rng, if i == 1 and reserved then 3 else nil)
		table.insert(eggs, { Id = id, Tier = Util.ShardIndex(Config, id), Reserved = reserved, Place = i })
	end
	-- the best eggs are guarded by meteor golems
	local order = table.clone(eggs)
	table.sort(order, function(a, b)
		return a.Tier > b.Tier
	end)
	for i = 1, math.min(spill.Guardians, #order) do
		order[i].Guardian = true
	end
	for i, entry in eggs do
		local angle = (i / count) * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local radius = rng:NextNumber(11, 19)
		local dx, dz = math.cos(angle) * radius, math.sin(angle) * radius
		if info.Narrow then
			-- (on the avenue: spread along the street, not into people's gardens)
			dx, dz = math.cos(angle) * (radius + 5), math.sin(angle) * rng:NextNumber(3, 10)
		end
		local spot = Vector3.new(position.X + dx, 0, position.Z + dz)
		local opts = { Beacon = true, WithGuardian = entry.Guardian }
		if entry.Reserved then
			opts.PriorityUser = entry.Reserved.UserId
			opts.PriorityUntil = now() + (if entry.Place == 1 then priority else priority - 1)
		end
		self:SpawnGround({ Kind = "Egg", Rarity = entry.Id, Egg = egg }, spot, nil, opts)
		if entry.Reserved then
			local medal = ({ "🥇", "🥈", "🥉" })[entry.Place]
			Net:Notify(entry.Reserved, "%s Your %s is waiting - grab it first!", Color3.fromRGB(255, 220, 90), medal, rarityName(entry.Id))
		end
	end
	return eggs
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
						local caughtItem = info.Item
						endCarry(target)
						Services.CharacterService:Stun(target, 1.2)
						local push = (root.Position - g.Position) * Vector3.new(1, 0, 1)
						push = if push.Magnitude > 0.01 then push.Unit else Vector3.zAxis
						Net:Send(target, "Knockback", push * 45 + Vector3.new(0, 30, 0))
						Net:Send(target, "CaughtByGuardian", itemName(caughtItem))
						g.Target = nil
						g.Done = false
						Shards:SpawnGround(caughtItem, g.Home, nil, {
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
			elseif info.Meta and info.Meta.Deadline and os.clock() > info.Meta.Deadline then
				-- held too long: the stolen pet escapes back home
				endCarry(player)
				returnHome(info.Meta, true)
				Net:Notify(player, "⏰ Too slow - the pet ran back home!", Color3.fromRGB(255, 150, 90))
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
			local mult = math.max(1, Services.EventService:Get("StarMult", 1))
			task.wait(rng:NextNumber(star.MinInterval, star.MaxInterval) / mult)
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
