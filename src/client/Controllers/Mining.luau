--[[
	Client mining: pickaxe input (click/tap/hold), auto-mine pass, target
	highlight + HP bar, hit/break effects, PvP knockback feedback.
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

local Mining = {}

local tool: Tool? = nil
local holding = false
local lastSwing = 0
local oresFolder = nil

local function getOres()
	if oresFolder and oresFolder.Parent then
		return oresFolder
	end
	local map = workspace:FindFirstChild("Map")
	oresFolder = map and map:FindFirstChild("Ores")
	return oresFolder
end

-- selection + hp bar ------------------------------------------------------
local selection = Instance.new("SelectionBox")
selection.LineThickness = 0.06
selection.Color3 = Color3.fromRGB(255, 230, 120)
selection.SurfaceTransparency = 1
selection.Parent = workspace

local hpGui = Lib.New("BillboardGui", {
	Size = UDim2.fromOffset(120, 18),
	StudsOffsetWorldSpace = Vector3.new(0, 4, 0),
	AlwaysOnTop = true,
	Enabled = false,
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
	setHp(ratio, if ore then ore.Name else "", if ratio > 0.5 then C.Green elseif ratio > 0.25 then C.Gold else C.Red)
	hpHideAt = os.clock() + 2
end

-- effects ----------------------------------------------------------------
local function burst(position: Vector3, color: Color3, amount: number)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Transparency = 1
	part.Size = Vector3.one
	part.Position = position
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	emitter.Speed = NumberRange.new(10, 22)
	emitter.Lifetime = NumberRange.new(0.4, 0.8)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -40, 0)
	emitter.Rate = 0
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.Parent = part
	part.Parent = workspace
	emitter:Emit(amount)
	Debris:AddItem(part, 1.5)
end

local function floatText(position: Vector3, text: string, color: Color3)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.Position = position + Vector3.new(0, 3, 0)
	anchor.Parent = workspace
	local gui = Lib.New("BillboardGui", { Size = UDim2.fromOffset(160, 40), AlwaysOnTop = true, Adornee = anchor, Parent = anchor })
	local label = Lib.Text({ Text = text, TextColor3 = color, Size = UDim2.fromScale(1, 1), MaxTextSize = 30, Parent = gui })
	TweenService:Create(anchor, TweenInfo.new(1), { Position = anchor.Position + Vector3.new(0, 4, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1 }):Play()
	Debris:AddItem(anchor, 1.1)
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
	Lib.PlaySound(Config.Sounds.Swing, 0.25)
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

	if holding then
		swing(true)
	elseif State.AutoMine and State.HasPass("AutoMine") then
		swing(false)
	end
end)

-- server feedback ----------------------------------------------------------
Net.On("MineHit", function(part, ratio)
	if typeof(part) == "Instance" and part:IsA("BasePart") then
		showHp(part, ratio)
		burst(part.Position + Vector3.new(0, 2.5, 0), part.Color, 4)
	end
end)

Net.On("MineBreak", function(position, oreId, gained, extra)
	local ore = Config.Ores[oreId]
	local color = if ore then ore.Color else Color3.new(1, 1, 1)
	burst(position, color, 18)
	Lib.PlaySound(Config.Sounds.Break, 0.4)
	hpGui.Enabled = false
	floatText(position, "+" .. Util.Format(gained) .. " ore", Color3.fromRGB(255, 255, 255))
	if extra and extra.Gems then
		floatText(position + Vector3.new(0, 2, 0), "+" .. extra.Gems .. " 💎", C.Gems)
	end
	if extra and extra.Stardust then
		floatText(position + Vector3.new(0, 2, 0), "+" .. extra.Stardust .. " ✨", C.Stardust)
	end
end)

local flash = Lib.New("Frame", {
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
	local hud = Mining.HUD
	if hud then
		hud.Toast(string.format("💥 %s bonked you! You dropped %s ore", attackerName, Util.Format(dropped)), C.Red)
	end
end)

return Mining
