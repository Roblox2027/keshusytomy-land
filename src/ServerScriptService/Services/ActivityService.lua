--!strict
--[[
	ActivityService
	Exploracion, descubrimiento e interaccion con el mundo (FASE 3).

	QUE HACE ESTE SERVICIO Y QUE HACE `ActivitiesRules`
	---------------------------------------------------
	`ActivitiesRules` es logica PURA: progreso, completion, reclamo atomico,
	cooldown y oferta. Se prueba sin motor. Este servicio anade lo que las
	reglas no saben:

	    - resolver el `Player` a su perfil real
	    - CONECTAR los eventos del juego a `RecordMetric`
	    - PAGAR la recompensa en la economia
	    - publicar el estado para que la UI lo vea

	LA REGLA DE AUTORIDAD
	---------------------
	El cliente NUNCA dice "actividad completada" ni "mision X esta en (x, z)".
	"Quiero reclamar la actividad X" y "estoy interactuando con el punto Y" son
	lo unico que pide; el servidor comprueba el progreso propio y la distancia
	PROPRIA. Una posicion mandada por el cliente se descarta: se usa la del
	personaje en el Workspace.

	LA REGLA DE LOS PUNTOS
	---------------------
	Discovery, Rescue y Mechanic son actividades con un PUNTO en el mapa. El
	servidor comprueba que el jugador este AL LADO (no que el cliente diga
	"estoy al lado"). Los puntos se registran con `RegisterPoints`: quien genera
	el mundo (el loader de WorldService, en FASE 3 follow-up) inyecta las
	posiciones; hasta entonces `Interact` rechaza con "no_point", que es seguro:
	mejor no avanzar que avanzar sin verificacion.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONFIG = SHARED:WaitForChild("Config")
local LIBRARIES = SHARED:WaitForChild("Libraries")
local UTILS = SHARED:WaitForChild("Utils")

local ActivitiesRules = require(LIBRARIES:WaitForChild("ActivitiesRules"))
local EconomyRules = require(LIBRARIES:WaitForChild("EconomyRules"))
local ActivityCatalog = require(CONFIG:WaitForChild("ActivityCatalog"))
local WorldAccessRules = require(LIBRARIES:WaitForChild("WorldAccessRules"))
local Logger = require(UTILS:WaitForChild("Logger"))

local Service = {}

Service.IsInitialized = false

-- ProfileService (estado), EconomyService (monedas) e InventoryService (items).
Service._profileService = nil
Service._economyService = nil
Service._inventoryService = nil

-- PlayerService y WorldService: para resolver el mundo del jugador y medir
-- la distancia al punto de interaccion.
Service._playerService = nil
Service._worldService = nil

-- Puntos de actividad interactuable: activityId (normalizado) -> { Position: Vector3, World: string? }.
-- Se inyectan con `RegisterPoints`; sin ellos `Interact` rechaza con "no_point".
Service._points = {}

-- Cache de actividades por tipo, como en `QuestService.definitionsFor`.
Service._typeCache = {}

-- Secuencia para los `requestId` del pago de recompensas.
Service._sequence = 0

-- Rango de interaccion: el servidor mide la distancia, nunca el cliente.
Service.INTERACT_RANGE = 18

-- Metricas que el servidor reconoce: el nombre del evento -> el tipo de
-- actividad que avanza. Es la frontera entre el contenido y los eventos
-- reales, como `QuestCatalog.Metric`.
Service.MetricToType = {
	MonsterDefeated = ActivitiesRules.ActivityType.Hunt,
	BossDefeated = ActivitiesRules.ActivityType.Hunt,
	MiniBossDefeated = ActivitiesRules.ActivityType.Hunt,
	BlockDestroyed = ActivitiesRules.ActivityType.Mechanic,
	SecretDiscovered = ActivitiesRules.ActivityType.Discovery,
	RoundWon = ActivitiesRules.ActivityType.Defense,
	PowerupCollected = ActivitiesRules.ActivityType.Collection,
}

Service.STATE_SECTIONS = { "Activities" }

--- Estadisticas para observabilidad.
Service._stats = {
	offered = 0,
	interacted = 0,
	completed = 0,
	claimed = 0,
	duplicateClaims = 0,
	rejected = 0,
}

--- Maid recibido en Init.
local MaidRef = nil

--- Reloj inyectable. En el motor es `os.time`; en pruebas se sustituye.
local nowSeconds = function(): number
	return os.time()
end

--- Inyecta las dependencias de ciclo de vida del servicio.
--
-- `inventoryService` puede ser nil: las monedas (Coins/Gems) van por
-- `EconomyService`, los materiales (Mat_*) van por `InventoryService`. Si
-- falta el servicio de inventario, los materiales se registran como error
-- pero las monedas se pagan normalmente.
--- @param profileService any
--- @param economyService any
--- @param inventoryService any?
function Service.SetDependencies(profileService: any, economyService: any, inventoryService: any?)
	Service._profileService = profileService
	Service._economyService = economyService
	Service._inventoryService = inventoryService
end

--- Inyecta PlayerService (resolucion de mundo) y WorldService (default).
--- @param playerService any
--- @param worldService any
function Service.SetPlayerService(playerService: any, worldService: any)
	Service._playerService = playerService
	Service._worldService = worldService
end

--- Registra los puntos interactuables de una actividad.
---
--- El loader del mundo llama esto al generar el mapa; sin puntos, `Interact`
--- rechaza con "no_point" hasta que existan. Es preferible a permitir el
--- avance sin verificacion de posicion.
--- @param points { [string]: { Position: any, World: string? } }
function Service.RegisterPoints(points: { [string]: any })
	for activityId, point in pairs(points or {}) do
		local normalized = ActivitiesRules.NormalizeId(activityId)
		Service._points[normalized] = point
	end
end

--- Inicializacion del servicio. Debe ser idempotente.
--- @param maid any?
--- @return boolean success
function Service.Init(maid: any?): boolean
	MaidRef = maid
	Service._sequence = 0
	Service._stats = {
		offered = 0,
		interacted = 0,
		completed = 0,
		claimed = 0,
		duplicateClaims = 0,
		rejected = 0,
	}

	-- El catalogo recibe las reglas aqui, y no con un `require` interno:
	-- ver la cabecera de `ActivityCatalog`.
	ActivityCatalog.Configure(ActivitiesRules)
	Service._typeCache = {}
	Service.IsInitialized = true
	return true
end

--- Arranque. Valida el catalogo ANTES de ofrecer actividades.
--- @param maid any?
--- @return boolean success
function Service.Start(maid: any?): boolean
	if not Service._profileService or not Service._economyService then
		Logger.Error("ActivityService: sin ProfileService/EconomyService; las actividades no funcionan.")
		return false
	end

	-- `Audit` comprueba estructura, tipos, recompensas y que NINGUN mundo quede
	-- sin actividades. Con `WorldAccessRules.WorldOrder` se valida el World
	-- declarado por cada actividad.
	local problems = ActivityCatalog.Validate(ActivitiesRules, WorldAccessRules.WorldOrder)

	if #problems > 0 then
		Logger.Error(
			("ActivityService: el catalogo tiene %d problemas: %s"):format(
				#problems,
				table.concat(problems, "; ")
			)
		)
		return false
	end

	local count = 0
	for _ in pairs(ActivityCatalog.GetAll()) do
		count += 1
	end

	Logger.Info(("ActivityService: listo (%d actividades publicadas)"):format(count))
	return true
end

--- Limpieza del servicio.
--- @return boolean success
function Service.Destroy(): boolean
	Service.IsInitialized = false
	Service._profileService = nil
	Service._economyService = nil
	Service._inventoryService = nil
	Service._playerService = nil
	Service._worldService = nil
	Service._typeCache = {}
	Service._points = {}
	MaidRef = nil
	return true
end

-- ---------------------------------------------------------------
-- Estado del jugador
-- ---------------------------------------------------------------

--- Devuelve la seccion de actividades del perfil, creandola si no existe.
---
--- El `typeof` filtra el caso peligroso: un perfil migrado puede traer
--- `Activities` como cadena o numero, y entonces asignar a `Progress`
--- reventaria al instante.
--- @param player Player?
--- @return any? section
local function activityStateOf(player: Player?): any?
	if not player or not Service._profileService then
		return nil
	end

	local profile = Service._profileService.GetProfile(player)

	if type(profile) ~= "table" then
		return nil
	end

	if type(profile.Activities) ~= "table" then
		profile.Activities = ActivitiesRules.NewPlayerState(player.UserId)
	end

	local state = profile.Activities

	-- Sub-tablas que un perfil guardado de una version anterior no tiene.
	if type(state.Progress) ~= "table" then
		state.Progress = {}
	end
	if type(state.Claims) ~= "table" then
		state.Claims = {}
	end
	if type(state.Completed) ~= "table" then
		state.Completed = {}
	end
	if type(state.CooldownUntil) ~= "table" then
		state.CooldownUntil = {}
	end

	return state
end

--- Resuelve el mundo donde esta el jugador.
---
--- El mundo viene del `PlayerService` (estado de sesion). Si no esta todavia
--- inicializado, cae al default de `WorldService`; sin `WorldService` ni session
--- no se puede ofrecer nada de forma segura.
--- @param player Player?
--- @return string? worldId
local function resolveWorldId(player: Player?): string?
	if Service._playerService and player then
		local session = Service._playerService.GetSessionFromPlayer(player)

		if session and session.WorldId then
			return session.WorldId
		end
	end

	if Service._worldService then
		return Service._worldService.GetDefaultWorldId()
	end

	return nil
end

-- ---------------------------------------------------------------
-- Metricas (eventos del juego -> avance)
-- ---------------------------------------------------------------

--- Actividades de un tipo, cacheadas porque `RecordMetric` se llama en CADA
--- monstruo derrotado y en CADA bloque destruido: recorrer el catalogo entero
--- en cada llamada seria trabajo desperdiciado en el bucle mas caliente.
--- @param activityType string
--- @return { any }
local function definitionsOfType(activityType: string): { any }
	local cached = Service._typeCache

	if not cached then
		cached = {}
		Service._typeCache = cached
	end

	local byType = cached[activityType]

	if not byType then
		byType = {}
		cached[activityType] = byType

		for _, definition in ipairs(ActivityCatalog.List()) do
			if definition.Type == activityType then
				table.insert(byType, definition)
			end
		end
	end

	return byType
end

--- Registra un evento de juego y avanza las actividades que escuchan ese tipo.
---
--- Es el CAMINO UNICO por el que una actividad de_tipo (Hunt/Defense/etc.)
--- avanza. Lo llaman los servicios del servidor cuando ocurre algo real: un
--- monstruo derrotado, una ronda ganada, un bloque destruido.
---
--- NO publica el offer: la oferta se recalcula en la proxima llamada a
--- `TryRequestOffer`. Un evento de progreso no cambia la oferta activa del
--- jugador, y recalculala en cada muerte seria trabajo en el bucle caliente.
--- @param player Player? quien causo el evento
--- @param activityType string una de `ActivitiesRules.ActivityType`
--- @param amount number? incremento (por defecto 1)
--- @return number advanced cuantas avanzaron
--- @return { string } newlyCompleted ids completados en ESTE evento
function Service.RecordMetric(player: Player?, activityType: string, amount: number?): (number, { string })
	local state = activityStateOf(player)

	if not state then
		return 0, {}
	end

	local definitions = definitionsOfType(activityType)

	if #definitions == 0 then
		return 0, {}
	end

	local increment = amount or 1
	local advanced = 0
	local newlyCompleted: { string } = {}

	for _, definition in ipairs(definitions) do
		local _, justCompleted = ActivitiesRules.Advance(state, definition, increment, nowSeconds())

		if justCompleted then
			advanced += 1
			table.insert(newlyCompleted, definition.Id)
		end
	end

	if #newlyCompleted > 0 then
		Service._stats.completed += 1
		-- Una actividad completada pasa a cooldown hasta la proxima oferta
		-- del dia: evita farmear el mismo punto en bucle.
		for _, id in ipairs(newlyCompleted) do
			ActivitiesRules.SetCooldown(
				state,
				id,
				nowSeconds() + ActivitiesRules.CompletionCooldown(ActivityCatalog.Get(id) or { Cooldown = nil })
			)
		end

		Service.PublishProgress(player, newlyCompleted)
	end

	return advanced, newlyCompleted
end

-- ---------------------------------------------------------------
-- Progreso por interaccion (Discovery/Rescue/Mechanic/Collection)
-- ---------------------------------------------------------------

--- Tipos que el jugador avanza INTERACTUANDO con un punto del mapa.
local INTERACTABLE = {
	[ActivitiesRules.ActivityType.Discovery] = true,
	[ActivitiesRules.ActivityType.Rescue] = true,
	[ActivitiesRules.ActivityType.Mechanic] = true,
	[ActivitiesRules.ActivityType.Collection] = true,
}

--- Avanza una actividad de punto (Discovery/Rescue/Mechanic/Collection) si el
--- jugador esta cerca del punto registrado.
---
--- La proximidad se comprueba en el SERVIDOR con la posicion del personaje:
--- si el cliente mandara la distancia, el filtro comprobara un dato que el
--- atacante controla. El `requestId` del avance incluye la actividad y el
--- jugador, para que un reenvio no duplique el progreso.
--- @param player Player?
--- @param rawId any
--- @return boolean accepted
--- @return string? rejection
function Service.TryInteract(player: Player?, rawId: any): (boolean, string?)
	if not player then
		return false, ActivitiesRules.Reject.NoProfile
	end

	local definition = ActivityCatalog.Get(rawId)

	if not definition then
		Service._stats.rejected += 1
		return false, ActivitiesRules.Reject.UnknownActivity
	end

	local activityType = definition.Type

	if not INTERACTABLE[activityType] then
		Service._stats.rejected += 1
		return false, ActivitiesRules.Reject.InvalidType
	end

	local state = activityStateOf(player)

	if not state then
		Service._stats.rejected += 1
		return false, ActivitiesRules.Reject.NoProfile
	end

	-- El punto debe estar registrado; sin el, no se avanza: es mejor no
	-- avanzar que avanzar sin verificacion de posicion.
	local point = Service._points[ActivitiesRules.NormalizeId(definition.Id)]

	if not point then
		Service._stats.rejected += 1
		return false, "no_point"
	end

	if not player.Character then
		Service._stats.rejected += 1
		return false, "no_character"
	end

	local root = player.Character:FindFirstChild("HumanoidRootPart")

	if not root or not root:IsA("BasePart") then
		Service._stats.rejected += 1
		return false, "no_root"
	end

	local distance = (Vector3.new(root.Position.X, root.Position.Y, root.Position.Z) - point.Position).magnitude

	if distance > Service.INTERACT_RANGE then
		Service._stats.rejected += 1
		return false, "out_of_range"
	end

	Service._stats.interacted += 1

	local progress, justCompleted = ActivitiesRules.Advance(state, definition, 1, nowSeconds())

	Service.PublishProgress(player, { definition.Id }, progress, definition.Target)

	if justCompleted then
		Service._stats.completed += 1
		ActivitiesRules.SetCooldown(
			state,
			definition.Id,
			nowSeconds() + ActivitiesRules.CompletionCooldown(definition)
		)
	end

	Service._profileService.MarkDirty(player)

	return true, nil
end

-- ---------------------------------------------------------------
-- Oferta y reclamo
-- ---------------------------------------------------------------

--- Calcula la oferta de hoy para el mundo del jugador, descartando actividades
--- que ya fueron reclamadas o que estan en cooldown.
---
--- La oferta la decide el SERVIDOR: si el cliente eligiera, un exploit podria
--- pedir la actividad mas cara todas las veces. El `size` del cliente es solo
--- un maximo: el servidor lo acota al catalogo del mundo.
--- @param player Player?
--- @param size number?
--- @return { string } activityIds ofertados (normalizados)
function Service.TryRequestOffer(player: Player?, size: number?): { string }
	local state = activityStateOf(player)

	if not state then
		return {}
	end

	local worldId = resolveWorldId(player)

	if not worldId then
		Logger.Warn("ActivityService: no se pudo resolver el mundo del jugador para la oferta.")
		return {}
	end

	local definitions = ActivityCatalog.ForWorld(worldId)
	local roll = ActivitiesRules.RollDailyOffer(definitions, nowSeconds(), size or ActivitiesRules.OFFER_SIZE)

	-- El jugador no ve actividades reclamadas ni en cooldown: la oferta debe
	-- ser siempre accionable. Una actividad COMPLETA pero no reclamada SIGUE
	-- en la oferta, asi el jugador la ve y puede reclamarla.
	local offer: { string } = {}

	for _, activityId in ipairs(roll) do
		if not ActivitiesRules.IsClaimed(state, activityId)
			and not ActivitiesRules.IsOnCooldown(state, activityId, nowSeconds()) then
			table.insert(offer, activityId)
		end
	end

	Service._stats.offered += 1
	Service.PublishOffer(player, offer)

	return offer
end

--- Publica la oferta en un atributo: la UI lista las actividades por id.
--- @param player Player?
--- @param offer { string }
function Service.PublishOffer(player: Player?, offer: { string })
	if not player then
		return
	end

	player:SetAttribute("ActivityOffer", table.concat(offer, ","))
end

--- Publica el progreso de actividades en un atributo de jugador.
---
--- El atributo es un texto "id:actual|objetivo" por actividad, separadas por
--- ";": los atributos de Roblox no admiten tablas anidadas de forma estable.
--- Cuando no se pasa progreso objetivo (por ejemplo, la notificacion de
--- completado tras un evento), se publica solo el id.
--- @param player Player?
--- @param ids { string }
--- @param progress number?
--- @param target number?
function Service.PublishProgress(
	player: Player?,
	ids: { string },
	progress: number?,
	target: number?
)
	if not player or not ids then
		return
	end

	local parts: { string } = {}

	for _, id in ipairs(ids) do
		if progress and target then
			table.insert(parts, ("%s:%d|%d"):format(id, progress, target))
		else
			table.insert(parts, id)
		end
	end

	player:SetAttribute("ActivityProgress", table.concat(parts, ";"))
end

--- Paga una recompensa ya comprometida. La llamada ANTES de `TryClaim` a
-- proposito: Luau resuelve los locales en tiempo de ejecucion, asi que un
-- `local function` declarado DESPUES tendria `nil` al invocarse.
--
-- Las monedas (Coins, Gems) van por `EconomyService.GrantCurrency`; los
-- materiales (Mat_*) van por `InventoryService.AddItem`. Si falta el
-- servicio de inventario, los materiales se registran como error pero no
-- se niega la recompensa de monedas.
--- @param player Player
--- @param rewards { [string]: number }
--- @param activityId string
--- @return { [string]: number } granted lo concedido de verdad
local function deliver(
	player: Player,
	rewards: { [string]: number },
	activityId: string
): { [string]: number }
	local granted: { [string]: number } = {}

	if not Service._economyService then
		Logger.Error("ActivityService: sin EconomyService; la recompensa se consumio sin pagar.")
		return granted
	end

	for rewardKey, amount in pairs(rewards) do
		Service._sequence += 1

		-- El `requestId` lo genera el SERVIDOR e incluye la actividad y el
		-- jugador: si la entrega se reintentara, el ledger la reconoceria como
		-- peticion repetida en vez de concedir dos veces.
		local requestId = ("activity:%s:%d:%d"):format(activityId, player.UserId, Service._sequence)
		local ok, err

		if EconomyRules.IsValidCurrency(rewardKey) then
			ok, _, err = Service._economyService.GrantCurrency(
				player,
				rewardKey,
				amount,
				"actividad",
				"activity",
				{ activityId = activityId, requestId = requestId },
				requestId
			)
		else
			if not Service._inventoryService then
				Logger.Error(
					("ActivityService: sin InventoryService; no se pudo pagar '%s' a %s"):format(
						tostring(rewardKey),
						player.Name
					)
				)
			else
				ok, err = Service._inventoryService.AddItem(
					player,
					rewardKey,
					amount,
					"activity",
					requestId
				)
			end
		end

		if ok then
			granted[rewardKey] = amount
		else
			Logger.Error(
				("ActivityService: no se pudo pagar '%s' a %s: %s"):format(
					tostring(rewardKey),
					player.Name,
					tostring(err)
				)
			)
		end
	end

	return granted
end

--- Reclama la recompensa de una actividad.
---
--- El unico camino que paga. El cliente pide por `ExploreAction.Claim` el
--- `activityId` y NADA mas: ni progreso, ni recompensa, ni un booleano de
--- "completada". El servidor decide con SU progreso.
--- @param player Player?
--- @param rawId any
--- @return boolean accepted
--- @return string? rejection
--- @return { [string]: number }? granted
function Service.TryClaim(
	player: Player?,
	rawId: any
): (boolean, string?, { [string]: number }?)
	local state = activityStateOf(player)

	if not state then
		Service._stats.rejected += 1
		return false, ActivitiesRules.Reject.NoProfile, nil
	end

	-- El reclamo ATOMICO marca antes de pagar. Un doble clic o un reintento
	-- encuentran el hueco ocupado y no pagan dos veces.
	local accepted, rejection, rewards = ActivitiesRules.Claim(state, rawId, ActivityCatalog.GetAll())

	if not accepted then
		if rejection == ActivitiesRules.Reject.AlreadyClaimed then
			Service._stats.duplicateClaims += 1
		else
			Service._stats.rejected += 1
		end

		Logger.Debug(
			("ActivityService: %s no pudo reclamar '%s': %s"):format(
				player.Name,
				tostring(rawId),
				tostring(rejection)
			)
		)

		Service.PublishClaimResult(player, false, rejection, nil)
		return false, rejection, nil
	end

	Service._stats.claimed += 1

	-- El pago va DESPUES de marcar el reclamo: si falla, el reclamo queda
	-- consumido y se avisa.
	local granted = deliver(player, rewards or {}, ActivitiesRules.NormalizeId(rawId) or "")

	Service._profileService.MarkDirty(player)
	Service.PublishClaimResult(player, true, nil, granted)

	Logger.Info(("ActivityService: %s reclamo '%s'"):format(player.Name, tostring(rawId)))

	return true, nil, granted
end

--- Publica el resultado de un reclamo de actividad.
--- @param player Player
--- @param accepted boolean
--- @param rejection string?
--- @param granted { [string]: number }?
function Service.PublishClaimResult(
	player: Player,
	accepted: boolean,
	rejection: string?,
	granted: { [string]: number }?
)
	-- Se escribe en una variable y se publica, en vez de usar una EXPRESION
	-- `if` dentro de la llamada: un analizador estatico que no distingue
	-- sintaxis real de convenciones podria contar un bloque que no existe.
	local outcome = "rejected"

	if accepted then
		outcome = "claimed"
	end

	-- `granted` es una tabla { currency = amount }: `SetAttribute` no admite
	-- diccionarios (Roblox rechaza "Dictionary is not a supported attribute
	-- type"). Se serializa como "currency:amount,currency:amount" para que
	-- la UI lo lea sin un segundo remoto.
	local rewardText = ""

	if granted and type(granted) == "table" then
		local parts = {}
		for currency, amount in pairs(granted) do
			table.insert(parts, ("%s:%d"):format(tostring(currency), tonumber(amount) or 0))
		end
		table.sort(parts)
		rewardText = table.concat(parts, ",")
	end

	player:SetAttribute("ActivityClaimOutcome", outcome)
	player:SetAttribute("ActivityClaimRejection", rejection)
	player:SetAttribute("ActivityClaimReward", rewardText)
end

--- Cuantas actividades del jugador estan listas para reclamar.
--- @param player Player?
--- @return number
function Service.GetClaimableCount(player: Player?): number
	local state = activityStateOf(player)

	if not state then
		return 0
	end

	local count = 0

	for id in pairs(ActivityCatalog.GetAll()) do
		if ActivitiesRules.IsComplete(state, id) and not ActivitiesRules.IsClaimed(state, id) then
			count += 1
		end
	end

	return count
end

--- Solo para pruebas: sustituye el reloj del servicio.
--- @param clock () -> number
function Service._setClock(clock: () -> number)
	nowSeconds = clock
end

--- Resumen para observabilidad.
--- @return { [string]: number }
function Service.GetStats(): { [string]: number }
	return {
		offered = Service._stats.offered,
		interacted = Service._stats.interacted,
		completed = Service._stats.completed,
		claimed = Service._stats.claimed,
		duplicateClaims = Service._stats.duplicateClaims,
		rejected = Service._stats.rejected,
	}
end

return Service
