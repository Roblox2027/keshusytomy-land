--!strict
--[[
	CHEST RULES
	Reglas puras para la generación y recompensas de cofres.

	POR QUE EXISTE
	--------------
	Los cofres son objetos interactivos que el jugador encuentra explorando
	el mundo. Al abrirlos, concede una HABILIDAD pasiva (definida en
	`SkillCatalog`). Este módulo define:
	  - Cuántos cofres hay por mundo y dónde (marcadores de spawn)
	  - Qué tipo de cofre es (Common / Rare / Epic / Legacy)
	  - Qué habilidad puede contener según el tipo y el mundo
	  - Cómo se hace el roll de la recompensa (determinista con `roll` inyectado)

	LA TABLA DE DROPS
	-----------------
	Cada cofre de tipo T en mundo W puede contener habilidades de SkillCatalog
	cuyo World == W y cuyo Tier es <= TierMax(T). La rareza del cofre
	limita el Tier:

	  Common:    habilidades de Tier 1
	  Rare:      habilidades de Tier ≤ 2
	  Epic:      habilidades de Tier ≤ 2, preferencia por Rares
	  Legendary: habilidades de Tier 3 o Legacy

	Los habilidades "de mundo" tienen prioridad: si el mundo es Forest, las
	habilidades Forest son más probables. El roll injected controla esto.

	AUTORIDAD
	---------
	Este módulo NO crea modelos ni ProximityPrompts. `ChestService` instancia
	los cofres físicos y llama a `OpenReward` para determinar la recompensa.
	Toda la lógica de "qué cae" está aquí, probable con `luau.exe`.
]]

-- `SkillCatalog` se importa con ruta RELATIVA, igual que
-- `MonsterDefinitions` importa `MonsterScaleRules`. Esta forma funciona
-- tanto en Roblox (donde `require` resuelve rutas relativas desde el
-- ModuleScript) como en el interprete standalone de `luau.exe` que
-- ejecuta las pruebas.
local SkillCatalog = require("../Config/SkillCatalog")

local Rules = {}

-- ---------------------------------------------------------------------------
-- TIPOS DE CAJA
-- ---------------------------------------------------------------------------

Rules.ChestType = {
	Common = "Common",
	Rare = "Rare",
	Epic = "Epic",
	Legacy = "Legacy",
}

-- Tier máximo de habilidad que cada tipo de cofre puede contener.
Rules.ChestTierLimits = {
	[Rules.ChestType.Common] = 1,
	[Rules.ChestType.Rare] = 2,
	[Rules.ChestType.Epic] = 2,
	[Rules.ChestType.Legacy] = 3,
}

-- Probabilidad base de cada tipo de cofre (debe sumar ~1.0 con el roll).
-- Estos pesos se normalizan internamente.
Rules.ChestWeights = {
	{ Type = Rules.ChestType.Common, Weight = 50 },
	{ Type = Rules.ChestType.Rare, Weight = 30 },
	{ Type = Rules.ChestType.Epic, Weight = 15 },
	{ Type = Rules.ChestType.Legacy, Weight = 5 },
}

-- ---------------------------------------------------------------------------
-- GENERACIÓN DE COFRÉS POR MUNDO
-- ---------------------------------------------------------------------------

-- Cuántos cofres de cada tipo aparecen en cada mundo. El mundo completo
-- debe tener entre 12 y 20 cofres para mantener el ritmo de descubrimiento
-- sin saturar. La distribución se inclina hacia Common/Rare.
Rules.ChestsPerWorld = {
	Forest = { Common = 6, Rare = 3, Epic = 1, Legacy = 0 },
	Desert = { Common = 6, Rare = 3, Epic = 1, Legacy = 0 },
	Ice = { Common = 5, Rare = 4, Epic = 1, Legacy = 0 },
	Volcano = { Common = 5, Rare = 3, Epic = 2, Legacy = 0 },
	Cyber = { Common = 6, Rare = 4, Epic = 1, Legacy = 1 },
}

-- ---------------------------------------------------------------------------
-- API
-- ---------------------------------------------------------------------------

--- Distribución normalizada de cofres (suma 1.0).
--- @return { { ChestType: string, Weight: number } }
function Rules.GetChestWeights(): { { ChestType: string, Weight: number } }
	return Rules.ChestWeights
end

--- Todas las habilidades elegibles para un cofre de tipo `chestType` y mundo
--- `worldId`. Se filtran por Tier y World.
---
--- Si `worldId` es nil, se permiten habilidades de todos los mundos.
---
--- @param chestType string Tipo de cofre (Common/Rare/Epic/Legacy)
--- @param worldId string? Mundo donde está el cofre
--- @return { { [string]: any } } habilidades elegibles
function Rules.GetEligibleSkills(chestType: string, worldId: string?): { { [string]: any } }
	local tierLimit = Rules.ChestTierLimits[chestType]
	if not tierLimit then
		return {}
	end

	local pool = {}

	if worldId and worldId ~= "" then
		-- Habilidades de este mundo.
		for _, skill in ipairs(SkillCatalog.GetByWorld(worldId)) do
			if skill.Tier <= tierLimit then
				table.insert(pool, skill)
			end
		end
	end

	-- Si el cofre es Legacy, también permitimos habilidades Legacy de
	-- otros mundos (son raras y valiosas).
	if chestType == Rules.ChestType.Legacy then
		for _, id in ipairs(SkillCatalog.GetAllIds()) do
			local skill = SkillCatalog.Get(id)
			if skill and skill.Rarity == SkillCatalog.Rarity.Legacy and skill.Tier <= tierLimit then
				-- Evitar duplicados si el worldId coincide.
				local exists = false
				for _, existing in ipairs(pool) do
					if existing.Id == skill.Id then
						exists = true
						break
					end
				end
				if not exists then
					table.insert(pool, skill)
				end
			end
		end
	end

	return pool
end

--- Genera la recompensa de un cofre.
---
--- El `roll` inyectado controla si el cofre contiene una habilidad de mundo
--- (prob ~70%) o una habilidad genérica (prob ~30%). Devuelve nil si no
--- hay habilidades elegibles.
---
--- @param chestType string
--- @param worldId string
--- @param roll function función de azar 0..1
--- @return { id: string, name: string, description: string, rarity: string }? habilidad ganada, o nil
function Rules.OpenReward(chestType: string, worldId: string, roll: () -> number): { id: string, name: string, description: string, rarity: string }?
	local pool = Rules.GetEligibleSkills(chestType, worldId)

	if #pool == 0 then
		return nil
	end

	-- 70% de prob de skill de mundo.
	local useWorld = true
	if roll then
		useWorld = (roll() < 0.7)
	end

	local filtered = {}
	if useWorld then
		for _, skill in ipairs(pool) do
			if skill.World == worldId then
				table.insert(filtered, skill)
			end
		end
	end

	if #filtered == 0 then
		filtered = pool
	end

	if #filtered == 0 then
		return nil
	end

	local index = 1
	if roll then
		index = math.floor(roll() * #filtered) + 1
	else
		index = ((worldId and #worldId) or 0) % #filtered + 1
	end
	index = math.clamp(index, 1, #filtered)

	local skill = filtered[index]

	return {
		id = skill.Id,
		name = skill.Name,
		description = skill.Description or "",
		rarity = skill.Rarity,
	}
end

--- Distribución de cofres para un mundo (cuántos de cada tipo).
--- @param worldId string
--- @return { ChestType: string, Count: number }[]? lista, o nil si el mundo no tiene
function Rules.GetChestDistribution(worldId: string): { { ChestType: string, Count: number } }?
	local config = Rules.ChestsPerWorld[worldId]
	if not config then
		return nil
	end

	local result = {}
	for _, entry in ipairs(Rules.ChestWeights) do
		local key = entry.Type
		local count = config[key] or 0
		if count > 0 then
			table.insert(result, { ChestType = key, Count = count })
		end
	end
	return result
end

--- Audit: verifica que cada habilidad referenciada existe en el catálogo.
--- @return { string } problemas
function Rules.Audit(): { string }
	local problems = {}

	for worldId, config in pairs(Rules.ChestsPerWorld) do
		if not SkillCatalog then
			table.insert(problems, ("[%s] SkillCatalog no disponible"):format(worldId))
		else
			for _, entry in ipairs(Rules.ChestWeights) do
				local skills = Rules.GetEligibleSkills(entry.Type, worldId)
				if #skills == 0 then
					table.insert(problems, ("[%s] cofre %s sin habilidades elegibles"):format(worldId, entry.Type))
				end
			end
		end
	end

	-- Verificar que los TierLimits son coherentes.
	for _, limit in pairs(Rules.ChestTierLimits) do
		if type(limit) ~= "number" or limit < 0 or limit > 3 then
			table.insert(problems, ("ChestTierLimits tiene un límite inválido: %s"):format(tostring(limit)))
		end
	end

	return problems
end

return Rules
