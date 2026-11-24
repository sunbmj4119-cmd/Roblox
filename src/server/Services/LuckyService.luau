--[[
	LuckyService: 🍀 lucky blocks.
	A few drop in the hub and on the base avenue every few minutes (lots
	during 🍀 LUCKY BLOCK RAIN and the weekly party). Hold to open one for a
	random surprise: coins, gems, boosts, a pet, a star egg to run home with,
	a HUGE pet, a gem jackpot... or a prank (launched into the sky, zapped).
	Great for "I opened 100 lucky blocks" moments.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Net = require(script.Parent.Net)

local Lucky = {}
local Services
local Data

local SETTINGS = Config.LuckyBlocks
local MAX_BLOCKS = 24
local rng = Random.new()
local blocks = {} -- [model] = true
local folder = nil

local GOOD = Color3.fromRGB(120, 255, 140)
local BAD = Color3.fromRGB(255, 150, 90)

local function count(): number
	local n = 0
	for model in blocks do
		if model.Parent then
			n += 1
		else
			blocks[model] = nil
		end
	end
	return n
end

-- somewhere open in the hub, or on the avenue between the houses
local function randomSpot(): Vector3
	for _ = 1, 30 do
		local spot
		if rng:NextNumber() < 0.6 then
			spot = Vector3.new(rng:NextNumber(-44, 44), 0, rng:NextNumber(-70, 66))
			local nearCrater = (spot - Config.Meteor.Position).Magnitude < 26
			local nearSpawn = (spot - Vector3.new(0, 0, -60)).Magnitude < 10
			local fame = spot.X < -12 and spot.Z > -14 and spot.Z < -2
			if not nearCrater and not nearSpawn and not fame then
				return spot
			end
		else
			local half = Config.World.Bases.HalfX - 20
			return Vector3.new(rng:NextNumber(-half, half), 0, Util.AvenueZ(Config) + rng:NextNumber(-8, 8))
		end
	end
	return Vector3.new(rng:NextNumber(-30, 30), 0, rng:NextNumber(0, 20))
end

local function buildBlock(): Model
	local model = Instance.new("Model")
	model.Name = "LuckyBlock"
	local box = Instance.new("Part")
	box.Name = "Block"
	box.Anchored = true
	box.CanCollide = false
	box.Size = Vector3.one * 3.6
	box.Color = Color3.fromRGB(255, 205, 50)
	box.Material = Enum.Material.SmoothPlastic
	box.TopSurface = Enum.SurfaceType.Smooth
	box.BottomSurface = Enum.SurfaceType.Smooth
	box.Parent = model
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right, Enum.NormalId.Top } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Text = "?"
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Color3.new(1, 1, 1)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 6
		stroke.Color = Color3.fromRGB(170, 110, 0)
		stroke.Parent = label
		label.Parent = gui
		gui.Parent = box
	end
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 220, 110)
	glow.Range = 12
	glow.Brightness = 1.5
	glow.Parent = box
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 240, 150))
	sparkle.LightEmission = 1
	sparkle.Size = NumberSequence.new(0.4)
	sparkle.Lifetime = NumberRange.new(0.6, 1.2)
	sparkle.Rate = 6
	sparkle.Speed = NumberRange.new(1, 2)
	sparkle.Parent = box
	model.PrimaryPart = box
	model:SetAttribute("Spin", true)
	return model
end

-- the best coin egg the player has unlocked (pets from lucky blocks come from it)
local function zoneEgg(data): string
	local eggs = Config.Shards.ZoneEggs
	return eggs[math.clamp(data.ZoneLevel or 1, 1, #eggs)] or "Meadow"
end

-- open a block: roll a surprise and apply it
function Lucky:Open(player: Player, position: Vector3?)
	local data = Data:Get(player)
	if not data then
		return nil
	end
	data.Stats.LuckyBlocks = (data.Stats.LuckyBlocks or 0) + 1
	local entries = {}
	for index, outcome in SETTINGS.Outcomes do
		table.insert(entries, { index, outcome.Weight })
	end
	local outcome = SETTINGS.Outcomes[Util.WeightedPick(entries)]
	local kind = outcome.Kind
	local good = true
	if kind == "Coins" then
		local rate = Services.BaseService:IncomeRate(player, data)
		local amount = math.max(outcome.Min or 0, math.floor(rate * outcome.Seconds))
		data.Coins += amount
		data.Stats.LifetimeCoins += amount
		Services.Analytics:Economy(player, "Source", "Coins", amount, data.Coins, "Gameplay", "LuckyBlock")
		Net:Send(player, "Sold", amount)
		Net:Notify(player, "🍀 Lucky block: +💰%s!", GOOD, Util.Format(amount))
	elseif kind == "Gems" then
		local amount = rng:NextInteger(outcome.Min, outcome.Max)
		data.Gems += amount
		Net:Notify(player, "🍀 Lucky block: +💎%d!", GOOD, amount)
	elseif kind == "Boost" then
		Services.BoostService:Add(player, outcome.Boost, outcome.Seconds)
	elseif kind == "Pet" then
		Services.PetService:HatchStarEgg(player, zoneEgg(data), outcome.Luck or 1)
		Net:Notify(player, "🍀 Lucky block: a pet popped out!", GOOD)
	elseif kind == "StarEgg" then
		local shards = Services.ShardService
		if shards:IsCarrying(player) then
			data.Gems += 40
			Net:Notify(player, "🍀 Lucky block: +💎%d!", GOOD, 40)
		else
			shards:StartCarry(player, { Kind = "Egg", Rarity = outcome.Rarity, Egg = zoneEgg(data) }, nil)
			Net:Notify(player, "🍀 A star egg! Run it home before someone bonks you!", GOOD)
		end
	elseif kind == "Launch" then
		good = false
		Net:Send(player, "Launch", Vector3.new(0, 140, 0))
		Net:Notify(player, "💥 BOOM! It was a prank block!", BAD)
	elseif kind == "Zap" then
		good = false
		Services.CharacterService:Stun(player, outcome.Seconds)
		Net:Send(player, "Stunned", outcome.Seconds)
		Net:Notify(player, "⚡ ZAP! A prank block froze you!", BAD)
	elseif kind == "Huge" then
		local pick = Util.WeightedPick(Config.Eggs[zoneEgg(data)].Pets)
		Services.PetService:GrantPet(player, pick, "Huge")
		Net:Announce("🍀 %s found a HUGE %s in a lucky block!", Color3.fromRGB(255, 200, 60), player.DisplayName, pick)
	elseif kind == "Jackpot" then
		data.Gems += outcome.Gems
		Net:Announce("🍀 JACKPOT! %s won 💎%d from a lucky block!", Color3.fromRGB(255, 220, 90), player.DisplayName, outcome.Gems)
	end
	if position then
		Net:Broadcast(if good then "Confetti" else "Boom", position)
	end
	Services.ProgressionService:AddXP(player, 20)
	Services.Analytics:Custom(player, "LuckyBlock", 1)
	Data:MarkDirty(player)
	return kind
end

function Lucky:Spawn(position: Vector3?)
	if count() >= MAX_BLOCKS or not folder then
		return nil
	end
	local spot = position or randomSpot()
	local model = buildBlock()
	local ground = CFrame.new(spot + Vector3.new(0, 2.6, 0))
	model:PivotTo(ground + Vector3.new(0, 45, 0))
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open"
	prompt.ObjectText = "Lucky Block"
	prompt.HoldDuration = SETTINGS.OpenHold
	prompt.MaxActivationDistance = 11
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = model.PrimaryPart
	prompt.Triggered:Connect(function(player)
		if not blocks[model] then
			return
		end
		blocks[model] = nil
		local where = model:GetPivot().Position
		model:Destroy()
		local ok, err = pcall(self.Open, self, player, where)
		if not ok then
			warn("[Lucky] open failed: " .. tostring(err))
		end
	end)
	blocks[model] = true
	model.Parent = folder
	-- drop from the sky
	task.spawn(function()
		for step = 1, 20 do
			if not model.Parent then
				return
			end
			local t = step / 20
			model:PivotTo(ground + Vector3.new(0, 45 * (1 - t * t), 0))
			task.wait(0.03)
		end
		if model.Parent then
			model:PivotTo(ground)
		end
	end)
	task.delay(SETTINGS.Lifetime, function()
		if blocks[model] then
			blocks[model] = nil
			model:Destroy()
		end
	end)
	return model
end

function Lucky:Rain(amount: number)
	for _ = 1, amount do
		self:Spawn(nil)
		task.wait(0.15)
	end
end

function Lucky:Init(services)
	Services = services
	Data = services.DataService
end

function Lucky:Start()
	local map = workspace:FindFirstChild("Map")
	folder = Instance.new("Folder")
	folder.Name = "LuckyBlocks"
	folder.Parent = map or workspace

	-- 🍀 LUCKY BLOCK RAIN event
	Services.EventService:OnStart(function(def)
		if def.LuckyBlocks then
			task.spawn(self.Rain, self, def.LuckyBlocks)
		end
	end)

	task.spawn(function()
		task.wait(40)
		while true do
			if #Players:GetPlayers() > 0 then
				local ok, err = pcall(self.Rain, self, SETTINGS.Count)
				if not ok then
					warn("[Lucky] spawn failed: " .. tostring(err))
				else
					Net:Announce("🍀 Lucky blocks just dropped! Find them!", GOOD)
				end
			end
			task.wait(rng:NextNumber(SETTINGS.MinInterval, SETTINGS.MaxInterval))
		end
	end)
end

return Lucky
