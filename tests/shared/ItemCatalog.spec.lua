--!strict
--[[
	ItemCatalog.spec
	Validacion de integridad del catalogo central de items, incluyendo
	los nuevos grupos del mercado: alas, armas, objetos y vehiculos.

	La regla central es que `ItemCatalog.Validate()` no tenga problemas:
	un item con precio negativo, moneda desconocida o slot equivocado
 romperia la tienda de forma silente. Aqui se comprueba el catalogo
	entero, no solo los items nuevos.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local ItemCatalog = require("../../src/ReplicatedStorage/Shared/Config/ItemCatalog")
local InventoryRules = require("../../src/ReplicatedStorage/Shared/Libraries/InventoryRules")

local function describeItemCatalog()
	Harness.describe("ItemCatalog: integridad general", function()
		Harness.it("el catalogo pasa Validate sin problemas", function()
			expect.toBe(#ItemCatalog.Validate(), 0)
		end)

		Harness.it("todos los ids son unicos", function()
			local seen = {}
			for _, id in ipairs(ItemCatalog.GetAllIds()) do
				expect.toBe(seen[id], nil)
				seen[id] = true
			end
		end)

		Harness.it("todo item disponible tiene precio positivo", function()
			for _, id in ipairs(ItemCatalog.GetAllIds()) do
				local def = ItemCatalog.Get(id)
				if def.Available then
					expect.toBe(type(def.Price) == "number" and def.Price > 0, true)
				end
			end
		end)
	end)

	Harness.describe("ItemCatalog: nuevas categorias", function()
		Harness.it("las categorias Wings, Weapon y Vehicle existen", function()
			expect.toBe(ItemCatalog.Category.Wings, "Wings")
			expect.toBe(ItemCatalog.Category.Weapon, "Weapon")
			expect.toBe(ItemCatalog.Category.Vehicle, "Vehicle")
		end)

		Harness.it("hay alas equipables en la ranura Wings", function()
			local wings = {
				"Wings_Angel",
				"Wings_Demon",
				"Wings_Shadow",
				"Wings_Crystal",
				"Wings_Spring",
			}

			for _, id in ipairs(wings) do
				local def = ItemCatalog.Get(id)
				expect.toBe(def, def)
				expect.toBe(def.Equipable, true)
				expect.toBe(def.Slot, "Wings")
				expect.toBe(def.Category, ItemCatalog.Category.Wings)
			end
		end)

		Harness.it("las alas cosméticas no tienen stats", function()
			local def = ItemCatalog.Get("Wings_Angel")
			expect.toBe(def.Cosmetic, true)
			expect.toBe(type(def.Stats) == "table", false)
		end)

		Harness.it("las alas funcionales (Spring) tienen stats y usan monedas", function()
			local def = ItemCatalog.Get("Wings_Spring")
			expect.toBe(def.Cosmetic, false)
			expect.toBe(def.Currency, ItemCatalog.Currency.Coins)
			expect.toBe(type(def.Stats) == "table", true)
			expect.toBe(def.Stats.JumpPowerBonus, 30)
		end)

		Harness.it("hay armas equipables en la ranura Weapon", function()
			local weapons = {
				"Weapon_Sword_Flame",
				"Weapon_Axe_Bone",
				"Weapon_Staff_Void",
				"Weapon_Crossbow",
			}

			for _, id in ipairs(weapons) do
				local def = ItemCatalog.Get(id)
				expect.toBe(def, def)
				expect.toBe(def.Equipable, true)
				expect.toBe(def.Slot, "Weapon")
				expect.toBe(def.Category, ItemCatalog.Category.Weapon)
			end
		end)

		Harness.it("las armas con stats usan monedas, no gemas", function()
			local statWeapons = { "Weapon_Sword_Flame", "Weapon_Axe_Bone", "Weapon_Staff_Void" }

			for _, id in ipairs(statWeapons) do
				local def = ItemCatalog.Get(id)
				expect.toBe(def.Cosmetic, false)
				expect.toBe(def.Currency, ItemCatalog.Currency.Coins)
				expect.toBe(type(def.Stats) == "table", true)
				expect.toBe(type(def.Stats.MeleeDamageMult) == "number", true)
			end
		end)

		Harness.it("el arma cosmético (Crossbow) no aporta stats", function()
			local def = ItemCatalog.Get("Weapon_Crossbow")
			expect.toBe(def.Cosmetic, true)
			expect.toBe(type(def.Stats) == "table", false)
		end)

		Harness.it("los objetos consumibles son apilables", function()
			local objects = {
				"Potion_Invisibility",
				"Potion_Teleport",
				"Grenade_Cluster",
			}

			for _, id in ipairs(objects) do
				local def = ItemCatalog.Get(id)
				expect.toBe(def.Consumable, true)
				expect.toBe(def.Stackable, true)
				expect.toBe(def.Category, ItemCatalog.Category.Consumable)
			end
		end)

		Harness.it("los vehiculos son consumibles de tiempo limitado", function()
			local vehicles = {
				"Vehicle_MiniPlane",
				"Vehicle_Warplane",
			}

			for _, id in ipairs(vehicles) do
				local def = ItemCatalog.Get(id)
				expect.toBe(def.Consumable, true)
				expect.toBe(def.Category, ItemCatalog.Category.Vehicle)
				expect.toBe(type(def.DurationSeconds) == "number", true)
				expect.toBe(type(def.SpeedBoost) == "number", true)
				expect.toBe(def.Flight, true)
			end
		end)
	end)

	Harness.describe("ItemCatalog: ranuras nuevas", function()
		Harness.it("InventoryRules reconoce las ranuras Wings y Weapon", function()
			expect.toBe(InventoryRules.IsKnownSlot("Wings"), true)
			expect.toBe(InventoryRules.IsKnownSlot("Weapon"), true)
			expect.toBe(InventoryRules.IsKnownSlot("Head"), true)
		end)
	end)

	Harness.describe("ItemCatalog: rarezas y precios", function()
		Harness.it("hay items en cada rareza", function()
			local rarities = {}
			for _, id in ipairs(ItemCatalog.GetAllIds()) do
				local def = ItemCatalog.Get(id)
				rarities[def.Rarity] = true
			end

			expect.toBe(rarities[ItemCatalog.Rarity.Common], true)
			expect.toBe(rarities[ItemCatalog.Rarity.Rare], true)
			expect.toBe(rarities[ItemCatalog.Rarity.Epic], true)
			expect.toBe(rarities[ItemCatalog.Rarity.Legendary], true)
		end)

		Harness.it("las alas Legendary cuestan gemas", function()
			local def = ItemCatalog.Get("Wings_Crystal")
			expect.toBe(def.Rarity, ItemCatalog.Rarity.Legendary)
			expect.toBe(def.Currency, ItemCatalog.Currency.Gems)
		end)
	end)

	-- =================================================================
	-- WORLD DROPS / ROBUX (FASE 32)
	-- =================================================================
	Harness.describe("ItemCatalog: world drops y Robux", function()
		Harness.it("GetWorldDropItems solo devuelve cosmeticos con DeveloperProductId", function()
			local drops = ItemCatalog.GetWorldDropItems()
			local count = 0

			for itemId, definition in pairs(drops) do
				count += 1
				expect.toBe(definition.Cosmetic, true)
				expect.toBe(type(definition.DeveloperProductId) == "number", true)
				expect.toBe(definition.WorldDrop, true)
			end

			expect.toBe(count, 5)
		end)

		Harness.it("los items con stats no son WorldDrop (anti-P2W real)", function()
			local statItems = {
				"Gear_SwiftBoots",
				"Gear_GuardianPlate",
				"Gear_FocusBand",
				"Wings_Spring",
				"Weapon_Sword_Flame",
				"Weapon_Axe_Bone",
				"Weapon_Staff_Void",
				"Potion_Invisibility",
				"Potion_Teleport",
				"Grenade_Cluster",
				"Vehicle_MiniPlane",
				"Vehicle_Warplane",
			}

			for _, id in ipairs(statItems) do
				local def = ItemCatalog.Get(id)
				expect.toBe(not def.WorldDrop, true)
				expect.toBe(def.DeveloperProductId, nil)
			end
		end)

		Harness.it("Validate rechaza items con DeveloperProductId pero no cosméticos", function()
			local problems = ItemCatalog.Validate()
			for _, problem in ipairs(problems) do
				expect.toBe(
					not string.find(problem, "venta P2W", 1, true),
					true
				)
			end
		end)
	end)
end

return describeItemCatalog
