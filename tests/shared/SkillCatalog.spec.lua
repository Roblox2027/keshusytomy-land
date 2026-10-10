--!strict
--[[
	SkillCatalog.spec
	Tests para el catálogo de habilidades pasivas (FASE 20).

	Verifica:
	  - Que `Get` devuelve habilidades válidas.
	  - Que `Has` identifica habilidades existentes.
	  - Que `GetByCategory` filtra por categoría.
	  - Que `GetByWorld` incluye habilidades Legacy.
	  - Que el catálogo con IDs accesibles no tiene referencias rotas.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local Catalog = require("../../src/ReplicatedStorage/Shared/Config/SkillCatalog")
local ChestRules = require("../../src/ReplicatedStorage/Shared/Libraries/ChestRules")

return function()
	Harness.describe("Get", function()
		Harness.it("devuelve una habilidad válida", function()
			local skill = Catalog.Get("Skill_BombCapacity1")
			expect.toBeTruthy(skill)
			expect.toBe(skill.Id, "Skill_BombCapacity1")
			expect.toBeTruthy(skill.Name)
			expect.toBeTruthy(skill.Description)
			expect.toBe(skill.Tier, 1)
		end)

		Harness.it("devuelve nil para una habilidad inexistente", function()
			expect.toBeFalsy(Catalog.Get("NonExistentSkill"))
		end)
	end)

	Harness.describe("Has", function()
		Harness.it("identifica habilidades existentes", function()
			expect.toBe(Catalog.Has("Skill_BombCapacity1"), true)
		end)

		Harness.it("rechaza habilidades inexistentes", function()
			expect.toBe(Catalog.Has("NotASkill"), false)
		end)

		Harness.it("rechaza tipos no string", function()
			expect.toBe(Catalog.Has(nil), false)
			expect.toBe(Catalog.Has(123), false)
		end)
	end)

	Harness.describe("GetByCategory", function()
		Harness.it("Bomb tiene habilidades", function()
			local skills = Catalog.GetByCategory(Catalog.Categories.Bomb)
			expect.toBeTruthy(#skills > 0)
		end)

		Harness.it("solo devuelve habilidades de la categoría", function()
			local skills = Catalog.GetByCategory(Catalog.Categories.Movement)
			for _, skill in ipairs(skills) do
				expect.toBe(skill.Category, Catalog.Categories.Movement)
			end
		end)
	end)

	Harness.describe("GetByWorld", function()
		Harness.it("Forest incluye Common y Legacy", function()
			local all = Catalog.GetAllIds()
			local forestSkills = Catalog.GetByWorld("Forest")
			expect.toBeTruthy(#forestSkills > 0)

			-- Al menos una habilidad es Legacy.
			local hasLegacy = false
			for _, skill in ipairs(forestSkills) do
				if skill.Rarity == Catalog.Rarity.Legacy then
					hasLegacy = true
				end
			end
			expect.toBeTruthy(hasLegacy)
		end)

		Harness.it("un mundo desconocido devuelve tabla vacía", function()
			local skills = Catalog.GetByWorld("UnknownWorld")
			expect.toBe(#skills, 0)
		end)
	end)

	Harness.describe("GetByTier", function()
		Harness.it("Tier 1 Bomb incluye Skill_BombCapacity1", function()
			local tier1 = Catalog.GetByTier(Catalog.Categories.Bomb, 1)
			local found = false
			for _, skill in ipairs(tier1) do
				if skill.Id == "Skill_BombCapacity1" then
					found = true
				end
			end
			expect.toBeTruthy(found)
		end)

		Harness.it("Tier 3 Bomb existe y tiene habilidades", function()
			local tier3 = Catalog.GetByTier(Catalog.Categories.Bomb, 3)
			expect.toBeTruthy(#tier3 > 0)
		end)
	end)

	Harness.describe("GetAllIds", function()
		Harness.it("no tiene duplicados", function()
			local ids = Catalog.GetAllIds()
			local seen = {}
			for _, id in ipairs(ids) do
				expect.toBeFalsy(seen[id])
				seen[id] = true
			end
		end)

		Harness.it("todos los IDs son accesibles vía Get", function()
			local ids = Catalog.GetAllIds()
			expect.toBeTruthy(#ids > 0)
			for _, id in ipairs(ids) do
				expect.toBeTruthy(Catalog.Get(id))
			end
		end)
	end)

	Harness.describe("Categorías y Rareza", function()
		Harness.it("exponen todas las categorías", function()
			expect.toBe(Catalog.Categories.Bomb, "Bomb")
			expect.toBe(Catalog.Categories.Movement, "Movement")
			expect.toBe(Catalog.Categories.Combat, "Combat")
			expect.toBe(Catalog.Categories.Survival, "Survival")
			expect.toBe(Catalog.Categories.Utility, "Utility")
		end)

		Harness.it("exponen todas las rarezas", function()
			expect.toBe(Catalog.Rarity.Common, "Common")
			expect.toBe(Catalog.Rarity.Rare, "Rare")
			expect.toBe(Catalog.Rarity.Epic, "Epic")
			expect.toBe(Catalog.Rarity.Legacy, "Legacy")
		end)
	end)

	Harness.describe("ChestRules.Audit", function()
		Harness.it("ChestRules.Audit valida contra SkillCatalog real", function()
			local problems = ChestRules.Audit()
			expect.toBe(#problems, 0)
		end)
	end)
end
