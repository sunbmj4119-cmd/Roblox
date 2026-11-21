--[[
	Renders every player's equipped pets locally (server only replicates a
	JSON attribute). Pets float behind their owner in rows of three.
]]
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PetModel = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PetModel"))

local folder = Instance.new("Folder")
folder.Name = "ClientPets"
folder.Parent = workspace

local owners = {} -- [player] = { Models = { Model }, Key = string }

local function clear(player: Player)
	local entry = owners[player]
	if entry then
		for _, model in entry.Models do
			model:Destroy()
		end
	end
	owners[player] = nil
end

local function rebuild(player: Player)
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
	for i, name in names do
		if type(name) == "string" then
			local model = PetModel.Build(name)
			model.Name = player.Name .. "_" .. i
			model.Parent = folder
			table.insert(models, model)
		end
	end
	owners[player] = { Models = models, Key = key, Positions = {} }
end

local function track(player: Player)
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

RunService.RenderStepped:Connect(function(dt)
	local t = os.clock()
	local alpha = 1 - math.exp(-dt * 9)
	for player, entry in owners do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart
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
				model:PivotTo(cf)
			end
		end
	end
end)

return {}
