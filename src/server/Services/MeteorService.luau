--[[
	MeteorService: the server-wide competitive event.
	Every few minutes (or when someone buys "Summon Meteor") a meteor crashes
	into the hub crater. Everyone races to hit it; score per hit is
	1 + log10(damage) so new players can still compete with veterans.
	Top 3 get big stardust/gem rewards + weekly ranked points, everyone who
	participates gets a share. Stardust buys the exclusive Cosmic Egg.
]]
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(script.Parent.Net)

local Meteor = {}
local Services
local Data

local settings = Config.Meteor
local state = "Idle" -- Idle | Warning | Falling | Active | Ending
local nextAt = os.time() + math.min(150, settings.IntervalSeconds)
local warnEnd = 0
local endsAt = 0
local hp, maxHp = 0, 0
local scores = {} -- [player] = score
local meteorPart: BasePart? = nil
local summoner: Player? = nil
local summonQueue = {}

local function setAttributes()
	workspace:SetAttribute("MeteorState", state)
	workspace:SetAttribute("MeteorNext", nextAt)
	workspace:SetAttribute("MeteorWarnEnd", warnEnd)
	workspace:SetAttribute("MeteorEnd", endsAt)
	workspace:SetAttribute("MeteorHP", hp)
	workspace:SetAttribute("MeteorMaxHP", maxHp)
end

function Meteor:IsActive(): boolean
	return state == "Active"
end

function Meteor:InRange(position: Vector3): boolean
	if not meteorPart then
		return false
	end
	return (position - meteorPart.Position).Magnitude <= settings.Radius + Config.World.Reach + 2
end

local function ranking()
	local list = {}
	for player, score in scores do
		if player.Parent then
			table.insert(list, { Player = player, Score = score })
		end
	end
	table.sort(list, function(a, b)
		return a.Score > b.Score
	end)
	return list
end

local function buildMeteor(): BasePart
	local part = Instance.new("Part")
	part.Name = "Meteor"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * settings.Radius * 2
	part.Material = Enum.Material.Basalt
	part.Color = Color3.fromRGB(70, 50, 45)
	part.Anchored = true
	part.CanCollide = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	local core = Instance.new("Part")
	core.Name = "Core"
	core.Shape = Enum.PartType.Ball
	core.Size = part.Size * 0.85
	core.Material = Enum.Material.Neon
	core.Color = Color3.fromRGB(255, 120, 40)
	core.Transparency = 0.35
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.Parent = part

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 140, 60)
	light.Range = 40
	light.Brightness = 3
	light.Parent = part

	local fire = Instance.new("Fire")
	fire.Size = settings.Radius * 1.6
	fire.Heat = 12
	fire.Color = Color3.fromRGB(255, 120, 40)
	fire.SecondaryColor = Color3.fromRGB(255, 220, 80)
	fire.Parent = part

	local gui = Instance.new("BillboardGui")
	gui.Name = "HPBar"
	gui.Size = UDim2.new(18, 0, 2, 0)
	gui.StudsOffsetWorldSpace = Vector3.new(0, settings.Radius + 5, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 250
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(30, 20, 20)
	back.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = back
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(255, 120, 40)
	fill.BorderSizePixel = 0
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.5, 0)
	fillCorner.Parent = fill
	fill.Parent = back
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.Text = "☄️ METEOR"
	text:SetAttribute("LangFmt", "☄️ METEOR")
	text.ZIndex = 2
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = text
	text.Parent = back
	back.Parent = gui
	gui.Parent = part
	return part
end

local function updateBar()
	if not meteorPart then
		return
	end
	local gui = meteorPart:FindFirstChild("HPBar")
	local back = gui and gui:FindFirstChildOfClass("Frame")
	if back then
		local ratio = if maxHp > 0 then math.clamp(hp / maxHp, 0, 1) else 0
		(back :: any).Fill.Size = UDim2.fromScale(ratio, 1)
		Services.WorldService.SetText((back :: any).Text, "☄️ METEOR  %s%%", math.ceil(ratio * 100))
	end
end

local function shatter(position: Vector3)
	local folder = Services.WorldService:Folder("Drops")
	for _ = 1, 14 do
		local chunk = Instance.new("Part")
		chunk.Name = "MeteorChunk"
		chunk.Size = Vector3.one * math.random(15, 35) / 10
		chunk.Material = Enum.Material.Basalt
		chunk.Color = Color3.fromRGB(80, 55, 45)
		chunk.CanCollide = false
		chunk.CanQuery = false
		chunk.Position = position + Vector3.new(math.random(-4, 4), math.random(0, 4), math.random(-4, 4))
		chunk.AssemblyLinearVelocity = Vector3.new(math.random(-40, 40), math.random(40, 80), math.random(-40, 40))
		chunk.Parent = folder
		Debris:AddItem(chunk, 3)
	end
	local explosion = Instance.new("Explosion")
	explosion.Position = position
	explosion.BlastPressure = 0
	explosion.BlastRadius = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.Parent = workspace
end

local function finish(destroyed: boolean)
	if state ~= "Active" then
		return
	end
	state = "Ending"
	local list = ranking()
	local total = 0
	for _, entry in list do
		total += entry.Score
	end
	local mult = if destroyed then 1 else settings.FailedMultiplier
	local progression = Services.ProgressionService
	local topNames = {}

	for place, entry in list do
		local player = entry.Player
		local data = Data:Get(player)
		if data then
			local share = if total > 0 then entry.Score / total else 0
			local stardust = settings.ParticipationStardust + math.floor(share * settings.ShareStardust)
			local gems = 0
			local points = settings.ParticipationPoints
			local placeReward = settings.PlaceRewards[place]
			if placeReward then
				stardust += placeReward.Stardust
				gems += placeReward.Gems
				points = placeReward.Points
				table.insert(topNames, player.DisplayName)
			end
			stardust = math.floor(stardust * mult)
			gems = math.floor(gems * mult)
			if player == summoner then
				stardust *= 2
			end
			data.Stardust += stardust
			data.Gems += gems
			data.Stats.MeteorJoins += 1
			if place == 1 and destroyed then
				data.Stats.MeteorWins += 1
			end
			progression:AddQuest(player, "MeteorJoin", 1)
			if place <= 3 then
				progression:AddQuest(player, "MeteorTop3", 1)
			end
			progression:AddPoints(player, points)
			progression:AddSeasonXP(player, settings.PassXP)
			Net:Send(player, "MeteorResult", {
				Place = place,
				Total = #list,
				Stardust = stardust,
				Gems = gems,
				Points = points,
				Destroyed = destroyed,
			})
			Data:MarkDirty(player)
		end
	end

	local medals = { "🥇", "🥈", "🥉" }
	local parts = {}
	for i, name in topNames do
		table.insert(parts, medals[i] .. " " .. name)
	end
	local headline = if destroyed then "☄️ Meteor destroyed! %s" else "☄️ The meteor escaped! %s"
	Net:Announce(headline, Color3.fromRGB(255, 170, 80), table.concat(parts, "  "))

	if meteorPart then
		local position = meteorPart.Position
		meteorPart:Destroy()
		meteorPart = nil
		shatter(position)
	end
	if destroyed then
		-- the big payoff: a burst of star shards to race for
		local ok, err = pcall(function()
			Services.ShardService:SpillMeteor(Vector3.new(settings.Position.X, 0, settings.Position.Z), list)
		end)
		if not ok then
			warn("[Meteor] shard spill failed: " .. tostring(err))
		end
	end
	scores = {}
	summoner = nil
	hp, maxHp = 0, 0
	state = "Idle"
	nextAt = os.time() + settings.IntervalSeconds
	setAttributes()
	Net:Broadcast("MeteorRank", {})
end

-- back to a clean idle state so a failure never stops future events
local function resetToIdle()
	if meteorPart then
		meteorPart:Destroy()
		meteorPart = nil
	end
	scores = {}
	summoner = nil
	hp, maxHp = 0, 0
	state = "Idle"
	nextAt = os.time() + settings.IntervalSeconds
	setAttributes()
	Net:Broadcast("MeteorRank", {})
end

local function safeFinish(destroyed: boolean)
	local ok, err = pcall(finish, destroyed)
	if not ok then
		warn("[Meteor] finish failed: " .. tostring(err))
		resetToIdle()
	end
end

-- cooldown is the attacker's swing cooldown, used to size the meteor so the
-- event lasts about SecondsPerParticipant no matter how strong players are
function Meteor:Hit(player: Player, damage: number, cooldown: number?)
	if state ~= "Active" then
		return
	end
	local score = 1 + math.log10(math.max(1, damage))
	if not scores[player] then
		-- each new participant makes the meteor tougher by ~N seconds of their own hitting
		local extra = settings.SecondsPerParticipant * score / math.max(0.2, cooldown or 0.5)
		maxHp += extra
		hp += extra
		workspace:SetAttribute("MeteorMaxHP", maxHp)
	end
	scores[player] = (scores[player] or 0) + score
	hp = math.max(0, hp - score)
	workspace:SetAttribute("MeteorHP", hp)
	updateBar()
	Net:Send(player, "MeteorHit", score)
	if hp <= 0 then
		safeFinish(true)
	end
end

function Meteor:Summon(player: Player)
	table.insert(summonQueue, player)
	if state == "Idle" then
		Net:Notify(player, "☄️ Your meteor is on its way!", Color3.fromRGB(255, 170, 80))
	else
		Net:Notify(player, "☄️ Your meteor will fall right after the current one!", Color3.fromRGB(255, 170, 80))
	end
end

local function startWarning()
	local summoned = table.remove(summonQueue, 1)
	if summoned and not summoned.Parent then
		summoned = nil
	end
	summoner = summoned
	state = "Warning"
	warnEnd = os.time() + (if summoned then settings.SummonWarningSeconds else settings.WarningSeconds)
	setAttributes()
	if summoned then
		Net:Announce(
			"☄️ %s SUMMONED A METEOR! Get to the crater! (%ds)",
			Color3.fromRGB(255, 150, 60),
			summoned.DisplayName,
			warnEnd - os.time()
		)
	else
		Net:Announce("☄️ A METEOR is about to crash into the crater! (%ds)", Color3.fromRGB(255, 150, 60), warnEnd - os.time())
	end
end

local function startFalling()
	state = "Falling"
	setAttributes()
	local final = settings.Position + Vector3.new(0, settings.Radius * 0.6, 0)
	local part = buildMeteor()
	part.Position = final + Vector3.new(60, 320, 40)
	part.Parent = Services.WorldService:Folder("Drops")
	meteorPart = part
	local core = part:FindFirstChild("Core") :: BasePart
	core.Position = part.Position
	local info = TweenInfo.new(2.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(part, info, { Position = final }):Play()
	TweenService:Create(core, info, { Position = final }):Play()
	task.wait(2.25)
	local explosion = Instance.new("Explosion")
	explosion.Position = final
	explosion.BlastPressure = 0
	explosion.BlastRadius = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.Parent = workspace
	Net:Broadcast("MeteorImpact", final)

	maxHp = settings.BaseHP
	hp = maxHp
	scores = {}
	endsAt = os.time() + settings.DurationSeconds
	state = "Active"
	setAttributes()
	updateBar()
end

function Meteor:Init(services)
	Services = services
	Data = services.DataService
end

function Meteor:Start()
	setAttributes()
	task.spawn(function()
		local lastRankPush = 0
		local function step()
			local now = os.time()
			if state == "Idle" then
				if now >= nextAt or #summonQueue > 0 then
					startWarning()
				end
			elseif state == "Warning" then
				if now >= warnEnd then
					startFalling()
				end
			elseif state == "Active" then
				if now >= endsAt then
					safeFinish(false)
				elseif os.clock() - lastRankPush >= 1 then
					lastRankPush = os.clock()
					local list = ranking()
					local top = {}
					for i = 1, math.min(5, #list) do
						table.insert(top, { Name = list[i].Player.DisplayName, Score = math.floor(list[i].Score) })
					end
					for place, entry in list do
						Net:Send(entry.Player, "MeteorRank", top, place, math.floor(entry.Score))
					end
					for _, player in Players:GetPlayers() do
						if not scores[player] then
							Net:Send(player, "MeteorRank", top, nil, 0)
						end
					end
				end
			end
		end
		while true do
			task.wait(0.25)
			local ok, err = pcall(step)
			if not ok then
				warn("[Meteor] loop error: " .. tostring(err))
				resetToIdle()
			elseif state == "Ending" then
				-- finish() never got back to Idle: recover
				resetToIdle()
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		scores[player] = nil
	end)

	Net:On("GoToMeteor", 2, function(player)
		local character = player.Character
		if character and (state == "Warning" or state == "Falling" or state == "Active") then
			character:PivotTo(CFrame.new(settings.Position + Vector3.new(0, 4, -18)))
		end
	end)
end

return Meteor
