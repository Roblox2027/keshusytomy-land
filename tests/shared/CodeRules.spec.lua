--!strict
--[[
	CodeRules.spec
	Pruebas del canje de codigos.

	La prueba que manda sobre todas las demas es "el mismo codigo dos
	veces no paga dos veces". Todo lo demas (normalizacion, caducidad,
	limites) existe para que ese camino solo se pueda recorrer una vez.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local Rules = require("../../src/ReplicatedStorage/Shared/Libraries/CodeRules")

--- Estado de perfil minimo, tal y como lo migraria `ProfileSchema`.
local function newState()
	return { Redemptions = {}, RedemptionCounts = {} }
end

--- Contador COMPARTIDO del servidor.
---
--- `global` es una tabla aparte del perfil a proposito: cada jugador
--- tiene su perfil, asi que un limite global de canjes no puede vivir ahi.
--- Si no estuviera separada, `MaxRedemptions` no existiria.
local function newGlobal()
	return { RedeemedCodes = {} }
end

--- Catalogo de un codigo de ejemplo.
local function catalog(overrides)
	local base = { Code = "KESHUSY2026", Rewards = { Coins = 100 } }
	for key, value in (overrides or {}) do
		base[key] = value
	end
	return { keshusy2026 = base }
end

local function describeCodeRules()
	Harness.describe("CodeRules", function()
		---------------------------------------------------------
		-- NORMALIZACION
		---------------------------------------------------------

		Harness.it("normaliza mayusculas, espacios, guiones y guiones bajos", function()
			expect.toBe(Rules.Normalize("KESHUSY2026"), "keshusy2026")
			expect.toBe(Rules.Normalize("  keshusy2026  "), "keshusy2026")
			expect.toBe(Rules.Normalize("keshusy-2026"), "keshusy2026")
			expect.toBe(Rules.Normalize("keshusy_2026"), "keshusy2026")
		end)

		Harness.it("rechaza lo que no puede ser un codigo", function()
			expect.toBe(Rules.Normalize(""), nil)
			expect.toBe(Rules.Normalize("   "), nil)
			expect.toBe(Rules.Normalize(nil), nil)
			expect.toBe(Rules.Normalize(12345), nil)
			-- Con simbolos raros: es un intento, no un error de tecleo.
			expect.toBe(Rules.Normalize("code'; DROP--"), nil)
			expect.toBe(Rules.Normalize("code[1]"), nil)
		end)

		Harness.it("rechaza cadenas absurdamente largas", function()
			expect.toBe(Rules.Normalize(string.rep("A", 100)), nil)
		end)

		---------------------------------------------------------
		-- DEFINICION
		---------------------------------------------------------

		Harness.it("una definicion valida pasa", function()
			expect.toBe(Rules.IsDefinitionValid({ Code = "X1", Rewards = { Coins = 5 } }), true)
		end)

		Harness.it("una definicion sin recompensa se rechaza", function()
			expect.toBe(Rules.IsDefinitionValid({ Code = "X1", Rewards = {} }), false)
			expect.toBe(Rules.IsDefinitionValid({ Code = "X1" }), false)
		end)

		Harness.it("una recompensa no positiva o fraccionaria se rechaza", function()
			-- Negativa: canjear un codigo RESTARIA saldo.
			expect.toBe(Rules.IsDefinitionValid({ Code = "X", Rewards = { Coins = -100 } }), false)
			expect.toBe(Rules.IsDefinitionValid({ Code = "X", Rewards = { Coins = 0 } }), false)
			expect.toBe(Rules.IsDefinitionValid({ Code = "X", Rewards = { Coins = 1.5 } }), false)
			expect.toBe(Rules.IsDefinitionValid({ Code = "X", Rewards = { Coins = 0 / 0 } }), false)
		end)

		---------------------------------------------------------
		-- VIGENCIA
		---------------------------------------------------------

		Harness.it("un codigo sin caducidad esta siempre activo", function()
			expect.toBe(Rules.IsActive({ Code = "X", Rewards = { Coins = 1 } }, 0), true)
			expect.toBe(Rules.IsActive({ Code = "X", Rewards = { Coins = 1 } }, 1e12), true)
		end)

		Harness.it("un codigo caduca en el instante exacto", function()
			local definition = { Code = "X", Rewards = { Coins = 1 }, ExpiresAt = 100 }

			expect.toBe(Rules.IsActive(definition, 99), true)
			-- En el segundo exacto ya no vale: lectura conservadora.
			expect.toBe(Rules.IsActive(definition, 100), false)
			expect.toBe(Rules.IsActive(definition, 101), false)
		end)

		---------------------------------------------------------
		-- CANJE: el camino feliz
		---------------------------------------------------------

		Harness.it("canjea un codigo valido y devuelve la recompensa", function()
			local state = newState()
			local accepted, reason, rewards = Rules.Redeem(state, newGlobal(), 1, "KESHUSY2026", 0, catalog())

			expect.toBe(accepted, true)
			expect.toBe(reason, nil)
			expect.toBe(rewards.Coins, 100)
		end)

		Harness.it("el canje queda registrado y sobrevive a la reconexion", function()
			local state = newState()
			local shared = newGlobal()
			Rules.Redeem(state, shared, 7, "KESHUSY2026", 0, catalog())

			expect.toBe(state.Redemptions.keshusy2026, true)
			expect.toBe(shared.RedeemedCodes.keshusy2026, 1)
			expect.toBe(state.RedemptionCounts["7"], 1)

			-- "Reconectar" es recargar el perfil guardado: el canje anterior
			-- sigue ahi y por eso no se repite. El contador global tambien
			-- sobrevive mientras el servidor no se reinicie.
			local reloaded = { Redemptions = state.Redemptions, RedemptionCounts = state.RedemptionCounts }
			expect.toBe(Rules.Redeem(reloaded, shared, 7, "KESHUSY2026", 0, catalog()), false)
		end)

		---------------------------------------------------------
		-- CANJE: la garantia central
		---------------------------------------------------------

		Harness.it("el MISMO codigo dos veces por el mismo jugador no paga dos veces", function()
			local state = newState()
			local shared = newGlobal()
			local defs = catalog()

			local first, _, firstRewards = Rules.Redeem(state, shared, 1, "KESHUSY2026", 0, defs)
			expect.toBe(first, true)
			expect.toBe(firstRewards.Coins, 100)

			local second, reason, secondRewards = Rules.Redeem(state, shared, 1, "KESHUSY2026", 0, defs)
			expect.toBe(second, false)
			expect.toBe(reason, Rules.Reject.AlreadyUsed)
			expect.toBe(secondRewards, nil)

			-- El contador global solo avanzo una vez.
			expect.toBe(shared.RedeemedCodes.keshusy2026, 1)
		end)

		Harness.it("cien intentos del mismo codigo conceden UNA sola recompensa", function()
			local state = newState()
			local shared = newGlobal()
			local defs = catalog()
			local granted = 0

			for _ = 1, 100 do
				local accepted, _, rewards = Rules.Redeem(state, shared, 42, "KESHUSY2026", 0, defs)

				if accepted and rewards then
					granted += 1
				end
			end

			expect.toBe(granted, 1)
			expect.toBe(shared.RedeemedCodes.keshusy2026, 1)
		end)

		Harness.it("las variantes de escritura del mismo codigo tampoco cuelan", function()
			local state = newState()
			local shared = newGlobal()
			local defs = catalog()

			Rules.Redeem(state, shared, 1, "KESHUSY2026", 0, defs)

			-- Mismo codigo escrito de otra manera: sigue siendo el mismo.
			local second, reason = Rules.Redeem(state, shared, 1, "  keshusy-2026 ", 0, defs)
			expect.toBe(second, false)
			expect.toBe(reason, Rules.Reject.AlreadyUsed)
		end)

		Harness.it("jugadores DISTINTOS si pueden canjear el mismo codigo", function()
			-- Cada jugador tiene su PERFIL, pero el contador global es el
			-- mismo para todos: por eso tres jugadores distintos pueden
			-- canjear y el total llega a tres.
			local shared = newGlobal()
			local defs = catalog()

			expect.toBe(Rules.Redeem(newState(), shared, 1, "KESHUSY2026", 0, defs), true)
			expect.toBe(Rules.Redeem(newState(), shared, 2, "KESHUSY2026", 0, defs), true)
			expect.toBe(Rules.Redeem(newState(), shared, 3, "KESHUSY2026", 0, defs), true)

			expect.toBe(shared.RedeemedCodes.keshusy2026, 3)
		end)

		---------------------------------------------------------
		-- CANJE: rechazos
		---------------------------------------------------------

		Harness.it("un codigo inexistente se rechaza y no registra nada", function()
			local shared = newGlobal()
			local accepted, reason = Rules.Redeem(newState(), shared, 1, "NOEXISTE", 0, catalog())

			expect.toBe(accepted, false)
			expect.toBe(reason, Rules.Reject.Unknown)
			-- Un rechazo no deja rastro: ningun codigo queda contado, ni
			-- siquiera un canje a medias que un segundo intento pudiera
			-- confundir con uno completo.
			expect.toBe(shared.RedeemedCodes.keshusy2026, nil)
			expect.toBe(shared.RedeemedCodes.noexiste, nil)
		end)

		Harness.it("un codigo caducado se rechaza", function()
			local state = newState()
			local defs = catalog({ ExpiresAt = 100 })
			local accepted, reason = Rules.Redeem(state, newGlobal(), 1, "KESHUSY2026", 500, defs)

			expect.toBe(accepted, false)
			expect.toBe(reason, Rules.Reject.Expired)
		end)

		Harness.it("un codigo agotado se rechaza para todo el mundo", function()
			local shared = newGlobal()
			local defs = catalog({ MaxRedemptions = 2 })

			-- Dos jugadores distintos consumen los dos usos.
			expect.toBe(Rules.Redeem(newState(), shared, 1, "KESHUSY2026", 0, defs), true)
			expect.toBe(Rules.Redeem(newState(), shared, 2, "KESHUSY2026", 0, defs), true)

			-- Un tercero se lo encuentra agotado: es un rechazo DISTINTO
			-- del "ya lo usaste", porque este jugador si podria si hubiera
			-- un uso libre.
			local accepted, reason = Rules.Redeem(newState(), shared, 3, "KESHUSY2026", 0, defs)
			expect.toBe(accepted, false)
			expect.toBe(reason, Rules.Reject.Exhausted)
		end)

		Harness.it("un codigo mal formado no se canjea", function()
			local state = newState()
			local accepted, reason = Rules.Redeem(state, newGlobal(), 1, "", 0, catalog())

			expect.toBe(accepted, false)
			expect.toBe(reason, Rules.Reject.Malformed)
		end)

		Harness.it("una recompensa rota impide el canje y no lo consume", function()
			-- Es preferible que el canje falle a que el jugador pierda el
			-- codigo sin recibir nada.
			local state = newState()
			local broken = { keshusy2026 = { Code = "KESHUSY2026", Rewards = { Coins = -5 } } }
			local accepted, reason = Rules.Redeem(state, newGlobal(), 1, "KESHUSY2026", 0, broken)

			expect.toBe(accepted, false)
			expect.toBe(reason, Rules.Reject.Malformed)
			expect.toBe(state.Redemptions.keshusy2026, nil)

			-- Y el detalle tecnico explica POR QUE, para el log del servidor.
			local _, _, _, detail = Rules.Redeem(state, newGlobal(), 1, "KESHUSY2026", 0, broken)
			expect.toBe(detail, "bad_amount")
		end)

		---------------------------------------------------------
		-- AISLAMIENTO DE ESPACIOS DE NOMBRES
		---------------------------------------------------------

		Harness.it("un codigo con nombre de jugador no colisiona", function()
			-- El contador global y el perfil del jugador estan en estados
			-- separados: `player12` es un codigo valido y no puede
			-- confundirse con el jugador 12.
			local shared = newGlobal()
			local defs = {
				player12 = { Code = "PLAYER12", Rewards = { Coins = 5 }, MaxRedemptions = 1 },
			}

			local own = newState()
			expect.toBe(Rules.Redeem(own, shared, 12, "PLAYER12", 0, defs), true)
			expect.toBe(shared.RedeemedCodes.player12, 1)
			expect.toBe(own.RedemptionCounts["12"], 1)

			-- Agotado: ni el mismo jugador ni otro pueden repetirlo.
			local accepted, reason = Rules.Redeem(own, shared, 12, "PLAYER12", 0, defs)
			expect.toBe(accepted, false)
			expect.toBe(reason, Rules.Reject.AlreadyUsed)

			local acceptedB, reasonB = Rules.Redeem(newState(), shared, 99, "PLAYER12", 0, defs)
			expect.toBe(acceptedB, false)
			expect.toBe(reasonB, Rules.Reject.Exhausted)
		end)

		Harness.it("un perfil viejo sin las tablas de canjes no rompe nada", function()
			-- Migracion: un perfil guardado antes de que existiera el
			-- sistema no tiene `Redemptions` ni `RedeemedCodes`.
			local legacy = {}
			expect.toBe(Rules.Redeem(legacy, newGlobal(), 1, "KESHUSY2026", 0, catalog()), true)
			expect.toBe(legacy.Redemptions.keshusy2026, true)
		end)

		Harness.it("un estado corrupto se rechaza sin conceder nada", function()
			local accepted, reason = Rules.Redeem("no soy una tabla", newGlobal(), 1, "KESHUSY2026", 0, catalog())

			expect.toBe(accepted, false)
			expect.toBe(reason, "invalid_state")
		end)
	end)
end

return describeCodeRules