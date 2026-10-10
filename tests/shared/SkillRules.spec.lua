--!strict
--[[
	SkillRules.spec
	Tests para el cálculo de estadísticas de bomba desde habilidades.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local SkillRules = require("../../src/ReplicatedStorage/Shared/Libraries/SkillRules")
local Catalog = require("../../src/ReplicatedStorage/Shared/Config/SkillCatalog")

local function describeSkillRules()
	Harness.describe("ComputeBombStats: estado base", function()
		Harness.it("sin habilidades devuelve ceros y sabor default", function()
			local stats = SkillRules.ComputeBombStats({}, Catalog)

			expect.toBe(stats.capacity, 0)
			expect.toBe(stats.radiusMult, 0)
			expect.toBe(stats.damageMult, 0)
			expect.toBe(stats.flavor, SkillRules.Flavors.Default)
		end)

		Harness.it("argumentos inválidos no rompen el cálculo", function()
			local stats = SkillRules.ComputeBombStats(nil, nil)

			expect.toBe(stats.capacity, 0)
			expect.toBe(stats.flavor, SkillRules.Flavors.Default)
		end)
	end)

	Harness.describe("ComputeBombStats: capacidad", function()
		Harness.it("BombCapacity1 otorga +1", function()
			local stats = SkillRules.ComputeBombStats({ "Skill_BombCapacity1" }, Catalog)

			expect.toBe(stats.capacity, 1)
			expect.toBe(stats.flavor, SkillRules.Flavors.Capacity)
		end)

		Harness.it("BombCapacity3 (Legacy) otorga +3", function()
			local stats = SkillRules.ComputeBombStats({ "Skill_BombCapacity3" }, Catalog)

			expect.toBe(stats.capacity, 3)
			expect.toBe(stats.flavor, SkillRules.Flavors.Capacity)
		end)

		Harness.it("Tier mayor gana: Capacity1 + Capacity3 da +3", function()
			local stats = SkillRules.ComputeBombStats({ "Skill_BombCapacity1", "Skill_BombCapacity3" }, Catalog)

			expect.toBe(stats.capacity, 3)
		end)
	end)

	Harness.describe("ComputeBombStats: daño", function()
		Harness.it("BombDamage1 otorga +15% de daño", function()
			local stats = SkillRules.ComputeBombStats({ "Skill_BombDamage1" }, Catalog)

			expect.toBe(stats.damageMult, 0.15)
			expect.toBe(stats.flavor, SkillRules.Flavors.Damage)
		end)
	end)

	Harness.describe("ComputeBombStats: radio", function()
		Harness.it("BombRadius1 otorga +20% de radio", function()
			local stats = SkillRules.ComputeBombStats({ "Skill_BombRadius1" }, Catalog)

			expect.toBe(stats.radiusMult, 0.20)
			expect.toBe(stats.flavor, SkillRules.Flavors.Radius)
		end)
	end)

	Harness.describe("ComputeBombStats: combinaciones", function()
		Harness.it("daño + radio = sabor poderoso (power)", function()
			local stats = SkillRules.ComputeBombStats({ "Skill_BombDamage1", "Skill_BombRadius1" }, Catalog)

			expect.toBe(stats.damageMult, 0.15)
			expect.toBe(stats.radiusMult, 0.20)
			expect.toBe(stats.flavor, SkillRules.Flavors.Power)
		end)

		Harness.it("capacidad + daño = sabor damage (no power)", function()
			local stats = SkillRules.ComputeBombStats({ "Skill_BombCapacity2", "Skill_BombDamage1" }, Catalog)

			expect.toBe(stats.capacity, 2)
			expect.toBe(stats.damageMult, 0.15)
			expect.toBe(stats.flavor, SkillRules.Flavors.Damage)
		end)

		Harness.it("todas las habilidades de bomba combinadas", function()
			local stats = SkillRules.ComputeBombStats({
				"Skill_BombCapacity3",
				"Skill_BombDamage1",
				"Skill_BombRadius1",
			}, Catalog)

			expect.toBe(stats.capacity, 3)
			expect.toBe(stats.damageMult, 0.15)
			expect.toBe(stats.radiusMult, 0.20)
			expect.toBe(stats.flavor, SkillRules.Flavors.Power)
		end)

		Harness.it("IDs inexistentes son ignorados", function()
			local stats = SkillRules.ComputeBombStats({ "NoExiste", "Skill_BombDamage1" }, Catalog)

			expect.toBe(stats.capacity, 0)
			expect.toBe(stats.damageMult, 0.15)
		end)

		Harness.it("habilidades de otras categorías no aportan nada", function()
			local stats = SkillRules.ComputeBombStats({ "Skill_Speed1", "Skill_MaxHealth1" }, Catalog)

			expect.toBe(stats.capacity, 0)
			expect.toBe(stats.damageMult, 0)
			expect.toBe(stats.radiusMult, 0)
			expect.toBe(stats.flavor, SkillRules.Flavors.Default)
		end)
	end)
end

return describeSkillRules
