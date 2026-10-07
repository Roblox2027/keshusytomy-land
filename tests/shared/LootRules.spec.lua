--!strict
--[[
	LootRules.spec
	Drops de materiales por fuente (MASTER MISSION V2 - FASE 23/25).

	Lo que se certifica aqui es la TABLA: que los materiales existen en el
	catalogo, que cada mundo suelta el suyo y que la distribucion de la
	tirada es la declarada (recorriendo el rango, no rezando al azar).
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local Loot = require("../../src/ReplicatedStorage/Shared/Libraries/LootRules")
local Catalog = require("../../src/ReplicatedStorage/Shared/Config/ItemCatalog")
local Access = require("../../src/ReplicatedStorage/Shared/Libraries/WorldAccessRules")

local function describeLootRules()
	Harness.describe("Materiales", function()
		Harness.it("todo material de la tabla existe en el catalogo", function()
			-- Un drop de un id inventado NO da error al tirar: da un drop
			-- que `InventoryService.AddItem` rechaza en silencio. Es el
			-- peor fallo posible porque el jugador ve "DROP" y no recibe nada.
			for _, itemId in ipairs(Loot.GetMaterialIds()) do
				expect.toBe(
					Catalog.Has(itemId),
					true,
					("material inexistente en el catalogo: %s"):format(itemId)
				)
			end
		end)

		Harness.it("ningun material se VENDE en la tienda", function()
			-- Un material comprable convierte el drop en irrelevante.
			for _, itemId in ipairs(Loot.GetMaterialIds()) do
				local def = Catalog.Get(itemId)

				expect.toBe(
					def.Available == false,
					true,
					("%s se vende: el drop deja de tener sentido"):format(itemId)
				)
			end
		end)

		Harness.it("todo mundo jugable tiene material propio", function()
			for _, worldId in ipairs(Access.GetWorldIds()) do
				expect.toBe(
					Loot.MaterialForWorld[worldId] ~= nil,
					true,
					("%s sin material"):format(worldId)
				)
			end
		end)
	end)

	Harness.describe("Tirada de monstruo", function()
		Harness.it("cae solo cuando la tirada lo dice", function()
			local steps = 1000
			local hits = 0

			for i = 0, steps do
				local itemId = Loot.RollMonsterDrop("Forest", i / steps, 0.5)

				if itemId then
					hits += 1
					expect.toBe(itemId, "Mat_LeafEssence")
				end
			end

			local ratio = hits / steps

			-- 15 % declarado: la cuenta tiene que CAER cerca, no en "a veces".
			expect.toBe(ratio > 0.10 and ratio < 0.20, true, ("ratio %.2f"):format(ratio))
		end)

		Harness.it("un mundo sin material no suelta nada", function()
			local itemId, amount = Loot.RollMonsterDrop("NoExiste", 0.0, 0.0)

			expect.toBe(itemId, nil)
			expect.toBe(amount, 0)
		end)

		Harness.it("una tirada invalida no suelta nada", function()
			expect.toBe((Loot.RollMonsterDrop("Forest", nil, 0.5)), nil)
			expect.toBe((Loot.RollMonsterDrop("Forest", 0 / 0, 0.5)), nil)
		end)
	end)

	Harness.describe("Mini-boss y boss", function()
		Harness.it("el mini-boss SIEMPRE suelta", function()
			-- Es la promesa de "este bicho vale la pena": un mini-boss que
			-- no suelta nada es un saco de vida con nombre.
			for _, worldId in ipairs(Access.GetWorldIds()) do
				local itemId, amount = Loot.RollMiniBossDrop(worldId, 0.99)

				expect.toBe(itemId ~= nil, true, ("%s: miniboss sin drop"):format(worldId))
				expect.toBe(amount >= Loot.MiniBoss.BaseAmount, true)
			end
		end)

		Harness.it("la tirada doble dobla", function()
			local _, single = Loot.RollMiniBossDrop("Forest", 0.99)
			local _, double = Loot.RollMiniBossDrop("Forest", 0.0)

			expect.toBe(double, single * 2)
		end)

		Harness.it("el boss siempre suelta material raro y gemas", function()
			local itemId, amount, gems = Loot.RollBossDrop("Volcano")

			expect.toBe(itemId, "Mat_EmberCore")
			expect.toBe(amount, Loot.Boss.Amount)
			expect.toBe(gems > 0, true, "el boss no suelta gemas")
		end)
	end)
end

return describeLootRules
