--[[
	Panel manager: one modal window at a time. Each panel module returns
	{ Title, Color, Build(content, ctx) -> { Refresh(arg), OnOpen(arg) } }.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Lib = require(script.Parent.Lib)
local Root = require(script.Parent.Root)
local State = require(script.Parent.Parent.State)

local Panels = {}
Panels.Current = nil
Panels.CurrentArg = nil

local New = Lib.New
local C = Lib.Colors

-- dim backdrop: the HUD stays visible but clearly behind the panel; tap it to close
local backdrop = New("TextButton", {
	Name = "Backdrop",
	Text = "",
	AutoButtonColor = false,
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.45,
	Size = UDim2.fromScale(1, 1),
	Visible = false,
	ZIndex = 0,
	Parent = Root.PanelGui,
})
local cluster = Root.Cluster("Panels", Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.52), UDim2.fromOffset(700, 500), Root.PanelGui)
local registry = {}
local opened = {} -- [name] = { Window, Api }

local ctx = {
	Lib = Lib,
	State = State,
	Net = require(script.Parent.Parent.Net),
	Config = require(ReplicatedStorage.Shared.Config),
	Util = require(ReplicatedStorage.Shared.Util),
	Panels = Panels,
}

-- share other systems with panels (Upsell, Hatch, Toast)
function Panels.Provide(key: string, value: any)
	ctx[key] = value
end

local function makeWindow(name: string, def)
	local window = New("Frame", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Panel,
		Visible = false,
		Parent = cluster,
	}, {
		Lib.Corner(20),
		Lib.Stroke(Color3.new(0, 0, 0), 3, 0.2),
	})
	local header = New("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 58),
		BackgroundColor3 = def.Color or C.Blue,
		Parent = window,
	}, {
		Lib.Corner(20),
		Lib.Gradient(Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 170)),
	})
	-- square off the header's bottom corners
	New("Frame", {
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.new(0, 0, 1, -20),
		BackgroundColor3 = def.Color or C.Blue,
		BorderSizePixel = 0,
		Parent = header,
	}, { Lib.Gradient(Color3.fromRGB(205, 205, 205), Color3.fromRGB(170, 170, 170)) })
	Lib.Text({
		Name = "Title",
		Text = def.Title or name,
		Size = UDim2.new(1, -140, 0, 40),
		Position = UDim2.fromOffset(20, 9),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 34,
		ZIndex = 2,
		Parent = header,
	})
	Lib.Button({
		Name = "Close",
		Text = "X",
		Color = C.Red,
		Size = UDim2.fromOffset(46, 46),
		Position = UDim2.new(1, -54, 0, 6),
		ZIndex = 3,
		Parent = header,
		OnClick = function()
			Panels.Close()
		end,
	})
	local content = New("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 68),
		Size = UDim2.new(1, -28, 1, -80),
		Parent = window,
	})
	return window, content
end

function Panels.Register(name: string, def)
	registry[name] = def
end

local function ensure(name: string)
	if opened[name] then
		return opened[name]
	end
	local def = registry[name]
	if not def then
		return nil
	end
	local window, content = makeWindow(name, def)
	local ok, api = pcall(def.Build, content, ctx)
	if not ok then
		warn("[Panels] failed to build " .. name .. ": " .. tostring(api))
		api = {}
	end
	opened[name] = { Window = window, Api = api or {} }
	return opened[name]
end

function Panels.Open(name: string, arg: any?)
	if not State.Ready() then
		return
	end
	local entry = ensure(name)
	if not entry then
		return
	end
	if Panels.Current and Panels.Current ~= name and opened[Panels.Current] then
		opened[Panels.Current].Window.Visible = false
	end
	if Panels.Current ~= name then
		Lib.PlaySound("Open")
	end
	Panels.Current = name
	Panels.CurrentArg = arg
	backdrop.Visible = true
	entry.Window.Visible = true
	Lib.Pop(entry.Window)
	for _, hook in { "OnOpen", "Refresh" } do
		if entry.Api[hook] then
			local ok, err = pcall(entry.Api[hook], arg)
			if not ok then
				warn(string.format("[Panels] %s.%s failed: %s", name, hook, tostring(err)))
			end
		end
	end
end

function Panels.Close()
	local name = Panels.Current
	if name then
		Lib.PlaySound("Close")
	end
	if name and opened[name] then
		local window = opened[name].Window
		local scale = window:FindFirstChildOfClass("UIScale")
		if scale then
			local tween = TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 0.85 })
			tween:Play()
			tween.Completed:Once(function()
				if Panels.Current ~= name then
					window.Visible = false
				end
			end)
		else
			window.Visible = false
		end
	end
	Panels.Current = nil
	Panels.CurrentArg = nil
	backdrop.Visible = false
end

function Panels.Toggle(name: string, arg: any?)
	if Panels.Current == name then
		Panels.Close()
	else
		Panels.Open(name, arg)
	end
end

function Panels.RefreshCurrent()
	local name = Panels.Current
	local entry = name and opened[name]
	if entry and entry.Api.Refresh then
		local ok, err = pcall(entry.Api.Refresh, Panels.CurrentArg)
		if not ok then
			warn(string.format("[Panels] %s.Refresh failed: %s", name, tostring(err)))
		end
	end
end

backdrop.Activated:Connect(function()
	Panels.Close()
end)

State.OnChanged(Panels.RefreshCurrent)
task.spawn(function()
	while true do
		task.wait(1)
		local name = Panels.Current
		local entry = name and opened[name]
		if entry and entry.Api.Tick then
			pcall(entry.Api.Tick, Panels.CurrentArg)
		end
	end
end)

for _, module in script:GetChildren() do
	if module:IsA("ModuleScript") then
		local ok, def = pcall(require, module)
		if ok and type(def) == "table" then
			Panels.Register(def.Name or module.Name, def)
		else
			warn("[Panels] failed to load " .. module.Name .. ": " .. tostring(def))
		end
	end
end

return Panels
