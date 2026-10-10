--!strict
--[[
	BrainrotBehaviorRules
	IA DIFERENCIADA por arquetipo (FASE 9.3). Logica PURA, sin motor.

	POR QUE EXISTE
	--------------
	Las 15 especies brainrot declaran rasgos en `MonsterDefinitions`
	(`IsFlyer`, `IsSpectral`, `Vanishes`, `IsHeavy`, `IsTech`, `Teleports`,
	`IsVirus`, `Swarm`, `IsHunter`, ...), pero hasta ahora NINGUN servicio los
	leia: `MonsterService.StepAI` movia a todos con la MISMA maquina de
	estados y los MISMOS multiplicadores. Un mosquito volador y un yeti pesado
	se comportaban igual, y los rasgos eran letra muerta en los datos.

	Este modulo es el PUENTE entre los rasgos declarados y el comportamiento
	percibido. No mueve nada: deriva, de forma pura y comprobable, un PERFIL
	de comportamiento por arquetipo. `MonsterService` consume ese perfil para
	AJUSTAR la percepcion (cuanto ve y desde donde cada tipo). Es aditivo: no
	toca la maquina de estados `Idle->Patrol->Detect->...` ni el pathfinding,
	que estan validados en PLAY; solo modula el radio de deteccion/agro, que
	es justo lo que diferencia a un volador (ve desde el aire) de un pesado
	(miope pero lento).

	LOS ARQUETIPOS
	--------------
	Se derivan de los rasgos, con una prioridad explicita (un monstruo puede
	tener varios rasgos; el arquetipo es el DOMINANTE):

	  Flyer     IsFlyer             vuela: deteccion amplia, patrulla erratic
	  Spectral  IsSpectral/Vanishes etEreo: deteccion corta, sigilo/emboscada
	  Heavy     IsHeavy             pesado: deteccion corta, lento pero firme
	  Tech      IsTech/IsVirus      tecnologico: deteccion muy amplia (sensores)
	  Hunter    IsHunter            cazador: deteccion amplia y agresiva
	  Standard  (resto)            sin modificador: comportamiento base
]]

local Rules = {}

Rules.Archetype = {
	Flyer = "Flyer",
	Spectral = "Spectral",
	Heavy = "Heavy",
	Tech = "Tech",
	Hunter = "Hunter",
	Standard = "Standard",
}

-- Los multiplicadores son PUROS y acotados a proposito. Un multiplicador sin
-- tope es la clase de numero que alguien sube a 5 y el juego se rompe sin que
-- ningun test lo note. Todos viven en [0.5, 2.0].
Rules.Profiles = {
	[Rules.Archetype.Flyer] = { DetectionMult = 1.35, AggroMult = 1.30, PatrolRadiusMult = 1.40 },
	[Rules.Archetype.Spectral] = { DetectionMult = 0.75, AggroMult = 0.85, PatrolRadiusMult = 1.15 },
	[Rules.Archetype.Heavy] = { DetectionMult = 0.70, AggroMult = 0.80, PatrolRadiusMult = 0.80 },
	[Rules.Archetype.Tech] = { DetectionMult = 1.50, AggroMult = 1.45, PatrolRadiusMult = 1.20 },
	[Rules.Archetype.Hunter] = { DetectionMult = 1.25, AggroMult = 1.35, PatrolRadiusMult = 1.25 },
	[Rules.Archetype.Standard] = { DetectionMult = 1.0, AggroMult = 1.0, PatrolRadiusMult = 1.0 },
}

Rules.MIN_MULT = 0.5
Rules.MAX_MULT = 2.0

-- Prioridad de clasificacion. Se evalua EN ORDEN: el primer rasgo que
-- coincida decide el arquetipo. El orden es la politica de diseno (Tech y
-- Heavy ganan sobre Hunter; Spectral sobre Flyer).
Rules.Priority = {
	{ Archetype = Rules.Archetype.Tech, Traits = { "IsTech", "IsVirus" } },
	{ Archetype = Rules.Archetype.Heavy, Traits = { "IsHeavy" } },
	{ Archetype = Rules.Archetype.Spectral, Traits = { "IsSpectral", "Vanishes" } },
	{ Archetype = Rules.Archetype.Flyer, Traits = { "IsFlyer" } },
	{ Archetype = Rules.Archetype.Hunter, Traits = { "IsHunter" } },
}

--- Acota un multiplicador al rango seguro [MIN_MULT, MAX_MULT].
--- @param value number
--- @return number
local function clampMult(value: number): number
	if type(value) ~= "number" or value ~= value then
		return 1.0
	end
	return math.clamp(value, Rules.MIN_MULT, Rules.MAX_MULT)
end

--- Clasifica una definicion de monstruo en un arquetipo de comportamiento.
---
--- Pura y total: ante una definicion invalida o sin rasgos reconocidos
--- devuelve `Standard` (el 1.0 explicito), nunca nil. `MonsterService` la
--- llama en caliente, asi que no puede devolver nil.
--- @param def any definicion de `MonsterDefinitions`
--- @return string arquetipo (uno de `Rules.Archetype`)
function Rules.Classify(def: any): string
	if type(def) ~= "table" then
		return Rules.Archetype.Standard
	end

	for _, rule in ipairs(Rules.Priority) do
		for _, trait in ipairs(rule.Traits) do
			if def[trait] == true then
				return rule.Archetype
			end
		end
	end

	return Rules.Archetype.Standard
end

--- Perfil de comportamiento para una definicion (o directamente un arquetipo).
--- @param defOrArchetype any definicion de monstruo O string de arquetipo
--- @return { DetectionMult: number, AggroMult: number, PatrolRadiusMult: number }
function Rules.GetProfile(defOrArchetype: any): any
	local archetype = if type(defOrArchetype) == "string"
		then defOrArchetype
		else Rules.Classify(defOrArchetype)

	local profile = Rules.Profiles[archetype] or Rules.Profiles[Rules.Archetype.Standard]

	return {
		DetectionMult = clampMult(profile.DetectionMult),
		AggroMult = clampMult(profile.AggroMult),
		PatrolRadiusMult = clampMult(profile.PatrolRadiusMult),
	}
end

--- Radio de deteccion efectivo para una definicion.
---
--- Es lo que consume `MonsterService` en la percepcion: en vez de
--- `def.DetectionRange` a secas, usa el rango MODULADO por el arquetipo.
--- @param def any definicion de monstruo
--- @return number radio de deteccion efectivo (>= 0)
function Rules.EffectiveDetectionRange(def: any): number
	if type(def) ~= "table" or type(def.DetectionRange) ~= "number" then
		return 0
	end
	local mult = Rules.GetProfile(def).DetectionMult
	return math.max(0, def.DetectionRange * mult)
end

--- Radio de agresion (AggroRadius) efectivo para una definicion.
--- @param def any definicion de monstruo
--- @return number radio de aggro efectivo (>= 0)
function Rules.EffectiveAggroRadius(def: any): number
	if type(def) ~= "table" or type(def.AggroRadius) ~= "number" then
		return 0
	end
	local mult = Rules.GetProfile(def).AggroMult
	return math.max(0, def.AggroRadius * mult)
end

--- Audita que todas las especies brainrot tienen un arquetipo reconocido y un
--- perfil valido. Devuelve lista vacia si todo cuadra.
--- @param brainrotRules any el modulo `BrainrotRules`
--- @param monsterDefinitions any el modulo `MonsterDefinitions`
--- @return { string } problemas encontrados
function Rules.Audit(brainrotRules: any, monsterDefinitions: any): { string }
	local problems = {}

	if type(brainrotRules) ~= "table" or type(brainrotRules.GetAllSpeciesIds) ~= "function" then
		return { "BrainrotRules no es un modulo valido" }
	end
	if type(monsterDefinitions) ~= "table" or type(monsterDefinitions.Get) ~= "function" then
		return { "MonsterDefinitions no es un modulo valido" }
	end

	for _, id in ipairs(brainrotRules.GetAllSpeciesIds()) do
		local def = monsterDefinitions.Get(id)
		if not def then
			table.insert(problems, ("[%s] sin definicion en MonsterDefinitions"):format(id))
		else
			local archetype = Rules.Classify(def)
			local known = false
			for _, value in pairs(Rules.Archetype) do
				if value == archetype then
					known = true
					break
				end
			end
			if not known then
				table.insert(problems, ("[%s] arquetipo desconocido: %s"):format(id, tostring(archetype)))
			end
		end
	end

	return problems
end

return Rules

