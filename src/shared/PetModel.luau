--[[
	PetModel: cute, characterful pets built from primitive parts (no assets).
	Round "mochi" body, big shiny eyes, blushing cheeks, and features picked
	from the species name / flags: bunny ears, cat ears, fox tail, floppy
	puppy ears, owl beak + tufts, dragon horns, bat wings, slime shine,
	penguin belly, crowns for kings ... Mutations change the look:
	Golden (gold foil), Rainbow (colour cycle on clients), Galaxy (cosmic),
	Frozen (ice), Molten (lava cracks + embers).

	PetModel.Build(petName, variant) -> anchored Model, front faces -Z,
	pivot = PrimaryPart "Body". A custom model named after the pet inside
	ReplicatedStorage.PetModels replaces the generated one.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.Config)
local Util = require(script.Parent.Util)

local PetModel = {}

local function part(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

-- ellipsoid: a ball squashed / stretched with a sphere mesh
local function blob(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?)
	local p = part(model, name, size, cf, color, material, Enum.PartType.Block)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

local function wedge(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?)
	local p = Instance.new("WedgePart")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Parent = model
	return p
end

local function has(name: string, ...): boolean
	local lower = string.lower(name)
	for _, word in { ... } do
		if string.find(lower, word, 1, true) then
			return true
		end
	end
	return false
end

local function sparkles(parent: BasePart, color: Color3, rate: number, size: number?)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Sparkles"
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color)
	emitter.Size = NumberSequence.new(size or 0.35, 0)
	emitter.Lifetime = NumberRange.new(0.5, 1)
	emitter.Rate = rate
	emitter.Speed = NumberRange.new(0.5, 1.5)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.LightEmission = 1
	emitter.Parent = parent
	return emitter
end

local function custom(petName: string): Model?
	local folder = ReplicatedStorage:FindFirstChild("PetModels")
	local source = folder and folder:FindFirstChild(petName)
	if not source then
		return nil
	end
	local clone = source:Clone()
	if not clone:IsA("Model") or not clone.PrimaryPart then
		return nil
	end
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

-- uniform scale (ScaleTo, with a manual fallback)
local function scaleModel(model: Model, factor: number)
	if math.abs(factor - 1) < 0.001 then
		return
	end
	local ok = pcall(function()
		model:ScaleTo(model:GetScale() * factor)
	end)
	if not ok then
		local origin = model:GetPivot().Position
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Size *= factor
				local offset = d.Position - origin
				d.CFrame = CFrame.new(origin + offset * factor) * (d.CFrame - d.Position)
			end
		end
	end
end

-- 🌱 growth: babies are small, legends big; ★ evolved pets get a star halo
local function applyGrowth(model: Model, growth)
	local body = model.PrimaryPart
	if not growth or not body then
		return
	end
	local level = math.max(1, tonumber(growth.Level) or 1)
	local stars = math.max(0, tonumber(growth.Stars) or 0)
	local stage = Util.PetStage(Config, level)
	local _, size = model:GetBoundingBox()
	local top = body.Position.Y - body.Size.Y / 2 + size.Y
	if stage.Id == "Legend" then
		-- a little golden crown
		local crownY = top + 0.15
		for i = 1, 5 do
			local angle = i / 5 * math.pi * 2
			part(
				model,
				"Crown",
				Vector3.new(0.22, 0.45, 0.22),
				CFrame.new(body.Position.X + math.cos(angle) * 0.42, crownY, body.Position.Z + math.sin(angle) * 0.42),
				Color3.fromRGB(255, 205, 60),
				Enum.Material.SmoothPlastic
			)
		end
	end
	if stars > 0 then
		local color = Config.Growth.StarColors[math.clamp(stars, 1, #Config.Growth.StarColors)]
		local halo = part(
			model,
			"StarHalo",
			Vector3.new(0.14, 1.5 + stars * 0.25, 1.5 + stars * 0.25),
			CFrame.new(body.Position.X, top + 0.7, body.Position.Z) * CFrame.Angles(0, 0, math.rad(90)),
			color,
			Enum.Material.Neon,
			Enum.PartType.Cylinder
		)
		halo.Transparency = 0.25
		sparkles(body, color, 4 + stars * 4, 0.3 + stars * 0.05)
	end
	scaleModel(model, stage.Scale * (1 + Config.Growth.Evolve.StarScale * stars))
end

-- ☄️ meteor pets: a glowing crack + a little comet tail
local function applyMeteorLook(model: Model, info)
	local body = model.PrimaryPart
	if not info.Meteor or not body then
		return
	end
	local glow = info.Color:Lerp(Color3.fromRGB(255, 200, 80), 0.5)
	for i = 1, 3 do
		local crack = part(
			model,
			"MeteorCrack",
			Vector3.new(0.12, body.Size.Y * 0.5, 0.12),
			body.CFrame * CFrame.new((i - 2) * body.Size.X * 0.22, 0, body.Size.Z * 0.49) * CFrame.Angles(0, 0, math.rad((i - 2) * 25)),
			glow,
			Enum.Material.Neon
		)
		crack.CanQuery = false
	end
	local tail = Instance.new("ParticleEmitter")
	tail.Texture = "rbxasset://textures/particles/fire_main.dds"
	tail.Color = ColorSequence.new(glow, info.Color)
	tail.Size = NumberSequence.new(0.5, 0)
	tail.Lifetime = NumberRange.new(0.3, 0.6)
	tail.Rate = 8
	tail.Speed = NumberRange.new(0.5, 1.5)
	tail.LightEmission = 0.6
	tail.Parent = body
end

function PetModel.Build(petName: string, variant: string?, growth): Model
	local customModel = custom(petName)
	if customModel then
		return customModel
	end

	local info = Config.Pets[petName] or { Rarity = "Common", Color = Color3.new(1, 1, 1), Shape = "Ball" }
	local rarity = Config.Rarities[info.Rarity] or Config.Rarities.Common
	local s = 1.9 + rarity.Order * 0.16 -- rarer pets are a bit bigger
	local color = info.Color
	local dark = color:Lerp(Color3.new(0, 0, 0), 0.35)
	local light = color:Lerp(Color3.new(1, 1, 1), 0.45)

	local model = Instance.new("Model")
	model.Name = petName

	-- body: a round, slightly squashed mochi (taller for "Block" species)
	local tall = info.Shape == "Block"
	local bodySize = Vector3.new(s, s * (if tall then 1.05 else 0.92), s * 0.95)
	local body = blob(model, "Body", bodySize, CFrame.new(0, bodySize.Y / 2, 0), color)
	model.PrimaryPart = body
	local top = bodySize.Y
	local front = -bodySize.Z / 2

	local slime = has(petName, "slime")
	if slime then
		body.Material = Enum.Material.Glass
		body.Transparency = 0.15
		blob(model, "Shine", Vector3.new(s * 0.25, s * 0.18, s * 0.1), CFrame.new(-s * 0.22, top * 0.78, front * 0.8), Color3.new(1, 1, 1))
	end

	-- belly patch (penguins, owls, bears ...)
	if has(petName, "penguin", "owl", "bear", "yeti", "pup", "dog") then
		blob(model, "Belly", Vector3.new(s * 0.62, s * 0.55, s * 0.2), CFrame.new(0, top * 0.36, front * 0.86), light)
	end

	-- big shiny eyes
	local eyeY = top * 0.6
	local eyeSize = s * (if has(petName, "owl") then 0.36 else 0.28)
	for _, side in { -1, 1 } do
		local x = side * s * 0.21
		blob(model, "Eye", Vector3.new(eyeSize, eyeSize * 1.15, eyeSize * 0.4), CFrame.new(x, eyeY, front * 0.88), Color3.new(1, 1, 1))
		blob(
			model,
			"Pupil",
			Vector3.new(eyeSize * 0.66, eyeSize * 0.8, eyeSize * 0.3),
			CFrame.new(x, eyeY - eyeSize * 0.05, front * 0.96),
			Color3.fromRGB(25, 20, 35)
		)
		blob(
			model,
			"Shine",
			Vector3.new(eyeSize * 0.24, eyeSize * 0.24, eyeSize * 0.12),
			CFrame.new(x + side * eyeSize * 0.12, eyeY + eyeSize * 0.18, front * 1.02),
			Color3.new(1, 1, 1)
		)
		-- blush
		local cheek = blob(
			model,
			"Blush",
			Vector3.new(s * 0.16, s * 0.08, s * 0.05),
			CFrame.new(side * s * 0.34, top * 0.42, front * 0.82),
			Color3.fromRGB(255, 130, 150)
		)
		cheek.Transparency = 0.25
	end

	-- mouth / beak
	if has(petName, "owl", "chick", "phoenix", "penguin", "griffin", "duck") then
		wedge(
			model,
			"Beak",
			Vector3.new(s * 0.16, s * 0.14, s * 0.18),
			CFrame.new(0, top * 0.44, front * 1.02) * CFrame.Angles(math.rad(-90), 0, 0),
			Color3.fromRGB(255, 170, 40)
		)
	else
		blob(model, "Mouth", Vector3.new(s * 0.12, s * 0.06, s * 0.05), CFrame.new(0, top * 0.43, front * 0.96), Color3.fromRGB(60, 30, 40))
	end

	-- ears
	if has(petName, "bunny") then
		for _, side in { -1, 1 } do
			blob(
				model,
				"Ear",
				Vector3.new(s * 0.2, s * 0.7, s * 0.14),
				CFrame.new(side * s * 0.2, top + s * 0.25, 0) * CFrame.Angles(0, 0, math.rad(-side * 10)),
				color
			)
			blob(
				model,
				"EarInner",
				Vector3.new(s * 0.1, s * 0.5, s * 0.05),
				CFrame.new(side * s * 0.2, top + s * 0.25, -s * 0.07) * CFrame.Angles(0, 0, math.rad(-side * 10)),
				Color3.fromRGB(255, 170, 190)
			)
		end
	elseif has(petName, "pup", "dog") then
		for _, side in { -1, 1 } do
			blob(
				model,
				"Ear",
				Vector3.new(s * 0.18, s * 0.42, s * 0.12),
				CFrame.new(side * s * 0.46, top * 0.72, 0) * CFrame.Angles(0, 0, math.rad(side * 25)),
				dark
			)
		end
	elseif has(petName, "bear", "yeti", "golem", "titan") then
		for _, side in { -1, 1 } do
			blob(model, "Ear", Vector3.new(s * 0.24, s * 0.24, s * 0.14), CFrame.new(side * s * 0.33, top * 0.95, 0), dark)
		end
	elseif info.Ears or has(petName, "cat", "kitty", "fox", "wolf") then
		local tallEars = has(petName, "fox", "wolf")
		for _, side in { -1, 1 } do
			wedge(
				model,
				"Ear",
				Vector3.new(s * 0.08, s * (if tallEars then 0.42 else 0.3), s * 0.3),
				CFrame.new(side * s * 0.28, top * 0.92 + s * 0.12, 0) * CFrame.Angles(0, math.rad(90), math.rad(-side * 12)),
				color
			)
		end
	end

	-- owl tufts / phoenix crest
	if has(petName, "owl") then
		for _, side in { -1, 1 } do
			wedge(
				model,
				"Tuft",
				Vector3.new(s * 0.06, s * 0.22, s * 0.16),
				CFrame.new(side * s * 0.3, top * 0.98, 0) * CFrame.Angles(0, math.rad(90), math.rad(-side * 25)),
				dark
			)
		end
	elseif has(petName, "phoenix", "chick") then
		for i = -1, 1 do
			blob(
				model,
				"Crest",
				Vector3.new(s * 0.1, s * 0.3, s * 0.1),
				CFrame.new(i * s * 0.09, top + s * 0.08, 0) * CFrame.Angles(0, 0, math.rad(-i * 20)),
				if has(petName, "phoenix") then Color3.fromRGB(255, 200, 40) else color
			)
		end
	end

	-- horns
	if info.Horns or has(petName, "dragon", "dino", "serpent") then
		for _, side in { -1, 1 } do
			wedge(
				model,
				"Horn",
				Vector3.new(s * 0.08, s * 0.3, s * 0.16),
				CFrame.new(side * s * 0.22, top + s * 0.06, s * 0.05) * CFrame.Angles(math.rad(-15), math.rad(90), math.rad(-side * 15)),
				Color3.fromRGB(250, 240, 210)
			)
		end
	end

	-- wings
	if info.Wings then
		local bat = has(petName, "bat")
		for _, side in { -1, 1 } do
			local wing = blob(
				model,
				"Wing",
				Vector3.new(s * 0.18, s * (if bat then 0.55 else 0.45), s * 0.55),
				CFrame.new(side * s * 0.55, top * 0.55, s * 0.08) * CFrame.Angles(0, 0, math.rad(side * (if bat then 40 else 25))),
				if bat then dark else light
			)
			if rarity.Order >= 5 then
				wing.Material = Enum.Material.Neon
				wing.Transparency = 0.2
			end
		end
	end

	-- tails
	if has(petName, "fox", "wolf", "cat", "kitty", "dragon", "dino", "serpent") then
		local fluffy = has(petName, "fox", "wolf")
		local tail = blob(
			model,
			"Tail",
			Vector3.new(s * (if fluffy then 0.3 else 0.16), s * (if fluffy then 0.3 else 0.16), s * (if fluffy then 0.62 else 0.55)),
			CFrame.new(s * 0.12, top * 0.3, -front * 1.05) * CFrame.Angles(math.rad(35), 0, 0),
			color
		)
		if fluffy then
			blob(model, "TailTip", Vector3.new(s * 0.24, s * 0.24, s * 0.22), tail.CFrame * CFrame.new(0, 0, s * 0.26), Color3.new(1, 1, 1))
		end
	end

	-- royalty
	if has(petName, "king", "emperor", "midas", "titan") then
		local gold = Color3.fromRGB(255, 205, 50)
		part(
			model,
			"Crown",
			Vector3.new(s * 0.16, s * 0.5, s * 0.5),
			CFrame.new(0, top + s * 0.06, 0) * CFrame.Angles(0, 0, math.rad(90)),
			gold,
			Enum.Material.Foil,
			Enum.PartType.Cylinder
		)
		for i = 0, 3 do
			local angle = i * math.pi / 2
			wedge(
				model,
				"CrownSpike",
				Vector3.new(s * 0.06, s * 0.16, s * 0.12),
				CFrame.new(math.cos(angle) * s * 0.2, top + s * 0.2, math.sin(angle) * s * 0.2) * CFrame.Angles(0, -angle, 0),
				gold,
				Enum.Material.Foil
			)
		end
	end

	-- little feet
	for _, side in { -1, 1 } do
		blob(model, "Foot", Vector3.new(s * 0.26, s * 0.14, s * 0.3), CFrame.new(side * s * 0.24, s * 0.05, front * 0.55), dark)
	end

	-- rarity flair
	if rarity.Order >= 5 then
		sparkles(body, rarity.Color, 4 + (rarity.Order - 5) * 4, 0.3)
	end
	if rarity.Order >= 6 then
		local halo = part(
			model,
			"Halo",
			Vector3.new(0.12, s * 0.7, s * 0.7),
			CFrame.new(0, top + s * 0.45, 0) * CFrame.Angles(0, 0, math.rad(90)),
			rarity.Color,
			Enum.Material.Neon,
			Enum.PartType.Cylinder
		)
		halo.Transparency = 0.3
	end

	-- mutations
	if variant then
		model:SetAttribute("Variant", variant)
		local keep = { Eye = true, Pupil = true, Shine = true, Blush = true, Mouth = true, EarInner = true, Halo = true }
		local tint, material, glow
		if variant == "Golden" then
			tint, material, glow = Color3.fromRGB(255, 205, 50), Enum.Material.Foil, Color3.fromRGB(255, 230, 120)
		elseif variant == "Rainbow" then
			tint, material, glow = Color3.fromRGB(255, 90, 210), Enum.Material.SmoothPlastic, Color3.fromRGB(255, 200, 245)
		elseif variant == "Galaxy" then
			tint, material, glow = Color3.fromRGB(70, 30, 140), Enum.Material.Glass, Color3.fromRGB(190, 140, 255)
		elseif variant == "Frozen" then
			tint, material, glow = Color3.fromRGB(170, 225, 255), Enum.Material.Ice, Color3.fromRGB(220, 245, 255)
		elseif variant == "Molten" then
			tint, material, glow = Color3.fromRGB(255, 110, 30), Enum.Material.CrackedLava, Color3.fromRGB(255, 160, 60)
		end
		if tint then
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and not keep[d.Name] then
					d.Color = if variant == "Golden" then d.Color:Lerp(tint, 0.75) else tint
					d.Material = material
				end
			end
			local light = Instance.new("PointLight")
			light.Color = glow
			light.Range = 7
			light.Brightness = 0.7 -- (soft: a brighter light washed out the pedestals)
			light.Parent = body
			sparkles(body, glow, if variant == "Galaxy" then 14 else 8, if variant == "Galaxy" then 0.45 else 0.35)
			if variant == "Molten" then
				local fire = Instance.new("ParticleEmitter")
				fire.Texture = "rbxasset://textures/particles/fire_main.dds"
				fire.Color = ColorSequence.new(Color3.fromRGB(255, 180, 60), Color3.fromRGB(255, 60, 20))
				fire.Size = NumberSequence.new(0.6, 0)
				fire.Lifetime = NumberRange.new(0.3, 0.6)
				fire.Rate = 10
				fire.Speed = NumberRange.new(1, 3)
				fire.LightEmission = 1
				fire.Parent = body
			end
		end
		-- HUGE: same colours, twice the size, a golden shimmer
		local def = Util.VariantDef(Config, variant)
		if def and def.Scale and def.Scale ~= 1 then
			sparkles(body, Color3.fromRGB(255, 225, 120), 10, 0.5)
			local ok = pcall(function()
				model:ScaleTo(def.Scale)
			end)
			if not ok then
				for _, d in model:GetDescendants() do
					if d:IsA("BasePart") then
						d.Size *= def.Scale
						d.CFrame = CFrame.new(d.Position * def.Scale) * (d.CFrame - d.Position)
					end
				end
			end
		end
	end

	applyMeteorLook(model, info)
	applyGrowth(model, growth)
	return model
end

return PetModel
