--[[
	Client-side mirror of the player's data + server-computed multipliers.
]]
local State = {
	Data = nil,
	Derived = nil,
	ReceivedAt = 0,
}

local listeners = {}

function State.OnChanged(fn)
	table.insert(listeners, fn)
	if State.Data then
		task.spawn(fn)
	end
end

function State.Set(payload)
	if type(payload) ~= "table" then
		return
	end
	State.Data = payload.Data
	State.Derived = payload.Derived or {}
	State.ReceivedAt = os.clock()
	for _, fn in listeners do
		local ok, err = pcall(fn)
		if not ok then
			warn("[State] listener error: " .. tostring(err))
		end
	end
end

function State.Ready(): boolean
	return State.Data ~= nil
end

function State.Now(): number
	return workspace:GetServerTimeNow()
end

function State.HasPass(key: string): boolean
	local derived = State.Derived
	return derived ~= nil and derived.Passes ~= nil and derived.Passes[key] == true
end

-- remaining seconds of a personal boost, counted down locally between syncs
function State.BoostRemaining(key: string): number
	local data = State.Data
	if not data or not data.Boosts then
		return 0
	end
	local remaining = data.Boosts[key] or 0
	return math.max(0, remaining - (os.clock() - State.ReceivedAt))
end

return State
