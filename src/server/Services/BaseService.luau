--[[
	BaseService: every player gets a plot in the base district (south of the
	hub). Star shards placed on its pedestals earn coins every second into
	the base bank (collect it on the green pad), even while offline (50%, 2h).

	Other players can sneak in and STEAL a shard (hold the prompt), then must
	carry it to their own base; the owner gets an alarm and can bonk the thief
	to make them drop it (a dropped stolen shard flies home after a few
	seconds). The red pad locks the base for a minute (with a cooldown).

	Shard entries live in data.Base.Shards as { Id = rarityId }; an entry
	being carried away by a thief is marked Away = true until delivered.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local ShardModel = require(Shared.ShardModel)
local Net = require(script.Parent.Net)

local Base = {}
local Services
local Data
local World

local SETTINGS = Config.Base
local PLOT_HALF = 16
local WALL_HEIGHT = 9

-- every plot gets its own color (spread around the color wheel)
local function plotColor(index: number): Color3
	return Color3.fromHSV(((index - 1) * 0.618) % 1, 0.62, 1)
end

-- pedestal slots in plot space (front row first; -Z is the entrance side)
local PEDESTAL_SPOTS = {}
for _, z in { -1, 5.5, 12 } do
	for _, x in { -10.5, -3.5, 3.5, 10.5 } do
		table.insert(PEDESTAL_SPOTS, Vector3.new(x, 0, z))
	end
end

local plots = {} -- [index] = plot record
local plotOf = {} -- [player] = plot record
local waiting = {} -- players without a plot yet (server fuller than Plots)
local touchDebounce = {} -- [player] = os.clock()

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

local function debounced(player: Player, seconds: number): boolean
	local last = touchDebounce[player]
	if last and os.clock() - last < seconds then
		return true
	end
	touchDebounce[player] = os.clock()
	return false
end

---------------------------------------------------------------------------
-- building the plots (static shells, built once)
---------------------------------------------------------------------------
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
		Color = color:Lerp(Color3.new(0, 0, 0), 0.55),
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
			Transparency = 0.55,
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
	wallSegment(0, PLOT_HALF, PLOT_HALF * 2, 1) -- back
	wallSegment(-PLOT_HALF, 0, 1, PLOT_HALF * 2) -- sides
	wallSegment(PLOT_HALF, 0, 1, PLOT_HALF * 2)
	wallSegment(-10.5, -PLOT_HALF, 11, 1) -- front, gap in the middle
	wallSegment(10.5, -PLOT_HALF, 11, 1)

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
	local sign = billboard(signAnchor, 20, 5, 0, color)

	-- pads: collect (green) and lock (red), just inside the entrance
	local collect = part({
		Name = "CollectPad",
		Size = Vector3.new(7, 0.4, 7),
		CFrame = at(-9, 0.45, -9.5),
		Color = Color3.fromRGB(70, 255, 130),
		Material = Enum.Material.Neon,
		CanCollide = false,
	}, model)
	local bankLabel = billboard(collect, 9, 3, 3.5, Color3.fromRGB(140, 255, 170), 70)
	local lockPad = part({
		Name = "LockPad",
		Size = Vector3.new(7, 0.4, 7),
		CFrame = at(9, 0.45, -9.5),
		Color = Color3.fromRGB(255, 80, 90),
		Material = Enum.Material.Neon,
		CanCollide = false,
	}, model)
	local lockLabel = billboard(lockPad, 9, 2.4, 3.2, Color3.fromRGB(255, 150, 150), 50)

	local pedestals = {}
	for slot, spot in PEDESTAL_SPOTS do
		local pedestal = part({
			Name = "Pedestal_" .. slot,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(2.4, 4, 4),
			CFrame = at(spot.X, 1.2 + 0.4, spot.Z) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(230, 230, 240),
			Material = Enum.Material.Marble,
		}, model)
		local ring = part({
			Name = "Ring",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3, 4.3, 4.3),
			CFrame = at(spot.X, 2.85, spot.Z) * CFrame.Angles(0, 0, math.rad(90)),
			Color = color,
			Material = Enum.Material.Neon,
			CanCollide = false,
		}, model)
		pedestals[slot] = { Part = pedestal, Ring = ring, Top = at(spot.X, 3, spot.Z).Position }
	end

	model.Parent = World:Folder("Bases")
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
		Pedestals = pedestals,
		Displays = displays,
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
	while #layout < SETTINGS.Plots do
		local z = bases.ZStart - 32 - row * (PLOT_HALF * 2 + 4)
		for _, streetX in SETTINGS.Streets do
			for _, side in { -1, 1 } do
				if #layout < SETTINGS.Plots then
					table.insert(layout, {
						Center = Vector3.new(streetX + side * 30, 0, z),
						Facing = Vector3.new(-side, 0, 0), -- toward the street
					})
				end
			end
		end
		row += 1
	end
	return layout
end

---------------------------------------------------------------------------
-- income
---------------------------------------------------------------------------
function Base:ShardRate(player: Player, data, id: string): number
	local rate = Util.ShardIncome(Config, id, data.ZoneLevel) * Services.StatsService:CoinMultiplier(player, data)
	if Services.MonetizationService:HasPass(player, "DoubleBase") then
		rate *= 2
	end
	return rate
end

function Base:IncomeRate(player: Player, data): number
	local total = 0
	for _, entry in data.Base.Shards do
		if not entry.Away then
			total += self:ShardRate(player, data, entry.Id)
		end
	end
	return total
end

local function sellValue(player: Player, data, id: string): number
	return math.floor(Base:ShardRate(player, data, id) * Config.Shards.SellSeconds)
end

---------------------------------------------------------------------------
-- rendering a plot for its owner
---------------------------------------------------------------------------
local function setPrompt(parent: BasePart, action: string, object: string, role: string, hold: number, handler)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.HoldDuration = hold
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt:SetAttribute("Role", role) -- client shows Owner prompts only to the owner
	prompt.Parent = parent
	prompt.Triggered:Connect(function(player)
		local ok, err = pcall(handler, player)
		if not ok then
			warn("[Base] prompt failed: " .. tostring(err))
		end
	end)
	return prompt
end

function Base:Render(player: Player)
	local plot = plotOf[player]
	local data = Data:Get(player)
	if not plot or not data then
		return
	end
	plot.Displays:ClearAllChildren()
	local shards = data.Base.Shards
	for slot, pedestal in plot.Pedestals do
		local owned = slot <= data.Base.Pedestals
		pedestal.Part.Transparency = if owned then 0 else 0.7
		pedestal.Ring.Transparency = if owned then 0 else 0.85
		local entry = shards[slot]
		if entry and not Config.Shards.Rarities[entry.Id] then
			entry.Id = "Common" -- a rarity that no longer exists (config change)
		end
		if owned and entry and not entry.Away then
			local def = Config.Shards.Rarities[entry.Id]
			local model = ShardModel.Build(Config, entry.Id, 1)
			ShardModel.SetAnchored(model, true)
			model:PivotTo(CFrame.new(pedestal.Top + Vector3.new(0, 2.2, 0)))
			model:SetAttribute("Spin", true)
			model.Parent = plot.Displays
			local label = billboard(model.PrimaryPart :: BasePart, 7, 2.2, 3.2, def.Color, 60)
			World.SetText(label, "%s\n💰 %s/s", def.Name, Util.Format(self:ShardRate(player, data, entry.Id)))
			local core = model.PrimaryPart :: BasePart
			setPrompt(core, "Steal", def.Name, "Thief", SETTINGS.StealHold, function(thief)
				Base:TrySteal(thief, player, entry)
			end)
			setPrompt(core, "Sell", def.Name, "Owner", 0.6, function(who)
				if who == player then
					Base:SellEntry(player, entry)
				end
			end)
		elseif owned and entry and entry.Away then
			local anchor = part({
				Name = "StolenMark",
				Size = Vector3.one,
				CFrame = CFrame.new(pedestal.Top + Vector3.new(0, 2, 0)),
				Transparency = 1,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
			}, plot.Displays)
			World.SetText(billboard(anchor, 7, 2, 0, Color3.fromRGB(255, 90, 90), 80), "⚠️ STOLEN!")
		elseif slot == data.Base.Pedestals + 1 and slot <= SETTINGS.MaxPedestals then
			-- the next pedestal can be bought
			local cost = SETTINGS.PedestalCosts[slot] or math.huge
			local anchor = part({
				Name = "BuyMark",
				Size = Vector3.one,
				CFrame = CFrame.new(pedestal.Top + Vector3.new(0, 1, 0)),
				Transparency = 1,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
			}, plot.Displays)
			World.SetText(billboard(anchor, 6, 2, 0, Color3.fromRGB(255, 230, 140), 45), "🔒 💰 %s", Util.Format(cost))
			setPrompt(anchor, "Buy pedestal", "💰 " .. Util.Format(cost), "Owner", 0, function(who)
				if who == player then
					Base:BuyPedestal(player)
				end
			end)
		end
	end
	self:RefreshLabels(player, true)
end

function Base:RefreshLabels(player: Player, force: boolean?)
	local plot = plotOf[player]
	local data = Data:Get(player)
	if not plot or not data then
		return
	end
	local rate = self:IncomeRate(player, data)
	local signText = Util.Format(rate)
	if force or signText ~= plot.LastLabel then
		plot.LastLabel = signText
		World.SetText(plot.Sign, "🏠 %s's BASE\n💰 %s/s", player.DisplayName, signText)
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
end

local function clearPlot(plot)
	plot.Owner = nil
	plot.Displays:ClearAllChildren()
	plot.Model:SetAttribute("OwnerId", 0)
	plot.Model:SetAttribute("LockedUntil", 0)
	plot.LockedUntil = 0
	plot.LockReadyAt = 0
	plot.Shield.Transparency = 1
	plot.Shield.CanCollide = false
	for _, pedestal in plot.Pedestals do
		pedestal.Part.Transparency = 0.7
		pedestal.Ring.Transparency = 0.85
	end
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
	return plot and (plot.CFrame * CFrame.new(0, 3, -PLOT_HALF + 4))
end

function Base:IsLocked(owner: Player): boolean
	local plot = plotOf[owner]
	return plot ~= nil and plot.LockedUntil > now()
end

-- a carried shard arrives home. Returns a short result for the client.
function Base:AddShard(player: Player, id: string): (string, number)
	local data = Data:Get(player)
	if not data then
		return "None", 0
	end
	local shards = data.Base.Shards
	local result, coins = "Placed", 0
	if #shards < data.Base.Pedestals then
		table.insert(shards, { Id = id })
	else
		-- base full: the new shard replaces the weakest one if it's better, the other is sold
		local worstIndex, worstValue = nil, math.huge
		for i, entry in shards do
			if not entry.Away then
				local value = Util.ShardIndex(Config, entry.Id)
				if value < worstValue then
					worstIndex, worstValue = i, value
				end
			end
		end
		if worstIndex and Util.ShardIndex(Config, id) > worstValue then
			coins = sellValue(player, data, shards[worstIndex].Id)
			shards[worstIndex] = { Id = id }
			result = "Replaced"
		else
			coins = sellValue(player, data, id)
			result = "Sold"
		end
		data.Coins += coins
		data.Stats.LifetimeCoins += coins
	end
	data.Stats.ShardsDelivered = (data.Stats.ShardsDelivered or 0) + 1
	Data:MarkDirty(player)
	self:Render(player)
	return result, coins
end

function Base:SetAway(owner: Player, entry, away: boolean)
	entry.Away = if away then true else nil
	if owner.Parent then
		Data:MarkDirty(owner)
		self:Render(owner)
	end
end

function Base:RemoveEntry(owner: Player, entry)
	local data = Data:Get(owner)
	if not data then
		return
	end
	local index = table.find(data.Base.Shards, entry)
	if index then
		table.remove(data.Base.Shards, index)
	end
	Data:MarkDirty(owner)
	self:Render(owner)
end

function Base:SellEntry(player: Player, entry)
	local data = Data:Get(player)
	if not data or entry.Away then
		return
	end
	local index = table.find(data.Base.Shards, entry)
	if not index then
		return
	end
	local coins = sellValue(player, data, entry.Id)
	table.remove(data.Base.Shards, index)
	data.Coins += coins
	data.Stats.LifetimeCoins += coins
	local def = Config.Shards.Rarities[entry.Id]
	Net:Notify(player, "Sold %s for 💰%s", Color3.fromRGB(255, 220, 120), def.Name, Util.Format(coins))
	Data:MarkDirty(player)
	self:Render(player)
end

function Base:BuyPedestal(player: Player)
	local data = Data:Get(player)
	if not data then
		return
	end
	local nextSlot = data.Base.Pedestals + 1
	if nextSlot > SETTINGS.MaxPedestals then
		Net:Notify(player, "Your base is fully upgraded!")
		return
	end
	local cost = SETTINGS.PedestalCosts[nextSlot] or math.huge
	if data.Coins < cost then
		Net:Notify(player, "Not enough %s! Need %s more.", Color3.fromRGB(255, 110, 110), "coins", Util.Format(cost - data.Coins))
		return
	end
	data.Coins -= cost
	data.Base.Pedestals = nextSlot
	Net:Notify(player, "🏠 New pedestal! (%d/%d)", Color3.fromRGB(120, 255, 170), nextSlot, SETTINGS.MaxPedestals)
	Services.ProgressionService:AddQuest(player, "Upgrade", 1)
	Data:MarkDirty(player)
	self:Render(player)
end

function Base:TrySteal(thief: Player, owner: Player, entry)
	if thief == owner or not owner.Parent then
		return
	end
	local shards = Services.ShardService
	if shards:IsCarrying(thief) then
		Net:Notify(thief, "Your hands are full!")
		return
	end
	if not plotOf[thief] then
		Net:Notify(thief, "You need a base to steal shards!")
		return
	end
	if self:IsLocked(owner) then
		Net:Notify(thief, "🔒 This base is locked!")
		return
	end
	local data = Data:Get(owner)
	if not data or entry.Away or not table.find(data.Base.Shards, entry) then
		return
	end
	local def = Config.Shards.Rarities[entry.Id]
	self:SetAway(owner, entry, true)
	if not shards:StartCarry(thief, entry.Id, { From = owner, Entry = entry }) then
		self:SetAway(owner, entry, false)
		return
	end
	Net:Send(owner, "BaseAlarm", thief.DisplayName, def.Name)
	Net:Notify(owner, "🚨 %s is stealing your %s! Bonk them!", Color3.fromRGB(255, 80, 80), thief.DisplayName, def.Name)
	Net:Notify(thief, "🏃 You stole a %s! Run to your base!", Color3.fromRGB(255, 170, 80), def.Name)
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
-- plot assignment
---------------------------------------------------------------------------
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
			if player and plot.Owner == player and not debounced(player, 0.6) then
				Base:Collect(player)
			end
		end)
		plot.LockPad.Touched:Connect(function(hit)
			local player = playerFromHit(hit)
			if player and plot.Owner == player and not debounced(player, 0.6) then
				Base:Lock(player)
			end
		end)
	end

	Data:OnLoaded(function(player, data)
		-- shards a thief was carrying when the server closed are still ours
		for _, entry in data.Base.Shards do
			entry.Away = nil
		end
		assign(player, data)
	end)
	Data:OnLeaving(function(_player, data)
		data.Base.LastOnline = os.time()
		for _, entry in data.Base.Shards do
			entry.Away = nil
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		release(player)
		touchDebounce[player] = nil
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
end

return Base
