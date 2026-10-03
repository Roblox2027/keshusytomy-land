-- after-bomb.lua
-- Aisla CAPA POR CAPA la destruccion, porque "la destruccion no funciona"
-- puede ser verdad en tres sitios distintos y hay que saber en cual:
--   1. la explosion resuelve la parte correcta?  (affected)
--   2. DestructionService tiene la referencia?   (_destruction ~= nil)
--   3. el dano llega al bloque?                 (la salud baja)
--
-- Se mide la vida de un bloque CONCRETO dentro del radio antes y despues de
-- llamar a `Detonate` directamente: asi no depende de ningun contador
-- derivado, que es donde las versiones anteriores de esta prueba se
-- equivocaban.
local Destruction = require(game.ServerScriptService.Services.DestructionService)
local Explosion = require(game.ServerScriptService.Services.ExplosionService)
local GC = require(game.ReplicatedStorage.Shared.Config.GameConfig)

-- Se repiten EXACTAMENTE los parametros que usa `ExplosionService`.
local q = OverlapParams.new()
q.FilterType = Enum.RaycastFilterType.Include
q.FilterDescendantsInstances = { workspace }
q.RespectCanCollide = true

local centro = Vector3.new(500, 3, -8)
local alcanzados = workspace:GetPartBoundsInRadius(centro, GC.DefaultBombRadius, q)

-- Si la arena esta vacia de bloques NO se intenta nada: la ronda pudo terminar
-- entre muestra y muestra y `MatchService` restauro el mapa. En ese caso la
-- respuesta lo dice, para que un FAIL se lea como "no habia nada que medir" y
-- no como "la destruccion esta rota".
local enRadio = 0
local objetivo
for _, part in ipairs(alcanzados) do
	if part:IsA("BasePart") and string.sub(part.Name, 1, 6) == "Block_" then
		enRadio += 1
		objetivo = objetivo or part
	end
end

if not objetivo then
	return {
		sinBloques = true,
		bloquesEnRadio = 0,
		tieneDestruccion = Explosion._destruction ~= nil,
	}
end

local vidaAntes = Destruction.GetBlockHealth(objetivo)
local afectadas = Explosion.Detonate(centro, GC.DefaultBombRadius, nil)
local vidaDespues = Destruction.GetBlockHealth(objetivo)

return {
	tieneDestruccion = Explosion._destruction ~= nil,
	tieneCombate = Explosion._combat ~= nil,
	tieneMonstruos = Explosion._monsters ~= nil,
	afectadasPorDetonate = afectadas,
	objetivo = objetivo and objetivo.Name or "ninguno",
	vidaAntes = vidaAntes,
	vidaDespues = vidaDespues,
	bloquesEnRadio = enRadio,
	explosionesAcumuladas = Explosion.GetExplosionCount(),
}
