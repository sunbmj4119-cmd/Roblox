--[[
	YardPets: the pets waiting in storage don't vanish - they wander around
	their owner's yard (the server publishes up to Config.Base.YardPets of
	them per house as the plot attribute "Yard"). Only houses near the camera
	get models, so phones stay smooth.

	Also: a small "welcome" when you step onto your own land or someone
	else's (house name, level, likes).
]]
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local DecorModel = require(Shared.DecorModel)
local PetModel = require(Shared.PetModel)

local Client = script.Parent.Parent
local Lib = require(Client.UI.Lib)

local YardPets = {}
local player = Players.LocalPlayer
local T = Lib.T

local VIEW_DISTANCE = 150
local MAX_YARDS = 3 -- only the nearest houses get wandering pets (phones stay smooth)
local STEP = 1 / 20 -- pets move 20 times a second
local SPEED = 4
local folder = Instance.new("Folder")
folder.Name = "YardPets"
folder.Parent = workspace

local yards = {} -- [plot Model] = { Key, Pets = { { Model, Pos, Target, Wait, Lift } } }
local rng = Random.new()

local function plotFrame(plot: Model): CFrame?
	local floor = plot:FindFirstChild("Floor")
	return if floor and floor:IsA("BasePart") then floor.CFrame * CFrame.new(0, 0.2, 0) else nil
end

local function clear(plot: Model)
	local yard = yards[plot]
	if yard then
		for _, pet in yard.Pets do
			pet.Model:Destroy()
		end
	end
	yards[plot] = nil
end

local function randomSpot(plot: Model): Vector3
	local bounds = DecorModel.Bounds(Config, plot:GetAttribute("HouseLevel") or 1)
	return Vector3.new(rng:NextNumber(bounds.MinX + 2, bounds.MaxX - 2), 0, rng:NextNumber(bounds.MinZ + 2, bounds.MaxZ - 2))
end

local function build(plot: Model, key: string)
	clear(plot)
	local ok, names = pcall(HttpService.JSONDecode, HttpService, key)
	if not ok or type(names) ~= "table" then
		return
	end
	local pets = {}
	for i, entry in names do
		if type(entry) == "string" then
			local variant, name = string.match(entry, "^(.-)|(.+)$")
			if name and Config.Pets[name] then
				local model = PetModel.Build(name, if variant ~= "" then variant else nil)
				model.Name = plot.Name .. "_yard_" .. i
				model:PivotTo(CFrame.new())
				local box, size = model:GetBoundingBox()
				-- how far the pivot sits above the model's feet
				local lift = model:GetPivot().Position.Y - (box.Position.Y - size.Y / 2)
				for _, d in model:GetDescendants() do
					if d:IsA("Light") or d:IsA("ParticleEmitter") or d:IsA("Sparkles") or d:IsA("Fire") then
						d:Destroy() -- (cheap yard copies: no lights / particles)
					elseif d:IsA("BasePart") then
						d.CanCollide = false
						d.CanQuery = false
						d.CanTouch = false
					end
				end
				model.Parent = folder
				local start = randomSpot(plot)
				table.insert(pets, { Model = model, Pos = start, Target = randomSpot(plot), Wait = rng:NextNumber(0, 2), Lift = lift })
			end
		end
	end
	yards[plot] = { Key = key, Pets = pets }
end

local function bases(): { Model }
	local map = workspace:FindFirstChild("Map")
	local folderBases = map and map:FindFirstChild("Bases")
	return if folderBases then folderBases:GetChildren() :: any else {}
end

-- which houses get pets (near the camera only)
local function refreshYards()
	local camera = workspace.CurrentCamera
	local eye = camera and camera.CFrame.Position or Vector3.zero
	-- the nearest few houses within view distance
	local candidates = {}
	for _, plot in bases() do
		local frame = plotFrame(plot)
		if frame then
			local distance = (frame.Position - eye).Magnitude
			if distance < VIEW_DISTANCE then
				table.insert(candidates, { Plot = plot, Distance = distance })
			end
		end
	end
	table.sort(candidates, function(a, b)
		return a.Distance < b.Distance
	end)
	local chosen = {}
	for i = 1, math.min(MAX_YARDS, #candidates) do
		chosen[candidates[i].Plot] = true
	end
	for _, plot in bases() do
		local ownerId = plot:GetAttribute("OwnerId")
		local key = plot:GetAttribute("Yard")
		local near = chosen[plot] == true
		if near and type(ownerId) == "number" and ownerId ~= 0 and type(key) == "string" then
			local yard = yards[plot]
			if not yard or yard.Key ~= key then
				build(plot, key)
			end
		elseif yards[plot] then
			clear(plot)
		end
	end
end

-- welcome banner when you step onto a piece of land
local insidePlot: Model? = nil
local lastHome = 0
local function checkLand()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local found = nil
	local half = Config.Base.PlotSize / 2
	for _, plot in bases() do
		local frame = plotFrame(plot)
		if frame and (plot:GetAttribute("OwnerId") or 0) ~= 0 then
			local p = frame:PointToObjectSpace(root.Position)
			if math.abs(p.X) <= half and math.abs(p.Z) <= half then
				found = plot
			end
		end
	end
	if found == insidePlot then
		return
	end
	insidePlot = found
	local hud = YardPets.HUD
	if not found or not hud then
		return
	end
	if found:GetAttribute("OwnerId") == player.UserId then
		if os.clock() - lastHome > 30 then
			hud.Toast(T("🏡 Welcome home!"), Color3.fromRGB(140, 230, 160))
		end
		lastHome = os.clock()
	else
		local name = found:GetAttribute("HouseName")
		local title = if type(name) == "string" and name ~= ""
			then name
			else T("%s's House", tostring(found:GetAttribute("OwnerName") or "?"))
		local crown = if found:GetAttribute("BestHouse") then "👑 " else ""
		hud.Toast(
			crown
				.. "🏘️ "
				.. title
				.. "  •  Lv."
				.. tostring(found:GetAttribute("HouseLevel") or 1)
				.. "  ❤️ "
				.. tostring(found:GetAttribute("Likes") or 0),
			Color3.fromRGB(255, 170, 200)
		)
	end
end

task.spawn(function()
	while true do
		pcall(refreshYards)
		pcall(checkLand)
		task.wait(0.5)
	end
end)

local accumulator = 0
RunService.Heartbeat:Connect(function(frameDt)
	accumulator += frameDt
	if accumulator < STEP then
		return
	end
	local dt = math.min(accumulator, 0.2)
	accumulator = 0
	local t = os.clock()
	for plot, yard in yards do
		local frame = plotFrame(plot)
		if not frame or not plot.Parent then
			clear(plot)
			continue
		end
		for i, pet in yard.Pets do
			if pet.Wait > 0 then
				pet.Wait -= dt
			else
				local offset = pet.Target - pet.Pos
				local distance = offset.Magnitude
				if distance < 0.5 then
					pet.Target = randomSpot(plot)
					pet.Wait = rng:NextNumber(1, 4) -- sit for a moment
				else
					pet.Pos += offset.Unit * math.min(distance, SPEED * dt)
				end
			end
			local moving = pet.Wait <= 0
			local hop = if moving then math.abs(math.sin(t * 9 + i)) * 0.5 else 0
			local look = pet.Target - pet.Pos
			local world = frame * CFrame.new(pet.Pos + Vector3.new(0, pet.Lift + hop, 0))
			local facing = if look.Magnitude > 0.1 then frame:VectorToWorldSpace(look.Unit) else world.LookVector
			pet.Model:PivotTo(CFrame.lookAt(world.Position, world.Position + Vector3.new(facing.X, 0, facing.Z) + Vector3.new(0, 0.001, 0)))
		end
	end
end)

return YardPets
