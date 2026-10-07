--!strict
--[[
	EquipmentRules.spec
	Equipamiento con estadisticas reales (MASTER MISSION V2 - FASE 29).

	Lo que se certifica aqui es la suma y el ACOTADO: el equipo modifica
	stats reales sin que apilar piezas salga de control, y cada pieza con
	stats existe y es equipable de verdad.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local Equipment = require("../../src/ReplicatedStorage/Shared/Libraries/EquipmentRules")
local Catalog = require("../../src/ReplicatedStorage/Shared/Config/ItemCatalog")

local function describeEquipmentRules()
	Harness.describe("Piezas con stats", function()
		Harness.it("cada pieza con stats existe, es equipable y NO es cosmetica", function()
			-- Una pieza de stats marcada como cosmetica es una mentira de
			-- catalogo: la tienda diria "solo estetica" y cambiaria el juego.
			local count = 0

			for _, itemId in ipairs(Catalog.GetAllIds()) do
				local def = Catalog.Get(itemId)

				if type(def.Stats) == "table" then
					count += 1
					expect.toBe(def.Equipable, true, ("%s con stats sin equipar"):format(itemId))
					expect.toBe(def.Cosmetic, false, ("%s con stats y cosmetica"):format(itemId))
				end
			end

			-- La FASE 29 pide que el equipo modifique algo real: un catalogo
			-- sin una sola pieza de stats es la promesa incumplida.
			expect.toBe(count >= 3, true, "no hay piezas de equipo con stats")
		end)

		Harness.it("las piezas de stats se compran con monedas, nunca con pago real", function()
			for _, itemId in ipairs(Catalog.GetAllIds()) do
				local def = Catalog.Get(itemId)

				if type(def.Stats) == "table" then
					expect.toBe(
						def.Currency == "Coins",
						true,
						("%s con stats se vende por %s"):format(itemId, tostring(def.Currency))
					)
				end
			end
		end)
	end)

	Harness.describe("Calculo", function()
		Harness.it("sin equipo no hay bonus", function()
			local stats = Equipment.ComputeStats({}, Catalog)

			expect.toBe(stats.WalkSpeedMult, 1)
			expect.toBe(stats.MaxHealthBonus, 0)
			expect.toBe(stats.AbilityCooldownMult, 1)
		end)

		Harness.it("las piezas se suman", function()
			local stats = Equipment.ComputeStats({ Feet = "Gear_SwiftBoots" }, Catalog)

			expect.toBe(stats.WalkSpeedMult > 1, true)
		end)

		Harness.it("los ids invalidos no aportan nada", function()
			local stats = Equipment.ComputeStats({ Head = "NoExiste" }, Catalog)

			expect.toBe(stats.WalkSpeedMult, 1)
			expect.toBe(stats.MaxHealthBonus, 0)
		end)

		Harness.it("los topes se respetan aunque las piezas se apilen", function()
			-- El catalogo no deja apilar ranuras, pero la regla no puede
			-- depender de eso: si manana hay cuatro ranuras, el tope sigue.
			local fake = {
				Get = function(_self, _id)
					return { Stats = { WalkSpeedMult = 0.5 } }
				end,
			}

			local stats = Equipment.ComputeStats({ A = "x", B = "x", C = "x", D = "x" }, fake)

			expect.toBe(stats.WalkSpeedMult <= Equipment.Caps.WalkSpeedMult.Max, true)
		end)

		Harness.it("una entrada rota no rompe el calculo", function()
			local stats = Equipment.ComputeStats(nil, nil)

			expect.toBe(stats.WalkSpeedMult, 1)
		end)
	end)
end

return describeEquipmentRules
