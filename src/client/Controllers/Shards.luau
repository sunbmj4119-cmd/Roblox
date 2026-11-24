--[[
	Client side of the star-shard loop:
	* falling-star streaks + impact FX
	* carry banner ("run home!"), delivery / theft / recovery celebrations
	* base alarm when a thief grabs one of your shards
	* base prompts: you only see "Sell"/"Buy" on your own base and "Steal"
	  on other people's (and not while they're locked); your own lock shield
	  never blocks you
	* displayed / dropped shards slowly spin and bob
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
local Lib = require(Client.UI.Lib)
local Root = require(Client.UI.Root)

local player = Players.LocalPlayer
local C = Lib.Colors
local New = Lib.New
local T = Lib.T

local Shards = {}

local function rarity(id: string)
	return Config.Shards.Rarities[id] or Config.Shards.Rarities.Common
end

-- colour of a value tier 1..7 (Common .. Secret)
local TIER_COLORS = {}
for _, def in Config.Rarities do
	TIER_COLORS[def.Order] = def.Color
end
local function tierColor(tier: number?): Color3
	return TIER_COLORS[math.clamp(tier or 1, 1, 7)] or C.Gold
end

local function hud()
	return Shards.HUD
end

local function toast(text: string, color: Color3?)
	local h = hud()
	if h then
		h.Toast(text, color)
	end
end

local function celebrate(title: string, sub: string, color: Color3, confetti: boolean?)
	local h = hud()
	if h and h.Celebrate then
		h.Celebrate(title, sub, color, confetti)
	end
end

---------------------------------------------------------------------------
-- carry banner (bottom center, above the action row)
---------------------------------------------------------------------------
local cluster = Root.Cluster("Carry", Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -152), UDim2.fromOffset(500, 58))
local banner = New("Frame", {
	BackgroundColor3 = Color3.fromRGB(20, 22, 36),
	BackgroundTransparency = 0.1,
	Size = UDim2.fromScale(1, 1),
	Visible = false,
	Parent = cluster,
}, { Lib.Corner(14), Lib.Stroke(C.Gold, 3, 0) })
local bannerTitle = Lib.Text({
	Text = "",
	Size = UDim2.new(1, -16, 0, 30),
	Position = UDim2.fromOffset(8, 3),
	MaxTextSize = 24,
	Parent = banner,
})
local bannerSub = Lib.Text({
	Text = "",
	Font = Lib.BodyFont,
	TextColor3 = C.Sub,
	Size = UDim2.new(1, -16, 0, 18),
	Position = UDim2.fromOffset(8, 35),
	MaxTextSize = 14,
	Parent = banner,
})
local bannerStroke = banner:FindFirstChildOfClass("UIStroke") :: UIStroke
local bannerScale = New("UIScale", { Parent = banner })

local function refreshBanner()
	local carrying = player:GetAttribute("Carrying")
	if type(carrying) ~= "string" then
		banner.Visible = false
		return
	end
	local color = tierColor(player:GetAttribute("CarryTier"))
	local stolen = player:GetAttribute("CarryStolen") == true
	bannerTitle.Text = T(if stolen then "🏃 STOLEN %s - RUN HOME! 🏠" else "🌠 %s - RUN HOME! 🏠", T(carrying))
	bannerTitle.TextColor3 = color
	bannerSub.Text = T("You're slower and anyone can bonk you - don't get caught!")
	bannerStroke.Color = color
	banner.Visible = true
	bannerScale.Scale = 1.25
	TweenService:Create(bannerScale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end
player:GetAttributeChangedSignal("Carrying"):Connect(refreshBanner)
player:GetAttributeChangedSignal("CarryStolen"):Connect(refreshBanner)
refreshBanner()

RunService.RenderStepped:Connect(function()
	if banner.Visible then
		bannerStroke.Thickness = 3 + math.sin(os.clock() * 6) * 1.2
	end
end)

---------------------------------------------------------------------------
-- events
---------------------------------------------------------------------------
Net.On("CarryStart", function(name, fromName, tier)
	Lib.PlaySound("Lucky", 0.8)
	if not fromName then
		toast(T("🌠 You got a %s! Bring it to your base 🏠", T(tostring(name))), tierColor(tier))
	end
end)

Net.On("CarryLost", function(name)
	toast(T("💥 You dropped the %s!", T(tostring(name))), C.Red)
end)

-- star eggs show the normal hatch animation (HatchResult); stolen pets get a cheer
-- (stolen pets get the reveal card from HatchResult - it says where the pet went)
Net.On("ShardDelivered", function(_name, _result) end)

Net.On("ShardRecovered", function(name)
	Lib.PlaySound("Reward")
	celebrate(T("🛡️ RECOVERED!"), T(tostring(name)), C.Cyan)
end)

Net.On("BaseCollected", function(amount)
	Lib.PlaySound("CoinBig")
	local h = hud()
	if h and h.FlyCoins then
		h.FlyCoins(amount)
	end
	toast("+💰" .. Util.Format(amount), C.Coins)
end)

Net.On("OfflineEarnings", function(amount, seconds)
	local minutes = math.floor((seconds or 0) / 60)
	celebrate(
		T("💤 Your base earned 💰%s", Util.Format(amount)),
		T("while you were away (%d min) - collect it at your base!", minutes),
		C.Coins,
		true
	)
end)

-- base alarm: a thief took one of your shards
local alarm = New("Frame", {
	BackgroundColor3 = Color3.fromRGB(255, 30, 50),
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 85,
	Parent = Root.Overlay,
})
Net.On("BaseAlarm", function(thiefName, shardName)
	Lib.PlaySound("Bonked", 1.2)
	celebrate(T("🚨 THIEF!"), T("%s grabbed your %s - bonk them!", thiefName, T(shardName)), C.Red)
	task.spawn(function()
		for _ = 1, 4 do
			alarm.BackgroundTransparency = 0.6
			TweenService:Create(alarm, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
			Lib.PlaySound("Alarm", 0.8)
			task.wait(0.45)
		end
	end)
end)

-- jump pads / traps / guardians / likes -----------------------------------------
Net.On("Launch", function(velocity)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") and typeof(velocity) == "Vector3" then
		if humanoid then
			humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		end
		root.AssemblyLinearVelocity = velocity
		Lib.PlaySound("Swing", 1.3, 0.4)
	end
end)

local stunFrame = New("Frame", {
	BackgroundColor3 = Color3.fromRGB(255, 230, 80),
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 84,
	Parent = Root.Overlay,
})
Net.On("Stunned", function(seconds)
	Lib.PlaySound("Crit", 1, 0.3)
	stunFrame.BackgroundTransparency = 0.5
	TweenService:Create(stunFrame, TweenInfo.new(seconds or 2), { BackgroundTransparency = 1 }):Play()
end)

Net.On("GuardianChase", function(seconds)
	Lib.PlaySound("MeteorWarn", 0.8)
	celebrate(T("🗿 THE GUARDIAN WOKE UP!"), T("Run! It chases you for %d seconds", seconds or 12), Color3.fromRGB(255, 150, 80))
end)

Net.On("CaughtByGuardian", function(name)
	Lib.PlaySound("Bonked")
	toast(T("🗿 The guardian took the %s back!", T(tostring(name))), C.Red)
end)

Net.On("BaseLiked", function()
	Lib.PlaySound("Reward", 0.8, 0.2)
end)

---------------------------------------------------------------------------
-- falling stars: a bright streak from the sky, then a flash + shake
---------------------------------------------------------------------------
local function shakeCamera(strength: number, duration: number)
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

Net.On("StarFall", function(position, id, flight)
	if typeof(position) ~= "Vector3" then
		return
	end
	local def = rarity(id)
	local duration = flight or 1.8
	local landing = position + Vector3.new(0, 5, 0)
	local start = landing + Vector3.new(90, 320, 70)

	local star = Instance.new("Part")
	star.Name = "FallingStar"
	star.Shape = Enum.PartType.Ball
	star.Size = Vector3.one * 5
	star.Material = Enum.Material.Neon
	star.Color = def.Color
	star.Anchored = true
	star.CanCollide = false
	star.CanQuery = false
	star.CanTouch = false
	star.CFrame = CFrame.new(start)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 2, 0)
	a0.Parent = star
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -2, 0)
	a1.Parent = star
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(Color3.new(1, 1, 1), def.Color)
	trail.LightEmission = 1
	trail.Lifetime = 0.6
	trail.WidthScale = NumberSequence.new(1, 0)
	trail.Transparency = NumberSequence.new(0, 1)
	trail.FaceCamera = true
	trail.Parent = star
	local light = Instance.new("PointLight")
	light.Color = def.Color
	light.Range = 40
	light.Brightness = 4
	light.Parent = star
	star.Parent = workspace
	Lib.PlaySound("Swing", 1.5, -0.5)
	TweenService:Create(star, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(landing) })
		:Play()

	task.delay(duration, function()
		star:Destroy()
		-- impact
		local flashPart = Instance.new("Part")
		flashPart.Shape = Enum.PartType.Ball
		flashPart.Anchored = true
		flashPart.CanCollide = false
		flashPart.CanQuery = false
		flashPart.CanTouch = false
		flashPart.Material = Enum.Material.Neon
		flashPart.Color = def.Color
		flashPart.Size = Vector3.one * 4
		flashPart.CFrame = CFrame.new(landing)
		flashPart.Parent = workspace
		TweenService:Create(flashPart, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.one * 26,
			Transparency = 1,
		}):Play()
		Debris:AddItem(flashPart, 0.5)
		Lib.PlaySound("Break", 1.3, -0.3)
		Lib.PlaySound("Crit", 0.9, -0.4)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local distance = (root.Position - landing).Magnitude
			if distance < 120 then
				shakeCamera(math.clamp(1.2 - distance / 100, 0.2, 1.2), 0.4)
			end
		end
	end)
end)

---------------------------------------------------------------------------
-- base prompts / shields / spinning shards
---------------------------------------------------------------------------
local function refreshBases()
	local map = workspace:FindFirstChild("Map")
	local bases = map and map:FindFirstChild("Bases")
	if not bases then
		return
	end
	local serverNow = workspace:GetServerTimeNow()
	for _, plot in bases:GetChildren() do
		local ownerId = plot:GetAttribute("OwnerId")
		if type(ownerId) == "number" then
			local mine = ownerId == player.UserId
			local locked = (plot:GetAttribute("LockedUntil") or 0) > serverNow
			-- shields (newbie / after a theft / being robbed) hide the steal prompts,
			-- except for the victim's revenge (locks and shields don't stop it)
			local protection = plot:GetAttribute("Protection") or ""
			local revengeHere = player:GetAttribute("RevengeTarget") == ownerId and (player:GetAttribute("RevengeUntil") or 0) > serverNow
			local robbing = plot:GetAttribute("Robbing") == true
			local open = not robbing and ((protection == "" and not locked) or revengeHere)
			for _, prompt in plot:GetDescendants() do
				if prompt:IsA("ProximityPrompt") then
					local role = prompt:GetAttribute("Role")
					local enabled = if role == "Owner"
						then mine
						elseif role == "Thief" then not mine and open
						elseif role == "Visitor" then not mine
						else true
					if prompt.Enabled ~= enabled then
						prompt.Enabled = enabled
					end
				end
			end
			local shield = plot:FindFirstChild("Shield")
			if shield and shield:IsA("BasePart") and (mine or revengeHere) and shield.CanCollide then
				shield.CanCollide = false -- your own lock never blocks you (nor does it stop revenge)
			end
		end
	end
end

task.spawn(function()
	while true do
		local ok, err = pcall(refreshBases)
		if not ok then
			warn("[Shards] base refresh failed: " .. tostring(err))
		end
		task.wait(0.5)
	end
end)

-- spin + bob: displayed and dropped shards (each keeps its server pivot)
local spinning = {} -- [model] = base pivot
local function track(inst: Instance)
	if inst:IsA("Model") and inst:GetAttribute("Spin") then
		spinning[inst] = inst:GetPivot()
		inst.AncestryChanged:Connect(function()
			if not inst:IsDescendantOf(workspace) then
				spinning[inst] = nil
			end
		end)
	end
end
task.spawn(function()
	local map = workspace:WaitForChild("Map", 60)
	if not map then
		return
	end
	for _, name in { "Bases", "Shards" } do
		local folder = map:WaitForChild(name, 30)
		if folder then
			folder.DescendantAdded:Connect(function(inst)
				task.defer(track, inst)
			end)
			for _, inst in folder:GetDescendants() do
				track(inst)
			end
		end
	end
end)
RunService.RenderStepped:Connect(function()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local eye = camera.CFrame.Position
	local t = os.clock()
	for model, pivot in spinning do
		-- only animate what's near the camera (cheap on phones)
		if model.Parent and (pivot.Position - eye).Magnitude < 140 then
			if model:GetAttribute("PetId") then
				-- pets on pedestals: happy bounce + little sway (they face the street)
				local phase = t * 3 + pivot.X
				local hop = math.abs(math.sin(phase)) * 0.5
				model:PivotTo(pivot * CFrame.new(0, hop, 0) * CFrame.Angles(0, math.sin(phase * 0.5) * 0.35, math.sin(phase) * 0.06))
				if model:GetAttribute("Variant") == "Rainbow" and model.PrimaryPart then
					model.PrimaryPart.Color = Color3.fromHSV((t * 0.3) % 1, 0.7, 1)
				end
			else
				model:PivotTo(pivot * CFrame.new(0, math.sin(t * 2 + pivot.X) * 0.4, 0) * CFrame.Angles(0, t * 1.6, 0))
			end
		end
	end
end)

return Shards
