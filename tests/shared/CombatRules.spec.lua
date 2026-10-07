--!strict
--[[
	CombatRules.spec
	Combate V2: ataque rapido, dash y habilidad (MASTER MISSION V2 - FASE 8/9).

	Lo que se certifica aqui es la aritmetica del combate: cooldowns,
	ventana de combo, dano del especial y prueba de arco. La lectura de
	personajes y el remoto los prueba el playtest.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local Combat = require("../../src/ReplicatedStorage/Shared/Libraries/CombatRules")

-- Las posiciones son tablas `{X, Z}`: `InArc` va por campos a proposito
-- para no depender del `Vector3` del motor (que aqui no existe).
local function v(x: number, z: number)
	return { X = x, Y = 0, Z = z }
end

local function describeCombatRules()
	Harness.describe("Cooldowns", function()
		Harness.it("la primera accion siempre esta lista", function()
			expect.toBe(Combat.IsReady(nil, Combat.Melee.Cooldown, 100), true)
		end)

		Harness.it("el cooldown bloquea y se cumple", function()
			expect.toBe(Combat.IsReady(100, Combat.Melee.Cooldown, 100.1), false)
			expect.toBe(
				Combat.IsReady(100, Combat.Melee.Cooldown, 100 + Combat.Melee.Cooldown),
				true
			)
		end)

		Harness.it("un reloj invalido no concede nada", function()
			expect.toBe(Combat.IsReady(100, Combat.Melee.Cooldown, "tarde"), false)
			expect.toBe(Combat.IsReady(100, Combat.Melee.Cooldown, 0 / 0), false)
		end)

		Harness.it("el dash y la habilidad son decisiones, no spam", function()
			-- Un dash con cooldown de 0.5 s seria "boton de no me pegues";
			-- la habilidad de area con 2 s vaciaria cada encuentro.
			expect.toBe(Combat.Dash.Cooldown >= 2, true)
			expect.toBe(Combat.Ability.Cooldown >= 6, true)
		end)
	end)

	Harness.describe("Combo", function()
		Harness.it("encadena dentro de la ventana", function()
			expect.toBe(Combat.ComboStep(0, 0, 0), 1)
			expect.toBe(Combat.ComboStep(1, 10, 10.5), 2)
			expect.toBe(Combat.ComboStep(2, 10, 10.5), Combat.Combo.FinisherAt)
		end)

		Harness.it("fuera de la ventana la cadena se reinicia", function()
			local late = 10 + Combat.Combo.Window + 0.1
			expect.toBe(Combat.ComboStep(2, 10, late), 1)
		end)

		Harness.it("el cuarto golpe rapido NO es otro especial", function()
			-- Sin el reinicio, machacar el boton daria un especial cada dos
			-- golpes: el combo dejaria de ser una decision de ritmo.
			expect.toBe(Combat.ComboStep(Combat.Combo.FinisherAt, 10, 10.5), 1)
		end)

		Harness.it("el especial pega mas que el golpe base", function()
			expect.toBe(Combat.DamageFor(1), Combat.Melee.Damage)
			expect.toBe(Combat.DamageFor(Combat.Combo.FinisherAt) > Combat.Melee.Damage, true)
		end)

		Harness.it("la ventana exige ritmo sin machacar", function()
			expect.toBe(Combat.Combo.Window >= 1, true)
			expect.toBe(Combat.Combo.Window <= 2, true)
		end)
	end)

	Harness.describe("Arco del golpe", function()
		local origin = v(0, 0)
		local look = v(0, -1)

		Harness.it("alcanza lo que esta delante y cerca", function()
			expect.toBe(
				Combat.InArc(origin, look, v(0, -6), Combat.Melee.Range, Combat.Melee.MinDot),
				true
			)
		end)

		Harness.it("NO alcanza lo que esta detras", function()
			-- Un golpe que pega hacia atras convierte "apuntar" en decoracion.
			expect.toBe(
				Combat.InArc(origin, look, v(0, 6), Combat.Melee.Range, Combat.Melee.MinDot),
				false
			)
		end)

		Harness.it("NO alcanza fuera de rango", function()
			expect.toBe(
				Combat.InArc(origin, look, v(0, -50), Combat.Melee.Range, Combat.Melee.MinDot),
				false
			)
		end)

		Harness.it("la habilidad alcanza en cualquier direccion", function()
			expect.toBe(
				Combat.InArc(origin, look, v(6, 6), Combat.Ability.Range, Combat.Ability.MinDot),
				true
			)
		end)

		Harness.it("una rampa no rompe el golpe", function()
			-- El alcance se mide en XZ: un enemigo un poco por encima sigue
			-- siendo alcanzable.
			expect.toBe(
				Combat.InArc(
					origin,
					look,
					{ X = 0, Y = 4, Z = -6 },
					Combat.Melee.Range,
					Combat.Melee.MinDot
				),
				true
			)
		end)
	end)

	Harness.describe("Balance", function()
		Harness.it("el melee no desplaza a la bomba", function()
			-- La bomba hace 120 de dano; el melee es la opcion RAPIDA, no la
			-- mejor. Un melee de 80 haria la bomba inutil.
			expect.toBe(Combat.Melee.Damage <= 40, true)
		end)

		Harness.it("la invulnerabilidad del dash es una ventana, no un escudo", function()
			expect.toBe(Combat.Dash.InvulnerabilitySeconds <= 0.5, true)
			expect.toBe(Combat.Dash.InvulnerabilitySeconds > 0, true)
		end)
	end)
end

return describeCombatRules
