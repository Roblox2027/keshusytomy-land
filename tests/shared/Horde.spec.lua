--!strict
--[[
	Horde.spec
	El ciclo de vida de una horda (FASE 14).

	LA PRUEBA QUE IMPORTA
	---------------------
	"No otorgar recompensas multiples por el mismo evento". Eso es lo que pide
	el enunciado, y es exactamente el fallo que la economia no detecta: una
	recompensa duplicada no rompe nada, el perfil se guarda bien, el jugador ve
	el numero subir y no hay ningun error en el log.

	Por eso `ClaimReward` se prueba LLAMANDOLA VARIAS VECES, en distintos
	ordenes, y se comprueba que solo la primera entrega. Un test que la llamara
	una sola vez pasaria con un modulo que paga siempre.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local Horde = require("../../src/ReplicatedStorage/Shared/Libraries/HordeRules")

local function describeHorde()
	Harness.describe("Tamano", function()
		Harness.it("las hordas crecen con la noche", function()
			local previous = 0

			for night = 1, 99 do
				local size = Horde.SizeFor(night)

				expect.toBe(size >= previous, true, ("la noche %d tiene menos horda"):format(night))
				previous = size
			end
		end)

		Harness.it("la horda siempre tiene sentido como horda", function()
			-- Por debajo de 3 no es una horda: es un enemigo, y el jugador no
			-- percibe diferencia con la exploracion normal.
			for night = 1, 99 do
				expect.toBe(
					Horde.SizeFor(night) >= 3,
					true,
					("la noche %d tiene una horda de %d"):format(night, Horde.SizeFor(night))
				)
			end
		end)

		Harness.it("el tamano esta acotado", function()
			-- El argumento es que el jugador tiene que poder VER el final cerca.
			-- Una horda de 200 enemigos no es dificultad: es una cola de trabajo
			-- que nunca se termina.
			expect.toBe(Horde.SizeFor(99) <= 40, true, "la noche 99 supera 40 enemigos")
		end)

		Harness.it("acepta noches invalidas", function()
			local cases = { nil, "noche", {}, -5 }
			table.insert(cases, 0 / 0)

			for _, value in ipairs(cases) do
				local size = Horde.SizeFor(value)
				expect.toBe(size >= 3, true, ("tamano invalido: %s"):format(tostring(size)))
			end
		end)
	end)

	Harness.describe("Ciclo de vida", function()
		Harness.it("una horda nueva empieza corriendo y sin premio", function()
			local h = Horde.Create(1, "Forest", 10)

			expect.toBe(h.State, Horde.State.Running)
			expect.toBe(h.Killed, 0)
			expect.toBe(h.Rewarded, false)
			expect.toBe(h.WorldId, "Forest")
			expect.toBe(Horde.GetRemaining(h), h.Total)
		end)

		Harness.it("contar bajas avanza el contador y cierra al terminar", function()
			local h = Horde.Create(1, "Forest", 1, 4)

			expect.toBe(Horde.GetRemaining(h), 4)

			Horde.RegisterKill(h)
			expect.toBe(Horde.GetRemaining(h), 3)

			Horde.RegisterKill(h, 3)
			expect.toBe(h.State, Horde.State.Cleared)
			expect.toBe(Horde.GetRemaining(h), 0)
			expect.toBe(Horde.IsComplete(h), true)
		end)

		Harness.it("el contador nunca se pasa del total", function()
			-- Una bomba en cadena puede matar mas enemigos de los que quedaban.
			-- El contador se topa: un `Killed` mayor que `Total` haria que la
			-- recompensa se calculase sobre un numero que no existe.
			local h = Horde.Create(1, "Forest", 1, 5)
			Horde.RegisterKill(h, 999)

			expect.toBe(h.Killed, h.Total)
		end)

		Harness.it("una baja posterior no reabre una horda ya cerrada", function()
			-- El fallo real que esto evita: un enemigo que muere TARDE (una bomba
			-- que aun no habia explotado) inflaba el contador despues de
			-- `Cleared` y devolvia la horda a `Running` con el premio pagado.
			local h = Horde.Create(1, "Forest", 1, 2)
			Horde.RegisterKill(h, 2)
			expect.toBe(h.State, Horde.State.Cleared)

			Horde.RegisterKill(h)
			expect.toBe(h.State, Horde.State.Cleared)
			expect.toBe(h.Killed, 2)
		end)
	end)
Harness.describe("Fallo y expiracion", function()
		Harness.it("una horda fallida NO paga", function()
			-- Si pagara igual, al jugador le seria indiferente limpiar o no, y
			-- el limite de tiempo no significaria nada.
			local h = Horde.Create(1, "Forest", 5, 10)
			Horde.RegisterKill(h, 4)
			Horde.Fail(h)

			expect.toBe(h.State, Horde.State.Failed)
			expect.toBe(Horde.IsFailed(h), true)

			local paid, reward = Horde.ClaimReward(h)
			expect.toBe(paid, false)
			expect.toBe(reward, nil)
		end)

		Harness.it("una horda expirada NO paga", function()
			-- El jugador salio del mundo o el servidor esta apagando: lo que
			-- estaba haciendo alli ya no se cobra.
			local h = Horde.Create(1, "Forest", 5, 10)
			Horde.RegisterKill(h, 10)
			expect.toBe(h.State, Horde.State.Cleared)

			Horde.Expire(h)
			expect.toBe(Horde.IsExpired(h), true)
			expect.toBe((Horde.ClaimReward(h)), false)
		end)

		Harness.it("no se puede fallar ni expirar dos veces", function()
			local h = Horde.Create(1, "Forest", 5, 10)

			expect.toBe(Horde.Fail(h), true)
			expect.toBe(Horde.Fail(h), false)
		end)
	end)

	Harness.describe("EL PREMIO: no se paga dos veces (FASE 14)", function()
		Harness.it("la primera llamada paga y la segunda NO", function()
			local h = Horde.Create(1, "Forest", 10, 8)
			Horde.RegisterKill(h, 8)

			local paid1, reward1 = Horde.ClaimReward(h)
			expect.toBe(paid1, true, "la primera llamada no pago")
			expect.toBe(reward1 ~= nil, true)

			local paid2, reward2 = Horde.ClaimReward(h)
			expect.toBe(paid2, false, "la segunda llamada pago: recompensa duplicada")
			expect.toBe(reward2, nil)
		end)

		Harness.it("aguanta muchas llamadas seguidas", function()
			-- Un test con dos llamadas pasaria con un modulo que paga "dos veces
			-- y luego ya no". Con treinta se ve cualquier patron.
			local h = Horde.Create(1, "Forest", 10, 5)
			Horde.RegisterKill(h, 5)

			local timesPaid = 0

			for _ = 1, 30 do
				if Horde.ClaimReward(h) then
					timesPaid += 1
				end
			end

			expect.toBe(timesPaid, 1, ("se pagó %d veces"):format(timesPaid))
		end)

		Harness.it("el orden de expirar y reclamar no altera el resultado", function()
			-- Tres ordenes distintos, una sola conclusion: se paga si y solo si
			-- la horda se completo y nadie la cerro antes.
			local clean = Horde.Create(1, "Forest", 10, 4)
			Horde.RegisterKill(clean, 4)
			expect.toBe((Horde.ClaimReward(clean)), true)

			local late = Horde.Create(2, "Forest", 10, 4)
			Horde.RegisterKill(late, 4)
			Horde.ClaimReward(late)
			expect.toBe((Horde.ClaimReward(late)), false)

			local early = Horde.Create(3, "Forest", 10, 4)
			Horde.Expire(early)
			Horde.RegisterKill(early, 4)
			expect.toBe((Horde.ClaimReward(early)), false)
		end)

		Harness.it("dos hordas distintas pagan por separado", function()
			-- El cortafuegos es POR HORDA, no global: si el flag fuera global, la
			-- segunda horda de la noche no pagaria nunca y el jugador dejaria de
			-- hacerlas.
			local a = Horde.Create(1, "Forest", 10, 4)
			local b = Horde.Create(2, "Forest", 10, 4)

			Horde.RegisterKill(a, 4)
			Horde.RegisterKill(b, 4)

			expect.toBe((Horde.ClaimReward(a)), true)
			expect.toBe((Horde.ClaimReward(a)), false)
			expect.toBe((Horde.ClaimReward(b)), true)
			expect.toBe((Horde.ClaimReward(b)), false)
		end)

		Harness.it("la recompensa escala con la noche y esta acotada", function()
			local low = Horde.Create(1, "Forest", 1, 10)
			local high = Horde.Create(2, "Forest", 99, 10)

			expect.toBe(
				Horde.RewardFor(high).XP > Horde.RewardFor(low).XP,
				true,
				"la noche 99 no paga mas que la noche 1"
			)

			-- El tope protege la economia: una horda no puede pagar mas que el
			-- cierre del mundo.
			expect.toBe(
				Horde.RewardFor(high, 500).XP,
				Horde.RewardFor(high, 3).XP,
				"el multiplicador de evento no esta acotado"
			)
		end)

		Harness.it("la gema solo aparece en noches altas", function()
			expect.toBe(Horde.RewardFor(Horde.Create(1, "Forest", 20, 10)).Gems, 0)
			expect.toBe(Horde.RewardFor(Horde.Create(2, "Forest", 60, 10)).Gems, 1)
		end)
	end)
end

return describeHorde