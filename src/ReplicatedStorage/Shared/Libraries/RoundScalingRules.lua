--!strict
--[[
	RoundScalingRules
	DIFICULTAD PROGRESIVA POR RONDA: cada ronda trae mas monstruos.

	POR QUE EXISTE
	--------------
	Antes la arena se llenaba SIEMPRE con la misma poblacion: el mundo declara
	unos `SpawnRules` y `BuildMonsterSpawns` generaba exactamente esos, ronda
	tras ronda. El jugador aprendia el mapa a la tercera vez y la partida dejaba
	de tener tension: no habia motivo para volver.

	Este modulo convierte el NUMERO DE RONDA en cuantos monstruos extra entran.
	Es la misma idea que `DifficultyRules` con la noche, pero medida en rondas,
	que es la unidad que el jugador vive.

	LA REGLA DE LOS TOPES
	---------------------
	Crecer sin techo seria el bug que este codebase persigue en todas partes:
	`MonsterService.Spawn` ya rechaza por encima de `MaxMonsters` (30) y de
	`MaxAlive` por tipo, asi que el servidor esta protegido pase lo que pase.
	Aun asi el escalado declara SU propio techo (`AbsoluteMax`) por DEBAJO del
	global: asi una ronda alta deja hueco para el boss y las hordas en vez de
	acaparar los 30 con la poblacion base.

	Es puro y se prueba sin motor. `MatchService` solo consume `SpawnTarget`.
]]

local Rules = {}

--- Monstruos extra que suma cada ronda por encima de la poblacion base.
Rules.PerRoundBonus = 2

--- Tope de extras. Se alcanza y se mantiene: la curva deja de empinar para que
--- la partida siga siendo jugable en sesiones largas.
Rules.MaxBonus = 10

--- Tope ABSOLUTO de monstruos por ronda.
---
--- VA POR DEBAJO de `PerformanceConfig.Limits.MaxMonsters` (30) a proposito: la
--- poblacion base no debe acaparar el global. Lo que sobre queda para el boss y
--- las hordas, que entran por su propio camino.
Rules.AbsoluteMax = 24

--- Extras que corresponden a este numero de ronda.
---
--- Ronda 1 (la primera) no suma nada: el jugador entra, se situa y aprende el
--- mapa sin que le caigan seis enemigos encima. A partir de ahi crece.
--- @param round any numero de ronda (1 = primera)
--- @return number extras en [0, MaxBonus]
function Rules.BonusFor(round: any): number
	local r = tonumber(round)

	-- Un round invalido se trata como la primera ronda: no se concede bonus por
	-- un numero corrupto, igual que hace `DifficultyRules` con la noche.
	if not r or r ~= r or r < 1 then
		r = 1
	end

	r = math.floor(r)

	return math.clamp((r - 1) * Rules.PerRoundBonus, 0, Rules.MaxBonus)
end

--- Cuantos monstruos generar en total esta ronda.
--- @param baseCount any poblacion base declarada por el mundo
--- @param round any numero de ronda (1 = primera)
--- @return number objetivo en [0, AbsoluteMax]
function Rules.SpawnTarget(baseCount: any, round: any): number
	local base = tonumber(baseCount) or 0

	if base < 0 then
		base = 0
	end

	return math.clamp(base + Rules.BonusFor(round), 0, Rules.AbsoluteMax)
end

return Rules