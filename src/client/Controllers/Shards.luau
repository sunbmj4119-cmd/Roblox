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
local State = require(Client.State)
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
	local def = rarity(carrying)
	local stolen = player:GetAttribute("CarryStolen") == true
	bannerTitle.Text = T(if stolen then "🏃 STOLEN %s - RUN HOME! 🏠" else "🌠 %s - RUN HOME! 🏠", T(def.Name))
	bannerTitle.TextColor3 = def.Color
	bannerSub.Text = T("You're slower and anyone can bonk you - don't get caught!")
	bannerStroke.Color = def.Color
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
Net.On("CarryStart", function(id, fromName)
	Lib.PlaySound("Lucky", 0.8)
	if not fromName then
		toast(T("🌠 You got a %s! Bring it to your base 🏠", T(rarity(id).Name)), rarity(id).Color)
	end
end)

Net.On("CarryLost", function(id)
	toast(T("💥 You dropped the %s!", T(rarity(id).Name)), C.Red)
end)

Net.On("ShardDelivered", function(id, result, coins)
	local def = rarity(id)
	local data, derived = State.Data, State.Derived
	local income = Util.ShardIncome(Config, id, if data then data.ZoneLevel else 1) * ((derived and derived.CoinMult) or 1)
	local sub
	if result == "Sold" then
		sub = T("Base full - sold it for 💰%s. Buy more pedestals!", Util.Format(coins or 0))
	elseif result == "Replaced" then
		sub = T("Replaced your weakest shard (+💰%s)", Util.Format(coins or 0))
	else
		sub = T("+💰%s every second - even offline!", Util.Format(income))
	end
	Lib.PlaySound("LevelUp")
	celebrate(T("🏠 %s SECURED!", T(def.Name)), sub, def.Color, Util.ShardIndex(Config, id) >= 3)
end)

Net.On("ShardRecovered", function(id)
	Lib.PlaySound("Reward")
	celebrate(T("🛡️ RECOVERED!"), T(rarity(id).Name), C.Cyan)
end)

Net.On("BaseCollected", function(amount)
	Lib.PlaySound("Coin", 1, 0.2)
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
			Lib.PlaySound("Swing", 0.6, 0.5)
			task.wait(0.45)
		end
	end)
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
			for _, prompt in plot:GetDescendants() do
				if prompt:IsA("ProximityPrompt") then
					local role = prompt:GetAttribute("Role")
					local enabled = if role == "Owner" then mine elseif role == "Thief" then not mine and not locked else true
					if prompt.Enabled ~= enabled then
						prompt.Enabled = enabled
					end
				end
			end
			local shield = plot:FindFirstChild("Shield")
			if shield and shield:IsA("BasePart") and mine and shield.CanCollide then
				shield.CanCollide = false -- your own lock never blocks you
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
			model:PivotTo(pivot * CFrame.new(0, math.sin(t * 2 + pivot.X) * 0.4, 0) * CFrame.Angles(0, t * 1.6, 0))
		end
	end
end)

return Shards
