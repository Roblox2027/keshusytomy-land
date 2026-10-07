--!strict
--[[
	ItemCatalog
	Catalogo CENTRAL y UNICO de items del juego.

	POR QUE ESTE ARCHIVO
	--------------------
	Antes, cada sistema que necesidase saber "que items existen" se
	inventaba su propia lista. Eso producia tres fallos reales:

	  1. La tienda podia VENDER un id que el inventario no conocia, y
	     el jugador pagaba por nada.
	  2. Cliente y servidor podian tener listas distintas: el cliente
	     muestra un precio que el servidor no conoce.
	  3. Anadir un item obligaba a tocar 4 archivos, y era facil
	     olvidar uno.

	Aqui hay UNA definicion por `ItemId`. Servidor y cliente leen de
	este mismo modulo, asi que no pueden discrepar.

	REGLA DE AUTORIDAD (importante)
	-------------------------------
	Que un item ESTE aqui no concede nada. Este catalogo responde
	"que es este item y cuanto cuesta", nunca "el jugador lo tiene" ni
	"puede pagarlo". Eso lo deciden, en el servidor y en este orden:

	    ItemCatalog (que es)
	      -> InventoryService (si lo posee)
	      -> EconomyService (si lo puede pagar)
	      -> ShopService (orquesta la compra)

	El `Price` es un dato de CONSULTA. El cliente jamas lo envia: pide
	`"quiero comprar X"` y el servidor busca aqui el precio real. Si un
	cliente enviara un precio, seria un exploit, no una funcionalidad.

	NOTA DE PERSISTENCIA
	--------------------
	Un `ItemId` NO debe cambiar jamas. Es la clave con la que se
	serializa el inventario en el perfil. Renombrar un id pierde el
	inventario de todos los que lo tenian. Para cambiar el texto o el
	precio se edita la definicion; para retirar un item se marca
	`Available = false` (se sigue reconociendo, deja de venderse).
]]

local ItemCatalog = {}

-- Categorias. Texto estable, agrupado por la UI.
ItemCatalog.Category = {
	Consumable = "Consumable",
	Cosmetic = "Cosmetic",
	Skin = "Skin",
	Emote = "Emote",
	Booster = "Booster",
	Powerup = "Powerup",
	Bundle = "Bundle",
	VIP = "VIP",
}

-- Rarezas. `Common` es la de partida; las demas son PURA cosmetica y
-- no otorgan ventaja competitiva (regla anti-P2W de esta fase).
ItemCatalog.Rarity = {
	Common = "Common",
	Rare = "Rare",
	Epic = "Epic",
	Legendary = "Legendary",
}

-- Monedas admitidas. Deliberadamente las MISMAS dos que valida
-- `EconomyRules`. Un item con una moneda que la economia no conoce es
-- un item que no se puede cobrar nunca.
ItemCatalog.Currency = {
	Coins = "Coins",
	Gems = "Gems",
	Free = "Free",
}

-- ---------------------------------------------------------------
-- Catalogo
-- ---------------------------------------------------------------
--
-- Campos por definicion:
--   Id            identificador ESTABLE (clave de persistencia)
--   DisplayName   texto para el jugador
--   Category      uno de ItemCatalog.Category
--   Rarity        uno de ItemCatalog.Rarity
--   Stackable     admite mas de una unidad por registro
--   MaxStack      tope por registro (1 si no es apilable)
--   Tradable      si puede cambiar de manos
--   Consumable    se gasta al usarse
--   Cosmetic      NO da ventaja competitiva
--   Equipable     se puede equipar
--   Slot          ranura de equipar (solo si Equipable)
--   Price         coste en `Currency`
--   Available     si se puede COMPRAR ahora
--   Description   texto para el jugador
local ITEMS: { [string]: any } = {
	-- --- Consumibles -------------------------------------------------
	-- Cure: cura pura. No aumenta dano, no da velocidad, no salta mas
	-- alto: solo quita vida. Es consumible, no ventaja.
	Cure_Potion = {
		Id = "Cure_Potion",
		DisplayName = "Pocion de cura",
		Category = ItemCatalog.Category.Consumable,
		Rarity = ItemCatalog.Rarity.Common,
		Stackable = true,
		MaxStack = 99,
		Tradable = false,
		Consumable = true,
		Cosmetic = false,
		Equipable = false,
		Price = 25,
		Currency = ItemCatalog.Currency.Coins,
		Available = true,
		Description = "Restaura 50 de vida al usarse.",
		HealAmount = 50,
	},

	-- --- Cosmeticos --------------------------------------------------
	-- Todos `Cosmetic = true` y ninguno tiene efecto mecanico: es la
	-- garantia estructural de que la tienda no es pay-to-win.
	Hat_Keshusy = {
		Id = "Hat_Keshusy",
		DisplayName = "Sombrero Keshusy",
		Category = ItemCatalog.Category.Cosmetic,
		Rarity = ItemCatalog.Rarity.Common,
		Stackable = false,
		MaxStack = 1,
		Tradable = false,
		Consumable = false,
		Cosmetic = true,
		Equipable = true,
		Slot = "Head",
		Price = 500,
		Currency = ItemCatalog.Currency.Coins,
		Available = true,
		Description = "Sombrero del guardian del nucleo. Puramente estetico.",
	},

	Cape_Flame = {
		Id = "Cape_Flame",
		DisplayName = "Capa de llama",
		Category = ItemCatalog.Category.Cosmetic,
		Rarity = ItemCatalog.Rarity.Rare,
		Stackable = false,
		MaxStack = 1,
		Tradable = false,
		Consumable = false,
		Cosmetic = true,
		Equipable = true,
		Slot = "Back",
		Price = 1200,
		Currency = ItemCatalog.Currency.Coins,
		Available = true,
		Description = "Capa que arde. No hace dano: solo se ve.",
	},

	Trail_Gems = {
		Id = "Trail_Gems",
		DisplayName = "Estela de gemas",
		Category = ItemCatalog.Category.Cosmetic,
		Rarity = ItemCatalog.Rarity.Epic,
		Stackable = false,
		MaxStack = 1,
		Tradable = false,
		Consumable = false,
		Cosmetic = true,
		Equipable = true,
		Slot = "Trail",
		Price = 40,
		Currency = ItemCatalog.Currency.Gems,
		Available = true,
		Description = "Estela de gemas. No cambia nada del juego.",
	},

	-- --- Skins -------------------------------------------------------
	Skin_Gold = {
		Id = "Skin_Gold",
		DisplayName = "Skin dorado",
		Category = ItemCatalog.Category.Skin,
		Rarity = ItemCatalog.Rarity.Legendary,
		Stackable = false,
		MaxStack = 1,
		Tradable = false,
		Consumable = false,
		Cosmetic = true,
		Equipable = true,
		Slot = "Body",
		Price = 120,
		Currency = ItemCatalog.Currency.Gems,
		Available = true,
		Description = "Skin dorado. En juego es identico a la basica.",
	},

	-- --- Emotes ------------------------------------------------------
	Emote_Dance = {
		Id = "Emote_Dance",
		DisplayName = "Baile",
		Category = ItemCatalog.Category.Emote,
		Rarity = ItemCatalog.Rarity.Common,
		Stackable = false,
		MaxStack = 1,
		Tradable = false,
		Consumable = false,
		Cosmetic = true,
		Equipable = false,
		Price = 100,
		Currency = ItemCatalog.Currency.Coins,
		Available = true,
		Description = "Emote de baile. No otorga ninguna ventaja.",
	},

	-- --- Boosters ----------------------------------------------------
	-- Los boosters SOLO alteran EXPERIENCIA y MONEDAS, nunca el dano ni
	-- la vida. Por eso el catalogo no tiene ningun item que mejore el
	-- PvP: el PvP no se puede comprar.
	Booster_XP = {
		Id = "Booster_XP",
		DisplayName = "Booster de experiencia",
		Category = ItemCatalog.Category.Booster,
		Rarity = ItemCatalog.Rarity.Rare,
		Stackable = true,
		MaxStack = 20,
		Tradable = false,
		Consumable = true,
		Cosmetic = false,
		Equipable = false,
		Price = 300,
		Currency = ItemCatalog.Currency.Coins,
		Available = true,
		Description = "Doble XP durante 5 minutos. No afecta al combate.",
		DurationSeconds = 300,
		XpMultiplier = 2,
	},

	Booster_Coins = {
		Id = "Booster_Coins",
		DisplayName = "Booster de monedas",
		Category = ItemCatalog.Category.Booster,
		Rarity = ItemCatalog.Rarity.Rare,
		Stackable = true,
		MaxStack = 20,
		Tradable = false,
		Consumable = true,
		Cosmetic = false,
		Equipable = false,
		Price = 300,
		Currency = ItemCatalog.Currency.Coins,
		Available = true,
		Description = "Doble de monedas durante 5 minutos.",
		DurationSeconds = 300,
		CoinMultiplier = 2,
	},

	-- --- Bundles -----------------------------------------------------
	-- Un bundle agrupa varios items. El servidor lo expande al
	-- inventario; nunca se guarda como id suelto, porque asi sus
	-- componentes se pueden usar por separado.
	Bundle_Starter = {
		Id = "Bundle_Starter",
		DisplayName = "Pack de inicio",
		Category = ItemCatalog.Category.Bundle,
		Rarity = ItemCatalog.Rarity.Common,
		Stackable = false,
		MaxStack = 1,
		Tradable = false,
		Consumable = false,
		Cosmetic = true,
		Equipable = false,
		Price = 750,
		Currency = ItemCatalog.Currency.Coins,
		Available = true,
		Description = "Sombrero Keshusy, estela de gemas y 3 pociones.",
		Contents = { "Hat_Keshusy", "Trail_Gems", "Cure_Potion" },
		ContentCounts = { Hat_Keshusy = 1, Trail_Gems = 1, Cure_Potion = 3 },
	},

	-- --- Materiales de mundo (mision V2, FASE 23/25) ------------------
	--
	-- NO SE VENDEN (`Available = false`): entran al inventario por DROPS
	-- de monstruos, minibosses, bosses y eventos, no por la tienda. Un
	-- material comprable convertiria el drop en irrelevante y la tienda
	-- en pay-to-skip.
	--
	-- La categoria es `Powerup` (la categoria "no cosmetica, no
	-- equipable" que ya existe): crear una categoria nueva obligaria a
	-- tocar la UI, las reglas y los tests por un solo dato.
	Mat_LeafEssence = {
		Id = "Mat_LeafEssence",
		DisplayName = "Esencia de hoja",
		Category = ItemCatalog.Category.Powerup,
		Rarity = ItemCatalog.Rarity.Common,
		Stackable = true,
		MaxStack = 999,
		Tradable = false,
		Consumable = false,
		Cosmetic = false,
		Equipable = false,
		Price = 0,
		Currency = ItemCatalog.Currency.Free,
		Available = false,
		Description = "Material del bosque. Lo sueltan sus criaturas.",
	},
	Mat_SandCrystal = {
		Id = "Mat_SandCrystal",
		DisplayName = "Cristal de arena",
		Category = ItemCatalog.Category.Powerup,
		Rarity = ItemCatalog.Rarity.Common,
		Stackable = true,
		MaxStack = 999,
		Tradable = false,
		Consumable = false,
		Cosmetic = false,
		Equipable = false,
		Price = 0,
		Currency = ItemCatalog.Currency.Free,
		Available = false,
		Description = "Material del desierto. Lo sueltan sus criaturas.",
	},
	Mat_FrostShard = {
		Id = "Mat_FrostShard",
		DisplayName = "Fragmento de escarcha",
		Category = ItemCatalog.Category.Powerup,
		Rarity = ItemCatalog.Rarity.Common,
		Stackable = true,
		MaxStack = 999,
		Tradable = false,
		Consumable = false,
		Cosmetic = false,
		Equipable = false,
		Price = 0,
		Currency = ItemCatalog.Currency.Free,
		Available = false,
		Description = "Material del hielo. Lo sueltan sus criaturas.",
	},
	Mat_EmberCore = {
		Id = "Mat_EmberCore",
		DisplayName = "Nucleo de brasa",
		Category = ItemCatalog.Category.Powerup,
		Rarity = ItemCatalog.Rarity.Rare,
		Stackable = true,
		MaxStack = 999,
		Tradable = false,
		Consumable = false,
		Cosmetic = false,
		Equipable = false,
		Price = 0,
		Currency = ItemCatalog.Currency.Free,
		Available = false,
		Description = "Material raro del volcan. Lo sueltan sus criaturas.",
	},
	Mat_CircuitChip = {
		Id = "Mat_CircuitChip",
		DisplayName = "Chip de circuito",
		Category = ItemCatalog.Category.Powerup,
		Rarity = ItemCatalog.Rarity.Rare,
		Stackable = true,
		MaxStack = 999,
		Tradable = false,
		Consumable = false,
		Cosmetic = false,
		Equipable = false,
		Price = 0,
		Currency = ItemCatalog.Currency.Free,
		Available = false,
		Description = "Material raro del mundo cyber. Lo sueltan sus criaturas.",
	},

	-- --- Equipo de aventurero (mision V2, FASE 29) ---------------------
	--
	-- Piezas con STATS REALES, no cosmeticas: cada una modifica algo que
	-- cambia como se juega. Se compran con MONEDAS (la moneda que se gana
	-- jugando): son el sink de la economia, nunca pago real. Los deltas
	-- son modestos a proposito; los topes los aplica `EquipmentRules`.
	Gear_SwiftBoots = {
		Id = "Gear_SwiftBoots",
		DisplayName = "Botas ligeras",
		Category = ItemCatalog.Category.Cosmetic,
		Rarity = ItemCatalog.Rarity.Rare,
		Stackable = false,
		MaxStack = 1,
		Tradable = false,
		Consumable = false,
		Cosmetic = false,
		Equipable = true,
		Slot = "Feet",
		Price = 900,
		Currency = ItemCatalog.Currency.Coins,
		Available = true,
		Description = "+10 % de velocidad de movimiento.",
		Stats = { WalkSpeedMult = 0.10 },
	},
	Gear_GuardianPlate = {
		Id = "Gear_GuardianPlate",
		DisplayName = "Placa del guardian",
		Category = ItemCatalog.Category.Cosmetic,
		Rarity = ItemCatalog.Rarity.Epic,
		Stackable = false,
		MaxStack = 1,
		Tradable = false,
		Consumable = false,
		Cosmetic = false,
		Equipable = true,
		Slot = "Body",
		Price = 1400,
		Currency = ItemCatalog.Currency.Coins,
		Available = true,
		Description = "+25 de vida maxima.",
		Stats = { MaxHealthBonus = 25 },
	},
	Gear_FocusBand = {
		Id = "Gear_FocusBand",
		DisplayName = "Banda de enfoque",
		Category = ItemCatalog.Category.Cosmetic,
		Rarity = ItemCatalog.Rarity.Epic,
		Stackable = false,
		MaxStack = 1,
		Tradable = false,
		Consumable = false,
		Cosmetic = false,
		Equipable = true,
		Slot = "Head",
		Price = 1600,
		Currency = ItemCatalog.Currency.Coins,
		Available = true,
		Description = "-10 % al enfriamiento de la habilidad.",
		Stats = { AbilityCooldownMult = -0.10 },
	},
}

-- ---------------------------------------------------------------
-- Consultas
-- ---------------------------------------------------------------

--- Indica si un id existe en el catalogo.
--- @param itemId any
--- @return boolean
function ItemCatalog.Has(itemId: any): boolean
	if type(itemId) ~= "string" then
		return false
	end
	return ITEMS[itemId] ~= nil
end

--- Definicion de un item, o nil.
---
--- Se devuelve la tabla INTERNA a proposito: es de solo lectura por
--- convencion, y clonar cada definicion en cada consulta desperdiciaria
--- memoria en un bucle de UI. Quien necesite modificarla debe pasar por
--- `ItemCatalog.Add` en vez de escribir en la tabla.
--- @param itemId any
--- @return any? definition
function ItemCatalog.Get(itemId: any): any?
	if type(itemId) ~= "string" then
		return nil
	end
	return ITEMS[itemId]
end

--- Todos los ids del catalogo, en orden alfabetico.
---
--- El orden es FIJO a proposito: la UI lo recorre y un orden que
--- cambia entre llamadas haria parpadear la tienda.
--- @return { string }
function ItemCatalog.GetAllIds(): { string }
	local ids = {}
	for id in pairs(ITEMS) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	return ids
end

--- Definiciones para la UI, ordenadas por precio y luego por id.
---
--- Se ordenan por precio porque es como se lee una tienda; el id
--- desempata para que el orden sea estable entre llamadas.
--- @param options { category: string?, includeUnavailable: boolean? }?
--- @return { any }
function ItemCatalog.List(options: { category: string?, includeUnavailable: boolean? }?): { any }
	local resolved: { category: string?, includeUnavailable: boolean? } = options or {}
	local category = resolved.category
	local includeUnavailable = resolved.includeUnavailable == true

	local result = {}
	for _, id in ipairs(ItemCatalog.GetAllIds()) do
		local definition = ITEMS[id]
		if includeUnavailable or definition.Available then
			if category == nil or definition.Category == category then
				result[#result + 1] = definition
			end
		end
	end

	table.sort(result, function(a, b)
		local priceA = a.Price or 0
		local priceB = b.Price or 0
		if priceA ~= priceB then
			return priceA < priceB
		end
		return a.Id < b.Id
	end)

	return result
end

--- Cuantas unidades lleva un bundle al expandirse.
---
--- Devuelve una tabla NUEVA cada vez: si devolviera la interna,
--- `InventoryService` acabaria escribiendo sobre la definicion del
--- catalogo y el bundle se volveria acumulativo entre compras.
--- @param bundleId string
--- @return { [string]: number }
function ItemCatalog.GetBundleContents(bundleId: string): { [string]: number }
	local result: { [string]: number } = {}
	local definition = ITEMS[bundleId]

	if not definition or definition.Category ~= ItemCatalog.Category.Bundle then
		return result
	end

	local contents = definition.Contents
	if type(contents) ~= "table" then
		return result
	end

	local counts = definition.ContentCounts or {}

	for _, itemId in ipairs(contents) do
		-- Un bundle NO puede contener un id que no existe: si lo
		-- contuviera, la compra daria algo que el inventario no sabe
		-- representar. Se descarta aqui y `Validate` lo reporta arriba.
		if ItemCatalog.Has(itemId) then
			local count = counts[itemId]
			if type(count) ~= "number" or count < 1 then
				count = 1
			end
			result[itemId] = math.floor(count)
		end
	end

	return result
end

--- Anade una definicion nueva. Pensado para contenido y para pruebas.
--- @param definition any
--- @return boolean success
--- @return string? reason
function ItemCatalog.Add(definition: any): (boolean, string?)
	if type(definition) ~= "table" then
		return false, "definicion no es una tabla"
	end
	if type(definition.Id) ~= "string" or definition.Id == "" then
		return false, "Id invalido"
	end
	if not ITEMS[definition.Id] then
		return false, ("ItemId invalido: %s"):format(tostring(definition.Id))
	end

	-- Se rellenan los opcionales para que ningun consumidor tenga que
	-- preguntar por nil en un campo que conceptualmente siempre existe.
	local filled = table.clone(definition)
	filled.Stackable = filled.Stackable == true
	filled.MaxStack = filled.MaxStack or (filled.Stackable and 99 or 1)
	filled.Tradable = filled.Tradable == true
	filled.Consumable = filled.Consumable == true
	filled.Cosmetic = filled.Cosmetic == true
	filled.Equipable = filled.Equipable == true
	filled.Available = filled.Available ~= false
	filled.Price = filled.Price or 0
	filled.Currency = filled.Currency or ItemCatalog.Currency.Coins

	ITEMS[definition.Id] = filled
	return true, nil
end

--- Elimina una definicion. NO se usa en produccion: existe para que las
--- pruebas puedan montar un catalogo minimo sin ensuciar el real.
--- @param itemId string
function ItemCatalog.Remove(itemId: string)
	ITEMS[itemId] = nil
end

--- Valida el catalogo entero.
---
--- Esto es un CONTROL DE INTEGRIDAD, no una formalidad: un item con
--- precio negativo, moneda desconocida o bundle que se contiene a si
--- mismo es un item que rompe alguna regla mas adelante, y el fallo
--- aparece en produccion, no aqui.
--- @return { string } problems lista vacia si todo esta bien
function ItemCatalog.Validate(): { string }
	local problems: { string } = {}

	for _, id in ipairs(ItemCatalog.GetAllIds()) do
		local definition = ITEMS[id]

		if type(definition.Price) ~= "number" or definition.Price < 0 then
			table.insert(
				problems,
				("%s: precio invalido (%s)"):format(id, tostring(definition.Price))
			)
		end

		local currencyKnown = definition.Currency == ItemCatalog.Currency.Coins
			or definition.Currency == ItemCatalog.Currency.Gems
			or definition.Currency == ItemCatalog.Currency.Free
		if not currencyKnown then
			table.insert(
				problems,
				("%s: moneda desconocida (%s)"):format(id, tostring(definition.Currency))
			)
		end

		if definition.Tradable then
			table.insert(problems, ("%s: declara Tradable pero no hay mercado"):format(id))
		end

		-- Anti-P2W estructural: un item NO puede ser cosmetico y a la
		-- vez aportar efecto mecanico.
		if
			definition.Cosmetic
			and (definition.XpMultiplier or definition.CoinMultiplier or definition.HealAmount)
		then
			table.insert(problems, ("%s: es Cosmetic pero aporta efecto mecanico"):format(id))
		end

		if definition.Category == ItemCatalog.Category.Bundle then
			local contents = definition.Contents
			if type(contents) ~= "table" or #contents == 0 then
				table.insert(problems, ("%s: bundle sin contenido"):format(id))
			else
				for _, itemId in ipairs(contents) do
					if itemId == id then
						table.insert(problems, ("%s: bundle que se contiene a si mismo"):format(id))
					elseif not ItemCatalog.Has(itemId) then
						table.insert(
							problems,
							("%s: contiene el id inexistente %s"):format(id, tostring(itemId))
						)
					end
				end
			end
		end

		if definition.Equipable then
			if type(definition.Slot) ~= "string" or definition.Slot == "" then
				table.insert(problems, ("%s: Equipable sin Slot"):format(id))
			end
		elseif definition.Slot ~= nil then
			table.insert(problems, ("%s: tiene Slot pero no es Equipable"):format(id))
		end

		if definition.MaxStack ~= nil and definition.MaxStack < 1 then
			table.insert(problems, ("%s: MaxStack invalido"):format(id))
		end
	end

	return problems
end

return ItemCatalog
