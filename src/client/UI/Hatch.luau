--[[
	Egg hatch animation: egg shakes, flashes, then reveals the pet(s) in a
	3D viewport with a rarity-colored burst. The dopamine moment of the game.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local PetModel = require(Shared.PetModel)
local Lib = require(script.Parent.Lib)
local Root = require(script.Parent.Root)
local Net = require(script.Parent.Parent.Net)

local New, C = Lib.New, Lib.Colors
local Hatch = {}
Hatch.Playing = false

local dim = New("Frame", {
	Name = "HatchOverlay",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.35,
	Visible = false,
	ZIndex = 100,
	Parent = Root.Overlay,
})
local holder = Root.Cluster("HatchHolder", Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(900, 420), dim)
New("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 20),
	Parent = holder,
})

local queue = {}

local function slot(petName: string, eggColor: Color3)
	local info = Config.Pets[petName]
	local rarity = Config.Rarities[info.Rarity]
	local frame = New("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(260, 400),
		ZIndex = 101,
		Parent = holder,
	})
	local viewport = New("ViewportFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(260, 260),
		ZIndex = 102,
		Ambient = Color3.fromRGB(200, 200, 200),
		LightColor = Color3.new(1, 1, 1),
		Parent = frame,
	})
	local camera = New("Camera", { FieldOfView = 40, Parent = viewport })
	viewport.CurrentCamera = camera

	local egg = New("Part", {
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(4, 4, 4),
		Color = eggColor,
		Material = Enum.Material.SmoothPlastic,
		Anchored = true,
		CFrame = CFrame.new(),
		Parent = viewport,
	}, { New("SpecialMesh", { MeshType = Enum.MeshType.Sphere, Scale = Vector3.new(1, 1.3, 1) }) })
	camera.CFrame = CFrame.new(Vector3.new(0, 0.6, 11), Vector3.new(0, 0, 0))

	local nameLabel = Lib.Text({
		Text = petName,
		Size = UDim2.new(1, 0, 0, 40),
		Position = UDim2.fromOffset(0, 262),
		MaxTextSize = 34,
		ZIndex = 103,
		Visible = false,
		Parent = frame,
	})
	local rarityLabel = Lib.Text({
		Text = string.upper(info.Rarity),
		TextColor3 = rarity.Color,
		Size = UDim2.new(1, 0, 0, 34),
		Position = UDim2.fromOffset(0, 302),
		MaxTextSize = 30,
		ZIndex = 103,
		Visible = false,
		Parent = frame,
	})
	local powerLabel = Lib.Text({
		Text = "💥 +" .. Util.Format(info.Power) .. "x power",
		Font = Lib.BodyFont,
		Size = UDim2.new(1, 0, 0, 26),
		Position = UDim2.fromOffset(0, 340),
		MaxTextSize = 22,
		ZIndex = 103,
		Visible = false,
		Parent = frame,
	})
	return {
		Frame = frame,
		Viewport = viewport,
		Camera = camera,
		Egg = egg,
		Labels = { nameLabel, rarityLabel, powerLabel },
		Rarity = rarity,
		PetName = petName,
	}
end

local function play(pets, eggId)
	Hatch.Playing = true
	Lib.Clear(holder)
	local egg = eggId and Config.Eggs[eggId]
	local eggColor = if egg then egg.Color else C.Gold
	local slots = {}
	for _, name in pets do
		if Config.Pets[name] then
			table.insert(slots, slot(name, eggColor))
		end
	end
	dim.Visible = true

	-- shake
	local start = os.clock()
	local shakeTime = if egg then 1.4 else 0.2
	while os.clock() - start < shakeTime do
		local t = os.clock() - start
		local intensity = t / shakeTime
		for _, s in slots do
			s.Egg.CFrame = CFrame.Angles(0, 0, math.sin(t * 40) * 0.35 * intensity)
		end
		RunService.RenderStepped:Wait()
	end

	-- reveal
	local best = 0
	for _, s in slots do
		s.Egg:Destroy()
		local model = PetModel.Build(s.PetName)
		model.Parent = s.Viewport
		model:PivotTo(CFrame.new())
		local size = model:GetExtentsSize().Magnitude
		s.Camera.CFrame = CFrame.new(Vector3.new(0, size * 0.25, size * 2.4), Vector3.zero)
		s.Model = model
		for _, label in s.Labels do
			label.Visible = true
		end
		Lib.Pop(s.Frame)
		best = math.max(best, s.Rarity.Order)
		local flash = New("Frame", {
			BackgroundColor3 = s.Rarity.Color,
			BackgroundTransparency = 0.2,
			Size = UDim2.fromOffset(260, 260),
			ZIndex = 101,
			Parent = s.Frame,
		}, { Lib.Corner(130) })
		TweenService:Create(flash, TweenInfo.new(0.8), { BackgroundTransparency = 1 }):Play()
	end
	Lib.PlaySound(Config.Sounds.Coins, if best >= 5 then 1 else 0.6)

	-- spin for a moment
	local spinStart = os.clock()
	local duration = if best >= 5 then 3.2 else 2.2
	while os.clock() - spinStart < duration do
		for _, s in slots do
			if s.Model then
				s.Model:PivotTo(CFrame.Angles(0, (os.clock() - spinStart) * 2, 0))
			end
		end
		RunService.RenderStepped:Wait()
	end
	dim.Visible = false
	Lib.Clear(holder)
	Hatch.Playing = false
end

function Hatch.Play(pets, eggId)
	table.insert(queue, { Pets = pets, Egg = eggId })
	if Hatch.Playing then
		return
	end
	task.spawn(function()
		while #queue > 0 do
			local item = table.remove(queue, 1)
			local ok, err = pcall(play, item.Pets, item.Egg)
			if not ok then
				warn("[Hatch] " .. tostring(err))
				dim.Visible = false
				Hatch.Playing = false
			end
		end
	end)
end

-- paid eggs & reward pets arrive from the server
Net.On("HatchResult", function(pets, eggId)
	Hatch.Play(pets, eggId)
end)

return Hatch
