--!strict
--[[
	InventoryRules
	Inventario como LOGICA PURA, con propiedad REAL en servidor.

	POR QUE ES PURA
	---------------
	Las reglas "este item existe", "el jugador lo tiene", "se puede
	equipar en esta ranura" son FORMULAS sobre tablas. Si viven dentro de
	`InventoryService` no se pueden probar con `luau.exe`. Este modulo las
	aisla, igual que hizo `CombatMath` con el dano.

	LA REGLA CENTRAL DEL INVENTARIO
	------------------------------
	El cliente NUNCA declara lo que tiene. Dice:

	    "quiero usar el item X"

	y el servidor responde:

	    1. X existe en el catalogo?          -> si no, no hay nada
	    2. el jugador lo posee?              -> si no, no hay nada
	    3. se puede usar ahora?              -> si no, no hay nada
	    4. se EJECUTA                        -> solo aqui
	    5. se ACTUALIZA el inventario         -> solo aqui
	    6. se RESPONDE con el resultado      -> solo aqui

	Los pasos 1-3 son validaciones y NO conceden nada. El unico que
	modifica el estado es el 4-5. Confundir esos dos pasos es lo que
	permite que un cliente se invente un item.

	ESTADO (`Items`)
	----------------
	Se guarda como `Items[itemId] = { Quantity = n }`. Es una tabla PLANA
	de numeros: sin Instances, sin funciones, serializable tal cual hacia
	el DataStore. La definicion (nombre, precio, si es equiparable) NO se
	duplica aqui: se consulta en `ItemCatalog`. Duplicarla haria que
	cambiar el nombre de un item dejara de actualizar la UI.
]]

-- `ItemCatalog` NO se requiere aqui a proposito.
--
-- En Roblox, `require` necesita una Instance y se escribiria
-- `require(script.Parent.Parent.Config.ItemCatalog)`. En el interprete de
-- pruebas (`luau.exe`) `script` NO existe, asi que esa misma linea deja
-- el modulo sin cargar y la suite entera falla. No hay una forma que
-- funcione en los dos entornos a la vez.
--
-- Por eso, exactamente igual que hace `RemoteSchema` con
-- `GameConstants.RemoteAction`, el catalogo se INYECTA desde el
-- consumidor:
--
--     local Inventory = InventoryRules.new(ItemCatalog)
--     local ok = Inventory.AddItem(state, "Cure_Potion", 1, "shop")
--
-- Ventaja adicional: el modulo queda como logica pura, sin dependencias,
-- y por tanto es 100% testeable.
local InventoryRules = {}
InventoryRules.__index = InventoryRules

--- Ranuras libres de una sesion.
---
--- Son una propiedad del JUGADOR (que lleva equipado), no del item, asi
--- que viven aqui y no en el catalogo. Anadir una ranura es un cambio de
--- contenido, no de codigo.
InventoryRules.Slots = { "Head", "Body", "Back", "Trail" }

--- Crea un conjunto de reglas con su catalogo.
--- @param catalog any modulo `ItemCatalog`
--- @return table
function InventoryRules.new(catalog: any)
	assert(type(catalog) == "table", "InventoryRules.new requiere un catalogo")
	assert(type(catalog.Get) == "function", "el catalogo debe exponer Get()")

	return setmetatable({ catalog = catalog }, InventoryRules)
end

--- Crea un inventario vacio.
--- @param playerId number
--- @return any state
function InventoryRules.NewState(playerId: number): any
	return {
		PlayerId = playerId,
		-- itemId -> { Quantity = n }
		Items = {},
		-- ranura -> itemId
		Equipped = {},
		-- requestId -> indice en `Entries`
		Requests = {},
		Entries = {},
		Sequence = 0,
	}
end

-- ---------------------------------------------------------------
-- Consultas (NO conceden nada)
-- ---------------------------------------------------------------

--- Cuantas unidades de un item tiene el jugador.
--- @param state any
--- @param itemId string
--- @return number quantity
function InventoryRules:GetQuantity(state: any, itemId: string): number
	if type(state) ~= "table" or type(state.Items) ~= "table" then
		return 0
	end

	local entry = state.Items[itemId]
	if type(entry) ~= "table" then
		return 0
	end

	local quantity = entry.Quantity
	if type(quantity) ~= "number" or quantity ~= quantity then
		return 0
	end

	return quantity
end

--- Indica si el jugador posee AL MENOS una unidad.
---
--- Acepta `minimum` para preguntas del tipo "tengo al menos 3?".
--- @param state any
--- @param itemId string
--- @param minimum number?
--- @return boolean
function InventoryRules:HasItem(state: any, itemId: string, minimum: number?): boolean
	local required = minimum or 1

	if type(required) ~= "number" or required < 1 then
		return false
	end

	return self:GetQuantity(state, itemId) >= required
end

--- Copia del inventario lista para la UI: id -> cantidad.
---
--- Se devuelven COPIAS. Devolver los registros internos significaria
--- que un `table.sort` de la UI reordenara el inventario del jugador.
--- @param state any
--- @return { [string]: number }
function InventoryRules:GetItems(state: any): { [string]: number }
	local result: { [string]: number } = {}
	if type(state) ~= "table" or type(state.Items) ~= "table" then
		return result
	end

	-- Las claves se normalizan a cadena antes de indexar el resultado. `pairs`
	-- sobre un campo `any` devuelve claves de tipo desconocido para el
	-- analizador; convertirlas aqui hace que el contrato de la funcion
	-- (`[string]: number`) sea cierto de verdad y no solo de intentions.
	for rawItemId, rawEntry in pairs(state.Items) do
		local entry: any = rawEntry

		if type(entry) == "table" and type(entry.Quantity) == "number" and entry.Quantity > 0 then
			result[tostring(rawItemId)] = entry.Quantity
		end
	end

	return result
end

--- Que hay equipado ahora en cada ranura.
--- @param state any
--- @return { [string]: string }
function InventoryRules:GetEquipped(state: any): { [string]: string }
	local result: { [string]: string } = {}
	if type(state) ~= "table" or type(state.Equipped) ~= "table" then
		return result
	end

	for rawSlot, rawItemId in pairs(state.Equipped) do
		if type(rawItemId) == "string" then
			result[tostring(rawSlot)] = rawItemId
		end
	end

	return result
end

--- Cuantos items DISTINTOS tiene. Solo informativo, para la UI.
--- @param state any
--- @return number
function InventoryRules:GetUniqueCount(state: any): number
	local total = 0
	for _ in pairs(self:GetItems(state)) do
		total += 1
	end
	return total
end

-- ---------------------------------------------------------------
-- Mutacion (AQUI si se modifica el estado)
-- ---------------------------------------------------------------

--- Una cantidad utilizable: entera, finita y positiva.
--- @param amount any
--- @return number? safeAmount
--- @return string? reason
local function sanitizeQuantity(amount: any): (number?, string?)
	if type(amount) ~= "number" then
		return nil, "cantidad no es un numero"
	end
	if amount ~= amount then
		return nil, "cantidad NaN"
	end
	if amount == math.huge or amount == -math.huge then
		return nil, "cantidad infinita"
	end
	if amount <= 0 then
		return nil, "cantidad no positiva"
	end

	return math.floor(amount), nil
end

--- Registra un movimiento en el historial del inventario.
--- @param state any
--- @param record any
--- @return number index
local function appendEntry(state: any, record: any): number
	local index = #state.Entries + 1
	state.Entries[index] = record
	return index
end

--- Anade unidades de un item al inventario del jugador.
---
--- `UnlockItem` es `AddItem` con cantidad 1, asi que no hay dos nociones
--- ("desbloqueado" y "en inventario") sino UNA sola: tener 1 unidad. Dos
--- nociones que siempre coinciden son dos fuentes de verdad, y en el
--- momento en que dejan de coincidir el jugador tiene un item que la UI
--- no muestra y el servidor no puede quitar.
--- @param state any
--- @param itemId string
--- @param amount number
--- @param source string quien lo pidio (para el historial)
--- @param requestId string? para idempotencia
--- @return boolean success
--- @return any? entry
--- @return string? errorReason
function InventoryRules:AddItem(
	state: any,
	itemId: string,
	amount: number,
	source: string,
	requestId: string?
): (boolean, any?, string?)
	if type(state) ~= "table" or type(state.Items) ~= "table" then
		return false, nil, "estado de inventario invalido"
	end

	-- Idempotencia antes de validar: una peticion repetida devuelve SU
	-- resultado en lugar de fallar por un motivo distinto.
	if type(requestId) == "string" and requestId ~= "" then
		local previousIndex = state.Requests[requestId]
		if previousIndex then
			local previous = state.Entries[previousIndex]
			if previous then
				return true, previous, "peticion repetida; se devuelve el resultado anterior"
			end
		end
	end

	-- El id tiene que existir en el catalogo. Sin esta comprobacion se
	-- podrian meter en el inventario ids inventados, y al guardar el
	-- perfil el jugador se encontraria con items que no se pueden usar.
	if not self.catalog.Has(itemId) then
		return false, nil, ("item desconocido: %s"):format(tostring(itemId))
	end

	local definition = self.catalog.Get(itemId)
	if definition.Available == false and definition.Stackable ~= true then
		return false, nil, ("el item ya no esta disponible: %s"):format(tostring(itemId))
	end

	local safe, amountReason = sanitizeQuantity(amount)
	if safe == nil then
		return false, nil, amountReason
	end

	local current = self:GetQuantity(state, itemId)
	local maxStack = definition.MaxStack or 1

	-- Un item NO apilable no puede pasar de 1 unidad. Sin este tope, un
	-- `AddItem` repetido sobre un cosmetic acumularia unidades de algo
	-- que conceptualmente es de una sola vez, y el perfil guardado
	-- llevaria un numero que no corresponde con nada.
	if not definition.Stackable then
		if current >= 1 then
			-- No es un error: ya lo tiene. Se informa como exito para
			-- que la UI no muestre un fallo por reintentar una compra.
			return true, state.Items[itemId], "el jugador ya posee ese item"
		end
		state.Items[itemId] = { Quantity = 1 }
	elseif current + (safe :: number) > maxStack then
		-- Se CAPA en el tope en lugar de rechazar: rechazar perderia la
		-- recompensa entera por un hueco de dos unidades.
		local room = maxStack - current
		if room <= 0 then
			return false, nil, ("pila de %s llena (%d)"):format(tostring(itemId), maxStack)
		end
		state.Items[itemId] = { Quantity = current + room }
	else
		state.Items[itemId] = { Quantity = current + (safe :: number) }
	end

	state.Sequence += 1
	local entry = {
		entryId = ("inv-%s-%d"):format(tostring(state.PlayerId), state.Sequence),
		playerId = state.PlayerId,
		action = "Add",
		itemId = itemId,
		quantity = state.Items[itemId].Quantity,
		source = type(source) == "string" and source or "desconocido",
		timestamp = os.time(),
	}

	local index = appendEntry(state, entry)
	if type(requestId) == "string" and requestId ~= "" then
		state.Requests[requestId] = index
	end

	return true, state.Items[itemId], nil
end
--- Retira unidades de un item.
---
--- No comprueba que el item sea consumible: `RemoveItem` es la via
--- administrativa (devoluciones, correcciones) y `ConsumeItem` es la via
--- del jugador. Confundirlas haria imposible depurar por que un item
--- desaparecio del inventario.
--- @param state any
--- @param itemId string
--- @param amount number
--- @param source string
--- @param requestId string?
--- @return boolean success
--- @return string? errorReason
function InventoryRules:RemoveItem(
	state: any,
	itemId: string,
	amount: number,
	source: string,
	requestId: string?
): (boolean, string?)
	if type(state) ~= "table" or type(state.Items) ~= "table" then
		return false, "estado de inventario invalido"
	end

	if type(requestId) == "string" and requestId ~= "" then
		local previousIndex = state.Requests[requestId]
		if previousIndex then
			local previous = state.Entries[previousIndex]
			if previous then
				return true, "peticion repetida; se devuelve el resultado anterior"
			end
		end
	end

	if not self.catalog.Has(itemId) then
		return false, ("item desconocido: %s"):format(tostring(itemId))
	end

	local safe, amountReason = sanitizeQuantity(amount)
	if safe == nil then
		return false, amountReason
	end

	local current = self:GetQuantity(state, itemId)
	local wanted = safe :: number

	-- No se puede retirar mas de lo que hay. Sin esta comprobacion el
	-- inventario llegaria a `Quantity = -5`, que la UI interpretaria como
	-- corrupto y el servidor no podria reparar.
	if current < wanted then
		return false, ("no tiene suficiente '%s' (tiene %d, pide %d)"):format(
			tostring(itemId),
			current,
			wanted
		)
	end

	local remaining = current - wanted

	if remaining > 0 then
		state.Items[itemId] = { Quantity = remaining }
	else
		-- A cero se BORRA la entrada en lugar de dejar `Quantity = 0`.
		-- Una entrada con cero tiene dos efectos malos: aparece en los
		-- recorridos como si el jugador lo tuviera, y al serializar el
		-- perfil infla el tamano con claves muertas.
		state.Items[itemId] = nil

		-- Un item que desaparece no puede seguir equipado.
		for slot, equippedId in pairs(state.Equipped) do
			if equippedId == itemId then
				state.Equipped[slot] = nil
			end
		end
	end

	state.Sequence += 1
	local entry = {
		entryId = ("inv-%s-%d"):format(tostring(state.PlayerId), state.Sequence),
		playerId = state.PlayerId,
		action = "Remove",
		itemId = itemId,
		quantity = wanted,
		source = type(source) == "string" and source or "desconocido",
		timestamp = os.time(),
	}

	local index = appendEntry(state, entry)
	if type(requestId) == "string" and requestId ~= "" then
		state.Requests[requestId] = index
	end

	return true, nil
end
--- Consume una unidad: el camino del "quiero usar el item X".
---
--- A diferencia de `RemoveItem`, EXIGE que el item sea consumible. Esa
--- diferencia es la que impide que un jugador pueda "gastarse" un
--- cosmetic con `Use`, y es tambien la que permite responder "este item
--- no se usa, se equipa" en lugar de un error generico.
--- @param state any
--- @param itemId string
--- @param source string
--- @param requestId string?
--- @return boolean success
--- @return any? definition definicion del item consumido
--- @return string? errorReason
function InventoryRules:ConsumeItem(
	state: any,
	itemId: string,
	source: string,
	requestId: string?
): (boolean, any?, string?)
	if not self.catalog.Has(itemId) then
		return false, nil, ("item desconocido: %s"):format(tostring(itemId))
	end

	local definition = self.catalog.Get(itemId)

	if definition.Consumable ~= true then
		return false, nil, ("el item no es consumible: %s"):format(tostring(itemId))
	end

	-- Se comprueba la propiedad ANTES de gastar. Usar un item que no se
	-- tiene no puede funcionar, y aqui no se concede nada.
	if not self:HasItem(state, itemId, 1) then
		return false, nil, ("no posee '%s'"):format(tostring(itemId))
	end

	local ok, reason = self:RemoveItem(state, itemId, 1, source, requestId)
	if not ok then
		return false, nil, reason
	end

	return true, definition, nil
end

--- Desbloquea un item: le da una unidad si no lo tiene.
---
--- Es `AddItem` con cantidad 1 y una comprobacion de "ya lo tiene", que
--- devuelve EXITO y no error. La diferencia no es cosmetica: reintentar
--- una compra ya completada debe verse como "ya lo tienes", nunca como
--- un fallo, porque el jugador no hizo nada mal.
--- @param state any
--- @param itemId string
--- @param source string
--- @param requestId string?
--- @return boolean success
--- @return string? errorReason
function InventoryRules:UnlockItem(
	state: any,
	itemId: string,
	source: string,
	requestId: string?
): (boolean, string?)
	if not self.catalog.Has(itemId) then
		return false, ("item desconocido: %s"):format(tostring(itemId))
	end

	if self:HasItem(state, itemId, 1) then
		return true, nil
	end

	local ok, reason = self:AddItem(state, itemId, 1, source, requestId)
	return ok, reason
end

--- Indica si `slot` es una ranura que existe.
--- @param slot any
--- @return boolean
function InventoryRules.IsKnownSlot(slot: any): boolean
	if type(slot) ~= "string" then
		return false
	end
	for _, known in ipairs(InventoryRules.Slots) do
		if known == slot then
			return true
		end
	end
	return false
end

--- Equipa un item que el jugador posee.
---
--- Se validan TRES cosas, en este orden: el item existe, es equiparable y
--- el jugador lo tiene. Falta cualquiera de las tres y no se equipa nada.
--- @param state any
--- @param itemId string
--- @param requestId string?
--- @return boolean success
--- @return string? errorReason
function InventoryRules:EquipItem(state: any, itemId: string, requestId: string?): (boolean, string?)
	if type(state) ~= "table" or type(state.Equipped) ~= "table" then
		return false, "estado de inventario invalido"
	end

	if not self.catalog.Has(itemId) then
		return false, ("item desconocido: %s"):format(tostring(itemId))
	end

	local definition = self.catalog.Get(itemId)

	if definition.Equipable ~= true then
		return false, ("el item no se puede equipar: %s"):format(tostring(itemId))
	end

	local slot = definition.Slot
	if not InventoryRules.IsKnownSlot(slot) then
		return false, ("ranura desconocida: %s"):format(tostring(slot))
	end

	-- Equipar algo que no se posee es el intento clasico de rostro falso.
	if not self:HasItem(state, itemId, 1) then
		return false, ("no posee '%s'"):format(tostring(itemId))
	end

	if type(requestId) == "string" and requestId ~= "" then
		local previousIndex = state.Requests[requestId]
		if previousIndex then
			local previous = state.Entries[previousIndex]
			if previous then
				return true, "peticion repetida; se devuelve el resultado anterior"
			end
		end
	end

	-- Una ranura tiene UN equipped. Si ya hay algo, se sustituye. Es
	-- correcto: el jugador no puede llevar dos sombreros.
	state.Equipped[slot] = itemId

	state.Sequence += 1
	local entry = {
		entryId = ("inv-%s-%d"):format(tostring(state.PlayerId), state.Sequence),
		playerId = state.PlayerId,
		action = "Equip",
		itemId = itemId,
		slot = slot,
		source = "equip",
		timestamp = os.time(),
	}

	local index = appendEntry(state, entry)
	if type(requestId) == "string" and requestId ~= "" then
		state.Requests[requestId] = index
	end

	return true, nil
end

--- Quita el item de una ranura. No devuelve nada al inventario: equipar
--- no era una propiedad del item, era una ranura ocupada.
--- @param state any
--- @param slot string
--- @return boolean success
--- @return string? errorReason
function InventoryRules:UnequipItem(state: any, slot: string): (boolean, string?)
	if type(state) ~= "table" or type(state.Equipped) ~= "table" then
		return false, "estado de inventario invalido"
	end

	if not InventoryRules.IsKnownSlot(slot) then
		return false, ("ranura desconocida: %s"):format(tostring(slot))
	end

	local current = state.Equipped[slot]
	if current == nil then
		-- No lleva nada puesto: no es un fallo grave, pero se informa
		-- para que la UI sepa distinguir "no llevaba nada" de un error.
		return false, ("la ranura %s esta vacia"):format(slot)
	end

	state.Equipped[slot] = nil

	state.Sequence += 1
	appendEntry(state, {
		entryId = ("inv-%s-%d"):format(tostring(state.PlayerId), state.Sequence),
		playerId = state.PlayerId,
		action = "Unequip",
		itemId = current,
		slot = slot,
		source = "unequip",
		timestamp = os.time(),
	})

	return true, nil
end
--- Expande un bundle en sus componentes y los anade al inventario.
---
--- Los bundles NUNCA se guardan como un id suelto: si se guardaran, el
--- jugador no podria usar ni equipar por separado lo que compro, y el
--- inventario mostraria un "pack" en lugar de sus piezas.
---
--- Es PARCIAL a proposito: si un componente falla (pila llena), los otros
--- se entregan igualmente. Devolver todo o nada ante un fallo parcial
--- haria que el jugador perdiera los items que si podia recibir.
--- @param state any
--- @param bundleId string
--- @param source string
--- @param requestId string?
--- @return boolean success
--- @return { string } granted ids efectivamente anadidos
--- @return { string } problems motivos de los que no se pudieron anadir
--- @return string? errorReason
function InventoryRules:ExpandBundle(
	state: any,
	bundleId: string,
	source: string,
	requestId: string?
): (boolean, { string }, { string }, string?)
	if not self.catalog.Has(bundleId) then
		return false, {}, {}, ("item desconocido: %s"):format(tostring(bundleId))
	end

	local definition = self.catalog.Get(bundleId)
	if definition.Category ~= self.catalog.Category.Bundle then
		return false, {}, {}, ("no es un bundle: %s"):format(tostring(bundleId))
	end

	local contents = self.catalog.GetBundleContents(bundleId)
	local granted: { string } = {}
	local problems: { string } = {}

	-- Los ids se ordenan para que el orden de entrega sea SIEMPRE el
	-- mismo. Sin esto, un bundle con dos componentes que uno bien y otro
	-- mal devolveria los motivos en orden distinto en cada llamada, y la
	-- lista de errores de la UI pareceria aleatoria.
	for _, itemId in ipairs(self.catalog.GetAllIds()) do
		local count = contents[itemId]

		if count then
			local ok = self:AddItem(
				state,
				itemId,
				count,
				(source .. ":bundle"),
				requestId and (("%s:%s"):format(requestId, itemId)) or nil
			)

			if ok then
				table.insert(granted, itemId)
			else
				table.insert(problems, ("%s: pila llena"):format(itemId))
			end
		end
	end

	return true, granted, problems, nil
end

--- Anomalias del inventario. Consulta pura: no modifica nada.
---
--- Busca, en este orden: ids que ya no existen en el catalogo (un item
--- retirado del juego sigue en el perfil de quien lo compro y hay que
--- decidir que hacer con el), cantidades imposibles y ranuras ocupadas
--- por items que el jugador ya no tiene.
--- @param state any
--- @return { string }
function InventoryRules:Audit(state: any): { string }
	local problems: { string } = {}

	if type(state) ~= "table" or type(state.Items) ~= "table" then
		table.insert(problems, "estado de inventario invalido")
		return problems
	end

	for itemId, entry in pairs(state.Items) do
		if type(entry) ~= "table" then
			table.insert(problems, ("%s: entrada no es una tabla"):format(tostring(itemId)))
		elseif type(entry.Quantity) ~= "number" or entry.Quantity ~= entry.Quantity then
			table.insert(problems, ("%s: cantidad no numerica"):format(tostring(itemId)))
		elseif entry.Quantity <= 0 then
			-- Una entrada con cero no deberia existir: `RemoveItem` la borra.
			table.insert(problems, ("%s: entrada con cantidad %d"):format(tostring(itemId), entry.Quantity))
		elseif not self.catalog.Has(itemId) then
			-- Se AVISA, no se borra: el jugador pago por ese item. Que lo
			-- retire una persona, no una auditoria automatica.
			table.insert(problems, ("%s: ya no existe en el catalogo"):format(tostring(itemId)))
		end
	end

	if type(state.Equipped) == "table" then
		for slot, itemId in pairs(state.Equipped) do
			if not InventoryRules.IsKnownSlot(slot) then
				table.insert(problems, ("ranura desconocida: %s"):format(tostring(slot)))
			elseif self:GetQuantity(state, itemId) < 1 then
				-- Equipar algo que no se tiene es exactamente lo que un
				-- cliente exploit intentaria injectar en el perfil.
				table.insert(problems, ("ranura %s con un item no poseido: %s"):format(
					tostring(slot),
					tostring(itemId)
				))
			end
		end
	end

	return problems
end

return InventoryRules