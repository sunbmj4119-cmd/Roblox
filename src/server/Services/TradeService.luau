--[[
	TradeService: swap pets with another player in the same server.

	Flow: request -> the other player accepts -> both pick up to MaxPets pets
	-> both press Ready -> 3 second countdown -> swap.
	Safety: every change resets both Ready flags (no bait-and-switch), the
	server re-checks ownership at the moment of the swap, pets being stolen
	can't be traded, and the swap happens all at once (both sides or none).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Net = require(script.Parent.Net)

local Trade = {}
local Services
local Data

local SETTINGS = { MaxPets = 4, Countdown = 3, RequestSeconds = 20 }
Trade.Settings = SETTINGS

local requests = {} -- [target] = { From = player, Expires = os.clock() }
local trades = {} -- [player] = session (both players point to the same session)

local function other(session, player: Player): Player
	return if session.A == player then session.B else session.A
end

local function petInfo(data, petId)
	for _, pet in data.Pets do
		if pet.Id == petId then
			return pet
		end
	end
	return nil
end

-- what each client sees: both offers (names so the other side can render them)
local function sendState(session)
	for _, player in { session.A, session.B } do
		local partner = other(session, player)
		local function describe(who: Player)
			local data = Data:Get(who)
			local list = {}
			for _, petId in session.Offers[who] do
				local pet = data and petInfo(data, petId)
				if pet then
					table.insert(list, {
						Id = pet.Id,
						Name = pet.Name,
						Variant = pet.Variant,
						Serial = pet.Serial,
						Level = pet.Level,
						Stars = pet.Stars,
					})
				end
			end
			return list
		end
		Net:Send(player, "TradeState", {
			Partner = partner.DisplayName,
			Mine = describe(player),
			Theirs = describe(partner),
			MyReady = session.Ready[player] == true,
			TheirReady = session.Ready[partner] == true,
			Countdown = session.CountdownEnds,
		})
	end
end

local function close(session, reason: string?)
	for _, player in { session.A, session.B } do
		if trades[player] == session then
			trades[player] = nil
			if player.Parent then
				Net:Send(player, "TradeClosed", if reason then Net:L(player, reason) else nil)
			end
		end
	end
	session.Closed = true
end

local function resetReady(session)
	session.Ready = {}
	session.CountdownEnds = nil
end

-- validate + swap atomically
local function complete(session)
	local a, b = session.A, session.B
	local dataA, dataB = Data:Get(a), Data:Get(b)
	if not dataA or not dataB then
		close(session, "Trade cancelled.")
		return
	end
	local shards = Services.ShardService
	if shards:IsCarrying(a) or shards:IsCarrying(b) then
		close(session, "Trade cancelled - someone is carrying something.")
		return
	end
	local function collect(data, ids)
		local list = {}
		for _, petId in ids do
			local pet = petInfo(data, petId)
			if not pet or pet.Away or pet.SerialPending then
				return nil
			end
			-- both sides must be allowed to trade paid items
			if
				Util.IsExclusive(Config, pet)
				and not (a:GetAttribute("PaidTradeAllowed") == true and b:GetAttribute("PaidTradeAllowed") == true)
			then
				return nil
			end
			table.insert(list, pet)
		end
		return list
	end
	local giveA = collect(dataA, session.Offers[a])
	local giveB = collect(dataB, session.Offers[b])
	if not giveA or not giveB then
		close(session, "Trade cancelled - a pet is no longer available.")
		return
	end
	if #dataA.Pets - #giveA + #giveB > Config.MaxPets or #dataB.Pets - #giveB + #giveA > Config.MaxPets then
		close(session, "Trade cancelled - not enough pet storage.")
		return
	end
	-- remove from both, then add to both (all checks passed above)
	local function remove(data, pets)
		for _, pet in pets do
			local index = table.find(data.Pets, pet)
			if index then
				table.remove(data.Pets, index)
			end
		end
	end
	local function add(data, pets)
		for _, pet in pets do
			local copy = {
				Id = data.NextPetUid,
				Name = pet.Name,
				Variant = pet.Variant,
				Serial = pet.Serial,
				Level = pet.Level,
				XP = pet.XP,
				Stars = pet.Stars,
			}
			data.NextPetUid += 1
			table.insert(data.Pets, copy)
			data.PetIndex[pet.Name] = true
		end
	end
	remove(dataA, giveA)
	remove(dataB, giveB)
	add(dataA, giveB)
	add(dataB, giveA)
	Services.PetService:Changed(a)
	Services.PetService:Changed(b)
	Services.Analytics:Custom(a, "Trade", #giveA + #giveB)
	Services.Analytics:Custom(b, "Trade", #giveA + #giveB)
	-- save both right away so a crash can't duplicate or lose pets
	task.spawn(Data.Save, Data, a)
	task.spawn(Data.Save, Data, b)
	for _, player in { a, b } do
		Net:Send(player, "TradeDone", other(session, player).DisplayName)
	end
	close(session, nil)
end

-- cloud tests only: open a trade between two stand-in players
function Trade:BeginForTest(a: any, b: any)
	assert(not game:GetService("RunService"):IsRunning(), "test hook used on a live server")
	local session = { A = a, B = b, Offers = { [a] = {}, [b] = {} }, Ready = {} }
	trades[a] = session
	trades[b] = session
	return session
end

function Trade:IsTrading(player: Player): boolean
	return trades[player] ~= nil
end

function Trade:Init(services)
	Services = services
	Data = services.DataService
end

function Trade:Start()
	Net:On("TradeRequest", 3, function(player, targetUserId)
		local target = type(targetUserId) == "number" and Players:GetPlayerByUserId(targetUserId)
		if not target or target == player or not Data:Get(player) or not Data:Get(target) then
			return
		end
		if trades[player] or trades[target] then
			Net:Notify(player, "That player is busy trading.")
			return
		end
		requests[target] = { From = player, Expires = os.clock() + SETTINGS.RequestSeconds }
		Net:Send(target, "TradeRequested", player.UserId, player.DisplayName)
		Net:Notify(player, "🤝 Trade request sent to %s", Color3.fromRGB(150, 230, 255), target.DisplayName)
	end)

	Net:On("TradeRespond", 1, function(player, accept)
		local request = requests[player]
		requests[player] = nil
		if not request or os.clock() > request.Expires then
			return
		end
		local from = request.From
		if not accept then
			Net:Notify(from, "%s declined the trade.", nil, player.DisplayName)
			return
		end
		if not from.Parent or trades[from] or trades[player] then
			Net:Notify(player, "That player is busy trading.")
			return
		end
		local session = { A = from, B = player, Offers = { [from] = {}, [player] = {} }, Ready = {} }
		trades[from] = session
		trades[player] = session
		sendState(session)
	end)

	Net:On("TradeSetOffer", 0.2, function(player, petIds)
		local session = trades[player]
		local data = Data:Get(player)
		if not session or not data or type(petIds) ~= "table" or #petIds > SETTINGS.MaxPets then
			return
		end
		local clean, seen = {}, {}
		for i = 1, #petIds do
			local petId = petIds[i]
			if type(petId) == "number" and not seen[petId] and #clean < SETTINGS.MaxPets then
				local pet = petInfo(data, petId)
				-- exclusive (Robux) pets can't be traded where Roblox restricts paid item trading
				local blocked = Util.IsExclusive(Config, pet) and player:GetAttribute("PaidTradeAllowed") ~= true
				if pet and not pet.Away and not pet.SerialPending and not blocked then
					seen[petId] = true
					table.insert(clean, petId)
				elseif pet and blocked then
					Net:Notify(player, "💎 Exclusive pets can't be traded in your region.")
				end
			end
		end
		session.Offers[player] = clean
		resetReady(session) -- any change: both have to confirm again
		sendState(session)
	end)

	Net:On("TradeReady", 0.3, function(player, ready)
		local session = trades[player]
		if not session then
			return
		end
		session.Ready[player] = ready == true
		if session.Ready[session.A] and session.Ready[session.B] then
			session.CountdownEnds = workspace:GetServerTimeNow() + SETTINGS.Countdown
			local token = {}
			session.Token = token
			sendState(session)
			task.delay(SETTINGS.Countdown, function()
				if not session.Closed and session.Token == token and session.Ready[session.A] and session.Ready[session.B] then
					complete(session)
				end
			end)
		else
			session.CountdownEnds = nil
			sendState(session)
		end
	end)

	Net:On("TradeCancel", 0.3, function(player)
		local session = trades[player]
		if session then
			close(session, "Trade cancelled.")
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		requests[player] = nil
		local session = trades[player]
		if session then
			close(session, "The other player left.")
		end
	end)
end

return Trade
