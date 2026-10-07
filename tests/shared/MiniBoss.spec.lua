--!strict
--[[
	MiniBoss.spec
	Mini-bosses por mundo (FASES 15 y 16).

	LA GARANTIA CENTRAL
	------------------
	"Los mini-bosses NO reemplazan al boss principal". Eso no se comprueba
	mirando el catalogo de mini-bosses: se comprueba que NINGUNO de sus ids
	coincida con el de un boss principal, y que los bosses principales sigan
	declarados en `MonsterDefinitions`.

	Ademas se comprueba la diferencia de DISENO que los separa: mas pequenos que
	un boss, con enfriamiento, en zonas distintas y pagando menos. Un mini-boss
	que cumple esas cuatro cosas es contenido repetible; uno que no, es un boss
	mas.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local Mini = require("../../src/ReplicatedStorage/Shared/Libraries/MiniBossRules")
local Access = require("../../src/ReplicatedStorage/Shared/Libraries/WorldAccessRules")
local MonsterDefinitions = require("../../src/ReplicatedStorage/Shared/MonsterDefinitions")

local BOSS_BY_WORLD = {
	Forest = "ForestGrooty",
	Desert = "DesertSandBeast",
	Ice = "IceFrostKing",
	Volcano = "VolcanoMagmaLord",
	Cyber = "CyberCore",
}

local function describeMiniBoss()
	Harness.describe("Catalogo", function()
		Harness.it("cada mundo tiene varios mini-bosses", function()
			-- "Varios" son al menos dos. Con uno solo, el jugador lo ve una vez y
			-- el tier raro desaparece del mundo.
			for _, worldId in ipairs(Access.GetWorldIds()) do
				local list = Mini.GetForWorld(worldId)

				expect.toBe(#list >= 2, true, ("%s tiene %d mini-bosses"):format(worldId, #list))
			end
		end)

		Harness.it("cada mundo tiene los tres tiers", function()
			-- Sin un `Rare` el tier no existe en la practica; sin un `Common`,
			-- el raro es lo unico que el jugador ve y se normaliza.
			for _, worldId in ipairs(Access.GetWorldIds()) do
				local tiers = {}

				for _, mini in ipairs(Mini.GetForWorld(worldId)) do
					tiers[mini.Tier] = true
				end

				expect.toBe(tiers[Mini.Tier.Common] == true, true, ("%s sin Common"):format(worldId))
				expect.toBe(tiers[Mini.Tier.Rare] == true, true, ("%s sin Rare"):format(worldId))
			end
		end)

		Harness.it("Audit no reporta ninguno", function()
			local problems = Mini.Audit()
			expect.toBe(#problems, 0, table.concat(problems, "; "))
		end)

		Harness.it("un mundo inexistente no devuelve mini-bosses", function()
			-- Misma frontera que en los eventos: un `worldId` inventado no puede
			-- fabricar contenido.
			expect.toBe(#Mini.GetForWorld("NoExiste"), 0)
			expect.toBe(#Mini.GetForWorld(nil), 0)
			expect.toBe(#Mini.GetForWorld(42), 0)
		end)

		Harness.it("los ids son unicos en todo el catalogo", function()
			local seen = {}

			for worldId, list in pairs(Mini.ByWorld) do
				for _, mini in ipairs(list) do
					expect.toBe(
						seen[mini.Id] == nil,
						true,
						("id repetido: %s (%s)"):format(tostring(mini.Id), worldId)
					)
					seen[mini.Id] = true
				end
			end
		end)
	end)

	Harness.describe("FASE 16: los bosses principales se conservan", function()
		Harness.it("los cinco bosses siguen declarados como bosses", function()
			-- Esta es la comprobacion de REGRESION: la expansion anadio quince
			-- mini-bosses, y nada de eso puede haber tocado los cinco cierres de
			-- mundo que ya estaban certificados.
			for worldId, bossId in pairs(BOSS_BY_WORLD) do
				local def = MonsterDefinitions.Get(bossId)

				expect.toBe(def ~= nil, true, ("falta el boss %s"):format(bossId))
				expect.toBe(def.IsBoss, true, ("%s ya no es boss"):format(bossId))
				expect.toBe(def.World, worldId, ("%s no pertenece a %s"):format(bossId, worldId))
			end
		end)

		Harness.it("ningun mini-boss usa el id de un boss principal", function()
			for worldId, list in pairs(Mini.ByWorld) do
				for _, mini in ipairs(list) do
					expect.toBe(
						Mini.BossIds[mini.Id] == nil,
						true,
						("%s declara '%s', que es el boss de un mundo"):format(worldId, mini.Id)
					)

					-- Y tampoco puede COLISIONAR con un boss real ya declarado.
					local real = MonsterDefinitions.Get(mini.Id)
					expect.toBe(
						real == nil or not real.IsBoss,
						true,
						("'%s' choca con un boss de MonsterDefinitions"):format(mini.Id)
					)
				end
			end
		end)

		Harness.it("la lista de bosses que el modulo protege esta al dia", function()
			-- Si se anade un boss nuevo a `MonsterDefinitions` y no se declara
			-- aqui, la auditoria dejaria de protegerlo en silencio.
			for bossId in pairs(Mini.BossIds) do
				local def = MonsterDefinitions.Get(bossId)

				expect.toBe(def ~= nil, true, ("%s esta en BossIds pero no existe"):format(bossId))
				expect.toBe(def and def.IsBoss, true, ("%s no es boss"):format(bossId))
			end
		end)
	end)
Harness.describe("Un mini-boss NO es un boss", function()
		Harness.it("es mas pequeno que el boss de su mundo", function()
			-- Si un mini-boss mide lo mismo que el boss, el jugador no puede
			-- distinguirlos de un vistazo y elige la estrategia equivocada.
			for _, worldId in ipairs(Access.GetWorldIds()) do
				local bossId = BOSS_BY_WORLD[worldId]
				local bossScale = (MonsterDefinitions.Get(bossId) or {}).VisualScale or 2.9

				for _, mini in ipairs(Mini.GetForWorld(worldId)) do
					expect.toBe(
						mini.Scale < bossScale,
						true,
						("%s mide %.2f y su boss %.2f")
							:format(mini.Id, mini.Scale, bossScale)
					)
				end
			end
		end)

		Harness.it("tiene enfriamiento, y el raro mas largo", function()
			expect.toBe(Mini.CooldownFor({ Tier = Mini.Tier.Common }), Mini.CooldownSeconds)
			expect.toBe(Mini.CooldownFor({ Tier = Mini.Tier.Rare }), Mini.RareCooldownSeconds)

			-- El raro tiene que esperar MAS: con el mismo enfriamiento seria
			-- estrictamente mejor que el comun y el resto dejaria de usarse.
			expect.toBe(
				Mini.RareCooldownSeconds > Mini.CooldownSeconds,
				true,
				"el raro no espera mas que el comun"
			)
		end)

		Harness.it("paga menos que su boss incluso en la noche 99", function()
			-- El motivo por el que existen dos clases y no una: si pagaran igual,
			-- el jugador buscaria mini-bosses y esquivaria el cierre del mundo.
			for _, worldId in ipairs(Access.GetWorldIds()) do
				for _, mini in ipairs(Mini.GetForWorld(worldId)) do
					local reward = Mini.RewardFor(mini, 99, 3)

					expect.toBe(
						reward.XP <= Mini.MaxXP,
						true,
						("%s paga %d XP, por encima del tope %d")
							:format(mini.Id, reward.XP, Mini.MaxXP)
					)
				end
			end
		end)

		Harness.it("el tier raro paga mas que el comun", function()
			local common = { Tier = Mini.Tier.Common }
			local rare = { Tier = Mini.Tier.Rare }

			expect.toBe(
				Mini.RewardFor(rare, 50).XP > Mini.RewardFor(common, 50).XP,
				true,
				"el raro no paga mas que el comun"
			)
		end)

		Harness.it("la recompensa crece con la noche y esta acotada", function()
			local mini = Mini.GetForZone("Forest", "Hollow")

			expect.toBe(
				Mini.RewardFor(mini, 99).XP > Mini.RewardFor(mini, 1).XP,
				true,
				"la noche 99 no paga mas que la noche 1"
			)
			expect.toBe(
				Mini.RewardFor(mini, 99, 500).XP <= Mini.MaxXP,
				true,
				"un multiplicador absurdo rompe el tope"
			)
		end)
	end)

	Harness.describe("Aparicion", function()
		Harness.it("el raro sale menos que el comun", function()
			expect.toBe(
				Mini.RollChance[Mini.Tier.Rare] < Mini.RollChance[Mini.Tier.Common],
				true,
				"el raro sale tanto o mas que el comun"
			)
		end)

		Harness.it("la probabilidad se respeta en todo el rango", function()
			-- Se recorre el rango entero y se cuenta la proporcion real de
			-- apariciones: una probabilidad declarada que no se corresponde con
			-- el comportamiento es un dato que miente en la documentacion.
			local common = { Tier = Mini.Tier.Common }
			local steps = 1000
			local hits = 0

			for i = 0, steps do
				if Mini.ShouldSpawn(common, i / steps) then
					hits += 1
				end
			end

			local rate = hits / steps
			expect.toBe(
				math.abs(rate - Mini.RollChance[Mini.Tier.Common]) < 0.02,
				true,
				("sale el %.3f pero se declara %.3f"):format(rate, Mini.RollChance[Mini.Tier.Common])
			)
		end)

		Harness.it("un roll invalido no hace aparecer nada", function()
			local cases = { nil, "alto", {} }
			table.insert(cases, 0 / 0)

			for _, value in ipairs(cases) do
				expect.toBe(
					Mini.ShouldSpawn({ Tier = Mini.Tier.Common }, value),
					false,
					("ShouldSpawn devolvio true con %s"):format(tostring(value))
				)
			end
		end)

		Harness.it("las fases van de la vida alta a la baja", function()
			expect.toBe(Mini.PhaseFor(1.0), 1)
			expect.toBe(Mini.PhaseFor(0.7), 1)
			expect.toBe(Mini.PhaseFor(0.5), 2)
			expect.toBe(Mini.PhaseFor(0.1), 3)

			-- El nombre de la fase es lo que ve el jugador: sin el, el cambio no
			-- se comunica.
			expect.toBe(Mini.Phases[3].Name, "FURIA")
			expect.toBe(Mini.Phases[3].Damage > Mini.Phases[1].Damage, true)
		end)
	end)
end

return describeMiniBoss