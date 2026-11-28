--[[
	Meteor event UI: always-visible countdown (anticipation) with WHAT is
	falling WHERE ("🔥 Big Lava Meteor -> Hub"), "GO" button during the
	warning, live top-5 ranking with your own place, camera shake on impact,
	"grab the eggs!" after the burst and the result popup (+ meteor index).
]]
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = require(Shared.Util)

local Client = script.Parent.Parent
local Net = require(Client.Net)
local State = require(Client.State)
local Lib = require(Client.UI.Lib)
local Root = require(Client.UI.Root)
local HUD = require(Client.Controllers.HUD)

local New, C = Lib.New, Lib.Colors
local T = Lib.T
local player = Players.LocalPlayer
local MeteorUI = {}

-- countdown pill ---------------------------------------------------------
local top = Root.Cluster("Meteor", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 8), UDim2.fromOffset(380, 44))
local pill = New("Frame", {
	BackgroundColor3 = Color3.fromRGB(20, 22, 34),
	BackgroundTransparency = 0.15,
	Size = UDim2.fromOffset(250, 40),
	Position = UDim2.fromOffset(0, 2),
	Parent = top,
}, { Lib.Corner(20), Lib.Stroke(Color3.fromRGB(255, 150, 60), 2, 0) })
local pillText = Lib.Text({
	Text = "☄️ Meteor",
	TextColor3 = Color3.fromRGB(255, 190, 120),
	Size = UDim2.new(1, -16, 1, -8),
	Position = UDim2.fromOffset(8, 4),
	MaxTextSize = 20,
	Parent = pill,
})
local goButton = Lib.Button({
	Text = "GO ☄️",
	Color = Color3.fromRGB(255, 120, 40),
	Size = UDim2.fromOffset(120, 42),
	Position = UDim2.fromOffset(258, 1),
	Parent = top,
	OnClick = function()
		Net.Fire("GoToMeteor")
	end,
})
goButton.Visible = false
local summonButton = Lib.Button({
	Text = "☄️+",
	Color = Color3.fromRGB(150, 80, 40),
	Size = UDim2.fromOffset(56, 42),
	Position = UDim2.fromOffset(258, 1),
	TextSize = 18,
	Parent = top,
	OnClick = function()
		Net.Fire("BuyProduct", "SummonMeteor")
	end,
})

-- live ranking -------------------------------------------------------------
local rankFrame = New("Frame", {
	BackgroundColor3 = Color3.fromRGB(20, 22, 34),
	BackgroundTransparency = 0.1,
	Size = UDim2.fromOffset(240, 250),
	LayoutOrder = 10,
	Visible = false,
	Parent = HUD.RightColumn,
}, { Lib.Corner(14), Lib.Stroke(Color3.fromRGB(255, 150, 60), 2.5, 0) })
Lib.Text({
	Text = "☄️ LIVE RANKING",
	TextColor3 = Color3.fromRGB(255, 180, 100),
	Size = UDim2.new(1, -16, 0, 28),
	Position = UDim2.fromOffset(8, 6),
	MaxTextSize = 22,
	Parent = rankFrame,
})
local rankLines = {}
for i = 1, 5 do
	rankLines[i] = Lib.Text({
		Text = "",
		Size = UDim2.new(1, -16, 0, 26),
		Position = UDim2.fromOffset(8, 36 + (i - 1) * 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 19,
		TextColor3 = if i == 1
			then C.Gold
			elseif i == 2 then Color3.fromRGB(220, 225, 240)
			elseif i == 3 then Color3.fromRGB(230, 150, 80)
			else C.Text,
		Parent = rankFrame,
	})
end
local myLine = Lib.Text({
	Text = "",
	TextColor3 = C.Green,
	Size = UDim2.new(1, -16, 0, 30),
	Position = UDim2.fromOffset(8, 192),
	MaxTextSize = 22,
	Parent = rankFrame,
})
local hint = Lib.Text({
	Text = "Hit the meteor with your pickaxe!",
	Font = Lib.BodyFont,
	TextColor3 = C.Sub,
	Size = UDim2.new(1, -16, 0, 18),
	Position = UDim2.fromOffset(8, 224),
	MaxTextSize = 13,
	Parent = rankFrame,
})

local MEDALS = { "🥇", "🥈", "🥉", "4.", "5." }
Net.On("MeteorRank", function(list, myPlace, myScore)
	local entries = if type(list) == "table" then list else {}
	for i = 1, 5 do
		local entry = entries[i]
		rankLines[i].Text = if entry
			then string.format("%s %s  <font color='#BBBBBB'>%d</font>", MEDALS[i], entry.Name, entry.Score)
			else ""
	end
	if myPlace then
		myLine.Text = T("You: #%d  •  %d pts", myPlace, myScore or 0)
		hint.Text = if myPlace <= 3 then T("Top 3 wins big rewards - keep going!") else T("Hit harder to reach the top 3!")
	else
		myLine.Text = T("You: not participating")
		hint.Text = T("Hit the meteor with your pickaxe!")
	end
end)

-- result popup ---------------------------------------------------------------
local resultCluster =
	Root.Cluster("MeteorResult", Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.42), UDim2.fromOffset(460, 220), Root.Overlay)
local result = New("Frame", {
	BackgroundColor3 = C.Panel,
	Size = UDim2.fromScale(1, 1),
	Visible = false,
	Parent = resultCluster,
}, { Lib.Corner(20), Lib.Stroke(C.Gold, 3, 0) })
local resultTitle =
	Lib.Text({ Text = "", Size = UDim2.new(1, -20, 0, 50), Position = UDim2.fromOffset(10, 14), MaxTextSize = 40, Parent = result })
local resultBody = Lib.Text({
	Text = "",
	Size = UDim2.new(1, -20, 0, 70),
	Position = UDim2.fromOffset(10, 70),
	TextWrapped = true,
	MaxTextSize = 24,
	Parent = result,
})
Lib.Button({
	Text = "Awesome!",
	Size = UDim2.fromOffset(180, 46),
	Position = UDim2.new(0.5, -90, 1, -60),
	Parent = result,
	OnClick = function()
		result.Visible = false
	end,
})

Net.On("MeteorResult", function(info)
	if type(info) ~= "table" then
		return
	end
	local placeText = if info.Place == 1
		then T("🥇 1ST PLACE!")
		elseif info.Place == 2 then T("🥈 2ND PLACE!")
		elseif info.Place == 3 then T("🥉 3RD PLACE!")
		else T("#%d of %d", info.Place, info.Total)
	resultTitle.Text = placeText
	resultTitle.TextColor3 = if info.Place <= 3 then C.Gold else C.Text
	local parts = { "+" .. Util.Format(info.Stardust) .. " ✨" }
	if info.Gems > 0 then
		table.insert(parts, "+" .. Util.Format(info.Gems) .. " 💎")
	end
	table.insert(parts, T("+%d ranked pts", info.Points))
	local extra = ""
	if not info.Destroyed then
		extra = "\n<font color='#FF8888'>" .. T("The meteor escaped - half rewards") .. "</font>"
	elseif info.FirstCrack and type(info.Kind) == "string" then
		extra = "\n<font color='#FFD25A'>" .. T("📖 NEW in your meteor index: %s %s!", info.Icon or "☄️", info.Kind) .. "</font>"
	else
		extra = "\n<font color='#9BE7FF'>" .. T("🥚 Now grab a star egg and run home!") .. "</font>"
	end
	resultBody.Text = table.concat(parts, "   ") .. extra
	result.Visible = true
	Lib.Pop(result)
	Lib.PlaySound(if info.Place <= 3 then "RankUp" else "Reward")
	task.delay(7, function()
		result.Visible = false
	end)
end)

-- hit feedback -------------------------------------------------------------------
local lastHitSound = 0
Net.On("MeteorHit", function(score)
	if os.clock() - lastHitSound > 0.15 then
		lastHitSound = os.clock()
		Lib.PlaySound("HitStone", 0.8)
	end
	if type(score) == "number" then
		myLine.Text = T("+%s pts!", string.format("%.1f", score))
	end
end)

-- camera shake on impact -------------------------------------------------------
-- 💥 impact: an expanding shockwave ring + a dust cloud where it hit
local function shockwave(position: Vector3)
	local ground = Vector3.new(position.X, 0.3, position.Z)
	local ring = Instance.new("Part")
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 170, 80)
	ring.Transparency = 0.2
	ring.Size = Vector3.new(0.4, 6, 6)
	ring.CFrame = CFrame.new(ground) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = workspace
	TweenService:Create(ring, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.2, 90, 90),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, 0.9)
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(16, 1, 16)
	holder.CFrame = CFrame.new(ground + Vector3.new(0, 1, 0))
	holder.Parent = workspace
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Color = ColorSequence.new(Color3.fromRGB(170, 150, 130), Color3.fromRGB(110, 95, 85))
	dust.Size = NumberSequence.new(4, 12)
	dust.Transparency = NumberSequence.new(0.3, 1)
	dust.Lifetime = NumberRange.new(1.5, 2.5)
	dust.Speed = NumberRange.new(18, 34)
	dust.SpreadAngle = Vector2.new(80, 10)
	dust.EmissionDirection = Enum.NormalId.Top
	dust.Drag = 3
	dust.Rate = 0
	dust.Parent = holder
	dust:Emit(40)
	Debris:AddItem(holder, 3)
end

Net.On("MeteorImpact", function(position)
	Lib.PlaySound("Impact")
	if typeof(position) == "Vector3" then
		shockwave(position)
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not humanoid or not root or typeof(position) ~= "Vector3" then
		return
	end
	local distance = (root.Position - position).Magnitude
	local strength = math.clamp(1 - distance / 300, 0.15, 1) * 1.6
	local start = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		if t > 0.8 then
			humanoid.CameraOffset = Vector3.zero
			connection:Disconnect()
			return
		end
		local fade = 1 - t / 0.8
		humanoid.CameraOffset = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * strength * fade
	end)
end)

-- countdown loop ---------------------------------------------------------------
local lastStateName = "Idle"
task.spawn(function()
	while true do
		task.wait(0.25)
		local stateName = workspace:GetAttribute("MeteorState") or "Idle"
		if stateName ~= lastStateName then
			if stateName == "Warning" then
				-- siren-like warning: three low hits
				for i = 0, 2 do
					task.delay(i * 0.45, function()
						Lib.PlaySound("MeteorWarn")
					end)
				end
			end
			lastStateName = stateName
		end
		local now = State.Now()
		local stroke = pill:FindFirstChildOfClass("UIStroke")
		if stateName == "Idle" then
			local nextAt = workspace:GetAttribute("MeteorNext") or now
			pillText.Text = T("☄️ Next meteor in %s", Util.FormatTime(nextAt - now))
			pillText.TextColor3 = Color3.fromRGB(255, 190, 120)
			stroke.Color = Color3.fromRGB(255, 150, 60)
			goButton.Visible = false
			summonButton.Visible = true
			rankFrame.Visible = false
		elseif stateName == "Warning" or stateName == "Falling" then
			local warnEnd = workspace:GetAttribute("MeteorWarnEnd") or now
			local blink = math.floor(os.clock() * 3) % 2 == 0
			local golden = workspace:GetAttribute("MeteorGolden") == true
			local icon = workspace:GetAttribute("MeteorIcon") or "☄️"
			local site = workspace:GetAttribute("MeteorSite") or ""
			local siteZone = workspace:GetAttribute("MeteorSiteZone") or 0
			local data = State.Data
			local locked = data ~= nil and siteZone > data.ZoneLevel
			pillText.Text = if stateName == "Falling"
				then T("☄️ IMPACT!")
				else T(
					"%s%s %s → %s  %s",
					if golden then "✨" else "",
					icon,
					workspace:GetAttribute("MeteorKind") or "",
					site,
					Util.FormatTime(warnEnd - now)
				)
			pillText.TextColor3 = if golden then C.Gold elseif blink then C.Red else Color3.fromRGB(255, 220, 120)
			stroke.Color = if golden then C.Gold else C.Red
			goButton.Visible = stateName == "Warning"
			local goLabel = goButton:FindFirstChild("Label") :: TextLabel
			local goText = if locked then "🔒" else T("GO ☄️")
			if goLabel and goLabel.Text ~= goText then
				goLabel.Text = goText
			end
			summonButton.Visible = false
			rankFrame.Visible = false
		elseif stateName == "Active" then
			local endsAt = workspace:GetAttribute("MeteorEnd") or now
			local hp = workspace:GetAttribute("MeteorHP") or 0
			local maxHp = math.max(1, workspace:GetAttribute("MeteorMaxHP") or 1)
			pillText.Text = T("☄️ SMASH IT! %s  •  %d%%", Util.FormatTime(endsAt - now), math.ceil(hp / maxHp * 100))
			pillText.TextColor3 = C.Gold
			stroke.Color = C.Gold
			goButton.Visible = false
			summonButton.Visible = false
			rankFrame.Visible = true
		else
			goButton.Visible = false
			rankFrame.Visible = false
		end
		-- right after the burst: everyone races for the eggs
		if stateName == "Idle" and (workspace:GetAttribute("MeteorLootUntil") or 0) > State.Now() then
			pillText.Text = T("🥚 GRAB THE STAR EGGS & RUN HOME!")
			pillText.TextColor3 = Color3.fromRGB(150, 230, 255)
			stroke.Color = Color3.fromRGB(150, 230, 255)
		end
	end
end)

return MeteorUI
