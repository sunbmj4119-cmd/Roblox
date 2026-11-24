--[[
	Pet reveal: the egg shakes (rising whoosh), cracks, and the pet pops out
	in a 3D viewport with a rarity-coloured flash. Every card says clearly
	WHAT you got and WHERE it went:
	    🔒 safe in your vault · 🏠 on display (earning) · 📦 in storage
	    ⭐ follows you · 💰 sold (storage full) · ✨ NEW (first of its kind)
	Tap anywhere to continue; afterwards the pets fly into the 🐾 Pets button.
	Stolen pets and reward pets use the same card (no egg).
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

local New, C, T = Lib.New, Lib.Colors, Lib.T
local Hatch = {}
Hatch.Playing = false
Hatch.HUD = nil -- set by Main (fly-to-pets animation)

local dim = New("TextButton", {
	Name = "HatchOverlay",
	Text = "",
	AutoButtonColor = false,
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.35,
	Visible = false,
	ZIndex = 100,
	Parent = Root.Overlay,
})
local holder = Root.Cluster("HatchHolder", Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(900, 440), dim)
New("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 20),
	Parent = holder,
})
local titleCluster = Root.Cluster("HatchTitle", Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.12), UDim2.fromOffset(700, 60), dim)
local title = Lib.Text({ Text = "", Size = UDim2.fromScale(1, 1), MaxTextSize = 46, ZIndex = 104, Parent = titleCluster })
local hintCluster = Root.Cluster("HatchHint", Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -24), UDim2.fromOffset(400, 34), dim)
local hint = Lib.Text({
	Text = "",
	Font = Lib.BodyFont,
	TextColor3 = Color3.fromRGB(220, 220, 230),
	Size = UDim2.fromScale(1, 1),
	MaxTextSize = 20,
	ZIndex = 104,
	Parent = hintCluster,
})

local queue = {}
local skip = false
dim.Activated:Connect(function()
	skip = true
end)

local VARIANT_COLORS = {
	Rainbow = Color3.fromRGB(255, 120, 230),
	Golden = Color3.fromRGB(255, 210, 60),
	Galaxy = Color3.fromRGB(190, 140, 255),
	Frozen = Color3.fromRGB(170, 225, 255),
	Molten = Color3.fromRGB(255, 130, 50),
	Huge = Color3.fromRGB(255, 190, 60),
	Titanic = Color3.fromRGB(255, 120, 60),
}

-- where the pet went, in words + colour
local function placeText(entry): (string, Color3)
	local where = entry.Where
	if where == "Vault" then
		return T("🔒 Safe in your vault"), Color3.fromRGB(110, 170, 255)
	elseif where == "Display" then
		return T("🏠 On display - earning!"), Color3.fromRGB(110, 230, 140)
	elseif where == "Sold" then
		return T("💰 Storage full - sold for %s", Util.Format(entry.Coins or 0)), C.Gold
	elseif where == "Storage" then
		return T("📦 Saved in storage"), Color3.fromRGB(200, 200, 215)
	end
	return "", C.Sub
end

local function slot(entry, eggColor: Color3?)
	local petName, variant = entry.Name, entry.Variant
	local info = Config.Pets[petName]
	local variantColor = variant and VARIANT_COLORS[variant]
	local rarity = Config.Rarities[info.Rarity]
	local frame = New("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(260, 430),
		ZIndex = 101,
		Parent = holder,
	})
	local viewport = New("ViewportFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(260, 240),
		ZIndex = 102,
		Ambient = Color3.fromRGB(200, 200, 200),
		LightColor = Color3.new(1, 1, 1),
		Parent = frame,
	})
	local camera = New("Camera", { FieldOfView = 40, Parent = viewport })
	viewport.CurrentCamera = camera
	local egg = nil
	if eggColor then
		egg = New("Part", {
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(4, 4, 4),
			Color = eggColor,
			Material = Enum.Material.SmoothPlastic,
			Anchored = true,
			CFrame = CFrame.new(),
			Parent = viewport,
		}, { New("SpecialMesh", { MeshType = Enum.MeshType.Sphere, Scale = Vector3.new(1, 1.3, 1) }) })
	end
	camera.CFrame = CFrame.new(Vector3.new(0, 0.6, 11), Vector3.new(0, 0, 0))

	local labels = {}
	if entry.New then
		table.insert(
			labels,
			New("Frame", {
				BackgroundColor3 = C.Pink,
				Size = UDim2.fromOffset(150, 30),
				Position = UDim2.new(0.5, -75, 0, 4),
				ZIndex = 105,
				Visible = false,
				Parent = frame,
			}, {
				Lib.Corner(15),
				Lib.Stroke(Color3.new(1, 1, 1), 2, 0),
				Lib.Text({ Text = "✨ NEW! 📖 +1", Size = UDim2.fromScale(1, 1), MaxTextSize = 18, ZIndex = 106 }),
			})
		)
	end
	local name = Util.PetDisplayName(T(petName), variant and T(variant))
	if entry.Serial then
		name ..= " #" .. tostring(entry.Serial)
	end
	table.insert(
		labels,
		Lib.Text({
			Text = name,
			Size = UDim2.new(1, 0, 0, 38),
			Position = UDim2.fromOffset(0, 242),
			MaxTextSize = 32,
			ZIndex = 103,
			Visible = false,
			Parent = frame,
		})
	)
	table.insert(
		labels,
		Lib.Text({
			Text = (if variant then "✨ " .. string.upper(T(variant)) .. " ✨  " else "") .. string.upper(T(info.Rarity)),
			TextColor3 = variantColor or rarity.Color,
			Size = UDim2.new(1, 0, 0, 30),
			Position = UDim2.fromOffset(0, 280),
			MaxTextSize = 26,
			ZIndex = 103,
			Visible = false,
			Parent = frame,
		})
	)
	-- where it went (only when the server told us)
	local text, color = placeText(entry)
	if text ~= "" then
		table.insert(
			labels,
			New("Frame", {
				BackgroundColor3 = Color3.fromRGB(20, 22, 34),
				BackgroundTransparency = 0.1,
				Size = UDim2.fromOffset(250, 34),
				Position = UDim2.fromOffset(5, 316),
				ZIndex = 103,
				Visible = false,
				Parent = frame,
			}, {
				Lib.Corner(17),
				Lib.Stroke(color, 2.5, 0),
				Lib.Text({
					Text = text,
					TextColor3 = color,
					Size = UDim2.new(1, -12, 1, -6),
					Position = UDim2.fromOffset(6, 3),
					MaxTextSize = 18,
					ZIndex = 104,
				}),
			})
		)
	end
	local income = Util.PetIncome(Config, petName, variant)
	local line
	if entry.Where == "Display" or entry.Where == "Vault" then
		line = T("💰 %s/s in your base", Util.Format(entry.Rate or income))
	elseif entry.Where == "Storage" then
		line = T("Earns 💰%s/s on a pedestal", Util.Format(income))
	elseif entry.Where == "Sold" then
		line = ""
	else
		line = T("💰 %s/s in your base", Util.Format(income))
	end
	if entry.Follow then
		line = (if line ~= "" then line .. "  •  " else "") .. T("⭐ follows you")
	end
	table.insert(
		labels,
		Lib.Text({
			Text = line,
			Font = Lib.BodyFont,
			Size = UDim2.new(1, 0, 0, 24),
			Position = UDim2.fromOffset(0, 356),
			MaxTextSize = 19,
			ZIndex = 103,
			Visible = false,
			Parent = frame,
		})
	)
	return {
		Frame = frame,
		Viewport = viewport,
		Camera = camera,
		Egg = egg,
		Labels = labels,
		Rarity = rarity,
		Entry = entry,
		FlashColor = variantColor or rarity.Color,
	}
end

local function play(pets, eggId, mode)
	Hatch.Playing = true
	skip = false
	Lib.Clear(holder)
	local egg = eggId and Config.Eggs[eggId]
	local stolen = mode == "Stolen"
	local eggColor = if stolen then nil elseif egg then egg.Color else C.Gold
	local slots = {}
	local entries = {}
	for _, raw in pets do
		-- entries are { Name, Variant, Where, ... } (older format: plain name)
		local entry = if type(raw) == "table" then raw else { Name = raw }
		if Config.Pets[entry.Name] then
			table.insert(entries, entry)
			table.insert(slots, slot(entry, eggColor))
		end
	end
	if #slots == 0 then
		Hatch.Playing = false
		return
	end
	title.Text = if stolen then T("🦹 STOLEN!") else ""
	title.TextColor3 = C.Pink
	hint.Text = ""
	dim.Visible = true

	-- shake (eggs only): a rising whoosh while it wobbles
	if eggColor then
		Lib.PlaySound("EggShake")
		local start = os.clock()
		local shakeTime = if egg then 1.3 else 0.5
		while os.clock() - start < shakeTime do
			local t = os.clock() - start
			local intensity = t / shakeTime
			for _, s in slots do
				if s.Egg then
					s.Egg.CFrame = CFrame.Angles(0, 0, math.sin(t * 40) * 0.35 * intensity)
				end
			end
			RunService.RenderStepped:Wait()
		end
		Lib.PlaySound("EggCrack")
	end

	-- reveal
	local best, anyVariant, anyNew, big = 0, false, false, false
	for _, s in slots do
		if s.Egg then
			s.Egg:Destroy()
		end
		local model = PetModel.Build(s.Entry.Name, s.Entry.Variant)
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
		anyVariant = anyVariant or s.Entry.Variant ~= nil
		anyNew = anyNew or s.Entry.New == true
		big = big or s.Entry.Variant == "Huge" or s.Entry.Variant == "Titanic"
		local flash = New("Frame", {
			BackgroundColor3 = s.FlashColor,
			BackgroundTransparency = 0.2,
			Size = UDim2.fromOffset(240, 240),
			Position = UDim2.fromOffset(10, 0),
			ZIndex = 101,
			Parent = s.Frame,
		}, { Lib.Corner(120) })
		TweenService:Create(flash, TweenInfo.new(0.8), { BackgroundTransparency = 1 }):Play()
	end
	-- the sound matches how special it is
	if big or best >= 6 then
		Lib.PlaySound("Fanfare")
		Lib.PlaySound("Cheer")
	elseif best >= 5 or stolen then
		Lib.PlaySound("Fanfare")
	elseif best >= 3 or anyVariant then
		Lib.PlaySound("RevealRare")
	else
		Lib.PlaySound("Reveal")
	end
	if anyNew then
		task.delay(0.35, function()
			Lib.PlaySound("Discover")
		end)
	end

	-- spin until tapped (or a few seconds)
	skip = false
	task.delay(0.6, function()
		if dim.Visible then
			hint.Text = T("Tap to continue")
		end
	end)
	local spinStart = os.clock()
	local duration = if best >= 5 or big then 4.5 else 3
	while os.clock() - spinStart < duration and not (skip and os.clock() - spinStart > 0.5) do
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
	-- the pets fly into the Pets button (so you see where they went)
	local hud = Hatch.HUD
	if hud and hud.PetsLanded then
		task.spawn(hud.PetsLanded, entries)
	end
end

function Hatch.Play(pets, eggId, mode)
	table.insert(queue, { Pets = pets, Egg = eggId, Mode = mode })
	if Hatch.Playing then
		return
	end
	task.spawn(function()
		while #queue > 0 do
			local item = table.remove(queue, 1)
			local ok, err = pcall(play, item.Pets, item.Egg, item.Mode)
			if not ok then
				warn("[Hatch] " .. tostring(err))
				dim.Visible = false
				Hatch.Playing = false
			end
		end
	end)
end

-- star eggs, rewards, lucky blocks, stolen pets, quick hatches at the stands
Net.On("HatchResult", function(pets, eggId, mode)
	Hatch.Play(pets, eggId, mode)
end)

return Hatch
