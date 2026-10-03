-- explosion-reach.lua
-- Que partes cae REALMENTE dentro del radio de una bomba colocada junto al
-- personaje. Solo lectura.
--
-- POR QUE: "la bomba exploto" y "la bomba destruyo bloques" son dos hechos
-- distintos. Si la explosion resuelve cero partes, el problema no esta en la
-- destruccion sino en que el mapa no tiene nada donde el radio llega.
local Players = game:GetService("Players")
local Destruction = require(game.ServerScriptService.Services.DestructionService)
local GC = require(game.ReplicatedStorage.Shared.Config.GameConfig)

local p = Players:GetPlayers()[1]
if not p then return "no hay jugadores" end

local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
if not root then return "sin personaje" end

local center = root.Position + Vector3.new(0, 0, -8)

-- Se repiten EXACTAMENTE los parametros que usa ExplosionService: si esta
-- sonda usara otros, mediria una explosion que el juego nunca hace.
local q = OverlapParams.new()
q.FilterType = Enum.RaycastFilterType.Include
q.FilterDescendantsInstances = { workspace }
q.RespectCanCollide = true

local near = workspace:GetPartBoundsInRadius(center, GC.DefaultBombRadius, q)
local nombres = {}
local conNombreDeBloque = 0
for _, part in ipairs(near) do
	nombres[#nombres+1] = part.Name
	if string.sub(part.Name, 1, 6) == "Block_" then
		conNombreDeBloque += 1
	end
end
table.sort(nombres)

local bscale = GC.DefaultBombDamage * GC.BlockDamageScale

return {
	centro = string.format("(%.0f,%.0f,%.0f)", center.X, center.Y, center.Z),
	radio = GC.DefaultBombRadius,
	partesEnRadio = #near,
	bloquesEnRadio = conNombreDeBloque,
	nombres = table.concat(nombres, ","),
	danoEscalaBloque = bscale,
	vidaBloque = GC.BlockHealth,
	bombasNecesariasPorBloque = math.ceil(GC.BlockHealth / math.max(bscale, 0.001)),
	bloquesVivos = Destruction.GetAliveBlockCount(),
}