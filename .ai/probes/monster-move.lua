-- Por que los monstruos NO se mueven: se mide la distancia real al jugador
-- y el estado de la ronda en el mismo instante en el que corre la IA.
local services = game:GetService("ServerScriptService").Services
local roundService = require(services:WaitForChild("RoundService"))
local matchService = require(services:WaitForChild("MatchService"))
local monsterService = require(services:WaitForChild("MonsterService"))

for _, estado in ipairs({ "Countdown", "RoundStarting", "Playing" }) do
	roundService.Transition(estado)
end

local jugador = game:GetService("Players"):GetPlayers()[1]
matchService.MovePlayer(jugador, "Arena_Forest")

local root = jugador.Character and jugador.Character:FindFirstChild("HumanoidRootPart")
local out = {
	estado = roundService.GetState(),
	isPlaying = roundService.IsPlaying(),
	jugador = if root then string.format("%.0f,%.0f", root.Position.X, root.Position.Z) else "NIL",
	vivos = monsterService.GetAliveCount(),
	antes = {},
}

for _, model in ipairs(workspace.Monsters:GetChildren()) do
	if model:IsA("Model") and model.PrimaryPart then
		local p = model.PrimaryPart.Position
		local d = if root then (p - root.Position).Magnitude else -1
		table.insert(out.antes, string.format("%s (%.0f,%.0f) dist=%.1f", model.Name, p.X, p.Z, d))
	end
end

task.wait(0.4)
out.despues = {}

for _, model in ipairs(workspace.Monsters:GetChildren()) do
	if model:IsA("Model") and model.PrimaryPart then
		local p = model.PrimaryPart.Position
		table.insert(out.despues, string.format("%s (%.0f,%.0f)", model.Name, p.X, p.Z))
	end
end

return out