--!strict
--[[
	CombatMath.spec
	Pruebas de la logica PURA de combate (FASES 4, 5, 8 y 12).

	Por que existen:
	`CombatMath` concentra las FORMULAS que deciden si una bomba mata,
	si una explosion encadena, cuanta vida tiene un bloque y que nivel
	corresponde a una cantidad de XP. Esas formulas vivian dentro de
	servicios que dependen de Workspace, asi que NO se podian probar.
	Ahora si.

	Limite honesto: que el dano llegue de verdad a un Humanoid, que la
	bomba se vea en pantalla o que un muro proteja de forma real solo se
	comprueba en Roblox Studio. Eso queda BLOCKED, no PASS.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local GameConfig = require("../../src/ReplicatedStorage/Shared/Config/GameConfig")
local GameConstants = require("../../src/ReplicatedStorage/Shared/Constants/GameConstants")
local CombatMath = require("../../src/ReplicatedStorage/Shared/Libraries/CombatMath")

local XP_PER_LEVEL = GameConfig.XPPerLevel
local EXPONENT = GameConfig.LevelCurveExponent
local MAX_LEVEL = GameConfig.MaxLevel

local function describeCombatMath()
	Harness.describe("Numeros no finitos", function()
		Harness.it("rechaza NaN e infinito", function()
			expect.toBe(CombatMath.IsFiniteNumber(0), true)
			expect.toBe(CombatMath.IsFiniteNumber(0 / 0), false)
			expect.toBe(CombatMath.IsFiniteNumber(math.huge), false)
			expect.toBe(CombatMath.IsFiniteNumber(-math.huge), false)
		end)

		Harness.it("una posicion con componente no finito se rechaza", function()
			local ok, reason = CombatMath.ValidatePosition(0, 0 / 0, 0)
			expect.toBe(ok, false)
			expect.toContain(tostring(reason), "no finito")
		end)

		Harness.it("una altura absurda se rechaza", function()
			-- Colocarse en el techo por payload manipulado.
			expect.toBe((CombatMath.ValidatePosition(0, 99999, 0)), false)
			expect.toBe((CombatMath.ValidatePosition(0, 0, 0)), true)
		end)
	end)

	Harness.describe("Dano por distancia", function()
		Harness.it("el centro recibe el dano maximo", function()
			expect.toBe(
				CombatMath.FalloffDamage(0, 24, GameConfig.DefaultBombDamage),
				GameConfig.DefaultBombDamage
			)
		end)

		Harness.it("el borde y fuera del borde reciben cero", function()
			expect.toBe(CombatMath.FalloffDamage(24, 24, 120), 0)
			expect.toBe(CombatMath.FalloffDamage(100, 24, 120), 0)
		end)

		Harness.it("nunca devuelve dano negativo (seria una curacion)", function()
			expect.toBe(CombatMath.FalloffDamage(1e9, 24, 120) >= 0, true)
			expect.toBe(CombatMath.FalloffDamage(0, 0, 120), 0)
			expect.toBe(CombatMath.FalloffDamage(0, 24, 0), 0)
		end)

		Harness.it("ningun parametro no finito rompe la aritmetica", function()
			-- Sin este filtro, un radio o dano en infinito devolveria
			-- `inf` y contaminaria la vida del jugador de forma
			-- irreversible (fallo detectado por esta misma suite).
			expect.toBe(CombatMath.FalloffDamage(0 / 0, 24, 120), 0)
			expect.toBe(CombatMath.FalloffDamage(5, 24, 120 / 0), 0)
			expect.toBe(CombatMath.FalloffDamage(5, 24 / 0, 120), 0)
		end)

		Harness.it("el multiplicador de muerte subita aumenta el dano", function()
			-- Es la prueba de que SuddenDeath tiene consecuencias reales.
			local normal = CombatMath.FalloffDamage(12, 24, 120, 1)
			local sudden = CombatMath.FalloffDamage(12, 24, 120, GameConfig.SuddenDeathDamageMultiplier)
			expect.toBe(sudden > normal, true)
		end)
	end)

	Harness.describe("Oclusion por obstaculos", function()
		Harness.it("sin muro el dano pasa intacto", function()
			expect.toBe(CombatMath.ApplyOcclusion(true, 100), 100)
		end)

		Harness.it("con muro el dano baja, pero no a cero", function()
			-- Si fuera 0, un muro seria cobertura absoluta y el PvP
			-- dependeria por completo de la geometria.
			local blocked = CombatMath.ApplyOcclusion(false, 100)
			expect.toBe(blocked < 100, true)
			expect.toBe(blocked > 0, true)
		end)

		Harness.it("el factor se limita al rango valido", function()
			expect.toBe(CombatMath.ApplyOcclusion(false, 100, 5), 100)
			expect.toBe(CombatMath.ApplyOcclusion(false, 100, -5), 0)
		end)
	end)

	Harness.describe("Cadena de reaccion", function()
		local entries = {
			{ X = 0, Z = 0, Id = 10 },
			{ X = 5, Z = 0, Id = 11 },
			{ X = 50, Z = 0, Id = 12 },
		}

		Harness.it("solo incluye las bombas dentro del radio", function()
			expect.toBe(#CombatMath.BuildChain(entries, 0, 0, 12, 0.012), 2)
		end)

		Harness.it("la bomba mas cercana detona primero", function()
			local chain = CombatMath.BuildChain(entries, 0, 0, 12, 0.012)
			expect.toBe(chain[1].Id, 10)
			expect.toBe(chain[2].Id, 11)
			expect.toBe(chain[1].Delay <= chain[2].Delay, true)
		end)

		Harness.it("el resultado es DETERMINISTA (no depende de pairs)", function()
			-- El orden de `pairs` no esta garantizado: sin `table.sort`
			-- la cadena seria distinta en cada ejecucion del servidor.
			local first = CombatMath.BuildChain(entries, 0, 0, 12, 0.012)
			local second = CombatMath.BuildChain(entries, 0, 0, 12, 0.012)
			expect.toBe(#first, #second)

			for i = 1, #first do
				expect.toBe(first[i].Id, second[i].Id)
			end
		end)

		Harness.it("un radio no positivo no encadena nada", function()
			expect.toBe(#CombatMath.BuildChain(entries, 0, 0, 0, 0.012), 0)
		end)
	end)

	Harness.describe("Destruccion de bloques", function()
		Harness.it("el dano a bloques es una fraccion del dano de explosion", function()
			expect.toBe(CombatMath.BlockDamageFromExplosion(120, 0.5), 60)
		end)

		Harness.it("la fraccion se limita a 0..1", function()
			expect.toBe(CombatMath.BlockDamageFromExplosion(100, 5), 100)
			expect.toBe(CombatMath.BlockDamageFromExplosion(100, -1), 0)
		end)

		Harness.it("la vida nunca queda por debajo de cero", function()
			-- Una vida negativa romperia el calculo de cuantas
			-- explosiones faltan para destruir el bloque.
			expect.toBe(CombatMath.ApplyBlockDamage(60, 100), 0)
			expect.toBe(CombatMath.ApplyBlockDamage(60, 10), 50)
			expect.toBe(CombatMath.ApplyBlockDamage(60, -10), 60)
		end)
	end)

	Harness.describe("Curva de progresion", function()
		Harness.it("el nivel 1 no cuesta XP", function()
			expect.toBe(CombatMath.XpForLevel(1, XP_PER_LEVEL, EXPONENT, MAX_LEVEL), 0)
			expect.toBe(CombatMath.LevelForXp(0, XP_PER_LEVEL, EXPONENT, MAX_LEVEL), 1)
		end)

		Harness.it("el nivel SUBE de forma continua, sin tope en 100", function()
			-- El requisito es explicito: nivel 1+ sin limite artificial.
			local level = CombatMath.LevelForXp(1000000000, XP_PER_LEVEL, EXPONENT, MAX_LEVEL)
			expect.toBe(level > 100, true)
		end)

		Harness.it("el nivel es coherente con el coste acumulado", function()
			for _, xp in ipairs({ 0, 50, 250, 5000, 250000 }) do
				local level = CombatMath.LevelForXp(xp, XP_PER_LEVEL, EXPONENT, MAX_LEVEL)
				expect.toBe(CombatMath.XpForLevel(level, XP_PER_LEVEL, EXPONENT, MAX_LEVEL) <= xp, true)

				if level < MAX_LEVEL then
					local nextCost = CombatMath.XpForLevel(level + 1, XP_PER_LEVEL, EXPONENT, MAX_LEVEL)
					expect.toBe(nextCost > xp, true)
				end
			end
		end)

		Harness.it("el progreso dentro del nivel es correcto y no se desborda", function()
			local current, needed = CombatMath.LevelProgress(150, XP_PER_LEVEL, EXPONENT, MAX_LEVEL)
			expect.toBe(current >= 0, true)
			expect.toBe(needed > 0, true)
			expect.toBe(current <= needed, true)
		end)

		Harness.it("en el nivel maximo no se pide mas XP", function()
			local _, needed = CombatMath.LevelProgress(1e12, XP_PER_LEVEL, EXPONENT, MAX_LEVEL)
			expect.toBe(needed, 0)
		end)
	end)

	Harness.describe("Recompensas seguras", function()
		Harness.it("un XP no finito no se aplica", function()
			-- Un NaN en el perfil lo corrompe de forma PERMANENTE.
			expect.toBe(CombatMath.SafeRewardAmount(0 / 0, 100), 0)
			expect.toBe(CombatMath.SafeRewardAmount(math.huge, 100), 0)
		end)

		Harness.it("una recompensa negativa nunca resta", function()
			expect.toBe(CombatMath.SafeRewardAmount(-50, 100), 0)
		end)

		Harness.it("una recompensa valida se trunca a entero", function()
			expect.toBe(CombatMath.SafeRewardAmount(25.7, 0), 25)
		end)

		Harness.it("la sesion nunca queda negativa", function()
			expect.toBe(CombatMath.SafeRewardAmount(10, -50), 0)
		end)
	end)

	Harness.describe("Coherencia con la configuracion", function()
		Harness.it("la cadena no es instantanea", function()
			expect.toBe(GameConfig.ChainReactionDelayPerStud > 0, true)
		end)

		Harness.it("la cadena tiene tope de profundidad", function()
			-- Sin este limite, llenar la arena de bombas tumba el servidor.
			expect.toBe(GameConfig.MaxChainDepth >= 1, true)
		end)

		Harness.it("el radio de cadena cabe dentro de la explosion", function()
			expect.toBe(GameConfig.ChainReactionRadius <= GameConfig.DefaultBombRadius, true)
		end)

		Harness.it("la invulnerabilidad de aparicion es positiva", function()
			expect.toBe(GameConfig.SpawnProtectionTime > 0, true)
		end)

		Harness.it("la muerte subita aumenta el dano", function()
			expect.toBe(GameConfig.SuddenDeathDamageMultiplier > 1, true)
		end)

		Harness.it("una bomba base sigue matando de un golpe en el centro", function()
			expect.toBe(GameConfig.DefaultBombDamage >= 100, true)
		end)

		Harness.it("la muerte subita es un estado real del ciclo", function()
			expect.toBe(GameConstants.RoundState.SuddenDeath ~= nil, true)
		end)

		Harness.it("el dano a bloques es menor que el dano a jugadores", function()
			-- Si fueran iguales, una bomba borraria la estructura entera
			-- ademas de matar: la arena desapareceria de un golpe.
			expect.toBe(GameConfig.BlockDamageScale < 1, true)
		end)
	end)
end

return describeCombatMath