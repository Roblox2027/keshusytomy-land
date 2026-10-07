--!strict
--[[
	Events.spec
	Eventos de mundo y eventos raros (FASES 17 y 18).

	POR QUE LA SELECCION ES PURA
	-----------------------------
	`Roll` recibe un numero en vez de llamar a `math.random`. Eso permite
	comprobar la DISTRIBUCION entera recorriendo `0.0 .. 1.0` en pasos finos y
	mirando cuantas veces sale cada evento.

	Un test que sorteara con azar comprobaria "a veces sale algo", que no es un
	contrato: pasaria igual con un `Rarity` de 0.9 y con uno de 0.05. Recorriendo
	el rango se comprueba la cosa que de verdad importa, que es que un evento
	raro NO sale en la mayor parte de las tiradas.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local Event = require("../../src/ReplicatedStorage/Shared/Libraries/EventRules")
local Access = require("../../src/ReplicatedStorage/Shared/Libraries/WorldAccessRules")

local function describeEvents()
	Harness.describe("Catalogo", function()
		Harness.it("cada mundo tiene sus eventos", function()
			-- El enunciado nombra al menos tres por mundo. Menos de tres es un
			-- mundo sin variedad: el jugador ve el mismo evento cada vez y
			-- deja de atender al HUD.
			for _, worldId in ipairs(Access.GetWorldIds()) do
				local events = Event.GetForWorld(worldId)

				expect.toBe(#events >= 3, true, ("%s tiene %d eventos"):format(worldId, #events))
			end
		end)

		Harness.it("los ids de evento son unicos", function()
			-- Un id repetido hace que `Get` devuelva el evento equivocado y que
			-- dos eventos distintos compartan estado.
			local seen = {}

			for _, entry in ipairs(Event.GetAll()) do
				expect.toBe(seen[entry.Id] == nil, true, ("id repetido: %s"):format(entry.Id))
				seen[entry.Id] = true
			end
		end)

		Harness.it("todo evento tiene los campos que el servicio necesita", function()
			for _, entry in ipairs(Event.GetAll()) do
				local def = Event.Get(entry.Id)

				expect.toBe(type(def.Label), "string", ("%s sin etiqueta"):format(entry.Id))
				expect.toBe(def.Duration > 0, true, ("%s dura 0 s"):format(entry.Id))
				expect.toBe(
					def.Rarity > 0 and def.Rarity <= 1,
					true,
					("%s tiene probabilidad %s"):format(entry.Id, tostring(def.Rarity))
				)
			end
		end)

		Harness.it("los eventos raros son raros de verdad", function()
			-- FASE 18: "no abusar". Un evento raro con probabilidad 0.5 no es
			-- raro, es un evento normal con mala prensa.
			for _, def in ipairs(Event.Rare) do
				expect.toBe(
					def.Rarity <= 0.1,
					true,
					("%s tiene probabilidad %s y deberia ser <= 0.1")
						:format(def.Id, tostring(def.Rarity))
				)
			end
		end)
	end)

	Harness.describe("Seleccion por probabilidad", function()
		Harness.it("se recorre todo el rango 0..1 sin fallar", function()
			for _, worldId in ipairs(Access.GetWorldIds()) do
				for i = 0, 200 do
					local picked = Event.Roll(worldId, i / 200, true)

					if picked then
						expect.toBe(
							Event.Get(picked.Id) ~= nil,
							true,
							("roll %.3f devolvio un evento inexistente"):format(i / 200)
						)
					end
				end
			end
		end)

		Harness.it("un evento raro sale en menos del 20 % de las tiradas", function()
			-- Esta es la comprobacion que hace que un evento RARO se sienta
			-- especial. Recorre 1000 tiradas por mundo y cuenta las raras.
			for _, worldId in ipairs(Access.GetWorldIds()) do
				local rareHits = 0
				local steps = 1000

				for i = 0, steps do
					local picked = Event.Roll(worldId, i / steps, true)

					if picked and Event.IsRare(picked.Id) then
						rareHits += 1
					end
				end

				expect.toBe(
					rareHits / steps <= 0.2,
					true,
					("%s: los eventos raros salen el %.1f %% de las veces")
						:format(worldId, (rareHits / steps) * 100)
				)
			end
		end)

		Harness.it("con eventos raros desactivados NO sale ninguno", function()
			for _, worldId in ipairs(Access.GetWorldIds()) do
				for i = 0, 200 do
					local picked = Event.Roll(worldId, i / 200, false)

					if picked then
						expect.toBe(
							Event.IsRare(picked.Id),
							false,
							("%s devolvio un evento raro con allowRare=false"):format(worldId)
						)
					end
				end
			end
		end)

		Harness.it("un roll invalido no rompe nada", function()
			local cases = { nil, "alto", {} }
			table.insert(cases, 0 / 0)

			for _, worldId in ipairs(Access.GetWorldIds()) do
				for _, value in ipairs(cases) do
					expect.toBe(
						pcall(Event.Roll, worldId, value, true),
						true,
						("Roll fallo con %s"):format(tostring(value))
					)
				end
			end
		end)

		Harness.it("un mundo desconocido no devuelve eventos", function()
			expect.toBe(Event.Roll("NoExiste", 0.01, true), nil)
		end)
	end)

Harness.describe("Ciclo de vida y limpieza", function()
		Harness.it("un evento empieza corriendo y con duracion", function()
			local def = Event.Get("ForestSwarm")
			local active = Event.Start(1, def, "Forest", 10, 1000)

			expect.toBe(active.State, Event.State.Running)
			expect.toBe(active.Duration, def.Duration)
			expect.toBe(active.CleanedUp, false)
			expect.toBe(Event.GetRemaining(active, 1000), def.Duration)
		end)

		Harness.it("el tiempo restante baja y nunca es negativo", function()
			local active = Event.Start(1, Event.Get("ForestSwarm"), "Forest", 10, 1000)

			expect.toBe(Event.GetRemaining(active, 1030), active.Duration - 30)

			-- Pasada la duracion, el resto es 0 y no un numero negativo que
			-- luego se sumaria a otros para dar una UI con "-40s".
			expect.toBe(Event.GetRemaining(active, 99999), 0)
			expect.toBe(Event.IsExpired(active, 99999), true)
		end)

		Harness.it("un evento se limpia UNA sola vez", function()
			-- El servicio llama `Finish` desde el tick (por tiempo) y desde el
			-- cleanup (por salida del jugador). Con dos llamadas, la segunda
			-- destruiria NPCs ya destruidos.
			local active = Event.Start(1, Event.Get("ForestSwarm"), "Forest", 10, 1000)

			expect.toBe(Event.Finish(active), true)
			expect.toBe(active.CleanedUp, true)
			expect.toBe(active.State, Event.State.Finished)
			expect.toBe(Event.Finish(active), false)
		end)

		Harness.it("cancelar y terminar son estados distintos", function()
			-- El jugador se va: el evento se cancela, no "termina". La
			-- distincion es la que permite no pagar por algo que el jugador no
			-- llego a completar.
			local active = Event.Start(1, Event.Get("ForestSwarm"), "Forest", 10, 1000)
			Event.Finish(active, true)

			expect.toBe(active.State, Event.State.Cancelled)
		end)

		Harness.it("un evento ya limpio no puede expirar de nuevo", function()
			local active = Event.Start(1, Event.Get("ForestSwarm"), "Forest", 10, 1000)
			Event.Finish(active)

			expect.toBe(Event.IsExpired(active, 99999), false)
		end)
	end)

	Harness.describe("Recompensa", function()
		Harness.it("un evento raro paga mas que uno normal", function()
			-- La promesa de "raro" es que compensa. Un evento raro que paga igual
			-- que uno normal es una mentira que el jugador detecta en dos
			-- tiradas.
			local normal = Event.Start(1, Event.Get("ForestSwarm"), "Forest", 10, 0)
			local rare = Event.Start(2, Event.Get("LegendaryChest"), "Forest", 10, 0)

			expect.toBe(
				Event.RewardFor(rare).XP > Event.RewardFor(normal).XP,
				true,
				"el evento raro no paga mas"
			)
			expect.toBe(Event.RewardFor(rare).Gems, 1)
			expect.toBe(Event.RewardFor(normal).Gems, 0)
		end)

		Harness.it("la presion del evento esta acotada", function()
			-- El `Threat` entra en `DifficultyRules.Resolve`, que acota. Aqui se
			-- limita a un rango sano para que un valor raro del catalogo no
			-- empuje el perfil entero.
			for _, entry in ipairs(Event.GetAll()) do
				local threat = Event.ThreatOf(Event.Get(entry.Id))
				expect.toBe(threat >= 0.5 and threat <= 2, true, ("%s: %s"):format(entry.Id, tostring(threat)))
			end

			expect.toBe(Event.ThreatOf(nil), 1)
		end)
	end)
end

return describeEvents
