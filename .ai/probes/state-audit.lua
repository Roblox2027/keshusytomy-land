local function count(root)
	if root == nil then return -1 end
	local n = 0
	for _, d in ipairs(root:GetDescendants()) do
		n = n + 1
	end
	return n
end

local s = {}
for _, r in ipairs({ "Workspace", "ReplicatedStorage", "ServerScriptService", "StarterGui", "StarterPlayer", "ServerStorage", "Lighting", "SoundService" }) do
	s[r] = count(game:GetService(r))
end

local w = game:GetService("Workspace")
s.Worlds = count(w:FindFirstChild("Worlds"))
s.Lobby = count(w:FindFirstChild("Lobby"))
s.LobbyChildren = {}
local lobby = w:FindFirstChild("Lobby")
if lobby then
	for _, c in ipairs(lobby:GetChildren()) do
		table.insert(s.LobbyChildren, c.Name)
	end
end

s.WorldChildren = {}
local worlds = w:FindFirstChild("Worlds")
if worlds then
	for _, wd in ipairs(worlds:GetChildren()) do
		table.insert(s.WorldChildren, wd.Name .. "=" .. count(wd))
	end
end

s.players = #game:GetService("Players"):GetPlayers()

-- Lighting
local L = game:GetService("Lighting")
s.lightingChildren = {}
for _, c in ipairs(L:GetChildren()) do
	table.insert(s.lightingChildren, c.Name .. "[" .. c.ClassName .. "]")
end

return s