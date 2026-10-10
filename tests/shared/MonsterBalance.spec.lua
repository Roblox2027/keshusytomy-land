--!strict
--[[
	MonsterBalance.spec
	Las reglas de BALANCE de los monstruos, comprobadas contra TODOS los
	monstruos declarados.

	POR QUE ESTA SEPARADA DE `AIService.spec`
	--------------------------------------------
	`AIService.spec` prueba la MAQUINA con datos inventados: "si le doy esta
	definicion, devuelve este estado". Esta prueba hace lo contrario: mira los
	monstruos REALES y falla si alguno incumple una regla de juego.

	La separacion importa porque las dos responden a preguntas distintas:
	  - "la IA hace lo que dice"   -> AIService.spec
	  - "lo que dice es jugable"    -> este fichero

	En un solo fichero las dos dan un PASS verde mientras un monstruo corre a
	25 studs/s: la maquina funciona y el juego es injusto.

	REGLAS (las mismas que valida `MonsterDefinitions.GetBalanceProblems`)
	---------------------------------------------------------------------
	1. Ningun `ChaseSpeed` supera la velocidad del jugador.
	2. La ventana de reaccion (`DetectTime + WarningTime`) es >= 0.8 s.
	3. `RecoveryTime` >= 1.5 s: hay tiempo a la bomba siguiente.
	4. Solo la `ChargeSpeed` supera al jugador, y durante <= 0.7 s.
	5. Todo monstruo da recompensa y puede aparecer.
	6. Las personalidades se distinguen entre si.

	Limite honesto: que el NPC se MUEVA de verdad y que el golpe llegue al
	jugador se comprueba en Roblox Studio, no aqui. Eso queda BLOCKED.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

-- NO se declaran stubs de `Color3`/`Enum` aqui a proposito: `require` del
-- interprete standalone ejecuta el modulo en un entorno propio, asi que un
-- global definido en este fichero no seria visible dentro de
-- `MonsterDefinitions`. La guarda esta en el propio modulo, que es donde
-- corresponde.
local AIService = require("../../src/ReplicatedStorage/Shared/Libraries/AIService")
local MonsterDefinitions = require("../../src/ReplicatedStorage/Shared/MonsterDefinitions")

-- Velocidad del jugador: la MISMA constante que usa `AIService`, y a proposito
-- NO se lee de `GameConfig` (no existe fuera de Roblox). El comentario de
-- `AI.GetPlayerSpeed` explica por que el numero esta duplicado.
local PLAYER_SPEED = AIService.GetPlayerSpeed()

local function describeMonsterBalance()
	local ids = MonsterDefinitions.GetIds()

	Harness.describe("Catalogo", function()
		Harness.it("hay al menos ocho monstruos distintos", function()
			-- Ocho es el numero de arquetipos que el juego promete. Con menos,
			-- dos mundos comparten enemigo y el jugador nota el recorte.
			expect.toBe(#ids >= 8, true, ("solo hay %d monstruos"):format(#ids))
		end)

		Harness.it("cada definicion declara los campos de IA por estado", function()
			for _, id in ipairs(ids) do
				local def = MonsterDefinitions.Get(id)

				for _, field in ipairs({
					"PatrolSpeed", "ChaseSpeed", "ChargeSpeed",
					"DetectTime", "WarningTime", "ChargeDuration", "RecoveryTime",
					"LoseTargetRange", "Pressure",
				}) do
					expect.toBe(
						type(def[field]) == "number",
						true,
						("%s no declara %s"):format(id, field)
					)
				end
			end
		end)
	end)
Harness.describe("Regla 1: la persecucion es mas lenta que el jugador", function()
		Harness.it("ningun monstruo corre mas rapido que el jugador al perseguir", function()
			for _, id in ipairs(ids) do
				local def = MonsterDefinitions.Get(id)

				expect.toBe(
					def.ChaseSpeed < PLAYER_SPEED,
					true,
					("%s persigue a %.1f studs/s y el jugador corre a %d")
						:format(id, def.ChaseSpeed, PLAYER_SPEED)
				)
			end
		end)

		Harness.it("la velocidad REAL que aplica la IA tambien lo respeta", function()
			-- Comprueba el valor que devuelve `StateSpeed`, no el declarado: si
			-- la IA calculara otra cosa, la garantia estaria rota aunque el dato
			-- del monstruo fuera correcto.
			for _, id in ipairs(ids) do
				local def = MonsterDefinitions.Get(id)
				local effective = AIService.StateSpeed(def, AIService.States.Chase)

				expect.toBe(
					effective < PLAYER_SPEED,
					true,
					("%s persigue de verdad a %.2f studs/s"):format(id, effective)
				)
			end
		end)

		Harness.it("patrulla nunca es mas rapida que persecucion", function()
			-- Si el monstruo corriera mas rapido SIN objetivo, el jugador no
			-- tendria ventaja en la retirada.
			for _, id in ipairs(ids) do
				local def = MonsterDefinitions.Get(id)
				expect.toBe(
					def.PatrolSpeed <= def.ChaseSpeed,
					true,
					("%s patrulla a %.1f y persigue a %.1f")
						:format(id, def.PatrolSpeed, def.ChaseSpeed)
				)
			end
		end)
	end)

	Harness.describe("Regla 2: hay ventana de reaccion", function()
		Harness.it("todo monstruo avisa al menos 0.8 s antes del primer golpe", function()
			for _, id in ipairs(ids) do
				local def = MonsterDefinitions.Get(id)
				local reaction = def.DetectTime + def.WarningTime

				expect.toBe(
					reaction >= 0.8,
					true,
					("%s solo da %.2f s de aviso"):format(id, reaction)
				)
			end
		end)

		Harness.it("Detect y Warning son estados en los que el monstruo NO se mueve", function()
			-- Si se moviera durante el aviso, el jugador no tendria tiempo a
			-- salir aunque el reloj se lo concediera.
			expect.toBe(AIService.CanMove(AIService.States.Detect), false)
			expect.toBe(AIService.CanMove(AIService.States.Warning), false)
			expect.toBe(AIService.IsTelegraph(AIService.States.Warning), true)
		end)
	end)

	Harness.describe("Regla 3: hay cooldown entre golpes", function()
		Harness.it("todo monstruo descansa al menos 1.5 s tras atacar", function()
			for _, id in ipairs(ids) do
				local def = MonsterDefinitions.Get(id)

				expect.toBe(
					def.RecoveryTime >= 1.5,
					true,
					("%s solo descansa %.2f s entre golpes"):format(id, def.RecoveryTime)
				)
			end
		end)
	end)

	Harness.describe("Regla 4: la carga es corta y telegrafiada", function()
		Harness.it("una carga mas rapida que el jugador dura como mucho 0.7 s", function()
			-- 0.7 s es lo que tarda un jugador lento en reaccionar. Mas alla,
			-- "carga" no es una amenaza: es "te ha alcanzado".
			for _, id in ipairs(ids) do
				local def = MonsterDefinitions.Get(id)

				if def.ChargeSpeed > PLAYER_SPEED then
					expect.toBe(
						def.ChargeDuration <= 0.7,
						true,
						("%s carga a %.1f durante %.2f s: no es esquivable")
							:format(id, def.ChargeSpeed, def.ChargeDuration)
					)
				end
			end
		end)

		Harness.it("la carga siempre queda recortada por el tope global", function()
			-- Un `ChargeSpeed` mal escrito (999) no puede convertir al enemigo
			-- en un muro: es `StateSpeed` quien lo recorta.
			local absurd = { Speed = 10, ChaseSpeed = 10, ChargeSpeed = 999 }
			expect.toBe(
				AIService.StateSpeed(absurd, AIService.States.Attack)
					<= AIService.MaxChargeSpeed(),
				true
			)
		end)
	end)
Harness.describe("Regla 5: todo monstruo tiene recompensa", function()
		Harness.it("XP, monedas y MaxAlive son positivos", function()
			for _, id in ipairs(ids) do
				local def = MonsterDefinitions.Get(id)

				expect.toBe(def.XP > 0, true, ("%s no da XP"):format(id))
				expect.toBe(def.Coins > 0, true, ("%s no da monedas"):format(id))
				expect.toBe(def.MaxAlive > 0, true, ("%s nunca aparece"):format(id))
			end
		end)

		Harness.it("matarlo siempre merece la pena frente al coste de la bomba", function()
			-- Si un monstruo de 200 de vida da 5 XP, la bomba sale cara y el
			-- juego empuja a no jugar. Se miran los DOS lados de la ecuacion:
			-- recompensa alta y bomba barata.
			for _, id in ipairs(ids) do
				local def = MonsterDefinitions.Get(id)
				local bombsToKill = math.ceil(def.Health / 120)

				expect.toBe(
					def.XP >= bombsToKill,
					true,
					("%s cuesta %d bomba(s) y da %d XP")
						:format(id, bombsToKill, def.XP)
				)
			end
		end)
	end)

	Harness.describe("Regla 6: las personalidades se distinguen", function()
		Harness.it("no hay dos monstruos con exactamente los mismos tiempos", function()
			-- Si todos los temporizadores coinciden, el jugador no tiene nada
			-- que aprender entre el Forest y el Cyber: lo unico que cambia es
			-- la vida, y eso se ve en la barra, no se siente.
			local seen = {}

			for _, id in ipairs(ids) do
				local def = MonsterDefinitions.Get(id)
				local signature = table.concat({
					tostring(def.DetectTime),
					tostring(def.WarningTime),
					tostring(def.ChargeDuration),
					tostring(def.RecoveryTime),
				}, "|")

				expect.toBe(
					seen[signature] == nil,
					true,
					("%s tiene los mismos tiempos que %s")
						:format(id, tostring(seen[signature]))
				)
				seen[signature] = id
			end
		end)

		Harness.it("las personalidades prometidas existen de verdad", function()
			-- Sin `Vanishes` no hay Shadow; sin `AppliesSlow` no hay Ice Beast.
			-- Esto convierte el diseño en una garantia verificable.
			local required = {
				Slime = { StillWhenIdle = false },
				Guardian = { StillWhenIdle = true },
				Shadow = { Vanishes = true },
				BombBug = { LeavesBomb = true },
				IceBeast = { AppliesSlow = true },
				FireBeast = { AppliesBurn = true },
			}

			for id, traits in pairs(required) do
				local def = MonsterDefinitions.Get(id)
				expect.toBe(def ~= nil, true, ("falta el monstruo %s"):format(id))

				for trait, expected in pairs(traits) do
					expect.toBe(
						def[trait] == expected,
						true,
						("%s deberia tener %s = %s"):format(id, trait, tostring(expected))
					)
				end
			end
		end)

		Harness.it("el Guardian es el muro, no un perseguidor", function()
			-- Si corriera rapido, dejaria de ser la leccion de POSICION y
			-- seria un Hunter mas lento.
			local def = MonsterDefinitions.Get("Guardian")

			expect.toBe(def.StillWhenIdle, true)
			expect.toBe(def.ChaseSpeed <= 10, true)
			expect.toBe(def.AggroRadius <= 32, true)
			expect.toBe(def.Health >= 120, true)
		end)

		Harness.it("el Hunter supera al jugador SOLO con la carga", function()
			-- Es el enemigo rapido por diseño. La garantia de que el jugador
			-- puede huir esta en que su persecucion es mas lenta y en que la
			-- carga avisa y tiene cooldown largo.
			local def = MonsterDefinitions.Get("Hunter")

			expect.toBe(def.ChaseSpeed < PLAYER_SPEED, true)
			expect.toBe(def.ChargeSpeed > PLAYER_SPEED, true)
			expect.toBe(def.WarningTime >= 0.8, true)
			expect.toBe(def.RecoveryTime >= 4, true)
		end)

		Harness.it("los brainrots zombies conservan sus rasgos en la definicion", function()
			-- Los zombies declaran traits personalizados que identifican su
			-- comportamiento. Si `define` los borra, el monstruo sale como
			-- una caja sin identidad y "no se ven reflejados en el juego".
			local required = {
				Zombini = { AppliesPoison = true },
				Mumifico = { BlocksVision = true },
				Congelado = { AppliesFreeze = true, CrackedIce = true },
				Carbonizado = { AppliesBurn = true, Embers = true },
				Necrobyte = { IsTech = true, StaticDischarge = true },
			}

			for id, traits in pairs(required) do
				local def = MonsterDefinitions.Get(id)
				expect.toBe(def ~= nil, true, ("falta el zombie %s"):format(id))

				for trait, expected in pairs(traits) do
					expect.toBe(
						def[trait] == expected,
						true,
						("%s deberia tener %s = %s"):format(id, trait, tostring(expected))
					)
				end
			end
		end)
	end)

	Harness.describe("Validacion interna", function()
		Harness.it("GetBalanceProblems no reporta ninguno", function()
			-- Es la MISMA comprobacion que hace el servicio al arrancar, pero
			-- aqui falla la suite en vez de dejar un aviso en el log. Un aviso
			-- en el log no lo lee nadie; una suite roja, si.
			local problems = MonsterDefinitions.GetBalanceProblems()
			expect.toBe(#problems, 0, table.concat(problems, "; "))
		end)

		Harness.it("Get devuelve nil para un id inexistente", function()
			expect.toBe(MonsterDefinitions.Get("NoExiste"), nil)
		end)

		Harness.it("GetIds viene ordenado y sin repetidos", function()
			local seen = {}

			for index, id in ipairs(ids) do
				expect.toBe(seen[id] == nil, true, ("id repetido: %s"):format(id))
				seen[id] = true

				if index > 1 then
					expect.toBe(id > ids[index - 1], true, "GetIds no viene ordenado")
				end
			end
		end)
	end)
end

return describeMonsterBalance