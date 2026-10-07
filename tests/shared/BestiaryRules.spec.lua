--!strict
--[[
	BestiaryRules.spec
	Coleccion de especies (MASTER MISSION V2 - FASE 20).

	Lo que se certifica aqui es la contabilidad de la coleccion: primera
	baja = descubrimiento, rareza funcional deducida de la definicion y
	completitud medible.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local Bestiary = require("../../src/ReplicatedStorage/Shared/Libraries/BestiaryRules")
local Monsters = require("../../src/ReplicatedStorage/Shared/MonsterDefinitions")

local function describeBestiaryRules()
	Harness.describe("Rareza funcional", function()
		Harness.it("un boss es Legendario", function()
			expect.toBe(Bestiary.RarityOf(Monsters.Get("ForestGrooty")), "Legendary")
		end)

		Harness.it("un mini-boss sube de rareza y la fauna es comun", function()
			expect.toBe(Bestiary.RarityOf(Monsters.Get("ForestAcechador")), "Epic")
			expect.toBe(Bestiary.RarityOf(Monsters.Get("Slime")), "Common")
		end)

		Harness.it("una definicion rota no rompe la rareza", function()
			expect.toBe(Bestiary.RarityOf(nil), "Common")
			expect.toBe(Bestiary.RarityOf({}), "Common")
		end)
	end)

	Harness.describe("Registro de bajas", function()
		Harness.it("la primera baja es descubrimiento, la segunda no", function()
			local state = { Species = {} }

			local isNew, kills = Bestiary.RecordKill(state, "Slime")
			expect.toBe(isNew, true)
			expect.toBe(kills, 1)

			local isNew2, kills2 = Bestiary.RecordKill(state, "Slime")
			expect.toBe(isNew2, false)
			expect.toBe(kills2, 2)
		end)

		Harness.it("una entrada rota no rompe el registro", function()
			expect.toBe(Bestiary.RecordKill(nil, "Slime"), false)
			expect.toBe(Bestiary.RecordKill({ Species = {} }, nil), false)
			expect.toBe(Bestiary.RecordKill({ Species = {} }, ""), false)
		end)
	end)

	Harness.describe("Completitud", function()
		Harness.it("cuenta especies distintas, no bajas", function()
			local state = { Species = {} }

			Bestiary.RecordKill(state, "Slime")
			Bestiary.RecordKill(state, "Slime")
			Bestiary.RecordKill(state, "Hunter")

			expect.toBe(Bestiary.CountDiscovered(state), 2)
		end)

		Harness.it("la ratio esta acotada y nunca inventa", function()
			expect.toBe(Bestiary.CompletionRatio(nil, 10), 0)
			expect.toBe(Bestiary.CompletionRatio({ Species = {} }, 0), 0)

			local state = { Species = {} }
			Bestiary.RecordKill(state, "Slime")

			expect.toBe(Bestiary.CompletionRatio(state, 4), 0.25)
		end)
	end)
end

return describeBestiaryRules
