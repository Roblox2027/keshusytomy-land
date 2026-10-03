--!strict
--[[
	Inventory.spec
	Pruebas del inventario server-authoritative.

	El caso central es la SEGURIDAD: el cliente pide "quiero usar X" y el
	servidor decide. Se comprueba que un item que el jugador NO posee
	nunca se puede usar ni equipar, porque ese es el intento clasico de
	exploit (ponerse un item inventado).
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local ItemCatalog = require("../../src/ReplicatedStorage/Shared/Config/ItemCatalog")
local InventoryRules = require("../../src/ReplicatedStorage/Shared/Libraries/InventoryRules")

local function makeInventory()
	return InventoryRules.new(ItemCatalog)
end

local function newState()
	return InventoryRules.NewState(1)
end

return function()
	Harness.describe("Inventory: add", function()
		Harness.it("anade un item", function()
			local inventory = makeInventory()
			local state = newState()

			local ok = inventory:AddItem(state, "Cure_Potion", 1, "shop")
			expect.toBe(ok, true)
			expect.toBe(inventory:GetQuantity(state, "Cure_Potion"), 1)
			expect.toBe(inventory:HasItem(state, "Cure_Potion"), true)
		end)

		Harness.it("apila consumibles", function()
			local inventory = makeInventory()
			local state = newState()

			inventory:AddItem(state, "Cure_Potion", 2, "shop")
			inventory:AddItem(state, "Cure_Potion", 3, "shop")
			expect.toBe(inventory:GetQuantity(state, "Cure_Potion"), 5)
		end)

		Harness.it("NO apila un item de una sola vez", function()
			-- Un sombrero no puede tener 5 unidades: seria un perfil con
			-- un numero que no corresponde con nada.
			local inventory = makeInventory()
			local state = newState()

			inventory:AddItem(state, "Hat_Keshusy", 1, "shop")
			inventory:AddItem(state, "Hat_Keshusy", 1, "shop")
			expect.toBe(inventory:GetQuantity(state, "Hat_Keshusy"), 1)
		end)

		Harness.it("rechaza un item que no existe", function()
			-- Si esto pasara, el perfil guardaria ids inventados que la UI
			-- no sabe dibujar y el servidor no puede quitar.
			local inventory = makeInventory()
			local state = newState()

			local ok = inventory:AddItem(state, "Item_Fantasma", 1, "shop")
			expect.toBe(ok, false)
			expect.toBe(inventory:GetQuantity(state, "Item_Fantasma"), 0)
		end)

		Harness.it("rechaza cantidades imposibles", function()
			local inventory = makeInventory()
			local state = newState()

			expect.toBe((inventory:AddItem(state, "Cure_Potion", 0, "shop")), false)
			expect.toBe((inventory:AddItem(state, "Cure_Potion", -5, "shop")), false)
			expect.toBe((inventory:AddItem(state, "Cure_Potion", 0 / 0, "shop")), false)
			expect.toBe((inventory:AddItem(state, "Cure_Potion", math.huge, "shop")), false)
			expect.toBe(inventory:GetQuantity(state, "Cure_Potion"), 0)
		end)

		Harness.it("capa la pila en MaxStack", function()
			local inventory = makeInventory()
			local state = newState()

			local maxStack = ItemCatalog.Get("Cure_Potion").MaxStack
			inventory:AddItem(state, "Cure_Potion", maxStack + 50, "shop")
			expect.toBe(inventory:GetQuantity(state, "Cure_Potion"), maxStack)
		end)

		Harness.it("la misma peticion NO anade dos veces", function()
			local inventory = makeInventory()
			local state = newState()

			inventory:AddItem(state, "Cure_Potion", 5, "shop", "req-1")
			inventory:AddItem(state, "Cure_Potion", 5, "shop", "req-1")
			expect.toBe(inventory:GetQuantity(state, "Cure_Potion"), 5)
		end)
	end)

	Harness.describe("Inventory: quitar y consumir", function()
		Harness.it("quita unidades", function()
			local inventory = makeInventory()
			local state = newState()

			inventory:AddItem(state, "Cure_Potion", 5, "shop")
			local ok = inventory:RemoveItem(state, "Cure_Potion", 2, "admin")
			expect.toBe(ok, true)
			expect.toBe(inventory:GetQuantity(state, "Cure_Potion"), 3)
		end)

		Harness.it("no deja la cantidad en cero", function()
			-- Una entrada con 0 aparece como "lo tiene" en algunos
			-- recorridos e infla el perfil guardado.
			local inventory = makeInventory()
			local state = newState()

			inventory:AddItem(state, "Cure_Potion", 1, "shop")
			inventory:RemoveItem(state, "Cure_Potion", 1, "admin")
			expect.toBe(state.Items.Cure_Potion, nil)
		end)

		Harness.it("no permite quedar en negativo", function()
			local inventory = makeInventory()
			local state = newState()

			inventory:AddItem(state, "Cure_Potion", 2, "shop")
			local ok = inventory:RemoveItem(state, "Cure_Potion", 5, "admin")
			expect.toBe(ok, false)
			expect.toBe(inventory:GetQuantity(state, "Cure_Potion"), 2)
		end)

		Harness.it("consume un consumible y lo gasta", function()
			local inventory = makeInventory()
			local state = newState()

			inventory:AddItem(state, "Cure_Potion", 2, "shop")
			local ok, definition = inventory:ConsumeItem(state, "Cure_Potion", "use")

			expect.toBe(ok, true)
			expect.toBe(definition.HealAmount, 50)
			expect.toBe(inventory:GetQuantity(state, "Cure_Potion"), 1)
		end)

		Harness.it("NO consume un item que no es consumible", function()
			-- Un sombrero no se "usa": se equipa. Si `ConsumeItem` lo
			-- admitiera, el jugador perderia su item usandolo dos veces.
			local inventory = makeInventory()
			local state = newState()

			inventory:AddItem(state, "Hat_Keshusy", 1, "shop")
			local ok = inventory:ConsumeItem(state, "Hat_Keshusy", "use")

			expect.toBe(ok, false)
			expect.toBe(inventory:GetQuantity(state, "Hat_Keshusy"), 1)
		end)
	end)

	Harness.describe("Inventory: seguridad (el caso de exploit)", function()
		Harness.it("NO usa un item que el jugador NO tiene", function()
			-- El cliente dice "quiero usar X" sin tener X. El servidor
			-- comprueba y NO ejecuta.
			local inventory = makeInventory()
			local state = newState()

			local ok = inventory:ConsumeItem(state, "Cure_Potion", "use")
			expect.toBe(ok, false)
			expect.toBe(inventory:GetQuantity(state, "Cure_Potion"), 0)
		end)

		Harness.it("NO equipa un item que el jugador NO tiene", function()
			-- Es el intento clasico: consigo un sombrero gratis.
			local inventory = makeInventory()
			local state = newState()

			local ok = inventory:EquipItem(state, "Hat_Keshusy")
			expect.toBe(ok, false)
			expect.toBe(inventory:GetEquipped(state).Head, nil)
		end)

		Harness.it("NO equipa un item inexistente", function()
			local inventory = makeInventory()
			local state = newState()

			expect.toBe((inventory:EquipItem(state, "Sombrero_Inventado")), false)
		end)

		Harness.it("NO equipa un item no equiparable", function()
			local inventory = makeInventory()
			local state = newState()

			inventory:AddItem(state, "Cure_Potion", 3, "shop")
			local ok = inventory:EquipItem(state, "Cure_Potion")
			expect.toBe(ok, false)
		end)
	end)

	Harness.describe("Inventory: equipar", function()
		Harness.it("equipa un item que posee", function()
			local inventory = makeInventory()
			local state = newState()

			inventory:AddItem(state, "Hat_Keshusy", 1, "shop")
			local ok = inventory:EquipItem(state, "Hat_Keshusy")

			expect.toBe(ok, true)
			expect.toBe(inventory:GetEquipped(state).Head, "Hat_Keshusy")
		end)

		Harness.it("una ranura tiene UN item", function()
			-- Dos sombreros a la vez no existen.
			local inventory = makeInventory()
			local state = newState()

			inventory:AddItem(state, "Hat_Keshusy", 1, "shop")
			inventory:AddItem(state, "Skin_Gold", 1, "shop")
			inventory:EquipItem(state, "Hat_Keshusy")
			inventory:EquipItem(state, "Skin_Gold")

			local equipped = inventory:GetEquipped(state)
			expect.toBe(equipped.Body, "Skin_Gold")
			expect.toBe(equipped.Head, "Hat_Keshusy")
		end)

		Harness.it("desequipar vacia la ranura pero conserva el item", function()
			local inventory = makeInventory()
			local state = newState()

			inventory:AddItem(state, "Hat_Keshusy", 1, "shop")
			inventory:EquipItem(state, "Hat_Keshusy")

			local ok = inventory:UnequipItem(state, "Head")
			expect.toBe(ok, true)
			expect.toBe(inventory:GetEquipped(state).Head, nil)
			expect.toBe(inventory:GetQuantity(state, "Hat_Keshusy"), 1)
		end)

		Harness.it("perder el item lo desequipa", function()
			-- Un item equipado que ya no existe no puede seguir "puesto".
			local inventory = makeInventory()
			local state = newState()

			inventory:AddItem(state, "Hat_Keshusy", 1, "shop")
			inventory:EquipItem(state, "Hat_Keshusy")
			inventory:RemoveItem(state, "Hat_Keshusy", 1, "admin")

			expect.toBe(inventory:GetEquipped(state).Head, nil)
		end)
	end)

	Harness.describe("Inventory: auditoria", function()
		Harness.it("un inventario sano no reporta anomalias", function()
			local inventory = makeInventory()
			local state = newState()

			inventory:AddItem(state, "Cure_Potion", 3, "shop")
			inventory:AddItem(state, "Hat_Keshusy", 1, "shop")
			inventory:EquipItem(state, "Hat_Keshusy")

			expect.toBe(#inventory:Audit(state), 0)
		end)

		Harness.it("detecta equipar algo que no se tiene", function()
			-- Asi se delata un perfil inyectado por un cliente.
			local inventory = makeInventory()
			local state = newState()

			state.Equipped.Head = "Hat_Keshusy"
			expect.toBe(#inventory:Audit(state) > 0, true)
		end)

		Harness.it("detecta un item que ya no existe en el catalogo", function()
			-- Se AVISA, no se borra: el jugador pago por ese item.
			local inventory = makeInventory()
			local state = newState()

			state.Items.Item_Retirado = { Quantity = 1 }
			expect.toBe(#inventory:Audit(state) > 0, true)
		end)

		Harness.it("detecta una cantidad imposible", function()
			local inventory = makeInventory()
			local state = newState()

			state.Items.Cure_Potion = { Quantity = -3 }
			expect.toBe(#inventory:Audit(state) > 0, true)
		end)
	end)
end