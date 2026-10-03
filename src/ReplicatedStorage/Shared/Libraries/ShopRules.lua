--!strict
--[[
	ShopRules
	La cadena de compra COMPLETA, como logica pura.

	POR QUE EXISTE
	--------------
	Una compra son siete pasos y el fallo aparece en el que se olvida uno:

	    1. el cliente pide "quiero comprar X"   (nunca un precio)
	    2. X existe en el catalogo?
	    3. el jugador tiene perfil?
	    4. el jugador ya lo tiene?               -> "ya lo tienes"
	    5. puede pagarlo?
	    6. SE COBRA y SE ENTREGA
	    7. se RESPONDE

	Los pasos 2-5 NO conceden nada. Solo el 6 modifica estado. Por eso este
	modulo separa `Validate` (que no cobra) de `Execute` (que cobra), y por
	eso el servicio que lo llama puede repetir la validacion sin coste.

	LA REGLA DE IDEMPOTENCIA
	------------------------
	Cada compra lleva un `requestId`. Si llega dos veces:

	    primera  -> EXECUTE, guarda el resultado
	    segunda  -> devuelve el MISMO resultado, sin cobrar

	Es imprescindible porque el fallo tipico no es un atacante: es el
	jugador que pierde la conexion justo despues de pulsar "comprar" y
	reintenta. Sin este control, paga dos veces y recibe un item.

	POR QUE NO SE USA `require` AQUI
	---------------------------------
	Igual que `RemoteSchema` e `InventoryRules`: en el interprete de pruebas
	`script` no existe, asi que las dependencias se INYECTAN.
]]

local ShopRules = {}
ShopRules.__index = ShopRules

--- Crea las reglas con sus dependencias.
--- @param deps { catalog: any, economy: any, inventory: any }
--- @return table
function ShopRules.new(deps: any): any
	assert(type(deps) == "table", "ShopRules.new requiere dependencias")
	assert(type(deps.catalog) == "table", "falta el catalogo")
	assert(type(deps.economy) == "table", "falta la economia")
	assert(type(deps.inventory) == "table", "falta el inventario")

	return setmetatable({
		catalog = deps.catalog,
		economy = deps.economy,
		inventory = deps.inventory,
		-- requestId -> recibo de la compra YA resuelta.
		--
		-- Este registro es OBLIGATORIO, no una optimizacion. Si no
		-- existiera, un reintento pasaria por `Validate` de nuevo y
		-- devolveria "ya lo tienes": el jugador veria un error tras haber
		-- comprado bien, y el cliente no podria distinguir "comprado" de
		-- "fallido". Peor: si la compra se pagara con dos monedas, el
		-- reintento con `already_owned` pasaria por un camino distinto al
		-- original y los dos recibos no coincidirian.
		--
		-- Vive en la INSTANCIA, no en el estado del jugador: es un registro
		-- de esta sesion de compra, no del perfil. Un perfil guardado no
		-- necesita guardarlo (cobrar dos veces el mismo objeto no tiene
		-- sentido entre sesiones).
		_purchases = {},
	}, ShopRules)
end

--- Resultado de una compra ya resuelta con este `requestId`, o nil.
--- @param requestId string
--- @return any?
function ShopRules:GetCompletedPurchase(requestId: string): any?
	if type(requestId) ~= "string" or requestId == "" then
		return nil
	end

	return self._purchases[requestId]
end

--- Motivos de rechazo. Texto estable: la UI decide que texto mostrar.
ShopRules.Rejection = {
	UnknownItem = "unknown_item",
	NotAvailable = "not_available",
	NoProfile = "no_profile",
	AlreadyOwned = "already_owned",
	InsufficientFunds = "insufficient_funds",
	InvalidRequest = "invalid_request",
	InvalidPrice = "invalid_price",
	InvalidCurrency = "invalid_currency",
	DuplicateRequest = "duplicate_request",
}

--- Compra CONCEDIDA.
ShopRules.Outcome = {
	Purchased = "purchased",
	AlreadyOwned = "already_owned",
	Rejected = "rejected",
}

--- Catalogo de la tienda, ya filtrado a lo que se puede COMPRAR.
---
--- El precio sale del catalogo del servidor. Un cliente que envie un
--- precio propio no tendria donde escribirlo: `Purchase` solo acepta el
--- `ItemId`, que es lo unico que puede legitimamente conocer el cliente.
--- @param options { category: string? }?
--- @return { any }
function ShopRules:GetCatalogForSale(options: any): { any }
	local resolved: { category: string? } = options or {}
	return self.catalog.List({
		category = resolved.category,
		includeUnavailable = false,
	})
end

--- Valida una compra SIN COBRAR NADA.
---
--- Existe separada de `Execute` por una razon concreta: la UI necesita
--- poder preguntar "puedo comprar esto?" (para mostrar el boton activo o
--- el precio en rojo) sin que esa pregunta tenga efecto. Si las dos cosas
--- estuvieran juntas, ese boton DESCONTARIA monedas cada vez que el
--- jugador pase el raton por encima.
--- @param itemId any
--- @param profileState any { economy: any, inventory: any }
--- @return boolean valid
--- @return string? rejectionCode
--- @return any? definition
function ShopRules:Validate(itemId: any, profileState: any): (boolean, string?, any?)
	if type(itemId) ~= "string" or itemId == "" then
		return false, ShopRules.Rejection.InvalidRequest, nil
	end

	if not self.catalog.Has(itemId) then
		return false, ShopRules.Rejection.UnknownItem, nil
	end

	local definition = self.catalog.Get(itemId)

	if definition.Available == false then
		return false, ShopRules.Rejection.NotAvailable, definition
	end

	if type(profileState) ~= "table" or type(profileState.economy) ~= "table"
		or type(profileState.inventory) ~= "table" then
		return false, ShopRules.Rejection.NoProfile, definition
	end

	-- El precio se valida COMO DATO del servidor, no como lo que dice el
	-- cliente. Un precio que no sea un entero positivo haria imposible
	-- incluso cobrarlo.
	local price = definition.Price
	if type(price) ~= "number" or price ~= price or price < 0 then
		return false, ShopRules.Rejection.InvalidPrice, definition
	end

	local currency = definition.Currency
	if currency ~= self.catalog.Currency.Coins and currency ~= self.catalog.Currency.Gems then
		return false, ShopRules.Rejection.InvalidCurrency, definition
	end

	-- Un item de precio 0 y apilable (un consumible gratis) se puede
	-- "comprar" todas las veces que se quiera. Para el resto, ya tenerlo
	-- significa que la compra no tiene sentido.
	if price > 0 and not definition.Stackable then
		if self.inventory:HasItem(profileState.inventory, itemId, 1) then
			return false, ShopRules.Rejection.AlreadyOwned, definition
		end
	end

	if not self.economy.CanAfford(profileState.economy, currency, price) then
		return false, ShopRules.Rejection.InsufficientFunds, definition
	end

	return true, nil, definition
end

--- Ejecuta una compra completa: valida, cobra y entrega.
---
--- ORDEN DE LAS OPERACIONES (importante)
--- -------------------------------------
--- Se COBRA primero y se ENTREGA despues, nunca al reves. Cobrar y que la
--- entrega falle deja al jugador sin saldo y sin item; entregar y que el
--- cobro falle deja al jugador con un item que no ha pagado. El primer
--- fallo se puede deshacer devolviendo las monedas; el segundo significo
--- regalar un item, y regalar un item si se puede arreglar (esta compra
--- con `requestId` propio es idempotente y el cobro se revierte).
---
--- Si la entrega falla DESPUES de cobrar, se devuelve el dinero con una
--- peticion propia (`:refund`). Es una transaccion mas, no una escritura
--- silenciosa: el ledger deja constancia del cobro y de la devolucion, y
--- eso es justo lo que permite distinguir un fallo de compra de un robo.
--- @param itemId string
--- @param profileState any { economy: any, inventory: any }
--- @param requestId string id unico de ESTA compra
--- @param source string
--- @return string outcome uno de ShopRules.Outcome
--- @return string? rejectionCode
--- @return any? receipt informacion para la UI
function ShopRules:Purchase(
	itemId: string,
	profileState: any,
	requestId: string,
	source: string
): (string, string?, any?)
	-- Idempotencia PRIMERO, antes de validar.
	--
	-- El orden es lo unico que importa aqui. Si se validara antes, un
	-- reintento veria que el jugador ya tiene el item y responderia
	-- "already_owned": el cliente mostraria un error tras una compra
	-- CORRECTA, y no habria forma de distinguir los dos casos. Devolviendo
	-- el recibo original, el reintento es invisible para el jugador y
	-- completamente gratis para el servidor.
	local previous = self:GetCompletedPurchase(requestId)
	if previous then
		return previous.outcome, previous.rejection, previous.receipt
	end

	local valid, rejection, definition = self:Validate(itemId, profileState)

	-- Todo resultado (comprado, ya_lo_tenia o rechazado) se REGISTRA.
	-- Solo se registra lo que se ha resuelto: volver a rechazar una peticion
	-- con el mismo `requestId` es correcto y no cobra nada, asi que repetir
	-- el rechazo no cuesta nada.
	if not valid then
		-- "Ya lo tienes" no es un fallo: es una compra que no hacia
		-- falta. Se responde como tal para que la UI no muestre un error
		-- rojo cuando el jugador pulsa "comprar" por costumbre.
		local outcome = if rejection == ShopRules.Rejection.AlreadyOwned
			then ShopRules.Outcome.AlreadyOwned
			else ShopRules.Outcome.Rejected

		self._purchases[requestId] = { outcome = outcome, rejection = rejection, receipt = nil }
		return outcome, rejection, definition
	end

	local price = definition.Price
	local currency = definition.Currency

	-- --- Paso 1: cobrar. ---------------------------------------------
	local charged, _, chargeError = self.economy.RemoveCurrency(
		profileState.economy,
		currency,
		price,
		"compra",
		source,
		{ itemId = itemId, requestId = requestId },
		requestId
	)

	if not charged then
		-- El `Validate` de antes dio el visto bueno, asi que este fallo es
		-- una CARRERA: el saldo cambio entre la validacion y el cobro (por
		-- ejemplo otra compra simultanea). Por eso se vuelve a mirar el
		-- saldo real en vez de asumir nada.
		--
		-- Se distingue el caso de "no le queda" del de saldo insuficiente
		-- por el motivo REAL, para que la UI pueda distinguir "tu saldo bajo"
		-- de "algo se rompio". Y si el motivo es otro, se avisa en vez de
		-- esconderse detras de un codigo de UI.
		local message = tostring(chargeError)
		if not message:find("insuficiente") then
			warn(("ShopRules: cobro rechazado por un motivo inesperado: %s"):format(message))
		end

		self._purchases[requestId] = {
			outcome = ShopRules.Outcome.Rejected,
			rejection = ShopRules.Rejection.InsufficientFunds,
			receipt = nil,
		}

		return ShopRules.Outcome.Rejected, ShopRules.Rejection.InsufficientFunds, definition
	end

	-- --- Paso 2: entregar. -------------------------------------------
	--
	-- Un bundle se EXPANDE: el jugador recibe sus piezas, no un "pack".
	if definition.Category == self.catalog.Category.Bundle then
		local _, granted, problems = self.inventory:ExpandBundle(
			profileState.inventory,
			itemId,
			source,
			requestId
		)

		if #granted == 0 then
			-- No se entrego NADA: se devuelve el dinero entero.
			self.economy.Refund(
				profileState.economy,
				currency,
				price,
				"compra_sin_entrega",
				source,
				(requestId .. ":refund")
			)

			return ShopRules.Outcome.Rejected, ShopRules.Rejection.InvalidRequest, definition
		end

		local receipt = {
			itemId = itemId,
			price = price,
			currency = currency,
			granted = granted,
			-- `problems` va en el recibo: el jugador recibio parte del
			-- bundle y le faltaron otras piezas. Ocultarlo seria una mentira:
			-- le diria que tiene el pack entero cuando no.
			problems = problems,
			requestId = requestId,
		}

		self._purchases[requestId] = {
			outcome = ShopRules.Outcome.Purchased,
			rejection = nil,
			receipt = receipt,
		}

		return ShopRules.Outcome.Purchased, nil, receipt
	end

	local delivered = self.inventory:AddItem(
		profileState.inventory,
		itemId,
		1,
		source,
		requestId
	)

	if not delivered then
		-- Cobrado y sin entrega: se devuelve el dinero. El item NO se
		-- entrega "aPartial": o se entrega entero o no se entrega.
		self.economy.Refund(
			profileState.economy,
			currency,
			price,
			"compra_sin_entrega",
			source,
			(requestId .. ":refund")
		)

		return ShopRules.Outcome.Rejected, ShopRules.Rejection.InvalidRequest, definition
	end

	local receipt = {
		itemId = itemId,
		price = price,
		currency = currency,
		granted = { itemId },
		problems = {},
		requestId = requestId,
	}

	self._purchases[requestId] = {
		outcome = ShopRules.Outcome.Purchased,
		rejection = nil,
		receipt = receipt,
	}

	return ShopRules.Outcome.Purchased, nil, receipt
end

return ShopRules