--!strict
--[[
	BestiaryRules
	COLECCION de especies (MASTER MISSION V2 - FASE 20: coleccion funcional
	del contenido existente; los disenos visuales NO se tocan).

	POR QUE EXISTE
	--------------
	Las criaturas del juego (los "brainrot" jugables: monstruos, mini-bosses
	y bosses) existian solo como obstaculos: se mataban y desaparecian. La
	coleccion las convierte en CONTENIDO: cada especie derrotada queda
	registrada en el bestiario, con contador y rareza, y el jugador puede
	ver cuanto le falta.

	QUE VIVE AQUI
	-------------
	La clasificacion y la aritmetica de coleccion: pura y probada. El
	servicio (`BestiaryService`) aporta el perfil y la publicacion.

	LA REGLA DE RAREZA
	------------------
	La rareza es FUNCIONAL (de donde sale y cuanto cuesta encontrarla), no
	visual: un boss es Legendario porque hay uno por mundo, no porque
	brille mas.
]]

local Rules = {}

-- ---------------------------------------------------------------------------
-- RAREZA FUNCIONAL
-- ---------------------------------------------------------------------------

Rules.Rarity = {
	Common = "Common",
	Rare = "Rare",
	Epic = "Epic",
	Legendary = "Legendary",
}

--- Rareza de una especie segun su definicion de monstruo.
---
--- Boss = Legendario; mini-boss (los `Forest*`/`Desert*`... de tiers) o
-- enemigo de elite de mundo (vida >= 200) = Epico/Raro; el resto es
--- fauna comun. La rareza se DEDUCE de la definicion, nunca la manda el
--- cliente.
--- @param def any MonsterDefinition
--- @return string
function Rules.RarityOf(def: any): string
	if type(def) ~= "table" then
		return Rules.Rarity.Common
	end

	if def.IsBoss then
		return Rules.Rarity.Legendary
	end

	local health = tonumber(def.Health) or 0

	if health >= 400 then
		return Rules.Rarity.Epic
	end

	if health >= 100 then
		return Rules.Rarity.Rare
	end

	return Rules.Rarity.Common
end

-- ---------------------------------------------------------------------------
-- COLECCION
-- ---------------------------------------------------------------------------

--- Registra una baja en el estado del bestiario.
---
--- Devuelve si fue NUEVO: la primera baja de una especie es un
--- descubrimiento y merece aviso; la decima es progreso silencioso.
--- @param state any seccion `Bestiary` del perfil
--- @param defId any
--- @return boolean isNew
--- @return number kills totales de la especie
function Rules.RecordKill(state: any, defId: any): (boolean, number)
	if type(state) ~= "table" or type(defId) ~= "string" or defId == "" then
		return false, 0
	end

	if type(state.Species) ~= "table" then
		state.Species = {}
	end

	local entry = state.Species[defId]

	if type(entry) ~= "table" then
		entry = { Kills = 0 }
		state.Species[defId] = entry
	end

	entry.Kills = (tonumber(entry.Kills) or 0) + 1

	return entry.Kills == 1, entry.Kills
end

--- Cuantas especies distintas hay registradas.
--- @param state any
--- @return number
function Rules.CountDiscovered(state: any): number
	if type(state) ~= "table" or type(state.Species) ~= "table" then
		return 0
	end

	local count = 0

	for _ in pairs(state.Species) do
		count += 1
	end

	return count
end

--- Completitud de la coleccion: descubiertas / totales.
--- @param state any
--- @param totalSpecies any numero de especies del juego
--- @return number ratio 0..1
function Rules.CompletionRatio(state: any, totalSpecies: any): number
	local total = tonumber(totalSpecies) or 0

	if total <= 0 then
		return 0
	end

	return math.clamp(Rules.CountDiscovered(state) / total, 0, 1)
end

return Rules
