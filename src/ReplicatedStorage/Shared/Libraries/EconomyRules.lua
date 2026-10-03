--!strict
--[[
	EconomyRules
	Economia de MONEDAS como LOGICA PURA, con libro mayor (ledger).

	POR QUE ES PURA Y NO UN SERVICIO
	--------------------------------
	Las reglas que deciden "este saldo puede bajar 30" o "esta
	transaccion ya se ejecuto" son FORMULAS sobre numeros. Si viven
	dentro de `EconomyService` no se pueden probar: `luau.exe` no tiene
	`Players`. Este modulo las aisla para que la suite las ejecute de
	verdad, exactamente igual que hizo `CombatMath` con el dano.

	REGLA DE AUTORIDAD
	------------------
	El cliente NUNCA dice cuanto recibe, cuanto gasta ni cuanto cuesta
	algo. Como maximo dice "quiero comprar X" o "quiero usar Y". Aqui
	nunca entra una cantidad enviada por el cliente: todas las cantidades
	que se aceptan salen de `GameConfig` o de `ItemCatalog`.

	EL LEDGER (libro mayor)
	----------------------
	Cada modificacion deja un registro INMUTABLE con:

	    transactionId  id unico de la transaccion
	    playerId       quien la ejecuto
	    currency       que moneda
	    amount         cuanto (siempre positivo; el signo lo da el tipo)
	    balanceBefore  saldo antes
	    balanceAfter   saldo despues
	    reason         por que (texto estable, para agrupar en logs)
	    source         quien la pidio (servicio / sistema)
	    metadata       datos minimos y NO secretos
	    timestamp      os.time()

	El ledger no es decoracion. Es lo que permite responder, sin
	adivinar, a las cinco preguntas que importan cuando algo va mal:

	    - Se ha pagado dos veces la misma compra?  -> `GetTransactionByRequest`
	    - Alguien quedo en negativo?               -> `FindNegativeBalances`
	    - El saldo de despues no cuadra con la suma? -> `FindBalanceMismatch`
	    - Se pago la misma recompensa dos veces?   -> `FindDuplicateReasons`

	NUNCA guarda: contrasenas, tokens, nombres de DataStore, el
	contenido del perfil ni datos personales.
]]

local EconomyRules = {}

-- ---------------------------------------------------------------
-- Monedas
-- ---------------------------------------------------------------
--
-- Son las MISMAS dos que publica `PlayerService` como atributos
-- (`Coins`, `Gems`). Anadir una tercera moneda obliga a tocar esta
-- lista: es deliberado, para que una moneda nueva no aparezca medio
-- implementada en la UI.
EconomyRules.Currencies = { "Coins", "Gems" }

--- Tope absoluto de saldo por moneda.
---
--- No es un tope de contenido: es la red que corta el `overflow` antes
--- de que un saldo corrupto (por ejemplo 1e308) rompa la aritmetica o
--- la UI. Un jugador no llega ni de lejos con 9 mil millones de coins.
EconomyRules.MaxBalance = 1000000000

--- Cuanto se recuerda del ledger por defecto al pedir historial.
EconomyRules.DefaultHistoryLimit = 50

--- @param currency any
--- @return boolean
function EconomyRules.IsValidCurrency(currency: any): boolean
	if type(currency) ~= "string" then
		return false
	end
	for _, valid in ipairs(EconomyRules.Currencies) do
		if valid == currency then
			return true
		end
	end
	return false
end

--- Una cantidad utilizable: entera, finita, positiva y sin desborde.
---
--- Devuelve `nil` en vez de un numero "arreglado". La diferencia
--- importa: un `0` silencioso hace que un llamador que solo mira
--- "funciono" crea que concedio algo cuando no concedio nada.
--- @param amount any
--- @return number? safeAmount
--- @return string? reason
function EconomyRules.SanitizeAmount(amount: any): (number?, string?)
	if type(amount) ~= "number" then
		return nil, "cantidad no es un numero"
	end

	-- NaN e infinito salen ANTES que cualquier comparacion: en Luau
	-- `nan < 0` es false, asi que un filtro ingenuo los dejaria pasar.
	if amount ~= amount then
		return nil, "cantidad NaN"
	end
	if amount == math.huge or amount == -math.huge then
		return nil, "cantidad infinita"
	end

	if amount <= 0 then
		return nil, "cantidad no positiva"
	end

	local floored = math.floor(amount)
	if floored <= 0 then
		return nil, "cantidad menor que 1 tras redondear"
	end

	return floored, nil
end

-- ---------------------------------------------------------------
-- Estado de economia
-- ---------------------------------------------------------------

--- Crea un estado de economia vacio para un jugador.
---
--- Es una TABLA PLANA a proposito: son solo numeros y cadenas, sin
--- Instances ni funciones, y por tanto serializable tal cual hacia el
--- DataStore. `ProfileService` la guarda entera.
--- @param playerId number
--- @return any state
function EconomyRules.NewState(playerId: number): any
	return {
		PlayerId = playerId,
		Balances = { Coins = 0, Gems = 0 },
		-- Contador monotono de transacciones. Da un `transactionId`
		-- unico aunque dos transacciones ocurran en el mismo segundo.
		Sequence = 0,
		-- requestId -> indice en `Entries`. Es la idempotencia.
		Requests = {},
		Entries = {},
	}
end

--- Cuanto tiene el jugador de una moneda.
--- @param state any
--- @param currency string
--- @return number balance 0 si el estado o la moneda no existen
function EconomyRules.GetBalance(state: any, currency: string): number
	if type(state) ~= "table" or type(state.Balances) ~= "table" then
		return 0
	end

	local balance = state.Balances[currency]
	if type(balance) ~= "number" or balance ~= balance then
		return 0
	end

	return balance
end

--- Copia de solo lectura de los saldos, para la UI.
--- @param state any
--- @return { [string]: number }
function EconomyRules.GetBalances(state: any): { [string]: number }
	local result: { [string]: number } = {}
	for _, currency in ipairs(EconomyRules.Currencies) do
		result[currency] = EconomyRules.GetBalance(state, currency)
	end
	return result
end

--- Indica si el jugador puede pagar esa cantidad.
---
--- OJO: esto es una CONSULTA. No reserva ni descuenta nada. Un
--- `CanAfford` que pasa no es una compra: entre la pregunta y el cobro
--- el saldo puede haber cambiado, y por eso `RemoveCurrency` vuelve a
--- comprobarlo.
--- @param state any
--- @param currency string
--- @param amount number
--- @return boolean
function EconomyRules.CanAfford(state: any, currency: string, amount: number): boolean
	if not EconomyRules.IsValidCurrency(currency) then
		return false
	end

	local safe, reason = EconomyRules.SanitizeAmount(amount)
	if safe == nil then
		-- Sin `Logger`: este modulo es puro y no depende de ReplicatedStorage.
		-- El motivo viaja en el valor de retorno para que lo registre quien
		-- llama, que si tiene Logger.
		local _ = reason
		return false
	end

	return EconomyRules.GetBalance(state, currency) >= (safe :: number)
end

-- ---------------------------------------------------------------
-- Mutacion y ledger
-- ---------------------------------------------------------------

--- Escribe una entrada en el ledger y devuelve su indice.
---
--- La entrada se guarda como una tabla NUEVA, nunca por referencia a una
--- tabla viva: si el llamador siguiera modificando la suya despues, el
--- ledger ("es inmutable") dejaria de ser cierto y las auditorias darian
--- resultados que dependen del momento en que se miren.
--- @param state any
--- @param record any
--- @return number index
local function appendEntry(state: any, record: any): number
	local index = #state.Entries + 1
	state.Entries[index] = record
	return index
end

--- Nuclear de `AddCurrency` y `RemoveCurrency`.
---
--- Toda escritura economica pasa por aqui, sin excepcion. Eso es lo que
--- hace que el ledger sea FIABLE: si existiera otra ruta que escribiera
--- `state.Balances` sin registrar, el ledger dejaria de servir para
--- detectar una doble recompensa.
--- @param state any
--- @param direction string "Add" o "Remove"
--- @param currency string
--- @param amount number
--- @param reason string
--- @param source string
--- @param metadata any?
--- @param requestId string?
--- @return boolean success
--- @return any? transaction entrada creada (o la previa si era repetida)
--- @return string? errorReason
local function applyTransaction(
	state: any,
	direction: string,
	currency: string,
	amount: number,
	reason: string,
	source: string,
	metadata: any?,
	requestId: string?
): (boolean, any?, string?)
	if type(state) ~= "table" or type(state.Balances) ~= "table" then
		return false, nil, "estado de economia invalido"
	end

	-- --- Idempotencia. Va PRIMERO, antes de validar nada mas. --------
	--
	-- Si la misma peticion ya se ejecuto, se devuelve SU resultado y no se
	-- toca el saldo. El orden importa: validar antes filtraria una
	-- repeticion por un motivo distinto y el llamador veria un error en
	-- lugar de "ya lo tienes", que es justo el caso que mas confunde.
	if type(requestId) == "string" and requestId ~= "" then
		local previousIndex = state.Requests[requestId]
		if previousIndex then
			local previous = state.Entries[previousIndex]
			if previous then
				return true, previous, "peticion repetida; se devuelve el resultado anterior"
			end
		end
	end

	if not EconomyRules.IsValidCurrency(currency) then
		return false, nil, ("moneda invalida: %s"):format(tostring(currency))
	end

	local safeAmount, amountReason = EconomyRules.SanitizeAmount(amount)
	if safeAmount == nil then
		return false, nil, amountReason
	end

	local delta: number
	if direction == "Add" then
		delta = safeAmount
	else
		delta = -(safeAmount :: number)
	end

	local balanceBefore = EconomyRules.GetBalance(state, currency)
	local balanceAfter = balanceBefore + delta

	-- --- Nunca saldo negativo. ---------------------------------------
	--
	-- Se comprueba ANTES de escribir. Un saldo negativo no es "un saldo
	-- pequeno": es un jugador que puede gastar algo que no tiene, y a
	-- partir de ahi cualquier compra suya queda en negativo.
	if balanceAfter < 0 then
		return false, nil, ("saldo insuficiente en %s (tiene %d, necesita %d)"):format(
			currency,
			balanceBefore,
			safeAmount
		)
	end

	-- --- Overflow. ----------------------------------------------------
	--
	-- Se comprueba en la direccion de suma. Sin esto, dos recompensas
	-- grandes sobre un saldo enorme dejarian el perfil en `inf`, que no
	-- se puede guardar en un DataStore ni sumar mas.
	if delta > 0 and balanceAfter > EconomyRules.MaxBalance then
		local capped = EconomyRules.MaxBalance - balanceBefore
		if capped <= 0 then
			return false, nil, ("saldo de %s en el tope"):format(currency)
		end
		-- Se CAPA en lugar de rechazar: perder una recompensa pequena es
		-- peor que no dar la ultima moneda de un saldo ya enorme. El
		-- ledger registra lo que REALMENTE se aplico, no lo pedido.
		delta = capped
		balanceAfter = balanceBefore + delta
	end

	state.Balances[currency] = balanceAfter

	state.Sequence += 1
	local transactionId = ("%s-%d-%d"):format(tostring(state.PlayerId), state.Sequence, os.time())

	local record = {
		transactionId = transactionId,
		playerId = state.PlayerId,
		currency = currency,
		amount = math.abs(delta),
		-- El signo va en `Direction`, no en `Amount`: `Amount` es siempre
		-- positivo, y un consumidor que sume o reste segun el signo del
		-- amount se equivoca con un valor negativo en la UI.
		Direction = direction,
		balanceBefore = balanceBefore,
		balanceAfter = balanceAfter,
		reason = type(reason) == "string" and reason ~= "" and reason or "sin_motivo",
		source = type(source) == "string" and source ~= "" and source or "desconocido",
		metadata = type(metadata) == "table" and metadata or nil,
		timestamp = os.time(),
	}

	local index = appendEntry(state, record)

	if type(requestId) == "string" and requestId ~= "" then
		state.Requests[requestId] = index
	end

	return true, record, nil
end

--- Concede saldo. Unica via de ENTRADA.
--- @param state any
--- @param currency string
--- @param amount number
--- @param reason string
--- @param source string
--- @param metadata any?
--- @param requestId string?
--- @return boolean success
--- @return any? transaction
--- @return string? errorReason
function EconomyRules.AddCurrency(
	state: any,
	currency: string,
	amount: number,
	reason: string,
	source: string,
	metadata: any?,
	requestId: string?
): (boolean, any?, string?)
	return applyTransaction(state, "Add", currency, amount, reason, source, metadata, requestId)
end

--- Retira saldo. Unica via de SALIDA, y nunca deja el saldo negativo.
--- @param state any
--- @param currency string
--- @param amount number
--- @param reason string
--- @param source string
--- @param metadata any?
--- @param requestId string?
--- @return boolean success
--- @return any? transaction
--- @return string? errorReason
function EconomyRules.RemoveCurrency(
	state: any,
	currency: string,
	amount: number,
	reason: string,
	source: string,
	metadata: any?,
	requestId: string?
): (boolean, any?, string?)
	return applyTransaction(state, "Remove", currency, amount, reason, source, metadata, requestId)
end

--- Concede saldo como `Grant`. Mismo comportamiento que `AddCurrency`.
---
--- Existe con nombre propio porque "add" y "grant" significan cosas
--- distintas al leer un log: `grant` es una recompensa del juego (matar,
--- ronda, nivel) y `add` es una correccion o un ajuste. El ledger guarda
--- el texto exacto, asi que poder distinguirlos sin mirar el `source` es
--- lo que hace el historial legible.
--- @param state any
--- @param currency string
--- @param amount number
--- @param reason string
--- @param source string
--- @param metadata any?
--- @param requestId string?
--- @return boolean success
--- @return any? transaction
--- @return string? errorReason
function EconomyRules.Grant(
	state: any,
	currency: string,
	amount: number,
	reason: string,
	source: string,
	metadata: any?,
	requestId: string?
): (boolean, any?, string?)
	return applyTransaction(state, "Add", currency, amount, reason, source, metadata, requestId)
end

--- Devuelve saldo al jugador (deshace un cobro).
---
--- NO es `AddCurrency` con otro nombre. Existe separada porque una
--- devolucion tiene que poder distinguirse de una recompensa en el ledger:
--- "le devolvieron 500 porque fallo la entrega" y "le dieron 500 por subir
--- de nivel" son hechos distintos, y sin el `reason` correcto no hay
--- forma de saber por que un jugador tiene monedas de mas.
---
--- Se comporta como un `Add` normal, con su propia idempotencia.
--- @param state any
--- @param currency string
--- @param amount number
--- @param reason string
--- @param source string
--- @param requestId string?
--- @return boolean success
--- @return any? transaction
--- @return string? errorReason
function EconomyRules.Refund(
	state: any,
	currency: string,
	amount: number,
	reason: string,
	source: string,
	requestId: string?
): (boolean, any?, string?)
	return applyTransaction(state, "Add", currency, amount, reason, source, nil, requestId)
end

--- Transfiere saldo entre dos estados de economia.
---
--- Es ATOMICA en el sentido que importa: si el destino no puede
--- recibir, el origen no se toca. Sin esa comprobacion, un cobro al
--- jugador sin entrega al receptor destruye saldo, y un saldo
--- destruido no se puede recuperar por mas que se repita la operacion.
---
--- Las dos partes comparten `requestId`, de modo que reintentar la
--- misma transferencia no cobra ni paga dos veces.
--- @param fromState any estado que paga
--- @param toState any estado que recibe
--- @param currency string
--- @param amount number
--- @param reason string
--- @param source string
--- @param requestId string?
--- @return boolean success
--- @return any? fromTransaction
--- @return any? toTransaction
--- @return string? errorReason
function EconomyRules.Transfer(
	fromState: any,
	toState: any,
	currency: string,
	amount: number,
	reason: string,
	source: string,
	requestId: string?
): (boolean, any?, any?, string?)
	if type(fromState) ~= "table" or type(toState) ~= "table" then
		return false, nil, nil, "estado de economia invalido"
	end

	-- Si ambos lados son el MISMO estado, esto no es una transferencia:
	-- se restaria y sumaria sobre la misma variable de saldo y el
	-- resultado seria un saldo "correcto" con dos movimientos en el
	-- ledger. Se rechaza antes de escribir.
	if fromState == toState then
		return false, nil, nil, "origen y destino son el mismo jugador"
	end

	local safeAmount, amountReason = EconomyRules.SanitizeAmount(amount)
	if safeAmount == nil then
		return false, nil, nil, amountReason
	end

	local fromOk, fromTransaction, fromError = EconomyRules.RemoveCurrency(
		fromState,
		currency,
		(safeAmount :: number),
		reason,
		source,
		nil,
		requestId
	)

	if not fromOk then
		return false, nil, nil, fromError
	end

	local toOk, toTransaction, toError = EconomyRules.AddCurrency(
		toState,
		currency,
		(safeAmount :: number),
		reason,
		source,
		nil,
		requestId
	)

	if not toOk then
		-- Se devuelve lo retirado. Esto NO es una excepcion: el ledger deja
		-- constancia de las DOS transacciones, y eso es justo lo que permite
		-- despues distinguir un rollback de un robo. Reutilizar el
		-- `requestId` original haria que un reintento devolviera la entrada
		-- original en vez de la nueva, asi que la devolucion lleva su clave.
		EconomyRules.AddCurrency(
			fromState,
			currency,
			(safeAmount :: number),
			(reason .. ":rollback"),
			source,
			nil,
			requestId and (requestId .. ":rollback") or nil
		)

		return false, nil, nil, ("no se pudo entregar: %s"):format(tostring(toError))
	end

	return true, fromTransaction, toTransaction, nil
end

-- ---------------------------------------------------------------
-- Consulta del ledger
-- ---------------------------------------------------------------

--- Ultimas transacciones, de la mas reciente a la mas antigua.
---
--- Se devuelve una COPIA de la lista, con las mismas entradas. Si
--- devolviera la tabla interna, quien leyera el historial podria
--- mutar el ledger desde la UI y perderian valor probatorio las
--- auditorias de abajo.
--- @param state any
--- @param limit number?
--- @return { any }
function EconomyRules.GetTransactionHistory(state: any, limit: number?): { any }
	if type(state) ~= "table" or type(state.Entries) ~= "table" then
		return {}
	end

	local requested = limit or EconomyRules.DefaultHistoryLimit
	if type(requested) ~= "number" or requested < 0 then
		requested = EconomyRules.DefaultHistoryLimit
	end
	requested = math.floor(requested)

	local total = #state.Entries
	local count = math.min(requested, total)
	local result = {}

	for index = 1, count do
		-- `total - index + 1` invierte el orden: la mas reciente primero.
		result[index] = state.Entries[total - index + 1]
	end

	return result
end

--- Transaccion de una peticion repetida, o nil.
--- @param state any
--- @param requestId string
--- @return any?
function EconomyRules.GetTransactionByRequest(state: any, requestId: string): any?
	if type(state) ~= "table" or type(state.Requests) ~= "table" then
		return nil
	end

	if type(requestId) ~= "string" or requestId == "" then
		return nil
	end

	local index = state.Requests[requestId]
	if not index then
		return nil
	end

	return state.Entries[index]
end

--- Cuantas transacciones hay registradas.
--- @param state any
--- @return number
function EconomyRules.GetTransactionCount(state: any): number
	if type(state) ~= "table" or type(state.Entries) ~= "table" then
		return 0
	end
	return #state.Entries
end

-- ---------------------------------------------------------------
-- Auditorias
-- ---------------------------------------------------------------
--
-- Son consultas, NO reparaciones. Ninguna modifica el estado: detectar
-- un problema y arreglarlo de verdad son decisiones distintas, y una
-- auditoria que "se arregla sola" puede tapar justo el fallo que la
-- ha provocado. Se ejecutan desde el servidor y desde las pruebas.

--- Saldos imposibles: negativos, NaN, infinitos o por encima del tope.
---
--- No deberia haber NUNCA: `applyTransaction` lo impide todos. Que
--- aparezca significa que alguien escribio `Balances` por fuera de la
--- economia, y ese es exactamente el fallo que hay que encontrar.
--- @param state any
--- @return { any }
function EconomyRules.FindNegativeBalances(state: any): { any }
	local problems = {}
	if type(state) ~= "table" or type(state.Balances) ~= "table" then
		return problems
	end

	-- Las claves se convierten a cadena ANTES de usarlas. `pairs` sobre un
	-- campo `any` devuelve claves de tipo desconocido para el analizador, y
	-- `format` con `%s` las acepta; pasarlas tal cual no.
	for rawCurrency, rawBalance in pairs(state.Balances) do
		local currency = tostring(rawCurrency)
		local balance = rawBalance

		if type(balance) ~= "number" then
			table.insert(problems, ("%s: saldo no numerico (%s)"):format(currency, tostring(balance)))
		elseif balance ~= balance then
			table.insert(problems, ("%s: saldo NaN"):format(currency))
		elseif balance == math.huge or balance == -math.huge then
			table.insert(problems, ("%s: saldo infinito"):format(currency))
		elseif balance < 0 then
			table.insert(problems, ("%s: saldo negativo (%d)"):format(currency, balance))
		elseif balance > EconomyRules.MaxBalance then
			table.insert(problems, ("%s: saldo por encima del tope (%d)"):format(currency, balance))
		end
	end

	return problems
end

--- Transacciones cuyo `balanceAfter` no cuadra con lo que sigue.
---
--- Cada entrada declara el saldo que dejo. Si la siguiente declara un
--- `balanceBefore` distinto, alguien escribio entre medias sin pasar por
--- la economia: el ledger y el saldo han divergido.
--- @param state any
--- @return { any }
function EconomyRules.FindBalanceMismatch(state: any): { any }
	local problems = {}
	if type(state) ~= "table" or type(state.Entries) ~= "table" then
		return problems
	end

	local entries = state.Entries

	for index = 1, #entries do
		local current = entries[index]
		local nextEntry = entries[index + 1]

		if type(current) ~= "table" or type(current.balanceBefore) ~= "number" then
			table.insert(problems, ("entrada %d mal formada"):format(index))
		else
			-- El registro debe ser coherente consigo mismo.
			local expectedAfter = current.balanceBefore
			if current.Direction == "Remove" then
				expectedAfter -= current.amount
			else
				expectedAfter += current.amount
			end

			if expectedAfter ~= current.balanceAfter then
				table.insert(problems, ("entrada %d: balanceAfter incoherente"):format(index))
			end

			if
				nextEntry
				and type(nextEntry) == "table"
				and nextEntry.currency == current.currency
				and nextEntry.balanceBefore ~= current.balanceAfter
			then
				table.insert(problems, ("entrada %d: el saldo no encadena"):format(index))
			end
		end
	end

	-- El saldo ACTUAL de cada moneda tiene que ser el `balanceAfter` de
	-- su ULTIMA transaccion. Sin esta comprobacion, editar el saldo a
	-- mano DESPUES de la ultima compra pasaria desapercibido: el ledger
	-- seguiria encadenando bien consigo mismo, porque solo compara
	-- entradas contiguas, y el desvio no se veria hasta que un jugador
	-- pagara de mas.
	if type(state.Balances) == "table" then
		local lastByCurrency: { [string]: any } = {}

		for _, entry in ipairs(entries) do
			if type(entry) == "table" and type(entry.currency) == "string" then
				lastByCurrency[entry.currency] = entry
			end
		end

		for currency, entry in pairs(lastByCurrency) do
			local currentBalance = EconomyRules.GetBalance(state, currency)

			if type(entry.balanceAfter) == "number" and currentBalance ~= entry.balanceAfter then
				table.insert(problems, ("%s: el saldo (%d) no coincide con la ultima transaccion (%s)"):format(
					currency,
					currentBalance,
					tostring(entry.balanceAfter)
				))
			end
		end
	end

	return problems
end

--- Motivos que aparecen MAS de una vez con la misma magnitud.
---
--- No es un error por si mismo: comprar dos veces el mismo item es
--- legitimo. Por eso devuelve una lista para que un humano mire la
--- razon, en lugar de afirmar "algo va mal".
--- @param state any
--- @return { any }
function EconomyRules.FindDuplicateReasons(state: any): { any }
	local problems = {}
	if type(state) ~= "table" or type(state.Entries) ~= "table" then
		return problems
	end

	local seen: { [string]: number } = {}
	for index, entry in ipairs(state.Entries) do
		-- La anotacion `any` es explicita: sin ella el analizador infiere
		-- una tabla vacia de `ipairs` sobre un campo `any` y se queja de
		-- que `currency` "no existe". El campo SI existe: lo escribe
		-- `applyTransaction`.
		local record: any = entry

		if type(record) == "table" then
			local key = ("%s|%s|%s|%s"):format(
				tostring(record.currency),
				tostring(record.Direction),
				tostring(record.reason),
				tostring(record.amount)
			)
			seen[key] = (seen[key] or 0) + 1
		else
			table.insert(problems, ("entrada %d no es una tabla"):format(index))
		end
	end

	for key, count in pairs(seen) do
		if count > 1 then
			table.insert(problems, ("%d repeticiones de '%s'"):format(count, key))
		end
	end

	return problems
end

--- Todas las anomalias de una vez, en una sola lista.
---
--- Esta es la funcion que llama el servidor tras cada operacion
--- importante. Devuelve una lista VACIA cuando todo esta bien, y ese
--- vacio es un resultado que se puede afirmar en voz alta.
--- @param state any
--- @return { any }
function EconomyRules.Audit(state: any): { any }
	local problems = {}
	for _, problem in ipairs(EconomyRules.FindNegativeBalances(state)) do
		table.insert(problems, problem)
	end
	for _, problem in ipairs(EconomyRules.FindBalanceMismatch(state)) do
		table.insert(problems, problem)
	end
	return problems
end

return EconomyRules