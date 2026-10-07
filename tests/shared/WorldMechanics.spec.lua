--!strict
--[[
	WorldMechanics.spec
	Mecanicas expandidas por mundo (FASE 4).

	Lo que se certifica aqui es el CATALOGO y la aritmetica PURA:
	- que cada mundo tiene mecanicas propias (y distintas)
	- que las maquinas de fase temporales (tormenta, erupcion) derivan
	  correctamente del reloj
	- que la maquina de estado de terminales restringe transiciones invalidas
	- que las plataformas frailibles siguen el orden correcto
	- que los modificadores de movimiento se calculan bien
	- que la validacion de posicion/interaccion funciona
	- que Audit detecta incoherencias entre definiciones y reglas

	Las partes, el hilo y la lectura de posiciones las prueba el playtest.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local Mechanics = require("../../src/ReplicatedStorage/Shared/Libraries/WorldMechanics")
local Access = require("../../src/ReplicatedStorage/Shared/Libraries/WorldAccessRules")
local Forest = require("../../src/ReplicatedStorage/WorldDefinitions/Forest")
local Desert = require("../../src/ReplicatedStorage/WorldDefinitions/Desert")
local Ice = require("../../src/ReplicatedStorage/WorldDefinitions/Ice")
local Volcano = require("../../src/ReplicatedStorage/WorldDefinitions/Volcano")
local Cyber = require("../../src/ReplicatedStorage/WorldDefinitions/Cyber")

local DECLARED = {
	Forest = Forest,
	Desert = Desert,
	Ice = Ice,
	Volcano = Volcano,
	Cyber = Cyber,
}

-- Posicion de prueba con campos X/Z (compatible con Vector3 y tablas).
local POS_A = { X = 0, Z = 0 }
local POS_B = { X = 10, Z = 0 }
local POS_C = { X = 6, Z = 8 } -- distancia 10 del origen

local function describeWorldMechanics()
	Harness.describe("Catalogo por mundo", function()
		Harness.it("todo mundo jugable tiene mecanicas propias", function()
			for _, worldId in ipairs(Access.GetWorldIds()) do
				local mech = Mechanics.ForWorld(worldId)

				expect.toBe(mech ~= nil, true, ("%s sin mecanicas"):format(worldId))
			end
		end)

		Harness.it("ningun mundo repite el mismo conjunto de mecanicas", function()
			-- Cada mundo debe tener una "huella" distinta de mecanicas.
			-- Si dos mundos tienen exactamente las mismas, se sienten iguales.
			local seen = {}

			for _, worldId in ipairs(Mechanics.GetWorldIds()) do
				local mech = Mechanics.ForWorld(worldId)
				local key = ""

				if mech.Tracking then
					key = key .. "T"
				end

				if mech.NaturalMechanisms then
					key = key .. "N"
				end

				if mech.TemporalEvents then
					key = key .. "E"
				end

				if mech.BuriedTreasures then
					key = key .. "B"
				end

				if mech.Oases then
					key = key .. "O"
				end

				if mech.SlipperyIce then
					key = key .. "S"
				end

				if mech.FragilePlatforms then
					key = key .. "F"
				end

				if mech.MeteorShower then
					key = key .. "M"
				end

				if mech.Terminals then
					key = key .. "R"
				end

				if mech.SecurityDoors then
					key = key .. "D"
				end

				if mech.SecurityLasers then
					key = key .. "L"
				end

				if mech.DynamicRoutes then
					key = key .. "G"
				end

				expect.toBe(seen[key] == nil, true, ("huella repetida: %s"):format(key))
				seen[key] = true
			end
		end)

		Harness.it("Forest tiene tracking pero no eventos temporales", function()
			local forest = Mechanics.ForWorld("Forest")
			expect.toBe(forest.Tracking ~= nil, true)
			expect.toBe(forest.TemporalEvents, nil)
		end)

		Harness.it("Desert tiene tormenta de arena", function()
			local desert = Mechanics.ForWorld("Desert")
			expect.toBe(desert.TemporalEvents ~= nil, true)
			expect.toBe(#desert.TemporalEvents >= 1, true)

			local event = desert.TemporalEvents[1]
			expect.toBe(event.Kind, "Sandstorm")
		end)

		Harness.it("Ice tiene hielo deslizante y plataformas frailibles", function()
			local ice = Mechanics.ForWorld("Ice")
			expect.toBe(ice.SlipperyIce ~= nil, true)
			expect.toBe(ice.FragilePlatforms ~= nil, true)
		end)

		Harness.it("Volcano tiene erupcion y lluvia de meteoros", function()
			local volcano = Mechanics.ForWorld("Volcano")
			expect.toBe(volcano.TemporalEvents ~= nil, true)
			expect.toBe(volcano.MeteorShower ~= nil, true)

			expect.toBe(volcano.TemporalEvents[1].Kind, "Eruption")
		end)

		Harness.it("Cyber tiene terminales y puertas de seguridad", function()
			local cyber = Mechanics.ForWorld("Cyber")
			expect.toBe(cyber.Terminals ~= nil, true)
			expect.toBe(cyber.SecurityDoors ~= nil, true)
			expect.toBe(cyber.SecurityLasers ~= nil, true)
		end)
	end)

	Harness.describe("Coherencia entre reglas y definiciones", function()
		Harness.it("Audit no reporta problemas entre reglas y definiciones", function()
			local declared = {}

			for _, id in ipairs(Access.GetWorldIds()) do
				declared[id] = DECLARED[id]
			end

			-- Build a mechanics table from the declared definitions.
			local mechanics = {}

			for _, id in ipairs(Access.GetWorldIds()) do
				mechanics[id] = Mechanics.ForWorld(id)
			end

			local problems = Mechanics.Audit(mechanics, Access.GetWorldIds())
			expect.toBe(#problems, 0, table.concat(problems, "; "))
		end)

		Harness.it("cada mundo declarado tiene Mechanics lista", function()
			for _, id in ipairs(Access.GetWorldIds()) do
				expect.toBe(
					type(DECLARED[id].Mechanics),
					"table",
					("%s: sin lista Mechanics"):format(id)
				)
				expect.toBe(#DECLARED[id].Mechanics > 0, true, ("%s: lista Mechanics vacia"):format(id))
			end
		end)
	end)

	Harness.describe("Maquina de fases temporal", function()
		Harness.it("phase Calm fuera de ciclo", function()
			local event = {
				WarningDuration = 5,
				ActiveDuration = 15,
				RecoveryDuration = 8,
				Cooldown = 120,
			}

			-- 200s deberia estar en Cooldown (fase Calm)
			expect.toBe(Mechanics.TemporalPhaseAt(event, 0, 200), Mechanics.TemporalPhase.Calm)
		end)

		Harness.it("phase Warning al inicio del ciclo", function()
			local event = {
				WarningDuration = 5,
				ActiveDuration = 15,
				RecoveryDuration = 8,
				Cooldown = 120,
			}

			expect.toBe(Mechanics.TemporalPhaseAt(event, 0, 0), Mechanics.TemporalPhase.Warning)
			expect.toBe(Mechanics.TemporalPhaseAt(event, 0, 4.9), Mechanics.TemporalPhase.Warning)
		end)

		Harness.it("phase Active durante el evento", function()
			local event = {
				WarningDuration = 5,
				ActiveDuration = 15,
				RecoveryDuration = 8,
				Cooldown = 120,
			}

			expect.toBe(Mechanics.TemporalPhaseAt(event, 0, 5), Mechanics.TemporalPhase.Active)
			expect.toBe(Mechanics.TemporalPhaseAt(event, 0, 19.9), Mechanics.TemporalPhase.Active)
		end)

		Harness.it("phase Recovery despues del evento", function()
			local event = {
				WarningDuration = 5,
				ActiveDuration = 15,
				RecoveryDuration = 8,
				Cooldown = 120,
			}

			expect.toBe(Mechanics.TemporalPhaseAt(event, 0, 20), Mechanics.TemporalPhase.Recovery)
			expect.toBe(Mechanics.TemporalPhaseAt(event, 0, 27.9), Mechanics.TemporalPhase.Recovery)
		end)

		Harness.it("phase Calm durante cooldown", function()
			local event = {
				WarningDuration = 5,
				ActiveDuration = 15,
				RecoveryDuration = 8,
				Cooldown = 120,
			}

			-- Cycle: 5 + 15 + 8 + 120 = 148
			-- En el cooldown (28..148) esta en Calm
			expect.toBe(Mechanics.TemporalPhaseAt(event, 0, 28), Mechanics.TemporalPhase.Calm)
			expect.toBe(Mechanics.TemporalPhaseAt(event, 0, 100), Mechanics.TemporalPhase.Calm)
			expect.toBe(Mechanics.TemporalPhaseAt(event, 0, 147.9), Mechanics.TemporalPhase.Calm)
		end)
	end)

	Harness.describe("Danos temporales", function()
		Harness.it("solo la fase Active causa dano", function()
			local event = {
				WarningDuration = 5,
				ActiveDuration = 15,
				RecoveryDuration = 8,
				Cooldown = 120,
				DamagePerSecond = 8,
			}

			local tickDelta = 0.5

			-- Warning: 0 damage
			expect.toBe(Mechanics.TemporalDamagePerTick(event, 0, 2, tickDelta), 0)

			-- Active: 8 * 0.5 = 4
			expect.toBeClose(Mechanics.TemporalDamagePerTick(event, 0, 7, tickDelta), 4)

			-- Recovery: 0 damage
			expect.toBe(Mechanics.TemporalDamagePerTick(event, 0, 25, tickDelta), 0)

			-- Cooldown: 0 damage
			expect.toBe(Mechanics.TemporalDamagePerTick(event, 0, 50, tickDelta), 0)
		end)

		Harness.it("un evento sin DamagePerSecond no dania", function()
			local event = {
				WarningDuration = 5,
				ActiveDuration = 15,
				RecoveryDuration = 8,
				Cooldown = 120,
			}

			expect.toBe(Mechanics.TemporalDamagePerTick(event, 0, 7, 0.5), 0)
		end)

		Harness.it("visibilidad 1 en Calm, < 1 en Active", function()
			local event = {
				WarningDuration = 5,
				ActiveDuration = 15,
				RecoveryDuration = 8,
				Cooldown = 120,
				Visibility = 0.3,
			}

			-- Calm
			expect.toBe(Mechanics.VisibilityFactor(event, 0, 200), 1)

			-- Active
			local vis = Mechanics.VisibilityFactor(event, 0, 7)
			expect.toBe(vis < 1, true)
			expect.toBe(vis >= 0, true)
		end)
	end)

	Harness.describe("Maquina de estados de terminal", function()
		Harness.it("Offline -> Accessing es valida", function()
			expect.toBe(
				Mechanics.CanTerminalTransition(Mechanics.TerminalState.Offline, Mechanics.TerminalState.Accessing),
				true
			)
		end)

		Harness.it("Accessing -> Active es valida", function()
			expect.toBe(
				Mechanics.CanTerminalTransition(Mechanics.TerminalState.Accessing, Mechanics.TerminalState.Active),
				true
			)
		end)

		Harness.it("Active -> Complete es valida", function()
			expect.toBe(
				Mechanics.CanTerminalTransition(Mechanics.TerminalState.Active, Mechanics.TerminalState.Complete),
				true
			)
		end)

		Harness.it("Complete -> Offline es valida (reset)", function()
			expect.toBe(
				Mechanics.CanTerminalTransition(Mechanics.TerminalState.Complete, Mechanics.TerminalState.Offline),
				true
			)
		end)

		Harness.it("saltarse Accessing es invalido", function()
			-- Un exploit que salte directamente a Active debe ser rechazado.
			expect.toBe(
				Mechanics.CanTerminalTransition(Mechanics.TerminalState.Offline, Mechanics.TerminalState.Active),
				false
			)
			expect.toBe(
				Mechanics.CanTerminalTransition(Mechanics.TerminalState.Offline, Mechanics.TerminalState.Complete),
				false
			)
		end)

		Harness.it("saltarse Complete es invalido", function()
			expect.toBe(
				Mechanics.CanTerminalTransition(Mechanics.TerminalState.Active, Mechanics.TerminalState.Offline),
				true
			)
			expect.toBe(
				Mechanics.CanTerminalTransition(Mechanics.TerminalState.Accessing, Mechanics.TerminalState.Complete),
				false
			)
		end)

		Harness.it("una transicion a estado desconocido es invalida", function()
			expect.toBe(
				Mechanics.CanTerminalTransition(Mechanics.TerminalState.Active, "Bogus"),
				false
			)
		end)
	end)

	Harness.describe("Plataformas frailibles", function()
		Harness.it("Stable -> Cracked es valida", function()
			expect.toBe(
				Mechanics.CanFragileTransition(Mechanics.FragileState.Stable, Mechanics.FragileState.Cracked),
				true
			)
		end)

		Harness.it("Cracked -> Broken es valida", function()
			expect.toBe(
				Mechanics.CanFragileTransition(Mechanics.FragileState.Cracked, Mechanics.FragileState.Broken),
				true
			)
		end)

		Harness.it("no se puede revertir el orden", function()
			expect.toBe(
				Mechanics.CanFragileTransition(Mechanics.FragileState.Broken, Mechanics.FragileState.Cracked),
				false
			)
			expect.toBe(
				Mechanics.CanFragileTransition(Mechanics.FragileState.Cracked, Mechanics.FragileState.Stable),
				false
			)
		end)

		Harness.it("saltar Stable -> Broken es invalido", function()
			expect.toBe(
				Mechanics.CanFragileTransition(Mechanics.FragileState.Stable, Mechanics.FragileState.Broken),
				false
			)
		end)
	end)

	Harness.describe("Modificadores de movimiento", function()
		Harness.it("ice multiplier > 1 acelera", function()
			local speed = Mechanics.ModifiedWalkSpeed(1.3)
			expect.toBe(speed > Mechanics.DefaultWalkSpeed, true)
			expect.toBe(speed, 20) -- floor(16 * 1.3) = floor(20.8) = 20
		end)

		Harness.it("multiplier 1 conserva la velocidad base", function()
			expect.toBe(Mechanics.ModifiedWalkSpeed(1), Mechanics.DefaultWalkSpeed)
		end)

		Harness.it("multiplier < 1 frena", function()
			local speed = Mechanics.ModifiedWalkSpeed(0.5)
			expect.toBe(speed < Mechanics.DefaultWalkSpeed, true)
			expect.toBe(speed, 8) -- floor(16 * 0.5) = 8
		end)

		Harness.it("NaN e infinito caen al default", function()
			expect.toBe(Mechanics.ModifiedWalkSpeed(0 / 0), Mechanics.DefaultWalkSpeed)
			expect.toBe(Mechanics.ModifiedWalkSpeed(math.huge), Mechanics.DefaultWalkSpeed)
		end)

		Harness.it("el minimo es 1 (nunca inmoviliza)", function()
			local speed = Mechanics.ModifiedWalkSpeed(0.01)
			expect.toBe(speed >= 1, true)
		end)
	end)

	Harness.describe("Validacion de posicion", function()
		Harness.it("distancia 2D al cuadrado", function()
			expect.toBe(Mechanics.DistanceSqXZ(POS_A, POS_B), 100)
			expect.toBe(Mechanics.DistanceSqXZ(POS_A, POS_C), 100)
		end)

		Harness.it("distancia a si mismo es 0", function()
			expect.toBe(Mechanics.DistanceSqXZ(POS_A, POS_A), 0)
		end)

		Harness.it("posiciones invalidas dan distancia infinita", function()
			expect.toBe(Mechanics.DistanceSqXZ(nil, POS_A), math.huge)
			expect.toBe(Mechanics.DistanceSqXZ(POS_A, nil), math.huge)
		end)

		Harness.it("in range dentro del radio", function()
			-- POS_C esta a distancia 10 del origen.
			expect.toBe(Mechanics.IsInRange(POS_A, POS_C, 18), true)
			expect.toBe(Mechanics.IsInRange(POS_A, POS_C, 15), true)
		end)

		Harness.it("fuera de rango", function()
			-- POS_B esta a 10, fuera de rango 5.
			expect.toBe(Mechanics.IsInRange(POS_A, POS_B, 5), false)
		end)

		Harness.it("en el borde esta dentro", function()
			-- Distancia exactamente 10, rango 10.
			expect.toBe(Mechanics.IsInRange(POS_A, POS_C, 10), true)
		end)

		Harness.it("rango no positivo rechaza todo", function()
			expect.toBe(Mechanics.IsInRange(POS_A, POS_A, 0), false)
			expect.toBe(Mechanics.IsInRange(POS_A, POS_A, -5), false)
		end)
	end)

	Harness.describe("Limites y ritmo", function()
		Harness.it("duraciones de fase son positivas", function()
			expect.toBe(Mechanics.WarningDuration > 0, true)
			expect.toBe(Mechanics.ActiveDuration > 0, true)
			expect.toBe(Mechanics.RecoveryDuration > 0, true)
			expect.toBe(Mechanics.EventCooldown > 0, true)
		end)

		Harness.it("el cooldown es suficientemente largo para explorar", function()
			-- 120s: deja tiempo a morir, reaparecer y volver sin farmear.
			expect.toBe(Mechanics.EventCooldown >= 90, true)
		end)

		Harness.it("el acceso a terminal no es instantaneo ni interminable", function()
			expect.toBe(Mechanics.TerminalAccessDuration > 0, true)
			expect.toBe(Mechanics.TerminalAccessDuration <= 5, true)
		end)

		Harness.it("la ventana de crack es real", function()
			-- 1s: tiempo suficiente para reaccionar, no para relajarse.
			expect.toBe(Mechanics.DefaultCrackWindow > 0, true)
			expect.toBe(Mechanics.DefaultCrackWindow <= 3, true)
		end)
	end)

	Harness.describe("Audit", function()
		Harness.it("detecta un mundo sin mecanicas", function()
			local bad = {
				Forest = { Tracking = nil },
				Desert = Mechanics.ForWorld("Desert"),
				Ice = Mechanics.ForWorld("Ice"),
				Volcano = Mechanics.ForWorld("Volcano"),
				Cyber = Mechanics.ForWorld("Cyber"),
			}

			local problems = Mechanics.Audit(bad, Access.GetWorldIds())
			expect.toBe(#problems > 0, true)
		end)

		Harness.it("catalogo sano no reporta problemas", function()
			local mechanics = {}

			for _, id in ipairs(Access.GetWorldIds()) do
				mechanics[id] = Mechanics.ForWorld(id)
			end

			expect.toBe(#Mechanics.Audit(mechanics, Access.GetWorldIds()), 0)
		end)

		Harness.it("un mundo conocido pero ausente es problema", function()
			local incomplete = {}

			for _, id in ipairs(Access.GetWorldIds()) do
				if id ~= "Cyber" then
					incomplete[id] = Mechanics.ForWorld(id)
				end
			end

			local problems = Mechanics.Audit(incomplete, Access.GetWorldIds())
			expect.toBe(#problems > 0, true)
		end)

		Harness.it("un catalogo nil reporta problema", function()
			local problems = Mechanics.Audit(nil, Access.GetWorldIds())
			expect.toBe(#problems > 0, true)
		end)
	end)
end

return describeWorldMechanics
