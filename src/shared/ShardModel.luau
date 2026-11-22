--[[
	ShardModel: procedural star-shard crystal (no assets needed).
	ShardModel.Build(config, rarityId, scale) -> Model with PrimaryPart "Core".
	Every part is unanchored-safe (welded to Core), non-colliding and
	non-queryable; the caller decides Anchored / where to weld it.
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

function ShardModel.Build(config, rarityId: string, scale: number?): Model
	local def = config.Shards.Rarities[rarityId] or config.Shards.Rarities.Common
	local s = scale or 1
	local index = table.find(config.Shards.Order, rarityId) or 1
	local model = Instance.new("Model")
	model.Name = "Shard_" .. rarityId
	model:SetAttribute("Rarity", rarityId)

	local secret = rarityId == "Secret"
	local coreColor = if secret then Color3.fromRGB(20, 10, 35) else def.Color
	local core = piece("Core", Vector3.new(1.3, 2.6, 1.3) * s, coreColor, if secret then Enum.Material.Glass else Enum.Material.Neon, model)
	core.CFrame = CFrame.Angles(0, math.rad(45), math.rad(12))
	model.PrimaryPart = core

	-- side crystals: rarer shards grow more of them
	local count = math.min(2 + index, 6)
	for i = 1, count do
		local angle = (i / count) * math.pi * 2
		local crystal = piece(
			"Crystal",
			Vector3.new(0.6, 1.2 + (i % 2) * 0.5, 0.6) * s,
			def.Color:Lerp(Color3.new(1, 1, 1), 0.25),
			Enum.Material.Neon,
			model
		)
		crystal.CFrame = core.CFrame
			* CFrame.new(math.cos(angle) * 0.75 * s, -0.5 * s, math.sin(angle) * 0.75 * s)
			* CFrame.Angles(math.cos(angle) * 0.6, 0, math.sin(angle) * 0.6)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = core
		weld.Part1 = crystal
		weld.Parent = crystal
	end

	-- legendary+ get a spinning-looking halo ring
	if index >= 4 then
		local ring = piece("Ring", Vector3.new(0.2, 3.4, 3.4) * s, def.Color, Enum.Material.Neon, model)
		ring.Shape = Enum.PartType.Cylinder
		ring.Transparency = 0.35
		ring.CFrame = CFrame.new(core.Position) * CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(math.rad(20), 0, 0)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = core
		weld.Part1 = ring
		weld.Parent = ring
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
