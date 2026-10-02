--!strict
--[[
	PortalService
	Portales del lobby: validan y ejecutan la entrada a un mundo.

	REGLA DE AUTORIDAD (no negociable)
	----------------------------------
	El cliente NUNCA dice adonde va. Llega `PortalAction:FireServer("Enter",
	worldId)` y eso es SOLO una peticion. Este servicio decide, en el
	servidor, si el viaje procede. Un cliente modificado puede pedir
	cualquier cadena, y todos los destinos se validan contra la lista de
	portales REALES del mapa.

	Flujo completo (cada paso puede rechazar):
		1. El `worldId` es una cadena no vacia.
		2. El jugador tiene personaje con Humanoid vivo.
		3. El `worldId` corresponde a un portal que existe en el mapa.
		4. El portal esta abierto y no hay ronda en curso.
		5. El jugador tiene el nivel requerido por el mundo.
		6. El mundo destino esta disponible (FeatureConfig + registro).
		7. El jugador esta junto al umbral y no esta en cooldown.
		8. El teleport lo ejecuta el SERVIDOR.

	El paso 3 es el que cierra el teleport arbitrario: un `worldId`
	inventado no tiene portal, y sin portal no hay viaje. El paso 8 es el
	que evita que la posicion la elija el cliente: el destino se calcula
	siempre a partir de instancias del mapa.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONSTANTS = SHARED:WaitForChild("Constants")
local UTILS = SHARED:WaitForChild("Utils")

-- Necesario para resolver el canal `PortalAction` en `SendVerdict`.
local GameConstants = require(CONSTANTS:WaitForChild("GameConstants"))
local Logger = require(UTILS:WaitForChild("Logger"))
local RateLimiter = require(SHARED:WaitForChild("Libraries"):WaitForChild("RateLimiter"))

local RemoteAction = GameConstants.RemoteAction

local Service = {}

Service.IsInitialized = false

--- Prefijo de nombre de los portales del mapa. Es el CONTRATO con
--- `tools/generate-project.js`, que los genera como `Portal_<WorldId>`.
Service.PORTAL_PREFIX = "Portal_"

--- Segundos que un jugador debe esperar entre dos traslados. Evita que el
--- portal se use como bomba de teletransporte.
Service.PORTAL_COOLDOWN = 3

--- Distancia maxima a la que se acepta una peticion de portal.
---
--- El cliente no envia la posicion (no es de fiar), pero se usa SU
--- personaje como prueba de presencia: sin esta comprobacion, un jugador
--- sentado en el lobby activaria un portal desde el otro extremo del mapa.
--- Es una comprobacion de PROXIMIDAD, no de confianza.
Service.MAX_INTERACTION_DISTANCE = 14

--- Forma de una entrada de `Service._portals`.
---
--- Se declara de forma explicita porque la tabla se construye en
--- `CollectPortals` y se consume en cuatro sitios mas. Sin este tipo, Luau
-- infiere una tabla abierta y `portal.RequiredLevel` se marca como acceso a
-- una clave que el analizador no puede verificar: cada consumidor necesitaria
-- su propia comprobacion defensiva.
--
-- Es un alias LOCAL y no `export type`: un ModuleScript que devuelve una
-- tabla no exporta tipos, y `export type` solo es valido en modulos cuyo
-- unico producto son tipos.
type PortalDefinition = {
	Name: string,
	WorldId: string,
	Instance: Model,
	Threshold: BasePart,
	Position: Vector3,
	RequiredLevel: number,
	DisplayName: string,
	State: string,
}

-- worldId -> definicion de portal.
--
-- La tabla NO lleva anotacion porque `Service` es una tabla literal sin
-- metatable: Luau no comprueba los tipos que se le escriben encima y
-- `Service._portals: T = {}` se interpreta como una Sentencia de la misma
-- linea. El alias `PortalDefinition` se usa igual en las firmas de retorno.
Service._portals = {}
-- Jugador -> instante (os.clock) del ultimo traslado concedido.
Service._lastTravel = {}

-- Servicios inyectados por ServerMain.
Service._worldService = nil
Service._matchService = nil
Service._roundService = nil
Service._playerService = nil

-- Freno anti-spam. El RemoteGateway ya limita por canal, pero el portal
-- recibe peticiones de una sola accion (`Enter`): un limite propio hace el
-- dano innecesario mas improbable sin depender del externo.
local travelLimiter = RateLimiter.new({ capacity = 3, refillPerSecond = 1 })

--- Estados posibles de un portal. Un portal no abierto no acepta a nadie.
Service.PortalState = {
	Open = "Open",
	Locked = "Locked",
	Disabled = "Disabled",
}

--- La parte que ACTUA como umbral, no el marco decorativo.
---
--- Se busca `PortalPanel` y, en su defecto, `Panel` o `Threshold`. El mapa
--- del generador nombra las piezas `Portal_<WorldId>_Panel`; dentro de un
--- Model agrupado el nombre corto seria `Panel`. Se aceptan ambas formas para
--- que el servicio sobreviva a como se construya el portal.
---
--- Se elige el PANEL y no `_Base` o `_Lintel` a proposito: el panel es la
--- hoja central, la unica cuya posicion representa "dentro del portal".
--- `_Base` esta en el suelo y `_Lintel` en el techo, asi que usar cualquiera
--- de las dos daria un error de varios studs y haria fallar la comprobacion
--- de proximidad de forma siempre correcta pero nunca util.
--- @param portal Model
--- @return BasePart?
local function findThreshold(portal: Model): BasePart?
	for _, candidate in ipairs({ "PortalPanel", "Panel", "Threshold" }) do
		local part = portal:FindFirstChild(candidate)
		if part and part:IsA("BasePart") then
			return part :: BasePart
		end
	end
	return nil
end

--- Construye la tabla de portales a partir del mapa.
---
--- Cada entrada necesita Model + umbral + mundo registrado. Las que no
--- cumplen se ignoran con un aviso: un portal a medio construir no debe
--- romper el servicio entero ni permitir un viaje sin destino.
--- @return number total
function Service.CollectPortals(): number
	Service._portals = {}

	local lobby = Workspace:FindFirstChild("Lobby")
	if not lobby then
		Logger.Warn("Workspace.Lobby no existe; no hay portales.")
		return 0
	end

	-- El mapa del generador deja los portales planos bajo `Lobby` y el
	-- contrato del proyecto los agrupa en `Lobby.Portals`. `GetDescendants`
	-- cubre ambas formas sin duplicar: cada instancia aparece UNA sola vez
	-- en el recorrido.
	local total = 0

	for _, instance in ipairs(lobby:GetDescendants()) do
		local worldId = string.match(instance.Name, "^" .. Service.PORTAL_PREFIX .. "(.+)$")

		if worldId and instance:IsA("Model") then
			local panel = findThreshold(instance :: Model)
			local world = Service._worldService and Service._worldService.GetWorld(worldId)

			if world and panel then
				Service._portals[worldId] = {
					Name = instance.Name,
					WorldId = worldId,
					Instance = instance,
					Threshold = panel,
					Position = panel.Position,
					RequiredLevel = world.RequiredLevel or 1,
					DisplayName = world.DisplayName or worldId,
					State = Service.PortalState.Open,
				}
				total += 1
			elseif not world then
				Logger.Debug(("portal '%s' ignorado: mundo no registrado"):format(worldId))
			else
				Logger.Warn(("portal '%s' sin umbral; se ignora"):format(worldId))
			end
		end
	end

	return total
end

--- Portales registrados, en orden estable (interfaz y pruebas).
--- @return { string } worldIds
function Service.GetPortalIds(): { string }
	local ids = {}
	for worldId in pairs(Service._portals) do
		table.insert(ids, worldId)
	end
	table.sort(ids)
	return ids
end

--- Definicion de un portal, o nil si no existe.
--- @param worldId string
--- @return any?
function Service.GetPortal(worldId: string): any?
	return Service._portals[worldId]
end

--- Cambia el estado de un portal. Un portal no abierto no acepta viaje.
--- @param worldId string
--- @param state string
--- @return boolean success
function Service.SetPortalState(worldId: string, state: string): boolean
	local portal = Service._portals[worldId]
	if not portal then
		return false
	end

	portal.State = state
	Logger.Info(("portal '%s' -> %s"):format(worldId, state))
	return true
end

--- Indica si un portal esta en un estado que permite viajar.
--- @param portal any?
--- @return boolean
function Service.IsPortalUsable(portal: any?): boolean
	return portal ~= nil and (portal :: any).State == Service.PortalState.Open
end

--- Nivel actual de un jugador. Se lee de `PlayerService` si esta inyectado;
--- si no, del atributo `Level` que el propio PlayerService publica.
---
--- El atributo NO es la fuente preferente a proposito: lo escribe el
--- servidor, pero un cliente puede mutar sus propios atributos en local. Por
--- eso la fuente preferida es la sesion del servicio y el atributo es solo el
--- respaldo cuando el servicio no esta disponible.
--- @param player Player
--- @return number level
function Service.GetPlayerLevel(player: Player): number
	local playerService = Service._playerService
	if playerService and playerService.GetSessionFromPlayer then
		local session = playerService.GetSessionFromPlayer(player)
		if session and type(session.Level) == "number" then
			return session.Level
		end
	end

	local attribute = player:GetAttribute("Level")
	return type(attribute) == "number" and attribute or 1
end

--- Valida un viaje completo SIN ejecutarlo.
---
--- Se separa de `TryEnter` a proposito: permite auditar POR QUE se rechaza
--- un viaje (pruebas, diagnostico, mensajes de interfaz) sin provocar el
--- efecto. Devolver el motivo es lo que hace util el rechazo.
--- @param player Player
--- @param worldId any
--- @return boolean allowed
--- @return string? reason motivo legible del rechazo
function Service.CanTravel(player: Player, worldId: any): (boolean, string?)
	-- 1. Tipo de dato. `worldId` llega de la red: se comprueba ANTES de
	-- indexar la tabla para que un numero o una tabla no la rompan.
	if type(worldId) ~= "string" or worldId == "" then
		return false, "destino invalido"
	end

	-- 2. Jugador real, en el servidor y con personaje.
	local character = player.Character
	if not character then
		return false, "sin personaje"
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false, "sin humanoid vivo"
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return false, "sin HumanoidRootPart"
	end

	-- 3. El portal existe de verdad en el mapa. Esta comprobacion cierra el
	-- teleport arbitrario: un `worldId` inventado no tiene portal.
	local portal = Service._portals[worldId]
	if not portal then
		return false, "portal inexistente"
	end

	-- 4. Estado del portal.
	if not Service.IsPortalUsable(portal) then
		return false, ("portal %s"):format(tostring(portal.State))
	end

	-- 5. El mundo destino esta habilitado.
	local worldService = Service._worldService
	if not worldService or not worldService.IsWorldAvailable(worldId) then
		return false, "mundo no disponible"
	end

	-- 6. No hay ronda en curso: durante la partida los jugadores viven en la
	-- arena y salir por el portal seria una via de escape.
	local roundService = Service._roundService
	if roundService and roundService.IsPlaying and roundService.IsPlaying() then
		return false, "hay una ronda en curso"
	end

	-- 7. Nivel requerido.
	local level = Service.GetPlayerLevel(player)
	if level < portal.RequiredLevel then
		return false, ("requiere nivel %d"):format(portal.RequiredLevel)
	end

	-- 8. Proximidad al umbral.
	local distance = ((rootPart :: BasePart).Position - portal.Position).Magnitude
	if distance > Service.MAX_INTERACTION_DISTANCE then
		return false, "demasiado lejos del portal"
	end

	-- 9. Cooldown individual.
	local last = Service._lastTravel[player]
	if last and (os.clock() - last) < Service.PORTAL_COOLDOWN then
		return false, "en cooldown"
	end

	-- 10. Freno anti-spam.
	if not travelLimiter.TryConsume(tostring(player.UserId)) then
		return false, "demasiadas peticiones"
	end

	return true, nil
end

--- Inyeccion de dependencias. La llama ServerMain entre Init y Start.
--- @param worldService any
--- @param matchService any
--- @param roundService any
--- @param playerService any?
function Service.SetDependencies(
	worldService: any,
	matchService: any,
	roundService: any,
	playerService: any?
)
	Service._worldService = worldService
	Service._matchService = matchService
	Service._roundService = roundService
	Service._playerService = playerService
end

--- Ejecuta el viaje de un jugador a un mundo, si todo es valido.
--- @param player Player
--- @param worldId any
--- @return boolean success
--- @return string? reason
function Service.TryEnter(player: Player, worldId: any): (boolean, string?)
	local allowed, reason = Service.CanTravel(player, worldId)
	if not allowed then
		return false, reason
	end

	local portal = Service._portals[worldId]
	local matchService = Service._matchService

	if not matchService then
		Logger.Error("PortalService: MatchService no inyectado; no se puede viajar.")
		return false, "servicio no disponible"
	end

	-- Destino SEGURO: nunca la posicion que envio el cliente, sino el
	-- marcador que elige el servidor. `Forest` es el unico mundo con arena
	-- construida; el resto devuelven al lobby, que siempre existe.
	local destinationKey = portal.WorldId == "Forest" and "Arena" or "Lobby"
	local moved = matchService.MovePlayer(player, destinationKey)

	if not moved then
		Logger.Warn(("no se movio '%s' a '%s'"):format(player.Name, worldId))
		return false, "destino no encontrado"
	end

	Service._lastTravel[player] = os.clock()
	Logger.Info(("%s entro por el portal a '%s'"):format(player.Name, worldId))

	return true, nil
end

--- Envia el veredicto al cliente que pidio el viaje.
---
--- Por que hace falta (vertical slice 1): antes el rechazo se registraba
--- solo en el log del servidor. Para el jugador eso es una interaccion
--- SILENCIOSA: pulsa el portal, no ocurre nada y no hay forma de saber si
--- el boton esta roto, si le falta nivel o si hay una ronda en curso. Con
--- este envio, el motivo llega a la pantalla.
---
--- Se viaja por el MISMO `PortalAction`: un `RemoteEvent` es bidireccional
--- y no hace falta un remoto nuevo para una sola respuesta.
---
--- Solo manda INFORMACION: `accepted`, el motivo y el nivel requerido. No
--- concede nada y no filtra datos de otros jugadores.
--- @param player Player
--- @param worldId any
--- @param accepted boolean
--- @param reason string?
--- @return boolean sent
function Service.SendVerdict(player: Player, worldId: any, accepted: boolean, reason: string?): boolean
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local remote = remotes and remotes:FindFirstChild(RemoteAction.Portal)

	if not remote or not remote:IsA("RemoteEvent") then
		Logger.Warn("PortalService: no hay PortalAction para enviar el veredicto.")
		return false
	end

	-- El `worldId` se devuelve como cadena solo si lo es. Con un valor raro
	-- (el cliente pudo mandar cualquier cosa) se manda un texto neutro, para
	-- que el cliente nunca forme un nombre de mundo a partir de basura.
	local safeWorldId = if type(worldId) == "string" then worldId else "?"

	-- El nivel requerido se consulta al portal registrado, no al payload:
	-- el servidor no le cree al cliente ni le "corrige" su propia peticion.
	local requiredLevel = 0
	if type(worldId) == "string" then
		local portal = Service._portals[worldId]
		if portal then
			requiredLevel = portal.RequiredLevel or 0
		end
	end

	remote:FireClient(player, "Result", safeWorldId, accepted, reason, requiredLevel)
	return true
end

--- Maneja la peticion `Enter` del canal de portales.
---
--- Es lo UNICO que el cliente puede pedir, y solo pide un nombre. El
--- resultado lo decide el servidor por completo Y se devuelve siempre:
--- un rechazo sin respuesta seria indistinguible de un portal roto.
--- @param player Player
--- @param worldId any
function Service.HandleEnter(player: Player, worldId: any)
	-- `pcall` porque un handler de remoto NUNCA debe tumbar el servidor,
	-- ni siquiera con datos malformados.
	local ok, success, reason = pcall(Service.TryEnter, player, worldId)

	if not ok then
		Logger.Error(("PortalService.Enter fallo: %s"):format(tostring(success)))
		return
	end

	if success then
		Service.SendVerdict(player, worldId, true, nil)
		return
	end

	Logger.Debug(("portal rechazado para %s: %s"):format(player.Name, tostring(reason)))
	Service.SendVerdict(player, worldId, false, reason)
end

--- Inicializacion del servicio. Idempotente.
---
--- NO comprueba aqui las dependencias, y es deliberado. El registro ejecuta
--- `InitAll` ANTES de `wireDependencies`, de modo que en este punto
--- `SetDependencies` todavia no se ha llamado y exigir `WorldService` o
--- `MatchService` haria fallar el Init de un servicio perfectamente valido.
--- La comprobacion vive en `Start`, que ya corre despues del cableado.
--- @param maid any?
--- @return boolean success
function Service.Init(maid: any?): boolean
	if Service.IsInitialized then
		return true
	end

	Service._portals = {}
	Service._lastTravel = {}

	Service.IsInitialized = true
	return true
end

--- Comienza a servir peticiones de portal.
---
--- Aqui ya estan inyectadas las dependencias, asi que es el primer momento en
--- que se puede resolver el mapa: los portales se recogen aqui y no en `Init`.
--- @return boolean success
function Service.Start(): boolean
	if not Service.IsInitialized then
		Logger.Error("PortalService: Start sin Init")
		return false
	end

	-- Sin `WorldService` no se puede resolver el mundo de un portal, y sin
	-- `MatchService` no hay a donde teletransportar. Es un fallo de arranque
	-- y no un aviso: un portal "activo" sin esas piezas acepta peticiones que
	-- no llegan a ningun sitio y parece un bug de mapeo.
	if not Service._worldService then
		Logger.Error("PortalService: WorldService no inyectado; no arranca.")
		return false
	end

	if not Service._matchService then
		Logger.Error("PortalService: MatchService no inyectado; no arranca.")
		return false
	end

	local ok, err = pcall(function()
		local total = Service.CollectPortals()
		Logger.Info(("PortalService: %d portales activos (%s)"):format(
			total,
			table.concat(Service.GetPortalIds(), ", ")
		))
	end)

	if not ok then
		Logger.Error("PortalService Start fallo: " .. tostring(err))
		return false
	end

	return true
end

--- Limpieza del servicio.
--- @return boolean success
function Service.Destroy(): boolean
	Service.IsInitialized = false
	Service._portals = {}
	Service._lastTravel = {}
	travelLimiter.Clear()
	return true
end

return Service
