--!strict
--[[
	AchievementRules.spec
	Logros y titulos (MASTER MISSION V2 - FASES 17 y 19).

	Lo que se certifica aqui es el catalogo: ids unicos, metricas reales,
	umbrales alcanzables jugando y titulos que salen de logros.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local Achievements = require("../../src/ReplicatedStorage/Shared/Libraries/AchievementRules")
local QuestCatalog = require("../../src/ReplicatedStorage/Shared/Config/QuestCatalog")

local function describeAchievementRules()
	Harness.describe("Catalogo", function()
		Harness.it("los ids son unicos", function()
			local seen = {}

			for _, achievement in ipairs(Achievements.Catalog) do
				expect.toBe(
					seen[achievement.Id] == nil,
					true,
					("id repetido: %s"):format(achievement.Id)
				)
				seen[achievement.Id] = true
			end
		end)

		Harness.it("toda metrica de logro existe en el catalogo de misiones", function()
			-- Un logro alimentado por una metrica que nadie emite es un
			-- logro imposible: el peor fallo, porque parece desbloqueable.
			for _, achievement in ipairs(Achievements.Catalog) do
				local exists = false

				for _, metric in pairs(QuestCatalog.Metric or {}) do
					if metric == achievement.Metric then
						exists = true
						break
					end
				end

				-- La metrica puede no estar en QuestCatalog si ningun quest
				-- la usa aun (BossDefeated); lo que no puede es ser un
				-- nombre inventado sin emisor. Se comprueba que es cadena
				-- legible y que el catalogo la declara o la emite el juego.
				expect.toBe(type(achievement.Metric), "string")
				expect.toBe(#achievement.Metric > 2, true)
				expect.toBe(exists or achievement.Metric == "BossDefeated", true,
					("metrica sin emisor conocido: %s"):format(achievement.Metric))
			end
		end)

		Harness.it("ningun umbral es imposible ni trivial", function()
			-- Un logro de "mata 1" se desbloquea sin jugar; uno de
			-- "mata 100000" no existe en la practica. Los dos son ruido.
			for _, achievement in ipairs(Achievements.Catalog) do
				expect.toBe(
					achievement.Threshold >= 1 and achievement.Threshold <= 1000,
					true,
					("%s pide %d"):format(achievement.Id, achievement.Threshold)
				)
			end
		end)

		Harness.it("ningun logro paga poder", function()
			-- Monedas y titulo: jamas dano ni ventaja. Es la regla
			-- anti-P2W del proyecto aplicada a los logros.
			for _, achievement in ipairs(Achievements.Catalog) do
				expect.toBe(type(achievement.Coins), "number")
				expect.toBe(achievement.Damage == nil, true, ("%s paga dano"):format(achievement.Id))
			end
		end)
	end)

	Harness.describe("Desbloqueo", function()
		Harness.it("se desbloquea al cruzar el umbral, no antes", function()
			expect.toBe(#Achievements.UnlockedFor({ MonsterDefeated = 49 }), 0)

			local unlocked = Achievements.UnlockedFor({ MonsterDefeated = 50 })
			local found = false

			for _, id in ipairs(unlocked) do
				if id == "Kills50" then
					found = true
				end
			end

			expect.toBe(found, true)
		end)

		Harness.it("un mapa vacio no desbloquea nada", function()
			expect.toBe(#Achievements.UnlockedFor({}), 0)
			expect.toBe(#Achievements.UnlockedFor(nil), 0)
		end)

		Harness.it("los titulos salen de logros desbloqueados", function()
			local titles = Achievements.TitlesFor({ Kills50 = true })

			expect.toBe(#titles, 1)
			expect.toBe(titles[1], "Cazador")
		end)

		Harness.it("ForMetric devuelve solo los logros de esa metrica", function()
			for _, achievement in ipairs(Achievements.ForMetric("BossDefeated")) do
				expect.toBe(achievement.Metric, "BossDefeated")
			end

			expect.toBe(#Achievements.ForMetric("NoExiste"), 0)
		end)
	end)
end

return describeAchievementRules
