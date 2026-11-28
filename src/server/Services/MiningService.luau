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

-- 🪨 an ore node reads as a natural boulder: a rough rock shell (the zone's
-- stone) around a core of the ore, with crystals (gems) or nuggets (metals)
-- growing out of it. Only the core part is the hit target.
local GEM_MATERIALS = {
	[Enum.Material.Glass] = true,
	[Enum.Material.Neon] = true,
	[Enum.Material.Ice] = true,
}
local METAL_MATERIALS = {
	[Enum.Material.Metal] = true,
	[Enum.Material.Foil] = true,
	[Enum.Material.DiamondPlate] = true,
}

local function piece(parent: BasePart, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

local function rockColorFor(zone: number): Color3
	local def = Config.Zones[zone]
	local base = if def and def.FloorColor then def.FloorColor else Color3.fromRGB(120, 115, 110)
	return base:Lerp(Color3.fromRGB(95, 92, 90), 0.55)
end

local function decorate(part: BasePart, ore, _size: number, zone: number)
	local rock = rockColorFor(zone)
	local center = part.CFrame
	-- rough shell: rotated slabs hugging the core
	for i = 1, 4 do
		local angle = i * (math.pi / 2) + oreRng:NextNumber(-0.4, 0.4)
		local w = oreRng:NextNumber(2.2, 3.4)
		piece(
			part,
			"Rock",
			Vector3.new(w, oreRng:NextNumber(2, 3.2), w * oreRng:NextNumber(0.8, 1.2)),
			CFrame.new(center.Position + Vector3.new(math.cos(angle) * 1.5, -0.6, math.sin(angle) * 1.5))
				* CFrame.Angles(oreRng:NextNumber(-0.5, 0.5), oreRng:NextNumber(0, 6.2), oreRng:NextNumber(-0.5, 0.5)),
			rock:Lerp(Color3.new(0, 0, 0), oreRng:NextNumber(0, 0.2)),
			if i % 2 == 0 then Enum.Material.Slate else Enum.Material.Rock
		)
	end
	if GEM_MATERIALS[ore.Material] or ore.Glow then
		-- crystals growing out of the rock
		local material = if ore.Glow then Enum.Material.Neon else Enum.Material.Glass
		for i = 1, oreRng:NextInteger(4, 6) do
			local angle = i * 1.25 + oreRng:NextNumber(-0.3, 0.3)
			local h = oreRng:NextNumber(2.2, 4.6)
			local w = oreRng:NextNumber(0.7, 1.15)
			local tilt = oreRng:NextNumber(0.25, 0.6)
			local crystal = piece(
				part,
				"Crystal",
				Vector3.new(w, h, w),
				CFrame.new(center.Position + Vector3.new(math.cos(angle) * 1.1, 1 + h * 0.3, math.sin(angle) * 1.1))
					* CFrame.Angles(math.sin(angle) * tilt, angle, -math.cos(angle) * tilt)
					* CFrame.Angles(0, math.rad(45), 0),
				ore.Color:Lerp(Color3.new(1, 1, 1), oreRng:NextNumber(0, 0.25)),
				material
			)
			crystal.Transparency = if material == Enum.Material.Glass then 0.15 else 0
		end
	elseif METAL_MATERIALS[ore.Material] then
		-- shiny nuggets in the stone
		for i = 1, oreRng:NextInteger(4, 7) do
			local angle = i * 1.1 + oreRng:NextNumber(-0.4, 0.4)
			local sizeN = oreRng:NextNumber(0.8, 1.5)
			piece(
				part,
				"Nugget",
				Vector3.one * sizeN,
				CFrame.new(center.Position + Vector3.new(math.cos(angle) * 1.9, oreRng:NextNumber(-0.4, 1.4), math.sin(angle) * 1.9)),
				ore.Color,
				ore.Material,
				Enum.PartType.Ball
			)
		end
	elseif ore.Value >= 2 then
		-- coal / plain rock: dark lumps
		for i = 1, 4 do
			local angle = i * 1.6
			piece(
				part,
				"Vein",
				Vector3.one * oreRng:NextNumber(0.9, 1.4),
				CFrame.new(center.Position + Vector3.new(math.cos(angle) * 1.9, oreRng:NextNumber(-0.3, 1), math.sin(angle) * 1.9))
					* CFrame.Angles(oreRng:NextNumber(0, 3), oreRng:NextNumber(0, 3), 0),
				ore.Color,
				ore.Material
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
	part.Size = Vector3.new(size * 0.8, size * 0.7, size * 0.8)
	part.Anchored = true
	part.Material = ore.Material
	part.Color = ore.Color:Lerp(rockColorFor(slot.Zone), if ore.Glow then 0 else 0.2)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CFrame = CFrame.new(slot.Position - Vector3.new(0, 0.6, 0))
		* CFrame.Angles(math.rad(oreRng:NextNumber(-20, 20)), math.rad(oreRng:NextNumber(0, 360)), math.rad(oreRng:NextNumber(-20, 20)))
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
		light.Range = 10
		light.Brightness = 1
		light.Parent = part
		addCrystals(part, part.Color, part.Material)
	elseif ore.Glow then
		local light = Instance.new("PointLight")
		light.Color = ore.Color
		light.Range = 8
		light.Brightness = 0.8
		light.Parent = part
		-- (glowing ores already grow neon crystals in decorate)
	end
	decorate(part, ore, size, slot.Zone)
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
		if model and Services.RivalService:IsRival(model) then
			Services.RivalService:Bonk(player, model)
			return
		end
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
	local robot = Services.RivalService:NearestCarrying(root.Position, Config.PvP.BonkRange + 2)
	if robot then
		Services.RivalService:Bonk(player, robot)
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

---------------------------------------------------------------------------
-- 🐾 pet helpers: following pets hit ores / the meteor next to their owner
---------------------------------------------------------------------------
local PET_HELP = Config.PetHelp
-- (only clients close enough to see the pets get the hop animation)
local function sendPetHelp(player: Player, at: Vector3, targets)
	for _, other in Players:GetPlayers() do
		local character = other.Character
		local otherRoot = character and character:FindFirstChild("HumanoidRootPart")
		if otherRoot and otherRoot:IsA("BasePart") and (otherRoot.Position - at).Magnitude <= 160 then
			Net:Send(other, "PetHelp", player.UserId, targets)
		end
	end
end

local function petHelpFor(player: Player)
	local data = Data:Get(player)
	local last = lastSwing[player]
	local pets = data and #data.Equipped or 0
	if pets <= 0 or not last or os.clock() - last > PET_HELP.ActiveSeconds then
		return
	end
	if Services.ShardService:IsCarrying(player) then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local damage = Services.StatsService:Damage(player, data)
	local meteor = Services.MeteorService
	if meteor:IsActive() and meteor:InRange(root.Position) then
		if meteor:PetHit(player, pets, damage) then
			Services.PetService:AddFollowXP(player, Config.Growth.HelpXP)
			local at = meteor:Position()
			if at then
				sendPetHelp(player, root.Position, { at })
			end
		end
		return
	end
	local zone = World:ZoneAt(root.Position)
	if not zone or zone == 0 or zone > data.ZoneLevel then
		return
	end
	-- the closest ores around you, one per pet
	local near = {}
	for part in zoneBlocks[zone] do
		local distance = (part.Position - root.Position).Magnitude
		if distance <= PET_HELP.Range then
			table.insert(near, { Part = part, Distance = distance })
		end
	end
	if #near == 0 then
		return
	end
	table.sort(near, function(a, b)
		return a.Distance < b.Distance
	end)
	local targets = {}
	for i = 1, pets do
		local entry = near[((i - 1) % #near) + 1]
		if blockInfo[entry.Part] then
			table.insert(targets, entry.Part.Position)
			hitBlock(player, data, entry.Part, damage * PET_HELP.OreShare, false, true)
		end
	end
	if #targets > 0 then
		sendPetHelp(player, root.Position, targets)
		Services.PetService:AddFollowXP(player, Config.Growth.HelpXP)
		Data:MarkDirty(player)
	end
end

---------------------------------------------------------------------------
-- rival players (RivalService)
---------------------------------------------------------------------------
-- the closest ore in a zone (where a rival goes mining)
function Mining:NearestOreIn(zone: number, position: Vector3): BasePart?
	local best, bestDistance = nil, math.huge
	for part in zoneBlocks[zone] or {} do
		local distance = (part.Position - position).Magnitude
		if distance < bestDistance then
			best, bestDistance = part, distance
		end
	end
	return best
end

-- a rival hits an ore (no rewards; the ore breaks and respawns like any other)
function Mining:NpcHit(part: BasePart, damage: number): boolean
	local info = blockInfo[part]
	if not info then
		return false
	end
	info.HP -= damage
	if info.HP > 0 then
		part:SetAttribute("HP", info.HP)
		return true
	end
	removeBlock(part, info)
	return true
end

-- may a rival bonk this player? (same safety rules as players, plus: never a
-- new player's first egg, never in the base district)
-- (rivalId: a rival may chase a thief carrying ITS pet even into the base district)
function Mining:CanNpcBonk(victim: Player, rivalId: number?): boolean
	local data = Data:Get(victim)
	local root = victim.Character and victim.Character:FindFirstChild("HumanoidRootPart")
	if not data or not root or not root:IsA("BasePart") or not Services.ShardService:IsCarrying(victim) then
		return false
	end
	local tutorial = data.Tutorial
	if tutorial and not tutorial.Done and tutorial.Step <= 3 then
		return false
	end
	if (root.Position - World.HubSpawn.Position).Magnitude <= Config.World.SpawnSafeRadius then
		return false
	end
	local meta = Services.ShardService:CarryMeta(victim)
	local ownPet = rivalId ~= nil and meta ~= nil and meta.RivalFrom == rivalId
	if Util.InBases(Config, root.Position) and not ownPet then
		return false
	end
	return (immunity[victim] or 0) <= os.clock()
end

function Mining:NpcBonk(attackerRoot: BasePart, attackerName: string, victim: Player, rivalId: number?): boolean
	if not self:CanNpcBonk(victim, rivalId) then
		return false
	end
	local vRoot = victim.Character and victim.Character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not vRoot or (vRoot.Position - attackerRoot.Position).Magnitude > Config.PvP.BonkRange then
		return false
	end
	immunity[victim] = os.clock() + Config.PvP.ImmunitySeconds
	Services.ShardService:Drop(victim, nil)
	local direction = (vRoot.Position - attackerRoot.Position) * Vector3.new(1, 0, 1)
	direction = if direction.Magnitude > 0.01 then direction.Unit else Vector3.zAxis
	Net:Send(victim, "Knockback", direction * Config.PvP.Knockback + Vector3.new(0, 35, 0))
	Net:Send(victim, "Bonked", attackerName)
	return true
end

-- cloud tests: one pet-help tick for a player now
function Mining:PetHelpForTest(player: Player, swungAgo: number?)
	assert(not game:GetService("RunService"):IsRunning(), "test hook used on a live server")
	lastSwing[player] = os.clock() - (swungAgo or 0)
	petHelpFor(player)
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

	task.spawn(function()
		while true do
			task.wait(PET_HELP.Interval)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(petHelpFor, player)
				if not ok then
					warn("[Mining] pet help failed: " .. tostring(err))
				end
			end
		end
	end)

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
