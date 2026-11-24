--[[
	CharacterService: gives the pickaxe tool, walk speed perks and the
	overhead tag (weekly rank, VIP / Club / leaderboard titles) that shows off
	status to everyone - a key driver of competition and pass sales.
]]
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)

local Net = require(script.Parent.Net)

local CharacterService = {}
local Services
local Data
local unlockedTitles = {} -- [player] = number of titles unlocked (for "new title!" toasts)

local function buildPickaxe(tier: number): Tool
	local info = Config.Pickaxes[tier] or Config.Pickaxes[1]
	local tool = Instance.new("Tool")
	tool.Name = "Pickaxe"
	tool.ToolTip = info.Name
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("Tier", tier)
	tool.Grip = CFrame.new(0, -1.1, 0)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.35, 3.4, 0.35)
	handle.Color = Color3.fromRGB(110, 75, 45)
	handle.Material = Enum.Material.Wood
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(2.8, 0.5, 0.5)
	head.Color = info.Color
	head.Material = if tier >= 7 then Enum.Material.Neon else Enum.Material.Metal
	head.CanCollide = false
	head.Massless = true
	head.CFrame = handle.CFrame * CFrame.new(0, 1.5, 0)
	head.Parent = tool

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = head
	weld.Parent = handle

	if tier >= 7 then
		local light = Instance.new("PointLight")
		light.Color = info.Color
		light.Range = 8
		light.Parent = head
	end
	-- swing trail from tier 4: upgrades you can SEE are upgrades people buy
	if tier >= 4 then
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(-1.3, 0, 0)
		a0.Parent = head
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(1.3, 0, 0)
		a1.Parent = head
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Color = ColorSequence.new(info.Color)
		trail.LightEmission = if tier >= 7 then 1 else 0.4
		trail.Lifetime = 0.18
		trail.Transparency = NumberSequence.new(0.2, 1)
		trail.FaceCamera = true
		trail.Parent = head
	end
	return tool
end

function CharacterService:GivePickaxe(player: Player)
	local data = Data:Get(player)
	local tier = if data then data.PickaxeTier else 1 -- a basic pickaxe before data loads
	local backpack = player:FindFirstChildOfClass("Backpack")
	local character = player.Character
	for _, container in { backpack, character } do
		if container then
			local existing = container:FindFirstChild("Pickaxe")
			if existing then
				existing:Destroy()
			end
		end
	end
	local tool = buildPickaxe(tier)
	-- always in hand: the hotbar is hidden, so an unequipped pickaxe = can't mine
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		for _, other in character:GetChildren() do
			if other:IsA("Tool") and other ~= tool then
				other.Parent = backpack
			end
		end
		tool.Parent = character
	elseif backpack then
		tool.Parent = backpack
	end
end

local padUntil = {} -- [player] = os.clock() when the dash pad boost ends
local stunnedUntil = {} -- [player] = os.clock() when a trap/guardian stun ends
local DEFAULT_JUMP = 7.2

function CharacterService:ApplyWalkSpeed(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		if (stunnedUntil[player] or 0) > os.clock() then
			humanoid.WalkSpeed = 0
			humanoid.JumpHeight = 0
			return
		end
		humanoid.JumpHeight = DEFAULT_JUMP
		local speed = Config.World.WalkSpeed
		local data = Data:Get(player)
		local boots = data and Config.Boots[data.SpeedTier or 1]
		if boots then
			speed *= 1 + boots.Bonus
		end
		if Services.MonetizationService:HasPass(player, "Speed") then
			speed *= 1.5
		end
		local shards = Services.ShardService
		if shards then
			speed *= shards:SpeedMult(player)
		end
		local mining = Services.MiningService
		if mining and mining:IsFever(player) then
			speed *= Config.Fever.SpeedMult
		end
		if (padUntil[player] or 0) > os.clock() then
			speed *= Config.SpeedPads.Mult
		end
		humanoid.WalkSpeed = speed
	end
end

-- freeze a player for a moment (stun traps, guardians)
function CharacterService:Stun(player: Player, seconds: number)
	stunnedUntil[player] = os.clock() + seconds
	self:ApplyWalkSpeed(player)
	task.delay(seconds + 0.05, function()
		if player.Parent and (stunnedUntil[player] or 0) <= os.clock() then
			stunnedUntil[player] = nil
			self:ApplyWalkSpeed(player)
		end
	end)
end

function CharacterService:SpeedPad(player: Player)
	padUntil[player] = os.clock() + Config.SpeedPads.Seconds
	self:ApplyWalkSpeed(player)
	task.delay(Config.SpeedPads.Seconds + 0.05, function()
		if player.Parent and (padUntil[player] or 0) <= os.clock() then
			self:ApplyWalkSpeed(player)
		end
	end)
end

-- overhead tag: title, name (gold for VIP), level/rank/rebirths, bounty
function CharacterService:RefreshOverhead(player: Player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local data = Data:Get(player)
	if not head or not data then
		return
	end
	local gui = head:FindFirstChild("Overhead") :: BillboardGui
	if not gui then
		gui = Instance.new("BillboardGui")
		gui.Name = "Overhead"
		gui.Size = UDim2.new(7, 0, 2.6, 0) -- studs: small up close, readable nearby
		gui.StudsOffset = Vector3.new(0, 3.4, 0)
		gui.MaxDistance = 90
		gui.LightInfluence = 0

		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Vertical
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = gui

		for i, name in { "Bounty", "Title", "Tags", "Name", "Rank" } do
			local label = Instance.new("TextLabel")
			label.Name = name
			label.LayoutOrder = i
			label.BackgroundTransparency = 1
			label.Size = UDim2.new(1, 0, if name == "Name" then 0.26 else 0.18, 0)
			label.Font = Enum.Font.FredokaOne
			label.TextScaled = true
			label.RichText = true
			label.TextColor3 = Color3.new(1, 1, 1)
			local stroke = Instance.new("UIStroke")
			stroke.Thickness = 2
			stroke.Parent = label
			label.Parent = gui
		end
		gui.Parent = head
		-- our tag shows the name (so VIPs can have a gold one)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
	end
	local monetization = Services.MonetizationService
	local vip = monetization:HasPass(player, "VIP")

	local rank = Util.RankFor(Config, data.Weekly.Points)
	local rankLabel = gui:FindFirstChild("Rank") :: TextLabel
	rankLabel.Text = if data.Rebirths > 0
		then string.format("Lv.%d %s ♻️%d", data.Level, rank.Icon or "", data.Rebirths)
		else string.format("Lv.%d %s", data.Level, rank.Icon or "")
	rankLabel.TextColor3 = rank.Color

	local nameLabel = gui:FindFirstChild("Name") :: TextLabel
	nameLabel.Text = (if vip then "👑 " else "") .. player.DisplayName
	nameLabel.TextColor3 = if vip then Color3.fromRGB(255, 210, 70) else Color3.new(1, 1, 1)

	-- earned title (each viewer reads it in their own language, see WorldFX)
	local title = Util.CurrentTitle(Config, data, function(key)
		return monetization:HasPass(player, key)
	end)
	local titleLabel = gui:FindFirstChild("Title") :: TextLabel
	titleLabel.Visible = title ~= nil and title.Id ~= "Newcomer"
	if title then
		titleLabel.Text = title.Name
		titleLabel.TextColor3 = title.Color
		titleLabel:SetAttribute("LangFmt", "%s")
		titleLabel:SetAttribute("LangArgs", HttpService:JSONEncode({ title.Name }))
	end
	-- leaderboard place + VIP / CLUB tags
	local tags = {}
	local place = player:GetAttribute("Title")
	if type(place) == "string" and place ~= "" then
		table.insert(tags, "<font color='#FFD84A'>" .. place .. "</font>")
	end
	if vip then
		table.insert(tags, "<font color='#FFC93C'>[VIP]</font>")
	end
	if monetization:IsSubscribed(player) then
		table.insert(tags, "<font color='#5CF2FF'>[CLUB]</font>")
	end
	local tagLabel = gui:FindFirstChild("Tags") :: TextLabel
	tagLabel.Text = table.concat(tags, " ")
	tagLabel.Visible = #tags > 0
	player:SetAttribute("TitleName", if title then title.Name else "")

	local bountyLabel = gui:FindFirstChild("Bounty") :: TextLabel
	local bounty = player:GetAttribute("Bounty")
	bountyLabel.Visible = type(bounty) == "number" and bounty > 0
	if bountyLabel.Visible then
		bountyLabel.Text = "💰 BOUNTY " .. Util.Format(bounty)
		bountyLabel.TextColor3 = Color3.fromRGB(255, 90, 70)
	end
end

local function onCharacter(player: Player, character: Model)
	character:WaitForChild("Humanoid", 10)
	-- pickaxe in hand right away, even while the save is still loading
	if not Data:Get(player) then
		CharacterService:GivePickaxe(player)
		CharacterService:ApplyWalkSpeed(player)
	end
	local data = Data:WaitFor(player, 30)
	if not data or player.Character ~= character then
		return
	end
	character:WaitForChild("Head", 10)
	CharacterService:GivePickaxe(player)
	CharacterService:ApplyWalkSpeed(player)
	CharacterService:RefreshOverhead(player)
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
	for _, attribute in { "Title", "Bounty" } do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			CharacterService:RefreshOverhead(player)
		end)
	end
end

function CharacterService:Init(services)
	Services = services
	Data = services.DataService
end

function CharacterService:Start()
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		padUntil[player] = nil
		stunnedUntil[player] = nil
		unlockedTitles[player] = nil
	end)

	-- new titles: tell the player + update the tag
	task.spawn(function()
		while true do
			task.wait(15)
			for _, player in Data:LoadedPlayers() do
				local data = Data:Get(player)
				if data then
					local hasPass = function(key)
						return Services.MonetizationService:HasPass(player, key)
					end
					local count, newest = 0, nil
					for _, title in Config.Titles do
						if Util.TitleUnlocked(Config, title, data, hasPass) then
							count += 1
							newest = title
						end
					end
					local before = unlockedTitles[player]
					unlockedTitles[player] = count
					if before and count > before and newest then
						Net:Notify(player, "🏅 New title unlocked: %s! (👑 Titles)", newest.Color, newest.Name)
						self:RefreshOverhead(player)
					elseif player:GetAttribute("TitleName") ~= Util.CurrentTitle(Config, data, hasPass).Name then
						self:RefreshOverhead(player)
					end
				end
			end
		end
	end)

	-- dash pads
	local net = Net
	for _, pad in Services.WorldService.SpeedPads do
		pad.Touched:Connect(function(hit)
			local model = hit:FindFirstAncestorOfClass("Model")
			local player = model and Players:GetPlayerFromCharacter(model)
			if player and (padUntil[player] or 0) - os.clock() < Config.SpeedPads.Seconds - 0.4 then
				self:SpeedPad(player)
				net:Send(player, "SpeedPad")
			end
		end)
	end
end

return CharacterService
