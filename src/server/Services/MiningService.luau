--[[
	MiningService: ore blocks (spawn / damage / respawn), the pickaxe swing
	handler (server-authoritative range + cooldown checks). Broken ore pays
	coins instantly (no backpack, no selling). Players carrying a star shard
	can be bonked to make them drop it.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Net = require(script.Parent.Net)

local Mining = {}
local Services
local Data
local World

local blockInfo = {} -- [part] = { Slot, Ore, HP, Zone }
local zoneBlocks = {} -- [zone] = { [part] = true }
local lastSwing = {} -- [player] = os.clock()
local immunity = {} -- [player] = os.clock() until
local combos = {} -- [player] = { Count, Last }
local feverUntil = {} -- [player] = server time
local feverStart = {} -- [player] = server time
local lastWarn = {} -- [player] = os.clock() (throttles hint messages)
local oreFolder: Folder

local oreRng = Random.new()

local function pickOre(zoneIndex: number): string
	return Util.WeightedPick(Config.Zones[zoneIndex].Ores, nil, oreRng)
end

local function rollLucky()
	local mult = Services.EventService:Get("LuckyMult", 1)
	for _, def in Config.LuckyOres do
		if oreRng:NextNumber() < def.Chance * mult then
			return def
		end
	end
	return nil
end

local function addSparkles(part: BasePart, color: Color3, rate: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Sparkles"
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.6, 1.2)
	emitter.Speed = NumberRange.new(1, 3)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = rate
	emitter.Parent = part
end

-- small crystal spikes on top of rare ores so they read as "valuable" at a glance
local function addCrystals(part: BasePart, color: Color3, material: Enum.Material)
	local size = Config.World.OreSize
	for i = 1, 3 do
		local spike = Instance.new("Part")
		spike.Name = "Crystal"
		spike.Anchored = true
		spike.CanCollide = false
		spike.CanQuery = false
		spike.CanTouch = false
		spike.CastShadow = false
		spike.Material = material
		spike.Color = color
		spike.Size = Vector3.new(0.9, 2 + i * 0.5, 0.9)
		local angle = i * 2.1
		spike.CFrame = part.CFrame
			* CFrame.new(math.cos(angle) * size * 0.22, size / 2 + spike.Size.Y * 0.35, math.sin(angle) * size * 0.22)
			* CFrame.Angles(math.rad(18) * math.cos(angle), 0, math.rad(18) * math.sin(angle))
		spike.Parent = part
	end
end

-- rock chunks around the base + ore "veins" so blocks read as rocks, not cubes
local function decorate(part: BasePart, ore, size: number)
	local function chunk(cf: CFrame, chunkSize: Vector3, color: Color3, material: Enum.Material, name: string)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Size = chunkSize
		p.CFrame = cf
		p.Color = color
		p.Material = material
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = part
	end
	local dark = part.Color:Lerp(Color3.new(0, 0, 0), 0.3)
	local base = part.CFrame
	chunk(
		base * CFrame.new(size * 0.42, -size * 0.28, size * 0.36) * CFrame.Angles(0.3, oreRng:NextNumber(0, 3), 0.2),
		Vector3.new(size * 0.5, size * 0.42, size * 0.48),
		dark,
		part.Material,
		"Rock"
	)
	chunk(
		base * CFrame.new(-size * 0.4, -size * 0.3, -size * 0.34) * CFrame.Angles(-0.2, oreRng:NextNumber(0, 3), 0.3),
		Vector3.new(size * 0.44, size * 0.38, size * 0.42),
		dark,
		part.Material,
		"Rock"
	)
	if ore.Value >= 2 then
		local vein = part.Color:Lerp(Color3.new(1, 1, 1), 0.2)
		local material = if ore.Glow then Enum.Material.Neon else part.Material
		for i = 1, 2 do
			local side = if i == 1 then 1 else -1
			chunk(
				base * CFrame.new(side * size * 0.5, size * (0.05 + i * 0.12), side * size * 0.12) * CFrame.Angles(0.6, 0.7 * i, 0.4),
				Vector3.new(1.1, 1.1, 1.1) * (0.8 + i * 0.25),
				vein,
				material,
				"Vein"
			)
		end
	end
end

local function spawnBlock(slot, forcedLucky)
	if slot.Part and slot.Part.Parent then
		return
	end
	local oreId = pickOre(slot.Zone)
	local ore = Config.Ores[oreId]
	local lucky = forcedLucky or rollLucky()
	local hp = ore.HP * (if lucky then lucky.HPMult or 1 else 1)
	local size = Config.World.OreSize
	local part = Instance.new("Part")
	part.Name = oreId
	part.Size = Vector3.new(size, size, size)
	part.Anchored = true
	part.Material = ore.Material
	part.Color = ore.Color
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CFrame = CFrame.new(slot.Position)
		* CFrame.Angles(
			math.rad(oreRng:NextNumber(-6, 6)),
			math.rad(oreRng:NextInteger(0, 3) * 90 + oreRng:NextNumber(-14, 14)),
			math.rad(oreRng:NextNumber(-6, 6))
		)
	part:SetAttribute("Ore", oreId)
	part:SetAttribute("HP", hp)
	part:SetAttribute("MaxHP", hp)
	part:SetAttribute("Zone", slot.Zone)
	if lucky then
		part:SetAttribute("Lucky", lucky.Id)
		if lucky.Id == "Golden" then
			part.Color = Color3.fromRGB(255, 205, 50)
			part.Material = Enum.Material.Foil
			addSparkles(part, Color3.fromRGB(255, 230, 120), 8)
		else
			part.Color = Color3.fromRGB(255, 80, 200) -- clients cycle the hue
			part.Material = Enum.Material.Neon
			addSparkles(part, Color3.new(1, 1, 1), 20)
		end
		local light = Instance.new("PointLight")
		light.Color = part.Color
		light.Range = 16
		light.Brightness = 2
		light.Parent = part
		addCrystals(part, part.Color, part.Material)
	elseif ore.Glow then
		local light = Instance.new("PointLight")
		light.Color = ore.Color
		light.Range = 10
		light.Brightness = 1.4
		light.Parent = part
		addCrystals(part, ore.Color, Enum.Material.Neon)
	end
	decorate(part, ore, size)
	part.Parent = oreFolder
	slot.Part = part
	blockInfo[part] = { Slot = slot, Ore = oreId, HP = hp, MaxHP = hp, Zone = slot.Zone, Lucky = lucky }
	zoneBlocks[slot.Zone][part] = true
	if lucky and lucky.Announce then
		Net:Announce("🌈 A RAINBOW ORE appeared in %s! (50x value)", Color3.fromRGB(255, 120, 230), Config.Zones[slot.Zone].Name)
	end
end

local function removeBlock(part: BasePart, info)
	blockInfo[part] = nil
	zoneBlocks[info.Zone][part] = nil
	info.Slot.Part = nil
	part:Destroy()
	local delay = Config.World.OreRespawnSeconds * Services.EventService:Get("RespawnMult", 1)
	task.delay(delay, spawnBlock, info.Slot)
end

local function withinReach(root: BasePart, part: BasePart, extra: number?): boolean
	local reach = Config.World.Reach + (extra or 0) + part.Size.Magnitude / 2
	return (root.Position - part.Position).Magnitude <= reach
end

local function nearestBlock(root: BasePart): BasePart?
	local zone = World:ZoneAt(root.Position)
	if not zone or zone == 0 then
		return nil
	end
	local best, bestDistance = nil, math.huge
	for part in zoneBlocks[zone] do
		local distance = (part.Position - root.Position).Magnitude
		if distance < bestDistance then
			best, bestDistance = part, distance
		end
	end
	if best and withinReach(root, best) then
		return best
	end
	return nil
end

local function now(): number
	return workspace:GetServerTimeNow()
end

local function warnOnce(player: Player, seconds: number, text: string, ...)
	if lastWarn[player] and os.clock() - lastWarn[player] < seconds then
		return
	end
	lastWarn[player] = os.clock()
	Net:Notify(player, text, Color3.fromRGB(255, 170, 110), ...)
end

---------------------------------------------------------------------------
-- FEVER: a long combo turns into a short frenzy
---------------------------------------------------------------------------
function Mining:IsFever(player: Player): boolean
	return (feverUntil[player] or 0) > now()
end

local function feverFX(player: Player, on: boolean)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local existing = root:FindFirstChild("FeverFX")
	if not on then
		if existing then
			existing:Destroy()
		end
		return
	end
	if existing then
		return
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "FeverFX"
	emitter.Texture = "rbxasset://textures/particles/fire_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 170, 50), Color3.fromRGB(255, 60, 40))
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.4, 0.7)
	emitter.Speed = NumberRange.new(4, 8)
	emitter.SpreadAngle = Vector2.new(25, 25)
	emitter.Rate = 40
	emitter.Parent = root
end

local function startFever(player: Player, data)
	local t = now()
	feverStart[player] = t
	feverUntil[player] = t + Config.Fever.Duration
	player:SetAttribute("FeverUntil", feverUntil[player])
	data.Stats.Fevers = (data.Stats.Fevers or 0) + 1
	feverFX(player, true)
	Services.CharacterService:ApplyWalkSpeed(player)
	Net:Send(player, "Fever", Config.Fever.Duration)
end

local function extendFever(player: Player)
	local cap = (feverStart[player] or now()) + Config.Fever.MaxDuration
	feverUntil[player] = math.min(cap, (feverUntil[player] or now()) + Config.Fever.Extend)
	player:SetAttribute("FeverUntil", feverUntil[player])
end

local function endFever(player: Player)
	feverUntil[player] = nil
	feverStart[player] = nil
	combos[player] = nil
	if player.Parent then
		player:SetAttribute("FeverUntil", nil)
		feverFX(player, false)
		Services.CharacterService:ApplyWalkSpeed(player)
		Net:Send(player, "FeverEnd")
	end
end

---------------------------------------------------------------------------
-- hitting / breaking blocks
---------------------------------------------------------------------------
local function breakBlock(player: Player, data, part: BasePart, info, crit: boolean)
	-- combo: consecutive breaks within the window
	local clock = os.clock()
	local combo = combos[player]
	if combo and clock - combo.Last <= Config.Combo.Window then
		combo.Count += 1
	else
		combo = { Count = 1, Last = clock }
		combos[player] = combo
	end
	combo.Last = clock
	data.Stats.BestCombo = math.max(data.Stats.BestCombo, combo.Count)
	local comboBonus = math.min(Config.Combo.MaxBonus, (combo.Count - 1) * Config.Combo.BonusPer)

	local fever = Mining:IsFever(player)
	if fever then
		extendFever(player)
	elseif combo.Count >= Config.Fever.Combo then
		startFever(player, data)
		fever = true
	end

	local ore = Config.Ores[info.Ore]
	local events = Services.EventService
	local lucky = info.Lucky
	local value = ore.Value
		* (if lucky then lucky.ValueMult else 1)
		* events:Get("ValueMult", 1)
		* (1 + comboBonus)
		* (if fever then Config.Fever.ValueMult else 1)
	-- coins straight away: one less step, and combos/FEVER never get interrupted
	local gained = math.max(1, math.floor(value * Services.StatsService:CoinMultiplier(player, data)))
	data.Coins += gained
	data.Stats.LifetimeCoins += gained
	data.Stats.BlocksMined += 1

	local extra = { Crit = crit, Combo = combo.Count, Lucky = if lucky then lucky.Id else nil, Fever = fever }
	local gems = 0
	if ore.GemChance and math.random() < ore.GemChance then
		gems += ore.Gems
	end
	local stormChance = events:Get("GemChance", 0)
	if stormChance > 0 and math.random() < stormChance then
		gems += info.Zone
	end
	if lucky then
		gems += lucky.Gems
		data.Stats.LuckyOres += 1
	end
	if gems > 0 then
		data.Gems += gems
		extra.Gems = gems
	end
	if ore.Stardust then
		data.Stardust += ore.Stardust
		extra.Stardust = ore.Stardust
	end
	local position = part.Position
	removeBlock(part, info)
	local progression = Services.ProgressionService
	progression:OnBlockMined(player, info.Zone)
	progression:AddXP(player, info.Zone * (if lucky then 10 else 1))
	Net:Send(player, "MineBreak", position, info.Ore, gained, extra)
	if lucky and lucky.Announce then
		Net:Announce("🌈 %s mined a RAINBOW %s! (+%d 💎)", Color3.fromRGB(255, 120, 230), player.DisplayName, ore.Name, gems)
	end
end

-- returns "hit" | "broken" | nil (not allowed)
local function hitBlock(player: Player, data, part: BasePart, damage: number, crit: boolean, isSplash: boolean)
	local info = blockInfo[part]
	if not info then
		return nil
	end
	if info.Zone > data.ZoneLevel then
		if not isSplash then
			warnOnce(player, 2, "Unlock %s to mine here!", Config.Zones[info.Zone].Name)
		end
		return nil
	end
	info.HP -= damage
	if info.HP > 0 then
		part:SetAttribute("HP", info.HP)
		Net:Send(player, "MineHit", part, info.HP / info.MaxHP, crit, damage, isSplash)
		return "hit"
	end
	breakBlock(player, data, part, info, crit)
	return "broken"
end

local function mineBlock(player: Player, data, part: BasePart)
	local info = blockInfo[part]
	if not info then
		return
	end
	local zone = info.Zone
	local center = part.Position
	local damage = Services.StatsService:Damage(player, data)
	local crit = math.random() < Config.Crit.Chance
	if crit then
		damage *= Config.Crit.Multiplier
		data.Stats.Crits += 1
	end
	local result = hitBlock(player, data, part, damage, crit, false)
	if result == "hit" or result == "broken" then
		-- shockwave: crits (and every hit during FEVER) damage nearby blocks too
		local fever = Mining:IsFever(player)
		if crit or fever then
			local radius = if fever then Config.Fever.SplashRadius else Config.Crit.SplashRadius
			local mult = if fever then Config.Fever.SplashDamage else Config.Crit.SplashDamage
			local targets = {}
			for other in zoneBlocks[zone] do
				if other ~= part and (other.Position - center).Magnitude <= radius then
					table.insert(targets, other)
				end
			end
			if #targets > 0 then
				Net:Send(player, "Shockwave", center, radius, fever)
				for _, other in targets do
					hitBlock(player, data, other, damage * mult, false, true)
				end
			end
		end
	end
	Data:MarkDirty(player)
end

-- DEV: turn the block closest to the player into a Rainbow ore
function Mining:DevRainbow(player: Player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart
	local target = root and nearestBlock(root)
	if not target then
		return false
	end
	local slot = blockInfo[target].Slot
	removeBlock(target, blockInfo[target]) -- the scheduled respawn no-ops because we refill now
	spawnBlock(slot, Config.LuckyOres[1])
	return true
end

---------------------------------------------------------------------------
-- PvP
---------------------------------------------------------------------------
local function tryBonk(attacker: Player, victim: Player)
	local aRoot = attacker.Character and attacker.Character:FindFirstChild("HumanoidRootPart") :: BasePart
	local vRoot = victim.Character and victim.Character:FindFirstChild("HumanoidRootPart") :: BasePart
	local aData, vData = Data:Get(attacker), Data:Get(victim)
	if not aRoot or not vRoot or not aData or not vData then
		return
	end
	if (aRoot.Position - vRoot.Position).Magnitude > Config.PvP.BonkRange then
		return
	end
	local shards = Services.ShardService
	if not shards:IsCarrying(victim) then
		warnOnce(attacker, 3, "⚔️ You can only bonk players carrying a shard!")
		return
	end
	if (vRoot.Position - World.HubSpawn.Position).Magnitude <= Config.World.SpawnSafeRadius then
		warnOnce(attacker, 3, "🛡️ The spawn is a safe zone!")
		return
	end
	-- a new player's very first egg (tutorial) can't be knocked away
	local tutorial = vData.Tutorial
	if tutorial and not tutorial.Done and tutorial.Step <= 3 then
		warnOnce(attacker, 3, "🛡️ That's a new player's first egg - let them bring it home!")
		return
	end
	local clock = os.clock()
	if (immunity[victim] or 0) > clock then
		return
	end
	immunity[victim] = clock + Config.PvP.ImmunitySeconds

	local meta = shards:CarryMeta(victim)
	local wasThief = meta ~= nil and meta.From ~= nil
	local firstCatch = wasThief and not meta.Caught -- one catch per theft (no re-grab farming)
	if firstCatch then
		meta.Caught = true
	end
	shards:Drop(victim, attacker)
	if wasThief then
		-- stopped a thief: counts for the 🛡️ Guardian title + claims any bounty
		Services.BaseService:ThiefCaught(attacker, victim, firstCatch)
	end
	aData.Stats.Bonks += 1
	local progression = Services.ProgressionService
	progression:AddQuest(attacker, "Bonk", 1)
	progression:AddPoints(attacker, Config.PvP.PointsPerBonk)

	local direction = (vRoot.Position - aRoot.Position) * Vector3.new(1, 0, 1)
	direction = if direction.Magnitude > 0.01 then direction.Unit else Vector3.zAxis
	Net:Send(victim, "Knockback", direction * Config.PvP.Knockback + Vector3.new(0, 35, 0))
	Net:Send(victim, "Bonked", attacker.DisplayName)
	Net:Send(attacker, "BonkHit", vRoot.Position)
	Data:MarkDirty(attacker)
	Data:MarkDirty(victim)
end

-- the closest shard carrier in bonk range (mobile players just hold MINE)
local function nearestCarrier(player: Player, root: BasePart): Player?
	local best, bestDistance = nil, Config.PvP.BonkRange
	for _, other in Players:GetPlayers() do
		if other ~= player and Services.ShardService:IsCarrying(other) then
			local otherRoot = other.Character and other.Character:FindFirstChild("HumanoidRootPart") :: BasePart
			if otherRoot then
				local distance = (otherRoot.Position - root.Position).Magnitude
				if distance <= bestDistance then
					best, bestDistance = other, distance
				end
			end
		end
	end
	return best
end

---------------------------------------------------------------------------
local function onSwing(player: Player, hint)
	local data = Data:Get(player)
	local character = player.Character
	if not data or not character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	-- the pickaxe is always in hand; if it got unequipped, put it back
	if not character:FindFirstChild("Pickaxe") then
		local backpack = player:FindFirstChildOfClass("Backpack")
		local tool = backpack and backpack:FindFirstChild("Pickaxe")
		if tool and tool:IsA("Tool") then
			humanoid:EquipTool(tool)
		else
			Services.CharacterService:GivePickaxe(player)
		end
	end
	local clock = os.clock()
	local cooldown = Services.StatsService:SwingCooldown(player, data)
	if lastSwing[player] and clock - lastSwing[player] < cooldown * 0.8 then
		return
	end
	lastSwing[player] = clock

	if Services.ShardService:IsCarrying(player) then
		warnOnce(player, 4, "🌠 Hands full! Bring the shard to your base 🏠")
		return
	end

	local hintPart = if typeof(hint) == "Instance" and hint:IsA("BasePart") then hint else nil
	local meteor = Services.MeteorService

	-- 1) explicit target: another player (bonk) or a block
	if hintPart then
		local model = hintPart:FindFirstAncestorOfClass("Model")
		local victim = model and Players:GetPlayerFromCharacter(model)
		if victim and victim ~= player then
			tryBonk(player, victim)
			return
		end
		local shards = Services.ShardService
		if model and shards:IsGuardian(model) then
			if (hintPart.Position - root.Position).Magnitude <= Config.PvP.BonkRange + 2 then
				shards:HitGuardian(player, model)
			end
			return
		end
		if blockInfo[hintPart] and withinReach(root, hintPart, 3) then
			mineBlock(player, data, hintPart)
			return
		end
	end

	-- 2) meteor event (or the new player's own tutorial meteor)
	if meteor:HasTutorialMeteor(player) and meteor:TutorialHit(player, root.Position) then
		return
	end
	if meteor:IsActive() and meteor:InRange(root.Position) then
		meteor:Hit(player, Services.StatsService:Damage(player, data), cooldown)
		return
	end

	-- 3) a shard carrier (or a star guardian) right next to us
	local carrier = nearestCarrier(player, root)
	if carrier then
		tryBonk(player, carrier)
		return
	end
	local guardian = Services.ShardService:NearestGuardian(root.Position, Config.PvP.BonkRange)
	if guardian then
		Services.ShardService:HitGuardian(player, guardian)
		return
	end

	-- 4) auto target the closest block (mobile friendly + auto mine pass)
	local target = nearestBlock(root)
	if target then
		mineBlock(player, data, target)
	end
end

function Mining:Init(services)
	Services = services
	Data = services.DataService
	World = services.WorldService
end

function Mining:Start()
	oreFolder = World:Folder("Ores")
	for zone, slots in World.OreSlots do
		zoneBlocks[zone] = {}
		for _, slot in slots do
			spawnBlock(slot)
		end
	end

	Net:On("Swing", 0.08, onSwing)

	-- fever expiry
	task.spawn(function()
		while true do
			task.wait(0.25)
			local t = now()
			for player, untilTime in feverUntil do
				if untilTime <= t then
					endFever(player)
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastSwing[player] = nil
		immunity[player] = nil
		combos[player] = nil
		feverUntil[player] = nil
		feverStart[player] = nil
		lastWarn[player] = nil
	end)
end

return Mining
