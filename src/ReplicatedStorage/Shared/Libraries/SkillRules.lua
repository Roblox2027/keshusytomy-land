--!strict
--[[
	SkillRules
	Reglas PURAS para derivar estadísticas de bomba a partir del
	catálogo de habilidades y la lista de habilidades desbloqueadas por un
	jugador.

	POR QUE EXISTE
	--------------
	`SkillCatalog` define habilidades con efectos (BombCapacity,
	BombDamageMult, BombRadiusMult), y `ChestService` las guarda en
	`profile.Skills.Unlocked`. Pero hasta ahora NADA leía esos efectos:
	BombService y ExplosionService usaban siempre los valores de GameConfig.

	Este módulo es el PUENTE: toma una lista de IDs de habilidades
	desbloqueadas + el catálogo, y devuelve las estadísticas de bomba
	efectivas que el servidor debe aplicar.

	ES PURO Y TESTEABLE: no usa Color3, Enum, ni servicios de Roblox.
]]

local Rules = {}

-- ---------------------------------------------------------------------------
-- CONSTANTES DE EFECTO
-- ---------------------------------------------------------------------------

--- Claves de efecto que afectan a las bombas (deben coincidir con SkillCatalog.Effect).
Rules.EffectKeys = {
	BombCapacity = "BombCapacity",
	BombDamageMult = "BombDamageMult",
	BombRadiusMult = "BombRadiusMult",
}

--- Sabores visuales posibles según las habilidades de bomba desbloqueadas.
Rules.Flavors = {
	Default = "default",
	Damage = "damage",
	Radius = "radius",
	Capacity = "capacity",
	Power = "power",
}

-- ---------------------------------------------------------------------------
-- CAPAS DE STACKING
-- ---------------------------------------------------------------------------

--- Regla de stacking de la categoría Bomba.
---
--- - BombCapacity: habilidades con distinto Tier pero el MISMO efecto.
---   Solo se usa el de mayor Tier (el jugador "elige" el mejor).
--- - BombDamageMult / BombRadiusMult: hay un único skill por efecto, luego
---   se suman (por si el catálogo crece).
---
--- @param unlockedIds { string }
--- @return { capacity: number, radiusMult: number, damageMult: number, flavor: string }
function Rules.ComputeBombStats(unlockedIds: { string }?, catalog: any?): {
	capacity: number,
	radiusMult: number,
	damageMult: number,
	flavor: string,
}
	local totals = {
		capacity = 0,
		radiusMult = 0,
		damageMult = 0,
		flavor = Rules.Flavors.Default,
	}

	if type(unlockedIds) ~= "table" or type(catalog) ~= "table" or type(catalog.Get) ~= "function" then
		return totals
	end

	-- Para capacidad: conservar el de mayor Tier.
	local bestCapacityTier = 0
	local bestCapacityValue = 0

	for _, id in ipairs(unlockedIds) do
		if type(id) ~= "string" then
			continue
		end

		local skill = catalog.Get(id)
		if not skill then
			continue
		end

		if skill.Category ~= catalog.Categories.Bomb then
			continue
		end

		local effect = skill.Effect
		if type(effect) ~= "table" then
			continue
		end

		local tier = tonumber(skill.Tier) or 0

		if effect.BombCapacity then
			if tier > bestCapacityTier then
				bestCapacityTier = tier
				bestCapacityValue = tonumber(effect.BombCapacity) or 0
			end
		end

		if effect.BombDamageMult then
			totals.damageMult += tonumber(effect.BombDamageMult) or 0
		end

		if effect.BombRadiusMult then
			totals.radiusMult += tonumber(effect.BombRadiusMult) or 0
		end
	end

	totals.capacity = bestCapacityValue

	-- Sabor visual: refleja qué habilidades de bomba el jugador tiene.
	-- Priority: power (damage + radius) > damage > radius > capacity > default.
	if totals.damageMult > 0 and totals.radiusMult > 0 then
		totals.flavor = Rules.Flavors.Power
	elseif totals.damageMult > 0 then
		totals.flavor = Rules.Flavors.Damage
	elseif totals.radiusMult > 0 then
		totals.flavor = Rules.Flavors.Radius
	elseif totals.capacity > 0 then
		totals.flavor = Rules.Flavors.Capacity
	else
		totals.flavor = Rules.Flavors.Default
	end

	return totals
end

return Rules
