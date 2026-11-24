--[[
	Local world state: zone gates open only for players who unlocked them,
	and chat tags ([VIP], [CLUB], weekly titles) via TextChatService.
]]
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local Client = script.Parent.Parent
local State = require(Client.State)

local player = Players.LocalPlayer

local function gatesFolder()
	local map = workspace:FindFirstChild("Map")
	return map and map:FindFirstChild("Gates")
end

local function refreshGates()
	local data = State.Data
	local folder = gatesFolder()
	if not data or not folder then
		return
	end
	for _, gate in folder:GetChildren() do
		if gate:IsA("BasePart") then
			local index = gate:GetAttribute("ZoneIndex") or 99
			local open = data.ZoneLevel >= index
			gate.CanCollide = not open
			gate.Transparency = if open then 1 else 0.1
			local label = gate:FindFirstChild("Label")
			if label and label:IsA("BillboardGui") then
				label.Enabled = not open
			end
			local prompt = gate:FindFirstChildOfClass("ProximityPrompt")
			if prompt then
				prompt.Enabled = not open and data.ZoneLevel + 1 == index
			end
		end
	end
end

State.OnChanged(refreshGates)
task.spawn(function()
	local map = workspace:WaitForChild("Map", 30)
	local folder = map and map:WaitForChild("Gates", 30)
	if folder then
		folder.ChildAdded:Connect(refreshGates)
		refreshGates()
	end
end)

-- world text translation -----------------------------------------------------
-- Server-built signs carry LangFmt (+ JSON LangArgs); render them in OUR language.
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lang = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Lang"))

local function applyLabel(label: TextLabel)
	local fmt = label:GetAttribute("LangFmt")
	if type(fmt) ~= "string" then
		return
	end
	local args = {}
	local raw = label:GetAttribute("LangArgs")
	if type(raw) == "string" and raw ~= "" then
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
		if ok and type(decoded) == "table" then
			args = decoded
		end
	end
	local text = Lang.T(fmt, table.unpack(args))
	if label.Text ~= text then
		label.Text = text
	end
end

local function hook(inst: Instance)
	if inst:IsA("TextLabel") then
		applyLabel(inst)
		inst:GetAttributeChangedSignal("LangFmt"):Connect(function()
			applyLabel(inst)
		end)
		inst:GetAttributeChangedSignal("LangArgs"):Connect(function()
			applyLabel(inst)
		end)
		inst:GetPropertyChangedSignal("Text"):Connect(function()
			task.defer(applyLabel, inst)
		end)
	elseif inst:IsA("ProximityPrompt") then
		inst.ActionText = Lang.T(inst.ActionText)
		inst.ObjectText = Lang.T(inst.ObjectText)
	end
end

-- overhead tags (titles) live on characters, not in the map
local Players = game:GetService("Players")
local function hookCharacter(character: Model)
	for _, d in character:GetDescendants() do
		hook(d)
	end
	character.DescendantAdded:Connect(hook)
end
local function hookPlayer(other: Player)
	other.CharacterAdded:Connect(hookCharacter)
	if other.Character then
		hookCharacter(other.Character)
	end
end
Players.PlayerAdded:Connect(hookPlayer)
for _, other in Players:GetPlayers() do
	hookPlayer(other)
end

task.spawn(function()
	local map = workspace:WaitForChild("Map", 60)
	if not map then
		return
	end
	map.DescendantAdded:Connect(hook)
	for _, inst in map:GetDescendants() do
		hook(inst)
	end
end)

-- chat tags ----------------------------------------------------------------
TextChatService.OnIncomingMessage = function(message: TextChatMessage)
	local props = Instance.new("TextChatMessageProperties")
	local source = message.TextSource
	if source then
		local speaker = Players:GetPlayerByUserId(source.UserId)
		if speaker then
			local tags = {}
			local title = speaker:GetAttribute("Title")
			if type(title) == "string" and title ~= "" then
				table.insert(tags, "<font color='#FFD84A'>[" .. title .. "]</font>")
			end
			if speaker:GetAttribute("VIP") then
				table.insert(tags, "<font color='#FFC93C'>[VIP]</font>")
			end
			if speaker:GetAttribute("Club") then
				table.insert(tags, "<font color='#5CF2FF'>[CLUB]</font>")
			end
			if #tags > 0 then
				props.PrefixText = table.concat(tags, " ") .. " " .. message.PrefixText
			end
		end
	end
	return props
end

player:GetAttributeChangedSignal("DataLoaded"):Connect(refreshGates)

return {}
