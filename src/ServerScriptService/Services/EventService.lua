--!strict
--[[
	EventService
	EVENTOS DE MUNDO y eventos raros (FASES 17 y 18).

	QUE HACE Y QUE DELEGA
	-----------------------
	NO calcula nada: el catalogo, las rarezas, la seleccion, la
	caducidad y la recompensa son de `EventRules` (puro, probado).
	Este servicio aporta lo que el motor: el hilo de mantenimiento,
	el registro de instancias activas, la publicacion para el HUD
	y el pago.

	LA REGLA DE AUTORIDAD
	---------------------
	El UNICO camino de cierre es `FinishEvent`. Tanto el tick (por
	tiempo) como la salida del mundo (por cleanup) pasan por el,
	y `EventRules.Finish` es idempotente: la segunda llamada no
	paga y no vuelve a limpiar.

	LA SUMA DE LA AMENAZA
	-----------------------
	`GetWorldThreat` devuelve el multiplicador que los eventos
	ABIERTOS de un mundo aportan a la dificultad. `SpawnDirector`
	lo pasa a `DifficultyRules.Resolve`, que ACOTA el resultado.
	Este servicio no multiplica nada: solo suma las `Threat` de sus
	propios eventos y las devuelve.

	MULTIPLAYER
	-------------
	Un evento es MUNDIAL: lo comparten todos los jugadores del
	mundo. La recompensa de terminar se paga a cada jugador
	PRESENTE al cerrarse, y el registro es por mundo, no por
	jugador: dos jugadores no pueden tener dos "suyos" del mismo
	evento pagandose dos veces.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local UTILS = SHARED:WaitForChild("Utils")

local EventRules = require(SHARED:WaitForChild("Libraries"):WaitForChild("EventRules"))
local Logger = require(UTILS:WaitForChild("Logger"))

local Service = {}

Service.IsInitialized = false

-- Instancia activa -> registro de `EventRules.Start`.
-- La tabla es por INSTANCIA (no por evento): el mismo evento
-- puede abrirse otra vez en otro mundo o tras cerrarse.
Service._active = {}

-- Siguiente id de instancia. Empieza en 1: un 0 se leeria como
-- "sin evento" en cualquier log.
Service._nextInstance = 1

-- Ultima tirada por mundo. El evento no se sortea cada tick:
-- hay una ventana entre sorteos para que el mundo respire.
Service._lastRoll = {}

-- Segundos entre sorteos de un mundo.
--
-- No es una constante magica: es el PROMEDIO de la ventana. Con
-- ~0.30 de rareza acumulada y una ventana de 90 s, un mundo tiene
-- un evento cada ~5 minutos de media. `EventRules.Roll` sigue
-- decidiendo si esta tirada concreta da evento o no.
Service.RollWindow = 90

-- Servicios inyectados por `ServerMain`.
Service._nightService = nil
Service._playerService = nil
Service._questService = nil

-- MonsterService: el CUERPO del evento (mision V2, Bloque 1).
-- Opcional como todos los observadores: sin el, el evento sigue
-- abriendo, sumando amenaza y pagando; lo que falta es lo unico
-- que el jugador VE en el mapa.
Service._monsterService = nil

-- Estado del cuerpo por instancia: bajas contadas y enemigos
-- generados que aun viven. Va APARTE de `EventRules.Start` porque
-- ese registro es puro y probado sin motor; esto es motor.
Service._bodies = {}

-- Cache de centros de zona por mundo (mismo contrato que
-- `MiniBossService.GetZoneCenter`: la losa `_Core` del generador).
Service._zoneCache = {}

-- Hilo de mantenimiento.
Service._thread = nil
Service._running = false

-- ---------------------------------------------------------------------------
-- INYECCION
-- ---------------------------------------------------------------------------

--- @param nightService any
--- @param playerService any?
--- @param questService any?
--- @param monsterService any? (mision V2: el cuerpo del evento)
function Service.SetDependencies(
	nightService: any,
	playerService: any?,
	questService: any?,
	monsterService: any?
)
	Service._nightService = nightService
	Service._playerService = playerService
	Service._questService = questService
	Service._monsterService = monsterService
end

-- ---------------------------------------------------------------------------
-- CONSULTA
-- ---------------------------------------------------------------------------

--- Eventos activos de un mundo (tabla nueva).
--- @param worldId any
--- @return { any }
function Service.GetActiveForWorld(worldId: any): { any }
	local out = {}

	if type(worldId) ~= "string" then
		return out
	end

	for _, active in pairs(Service._active) do
		if active.WorldId == worldId and not active.CleanedUp then
			table.insert(out, active)
		end
	end

	return out
end

--- Eventos activos en TODO el servidor.
--- @return number
function Service.GetActiveCount(): number
	local count = 0

	for _, active in pairs(Service._active) do
		if not active.CleanedUp then
			count += 1
		end
	end

	return count
end

--- Multiplicador de amenaza que aportan los eventos abiertos de un mundo.
---
--- Es la SUMA de las `Threat` de los eventos activos, acotada a
--- [0.5, 2] por `EventRules.ThreatOf` al abrirse. `SpawnDirector`
--- la pasa a `DifficultyRules.Resolve` como `eventMultiplier`, y
--- esa funcion tiene sus propios topes: aunque aqui saliera un
--- numero raro, el perfil final sigue acotado.
--- @param worldId any
--- @return number threat 1.0 = sin presion extra
function Service.GetWorldThreat(worldId: any): number
	local threat = 1.0

	if type(worldId) ~= "string" then
		return threat
	end

	for _, active in pairs(Service._active) do
		if active.WorldId == worldId and not active.CleanedUp then
			local event = EventRules.Get(active.EventId)
			threat += EventRules.ThreatOf(event) - 1.0
		end
	end

	return math.clamp(threat, 0.5, 3.0)
end

--- Un evento activo por id de instancia.
--- @param instanceId any
--- @return any?
function Service.Get(instanceId: any): any?
	if type(instanceId) ~= "number" then
		return nil
	end

	return Service._active[instanceId]
end

--- Jugadores presentes en un mundo.
---
--- Se resuelve por el atributo `World` que escribe `MatchService`
--- en cada traslado: es la misma fuente de verdad que usa
--- `HordeService`, y no se pide a `MatchService` aqui para no
-- crear una dependencia circular.
--- @param worldId any
--- @return { Player }
function Service.GetPlayersInWorld(worldId: any): { Player }
	local out = {}

	if type(worldId) ~= "string" then
		return out
	end

	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("World") == worldId then
			table.insert(out, player)
		end
	end

	return out
end

-- ---------------------------------------------------------------------------
-- CICLO DE VIDA DEL EVENTO
-- ---------------------------------------------------------------------------

--- Abre un evento en un mundo.
---
--- Es el UNICO punto de apertura: tanto el sorteo del tick como
--- las pruebas y el admin pasan por el. Aplica los limites de
--- `EventRules` ANTES de crear la instancia, y paga la recompensa
--- solo al CERRARSE, no al abrirse.
--- @param worldId string
--- @param eventId string? definicion concreta (nil = sorteo de `EventRules.Roll`)
--- @param roll number? tirada 0..1 cuando `eventId` es nil
--- @return any? instancia activa, o nil si no se pudo abrir
function Service.StartEvent(worldId: string, eventId: string?, roll: number?): any?
	if type(worldId) ~= "string" then
		return nil
	end

	-- Un mundo que no existe en el catalogo no puede albergar
	-- eventos: `EventRules.GetForWorld` devuelve lista vacia y
	-- el sorteo no daria nada, pero la comprobacion explicita
	-- convierte ese "nada" en un rechazo legible en el log.
	local definition = nil

	if eventId then
		definition = EventRules.Get(eventId)

		if not definition then
			Logger.Warn(("EventService: evento desconocido '%s'"):format(tostring(eventId)))
			return nil
		end

		-- Un evento explicito tiene que pertenecer al mundo:
		-- los propios mas los raros (que son transversales).
		-- `GetForWorld` es exactamente esa lista; un evento
		-- de OTRO mundo no aparece en ella.
		local belongs = false

		for _, candidate in ipairs(EventRules.GetForWorld(worldId)) do
			if candidate.Id == eventId then
				belongs = true
				break
			end
		end

		if not belongs then
			Logger.Warn(
				("EventService: '%s' no es evento de '%s'"):format(tostring(eventId), worldId)
			)
			return nil
		end
	else
		definition = EventRules.Roll(worldId, roll or math.random(), true)
	end

	if not definition then
		return nil
	end

	-- Limites: por mundo y global. Se comprueban ANTES de crear
	-- la instancia: un evento que no puede abrirse no debe dejar
	-- basura en el registro.
	if #Service.GetActiveForWorld(worldId) >= EventRules.MaxActivePerWorld then
		return nil
	end

	if Service.GetActiveCount() >= EventRules.MaxActiveTotal then
		return nil
	end

	local night = 1

	if Service._nightService and Service._nightService.GetNight then
		night = Service._nightService.GetNight()
	end

	local instanceId = Service._nextInstance
	Service._nextInstance += 1

	local active = EventRules.Start(instanceId, definition, worldId, night, os.clock())
	Service._active[instanceId] = active

	Logger.Info(
		("EventService: '%s' abierto en %s (noche %d, %d s)"):format(
			active.EventId,
			worldId,
			active.Night,
			active.Duration
		)
	)

	-- El cuerpo: lo que el evento PONE en el mapa. Va ANTES de
	-- publicar para que el primer aviso del HUD ya venga con
	-- objetivo.
	Service.SpawnBody(active)

	Service.Publish()
	return active
end

--- Cierra un evento. UNICO camino de cierre, idempotente.
---
--- Si el cierre es NATURAL (por tiempo) paga la recompensa a los
--- jugadores presentes. Si es CANCELADO (salida del mundo, apagado
--- del servidor) no paga nada: lo que el jugador estaba haciendo
--- en un mundo que ya dejo de existir no se cobra.
--- @param instanceId number
--- @param cancelled boolean?
--- @return boolean changed
function Service.FinishEvent(instanceId: number, cancelled: boolean?): boolean
	local active = Service.Get(instanceId)

	if not active then
		return false
	end

	local changed = EventRules.Finish(active, cancelled)

	if changed then
		-- El cuerpo se limpia SIEMPRE, por el unico camino de cierre:
		-- un enemigo de evento que sobrevive al evento es un NPC
		-- huerfano que nadie volvera a contar ni a limpiar.
		Service.CleanupBody(active)

		if not cancelled then
			Service.PayReward(active)
			Service.RecordCompletion(active)
		end

		local status = cancelled and "cancelado" or "completado"
		Logger.Info(
			("EventService: '%s' cerrado en %s (%s)"):format(active.EventId, active.WorldId, status)
		)
	end

	Service._bodies[instanceId] = nil
	Service.Publish()
	return changed
end

--- Paga la recompensa de terminar un evento.
---
--- La recompensa es COMPARTIDA: el evento es mundial y todos los
--- jugadores presentes cuando se cierra la cobran ENTERA. Dividirla
--- haria que entrar un jugador al mundo RESTARA recompensa a los
--- demas, que es el efecto perverso que ya se evita en `HordeService`.
---
--- El pago pasa por `PlayerService.AddRewards`, que es el mismo
--- camino que el XP de un monstruo: una sola forma de ganar XP y
--- monedas en el servidor, y por tanto una sola que auditar.
--- @param active any
function Service.PayReward(active: any)
	local players = Service._playerService

	if not players or not players.AddRewards then
		return
	end

	local reward = EventRules.RewardFor(active)
	local targets = Service.GetPlayersInWorld(active.WorldId)

	for _, player in ipairs(targets) do
		pcall(players.AddRewards, player, reward.XP, reward.Coins)
	end
end

--- Registra el completado en las misiones.
---
--- Va DENTRO del cierre natural y ANTES de limpiar: una mision de
--- "completa un evento" solo puede avanzar si el evento termino de
--- verdad, y `RecordMetric` exige un `Player` real con perfil.
--- @param active any
function Service.RecordCompletion(active: any)
	local quests = Service._questService

	if not quests or not quests.RecordMetric then
		return
	end

	for _, player in ipairs(Service.GetPlayersInWorld(active.WorldId)) do
		quests.RecordMetric(player, "EventCompleted", 1)
	end
end

--- Abre el mundo a nuevos eventos: cierra los suyos sin pagar.
---
--- Lo llama el servicio cuando un mundo se descarga (el ultimo
--- jugador sale). Los eventos abiertos de ese mundo no pueden
--- completarse porque ya no hay nadie que los complete: se cierran
--- CANCELADOS, que es el unico camino que no paga.
--- @param worldId any
--- @return number cerrados
function Service.CloseWorldEvents(worldId: any): number
	local closed = 0

	for instanceId, active in pairs(Service._active) do
		if active.WorldId == worldId and not active.CleanedUp then
			if Service.FinishEvent(instanceId, true) then
				closed += 1
			end
		end
	end

	return closed
end

-- ---------------------------------------------------------------------------
-- CUERPO DEL EVENTO (MASTER MISSION V2 - Bloque 1)
-- ---------------------------------------------------------------------------

--- Centros de zona del mundo, en orden estable. Mismo contrato de
--- generador que `MiniBossService`: carpeta `Zone_<Mundo>_<Zona>`
--- con losa central `_Core`. El cache vive lo que vive el mapa.
--- @param worldId string
--- @return { Vector3 }
local function zoneCenters(worldId: string): { Vector3 }
	local cache = Service._zoneCache[worldId]

	if cache then
		return cache
	end

	cache = {}
	Service._zoneCache[worldId] = cache

	local worlds = Workspace:FindFirstChild("Worlds")
	local worldFolder = worlds and worlds:FindFirstChild(worldId)
	local zones = worldFolder and worldFolder:FindFirstChild("Zones")

	if zones and zones:IsA("Folder") then
		for _, child in ipairs(zones:GetChildren()) do
			if child:IsA("Folder") and string.sub(child.Name, 1, 5) == "Zone_" then
				local core = child:FindFirstChild(child.Name .. "_Core")

				if core and core:IsA("BasePart") then
					table.insert(cache, core.Position)
				end
			end
		end
	end

	return cache
end

--- Punto de aparicion para el cuerpo: una zona aleatoria del mundo,
--- ligeramente desplazada para que dos enemigos no aparezcan
--- apilados en el centro exacto.
--- @param worldId string
--- @return Vector3?
local function bodySpawnPoint(worldId: string): Vector3?
	local centers = zoneCenters(worldId)

	if #centers == 0 then
		return nil
	end

	local center = centers[math.random(1, #centers)]
	local offset = Vector3.new(math.random(-8, 8), 3, math.random(-8, 8))

	return center + offset
end

--- Genera el cuerpo inicial de un evento abierto.
--- @param active any
function Service.SpawnBody(active: any)
	local monsters = Service._monsterService

	if not monsters or not monsters.Spawn then
		return
	end

	local body = EventRules.BodyFor(active.EventId)

	if not body then
		return
	end

	local state = {
		Kills = 0,
		Spawned = {},
		Target = EventRules.ObjectiveTargetFor(active.EventId, active.Night),
	}
	Service._bodies[active.InstanceId] = state

	local plan = EventRules.SpawnPlanFor(active.EventId, active.Night, 0, 0)

	for _ = 1, plan do
		local position = bodySpawnPoint(active.WorldId)

		if position then
			local spawnId = body.Spawns[math.random(1, #body.Spawns)]
			local monsterId = monsters.Spawn(spawnId, position, active.WorldId)

			if monsterId then
				state.Spawned[monsterId] = true
			end
		end
	end
end

--- Mantiene el cuerpo de todos los eventos: repone los caidos hasta
--- el plan y deja de generar cuando el objetivo ya esta cubierto.
function Service.MaintainBodies()
	local monsters = Service._monsterService

	if not monsters or not monsters.Spawn then
		return
	end

	for _, active in pairs(Service._active) do
		local state = Service._bodies[active.InstanceId]
		local body = state and EventRules.BodyFor(active.EventId)

		if state and body and not active.CleanedUp then
			-- Los vivos se RECUENTAN en cada paso: no se confia en la
			-- tabla `Spawned` porque un enemigo puede morir sin pasar
			-- por `OnMonsterDied` (desconexion del modelo, cleanup de
			-- la arena). El registro de `MonsterService` es la verdad.
			local alive = 0

			for monsterId in pairs(state.Spawned) do
				if monsters.Get and monsters.Get(monsterId) then
					alive += 1
				else
					state.Spawned[monsterId] = nil
				end
			end

			local plan = EventRules.SpawnPlanFor(active.EventId, active.Night, state.Kills, alive)

			for _ = 1, plan do
				local position = bodySpawnPoint(active.WorldId)

				if position then
					local spawnId = body.Spawns[math.random(1, #body.Spawns)]
					local monsterId = monsters.Spawn(spawnId, position, active.WorldId)

					if monsterId then
						state.Spawned[monsterId] = true
					end
				end
			end
		end
	end
end

--- Limpia el cuerpo: desaparece los enemigos del evento que queden
--- vivos, sin recompensa, por el `Despawn` de `MonsterService`.
--- @param active any
function Service.CleanupBody(active: any)
	local monsters = Service._monsterService
	local state = Service._bodies[active.InstanceId]

	if not monsters or not monsters.Despawn or not state then
		return
	end

	for monsterId in pairs(state.Spawned) do
		pcall(monsters.Despawn, monsterId)
	end

	state.Spawned = {}
end

--- Observador de muertes de `MonsterService` (mision V2).
---
--- Cuenta la baja si el monstruo era del evento y cierra el evento
--- AL COMPLETAR el objetivo, no al expirar el reloj: la promesa de
--- un evento de caza es "derrotalos y cobra", no "espera y cobra".
--- @param monsterId any
--- @param _record any
function Service.OnMonsterDied(monsterId: any, _record: any)
	if type(monsterId) ~= "number" then
		return
	end

	for instanceId, state in pairs(Service._bodies) do
		if state.Spawned[monsterId] then
			state.Spawned[monsterId] = nil
			state.Kills += 1

			local active = Service._active[instanceId]

			if active and state.Target > 0 and state.Kills >= state.Target then
				Service.FinishEvent(instanceId, false)
			end

			Service.Publish()
			return
		end
	end
end

-- ---------------------------------------------------------------------------
-- MANTENIMIENTO
-- ---------------------------------------------------------------------------

--- Un paso de mantenimiento.
---
--- Hace las DOS cosas que mantienen el sistema acotado:
---   1. cerrar los eventos que ya cumplieron su duracion
---      (pago incluido, por el unico camino de cierre);
---   2. sortear eventos NUEVOS en los mundos que tienen
---      jugadores, respetando la ventana entre sorteos.
---
--- No hay `Heartbeat`: el hilo propio duerme entre pasos y el
--- coste no lo paga quien no esta en un mundo con eventos.
--- @param now any? reloj del servidor
--- @return number eventosCerrados
function Service.Tick(now: any?): number
	local t = now

	if type(t) ~= "number" or t ~= t then
		t = os.clock()
	end

	local closed = 0

	-- 1. Caducidad. Se copia la lista de ids antes de cerrar:
	-- `FinishEvent` borra entradas mientras se recorre.
	local expired = {}

	for instanceId, active in pairs(Service._active) do
		if EventRules.IsExpired(active, t) then
			table.insert(expired, instanceId)
		end
	end

	for _, instanceId in ipairs(expired) do
		-- Un evento de CAZA que expira sin completar su objetivo se
		-- cierra CANCELADO: pagarlo premiaria no haber jugado. Los
		-- demas (supervivencia, recompensa, ambientales) expiran
		-- completados, que es su objetivo.
		local active = Service._active[instanceId]
		local cancelled = active ~= nil and not EventRules.CompletesOnExpiry(active.EventId)

		if Service.FinishEvent(instanceId, cancelled) and not cancelled then
			closed += 1
		end
	end

	-- 1b. Cuerpo: reponer los caidos hasta el plan de cada evento.
	Service.MaintainBodies()

	-- 2. Sorteo en mundos con jugadores. El sorteo es POR MUNDO
	-- con ventana: un mundo vacio de jugadores no consume tiradas
	-- y no acumula eventos que nadie vera.
	for _, player in ipairs(Players:GetPlayers()) do
		local worldId = player:GetAttribute("World")

		if type(worldId) == "string" then
			local last = Service._lastRoll[worldId]

			if not last or (t - last) >= Service.RollWindow then
				Service._lastRoll[worldId] = t

				-- `StartEvent` aplica los limites y el sorteo de
				-- `EventRules.Roll`: la mayoria de las tiradas no
				-- dan evento, y eso es lo normal.
				Service.StartEvent(worldId, nil, math.random())
			end
		end
	end

	return closed
end

--- Publica el estado de los eventos a los jugadores de cada mundo.
---
--- El CONTRATO con la UI son tres atributos escalares: el id del
--- evento (o cadena vacia), su etiqueta legible y los segundos
--- que quedan. Solo se escriben cuando CAMBIAN, y el reloj de un
--- evento se publica a 1 Hz, no a 60: un evento dura decenas de
--- segundos y el jugador no necesita precision de frame.
--- @return number atributos escritos
function Service.Publish(): number
	local written = 0

	for _, player in ipairs(Players:GetPlayers()) do
		local worldId = player:GetAttribute("World")
		local best = nil
		local remaining = 0

		if type(worldId) == "string" then
			for _, active in pairs(Service._active) do
				if active.WorldId == worldId and not active.CleanedUp then
					if not best or active.StartedAt < best.StartedAt then
						best = active
					end
				end
			end
		end

		if best then
			remaining = math.floor(EventRules.GetRemaining(best, os.clock()))
		end

		local eventId = if best then best.EventId else ""
		local label = ""
		local objective = ""

		if best then
			local definition = EventRules.Get(best.EventId)
			label = if definition then definition.Label else best.EventId

			local body = Service._bodies[best.InstanceId]
			objective = EventRules.ObjectiveText(best.EventId, best.Night, body and body.Kills or 0)
		end

		if player:GetAttribute("EventActive") ~= eventId then
			player:SetAttribute("EventActive", eventId)
			written += 1
		end

		if player:GetAttribute("EventLabel") ~= label then
			player:SetAttribute("EventLabel", label)
			written += 1
		end

		if player:GetAttribute("EventObjective") ~= objective then
			player:SetAttribute("EventObjective", objective)
			written += 1
		end

		if player:GetAttribute("EventRemaining") ~= remaining then
			player:SetAttribute("EventRemaining", remaining)
			written += 1
		end
	end

	return written
end

-- ---------------------------------------------------------------------------
-- CICLO DE VIDA DEL SERVICIO
-- ---------------------------------------------------------------------------

local function runMaintenance()
	while Service._running do
		local ok, err = pcall(Service.Tick)

		if not ok then
			-- Un vigilante que muere en el primer error dejaria
			-- eventos abiertos para siempre. Se avisa y se sigue:
			-- un evento colgado es una degradacion, no un crash.
			Logger.Error(("EventService: el mantenimiento fallo: %s"):format(tostring(err)))
		end

		task.wait(1)
	end
end

--- Inicializacion. Idempotente.
--- @param maid any?
--- @return boolean success
function Service.Init(maid: any?): boolean
	if Service.IsInitialized then
		return true
	end

	Service._active = {}
	Service._nextInstance = 1
	Service._lastRoll = {}
	Service._bodies = {}

	Service.IsInitialized = true
	return true
end

--- Arranca el mantenimiento. Idempotente.
--- @return boolean success
function Service.Start(): boolean
	if not Service.IsInitialized then
		Logger.Error("EventService: Start sin Init")
		return false
	end

	if Service._running then
		return true
	end

	Service._running = true
	Service._thread = task.spawn(runMaintenance)

	Logger.Info(
		("EventService: listo (max %d por mundo, %d global, ventana %d s)"):format(
			EventRules.MaxActivePerWorld,
			EventRules.MaxActiveTotal,
			Service.RollWindow
		)
	)

	return true
end

--- Para el servicio y cierra TODO sin pagar. Idempotente.
--- @return boolean success
function Service.Destroy(): boolean
	Service._running = false

	if Service._thread then
		pcall(task.cancel, Service._thread)
		Service._thread = nil
	end

	-- Cierre TOTAL: al apagar el servidor ningun evento se cobra,
	-- porque "terminar" un evento que nadie pudo completar no es
	-- un completado.
	for instanceId in pairs(Service._active) do
		Service.FinishEvent(instanceId, true)
	end

	Service._active = {}
	Service._bodies = {}
	Service._lastRoll = {}
	Service.IsInitialized = false
	return true
end

return Service
