--!strict
--[[
	BrainrotRules.spec
	Tests para las reglas puras de distribución de brainrots (FASE 20).

	Verifica:
	  - Que cada mundo tiene especies de brainrot declaradas.
	  - Que `GetSpecies` devuelve copias independientes.
	  - Que `RollGroups` genera grupos determinísticos.
	  - Que `Audit` valida contra MonsterDefinitions.
	  - Que todos los IDs de brainrot existen en MonsterDefinitions.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local Rules = require("../../src/ReplicatedStorage/Shared/Libraries/BrainrotRules")
local Monsters = require("../../src/ReplicatedStorage/Shared/MonsterDefinitions")

local function deterministicRoll(seed)
	local h = seed
	return function()
		h = (h * 374761393 + 1) % 100000
		return h / 100000
	end
end

return function()
	Harness.describe("Especies por mundo", function()
		Harness.it("todos los mundos tienen especies", function()
			for _, worldId in ipairs(Rules.GetWorlds()) do
				local species = Rules.GetSpecies(worldId)
				expect.toBeTruthy(#species > 0, true)
			end
		end)

		Harness.it("Forest tiene Locotto, Bambino, Bombino y Zombini", function()
			local species = Rules.GetSpecies("Forest")
			expect.toBe(species[1], "Locotto")
			expect.toBe(species[2], "Bambino")
			expect.toBe(species[3], "Bombino")
			expect.toBe(species[4], "Zombini")
		end)

		Harness.it("Cyber tiene Glitchino, Pixeloni, Virusini y Necrobyte", function()
			local species = Rules.GetSpecies("Cyber")
			expect.toBe(species[1], "Glitchino")
			expect.toBe(species[2], "Pixeloni")
			expect.toBe(species[3], "Virusini")
			expect.toBe(species[4], "Necrobyte")
		end)

		Harness.it("un mundo desconocido devuelve tabla vacía", function()
			local species = Rules.GetSpecies("UnknownWorld")
			expect.toBe(#species, 0)
		end)

		Harness.it("GetSpecies devuelve una copia independiente", function()
			local a = Rules.GetSpecies("Forest")
			local b = Rules.GetSpecies("Forest")
			expect.toBe(a[1], b[1])
			a[1] = "Modified"
			expect.toBe(b[1], "Locotto")
		end)
	end)

	Harness.describe("Configuración de grupos", function()
		Harness.it("Forest genera 20 grupos (población masiva FASE 9.5)", function()
			local config = Rules.GetGroupConfig("Forest")
			expect.toBeTruthy(config)
			expect.toBe(config.Groups, 20)
		end)

		Harness.it("Cyber genera 20 grupos", function()
			local config = Rules.GetGroupConfig("Cyber")
			expect.toBe(config.Groups, 20)
		end)

		Harness.it("PerGroup tiene Min y Max coherentes", function()
			for _, worldId in ipairs(Rules.GetWorlds()) do
				local config = Rules.GetGroupConfig(worldId)
				expect.toBeTruthy(config.PerGroup.Min >= 1)
				expect.toBeTruthy(config.PerGroup.Max >= config.PerGroup.Min)
			end
		end)
	end)

	Harness.describe("Población masiva (FASE 9.5)", function()
		Harness.it("cada mundo apunta a 40+ brainrots potenciales", function()
			-- La intención de población: Groups * Min debe superar el rango
			-- pedido (40-80 por mundo). El tope real lo pone MonsterService
			-- (MaxAlive por especie + MaxMonsters global); aquí solo se fija
			-- la INTENCIÓN de que el mapa esté vivo.
			for _, worldId in ipairs(Rules.GetWorlds()) do
				local config = Rules.GetGroupConfig(worldId)
				local minPopulation = config.Groups * config.PerGroup.Min
				local maxPopulation = config.Groups * config.PerGroup.Max
				expect.toBe(minPopulation >= 40, true, (("%s: min %d < 40"):format(worldId, minPopulation)))
				expect.toBe(maxPopulation <= 200, true)
			end
		end)
	end)

	Harness.describe("RollGroups", function()
		Harness.it("genera el número correcto de grupos", function()
			local groups = Rules.RollGroups("Forest", deterministicRoll(42))
			expect.toBeTruthy(groups)
			expect.toBe(#groups, 20)
		end)

		Harness.it("cada grupo tiene Species, Count y Slot", function()
			local groups = Rules.RollGroups("Desert", deterministicRoll(99))
			expect.toBeTruthy(groups)
			for i, group in ipairs(groups) do
				expect.toBeTruthy(group.Species)
				expect.toBeTruthy(type(group.Count) == "number")
				expect.toBe(group.Slot, i - 1)
				expect.toBeTruthy(group.Count >= 1)
				expect.toBeTruthy(group.Count <= 4)
			end
		end)

		Harness.it("es determinista con el mismo roll", function()
			local groups1 = Rules.RollGroups("Ice", deterministicRoll(123))
			local groups2 = Rules.RollGroups("Ice", deterministicRoll(123))

			for i = 1, #groups1 do
				expect.toBe(groups1[i].Species, groups2[i].Species)
				expect.toBe(groups1[i].Count, groups2[i].Count)
			end
		end)

		Harness.it("devuelve nil para un mundo sin especies", function()
			expect.toBeFalsy(Rules.RollGroups("UnknownWorld", deterministicRoll(1)))
		end)

		Harness.it("todas las especies están en MonsterDefinitions", function()
			local groups = Rules.RollGroups("Volcano", deterministicRoll(77))
			expect.toBeTruthy(groups)
			for _, group in ipairs(groups) do
				expect.toBeTruthy(Monsters.Get(group.Species))
			end
		end)
	end)

	Harness.describe("Audit", function()
		Harness.it("no encuentra problemas con MonsterDefinitions real", function()
			local problems = Rules.Audit(Monsters)
			expect.toBe(#problems, 0)
		end)

		Harness.it("detecta una especie falta", function()
			local mock = {
				Get = function(id)
					if id == "Locotto" then
						return { Id = "Locotto" }
					end
					return nil
				end,
			}
			local problems = Rules.Audit(mock)
			expect.toBeTruthy(#problems > 0)
		end)
	end)

	Harness.describe("GetAllSpeciesIds", function()
		Harness.it("devuelve todos los IDs sin duplicados", function()
			local ids = Rules.GetAllSpeciesIds()
			expect.toBeTruthy(#ids > 0)

			-- Sin duplicados: seen[id] debe ser falsy antes de marcar el ID.
			local seen = {}
			for _, id in ipairs(ids) do
				expect.toBeFalsy(seen[id])
				seen[id] = true
				expect.toBeTruthy(Monsters.Get(id))
			end
		end)
	end)

	Harness.describe("GetWorlds", function()
		Harness.it("incluye todos los mundos con brainrots", function()
			local worlds = Rules.GetWorlds()
			expect.toBeTruthy(table.find(worlds, "Forest"))
			expect.toBeTruthy(table.find(worlds, "Desert"))
			expect.toBeTruthy(table.find(worlds, "Ice"))
			expect.toBeTruthy(table.find(worlds, "Volcano"))
			expect.toBeTruthy(table.find(worlds, "Cyber"))
		end)
	end)

	Harness.describe("IsBrainrot", function()
		Harness.it("reconoce una especie brainrot de cada mundo", function()
			expect.toBe(Rules.IsBrainrot("Locotto"), true)
			expect.toBe(Rules.IsBrainrot("Explodini"), true)
			expect.toBe(Rules.IsBrainrot("Fantasmitti"), true)
			expect.toBe(Rules.IsBrainrot("Magmatico"), true)
			expect.toBe(Rules.IsBrainrot("Virusini"), true)
		end)

		Harness.it("no confunde un monstruo normal con brainrot", function()
			-- Los monstruos de arena/jefe NO son fauna brainrot.
			expect.toBe(Rules.IsBrainrot("Slime"), false)
			expect.toBe(Rules.IsBrainrot("Hunter"), false)
			expect.toBe(Rules.IsBrainrot("Grooty"), false)
		end)

		Harness.it("es robusto ante entradas no validas", function()
			-- Un id nil, un numero o una tabla no deben romper la frontera
			-- que consulta `MonsterService` en cada muerte.
			expect.toBe(Rules.IsBrainrot(nil), false)
			expect.toBe(Rules.IsBrainrot(42), false)
			expect.toBe(Rules.IsBrainrot({}), false)
			expect.toBe(Rules.IsBrainrot(""), false)
		end)

		Harness.it("todo id de GetAllSpeciesIds es brainrot", function()
			-- Coherencia: el conjunto O(1) que usa IsBrainrot debe cuadrar
			-- con la lista que devuelve GetAllSpeciesIds.
			for _, id in ipairs(Rules.GetAllSpeciesIds()) do
				expect.toBe(Rules.IsBrainrot(id), true)
			end
		end)
	end)
end
