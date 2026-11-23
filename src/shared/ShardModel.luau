--[[
	ShardModel: procedural STAR EGG (no assets needed). Falling stars and
	meteors drop these; carried home they hatch into a pet.
	ShardModel.Build(config, rarityId, scale) -> Model with PrimaryPart "Core".
	Parts are welded to Core; the caller decides Anchored / where to weld it.
]]
local ShardModel = {}

local function piece(name: string, size: Vector3, color: Color3, material: Enum.Material, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

function ShardModel.Build(config, rarityId: string, scale: number?): Model
	local def = config.Shards.Rarities[rarityId] or config.Shards.Rarities.Common
	local s = (scale or 1) * 1.15
	local index = table.find(config.Shards.Order, rarityId) or 1
	local model = Instance.new("Model")
	model.Name = "StarEgg_" .. rarityId
	model:SetAttribute("Rarity", rarityId)

	-- the egg: a stretched sphere, glowing in the star's colour
	local secret = rarityId == "Secret"
	local core = piece(
		"Core",
		Vector3.new(2.2, 2.8, 2.2) * s,
		if secret then Color3.fromRGB(25, 12, 45) else def.Color:Lerp(Color3.new(1, 1, 1), 0.35),
		if secret then Enum.Material.Glass else Enum.Material.SmoothPlastic,
		model
	)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = core
	model.PrimaryPart = core

	-- glowing zig-zag band around the middle
	local band = piece("Band", Vector3.new(0.35 * s, 2.25 * s, 2.25 * s), def.Color, Enum.Material.Neon, model)
	band.Shape = Enum.PartType.Cylinder
	band.CFrame = core.CFrame * CFrame.Angles(0, 0, math.rad(90))
	weld(core, band)

	-- little stars stuck to the shell (more for rarer eggs)
	for i = 1, math.min(2 + index, 7) do
		local angle = (i / math.min(2 + index, 7)) * math.pi * 2
		local y = if i % 2 == 0 then 0.55 else -0.45
		local star = piece("Star", Vector3.new(0.4, 0.4, 0.4) * s, Color3.fromRGB(255, 245, 190), Enum.Material.Neon, model)
		star.CFrame = core.CFrame
			* CFrame.new(math.cos(angle) * 1.02 * s, y * s, math.sin(angle) * 1.02 * s)
			* CFrame.Angles(0, -angle, math.rad(45))
		weld(core, star)
	end

	-- legendary+ eggs get a halo
	if index >= 4 then
		local ring = piece("Ring", Vector3.new(0.18, 3.4 * s, 3.4 * s), def.Color, Enum.Material.Neon, model)
		ring.Shape = Enum.PartType.Cylinder
		ring.Transparency = 0.35
		ring.CFrame = core.CFrame * CFrame.new(0, 1.9 * s, 0) * CFrame.Angles(0, 0, math.rad(90))
		weld(core, ring)
	end

	local light = Instance.new("PointLight")
	light.Color = def.Color
	light.Range = 8 + index * 2
	light.Brightness = 1.5 + index * 0.3
	light.Parent = core

	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "Sparkles"
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Color = ColorSequence.new(def.Color)
	sparkles.LightEmission = 1
	sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45 * s), NumberSequenceKeypoint.new(1, 0) })
	sparkles.Lifetime = NumberRange.new(0.6, 1.1)
	sparkles.Speed = NumberRange.new(1, 3)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Rate = 4 + index * 3
	sparkles.Parent = core

	return model
end

-- every part anchored (displays / ground drops) or not (carried)
function ShardModel.SetAnchored(model: Model, anchored: boolean)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = anchored
		end
	end
end

return ShardModel
