--!strict
--[[
	InventoryService
	Inventario del jugador, con propiedad real en el servidor.

	QUE ES Y QUE NO ES
	------------------
	Este servicio NO decide las reglas del inventario: las APLICA. Las
	reglas (que id existe, si se puede equipar, si la pila esta llena) viven
	en `InventoryRules`, logica pura y testeable sin motor.

	LA REGLA CENTRAL
	----------------
	El cliente NUNCA declara lo que tiene. Dice "quiero usar X" y el
	servidor responde en este orden:

	    1. X existe?          -> no, no hay nada
	    2. el jugador lo tiene? -> no, no hay nada
	    3. se puede usar?      -> no, no hay nada
	    4. SE EJECUTA           <- aqui, y solo aqui
	    5. se ACTUALIZA el perfil
	    6. se RESPONDE con el resultado

	Los pasos 1-3 no conceden nada. El unico que modifica el estado es el
	4-5. Confundirlos es lo que permite que un cliente se invente un item.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local UTILS = SHARED:WaitForChild("Utils")

local ItemCatalog = require(SHARED:WaitForChild("Config"):WaitForChild("ItemCatalog"))
local InventoryRules = require(SHARED:WaitForChild("Libraries"):WaitForChild("InventoryRules"))
local Logger = require(UTILS:WaitForChild("Logger"))

local Service = {}

Service.IsInitialized = false

-- ProfileService inyectado por ServerMain.
Service._profileService = nil

-- Reglas puras. Sin estado compartido entre jugadores: el estado va
-- dentro del perfil de cada uno.
local Rules = InventoryRules.new(ItemCatalog)
Service._rules = Rules

Service._stats = { granted = 0, rejected = 0, used = 0, equipped = 0 }

-- Maid recibido en Init.
local MaidRef = nil

--- Inyecta las dependencias del servicio.
--- @param profileService any
function Service.SetDependencies(profileService: any)
	Service._profileService = profileService
end

--- Inicializacion del servicio. Idempotente.
--- @param maid any?
--- @return boolean success
function Service.Init(maid: any?): boolean
	MaidRef = maid
	Service._stats = { granted = 0, rejected = 0, used = 0, equipped = 0 }
	Service.IsInitialized = true
	return true
end

--- Arranque. Verifica catalogo y perfil.
--- @param maid any?
--- @return boolean success
function Service.Start(maid: any?): boolean
	if not Service._profileService then
		Logger.Error("InventoryService: sin ProfileService; el inventario no puede funcionar.")
		return false
	end

	-- El catalogo se valida entero al arrancar: un item con precio
	-- negativo o con una ranura que no existe es un item que se compra y
	-- despues no se puede equipar.
	local problems = ItemCatalog.Validate()
	if #problems > 0 then
		Logger.Error(("InventoryService: el catalogo tiene %d problemas: %s"):format(
			#problems,
			table.concat(problems, "; ")
		))
		return false
	end

	Logger.Info(("InventoryService: inventario listo (%d items en catalogo)"):format(#ItemCatalog.GetAllIds()))
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

--- Estado de inventario de un jugador, o nil.
--- @param player Player?
--- @return any?
local function inventoryStateOf(player: Player?): any?
	if not player or not Service._profileService then
		return nil
	end
	return Service._profileService.GetInventoryState(player)
end

--- Inventario completo del jugador, listo para la UI.
--- @param player Player?
--- @return { [string]: number }
function Service.GetInventory(player: Player?): { [string]: number }
	return Rules:GetItems(inventoryStateOf(player))
end

--- Que hay equipado ahora, por ranura.
--- @param player Player?
--- @return { [string]: string }
function Service.GetEquipped(player: Player?): { [string]: string }
	return Rules:GetEquipped(inventoryStateOf(player))
end

--- Indica si el jugador posee un item.
---
--- ES UNA CONSULTA y no un permiso: que responda `true` NO significa que
--- el item se pueda usar ahora. Un consumible puede estar en cooldown y un
--- cosmetico puede no ser equiparable. Para actuar hay que llamar a
--- `UseItem` o `EquipItem`.
--- @param player Player?
--- @param itemId string
--- @param minimum number?
--- @return boolean
function Service.HasItem(player: Player?, itemId: string, minimum: number?): boolean
	return Rules:HasItem(inventoryStateOf(player), itemId, minimum)
end

--- Concede un item (recompensa, compra, codigo).
---
--- `requestId` evita entregar dos veces la misma recompensa.
--- @param player Player?
--- @param itemId string
--- @param amount number
--- @param source string
--- @param requestId string?
--- @return boolean success
--- @return string? errorReason
function Service.AddItem(
	player: Player?,
	itemId: string,
	amount: number,
	source: string,
	requestId: string?
): (boolean, string?)
	local state = inventoryStateOf(player)
	if not state then
		Service._stats.rejected += 1
		return false, "el jugador no tiene perfil cargado"
	end

	local ok, err = Rules:AddItem(state, itemId, amount, source, requestId)

	if ok then
		Service._stats.granted += 1
		Service._profileService.MarkDirty(player)
		Logger.Debug(("Inventory: +%d %s a %s (%s)"):format(amount, itemId, player.Name, source))
	else
		Service._stats.rejected += 1
		Logger.Warn(("Inventory: no se pudo dar %s: %s"):format(tostring(itemId), tostring(err)))
	end

	return ok, err
end

--- Quita un item sin consumirlo (devoluciones, correcciones).
---
--- No comprueba que sea consumible: `ConsumeItem` es la via del jugador y
--- esta la administrativa. Confundirlas haria imposible depurar por que un
--- item desaparecio del inventario.
--- @param player Player?
--- @param itemId string
--- @param amount number
--- @param source string
--- @param requestId string?
--- @return boolean success
--- @return string? errorReason
function Service.RemoveItem(
	player: Player?,
	itemId: string,
	amount: number,
	source: string,
	requestId: string?
): (boolean, string?)
	local state = inventoryStateOf(player)
	if not state then
		return false, "el jugador no tiene perfil cargado"
	end

	local ok, err = Rules:RemoveItem(state, itemId, amount, source, requestId)

	if ok then
		Service._profileService.MarkDirty(player)
	else
		Logger.Warn(("Inventory: no se pudo quitar %s: %s"):format(tostring(itemId), tostring(err)))
	end

	return ok, err
end

--- Consume un item: la via del "quiero usar X".
---
--- Valida TODO en el servidor antes de gastar: existe, es consumible y el
--- jugador lo tiene. Un cliente que mande el id de un item que no posee no
--- obtiene nada.
--- @param player Player?
--- @param itemId string
--- @param requestId string?
--- @return boolean success
--- @return any? definition definicion del item consumido
--- @return string? errorReason
function Service.UseItem(player: Player?, itemId: string, requestId: string?): (boolean, any?, string?)
	local state = inventoryStateOf(player)
	if not state then
		Service._stats.rejected += 1
		return false, nil, "el jugador no tiene perfil cargado"
	end

	local ok, definition, err = Rules:ConsumeItem(state, itemId, "player_use", requestId)

	if not ok then
		Service._stats.rejected += 1
		-- Un intento de usar algo que no se tiene es la senal mas
		-- interesante que puede mandar un cliente. Se registra con nombre
		-- de jugador, sin conexion: registrar el evento es lo primero, y
		-- expulsar por el es una decision posterior.
		Logger.Warn(("Inventory: %s intento usar '%s': %s"):format(player.Name, tostring(itemId), tostring(err)))
		return false, nil, err
	end

	Service._stats.used += 1
	Service._profileService.MarkDirty(player)

	-- El `HealAmount` NO se aplica aqui. Este servicio es el inventario: no
	-- sabe nada del personaje ni del combate. Devuelve la definicion y es
	-- quien corresponda (el combate) quien decide que hacer con ella. Aplicar
	-- la cura aqui seria inventar una dependencia de este servicio con el
	-- combate, y el combate ya depende de otras cosas.
	Logger.Info(("Inventory: %s uso '%s'"):format(player.Name, itemId))

	return true, definition, nil
end

--- Equipa un item que el jugador posee.
--- @param player Player?
--- @param itemId string
--- @param requestId string?
--- @return boolean success
--- @return string? errorReason
function Service.EquipItem(player: Player?, itemId: string, requestId: string?): (boolean, string?)
	local state = inventoryStateOf(player)
	if not state then
		Service._stats.rejected += 1
		return false, "el jugador no tiene perfil cargado"
	end

	local ok, err = Rules:EquipItem(state, itemId, requestId)

	if ok then
		Service._stats.equipped += 1
		Service._profileService.MarkDirty(player)
		-- `Equipped` se publica como ARRAY de "ranura=itemId", no como
		-- tabla: los atributos de Roblox no admiten diccionarios, y
		-- publicarlo asi fallaria con "Dictionary is not a supported
		-- attribute type" DESPUES de haber equipado. El item quedaria
		-- equipado y el jugador veria un error en vez de su sombrero.
		player:SetAttribute("Equipped", Service.GetEquippedSummary(player))
		Logger.Debug(("Inventory: %s equipa '%s'"):format(player.Name, itemId))
	else
		Service._stats.rejected += 1
		Logger.Warn(("Inventory: %s no pudo equipar '%s': %s"):format(player.Name, tostring(itemId), tostring(err)))
	end

	return ok, err
end

--- Desequipa una ranura.
---
--- Devuelve el `itemId` que estaba puesto, para que la UI pueda
--- actualizar el icono sin tener que preguntar por el inventario entero.
--- @param player Player?
--- @param slot string
--- @return boolean success
--- @return string? removedItemId
--- @return string? errorReason
function Service.UnequipItem(player: Player?, slot: string): (boolean, string?, string?)
	local state = inventoryStateOf(player)
	if not state then
		return false, nil, "el jugador no tiene perfil cargado"
	end

	local previous = state.Equipped[slot]
	local ok, err = Rules:UnequipItem(state, slot)

	if ok then
		Service._profileService.MarkDirty(player)
		player:SetAttribute("Equipped", Service.GetEquippedSummary(player))
		Logger.Debug(("Inventory: %s unequip '%s'"):format(player.Name, tostring(previous)))
	end

	return ok, previous, err
end

--- Ranuras ocupadas como CADENA "ranura=itemId" separada por comas.
---
--- Es una cadena y no una tabla por la restriccion de los atributos de
--- Roblox (solo escalares). Ver `ShopService.GetInventorySummary`.
--- @param player Player?
--- @return string
function Service.GetEquippedSummary(player: Player?): string
	local result = {}
	for slot, itemId in pairs(Service.GetEquipped(player)) do
		result[#result + 1] = ("%s=%s"):format(slot, itemId)
	end
	table.sort(result)
	return table.concat(result, ",")
end

--- Anomalias del inventario. Lista vacia = todo cuadra.
--- @param player Player?
--- @return { string }
function Service.AuditPlayer(player: Player?): { string }
	return Rules:Audit(inventoryStateOf(player))
end

--- Resumen para observabilidad.
--- @return { [string]: number }
function Service.GetStats(): { [string]: number }
	return {
		granted = Service._stats.granted,
		rejected = Service._stats.rejected,
		used = Service._stats.used,
		equipped = Service._stats.equipped,
	}
end

return Service
