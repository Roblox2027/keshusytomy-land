--!strict
--[[
	EquipmentRules
	EQUIPAMIENTO CON ESTADISTICAS REALES (MASTER MISSION V2 - FASE 29).

	POR QUE EXISTE
	--------------
	El equipamiento era cosmetico: las tres ranuras (Head/Body/Feet) no
	cambiaban nada de como se juega. Aqui cada pieza MODIFICA algo real:

	  - velocidad de movimiento,
	  - vida maxima,
	  - enfriamiento de la habilidad.

	QUE VIVE AQUI
	-------------
	La suma de stats: pura y probada sin motor. La aplicacion (escribir el
	WalkSpeed del personaje) la hace el servidor, con el catalogo como
	UNICA fuente de "que da cada pieza".

	LA REGLA ANTI-P2W
	-----------------
	Las piezas con stats se ganan JUGANDO (tienda de monedas o drops), y
	los efectos son modestos: +10 % de velocidad se nota, +200 % rompe el
	juego. El tope por stat es la garantia de que apilar piezas nunca
	salga de control.
]]

local Rules = {}

-- ---------------------------------------------------------------------------
-- LIMITES
-- ---------------------------------------------------------------------------

--- Tope de cada modificador. Las piezas se SUMAN y luego se ACOTAN:
--- sin techo, tres piezas de velocidad harian al jugador inalcanzable.
Rules.Caps = {
	-- Multiplicador de velocidad: entre 0.8 y 1.35.
	WalkSpeedMult = { Min = 0.8, Max = 1.35 },
	-- Vida maxima EXTRA: entre 0 y 60.
	MaxHealthBonus = { Min = 0, Max = 60 },
	-- Multiplicador del cooldown de la habilidad: entre 0.75 y 1.
	-- Bajarlo demasiado convertiria la habilidad en el ataque basico.
	AbilityCooldownMult = { Min = 0.75, Max = 1.0 },
}

-- ---------------------------------------------------------------------------
-- CALCULO
-- ---------------------------------------------------------------------------

--- Stats totales de un conjunto equipado.
---
--- El catalogo se INYECTA (mismo patron que el resto de reglas puras):
--- la regla no sabe de donde sale la definicion, solo que tiene `Stats`.
--- @param equippedIds any { [slot] = itemId }
--- @param catalog any ItemCatalog
--- @return { WalkSpeedMult: number, MaxHealthBonus: number, AbilityCooldownMult: number }
function Rules.ComputeStats(equippedIds: any, catalog: any): { [string]: number }
	local totals = {
		WalkSpeedMult = 1,
		MaxHealthBonus = 0,
		AbilityCooldownMult = 1,
	}

	if
		type(equippedIds) ~= "table"
		or type(catalog) ~= "table"
		or type(catalog.Get) ~= "function"
	then
		return totals
	end

	for _, itemId in pairs(equippedIds) do
		local definition = catalog.Get(itemId)
		local stats = definition and definition.Stats

		if type(stats) == "table" then
			totals.WalkSpeedMult += tonumber(stats.WalkSpeedMult) or 0
			totals.MaxHealthBonus += tonumber(stats.MaxHealthBonus) or 0
			totals.AbilityCooldownMult += tonumber(stats.AbilityCooldownMult) or 0
		end
	end

	-- Acotado: la suma nunca sale de los topes declarados.
	totals.WalkSpeedMult =
		math.clamp(totals.WalkSpeedMult, Rules.Caps.WalkSpeedMult.Min, Rules.Caps.WalkSpeedMult.Max)
	totals.MaxHealthBonus = math.clamp(
		totals.MaxHealthBonus,
		Rules.Caps.MaxHealthBonus.Min,
		Rules.Caps.MaxHealthBonus.Max
	)
	totals.AbilityCooldownMult = math.clamp(
		totals.AbilityCooldownMult,
		Rules.Caps.AbilityCooldownMult.Min,
		Rules.Caps.AbilityCooldownMult.Max
	)

	return totals
end

return Rules
