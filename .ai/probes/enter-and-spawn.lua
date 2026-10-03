-- Entrar al mundo y MEDIR dentro de la ronda, antes de que termine.
--
-- La ronda es corta: al terminar devuelve al jugador al lobby, asi que
-- medir "15 segundos despues" mide siempre el lobby y hace creer que el
-- teleport no llego al cliente.
local Players = game:GetService("Players")
local services = game:GetService("ServerScriptService").Services
local portalService = require(services:WaitForChild("PortalService"))
local matchService = require(services:WaitForChild("MatchService"))

local player = Players:GetPlayers()[1]

if not player then
	return { error = "sin jugador" }
end

local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
local portal = portalService.GetPortal("Forest")

if root and portal then
	root.CFrame = CFrame.new(portal.Position.X, portal.Position.Y + 1, portal.Position.Z + 2)
end

local ok, reason = portalService.TryEnter(player, "Forest")
local moved = if root then root.Position else Vector3.zero

local monsters = matchService.BuildMonsterSpawns()
local spawned = matchService.SpawnMonstersForRound("Forest")
local powerups = matchService.SpawnPowerupsForRound("Forest")

return {
	entered = ok,
	reason = reason,
	world = player:GetAttribute("World"),
	pos = tostring(moved),
	spawnPoints = #monsters,
	monsters = spawned,
	powerups = powerups,
	roundState = player:GetAttribute("RoundState"),
}