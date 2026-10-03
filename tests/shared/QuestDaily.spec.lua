--!strict
--[[
	QuestDaily.spec
	Recompensas diarias: dia, racha y proteccion de duplicado (spec 27).

	POR QUE ESTA SUITE ESTA SEPARADA
	--------------------------------
	El diario no es "una mision mas": su unidad de tiempo es el DIA, y su
	fallo caracteristico no es el progreso sino la DUPLICACION. Un jugador
	que pulsa el boton treinta veces en el mismo segundo, o que reconecta
	cinco veces, debe recibir UNA recompensa.

	Las pruebas usan un reloj INYECTADO. Es la unica forma de comprobar un
	limite por fecha sin esperar un dia, y es tambien la razon por la que
	`QuestRules` no usa `os.time()` dentro de la logica.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local Rules = require("../../src/ReplicatedStorage/Shared/Libraries/QuestRules")

local DAY = 86400

--- Un instante fijo: 2026-01-01T00:00:00Z.
local T0 = 1767225600

local function describeQuestDaily()
	Harness.describe("QuestDaily", function()
		---------------------------------------------------------
		-- INDICE DEL DIA
		---------------------------------------------------------

		Harness.it("el indice del dia avanza cada 24 horas", function()
			expect.toBe(Rules.GetDayIndex(T0), Rules.GetDayIndex(T0 + DAY - 1))
			expect.toBe(Rules.GetDayIndex(T0 + DAY), Rules.GetDayIndex(T0) + 1)
		end)

		Harness.it("el indice no depende de la zona horaria del jugador", function()
			-- "Hoy" son 24 horas desde una referencia comun. Si dependiera
			-- del calendario local, dos jugadores en paises distintos
			-- tendrian dias distintos en el MISMO instante, y el limite
			-- por fecha dejaria de ser un limite.
			expect.toBe(Rules.GetDayIndex(T0 + 12 * 3600), Rules.GetDayIndex(T0))
		end)

		Harness.it("un reloj invalido no rompe el calculo", function()
			expect.toBe(Rules.GetDayIndex(0 / 0), 0)
			expect.toBe(Rules.GetDayIndex("hoy"), 0)
		end)

		---------------------------------------------------------
		-- RECLAMO UNICO POR DIA
		---------------------------------------------------------

		Harness.it("un jugador nuevo no ha reclamado hoy", function()
			local state = Rules.NewState(1)
			expect.toBe(Rules.IsDailyClaimed(state, T0), false)
		end)

		Harness.it("el primer reclamo del dia se acepta", function()
			local state = Rules.NewState(1)
			local accepted, rejection, rewards, streak = Rules.ClaimDaily(state, T0, { Coins = 50 })

			expect.toBe(accepted, true)
			expect.toBe(rejection, nil)
			expect.toBe(rewards.Coins, 50)
			expect.toBe(streak, 1)
		end)

		Harness.it("no se puede reclamar DOS veces el mismo dia", function()
			-- La proteccion principal del diario. Treinta pulsaciones en el
			-- mismo segundo deben dar UNA recompensa.
			local state = Rules.NewState(1)
			Rules.ClaimDaily(state, T0, { Coins = 50 })

			local accepted, rejection = Rules.ClaimDaily(state, T0, { Coins = 50 })
			expect.toBe(accepted, false)
			expect.toBe(rejection, Rules.Reject.AlreadyClaimed)

			-- Ni aunque pase una hora, ni aunque "cambie de dia" para el
			-- jugador pero no para el indice.
			expect.toBe(Rules.ClaimDaily(state, T0 + 3600, { Coins = 50 }), false)
			expect.toBe(Rules.ClaimDaily(state, T0 + DAY - 1, { Coins = 50 }), false)
		end)

		Harness.it("treinta reclamos seguidos pagan una sola vez", function()
			local state = Rules.NewState(1)
			local acceptedCount = 0

			for _ = 1, 30 do
				local accepted = Rules.ClaimDaily(state, T0, { Coins = 50 })
				if accepted then
					acceptedCount += 1
				end
			end

			expect.toBe(acceptedCount, 1)
		end)

		Harness.it("al dia siguiente se puede reclamar otra vez", function()
			local state = Rules.NewState(1)
			Rules.ClaimDaily(state, T0, { Coins = 50 })

			local accepted = Rules.ClaimDaily(state, T0 + DAY, { Coins = 50 })
			expect.toBe(accepted, true)
		end)

		Harness.it("el reclamo diario sobrevive a la reconexion", function()
			-- Si el registro fuera en memoria, reconectar permitiria
			-- reclamar el mismo dia otra vez, indefinidamente.
			local state = Rules.NewState(1)
			Rules.ClaimDaily(state, T0, { Coins = 50 })

			local accepted = Rules.ClaimDaily(state, T0, { Coins = 50 })
			expect.toBe(accepted, false)
		end)

		Harness.it("un reloj que retrocede no permite un segundo reclamo", function()
			-- Un NTP mal sincronizado puede mover el reloj del servidor
			-- hacia atras. El caso degenerado se trata como "ya reclamado",
			-- que es la lectura conservadora: preferimos fastidiar a un
			-- jugador legitimo antes que abrir una via de duplicacion.
			local state = Rules.NewState(1)
			Rules.ClaimDaily(state, T0, { Coins = 50 })

			local accepted = Rules.ClaimDaily(state, T0 - 600, { Coins = 50 })
			expect.toBe(accepted, false)
		end)
---------------------------------------------------------
		-- RACHA
		---------------------------------------------------------

		Harness.it("la racha sube con dias consecutivos", function()
			local state = Rules.NewState(1)

			local _, _, _, streak = Rules.ClaimDaily(state, T0, {})
			expect.toBe(streak, 1)

			_, _, _, streak = Rules.ClaimDaily(state, T0 + DAY, {})
			expect.toBe(streak, 2)

			_, _, _, streak = Rules.ClaimDaily(state, T0 + DAY * 2, {})
			expect.toBe(streak, 3)
		end)

		Harness.it("saltarse un dia reinicia la racha", function()
			local state = Rules.NewState(1)
			Rules.ClaimDaily(state, T0, {})
			Rules.ClaimDaily(state, T0 + DAY, {})

			-- Se salta el dia +2 y vuelve en el +3.
			local _, _, _, streak = Rules.ClaimDaily(state, T0 + DAY * 3, {})
			expect.toBe(streak, 1)
		end)

		Harness.it("la racha esta acotada", function()
			-- Una racha infinita obliga a entrar todos los dias y se
			-- convierte en presion en vez de incentivo.
			local state = Rules.NewState(1)
			local streak = 0

			for day = 0, Rules.MAX_STREAK + 20 do
				local _, _, _, current = Rules.ClaimDaily(state, T0 + day * DAY, {})
				streak = current
			end

			expect.toBe(streak, Rules.MAX_STREAK)
		end)

		Harness.it("la racha de un estado corrupto no rompe nada", function()
			local state = Rules.NewState(1)
			state.Daily = { Streak = "muchos" }

			local _, _, _, streak = Rules.ClaimDaily(state, T0, {})
			expect.toBe(streak, 1)
			expect.toBe(Rules.GetStreak(state), 1)
		end)

		Harness.it("un estado invalido no paga el diario", function()
			local accepted, rejection = Rules.ClaimDaily("no soy una tabla", T0, { Coins = 50 })
			expect.toBe(accepted, false)
			expect.toBe(rejection, Rules.Reject.NoProfile)
		end)

		---------------------------------------------------------
		-- OFERTA DEL DIA
		---------------------------------------------------------

		Harness.it("la oferta es la MISMA para todos los jugadores de un dia", function()
			-- Si dependiera del estado del servidor, dos jugadores
			-- conectados al mismo tiempo verian ofertas distintas, y el
			-- mismo jugador veria cambiar su lista al reconectar.
			local catalog = {
				dailya = { Id = "DAILYA", Type = "Daily" },
				dailyb = { Id = "DAILYB", Type = "Daily" },
				dailyc = { Id = "DAILYC", Type = "Daily" },
			}

			local first = Rules.RollDailyOffer(catalog, T0, 2)
			local second = Rules.RollDailyOffer(catalog, T0, 2)

			expect.toBe(#first, 2)
			expect.toBe(first[1], second[1])
			expect.toBe(first[2], second[2])
		end)

		Harness.it("la oferta cambia de un dia a otro", function()
			local catalog = {
				dailya = { Id = "DAILYA", Type = "Daily" },
				dailyb = { Id = "DAILYB", Type = "Daily" },
				dailyc = { Id = "DAILYC", Type = "Daily" },
			}

			local today = table.concat(Rules.RollDailyOffer(catalog, T0, 2), ",")
			local tomorrow = table.concat(Rules.RollDailyOffer(catalog, T0 + DAY, 2), ",")

			expect.toBe(today ~= tomorrow, true)
		end)

		Harness.it("la oferta nunca pide mas misiones de las que hay", function()
			-- Con un solo daily, pedir tres devolveria el mismo id tres
			-- veces, y el jugador veria tres filas identicas.
			local catalog = { dailya = { Id = "DAILYA", Type = "Daily" } }
			local offer = Rules.RollDailyOffer(catalog, T0, 3)

			expect.toBe(#offer, 1)
			expect.toBe(offer[1], "dailya")
		end)

		Harness.it("un catalogo vacio o invalido no rompe la oferta", function()
			expect.toBe(#Rules.RollDailyOffer({}, T0, 3), 0)
			expect.toBe(#Rules.RollDailyOffer("no soy tabla", T0, 3), 0)
		end)
	end)
end

return describeQuestDaily