--[[
	Tiny UI toolkit: every screen in the game is built from code with these
	helpers, so there are no Studio-made GUIs to keep in sync.
]]
local Debris = game:GetService("Debris")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Lib = {}

Lib.Colors = {
	Panel = Color3.fromRGB(26, 28, 44),
	PanelLight = Color3.fromRGB(40, 43, 66),
	Card = Color3.fromRGB(52, 56, 86),
	Text = Color3.fromRGB(255, 255, 255),
	Sub = Color3.fromRGB(185, 190, 215),
	Green = Color3.fromRGB(60, 205, 105),
	Blue = Color3.fromRGB(70, 150, 255),
	Purple = Color3.fromRGB(150, 90, 255),
	Gold = Color3.fromRGB(255, 190, 45),
	Red = Color3.fromRGB(235, 75, 90),
	Pink = Color3.fromRGB(255, 90, 200),
	Cyan = Color3.fromRGB(50, 215, 255),
	Gray = Color3.fromRGB(105, 108, 130),
	Coins = Color3.fromRGB(255, 205, 60),
	Gems = Color3.fromRGB(80, 220, 255),
	Stardust = Color3.fromRGB(255, 120, 230),
	Robux = Color3.fromRGB(110, 255, 140),
}
Lib.Font = Enum.Font.FredokaOne
Lib.BodyFont = Enum.Font.GothamBold

function Lib.New(className: string, props: { [string]: any }?, children: { Instance }?)
	local inst = Instance.new(className)
	local parent = nil
	for key, value in props or {} do
		if key == "Parent" then
			parent = value
		else
			(inst :: any)[key] = value
		end
	end
	for _, child in children or {} do
		child.Parent = inst
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end
local New = Lib.New

function Lib.Corner(radius: number?)
	return New("UICorner", { CornerRadius = UDim.new(0, radius or 12) })
end

function Lib.Stroke(color: Color3?, thickness: number?, transparency: number?)
	return New("UIStroke", {
		Color = color or Color3.new(0, 0, 0),
		Thickness = thickness or 2,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Lib.Padding(px: number)
	return New("UIPadding", {
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
	})
end

function Lib.List(direction: Enum.FillDirection?, padding: number?, hAlign: Enum.HorizontalAlignment?, vAlign: Enum.VerticalAlignment?)
	return New("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding or 6),
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Center,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

function Lib.Grid(cell: UDim2, padding: number?)
	return New("UIGridLayout", {
		CellSize = cell,
		CellPadding = UDim2.fromOffset(padding or 8, padding or 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	})
end

function Lib.Gradient(top: Color3, bottom: Color3)
	return New("UIGradient", {
		Color = ColorSequence.new(top, bottom),
		Rotation = 90,
	})
end

-- TextLabel with outline and sane defaults
function Lib.Text(props)
	local maxSize = props.MaxTextSize or 28
	props.MaxTextSize = nil
	local label = New("TextLabel", {
		BackgroundTransparency = 1,
		Font = props.Font or Lib.Font,
		TextColor3 = props.TextColor3 or Lib.Colors.Text,
		TextScaled = true,
		RichText = true,
		Size = props.Size or UDim2.new(1, 0, 0, 24),
	})
	for key, value in props do
		if key ~= "Parent" and key ~= "Outline" then
			(label :: any)[key] = value
		end
	end
	New("UITextSizeConstraint", { MaxTextSize = maxSize, MinTextSize = 8, Parent = label })
	if props.Outline ~= false then
		New("UIStroke", { Thickness = 1.5, Color = Color3.new(0, 0, 0), Transparency = 0.2, Parent = label })
	end
	if props.Parent then
		label.Parent = props.Parent
	end
	return label
end

function Lib.PlaySound(id: string?, volume: number?)
	if not id or id == "" then
		return
	end
	local sound = New("Sound", { SoundId = id, Volume = volume or 0.5, Parent = SoundService })
	sound:Play()
	Debris:AddItem(sound, 3)
end

-- Big chunky game button. props.Color, props.Text, props.OnClick
function Lib.Button(props)
	local color = props.Color or Lib.Colors.Green
	local button = New("TextButton", {
		Name = props.Name or "Button",
		AutoButtonColor = false,
		BackgroundColor3 = color,
		Size = props.Size or UDim2.fromOffset(140, 44),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		Text = "",
		ZIndex = props.ZIndex or 1,
		Parent = props.Parent,
	}, {
		Lib.Corner(props.Radius or 12),
		Lib.Stroke(Color3.new(0, 0, 0), 2, 0.35),
		Lib.Gradient(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190)),
	})
	local label = Lib.Text({
		Name = "Label",
		Text = props.Text or "",
		Size = UDim2.new(1, -10, 1, -6),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = props.TextSize or 24,
		ZIndex = (props.ZIndex or 1) + 1,
		Parent = button,
	})
	local scale = New("UIScale", { Parent = button })
	button.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1.05 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1 }):Play()
	end)
	button.Activated:Connect(function()
		scale.Scale = 0.92
		TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		Lib.PlaySound(Config.Sounds.UI, 0.35)
		if props.OnClick then
			props.OnClick()
		end
	end)
	return button, label
end

function Lib.SetButton(button: TextButton, text: string?, color: Color3?)
	if text then
		(button:FindFirstChild("Label") :: TextLabel).Text = text
	end
	if color then
		button.BackgroundColor3 = color
	end
end

-- Progress bar: returns frame and setter(ratio, text?)
function Lib.Bar(props)
	local back = New("Frame", {
		Name = props.Name or "Bar",
		BackgroundColor3 = props.Back or Color3.fromRGB(20, 20, 30),
		Size = props.Size or UDim2.new(1, 0, 0, 20),
		Position = props.Position or UDim2.new(),
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	}, {
		Lib.Corner(props.Radius or 10),
		Lib.Stroke(Color3.new(0, 0, 0), 2, 0.3),
	})
	local fill = New("Frame", {
		Name = "Fill",
		BackgroundColor3 = props.Color or Lib.Colors.Green,
		Size = UDim2.fromScale(0, 1),
		Parent = back,
	}, { Lib.Corner(props.Radius or 10), Lib.Gradient(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200)) })
	local label = Lib.Text({
		Name = "Label",
		Text = "",
		Size = UDim2.new(1, -8, 1, -2),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = props.TextSize or 18,
		ZIndex = 3,
		Parent = back,
	})
	local function set(ratio: number, text: string?, color: Color3?)
		fill.Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
		fill.Visible = ratio > 0.001
		if text then
			label.Text = text
		end
		if color then
			fill.BackgroundColor3 = color
		end
	end
	return back, set
end

function Lib.Scroll(props)
	local scroll = New("ScrollingFrame", {
		Name = props.Name or "Scroll",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position or UDim2.new(),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = props.Horizontal and Enum.AutomaticSize.X or Enum.AutomaticSize.Y,
		ScrollingDirection = props.Horizontal and Enum.ScrollingDirection.X or Enum.ScrollingDirection.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Color3.fromRGB(200, 200, 220),
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	})
	return scroll
end

function Lib.Clear(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

function Lib.Pop(gui: GuiObject)
	local scale = gui:FindFirstChildOfClass("UIScale") or New("UIScale", { Parent = gui })
	scale.Scale = 0.6
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- Real Robux prices (falls back to the suggested price in Config)
local priceCache = {}
function Lib.Price(kind: string, key: string): number
	local entry = if kind == "Pass" then Config.GamePasses[key] else Config.Products[key]
	if not entry then
		return 0
	end
	if entry.Id == 0 then
		return entry.Price
	end
	local cacheKey = kind .. key
	if priceCache[cacheKey] == nil then
		priceCache[cacheKey] = entry.Price
		task.spawn(function()
			local ok, info = pcall(
				MarketplaceService.GetProductInfo,
				MarketplaceService,
				entry.Id,
				if kind == "Pass" then Enum.InfoType.GamePass else Enum.InfoType.Product
			)
			if ok and info and info.PriceInRobux then
				priceCache[cacheKey] = info.PriceInRobux
			end
		end)
	end
	return priceCache[cacheKey]
end

return Lib
