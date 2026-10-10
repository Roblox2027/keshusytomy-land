--!strict
--[[
	BRAINROT RULES
	Distribución funcional de brainrots en el mundo (FASE 20: contenido
	colectivo disperso).

	POR QUE EXISTE
	--------------
	Los brainrots (Locotto, Bambino, Bombino, ...) existen como DEFINICIONES
	en `MonsterDefinitions`, pero hasta ahora solo aparecen como fauna de
	arena (SpawnRules) o mini-bosses (zonas dedicadas). Nunca están
	presentes como NPCs errantes en el mapa: el jugador explora 96 zonas
	y el mundo está vacío salvo el slime que aparece al entrar en la arena.

	Este módulo define QUÉ brainrot aparece EN QUÉ mundo, EN QUÉ GRUPOS y
	con qué comportamiento de paseo. La lógica de spawn propiamente dicha
	vive en `BrainrotService`; aquí solo hay datos y aritmética pura,
	comprobable con `luau.exe`.

	LA REGLA DE CLASIFICACIÓN
	--------------------------
	Los brainrots se clasifican por mundo de origen, usando los IDs ya
	declarados en `MonsterDefinitions`:

	  Forest:   Locotto (tronco), Bambino (mosquito), Bombino (hongo)
	  Desert:   Explodini (camello), Bailarino (cactus), Sandwichini (lunch)
	  Ice:      Glaciacino (pingüino), Macarronni (yeti), Fantasmitti (fantasma)
	  Volcano:  Lavaccino (lava), Peperoni (dragón), Magmatico (tanque)
	  Cyber:    Glitchino (robot), Pixeloni (cazador), Virusini (virus)

	Cada mundo genera GRUPOS de estos brainrots en zonas de exploración
	(no en la arena de combate). Un grupo es un punto de aparición con un
	tipo y un número de individuos. El jugador los encuentra vagando por
	el mapa, no en la arena de rondas.

	AUTORIDAD
	----------
	Este módulo no instancia nada. `BrainrotService` decide cuándo y dónde
	spawnear usando `MonsterService.Spawn`. La tabla de grupos es
	determinista: `RollGroups` recibe el generador de números inyectado
	(igual que `EventRules.Roll`) para que las pruebas no dependan del azar.
]]

local Rules = {}

-- ---------------------------------------------------------------------------
-- ESPECIES POR MUNDO
-- ---------------------------------------------------------------------------
--
-- El índice es el `Id` del mundo. El valor es una lista de IDs de definición
-- de monstruo que representan los "brainrot" nativos de ese mundo.
--
-- Estos IDs DEBEN existir en `MonsterDefinitions`. La prueba
-- `BrainrotRules.spec` verifica que cada uno tenga definición.

Rules.SpeciesByWorld = {
	Forest = { "Locotto", "Bambino", "Bombino", "Zombini" },
	Desert = { "Explodini", "Bailarino", "Sandwichini", "Mumifico" },
	Ice = { "Glaciacino", "Macarronni", "Fantasmitti", "Congelado" },
	Volcano = { "Lavaccino", "Peperoni", "Magmatico", "Carbonizado" },
	Cyber = { "Glitchino", "Pixeloni", "Virusini", "Necrobyte" },
}

-- ---------------------------------------------------------------------------
-- GRUPOS POR MUNDO
-- ---------------------------------------------------------------------------
--
-- Cuántos grupos generar y cuántos individuos por grupo. Estos números
-- están calibrados para que un mundo tenga "vida" sin saturar el servidor.
--
-- FASE 9.5 (población masiva): antes eran 8 grupos x 2-3 (~20 brainrots por
-- mundo, un mapa que se sentía vacío al recorrerlo). Ahora 20 grupos x 2-4,
-- lo que acerca cada mundo al rango pedido (40-80 brainrots). El tope REAL
-- lo sigue poniendo `MonsterService`: `MaxAlive` por especie acota cuántos
-- individuos de cada tipo coexisten, y `PerformanceConfig.Limits.MaxMonsters`
-- (=80) es el presupuesto global del servidor. Estos números son la INTENCIÓN
-- de población; los topes duros son la garantía de que no se degrada.
--
-- El formato es: { Groups = N, PerGroup = { Min, Max } }

Rules.GroupConfig = {
	Forest = { Groups = 20, PerGroup = { Min = 2, Max = 4 } },
	Desert = { Groups = 20, PerGroup = { Min = 2, Max = 4 } },
	Ice = { Groups = 20, PerGroup = { Min = 2, Max = 4 } },
	Volcano = { Groups = 20, PerGroup = { Min = 2, Max = 4 } },
	Cyber = { Groups = 20, PerGroup = { Min = 2, Max = 4 } },
}

-- ---------------------------------------------------------------------------
-- COMPORTAMIENTO DE PASEO
-- ---------------------------------------------------------------------------
--
-- Los brainrots son PACÍFOS (no atacan al jugador). Su IA de paseo se
-- basa en patrullar entre puntos cercanos. Los siguientes valores definen
-- el comportamiento de vagaboreo:

Rules.Roam = {
	-- Radio de patrullaje alrededor del punto de spawn, en studs.
	PatrolRadius = 20,
	-- Velocidad de movimiento (muy lenta: son decorativos, no amenazas).
	WalkSpeed = 4,
	-- Tiempo entre cambio de dirección de patrullaje, en segundos.
	IdleIntervalMin = 8,
	IdleIntervalMax = 15,
}

-- ---------------------------------------------------------------------------
-- API
-- ---------------------------------------------------------------------------

--- Especies disponibles para un mundo.
--- @param worldId string?
--- @return { string } ids de especies (tabla vacía si el mundo no tiene brainrots)
function Rules.GetSpecies(worldId: string?): { string }
	local species = Rules.SpeciesByWorld[worldId or ""]

	if not species then
		return {}
	end

	local copy = {}
	for i = 1, #species do
		copy[i] = species[i]
	end
	return copy
end

--- Configuración de grupos para un mundo.
--- @param worldId string?
--- @return { Groups: number, PerGroup: { Min: number, Max: number } }?
function Rules.GetGroupConfig(worldId: string?): { Groups: number, PerGroup: { Min: number, Max: number } }?
	return Rules.GroupConfig[worldId or ""]
end

--- Todos los IDs de brainrot del juego (para auditoría).
--- @return { string }
function Rules.GetAllSpeciesIds(): { string }
	local ids = {}
	for _, species in pairs(Rules.SpeciesByWorld) do
		for _, id in ipairs(species) do
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return ids
end

--- Todos los mundos que tienen brainrots.
--- @return { string }
function Rules.GetWorlds(): { string }
	local worlds = {}
	for worldId in pairs(Rules.SpeciesByWorld) do
		table.insert(worlds, worldId)
	end
	table.sort(worlds)
	return worlds
end

-- Conjunto de TODOS los ids de especie brainrot, construido una vez.
--
-- Existe para que `IsBrainrot` sea O(1): `MonsterService` lo consulta en
-- cada muerte de monstruo, y recorrer `SpeciesByWorld` cada vez seria trabajo
-- tirado a la basura en el camino caliente del juego.
local BRAINROT_SET: { [string]: boolean } = {}
for _, worldId in ipairs(Rules.GetWorlds()) do
	for _, id in ipairs(Rules.GetSpecies(worldId)) do
		BRAINROT_SET[id] = true
	end
end
Rules._BrainrotSet = BRAINROT_SET

--- ?Este id de monstruo es un brainrot?
---
--- Es la FRONTERA que usa `MonsterService` para decidir si una muerte emite
--- la metrica `BrainrotDefeated`. Se resuelve contra el conjunto precalculado
--- para no depender de recorrer tablas en caliente.
---
--- @param monsterId any id tal como aparece en `MonsterDefinitions`
--- @return boolean
function Rules.IsBrainrot(monsterId: any): boolean
	return type(monsterId) == "string" and BRAINROT_SET[monsterId] == true
end

--- Genera los grupos de brainrots para un mundo.
---
--- La función recibe un `roll` inyectado (igual que `EventRules.Roll`) para
--- que las pruebas puedan forzar resultados deterministas. Cada grupo
--- contiene:
---   - `Species`: ID del brainrot
---   - `Count`: número de individuos (1 o 2)
---   - `Slot`: índice del grupo (0..N-1), usado para posicionarlo
---
--- @param worldId string
--- @param roll function funcion de azar 0..1
--- @return { { Species: string, Count: number, Slot: number } }? grupos, o nil si el mundo no tiene
function Rules.RollGroups(worldId: string, roll: () -> number): { { Species: string, Count: number, Slot: number } }?
	local config = Rules.GetGroupConfig(worldId)

	if not config then
		return nil
	end

	local species = Rules.GetSpecies(worldId)

	if #species == 0 then
		return nil
	end

	local groups = {}
	local perGroupMin = config.PerGroup.Min
	local perGroupMax = config.PerGroup.Max

	for i = 1, config.Groups do
		local speciesIndex = ((i - 1) % #species) + 1

		-- Distribución round-robin de especies, con variación ligera
		-- usando el roll injectado.
		local variant = math.floor((roll() or 0) * #species) + 1
		speciesIndex = ((speciesIndex - 1 + variant - 1) % #species) + 1

		local countRange = perGroupMax - perGroupMin + 1
		local count = perGroupMin + math.floor((roll() or 0) * countRange)

		table.insert(groups, {
			Species = species[speciesIndex],
			Count = count,
			Slot = i - 1,
		})
	end

	return groups
end

--- Audita la coherencia entre las especies declaradas y el catálogo
--- de monstruos. Devuelve una lista vacía si todo cuadra.
---
--- @param monsterDefinitions any el módulo `MonsterDefinitions`
--- @return { string } problemas encontrados
function Rules.Audit(monsterDefinitions: any): { string }
	local problems = {}

	if type(monsterDefinitions) ~= "table" or type(monsterDefinitions.Get) ~= "function" then
		return { "MonsterDefinitions no es un modulo valido" }
	end

	for _, worldId in ipairs(Rules.GetWorlds()) do
		local species = Rules.GetSpecies(worldId)

		for _, id in ipairs(species) do
			if not monsterDefinitions.Get(id) then
				table.insert(problems, ("[%s] brainrot '%s' sin definicion en MonsterDefinitions"):format(worldId, id))
			end
		end
	end

	return problems
end

return Rules
