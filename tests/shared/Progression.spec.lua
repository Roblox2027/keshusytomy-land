--!strict
--[[
	Progression.spec
	Pruebas de XP, niveles, multi-subida y recompensas de nivel.

	La prueba clave es "cruza varios niveles de una vez". Es el fallo que
	mas se repite en los juegos de progresion: un `if` en lugar de un
	bucle, y el jugador sube un nivel y pierde el resto de la recompensa.

	La curva REAL del proyecto se usa aqui: se inyecta `CombatMath` con
	`GameConfig`, exactamente igual que hara `ProgressionService`. Asi, si
	alguien cambia el balance, estas pruebas describen el juego nuevo y no
	una fiction.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local CombatMath = require("../../src/ReplicatedStorage/Shared/Libraries/CombatMath")
local GameConfig = require("../../src/ReplicatedStorage/Shared/Config/GameConfig")
local ProgressionRules = require("../../src/ReplicatedStorage/Shared/Libraries/ProgressionRules")

-- Las mismas piezas que inyecta el servicio real.
local CURVE = {
	xpPerLevel = GameConfig.XPPerLevel,
	exponent = GameConfig.LevelCurveExponent,
	maxLevel = GameConfig.MaxLevel,
}

local function makeProgression()
	return ProgressionRules.new({
		levelForXp = CombatMath.LevelForXp,
		xpForLevel = CombatMath.XpForLevel,
		levelProgress = CombatMath.LevelProgress,
	})
end

local function newState()
	return ProgressionRules.NewState(1)
end

return function()
	Harness.describe("Progression: XP y nivel", function()
		Harness.it("un jugador nuevo es nivel 1 con 0 XP", function()
			local p = makeProgression()
			local state = newState()
			expect.toBe(p:GetXP(state), 0)
			expect.toBe(p:GetLevel(state, CURVE), 1)
		end)

		Harness.it("anade XP y sube de nivel", function()
			local p = makeProgression()
			local state = newState()

			local ok, result = p:AddXP(state, 100, CURVE, "kill")
			expect.toBe(ok, true)
			expect.toBe(p:GetXP(state), 100)
			expect.toBe(p:GetLevel(state, CURVE), 2)
			expect.toBe(result.levelsGained, 1)
		end)

		Harness.it("el nivel se DERIVA del XP, no se guarda aparte", function()
			-- Si `Level` fuese la fuente de verdad, escribirlo a mano
			-- fabricaria niveles. Aqui se comprueba que no.
			local p = makeProgression()
			local state = newState()
			p:AddXP(state, 100, CURVE, "kill")

			state.Level = 9999
			expect.toBe(p:GetLevel(state, CURVE), 2)
		end)

		Harness.it("rechaza XP cero, negativo, NaN e infinito", function()
			local p = makeProgression()
			local state = newState()

			expect.toBe((p:AddXP(state, 0, CURVE, "x")), false)
			expect.toBe((p:AddXP(state, -50, CURVE, "x")), false)
			expect.toBe((p:AddXP(state, 0 / 0, CURVE, "x")), false)
			expect.toBe((p:AddXP(state, math.huge, CURVE, "x")), false)
			expect.toBe((p:AddXP(state, "mucha", CURVE, "x")), false)

			-- Lo que importa: ninguna de esas llamadas dejo XP.
			expect.toBe(p:GetXP(state), 0)
		end)
	end)

	Harness.describe("Progression: subida de varios niveles", function()
		Harness.it("una recompensa grande cruza TODOS los niveles", function()
			local p = makeProgression()
			local state = newState()

			-- Con la curva del proyecto (XPPerLevel 100, exponente 1.35):
			-- el nivel 2 cuesta 100 y el 3 unos 234. Con 500 XP de golpe el
			-- jugador debe subir mas de un nivel en UNA sola llamada.
			local ok, result = p:AddXP(state, 500, CURVE, "reward_grande")

			expect.toBe(ok, true)
			expect.toBe(p:GetXP(state), 500)
			expect.toBe(result.levelsGained >= 2, true)
			expect.toBe(result.levelAfter, p:GetLevel(state, CURVE))
		end)

		Harness.it("NO se pierde XP al subir varios niveles", function()
			-- El fallo clasico: procesar el multi-nivel CONSUMIENDO el XP
			-- de cada nivel en vez de acumularlo.
			local p = makeProgression()
			local state = newState()

			p:AddXP(state, 500, CURVE, "reward")
			expect.toBe(p:GetXP(state), 500)
		end)

		Harness.it("cada nivel se paga por separado", function()
			-- Si se pagara solo el ultimo, el jugador perderia dos
			-- recompensas sin enterarse.
			local p = makeProgression()
			local state = newState()

			p:AddXP(state, 500, CURVE, "reward")
			local claims = p:ClaimLevelRewards(state, CURVE, { baseCoins = 100, coinsPerLevel = 50 })

			expect.toBe(#claims >= 2, true)
			expect.toBe(claims[1].level, 2)
		end)

		Harness.it("no vuelve a pagar un nivel ya cobrado", function()
			local p = makeProgression()
			local state = newState()

			p:AddXP(state, 500, CURVE, "reward")
			local first = p:ClaimLevelRewards(state, CURVE, { baseCoins = 100 })
			local second = p:ClaimLevelRewards(state, CURVE, { baseCoins = 100 })

			expect.toBe(#first >= 1, true)
			-- La segunda pasada no debe pagar NADA.
			expect.toBe(#second, 0)
		end)

		Harness.it("la recompensa de nivel 1 no existe", function()
			-- Llegar a nivel 1 es el estado inicial: no es un logro.
			local p = makeProgression()
			local state = newState()
			expect.toBe(#p:ClaimLevelRewards(state, CURVE, { baseCoins = 100 }), 0)
		end)
	end)

	Harness.describe("Progression: idempotencia", function()
		Harness.it("la misma recompensa NO sube dos veces", function()
			local p = makeProgression()
			local state = newState()

			p:AddXP(state, 100, CURVE, "kill", "kill-1")
			local xpAfterFirst = p:GetXP(state)

			local ok, result = p:AddXP(state, 100, CURVE, "kill", "kill-1")

			expect.toBe(ok, true)
			expect.toBe(p:GetXP(state), xpAfterFirst)
			-- `levelsGained = 0` es lo que evita que quien llame pague la
			-- recompensa de subida por segunda vez.
			expect.toBe(result.levelsGained, 0)
			expect.toBe(result.Replayed, true)
			-- Y aun asi conserva el nivel alcanzado, para poder responder.
			expect.toBe(result.levelAfter, 2)
		end)

		Harness.it("peticiones DISTINTAS si cuentan", function()
			local p = makeProgression()
			local state = newState()

			p:AddXP(state, 100, CURVE, "kill", "kill-1")
			p:AddXP(state, 100, CURVE, "kill", "kill-2")
			expect.toBe(p:GetXP(state), 200)
		end)
	end)

	Harness.describe("Progression: XP por fuente y limites", function()
		Harness.it("las fuentes se acumulan APARTE", function()
			-- Mezclar XP de evento con XP de jugador daria nivel de mas sin
			-- que nadie lo viera.
			local p = makeProgression()
			local state = newState()

			p:AddXP(state, 100, CURVE, "evento", nil, ProgressionRules.Sources.Event)
			expect.toBe(p:GetXP(state), 100)
			expect.toBe(state.Sources.Event, 100)
		end)

		Harness.it("no deja que el XP pase del tope", function()
			local p = makeProgression()
			local state = newState()
			state.XP = ProgressionRules.MaxXP

			p:AddXP(state, 1000, CURVE, "exploit")
			expect.toBe(p:GetXP(state) <= ProgressionRules.MaxXP, true)
		end)

		Harness.it("una progresion sana no reporta anomalias", function()
			local p = makeProgression()
			local state = newState()
			p:AddXP(state, 250, CURVE, "kill")
			expect.toBe(#p:Audit(state, CURVE), 0)
		end)

		Harness.it("detecta un nivel guardado que no cuadra con el XP", function()
			-- Asi se delata un perfil editado a mano.
			local p = makeProgression()
			local state = newState()
			state.XP = 100
			state.Level = 500

			expect.toBe(#p:Audit(state, CURVE) > 0, true)
		end)

		Harness.it("detecta XP negativo o NaN", function()
			local p = makeProgression()
			local state = newState()

			state.XP = -1
			expect.toBe(#p:Audit(state, CURVE) > 0, true)

			state.XP = 0 / 0
			expect.toBe(#p:Audit(state, CURVE) > 0, true)
		end)
	end)
end