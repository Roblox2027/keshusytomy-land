--!strict
--[[
	PuzzleRules.spec
	Puzzles cortos y secretos cooperativos (MASTER MISSION V2 - FASES 13/14).

	Lo que se certifica aqui es la ventana y el cooldown: el doble
	interruptor es posible para un jugador solo (ventana generosa) y no es
	farmeable (cooldown largo).
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local Puzzle = require("../../src/ReplicatedStorage/Shared/Libraries/PuzzleRules")

local function describePuzzleRules()
	Harness.describe("Ventana de activacion", function()
		Harness.it("abierta dentro de la ventana, cerrada fuera", function()
			expect.toBe(Puzzle.IsWindowOpen(100, 100 + Puzzle.WindowSeconds - 0.1), true)
			expect.toBe(Puzzle.IsWindowOpen(100, 100 + Puzzle.WindowSeconds + 0.1), false)
		end)

		Harness.it("sin primera activacion no hay ventana", function()
			expect.toBe(Puzzle.IsWindowOpen(nil, 100), false)
		end)

		Harness.it("un reloj invalido no abre nada", function()
			expect.toBe(Puzzle.IsWindowOpen(100, "tarde"), false)
			expect.toBe(Puzzle.IsWindowOpen(100, 0 / 0), false)
		end)

		Harness.it("la ventana permite hacerlo SOLO, sin obligar a ello", function()
			-- La regla de la FASE 13: nada del progreso principal exige otro
			-- jugador. Una ventana de menos de 4 s haria el viaje imposible
			-- para uno solo; mas de 15 no seria un puzzle.
			expect.toBe(Puzzle.WindowSeconds >= 4, true)
			expect.toBe(Puzzle.WindowSeconds <= 15, true)
		end)
	end)

	Harness.describe("Cooldown anti-granja", function()
		Harness.it("cumplido al principio y tras esperar", function()
			expect.toBe(Puzzle.IsOffCooldown(nil, 100), true)
			expect.toBe(Puzzle.IsOffCooldown(100, 100 + Puzzle.CooldownSeconds), true)
		end)

		Harness.it("recien completado no se repite", function()
			expect.toBe(Puzzle.IsOffCooldown(100, 100), false)
		end)

		Harness.it("el cooldown es LARGO", function()
			-- Un puzzle que se repite cada 10 segundos es una fuente de
			-- monedas infinita con pasos extra.
			expect.toBe(Puzzle.CooldownSeconds >= 120, true)
		end)
	end)
end

return describePuzzleRules
