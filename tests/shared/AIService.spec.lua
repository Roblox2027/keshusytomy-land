--!strict
--[[
	AIService.spec
	Pruebas de la IA de monstruos.

	POR QUE EXISTEN
	---------------
	`AIService` es lo que decide si un monstruo persigue, se mueve o ataca.
	Si el fallo esta en esa formula (un NaN por normalizar un vector de
	distancia cero, un monstruo que persigue a 400 studs, una velocidad sin
	tope), el sintoma en pantalla es un NPC clavado en el sitio o un NPC
	imparable: dos fallos MUY visibles cuyo origen no se ve en ningun log.

	Por eso la IA se额外saco de `MonsterService` a `Shared/Libraries`:
	desde aqui se prueban de verdad, sin montar Roblox.

	Limite honesto: que el NPC se MUEVA de verdad y que su golpe llegue al
	jugador solo se comprueba en Studio. Eso queda BLOCKED, no PASS.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local AIService = require("../../src/ReplicatedStorage/Shared/Libraries/AIService")

local function describeAIService()
	Harness.describe("Direccion y distancia", function()
		Harness.it("normaliza la direccion en el plano XZ", function()
			local dx, dz = AIService.Direction({ x = 0, z = 0 }, { x = 3, z = 4 })
			expect.toBe(dx, 0.6)
			expect.toBe(dz, 0.8)
		end)

		Harness.it("distancia cero devuelve direccion cero, no NaN", function()
			-- BUG REAL que motivó el modulo: normalizar (0,0) divide 0/0 y
			-- el monstruo se queda vibrando clavado donde estaba.
			local dx, dz = AIService.Direction({ x = 5, z = 5 }, { x = 5, z = 5 })
			expect.toBe(dx, 0)
			expect.toBe(dz, 0)
			expect.toBe(dx ~= dx, false)
		end)

		Harness.it("la distancia es horizontal, ignora la altura", function()
			local d = AIService.Distance(0, 0, 3, 4)
			expect.toBe(d, 5)
		end)
	end)

	Harness.describe("Paso de IA", function()
		Harness.it("persigue un objetivo dentro del rango", function()
			local step = AIService.Step({ X = 0, Y = 0, Z = 0 }, { X = 10, Y = 0, Z = 0 }, 40)
			expect.toBe(step.Move, true)
			expect.toBe(step.Distance, 10)
			expect.toBe(step.Direction.x, 1)
		end)

		Harness.it("NO persigue un objetivo fuera del rango", function()
			-- Sin esto, todos los monstruos del mapa convergian en el
			-- unico jugador vivo.
			local step = AIService.Step({ X = 0, Y = 0, Z = 0 }, { X = 400, Y = 0, Z = 0 }, 40)
			expect.toBe(step.Move, false)
			expect.toBe(step.Distance, 400)
		end)

		Harness.it("un objetivo encima no produce movimiento ni NaN", function()
			local step = AIService.Step({ X = 5, Y = 0, Z = 5 }, { X = 5, Y = 0, Z = 5 }, 40)
			expect.toBe(step.Move, false)
			expect.toBe(step.Distance, 0)
			expect.toBe(step.Direction.x ~= step.Direction.x, false)
		end)

		Harness.it("el limite del rango es inclusivo", function()
			local step = AIService.Step({ X = 0, Y = 0, Z = 0 }, { X = 40, Y = 0, Z = 0 }, 40)
			expect.toBe(step.Move, true)
		end)
	end)

	Harness.describe("Ataque", function()
		Harness.it("ataca dentro del alcance y no fuera", function()
			expect.toBe(AIService.ShouldAttack(5, 6), true)
			expect.toBe(AIService.ShouldAttack(6, 6), true)
			expect.toBe(AIService.ShouldAttack(7, 6), false)
		end)

		Harness.it("el alcance de ataque NO es el de deteccion", function()
			-- Perseguir y atacar son preguntas distintas: se puede seguir a
			-- alguien a 30 studs y no poder golpearle hasta 6.
			local pursuit = AIService.Step({ X = 0, Y = 0, Z = 0 }, { X = 30, Y = 0, Z = 0 }, 40)
			expect.toBe(pursuit.Move, true)
			expect.toBe(AIService.ShouldAttack(pursuit.Distance, 6), false)
		end)
	end)

	Harness.describe("Velocidad", function()
		Harness.it("aplica el multiplicador de persecucion", function()
			expect.toBe(AIService.ChaseSpeed(10, 1.5), 15)
		end)

		Harness.it("un multiplicador absurdo queda acotado", function()
			-- Un 40 en la configuracion haria el NPC instantaneamente
			-- imparable; el tope lo convierte en un fallo de balance y no
			-- en un crash del servidor.
			expect.toBe(AIService.ChaseSpeed(10, 40), 30)
			expect.toBe(AIService.ChaseSpeed(10, 0.1), 10)
		end)
	end)
end

return describeAIService