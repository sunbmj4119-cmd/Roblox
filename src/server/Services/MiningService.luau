--[[
	MiningService: ore blocks (spawn / damage / respawn), the pickaxe swing
	handler (server-authoritative range + cooldown checks), backpack filling,
	and Star Crater PvP: bonk a player to knock 25% of their ore onto the
	ground as orbs anyone can grab.
]]
local Debris = game:GetService("Debris")
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
local oreFolder: Folder
local dropFolder: Folder

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
	part.CFrame = CFrame.new(slot.Position) * CFrame.Angles(0, math.rad(oreRng:NextInteger(0, 3) * 90), 0)
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
	part.Parent = oreFolder
	slot.Part = part
	blockInfo[part] = { Slot = slot, Ore = oreId, HP = hp, MaxHP = hp, Zone = slot.Zone, Lucky = lucky }
	zoneBlocks[slot.Zone][part] = true
	if lucky and lucky.Announce then
		Net:Announce("🌈 A RAINBOW ORE appeared in " .. Config.Zones[slot.Zone].Name .. "! (50x value)", Color3.fromRGB(255, 120, 230))
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

local function mineBlock(player: Player, data, part: BasePart)
	local info = blockInfo[part]
	if not info then
		return
	end
	if info.Zone > data.ZoneLevel then
		Net:Notify(player, "Unlock " .. Config.Zones[info.Zone].Name .. " to mine here!", Color3.fromRGB(255, 110, 110))
		return
	end
	local stats = Services.StatsService
	local monetization = Services.MonetizationService
	local capacity = stats:Capacity(player, data)
	if data.Backpack >= capacity then
		if monetization:HasPass(player, "AutoSell") then
			Services.EconomyService:Sell(player, true)
		else
			Net:Send(player, "BackpackFull")
			return
		end
	end

	local ore = Config.Ores[info.Ore]
	local damage = stats:Damage(player, data)
	local crit = math.random() < Config.Crit.Chance
	if crit then
		damage *= Config.Crit.Multiplier
		data.Stats.Crits += 1
	end
	info.HP -= damage
	if info.HP > 0 then
		part:SetAttribute("HP", info.HP)
		Net:Send(player, "MineHit", part, info.HP / info.MaxHP, crit, damage)
		return
	end

	-- combo: consecutive breaks within the window
	local now = os.clock()
	local combo = combos[player]
	if combo and now - combo.Last <= Config.Combo.Window then
		combo.Count += 1
	else
		combo = { Count = 1, Last = now }
		combos[player] = combo
	end
	combo.Last = now
	data.Stats.BestCombo = math.max(data.Stats.BestCombo, combo.Count)
	local comboBonus = math.min(Config.Combo.MaxBonus, (combo.Count - 1) * Config.Combo.BonusPer)

	local events = Services.EventService
	local lucky = info.Lucky
	local value = ore.Value * (if lucky then lucky.ValueMult else 1) * events:Get("ValueMult", 1) * (1 + comboBonus)
	local gained = math.min(math.floor(value), capacity - data.Backpack)
	data.Backpack += gained
	data.Stats.BlocksMined += 1

	local extra = { Crit = crit, Combo = combo.Count, Lucky = if lucky then lucky.Id else nil, Damage = damage }
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
		Net:Announce(
			string.format("🌈 %s mined a RAINBOW %s! (+%d 💎)", player.DisplayName, ore.Name, gems),
			Color3.fromRGB(255, 120, 230)
		)
	end

	if data.Backpack >= capacity and monetization:HasPass(player, "AutoSell") then
		Services.EconomyService:Sell(player, true)
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
local function spawnOrbs(origin: Vector3, total: number)
	local count = math.clamp(total, 1, 6)
	local each = math.floor(total / count)
	local remainder = total - each * count
	for i = 1, count do
		local value = each + (if i == 1 then remainder else 0)
		local angle = (i / count) * math.pi * 2
		local orb = Instance.new("Part")
		orb.Name = "OreOrb"
		orb.Shape = Enum.PartType.Ball
		orb.Size = Vector3.one * 1.8
		orb.Material = Enum.Material.Neon
		orb.Color = Color3.fromRGB(255, 120, 230)
		orb.Anchored = true
		orb.CanCollide = false
		orb.Position = Vector3.new(origin.X + math.cos(angle) * 6, 1.6, origin.Z + math.sin(angle) * 6)
		orb:SetAttribute("Value", value)
		local light = Instance.new("PointLight")
		light.Color = orb.Color
		light.Range = 8
		light.Parent = orb

		local taken = false
		orb.Touched:Connect(function(hit)
			if taken then
				return
			end
			local character = hit:FindFirstAncestorOfClass("Model")
			local player = character and Players:GetPlayerFromCharacter(character)
			local data = player and Data:Get(player)
			if not data then
				return
			end
			local capacity = Services.StatsService:Capacity(player, data)
			if data.Backpack >= capacity then
				return
			end
			taken = true
			local added = math.min(value, capacity - data.Backpack)
			data.Backpack += added
			Net:Notify(player, "✨ +" .. Util.Format(added) .. " stolen ore!", Color3.fromRGB(255, 140, 230))
			Data:MarkDirty(player)
			orb:Destroy()
		end)
		orb.Parent = dropFolder
		Debris:AddItem(orb, Config.PvP.OrbLifetime)
	end
end

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
	local pvpZone = World.PvPZone
	if World:ZoneAt(aRoot.Position) ~= pvpZone or World:ZoneAt(vRoot.Position) ~= pvpZone then
		Net:Notify(attacker, "⚔️ You can only bonk players inside the Star Crater!")
		return
	end
	local now = os.clock()
	if (immunity[victim] or 0) > now then
		return
	end
	immunity[victim] = now + Config.PvP.ImmunitySeconds

	local drop = math.floor(vData.Backpack * Config.PvP.DropPercent)
	if drop > 0 then
		vData.Backpack -= drop
		spawnOrbs(vRoot.Position, drop)
	end
	aData.Stats.Bonks += 1
	local progression = Services.ProgressionService
	progression:AddQuest(attacker, "Bonk", 1)
	progression:AddPoints(attacker, Config.PvP.PointsPerBonk)

	local direction = (vRoot.Position - aRoot.Position) * Vector3.new(1, 0, 1)
	direction = if direction.Magnitude > 0.01 then direction.Unit else Vector3.zAxis
	Net:Send(victim, "Knockback", direction * Config.PvP.Knockback + Vector3.new(0, 35, 0))
	Net:Send(victim, "Bonked", attacker.DisplayName, drop)
	Net:Notify(attacker, string.format("💥 Bonked %s! %s ore dropped", victim.DisplayName, Util.Format(drop)), Color3.fromRGB(255, 140, 90))
	Data:MarkDirty(attacker)
	Data:MarkDirty(victim)
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
	if not character:FindFirstChild("Pickaxe") then
		return
	end
	local now = os.clock()
	local cooldown = Services.StatsService:SwingCooldown(player, data)
	if lastSwing[player] and now - lastSwing[player] < cooldown * 0.8 then
		return
	end
	lastSwing[player] = now

	local hintPart = if typeof(hint) == "Instance" and hint:IsA("BasePart") then hint else nil
	local meteor = Services.MeteorService

	-- 1) explicit target: another player (PvP) or a block
	if hintPart then
		local model = hintPart:FindFirstAncestorOfClass("Model")
		local victim = model and Players:GetPlayerFromCharacter(model)
		if victim and victim ~= player then
			tryBonk(player, victim)
			return
		end
		if blockInfo[hintPart] and withinReach(root, hintPart) then
			mineBlock(player, data, hintPart)
			return
		end
	end

	-- 2) meteor event
	if meteor:IsActive() and meteor:InRange(root.Position) then
		meteor:Hit(player, Services.StatsService:Damage(player, data), cooldown)
		return
	end

	-- 3) auto target the closest block (mobile friendly + auto mine pass)
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
	dropFolder = World:Folder("Drops")
	for zone, slots in World.OreSlots do
		zoneBlocks[zone] = {}
		for _, slot in slots do
			spawnBlock(slot)
		end
	end

	Net:On("Swing", 0.08, onSwing)

	Players.PlayerRemoving:Connect(function(player)
		lastSwing[player] = nil
		immunity[player] = nil
		combos[player] = nil
	end)
end

return Mining
