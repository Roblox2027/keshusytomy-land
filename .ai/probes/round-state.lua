-- Estado de la ronda y conteos, para saber si se puede colocar una bomba.
local out = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players:GetPlayers()[1]

out.roundState = if player then player:GetAttribute("RoundState") else "sin jugador"
out.world = if player then player:GetAttribute("World") else "-"
out.bombsAttr = if player then player:GetAttribute("Bombs") else "-"
out.alive = if player then player:GetAttribute("AliveCount") else "-"

local root = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
out.pos = if root then tostring(root.Position) else "NONE"

local monsterService = require(
	game:GetService("ServerScriptService").Services:WaitForChild("MonsterService")
)
local powerupService = require(
	game:GetService("ServerScriptService").Services:WaitForChild("PowerupService")
)

out.monsters = monsterService.GetAliveCount()
out.monstersAlive = (function()
	local folder = workspace:FindFirstChild("Monsters")
	return if folder then #folder:GetChildren() else -1
end)()

local puFolder = workspace:FindFirstChild("Powerups")
out.powerups = if puFolder then #puFolder:GetChildren() else -1
out.powerupServiceOk = powerupService ~= nil

return out