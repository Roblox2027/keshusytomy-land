local Players = game:GetService("Players")
local out = {}
out.list = {}

for _, p in ipairs(Players:GetPlayers()) do
	local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	out.list[#out.list + 1] = p.Name .. " pos=" .. tostring(root and root.Position or "?")
		.. " world=" .. tostring(p:GetAttribute("World"))
end

out.localName = if Players.LocalPlayer then Players.LocalPlayer.Name else "NINGUNO"

local monsters = workspace:FindFirstChild("Monsters")
local powerups = workspace:FindFirstChild("Powerups")
out.monsters = if monsters then #monsters:GetChildren() else -1
out.powerups = if powerups then #powerups:GetChildren() else -1

return out