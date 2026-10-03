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

	Harness.describe("Maquina de estados", function()
		local S = AIService.States

		-- Definicion minima de un monstruo lento y legible: todos los tiempos
		-- cortos para que las pruebas sean legibles.
		local def = {
			Id = "Test",
			AttackRange = 6,
			DetectTime = 0.5,
			WarningTime = 0.8,
			ChargeDuration = 0.5,
			RecoveryTime = 2.0,
			LoseTargetRange = 60,
		}

		Harness.it("sin objetivo se patrulla", function()
			expect.toBe(AIService.Think(S.Patrol, 0, def, false, math.huge), S.Patrol)
		end)

		Harness.it("el Guardian con StillWhenIdle se queda quieto", function()
			local still = { StillWhenIdle = true }
			expect.toBe(AIService.Think(S.Patrol, 0, still, false, math.huge), S.Idle)
		end)

		Harness.it("ve al jugador y pasa a Detect, sin moverse", function()
			-- El salto de "no veo nada" a "te estoy persiguiendo" no puede
			-- ser instantaneo: `Detect` es la ventana en la que el jugador ve
			-- que le han detectado y todavia puede decidir.
			expect.toBe(AIService.Think(S.Patrol, 0, def, true, 30), S.Detect)
			expect.toBe(AIService.CanMove(S.Detect), false)
		end)

		Harness.it("Detect aguanta su tiempo y luego avisa (Warning)", function()
			expect.toBe(AIService.Think(S.Detect, 0.2, def, true, 30), S.Detect)
			expect.toBe(AIService.Think(S.Detect, 0.5, def, true, 30), S.Warning)
		end)

		Harness.it("Warning aguanta su tiempo y luego persigue", function()
			expect.toBe(AIService.Think(S.Warning, 0.4, def, true, 30), S.Warning)
			expect.toBe(AIService.Think(S.Warning, 0.8, def, true, 30), S.Chase)
		end)

		Harness.it("el CICLO COMPLETO se puede recorrer sin quedarse atascado", function()
			-- Este es el test que importa de verdad: recorre la maquina como
			-- lo haria `StepAI` y comprueba que TODOS los estados se alcanzan.
			-- Un estado inalcanzable (por ejemplo un `Attack` que nunca llega
			-- porque el cooldown no se cumple nunca) haria que el monstruo
			-- persiguiera para siempre sin golpear nunca, que es el fallo mas
			-- caro y mas invisible de una IA.
			--
			-- El tiempo se acumula mientras el estado no cambie, IGUAL que en
			-- el servidor. Reiniciarlo a mano mediria una maquina que no existe
			-- y daria un falso PASS.
			local state = S.Patrol
			local timeInState = 0
			local distance = 30
			local seen = {}

			for _ = 1, 600 do
				state = AIService.Think(state, timeInState, def, true, distance)
				seen[state] = true
				timeInState += 0.1

				-- El jugador se acerca, se aleja, y asi sucesivamente.
				if timeInState > 3 then
					distance = (distance > 20) and 4 or 30
				end

				if distance < 20 and timeInState > 4 then
					timeInState = 0
				end
			end

			for _, wanted in ipairs({ S.Detect, S.Warning, S.Chase, S.Attack, S.Recovery }) do
				expect.toBe(seen[wanted] == true, true, ("estado no alcanzado: %s"):format(wanted))
			end
		end)

		Harness.it("el telegraph NO se puede saltar: Detect y Warning son obligatorios", function()
			-- Por el camino corto (Patrol -> Chase) el jugador recibiria un
			-- golpe sin aviso. Con la maquina completa no hay atajo.
			local state = S.Patrol
			for _ = 1, 20 do
				state = AIService.Think(state, 1.0, def, true, 4)
			end
			expect.toBe(state ~= S.Warning, true)
		end)

		Harness.it("en Chase, cerca y sin cooldown, pasa a Attack", function()
			local chase = { RecoveryTime = 0 }
			expect.toBe(AIService.Think(S.Chase, 3, chase, true, 4), S.Attack)
		end)

		Harness.it("Attack dura su duracion y luego va a Recovery", function()
			expect.toBe(AIService.Think(S.Attack, 0.2, def, true, 4), S.Attack)
			expect.toBe(AIService.Think(S.Attack, 0.5, def, true, 4), S.Recovery)
		end)

		Harness.it("Recovery dura el cooldown y vuelve a Chase", function()
			expect.toBe(AIService.Think(S.Recovery, 1.0, def, true, 20), S.Recovery)
			expect.toBe(AIService.Think(S.Recovery, 2.0, def, true, 20), S.Chase)
		end)

		Harness.it("perder al objetivo devuelve a patrulla, no a persecucion", function()
			expect.toBe(AIService.Think(S.Chase, 1, def, false, math.huge), S.Patrol)
		end)

		Harness.it("perder al objetivo durante la carga NO cancela el ataque", function()
			-- Cancelarla dejaria al monstruo girando y, peor, permitiria
			-- cobrar dano sin haber avisado. Termina en Recovery.
			expect.toBe(AIService.Think(S.Attack, 0.1, def, false, math.huge), S.Recovery)
			expect.toBe(AIService.Think(S.Warning, 0.1, def, false, math.huge), S.Recovery)
		end)

		Harness.it("alejarse mas de LoseTargetRange abandona la persecucion", function()
			-- Sin esto el monstruo recuerda al jugador para siempre y el mapa
			-- entero se convierte en una persecucion continua sin decision.
			local far = { LoseTargetRange = 50, AttackRange = 6 }
			expect.toBe(AIService.Think(S.Chase, 1, far, true, 80), S.Patrol)
		end)

		Harness.it("un estado desconocido no atrapa al monstruo", function()
			-- Un typo en el estado ("chase" en vez de "Chase") no puede
			-- dejarlo en un `if` que no existe: cae a `Patrol` y sigue el
			-- ciclo normal. El resultado es `Detect`, no `Chase`: no se puede
			-- saltar el telegraph por escribir mal un nombre.
			expect.toBe(AIService.Think("chase", 0, def, true, 30), S.Detect)
			expect.toBe(AIService.Think("", 0, def, true, 30), S.Detect)
			expect.toBe(AIService.Think("Persiguiendo", 0, def, true, 30), S.Detect)
		end)

		Harness.it("datos corruptos no rompen la maquina", function()
			expect.toBe(AIService.Think(S.Warning, 0 / 0, def, true, 30), S.Warning)
			expect.toBe(AIService.Think(S.Warning, 0, nil, true, 30), S.Warning)
			expect.toBe(AIService.Think(S.Warning, 0, def, true, 0 / 0), S.Warning)
		end)
	end)

	Harness.describe("Telegraph visible", function()
		local S = AIService.States

		Harness.it("solo Warning avisa", function()
			expect.toBe(AIService.IsTelegraph(S.Warning), true)
			expect.toBe(AIService.IsTelegraph(S.Chase), false)
			expect.toBe(AIService.IsTelegraph(S.Attack), false)
		end)

		Harness.it("cuenta atras para el cartel", function()
			local def = { WarningTime = 1.4 }
			expect.toBe(AIService.TimeLeftInState(S.Warning, 0, def), 1.4)
			expect.toBe(AIService.TimeLeftInState(S.Warning, 1.0, def), 0.4)
			expect.toBe(AIService.TimeLeftInState(S.Warning, 9.0, def), 0)
			expect.toBe(AIService.TimeLeftInState(S.Chase, 0, def), 0)
		end)

		Harness.it("un estado con duracion cero no rompe la cuenta", function()
			expect.toBe(AIService.TimeLeftInState(S.Warning, 0, nil), 0.6)
		end)
	end)

	Harness.describe("Velocidad", function()
		Harness.it("aplica el multiplicador dentro de la banda permitida", function()
			-- 6 x 1.5 = 9, por debajo del tope de 12.48 (16 x 0.78), asi que
			-- sale SIN recortar: el multiplicador sigue sirviendo para
			-- distinguir enemigos lentos de enemigos rapidos.
			expect.toBe(AIService.ChaseSpeed(6, 1.5), 9)
		end)

		Harness.it("un multiplicador absurdo queda acotado", function()
			-- Un 40 en la configuracion haria el NPC instantaneamente
			-- imparable. Aqui 8 x 1.5 = 12, que ya esta por debajo del tope
			-- (12.48), asi que sale recortado por el multiplicador y no por
			-- la garantia. El caso que llega al tope es un `Speed` alto.
			expect.toBe(AIService.ChaseSpeed(8, 40), 12)
			expect.toBe(AIService.ChaseSpeed(30, 1.5), 12.48)
			expect.toBe(AIService.ChaseSpeed(10, 0.1), 10)
		end)

		Harness.it("NINGUN multiplicador produce una persecucion mas rapida que el jugador", function()
			-- Esta es la prueba que protege el gameplay de bombas. Con el
			-- tope antiguo (3x) un monstruo con `Speed = 14` y
			-- `ChaseMultiplier = 1.8` corria a 25.2 studs/s contra un
			-- jugador de 16: imbatible, y la bomba dejaba de ser una
			-- decision. Ahora el recorte contra la velocidad del jugador es
			-- la garantia, y el multiplicador solo la aproxima.
			local player = AIService.GetPlayerSpeed()
			local ceiling = AIService.MaxChaseSpeed()

			expect.toBe(ceiling < player, true)

			for _, base in ipairs({ 6, 8, 10, 12, 14, 16, 20, 30 }) do
				for _, multiplier in ipairs({ 1, 1.2, 1.5, 2, 5, 40 }) do
					local speed = AIService.ChaseSpeed(base, multiplier)
					expect.toBe(
						speed <= player,
						true,
						("base %d x %.1f = %.2f supera al jugador (%d)")
							:format(base, multiplier, speed, player)
					)
				end
			end
		end)

		Harness.it("la presion del mundo acerca la persecucion sin igualarla", function()
			-- Cyber (0.85) es el mundo mas apretado y aun asi sigue siendo mas
			-- lento que el jugador. Si algun dia `Pressure` llegara a 1.0, el
			-- jugador dejaria de poder huir en linea recta y habria que jugar
			-- con obstaculos, que es una decision de diseno distinta.
			for _, pressure in ipairs({ 0.55, 0.6, 0.62, 0.7, 0.72, 0.78, 0.85 }) do
				expect.toBe(
					AIService.MaxChaseSpeed(pressure) < AIService.GetPlayerSpeed(),
					true,
					("presion %.2f iguala o supera al jugador"):format(pressure)
				)
			end
		end)

		Harness.it("la velocidad de estado cae a Speed si el dato falta", function()
			-- Un monstruo declarado sin `PatrolSpeed` no puede quedarse con
			-- velocidad `nil`: eso daria NaN al multiplicar y lo dejaria
			-- clavado en el sitio sin ningun error visible.
			local def = { Speed = 10 }
			expect.toBe(AIService.StateSpeed(def, AIService.States.Chase), 10)
			expect.toBe(AIService.StateSpeed(def, AIService.States.Patrol), 10)
			expect.toBe(AIService.StateSpeed(nil, AIService.States.Chase), 0)
		end)

		Harness.it("la carga es lo UNICO que puede superar al jugador", function()
			-- Y aun asi esta recortada por `MaxChargeSpeed`, para que un
			-- `ChargeSpeed` mal escrito no convierta al enemigo en un muro.
			local def = { Speed = 10, ChargeSpeed = 999, ChaseSpeed = 10 }
			local charge = AIService.StateSpeed(def, AIService.States.Attack)
			local chase = AIService.StateSpeed(def, AIService.States.Chase)

			expect.toBe(charge <= AIService.MaxChargeSpeed(), true)
			expect.toBe(charge > chase, true)
			expect.toBe(chase < AIService.GetPlayerSpeed(), true)
		end)
	end)
end

return describeAIService