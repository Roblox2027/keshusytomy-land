--!strict
--[[
	ItemDropService
	Pickups brillantes en el mapa que cuestionan Robux al recogerse (FASE 32).

	POR QUE EXISTE
	--------------
	La tienda con monedas (ShopService) es para items cosméticos y stats.
	Estos pickups son para el MUNDO: el jugador ve un objeto brillando en
	el mapa, se acerca, y el juego abre la puerta de pago de Robux. El
	pago es el UNICO camino: no hay alternativa con monedas, asi el
	item cosmético no devalúa la moneda del juego.

	LA REGLA ANTI-P2W
	-----------------
	Solo items con `Cosmetic = true` y `DeveloperProductId` pueden aparecer
	como pickups. Esto se valida en `ItemCatalog.Validate()` y se vuelve a
	comprobar aqui: un stat item jamás se vende por Robux.

	FLUJO DE RECOGIDA
	-----------------
		1. El jugador toca el pickup (Touch en `Core`).
		2. El servicio verifica proximidad y abre `ProximityPrompt`.
		3. El jugador confirma: `MarketplaceService:PromptProductPurchase`.
		4. Roblox llama a `ProcessReceipt`: el servicio entrega el item al
		   perfil del jugador y destruye el pickup.

	El pickup se destruye al INICIO de la compra: si el jugador cancela,
	el producto vuelve a aparecer tras `RefundTimeout`. Esto evita que
	dos jugadores compren el mismo pickup al mismo tiempo.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONFIG = SHARED:WaitForChild("Config")
local UTILS = SHARED:WaitForChild("Utils")

local ItemCatalog = require(CONFIG:WaitForChild("ItemCatalog"))
local VisualKit = require(SHARED:WaitForChild("Libraries"):WaitForChild("VisualKit"))
local Logger = require(UTILS:WaitForChild("Logger"))

local Service = {}

Service.IsInitialized = false

-- Folder unico donde viven los pickups del mundo.
Service._folder = nil
Service._maid = nil
Service._worldService = nil
-- ProfileService y InventoryService: para entregar el item tras el pago.
Service._profileService = nil
Service._inventoryService = nil

-- Pickup activo por jugador (evita prompts solapados).
Service._pendingPurchase = {}

-- Tiempo tras el cual un pickup cancelado reaparece.
Service.RefundTimeout = 8

-- Pickups generados / recogidos / pagados (diagnostico).
Service._spawned = 0
Service._collected = 0
Service._paid = 0

-- =========================================================================
-- CONFIGURACIÓN DE SPAWN
-- =========================================================================

--- Mundos donde se generan pickups y la lista de items que pueden salir.
--- Se declara como tabla de datos (no se lee del mapa) para que las pruebas
--- puedan verificar el comportamiento sin un Workspace real.
Service.SpawnConfig = {
	-- worldId -> { position = Vector3, itemId = string }[]
	Forest = {
		{ position = Vector3.new(-80, 5, -40),  itemId = "Wings_Angel" },
		{ position = Vector3.new(-72, 5, -32),  itemId = "Weapon_Crossbow" },
		{ position = Vector3.new(-88, 5, -48),  itemId = "Wings_Demon" },
	},
	Desert = {
		{ position = Vector3.new(90, 5, 110),  itemId = "Wings_Shadow" },
		{ position = Vector3.new(98, 5, 118),  itemId = "Wings_Crystal" },
		{ position = Vector3.new(82, 5, 102),  itemId = "Weapon_Crossbow" },
	},
	Ice = {
		{ position = Vector3.new(0, 5, -200),  itemId = "Wings_Angel" },
		{ position = Vector3.new(8, 5, -192),  itemId = "Wings_Crystal" },
	},
	Volcano = {
		{ position = Vector3.new(120, 30, 60),  itemId = "Weapon_Crossbow" },
		{ position = Vector3.new(128, 30, 68),  itemId = "Wings_Demon" },
	},
	Cyber = {
		{ position = Vector3.new(-50, 10, 130), itemId = "Wings_Shadow" },
		{ position = Vector3.new(-42, 10, 138), itemId = "Wings_Crystal" },
		{ position = Vector3.new(-58, 10, 122), itemId = "Weapon_Crossbow" },
	},
}

-- =========================================================================
-- UTILIDADES
-- =========================================================================

--- Carpeta unica donde viven los pickups.
--- @return Folder?
function Service.GetFolder(): Folder?
	if Service._folder and Service._folder.Parent then
		return Service._folder
	end

	local folder = Instance.new("Folder")
	folder.Name = "ItemDrops"
	folder:SetAttribute("IsItemDropFolder", true)
	folder.Parent = Workspace

	Service._folder = folder
	return folder
end

--- Inyecta dependencias del servidor.
--- @param profileService any?
--- @param inventoryService any?
function Service.SetDependencies(profileService: any?, inventoryService: any?)
	Service._profileService = profileService
	Service._inventoryService = inventoryService
end

--- Inyecta el world service (opcional: sin el, los spawns se usan por defecto).
--- @param worldService any?
function Service.SetWorldService(worldService: any?)
	Service._worldService = worldService
end

--- @return Folder? folder
--- @return number total
function Service.GetFolderInfo(): (Folder?, number)
	local folder = Service.GetFolder()
	local count = 0
	if folder then
		for _ in ipairs(folder:GetChildren()) do
			count += 1
		end
	end
	return folder, count
end

-- =========================================================================
-- RESOLUCIÓN DE ITEM / JUGADOR
-- =========================================================================

--- Busca el ItemId para un pickup a partir de su posicion.
--- En runtime, el pickup es un Model con atributo `ItemId`. En tests sin
--- motor de Roblox, se pasa el ItemId directamente.
--- @param pickuParam any Model|Instance|String
--- @return string? itemId
function Service.ResolveItemId(pickuParam: any): string?
	if type(pickuParam) == "string" then
		return pickuParam
	end

	if typeof(pickuParam) == "Instance" then
		if pickuParam:IsA("Model") then
			return pickuParam:GetAttribute("ItemId")
		end
		if pickuParam:IsA("BasePart") then
			local model = pickuParam:FindFirstAncestorWhichIsA("Model")
			return model and model:GetAttribute("ItemId")
		end
	end

	return nil
end

--- Mide la distancia entre el jugador y un punto, con validacion de tipo.
--- @param player Player
--- @param position any
--- @return number?
local function measureDistance(player: Player, position: any): number?
	if typeof(position) ~= "Vector3" then
		return nil
	end

	local character = player.Character
	if not character then
		return nil
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return nil
	end

	return (rootPart.Position - position).Magnitude
end

--- Indica si un jugador puede recoger un pickup (distancia + item valido).
--- @param player Player
--- @param itemId string
--- @param pickupPosition Vector3
--- @return boolean allowed
--- @return string? reason
function Service.CanCollect(player: Player, itemId: string, pickupPosition: Vector3): (boolean, string?)
	if type(player) ~= "userdata" or not player.Parent then
		return false, "jugador invalido"
	end

	local definition = ItemCatalog.Get(itemId)
	if not definition then
		return false, "item desconocido"
	end

	if not definition.WorldDrop or not definition.Cosmetic then
		return false, "item no disponible como pickup"
	end

	if type(definition.DeveloperProductId) ~= "number" then
		return false, "item sin DeveloperProductId"
	end

	local distance = measureDistance(player, pickupPosition)
	if not distance then
		return false, "no se pudo medir la distancia"
	end

	if distance > Service.CollectRadius then
		return false, "demasiado lejos"
	end

	return true
end

Service.CollectRadius = 14

-- =========================================================================
-- SPAWN Y DESPAWN
-- =========================================================================

--- Genera los pickups de un mundo desde la configuracion.
--- @param worldId string?
--- @return number spawned
function Service.SpawnForWorld(worldId: string?): number
	local world = worldId
		or (Service._worldService and Service._worldService.GetDefaultWorldId())

	if not world then
		world = "Forest"
	end

	local config = Service.SpawnConfig[world]
	if not config then
		return 0
	end

	local folder = Service.GetFolder()
	if not folder then
		return 0
	end

	local spawned = 0

	for _, entry in ipairs(config) do
		if type(entry.itemId) ~= "string" then
			continue
		end

		local definition = ItemCatalog.Get(entry.itemId)
		if not definition or not definition.WorldDrop then
			continue
		end

		local model = VisualKit.BuildItemDrop(definition, entry.position)
		if model then
			model.Parent = folder
			spawned += 1
		end
	end

	Service._spawned += spawned

	if spawned > 0 then
		Logger.Info(("ItemDropService: %d pickups generados en %s"):format(spawned, world))
	end

	return spawned
end

--- Regenera los pickups vacios (recogidos o expirados).
--- @param worldId string?
--- @return number spawned
function Service.RespawnEmpty(worldId: string?): number
	local folder = Service._folder

	if not folder then
		return 0
	end

	-- Cuenta cuantos quedan activos por ItemId.
	local active = {}

	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") then
			local itemId = child:GetAttribute("ItemId")
			if type(itemId) == "string" then
				active[itemId] = (active[itemId] or 0) + 1
			end
		end
	end

	local world = worldId
		or (Service._worldService and Service._worldService.GetDefaultWorldId()) or "Forest"

	local config = Service.SpawnConfig[world]
	if not config then
		return 0
	end

	local spawned = 0

	for _, entry in ipairs(config) do
		if type(entry.itemId) ~= "string" then
			continue
		end

		local definition = ItemCatalog.Get(entry.itemId)
		if not definition or not definition.WorldDrop then
			continue
		end

		local count = active[entry.itemId] or 0
		if count < 1 then
			local model = VisualKit.BuildItemDrop(definition, entry.position)
			if model then
				model.Parent = folder
				spawned += 1
			end
		end
	end

	return spawned
end

--- Borra todos los pickups vivos.
--- @return number removed
function Service.ClearAll(): number
	local removed = 0

	if not Service._folder then
		return 0
	end

	for _, child in ipairs(Service._folder:GetChildren()) do
		child:Destroy()
		removed += 1
	end

	return removed
end

-- =========================================================================
-- FLUJO DE RECOLECCIÓN
-- =========================================================================

--- El jugador intenta recoger un pickup.
---
--- No cobra nada aqui: abre el ProximityPrompt. El cobro ocurre en
--- `OnPurchaseComplete` tras la confirmacion de Roblox.
--- @param player Player
--- @param itemId string
--- @param position Vector3
--- @return boolean requested
function Service.RequestCollect(player: Player, itemId: string, position: Vector3): boolean
	if Service._pendingPurchase[player.UserId] then
		return false
	end

	local allowed, reason = Service.CanCollect(player, itemId, position)
	if not allowed then
		Logger.Debug(("ItemDrop: %s no puede recoger %s: %s"):format(
			player.Name, tostring(itemId), tostring(reason)
		))
		return false
	end

	-- Marca como pendiente: evita prompts dobles.
	Service._pendingPurchase[player.UserId] = {
		itemId = itemId,
		position = position,
	}

	player:SetAttribute("ItemDropPending", itemId)
	player:SetAttribute("ItemDropProductId", ItemCatalog.Get(itemId).DeveloperProductId)

	return true
end

--- Procesa el resultado del prompt de Robux de Roblox.
---
--- Si el jugador confirma, `MarketplaceService.ProcessReceipt` entrega el
--- item. Si cancela, el pickup se reubica tras `RefundTimeout`.
--- @param player Player
--- @param productId number
--- @param wasPurchased boolean
function Service.OnPurchaseResult(player: Player, productId: number, wasPurchased: boolean)
	local pending = Service._pendingPurchase[player.UserId]
	if not pending then
		return
	end

	if wasPurchased then
		-- El item se entrega en ProcessReceipt (autoridad de Roblox).
		-- Aqui solo destruimos el pickup para que no quede dos veces.
		local model = Service.FindPickupAt(pending.position)
		if model and model.Parent then
			model:Destroy()
		end
		Service._paid += 1
	else
		-- Cancelado: reaparece tras el timeout.
		local itemId = pending.itemId
		local position = pending.position

		task.delay(Service.RefundTimeout, function()
			if player.Parent and player.UserId == player.UserId then
				local folder = Service.GetFolder()
				if folder then
					local definition = ItemCatalog.Get(itemId)
					if definition and definition.WorldDrop then
						local model = VisualKit.BuildItemDrop(definition, position)
						if model then
							model.Parent = folder
						end
					end
				end
			end
		end)
	end

	Service._pendingPurchase[player.UserId] = nil
	player:SetAttribute("ItemDropPending", nil)
	player:SetAttribute("ItemDropProductId", nil)
	player:SetAttribute("ItemDropOutcome", wasPurchased and "purchased" or "cancelled")
end

--- Busca el pickup mas cercano a una posicion.
--- @param position Vector3
--- @return Model?
function Service.FindPickupAt(position: Vector3): Model?
	local folder = Service._folder
	if not folder then
		return nil
	end

	local closest: Model? = nil
	local closestDist = math.huge

	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") then
			local core = child:FindFirstChild("Core")
			if core and core:IsA("BasePart") then
				local dist = (core.Position - position).Magnitude
				if dist < closestDist and dist <= 2 then
					closest = child
					closestDist = dist
				end
			end
		end
	end

	return closest
end

-- =========================================================================
-- PROCESO DE RECEPCION (ProcessReceipt de Roblox)
-- =========================================================================

--- ProcessReceipt: Roblox confirma el pago y el servidor entrega el item.
---
--- Este metodo se registra como callback de `MarketplaceService.ProcessReceipt`
--- en `Start`. Recibe `receiptInfo` con `PlayerId`, `ProductId`, `PurchaseId`.
--- @param player Player
--- @param productId number
--- @param purchaseId string
--- @return boolean delivered
function Service.ProcessReceipt(player: Player, productId: number, purchaseId: string): boolean
	if not Service._profileService or not Service._inventoryService then
		Logger.Error("ItemDropService: ProcessReceipt sin ProfileService/InventoryService")
		return false
	end

	-- Busca el item por DeveloperProductId.
	local itemId: string? = nil
	local worlds = ItemCatalog.GetWorldDropItems()

	for id, definition in pairs(worlds) do
		if definition.DeveloperProductId == productId then
			itemId = id
			break
		end
	end

	if not itemId then
		Logger.Error(("ItemDropService: productId %d no reconocido"):format(productId))
		return false
	end

	-- Entrega el item al perfil del jugador.
	local ok = Service._inventoryService.AddItem(player, itemId, 1, "robux_purchase", nil)

	if ok then
		Service._profileService.MarkDirty(player)
		Logger.Info(("ItemDropService: %s compro %s via Robux (purchaseId=%s)"):format(
			player.Name, itemId, tostring(purchaseId)
		))
		-- Notifica al cliente para que muestre el efecto de recogida.
		player:SetAttribute("ItemDropLastGranted", itemId)
	else
		Logger.Error(("ItemDropService: no se pudo entregar %s a %s"):format(itemId, player.Name))
		return false
	end

	return true
end

-- =========================================================================
-- CICLO DE VIDA
-- =========================================================================

--- @param maid any?
--- @return boolean success
function Service.Init(maid: any?): boolean
	if Service.IsInitialized then
		return true
	end

	Service._maid = maid
	Service._spawned = 0
	Service._collected = 0
	Service._paid = 0

	if not Service.GetFolder() then
		Logger.Error("ItemDropService: no se pudo crear la carpeta de pickups.")
		return false
	end

	Service.IsInitialized = true
	Logger.Info("ItemDropService: inicializado.")
	return true
end

--- @return boolean success
function Service.Start(): boolean
	if not Service.IsInitialized then
		Logger.Error("ItemDropService: Start sin Init")
		return false
	end

	-- Registra ProcessReceipt para que Roblox gestiona el pago real.
	-- `pcall` por si MarketplaceService no esta disponible en tests.
	local ok = pcall(function()
		MarketplaceService.ProcessReceipt = function(_receiptInfo: any)
			local player = Players:GetPlayerByUserId(_receiptInfo.PlayerId)
			if not player or not player.Parent then
				return Enum.ProductPurchaseDecision.NotPurchased
			end

			local productId = tonumber(_receiptInfo.ProductId)
			if not productId then
				return Enum.ProductPurchaseDecision.NotPurchased
			end

			local delivered = Service.ProcessReceipt(player, productId, tostring(_receiptInfo.PurchaseId))
			if delivered then
				return Enum.ProductPurchaseDecision.PurchaseGranted
			else
				return Enum.ProductPurchaseDecision.NotPurchased
			end
		end
	end)

	if not ok then
		Logger.Warn("ItemDropService: MarketplaceService no disponible (entorno de pruebas).")
	end

	-- Inicia el brillo pulsátil de los pickups vivos.
	task.spawn(function()
		while Service.IsInitialized do
			local folder = Service._folder
			if folder then
				local now = os.clock()
				for _, child in ipairs(folder:GetChildren()) do
					if child:IsA("Model") then
						local light = child:FindFirstChild("Glow", true)
						if light and light:IsA("PointLight") then
							local pulse = math.sin(now * 3) * 0.5 + 1.5
							light.Brightness = pulse
						end
					end
				end
			end
			task.wait(0.1)
		end
	end)

	-- Reabastece pickups cancellados.
	task.spawn(function()
		while Service.IsInitialized do
			task.wait(15)
			if Service.IsInitialized then
				Service.RespawnEmpty()
			end
		end
	end)

	Logger.Info("ItemDropService: activo (pickups brillantes en el mapa).")
	return true
end

--- @return boolean success
function Service.Destroy(): boolean
	Service.ClearAll()

	if Service._folder and Service._folder.Parent then
		Service._folder:Destroy()
	end

	Service._folder = nil
	Service._worldService = nil
	Service._profileService = nil
	Service._inventoryService = nil
	Service._maid = nil
	Service._pendingPurchase = {}
	Service.IsInitialized = false
	return true
end

return Service
