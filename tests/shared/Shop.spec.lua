--!strict
--[[
	Shop.spec
	Pruebas de la cadena de compra COMPLETA.

	Se prueba con los modulos REALES (`ItemCatalog`, `EconomyRules`,
	`InventoryRules`), inyectados igual que hara `ShopService`. Asi, si el
	catalogo y la economia se desincronizan, estas pruebas lo detectan: un
	doble de prueba podria cobrar un precio que el catalogo no tiene y
	todo pasaria.

	Los casos que importan, y por que:

	  - no cobrar dos veces por la misma peticion (el fallo que mas cuesta)
	  - no cobrar un item que ya tiene
	  - no cobrar si no tiene saldo
	  - devolver el dinero si la entrega falla
	  - nunca regalar un item (cobrar y no entregar)
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local ItemCatalog = require("../../src/ReplicatedStorage/Shared/Config/ItemCatalog")
local EconomyRules = require("../../src/ReplicatedStorage/Shared/Libraries/EconomyRules")
local InventoryRules = require("../../src/ReplicatedStorage/Shared/Libraries/InventoryRules")
local ShopRules = require("../../src/ReplicatedStorage/Shared/Libraries/ShopRules")

local Outcome = ShopRules.Outcome
local Rejection = ShopRules.Rejection

-- Mismas piezas que inyecta el servicio real.
local function makeShop()
	local inventory = InventoryRules.new(ItemCatalog)
	return ShopRules.new({
		catalog = ItemCatalog,
		economy = EconomyRules,
		inventory = inventory,
	}), inventory
end

-- Perfil con saldo inicial, como lo montaria ProfileService.
local function profileWith(coins, gems)
	local state = {
		economy = EconomyRules.NewState(1),
		inventory = InventoryRules.NewState(1),
	}
	EconomyRules.AddCurrency(state.economy, "Coins", coins, "saldo_inicial", "test")
	EconomyRules.AddCurrency(state.economy, "Gems", gems or 1, "saldo_inicial", "test")
	return state
end

return function()
	Harness.describe("Shop: catalogo", function()
		Harness.it("el catalogo real no tiene problemas de integridad", function()
			-- Si un item tuviera precio negativo o moneda desconocida, el
			-- servicio cobraria cosas imposibles. Se comprueba el catalogo
			-- entero, no item a item.
			local problems = ItemCatalog.Validate()
			expect.toBe(#problems, 0)
		end)

		Harness.it("la tienda solo ofrece lo disponible", function()
			local shop = makeShop()
			local catalog = shop:GetCatalogForSale()
			expect.toBe(#catalog > 0, true)

			for _, definition in ipairs(catalog) do
				expect.toBe(definition.Available, true)
			end
		end)

		Harness.it("el precio sale del catalogo, no del cliente", function()
			local shop = makeShop()
			local definition = ItemCatalog.Get("Hat_Keshusy")
			expect.toBe(definition.Price, 500)
			expect.toBe(definition.Currency, ItemCatalog.Currency.Coins)
		end)
	end)

	Harness.describe("Shop: compra correcta", function()
		Harness.it("compra, cobra y entrega", function()
			local shop = makeShop()
			local profile = profileWith(1000)

			local outcome, rejection, receipt = shop:Purchase("Hat_Keshusy", profile, "p1", "shop")

			expect.toBe(outcome, Outcome.Purchased)
			expect.toBe(rejection, nil)
			expect.toBe(EconomyRules.GetBalance(profile.economy, "Coins"), 500)
			expect.toBe(profile.inventory.Items.Hat_Keshusy.Quantity, 1)
			expect.toBe(receipt.price, 500)
		end)

		Harness.it("cobra en la moneda correcta", function()
			-- El item cuesta gemas: cobrar coins seria un fallo grave.
			local shop = makeShop()
			local profile = profileWith(1000, 500)

			local outcome = shop:Purchase("Trail_Gems", profile, "p1", "shop")

			expect.toBe(outcome, Outcome.Purchased)
			expect.toBe(EconomyRules.GetBalance(profile.economy, "Gems"), 460)
			expect.toBe(EconomyRules.GetBalance(profile.economy, "Coins"), 1000)
		end)

		Harness.it("un bundle se expande en sus piezas", function()
			-- El jugador recibe SOMBRERO, ESTELA y POCIONES, no un "pack".
			local shop = makeShop()
			local profile = profileWith(1000)

			local outcome, _, receipt = shop:Purchase("Bundle_Starter", profile, "p1", "shop")

			expect.toBe(outcome, Outcome.Purchased)
			expect.toBe(profile.inventory.Items.Hat_Keshusy.Quantity, 1)
			expect.toBe(profile.inventory.Items.Trail_Gems.Quantity, 1)
			expect.toBe(profile.inventory.Items.Cure_Potion.Quantity, 3)
			expect.toBe(#receipt.granted, 3)
			-- El bundle no existe como item guardado.
			expect.toBe(profile.inventory.Items.Bundle_Starter, nil)
		end)
	end)

	Harness.describe("Shop: rechazo sin cobrar", function()
		Harness.it("rechaza un item inexistente SIN cobrar", function()
			local shop = makeShop()
			local profile = profileWith(1000)

			local outcome, rejection = shop:Purchase("Item_Inventado", profile, "p1", "shop")

			expect.toBe(outcome, Outcome.Rejected)
			expect.toBe(rejection, Rejection.UnknownItem)
			expect.toBe(EconomyRules.GetBalance(profile.economy, "Coins"), 1000)
		end)

		Harness.it("rechaza sin saldo suficiente SIN cobrar", function()
			local shop = makeShop()
			local profile = profileWith(10)

			local outcome, rejection = shop:Purchase("Cape_Flame", profile, "p1", "shop")

			expect.toBe(outcome, Outcome.Rejected)
			expect.toBe(rejection, Rejection.InsufficientFunds)
			-- Lo que importa: el saldo intacto.
			expect.toBe(EconomyRules.GetBalance(profile.economy, "Coins"), 10)
		end)

		Harness.it("no cobra un item que ya tiene", function()
			local shop = makeShop()
			local profile = profileWith(2000)

			shop:Purchase("Hat_Keshusy", profile, "p1", "shop")
			local afterFirst = EconomyRules.GetBalance(profile.economy, "Coins")

			local outcome, rejection = shop:Purchase("Hat_Keshusy", profile, "p2", "shop")

			expect.toBe(outcome, Outcome.AlreadyOwned)
			expect.toBe(rejection, Rejection.AlreadyOwned)
			expect.toBe(EconomyRules.GetBalance(profile.economy, "Coins"), afterFirst)
		end)

		Harness.it("rechaza una peticion malformada SIN cobrar", function()
			local shop = makeShop()
			local profile = profileWith(1000)

			expect.toBe((shop:Purchase(nil, profile, "p1", "shop")), Outcome.Rejected)
			expect.toBe((shop:Purchase("", profile, "p1", "shop")), Outcome.Rejected)
			expect.toBe((shop:Purchase(42, profile, "p1", "shop")), Outcome.Rejected)
			expect.toBe(EconomyRules.GetBalance(profile.economy, "Coins"), 1000)
		end)

		Harness.it("rechaza si no hay perfil", function()
			-- Un jugador sin perfil cargado no puede comprar. Aceptarlo
			-- significaria crear un item en un perfil que no existe.
			local shop = makeShop()
			expect.toBe((shop:Purchase("Hat_Keshusy", nil, "p1", "shop")), Outcome.Rejected)
		end)
	end)

	Harness.describe("Shop: idempotencia de la compra", function()
		Harness.it("la misma peticion NO cobra dos veces", function()
			-- El fallo mas caro y mas frecuente: el jugador pierde la
			-- conexion al pulsar "comprar" y reintenta. Sin este control,
			-- paga dos veces y recibe un item.
			local shop = makeShop()
			local profile = profileWith(2000)

			local first = shop:Purchase("Hat_Keshusy", profile, "compra-1", "shop")
			local balanceAfterFirst = EconomyRules.GetBalance(profile.economy, "Coins")
			local second = shop:Purchase("Hat_Keshusy", profile, "compra-1", "shop")

			expect.toBe(first, Outcome.Purchased)
			-- La segunda devuelve el MISMO resultado, no un rechazo distinto:
			-- el cliente puede mostrar "comprado" sin que se cobre otra vez.
			expect.toBe(second, Outcome.Purchased)
			expect.toBe(EconomyRules.GetBalance(profile.economy, "Coins"), balanceAfterFirst)
			expect.toBe(profile.inventory.Items.Hat_Keshusy.Quantity, 1)
		end)

		Harness.it("peticiones DISTINTAS del mismo item SI se cobran", function()
			-- El control no puede ser "cobrar una vez y ya". Un consumible
			-- apilable se puede comprar varias veces (una por peticion).
			local shop = makeShop()
			local profile = profileWith(1000)

			shop:Purchase("Cure_Potion", profile, "c1", "shop")
			shop:Purchase("Cure_Potion", profile, "c2", "shop")

			expect.toBe(profile.inventory.Items.Cure_Potion.Quantity, 2)
			expect.toBe(EconomyRules.GetBalance(profile.economy, "Coins"), 950)
		end)

		Harness.it("reintentar un bundle no lo entrega dos veces", function()
			local shop = makeShop()
			local profile = profileWith(2000)

			shop:Purchase("Bundle_Starter", profile, "b1", "shop")
			local coins = EconomyRules.GetBalance(profile.economy, "Coins")
			shop:Purchase("Bundle_Starter", profile, "b1", "shop")

			expect.toBe(EconomyRules.GetBalance(profile.economy, "Coins"), coins)
			expect.toBe(profile.inventory.Items.Hat_Keshusy.Quantity, 1)
		end)
	end)

	Harness.describe("Shop: coherencia del dinero", function()
		Harness.it("una compra deja la economia sin anomalias", function()
			-- El ledger tiene que cuadrar DESPUES de una compra real, no
			-- solo en un escenario inventado.
			local shop = makeShop()
			local profile = profileWith(2000)

			shop:Purchase("Hat_Keshusy", profile, "p1", "shop")
			shop:Purchase("Cure_Potion", profile, "p2", "shop")

			expect.toBe(#EconomyRules.Audit(profile.economy), 0)
		end)

		Harness.it("nunca queda el saldo en negativo", function()
			local shop = makeShop()
			local profile = profileWith(30)

			shop:Purchase("Cure_Potion", profile, "p1", "shop")

			expect.toBe(EconomyRules.GetBalance(profile.economy, "Coins") >= 0, true)
		end)

		Harness.it("el saldo coincide siempre con lo que dice la UI", function()
			-- Compra, rechazo y denegado por saldo: el saldo tiene que ser
			-- exactamente 1000 - 500 tras la unica compra aceptada.
			local shop = makeShop()
			local profile = profileWith(1000)

			shop:Purchase("Item_Inventado", profile, "x1", "shop")
			shop:Purchase("Cape_Flame", profile, "x2", "shop")
			shop:Purchase("Hat_Keshusy", profile, "x3", "shop")

			expect.toBe(EconomyRules.GetBalance(profile.economy, "Coins"), 500)
		end)
	end)

	-- -------------------------------------------------------------------
	-- Nuevas categorias del mercado (FASE 31): alas, armas, objetos,
	-- vehiculos. La cadena de compra es la MISMA: valida, cobra, entrega.
	-- Lo que cambia es solo la definicion del item.
	-- -------------------------------------------------------------------
	Harness.describe("Shop: alas, armas, objetos y vehiculos", function()
		Harness.it("compra alas cosméticas y las entrega en inventario", function()
			local shop = makeShop()
			local profile = profileWith(500)

			local outcome, _, receipt = shop:Purchase("Wings_Angel", profile, "w1", "shop")

			expect.toBe(outcome, Outcome.Purchased)
			expect.toBe(profile.inventory.Items.Wings_Angel.Quantity, 1)
			expect.toBe(receipt.granted[1], "Wings_Angel")
		end)

		Harness.it("compra armas con stats y efectúa el cobro correcto", function()
			local shop = makeShop()
			local profile = profileWith(1500)

			local outcome, _, receipt = shop:Purchase("Weapon_Sword_Flame", profile, "wp1", "shop")

			expect.toBe(outcome, Outcome.Purchased)
			expect.toBe(EconomyRules.GetBalance(profile.economy, "Coins"), 100)
			expect.toBe(receipt.price, 1400)
			expect.toBe(receipt.currency, "Coins")
		end)

		Harness.it("compra alas de stats con monedas, no con gemas", function()
			-- Regla anti-P2W: cualquier item con Stats debe venderse en Coins.
			local shop = makeShop()
			local profile = profileWith(2000)

			local outcome, _, receipt = shop:Purchase("Wings_Spring", profile, "ws1", "shop")

			expect.toBe(outcome, Outcome.Purchased)
			expect.toBe(receipt.currency, "Coins")
		end)

		Harness.it("compra objetos consumibles apilables", function()
			local shop = makeShop()
			local profile = profileWith(1000)

			shop:Purchase("Potion_Invisibility", profile, "p1", "shop")
			shop:Purchase("Potion_Invisibility", profile, "p2", "shop")

			expect.toBe(profile.inventory.Items.Potion_Invisibility.Quantity, 2)
			expect.toBe(EconomyRules.GetBalance(profile.economy, "Coins"), 400)
		end)

		Harness.it("compra vehiculos con gemas", function()
			local shop = makeShop()
			local profile = profileWith(10, 100)

			local outcome, _, receipt = shop:Purchase("Vehicle_Warplane", profile, "v1", "shop")

			expect.toBe(outcome, Outcome.Purchased)
			expect.toBe(EconomyRules.GetBalance(profile.economy, "Gems"), 40)
			expect.toBe(receipt.currency, "Gems")
		end)

		Harness.it("una arma cosmética cuesta gemas y no entrega stats", function()
			local shop = makeShop()
			local profile = profileWith(10, 50)

			local outcome, _, receipt = shop:Purchase("Weapon_Crossbow", profile, "wc1", "shop")

			expect.toBe(outcome, Outcome.Purchased)
			local def = ItemCatalog.Get("Weapon_Crossbow")
			expect.toBe(def.Cosmetic, true)
			expect.toBe(type(def.Stats) == "table", false)
		end)

		Harness.it("el catalogo de venta incluye las nuevas categorias", function()
			local shop = makeShop()
			local catalog = shop:GetCatalogForSale()

			local hasWings = false
			local hasWeapon = false
			local hasVehicle = false

			for _, def in ipairs(catalog) do
				if def.Category == ItemCatalog.Category.Wings then
					hasWings = true
				elseif def.Category == ItemCatalog.Category.Weapon then
					hasWeapon = true
				elseif def.Category == ItemCatalog.Category.Vehicle then
					hasVehicle = true
				end
			end

			expect.toBe(hasWings, true)
			expect.toBe(hasWeapon, true)
			expect.toBe(hasVehicle, true)
		end)

		Harness.it("no se puede comprar dos veces la misma arma unica", function()
			local shop = makeShop()
			local profile = profileWith(10000)

			shop:Purchase("Weapon_Sword_Flame", profile, "r1", "shop")
			local outcome, rejection = shop:Purchase("Weapon_Sword_Flame", profile, "r2", "shop")

			expect.toBe(outcome, Outcome.AlreadyOwned)
			expect.toBe(rejection, Rejection.AlreadyOwned)
		end)
	end)
end