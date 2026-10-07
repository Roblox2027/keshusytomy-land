--!strict
--[[
	MiniBossService
	MINI-BOSSES por zona, con enfriamiento (FASE 15).

	QUE HACE Y QUE DELEGA
	-------------------------
	NO decide nada de diseno: el catalogo, los tiers, las
	probabilidades, los enfriamientos, las fases y las
	recompensas escaladas son de `MiniBossRules` (puro,
	probado). Este servicio aporta lo que el motor:
	el conocimiento de las ZONAS del mapa, la proximidad
	del jugador, el spawn a traves de `MonsterService` y
	el registro de muertes.

	POR QUE NO ES UN BOSS
	-------------------------
	Un mini-boss es contenido REPETIBLE: aparece en su zona,
	se derrota, y VUELVE a aparecer tras su enfriamiento. El
	boss principal es el cierre del mundo: una vez, en su
	arena, con barra propia. De ahi las dos diferencias de
	este servicio:

	  1. El enfriamiento. Sin el, la zona es una sala de
	     espera permanente.
	  2. La recompensa la cobra QUIEN MATO, no todos los
	     del mundo: el bonus de tier es del asesino, como
	     el XP de cualquier fauna.

	EL SPAWN
	-------------
	Un mini-boss SOLO aparece en una zona ACTIVA (el jugador
	esta cerca), cuando su enfriamiento ha terminado, y con
	la probabilidad de su tier. Las tres condiciones se
	comprueban en `TrySpawnForZone`; ninguna se salta.

	LA MUERTE
	---------------
	`MonsterService` notifica la muerte ANTES de limpiar el
	registro. Este servicio mira si el id muerto es un
	mini-boss SUYO: si lo es, paga el bonus escalado, arranca
	el enfriamiento y lo borra del registro. Si no, no hace
	nada: la fauna normal no es asunto de este servicio.

	FALLA DE ZONA NO DETECTADA
	------------------------------
	Si una zona del catalogo no existe en el mapa (el
	generador no la construyo), el mini-boss simplemente
	nunca aparece y se avisa UNA vez en el log. No es un
	error de ejecucion: es un defecto de contenido que la
	auditoria (`MiniBossRules.Audit`) no puede ver porque
	solo lee el catalogo.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local UTILS = SHARED:WaitForChild("Utils")

local MiniBossRules = require(SHARED:WaitForChild("Libraries"):WaitForChild("MiniBossRules"))
local ZoneRules = require(SHARED:WaitForChild("Libraries"):WaitForChild("ZoneRules"))
local Logger = require(UTILS:WaitForChild("Logger"))

local Service = {}

Service.IsInitialized = false

-- worldId -> zona -> marca de la ultima derrota (os.clock).
-- Es la unica memoria del enfriamiento: no se guarda en
-- perfil porque el enfriamiento es DEL SERVIDOR, no del
-- jugador (un mini-boss no reaparece antes porque cambies
-- de personaje).
Service._cooldowns = {}

-- monsterId -> registro del mini-boss vivo.
Service._live = {}

-- worldId -> zona -> monsterId vivo. Una zona nunca tiene
-- dos mini-bosses a la vez: la zona es el lugar que el
-- mini-boss defiende.
Service._zoneOccupant = {}

-- worldId -> zona -> true (aviso unico de zona ausente).
Service._warnedMissing = {}

-- Servicios inyectados por `ServerMain`.
Service._monsterService = nil
Service._playerService = nil
Service._questService = nil
Service._nightService = nil

-- LootService: observador opcional (mision V2, FASE 23/25).
Service._lootService = nil

-- Hilo de mantenimiento.
Service._thread = nil
Service._running = false

-- Cadencia del mantenimiento.
--
-- 2 s: el mini-boss no debe aparecer medio segundo despues
-- de que el jugador entra en la zona, pero tampoco hay que
-- medir la proximidad a 60 Hz. `ZoneRules.ActiveDistance`
-- son 220 studs: a 2 s, el peor caso es un mini-boss que
-- tarda dos segundos en notar que hay alguien cerca.
Service.TickInterval = 2

-- ---------------------------------------------------------------------------
-- INYECCION
-- ---------------------------------------------------------------------------

--- @param monsterService any
--- @param playerService any?
--- @param questService any?
--- @param nightService any?
function Service.SetDependencies(
	monsterService: any,
	playerService: any?,
	questService: any?,
	nightService: any?
)
	Service._monsterService = monsterService
	Service._playerService = playerService
	Service._questService = questService
	Service._nightService = nightService
end

--- Inyecta el `LootService` (mision V2, FASE 23/25).
--- @param lootService any
function Service.SetLootService(lootService: any)
	Service._lootService = lootService
end

-- ---------------------------------------------------------------------------
-- MAPA DE ZONAS
-- ---------------------------------------------------------------------------

-- Cache del mundo: zona -> { Center = Vector3, Folder = Instance }.
-- Se construye UNA vez por mundo y se invalida cuando el
-- arbol del mundo cambia (apagado del servidor).
Service._zoneCache = {}

--- Carpeta de zonas de un mundo, o nil.
---
--- La ruta es la misma que leen `MatchService` y
--- `BombService`: `Workspace.Worlds.<WorldId>.Zones`.
--- Se lee del MAPA, no del generador: el servicio
--- funciona con cualquier mundo que el generador
--- construya, sin depender de `WorldService` (cuyo
--- `GetWorld` devuelve la DEFINICION, no la carpeta).
--- @param worldId string
--- @return Instance?
local function zonesFolder(worldId: string): Instance?
	local worlds = Workspace:FindFirstChild("Worlds")
	local worldFolder = worlds and worlds:FindFirstChild(worldId)

	if not worldFolder then
		return nil
	end

	local zones = worldFolder:FindFirstChild("Zones")

	if zones and zones:IsA("Folder") then
		return zones
	end

	return nil
end

--- Centro de una zona del mapa, o nil.
---
--- El generador (`tools/worlds.js`) construye cada zona como
--- una carpeta `Zone_<WorldId>_<ZoneId>` con una losa central
--- `<...>_Core` en el centro de la zona. Esa losa es el
--- CONTRATO de posicion: el mini-boss aparece donde el
--- jugador puede llegar y pelear, no en el borde.
---
--- El cache se construye por mundo la primera vez que se
--- pregunta ese mundo: recorrer el mapa en cada tick es
--- trabajo desperdiciado, y el mapa no cambia mientras el
--- servidor vive.
--- @param worldId string
--- @param zoneId string
--- @return Vector3?
function Service.GetZoneCenter(worldId: string, zoneId: string): Vector3?
	if type(worldId) ~= "string" or type(zoneId) ~= "string" then
		return nil
	end

	local cache = Service._zoneCache[worldId]

	if cache == nil then
		cache = {}
		Service._zoneCache[worldId] = cache

		local folder = zonesFolder(worldId)

		if folder then
			for _, child in ipairs(folder:GetChildren()) do
				if child:IsA("Folder") and string.sub(child.Name, 1, 5) == "Zone_" then
					-- El centro lo da la losa central, no el
					-- bounding box: la zona es una elipse y su
					-- caja abarca tambien los rebordes.
					local core = child:FindFirstChild(child.Name .. "_Core")

					if core and core:IsA("BasePart") then
						local zoneId = string.sub(child.Name, (#"Zone_" + #worldId + 2))
						cache[zoneId] = core.Position
					end
				end
			end
		end
	end

	return cache[zoneId]
end

--- Invalida el cache de zonas (el mapa se descargo).
--- @param worldId any
function Service.InvalidateZoneCache(worldId: any)
	if type(worldId) == "string" then
		Service._zoneCache[worldId] = nil
	end
end

-- ---------------------------------------------------------------------------
-- CONSULTA
-- ---------------------------------------------------------------------------

--- Mini-boss vivo por id de monstruo.
--- @param monsterId any
--- @return any?
function Service.GetLive(monsterId: any): any?
	if type(monsterId) ~= "number" then
		return nil
	end

	return Service._live[monsterId]
end

--- Cuantos mini-bosses estan vivos.
--- @return number
function Service.GetLiveCount(): number
	local count = 0

	for _ in pairs(Service._live) do
		count += 1
	end

	return count
end

--- Segundos que faltan para que el mini-boss de una zona
--- pueda volver a aparecer.
--- @param worldId any
--- @param zoneId any
--- @return number
function Service.GetCooldownRemaining(worldId: any, zoneId: any): number
	if type(worldId) ~= "string" or type(zoneId) ~= "string" then
		return 0
	end

	local world = Service._cooldowns[worldId]
	local last = world and world[zoneId]

	if not last then
		return 0
	end

	return math.max(0, last - os.clock())
end

-- ---------------------------------------------------------------------------
-- SPAWN
-- ---------------------------------------------------------------------------

--- Intenta generar el mini-boss de una zona.
---
--- Las comprobaciones van en orden de precio: la zona tiene
--- que existir en el mapa, no estar ocupada, tener su
--- enfriamiento cumplido, estar ACTIVA para el jugador, y
--- por ultimo la tirada de probabilidad del tier.
--- @param worldId string
--- @param zoneId string
--- @param mini any definicion de `MiniBossRules`
--- @param player Player jugador que dispara la comprobacion
--- @return number? monsterId
function Service.TrySpawnForZone(
	worldId: string,
	zoneId: string,
	mini: any,
	player: Player
): number?
	if not Service._monsterService or not Service._monsterService.Spawn then
		return nil
	end

	-- La zona existe en el MAPA, no solo en el catalogo.
	local center = Service.GetZoneCenter(worldId, zoneId)

	if not center then
		if not Service._warnedMissing[worldId] then
			Service._warnedMissing[worldId] = {}
		end

		if not Service._warnedMissing[worldId][zoneId] then
			Service._warnedMissing[worldId][zoneId] = true
			Logger.Warn(
				("MiniBossService: '%s' declara zona '%s' que el mapa no tiene"):format(
					worldId,
					zoneId
				)
			)
		end

		return nil
	end

	-- Una zona tiene UNA sola ocupacion a la vez.
	if Service._zoneOccupant[worldId] and Service._zoneOccupant[worldId][zoneId] then
		return nil
	end

	-- Enfriamiento cumplido.
	if Service.GetCooldownRemaining(worldId, zoneId) > 0 then
		return nil
	end

	-- La zona esta ACTIVA: el jugador esta lo bastante
	-- cerca para que valga la pena tener contenido aqui.
	-- `ZoneRules` es la UNICA distancia: si este servicio
	-- inventara la suya, el mini-boss apareceria donde el
	-- sistema de zonas dice que no hay nadie.
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")

	if not root or not root:IsA("BasePart") then
		return nil
	end

	local lod = ZoneRules.LodAt((root.Position - center).Magnitude)

	if not ZoneRules.HasFullAI(lod) then
		return nil
	end

	-- Probabilidad del tier. `ShouldSpawn` es pura: el azar
	-- lo pone aqui y la decision es comprobable en pruebas.
	if not MiniBossRules.ShouldSpawn(mini, math.random()) then
		return nil
	end

	local monsterId = Service._monsterService.Spawn(mini.Id, center, worldId)

	if not monsterId then
		return nil
	end

	Service._live[monsterId] = {
		MonsterId = monsterId,
		Mini = mini,
		WorldId = worldId,
		ZoneId = zoneId,
		SpawnedAt = os.clock(),
	}

	Service._zoneOccupant[worldId] = Service._zoneOccupant[worldId] or {}
	Service._zoneOccupant[worldId][zoneId] = monsterId

	Logger.Info(
		("MiniBossService: '%s' aparece en %s/%s (nivel de tier %s)"):format(
			mini.Id,
			worldId,
			zoneId,
			tostring(mini.Tier)
		)
	)

	return monsterId
end

-- ---------------------------------------------------------------------------
-- MUERTE
-- ---------------------------------------------------------------------------

--- Notifica la muerte de un monstruo.
---
--- La llama `MonsterService` DESPUES de pagar la recompensa
--- de fauna y ANTES de liberar el registro. Si el monstruo
--- no es un mini-boss registrado, esta funcion no hace
--- nada: ese es el caso normal y debe ser barato.
--- @param monsterId number
--- @param record table registro de `MonsterService`
function Service.OnMonsterDied(monsterId: number, record: table)
	local live = Service._live[monsterId]

	if not live then
		return
	end

	local mini = live.Mini
	local worldId = live.WorldId
	local zoneId = live.ZoneId

	-- Quien lo mato lo decide el Humanoid, igual que la fauna.
	local sourceId = record.Humanoid and record.Humanoid:GetAttribute("LastDamageSource")
	local killer = if type(sourceId) == "number" then Players:GetPlayerByUserId(sourceId) else nil

	-- BONUS DE TIER. La recompensa base de la definicion ya
	-- la cobro `MonsterService` como fauna; esta es la parte
	-- escalada por noche y tier, y la cobra el ASESINO: es
	-- quien enfrento al mini-boss, no quien paseaba cerca.
	--
	-- La noche NO viene del registro: `MonsterService` no
	-- guarda la noche del spawn (el mini-boss puede vivir
	-- dias enteros), y la escala se mide AL MORIR, que es
	-- cuando se cobra.
	--
	-- El pago pasa por `PlayerService.AddRewards`, el mismo
	-- camino que el XP de la fauna: una sola forma de ganar
	-- recompensas y, por tanto, una sola que auditar.
	if killer and Service._playerService and Service._playerService.AddRewards then
		local night = 1

		if Service._nightService and Service._nightService.GetNight then
			local current = Service._nightService.GetNight()

			if type(current) == "number" then
				night = current
			end
		end

		local reward = MiniBossRules.RewardFor(mini, night, 1)
		pcall(Service._playerService.AddRewards, killer, reward.XP, reward.Coins)
	end

	-- Progreso de misiones: "derrota un mini-boss" solo
	-- avanza con una muerte real de un mini-boss registrado.
	if killer and Service._questService and Service._questService.RecordMetric then
		Service._questService.RecordMetric(killer, "MiniBossDefeated", 1)
	end

	-- LOOT (mision V2, FASE 23/25): el mini-boss SIEMPRE suelta
	-- material, y a veces doble. Es el observador opcional de turno:
	-- sin el, el mini-boss paga su tier y listo.
	if killer and Service._lootService and Service._lootService.OnMiniBossDefeated then
		pcall(Service._lootService.OnMiniBossDefeated, killer, worldId)
	end

	-- LIMPIEZA: registro, ocupacion de zona y ENFRIAMIENTO.
	-- El enfriamiento arranca AQUI, no cuando se intento
	-- generar: derrotarlo es lo que reinicia el ciclo.
	Service._live[monsterId] = nil

	if Service._zoneOccupant[worldId] then
		if Service._zoneOccupant[worldId][zoneId] == monsterId then
			Service._zoneOccupant[worldId][zoneId] = nil
		end
	end

	Service._cooldowns[worldId] = Service._cooldowns[worldId] or {}
	Service._cooldowns[worldId][zoneId] = os.clock() + MiniBossRules.CooldownFor(mini)

	Logger.Info(
		("MiniBossService: '%s' derrotado en %s/%s; enfriamiento %d s"):format(
			mini.Id,
			worldId,
			zoneId,
			math.floor(MiniBossRules.CooldownFor(mini))
		)
	)
end

-- ---------------------------------------------------------------------------
-- MANTENIMIENTO
-- ---------------------------------------------------------------------------

--- Un paso de mantenimiento.
---
--- Recorre los jugadores y, para cada uno, sortea los
--- mini-bosses de SU mundo. El coste es por jugador y por
--- zona declarada (tres por mundo), no por enemigo: el
-- sistema no puede crecer con la poblacion.
--- @return number spawns generados
function Service.Tick(): number
	local spawned = 0

	for _, player in ipairs(Players:GetPlayers()) do
		local worldId = player:GetAttribute("World")

		if type(worldId) == "string" then
			-- Cada mini-boss del mundo se INTENTA una vez por
			-- jugador: las comprobaciones (zona ocupada,
			-- enfriamiento, proximidad, tirada) son las que
			-- deciden, y todas son baratas.
			for _, mini in ipairs(MiniBossRules.GetForWorld(worldId)) do
				Service.TrySpawnForZone(worldId, mini.Zone, mini, player)
			end
		end
	end

	return spawned
end

-- ---------------------------------------------------------------------------
-- CICLO DE VIDA DEL SERVICIO
-- ---------------------------------------------------------------------------

local function runMaintenance()
	while Service._running do
		local ok, err = pcall(Service.Tick)

		if not ok then
			-- Un fallo de proximidad no puede matar el sistema:
			-- se avisa y se sigue en el siguiente paso.
			Logger.Error(("MiniBossService: el mantenimiento fallo: %s"):format(tostring(err)))
		end

		task.wait(Service.TickInterval)
	end
end

--- Inicializacion. Idempotente.
--- @param maid any?
--- @return boolean success
function Service.Init(maid: any?): boolean
	if Service.IsInitialized then
		return true
	end

	Service._cooldowns = {}
	Service._live = {}
	Service._zoneOccupant = {}
	Service._warnedMissing = {}
	Service._zoneCache = {}

	Service.IsInitialized = true
	return true
end

--- Arranca el mantenimiento. Idempotente.
--- @return boolean success
function Service.Start(): boolean
	if not Service.IsInitialized then
		Logger.Error("MiniBossService: Start sin Init")
		return false
	end

	if Service._running then
		return true
	end

	Service._running = true
	Service._thread = task.spawn(runMaintenance)

	Logger.Info(
		("MiniBossService: listo (%d mini-bosses en el catalogo)"):format((function(): number
			local total = 0
			for _, list in pairs(MiniBossRules.ByWorld) do
				total += #list
			end
			return total
		end)())
	)

	return true
end

--- Para el servicio y limpia el estado. Idempotente.
--- @return boolean success
function Service.Destroy(): boolean
	Service._running = false

	if Service._thread then
		pcall(task.cancel, Service._thread)
		Service._thread = nil
	end

	-- Los mini-bosses VIVOS son monstruos de `MonsterService`:
	-- su cleanup es el de cualquier enemigo (`ClearAll` del
	-- servicio de monstruos). Aqui solo se olvida el registro
	-- propio: no se destruye nada, no hay nada que destruir.
	Service._live = {}
	Service._zoneOccupant = {}
	Service._cooldowns = {}
	Service._zoneCache = {}
	Service._warnedMissing = {}
	Service.IsInitialized = false
	return true
end

return Service
