--[[
	Renders every player's equipped pets locally (server only replicates a
	JSON attribute). Pets float behind their owner in rows of three.
	🐾 Pet help: when the server says a player's pets hit something
	("PetHelp"), each pet hops over to its target and back.
]]
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PetModel = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PetModel"))
local Net = require(script.Parent.Parent.Net)
local Lib = require(script.Parent.Parent.UI.Lib)

local HOP_TIME = 0.5

local folder = Instance.new("Folder")
folder.Name = "ClientPets"
folder.Parent = workspace

local owners = {} -- [player] = { Models = { Model }, Key = string }

local function clear(player: any)
	local entry = owners[player]
	if entry then
		for _, model in entry.Models do
			model:Destroy()
		end
	end
	owners[player] = nil
end

local function rebuild(player: any)
	local raw = player:GetAttribute("Pets")
	local key = if type(raw) == "string" then raw else "[]"
	local entry = owners[player]
	if entry and entry.Key == key then
		return
	end
	clear(player)
	local ok, names = pcall(HttpService.JSONDecode, HttpService, key)
	if not ok or type(names) ~= "table" then
		names = {}
	end
	local models = {}
	for i, entry in names do
		if type(entry) == "string" then
			-- entries look like "Golden|Fox|7|1" (variant|name|level|stars) or "|Fox"
			local parts = string.split(entry, "|")
			local variant, name = parts[1] or "", parts[2]
			if not name then
				variant, name = "", entry
			end
			local growth = { Level = tonumber(parts[3]) or 1, Stars = tonumber(parts[4]) or 0 }
			local model = PetModel.Build(name, if variant ~= "" then variant else nil, growth)
			model.Name = player.Name .. "_" .. i
			model.Parent = folder
			table.insert(models, model)
		end
	end
	owners[player] = { Models = models, Key = key, Positions = {}, Hops = {} }
end

local function track(player: any)
	player:GetAttributeChangedSignal("Pets"):Connect(function()
		rebuild(player)
	end)
	rebuild(player)
end

Players.PlayerAdded:Connect(track)
Players.PlayerRemoving:Connect(clear)
for _, player in Players:GetPlayers() do
	track(player)
end

-- rival players (server game characters) have pets following them too
local function trackRival(model: Instance)
	if model:IsA("Model") and model:GetAttribute("Rival") == true then
		track(model)
		model.AncestryChanged:Connect(function()
			if not model.Parent then
				clear(model)
			end
		end)
	end
end
workspace.ChildAdded:Connect(function(child)
	task.defer(trackRival, child)
end)
for _, child in workspace:GetChildren() do
	trackRival(child)
end

local function rootOf(owner: any): BasePart?
	local character = if owner:IsA("Player") then owner.Character else owner
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

RunService.RenderStepped:Connect(function(dt)
	local t = os.clock()
	local rainbow = Color3.fromHSV((t * 0.3) % 1, 0.7, 1)
	local alpha = 1 - math.exp(-dt * 9)
	for player, entry in owners do
		local root = rootOf(player)
		if root then
			local base = root.CFrame
			for i, model in entry.Models do
				local index = i - 1
				local row = math.floor(index / 3)
				local col = index % 3
				local offset = Vector3.new((col - 1) * 3.6, -0.6 + math.sin(t * 3 + i) * 0.35, 4.2 + row * 3.4)
				local target = base * CFrame.new(offset)
				local current = entry.Positions[i] or target
				local position = current.Position:Lerp(target.Position, alpha)
				local look = base.LookVector
				local cf = CFrame.lookAt(position, position + Vector3.new(look.X, 0, look.Z) + Vector3.new(0, 0.001, 0))
				entry.Positions[i] = cf
				-- hopping over to hit an ore / the meteor (and back)
				local hop = entry.Hops[i]
				if hop then
					local p = (t - hop.Start) / HOP_TIME
					if p >= 1 then
						entry.Hops[i] = nil
					elseif p > 0 then
						local weight = math.sin(p * math.pi)
						local at = position:Lerp(hop.Target, weight) + Vector3.new(0, weight * 2.5, 0)
						local face = hop.Target - position
						face = Vector3.new(face.X, 0, face.Z)
						cf = if face.Magnitude > 0.1 then CFrame.lookAt(at, at + face) else CFrame.new(at)
					end
				end
				model:PivotTo(cf)
				if model:GetAttribute("Variant") == "Rainbow" and model.PrimaryPart then
					model.PrimaryPart.Color = rainbow
				end
			end
		end
	end
end)

Net.On("PetHelp", function(userId, targets)
	local owner = type(userId) == "number" and Players:GetPlayerByUserId(userId)
	local entry = owner and owners[owner]
	if not entry or type(targets) ~= "table" or #targets == 0 then
		return
	end
	local t = os.clock()
	for i in entry.Models do
		local target = targets[((i - 1) % #targets) + 1]
		if typeof(target) == "Vector3" and not entry.Hops[i] then
			-- stop just short of the target, a little above the ground
			entry.Hops[i] = { Target = target + Vector3.new(0, 1, 0), Start = t + (i - 1) * 0.08 }
		end
	end
	if owner == Players.LocalPlayer then
		Lib.PlaySound("Pop", 0.18)
	end
end)

return {}
