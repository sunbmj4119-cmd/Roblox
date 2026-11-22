--[[
	New-player guide: a glowing beam from your character to the next thing
	to do (mine -> sell -> hatch -> upgrade -> unlock). The first minutes
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
	Size = UDim2.fromOffset(240, 70),
	StudsOffsetWorldSpace = Vector3.new(0, 6, 0),
	AlwaysOnTop = true,
	Adornee = marker,
	Enabled = false,
	ResetOnSpawn = false,
	Parent = player:WaitForChild("PlayerGui"),
})
local label = Lib.Text({ Text = "", TextColor3 = Color3.fromRGB(255, 230, 120), Size = UDim2.fromScale(1, 0.55), MaxTextSize = 30, Parent = billboard })
local arrow = Lib.Text({ Text = "⬇", TextColor3 = Color3.fromRGB(255, 230, 120), Size = UDim2.fromScale(1, 0.45), Position = UDim2.fromScale(0, 0.55), MaxTextSize = 30, Parent = billboard })

local function part(path: { string }): BasePart?
	local node: Instance? = workspace:FindFirstChild("Map")
	for _, name in path do
		node = node and node:FindFirstChild(name)
	end
	return if node and node:IsA("BasePart") then node else nil
end

-- returns target position + label, or nil when the player needs no help
local function pickTarget(root: BasePart)
	local data, derived = State.Data, State.Derived
	if not data or not derived then
		return nil
	end
	if (data.Level or 1) >= MAX_LEVEL or data.ZoneLevel >= 3 then
		return nil
	end
	local capacity = derived.Capacity or math.huge
	if data.Backpack >= capacity then
		local pad = part({ "Hub", "SellPad" })
		return pad and pad.Position + Vector3.new(0, 1, 0), "💰 SELL YOUR ORE"
	end
	if data.Stats.EggsHatched == 0 and data.Coins >= Config.Eggs.Meadow.Price then
		local egg = part({ "Hub", "Eggs", "MeadowEgg" })
		return egg and egg.Position, "🥚 HATCH A PET"
	end
	local pick = Config.Pickaxes[data.PickaxeTier + 1]
	if pick and data.Coins >= pick.Cost and data.PickaxeTier < 4 then
		return PICKAXE_SHOP, "⛏️ BETTER PICKAXE"
	end
	local zone = Config.Zones[data.ZoneLevel + 1]
	if zone and data.Coins >= zone.Cost then
		local gate = part({ "Gates", "Gate_" .. (data.ZoneLevel + 1) })
		return gate and gate.Position, "🔓 UNLOCK " .. string.upper(zone.Name)
	end
	if Util.ZoneAt(Config, root.Position) == 0 and data.Backpack < capacity then
		return MINE_ENTRANCE, "⛏️ MINE ORE HERE"
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
