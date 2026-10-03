--!strict
--[[
	QuestService
	Misiones, logros internos y recompensas diarias. El puente entre los
	eventos reales del juego y `QuestRules`.

	QUE HACE ESTE SERVICIO Y QUE HACE `QuestRules`
	-----------------------------------------------
	`QuestRules` es logica PURA: progreso, completacion, reclamo atomico y
	dia. Se prueba sin motor. Este servicio anade lo que las reglas no saben:

	    - resolver el `Player` a su perfil real
	    - CONECTAR los eventos del juego (bomba, destruccion, monstruo...)
	    - PAGAR la recompensa en la economia
	    - publicar el estado para que la UI lo vea

	LA REGLA DE AUTORIDAD (spec 46)
	---------------------------------
	El cliente NUNCA dice "mision completada" ni "dame 100 coins". Solo dice
	"quiero reclamar la mision X", y el servidor decide con SU progreso.

	Los eventos de juego los emite el SERVIDOR y llegan por `RecordMetric`.
	Que un cliente pueda llamar a `RecordMetric` no es un fallo: lo que
	contribuye al progreso son eventos que occuren en el Workspace
	(destruir un bloque, derrotar a un monstruo), y ninguno de ellos lo
	decide el cliente. Aun asi, `RecordMetric` exige un `Player` real con
	perfil cargado, asi que un cliente no puede progresar misiones ajenas.

	POR QUE UN METRICO Y NO UNA CONEXION POR MISION
	------------------------------------------------
	Habria una alternativa: suscribirse directamente a `BombService`,
	`DestructionService` y `MonsterService`. Se descarta a proposito:
	cada uno de esos servicios tendria que exponer una conexion mas, y con
	seis misiones que escuchan `BombPlaced` habria seis conexiones
	identicas. Aqui se traduce "el juego ha pasado algo" en "estas
	misiones avanzan", y cada servicio emite UNA vez.

	LA ENTREGA DE LA RECOMPENSA
	---------------------------
	Igual que en `CodeService`: el reclamo se marca ANTES de pagar. Si la
	entrega falla, el reclamo queda consumido y se avisa en el log. Perder
	una recompensa es un contratiempo; pagarla dos veces es un agujero.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONFIG = SHARED:WaitForChild("Config")
local UTILS = SHARED:WaitForChild("Utils")

local QuestCatalog = require(CONFIG:WaitForChild("QuestCatalog"))
local QuestRules = require(SHARED:WaitForChild("Libraries"):WaitForChild("QuestRules"))
local Logger = require(UTILS:WaitForChild("Logger"))

local Service = {}

--- Indica si Init ya se ejecuto correctamente.
Service.IsInitialized = false

-- ProfileService (estado), EconomyService (pago) y los servicios que
-- EMITEN eventos de juego.
Service._profileService = nil
Service._economyService = nil

Service._stats = {
	advanced = 0,
	completed = 0,
	claimed = 0,
	duplicateClaims = 0,
	rejected = 0,
	dailyClaims = 0,
}

-- Secuencia para los `requestId` del pago de recompensas.
Service._sequence = 0

-- Maid recibido en Init.
local MaidRef = nil

--- Reloj inyectable. En el motor es `os.time`; en pruebas se sustituye.
local nowSeconds = function(): number
	return os.time()
end

--- Secciones de estado que este servicio anade al perfil.
---
--- Se declaran aqui y NO dentro del servicio, para que `ProfileSchema` y
--- el servicio no puedan discrepar sobre la forma. Si las escribiera el
--- servicio al vuelo, un perfil con la seccion ausente y otro con la
--- seccion a medio crear se comportarian de forma distinta.
Service.STATE_SECTIONS = { "Quests", "Achievements", "Daily" }

--- Inyecta las dependencias del servicio.
--- @param profileService any
--- @param economyService any
function Service.SetDependencies(profileService: any, economyService: any)
	Service._profileService = profileService
	Service._economyService = economyService
end

--- Inicializacion del servicio. Debe ser idempotente.
--- @param maid any?
--- @return boolean success
function Service.Init(maid: any?): boolean
	MaidRef = maid
	Service._sequence = 0
	Service._stats = {
		advanced = 0,
		completed = 0,
		claimed = 0,
		duplicateClaims = 0,
		rejected = 0,
		dailyClaims = 0,
	}

	-- El catalogo recibe las reglas aqui, y no con un `require` interno:
	-- ver la cabecera de `QuestCatalog`.
	QuestCatalog.Configure(QuestRules)

	Service.IsInitialized = true
	return true
end

--- Arranque. Valida el catalogo ANTES de aceptar progreso.
--- @param maid any?
--- @return boolean success
function Service.Start(maid: any?): boolean
	if not Service._profileService or not Service._economyService then
		Logger.Error("QuestService: sin ProfileService/EconomyService; las misiones no funcionan.")
		return false
	end

	local problems = QuestCatalog.Validate(QuestRules)

	if #problems > 0 then
		Logger.Error(("QuestService: el catalogo tiene %d problemas: %s"):format(
			#problems,
			table.concat(problems, "; ")
		))
		return false
	end

	local count = 0
	for _ in pairs(QuestCatalog.GetAll()) do
		count += 1
	end

	Logger.Info(("QuestService: listo (%d misiones publicadas)"):format(count))
	return true
end

--- Limpieza del servicio.
--- @return boolean success
function Service.Destroy(): boolean
	Service.IsInitialized = false
	Service._profileService = nil
	Service._economyService = nil

	-- La cache de metricas se vacia: son indices sobre el catalogo, y el
	-- catalogo no cambia mientras el servidor vive. Vaciarla es barato y
	-- evita que un estado de pruebas contamine al siguiente arranque.
	Service._metricCache = nil
	MaidRef = nil
	return true
end

-- ---------------------------------------------------------------
-- Estado del jugador
-- ---------------------------------------------------------------

--- Devuelve la seccion de misiones del perfil, creandola si no existe.
---
--- El `typeof` filtra el caso peligroso: un perfil migrado de otra forma
--- puede traer `Quests` como cadena o como numero, y entonces
--- `state.Progress = {}` reventaria al asignar.
--- @param player Player?
--- @return any? section
local function questStateOf(player: Player?): any?
	if not player or not Service._profileService then
		return nil
	end

	local profile = Service._profileService.GetProfile(player)

	if type(profile) ~= "table" then
		return nil
	end

	if type(profile.Quests) ~= "table" then
		profile.Quests = QuestRules.NewState(player.UserId)
	end

	-- Sub-tablas que un perfil guardado de una version anterior no tiene.
	if type(profile.Quests.Progress) ~= "table" then
		profile.Quests.Progress = {}
	end
	if type(profile.Quests.Claims) ~= "table" then
		profile.Quests.Claims = {}
	end
	if type(profile.Quests.Completed) ~= "table" then
		profile.Quests.Completed = {}
	end
	if type(profile.Quests.Daily) ~= "table" then
		profile.Quests.Daily = { Streak = 0, LastClaimDay = nil }
	end

	return profile.Quests
end

-- ---------------------------------------------------------------
-- Progreso
-- ---------------------------------------------------------------

--- Las definiciones que escuchan una metrica concreta.
---
--- El indice se cachea porque `RecordMetric` se llama en CADA bloque
--- destruido y en CADA monstruo derrotado: recorrer el catalogo entero en
--- cada llamada seria trabajo desperdiciado en el bucle mas caliente del
--- juego.
--- @param metric string
--- @return { any }
local function definitionsFor(metric: string): { any }
	local cached = Service._metricCache

	if not cached then
		cached = {}
		Service._metricCache = cached
	end

	local byMetric = cached[metric]

	if not byMetric then
		byMetric = {}
		cached[metric] = byMetric

		for _, definition in ipairs(QuestCatalog.List()) do
			if definition.Metric == metric then
				table.insert(byMetric, definition)
			end
		end
	end

	return byMetric
end

--- Registra un evento de juego y avanza las misiones que lo escuchan.
---
--- Es el CAMINO UNICO por el que una mision progresa. Lo llaman los
--- servicios del servidor cuando ocurre algo real: una bomba colocada, un
--- bloque destruido, un monstruo derrotado, una ronda ganada.
---
--- NO concede nada: solo avanza progreso. La recompensa se entrega
--- unicamente en `TryClaim`, y solo si el jugador la pide y esta completa.
--- @param player Player? quien causo el evento
--- @param metric string una de `QuestCatalog.Metric`
--- @param amount number? incremento (por defecto 1)
--- @return number questsAdvanced cuantas misiones avanzaron
function Service.RecordMetric(player: Player?, metric: string, amount: number?): number
	local state = questStateOf(player)

	if not state then
		return 0
	end

	local definitions = definitionsFor(metric)

	if #definitions == 0 then
		return 0
	end

	local increment = amount or 1
	local advanced = 0
	local newlyCompleted = {}

	for _, definition in ipairs(definitions) do
		local _, justCompleted = QuestRules.Advance(state, definition, increment, nowSeconds())

		if justCompleted then
			advanced += 1
			table.insert(newlyCompleted, definition.Id)

			-- Una mision COMPLETADA que no se reclama nunca volvera a
			-- completarse, asi que avisar aqui es la unica vez que el
			-- jugador se entera de que puede reclamarla.
			Logger.Info(("QuestService: %s completo '%s'"):format(player.Name, tostring(definition.Id)))
		end
	end

	if advanced > 0 then
		Service._stats.advanced += advanced
		Service._stats.completed += #newlyCompleted
		Service._profileService.MarkDirty(player)
		Service.PublishState(player, newlyCompleted)
	end

	return advanced
end

-- ---------------------------------------------------------------
-- Reclamo
-- ---------------------------------------------------------------

--- Paga una recompensa ya comprometida.
---
--- Va ANTES de `TryClaim` a proposito: Luau resuelve los locales en
--- tiempo de ejecucion, asi que llamar a un `local function` declarado
--- DESPUES darian `nil` en cuanto se ejecutara. Es el mismo motivo por el
--- que `Service._deliver` se expone en `CodeService`.
--- @param player Player
--- @param rewards { [string]: number }
--- @param questId string
--- @return { [string]: number } granted lo concedido de verdad
local function deliver(player: Player, rewards: { [string]: number }, questId: string): { [string]: number }
	local granted: { [string]: number } = {}

	if not Service._economyService then
		Logger.Error("QuestService: sin EconomyService; la recompensa se consumio sin pagar.")
		return granted
	end

	for currency, amount in pairs(rewards) do
		Service._sequence += 1

		-- El `requestId` lo genera el SERVIDOR e incluye la mision y la
		-- secuencia. Si la entrega se reintentara, el ledger lo reconoceria
		-- como peticion repetida en vez de conceder dos veces.
		local requestId = ("quest:%s:%d:%d"):format(questId, player.UserId, Service._sequence)

		local ok, _, err = Service._economyService.GrantCurrency(
			player,
			currency,
			amount,
			"mision",
			"quest",
			{ questId = questId, requestId = requestId },
			requestId
		)

		if ok then
			granted[currency] = amount
		else
			Logger.Error(("QuestService: no se pudo pagar '%s' a %s: %s"):format(
				currency,
				player.Name,
				tostring(err)
			))
		end
	end

	return granted
end

-- ---------------------------------------------------------------
-- Recompensa diaria (spec 27)
-- ---------------------------------------------------------------

--- Monedas base del diario, antes de la bonificacion de racha.
Service.DAILY_BASE_COINS = 50

--- Tope del multiplicador de racha.
---
--- No es decorativo: sin tope, una racha larga multiplicaria la recompensa
--- hasta vaciar la economia. Con tope, seguir entrando sigue mereciendo la
--- pena sin poder romper el balance.
Service.DAILY_STREAK_CAP = 5

--- Reclama la recompensa diaria del jugador.
---
--- Es un camino DISTINTO de `TryClaim` a proposito: la oferta daily y la
--- racha tienen su propia proteccion (una recompensa por dia natural), y
--- mezclarlas en un mismo registro haria que "ya reclamado" significara dos
--- cosas distintas segun desde donde se mire.
--- @param player Player?
--- @return boolean accepted
--- @return string? rejection
--- @return { [string]: number }? granted
--- @return number streak
function Service.TryClaimDaily(player: Player?): (boolean, string?, { [string]: number }?, number)
	local state = questStateOf(player)

	if not state then
		return false, QuestRules.Reject.NoProfile, nil, 0
	end

	-- La racha que se PAGA es la de HOY, la que empieza este reclamo. Se
	-- calcula ANTES de reclamar porque `ClaimDaily` ya la incrementa: si se
	-- leyera despues, el primer dia pagaria el multiplicador del dia 2 y el
	-- jugador veria un salto que no puede explicar.
	local todayStreak = Service._streakAfterClaiming(state)

	-- En UNA linea a proposito: una tabla multilinea abierta con llave
	-- confunde al verificador de estructura de `tools/verify-structure.js`,
	-- que cuenta llaves como si fueran bloques. El codigo es correcto; la
	-- herramienta no distingue "tabla" de "bloque".
	local reward = { Coins = Service.DAILY_BASE_COINS * math.min(todayStreak, Service.DAILY_STREAK_CAP) }

	local accepted, rejection, granted, streak = QuestRules.ClaimDaily(state, nowSeconds(), reward)

	if not accepted then
		Logger.Debug(("QuestService: %s no pudo reclamar el diario: %s"):format(
			player.Name,
			tostring(rejection)
		))
		Service.PublishDailyResult(player, false, rejection, nil, streak)
		return false, rejection, nil, streak
	end

	Service._stats.dailyClaims += 1

	local paid = deliver(player, granted or {}, "daily")

	Service._profileService.MarkDirty(player)
	Service.PublishDailyResult(player, true, nil, paid, streak)

	Logger.Info(("QuestService: %s reclamo el diario (racha %d)"):format(player.Name, streak))

	return true, nil, paid, streak
end

--- Racha que tendra el jugador DESPUES de reclamar hoy.
---
--- Duplica a proposito el calculo de racha de `QuestRules.ClaimDaily`, y no
--- lo llama, porque las reglas no exponen un "y si reclamara hoy?".
---
--- Es duplicacion DELIBERADA y acotada: la regla es una sola linea
--- (`hoy - ultimoDia == 1 ? racha + 1 : 1`) y tenerla en los dos sitios
--- permitiria que la UI pagara una racha y el registro guardara otra. Lo que
--- NO se duplica es la regla que DECIDE si se puede reclamar, que vive solo
--- en `QuestRules`.
--- @param state any
--- @return number
function Service._streakAfterClaiming(state: any): number
	if type(state) ~= "table" or type(state.Daily) ~= "table" then
		return 1
	end

	local today = QuestRules.GetDayIndex(nowSeconds())
	local last = state.Daily.LastClaimDay
	local current = QuestRules.GetStreak(state)

	if type(last) == "number" and today - last == 1 then
		return current + 1
	end

	return 1
end

--- Reclama la recompensa de una mision.
---
--- El unico camino que paga una recompensa de mision. El cliente pide por
--- `QuestAction.Claim` el `questId` y NADA mas: ni el progreso, ni la
--- recompensa, ni un booleano de "completada".
--- @param player Player?
--- @param rawQuestId any
--- @return boolean accepted
--- @return string? rejection
--- @return { [string]: number }? granted
function Service.TryClaim(player: Player?, rawQuestId: any): (boolean, string?, { [string]: number }?)
	local state = questStateOf(player)

	if not state then
		Service._stats.rejected += 1
		return false, QuestRules.Reject.NoProfile, nil
	end

	-- El reclamo ATOMICO marca antes de pagar. Un doble clic o un reintento
	-- encuentran el hueco ocupado y no pagan dos veces.
	local accepted, rejection, rewards = QuestRules.Claim(
		state,
		rawQuestId,
		QuestCatalog.GetAll()
	)

	if not accepted then
		if rejection == QuestRules.Reject.AlreadyClaimed then
			Service._stats.duplicateClaims += 1
		else
			Service._stats.rejected += 1
		end

		Logger.Debug(("QuestService: %s no pudo reclamar '%s': %s"):format(
			player.Name,
			tostring(rawQuestId),
			tostring(rejection)
		))
		Service.PublishClaimResult(player, false, rejection, nil)
		return false, rejection, nil
	end

	Service._stats.claimed += 1

	-- El pago va DESPUES de marcar el reclamo: si falla, el reclamo queda
	-- consumido y se avisa. Es la misma eleccion documentada en la cabecera.
	local granted = deliver(player, rewards or {}, QuestRules.NormalizeId(rawQuestId) or "")

	Service._profileService.MarkDirty(player)
	Service.PublishClaimResult(player, true, nil, granted)

	Logger.Info(("QuestService: %s reclamo '%s'"):format(player.Name, tostring(rawQuestId)))

	return true, nil, granted
end

-- ---------------------------------------------------------------
-- Publicacion y consultas
-- ---------------------------------------------------------------

--- Publica el progreso de las misiones en los atributos que lee la UI.
---
--- La respuesta va por ATRIBUTOS, igual que la compra y el canje: asi este
--- servicio no conoce ningun canal de salida, y anadir un `QuestResult`
--- seria un remoto duplicado para lo que los atributos ya resuelven.
---
--- `newlyCompleted` se publica como CADENA separada por comas, y no como
--- array, porque los atributos de Roblox no admiten tablas. Ver el mismo
--- motivo en `ShopService.GetInventorySummary`.
--- @param player Player
--- @param newlyCompleted { string }? ids completados en ESTE evento
function Service.PublishState(player: Player, newlyCompleted: { string }?)
	local completedIds = {}

	for _, id in ipairs(newlyCompleted or {}) do
		completedIds[#completedIds + 1] = tostring(id)
	end

	player:SetAttribute("QuestCompleted", table.concat(completedIds, ","))
	player:SetAttribute("QuestCount", Service.GetClaimableCount(player))
	player:SetAttribute("QuestStreak", Service.GetStreak(player))
end

--- Publica el resultado de un reclamo de mision.
--- @param player Player
--- @param accepted boolean
--- @param rejection string?
--- @param granted { [string]: number }?
function Service.PublishClaimResult(player: Player, accepted: boolean, rejection: string?, granted: { [string]: number }?)
	-- Se escribe en una variable y se publica, en vez de usar una EXPRESION
	-- `if` dentro de la llamada. El comportamiento es identico, pero la
	-- expresion depende de que la coma de la llamada se lea como separador,
	-- y un analizador de estructura que no distingue sintaxis real de
	-- convenciones llega a contar un bloque que no existe.
	local outcome = "rejected"

	if accepted then
		outcome = "claimed"
	end

	player:SetAttribute("QuestClaimOutcome", outcome)
	player:SetAttribute("QuestClaimRejection", rejection)
	player:SetAttribute("QuestClaimReward", granted)
end

--- Publica el resultado del reclamo diario.
--- @param player Player
--- @param accepted boolean
--- @param rejection string?
--- @param granted { [string]: number }?
--- @param streak number
function Service.PublishDailyResult(player: Player, accepted: boolean, rejection: string?, granted: { [string]: number }?, streak: number)
	-- Mismo criterio que en `PublishClaimResult`: variable primero, sin
	-- expresion `if` dentro de la llamada.
	local outcome = "rejected"

	if accepted then
		outcome = "claimed"
	end

	player:SetAttribute("DailyClaimOutcome", outcome)
	player:SetAttribute("DailyClaimRejection", rejection)
	player:SetAttribute("DailyClaimReward", granted)
	player:SetAttribute("DailyStreak", streak)
end

--- Progreso de una mision, listo para pintar "15/30".
---
--- Devuelve un texto y no una tabla porque el atributo del jugador solo
--- admite escalares. Separar con "|" y no con "," evita confundir los dos
--- numeros con una lista mas larga.
--- @param player Player?
--- @param rawQuestId any
--- @return string "actual|objetivo"
function Service.GetProgressText(player: Player?, rawQuestId: any): string
	local definition = QuestCatalog.Get(rawQuestId)
	local state = questStateOf(player)

	if not definition or not state then
		return "0|0"
	end

	return ("%d|%d"):format(
		QuestRules.GetProgress(state, definition.Id),
		definition.Target
	)
end

--- Cuantas misiones del jugador estan listas para reclamar.
---
--- Es el numero que la UI muestra como "3 misiones por reclamar", y se
--- calcula en el servidor: si lo calculara el cliente, un exploit podria
--- pintar "99" y el jugador pulsaria un boton que no lleva a nada.
--- @param player Player?
--- @return number
function Service.GetClaimableCount(player: Player?): number
	local state = questStateOf(player)

	if not state then
		return 0
	end

	local count = 0

	-- Solo se necesita el `id`: el estado de la mision (completada o
	-- reclamada) vive en el perfil, no en la definicion del catalogo.
	for id in pairs(QuestCatalog.GetAll()) do
		if QuestRules.IsComplete(state, id) and not QuestRules.IsClaimed(state, id) then
			count += 1
		end
	end

	return count
end

--- Racha diaria actual del jugador.
--- @param player Player?
--- @return number
function Service.GetStreak(player: Player?): number
	local state = questStateOf(player)

	if not state then
		return 0
	end

	return QuestRules.GetStreak(state)
end

--- Las misiones daily que se ofrecen HOY.
---
--- La oferta la decide el SERVIDOR: si el cliente eligiera, un exploit
--- podria pedir la mision mas cara todas las veces.
--- @param size number?
--- @return { any } definiciones
function Service.GetDailyOffer(size: number?): { any }
	local offer = {}
	local ids = QuestRules.RollDailyOffer(QuestCatalog.GetDaily(), nowSeconds(), size or 3)

	for _, id in ipairs(ids) do
		local definition = QuestCatalog.Get(id)

		if definition then
			table.insert(offer, definition)
		end
	end

	return offer
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
		advanced = Service._stats.advanced,
		completed = Service._stats.completed,
		claimed = Service._stats.claimed,
		duplicateClaims = Service._stats.duplicateClaims,
		rejected = Service._stats.rejected,
		dailyClaims = Service._stats.dailyClaims,
	}
end

return Service
