--[[
	Root ScreenGui + screen "clusters" anchored to corners. Each cluster has
	its own UIScale so the UI fits phones, tablets and PCs.
]]
local Players = game:GetService("Players")

local Lib = require(script.Parent.Lib)

local player = Players.LocalPlayer
local Root = {}

Root.Gui = Lib.New("ScreenGui", {
	Name = "MeteorMinersUI",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	IgnoreGuiInset = false,
	DisplayOrder = 5,
	Parent = player:WaitForChild("PlayerGui"),
})

Root.Overlay = Lib.New("ScreenGui", {
	Name = "MeteorMinersOverlay",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	IgnoreGuiInset = true,
	DisplayOrder = 20,
	Parent = player:WaitForChild("PlayerGui"),
})

local scales = {}

function Root.Scale(): number
	local camera = workspace.CurrentCamera
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 760)
	return math.clamp(math.min(size.X / 1280, size.Y / 760), 0.55, 1.15)
end

local function applyScales()
	local s = Root.Scale()
	for _, scale in scales do
		scale.Scale = s
	end
end

function Root.Cluster(name: string, anchor: Vector2, position: UDim2, size: UDim2, parent: Instance?)
	local frame = Lib.New("Frame", {
		Name = name,
		AnchorPoint = anchor,
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		Parent = parent or Root.Gui,
	})
	local scale = Lib.New("UIScale", { Parent = frame })
	table.insert(scales, scale)
	applyScales()
	return frame
end

local function hookCamera()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyScales)
	end
	applyScales()
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hookCamera)
hookCamera()

return Root
