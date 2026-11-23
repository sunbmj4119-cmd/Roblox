--[[
	LeaderboardService: global OrderedDataStore boards rendered on giant
	signs in the hub (Weekly ranked / Richest / Most rebirths).
	The weekly board resets every Monday (new store key per week); the global
	top 10 get gem rewards and in-server crown titles.
]]
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)

local Leaderboards = {}
local Services
local Data

local MAX_VALUE = 2 ^ 53
local nameCache = {}
local storeCache = {}
local placementCache = {} -- [week] = { [userId] = place }
local currentTop = {} -- [boardKey] = entries

local function getStore(name: string)
	if storeCache[name] == nil then
		local ok, store = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, Config.LeaderboardPrefix .. name)
		storeCache[name] = if ok then store else false
	end
	return storeCache[name] or nil
end

local function storeFor(board, week: number?)
	if board.Weekly then
		return getStore("Weekly_" .. (week or Util.WeekNumber()))
	end
	return getStore(board.Key)
end

local function valueFor(key: string, data): number
	if key == "Weekly" then
		return data.Weekly.Points
	elseif key == "LifetimeCoins" then
		return data.Stats.LifetimeCoins
	elseif key == "Rebirths" then
		return data.Rebirths
	elseif key == "Likes" then
		return data.Base and data.Base.Likes or 0
	end
	return 0
end

local function formatValue(key: string, value: number): string
	if key == "Weekly" then
		return Util.Comma(value) .. " pts"
	elseif key == "Likes" then
		return "❤️ " .. Util.Comma(value)
	end
	return Util.Format(value)
end

local function nameFor(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		nameCache[userId] = player.Name
		return player.Name
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	if ok and name then
		nameCache[userId] = name
		return name
	end
	return "Player"
end

local function buildBoardGui(part: BasePart)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Board"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 25
	gui.LightInfluence = 0
	gui.Parent = part

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Color3.fromRGB(20, 20, 32)
	root.BorderSizePixel = 0
	root.Parent = gui

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 16)
	padding.PaddingRight = UDim.new(0, 16)
	padding.PaddingTop = UDim.new(0, 10)
	padding.Parent = root

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0.13, 0)
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 215, 80)
	Services.WorldService.SetText(title, part:GetAttribute("Title") or "LEADERBOARD")
	title.Parent = root

	local sub = Instance.new("TextLabel")
	sub.Name = "Sub"
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.fromScale(0, 0.13)
	sub.Size = UDim2.new(1, 0, 0.06, 0)
	sub.Font = Enum.Font.GothamBold
	sub.TextScaled = true
	sub.TextColor3 = Color3.fromRGB(180, 180, 200)
	sub.Text = ""
	sub.Parent = root

	local list = Instance.new("Frame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromScale(0, 0.21)
	list.Size = UDim2.fromScale(1, 0.77)
	list.Parent = root
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 3)
	layout.Parent = list

	for i = 1, 10 do
		local row = Instance.new("Frame")
		row.Name = "Row" .. i
		row.LayoutOrder = i
		row.Size = UDim2.new(1, 0, 0.097, 0)
		row.BackgroundColor3 = if i % 2 == 0 then Color3.fromRGB(32, 32, 48) else Color3.fromRGB(40, 40, 60)
		row.BorderSizePixel = 0
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = row
		local color = if i == 1
			then Color3.fromRGB(255, 215, 60)
			elseif i == 2 then Color3.fromRGB(210, 220, 235)
			elseif i == 3 then Color3.fromRGB(230, 150, 80)
			else Color3.new(1, 1, 1)
		for _, spec in
			{
				{ "PlaceLabel", 0, 0.12, Enum.TextXAlignment.Center },
				{ "NameLabel", 0.13, 0.55, Enum.TextXAlignment.Left },
				{ "ValueLabel", 0.68, 0.31, Enum.TextXAlignment.Right },
			}
		do
			local label = Instance.new("TextLabel")
			label.Name = spec[1]
			label.BackgroundTransparency = 1
			label.Position = UDim2.fromScale(spec[2], 0.1)
			label.Size = UDim2.fromScale(spec[3], 0.8)
			label.Font = Enum.Font.FredokaOne
			label.TextScaled = true
			label.TextXAlignment = spec[4]
			label.TextColor3 = color
			label.Text = if spec[1] == "PlaceLabel" then "#" .. i else "-"
			label.Parent = row
		end
		row.Parent = list
	end
	return gui
end

local function render(board, entries)
	local part = Services.WorldService.Boards[board.Key]
	if not part then
		return
	end
	local gui = part:FindFirstChild("Board") or buildBoardGui(part)
	local root = gui:FindFirstChild("Root")
	local list = root:FindFirstChild("List")
	for i = 1, 10 do
		local row = list:FindFirstChild("Row" .. i)
		local entry = entries[i]
		local nameLabel = row:FindFirstChild("NameLabel") :: TextLabel
		local valueLabel = row:FindFirstChild("ValueLabel") :: TextLabel
		nameLabel.Text = if entry then nameFor(entry.UserId) else "-"
		valueLabel.Text = if entry then formatValue(board.Key, entry.Value) else ""
	end
	local sub = root:FindFirstChild("Sub") :: TextLabel
	if board.Weekly then
		Services.WorldService.SetText(sub, "Resets in %s • Top 10 win gems!", Util.FormatTime(Util.SecondsUntilNextWeek()))
	else
		Services.WorldService.SetText(sub, "All-time • Global")
	end
end

local function localEntries(key: string)
	local entries = {}
	for _, player in Data:LoadedPlayers() do
		local data = Data:Get(player)
		if data then
			table.insert(entries, { UserId = player.UserId, Value = math.floor(valueFor(key, data)) })
		end
	end
	table.sort(entries, function(a, b)
		return a.Value > b.Value
	end)
	return entries
end

local function fetchTop(store)
	local ok, pages = pcall(store.GetSortedAsync, store, false, 10)
	if not ok then
		return nil
	end
	local entries = {}
	for _, item in pages:GetCurrentPage() do
		table.insert(entries, { UserId = tonumber(item.key) or 0, Value = item.value })
	end
	return entries
end

local function updateTitles()
	local weekly = currentTop.Weekly or {}
	local titles = {}
	for place, entry in weekly do
		if place <= 3 then
			titles[entry.UserId] = ({ "👑 #1", "🥈 #2", "🥉 #3" })[place]
		elseif place <= 10 then
			titles[entry.UserId] = "⭐ TOP10"
		end
	end
	for _, player in Players:GetPlayers() do
		local title = titles[player.UserId] or ""
		if player:GetAttribute("Title") ~= title then
			player:SetAttribute("Title", title)
		end
	end
end

local function refresh()
	-- push scores of everyone in this server
	for _, player in Data:LoadedPlayers() do
		local data = Data:Get(player)
		-- owner test mode: DEV-panel coins must not pollute the global boards
		local skip = Config.OwnerTestMode and Util.IsOwner(player)
		if data and not skip then
			for _, board in Config.Leaderboards.Boards do
				-- weekly points always go to the week they were earned in, so a
				-- refresh right after Monday 00:00 can't leak last week's points
				local store = if board.Weekly
					then (if data.Weekly.Week ~= 0 then storeFor(board, data.Weekly.Week) else nil)
					else storeFor(board)
				local value = math.floor(math.min(valueFor(board.Key, data), MAX_VALUE))
				if store and value > 0 then
					pcall(store.SetAsync, store, tostring(player.UserId), value)
				end
			end
		end
		task.wait(0.1)
	end
	-- pull global tops
	for _, board in Config.Leaderboards.Boards do
		local store = storeFor(board)
		local entries = store and fetchTop(store)
		if not entries then
			entries = localEntries(board.Key)
		end
		currentTop[board.Key] = entries
		render(board, entries)
	end
	updateTitles()
end

-- Returns the final placement (1-10) of a user in a past week, or nil.
function Leaderboards:GetWeeklyPlacement(week: number, userId: number): number?
	if not placementCache[week] then
		local weeklyBoard
		for _, board in Config.Leaderboards.Boards do
			if board.Weekly then
				weeklyBoard = board
			end
		end
		local store = weeklyBoard and storeFor(weeklyBoard, week)
		local entries = store and fetchTop(store)
		local map = {}
		for place, entry in entries or {} do
			map[entry.UserId] = place
		end
		placementCache[week] = map
	end
	return placementCache[week][userId]
end

function Leaderboards:Init(services)
	Services = services
	Data = services.DataService
end

function Leaderboards:Start()
	for _, board in Config.Leaderboards.Boards do
		local part = Services.WorldService.Boards[board.Key]
		if part then
			buildBoardGui(part)
		end
	end
	task.spawn(function()
		task.wait(10)
		while true do
			local ok, err = pcall(refresh)
			if not ok then
				warn("[Leaderboards] refresh failed: " .. tostring(err))
			end
			task.wait(Config.Leaderboards.RefreshSeconds)
		end
	end)
end

return Leaderboards
