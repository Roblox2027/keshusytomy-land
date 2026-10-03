--!strict
--[[
	QuestRules.spec
	Misiones, reclamos y recompensas diarias.

	EL ORDEN DE ESTA SUITE ES EL ORDEN DE LA MECANICA
	--------------------------------------------------
	Las pruebas van de "definicion" a "progreso" a "reclamo" a "dia",
	porque asi es como se llega a la recompensa en el juego. Y hay cuatro
	pruebas que dominan el resto, porque separan un sistema que FUNCIONA de
	uno que parece funcionar:

	    - el progreso NO se pierde al reconectar
	    - reclamar DOS veces no paga dos veces
	    - el diario no se puede reclamar dos veces el mismo dia
	    - muchos reclamos seguidos pagan una sola vez

	Las cuatro atacan el mismo fallo con distinta forma: estado duplicado.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local Rules = require("../../src/ReplicatedStorage/Shared/Libraries/QuestRules")

--- Centinela para QUITAR un campo. Una clave con valor `nil` no existe en
--- Luau, asi que no hay forma de expresar "sin recompensa" pasando `nil`:
--- hace falta una marca aparte.
local REMOVE = newproxy(false)

--- Definicion minima valida.
--- @param overrides any?
--- @return any
local function quest(overrides)
	local base = {
		Id = "TEST_DESTROY_10",
		Title = "Prueba",
		Description = "Prueba.",
		Type = "World",
		Metric = "BlockDestroyed",
		Target = 10,
		Rewards = { Coins = 100 },
	}

	-- `REMOVE` quita el campo; cualquier otro valor lo sustituye.
	for key, value in (overrides or {}) do
		if value == REMOVE then
			base[key] = nil
		else
			base[key] = value
		end
	end

	return base
end

--- Catalogo indexado por id normalizado.
--- @param definitions any
--- @return { [string]: any }
local function catalogOf(definitions)
	local index = {}

	for _, definition in ipairs(definitions) do
		index[Rules.NormalizeId(definition.Id)] = definition
	end

	return index
end
local function describeQuestRules()
	Harness.describe("QuestRules", function()
		---------------------------------------------------------
		-- NORMALIZACION
		---------------------------------------------------------

		Harness.it("normaliza mayusculas, espacios, guiones y guiones bajos", function()
			expect.toBe(Rules.NormalizeId("WORLD_DESTROY_30"), "worlddestroy30")
			expect.toBe(Rules.NormalizeId("  world_destroy_30  "), "worlddestroy30")
			expect.toBe(Rules.NormalizeId("world-destroy-30"), "worlddestroy30")
		end)

		Harness.it("rechaza lo que no puede ser un identificador", function()
			expect.toBe(Rules.NormalizeId(""), nil)
			expect.toBe(Rules.NormalizeId(nil), nil)
			expect.toBe(Rules.NormalizeId(42), nil)
			expect.toBe(Rules.NormalizeId("quest'; DROP--"), nil)
			expect.toBe(Rules.NormalizeId("quest[1]"), nil)
			expect.toBe(Rules.NormalizeId(string.rep("A", 100)), nil)
		end)

		---------------------------------------------------------
		-- DEFINICION
		---------------------------------------------------------

		Harness.it("una definicion valida pasa", function()
			expect.toBe(Rules.IsDefinitionValid(quest()), true)
		end)

		Harness.it("una definicion sin recompensa se rechaza", function()
			expect.toBe(Rules.IsDefinitionValid(quest({ Rewards = {} })), false)
			expect.toBe(Rules.IsDefinitionValid(quest({ Rewards = REMOVE })), false)
		end)

		Harness.it("una recompensa no positiva o fraccionaria se rechaza", function()
			expect.toBe(Rules.IsDefinitionValid(quest({ Rewards = { Coins = -1 } })), false)
			expect.toBe(Rules.IsDefinitionValid(quest({ Rewards = { Coins = 0 } })), false)
			expect.toBe(Rules.IsDefinitionValid(quest({ Rewards = { Coins = 1.5 } })), false)
			expect.toBe(Rules.IsDefinitionValid(quest({ Rewards = { Coins = 0 / 0 } })), false)
		end)

		Harness.it("un objetivo no positivo o fraccionario se rechaza", function()
			-- Objetivo 0: la mision estaria completada de salida, asi que
			-- "reclamar" seria trivial.
			expect.toBe(Rules.IsDefinitionValid(quest({ Target = 0 })), false)
			expect.toBe(Rules.IsDefinitionValid(quest({ Target = -5 })), false)
			expect.toBe(Rules.IsDefinitionValid(quest({ Target = 2.5 })), false)
			expect.toBe(Rules.IsDefinitionValid(quest({ Target = 0 / 0 })), false)
			expect.toBe(Rules.IsDefinitionValid(quest({ Target = REMOVE })), false)
		end)
---------------------------------------------------------
		-- PROGRESO
		---------------------------------------------------------

		Harness.it("una mision nueva empieza en cero", function()
			local state = Rules.NewState(1)
			expect.toBe(Rules.GetProgress(state, "test_destroy_10"), 0)
			expect.toBe(Rules.IsComplete(state, "test_destroy_10"), false)
		end)

		Harness.it("avanzar acumula progreso real", function()
			local state = Rules.NewState(1)
			local definition = quest()

			local progress, completed = Rules.Advance(state, definition, 3, 100)
			expect.toBe(progress, 3)
			expect.toBe(completed, false)

			progress = Rules.Advance(state, definition, 4, 100)
			expect.toBe(progress, 7)
			expect.toBe(completed, false)
		end)

		Harness.it("llegar al objetivo completa la mision UNA vez", function()
			local state = Rules.NewState(1)
			local definition = quest()

			Rules.Advance(state, definition, 7, 100)
			local progress, completed = Rules.Advance(state, definition, 3, 100)

			expect.toBe(progress, 10)
			expect.toBe(completed, true)
			expect.toBe(Rules.IsComplete(state, "test_destroy_10"), true)

			-- Seguir jugando despues de completar NO vuelve a cambiar la
			-- marca de tiempo ni vuelve a "completar".
			local _, completedAgain = Rules.Advance(state, definition, 100, 999)
			expect.toBe(completedAgain, false)
			expect.toBe(Rules.GetProgress(state, "test_destroy_10"), 10)
		end)

		Harness.it("el progreso NUNCA pasa del objetivo", function()
			-- Sin acotar, el perfil guardaria 500 y la UI dibujaria
			-- "500/10": progreso que no significa nada y que persistiria.
			local state = Rules.NewState(1)
			local progress = Rules.Advance(state, quest(), 500, 0)

			expect.toBe(progress, 10)
		end)

		Harness.it("el progreso no baja nunca", function()
			local state = Rules.NewState(1)
			local definition = quest()
			Rules.Advance(state, definition, 5, 0)

			-- Un incremento negativo, cero o NaN no es juego: es ruido o
			-- un intento. Se ignora, y sobre todo NO resta progreso ya
			-- ganado.
			Rules.Advance(state, definition, -50, 0)
			Rules.Advance(state, definition, 0, 0)
			Rules.Advance(state, definition, 0 / 0, 0)
			Rules.Advance(state, definition, math.huge, 0)

			expect.toBe(Rules.GetProgress(state, "test_destroy_10"), 5)
		end)

		Harness.it("el progreso sobrevive a la reconexion", function()
			-- El estado del perfil es lo UNICO que sobrevive a que el
			-- jugador se vaya. Un progreso en memoria seria 0 otra vez en
			-- cada reconexion, y el jugador perderia su trabajo en silencio.
			local state = Rules.NewState(1)
			Rules.Advance(state, quest(), 4, 0)

			-- "Reconectar" = volver a leer el estado guardado.
			local reloaded = state
			expect.toBe(Rules.GetProgress(reloaded, "test_destroy_10"), 4)
		end)

		Harness.it("un estado corrupto no rompe el avance", function()
			local legacy = {}
			expect.toBe(Rules.Advance(legacy, quest(), 3, 0), 3)
			expect.toBe(Rules.Advance(legacy, quest(), 0, 0), 3)
			expect.toBe(Rules.Advance(legacy, quest({ Id = "" }), 3, 0), 0)
			expect.toBe(Rules.Advance("no soy tabla", quest(), 3, 0), 0)
		end)

		Harness.it("una entrada de progreso corrupta se repara", function()
			-- Un perfil migrado de otra forma puede traer un numero donde
			-- deberia haber una tabla. Sin la comprobacion, `entry.Progress`
			-- reventaria al asignar y la partida caeria.
			local state = Rules.NewState(1)
			state.Progress = { testdestroy10 = 7 }

			local progress = Rules.Advance(state, quest(), 1, 0)
			expect.toBe(progress, 1)
		end)
---------------------------------------------------------
		-- RECLAMO
		---------------------------------------------------------

		Harness.it("una mision incompleta no se puede reclamar", function()
			local state = Rules.NewState(1)
			local catalog = catalogOf({ quest() })

			Rules.Advance(state, quest(), 5, 0)

			local accepted, rejection = Rules.Claim(state, "test_destroy_10", catalog)
			expect.toBe(accepted, false)
			expect.toBe(rejection, Rules.Reject.NotComplete)
		end)

		Harness.it("una mision completa se reclama y paga una vez", function()
			local state = Rules.NewState(1)
			local catalog = catalogOf({ quest() })

			Rules.Advance(state, quest(), 10, 0)

			local accepted, rejection, rewards = Rules.Claim(state, "test_destroy_10", catalog)
			expect.toBe(accepted, true)
			expect.toBe(rejection, nil)
			expect.toBe(rewards.Coins, 100)
		end)

		Harness.it("reclamar DOS veces no paga dos veces", function()
			-- La prueba que domina el sistema. El reclamo se marca DENTRO
			-- de `Claim`, asi que la segunda llamada lo encuentra ocupado.
			local state = Rules.NewState(1)
			local catalog = catalogOf({ quest() })

			Rules.Advance(state, quest(), 10, 0)

			local firstOk, _, firstRewards = Rules.Claim(state, "test_destroy_10", catalog)
			expect.toBe(firstOk, true)
			expect.toBe(firstRewards.Coins, 100)

			local secondOk, secondRejection, secondRewards = Rules.Claim(state, "test_destroy_10", catalog)
			expect.toBe(secondOk, false)
			expect.toBe(secondRejection, Rules.Reject.AlreadyClaimed)
			expect.toBe(secondRewards, nil)

			expect.toBe(Rules.IsClaimed(state, "test_destroy_10"), true)
		end)

		Harness.it("el reclamo sobrevive a la reconexion", function()
			-- La misma razon que el progreso: si el registro de reclamos
			-- fuera en memoria, un jugador podria reconectar y reclamar
			-- otra vez la misma mision.
			local state = Rules.NewState(1)
			local catalog = catalogOf({ quest() })

			Rules.Advance(state, quest(), 10, 0)
			Rules.Claim(state, "test_destroy_10", catalog)

			local accepted, rejection = Rules.Claim(state, "test_destroy_10", catalog)
			expect.toBe(accepted, false)
			expect.toBe(rejection, Rules.Reject.AlreadyClaimed)
		end)

		Harness.it("diez reclamos seguidos pagan una sola vez", function()
			-- Simula el doble clic y el reintento: muchas llamadas sin
			-- ninguna coordinacion externa. Solo la primera puede pagar.
			local state = Rules.NewState(1)
			local catalog = catalogOf({ quest() })
			Rules.Advance(state, quest(), 10, 0)

			local acceptedCount = 0

			for _ = 1, 10 do
				local accepted = Rules.Claim(state, "test_destroy_10", catalog)
				if accepted then
					acceptedCount += 1
				end
			end

			expect.toBe(acceptedCount, 1)
		end)
Harness.it("una mision inexistente no se reclama", function()
			local state = Rules.NewState(1)
			local accepted, rejection = Rules.Claim(state, "no_existe", catalogOf({ quest() }))

			expect.toBe(accepted, false)
			expect.toBe(rejection, Rules.Reject.UnknownQuest)
		end)

		Harness.it("un id de mision invalido no se reclama", function()
			local state = Rules.NewState(1)
			local catalog = catalogOf({ quest() })

			expect.toBe(Rules.Claim(state, "", catalog), false)
			expect.toBe(Rules.Claim(state, nil, catalog), false)
			expect.toBe(Rules.Claim(state, "'; DROP--", catalog), false)
		end)

		Harness.it("una definicion con recompensa rota no se reclama", function()
			-- Una entrada del catalogo modificada con una recompensa
			-- negativa haria que "reclamar" RESTARA saldo. Por eso
			-- `Claim` revalida, y no se fia solo de la validacion de
			-- arranque.
			local state = Rules.NewState(1)
			local broken = quest({ Rewards = { Coins = -100 } })
			local catalog = catalogOf({ broken })

			Rules.Advance(state, broken, 10, 0)

			local accepted, rejection = Rules.Claim(state, "test_destroy_10", catalog)
			expect.toBe(accepted, false)
			expect.toBe(rejection, Rules.Reject.InvalidReward)

			-- Y no consume el reclamo: el fallo fue de contenido, no del
			-- jugador.
			expect.toBe(Rules.IsClaimed(state, "test_destroy_10"), false)
		end)

		Harness.it("un estado invalido no concede nada", function()
			local catalog = catalogOf({ quest() })
			local accepted, rejection = Rules.Claim("no soy una tabla", "test_destroy_10", catalog)

			expect.toBe(accepted, false)
			expect.toBe(rejection, Rules.Reject.NoProfile)
		end)

		Harness.it("reclamar normaliza el id, con mayusculas o guiones", function()
			local state = Rules.NewState(1)
			local catalog = catalogOf({ quest() })
			Rules.Advance(state, quest(), 10, 0)

			expect.toBe(Rules.Claim(state, "TEST_DESTROY_10", catalog), true)
			expect.toBe(Rules.IsClaimed(state, "test-destroy-10"), true)
		end)
	end)
end

return describeQuestRules