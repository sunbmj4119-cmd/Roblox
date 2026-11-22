--[[
	Client mining: pickaxe input (click/tap/hold), auto-mine pass, target
	highlight + HP bar, and all the "juice": material hit sounds, block
	squash, damage numbers, CRIT pops, combo counter with rising pitch,
	golden/rainbow lucky-ore bursts, PvP knockback feedback.
	The server re-validates range and cooldown for every swing.
]]
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)

local Client = script.Parent.Parent
local Net = require(Client.Net)
local State = require(Client.State)
local Lib = require(Client.UI.Lib)
local Root = require(Client.UI.Root)

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local C = Lib.Colors
local New = Lib.New

local Mining = {}

local tool: Tool? = nil
local holding = false
local lastSwing = 0
local oresFolder = nil
local ORE_SIZE = Vector3.one * Config.World.OreSize

local function getOres()
	if oresFolder and oresFolder.Parent then
		return oresFolder
	end
	local map = workspace:FindFirstChild("Map")
	oresFolder = map and map:FindFirstChild("Ores")
	return oresFolder
end

local function hitSoundFor(oreId: string?): string
	local ore = oreId and Config.Ores[oreId]
	if ore then
		local m = ore.Material
		if m == Enum.Material.Metal or m == Enum.Material.Foil then
			return "HitMetal"
		elseif m == Enum.Material.Ice or m == Enum.Material.Glass or m == Enum.Material.Neon then
			return "HitIce"
		end
	end
	return "HitStone"
end

-- selection + hp bar ------------------------------------------------------
local selection = Instance.new("SelectionBox")
selection.LineThickness = 0.06
selection.Color3 = Color3.fromRGB(255, 230, 120)
selection.SurfaceTransparency = 1
selection.Parent = workspace

local hpGui = New("BillboardGui", {
	Size = UDim2.fromOffset(120, 18),
	StudsOffsetWorldSpace = Vector3.new(0, 4, 0),
	AlwaysOnTop = true,
	Enabled = false,
	ResetOnSpawn = false, -- module runs once; don't let respawn delete it
	Parent = player:WaitForChild("PlayerGui"),
})
local _, setHp = Lib.Bar({ Size = UDim2.fromScale(1, 1), Color = C.Green, TextSize = 12, Parent = hpGui })
local hpTarget: BasePart? = nil
local hpHideAt = 0

local function showHp(part: BasePart, ratio: number)
	hpTarget = part
	hpGui.Adornee = part
	hpGui.Enabled = true
	local ore = Config.Ores[part:GetAttribute("Ore") or ""]
	local name = if ore then ore.Name else ""
	local lucky = part:GetAttribute("Lucky")
	if type(lucky) == "string" then
		name = lucky .. " " .. name
	end
	setHp(ratio, name, if ratio > 0.5 then C.Green elseif ratio > 0.25 then C.Gold else C.Red)
	hpHideAt = os.clock() + 2
end

-- effects ----------------------------------------------------------------
local function burst(position: Vector3, color: Color3, amount: number, speed: number?)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Transparency = 1
	part.Size = Vector3.one
	part.Position = position
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) })
	emitter.Speed = NumberRange.new(10 * (speed or 1), 24 * (speed or 1))
	emitter.Lifetime = NumberRange.new(0.4, 0.9)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -45, 0)
	emitter.Rate = 0
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.Parent = part
	part.Parent = workspace
	emitter:Emit(amount)
	Debris:AddItem(part, 1.5)
end

local function floatText(position: Vector3, text: string, color: Color3, size: number?, rise: number?)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.Position = position + Vector3.new(math.random(-10, 10) / 10, 3, math.random(-10, 10) / 10)
	anchor.Parent = workspace
	local px = size or 36
	local gui = New("BillboardGui", { Size = UDim2.fromOffset(px * 6, px * 1.3), AlwaysOnTop = true, Adornee = anchor, Parent = anchor })
	local label = Lib.Text({ Text = text, TextColor3 = color, Size = UDim2.fromScale(1, 1), MaxTextSize = px, Parent = gui })
	local scale = New("UIScale", { Scale = 0.4, Parent = label })
	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(anchor, TweenInfo.new(1.1), { Position = anchor.Position + Vector3.new(0, rise or 4, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1 }):Play()
	Debris:AddItem(anchor, 1.2)
end

-- block squash on hit (purely local, restores the real size)
local function squash(part: BasePart)
	part.Size = ORE_SIZE * 0.86
	TweenService:Create(part, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = ORE_SIZE }):Play()
end

local function shake(strength: number, duration: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local start = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		if t > duration then
			humanoid.CameraOffset = Vector3.zero
			connection:Disconnect()
			return
		end
		local fade = 1 - t / duration
		humanoid.CameraOffset = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * strength * fade
	end)
end

-- combo counter (center right) -------------------------------------------
local comboCluster = Root.Cluster("Combo", Vector2.new(1, 0.5), UDim2.new(1, -30, 0.38, 0), UDim2.fromOffset(240, 90))
local comboLabel = Lib.Text({
	Text = "",
	TextColor3 = Color3.fromRGB(255, 170, 60),
	Size = UDim2.fromScale(1, 0.65),
	MaxTextSize = 48,
	Parent = comboCluster,
})
local comboSub = Lib.Text({
	Text = "",
	Font = Lib.BodyFont,
	TextColor3 = Color3.fromRGB(255, 230, 160),
	Size = UDim2.fromScale(1, 0.3),
	Position = UDim2.fromScale(0, 0.66),
	MaxTextSize = 18,
	Parent = comboCluster,
})
local comboScale = New("UIScale", { Parent = comboLabel })
local comboHideAt = 0

local function showCombo(count: number)
	if count < 3 then
		return
	end
	local bonus = math.min(Config.Combo.MaxBonus, (count - 1) * Config.Combo.BonusPer)
	comboLabel.Text = string.format("🔥 x%d COMBO", count)
	comboLabel.TextColor3 = if count >= 30
		then Color3.fromRGB(255, 80, 200)
		elseif count >= 15 then Color3.fromRGB(255, 90, 60)
		else Color3.fromRGB(255, 170, 60)
	comboSub.Text = string.format("+%d%% ore", math.floor(bonus * 100 + 0.5))
	comboScale.Scale = 1.35
	TweenService:Create(comboScale, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	comboLabel.Visible = true
	comboSub.Visible = true
	comboHideAt = os.clock() + Config.Combo.Window
end

-- swinging ---------------------------------------------------------------
local function playSwing()
	if not tool then
		return
	end
	local anim = Instance.new("StringValue")
	anim.Name = "toolanim"
	anim.Value = "Slash"
	anim.Parent = tool
	Debris:AddItem(anim, 0.5)
	Lib.PlaySound("Swing")
end

local function swing(useHint: boolean)
	if not tool or not tool.Parent or tool.Parent ~= player.Character then
		return
	end
	local cooldown = (State.Derived and State.Derived.Cooldown) or 0.5
	local now = os.clock()
	if now - lastSwing < cooldown then
		return
	end
	lastSwing = now
	playSwing()
	local hint = if useHint then mouse.Target else nil
	Net.Fire("Swing", hint)
end

local function bindTool(newTool: Tool)
	tool = newTool
	newTool.Activated:Connect(function()
		holding = true
		swing(true)
	end)
	newTool.Deactivated:Connect(function()
		holding = false
	end)
	newTool.Unequipped:Connect(function()
		holding = false
	end)
end

local function onCharacter(character: Model)
	tool = nil
	holding = false
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child.Name == "Pickaxe" then
			bindTool(child)
		end
	end)
	local existing = character:FindFirstChild("Pickaxe")
	if existing and existing:IsA("Tool") then
		bindTool(existing)
	end
	-- auto equip the pickaxe on spawn: one less step for new players
	task.spawn(function()
		local backpack = player:WaitForChild("Backpack")
		local pickaxe = backpack:WaitForChild("Pickaxe", 15)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if pickaxe and humanoid and not character:FindFirstChildOfClass("Tool") then
			humanoid:EquipTool(pickaxe)
		end
	end)
end

player.CharacterAdded:Connect(onCharacter)
if player.Character then
	onCharacter(player.Character)
end

RunService.Heartbeat:Connect(function()
	-- hover highlight (PC)
	local ores = getOres()
	local target = mouse.Target
	if tool and tool.Parent == player.Character and target and ores and target.Parent == ores then
		selection.Adornee = target
	else
		selection.Adornee = nil
	end

	if hpGui.Enabled and (os.clock() > hpHideAt or not hpTarget or not hpTarget.Parent) then
		hpGui.Enabled = false
	end
	if comboLabel.Visible and os.clock() > comboHideAt then
		comboLabel.Visible = false
		comboSub.Visible = false
	end

	if holding then
		swing(true)
	elseif State.AutoMine and State.HasPass("AutoMine") then
		swing(false)
	end
end)

-- rainbow ores cycle their color locally (only tracked rainbow parts)
local rainbowParts = {}
local function trackOre(part: Instance)
	if part:IsA("BasePart") and part:GetAttribute("Lucky") == "Rainbow" then
		rainbowParts[part] = true
	end
end
task.spawn(function()
	local map = workspace:WaitForChild("Map", 60)
	local ores = map and map:WaitForChild("Ores", 60)
	if not ores then
		return
	end
	for _, part in ores:GetChildren() do
		trackOre(part)
	end
	ores.ChildAdded:Connect(trackOre)
	ores.ChildRemoved:Connect(function(part)
		rainbowParts[part] = nil
	end)
end)
RunService.RenderStepped:Connect(function()
	if next(rainbowParts) == nil then
		return
	end
	local color = Color3.fromHSV((os.clock() * 0.35) % 1, 0.75, 1)
	for part in rainbowParts do
		part.Color = color
		for _, child in part:GetChildren() do
			if child:IsA("BasePart") then
				child.Color = color
			end
		end
	end
end)

-- server feedback ----------------------------------------------------------
Net.On("MineHit", function(part, ratio, crit, damage)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return
	end
	showHp(part, ratio)
	squash(part)
	local top = part.Position + Vector3.new(0, 2.5, 0)
	burst(top, part.Color, if crit then 10 else 4)
	Lib.PlaySound(hitSoundFor(part:GetAttribute("Ore")))
	if crit then
		Lib.PlaySound("Crit")
		floatText(top, "💥 CRIT " .. Util.Format(damage or 0), Color3.fromRGB(255, 120, 60), 44, 5)
		shake(0.25, 0.15)
	elseif type(damage) == "number" then
		floatText(top, Util.Format(damage), Color3.fromRGB(255, 255, 255), 26, 3)
	end
end)

Net.On("MineBreak", function(position, oreId, gained, extra)
	extra = extra or {}
	local ore = Config.Ores[oreId]
	local color = if ore then ore.Color else Color3.new(1, 1, 1)
	hpGui.Enabled = false
	Lib.PlaySound(hitSoundFor(oreId), 1.1, -0.15)
	Lib.PlaySound("Break")

	if extra.Lucky then
		local rainbow = extra.Lucky == "Rainbow"
		local luckyColor = if rainbow then Color3.fromRGB(255, 120, 230) else Color3.fromRGB(255, 210, 60)
		burst(position, luckyColor, 60, 1.6)
		burst(position, Color3.new(1, 1, 1), 25, 1.2)
		Lib.PlaySound("Lucky")
		shake(if rainbow then 0.8 else 0.4, 0.35)
		floatText(position, (if rainbow then "🌈 RAINBOW! " else "✨ GOLDEN! ") .. "+" .. Util.Format(gained), luckyColor, 56, 6)
	else
		burst(position, color, 18)
		floatText(position, "+" .. Util.Format(gained), Color3.fromRGB(255, 255, 255), 30)
	end
	if extra.Crit then
		Lib.PlaySound("Crit", 0.8)
	end
	if extra.Gems then
		floatText(position + Vector3.new(0, 2, 0), "+" .. extra.Gems .. " 💎", C.Gems, 34, 5)
		Lib.PlaySound("Reward", 0.7)
	end
	if extra.Stardust then
		floatText(position + Vector3.new(0, 2, 0), "+" .. extra.Stardust .. " ✨", C.Stardust, 30, 5)
	end
	if type(extra.Combo) == "number" then
		showCombo(extra.Combo)
		-- coin "ding" climbs in pitch as the combo grows
		Lib.PlaySound("Coin", 0.6, math.min(0.9, extra.Combo * 0.03))
	end
end)

local flash = New("Frame", {
	BackgroundColor3 = Color3.fromRGB(255, 40, 60),
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 90,
	Parent = Root.Overlay,
})

Net.On("Knockback", function(velocity)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and typeof(velocity) == "Vector3" then
		if humanoid then
			humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		end
		root.AssemblyLinearVelocity = velocity
	end
end)

Net.On("Bonked", function(attackerName, dropped)
	flash.BackgroundTransparency = 0.55
	TweenService:Create(flash, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
	Lib.PlaySound("Bonked")
	shake(0.6, 0.3)
	local hud = Mining.HUD
	if hud then
		hud.Toast(string.format("💥 %s bonked you! You dropped %s ore", attackerName, Util.Format(dropped)), C.Red)
	end
end)

return Mining
