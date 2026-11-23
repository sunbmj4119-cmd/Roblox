-- Does physics run in a Luau execution session? (drop a block, walk a humanoid)
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local out = {}
local floor = Instance.new("Part")
floor.Anchored = true
floor.Size = Vector3.new(200, 2, 200)
floor.CFrame = CFrame.new(0, -1, 500)
floor.Parent = workspace
local block = Instance.new("Part")
block.Size = Vector3.new(2, 2, 2)
block.CFrame = CFrame.new(0, 40, 500)
block.Parent = workspace
local steps = 0
local conn = RunService.Heartbeat:Connect(function()
	steps += 1
end)
local t0 = os.clock()
task.wait(2)
out.heartbeats = steps
out.waited = math.floor((os.clock() - t0) * 100) / 100
out.blockY = math.floor(block.Position.Y * 10) / 10
out.isRunning = RunService:IsRunning()
out.isServer = RunService:IsServer()
out.isStudio = RunService:IsStudio()
conn:Disconnect()
return HttpService:JSONEncode(out)
