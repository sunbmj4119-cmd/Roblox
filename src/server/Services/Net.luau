--[[
	Networking: one RemoteEvent for client->server actions, one RemoteFunction
	for requests that need a reply, one RemoteEvent for server->client messages.
	Every action is rate limited per player and wrapped in pcall.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}

local folder = Instance.new("Folder")
folder.Name = "Remotes"

local actionRemote = Instance.new("RemoteEvent")
actionRemote.Name = "Action"
actionRemote.Parent = folder

local requestRemote = Instance.new("RemoteFunction")
requestRemote.Name = "Request"
requestRemote.Parent = folder

local messageRemote = Instance.new("RemoteEvent")
messageRemote.Name = "Message"
messageRemote.Parent = folder

folder.Parent = ReplicatedStorage

local actionHandlers = {}
local requestHandlers = {}
local lastCall = {} -- [player] = { [name] = os.clock() }

local function allowed(player, name, minInterval)
	local calls = lastCall[player]
	if not calls then
		calls = {}
		lastCall[player] = calls
	end
	local now = os.clock()
	local last = calls[name]
	if last and now - last < minInterval then
		return false
	end
	calls[name] = now
	return true
end

function Net:On(name: string, minInterval: number, handler)
	actionHandlers[name] = { Interval = minInterval, Fn = handler }
end

function Net:OnRequest(name: string, minInterval: number, handler)
	requestHandlers[name] = { Interval = minInterval, Fn = handler }
end

function Net:Send(player: Player, kind: string, ...)
	if player and player.Parent then
		messageRemote:FireClient(player, kind, ...)
	end
end

function Net:Broadcast(kind: string, ...)
	messageRemote:FireAllClients(kind, ...)
end

function Net:Notify(player: Player, text: string, color: Color3?)
	self:Send(player, "Notify", text, color)
end

function Net:Announce(text: string, color: Color3?)
	self:Broadcast("Announce", text, color)
end

actionRemote.OnServerEvent:Connect(function(player, name, ...)
	if type(name) ~= "string" then
		return
	end
	local handler = actionHandlers[name]
	if not handler or not allowed(player, name, handler.Interval) then
		return
	end
	local ok, err = pcall(handler.Fn, player, ...)
	if not ok then
		warn(string.format("[Net] action %s from %s failed: %s", name, player.Name, tostring(err)))
	end
end)

requestRemote.OnServerInvoke = function(player, name, ...)
	if type(name) ~= "string" then
		return nil
	end
	local handler = requestHandlers[name]
	if not handler or not allowed(player, "req_" .. name, handler.Interval) then
		return nil
	end
	local results = table.pack(pcall(handler.Fn, player, ...))
	if not results[1] then
		warn(string.format("[Net] request %s from %s failed: %s", name, player.Name, tostring(results[2])))
		return nil
	end
	return table.unpack(results, 2, results.n)
end

Players.PlayerRemoving:Connect(function(player)
	lastCall[player] = nil
end)

return Net
