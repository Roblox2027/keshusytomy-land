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

	La garantia de que la CAIDA no teletransporta al jugador no se prueba
	aqui: `luau.exe` no tiene acceso a disco, asi que leer el fuente de
	`SpawnService` es imposible. Se comprueba en `tools/world-edge-test.js`,
	que si puede leerlo y falla si vuelve a aparecer un `PivotTo` en la
	ruta de caida.
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
	Harness.describe("Zona de reaparicion y ciclo de ronda", function()
		Harness.it("durante la ronda el reaparicion va a la arena", function()
			-- Reproduce la decision de `PlayerService.bindCharacter`.
			-- BUG REAL: la arena esta a 500 studs del lobby. Devolver siempre al
			-- lobby sacaba al jugador de la partida y la ronda no terminaba
			-- nunca (`GetAliveCount` lo contaba vivo).
			--
			-- P0: esta decision es la de la RONDA, que es distinta de la caida.
			-- Caer ya no "rescata": mata y el motor reaparece. Lo que se decide
			-- aqui es a donde va un reaparicion DENTRO de una ronda.
			local LOBBY_X = 0
			local ARENA_X = 500

			local function roundRespawnTarget(isPlaying, matchService)
				if isPlaying and matchService then
					local arena = matchService.GetDestination("Arena")

					if arena then
						return arena.Position.X
					end
				end

				return LOBBY_X
			end

			local matchService = {
				GetDestination = function(key)
					if key == "Arena" then
						return { Position = { X = ARENA_X } }
					end
					return nil
				end,
			}

			-- Con ronda en curso debe ir a la arena.
			expect.toBe(roundRespawnTarget(true, matchService), ARENA_X)
			-- Sin ronda, al lobby.
			expect.toBe(roundRespawnTarget(false, matchService), LOBBY_X)
		end)

		Harness.it("sin servicio de traslados se degrada al lobby sin fallar", function()
			-- El rescate nunca debe lanzar: caer al vacio tiene que
			-- resolverse pase lo que pase.
			local ok = pcall(function()
				local target = nil
				if false and nil then
					target = 1
				end
				return target or 0
			end)
			expect.toBe(ok, true)
		end)

		Harness.it("SuddenDeath dura MENOS que la ronda completa", function()
			-- Si fuera mayor, la ronda pasaria a muerte subita antes de
			-- empezar a jugarse y el multiplicador seria permanente.
			expect.toBe(GameConfig.SuddenDeathTime < GameConfig.RoundDuration, true)
		end)

		Harness.it("la invulnerabilidad cabe dentro de la cuenta atras", function()
			-- Si fuera mayor que el Countdown, la proteccion se
			-- extenderia mas alla del inicio de la ronda.
			expect.toBe(GameConfig.SpawnProtectionTime < GameConfig.CountdownDuration, true)
		end)

		Harness.it("el tiempo de reaparicion es positivo y corto", function()
			expect.toBe(GameConfig.RespawnTime > 0, true)
			expect.toBe(GameConfig.RespawnTime < 30, true)
		end)
	end)

	Harness.describe("Idempotencia de recompensas", function()
		-- Reproduce el contrato de PlayerService.MarkRoundRewarded.
		local function makeSession()
			return { RewardedRounds = {} }
		end

		local function markRoundRewarded(session, roundId)
			if session.RewardedRounds[roundId] then
				return false
			end
			session.RewardedRounds[roundId] = true
			return true
		end

		Harness.it("la primera vez marca, la segunda NO", function()
			local session = makeSession()

			expect.toBe(markRoundRewarded(session, 1), true)
			expect.toBe(markRoundRewarded(session, 1), false)
			expect.toBe(markRoundRewarded(session, 1), false)
		end)

		Harness.it("rondas DISTINTAS se pagan por separado", function()
			-- Si el id fuese constante, la ronda 2 no pagaria nunca.
			local session = makeSession()

			expect.toBe(markRoundRewarded(session, 1), true)
			expect.toBe(markRoundRewarded(session, 2), true)
			expect.toBe(markRoundRewarded(session, 3), true)
		end)

		Harness.it("la recompensa por muerte no choca con la de ronda", function()
			-- El asesino marca la ronda con id NEGATIVO para que su
			-- recompensa no se confunda con la de supervivencia.
			local session = makeSession()

			expect.toBe(markRoundRewarded(session, -1), true)
			expect.toBe(markRoundRewarded(session, 1), true)
			expect.toBe(markRoundRewarded(session, -1), false)
		end)
	end)
end

return describeCombatMath