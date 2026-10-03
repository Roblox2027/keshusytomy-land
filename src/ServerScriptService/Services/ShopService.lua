--!strict
--[[
	ShopService
	Catalogo y ejecucion de compras. Autoridad del servidor.

	LA REGLA QUE DEFINE ESTE SERVICIO
	----------------------------------
	El cliente manda SOLO un `ItemId`. Nunca un precio, nunca una cantidad,
	 nunca "tengo X coins".

	    CLIENTE   quiero comprar Hat_Keshusy
	    SERVIDOR  busca el precio en ItemCatalog
	    SERVIDOR  comprueba que el jugador lo puede pagar
	    SERVIDOR  comprueba que no lo tiene ya
	    SERVIDOR  cobra, con su requestId
	    SERVIDOR  entrega el item, con el MISMO requestId
	    SERVIDOR  responde con un recibo

	Si el cliente pudiera mandar el precio, el juego seria un cliente con la
	cartera. Por eso `RemoteSchema` declara `Purchase = String`: la forma
	del remoto NO admite un numero donde deberia ir el id.

	LA CADENA ESTA EN `ShopRules`
	-----------------------------
	Las siete validaciones y la compra viven ahi, en logica pura. Este
	servicio anade lo que necesita el motor: resolver el jugador a su perfil,
	registrar el resultado y publicar los atributos.

	POR QUE SE USA `ShopRules.new` Y NO LAS REGLAS SUELTAS
	------------------------------------------------------
	Porque `ShopRules` necesita las TRES piezas juntas (catalogo, economia,
	inventario) para validar y ejecutar. Es un servicio de dominio, no una
	funcion suelta.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local UTILS = SHARED:WaitForChild("Utils")

local EconomyRules = require(SHARED:WaitForChild("Libraries"):WaitForChild("EconomyRules"))
local InventoryRules = require(SHARED:WaitForChild("Libraries"):WaitForChild("InventoryRules"))
local ItemCatalog = require(SHARED:WaitForChild("Config"):WaitForChild("ItemCatalog"))
local ShopRules = require(SHARED:WaitForChild("Libraries"):WaitForChild("ShopRules"))
local Logger = require(UTILS:WaitForChild("Logger"))

local Service = {}

Service.IsInitialized = false

-- ProfileService (estado) y EconomyService (devoluciones).
Service._profileService = nil
Service._economyService = nil

-- Reglas de dominio, con las MISMAS piezas puras que usan las pruebas.
local Inventory = InventoryRules.new(ItemCatalog)
local Rules = ShopRules.new({
	catalog = ItemCatalog,
	economy = EconomyRules,
	inventory = Inventory,
})
Service._rules = Rules

Service._stats = { purchased = 0, alreadyOwned = 0, rejected = 0, refunded = 0 }

-- Maid recibido en Init.
local MaidRef = nil

--- Inyecta las dependencias del servicio.
--- @param profileService any
--- @param economyService any
function Service.SetDependencies(profileService: any, economyService: any)
	Service._profileService = profileService
	Service._economyService = economyService
end

--- Inicializacion del servicio. Idempotente.
--- @param maid any?
--- @return boolean success
function Service.Init(maid: any?): boolean
	MaidRef = maid
	Service._stats = { purchased = 0, alreadyOwned = 0, rejected = 0, refunded = 0 }
	Service.IsInitialized = true
	return true
end

--- Arranque. Verifica perfil y catalogo.
--- @param maid any?
--- @return boolean success
function Service.Start(maid: any?): boolean
	if not Service._profileService then
		Logger.Error("ShopService: sin ProfileService; la tienda no puede funcionar.")
		return false
	end

	local problems = ItemCatalog.Validate()
	if #problems > 0 then
		Logger.Error(("ShopService: el catalogo tiene %d problemas: %s"):format(
			#problems,
			table.concat(problems, "; ")
		))
		return false
	end

	Logger.Info(("ShopService: tienda lista (%d items a la venta)"):format(#Service.GetCatalog()))
	return true
end

--- Limpieza del servicio.
--- @return boolean success
function Service.Destroy(): boolean
	Service.IsInitialized = false
	Service._profileService = nil
	Service._economyService = nil
	MaidRef = nil
	return true
end

-- ---------------------------------------------------------------
-- API
-- ---------------------------------------------------------------

--- Catalogo de lo que se puede comprar ahora.
---
--- No acepta `includeUnavailable`: la tienda es lo que HAY, no lo que
--- estuvo una vez. Un item retirado no debe aparecer para comprar.
--- @param options { category: string? }?
--- @return { any }
function Service.GetCatalog(options: any): { any }
	return Rules:GetCatalogForSale(options)
end

--- Indica si un item esta en la tienda y se puede comprar.
---
--- ES UNA CONSULTA y no una compra: sirve para que la UI decida si
--- pintar el boton. No cobra, no entrega y no reserva.
--- @param player Player?
--- @param itemId string
--- @return boolean canBuy
--- @return string? rejectionCode
function Service.CanBuy(player: Player?, itemId: string): (boolean, string?)
	if not Service._profileService then
		return false, "la tienda no esta disponible"
	end

	local profileState = Service._profileService.GetProfileState(player)
	return Rules:Validate(itemId, profileState)
end

--- Compra un item. Cadena completa: valida, cobra y entrega.
---
--- @param player Player?
--- @param itemId string lo UNICO que manda el cliente
--- @param requestId string id unico de ESTA compra
--- @return string outcome uno de ShopRules.Outcome
--- @return string? rejectionCode
--- @return any? receipt informacion para la UI
function Service.Purchase(
	player: Player?,
	itemId: string,
	requestId: string
): (string, string?, any?)
	local outcome, rejection, receipt

	if not Service._profileService then
		Service._stats.rejected += 1
		return ShopRules.Outcome.Rejected, "no_profile", nil
	end

	local profileState = Service._profileService.GetProfileState(player)

	-- Sin perfil cargado no se compra NADA. Aceptarlo crearia un item en un
	-- perfil que no existe, y ese item se perderia al cargar el real.
	if profileState == nil then
		Service._stats.rejected += 1
		Logger.Warn(("Shop: %s intento comprar '%s' sin perfil cargado"):format(
			tostring(player and player.Name),
			tostring(itemId)
		))
		return ShopRules.Outcome.Rejected, ShopRules.Rejection.NoProfile, nil
	end

	outcome, rejection, receipt = Rules:Purchase(itemId, profileState, requestId, "shop")

	if outcome == ShopRules.Outcome.Purchased then
		Service._stats.purchased += 1
		Service._profileService.MarkDirty(player)
		-- El saldo se publica como numero, que SI es un tipo valido.
		if receipt then
			player:SetAttribute(receipt.currency, EconomyRules.GetBalance(profileState.economy, receipt.currency))
		end

		-- Los atributos de Roblox SOLO admiten escalares: `string`, `number`,
	-- `boolean`, `Color3`, `Vector3` y `nil`. Ni las tablas con claves
	-- ("Dictionary is not a supported attribute type") ni los arrays
	-- ("Array is not a supported attribute type") valen.
	--
	-- Por eso el inventario y el equipado viajan como CADENA separada por
	-- comas. Es la unica representacion que cabe, y es suficiente para que
	-- la UI sepa QUE tiene el jugador. Las CANTIDADES por item y las
	-- definiciones completas requieren `InvokeClient`, que es trabajo de la
	-- fase de UI, no de esta.
	--
	-- El fallo que esto evita NO es cosmetico: si la compra habia cobrado ya
	-- y la publicacion fallaba, el jugador pagaba y se quedaba sin item y
	-- sin mensaje.
	player:SetAttribute("InventorySummary", Service.GetInventorySummary(player))
		Logger.Info(("Shop: %s compro '%s' por %d %s"):format(
			player.Name,
			tostring(itemId),
			receipt and receipt.price or 0,
			receipt and receipt.currency or "?"
		))
	elseif outcome == ShopRules.Outcome.AlreadyOwned then
		Service._stats.alreadyOwned += 1
		-- No es un fallo: es el resultado de una compra repetida por costumbre.
		-- Se registra aparte para no llenar el log de ruido.
		Logger.Debug(("Shop: %s ya tenia '%s'"):format(player.Name, tostring(itemId)))
	else
		Service._stats.rejected += 1
		Logger.Warn(("Shop: compra rechazada de %s para '%s': %s"):format(
			player.Name,
			tostring(itemId),
			tostring(rejection)
		))
	end

	return outcome, rejection, receipt
end

--- Devuelve el dinero de una compra que se fallo tras cobrar.
---
--- `ShopRules` ya lo hace dentro del propio estado de economia. Este metodo
--- existe para el caso en que el estado que se modifico NO sea el del
--- jugador (por ejemplo, una compra de prueba en un harness).
--- @param player Player?
--- @param currency string
--- @param amount number
--- @param requestId string
--- @return boolean success
--- @return string? errorReason
function Service.Refund(player: Player?, currency: string, amount: number, requestId: string): (boolean, string?)
	if not Service._economyService then
		Service._stats.refunded += 1
		Logger.Error(("Shop: no hay EconomyService; no se puede devolver %d %s"):format(amount, currency))
		return false, "la tienda no tiene economia"
	end

	Service._stats.refunded += 1
	return Service._economyService.RefundCurrency(player, currency, amount, "compra_revertida", "shop", requestId)
end

--- Ids que el jugador posee. Lo que lee la UI de inventario.
--- @param player Player?
--- @return { [string]: number }
function Service.GetOwnedItems(player: Player?): { [string]: number }
	if not Service._profileService then
		return {}
	end
	return Inventory:GetItems(Service._profileService.GetInventoryState(player))
end

--- Los ids que el jugador posee, en una CADENA separada por comas.
---
--- Existe por una restriccion de la plataforma, no por gusto: los
--- atributos de Roblox SOLO admiten `string`, `number`, `boolean`, `Color3`,
--- `Vector3` y `nil`. Ni una tabla con claves ni un array caben, y
--- `SetAttribute` falla con "not a supported attribute type".
---
--- ORDEN alfabetico, para que la cadena no cambie entre lecturas y la UI
--- no parpadee.
--- @param player Player?
--- @return string
function Service.GetInventorySummary(player: Player?): string
	local ids = {}
	for itemId in pairs(Service.GetOwnedItems(player)) do
		ids[#ids + 1] = itemId
	end
	table.sort(ids)
	return table.concat(ids, ",")
end

--- Resumen para observabilidad.
--- @return { [string]: number }
function Service.GetStats(): { [string]: number }
	return {
		purchased = Service._stats.purchased,
		alreadyOwned = Service._stats.alreadyOwned,
		rejected = Service._stats.rejected,
		refunded = Service._stats.refunded,
	}
end

return Service
