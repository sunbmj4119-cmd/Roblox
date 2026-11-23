-- Cloud smoke test: does the server boot and build the world?
local HttpService = game:GetService("HttpService")
local out = {}
local map = workspace:WaitForChild("Map", 20)
out.mapBuilt = map ~= nil
out.serverScripts = game:GetService("ServerScriptService"):FindFirstChild("Server") ~= nil
if map then
	task.wait(3)
	local function count(name)
		local f = map:FindFirstChild(name)
		return f and #f:GetChildren() or -1
	end
	out.ores = count("Ores")
	out.plots = count("Bases")
	out.gates = count("Gates")
	local pads = 0
	for _, d in map:GetDescendants() do
		if d.Name == "SpeedPad" then
			pads += 1
		end
	end
	out.speedPads = pads
	local plot = map.Bases:FindFirstChild("Plot_1")
	out.plot1Sign = plot and plot:FindFirstChild("SignAnchor") and plot.SignAnchor.Label.Text.Text or "?"
end
out.meteorState = workspace:GetAttribute("MeteorState")
return HttpService:JSONEncode(out)
