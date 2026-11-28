--[[
	IncubatorService: 🥚 star eggs you bring home grow in an incubator before
	they hatch (like Steal an Egg's growing eggs / Grow a Garden's timers):

	  * rarer eggs take longer (15s ... 30 min), golden-meteor eggs are faster,
	  * the clock keeps running while you're offline -> a reason to come back,
	  * more incubators with every house level,
	  * tap a ready incubator at home to hatch it (the usual reveal card),
	    or skip the wait with 💎.
	The tutorial's first egg (and any egg when every incubator is full)
	still hatches right away, so nothing is ever lost.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local ShardModel = require(Shared.ShardModel)
local Net = require(script.Parent.Net)

local Incubator = {}
local Services
local Data
local World

local SETTINGS = Config.Incubator
local rebuilding = {}

-- pods in the front-left corner of the land (clear of the pads, the
-- corner tower and every house level's build area)
local SPOTS = {
	{ -21, -32.6 },
	{ -24.8, -32.6 },
	{ -28.6, -32.6 },
	{ -21, -28.8 },
	{ -24.8, -28.8 },
	{ -28.6, -28.8 },
	{ -32.4, -32.6 },
	{ -32.4, -28.8 },
}

local function now(): number
	return os.time()
end

local function houseLevel(data): number
	return Util.HouseLevel(Config, data)
end

function Incubator:Slots(data): number
	return Util.IncubatorSlots(Config, houseLevel(data))
end

local function rarityName(id: string): string
	local def = Config.Shards.Rarities[id]
	return if def then def.Name else id
end

---------------------------------------------------------------------------
-- the pods
---------------------------------------------------------------------------
local function podFolder(player: Player)
	local plot = Services.BaseService:PlotOf(player)
	if not plot then
		return nil, nil
	end
	local folder = plot.Model:FindFirstChild("Incubators")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Incubators"
		folder.Parent = plot.Model
	end
	return folder, plot
end

local function buildPod(cf: CFrame, index: number): Model
	local model = Instance.new("Model")
	model.Name = "Incubator_" .. index
	local function piece(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material, shape)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf * offset
		p.Color = color
		p.Material = material
		p.Anchored = true
		p.CanCollide = name == "Base"
		p.CanQuery = name == "Base" or name == "Dome"
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		if shape then
			p.Shape = shape
		end
		p.Parent = model
		return p
	end
	local base = piece(
		"Base",
		Vector3.new(0.8, 3.6, 3.6),
		CFrame.new(0, 0.4, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(70, 75, 95),
		Enum.Material.Metal,
		Enum.PartType.Cylinder
	)
	piece(
		"Ring",
		Vector3.new(0.25, 3.8, 3.8),
		CFrame.new(0, 0.85, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(120, 220, 255),
		Enum.Material.Neon,
		Enum.PartType.Cylinder
	)
	local dome =
		piece("Dome", Vector3.one * 3.2, CFrame.new(0, 2.3, 0), Color3.fromRGB(190, 235, 255), Enum.Material.Glass, Enum.PartType.Ball)
	dome.Transparency = 0.6
	model.PrimaryPart = base
	local gui = Instance.new("BillboardGui")
	gui.Name = "Timer"
	gui.Size = UDim2.new(5, 0, 1.4, 0)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 4.6, 0)
	gui.MaxDistance = 60
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = base
	return model
end

-- (re)build the pods and the eggs inside them
function Incubator:Render(player: Player)
	local data = Data:Get(player)
	local folder, plot = podFolder(player)
	if not data or not folder or not plot then
		return
	end
	folder:ClearAllChildren()
	local slots = self:Slots(data)
	for index = 1, slots do
		local spot = SPOTS[index]
		if spot then
			local cf = plot.CFrame * CFrame.new(spot[1], 0.4, spot[2])
			local pod = buildPod(cf, index)
			pod:SetAttribute("Slot", index)
			local entry = data.Incubators[index]
			if entry then
				local egg = ShardModel.Build(Config, entry.Rarity, 0.55)
				egg.Name = "Egg"
				ShardModel.SetAnchored(egg, true)
				egg:PivotTo(cf * CFrame.new(0, 2.2, 0))
				for _, part in egg:GetDescendants() do
					if part:IsA("BasePart") then
						part.CanQuery = false
						part.CanCollide = false
					end
				end
				egg.Parent = pod
				pod:SetAttribute("Ready", entry.Ready)
				-- one owner-only prompt: "Hatch" when ready, "⚡ Hatch now" (💎) before.
				-- (Role = Owner: the client shows it to the owner only. The text is
				-- set here, at build time, so it gets translated - the pod is rebuilt
				-- the moment its egg is ready.)
				local base = pod.PrimaryPart :: BasePart
				local ready = now() >= entry.Ready
				local hatchPrompt = Instance.new("ProximityPrompt")
				hatchPrompt.Name = "HatchPrompt"
				if ready then
					hatchPrompt.ActionText = "Hatch"
					hatchPrompt.ObjectText = rarityName(entry.Rarity)
					hatchPrompt.HoldDuration = 0.3
				else
					hatchPrompt.ActionText = "⚡ Hatch now"
					hatchPrompt.ObjectText = "💎" .. tostring(self:SkipCost(entry))
					hatchPrompt.HoldDuration = 1
				end
				hatchPrompt.MaxActivationDistance = 10
				hatchPrompt.RequiresLineOfSight = false
				hatchPrompt:SetAttribute("Role", "Owner")
				hatchPrompt.Parent = base
				local id = entry.Id or index
				hatchPrompt.Triggered:Connect(function(who)
					if who == player then
						self:Hatch(player, id, true)
					end
				end)
			end
			pod.Parent = folder
		end
	end
	self:Refresh(player)
end

-- timers + egg growth + which prompt shows (every second)
function Incubator:Refresh(player: Player)
	local data = Data:Get(player)
	local folder = podFolder(player)
	if not data or not folder then
		return
	end
	if #folder:GetChildren() == 0 then
		-- (no pods yet: e.g. the plot was assigned after we loaded)
		if not rebuilding[player] then
			rebuilding[player] = true
			pcall(self.Render, self, player)
			rebuilding[player] = nil
		end
		return
	end
	local t = now()
	for _, pod in folder:GetChildren() do
		local index = pod:GetAttribute("Slot")
		local entry = index and data.Incubators[index]
		local base = pod.PrimaryPart
		local gui = base and base:FindFirstChild("Timer")
		local label = gui and gui:FindFirstChild("Text")
		if label then
			if not entry then
				World.SetText(label, "🥚 empty")
				label.TextColor3 = Color3.fromRGB(170, 180, 200)
			elseif t >= entry.Ready then
				World.SetText(label, "✅ READY!")
				label.TextColor3 = Color3.fromRGB(120, 255, 160)
			else
				World.SetText(label, "🥚 %s", Util.FormatTime(entry.Ready - t))
				label.TextColor3 = Color3.fromRGB(255, 230, 150)
			end
		end
		if entry and base then
			local hatchPrompt = base:FindFirstChild("HatchPrompt")
			if hatchPrompt and hatchPrompt:IsA("ProximityPrompt") and t < entry.Ready then
				local cost = "💎" .. tostring(self:SkipCost(entry))
				if hatchPrompt.ObjectText ~= cost then
					hatchPrompt.ObjectText = cost
				end
			end
			-- the egg grows while it incubates
			local egg = pod:FindFirstChild("Egg")
			if egg and egg:IsA("Model") then
				local progress = math.clamp(1 - (entry.Ready - t) / math.max(1, entry.Total), 0, 1)
				local scale = 0.75 + progress * 0.45
				if math.abs((egg:GetAttribute("Grown") or 0) - scale) > 0.02 then
					egg:SetAttribute("Grown", scale)
					pcall(function()
						egg:ScaleTo(scale)
					end)
				end
			end
		end
	end
end

function Incubator:SkipCost(entry): number
	local left = math.max(0, entry.Ready - now())
	return math.max(1, math.ceil(left / 60) * SETTINGS.SkipGemsPerMinute)
end

---------------------------------------------------------------------------
-- public
---------------------------------------------------------------------------
-- a delivered star egg: into a free incubator (false = hatch it right away)
function Incubator:Add(player: Player, item): boolean
	local data = Data:Get(player)
	if not data or item.Kind ~= "Egg" or not data.Tutorial.Done then
		return false
	end
	data.Incubators = data.Incubators or {}
	local slots = self:Slots(data)
	if #data.Incubators >= slots then
		-- full: a ready egg hatches to make room (parked ready eggs must
		-- not let new eggs skip their timers)
		local oldest, oldestReady = nil, math.huge
		for index, entry in data.Incubators do
			if now() >= entry.Ready and entry.Ready < oldestReady then
				oldest, oldestReady = index, entry.Ready
			end
		end
		if not oldest or not self:Hatch(player, oldest, false) or #data.Incubators >= slots then
			Net:Notify(player, "🥚 All incubators are busy - this egg hatches right away!", Color3.fromRGB(255, 210, 120))
			return false
		end
	end
	local seconds = Util.IncubateSeconds(Config, item.Rarity, item.Golden)
	table.insert(data.Incubators, {
		Id = HttpService:GenerateGUID(false),
		Egg = item.Egg,
		Rarity = item.Rarity,
		MeteorKind = item.MeteorKind,
		Golden = item.Golden,
		Ready = now() + seconds,
		Total = seconds,
	})
	Data:MarkDirty(player)
	-- (from here on the egg is stored: nothing below may make it hatch twice)
	pcall(self.Render, self, player)
	pcall(function()
		Net:Notify(
			player,
			"🥚 Your %s is incubating - ready in %s!",
			Color3.fromRGB(150, 230, 255),
			rarityName(item.Rarity),
			Util.FormatTime(seconds)
		)
		Net:Send(player, "EggIncubating", item.Rarity, seconds)
	end)
	return true
end

-- key = the egg's Id (prompts: an old prompt can never hit another egg
-- after the list shifted) or its slot number
function Incubator:Hatch(player: Player, key: number | string, skip: boolean): boolean
	local data = Data:Get(player)
	local list = data and data.Incubators
	if not list then
		return false
	end
	local index = if type(key) == "number" then key else nil
	if type(key) == "string" then
		for i, candidate in list do
			if candidate.Id == key then
				index = i
				break
			end
		end
	end
	local entry = index and list[index]
	if not entry then
		return false
	end
	local cost = 0
	if now() < entry.Ready then
		if not skip then
			return false
		end
		cost = self:SkipCost(entry)
		if data.Gems < cost then
			Net:Notify(player, "Not enough 💎 (%s)", Color3.fromRGB(255, 110, 110), Util.Format(cost))
			return false
		end
		data.Gems -= cost
	end
	table.remove(list, index)
	local def = Config.Shards.Rarities[entry.Rarity]
	local meteorInfo = if entry.MeteorKind then { Kind = entry.MeteorKind, Golden = entry.Golden, Rarity = entry.Rarity } else nil
	local ok, err =
		pcall(Services.PetService.HatchStarEgg, Services.PetService, player, entry.Egg, if def then def.Luck or 1 else 1, meteorInfo)
	if not ok then
		-- (never lose the egg or the gems)
		warn("[Incubator] hatch failed: " .. tostring(err))
		table.insert(list, math.min(index, #list + 1), entry)
		data.Gems += cost
		cost = 0
	end
	if cost > 0 then
		Services.Analytics:Economy(player, "Sink", "Gems", cost, data.Gems, "Gameplay", "IncubatorSkip")
	end
	Data:MarkDirty(player)
	pcall(self.Render, self, player)
	return ok
end

-- how many eggs are ready (for the HUD)
function Incubator:ReadyCount(data): number
	local count = 0
	for _, entry in data.Incubators or {} do
		if now() >= entry.Ready then
			count += 1
		end
	end
	return count
end

-- cloud tests: make an egg ready now
function Incubator:FinishForTest(player: Player, index: number)
	assert(not RunService:IsRunning(), "test hook used on a live server")
	local data = Data:Get(player)
	local entry = data and data.Incubators[index]
	if entry then
		entry.Ready = now() - 1
	end
end

function Incubator:Init(services)
	Services = services
	Data = services.DataService
	World = services.WorldService
end

function Incubator:Start()
	Data:OnLoaded(function(player)
		task.delay(3, function()
			if player.Parent then
				pcall(self.Render, self, player)
			end
		end)
	end)
	-- timers tick; "ready!" once per egg
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in Data:LoadedPlayers() do
				local ok, err = pcall(self.Tick, self, player)
				if not ok then
					warn("[Incubator] tick failed: " .. tostring(err))
				end
			end
		end
	end)
end

function Incubator:Tick(player: Player)
	local data = Data:Get(player)
	if not data or not data.Incubators or #data.Incubators == 0 then
		if player:GetAttribute("EggsReady") then
			player:SetAttribute("EggsReady", nil)
		end
		return
	end
	local fresh = {}
	for _, entry in data.Incubators do
		if now() >= entry.Ready and not entry.Told then
			entry.Told = true
			table.insert(fresh, entry)
		end
	end
	if #fresh > 0 then
		-- (rebuilt so the prompt says "Hatch", translated)
		pcall(self.Render, self, player)
	else
		self:Refresh(player)
	end
	player:SetAttribute("EggsReady", self:ReadyCount(data))
	for _, entry in fresh do
		Net:Notify(player, "🥚 Your %s is ready to hatch! 🏠", Color3.fromRGB(120, 255, 160), rarityName(entry.Rarity))
		Net:Send(player, "EggReady", entry.Rarity)
	end
end

return Incubator
