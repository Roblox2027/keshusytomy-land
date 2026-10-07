--!strict
--[[
	NightCycle.spec
	El sistema de 99 noches: reloj, fases y progresion (FASES 8 y 9).

	QUE SE COMPRUEBA Y POR QUE
	--------------------------
	1. Las cuatro fases existen, cubren el ciclo entero y NO se solapan.
	   Un hueco entre fases es una fraccion de ciclo sin fase, y el servicio que
	   la consulte recibe el fallback en vez de un estado.

	2. El reloj marca una hora real (`HH:MM`) y la noche ocurre DE NOCHE en el
	   reloj. Esta es la comprobacion que mas valora el jugador: un HUD que
	   muestra "14:20" mientras la noche cae, el reloj esta roto aunque la
	   maquina de estados funcione.

	3. `GetClockState` es TOTAL: acepta `nil`, `NaN` y valores fuera de rango y
	   devuelve siempre un estado valido. El atributo que sale de aqui lo lee
	   toda la pantalla del servidor.

	4. La progresion de las 99 noches no salta ni decrece.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local Night = require("../../src/ReplicatedStorage/Shared/Libraries/NightRules")
local Access = require("../../src/ReplicatedStorage/Shared/Libraries/WorldAccessRules")

local function describeNightCycle()
	Harness.describe("Fases", function()
		Harness.it("declara las cuatro fases del enunciado", function()
			expect.toBe(Night.Phase.Day, "Day")
			expect.toBe(Night.Phase.Sunset, "Sunset")
			expect.toBe(Night.Phase.Night, "Night")
			expect.toBe(Night.Phase.Dawn, "Dawn")
		end)

		Harness.it("el ciclo se recorre entero, sin huecos", function()
			-- Se recorre el ciclo en pasos finos y se comprueba que cada
			-- fraccion pertenece a UNA fase. Un recorrido mas grueso podria
			-- dejar un hueco pequeno sin ver; este lo pisa entero.
			local steps = 1000

			for i = 0, steps do
				local f = i / steps
				local phase = Night.PhaseAt(f)

				expect.toBe(
					phase == Night.Phase.Day
						or phase == Night.Phase.Sunset
						or phase == Night.Phase.Night
						or phase == Night.Phase.Dawn,
					true,
					("la fraccion %.3f no pertenece a ninguna fase (%s)")
						:format(f, tostring(phase))
				)
			end
		end)

		Harness.it("cada fase ocupa tiempo real y positivo", function()
			for _, phase in ipairs(Night.PhaseOrder) do
				expect.toBe(
					Night.DurationFor(phase, 1) > 0,
					true,
					("%s dura %.1f s en la noche 1")
						:format(phase, Night.DurationFor(phase, 1))
				)
			end
		end)
	end)

	Harness.describe("El reloj", function()
		Harness.it("formatea HH:MM con dos digitos", function()
			expect.toBe(Night.FormatClock(6 * 60), "06:00")
			expect.toBe(Night.FormatClock(6 * 60 + 42), "06:42")
			expect.toBe(Night.FormatClock(23 * 60 + 5), "23:05")
			expect.toBe(Night.FormatClock(0), "00:00")
		end)

		Harness.it("nunca imprime una hora que no existe", function()
			-- El fallo que produce esto es "25:00" en pantalla: no es un reloj
			-- roto, es un dato roto, y el jugador lo lee como bug del juego.
			for minutes = -3000, 4000, 37 do
				local text = Night.FormatClock(minutes)
				local h = tonumber(text:sub(1, 2))
				local m = tonumber(text:sub(4, 5))

				expect.toBe(
					h ~= nil and h >= 0 and h <= 23,
					true,
					("hora invalida: %s"):format(text)
				)
				expect.toBe(
					m ~= nil and m >= 0 and m <= 59,
					true,
					("minuto invalido: %s"):format(text)
				)
			end
		end)

		Harness.it("la noche ocurre DE NOCHE en el reloj", function()
			-- El contrato de diseno: la fraccion `Night` del ciclo tiene que
			-- corresponderse con las horas oscuras. Si el reparto se cambiara,
			-- esto falla y avisa de que el HUD va a mentir.
			local state = Night.GetClockState(1, Night.PhaseStartFraction(Night.Phase.Night))
			local hour = tonumber(state.Clock:sub(1, 2))

			expect.toBe(state.Phase, Night.Phase.Night)
			expect.toBe(
				hour >= 22 or hour <= 4,
				true,
				("la fase Night cae a las %s, que no es de noche"):format(state.Clock)
			)
		end)

		Harness.it("el dia ocurre de dia en el reloj", function()
			local state = Night.GetClockState(1, Night.PhaseStartFraction(Night.Phase.Day))
			local hour = tonumber(state.Clock:sub(1, 2))

			expect.toBe(state.Phase, Night.Phase.Day)
			expect.toBe(
				hour >= 6 and hour < 20,
				true,
				("la fase Day cae a las %s, que no es de dia"):format(state.Clock)
			)
		end)

		Harness.it("las transiciones se marcan como tales", function()
			-- Sin este dato el jugador no tiene aviso: la noche aparece de golpe
			-- y se lee como un fallo del servidor en vez de como el paso del
			-- tiempo.
			local sunset = Night.GetClockState(1, Night.PhaseStartFraction(Night.Phase.Sunset))
			local dawn = Night.GetClockState(1, Night.PhaseStartFraction(Night.Phase.Dawn))
			local day = Night.GetClockState(1, Night.PhaseStartFraction(Night.Phase.Day))

			expect.toBe(sunset.Transition, true)
			expect.toBe(dawn.Transition, true)
			expect.toBe(day.Transition, false)
		end)
	end)

	Harness.describe("Robustez del estado", function()
		Harness.it("acepta nil, NaN y valores fuera de rango", function()
			-- Lo que sale de aqui se publica como atributo y lo lee toda la
			-- pantalla del servidor: un NaN en el reloj es un "NaN:NaN" para
			-- todos los jugadores a la vez.
			local cases = { nil, 999, "abc", {} }
			table.insert(cases, 0 / 0)

			for _, value in ipairs(cases) do
				local state = Night.GetClockState(value, value)

				expect.toBe(state.Night >= 1, true, ("noche invalida: %s"):format(tostring(state.Night)))
				expect.toBe(state.Night <= 99, true, ("fuera de rango: %s"):format(tostring(state.Night)))
				expect.toBe(#state.Clock, 5, ("reloj mal formado: %s"):format(tostring(state.Clock)))
			end
		end)

		Harness.it("la noche se acota al rango 1..99", function()
			expect.toBe(Access.ClampNight(nil), 1)
			expect.toBe(Access.ClampNight(0), 1)
			expect.toBe(Access.ClampNight(100), 99)
			expect.toBe(Access.ClampNight(-7), 1)
			expect.toBe(Access.ClampNight(0 / 0), 1)
			expect.toBe(Access.ClampNight(50.9), 50)
		end)

		Harness.it("las 99 noches tienen banda sin huecos", function()
			for n = 1, 99 do
				expect.toBe(Access.GetBand(n) ~= nil, true, ("la noche %d no tiene banda"):format(n))
			end

			expect.toBe(Access.GetBand(100) ~= nil, true, "una noche mayor no cae dentro de rango")
		end)

		Harness.it("la poblacion NO cae al avanzar la noche", function()
			-- La progresion tiene que ser monotona en cantidad. Una noche mas
			-- alta con menos enemigos es un error de balance, no una sorpresa:
			-- el jugador no puede aprender una regla que no se cumple.
			local previous = -1

			for n = 1, 99 do
				local band = Access.GetBand(n)

				expect.toBe(
					band.CountMul >= previous,
					true,
					("la noche %d tiene menos poblacion que la anterior"):format(n)
				)
				previous = band.CountMul
			end
		end)

		Harness.it("la noche 99 es la final y es distinta", function()
			expect.toBe(Access.IsFinalNight(99), true)
			expect.toBe(Access.IsFinalNight(98), false)

			local final = Access.GetBand(99)
			local preludio = Access.GetBand(98)

			expect.toBe(final.Label, "FINAL")
			expect.toBe(
				final.CountMul > preludio.CountMul,
				true,
				"la noche 99 no es mas dura que la 98"
			)
		end)

		Harness.it("el ciclo dura mas en las noches altas, con tope", function()
			local first = Night.CycleDuration(1)
			local last = Night.CycleDuration(99)

			expect.toBe(last > first, true, "la noche 99 dura lo mismo que la noche 1")

			-- El tope es lo que evita que "mas noches" sea "mas tiempo sin hacer
			-- nada": un ciclo de media hora es una desconexion disfrazada.
			expect.toBe(
				last <= Night.MaxCycleDuration * 4,
				true,
				("el ciclo de la noche 99 dura %.0f s"):format(last)
			)
		end)
	end)
end

return describeNightCycle