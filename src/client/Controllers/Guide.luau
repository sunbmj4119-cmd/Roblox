--[[
	Guide: a glowing beam from your character to the next thing to do -
	your tutorial meteor, the star egg, home, and for everyone: the meteor
	of this round while it is falling / being smashed. The first minutes
	decide whether a player comes back (D1 retention), so never leave them
	wondering what to do. Turns itself off once the player is established.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)

local Client = script.Parent.Parent
local State = require(Client.State)
local Lib = require(Client.UI.Lib)

local player = Players.LocalPlayer
local T = Lib.T

local MAX_LEVEL = 8 -- guide disappears after this level / zone 3
local PICKAXE_SHOP = Vector3.new(56, 4, -45)
local MINE_ENTRANCE = Vector3.new(0, 4, Config.World.Layout.FirstZ + 10)

-- local-only marker part the beam points at
local marker = Instance.new("Part")
marker.Name = "GuideMarker"
marker.Anchored = true
marker.CanCollide = false
marker.CanQuery = false
marker.CanTouch = false
marker.Transparency = 1
marker.Size = Vector3.one
marker.Parent = workspace
local targetAttachment = Instance.new("Attachment")
targetAttachment.Parent = marker

local beam = Instance.new("Beam")
beam.Attachment1 = targetAttachment
beam.Texture = "rbxasset://textures/particles/sparkles_main.dds"
beam.TextureMode = Enum.TextureMode.Wrap
beam.TextureLength = 3
beam.TextureSpeed = 2
beam.Color = ColorSequence.new(Color3.fromRGB(255, 230, 120), Color3.fromRGB(255, 160, 60))
beam.LightEmission = 1
beam.Width0 = 1.6
beam.Width1 = 1.6
beam.FaceCamera = true
beam.Segments = 20
beam.Transparency = NumberSequence.new(0.1, 0.4)
beam.Enabled = false
beam.Parent = marker

local billboard = Lib.New("BillboardGui", {
	-- studs, not pixels: a small sign near you, never a giant banner over the HUD
	Size = UDim2.new(9, 0, 2.6, 0),
	StudsOffsetWorldSpace = Vector3.new(0, 5, 0),
	AlwaysOnTop = true,
	MaxDistance = 160,
	Adornee = marker,
	Enabled = false,
	ResetOnSpawn = false,
	Parent = player:WaitForChild("PlayerGui"),
})
local label = Lib.Text({
	Text = "",
	TextColor3 = Color3.fromRGB(255, 230, 120),
	Size = UDim2.fromScale(1, 0.55),
	MaxTextSize = 22,
	Parent = billboard,
})
local arrow = Lib.Text({
	Text = "⬇",
	TextColor3 = Color3.fromRGB(255, 230, 120),
	Size = UDim2.fromScale(1, 0.45),
	Position = UDim2.fromScale(0, 0.55),
	MaxTextSize = 30,
	Parent = billboard,
})

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function part(path: { string }): BasePart?
	local node: Instance? = workspace:FindFirstChild("Map")
	for _, name in path do
		node = node and node:FindFirstChild(name)
	end
	return if node and node:IsA("BasePart") then node else nil
end

local function nearestOre(root: BasePart, maxZone: number): Vector3?
	local map = workspace:FindFirstChild("Map")
	local ores = map and map:FindFirstChild("Ores")
	if not ores then
		return nil
	end
	local best, bestDistance = nil, math.huge
	for _, ore in ores:GetChildren() do
		if ore:IsA("BasePart") and (ore:GetAttribute("Zone") or 99) <= maxZone then
			local distance = (ore.Position - root.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = ore, distance
			end
		end
	end
	return best and best.Position + Vector3.new(0, 2.5, 0)
end

-- "go mine": the nearest ore when in a mine, else the mine entrance
local function mineTarget(root: BasePart, data)
	if Util.ZoneAt(Config, root.Position) ~= 0 then
		local ore = nearestOre(root, data.ZoneLevel)
		if ore then
			return ore, T("⛏️ TAP ORE TO MINE")
		end
	end
	return MINE_ENTRANCE, T("⛏️ MINE ORE HERE")
end

-- your base's entrance (collect pad)
local function baseTarget()
	local index = player:GetAttribute("BaseIndex")
	local pad = index and part({ "Bases", "Plot_" .. tostring(index), "CollectPad" })
	return pad and pad.Position + Vector3.new(0, 1, 0)
end

-- the closest shard lying around in a place we can reach
local function shardTarget(root: BasePart, data)
	local map = workspace:FindFirstChild("Map")
	local folder = map and map:FindFirstChild("Shards")
	if not folder then
		return nil
	end
	local best, bestDistance = nil, math.huge
	for _, model in folder:GetChildren() do
		local hitbox = model:FindFirstChild("Hitbox")
		if hitbox and hitbox:IsA("BasePart") then
			local zone = Util.ZoneAt(Config, hitbox.Position)
			if zone ~= nil and zone <= data.ZoneLevel then
				local distance = (hitbox.Position - root.Position).Magnitude
				if distance < bestDistance then
					best, bestDistance = hitbox, distance
				end
			end
		end
	end
	return best and best.Position
end

-- ☄️ the meteor of this round (warning marker or the meteor itself), if we can get there
local function meteorTarget(root: BasePart, data)
	local state = workspace:GetAttribute("MeteorState")
	if state ~= "Warning" and state ~= "Falling" and state ~= "Active" then
		return nil
	end
	local site = workspace:GetAttribute("MeteorSiteZone") or 0
	if site > (data.ZoneLevel or 1) then
		return nil -- (a zone we haven't unlocked)
	end
	local position = workspace:GetAttribute("MeteorPos")
	if typeof(position) ~= "Vector3" then
		return nil
	end
	local radius = workspace:GetAttribute("MeteorRadius") or Config.Meteor.Radius
	if flat(position - root.Position).Magnitude <= radius + 12 then
		return nil -- we're there: just hit it
	end
	return position + Vector3.new(0, radius + 2, 0), if state == "Active" then T("☄️ SMASH IT!") else T("☄️ METEOR HERE!")
end

-- the new player's own tutorial meteor
local function tutorialMeteor()
	local map = workspace:FindFirstChild("Map")
	local drops = map and map:FindFirstChild("Drops")
	local meteor = drops and drops:FindFirstChild("TutorialMeteor_" .. tostring(player.UserId))
	return if meteor and meteor:IsA("BasePart") then meteor.Position + Vector3.new(0, 3, 0) else nil
end

-- returns target position + label, or nil when the player needs no help
local function pickTarget(root: BasePart)
	local data, derived = State.Data, State.Derived
	if not data or not derived then
		return nil
	end
	if player:GetAttribute("Carrying") then
		local home = baseTarget()
		if home then
			return home, T("🏠 RUN HOME!")
		end
	end
	local tutorial = data.Tutorial
	local step = tutorial and not tutorial.Done and Config.Tutorial.Steps[tutorial.Step]
	local id = step and step.Id
	if id == "Meteor" then
		local meteor = tutorialMeteor()
		if meteor then
			return meteor, T("☄️ SMASH IT!")
		end
		return nil
	elseif id == "Grab" or id == "Shard" then
		local shard = shardTarget(root, data)
		if shard then
			return shard, T("🥚 GRAB THE STAR EGG")
		end
	end
	local meteorAt, meteorText = meteorTarget(root, data)
	if meteorAt then
		return meteorAt, meteorText
	end
	if step then
		local nextPick = Config.Pickaxes[(data.PickaxeTier or 1) + 1]
		if id == "Pickaxe" and nextPick and data.Coins >= nextPick.Cost then
			return PICKAXE_SHOP, T("⛏️ BUY A PICKAXE")
		elseif id == "Hatch" and data.Coins >= Config.Eggs.Meadow.Price then
			local egg = part({ "Hub", "Eggs", "MeadowEgg" })
			return egg and egg.Position, T("🥚 HATCH HERE")
		end
		return mineTarget(root, data)
	end
	local shard = shardTarget(root, data)
	if shard then
		return shard, T("🥚 GRAB THE STAR EGG")
	end
	if (data.Level or 1) >= MAX_LEVEL or data.ZoneLevel >= 3 then
		return nil
	end
	local zone = Config.Zones[data.ZoneLevel + 1]
	if zone and data.Coins >= zone.Cost then
		local gate = part({ "Gates", "Gate_" .. (data.ZoneLevel + 1) })
		return gate and gate.Position, T("🔓 UNLOCK %s", zone.Name)
	end
	if Util.ZoneAt(Config, root.Position) == 0 then
		return MINE_ENTRANCE, T("⛏️ MINE ORE HERE")
	end
	return nil
end

local rootAttachment: Attachment? = nil
local function attachTo(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if root then
		local attachment = Instance.new("Attachment")
		attachment.Name = "GuideAttachment"
		attachment.Parent = root
		rootAttachment = attachment
		beam.Attachment0 = attachment
	end
end
player.CharacterAdded:Connect(attachTo)
if player.Character then
	task.spawn(attachTo, player.Character)
end

local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	arrow.Position = UDim2.fromScale(0, 0.55 + math.sin(os.clock() * 5) * 0.06)
	accumulator += dt
	if accumulator < 0.4 then
		return
	end
	accumulator = 0
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not root or not rootAttachment then
		beam.Enabled = false
		billboard.Enabled = false
		return
	end
	local ok, position, text = pcall(pickTarget, root)
	if not ok or not position then
		beam.Enabled = false
		billboard.Enabled = false
		return
	end
	marker.Position = position
	label.Text = text
	beam.Enabled = true
	billboard.Enabled = true
end)

return {}
