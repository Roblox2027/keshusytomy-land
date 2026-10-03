local Players = game:GetService("Players")
local player = Players:GetPlayers()[1]

if not player or not player.Character then
	return { error = "sin jugador" }
end

local root = player.Character:FindFirstChild("HumanoidRootPart")

if not root then
	return { error = "sin raiz" }
end

root.CFrame = CFrame.new(0, 5, -30)
return { moved = tostring(root.Position), player = player.Name }