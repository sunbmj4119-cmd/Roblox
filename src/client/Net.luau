local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local action = remotes:WaitForChild("Action") :: RemoteEvent
local request = remotes:WaitForChild("Request") :: RemoteFunction
local message = remotes:WaitForChild("Message") :: RemoteEvent

local Net = {}
local handlers = {}

message.OnClientEvent:Connect(function(kind, ...)
	local list = handlers[kind]
	if list then
		for _, fn in list do
			task.spawn(fn, ...)
		end
	end
end)

function Net.Fire(name: string, ...)
	action:FireServer(name, ...)
end

function Net.Invoke(name: string, ...)
	local results = table.pack(pcall(request.InvokeServer, request, name, ...))
	if not results[1] then
		warn("[Net] request failed: " .. tostring(results[2]))
		return nil
	end
	return table.unpack(results, 2, results.n)
end

function Net.On(kind: string, fn)
	handlers[kind] = handlers[kind] or {}
	table.insert(handlers[kind], fn)
end

return Net
