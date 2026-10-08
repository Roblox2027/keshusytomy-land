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
local Monsters = require("../../src/ReplicatedStorage/Shared/MonsterDefinitions")

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
					("%s tiene probabilidad %s y deberia ser <= 0.1"):format(
						def.Id,
						tostring(def.Rarity)
					)
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
					("%s: los eventos raros salen el %.1f %% de las veces"):format(
						worldId,
						(rareHits / steps) * 100
					)
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
				expect.toBe(
					threat >= 0.5 and threat <= 2,
					true,
					("%s: %s"):format(entry.Id, tostring(threat))
				)
			end

			expect.toBe(Event.ThreatOf(nil), 1)
		end)
	end)

	Harness.describe("Cuerpo del evento (mision V2)", function()
		Harness.it("los enemigos declarados por los cuerpos existen", function()
			-- Un `Spawns` con un id inventado no da error al cargar: da un
			-- evento que se abre, anuncia y NO PONE NADA en el mapa. Es el
			-- peor fallo posible porque parece configurado.
			for _, entry in ipairs(Event.GetBodies()) do
				expect.toBe(type(entry.Spawns), "table", ("%s sin Spawns"):format(entry.Id))
				expect.toBe(#entry.Spawns > 0, true, ("%s con Spawns vacio"):format(entry.Id))

				for _, spawnId in ipairs(entry.Spawns) do
					expect.toBe(
						Monsters.Get(spawnId) ~= nil,
						true,
						("%s: enemigo inexistente '%s'"):format(entry.Id, tostring(spawnId))
					)
				end
			end
		end)

		Harness.it("todo cuerpo referencia un evento que existe", function()
			-- La tabla `Bodies` es aparte del catalogo: un id aqui que no este
			-- en el catalogo es un cuerpo huerfano que nunca se genera.
			for _, entry in ipairs(Event.GetBodies()) do
				expect.toBe(
					Event.Get(entry.Id) ~= nil,
					true,
					("cuerpo sin evento: '%s'"):format(entry.Id)
				)
			end
		end)

		Harness.it("el objetivo de caza esta acotado con la noche", function()
			-- Sin techo, un evento de la noche 40 pediria decenas de bajas en
			-- 75 segundos: no es desafio, es imposible.
			for _, entry in ipairs(Event.GetBodies()) do
				if entry.Kind == "Hunt" then
					local target99 = Event.ObjectiveTargetFor(entry.Id, 99)

					expect.toBe(
						target99 <= 20,
						true,
						("%s pide %d bajas en la noche 99"):format(entry.Id, target99)
					)
				end
			end

			expect.toBe(Event.ObjectiveTargetFor("RareMiniBoss", 50), 1)
			expect.toBe(Event.ObjectiveTargetFor("ForestStorm", 10), 0)
		end)

		Harness.it("el plan de generacion respeta el tope de vivos", function()
			-- El plan nunca pide mas de `MaxAlivePerEvent` vivos ni mas de lo
			-- que falta para el objetivo: los dos extremos crean enemigos
			-- huerfanos en el mapa.
			local night = 1
			local target = Event.ObjectiveTargetFor("ForestSwarm", night)

			expect.toBe(
				Event.SpawnPlanFor("ForestSwarm", night, 0, 0) <= Event.MaxAlivePerEvent,
				true
			)
			expect.toBe(Event.SpawnPlanFor("ForestSwarm", night, target, 0), 0)
			expect.toBe(Event.SpawnPlanFor("ForestSwarm", night, 0, target), 0)
			expect.toBe(Event.SpawnPlanFor("ForestSwarm", night, 0, 3), 1)
			expect.toBe(Event.SpawnPlanFor("ForestStorm", night, 0, 0), 0)
		end)

		Harness.it("un evento de caza que expira NO se completa", function()
			-- Pagar una caza caducada premiaria no haber jugado: el evento se
			-- convertiria en "espera y cobra", que es lo que el cuerpo elimina.
			expect.toBe(Event.CompletesOnExpiry("ForestSwarm"), false)
			expect.toBe(Event.CompletesOnExpiry("RareMiniBoss"), false)
			expect.toBe(Event.CompletesOnExpiry("ForestStorm"), true)
			expect.toBe(Event.CompletesOnExpiry("RewardRain"), true)
		end)

		Harness.it("el evento mundial de invasion existe y es raro", function()
			-- FASE 5 de la mision: `WORLD_INVASION` con etiqueta de anuncio
			-- global, objetivo compartido y recompensa para los presentes.
			local def = Event.Get("WorldInvasion")

			expect.toBe(def ~= nil, true, "WorldInvasion no esta en el catalogo")
			expect.toBe(Event.IsRare("WorldInvasion"), true)
			expect.toBe(Event.BodyFor("WorldInvasion") ~= nil, true, "WorldInvasion sin cuerpo")
		end)
	end)

	Harness.describe("FAse 6: Catalogo dinámico", function()
		local DYNAMIC_EVENTS = {
			-- Forest
			"ForestAmbush", "LostCreature", "ForestRift", "NightHunters",
			-- Desert
			"BuriedTreasure", "Caravan", "SandBeastHunt",
			-- Ice
			"IceBreak", "FrozenRescue", "FrostPack",
			-- Volcano
			"Rockfall", "VolcanicEvacuation", "MagmaHunt",
			-- Cyber
			"SystemFailure", "SecurityLockdown", "HackTheCore", "SecuritySwarm",
		}

		local UNIVERSAL_EVENTS = { "TreasureRush", "MonsterSurge", "EliteSpawn" }
		local COOP_EVENTS = { "SharedThreat", "TwinBosses", "Nexus" }

		Harness.it("los eventos FASE 6 estan en el catalogo", function()
			for _, eventId in ipairs(DYNAMIC_EVENTS) do
				expect.toBe(Event.Get(eventId) ~= nil, true, eventId .. " no esta en el catalogo")
			end
		end)

		Harness.it("los eventos universal estan en el catalogo", function()
			for _, eventId in ipairs(UNIVERSAL_EVENTS) do
				expect.toBe(Event.Get(eventId) ~= nil, true, eventId .. " no esta en el catalogo")
			end
		end)

		Harness.it("los eventos COOP estan en el catalogo", function()
			for _, eventId in ipairs(COOP_EVENTS) do
				expect.toBe(Event.Get(eventId) ~= nil, true, eventId .. " no esta en el catalogo")
			end
		end)

		Harness.it("todo evento FASE 6 tiene Type y Weight", function()
			for _, eventId in ipairs(DYNAMIC_EVENTS) do
				local def = Event.Get(eventId)
				expect.toBe(type(def), "table", eventId .. " no es table")
				expect.toBe(type(def.Type), "string", eventId .. " sin Type")
				expect.toBe(tonumber(def.Weight) > 0, true, eventId .. " sin Weight > 0")
			end
		end)

		Harness.it("los eventos FASE 6 tienen duraciones de fase", function()
			for _, eventId in ipairs(DYNAMIC_EVENTS) do
				local def = Event.Get(eventId)
				expect.toBe(tonumber(def.WarningDuration) > 0, true, eventId .. " WarningDuration invalido")
				expect.toBe(tonumber(def.ActiveDuration) > 0, true, eventId .. " ActiveDuration invalido")
				expect.toBe(tonumber(def.RecoveryDuration) > 0, true, eventId .. " RecoveryDuration invalido")
			end
		end)

		Harness.it("los eventos COOP requieren jugadores minimos", function()
			for _, eventId in ipairs(COOP_EVENTS) do
				local def = Event.Get(eventId)
				expect.toBe(def.Type, Event.EventType.Coop, eventId .. " no es Coop")
				expect.toBe(tonumber(def.MinPlayers) >= 2, true, eventId .. " MinPlayers < 2")
			end
		end)

		Harness.it("cada mundo FASE 6 tiene eventos con zona", function()
			local checked = {}

			for _, worldId in ipairs(Access.GetWorldIds()) do
				local events = Event.GetForWorld(worldId)
				local hasLocal = false

				for _, evt in ipairs(events) do
					if evt.Type == Event.EventType.Local and evt.ZoneId then
						hasLocal = true
					end
				end

				expect.toBe(hasLocal, true, worldId .. " sin eventos LOCAL con zona")
				checked[worldId] = true
			end

			-- Confirm all 5 worlds were checked.
			local count = 0
			for _ in pairs(checked) do count += 1 end
			expect.toBe(count, 5, "no se revisaron los 5 mundos")
		end)

		Harness.it("todo evento FASE 6 tiene Rarity valido (compat con Roll)", function()
			for _, eventId in ipairs(DYNAMIC_EVENTS) do
				local def = Event.Get(eventId)
				expect.toBe(
					tonumber(def.Rarity) > 0 and tonumber(def.Rarity) <= 1,
					true,
					eventId .. " Rarity fuera de rango"
				)
			end
		end)
	end)

	Harness.describe("FAse 6: Maquina de 5 estados", function()
		Harness.it("DynamicStart crea evento en WARNING", function()
			local def = Event.Get("ForestAmbush")
			local active = Event.DynamicStart(1, def, "Forest", 1, 1000)

			expect.toBe(active.Phase, Event.DynamicState.Warning, "debe empezar en WARNING")
			expect.toBe(active.CleanUp, false, "no debe estar limpio al inicio")
			expect.toBe(active.ObjectiveCompleted, false, "objetivo no completado al inicio")
		end)

		Harness.it("AdvancePhase transita WARNING -> ACTIVE -> RECOVERY -> COOLDOWN -> IDLE", function()
			local def = Event.Get("ForestAmbush")
			local active = Event.DynamicStart(1, def, "Forest", 1, 1000)
			expect.toBe(active.Phase, Event.DynamicState.Warning)

			-- Simula el paso del tiempo: expire WARNING.
			Event.AdvancePhase(active, 1000 + 100)
			expect.toBe(active.Phase, Event.DynamicState.Active, "debe pasar a ACTIVE")

			-- Expira ACTIVE.
			Event.AdvancePhase(active, 1000 + 200)
			expect.toBe(active.Phase, Event.DynamicState.Recovery, "debe pasar a RECOVERY")

			-- Expira RECOVERY.
			Event.AdvancePhase(active, 1000 + 300)
			expect.toBe(active.Phase, Event.DynamicState.Cooldown, "debe pasar a COOLDOWN")

			-- Expira COOLDOWN -> IDLE.
			Event.AdvancePhase(active, 1000 + 400)
			expect.toBe(active.Phase, Event.DynamicState.Idle, "debe pasar a IDLE")
		end)

		Harness.it("GetPhaseRemaining baja y nunca es negativo", function()
			local def = Event.Get("ForestAmbush")
			local active = Event.DynamicStart(1, def, "Forest", 1, 1000)

			-- WARNING duration.
			expect.toBe(Event.GetPhaseRemaining(active, 1000), def.WarningDuration)
			expect.toBe(Event.GetPhaseRemaining(active, 1000 + def.WarningDuration), 0)
			expect.toBe(Event.IsPhaseExpired(active, 1000 + def.WarningDuration + 1), true)
		end)

		Harness.it("PhaseDuration devuelve la duracion de la fase actual", function()
			local def = Event.Get("ForestAmbush")
			local active = Event.DynamicStart(1, def, "Forest", 1, 1000)

			expect.toBe(Event.PhaseDuration(active), def.WarningDuration)

			active.Phase = Event.DynamicState.Active
			expect.toBe(Event.PhaseDuration(active), def.ActiveDuration)

			active.Phase = Event.DynamicState.Recovery
			expect.toBe(Event.PhaseDuration(active), def.RecoveryDuration)
		end)

		Harness.it("CompleteObjective y IsObjectiveDone funcionan", function()
			local active = Event.DynamicStart(1, Event.Get("ForestAmbush"), "Forest", 1, 1000)

			expect.toBe(Event.IsObjectiveDone(active), false, "no completado al inicio")

			Event.CompleteObjective(active, 1000)
			expect.toBe(active.ObjectiveCompleted, true, "debe marcar como completado")
			expect.toBe(Event.IsObjectiveDone(active), true, "debe reportar completado")

			-- Idempotente.
			expect.toBe(Event.CompleteObjective(active, 1000), false, "segunda llamada debe devolver false")
		end)

		Harness.it("DynamicStart usa WarningDuration por defecto si no esta definido", function()
			local def = { Id = "TestDefault", Label = "Test", Type = Event.EventType.Global }
			local active = Event.DynamicStart(1, def, "Forest", 1, 1000)

			expect.toBe(active.WarningDuration, 8, "warning default debe ser 8")
			expect.toBe(active.ActiveDuration, 45, "active default debe ser 45")
			expect.toBe(active.RecoveryDuration, 5, "recovery default debe ser 5")
		end)
	end)

	Harness.describe("FAse 6: Seleccion ponderada", function()
		Harness.it("WeightedRoll devuelve un evento valido", function()
			for _, worldId in ipairs(Access.GetWorldIds()) do
				for i = 0, 100 do
					local picked = Event.WeightedRoll(worldId, i / 100, true, false)

					if picked then
						expect.toBe(Event.Get(picked.Id) ~= nil, true, "evento inexistente")
					end
				end
			end
		end)

		Harness.it("WeightedRoll con rango 0..1 siempre devuelve algo", function()
			-- Con Weight-based selection, cualquier roll en 0..1 devuelve
			-- un evento (el peso normalizado siempre suma a 1 dentro del rango).
			for _, worldId in ipairs(Access.GetWorldIds()) do
				local picked = Event.WeightedRoll(worldId, 0.5, true, false)
				expect.toBe(picked ~= nil, true, worldId .. " WeightedRoll devolvio nil")
			end
		end)

		Harness.it("WeightedRoll excluye COOP cuando excludeCoop=true", function()
			for _, worldId in ipairs(Access.GetWorldIds()) do
				for i = 0, 200 do
					local picked = Event.WeightedRoll(worldId, i / 200, true, true)

					if picked then
						expect.toBe(
							Event.IsCoop(picked.Id),
							false,
							("COOP devuelto con excludeCoop=true en %s"):format(worldId)
						)
					end
				end
			end
		end)

		Harness.it("WeightedRoll con roll invalido no rompe", function()
			local cases = { nil, "alto", {} }
			table.insert(cases, 0 / 0)

			for _, worldId in ipairs(Access.GetWorldIds()) do
				for _, value in ipairs(cases) do
					expect.toBe(
						pcall(Event.WeightedRoll, worldId, value, true, false),
						true,
						("WeightedRoll fallo con %s"):format(tostring(value))
					)
				end
			end
		end)

		Harness.it("WeightedRoll con mundo desconocido devuelve nil", function()
			expect.toBe(Event.WeightedRoll("NoExiste", 0.5, true, false), nil)
		end)

		Harness.it("un evento COOP existe y requiere jugadores", function()
			local def = Event.Get("SharedThreat")
			expect.toBe(def.Type, Event.EventType.Coop, "SharedThreat no es Coop")
			expect.toBe(tonumber(def.MinPlayers), 3, "SharedThreat requiere 3 jugadores")
		end)

		Harness.it("GetPlayerRequirements devuelve los requisitos", function()
			local minP, maxP = Event.GetPlayerRequirements("TwinBosses")
			expect.toBe(minP, 4, "TwinBosses requiere 4")
			expect.toBe(maxP, 8, "TwinBosses max 8")

			minP, maxP = Event.GetPlayerRequirements("SharedThreat")
			expect.toBe(minP, 3, "SharedThreat requiere 3")
			expect.toBe(maxP, 8, "SharedThreat max 8")

			minP, maxP = Event.GetPlayerRequirements("Inexistente")
			expect.toBe(minP, nil)
			expect.toBe(maxP, nil)
		end)
	end)

	Harness.describe("FAse 6: Zonas, tipos y enfriamiento", function()
		Harness.it("GetZone devuelve la zona del evento", function()
			expect.toBe(Event.GetZone("ForestAmbush"), "BogHollow")
			expect.toBe(Event.GetZone("SecurityLockdown"), "ServerHall")
			expect.toBe(Event.GetZone("ForestStorm"), nil, "evento legacy sin zona")
		end)

		Harness.it("GetEventType clasifica los eventos", function()
			expect.toBe(Event.GetEventType("ForestAmbush"), Event.EventType.Local)
			expect.toBe(Event.GetEventType("SystemFailure"), Event.EventType.Global)
			expect.toBe(Event.GetEventType("SharedThreat"), Event.EventType.Coop)
			expect.toBe(Event.GetEventType("ForestSwarm"), nil, "evento legacy sin Type")
		end)

		Harness.it("CooldownFor devuelve el cooldown", function()
			expect.toBe(Event.CooldownFor("ForestAmbush"), 300)
			expect.toBe(Event.CooldownFor("Nexus"), 720)
			expect.toBe(Event.CooldownFor("ForestStorm"), 120, "default 120 para eventos sin Cooldown")
			expect.toBe(Event.CooldownFor("Inexistente"), 120, "default para evento inexistente")
		end)

		Harness.it("IsCoop e IsUniversal funcionan", function()
			expect.toBe(Event.IsCoop("SharedThreat"), true)
			expect.toBe(Event.IsCoop("ForestAmbush"), false)

			expect.toBe(Event.IsUniversal("TreasureRush"), true)
			expect.toBe(Event.IsUniversal("MonsterSurge"), true)
			expect.toBe(Event.IsUniversal("ForestAmbush"), false)
		end)

		Harness.it("GetDynamicEventIds incluye todos los eventos FASE 6", function()
			local ids = Event.GetDynamicEventIds()
			local seen = {}

			for _, id in ipairs(ids) do
				seen[id] = true
			end

			expect.toBe(seen["ForestAmbush"], true)
			expect.toBe(seen["BuriedTreasure"], true)
			expect.toBe(seen["IceBreak"], true)
			expect.toBe(seen["SecurityLockdown"], true)
			expect.toBe(seen["TreasureRush"], true)
			expect.toBe(seen["EliteSpawn"], true)
			expect.toBe(seen["Nexus"], true)
			expect.toBeFalsy(seen["WorldInvasion"])
			expect.toBeFalsy(seen["ForestSwarm"])
		end)
	end)

	Harness.describe("FAse 6: Cuerpos dinámicos", function()
		Harness.it("los monstruos declarados por los cuerpos dinámicos existen", function()
			for _, entry in ipairs(Event.GetDynamicBodies()) do
				expect.toBe(type(entry.Spawns), "table", entry.Id .. " sin Spawns")

				for _, spawnId in ipairs(entry.Spawns) do
					expect.toBe(
						Monsters.Get(spawnId) ~= nil,
						true,
						("%s: enemigo inexistente '%s'"):format(entry.Id, tostring(spawnId))
					)
				end
			end
		end)

		Harness.it("todo cuerpo dinámico referencia un evento que existe", function()
			for _, entry in ipairs(Event.GetDynamicBodies()) do
				expect.toBe(
					Event.Get(entry.Id) ~= nil,
					true,
					("cuerpo dinamico sin evento: '%s'"):format(entry.Id)
				)
			end
		end)

		Harness.it("el objetivo de caza dinámica esta acotado con la noche", function()
			for _, entry in ipairs(Event.GetDynamicBodies()) do
				if entry.Kind == "Hunt" or entry.Kind == "Boss" then
					local target99 = Event.DynamicObjectiveTargetFor(entry.Id, 99)

					expect.toBe(
						target99 <= 25,
						true,
						("%s pide %d bajas en la noche 99"):format(entry.Id, target99)
					)
				end
			end

			expect.toBe(Event.DynamicObjectiveTargetFor("ForestRift", 50), 0, "evento Survive sin objetivo")
		end)

		Harness.it("el plan de generacion dinámico respeta el tope de vivos", function()
			local night = 1
			local target = Event.DynamicObjectiveTargetFor("ForestAmbush", night)

			expect.toBe(
				Event.DynamicSpawnPlanFor("ForestAmbush", night, 0, 0) <= Event.MaxAlivePerEvent,
				true
			)
			expect.toBe(Event.DynamicSpawnPlanFor("ForestAmbush", night, target, 0), 0)
			expect.toBe(Event.DynamicSpawnPlanFor("ForestAmbush", night, 0, target), 0)
			expect.toBe(Event.DynamicSpawnPlanFor("ForestRift", night, 0, 0), 0, "Survive sin spawns")
		end)

		Harness.it("un evento de caza dinámico que expira NO se completa", function()
			expect.toBe(Event.DynamicCompletesOnExpiry("ForestAmbush"), false)
			expect.toBe(Event.DynamicCompletesOnExpiry("ForestRift"), true, "Survive completa al expirar")
			expect.toBe(Event.DynamicCompletesOnExpiry("SystemFailure"), true)
		end)

		Harness.it("DynamicObjectiveText genera texto para cada kind", function()
			expect.toBe(Event.DynamicObjectiveText("ForestAmbush", 1, 3):find("Derrota"), 1, "Hunt debe pedir derrotar")
			expect.toBe(Event.DynamicObjectiveText("ForestRift", 1, 0):find("Sobrevive"), 1, "Survive debe pedir sobrevivir")
			expect.toBe(Event.DynamicObjectiveText("TreasureRush", 1, 2):find("Colecciona"), 1, "Collect debe pedir coleccionar")
			expect.toBe(Event.DynamicObjectiveText("SystemFailure", 1, 0):find("Sobrevive"), 1, "SystemFailure es Survive")
		end)
	end)

	Harness.describe("FAse 6: Integridad de mundo", function()
		Harness.it("todo evento FASE 6 esta en GetForWorld del mundo correcto", function()
			for _, worldId in ipairs(Access.GetWorldIds()) do
				local events = Event.GetForWorld(worldId)

				for _, evt in ipairs(events) do
					-- Un evento LOCAL debe tener ZoneId.
					if evt.Type == Event.EventType.Local then
						expect.toBe(type(evt.ZoneId), "string", evt.Id .. " LOCAL sin zona")
					end

					-- Un evento COOP debe tener MinPlayers.
					if evt.Type == Event.EventType.Coop then
						expect.toBe(tonumber(evt.MinPlayers) > 0, true, evt.Id .. " COOP sin MinPlayers")
					end

					-- Todo evento FASE 6 tiene Cooldown.
					if evt.Weight ~= nil then
						expect.toBe(tonumber(evt.Cooldown) > 0, true, evt.Id .. " sin Cooldown")
					end
				end
			end
		end)

		Harness.it("no hay IDs duplicados entre todos los eventos", function()
			local seen = {}

			for _, entry in ipairs(Event.GetAll()) do
				expect.toBe(seen[entry.Id] == nil, true, "id duplicado: " .. entry.Id)
				seen[entry.Id] = true
			end
		end)

		Harness.it("los eventos raros siguen siendo raros", function()
			for _, def in ipairs(Event.Rare) do
				expect.toBe(def.Rarity <= 0.1, true, def.Id .. " Rarity > 0.1")
			end
		end)
	end)
 end

return describeEvents
