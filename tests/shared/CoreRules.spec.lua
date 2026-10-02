--!strict
--[[
	CoreRules.spec
	Pruebas de la maquina de estados del Keshusy Core.

	Se prueba la LOGICA PURA (no el servicio): asi estas reglas pueden
	comprobarse de verdad, sin Workspace ni Players. Lo que depende del
	motor (las partes visuales, la interaccion real) se verifica en
	Studio y no se marca PASS aqui.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local CoreRules = require("../../src/ReplicatedStorage/Shared/Libraries/CoreRules")

-- Opciones de un nucleo de prueba. La recarga es 0 para que las
-- transiciones se alcancen en pocas llamadas.
local function options(overrides)
	local base = {
		maxCharge = 100,
		chargePerFragment = 10,
		fragmentsPerPlayer = 20,
		fragmentCooldown = 0,
		activationDuration = 6,
		step = 0,
		drainPerSecond = 15,
		eventDuration = 10,
		now = 0,
	}
	for key, value in pairs(overrides or {}) do
		base[key] = value
	end
	return base
end

-- Aporta `count` fragmentos seguidos del mismo jugador.
local function feed(state, playerId, count, opts)
	local current = state
	for _ = 1, count do
		local accepted, reason, nextState = CoreRules.TryAddFragment(current, playerId, opts)
		if not accepted then
			return current, reason
		end
		current = nextState
	end
	return current, nil
end

local function describeCoreRules()
	Harness.describe("CoreRules", function()
		Harness.it("arranca inerte y sin carga", function()
			local state = CoreRules.NewState()
			expect.toBe(state.State, "Inactive")
			expect.toBe(state.Charge, 0)
			expect.toBe(state.ActivationCount, 0)
		end)

		Harness.it("un fragmento suma carga exacta", function()
			local accepted, _, nextState = CoreRules.TryAddFragment(
				CoreRules.NewState(), 1, options()
			)
			expect.toBe(accepted, true)
			expect.toBe(nextState.Charge, 10)
			expect.toBe(nextState.State, "Inactive")
		end)

		Harness.it("la carga se acumula entre jugadores", function()
			local opts = options()
			local state = feed(CoreRules.NewState(), 1, 3, opts)
			state = feed(state, 2, 2, opts)
			expect.toBe(state.Charge, 50)
			expect.toBe(state.FragmentsByPlayer[1], 3)
			expect.toBe(state.FragmentsByPlayer[2], 2)
		end)

		Harness.it("alcanzar el maximo dispara Activating", function()
			local opts = options({ now = 100 })
			local state = feed(CoreRules.NewState(), 1, 10, opts)
			expect.toBe(state.Charge, 100)
			expect.toBe(state.State, "Activating")
			expect.toBe(state.ActivationStartedAt, 100)
			expect.toBe(state.ActivationEndsAt, 106)
		end)

		Harness.it("Activating no admite mas fragmentos", function()
			local opts = options()
			local state = feed(CoreRules.NewState(), 1, 10, opts)
			expect.toBe(state.State, "Activating")

			local accepted, reason = CoreRules.TryAddFragment(state, 2, opts)
			expect.toBe(accepted, false)
			expect.toBe(reason ~= nil, true)
		end)

		-- Anti-abuso: reglas de seguridad del nucleo.
		Harness.it("respeta el limite de fragmentos por jugador", function()
			local opts = options({ fragmentsPerPlayer = 3 })
			local state = feed(CoreRules.NewState(), 1, 3, opts)
			expect.toBe(state.FragmentsByPlayer[1], 3)

			local accepted, reason = CoreRules.TryAddFragment(state, 1, opts)
			expect.toBe(accepted, false)
			expect.toBe(reason, "limite de fragmentos alcanzado")
		end)

		Harness.it("el limite por jugador no afecta a los demas", function()
			local opts = options({ fragmentsPerPlayer = 2 })
			local state = feed(CoreRules.NewState(), 1, 2, opts)
			expect.toBe(CoreRules.TryAddFragment(state, 2, opts), true)
		end)

		Harness.it("rechaza fragmentos demasiado rapidos", function()
			-- Las DOS llamadas ocurren en el MISMO instante: sin eso la
			-- prueba comprobaria el paso del tiempo, no la recarga, y
			-- pasaria aunque la recarga estuviese rota.
			local state = CoreRules.NewState()
			local first = select(3, CoreRules.TryAddFragment(
				state, 1, options({ fragmentCooldown = 0.5, now = 0 })
			))

			local rejected, reason, nextState = CoreRules.TryAddFragment(
				first, 1, options({ fragmentCooldown = 0.5, now = 0 })
			)
			expect.toBe(rejected, false)
			expect.toBe(reason, "demasiado rapido")
			expect.toBe(nextState, nil)

			-- Pasada la recarga, vuelve a aceptar.
			expect.toBe(
				CoreRules.TryAddFragment(
					first, 1, options({ fragmentCooldown = 0.5, now = 0.6 })
				),
				true
			)
		end)

		-- Un rechazo no debe dejar el estado a medias.
		Harness.it("un fragmento rechazado deja el estado intacto", function()
			local opts = options({ fragmentsPerPlayer = 1 })
			local state = feed(CoreRules.NewState(), 1, 1, opts)
			local chargeBefore = state.Charge

			CoreRules.TryAddFragment(state, 1, opts)

			expect.toBe(state.Charge, chargeBefore)
			expect.toBe(state.FragmentsByPlayer[1], 1)
		end)

		Harness.it("rechaza peticion con identificador no numerico", function()
			local accepted, reason = CoreRules.TryAddFragment(
				CoreRules.NewState(), "abc", options()
			)
			expect.toBe(accepted, false)
			expect.toBe(reason, "peticion invalida")
		end)

		Harness.it("una carga NaN se sella en cero", function()
			local state = CoreRules.NewState()
			state.Charge = 0 / 0

			local accepted, _, nextState = CoreRules.TryAddFragment(state, 1, options())
			expect.toBe(accepted, true)
			-- NaN + 10 es NaN; el clamp lo devuelve a 0.
			expect.toBe(nextState.Charge, 0)
		end)

		Harness.it("una carga infinita se recorta al maximo", function()
			expect.toBe(CoreRules.ClampCharge(math.huge, 100), 100)
			expect.toBe(CoreRules.ClampCharge(-math.huge, 100), 0)
			expect.toBe(CoreRules.ClampCharge(-50, 100), 0)
		end)

		Harness.it("rechaza configuracion imposible", function()
			local accepted, reason = CoreRules.TryAddFragment(
				CoreRules.NewState(), 1, options({ maxCharge = 0 })
			)
			expect.toBe(accepted, false)
			expect.toBe(reason, "configuracion invalida")
		end)

		-- Avance temporal de la maquina.
		Harness.it("Activating NO se completa antes de tiempo", function()
			local state = feed(CoreRules.NewState(), 1, 10, options())
			local nextState = CoreRules.Advance(state, 5, options())
			expect.toBe(nextState.State, "Activating")
			expect.toBe(nextState.ActivationCount, 0)
		end)

		Harness.it("Activating se completa al vencer la ventana", function()
			local state = feed(CoreRules.NewState(), 1, 10, options())
			local nextState = CoreRules.Advance(state, 6, options())
			expect.toBe(nextState.State, "Active")
			expect.toBe(nextState.ActivationCount, 1)
		end)

		Harness.it("avanzar dos veces no completa dos activaciones", function()
			local state = feed(CoreRules.NewState(), 1, 10, options())
			local once = CoreRules.Advance(state, 6, options())
			local twice = CoreRules.Advance(once, 6, options())
			expect.toBe(twice.ActivationCount, 1)
		end)

		Harness.it("el nucleo activo vuelve a inerte al descargarse", function()
			local state = feed(CoreRules.NewState(), 1, 10, options())
			local active = CoreRules.Advance(state, 6, options())
			expect.toBe(active.State, "Active")

			local drained = CoreRules.Advance(active, 7, options({
				step = 1,
				passiveDrainPerSecond = 10,
			}))
			expect.toBe(drained.Charge, 90)
			expect.toBe(drained.State, "Inactive")
		end)

		Harness.it("un evento con duracion 0 termina de inmediato", function()
			local state = feed(CoreRules.NewState(), 1, 10, options())
			local active = CoreRules.Advance(state, 6, options({ eventDuration = 0 }))
			expect.toBe(active.State, "Active")
		end)

		-- Sobrecarga.
		Harness.it("la sobrecarga se drena hasta quedar inerte", function()
			local state = CoreRules.Overload(CoreRules.NewState(), 120, 100)
			expect.toBe(state.State, "Overloaded")
			expect.toBe(state.Charge, 100)

			local drained = CoreRules.Advance(state, 1, options({
				step = 1,
				drainPerSecond = 15,
			}))
			expect.toBe(drained.Charge, 85)
			expect.toBe(drained.State, "Inactive")
		end)

		Harness.it("la sobrecarga no admite fragmentos", function()
			local state = CoreRules.Overload(CoreRules.NewState(), 120, 100)
			expect.toBe(CoreRules.TryAddFragment(state, 1, options()), false)
		end)

		-- Presentacion.
		Harness.it("la fraccion de carga va de 0 a 1", function()
			expect.toBe(CoreRules.ChargeFraction(0, 100), 0)
			expect.toBe(CoreRules.ChargeFraction(50, 100), 0.5)
			expect.toBe(CoreRules.ChargeFraction(999, 100), 1)
		end)

		Harness.it("una fraccion con configuracion imposible es 0", function()
			expect.toBe(CoreRules.ChargeFraction(50, 0), 0)
			expect.toBe(CoreRules.ChargeFraction(50, -1), 0)
		end)
	end)
end

return describeCoreRules