--!strict
--[[
	BrainrotService
	 NPCs pacíficos errantes en el mapa de exploración (FASE 20).

	POR QUE EXISTE
	--------------
	Los brainrots (Locotto, Bambino, Bombino, ...) existen como monstruos
	en `MonsterDefinitions`, pero hasta ahora solo aparecen como fauna de
	la arena de combate. Nunca como NPCs explorables en el mapa: al
	entrar en Forest, el mundo está vacío salvo los enemigos que aparecen
	en la arena.

	Este servicio coloca esos NPCs en el mapa, usando los marcadores
	`BrainrotSpawn_*` que genera `tools/worlds.js`. Cada uno es un monstruo
	real (modelo, Humanoid, IA) creado por `MonsterService.Spawn`, así que
	al morir se notifica automáticamente a `BestiaryService` y la colección
	de especies registra al asesino.

	LA REGLA DE LA PEACEFUL
	-----------------------
	Los brainrots usan el AI de patrullaje de `MonsterService` tal cual:
	erran entre puntos cercanos con `PatrolSpeed` (muy lento), y persiguen
	al jugador solo si se acerca demasiado. No son agresivos por nature
	-- atacan solo si el jugador losgolpea primero--, por lo que explorar
	el mapa se siente vivo sin ser hostil.

	LA REGLA DEL RESPAWN
	--------------------
	Un brainrot que muere vuelve a nacer. El mundo debe "tener vida" con
	o sin interacción del jugador: un mapa vacío después de la primera
	bola de nieve es un mapa muerto. El watchdog respawnea cadabrainrot
	caído cada intervalo fijo, usando el mismo MonsterService.Spawn para
	garantizar que el nuevo NPC tenga el modelo y la IA correctos.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local UTILS = SHARED:WaitForChild("Utils")

local BrainrotRules = require(SHARED:WaitForChild("Libraries"):WaitForChild("BrainrotRules"))
local MonsterDefinitions = require(SHARED:WaitForChild("MonsterDefinitions"))
local Logger = require(UTILS:WaitForChild("Logger"))

local Service = {}

Service.IsInitialized = false

-- Servicios inyectados por `ServerMain`.
Service._monsterService = nil
Service._worldService = nil
Service._maid = nil

-- brainrotId -> monsterId (el ID que devuelve MonsterService.Spawn)
-- Se usa para el respawn: si el ID desaparece de MonsterService._monsters,
-- el watchdog lo rehace.
Service._activeBrainrots = {}

-- Intervalo de respawn de brainrots caídos, en segundos.
-- 90 s es suficientemente lento como para no competir con la partida de
-- arena, y suficientemente rápido como para que el mundo "se reponga"
-- mientras el jugador explora.
Service.RespawnInterval = 90

-- Distancia mínima entre el jugador y un brainrot recién spawneado.
-- Sin esto, un brainrot podría aparecer justo encima de un jugador que
-- está explorando y causar confusión.
Service.SpawnMargin = 3

-- Contador de diagnóstico.
Service._spawned = 0
Service._respawned = 0

--- @param monsterService any
--- @param worldService any
function Service.SetDependencies(monsterService: any, worldService: any)
	Service._monsterService = monsterService
	Service._worldService = worldService
end

--- Puntos de spawn declarados en el mapa de un mundo.
---
--- Lee los marcadores `BrainrotSpawn_*` dentro de `Workspace.Worlds.<WorldId>`
--- y devuelve sus posiciones, ordenadas por nombre (igual que
--- `MatchService.CollectMonsterSpawnPoints`).
--- @param worldId string
--- @return { BasePart }
function Service.CollectSpawnPoints(worldId: string): { BasePart? }
	local points = {}

	if type(worldId) ~= "string" or worldId == "" then
		return points
	end

	local worlds = Workspace:FindFirstChild("Worlds")
	local worldFolder = worlds and worlds:FindFirstChild(worldId)

	if not worldFolder then
		return points
	end

	local spawnsFolder = worldFolder:FindFirstChild("BrainrotSpawns")

	if not spawnsFolder then
		return points
	end

	for _, child in ipairs(spawnsFolder:GetChildren()) do
		if child:IsA("BasePart") and child.Name:match("^BrainrotSpawn_") then
			table.insert(points, child :: BasePart)
		end
	end

	table.sort(points, function(a, b)
		return a.Name < b.Name
	end)

	return points
end

--- Genera los grupos de brainrots para un mundo.
---
--- Usa `BrainrotRules.RollGroups` con un generador de números basado en
--- el `worldId`, para que el reparto sea estable: el mismo mundo siempre
--- genera los mismos tipos en los mismos slots.
--- @param worldId string
--- @return { { Species: string, Count: number, Slot: number } }?
function Service.RollGroups(worldId: string)
	local hash = 0

	for i = 1, #worldId do
		hash = (hash * 31 + string.byte(worldId, i)) % 100000
	end

	local function roll()
		hash = (hash * 374761393 + 1) % 100000
		return hash / 100000
	end

	return BrainrotRules.RollGroups(worldId, roll)
end

--- Distribuye los grupos en los puntos de spawn disponibles.
---
--- Cada grupo se asigna a un slot de spawn: `Slot` es el índice del grupo,
--- y se mapea al N-ésimo punto de spawn disponible. Si hay más grupos que puntos,
--- se reutilizan (el brainrot aparece en el mismo lugar que otro).
---
--- Los individuos de un grupo se distribuyen a lo largo de spawn points
--- consecutivos en vez de agruparse en uno solo: con PerGroup = 2-3 y un
--- solo punto, el brainrot aparecería "amontonado" sobre sí mismo y no se
--- aprovecharían los marcadores repartidos por el mapa.
--- @param worldId string
--- @return { { Species: string, Position: Vector3 } }?
function Service.BuildSpawnAssignments(worldId: string): { { Species: string, Position: Vector3 } }?
	local points = Service.CollectSpawnPoints(worldId)

	if #points == 0 then
		return nil
	end

	local groups = Service.RollGroups(worldId)

	if not groups then
		return nil
	end

	local assignments = {}
	local pointIndex = 0

	for _, group in ipairs(groups) do
		for _ = 1, group.Count do
			-- Avanza de forma cíclica por los spawn points disponibles,
			-- distribuyendo individuos de un grupo en puntos distintos.
			local slot = pointIndex % #points
			local point = points[slot + 1]
			pointIndex += 1

			if point and point:IsA("BasePart") then
				local position = point.Position
				table.insert(assignments, {
					Species = group.Species,
					Position = Vector3.new(position.X, position.Y + 2, position.Z),
				})
			end
		end
	end

	return assignments
end

--- Genera todos los brainrots de un mundo.
--- @param worldId string
--- @return number spawned
function Service.SpawnBrainrotsForWorld(worldId: string): number
	if not Service._monsterService then
		Logger.Warn("BrainrotService: sin MonsterService; no se generan brainrots.")
		return 0
	end

	local assignments = Service.BuildSpawnAssignments(worldId)

	if not assignments then
		Logger.Debug(("BrainrotService: %s no tiene puntos de spawn"):format(worldId))
		return 0
	end

	local spawned = 0

	for _, assignment in ipairs(assignments) do
		local def = MonsterDefinitions.Get(assignment.Species)

		if def then
			local monsterId = Service._monsterService.Spawn(assignment.Species, assignment.Position, worldId)

			if monsterId then
				spawned += 1
				Service._activeBrainrots[monsterId] = {
					WorldId = worldId,
					Species = assignment.Species,
				}
				Service._spawned += 1
			end
		else
			Logger.Warn(("BrainrotService: especie desconocida '%s'"):format(assignment.Species))
		end
	end

	Logger.Info(("BrainrotService: %d brainrot(s) generados en %s"):format(spawned, worldId))
	return spawned
end

--- Genera brainrots para TODOS los mundos que tienen marcadores.
--- @return number total
function Service.SpawnAllWorlds(): number
	local total = 0

	if not Service._worldService then
		Logger.Warn("BrainrotService: sin WorldService.")
		return 0
	end

	local worlds = Workspace:FindFirstChild("Worlds")

	if not worlds then
		return 0
	end

	for _, folder in ipairs(worlds:GetChildren()) do
		if folder:IsA("Folder") then
			local worldId = folder.Name
			local spawns = folder:FindFirstChild("BrainrotSpawns")

			if spawns then
				total += Service.SpawnBrainrotsForWorld(worldId)
			end
		end
	end

	return total
end

--- Despawn de un brainrot individual.
--- @param brainrotId number
function Service.DespawnBrainrot(brainrotId: number)
	if not Service._monsterService then
		return
	end

	local entry = Service._activeBrainrots[brainrotId]

	if entry then
		if Service._monsterService.Despawn(brainrotId) then
			Service._activeBrainrots[brainrotId] = nil
		end
	end
end

--- Limpia TODOS los brainrots (fin de sesión, cambio de mundo).
--- @return number removed
function Service.ClearAll(): number
	if not Service._monsterService then
		return 0
	end

	local removed = 0

	for brainrotId in pairs(Service._activeBrainrots) do
		if Service._monsterService.Despawn(brainrotId) then
			removed += 1
		end
	end

	Service._activeBrainrots = {}

	Logger.Info(("BrainrotService: %d brainrot(s) limpiados"):format(removed))
	return removed
end

--- Watchdog de respawn: rehace los brainrots caídos.
---
--- Se suscribe a `RunService.Heartbeat` en `Start` y comprueba si los monstruos
--- registrados siguen vivos en `MonsterService`. Si uno desapareció, lo reemplaza.
--- @param now number
function Service.TickRespawn(now: number)
	if not Service._monsterService then
		return
	end

	local toRespawn = {}

	for brainrotId, entry in pairs(Service._activeBrainrots) do
		local record = Service._monsterService.Get(brainrotId)

		if not record then
			table.insert(toRespawn, entry)
			Service._activeBrainrots[brainrotId] = nil
		end
	end

	for _, entry in ipairs(toRespawn) do
		-- Buscar un punto de spawn en el mundo del brainrot caído.
		local points = Service.CollectSpawnPoints(entry.WorldId)

		if #points > 0 then
			-- Usar un slot determinístico basado en el índice de espacie.
			local slot = (#points > 0) and (Service._spawned % #points) or 0
			local point = points[slot + 1]

			if point then
				local position = point.Position
				local monsterId = Service._monsterService.Spawn(
					entry.Species,
					Vector3.new(position.X, position.Y + 2, position.Z),
					entry.WorldId
				)

				if monsterId then
					Service._activeBrainrots[monsterId] = {
						WorldId = entry.WorldId,
						Species = entry.Species,
					}
					Service._respawned += 1
				end
			end
		end
	end
end

--- Número de brainrots vivos.
--- @return number
function Service.GetAliveCount(): number
	local count = 0
	for _ in pairs(Service._activeBrainrots) do
		count += 1
	end
	return count
end

--- Resumen de diagnóstico.
--- @return { [string]: number }
function Service.GetStats(): { [string]: number }
	return {
		spawned = Service._spawned,
		respawned = Service._respawned,
		alive = Service.GetAliveCount(),
	}
end

--- Inicialización. Idempotente.
--- @param _maid any?
--- @return boolean success
function Service.Init(_maid: any?): boolean
	if Service.IsInitialized then
		return true
	end

	Service._activeBrainrots = {}
	Service._spawned = 0
	Service._respawned = 0
	Service.IsInitialized = true
	return true
end

--- Arranque. Registra el watchdog de respawn.
--- @param _maid any?
--- @return boolean success
function Service.Start(_maid: any?): boolean
	if not Service.IsInitialized then
		Logger.Error("BrainrotService: Start sin Init")
		return false
	end

	if not Service._monsterService then
		Logger.Error("BrainrotService: sin MonsterService; no se pueden generar brainrots.")
		return false
	end

	Service._maid = _maid

	-- El watchdog de respawn corre una vez por intervalo. Se usa RunService
	-- porque no hay un RemoteEvent para dispararlo: el servidor decide
	-- silenciamente cuándo rehacer a un brainrot caído.
	if _maid and Service.RespawnInterval > 0 then
		local lastCheck = 0

		_maid:Connect(RunService.Heartbeat, function(dt: number)
			lastCheck += dt

			if lastCheck >= Service.RespawnInterval then
				lastCheck = 0
				Service.TickRespawn(tick())
			end
		end)
	end

	-- Generar brainrots en TODOS los mundos que tengan marcadores.
	--
	-- No se espera a que un jugador entre: los brainrots son fauna del
	-- mapa, y deben estar allí antes de que el jugador aparezca, para
	-- que su primer paso por el bosje no sea "un mundo vacío".
	local total = Service.SpawnAllWorlds()
	Logger.Info(("BrainrotService: %d brainrot(s) en el mapa"):format(total))

	return true
end

--- Apagado. Limpia todo.
--- @return boolean success
function Service.Destroy(): boolean
	Service.ClearAll()
	Service._activeBrainrots = {}
	Service._monsterService = nil
	Service._worldService = nil
	Service._maid = nil
	Service.IsInitialized = false
	return true
end

return Service
