--!strict
--[[
	RoundScalingRules.spec
	Dificultad progresiva por ronda: cada ronda trae mas monstruos.

	LO QUE SE CERTIFICA
	-------------------
	Este modulo es la curva de "la partida se pone mas dura". Las propiedades que
	lo hacen correcto son las mismas que las de `DifficultyRules`, y se comprueban
	igual, recorriendo el rango y no un par de casos:

	  1. MONOTONIA: mas ronda NUNCA da menos monstruos. Una ronda alta que
	     devuelve menos es un bug, y el jugador no puede aprender una curva que
	     baja.
	  2. LA PRIMERA RONDA ES LA BASE: la ronda 1 no suma bonus. El jugador entra,
	     se situa y aprende el mapa sin seis enemigos encima.
	  3. TOPES: el objetivo nunca supera `AbsoluteMax`, y el bonus nunca supera
	     `MaxBonus`. Crecer sin techo es el bug que este codebase persigue.
	  4. `AbsoluteMax` POR DEBAJO DEL GLOBAL: deja hueco en `MaxMonsters` para el
	     boss y las hordas.
	  5. ENTRADAS CORRUPTAS: un round invalido se trata como ronda 1, no concede
	     bonus por un numero basura.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local Rules = require("../../src/ReplicatedStorage/Shared/Libraries/RoundScalingRules")

local function describeRoundScaling()
	Harness.describe("Bonus por ronda", function()
		Harness.it("la primera ronda no suma nada", function()
			expect.toBe(Rules.BonusFor(1), 0)
		end)

		Harness.it("crece de forma escalonada", function()
			-- +PerRoundBonus por cada ronda por encima de la primera.
			expect.toBe(Rules.BonusFor(2), Rules.PerRoundBonus)
			expect.toBe(Rules.BonusFor(3), Rules.PerRoundBonus * 2)
		end)

		Harness.it("el bonus nunca supera su tope", function()
			-- Ronda muy alta: el bonus se acota y se mantiene.
			expect.toBe(Rules.BonusFor(999), Rules.MaxBonus)
			expect.toBe(Rules.BonusFor(10000), Rules.MaxBonus)
		end)

		Harness.it("una entrada corrupta vale como primera ronda", function()
			-- No se concede bonus por un numero invalido.
			expect.toBe(Rules.BonusFor(nil), 0)
			expect.toBe(Rules.BonusFor(0), 0)
			expect.toBe(Rules.BonusFor(-5), 0)
			expect.toBe(Rules.BonusFor(0 / 0), 0)
			expect.toBe(Rules.BonusFor("tres"), 0)
		end)
	end)

	Harness.describe("Objetivo de poblacion", function()
		local base = 6

		Harness.it("la primera ronda es la poblacion base exacta", function()
			expect.toBe(Rules.SpawnTarget(base, 1), base)
		end)

		Harness.it("crece respecto a la base", function()
			expect.toBe(Rules.SpawnTarget(base, 5) > base, true)
		end)

		Harness.it("nunca supera el tope absoluto", function()
			-- Base grande + ronda enorme: se acota a `AbsoluteMax`.
			expect.toBe(Rules.SpawnTarget(base, 9999) <= Rules.AbsoluteMax, true)
			expect.toBe(Rules.SpawnTarget(1000, 9999), Rules.AbsoluteMax)
		end)

		Harness.it("una base corrupta no rompe el objetivo", function()
			expect.toBe(Rules.SpawnTarget(nil, 1), Rules.BonusFor(1))
			expect.toBe(Rules.SpawnTarget(-3, 1), 0)
		end)
	end)

	Harness.describe("Monotonia (recorrido)", function()
		Harness.it("mas ronda nunca da menos monstruos", function()
			-- Recorrer un rango y no un caso: una curva que baja en algun punto es
			-- un bug que el jugador nota y no puede aprender.
			local previous = 0

			for round = 1, 120 do
				local target = Rules.SpawnTarget(8, round)
				expect.toBe(target >= previous, true)
				previous = target
			end
		end)

		Harness.it("el objetivo deja de empinar y se mantiene", function()
			-- La curva se aplana cuando el bonus llega a su tope: con base 8 y
			-- bonus maximo 10, el techo real es 18 (NO `AbsoluteMax`, que solo
			-- actuaria con bases mas grandes). Se comprueba que SE MANTIENE, que
			-- es la propiedad que importa, y que jamas baja.
			local plateau = 8 + Rules.MaxBonus
			expect.toBe(Rules.SpawnTarget(8, 120), plateau)
			expect.toBe(Rules.SpawnTarget(8, 9999), plateau)
			expect.toBe(plateau <= Rules.AbsoluteMax, true)
		end)
	end)

	Harness.describe("Topes frente a los del servidor", function()
		Harness.it("el tope absoluto deja hueco para boss y hordas", function()
			-- `PerformanceConfig.Limits.MaxMonsters` es 30. El escalado se queda
			-- por debajo a proposito para no acaparar el global con la poblacion
			-- base. Se compara contra el limite real importado.
			local PerformanceConfig = require("../../src/ReplicatedStorage/Shared/Config/PerformanceConfig")
			expect.toBe(Rules.AbsoluteMax < PerformanceConfig.Limits.MaxMonsters, true)
		end)
	end)
end

return describeRoundScaling
