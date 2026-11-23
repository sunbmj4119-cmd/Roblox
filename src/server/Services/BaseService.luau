--[[
	BaseService: every player owns a 44x44 home in the base district.

	* DECORATE: buy any decoration from the build menu and place it anywhere
	  on the grid (move / rotate / remove at any time - removing refunds
	  100%, so redecorating is free). Saved with your data, seen by everyone.
	* PEDESTALS are decorations too: your best pets stand on them and earn
	  coins every second into the base bank (green pad), even offline (50%,
	  2h). The rest of your pets wait in storage.
	* DEFEND: stun traps freeze thieves (and send a stolen shard straight
	  home), the red pad locks the entrance for a minute.
	* SHOW OFF: visitors can ❤️ like your base once a day -> weekly ranked
	  points + the "Best Bases" leaderboard.
	* STEAL: hold the prompt on someone else's pet, then run it home.

	data.Base.Items = { { Uid, Id, X, Z, R, Paid, Cur }, ... } (plot space)
	data.Pets entries get Away = true while a thief carries them
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local PetModel = require(Shared.PetModel)
local DecorModel = require(Shared.DecorModel)
local Net = require(script.Parent.Net)

local Base = {}
local Services
local Data
local World

local SETTINGS = Config.Base
local PLOT_HALF = SETTINGS.PlotSize / 2
local WALL_HEIGHT = 9
local FLOOR_Y = 0.42 -- top of the plot floor

local plots = {} -- [index] = plot record
local plotOf = {} -- [player] = plot record
local waiting = {} -- players without a plot yet (server fuller than Plots)
local touchDebounce = {} -- ["userId:what"] = os.clock()
local trapReady = {} -- [trap model] = os.clock() when it can fire again

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------
local function part(props, parent: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

local function billboard(adornee: BasePart, width: number, height: number, offsetY: number, color: Color3, maxDistance: number?): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.new(width, 0, height, 0)
	gui.StudsOffsetWorldSpace = Vector3.new(0, offsetY, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = maxDistance or 140
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.RichText = true
	label.TextColor3 = color
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = adornee
	return label
end

local function now(): number
	return workspace:GetServerTimeNow()
end

local function playerFromHit(hit: BasePart): Player?
	local model = hit:FindFirstAncestorOfClass("Model")
	return model and Players:GetPlayerFromCharacter(model)
end

local function debounced(player: Player, what: string, seconds: number): boolean
	local key = player.UserId .. ":" .. what
	local last = touchDebounce[key]
	if last and os.clock() - last < seconds then
		return true
	end
	touchDebounce[key] = os.clock()
	return false
end

local function setPrompt(parent: BasePart, action: string, object: string, role: string, hold: number, handler, distance: number?)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.HoldDuration = hold
	prompt.MaxActivationDistance = distance or 9
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	-- the client shows Owner prompts only to the owner, Thief/Visitor ones to others
	prompt:SetAttribute("Role", role)
	prompt.Parent = parent
	prompt.Triggered:Connect(function(player)
		local ok, err = pcall(handler, player)
		if not ok then
			warn("[Base] prompt failed: " .. tostring(err))
		end
	end)
	return prompt
end

local function plotColor(index: number): Color3
	return Color3.fromHSV(((index - 1) * 0.618) % 1, 0.62, 1)
end

---------------------------------------------------------------------------
-- building the plots (static shells, built once)
---------------------------------------------------------------------------
local tryLike -- forward declaration

local function buildPlot(index: number, center: Vector3, facing: Vector3): any
	-- local -Z (LookVector) faces the street
	local cf = CFrame.lookAt(center, center + facing)
	local color = plotColor(index)
	local model = Instance.new("Model")
	model.Name = "Plot_" .. index
	model:SetAttribute("OwnerId", 0)
	model:SetAttribute("LockedUntil", 0)

	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end

	part({
		Name = "Floor",
		Size = Vector3.new(PLOT_HALF * 2, 0.4, PLOT_HALF * 2),
		CFrame = at(0, 0.2, 0),
		Color = Color3.fromRGB(44, 46, 64),
		Material = Enum.Material.Slate,
	}, model)
	part({
		Name = "Trim",
		Size = Vector3.new(PLOT_HALF * 2 - 2, 0.42, PLOT_HALF * 2 - 2),
		CFrame = at(0, 0.21, 0),
		Color = color:Lerp(Color3.new(0, 0, 0), 0.6),
		Material = Enum.Material.SmoothPlastic,
	}, model)

	-- glass walls with neon top trim; the front has an entrance gap
	local function wallSegment(x: number, z: number, sizeX: number, sizeZ: number)
		part({
			Name = "Wall",
			Size = Vector3.new(sizeX, WALL_HEIGHT, sizeZ),
			CFrame = at(x, WALL_HEIGHT / 2, z),
			Color = color:Lerp(Color3.new(1, 1, 1), 0.6),
			Material = Enum.Material.Glass,
			Transparency = 0.6,
		}, model)
		part({
			Name = "WallTrim",
			Size = Vector3.new(sizeX + 0.2, 0.5, sizeZ + 0.2),
			CFrame = at(x, WALL_HEIGHT + 0.25, z),
			Color = color,
			Material = Enum.Material.Neon,
			CanCollide = false,
		}, model)
	end
	local sideLength = PLOT_HALF - 5
	wallSegment(0, PLOT_HALF, PLOT_HALF * 2, 1) -- back
	wallSegment(-PLOT_HALF, 0, 1, PLOT_HALF * 2) -- sides
	wallSegment(PLOT_HALF, 0, 1, PLOT_HALF * 2)
	wallSegment(-(5 + sideLength / 2), -PLOT_HALF, sideLength, 1) -- front, gap in the middle
	wallSegment(5 + sideLength / 2, -PLOT_HALF, sideLength, 1)

	-- lock forcefield in the entrance (only blocks while locked)
	local shield = part({
		Name = "Shield",
		Size = Vector3.new(10, WALL_HEIGHT, 0.6),
		CFrame = at(0, WALL_HEIGHT / 2, -PLOT_HALF),
		Color = Color3.fromRGB(255, 80, 90),
		Material = Enum.Material.ForceField,
		Transparency = 1,
		CanCollide = false,
	}, model)

	-- sign above the entrance
	local signAnchor = part({
		Name = "SignAnchor",
		Size = Vector3.one,
		CFrame = at(0, 15, -PLOT_HALF),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	}, model)
	local sign = billboard(signAnchor, 22, 5.5, 0, color)

	-- like post on the street side of the entrance
	local heart = part({
		Name = "LikeHeart",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 2.2,
		CFrame = at(-8, 4.4, -PLOT_HALF - 1.2),
		Color = Color3.fromRGB(255, 80, 120),
		Material = Enum.Material.Neon,
		CanCollide = false,
	}, model)
	part({
		Name = "LikePost",
		Size = Vector3.new(0.4, 3.4, 0.4),
		CFrame = at(-8, 1.7, -PLOT_HALF - 1.2),
		Color = Color3.fromRGB(240, 240, 245),
		Material = Enum.Material.Metal,
		CanCollide = false,
	}, model)
	setPrompt(heart, "❤️ Like", "Base", "Visitor", 0, function(visitor)
		tryLike(visitor, index)
	end, 12)

	-- pads: collect (green) and lock (red), just inside the entrance
	local collect = part({
		Name = "CollectPad",
		Size = Vector3.new(7, 0.4, 7),
		CFrame = at(-14, 0.45, -PLOT_HALF + 5),
		Color = Color3.fromRGB(70, 255, 130),
		Material = Enum.Material.Neon,
		CanCollide = false,
	}, model)
	local bankLabel = billboard(collect, 9, 3, 3.5, Color3.fromRGB(140, 255, 170), 70)
	local lockPad = part({
		Name = "LockPad",
		Size = Vector3.new(7, 0.4, 7),
		CFrame = at(14, 0.45, -PLOT_HALF + 5),
		Color = Color3.fromRGB(255, 80, 90),
		Material = Enum.Material.Neon,
		CanCollide = false,
	}, model)
	local lockLabel = billboard(lockPad, 9, 2.4, 3.2, Color3.fromRGB(255, 150, 150), 50)

	model.Parent = World:Folder("Bases")
	local items = Instance.new("Folder")
	items.Name = "Items"
	items.Parent = model
	local displays = Instance.new("Folder")
	displays.Name = "Displays"
	displays.Parent = model

	return {
		Index = index,
		Model = model,
		CFrame = cf,
		Color = color,
		Owner = nil,
		Sign = sign,
		BankLabel = bankLabel,
		LockLabel = lockLabel,
		Shield = shield,
		CollectPad = collect,
		LockPad = lockPad,
		Items = items,
		Displays = displays,
		ItemModels = {}, -- [uid] = Model
		LockedUntil = 0,
		LockReadyAt = 0,
		LastLabel = "",
	}
end

-- plots line both sides of every street, nearest rows first
local function plotLayout(): { { Center: Vector3, Facing: Vector3 } }
	local bases = Config.World.Bases
	local layout = {}
	local row = 0
	local offset = 10 + 2 + PLOT_HALF -- half street + walkway + half plot
	while #layout < SETTINGS.Plots do
		local z = bases.ZStart - 18 - PLOT_HALF - row * (SETTINGS.PlotSize + 4)
		for _, streetX in SETTINGS.Streets do
			for _, side in { -1, 1 } do
				if #layout < SETTINGS.Plots then
					table.insert(layout, {
						Center = Vector3.new(streetX + side * offset, 0, z),
						Facing = Vector3.new(-side, 0, 0), -- toward the street
					})
				end
			end
		end
		row += 1
	end
	return layout
end
Base.PlotLayout = plotLayout

---------------------------------------------------------------------------
-- shards: best ones go on the pedestals, the rest wait in storage
---------------------------------------------------------------------------
local function pedestalItems(data)
	local list = {}
	for _, item in data.Base.Items do
		local def = Config.Decor[item.Id]
		if def and def.Function == "Pedestal" then
			table.insert(list, item)
		end
	end
	table.sort(list, function(a, b)
		return a.Uid < b.Uid
	end)
	return list
end

-- the pets standing on pedestals: the best earners (not being stolen)
local function displayedPets(data)
	local slots = #pedestalItems(data)
	local list = {}
	for _, pet in data.Pets do
		if not pet.Away and Config.Pets[pet.Name] then
			table.insert(list, pet)
		end
	end
	table.sort(list, function(a, b)
		local ia = Util.PetIncome(Config, a.Name, a.Variant)
		local ib = Util.PetIncome(Config, b.Name, b.Variant)
		if ia == ib then
			return a.Id < b.Id
		end
		return ia > ib
	end)
	local shown = {}
	for i = 1, math.min(slots, #list) do
		shown[i] = list[i]
	end
	return shown
end
Base.DisplayedPets = displayedPets

-- coins per second of one pet for its owner (boosts included)
function Base:PetRate(player: Player, data, pet): number
	local rate = Util.PetIncome(Config, pet.Name, pet.Variant) * Services.StatsService:CoinMultiplier(player, data)
	if Services.MonetizationService:HasPass(player, "DoubleBase") then
		rate *= 2
	end
	return rate
end

function Base:IncomeRate(player: Player, data): number
	local total = 0
	for _, pet in displayedPets(data) do
		total += self:PetRate(player, data, pet)
	end
	return total
end

---------------------------------------------------------------------------
-- rendering
---------------------------------------------------------------------------
local function itemCFrame(plot, item): CFrame
	return plot.CFrame * CFrame.new(item.X, FLOOR_Y + 0.1, item.Z) * CFrame.Angles(0, (item.R or 0) * math.pi / 2, 0)
end

local onTrap, onJump -- forward declarations

local function renderItem(plot, item)
	local existing = plot.ItemModels[item.Uid]
	if existing then
		existing:Destroy()
	end
	local model = DecorModel.Build(Config, item.Id)
	model:PivotTo(itemCFrame(plot, item))
	model:SetAttribute("Uid", item.Uid)
	model:SetAttribute("DecorId", item.Id)
	model.Parent = plot.Items
	plot.ItemModels[item.Uid] = model
	local def = Config.Decor[item.Id]
	local trigger = model:FindFirstChild("Trigger")
	if trigger and trigger:IsA("BasePart") and def then
		trigger.Touched:Connect(function(hit)
			local player = playerFromHit(hit)
			if not player then
				return
			end
			if def.Function == "Trap" then
				onTrap(plot, model, player)
			elseif def.Function == "Jump" then
				onJump(player, model)
			end
		end)
	end
end

function Base:RenderDisplays(player: Player)
	local plot = plotOf[player]
	local data = Data:Get(player)
	if not plot or not data then
		return
	end
	plot.Displays:ClearAllChildren()
	local shown = displayedPets(data)
	for slot, pedestal in pedestalItems(data) do
		local model = plot.ItemModels[pedestal.Uid]
		local top = model and model:FindFirstChild("Top")
		local pet = shown[slot]
		if top and top:IsA("BasePart") and pet then
			local info = Config.Pets[pet.Name]
			local rarity = Config.Rarities[info.Rarity] or Config.Rarities.Common
			local display = PetModel.Build(pet.Name, pet.Variant)
			display.Name = "Pet_" .. pet.Id
			display:PivotTo(CFrame.new(top.Position + Vector3.new(0, 1.6, 0)) * (top.CFrame - top.Position))
			display:SetAttribute("Spin", true)
			display:SetAttribute("PetId", pet.Id)
			display.Parent = plot.Displays
			local anchor = display.PrimaryPart :: BasePart
			local label = billboard(anchor, 8, 2.4, 3.4, rarity.Color, 60)
			local rate = Util.Format(self:PetRate(player, data, pet))
			if pet.Variant then
				World.SetText(label, "%s %s\n💰 %s/s", pet.Variant, pet.Name, rate)
			else
				World.SetText(label, "%s\n💰 %s/s", pet.Name, rate)
			end
			local petId = pet.Id
			setPrompt(anchor, "Steal", pet.Name, "Thief", SETTINGS.StealHold, function(thief)
				Base:TrySteal(thief, player, petId)
			end)
			setPrompt(anchor, "Sell", pet.Name, "Owner", 0.6, function(who)
				if who == player then
					Base:SellPet(player, petId)
				end
			end)
		end
	end
	self:RefreshLabels(player, true)
end

function Base:Render(player: Player)
	local plot = plotOf[player]
	local data = Data:Get(player)
	if not plot or not data then
		return
	end
	for _, model in plot.ItemModels do
		model:Destroy()
	end
	plot.ItemModels = {}
	for _, item in data.Base.Items do
		if Config.Decor[item.Id] then
			renderItem(plot, item)
		end
	end
	self:RenderDisplays(player)
end

function Base:RefreshLabels(player: Player, force: boolean?)
	local plot = plotOf[player]
	local data = Data:Get(player)
	if not plot or not data then
		return
	end
	local rate = self:IncomeRate(player, data)
	local stored = math.max(0, #data.Pets - #displayedPets(data))
	local signText = Util.Format(rate) .. "|" .. data.Base.Likes .. "|" .. stored
	if force or signText ~= plot.LastLabel then
		plot.LastLabel = signText
		if stored > 0 then
			World.SetText(
				plot.Sign,
				"🏠 %s's BASE\n💰 %s/s  ❤️ %s  📦 %s",
				player.DisplayName,
				Util.Format(rate),
				tostring(data.Base.Likes),
				tostring(stored)
			)
		else
			World.SetText(
				plot.Sign,
				"🏠 %s's BASE\n💰 %s/s  ❤️ %s",
				player.DisplayName,
				Util.Format(rate),
				tostring(data.Base.Likes)
			)
		end
	end
	World.SetText(plot.BankLabel, "💰 %s\nSTEP TO COLLECT", Util.Format(math.floor(data.Base.Bank)))
	local t = now()
	if plot.LockedUntil > t then
		World.SetText(plot.LockLabel, "🔒 LOCKED %ds", math.ceil(plot.LockedUntil - t))
	elseif plot.LockReadyAt > t then
		World.SetText(plot.LockLabel, "⏳ %ds", math.ceil(plot.LockReadyAt - t))
	else
		World.SetText(plot.LockLabel, "🔒 LOCK BASE")
	end
	player:SetAttribute("BaseRate", rate)
	player:SetAttribute("BaseBank", math.floor(data.Base.Bank))
	player:SetAttribute("BaseStored", stored)
end

local function clearPlot(plot)
	plot.Owner = nil
	for _, model in plot.ItemModels do
		model:Destroy()
	end
	plot.ItemModels = {}
	plot.Displays:ClearAllChildren()
	plot.Model:SetAttribute("OwnerId", 0)
	plot.Model:SetAttribute("LockedUntil", 0)
	plot.LockedUntil = 0
	plot.LockReadyAt = 0
	plot.Shield.Transparency = 1
	plot.Shield.CanCollide = false
	plot.LastLabel = ""
	World.SetText(plot.Sign, "🏠 FREE BASE")
	World.SetText(plot.BankLabel, "")
	World.SetText(plot.LockLabel, "")
end

---------------------------------------------------------------------------
-- public API (used by ShardService / MiningService / UI)
---------------------------------------------------------------------------
function Base:PlotOf(player: Player)
	return plotOf[player]
end

function Base:HasBase(player: Player): boolean
	return plotOf[player] ~= nil
end

-- is this position inside the player's own plot?
function Base:InOwnPlot(player: Player, position: Vector3): boolean
	local plot = plotOf[player]
	if not plot then
		return false
	end
	local localPos = plot.CFrame:PointToObjectSpace(position)
	return math.abs(localPos.X) <= PLOT_HALF and math.abs(localPos.Z) <= PLOT_HALF + 1
end

function Base:HomeCFrame(player: Player): CFrame?
	local plot = plotOf[player]
	return plot and (plot.CFrame * CFrame.new(0, 3, -PLOT_HALF + 5))
end

function Base:IsLocked(owner: Player): boolean
	local plot = plotOf[owner]
	return plot ~= nil and plot.LockedUntil > now()
end

-- a pet is being carried away by a thief (or came back)
function Base:SetAway(owner: Player, petId: number, away: boolean)
	local data = Data:Get(owner)
	local pet = data and Services.PetService.FindPet(data, petId)
	if not pet then
		return
	end
	pet.Away = if away then true else nil
	if owner.Parent then
		Services.PetService:Changed(owner)
	end
end

function Base:SellPet(player: Player, petId: number)
	local data = Data:Get(player)
	local pet, index = nil, nil
	if data then
		pet, index = Services.PetService.FindPet(data, petId)
	end
	if not pet or pet.Away then
		return
	end
	local coins = Services.PetService:SellValue(pet.Name, pet.Variant)
	table.remove(data.Pets, index)
	data.Coins += coins
	data.Stats.LifetimeCoins += coins
	Net:Notify(player, "Sold %s for 💰%s", Color3.fromRGB(255, 220, 120), pet.Name, Util.Format(coins))
	Services.PetService:Changed(player)
end

function Base:TrySteal(thief: Player, owner: Player, petId: number)
	if thief == owner or not owner.Parent then
		return
	end
	local shards = Services.ShardService
	if shards:IsCarrying(thief) then
		Net:Notify(thief, "Your hands are full!")
		return
	end
	if not plotOf[thief] then
		Net:Notify(thief, "You need a base to steal pets!")
		return
	end
	if self:IsLocked(owner) then
		Net:Notify(thief, "🔒 This base is locked!")
		return
	end
	local data = Data:Get(owner)
	local pet = data and Services.PetService.FindPet(data, petId)
	if not pet or pet.Away then
		return
	end
	self:SetAway(owner, petId, true)
	local item = { Kind = "Pet", Name = pet.Name, Variant = pet.Variant }
	if not shards:StartCarry(thief, item, { From = owner, PetId = petId }) then
		self:SetAway(owner, petId, false)
		return
	end
	local display = pet.Name
	Net:Send(owner, "BaseAlarm", thief.DisplayName, display)
	Net:Notify(owner, "🚨 %s is stealing your %s! Bonk them!", Color3.fromRGB(255, 80, 80), thief.DisplayName, display)
	Net:Notify(thief, "🏃 You stole a %s! Run to your base!", Color3.fromRGB(255, 170, 80), display)
end

function Base:Collect(player: Player)
	local data = Data:Get(player)
	if not data then
		return
	end
	local amount = math.floor(data.Base.Bank)
	if amount <= 0 then
		return
	end
	data.Base.Bank -= amount
	data.Coins += amount
	data.Stats.LifetimeCoins += amount
	Services.ProgressionService:AddQuest(player, "Collect", 1)
	Services.Analytics:Economy(player, "Source", "Coins", amount, data.Coins, "Gameplay", "BaseCollect")
	Net:Send(player, "BaseCollected", amount)
	Data:MarkDirty(player)
	self:RefreshLabels(player)
end

function Base:Lock(player: Player)
	local plot = plotOf[player]
	if not plot then
		return
	end
	local t = now()
	if plot.LockedUntil > t or plot.LockReadyAt > t then
		return
	end
	plot.LockedUntil = t + SETTINGS.LockSeconds
	plot.LockReadyAt = plot.LockedUntil + SETTINGS.LockCooldown
	plot.Model:SetAttribute("LockedUntil", plot.LockedUntil)
	plot.Shield.Transparency = 0.3
	plot.Shield.CanCollide = true -- the owner's client turns this off locally
	Net:Notify(player, "🔒 Base locked for %ds!", Color3.fromRGB(255, 150, 150), SETTINGS.LockSeconds)
	self:RefreshLabels(player)
end

---------------------------------------------------------------------------
-- decorating
---------------------------------------------------------------------------
local function findItem(data, uid)
	for index, item in data.Base.Items do
		if item.Uid == uid then
			return item, index
		end
	end
	return nil, nil
end

local function cleanTransform(x, z, r): (number?, number?, number?)
	if type(x) ~= "number" or type(z) ~= "number" or type(r) ~= "number" then
		return nil, nil, nil
	end
	if x ~= x or z ~= z then -- NaN
		return nil, nil, nil
	end
	return x, z, math.floor(r) % 4
end

-- returns ok, message
function Base:Place(player: Player, id, x, z, r): (boolean, string?)
	local data = Data:Get(player)
	local plot = plotOf[player]
	local def = type(id) == "string" and Config.Decor[id]
	x, z, r = cleanTransform(x, z, r)
	if not data or not plot or not def or not x then
		return false, "Can't place that here"
	end
	x, z = DecorModel.Snap(Config, id, x, z, r)
	local items = data.Base.Items
	local ok, reason = DecorModel.Validate(Config, items, id, x, z, r, nil)
	if not ok then
		return false, reason
	end
	local currency, price = DecorModel.Price(Config, id, items)
	local have = if currency == "Gems" then data.Gems else data.Coins
	if have < price then
		return false, if currency == "Gems" then "Not enough gems!" else "Not enough coins!"
	end
	if currency == "Gems" then
		data.Gems -= price
	else
		data.Coins -= price
	end
	local item = { Uid = data.Base.NextUid, Id = id, X = x, Z = z, R = r, Paid = price, Cur = currency }
	data.Base.NextUid += 1
	table.insert(items, item)
	renderItem(plot, item)
	if def.Function == "Pedestal" then
		self:RenderDisplays(player)
	end
	Services.ProgressionService:AddQuest(player, "Decorate", 1)
	Data:MarkDirty(player)
	return true, nil
end

function Base:Move(player: Player, uid, x, z, r): (boolean, string?)
	local data = Data:Get(player)
	local plot = plotOf[player]
	local item = data and type(uid) == "number" and findItem(data, uid)
	x, z, r = cleanTransform(x, z, r)
	if not item or not plot or not x then
		return false, "Can't move that"
	end
	x, z = DecorModel.Snap(Config, item.Id, x, z, r)
	local ok, reason = DecorModel.Validate(Config, data.Base.Items, item.Id, x, z, r, item.Uid)
	if not ok then
		return false, reason
	end
	item.X, item.Z, item.R = x, z, r
	renderItem(plot, item)
	if Config.Decor[item.Id].Function == "Pedestal" then
		self:RenderDisplays(player)
	end
	Data:MarkDirty(player)
	return true, nil
end

function Base:Remove(player: Player, uid): (boolean, string?)
	local data = Data:Get(player)
	local plot = plotOf[player]
	local item, index = nil, nil
	if data and type(uid) == "number" then
		item, index = findItem(data, uid)
	end
	if not item or not plot then
		return false, "Can't remove that"
	end
	local def = Config.Decor[item.Id]
	if def and def.Function == "Pedestal" and #pedestalItems(data) <= 1 then
		return false, "Keep at least one pedestal!"
	end
	table.remove(data.Base.Items, index)
	local refund = math.max(0, math.floor(item.Paid or 0))
	if item.Cur == "Gems" then
		data.Gems += refund
	else
		data.Coins += refund
	end
	local model = plot.ItemModels[item.Uid]
	plot.ItemModels[item.Uid] = nil
	if model then
		model:Destroy()
	end
	if def and def.Function == "Pedestal" then
		self:RenderDisplays(player)
	end
	Data:MarkDirty(player)
	return true, nil
end

-- traps: freeze intruders; a stolen shard from this base goes straight home
onTrap = function(plot, model: Model, player: Player)
	local owner = plot.Owner
	if not owner or owner == player then
		return
	end
	local ready = trapReady[model] or 0
	if os.clock() < ready then
		return
	end
	trapReady[model] = os.clock() + SETTINGS.TrapCooldown
	model.AncestryChanged:Once(function()
		trapReady[model] = nil
	end)
	Services.CharacterService:Stun(player, SETTINGS.TrapStun)
	local recovered = Services.ShardService:Confiscate(player, owner)
	Net:Send(player, "Stunned", SETTINGS.TrapStun)
	Net:Notify(player, "⚡ You stepped on a trap!", Color3.fromRGB(255, 230, 80))
	if recovered then
		Net:Notify(owner, "⚡ Your trap caught %s - shard saved!", Color3.fromRGB(255, 230, 80), player.DisplayName)
	else
		Net:Notify(owner, "⚡ Your trap stunned %s!", Color3.fromRGB(255, 230, 80), player.DisplayName)
	end
end

onJump = function(player: Player, model: Model)
	if debounced(player, "jump", 0.8) then
		return
	end
	local look = model:GetPivot().LookVector * Vector3.new(1, 0, 1)
	Net:Send(player, "Launch", Vector3.new(0, 95, 0) + look * 25)
end

---------------------------------------------------------------------------
-- likes
---------------------------------------------------------------------------
tryLike = function(visitor: Player, plotIndex: number)
	local plot = plots[plotIndex]
	local owner = plot and plot.Owner
	if not owner or owner == visitor then
		return
	end
	local data = Data:Get(owner)
	if not data then
		return
	end
	local base = data.Base
	local key = tostring(visitor.UserId)
	local today = Util.DayNumber()
	if base.LikedBy[key] == today then
		Net:Notify(visitor, "You already liked this base today ❤️")
		return
	end
	base.LikedBy[key] = today
	base.Likes += 1
	local week = Util.WeekNumber()
	if base.LikeWeek ~= week then
		base.LikeWeek = week
		base.WeeklyLikes = 0
	end
	base.WeeklyLikes += 1
	Services.ProgressionService:AddPoints(owner, SETTINGS.LikePoints)
	Services.ProgressionService:AddQuest(visitor, "Like", 1)
	Net:Notify(owner, "❤️ %s liked your base!", Color3.fromRGB(255, 120, 160), visitor.DisplayName)
	Net:Notify(visitor, "❤️ You liked %s's base!", Color3.fromRGB(255, 120, 160), owner.DisplayName)
	Net:Send(owner, "BaseLiked", visitor.DisplayName)
	Data:MarkDirty(owner)
	Base:RefreshLabels(owner, true)
end

---------------------------------------------------------------------------
-- plot assignment
---------------------------------------------------------------------------
-- first visit (or a save from before decorating existed): starter layout
local function seed(data)
	local base = data.Base
	if base.Seeded then
		return
	end
	base.Seeded = true
	local function add(id, x, z, r)
		x, z = DecorModel.Snap(Config, id, x, z, r)
		if DecorModel.Validate(Config, base.Items, id, x, z, r, nil) then
			table.insert(base.Items, { Uid = base.NextUid, Id = id, X = x, Z = z, R = r, Paid = 0, Cur = "Coins" })
			base.NextUid += 1
		end
	end
	for _, entry in Config.StarterBase do
		add(entry.Id, entry.X, entry.Z, entry.R)
	end
	-- pedestals bought before decorating existed are kept
	local extra = math.max(0, (base.Pedestals or 0) - SETTINGS.StartPedestals)
	for i = 1, extra do
		add("Pedestal", -12 + ((i - 1) % 5) * 6, 9 + math.floor((i - 1) / 5) * 6, 0)
	end
end

local function assign(player: Player, data)
	if plotOf[player] then
		return
	end
	local plot = nil
	for _, candidate in plots do
		if not candidate.Owner then
			plot = candidate
			break
		end
	end
	if not plot then
		if not table.find(waiting, player) then
			table.insert(waiting, player)
		end
		Net:Notify(player, "All bases are taken - you'll get one when someone leaves.")
		return
	end
	plot.Owner = player
	plotOf[player] = plot
	plot.Model:SetAttribute("OwnerId", player.UserId)
	player:SetAttribute("BaseIndex", plot.Index)

	-- offline earnings (lower rate, capped)
	local base = data.Base
	if base.LastOnline > 0 then
		local away = math.clamp(os.time() - base.LastOnline, 0, SETTINGS.OfflineMaxSeconds)
		local earned = math.floor(Base:IncomeRate(player, data) * away * SETTINGS.OfflineRate)
		if earned > 0 and away >= 60 then
			base.Bank += earned
			task.delay(6, function()
				if player.Parent then
					Net:Send(player, "OfflineEarnings", earned, away)
				end
			end)
		end
	end
	base.LastOnline = os.time()
	Base:Render(player)
end

local function release(player: Player)
	local plot = plotOf[player]
	plotOf[player] = nil
	local index = table.find(waiting, player)
	if index then
		table.remove(waiting, index)
	end
	if not plot then
		return
	end
	clearPlot(plot)
	-- give the plot to someone who's waiting
	while #waiting > 0 do
		local nextPlayer = table.remove(waiting, 1)
		local data = nextPlayer.Parent and Data:Get(nextPlayer)
		if data then
			assign(nextPlayer, data)
			break
		end
	end
end

---------------------------------------------------------------------------
function Base:Init(services)
	Services = services
	Data = services.DataService
	World = services.WorldService
end

function Base:Start()
	for index, spot in plotLayout() do
		local plot = buildPlot(index, spot.Center, spot.Facing)
		plots[index] = plot
		clearPlot(plot)
		plot.CollectPad.Touched:Connect(function(hit)
			local player = playerFromHit(hit)
			if player and plot.Owner == player and not debounced(player, "collect", 0.6) then
				Base:Collect(player)
			end
		end)
		plot.LockPad.Touched:Connect(function(hit)
			local player = playerFromHit(hit)
			if player and plot.Owner == player and not debounced(player, "lock", 0.6) then
				Base:Lock(player)
			end
		end)
	end

	Data:OnLoaded(function(player, data)
		local base = data.Base
		-- forget likes older than yesterday (keeps the save small)
		local today = Util.DayNumber()
		for key, day in base.LikedBy do
			if type(day) ~= "number" or day < today - 1 then
				base.LikedBy[key] = nil
			end
		end
		seed(data)
		assign(player, data)
	end)
	Data:OnLeaving(function(_player, data)
		data.Base.LastOnline = os.time()
		for _, pet in data.Pets do
			pet.Away = nil
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		release(player)
		for key in touchDebounce do
			if string.sub(key, 1, #tostring(player.UserId) + 1) == player.UserId .. ":" then
				touchDebounce[key] = nil
			end
		end
	end)

	-- income tick
	task.spawn(function()
		while true do
			task.wait(1)
			for player, plot in plotOf do
				local data = Data:Get(player)
				if data and player.Parent then
					data.Base.Bank += self:IncomeRate(player, data)
					data.Base.LastOnline = os.time()
					local ok, err = pcall(self.RefreshLabels, self, player)
					if not ok then
						warn("[Base] label refresh failed: " .. tostring(err))
					end
					if plot.LockedUntil > 0 and plot.LockedUntil <= now() then
						plot.LockedUntil = 0
						plot.Model:SetAttribute("LockedUntil", 0)
						plot.Shield.Transparency = 1
						plot.Shield.CanCollide = false
					end
				end
			end
		end
	end)

	Net:On("GoBase", 1, function(player)
		if Services.ShardService:IsCarrying(player) then
			Net:Notify(player, "Run! You can't teleport while carrying a shard.")
			return
		end
		local home = self:HomeCFrame(player)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart
		if home and root then
			character:PivotTo(home)
		end
	end)

	-- build mode requests answer with ok, translated message
	local function reply(player: Player, ok: boolean, message: string?)
		return ok, if message then Net:L(player, message) else nil
	end
	Net:OnRequest("BasePlace", 0.15, function(player, id, x, z, r)
		return reply(player, self:Place(player, id, x, z, r))
	end)
	Net:OnRequest("BaseMove", 0.15, function(player, uid, x, z, r)
		return reply(player, self:Move(player, uid, x, z, r))
	end)
	Net:OnRequest("BaseRemove", 0.15, function(player, uid)
		return reply(player, self:Remove(player, uid))
	end)
end

return Base
