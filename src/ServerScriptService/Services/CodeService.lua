--!strict
--[[
	CodeService
	Canje de codigos promocionales. El puente entre el jugador y `CodeRules`.

	QUE HACE ESTE SERVICIO Y QUE HACE `CodeRules`
	-----------------------------------------------
	`CodeRules` es logica PURA: normaliza, busca, comprueba caducidad y
	marca el canje de forma atomica. Se prueba con `luau.exe` sin motor.
	Este servicio anade lo que las reglas no pueden saber:

	    - resolver el `Player` a su perfil real
	    - ENTRGAR la recompensa en la economia del jugador
	    - publicar el resultado para que la UI lo vea
	    - limpiar lo que se creo al apagar

	EL FLUJO COMPLETO
	-----------------
	    CLIENTE   "quiero canjear X"
	      REMOTO  CodeAction.Redeem
	        GATEWAY  forma, esquema y frecuencia
	          ESTE    perfil? -> canje atomico -> recompensa -> registro
	        ATRIB   CodeOutcome / CodeRejection / CodeReward

	NINGUN PASO ENTRE EL REMOTO Y EL CANJE CONCEDE NADA. El unico que
	modifica estado es la llamada a `CodeRules.Redeem`, y es atomica: si algo
	falla despues (por ejemplo, la entrega de la recompensa), el canje
	QUEDA CONSUMIDO. Es la eleccion correcta: perder una recompensa es un
	contratiempo, pagar dos veces es un agujero de economia.

	POR QUE EL ESTADO DEL CANJE NO SE MEZCLA
	-----------------------------------------
	El canje se guarda en la seccion `Codes` del PERFIL, con una forma
	FIJA: `{ Redemptions = { [codigo] = true }, Counts = {} }`.

	El contador global de canjes vive FUERA del perfil, en
	`Service._global`, porque cada jugador tiene su propio perfil y ninguno
	veria los canjes de los demas: un codigo limitado a 100 usos se podria
	canjear 100 veces por jugador y el limite no existiria.

	El detalle que hace esto seguro: dentro de `Codes` NUNCA se escribe una
	clave numerica suelta. Si se escribiera `Codes["12"] = true` para decir
	"el jugador 12 canjeo esto", y el codigo se llamara `12`, las dos cosas
	compartirian hueco. Por eso las claves del interior son SIEMPRE codigos
	normalizados (alfanumericos) y las de `Counts` SIEMPRE cadenas de
	`userId`, en una tabla aparte.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONFIG = SHARED:WaitForChild("Config")
local UTILS = SHARED:WaitForChild("Utils")

local CodeCatalog = require(CONFIG:WaitForChild("CodeCatalog"))
local CodeRules = require(SHARED:WaitForChild("Libraries"):WaitForChild("CodeRules"))
local Logger = require(UTILS:WaitForChild("Logger"))

local Service = {}

--- Indica si Init ya se ejecuto correctamente.
Service.IsInitialized = false

-- ProfileService (estado) y EconomyService (pago de la recompensa).
Service._profileService = nil
Service._economyService = nil

-- Contador COMPARTIDO del servidor: codigo normalizado -> canjes totales.
--
-- Vive aqui y NO en el perfil por el motivo de la cabecera: es un limite
-- global y cada jugador tiene su propio perfil. Se inicializa en `Init` y
-- se vacia en `Destroy`, de modo que un arranque en caliente no hereda el
-- estado del arranque anterior.
Service._global = { RedeemedCodes = {} }

-- Limite de intentos por jugador. El gateway ya limita por canal, pero el
-- canje escribe en el perfil: sin un tope aqui, un cliente que reintenta
-- muchas veces genera una entrada de perfil por cada intento.
--
-- El limite cuenta INTENTOS, no canjes, y su ventana se renueva por
-- TIEMPO. Asi un jugador legitimo que canjea un codigo nuevo unas horas
-- despues no se encuentra con el residuo de un intento fallido anterior.
local MAX_ATTEMPTS_PER_WINDOW = 10
local ATTEMPT_WINDOW_SECONDS = 60

-- userId -> { count: number, windowStart: number }
Service._attempts = {}

-- Secuencia para los `requestId` de la entrega de la recompensa.
Service._sequence = 0

Service._stats = {
	accepted = 0,
	alreadyUsed = 0,
	expired = 0,
	exhausted = 0,
	rejected = 0,
	rateLimited = 0,
	granted = 0,
}

-- Maid recibido en Init.
local MaidRef = nil

--- Reloj inyectable. En el motor es `os.time`; en pruebas se sustituye.
local nowSeconds = function(): number
	return os.time()
end

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
	Service._global = { RedeemedCodes = {} }
	Service._attempts = {}
	Service._sequence = 0
	Service._stats = {
		accepted = 0,
		alreadyUsed = 0,
		expired = 0,
		exhausted = 0,
		rejected = 0,
		rateLimited = 0,
		granted = 0,
	}
	Service.IsInitialized = true
	return true
end

--- Arranque. Valida el catalogo ANTES de aceptar el primer canje.
--- @param maid any?
--- @return boolean success
function Service.Start(maid: any?): boolean
	if not Service._profileService or not Service._economyService then
		Logger.Error("CodeService: sin ProfileService/EconomyService; no se puede canjear.")
		return false
	end

	-- Un catalogo roto es un fallo de ARRANQUE, no de canje. Si se
	-- aceptara, el primer jugador que escribiera el codigo malo veria
	-- "no existe" y nadie sabria que el problema era nuestro.
	local problems = CodeCatalog.Validate(CodeRules)

	if #problems > 0 then
		Logger.Error(("CodeService: el catalogo tiene %d problemas: %s"):format(
			#problems,
			table.concat(problems, "; ")
		))
		return false
	end

	Logger.Info(("CodeService: listo (%d codigos publicados)"):format(#CodeCatalog.GetAll()))
	return true
end

--- Limpieza del servicio.
--- @return boolean success
function Service.Destroy(): boolean
	Service.IsInitialized = false
	Service._profileService = nil
	Service._economyService = nil
	Service._global = { RedeemedCodes = {} }
	Service._attempts = {}
	MaidRef = nil
	return true
end
-- ---------------------------------------------------------------
-- Estado del canje
-- ---------------------------------------------------------------

--- Devuelve la seccion `Codes` del perfil, creandola si no existe.
---
--- El `typeof` filtra el caso perigoso: un perfil corrupto o migrado de
--- forma incorrecta puede traer `Codes` como cadena o como numero. Sin
--- esta comprobacion, `state.Redemptions = {}` reventaria al asignar.
--- @param player Player?
--- @return any? section
local function codesStateOf(player: Player?): any?
	if not player or not Service._profileService then
		return nil
	end

	local profile = Service._profileService.GetProfile(player)

	if type(profile) ~= "table" then
		return nil
	end

	if type(profile.Codes) ~= "table" then
		profile.Codes = {}
	end

	if type(profile.Codes.Redemptions) ~= "table" then
		profile.Codes.Redemptions = {}
	end

	if type(profile.Codes.Counts) ~= "table" then
		profile.Codes.Counts = {}
	end

	return profile.Codes
end

--- Ventana de intento de un jugador, creando la que falte.
--- @param userId number
--- @return any bucket
local function attemptsOf(userId: number): any
	local bucket = Service._attempts[userId]

	if type(bucket) ~= "table" then
		bucket = { count = 0, windowStart = nowSeconds() }
		Service._attempts[userId] = bucket
	end

	return bucket
end

--- Indica si este jugador puede intentar un canje mas.
--- @param userId number
--- @return boolean allowed
function Service.CanAttempt(userId: number): boolean
	local bucket = attemptsOf(userId)
	local now = nowSeconds()

	if now - bucket.windowStart >= ATTEMPT_WINDOW_SECONDS then
		bucket.windowStart = now
		bucket.count = 0
	end

	return bucket.count < MAX_ATTEMPTS_PER_WINDOW
end

--- Consume un intento. Solo se llama DESPUES de que `CanAttempt` aprueba.
--- @param userId number
function Service.RecordAttempt(userId: number)
	local bucket = attemptsOf(userId)
	bucket.count += 1
end

--- Olvida el limite de intentos de un jugador. Se llama al salir.
--- @param userId number
function Service.ClearAttempts(userId: number)
	Service._attempts[userId] = nil
end

--- Resume una recompensa como texto, para el log.
---
--- Se ordenan las claves para que dos canjes de la MISMA recompensa
--- produzcan la MISMA linea: si el orden dependiera de `pairs`, el log
--- diria que un canje dio "Coins, Gems" y otro "Gems, Coins", y nadie
--- podria comparar las lineas.
--- @param granted { [string]: number }
--- @return string
local function describeReward(granted: { [string]: number }): string
	local keys = {}
	for currency in pairs(granted) do
		table.insert(keys, currency)
	end
	table.sort(keys)

	local parts = {}
	for _, currency in ipairs(keys) do
		table.insert(parts, ("%d %s"):format(granted[currency], currency))
	end

	if #parts == 0 then
		return "nada"
	end

	return table.concat(parts, " + ")
end

--- Paga la recompensa de un canje ya consumido.
---
--- Va DESPUES de `CodeRules.Redeem` a proposito: el uso del codigo ya
--- esta anotado cuando esta funcion corre. Si la economia no esta, el
--- canje se queda consumido sin pagar y se avisa en el log. Un fallo aqui
--- es un contratiempo; dar marcha atras abriria la via del pago doble.
--- @param player Player
--- @param rewards { [string]: number }
--- @param normalizedCode string?
--- @return { [string]: number } granted lo que se concedio de verdad
local function deliver(player: Player, rewards: { [string]: number }, normalizedCode: string?): { [string]: number }
	local granted: { [string]: number } = {}

	if not Service._economyService then
		Logger.Error("CodeService: sin EconomyService; el canje se consumio sin pagar.")
		return granted
	end

	for currency, amount in pairs(rewards) do
		Service._sequence += 1

		-- El `requestId` lo genera el SERVIDOR y lleva el codigo. Si el
		-- canje llegara a repetirse, el ledger lo reconoceria como
		-- peticion repetida en vez de conceder dos veces.
		local requestId = ("code:%s:%d:%d"):format(
			tostring(normalizedCode),
			player.UserId,
			Service._sequence
		)

		local ok, _, err = Service._economyService.GrantCurrency(
			player,
			currency,
			amount,
			"codigo",
			"code",
			{ code = normalizedCode, requestId = requestId },
			requestId
		)

		if ok then
			granted[currency] = amount
		else
			Logger.Error(("CodeService: no se pudo pagar '%s' a %s: %s"):format(
				currency,
				player.Name,
				tostring(err)
			))
		end
	end

	return granted
end
-- ---------------------------------------------------------------
-- Canje
-- ---------------------------------------------------------------

--- Canjea un codigo para un jugador.
---
--- Este es el CAMINO UNICO que concede una recompensa por codigo. Devuelve
--- un booleano y un motivo estable; la UI ya lee el saldo real de los
--- atributos que publica el servidor, asi que no necesita la recompensa
--- para pintarse.
--- @param player Player?
--- @param rawCode any lo que el jugador escribio
--- @return boolean accepted
--- @return string? rejection motivo estable (el que ve el jugador)
--- @return { [string]: number }? granted recompensa efectivamente pagada
function Service.TryRedeem(player: Player?, rawCode: any): (boolean, string?, { [string]: number }?)
	if not Service.IsInitialized then
		return false, "servicio_no_iniciado", nil
	end

	if not player then
		return false, "sin_jugador", nil
	end

	-- 1. El limite de frecuencia va PRIMERO y antes de tocar nada. Un
	-- jugador que spamea debe ser frenado sin generar una entrada de
	-- perfil por cada intento.
	if not Service.CanAttempt(player.UserId) then
		Service._stats.rateLimited += 1
		Logger.Warn(("CodeService: %s supera el limite de intentos de canje"):format(player.Name))
		return false, "demasiados_intentos", nil
	end
	Service.RecordAttempt(player.UserId)

	-- 2. Perfil cargado. Sin el no hay donde anotar el canje, y sin el
	-- registro el codigo podria canjearse otra vez en la siguiente
	-- sesion: eso no es un canje, es una pasada.
	local codes = codesStateOf(player)

	if not codes then
		Service._stats.rejected += 1
		return false, "no_profile", nil
	end

	-- 3. El canje ATOMICO: normaliza, busca, comprueba caducidad y tope
	-- global, y MARCA el uso antes de devolver. A partir de aqui el
	-- codigo esta gastado aunque la entrega de la recompensa falle.
	local accepted, rejection, rewards = CodeRules.Redeem(
		codes,
		Service._global,
		player.UserId,
		rawCode,
		nowSeconds(),
		CodeCatalog.GetAll()
	)

	if not accepted then
		if rejection == CodeRules.Reject.AlreadyUsed then
			Service._stats.alreadyUsed += 1
		elseif rejection == CodeRules.Reject.Expired then
			Service._stats.expired += 1
		elseif rejection == CodeRules.Reject.Exhausted then
			Service._stats.exhausted += 1
		else
			Service._stats.rejected += 1
		end

		Logger.Debug(("CodeService: %s no pudo canjear '%s': %s"):format(
			player.Name,
			tostring(rawCode),
			tostring(rejection)
		))
		Service.PublishRejection(player, rejection)
		return false, rejection, nil
	end

	Service._stats.accepted += 1

	-- 4. La entrega.
	local granted = deliver(player, rewards or {}, CodeRules.Normalize(rawCode))

	Service._stats.granted += 1
	Service._profileService.MarkDirty(player)
	Service.PublishResult(player, "redeemed", nil, granted)

	Logger.Info(("CodeService: %s canjeo un codigo (recompensa: %s)"):format(
		player.Name,
		describeReward(granted)
	))

	return true, nil, granted
end
-- ---------------------------------------------------------------
-- Publicacion y consultas
-- ---------------------------------------------------------------

--- Publica el resultado del canje en los atributos que lee la UI.
---
--- No hay remoto de salida: la respuesta viaja por atributos, igual que
--- la compra. Asi este servicio no conoce ningun canal, y anadir un
--- `CodeResult` seria un remoto duplicado para lo que los atributos ya
--- resuelven.
--- @param player Player
--- @param outcome string
--- @param rejection string?
--- @param granted { [string]: number }?
function Service.PublishResult(player: Player, outcome: string, rejection: string?, granted: { [string]: number }?)
	player:SetAttribute("CodeOutcome", outcome)
	player:SetAttribute("CodeRejection", rejection)
	player:SetAttribute("CodeReward", granted)
end

--- Publica un rechazo sin tocar la recompensa.
---
--- Se separa de `PublishResult` para que el camino de rechazo no pueda
--- escribir en `CodeReward` por descuido: si la UI leyera una recompensa
--- vieja mientras el canje acaba de fallar, veria "100 coins" debajo de
--- un "codigo invalido".
--- @param player Player
--- @param rejection string?
function Service.PublishRejection(player: Player, rejection: string?)
	player:SetAttribute("CodeOutcome", "rejected")
	player:SetAttribute("CodeRejection", rejection)
	player:SetAttribute("CodeReward", nil)
end

--- Codigos que el jugador ya canjeo, como cadena separada por comas.
---
--- Cadena y no tabla por la restriccion de los atributos de Roblox (solo
--- admiten escalares). Orden alfabetico para que la cadena no cambie entre
--- lecturas y la UI no parpadee.
--- @param player Player?
--- @return string
function Service.GetRedeemedSummary(player: Player?): string
	local codes = codesStateOf(player)

	if not codes then
		return ""
	end

	local ids = {}
	for code in pairs(codes.Redemptions) do
		ids[#ids + 1] = tostring(code)
	end
	table.sort(ids)

	return table.concat(ids, ",")
end

--- Cuantos codigos ha canjeado ESTE jugador.
--- @param player Player?
--- @return number
function Service.GetRedeemedCount(player: Player?): number
	local codes = codesStateOf(player)

	if not codes then
		return 0
	end

	local count = 0
	for _ in pairs(codes.Redemptions) do
		count += 1
	end

	return count
end

--- Cuantos canjes ha tenido un codigo en TODO el servidor.
---
--- Es la consulta que permite distinguir "agotado para todos" de "ya lo
--- usaste": las dos cosas son rechazos distintos y el jugador merece
--- saber cual de las dos es.
--- @param rawCode any
--- @return number
function Service.GetGlobalRedemptionCount(rawCode: any): number
	local normalized = CodeRules.Normalize(rawCode)

	if not normalized then
		return 0
	end

	local used = Service._global.RedeemedCodes[normalized]

	if type(used) ~= "number" then
		return 0
	end

	return used
end

--- Solo para pruebas: sustituye el reloj del servicio.
--- @param clock () -> number
function Service._setClock(clock: () -> number)
	nowSeconds = clock
end

--- Resumen para observabilidad.
--- @return { [string]: number }
function Service.GetStats(): { [string]: number }
	local totalAttempts = 0
	for _, bucket in pairs(Service._attempts) do
		totalAttempts += bucket.count
	end

	return {
		accepted = Service._stats.accepted,
		alreadyUsed = Service._stats.alreadyUsed,
		expired = Service._stats.expired,
		exhausted = Service._stats.exhausted,
		rejected = Service._stats.rejected,
		rateLimited = Service._stats.rateLimited,
		granted = Service._stats.granted,
		attempts = totalAttempts,
	}
end

return Service
