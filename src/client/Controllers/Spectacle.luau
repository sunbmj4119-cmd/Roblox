--[[
	Spectacle: the "clip it!" moments.
	  * 🎉 confetti (lucky block prizes, prank pets) and 💥 booms (prank blocks)
	  * a pillar of light where someone hatched a HUGE / TITANIC / secret pet
	  * 🌙 Thief Night turns the sky dark for everyone
	  * 🎉 party: a little fireworks show now and then
]]
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Client = script.Parent.Parent
local Net = require(Client.Net)
local Lib = require(Client.UI.Lib)

local Spectacle = {}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 90)),
	ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 220, 80)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(90, 230, 120)),
	ColorSequenceKeypoint.new(0.75, Color3.fromRGB(80, 170, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 110, 255)),
})

local function anchorAt(position: Vector3): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.one
	p.CFrame = CFrame.new(position)
	p.Parent = workspace
	return p
end

local function burst(position: Vector3, colors: ColorSequence, amount: number, speed: number, size: number)
	local holder = anchorAt(position + Vector3.new(0, 3, 0))
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARKLE
	emitter.Color = colors
	emitter.LightEmission = 0.6
	emitter.Size = NumberSequence.new(size, 0)
	emitter.Lifetime = NumberRange.new(1.2, 2.2)
	emitter.Speed = NumberRange.new(speed * 0.6, speed)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -30, 0)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-200, 200)
	emitter.Rate = 0
	emitter.Parent = holder
	emitter:Emit(amount)
	Debris:AddItem(holder, 3)
end

-- how loud something at this spot is for us (far away = quiet / silent)
local function nearVolume(position: Vector3): number
	local camera = workspace.CurrentCamera
	if not camera then
		return 1
	end
	local distance = (camera.CFrame.Position - position).Magnitude
	return math.clamp(1 - (distance - 30) / 90, 0, 1)
end

Net.On("Confetti", function(position)
	if typeof(position) ~= "Vector3" then
		return
	end
	burst(position, RAINBOW, 60, 30, 0.8)
	local volume = nearVolume(position)
	if volume > 0 then
		Lib.PlaySound("Pop", volume)
		Lib.PlaySound("Success", volume * 0.8)
	end
end)

Net.On("Boom", function(position)
	if typeof(position) ~= "Vector3" then
		return
	end
	burst(position, ColorSequence.new(Color3.fromRGB(255, 140, 40), Color3.fromRGB(60, 50, 50)), 45, 40, 1.4)
	local volume = nearVolume(position)
	if volume > 0 then
		Lib.PlaySound("Boom", volume)
	end
end)

-- a pillar of light on a lucky player (everyone sees it)
Net.On("BigHatch", function(userId, kind)
	local other = type(userId) == "number" and Players:GetPlayerByUserId(userId)
	local root = other and other.Character and other.Character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local color = if kind == "Titanic"
		then Color3.fromRGB(255, 120, 60)
		elseif kind == "Huge" then Color3.fromRGB(255, 210, 80)
		elseif kind == "Meteor" then Color3.fromRGB(255, 150, 70)
		elseif kind == "Evolve" then Color3.fromRGB(150, 220, 255)
		else Color3.fromRGB(200, 120, 255)
	local pillar = Instance.new("Part")
	pillar.Anchored = true
	pillar.CanCollide = false
	pillar.CanQuery = false
	pillar.CanTouch = false
	pillar.Shape = Enum.PartType.Cylinder
	pillar.Material = Enum.Material.Neon
	pillar.Color = color
	pillar.Transparency = 0.35
	pillar.Size = Vector3.new(400, 5, 5)
	pillar.CFrame = CFrame.new(root.Position + Vector3.new(0, 200, 0)) * CFrame.Angles(0, 0, math.rad(90))
	pillar.Parent = workspace
	burst(root.Position, RAINBOW, if kind == "Titanic" then 160 else 80, 45, 1)
	if other ~= Players.LocalPlayer then
		Lib.PlaySound("Cheer", 0.8) -- (the lucky player hears the fanfare on their card)
	end
	TweenService:Create(pillar, TweenInfo.new(8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Transparency = 1,
		Size = Vector3.new(400, 0.5, 0.5),
	}):Play()
	Debris:AddItem(pillar, 8.5)
end)

Net.On("Party", function()
	Lib.PlaySound("Cheer")
end)

-- 🌙 Thief Night is coming (20s): a short alarm so everyone runs home
Net.On("RaidWarning", function()
	for i = 0, 1 do
		task.delay(i * 0.6, function()
			Lib.PlaySound("Alarm", 0.7)
		end)
	end
end)

-- 🌙 Thief Night: the sky goes dark while it lasts
local normalClock = nil
local function refreshNight()
	local night = workspace:GetAttribute("EventId") == "ThiefNight"
	if night and normalClock == nil then
		normalClock = Lighting.ClockTime
		TweenService:Create(Lighting, TweenInfo.new(3), { ClockTime = 0.3 }):Play()
	elseif not night and normalClock ~= nil then
		TweenService:Create(Lighting, TweenInfo.new(3), { ClockTime = normalClock }):Play()
		normalClock = nil
	end
end
workspace:GetAttributeChangedSignal("EventId"):Connect(refreshNight)
refreshNight()

-- 🎉 party: fireworks over the hub every few seconds
task.spawn(function()
	while true do
		task.wait(4)
		local partyEnd = workspace:GetAttribute("PartyEnd") or 0
		if partyEnd > workspace:GetServerTimeNow() then
			local spot = Vector3.new(math.random(-60, 60), 40 + math.random(0, 20), math.random(-60, 60))
			burst(spot, RAINBOW, 70, 35, 1.2)
		end
	end
end)

return Spectacle
