local P = game:GetService("Players")
local pl = P:GetPlayers()[1]
local out = {}
local pc = 0
for _ in P:GetPlayers() do
	pc += 1
end
out.playerCount = pc
if pl then
	local c = pl.Character
	out.player = pl.Name
	out.hasChar = c ~= nil
	if c then
		out.hp = c:FindFirstChildOfClass("Humanoid") and c.Humanoid.Health
		out.rootPos = c:FindFirstChild("HumanoidRootPart") and tostring(c.HumanoidRootPart.Position)
		out.walkSpeed = c:FindFirstChildOfClass("Humanoid") and c.Humanoid.WalkSpeed
	end
	local attrs = pl:GetAttributes()
	out.attrs = {}
	for k, v in pairs(attrs) do
		if type(v) == "number" or type(v) == "string" or type(v) == "boolean" then
			out.attrs[k] = v
		end
	end
end

local W = game:GetService("Workspace")
local worlds = W:FindFirstChild("Worlds")
out.worlds = {}
if worlds then
	for _, wd in ipairs(worlds:GetChildren()) do
		local counts = { MonsterSpawns = 0, PowerupSpawns = 0, Hazards = 0, Decoration = 0, Blocks = 0, Terrain = 0, Keshusy = 0, Border = 0 }
		for name in pairs(counts) do
			local f = wd:FindFirstChild(name)
			if f then
				counts[name] = #f:GetChildren()
			end
		end
		counts.bossSpawn = wd:FindFirstChild("BossSpawn_" .. wd.Name) ~= nil
		counts.exit = wd:FindFirstChild("Exit_" .. wd.Name) ~= nil
		counts.spawn = wd:FindFirstChild("SpawnPoint_" .. wd.Name) ~= nil
		out.worlds[wd.Name] = counts
	end
end

-- Monstruos vivos ahora
local monsters = 0
local monsterNames = {}
for _, d in ipairs(W:GetDescendants()) do
	if d:IsA("Model") and d:GetAttribute("IsMonster") then
		monsters += 1
		table.insert(monsterNames, d.Name)
	end
end
out.monsters = monsters
out.monsterNames = monsterNames

-- Bombas vivas
local bombs = 0
for _, d in ipairs(W:GetDescendants()) do
	if d:IsA("Model") and d:GetAttribute("IsBomb") then
		bombs += 1
	end
end
out.bombs = bombs

-- Portales: como se detectan
local lobby = W:FindFirstChild("Lobby")
out.portals = {}
local pfs = lobby and lobby:FindFirstChild("Portals")
if pfs then
	for _, c in ipairs(pfs:GetChildren()) do
		local prompts, touches = 0, 0
		for _, d in ipairs(c:GetDescendants()) do
			if d:IsA("ProximityPrompt") then
				prompts += 1
			end
			if d:IsA("ClickDetector") then
				touches += 1
			end
		end
		table.insert(out.portals, c.Name .. " prompts=" .. prompts .. " clicks=" .. touches .. " children=" .. #c:GetChildren())
	end
end

return out