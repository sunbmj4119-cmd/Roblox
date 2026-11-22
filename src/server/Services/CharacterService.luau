--[[
	CharacterService: gives the pickaxe tool, walk speed perks and the
	overhead tag (weekly rank, VIP / Club / leaderboard titles) that shows off
	status to everyone - a key driver of competition and pass sales.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)

local CharacterService = {}
local Services
local Data

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
	if not data then
		return
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	local character = player.Character
	local wasEquipped = false
	for _, container in { backpack, character } do
		if container then
			local existing = container:FindFirstChild("Pickaxe")
			if existing then
				if container == character then
					wasEquipped = true
				end
				existing:Destroy()
			end
		end
	end
	local tool = buildPickaxe(data.PickaxeTier)
	if wasEquipped and character then
		tool.Parent = character
	elseif backpack then
		tool.Parent = backpack
	end
end

function CharacterService:ApplyWalkSpeed(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local speed = 18
		if Services.MonetizationService:HasPass(player, "Speed") then
			speed *= 1.5
		end
		humanoid.WalkSpeed = speed
	end
end

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
		gui.Size = UDim2.fromOffset(220, 52)
		gui.StudsOffset = Vector3.new(0, 3.1, 0)
		gui.MaxDistance = 90
		gui.LightInfluence = 0

		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Vertical
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = gui

		for i, name in { "Tags", "Rank" } do
			local label = Instance.new("TextLabel")
			label.Name = name
			label.LayoutOrder = i
			label.BackgroundTransparency = 1
			label.Size = UDim2.new(1, 0, 0, if name == "Rank" then 24 else 22)
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
	end

	local rank = Util.RankFor(Config, data.Weekly.Points)
	local rankLabel = gui:FindFirstChild("Rank") :: TextLabel
	rankLabel.Text = string.format("Lv.%d  •  %s  •  ♻️%d", data.Level, string.upper(rank.Name), data.Rebirths)
	rankLabel.TextColor3 = rank.Color

	local tags = {}
	local title = player:GetAttribute("Title")
	if type(title) == "string" and title ~= "" then
		table.insert(tags, "<font color='#FFD84A'>" .. title .. "</font>")
	end
	if Services.MonetizationService:HasPass(player, "VIP") then
		table.insert(tags, "<font color='#FFC93C'>[VIP]</font>")
	end
	if Services.MonetizationService:IsSubscribed(player) then
		table.insert(tags, "<font color='#5CF2FF'>[CLUB]</font>")
	end
	local tagLabel = gui:FindFirstChild("Tags") :: TextLabel
	tagLabel.Text = table.concat(tags, " ")
	tagLabel.Visible = #tags > 0
end

local function onCharacter(player: Player, character: Model)
	local data = Data:WaitFor(player, 30)
	if not data or player.Character ~= character then
		return
	end
	character:WaitForChild("Humanoid", 10)
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
	player:GetAttributeChangedSignal("Title"):Connect(function()
		CharacterService:RefreshOverhead(player)
	end)
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
end

return CharacterService
