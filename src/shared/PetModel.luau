--[[
	Builds simple, readable pet models out of primitive parts so the game works
	without any uploaded meshes. Replace with real models later by putting a
	Model named after the pet inside ReplicatedStorage.PetModels.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.Config)

local PetModel = {}

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

local function weld(a, b)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = a
end

function PetModel.Build(petName: string, variant: string?): Model
	local custom = ReplicatedStorage:FindFirstChild("PetModels")
	if custom and custom:FindFirstChild(petName) then
		local clone = (custom :: any)[petName]:Clone()
		if clone:IsA("Model") and clone.PrimaryPart then
			for _, d in clone:GetDescendants() do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
					d.CanQuery = false
					d.CanTouch = false
				end
			end
			return clone
		end
	end

	local info = Config.Pets[petName] or { Rarity = "Common", Color = Color3.new(1, 1, 1), Shape = "Ball" }
	local rarity = Config.Rarities[info.Rarity] or Config.Rarities.Common
	local scale = 1.4 + rarity.Order * 0.12

	local model = Instance.new("Model")
	model.Name = petName

	local body = part({
		Name = "Body",
		Shape = if info.Shape == "Block" then Enum.PartType.Block else Enum.PartType.Ball,
		Size = Vector3.one * scale,
		Color = info.Color,
		Material = if rarity.Order >= 5
			then Enum.Material.Neon
			elseif rarity.Order >= 4 then Enum.Material.Glass
			else Enum.Material.SmoothPlastic,
	})
	if rarity.Order >= 5 then
		body.Transparency = 0.05
	end
	body.Parent = model
	model.PrimaryPart = body

	local eyeSize = Vector3.one * scale * 0.18
	for _, side in { -1, 1 } do
		local eye = part({
			Name = "Eye",
			Shape = Enum.PartType.Ball,
			Size = eyeSize,
			Color = Color3.new(0.05, 0.05, 0.05),
			Material = Enum.Material.SmoothPlastic,
			CFrame = body.CFrame * CFrame.new(side * scale * 0.2, scale * 0.12, -scale * 0.45),
		})
		eye.Parent = model
		weld(body, eye)
		local shine = part({
			Name = "Shine",
			Shape = Enum.PartType.Ball,
			Size = eyeSize * 0.4,
			Color = Color3.new(1, 1, 1),
			Material = Enum.Material.Neon,
			CFrame = eye.CFrame * CFrame.new(eyeSize.X * 0.15, eyeSize.X * 0.2, -eyeSize.X * 0.35),
		})
		shine.Parent = model
		weld(body, shine)
	end

	if info.Ears then
		for _, side in { -1, 1 } do
			local ear = part({
				Name = "Ear",
				Size = Vector3.new(scale * 0.22, scale * 0.4, scale * 0.12),
				Color = info.Color:Lerp(Color3.new(0, 0, 0), 0.15),
				Material = body.Material,
				CFrame = body.CFrame * CFrame.new(side * scale * 0.28, scale * 0.55, 0) * CFrame.Angles(0, 0, math.rad(-side * 15)),
			})
			ear.Parent = model
			weld(body, ear)
		end
	end

	if info.Wings then
		for _, side in { -1, 1 } do
			local wing = part({
				Name = "Wing",
				Size = Vector3.new(scale * 0.55, scale * 0.12, scale * 0.45),
				Color = info.Color:Lerp(Color3.new(1, 1, 1), 0.3),
				Material = body.Material,
				CFrame = body.CFrame
					* CFrame.new(side * scale * 0.62, scale * 0.05, scale * 0.1)
					* CFrame.Angles(0, 0, math.rad(side * 25)),
			})
			wing.Parent = model
			weld(body, wing)
		end
	end

	if info.Horns then
		for _, side in { -1, 1 } do
			local horn = part({
				Name = "Horn",
				Size = Vector3.new(scale * 0.12, scale * 0.38, scale * 0.12),
				Color = Color3.fromRGB(255, 240, 200),
				Material = Enum.Material.SmoothPlastic,
				CFrame = body.CFrame
					* CFrame.new(side * scale * 0.18, scale * 0.6, -scale * 0.1)
					* CFrame.Angles(math.rad(-15), 0, math.rad(-side * 10)),
			})
			horn.Parent = model
			weld(body, horn)
		end
	end

	if rarity.Order >= 5 then
		local light = Instance.new("PointLight")
		light.Color = rarity.Color
		light.Range = 8
		light.Brightness = 1.5
		light.Parent = body
	end
	-- Golden / Rainbow variants: shiny material + glow + sparkles
	if variant == "Golden" or variant == "Rainbow" then
		local tint = if variant == "Golden" then Color3.fromRGB(255, 205, 50) else Color3.fromRGB(255, 90, 210)
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d.Name ~= "Eye" and d.Name ~= "Shine" then
				d.Color = if variant == "Golden" then d.Color:Lerp(tint, 0.75) else tint
				d.Material = if variant == "Golden" then Enum.Material.Foil else Enum.Material.Neon
			end
		end
		model:SetAttribute("Variant", variant)
		local glow = Instance.new("PointLight")
		glow.Color = tint
		glow.Range = 9
		glow.Brightness = 2
		glow.Parent = body
		local shimmer = Instance.new("ParticleEmitter")
		shimmer.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		shimmer.Color = ColorSequence.new(if variant == "Golden" then Color3.fromRGB(255, 240, 150) else Color3.new(1, 1, 1))
		shimmer.Size = NumberSequence.new(0.35, 0)
		shimmer.Lifetime = NumberRange.new(0.5, 0.9)
		shimmer.Rate = 8
		shimmer.Speed = NumberRange.new(0.5, 1.5)
		shimmer.SpreadAngle = Vector2.new(180, 180)
		shimmer.LightEmission = 1
		shimmer.Parent = body
	end

	if rarity.Order >= 6 then
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkle.Color = ColorSequence.new(rarity.Color)
		sparkle.Size = NumberSequence.new(0.3, 0)
		sparkle.Lifetime = NumberRange.new(0.6, 1)
		sparkle.Rate = 6
		sparkle.Speed = NumberRange.new(0.5, 1.5)
		sparkle.SpreadAngle = Vector2.new(180, 180)
		sparkle.LightEmission = 1
		sparkle.Parent = body
	end

	return model
end

return PetModel
