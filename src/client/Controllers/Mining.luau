--[[
	Client mining.
	Input: TAP / CLICK a block (or a shard carrier, a dropped shard, the
	meteor) and your character walks there and keeps swinging until it
	breaks. HOLD the mouse or the big ⛏️ button (phones) to mine the nearest
	blocks nonstop. Moving with the joystick/WASD cancels the auto-walk.
	The pickaxe is always kept in hand (no hotbar needed).
	Juice: material hit sounds, block squash, damage numbers, CRIT pops and
	shockwaves, combo counter with rising pitch, FEVER mode, lucky-ore
	bursts, bonk feedback. The server re-validates range and cooldown.
]]
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

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
local T = Lib.T

local Mining = {}

local tool: Tool? = nil
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
	local name = if ore then T(ore.Name) else ""
	local lucky = part:GetAttribute("Lucky")
	if type(lucky) == "string" then
		name = T(lucky) .. " " .. name
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
	comboLabel.Text = T("🔥 x%d COMBO", count)
	comboLabel.TextColor3 = if count >= 30
		then Color3.fromRGB(255, 80, 200)
		elseif count >= 15 then Color3.fromRGB(255, 90, 60)
		else Color3.fromRGB(255, 170, 60)
	comboSub.Text = T("+%d%% ore", math.floor(bonus * 100 + 0.5))
	comboScale.Scale = 1.35
	TweenService:Create(comboScale, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	comboLabel.Visible = true
	comboSub.Visible = true
	comboHideAt = os.clock() + Config.Combo.Window
end

-- input + targeting ---------------------------------------------------------
local REACH = Config.World.Reach
local target = nil -- { Kind = "Ore" | "Player" | "Meteor" | "Shard", Part = BasePart }
local autoWalk = false
local holdMouse = false
local holdButton = false
local lastMoveTo = 0
local lastSearch = 0

local targetHighlight = Instance.new("Highlight")
targetHighlight.Name = "MineTarget"
targetHighlight.FillColor = Color3.fromRGB(255, 230, 120)
targetHighlight.FillTransparency = 0.82
targetHighlight.OutlineColor = Color3.fromRGB(255, 230, 120)
targetHighlight.OutlineTransparency = 0
targetHighlight.DepthMode = Enum.HighlightDepthMode.Occluded
targetHighlight.Parent = workspace

-- the default PlayerModule tells us when the player steers by themselves
local controls = nil
task.spawn(function()
	local scripts = player:WaitForChild("PlayerScripts", 20)
	local module = scripts and scripts:WaitForChild("PlayerModule", 20)
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" and result.GetControls then
			controls = result:GetControls()
		end
	end
end)

local function userIsSteering(): boolean
	if not controls then
		return false
	end
	local ok, vector = pcall(function()
		return controls:GetMoveVector()
	end)
	return ok and typeof(vector) == "Vector3" and vector.Magnitude > 0.2
end

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

local function feverActive(): boolean
	local untilTime = player:GetAttribute("FeverUntil")
	return type(untilTime) == "number" and untilTime > workspace:GetServerTimeNow()
end

local function cooldownNow(): number
	local cooldown = (State.Derived and State.Derived.Cooldown) or 0.36
	if feverActive() then
		cooldown *= Config.Fever.CooldownMult
	end
	return cooldown
end

local function setTarget(newTarget, walk: boolean)
	target = newTarget
	autoWalk = walk and newTarget ~= nil
	lastMoveTo = 0
	targetHighlight.Adornee = if newTarget and newTarget.Kind ~= "Meteor" then newTarget.Part else nil
end

-- what did the player tap on?
local function classify(hit: Instance?)
	if not hit or not hit:IsA("BasePart") then
		return nil
	end
	local ores = getOres()
	if ores then
		if hit.Parent == ores then
			return { Kind = "Ore", Part = hit }
		end
		local parent = hit.Parent
		if parent and parent.Parent == ores and parent:IsA("BasePart") then
			return { Kind = "Ore", Part = parent }
		end
	end
	if hit.Name == "Meteor" then
		return { Kind = "Meteor", Part = hit }
	end
	local model = hit:FindFirstAncestorOfClass("Model")
	if model then
		local other = Players:GetPlayerFromCharacter(model)
		if other and other ~= player then
			local otherRoot = model:FindFirstChild("HumanoidRootPart")
			if otherRoot and otherRoot:IsA("BasePart") then
				return { Kind = "Player", Part = otherRoot }
			end
		end
		local map = workspace:FindFirstChild("Map")
		local shardFolder = map and map:FindFirstChild("Shards")
		if shardFolder and model.Parent == shardFolder then
			local hitbox = model:FindFirstChild("Hitbox")
			if hitbox and hitbox:IsA("BasePart") then
				return { Kind = "Shard", Part = hitbox }
			end
		end
	end
	return nil
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function pickAt(position: Vector3)
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local ray = camera:ScreenPointToRay(position.X, position.Y)
	rayParams.FilterDescendantsInstances = { player.Character :: Instance }
	local result = workspace:Raycast(ray.Origin, ray.Direction * 500, rayParams)
	return classify(result and result.Instance)
end

local function reachFor(kind: string): number
	if kind == "Player" then
		return Config.PvP.BonkRange - 1.5
	elseif kind == "Meteor" then
		return Config.Meteor.Radius + REACH - 2
	elseif kind == "Shard" then
		return 2
	end
	return REACH
end

local function flatDistance(a: Vector3, b: Vector3): number
	return ((a - b) * Vector3.new(1, 0, 1)).Magnitude
end

local function swingAt(root: BasePart, current)
	local now = os.clock()
	if now - lastSwing < cooldownNow() then
		return
	end
	lastSwing = now
	if current and current.Part then
		local p = current.Part.Position
		local look = Vector3.new(p.X, root.Position.Y, p.Z)
		if (look - root.Position).Magnitude > 0.5 then
			root.CFrame = CFrame.lookAt(root.Position, look)
		end
	end
	playSwing()
	local hint = if current and (current.Kind == "Ore" or current.Kind == "Player") then current.Part else nil
	Net.Fire("Swing", hint)
end

-- the closest block in the zone we're standing in
local function nearestOre(root: BasePart): BasePart?
	local ores = getOres()
	local zone = Util.ZoneAt(Config, root.Position)
	local data = State.Data
	if not ores or not zone or zone == 0 or not data or zone > data.ZoneLevel then
		return nil
	end
	local best, bestDistance = nil, math.huge
	for _, part in ores:GetChildren() do
		if part:IsA("BasePart") and part:GetAttribute("Zone") == zone then
			local distance = (part.Position - root.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = part, distance
			end
		end
	end
	return best
end

local function nearestCarrier(root: BasePart): BasePart?
	local best, bestDistance = nil, Config.PvP.BonkRange + 6
	for _, other in Players:GetPlayers() do
		if other ~= player and other:GetAttribute("Carrying") then
			local otherRoot = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
			if otherRoot and otherRoot:IsA("BasePart") then
				local distance = (otherRoot.Position - root.Position).Magnitude
				if distance < bestDistance then
					best, bestDistance = otherRoot, distance
				end
			end
		end
	end
	return best
end

local function bindTool(newTool: Tool)
	tool = newTool
end

local function onCharacter(character: Model)
	tool = nil
	setTarget(nil, false)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child.Name == "Pickaxe" then
			bindTool(child)
		end
	end)
	local existing = character:FindFirstChild("Pickaxe")
	if existing and existing:IsA("Tool") then
		bindTool(existing)
	end
end

player.CharacterAdded:Connect(onCharacter)
if player.Character then
	onCharacter(player.Character)
end

-- keep the pickaxe in hand no matter what (the hotbar is hidden)
task.spawn(function()
	while true do
		task.wait(0.5)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 and not character:FindFirstChildOfClass("Tool") then
			local backpack = player:FindFirstChildOfClass("Backpack")
			local pickaxe = backpack and backpack:FindFirstChild("Pickaxe")
			if pickaxe and pickaxe:IsA("Tool") then
				humanoid:EquipTool(pickaxe)
			end
		end
	end
end)

-- tap / click ------------------------------------------------------------------
local touches = {} -- [InputObject] = { Start = Vector3, Time = number, Drag = bool }

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		holdMouse = true
		local picked = pickAt(input.Position)
		if picked then
			setTarget(picked, true)
		end
	elseif input.UserInputType == Enum.UserInputType.Touch then
		touches[input] = { Start = input.Position, Time = os.clock(), Drag = false }
	end
end)

UserInputService.InputChanged:Connect(function(input)
	local touch = touches[input]
	if touch and (input.Position - touch.Start).Magnitude > 16 then
		touch.Drag = true -- that was a camera swipe, not a tap
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		holdMouse = false
	elseif input.UserInputType == Enum.UserInputType.Touch then
		local touch = touches[input]
		touches[input] = nil
		if touch and not touch.Drag and os.clock() - touch.Time < 0.45 then
			local picked = pickAt(input.Position)
			if picked then
				setTarget(picked, true)
			end
		end
	end
end)

-- big MINE button for phones (left of the jump button) ------------------------
local mineGui = New("ScreenGui", {
	Name = "MineButtonGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 6,
	Enabled = UserInputService.TouchEnabled,
	Parent = player:WaitForChild("PlayerGui"),
})
local mineButton = New("TextButton", {
	Name = "Mine",
	AnchorPoint = Vector2.new(1, 1),
	BackgroundColor3 = Color3.fromRGB(255, 170, 50),
	BackgroundTransparency = 0.08,
	AutoButtonColor = false,
	Text = "",
	Parent = mineGui,
}, {
	Lib.Corner(999),
	Lib.Stroke(Color3.new(1, 1, 1), 3, 0.1),
	Lib.Gradient(Color3.new(1, 1, 1), Color3.fromRGB(200, 130, 60)),
})
local mineIcon = Lib.Text({
	Text = "⛏️",
	Size = UDim2.fromScale(0.62, 0.55),
	Position = UDim2.fromScale(0.5, 0.42),
	AnchorPoint = Vector2.new(0.5, 0.5),
	MaxTextSize = 60,
	Parent = mineButton,
})
local mineCaption = Lib.Text({
	Text = "MINE",
	Size = UDim2.fromScale(0.8, 0.22),
	Position = UDim2.fromScale(0.5, 0.78),
	AnchorPoint = Vector2.new(0.5, 0.5),
	MaxTextSize = 18,
	Parent = mineButton,
})
local mineScale = New("UIScale", { Parent = mineButton })

local function layoutMineButton()
	local camera = workspace.CurrentCamera
	local size = if camera then camera.ViewportSize else Vector2.new(800, 400)
	local small = math.min(size.X, size.Y) <= 500
	local diameter = if small then 80 else 118
	mineButton.Size = UDim2.fromOffset(diameter, diameter)
	-- sits just left of Roblox's jump button
	mineButton.Position = if small then UDim2.new(1, -108, 1, -20) else UDim2.new(1, -186, 1, -88)
end
layoutMineButton()
task.spawn(function()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(layoutMineButton)
	end
end)
UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(function()
	mineGui.Enabled = UserInputService.TouchEnabled
end)

mineButton.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
		holdButton = true
		mineScale.Scale = 0.9
	end
end)
mineButton.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
		holdButton = false
		TweenService:Create(mineScale, TweenInfo.new(0.15, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
end)

-- main loop -------------------------------------------------------------------
RunService.Heartbeat:Connect(function()
	-- hover highlight (PC)
	local ores = getOres()
	local hover = mouse.Target
	if not UserInputService.TouchEnabled and hover and ores and hover.Parent == ores and hover ~= targetHighlight.Adornee then
		selection.Adornee = hover
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

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end

	-- hands full while carrying a shard: no mining (but you can still walk to things)
	local carrying = player:GetAttribute("Carrying") ~= nil
	local icon = if carrying then "🏃" elseif feverActive() then "🔥" else "⛏️"
	if mineIcon.Text ~= icon then
		mineIcon.Text = icon
		mineCaption.Text = T(if carrying then "RUN HOME!" else "MINE")
		mineButton.BackgroundTransparency = if carrying then 0.55 else 0.08
	end
	if carrying and target and target.Kind ~= "Shard" then
		setTarget(nil, false)
	end

	-- drop targets that vanished (block broken, player left, meteor gone)
	if target and (not target.Part or not target.Part.Parent) then
		setTarget(nil, false)
	end
	if target and autoWalk and userIsSteering() then
		autoWalk = false -- the player took over
	end

	local wantsMore = (holdMouse or holdButton or (State.AutoMine and State.HasPass("AutoMine"))) and not carrying
	if not target and wantsMore and os.clock() - lastSearch > 0.12 then
		lastSearch = os.clock()
		local meteorActive = workspace:GetAttribute("MeteorState") == "Active"
		local map = workspace:FindFirstChild("Map")
		local drops = map and map:FindFirstChild("Drops")
		local meteor = drops and drops:FindFirstChild("Meteor")
		local carrierRoot = nearestCarrier(root)
		if meteorActive and meteor and meteor:IsA("BasePart") and flatDistance(meteor.Position, root.Position) <= reachFor("Meteor") then
			setTarget({ Kind = "Meteor", Part = meteor }, false)
		elseif carrierRoot then
			setTarget({ Kind = "Player", Part = carrierRoot }, true)
		else
			local ore = nearestOre(root)
			if ore then
				setTarget({ Kind = "Ore", Part = ore }, true)
			end
		end
	end

	if not target then
		return
	end
	local distance = flatDistance(target.Part.Position, root.Position)
	local reach = reachFor(target.Kind)
	if distance > reach then
		if autoWalk then
			if os.clock() - lastMoveTo > 0.25 then
				lastMoveTo = os.clock()
				humanoid:MoveTo(target.Part.Position)
			end
		elseif not wantsMore or target.Kind ~= "Ore" then
			setTarget(nil, false) -- walked away from it
		else
			autoWalk = true
		end
		return
	end
	if autoWalk then
		autoWalk = false
		humanoid:MoveTo(root.Position) -- arrived: stop here
	end
	if target.Kind == "Shard" then
		setTarget(nil, false) -- touching it picks it up
	elseif not carrying then
		swingAt(root, target)
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
Net.On("MineHit", function(part, ratio, crit, damage, isSplash)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return
	end
	squash(part)
	local top = part.Position + Vector3.new(0, 2.5, 0)
	if isSplash then
		burst(top, part.Color, 3)
		return
	end
	showHp(part, ratio)
	burst(top, part.Color, if crit then 10 else 4)
	Lib.PlaySound(hitSoundFor(part:GetAttribute("Ore")))
	if crit then
		Lib.PlaySound("Crit")
		floatText(top, T("💥 CRIT %s", Util.Format(damage or 0)), Color3.fromRGB(255, 120, 60), 44, 5)
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
		floatText(position, (if rainbow then T("🌈 RAINBOW!") else T("✨ GOLDEN!")) .. " +" .. Util.Format(gained), luckyColor, 56, 6)
	else
		burst(position, color, if extra.Fever then 26 else 18)
		floatText(
			position,
			"+" .. Util.Format(gained),
			if extra.Fever then Color3.fromRGB(255, 170, 60) else Color3.fromRGB(255, 255, 255),
			if extra.Fever then 36 else 30
		)
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

Net.On("Bonked", function(attackerName, dropped, hadShard)
	flash.BackgroundTransparency = 0.55
	TweenService:Create(flash, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
	Lib.PlaySound("Bonked")
	shake(0.6, 0.3)
	local hud = Mining.HUD
	if hud then
		if hadShard then
			hud.Toast(T("💥 %s bonked you! You dropped your shard!", attackerName), C.Red)
		end
		if type(dropped) == "number" and dropped > 0 then
			hud.Toast(T("💥 %s bonked you! You dropped %s ore", attackerName, Util.Format(dropped)), C.Red)
		end
	end
end)

Net.On("BonkHit", function(position)
	if typeof(position) == "Vector3" then
		burst(position + Vector3.new(0, 2, 0), Color3.fromRGB(255, 200, 80), 24, 1.4)
		floatText(position, T("💥 BONK!"), Color3.fromRGB(255, 170, 60), 50, 5)
		Lib.PlaySound("Crit")
		shake(0.35, 0.15)
	end
end)

-- crit / fever shockwave ring --------------------------------------------------
Net.On("Shockwave", function(center, radius, fever)
	if typeof(center) ~= "Vector3" then
		return
	end
	local color = if fever then Color3.fromRGB(255, 120, 40) else Color3.fromRGB(255, 220, 120)
	local ring = Instance.new("Part")
	ring.Name = "Shockwave"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.2
	ring.Size = Vector3.new(0.4, 2, 2)
	ring.CFrame = CFrame.new(center.X, 0.6, center.Z) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = workspace
	local size = (radius or 9) * 2
	TweenService:Create(ring, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.4, size, size),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, 0.4)
	Lib.PlaySound("Crit", 0.6, -0.2)
	shake(if fever then 0.3 else 0.45, 0.18)
end)

-- FEVER --------------------------------------------------------------------------
local camera = workspace.CurrentCamera
local BASE_FOV = 70
local feverGlow = New("Frame", {
	Name = "FeverGlow",
	BackgroundColor3 = Color3.fromRGB(255, 110, 30),
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 80,
	Parent = Root.Overlay,
}, {
	New("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.18, 0.85),
			NumberSequenceKeypoint.new(0.82, 0.85),
			NumberSequenceKeypoint.new(1, 0),
		}),
	}),
})
local feverOn = false

local function setFov(fov: number, time: number)
	camera = workspace.CurrentCamera
	if camera then
		TweenService:Create(camera, TweenInfo.new(time, Enum.EasingStyle.Quad), { FieldOfView = fov }):Play()
	end
end

Net.On("Fever", function(duration)
	feverOn = true
	Lib.PlaySound("Lucky")
	Lib.PlaySound("LevelUp", 0.8)
	setFov(BASE_FOV + 10, 0.4)
	shake(0.7, 0.35)
	local hud = Mining.HUD
	if hud and hud.Celebrate then
		hud.Celebrate(T("🔥 FEVER!"), T("2x ore • faster swings • shockwaves!"), Color3.fromRGB(255, 130, 40))
	end
	comboLabel.TextColor3 = Color3.fromRGB(255, 120, 40)
	task.spawn(function()
		local started = os.clock()
		while feverOn and os.clock() - started < (duration or 8) + 10 do
			feverGlow.BackgroundTransparency = 0.55 + math.sin(os.clock() * 8) * 0.12
			RunService.RenderStepped:Wait()
		end
		feverGlow.BackgroundTransparency = 1
	end)
end)

Net.On("FeverEnd", function()
	feverOn = false
	feverGlow.BackgroundTransparency = 1
	setFov(BASE_FOV, 0.6)
end)

-- dash pads ---------------------------------------------------------------------
Net.On("SpeedPad", function()
	Lib.PlaySound("Swing", 1.2, -0.3)
	setFov(BASE_FOV + 14, 0.15)
	task.delay(Config.SpeedPads.Seconds, function()
		setFov(if feverOn then BASE_FOV + 10 else BASE_FOV, 0.5)
	end)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") and not root:FindFirstChild("DashTrail") then
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 1, 0)
		a0.Parent = root
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -1.5, 0)
		a1.Parent = root
		local trail = Instance.new("Trail")
		trail.Name = "DashTrail"
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Color = ColorSequence.new(Color3.fromRGB(90, 230, 255))
		trail.LightEmission = 1
		trail.Lifetime = 0.35
		trail.Transparency = NumberSequence.new(0.2, 1)
		trail.Parent = root
		Debris:AddItem(trail, Config.SpeedPads.Seconds)
		Debris:AddItem(a0, Config.SpeedPads.Seconds)
		Debris:AddItem(a1, Config.SpeedPads.Seconds)
	end
end)

return Mining
