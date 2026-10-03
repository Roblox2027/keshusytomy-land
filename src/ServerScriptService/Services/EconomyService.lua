--!strict
--[[
	EconomyService
	Saldo de monedas del jugador, con libro mayor (ledger) en servidor.

	QUE ES Y QUE NO ES
	------------------
	Este servicio NO decide la economia: la APLICA. Las reglas (que es una
	cantidad valida, cuando hay saldo negativo, que compra esta
	idempotente) viven en `EconomyRules`, que es logica pura y se prueba sin
	motor. Aqui solo hay lo que necesita el motor:

	    - resolver el `Player` a su estado de economia
	    - pedirle el saldo a `ProfileService` (la fuente de verdad)
	    - publicar el saldo como atributo para la UI
	    - registrar los eventos para observabilidad

	POR QUE `ProfileService` Y NO ESTE SERVICIO
	--------------------------------------------
	El saldo NO vive aqui. Vive en el perfil, porque tiene que SOBREVIVIR
	al servidor. Si el saldo estuviera aqui, cerrar el servidor perderia
	las monedas del jugador, y con ellas el contrato de "lo que compras se
	guarda".

	REGLA DE AUTORIDAD
	------------------
	El cliente nunca dice cuanto recibe ni cuanto gasta. Como maximo dice
	"quiero comprar X", y el precio lo busca el servidor en el catalogo.
	Toda cantidad que entra aqui viene de `GameConfig` o de un catalogo.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local UTILS = SHARED:WaitForChild("Utils")

local EconomyRules = require(SHARED:WaitForChild("Libraries"):WaitForChild("EconomyRules"))
local Logger = require(UTILS:WaitForChild("Logger"))

local Service = {}

Service.IsInitialized = false

-- ProfileService inyectado por ServerMain.
Service._profileService = nil

-- Contadores para el informe de arranque y para el log.
Service._stats = {
	granted = 0,
	spent = 0,
	rejected = 0,
	duplicates = 0,
}

-- Maid recibido en Init.
local MaidRef = nil

--- Inyecta las dependencias del servicio.
---
--- Se llama ENTRE Init y Start (ver `ServerMain.wireDependencies`), que es
--- el unico momento en que cablear significa algo.
--- @param profileService any
function Service.SetDependencies(profileService: any)
	Service._profileService = profileService
end

--- Inicializacion del servicio. Idempotente.
--- @param maid any?
--- @return boolean success
function Service.Init(maid: any?): boolean
	MaidRef = maid
	Service._stats = { granted = 0, spent = 0, rejected = 0, duplicates = 0 }
	Service.IsInitialized = true
	return true
end

--- Arranque. Verifica que la economia tiene un perfil detras.
--- @param maid any?
--- @return boolean success
function Service.Start(maid: any?): boolean
	if not Service._profileService then
		-- Sin `ProfileService` NO hay economia. Se devuelve false para que
		-- el informe de arranque lo diga: es un modo degradado, no un
		-- "funciona pero sin saldo".
		Logger.Error("EconomyService: sin ProfileService; la economia no puede funcionar.")
		return false
	end

	-- El catalogo de items se revisa al arrancar. Si un item tuviera una
	-- moneda que `EconomyRules` no conoce, la tienda tendria un producto
	-- que no se puede cobrar nunca. Se comprueba aqui, no en produccion.
	local ItemCatalog = require(SHARED:WaitForChild("Config"):WaitForChild("ItemCatalog"))
	local unknown = {}

	for _, definition in ipairs(ItemCatalog.List({ includeUnavailable = true })) do
		local currency = definition.Currency
		if
			currency ~= ItemCatalog.Currency.Coins
			and currency ~= ItemCatalog.Currency.Gems
			and currency ~= ItemCatalog.Currency.Free
		then
			table.insert(unknown, tostring(definition.Id) .. "=" .. tostring(currency))
		end
	end

	if #unknown > 0 then
		Logger.Error(("EconomyService: items con moneda desconocida: %s"):format(table.concat(unknown, ", ")))
		return false
	end

	Logger.Info("EconomyService: economia de servidor lista.")
	return true
end

--- Limpieza del servicio.
--- @return boolean success
function Service.Destroy(): boolean
	Service.IsInitialized = false
	Service._profileService = nil
	MaidRef = nil
	return true
end

-- ---------------------------------------------------------------
-- API
-- ---------------------------------------------------------------
--
-- Todos estos metodos NECESITAN un perfil cargado. Sin perfil no hay
-- economia: se devuelve `false` con un motivo, nunca un saldo inventado.

--- Estado de economia de un jugador, o nil.
--- @param player Player?
--- @return any?
local function economyStateOf(player: Player?): any?
	if not player then
		return nil
	end

	if not Service._profileService then
		return nil
	end

	return Service._profileService.GetEconomyState(player)
end

--- Publica el saldo en los atributos que lee la UI.
---
--- Se hace en CADA cambio, no en un bucle. El HUD lee atributos, y
--- actualizar el saldo aqui es lo que evita que la UI muestre una cifra
-- vieja despues de comprar.
--- @param player Player
local function publishBalances(player: Player)
	local state = economyStateOf(player)
	if not state then
		return
	end

	for currency, balance in pairs(EconomyRules.GetBalances(state)) do
		player:SetAttribute(currency, balance)
	end
end

--- Saldo de una moneda. 0 si no hay perfil o la moneda no existe.
--- @param player Player?
--- @param currency string
--- @return number
function Service.GetBalance(player: Player?, currency: string): number
	return EconomyRules.GetBalance(economyStateOf(player), currency)
end

--- Copia de los saldos, para el HUD o para un log.
--- @param player Player?
--- @return { [string]: number }
function Service.GetBalances(player: Player?): { [string]: number }
	return EconomyRules.GetBalances(economyStateOf(player))
end

--- Indica si puede pagar esa cantidad.
---
--- ES UNA CONSULTA. No reserva nada: entre la pregunta y el cobro el
--- saldo puede haber cambiado, y por eso `SpendCurrency` vuelve a
--- comprobarlo.
--- @param player Player?
--- @param currency string
--- @param amount number
--- @return boolean
function Service.CanAfford(player: Player?, currency: string, amount: number): boolean
	return EconomyRules.CanAfford(economyStateOf(player), currency, amount)
end

--- Concede saldo (recompensa).
---
--- Es la unica via de ENTRADA. `requestId` es lo que impide cobrar dos
--- veces la misma recompensa: sin el, un listener duplicado pagaria dos.
--- @param player Player?
--- @param currency string
--- @param amount number
--- @param reason string
--- @param source string
--- @param metadata any?
--- @param requestId string?
--- @return boolean success
--- @return any? transaction
--- @return string? errorReason
function Service.GrantCurrency(
	player: Player?,
	currency: string,
	amount: number,
	reason: string,
	source: string,
	metadata: any?,
	requestId: string?
): (boolean, any?, string?)
	local state = economyStateOf(player)
	if not state then
		Service._stats.rejected += 1
		return false, nil, "el jugador no tiene perfil cargado"
	end

	local ok, transaction, err = EconomyRules.Grant(
		state,
		currency,
		amount,
		reason,
		source,
		metadata,
		requestId
	)

	if not ok then
		Service._stats.rejected += 1
		-- El motivo se registra SIEMPRE: un rechazo sin log es
		-- imposible de depurar desde fuera.
		Logger.Warn(("Economy: '%s' no pudo recibir %s: %s"):format(
			tostring(reason),
			tostring(currency),
			tostring(err)
		))
		return false, nil, err
	end

	if err and err:find("peticion repetida") then
		Service._stats.duplicates += 1
		-- Una peticion repetida NO es un problema: es el control
		-- funcionando. Se cuenta aparte para que un numero alto aqui
		-- signifique "muchos reintentos", no "muchos fallos".
		Logger.Debug(("Economy: peticion duplicada de '%s' (%s)"):format(tostring(reason), tostring(currency)))
	else
		Service._stats.granted += 1
		Logger.Info(("Economy: %s +%d %s (%s)"):format(
			tostring(reason),
			transaction.amount,
			currency,
			source
		))
	end

	publishBalances(player)
	return true, transaction, nil
end

--- Retira saldo (gasto o compra). Unica via de SALIDA.
---
--- NUNCA deja el saldo negativo, y con `requestId` nunca cobra dos veces
--- por la misma peticion.
--- @param player Player?
--- @param currency string
--- @param amount number
--- @param reason string
--- @param source string
--- @param metadata any?
--- @param requestId string?
--- @return boolean success
--- @return any? transaction
--- @return string? errorReason
function Service.SpendCurrency(
	player: Player?,
	currency: string,
	amount: number,
	reason: string,
	source: string,
	metadata: any?,
	requestId: string?
): (boolean, any?, string?)
	local state = economyStateOf(player)
	if not state then
		Service._stats.rejected += 1
		return false, nil, "el jugador no tiene perfil cargado"
	end

	local ok, transaction, err = EconomyRules.RemoveCurrency(
		state,
		currency,
		amount,
		reason,
		source,
		metadata,
		requestId
	)

	if not ok then
		Service._stats.rejected += 1
		Logger.Debug(("Economy: gasto rechazado de '%s': %s"):format(tostring(reason), tostring(err)))
		return false, nil, err
	end

	if err and err:find("peticion repetida") then
		Service._stats.duplicates += 1
	else
		Service._stats.spent += 1
		Logger.Info(("Economy: %s -%d %s (%s)"):format(
			tostring(reason),
			transaction.amount,
			currency,
			source
		))
	end

	publishBalances(player)
	return true, transaction, nil
end

--- Devuelve saldo (deshace un cobro).
---
--- Se llama desde `ShopRules` cuando la entrega del item falla DESPUES
--- de cobrar. Es una transaccion propia, con su propio `reason`, para que
--- el ledger distinga "devolucion" de "recompensa".
--- @param player Player?
--- @param currency string
--- @param amount number
--- @param reason string
--- @param source string
--- @param requestId string?
--- @return boolean success
--- @return string? errorReason
function Service.RefundCurrency(
	player: Player?,
	currency: string,
	amount: number,
	reason: string,
	source: string,
	requestId: string?
): (boolean, string?)
	local state = economyStateOf(player)
	if not state then
		return false, "el jugador no tiene perfil cargado"
	end

	local ok, _, err = EconomyRules.Refund(state, currency, amount, reason, source, requestId)

	if ok then
		Logger.Info(("Economy: devolucion +%d %s (%s)"):format(amount, currency, tostring(reason)))
		publishBalances(player)
	else
		Logger.Error(("Economy: NO se pudo devolver %d %s: %s"):format(amount, currency, tostring(err)))
	end

	return ok, err
end

--- Historial de transacciones, para el soporte y para el diagnostico.
--- @param player Player?
--- @param limit number?
--- @return { any }
function Service.GetTransactionHistory(player: Player?, limit: number?): { any }
	local state = economyStateOf(player)
	if not state then
		return {}
	end
	return EconomyRules.GetTransactionHistory(state, limit)
end

--- Anomalias del ledger de un jugador. Lista vacia = todo cuadra.
---
--- Se llama tras operaciones importantes (una compra grande, un fin de
--- ronda) para que un desvio aparezca en el log antes de que un jugador
--- lo note.
--- @param player Player?
--- @return { string }
function Service.AuditPlayer(player: Player?): { string }
	return EconomyRules.Audit(economyStateOf(player))
end

--- Resumen para el informe de arranque.
--- @return { [string]: number }
function Service.GetStats(): { [string]: number }
	return {
		granted = Service._stats.granted,
		spent = Service._stats.spent,
		rejected = Service._stats.rejected,
		duplicates = Service._stats.duplicates,
	}
end

return Service
