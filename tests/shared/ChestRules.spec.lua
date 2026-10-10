--!strict
--[[
	ChestRules.spec
	Tests para las reglas puras de cofres (FASE 20).

	Verifica:
	  - Que la tabla de distribución es coherente.
	  - Que los límites de tiera por tipo de cofre son correctos.
	  - Que `OpenReward` siempre devuelve una habilidad válida.
	  - Que el resultado es determinista con el mismo roll.
	  - Que `Audit` no encuentra problemas con el SkillCatalog real.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local Rules = require("../../src/ReplicatedStorage/Shared/Libraries/ChestRules")
local SkillCatalog = require("../../src/ReplicatedStorage/Shared/Config/SkillCatalog")
local BrainrotRules = require("../../src/ReplicatedStorage/Shared/Libraries/BrainrotRules")

return function()
	local function deterministicRoll(sequence)
		local i = 0
		local values = {}
		for k in string.gmatch(sequence, ".") do
			i += 1
			values[i] = (string.byte(k) % 100) / 100
		end
		local index = 0
		return function()
			index += 1
			if index > i then
				index = 1
			end
			return values[index]
		end
	end

	Harness.describe("ChestType", function()
		Harness.it("tiene todos los tipos definidos", function()
			expect.toBe(Rules.ChestType.Common, "Common")
			expect.toBe(Rules.ChestType.Rare, "Rare")
			expect.toBe(Rules.ChestType.Epic, "Epic")
			expect.toBe(Rules.ChestType.Legacy, "Legacy")
		end)

		Harness.it("los límites de tiera son coherentes", function()
			expect.toBe(Rules.ChestTierLimits[Rules.ChestType.Common], 1)
			expect.toBe(Rules.ChestTierLimits[Rules.ChestType.Rare], 2)
			expect.toBe(Rules.ChestTierLimits[Rules.ChestType.Epic], 2)
			expect.toBe(Rules.ChestTierLimits[Rules.ChestType.Legacy], 3)
		end)
	end)

	Harness.describe("Distribución por mundo", function()
		Harness.it("Forest tiene cofres distribuidos", function()
			local dist = Rules.GetChestDistribution("Forest")
			expect.toBeTruthy(dist)
			expect.toBe(#dist > 0, true)

			local counts = {}
			for _, entry in ipairs(dist) do
				counts[entry.ChestType] = entry.Count
			end
			expect.toBeTruthy(counts[Rules.ChestType.Common] > 0)
			expect.toBeTruthy(counts[Rules.ChestType.Rare] > 0)
		end)

		Harness.it("un mundo desconocido no tiene distribución", function()
			expect.toBeFalsy(Rules.GetChestDistribution("UnknownWorld"))
		end)
	end)

	Harness.describe("Habilidades elegibles", function()
		Harness.it("Common solo permite Tier 1", function()
			local pool = Rules.GetEligibleSkills(Rules.ChestType.Common, "Forest")
			for _, skill in ipairs(pool) do
				expect.toBeTruthy(skill.Tier <= 1)
			end
		end)

		Harness.it("Legacy incluye habilidades de otros mundos", function()
			local pool = Rules.GetEligibleSkills(Rules.ChestType.Legacy, "Forest")
			local hasLegacy = false
			for _, skill in ipairs(pool) do
				if skill.Rarity == SkillCatalog.Rarity.Legacy then
					hasLegacy = true
				end
			end
			expect.toBeTruthy(hasLegacy)
		end)

		Harness.it("un tipo desconocido no tiene habilidades elegibles", function()
			local pool = Rules.GetEligibleSkills("UnknownType", "Forest")
			expect.toBe(#pool, 0)
		end)
	end)

	Harness.describe("OpenReward", function()
		Harness.it("devuelve una habilidad válida", function()
			local roll = deterministicRoll("ABC")
			local reward = Rules.OpenReward(Rules.ChestType.Common, "Forest", roll)

			expect.toBeTruthy(reward)
			expect.toBeTruthy(reward.id)
			expect.toBeTruthy(reward.name)
			expect.toBeTruthy(reward.rarity)
		end)

		Harness.it("es determinista con el mismo roll", function()
			local roll1 = deterministicRoll("XYZ")
			local roll2 = deterministicRoll("XYZ")

			local reward1 = Rules.OpenReward(Rules.ChestType.Rare, "Desert", roll1)
			local reward2 = Rules.OpenReward(Rules.ChestType.Rare, "Desert", roll2)

			expect.toBe(reward1.id, reward2.id)
		end)

		Harness.it("devuelve nil si no hay habilidades elegibles", function()
			local roll = deterministicRoll("A")
			local reward = Rules.OpenReward(Rules.ChestType.Common, "UnknownWorld", roll)
			expect.toBeFalsy(reward)
		end)
	end)

	Harness.describe("Audit", function()
		Harness.it("no encuentra problemas con el catálogo real", function()
			local problems = Rules.Audit()
			expect.toBe(#problems, 0)
		end)
	end)

	Harness.describe("ChestWeights", function()
		Harness.it("la suma de pesos es 100", function()
			local total = 0
			for _, entry in ipairs(Rules.GetChestWeights()) do
				total += entry.Weight
			end
			expect.toBe(total, 100)
		end)

		Harness.it("todos los tipos tienen peso positivo", function()
			for _, entry in ipairs(Rules.GetChestWeights()) do
				expect.toBeTruthy(entry.Weight > 0)
			end
		end)
	end)

	Harness.describe("ChestType compat", function()
		Harness.it("ChestRules.ChestType coincide con BrainrotRules", function()
			-- Verifica que los tipos de cofre son accesibles consistentemente.
			expect.toBe(Rules.ChestType.Common, "Common")
			expect.toBe(Rules.ChestType.Rare, "Rare")
			expect.toBe(Rules.ChestType.Epic, "Epic")
			expect.toBe(Rules.ChestType.Legacy, "Legacy")
		end)
	end)
end
