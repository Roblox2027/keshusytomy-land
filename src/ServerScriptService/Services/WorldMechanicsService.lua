--!strict
--[[
	WorldMechanicsService
	MECANICAS EXPANDIDAS POR MUNDO (FASE 4).

	QUE HACE Y QUE DELEGA
	---------------------
	Este servicio NO calcula nada: el catalogo, las fases de los eventos
	temporales y la aritmetica de movimiento viven en `WorldMechanics`
	(puro, probado). Este servicio aporta lo que el motor: el hilo de tick,
	la lectura de posiciones, la construccion de partes y la integracion
	con `ActivityService.RegisterPoints`.

	SERVICIOS QUE CONSUME
	---------------------
	- ActivityService: recibe puntos de interaccion (Discovery/Mechanic/
	  Collection) y notifica avances via RecordMetric.
	- CombatService: autoridad unica de dano para eventos que danan.
	- WorldService: resolucion de mundos y puntos de spawn.

	LA REGLA DE AUTORIDAD
	---------------------
	El cliente NUNCA decide fases, estados de terminal, ni recompensas.
	La fase de un evento se deriva del reloj del servidor: todos los
	jugadores ven la misma fase. Los puntos de interaccion se registran
	desde el servidor usando posiciones reales del mapa.

	MULTIPLAYER-SAFE
	-----------------
	El estado del servidor esta scoped a (mundo, evento): cada mundo tiene
	su propio ciclo de eventos temporales, y los cooldowns son por evento
	no por jugador. No hay estado mutable compartido entre jugadores.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONFIG = SHARED:WaitForChild("Config")
local LIBRARIES = SHARED:WaitForChild("Libraries")
local UTILS = SHARED:WaitForChild("Utils")

local WorldMechanics = require(LIBRARIES:WaitForChild("WorldMechanics"))
local ActivitiesRules = require(LIBRARIES:WaitForChild("ActivitiesRules"))
local ActivityCatalog = require(CONFIG:WaitForChild("ActivityCatalog"))
local Logger = require(UTILS:WaitForChild("Logger"))

local Service = {}

Service.IsInitialized = false

-- Servicios inyectados por ServerMain.
Service._activityService = nil
Service._combatService = nil
Service._worldService = nil

-- Eventos temporales activos: { worldId -> { EventDef, CycleStart } }.
Service._activeEvents = {}

-- Puntos de interaccion registrados: { activityId -> { Position, World } }.
Service._registeredPoints = {}

-- Cache de centros de zona por mundo (contrato Zone_*_Core).
Service._zoneCache = {}

-- Estadisticas de observability.
Service._stats = {
	pointsRegistered = 0,
	eventsStarted = 0,
	eventTicks = 0,
}

Service._folder = nil
Service._thread = nil
Service._running = false

-- Intervalo de tick para eventos temporales. Lo mismo que HazardService:
-- 0.5 s es suficiente para una fase legible y cuesta una fraccion de frame.
local TICK_SECONDS = 0.5

-- ---------------------------------------------------------------------------
-- INYECCION
-- ---------------------------------------------------------------------------

--- @param activityService any
--- @param combatService any
--- @param worldService any
function Service.SetDependencies(activityService: any, combatService: any, worldService: any)
	Service._activityService = activityService
	Service._combatService = combatService
	Service._worldService = worldService
end

-- ---------------------------------------------------------------------------
-- REGISTRO DE PUNTOS DE INTERACCION
-- ---------------------------------------------------------------------------

--- Centros de zona de un mundo, ordenados por nombre para determinismo.
---
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
		local entries = {}

		for _, child in ipairs(zones:GetChildren()) do
			if child:IsA("Folder") and string.sub(child.Name, 1, 5) == "Zone_" then
				local core = child:FindFirstChild(child.Name .. "_Core")

				if core and core:IsA("BasePart") then
					table.insert(entries, { Name = child.Name, Position = core.Position })
				end
			end
		end

		table.sort(entries, function(a, b)
			return a.Name < b.Name
		end)

		for _, entry in ipairs(entries) do
			table.insert(cache, entry.Position)
		end
	end

	return cache
end

-- Tipos de actividad que requieren un punto fisico en el mapa.
local INTERACTABLE_TYPES = {
	[ActivitiesRules.ActivityType.Discovery] = true,
	[ActivitiesRules.ActivityType.Mechanic] = true,
	[ActivitiesRules.ActivityType.Collection] = true,
	[ActivitiesRules.ActivityType.Rescue] = true,
}

--- Registra los puntos de interaccion de un mundo con ActivityService.
---
--- Los puntos provienen de:
---   - centros de zona (para Discovery: zonas ocultas)
---   - posiciones declaradas en la definicion de mundo (Mechanics)
---
--- La funcion es IDEMPOTENTE por mundo: no registra puntos duplicados.
--- @param worldId string
--- @return number registered
function Service.RegisterInteractionPoints(worldId: string): number
	if Service._registeredPoints[worldId] then
		return 0
	end

	local mechanics = WorldMechanics.ForWorld(worldId)

	if not mechanics then
		return 0
	end

	local points = {}
	local centers = zoneCenters(worldId)
	local count = 0

	-- Discovery: puntos en centros de zona (zonas ocultas).
	if mechanics.NaturalMechanisms then
		for _, mech in ipairs(mechanics.NaturalMechanisms) do
			if mech.Kind == WorldMechanics.MechanicKind.HiddenZone then
				for i = 1, math.min(mech.Count or 1, #centers) do
					local activityId = ("DISCOVER_%s_%d"):format(worldId, i)
					points[activityId] = {
						Position = centers[i],
						World = worldId,
					}
					count += 1
				end
			end
		end
	end

	-- Discovery: puntos en centros de zona (ademas de NaturalMechanisms).
	if mechanics.Tracking then
		for i = 1, math.min(3, #centers) do
			local activityId = ("DISCOVER_%s_TRACKING_%d"):format(worldId, i)
			points[activityId] = {
				Position = centers[i],
				World = worldId,
			}
			count += 1
		end
	end

	-- Collection: puntos de tesoro enterrado.
	if mechanics.BuriedTreasures then
		local treasureCount = mechanics.BuriedTreasures.Count or 3
		for i = 1, math.min(treasureCount, #centers) do
			local activityId = ("COLLECTION_%s_%d"):format(worldId, i)
			points[activityId] = {
				Position = centers[i],
				World = worldId,
			}
			count += 1
		end
	end

	-- Collectibles: puntos dispersos por el mapa.
	if mechanics.Collectibles then
		for i = 1, math.min(mechanics.Collectibles.Count or 3, #centers) do
			local activityId = ("COLLECT_%s_%d"):format(worldId, i)
			points[activityId] = {
				Position = centers[i],
				World = worldId,
			}
			count += 1
		end
	end

	-- Catalogo de actividades: garantiza puntos para TODAS las actividades
	-- interactuables del mundo, incluyendo Ice/Volcano/Cyber que no tienen
	-- mecanica de puntos. Usa centros de zona en round-robin para posiciones.
	local catalogActivities = ActivityCatalog.List(worldId)
	local centerIdx = 1

	for _, activity in ipairs(catalogActivities) do
		local activityId = activity.Id
		if not points[activityId] and INTERACTABLE_TYPES[activity.Type] then
			if #centers > 0 then
				local pos = centers[centerIdx]
				points[activityId] = {
					Position = pos,
					World = worldId,
				}
				count += 1
				centerIdx = centerIdx % #centers + 1
			else
				points[activityId] = {
					Position = Vector3.new(0, 0, 0),
					World = worldId,
				}
				count += 1
			end
		end
	end

	if count > 0 then
		if Service._activityService and Service._activityService.RegisterPoints then
			Service._activityService.RegisterPoints(points)
			Service._stats.pointsRegistered += count
			Service._registeredPoints[worldId] = points
			Logger.Info(("WorldMechanics: %d puntos registrados para %s"):format(count, worldId))
		else
			Logger.Warn("WorldMechanics: sin ActivityService; los puntos no se registraron.")
		end
	else
		Service._registeredPoints[worldId] = true
	end

	return count
end

-- ---------------------------------------------------------------------------
-- EVENTOS TEMPORALES
-- ---------------------------------------------------------------------------

--- Calcula el proximo inicio de ciclo de un evento temporal.
---
--- El evento esta en Cooldown despues de cada ciclo activo. El proximo
--- ciclo comienza cuando el cooldown termina.
--- @param eventDef any
--- @param cycleStart number
--- @param now number
--- @return number nextStart
local function nextCycleStart(eventDef: any, cycleStart: number, now: number): number
	local cooldown = tonumber(eventDef.Cooldown) or WorldMechanics.EventCooldown
	local cycleLength = (tonumber(eventDef.WarningDuration) or WorldMechanics.WarningDuration)
		+ (tonumber(eventDef.ActiveDuration) or WorldMechanics.ActiveDuration)
		+ (tonumber(eventDef.RecoveryDuration) or WorldMechanics.RecoveryDuration)
		+ cooldown

	local elapsed = now - cycleStart

	if elapsed >= cycleLength then
		return now
	end

	return cycleStart + cycleLength
end

--- Inicia un evento temporal para un mundo si procede.
---
--- Un evento entra en fase Calm hasta que el world seed (el tiempo del
--- servidor al arrancar el mundo) determina su primer ciclo. No todos los
--- mundos tienen eventos temporales.
--- @param worldId string
--- @param now number
function Service.StartEvent(worldId: string, now: number)
	local events = WorldMechanics.GetTemporalEvents(worldId)

	if not events then
		return
	end

	for _, eventDef in ipairs(events) do
		local existing = Service._activeEvents[worldId]

		if not existing then
			Service._activeEvents[worldId] = {
				EventDef = eventDef,
				CycleStart = now + math.random(0, 30),
			}
			Service._stats.eventsStarted += 1
			Logger.Info(("WorldMechanics: evento '%s' iniciado en %s"):format(
				tostring(eventDef.Kind), worldId
			))
		end
	end
end

--- Fase actual de un evento temporal para un mundo.
--- @param worldId string
--- @param now number?
--- @return string phase
function Service.GetTemporalPhase(worldId: string, now: number?): string
	local state = Service._activeEvents[worldId]

	if not state then
		return WorldMechanics.TemporalPhase.Calm
	end

	local t = now

	if type(t) ~= "number" or t ~= t then
		t = os.clock()
	end

	local phase = WorldMechanics.TemporalPhaseAt(state.EventDef, state.CycleStart, t)

	-- Si el ciclo termino, avanzar al siguiente: el evento se repite.
	if phase == WorldMechanics.TemporalPhase.Calm then
		if t >= nextCycleStart(state.EventDef, state.CycleStart, t) then
			state.CycleStart = nextCycleStart(state.EventDef, state.CycleStart, t)
			phase = WorldMechanics.TemporalPhaseAt(state.EventDef, state.CycleStart, t)
		end
	end

	return phase
end

--- Danos que aplica un evento temporal en este tick.
--- @param worldId string
--- @param now number
--- @param tickSeconds number?
--- @return number
function Service.TemporalDamage(worldId: string, now: number, tickSeconds: number?): number
	local state = Service._activeEvents[worldId]

	if not state then
		return 0
	end

	return WorldMechanics.TemporalDamagePerTick(
		state.EventDef,
		state.CycleStart,
		now,
		tickSeconds or TICK_SECONDS
	)
end

--- Factibilidad de visibilidad de un evento temporal (1 = normal, 0 = ciego).
--- @param worldId string
--- @param now number?
--- @return number
function Service.GetVisibility(worldId: string, now: number?): number
	local state = Service._activeEvents[worldId]

	if not state then
		return 1
	end

	local t = now

	if type(t) ~= "number" or t ~= t then
		t = os.clock()
	end

	return WorldMechanics.VisibilityFactor(state.EventDef, state.CycleStart, t)
end

-- ---------------------------------------------------------------------------
-- MOVIMIENTO
-- ---------------------------------------------------------------------------

--- Velocidad de caminar modificada para un tipo de mecanica de movimiento.
---
--- Lee la definicion del mundo y aplica el multiplicador correspondiente.
--- Usado por el cliente para mostrar el efecto y por el servidor para
--- validar.
--- @param worldId string
--- @param mechanicKind string
--- @return number
function Service.GetModifiedWalkSpeed(worldId: string, mechanicKind: string): number
	local mechanics = WorldMechanics.ForWorld(worldId)

	if not mechanics then
		return WorldMechanics.DefaultWalkSpeed
	end

	if mechanicKind == "SlipperyIce" and mechanics.SlipperyIce then
		return WorldMechanics.ModifiedWalkSpeed(mechanics.SlipperyIce.SpeedMultiplier)
	end

	return WorldMechanics.DefaultWalkSpeed
end

-- ---------------------------------------------------------------------------
-- PUBLICACION DE ESTADO
-- ---------------------------------------------------------------------------

--- Publica el estado temporal de un mundo en atributos de jugador.
---
--- La UI necesita saber la fase actual para mostrar el telegrapho del
--- evento. Se publica por atributos (scalars), no por un remoto nuevo.
--- @param player Player
--- @param worldId string
--- @param now number?
function Service.PublishEventState(player: Player, worldId: string, now: number?)
	if not player or not player:IsA("Player") then
		return
	end

	local phase = Service.GetTemporalPhase(worldId, now)
	local visibility = Service.GetVisibility(worldId, now)

	player:SetAttribute("WorldEventPhase_" .. worldId, phase)
	player:SetAttribute("WorldEventVisibility_" .. worldId, visibility)
end

-- ---------------------------------------------------------------------------
-- MANTENIMIENTO
-- ---------------------------------------------------------------------------

--- Un paso del servicio: registra puntos faltantes y avanza eventos.
--- @param now any?
function Service.Tick(now: any?)
	local t = now

	if type(t) ~= "number" or t ~= t then
		t = os.clock()
	end

	-- Registrar puntos para mundos cargados que aun no tengan puntos.
	if Service._worldService then
		for _, worldId in ipairs(Service._worldService.GetWorldIds()) do
			Service.RegisterInteractionPoints(worldId)
			Service.StartEvent(worldId, t)
		end
	end

	-- Publicar fase a jugadores en un mundo con eventos.
	local worldsPresent: { [string]: boolean } = {}

	for _, player in ipairs(Players:GetPlayers()) do
		local worldId = player:GetAttribute("World")

		if type(worldId) == "string" then
			worldsPresent[worldId] = true
		end

		Service.PublishEventState(player, worldId, t)
	end

	Service._stats.eventTicks += 1
end

local function runMaintenance()
	while Service._running do
		local ok, err = pcall(Service.Tick)

		if not ok then
			Logger.Error(("WorldMechanicsService: tick fallo: %s"):format(tostring(err)))
		end

		task.wait(TICK_SECONDS)
	end
end

-- ---------------------------------------------------------------------------
-- CICLO DE VIDA DEL SERVICIO
-- ---------------------------------------------------------------------------

--- Inicializacion. Idempotente.
--- @param _maid any?
--- @return boolean success
function Service.Init(_maid: any?): boolean
	if Service.IsInitialized then
		return true
	end

	Service._activeEvents = {}
	Service._registeredPoints = {}
	Service._zoneCache = {}
	Service._stats = {
		pointsRegistered = 0,
		eventsStarted = 0,
		eventTicks = 0,
	}

	Service.IsInitialized = true
	return true
end

--- Arranque. Idempotent.
--- @return boolean success
function Service.Start(): boolean
	if not Service.IsInitialized then
		Logger.Error("WorldMechanicsService: Start sin Init")
		return false
	end

	if Service._running then
		return true
	end

	Service._running = true
	Service._thread = task.spawn(runMaintenance)

	Logger.Info("WorldMechanicsService: listo (mecanicas expandidas por mundo).")
	return true
end

--- Para el servicio y limpia el estado. Idempotent.
--- @return boolean success
function Service.Destroy(): boolean
	Service._running = false

	if Service._thread then
		pcall(task.cancel, Service._thread)
		Service._thread = nil
	end

	Service._activeEvents = {}
	Service._registeredPoints = {}
	Service._zoneCache = {}
	Service._stats = {
		pointsRegistered = 0,
		eventsStarted = 0,
		eventTicks = 0,
	}

	if Service._folder then
		pcall(function()
			Service._folder:Destroy()
		end)
		Service._folder = nil
	end

	Service._activityService = nil
	Service._combatService = nil
	Service._worldService = nil
	Service.IsInitialized = false
	return true
end

--- Estadisticas para observability.
--- @return { [string]: number }
function Service.GetStats(): { [string]: number }
	return {
		pointsRegistered = Service._stats.pointsRegistered,
		eventsStarted = Service._stats.eventsStarted,
		eventTicks = Service._stats.eventTicks,
	}
end

return Service
