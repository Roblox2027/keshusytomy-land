--!strict
--[[
	PvpRules.spec
	Aritmetica del modo PvP: equilibrio de equipos y caja de la arena.

	Lo que se certifica es que la decision de "a que equipo entro" y "estoy
	dentro o fuera" es estable y no depende del motor. La aplicacion real del
	dano y el teletransporte las prueba el playtest.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local Pvp = require("../../src/ReplicatedStorage/Shared/Libraries/PvpRules")

-- Las posiciones son tablas `{X, Z}`, igual que en `CombatRules.spec`: las
-- funciones van por campos a proposito para no depender del `Vector3` del motor.
local function v(x: number, z: number)
	return { X = x, Y = 0, Z = z }
end

local function describePvpRules()
	Harness.describe("Equilibrio de equipos", function()
		Harness.it("con la arena vacia se entra al A", function()
			-- Regla determinista en el empate: si no, dos servidores
			-- balancearian distinto el mismo estado.
			expect.toBe(Pvp.AssignTeam(0, 0), "A")
		end)

		Harness.it("va al bando con menos gente", function()
			-- El objetivo del PvP es el duelo, no la emboscada: 1 contra 2 no
			-- se convierte en 1 contra 3.
			expect.toBe(Pvp.AssignTeam(3, 1), "B")
			expect.toBe(Pvp.AssignTeam(1, 3), "A")
		end)

		Harness.it("con empate reparte al A", function()
			expect.toBe(Pvp.AssignTeam(2, 2), "A")
		end)

		Harness.it("una cuenta corrupta no rompe el reparto", function()
			-- Un nil o un texto no debe cascar el arranque de la ronda. Un
			-- valor ilegible cuenta como 0, asi que (nil, 5) deja A como el
			-- bando con menos gente y entra al A.
			expect.toBe(Pvp.AssignTeam(nil, 5), "A")
			expect.toBe(Pvp.AssignTeam("x", "y"), "A")
		end)
	end)

	Harness.describe("Fuego amigo en la arena", function()
		-- El duelo es POR EQUIPOS: la bomba o el golpe de un companero de
		-- bando no puede bajarte la vida. `CombatService.ApplyDamage` consume
		-- esta regla; aqui se certifica que la decision es la correcta.
		Harness.it("dos jugadores del mismo equipo son fuego amigo", function()
			expect.toBe(Pvp.IsFriendlyFire("A", "A"), true)
			expect.toBe(Pvp.IsFriendlyFire("B", "B"), true)
		end)

		Harness.it("equipos distintos NO son fuego amigo", function()
			expect.toBe(Pvp.IsFriendlyFire("A", "B"), false)
			expect.toBe(Pvp.IsFriendlyFire("B", "A"), false)
		end)

		Harness.it("sin equipo en uno de los dos no hay fuego amigo", function()
			-- nil es el caso real de quien aun no entro o ya salio de la arena:
			-- la decision de danar la toma `ApplyDamage` con PvP/ronda, no aqui.
			expect.toBe(Pvp.IsFriendlyFire(nil, "A"), false)
			expect.toBe(Pvp.IsFriendlyFire("A", nil), false)
			expect.toBe(Pvp.IsFriendlyFire(nil, nil), false)
		end)

		Harness.it("un equipo vacio no cuenta como bando", function()
			expect.toBe(Pvp.IsFriendlyFire("", ""), false)
			expect.toBe(Pvp.IsFriendlyFire("", "A"), false)
		end)

		Harness.it("un equipo que no es texto no rompe la regla", function()
			expect.toBe(Pvp.IsFriendlyFire(1, 1), false)
			expect.toBe(Pvp.IsFriendlyFire(true, true), false)
		end)
	end)

	Harness.describe("Caja de la arena", function()
		local center = v(0, 82)
		local half = { X = 33, Y = 0, Z = 23 }

		Harness.it("el centro esta dentro", function()
			expect.toBe(Pvp.IsInsideArena(center, center, half), true)
		end)

		Harness.it("las esquinas justas cuentan como dentro", function()
			-- El borde es dentro: quien apoya un pie en la linea sigue en la
			-- arena y sigue en PvP.
			expect.toBe(Pvp.IsInsideArena(v(33, 105), center, half), true)
			expect.toBe(Pvp.IsInsideArena(v(-33, 59), center, half), true)
		end)

		Harness.it("un paso fuera de la caja ya esta fuera", function()
			-- Salir apaga el modo PvP (ver `CombatService`): el lobby vuelve a
			-- ser zona segura en cuanto cruzas el muro.
			expect.toBe(Pvp.IsInsideArena(v(34, 105), center, half), false)
			expect.toBe(Pvp.IsInsideArena(v(0, 120), center, half), false)
		end)
	end)

	Harness.describe("Marcador de entrada", function()
		local entry = v(0, 56)

		Harness.it("detecta al que pisa la entrada", function()
			expect.toBe(Pvp.IsNear(v(0, 58), entry, 6), true)
		end)

		Harness.it("ignora al que pasa de largo", function()
			expect.toBe(Pvp.IsNear(v(0, 90), entry, 6), false)
		end)

		Harness.it("un radio invalido no atrae a todo el mapa", function()
			expect.toBe(Pvp.IsNear(v(500, 500), entry, -1), false)
		end)
	end)

	Harness.describe("Marcador de kills", function()
		Harness.it("sin kills dice que no hay nada aun", function()
			expect.toBe(Pvp.FormatScoreboard({}), "Sin kills aun")
			expect.toBe(Pvp.FormatScoreboard({ { Name = "A", Kills = 0 } }), "Sin kills aun")
		end)

		Harness.it("ordena por kills descendente", function()
			local text = Pvp.FormatScoreboard({
				{ Name = "Ana", Kills = 1 },
				{ Name = "Beto", Kills = 5 },
				{ Name = "Cara", Kills = 3 },
			})
			-- La primera linea es la de mas kills; el marcador es la razon de
			-- competir, asi que el lider va arriba.
			expect.toContain(text, "1. Beto")
			local betoLine = string.find(text, "Beto") or 0
			local anaLine = string.find(text, "Ana") or 0
			expect.toBe(betoLine < anaLine, true)
		end)

		Harness.it("a igualdad de kills ordena por nombre (determinista)", function()
			local text = Pvp.FormatScoreboard({
				{ Name = "Zeta", Kills = 2 },
				{ Name = "Alfa", Kills = 2 },
			})
			local alfaLine = string.find(text, "Alfa") or 0
			local zetaLine = string.find(text, "Zeta") or 0
			expect.toBe(alfaLine < zetaLine, true)
		end)

		Harness.it("acota a 5 filas aunque haya mas", function()
			local entries = {}
			for i = 1, 12 do
				table.insert(entries, { Name = ("P%02d"):format(i), Kills = i })
			end
			local text = Pvp.FormatScoreboard(entries)
			local lines = 1
			for _ in string.gmatch(text, "\n") do
				lines += 1
			end
			expect.toBe(lines, 5)
		end)

		Harness.it("ignora entradas corruptas sin cascar", function()
			-- OJO: NO se pone un `nil` literal en medio del array. En Lua eso
			-- hace que `ipairs` se detenga ahi, y dejaria de probar lo que se
			-- quiere (que una basura suelta no rompa el formato). `GetChildren`
			-- nunca devuelve huecos: la basura realista es un string u otra
			-- tabla sin los campos.
			local text = Pvp.FormatScoreboard({
				{ Name = "Ana", Kills = 3 },
				"basura",
				42,
				{ Name = "Beto", Kills = 1 },
			})
			expect.toContain(text, "Ana")
			expect.toContain(text, "Beto")
		end)
	end)

	Harness.describe("Killfeed", function()
		Harness.it("nombra a quien elimino y a quien cayo", function()
			local text = Pvp.FormatKillLine("Ana", "Beto")
			expect.toContain(text, "Ana")
			expect.toContain(text, "Beto")
			expect.toContain(text, "elimino a")
		end)

		Harness.it("un nombre ausente no deja la linea vacia", function()
			expect.toContain(Pvp.FormatKillLine(nil, "Beto"), "Beto")
			expect.toContain(Pvp.FormatKillLine("Ana", nil), "Ana")
		end)
	end)
end

return describePvpRules
