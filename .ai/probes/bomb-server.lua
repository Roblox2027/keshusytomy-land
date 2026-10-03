-- Fuerza la ronda, LLEVA al jugador a la arena y coloca la bomba.
--
-- Por que todo junto: la ronda se acaba en cuanto se la fuerza, asi que los
-- tres pasos tienen que ocurrir en el mismo paso o el segundo ya mide "no hay
-- ronda". Y la bomba se RECHAZA fuera de la arena: sin mover al jugador al
-- mundo, `TryPlaceBomb` responde "fuera de la arena" y no crea ningun modelo.
-- Ese rechazo es CORRECTO: la validacion del servidor esta haciendo su
-- trabajo, no es un fallo de la bomba.
local Players = game:GetService("Players")
local services = game:GetService("ServerScriptService").Services
local roundService = require(services:WaitForChild("RoundService"))
local matchService = require(services:WaitForChild("MatchService"))
local bombService = require(services:WaitForChild("BombService"))

local player = Players:GetPlayers()[1]

if not player then
	return { error = "sin jugador" }
end

for _, estado in ipairs({ "Countdown", "RoundStarting", "Playing" }) do
	roundService.Transition(estado)
end

matchService.MovePlayer(player, "Arena_Forest")

local character = player.Character
local root = nil

if character then
	root = character:FindFirstChild("HumanoidRootPart")
end

local placed = false
local reason = "sin personaje"

if root then
	local ok, why = bombService.TryPlaceBomb(player, root.Position + Vector3.new(5, 0, 0))
	placed = ok == true
	reason = why or "colocada"
end

local models = {}

for _, child in ipairs(workspace.Bombs:GetChildren()) do
	if child:IsA("Model") then
		table.insert(models, child.Name .. " id=" .. tostring(child:GetAttribute("BombId"))
			.. " mundo=" .. tostring(child:GetAttribute("World"))
			.. " radio=" .. tostring(child:GetAttribute("VisualRadius"))
			.. " partes=" .. tostring(#child:GetChildren()))
	end
end

return {
	estado = roundService.GetState(),
	world = tostring(player:GetAttribute("World")),
	pos = if root then tostring(root.Position) else "NIL",
	placed = placed,
	reason = reason,
	models = models,
}