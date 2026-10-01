--!strict
--[[
	CombatMath
	Logica PURA de combate: sin servicios de Roblox, sin estado.

	Por que existe:
	Las reglas que deciden si una bomba mata, si una explosion encadena
	o cuanto XP da un nivel son FORMULAS. Si viven dentro de
	ExplosionService o BombService no se pueden probar: `luau.exe` no
	tiene Workspace. Este modulo las aisla para que la suite las
	ejecute de verdad.

	Regla: aqui no se toca ningun objeto del juego. Solo numeros que
	entran y numeros que salen. El servidor sigue siendo la autoridad:
	esta libreria no concede nada por si sola.
]]
local CombatMath = {}

--- Un numero utilizable: no es NaN ni infinito.
--- @param value number
--- @return boolean
function CombatMath.IsFiniteNumber(value: number): boolean
	if value ~= value then
		return false
	end

	if value == math.huge or value == -math.huge then
		return false
	end

	return true
end

--- Posicion con componentes utilizables.
--- @param x number
--- @param y number
--- @param z number
--- @return boolean valid
--- @return string? reason
function CombatMath.ValidatePosition(x: number, y: number, z: number): (boolean, string?)
	if not CombatMath.IsFiniteNumber(x)
		or not CombatMath.IsFiniteNumber(y)
		or not CombatMath.IsFiniteNumber(z) then
		return false, "componente no finito"
	end

	-- Alturas fuera de este rango significan mapa roto o payload
	-- manipulado para caer desde arriba o desde debajo del mundo.
	if y > 5000 or y < -5000 then
		return false, "altura fuera de rango"
	end

	return true, nil
end

--- Distancia horizontal entre dos puntos (ignora Y).
--- Se usa en cadenas de reaccion y limites de mapa, donde la altura
--- no debe alterar el resultado.
--- @param ax number
--- @param az number
--- @param bx number
--- @param bz number
--- @return number
function CombatMath.FlatDistance(ax: number, az: number, bx: number, bz: number): number
	local dx = ax - bx
	local dz = az - bz
	return math.sqrt(dx * dx + dz * dz)
end

--- Dano de una explosion en funcion de la distancia al centro.
--- Lineal: maximo en el centro, cero exactamente en el borde.
--- @param distance number
--- @param radius number
--- @param maxDamage number
--- @param multiplier number? multiplicador de muerte subita
--- @return number damage nunca negativo
function CombatMath.FalloffDamage(distance: number, radius: number, maxDamage: number, multiplier: number?): number
	-- Se filtra TODO, no solo la distancia: un `maxDamage` o un `radio`
	-- no finito devolverian `inf` o `nan` y contaminarian la vida del
	-- jugador de forma irreversible.
	if not CombatMath.IsFiniteNumber(distance)
		or not CombatMath.IsFiniteNumber(radius)
		or not CombatMath.IsFiniteNumber(maxDamage) then
		return 0
	end

	if radius <= 0 or maxDamage <= 0 then
		return 0
	end

	-- Fuera del radio: cero. Nunca negativo, porque un dano negativo
	-- seria una curacion y permitiria un exploit de vida infinita.
	if distance >= radius then
		return 0
	end

	local scale = multiplier or 1
	if scale < 0 then
		scale = 0
	end

	return maxDamage * (1 - (distance / radius)) * scale
end

--- Dano atenuado por obstaculos entre la bomba y el objetivo.
---
--- Sin esto, un muro no protege: el radio de la explosion no ocluye el
--- dano. El raycast del servidor es lo que decide si la linea esta
--- limpia, y aqui solo se aplica el factor.
---
--- @param hasLineOfSight boolean
--- @param damage number
--- @param obstructionFactor number? fraccion que atraviesa un muro
--- @return number damage
function CombatMath.ApplyOcclusion(hasLineOfSight: boolean, damage: number, obstructionFactor: number?): number
	if hasLineOfSight then
		return damage
	end

	local factor = obstructionFactor or 0.25
	if factor < 0 then
		factor = 0
	end
	if factor > 1 then
		factor = 1
	end

	return damage * factor
end

--- Bombas dentro del radio de encadenado, con su retardo.
---
--- Devuelve la lista ORDENADA por retardo: la mas cercana detona
--- primero. Sin ordenar, dos bombas a la vez se encadenarian de forma
--- no determinista, porque `pairs` no garantiza orden.
---
--- @param entries { { X: number, Z: number, Id: any } }
--- @param centerX number
--- @param centerZ number
--- @param radius number
--- @param delayPerStud number
--- @return { { Id: any, Delay: number } } cadena ordenada
function CombatMath.BuildChain(
	entries: { { X: number, Z: number, Id: any } },
	centerX: number,
	centerZ: number,
	radius: number,
	delayPerStud: number
): { { Id: any, Delay: number } }
	local chain = {}

	if radius <= 0 then
		return chain
	end

	for _, entry in ipairs(entries) do
		local distance = CombatMath.FlatDistance(centerX, centerZ, entry.X, entry.Z)

		if distance < radius then
			table.insert(chain, {
				Id = entry.Id,
				Delay = distance * delayPerStud,
			})
		end
	end

	table.sort(chain, function(a, b)
		if a.Delay == b.Delay then
			return tostring(a.Id) < tostring(b.Id)
		end
		return a.Delay < b.Delay
	end)

	return chain
end

--- Dano que recibe un bloque al recibir una explosion.
--- @param explosionDamage number
--- @param scale number fraccion del dano que aplica a estructuras
--- @return number
function CombatMath.BlockDamageFromExplosion(explosionDamage: number, scale: number): number
	if explosionDamage <= 0 then
		return 0
	end

	local clamped = scale
	if clamped < 0 then
		clamped = 0
	end
	if clamped > 1 then
		clamped = 1
	end

	return explosionDamage * clamped
end

--- Vida restante de un bloque tras un golpe.
--- @param currentHealth number
--- @param incomingDamage number
--- @return number newHealth nunca menor que 0
function CombatMath.ApplyBlockDamage(currentHealth: number, incomingDamage: number): number
	local health = currentHealth

	if incomingDamage > 0 then
		health -= incomingDamage
	end

	if health < 0 then
		return 0
	end

	return health
end

--- XP total necesaria para alcanzar un nivel.
---
--- No hay tope artificial en 100: la curva crece de forma suave pero
--- el nivel sigue subiendo. El limite duro (GameConfig.MaxLevel) existe
--- solo para valores corruptos, no como tope de contenido.
--- @param level number nivel objetivo (1 = 0 XP)
--- @param xpPerLevel number
--- @param exponent number
--- @param maxLevel number
--- @return number totalXp
function CombatMath.XpForLevel(level: number, xpPerLevel: number, exponent: number, maxLevel: number): number
	if level <= 1 then
		return 0
	end

	local capped = level
	if capped > maxLevel then
		capped = maxLevel
	end

	return xpPerLevel * ((capped - 1) ^ exponent)
end

--- Nivel correspondiente a una cantidad de XP.
---
--- Se recorre en vez de usar formula cerrada porque la curva es una
--- potencia fraccionaria: el resultado debe ser EXACTO, no aproximado.
--- @param xp number
--- @param xpPerLevel number
--- @param exponent number
--- @param maxLevel number
--- @return number level
function CombatMath.LevelForXp(xp: number, xpPerLevel: number, exponent: number, maxLevel: number): number
	if xp <= 0 then
		return 1
	end

	local level = 1

	while level < maxLevel do
		local nextCost = CombatMath.XpForLevel(level + 1, xpPerLevel, exponent, maxLevel)

		if nextCost > xp then
			break
		end

		level += 1
	end

	return level
end

--- Progreso de la barra de experiencia dentro del nivel actual.
--- @param xp number
--- @param xpPerLevel number
--- @param exponent number
--- @param maxLevel number
--- @return number currentWithinLevel
--- @return number neededForNextLevel 0 en el nivel maximo
function CombatMath.LevelProgress(
	xp: number,
	xpPerLevel: number,
	exponent: number,
	maxLevel: number
): (number, number)
	local level = CombatMath.LevelForXp(xp, xpPerLevel, exponent, maxLevel)
	local floorXp = CombatMath.XpForLevel(level, xpPerLevel, exponent, maxLevel)

	if level >= maxLevel then
		return math.max(0, xp - floorXp), 0
	end

	local nextXp = CombatMath.XpForLevel(level + 1, xpPerLevel, exponent, maxLevel)
	return math.max(0, xp - floorXp), math.max(1, nextXp - floorXp)
end

--- Tope de XP que se puede SUMAR a una sesion.
---
--- `AddRewards` es idempotente por ronda, pero aun asi un valor
--- absurdo (NaN, infinito, negativo) dejaria el perfil corrupto para
--- siempre. aqui se filtra antes de tocar el estado.
--- @param xp number
--- @param currentXp number
--- @return number applied siempre >= 0
function CombatMath.SafeRewardAmount(xp: number, currentXp: number): number
	if not CombatMath.IsFiniteNumber(xp) then
		return 0
	end

	if xp <= 0 then
		return 0
	end

	local applied = math.floor(xp)
	local result = currentXp + applied

	-- Un saldo negativo significaria que algo resto XP por error.
	if result < 0 then
		return 0
	end

	return applied
end

return CombatMath
