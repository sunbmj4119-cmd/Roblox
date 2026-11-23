--[[
	Build mode: decorate your own base.
	* Stand in your base -> tap "🔨 DECORATE".
	* The camera looks down on your base. Pick an item from the catalog,
	  tap the floor to move the preview (green = OK, red = blocked),
	  🔄 rotate, ✅ place. Placing again keeps the same item selected, so
	  floors and fences are quick to lay out.
	* Tap something you already placed to ✋ move, 🔄 rotate or 🗑 remove it
	  (removing refunds everything, so redecorating is free).
	The server re-validates every action (BaseService).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local DecorModel = require(Shared.DecorModel)

local Client = script.Parent.Parent
local Net = require(Client.Net)
local State = require(Client.State)
local Lib = require(Client.UI.Lib)
local Root = require(Client.UI.Root)

local player = Players.LocalPlayer
local C = Lib.Colors
local New = Lib.New
local T = Lib.T

local Build = {}
local SETTINGS = Config.Base
local PLOT_HALF = SETTINGS.PlotSize / 2
local FLOOR_Y = 0.42

State.BuildMode = false

---------------------------------------------------------------------------
-- plot helpers
---------------------------------------------------------------------------
local function myPlot(): Model?
	local index = player:GetAttribute("BaseIndex")
	local map = workspace:FindFirstChild("Map")
	local bases = map and map:FindFirstChild("Bases")
	local plot = index and bases and bases:FindFirstChild("Plot_" .. tostring(index))
	if plot and plot:GetAttribute("OwnerId") == player.UserId then
		return plot :: Model
	end
	return nil
end

local function plotFrame(plot: Model): CFrame?
	local floor = plot:FindFirstChild("Floor")
	return if floor and floor:IsA("BasePart") then floor.CFrame * CFrame.new(0, -0.2, 0) else nil
end

local function insideMyPlot(): boolean
	local plot = myPlot()
	local frame = plot and plotFrame(plot)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not frame or not root or not root:IsA("BasePart") then
		return false
	end
	local p = frame:PointToObjectSpace(root.Position)
	return math.abs(p.X) <= PLOT_HALF + 1 and math.abs(p.Z) <= PLOT_HALF + 1
end

local function items()
	local data = State.Data
	return if data and data.Base then data.Base.Items else {}
end

local function findItem(uid: number)
	for _, item in items() do
		if item.Uid == uid then
			return item
		end
	end
	return nil
end

local function priceText(id: string): string
	local currency, price = DecorModel.Price(Config, id, items())
	if price <= 0 then
		return T("FREE")
	elseif price == math.huge then
		return T("MAX")
	end
	return (if currency == "Gems" then "💎 " else "💰 ") .. Util.Format(price)
end

local function canAfford(id: string): boolean
	local data = State.Data
	if not data then
		return false
	end
	local currency, price = DecorModel.Price(Config, id, items())
	return (if currency == "Gems" then data.Gems else data.Coins) >= price
end

---------------------------------------------------------------------------
-- state
---------------------------------------------------------------------------
local mode = "browse" -- browse | placing | selected
local currentId: string? = nil -- item being placed
local movingUid: number? = nil -- existing item being moved
local selectedUid: number? = nil
local ghost: Model? = nil
local ghostX, ghostZ, ghostR = 0, 0, 0
local busy = false

-- highlights live in workspace (Adornee only), so destroying a model never kills them
local ghostHighlight = Instance.new("Highlight")
ghostHighlight.Name = "BuildGhostHighlight"
ghostHighlight.FillTransparency = 0.55
ghostHighlight.OutlineTransparency = 0
ghostHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
ghostHighlight.Parent = workspace
local selectHighlight = Instance.new("Highlight")
selectHighlight.Name = "BuildSelectHighlight"
selectHighlight.FillColor = Color3.fromRGB(255, 220, 90)
selectHighlight.FillTransparency = 0.7
selectHighlight.OutlineColor = Color3.fromRGB(255, 220, 90)
selectHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
selectHighlight.Parent = workspace

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------
-- the "DECORATE" button shows up while you stand in your own base
local entry = Root.Cluster("BuildEntry", Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -76), UDim2.fromOffset(230, 56))
local entryButton = Lib.Button({
	Text = "🔨 DECORATE",
	Color = Color3.fromRGB(255, 150, 60),
	Size = UDim2.fromScale(1, 1),
	TextSize = 24,
	Parent = entry,
	OnClick = function()
		Build.Enter()
	end,
})
entryButton.Visible = false

local screen = New("Frame", {
	Name = "BuildScreen",
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	Visible = false,
	ZIndex = 30,
	Parent = Root.Overlay,
})

local function cluster(name: string, anchor: Vector2, position: UDim2, size: UDim2)
	return Root.Cluster(name, anchor, position, size, screen)
end

-- top: title + hint, done button
local top = cluster("BuildTop", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 44), UDim2.fromOffset(560, 64))
local topCard = New("Frame", {
	BackgroundColor3 = Color3.fromRGB(20, 22, 34),
	BackgroundTransparency = 0.15,
	Size = UDim2.fromScale(1, 1),
	Parent = top,
}, { Lib.Corner(14), Lib.Stroke(Color3.fromRGB(255, 160, 70), 2.5, 0) })
Lib.Text({
	Text = "🔨 DECORATE YOUR BASE",
	TextColor3 = Color3.fromRGB(255, 190, 100),
	Size = UDim2.new(1, -16, 0, 30),
	Position = UDim2.fromOffset(8, 4),
	MaxTextSize = 24,
	Parent = topCard,
})
local topHint = Lib.Text({
	Text = "",
	Font = Lib.BodyFont,
	TextColor3 = C.Sub,
	Size = UDim2.new(1, -16, 0, 20),
	Position = UDim2.fromOffset(8, 38),
	MaxTextSize = 15,
	Parent = topCard,
})

local doneCluster = cluster("BuildDone", Vector2.new(1, 0), UDim2.new(1, -12, 0, 44), UDim2.fromOffset(130, 52))
Lib.Button({
	Text = "✔ DONE",
	Color = C.Green,
	Size = UDim2.fromScale(1, 1),
	TextSize = 22,
	Parent = doneCluster,
	OnClick = function()
		Build.Exit()
	end,
})

-- bottom: catalog (tabs + cards)
local catalog = cluster("BuildCatalog", Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -8), UDim2.fromOffset(760, 178))
local catalogCard = New("Frame", {
	BackgroundColor3 = Color3.fromRGB(20, 22, 34),
	BackgroundTransparency = 0.08,
	Size = UDim2.fromScale(1, 1),
	Parent = catalog,
}, { Lib.Corner(16), Lib.Stroke(Color3.new(0, 0, 0), 2, 0.3) })
local tabRow = New("Frame", {
	BackgroundTransparency = 1,
	Size = UDim2.new(1, -16, 0, 40),
	Position = UDim2.fromOffset(8, 6),
	Parent = catalogCard,
}, { Lib.List(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })
local cardScroll = New("ScrollingFrame", {
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Size = UDim2.new(1, -16, 0, 120),
	Position = UDim2.fromOffset(8, 52),
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.X,
	ScrollingDirection = Enum.ScrollingDirection.X,
	ScrollBarThickness = 6,
	Parent = catalogCard,
}, { Lib.List(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })

-- action bar (above the catalog)
local actions = cluster("BuildActions", Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -196), UDim2.fromOffset(620, 58))
local actionRow = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = actions }, {
	Lib.List(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
})
local actionButtons = {}
local function actionButton(key: string, text: string, color: Color3, order: number, onClick)
	local button = Lib.Button({
		Text = text,
		Color = color,
		Size = UDim2.fromOffset(140, 52),
		LayoutOrder = order,
		TextSize = 20,
		Parent = actionRow,
		OnClick = onClick,
	})
	button.Visible = false
	actionButtons[key] = button
	return button
end

---------------------------------------------------------------------------
-- ghost preview
---------------------------------------------------------------------------
local function clearGhost()
	if ghost then
		ghost:Destroy()
		ghost = nil
	end
	ghostHighlight.Adornee = nil
end

local function ghostValid(): boolean
	local id = currentId
	if not id then
		return false
	end
	local ok = DecorModel.Validate(Config, items(), id, ghostX, ghostZ, ghostR, movingUid)
	if not ok then
		return false
	end
	return movingUid ~= nil or canAfford(id)
end

local function updateGhost()
	local plot = myPlot()
	local frame = plot and plotFrame(plot)
	if not ghost or not frame then
		return
	end
	ghost:PivotTo(frame * CFrame.new(ghostX, FLOOR_Y + 0.1, ghostZ) * CFrame.Angles(0, ghostR * math.pi / 2, 0))
	local valid = ghostValid()
	local color = if valid then Color3.fromRGB(90, 255, 130) else Color3.fromRGB(255, 80, 80)
	ghostHighlight.FillColor = color
	ghostHighlight.OutlineColor = color
	Lib.SetButton(actionButtons.Place, nil, if valid then C.Green else C.Gray)
end

local function makeGhost(id: string)
	clearGhost()
	local model = DecorModel.Build(Config, id)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.CanQuery = false
			p.Transparency = math.max(p.Transparency, 0.35)
			if p.Name == "Footprint" then
				p.Transparency = 0.6
				p.Color = Color3.fromRGB(255, 255, 255)
			end
		elseif p:IsA("Light") then
			p.Enabled = false
		end
	end
	model.Name = "BuildGhost"
	model.Parent = workspace
	ghost = model
	ghostHighlight.Adornee = model
	updateGhost()
end

local function snapGhost(x: number, z: number)
	if not currentId then
		return
	end
	local bounds = SETTINGS.Build
	local w, d = DecorModel.Footprint(Config, currentId, ghostR)
	x = math.clamp(x, bounds.MinX + w / 2, bounds.MaxX - w / 2)
	z = math.clamp(z, bounds.MinZ + d / 2, bounds.MaxZ - d / 2)
	ghostX, ghostZ = DecorModel.Snap(Config, currentId, x, z, ghostR)
	updateGhost()
end

---------------------------------------------------------------------------
-- modes
---------------------------------------------------------------------------
local function setHint(text: string)
	topHint.Text = text
end

local function refreshActions()
	for _, button in actionButtons do
		button.Visible = false
	end
	if mode == "placing" then
		actionButtons.Rotate.Visible = true
		actionButtons.Place.Visible = true
		actionButtons.Cancel.Visible = true
		local def = currentId and Config.Decor[currentId]
		setHint(T("Tap the floor to move it • 🔄 rotate • ✅ place") .. (if def then "  (" .. T(def.Name) .. ")" else ""))
	elseif mode == "selected" then
		actionButtons.Move.Visible = true
		actionButtons.Turn.Visible = true
		actionButtons.Remove.Visible = true
		actionButtons.Cancel.Visible = true
		local item = selectedUid and findItem(selectedUid)
		local def = item and Config.Decor[item.Id]
		if item and def then
			local refund = math.floor(item.Paid or 0)
			local icon = if item.Cur == "Gems" then "💎" else "💰"
			Lib.SetButton(actionButtons.Remove, T("🗑 Remove") .. (if refund > 0 then " +" .. icon .. Util.Format(refund) else ""))
			setHint(T(def.Name))
		end
	else
		setHint(T("Pick something below, or tap an item in your base to edit it"))
	end
end

local function selectItem(uid: number?)
	selectedUid = uid
	selectHighlight.Adornee = nil
	local plot = myPlot()
	if uid and plot then
		local folder = plot:FindFirstChild("Items")
		for _, model in (folder and folder:GetChildren() or {}) do
			if model:GetAttribute("Uid") == uid then
				selectHighlight.Adornee = model
			end
		end
	end
end

local function startPlacing(id: string, fromItem)
	currentId = id
	movingUid = fromItem and fromItem.Uid or nil
	ghostR = fromItem and fromItem.R or ghostR
	mode = "placing"
	selectItem(nil)
	makeGhost(id)
	if fromItem then
		ghostX, ghostZ = fromItem.X, fromItem.Z
	else
		ghostX, ghostZ = 0, 6
	end
	snapGhost(ghostX, ghostZ)
	refreshActions()
end

local function backToBrowse()
	mode = "browse"
	currentId = nil
	movingUid = nil
	clearGhost()
	selectItem(nil)
	refreshActions()
end

local function request(name: string, ...)
	if busy then
		return false
	end
	busy = true
	local ok, message = Net.Invoke(name, ...)
	busy = false
	if not ok and type(message) == "string" then
		Lib.PlaySound("Bonked", 0.4)
		local hud = Build.HUD
		if hud then
			hud.Toast(message, C.Red)
		end
	end
	return ok == true
end

actionButton("Rotate", "🔄 Rotate", C.Blue, 1, function()
	ghostR = (ghostR + 1) % 4
	snapGhost(ghostX, ghostZ)
end)
actionButton("Place", "✅ Place", C.Green, 2, function()
	if mode ~= "placing" or not currentId then
		return
	end
	if movingUid then
		if request("BaseMove", movingUid, ghostX, ghostZ, ghostR) then
			Lib.PlaySound("Reward", 0.6)
			backToBrowse()
		end
	elseif request("BasePlace", currentId, ghostX, ghostZ, ghostR) then
		Lib.PlaySound("Coin", 0.8, 0.1)
		Lib.Pop(actionButtons.Place)
		-- keep the same item selected: quick to lay floors / fences
		task.delay(0.15, updateGhost)
	end
end)
actionButton("Move", "✋ Move", C.Blue, 1, function()
	local item = selectedUid and findItem(selectedUid)
	if item then
		startPlacing(item.Id, item)
	end
end)
actionButton("Turn", "🔄 Rotate", C.Purple, 2, function()
	local item = selectedUid and findItem(selectedUid)
	if item and request("BaseMove", item.Uid, item.X, item.Z, (item.R + 1) % 4) then
		Lib.PlaySound("UI")
		task.delay(0.2, function()
			selectItem(item.Uid)
		end)
	end
end)
actionButton("Remove", "🗑 Remove", C.Red, 3, function()
	local item = selectedUid and findItem(selectedUid)
	if item and request("BaseRemove", item.Uid) then
		Lib.PlaySound("Coin", 0.7, -0.1)
		backToBrowse()
	end
end)
actionButton("Cancel", "✖", C.Gray, 4, function()
	backToBrowse()
end)
actionButtons.Cancel.Size = UDim2.fromOffset(64, 52)

---------------------------------------------------------------------------
-- catalog
---------------------------------------------------------------------------
local currentCategory = Config.DecorCategories[1].Id
local tabButtons = {}
local cards = {} -- [id] = { Button, Price }

local function refreshCatalog()
	for id, card in cards do
		local def = Config.Decor[id]
		card.Price.Text = priceText(id)
		local limit = if def.Function == "Pedestal" then SETTINGS.MaxPedestals else def.Limit
		card.Count.Text = if limit then string.format("%d/%d", DecorModel.Count(items(), id), limit) else ""
		card.Button.BackgroundColor3 = if canAfford(id) then C.Card else Color3.fromRGB(60, 40, 50)
	end
	for id, button in tabButtons do
		button.BackgroundColor3 = if id == currentCategory then Color3.fromRGB(255, 160, 70) else C.Gray
	end
end

local function buildCards()
	Lib.Clear(cardScroll)
	cards = {}
	for order, id in Config.DecorOrder do
		local def = Config.Decor[id]
		if def and def.Category == currentCategory then
			local button = New("TextButton", {
				Name = id,
				AutoButtonColor = true,
				BackgroundColor3 = C.Card,
				Size = UDim2.fromOffset(112, 112),
				LayoutOrder = order,
				Text = "",
				Parent = cardScroll,
			}, { Lib.Corner(12), Lib.Stroke(Color3.new(0, 0, 0), 2, 0.4) })
			Lib.Text({
				Text = def.Icon,
				Size = UDim2.new(1, 0, 0, 46),
				Position = UDim2.fromOffset(0, 6),
				MaxTextSize = 40,
				Parent = button,
			})
			Lib.Text({
				Text = def.Name,
				Size = UDim2.new(1, -8, 0, 26),
				Position = UDim2.fromOffset(4, 52),
				MaxTextSize = 15,
				Parent = button,
			})
			local price = Lib.Text({
				Text = "",
				TextColor3 = if def.Gems then C.Gems else C.Coins,
				Size = UDim2.new(1, -8, 0, 22),
				Position = UDim2.fromOffset(4, 82),
				MaxTextSize = 16,
				Parent = button,
			})
			local count = Lib.Text({
				Text = "",
				Font = Lib.BodyFont,
				TextColor3 = C.Sub,
				Size = UDim2.fromOffset(40, 16),
				Position = UDim2.new(1, -44, 0, 4),
				MaxTextSize = 12,
				Parent = button,
			})
			button.Activated:Connect(function()
				Lib.PlaySound("UI")
				startPlacing(id, nil)
			end)
			cards[id] = { Button = button, Price = price, Count = count }
		end
	end
	refreshCatalog()
end

for order, category in Config.DecorCategories do
	local button = Lib.Button({
		Text = category.Icon .. " " .. T(category.Name),
		Color = C.Gray,
		Size = UDim2.fromOffset(100, 36),
		LayoutOrder = order,
		TextSize = 15,
		Parent = tabRow,
		OnClick = function()
			currentCategory = category.Id
			buildCards()
		end,
	})
	tabButtons[category.Id] = button
end

---------------------------------------------------------------------------
-- tapping in the world while building
---------------------------------------------------------------------------
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function tapAt(position: Vector3)
	local camera = workspace.CurrentCamera
	local plot = myPlot()
	local frame = plot and plotFrame(plot)
	if not camera or not plot or not frame then
		return
	end
	local ray = camera:ScreenPointToRay(position.X, position.Y)
	local ignore = { player.Character :: Instance }
	if ghost then
		table.insert(ignore, ghost)
	end
	rayParams.FilterDescendantsInstances = ignore
	local result = workspace:Raycast(ray.Origin, ray.Direction * 400, rayParams)
	if not result then
		return
	end
	-- tapped one of our decorations?
	local folder = plot:FindFirstChild("Items")
	local model = result.Instance:FindFirstAncestorOfClass("Model")
	if mode ~= "placing" and model and folder and model.Parent == folder then
		local uid = model:GetAttribute("Uid")
		if type(uid) == "number" then
			mode = "selected"
			selectItem(uid)
			refreshActions()
			Lib.PlaySound("UI")
		end
		return
	end
	local localPos = frame:PointToObjectSpace(result.Position)
	if mode == "placing" then
		snapGhost(localPos.X, localPos.Z)
	elseif mode == "selected" then
		backToBrowse()
	end
end

local touches = {}
UserInputService.InputBegan:Connect(function(input, processed)
	if not State.BuildMode or processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		tapAt(input.Position)
	elseif input.UserInputType == Enum.UserInputType.Touch then
		touches[input] = { Start = input.Position, Time = os.clock(), Drag = false }
	end
end)
UserInputService.InputChanged:Connect(function(input)
	local touch = touches[input]
	if touch and (input.Position - touch.Start).Magnitude > 16 then
		touch.Drag = true
	end
end)
UserInputService.InputEnded:Connect(function(input)
	local touch = touches[input]
	touches[input] = nil
	if State.BuildMode and touch and not touch.Drag and os.clock() - touch.Time < 0.45 then
		tapAt(input.Position)
	end
end)

---------------------------------------------------------------------------
-- enter / exit (overview camera of the base)
---------------------------------------------------------------------------
local savedCameraType = Enum.CameraType.Custom
function Build.Enter()
	if State.BuildMode or player:GetAttribute("Carrying") then
		return
	end
	local plot = myPlot()
	local frame = plot and plotFrame(plot)
	if not frame then
		return
	end
	State.BuildMode = true
	entryButton.Visible = false
	screen.Visible = true
	local camera = workspace.CurrentCamera
	if camera then
		savedCameraType = camera.CameraType
		camera.CameraType = Enum.CameraType.Scriptable
		local eye = frame * CFrame.new(0, 54, -44)
		local target = frame * CFrame.new(0, 0, 3)
		TweenService:Create(camera, TweenInfo.new(0.6, Enum.EasingStyle.Quad), {
			CFrame = CFrame.lookAt(eye.Position, target.Position),
		}):Play()
	end
	Lib.PlaySound("UI")
	buildCards()
	backToBrowse()
end

function Build.Exit()
	if not State.BuildMode then
		return
	end
	State.BuildMode = false
	backToBrowse()
	screen.Visible = false
	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = if savedCameraType == Enum.CameraType.Scriptable then Enum.CameraType.Custom else savedCameraType
	end
end

-- leave build mode if we walk out / start carrying / respawn
player.CharacterAdded:Connect(function()
	Build.Exit()
end)

local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < 0.3 then
		return
	end
	accumulator = 0
	local inside = insideMyPlot()
	local carrying = player:GetAttribute("Carrying") ~= nil
	entryButton.Visible = inside and not carrying and not State.BuildMode
	if State.BuildMode and (carrying or not myPlot()) then
		Build.Exit()
	end
end)

State.OnChanged(function()
	if State.BuildMode then
		refreshCatalog()
		if mode == "placing" then
			updateGhost()
		elseif mode == "selected" and selectedUid and not findItem(selectedUid) then
			backToBrowse()
		end
	end
end)

return Build
