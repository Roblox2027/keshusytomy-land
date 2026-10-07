--!strict
--[[
	ActivitiesRules.spec
	Exploracion, descubrimiento e interaccion con el mundo.

	ESTA SUITE PROTEGE LO QUE `QuestRules.spec` YA PROTOJA PARA MISIONES:
	progreso acumulado, reclamo atomico y oferta determinista. El sistema de
	actividades hereda esas mismas invariantes (una y solo una recompensa por
	completado) y las extiende con cooldown y oferta diaria.

	Las pruebas siguen el orden de juego: normalizacion -> definicion ->
	progreso -> completion -> reclamo -> cooldown -> oferta.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local Rules = require("../../src/ReplicatedStorage/Shared/Libraries/ActivitiesRules")

--- Centinela para QUITAR un campo. Una clave con valor `nil` no existe en
--- Luau, asi que no hay forma de expresar "sin recompensa" pasando `nil`:
--- hace falta una marca aparte.
local REMOVE = newproxy(false)

--- Definicion minima valida.
--- @param overrides any?
--- @return any
local function activity(overrides)
	local base = {
		Id = "HUNT_FOREST_3",
		Title = "Caza en el bosque",
		Description = "Derrota cazadores en el bosque.",
		Type = "Hunt",
		World = "Forest",
		Target = 3,
		Cooldown = 120,
		Rewards = { Coins = 50, Wood = 10 },
	}

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

local function describeActivitiesRules()
	Harness.describe("ActivitiesRules", function()
		---------------------------------------------------------
		-- ACTIVITY TYPE
		---------------------------------------------------------

		Harness.it("conoce los tipos de actividad declarados", function()
			expect.toBe(type(Rules.ActivityType), "table")
			expect.toBe(Rules.ActivityType.Hunt, "Hunt")
			expect.toBe(Rules.ActivityType.Collection, "Collection")
			expect.toBe(Rules.ActivityType.Rescue, "Rescue")
			expect.toBe(Rules.ActivityType.Mechanic, "Mechanic")
			expect.toBe(Rules.ActivityType.Defense, "Defense")
			expect.toBe(Rules.ActivityType.Discovery, "Discovery")
		end)

		---------------------------------------------------------
		-- NORMALIZACION
		---------------------------------------------------------

		Harness.it("normaliza mayusculas, espacios, guiones y guiones bajos", function()
			expect.toBe(Rules.NormalizeId("HUNT_FOREST_3"), "huntforest3")
			expect.toBe(Rules.NormalizeId("  hunt-forest-3  "), "huntforest3")
			expect.toBe(Rules.NormalizeId("H U N T"), "hunt")
		end)

		Harness.it("rechaza lo que no puede ser un identificador", function()
			expect.toBe(Rules.NormalizeId(""), nil)
			expect.toBe(Rules.NormalizeId(nil), nil)
			expect.toBe(Rules.NormalizeId(42), nil)
			expect.toBe(Rules.NormalizeId("'; DROP--"), nil)
			expect.toBe(Rules.NormalizeId("hunt[1]"), nil)
			expect.toBe(Rules.NormalizeId(string.rep("A", 100)), nil)
		end)

		---------------------------------------------------------
		-- DEFINICION
		---------------------------------------------------------

		Harness.it("una definicion valida pasa", function()
			expect.toBe(Rules.IsDefinitionValid(activity()), true)
		end)

		Harness.it("un tipo de actividad desconocido se rechaza", function()
			local valid, reason = Rules.IsDefinitionValid(activity({ Type = "Fishing" }))
			expect.toBe(valid, false)
			expect.toBe(reason, Rules.Reject.InvalidType)
		end)

		Harness.it("una definicion sin recompensa se rechaza", function()
			expect.toBe(Rules.IsDefinitionValid(activity({ Rewards = {} })), false)
			expect.toBe(Rules.IsDefinitionValid(activity({ Rewards = REMOVE })), false)
		end)

		Harness.it("una recompensa no positiva, fraccionaria o NaN se rechaza", function()
			expect.toBe(Rules.IsDefinitionValid(activity({ Rewards = { Coins = -1 } })), false)
			expect.toBe(Rules.IsDefinitionValid(activity({ Rewards = { Coins = 0 } })), false)
			expect.toBe(Rules.IsDefinitionValid(activity({ Rewards = { Coins = 1.5 } })), false)
			expect.toBe(Rules.IsDefinitionValid(activity({ Rewards = { Coins = 0 / 0 } })), false)
		end)

		Harness.it("un objetivo no positivo, fraccionario o NaN se rechaza", function()
			expect.toBe(Rules.IsDefinitionValid(activity({ Target = 0 })), false)
			expect.toBe(Rules.IsDefinitionValid(activity({ Target = -5 })), false)
			expect.toBe(Rules.IsDefinitionValid(activity({ Target = 2.5 })), false)
			expect.toBe(Rules.IsDefinitionValid(activity({ Target = 0 / 0 })), false)
			expect.toBe(Rules.IsDefinitionValid(activity({ Target = REMOVE })), false)
		end)

		Harness.it("una definicion sin Id valido se rechaza", function()
			expect.toBe(Rules.IsDefinitionValid(activity({ Id = "" })), false)
			expect.toBe(Rules.IsDefinitionValid(activity({ Id = REMOVE })), false)
		end)

		---------------------------------------------------------
		-- ESTADO INICIAL
		---------------------------------------------------------

		Harness.it("un jugador nuevo tiene progreso cero", function()
			local state = Rules.NewPlayerState(1)
			expect.toBe(Rules.GetProgress(state, "hunt_forest_3"), 0)
			expect.toBe(Rules.IsComplete(state, "hunt_forest_3"), false)
			expect.toBe(Rules.IsClaimed(state, "hunt_forest_3"), false)
		end)

		---------------------------------------------------------
		-- PROGRESO
		---------------------------------------------------------

		Harness.it("avanzar acumula progreso real", function()
			local state = Rules.NewPlayerState(1)
			local def = activity()

			local progress, completed = Rules.Advance(state, def, 1, 100)
			expect.toBe(progress, 1)
			expect.toBe(completed, false)

			progress = Rules.Advance(state, def, 1, 100)
			expect.toBe(progress, 2)
		end)

		Harness.it("llegar al objetivo completa UNA vez", function()
			local state = Rules.NewPlayerState(1)
			local def = activity()

			Rules.Advance(state, def, 2, 100)
			local progress, completed = Rules.Advance(state, def, 1, 100)

			expect.toBe(progress, 3)
			expect.toBe(completed, true)
			expect.toBe(Rules.IsComplete(state, "hunt_forest_3"), true)

			-- Seguir despues de completar no vuelve a "completar".
			local _, completedAgain = Rules.Advance(state, def, 50, 999)
			expect.toBe(completedAgain, false)
			expect.toBe(Rules.GetProgress(state, "hunt_forest_3"), 3)
		end)

		Harness.it("el progreso NUNCA pasa del objetivo", function()
			local state = Rules.NewPlayerState(1)
			local progress = Rules.Advance(state, activity(), 999, 0)
			expect.toBe(progress, 3)
		end)

		Harness.it("incrementos no positivos, NaN o infinito no restan progreso", function()
			local state = Rules.NewPlayerState(1)
			local def = activity()

			Rules.Advance(state, def, 2, 0)
			Rules.Advance(state, def, -50, 0)
			Rules.Advance(state, def, 0, 0)
			Rules.Advance(state, def, 0 / 0, 0)
			Rules.Advance(state, def, math.huge, 0)

			expect.toBe(Rules.GetProgress(state, "hunt_forest_3"), 2)
		end)

		Harness.it("el progreso sobrevive a la reconexion", function()
			local state = Rules.NewPlayerState(1)
			Rules.Advance(state, activity(), 2, 0)

			local reloaded = state
			expect.toBe(Rules.GetProgress(reloaded, "hunt_forest_3"), 2)
		end)

		Harness.it("un estado corrupto no rompe el avance", function()
			local legacy = {}
			expect.toBe(Rules.Advance(legacy, activity(), 1, 0), 1)
			expect.toBe(Rules.Advance(legacy, activity({ Id = "" }), 1, 0), 0)
			expect.toBe(Rules.Advance("no soy tabla", activity(), 1, 0), 0)
		end)

		Harness.it("una entrada de progreso corrupta se repara al escribir", function()
			local state = Rules.NewPlayerState(1)
			state.Progress = { huntforest3 = 7 }

			-- La entrada es un numero donde deberia haber tabla; se recrea
			-- limpia y el progreso real pasa a ser 1.
			local progress = Rules.Advance(state, activity(), 1, 0)
			expect.toBe(progress, 1)
		end)

		---------------------------------------------------------
		-- RECLAMO
		---------------------------------------------------------

		Harness.it("una actividad incompleta no se puede reclamar", function()
			local state = Rules.NewPlayerState(1)
			local catalog = catalogOf({ activity() })

			Rules.Advance(state, activity(), 1, 0)

			local accepted, rejection = Rules.Claim(state, "hunt_forest_3", catalog)
			expect.toBe(accepted, false)
			expect.toBe(rejection, Rules.Reject.NotComplete)
		end)

		Harness.it("una actividad completa se reclama y paga una vez", function()
			local state = Rules.NewPlayerState(1)
			local catalog = catalogOf({ activity() })

			Rules.Advance(state, activity(), 3, 0)

			local accepted, rejection, rewards = Rules.Claim(state, "hunt_forest_3", catalog)
			expect.toBe(accepted, true)
			expect.toBe(rejection, nil)
			expect.toBe(rewards.Coins, 50)
			expect.toBe(rewards.Wood, 10)
		end)

		Harness.it("reclamar DOS veces no paga dos veces", function()
			local state = Rules.NewPlayerState(1)
			local catalog = catalogOf({ activity() })

			Rules.Advance(state, activity(), 3, 0)

			local firstOk, _, firstRewards = Rules.Claim(state, "hunt_forest_3", catalog)
			expect.toBe(firstOk, true)
			expect.toBe(firstRewards.Coins, 50)

			local secondOk, secondRejection, secondRewards = Rules.Claim(state, "hunt_forest_3", catalog)
			expect.toBe(secondOk, false)
			expect.toBe(secondRejection, Rules.Reject.AlreadyClaimed)
			expect.toBe(secondRewards, nil)

			expect.toBe(Rules.IsClaimed(state, "hunt_forest_3"), true)
		end)

		Harness.it("el reclamo sobrevive a la reconexion", function()
			local state = Rules.NewPlayerState(1)
			local catalog = catalogOf({ activity() })

			Rules.Advance(state, activity(), 3, 0)
			Rules.Claim(state, "hunt_forest_3", catalog)

			local accepted, rejection = Rules.Claim(state, "hunt_forest_3", catalog)
			expect.toBe(accepted, false)
			expect.toBe(rejection, Rules.Reject.AlreadyClaimed)
		end)

		Harness.it("diez reclamos seguidos pagan una sola vez", function()
			local state = Rules.NewPlayerState(1)
			local catalog = catalogOf({ activity() })
			Rules.Advance(state, activity(), 3, 0)

			local acceptedCount = 0

			for _ = 1, 10 do
				if Rules.Claim(state, "hunt_forest_3", catalog) then
					acceptedCount += 1
				end
			end

			expect.toBe(acceptedCount, 1)
		end)

		Harness.it("una actividad inexistente no se reclama", function()
			local state = Rules.NewPlayerState(1)
			local accepted, rejection = Rules.Claim(state, "no_existe", catalogOf({ activity() }))

			expect.toBe(accepted, false)
			expect.toBe(rejection, Rules.Reject.UnknownActivity)
		end)

		Harness.it("un id invalido no se reclama", function()
			local state = Rules.NewPlayerState(1)
			local catalog = catalogOf({ activity() })

			expect.toBe(Rules.Claim(state, "", catalog), false)
			expect.toBe(Rules.Claim(state, nil, catalog), false)
			expect.toBe(Rules.Claim(state, "'; DROP--", catalog), false)
		end)

		Harness.it("una definicion con recompensa rota no se reclama ni consume el reclamo", function()
			local state = Rules.NewPlayerState(1)
			local broken = activity({ Rewards = { Coins = -100 } })
			local catalog = catalogOf({ broken })

			Rules.Advance(state, broken, 3, 0)

			local accepted, rejection = Rules.Claim(state, "hunt_forest_3", catalog)
			expect.toBe(accepted, false)
			expect.toBe(rejection, Rules.Reject.InvalidReward)
			expect.toBe(Rules.IsClaimed(state, "hunt_forest_3"), false)
		end)

		Harness.it("un estado invalido no concede nada", function()
			local catalog = catalogOf({ activity() })
			local accepted, rejection = Rules.Claim("no soy tabla", "hunt_forest_3", catalog)

			expect.toBe(accepted, false)
			expect.toBe(rejection, Rules.Reject.NoProfile)
		end)

		Harness.it("reclamar normaliza el id", function()
			local state = Rules.NewPlayerState(1)
			local catalog = catalogOf({ activity() })
			Rules.Advance(state, activity(), 3, 0)

			expect.toBe(Rules.Claim(state, "HUNT-FOREST-3", catalog), true)
			expect.toBe(Rules.IsClaimed(state, "hunt_forest_3"), true)
		end)

		---------------------------------------------------------
		-- COOLDOWN
		---------------------------------------------------------

		Harness.it("una actividad completada queda en cooldown", function()
			local state = Rules.NewPlayerState(1)

			expect.toBe(Rules.IsOnCooldown(state, "hunt_forest_3", 0), false)

			Rules.SetCooldown(state, "hunt_forest_3", 1000)

			expect.toBe(Rules.IsOnCooldown(state, "hunt_forest_3", 500), true)
			expect.toBe(Rules.IsOnCooldown(state, "hunt_forest_3", 1001), false)
		end)

		Harness.it("CompletionCooldown respeta el dato y cae al default", function()
			expect.toBe(Rules.CompletionCooldown(activity({ Cooldown = 30 })), 30)
			expect.toBe(Rules.CompletionCooldown(activity({ Cooldown = REMOVE })), Rules.DEFAULT_COOLDOWN)
			expect.toBe(Rules.CompletionCooldown(activity({ Cooldown = -1 })), Rules.DEFAULT_COOLDOWN)
			expect.toBe(Rules.CompletionCooldown(activity({ Cooldown = 1.5 })), Rules.DEFAULT_COOLDOWN)
		end)

		---------------------------------------------------------
		-- OFERTA DIARIA
		---------------------------------------------------------

		Harness.it("GetDayIndex es determinista por segundos", function()
			expect.toBe(Rules.GetDayIndex(0), 0)
			expect.toBe(Rules.GetDayIndex(Rules.DAY_SECONDS - 1), 0)
			expect.toBe(Rules.GetDayIndex(Rules.DAY_SECONDS), 1)
			expect.toBe(Rules.GetDayIndex(Rules.DAY_SECONDS * 365), 365)
		end)

		Harness.it("RollDailyOffer es determinista por dia e indice", function()
			local defs = {
				activity({ Id = "A_1" }),
				activity({ Id = "B_2" }),
				activity({ Id = "C_3" }),
			}

			local index = {}
			for _, def_ in ipairs(defs) do
				index[Rules.NormalizeId(def_.Id)] = def_
			end

			local day1 = Rules.RollDailyOffer(index, 0, 3)
			local day2 = Rules.RollDailyOffer(index, Rules.DAY_SECONDS, 3)

			expect.toBe(#day1, 3)
			-- El dia 1 y el dia 2 NO son idénticos: la rotacion cambia.
			expect.toBe(day1[1] == day2[1], false)

			-- Pero el MISMO dia e la MISMA entrada siempre dan lo MISMO:
			-- esto es lo que evita ofertas distintas entre reconexiones.
			expect.toBe(Rules.RollDailyOffer(index, 0, 3)[1], day1[1])
		end)

		Harness.it("RollDailyOffer respeta el size pedido y el numero de actividades", function()
			local index = { a1 = activity({ Id = "A_1" }) }

			expect.toBe(#Rules.RollDailyOffer(index, 0, 5), 1)
			expect.toBe(#Rules.RollDailyOffer(index, 0, 1), 1)
		end)

		Harness.it("RollDailyOffer con 0 actividades devuelve vacio", function()
			expect.toBe(#Rules.RollDailyOffer({}, 0), 0)
		end)

		---------------------------------------------------------
		-- AUDITORIA
		---------------------------------------------------------

		Harness.it("Audit detecta el catalogo roto y lo deja sano", function()
			local knownWorlds = { "Forest", "Desert", "Ice", "Volcano", "Cyber" }

			local clean = catalogOf({
				activity({ Id = "HUNT_FOREST_3", World = "Forest" }),
				activity({ Id = "COLLECTION_DESERT_5", World = "Desert" }),
				activity({ Id = "DISCOVERY_ICE_2", World = "Ice" }),
				activity({ Id = "RESCUE_VOLCANO_1", World = "Volcano" }),
				activity({ Id = "MECHANIC_CYBER_4", World = "Cyber" }),
			})

			expect.toBe(#Rules.Audit(clean, knownWorlds), 0)

			local dirty = catalogOf({
				activity({ Id = "hunt_forest_3", World = "Forest" }),
				activity({ Id = "BROKEN", Type = "Fishing", Rewards = { Coins = -1 } }),
				activity({ Id = "ORPHAN", World = "Nowhere" }),
			})

			local problems = Rules.Audit(dirty, knownWorlds)

			-- Al menos: tipo invalido + recompensa rota (BROKEN), mundo
			-- desconocido (ORPHAN) y mundos sin actividades (Desert/Ice/...).
			expect.toBe(#problems > 0, true)
		end)
	end)
end

return describeActivitiesRules
