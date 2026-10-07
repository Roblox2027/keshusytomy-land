--!strict
--[[
	Difficulty.spec
	La dificultad de (mundo, noche, evento) (FASES 4, 8 y 32).

	EL ARGUMENTO CENTRAL
	--------------------
	"El enunciado prohibe las multiplicaciones absurdas". Eso NO se comprueba
	mirando un par de casos: se comprueba recorriendo TODAS las combinaciones
	de mundo y noche y verificando dos cosas en cada una:

	  1. que el perfil este DENTRO de los topes declarados;
	  2. que la dificultad CREZCA de forma monotona al avanzar la noche.

	La segunda es la importante: una noche mas alta que devuelve menos enemigos
	es un bug, y el jugador no puede aprender una regla que no se cumple.

	LA SEGUNDA REGLA
	----------------
	Los enemigos NO se vuelven imposibles solo por vida. Se comprueba que la
	vida sube MAS despacio que la cantidad, que es la razon por la que la vida
	tiene un tope mas bajo: mas enemigos es una decision de espacio, mas vida es
	una cuenta pendiente.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local Diff = require("../../src/ReplicatedStorage/Shared/Libraries/DifficultyRules")
local Access = require("../../src/ReplicatedStorage/Shared/Libraries/WorldAccessRules")

local WORLDS = Access.GetWorldIds()

local function describeDifficulty()
	Harness.describe("Factor de mundo", function()
		Harness.it("el mundo mas dificil da mas presion que el mas facil", function()
			for _, axis in ipairs({ "Health", "Damage", "Count", "Reward" }) do
				local forest = Diff.NightFactor(50, axis) * Diff.WorldFactor("Forest")
				local cyber = Diff.NightFactor(50, axis) * Diff.WorldFactor("Cyber")

				expect.toBe(
					cyber >= forest,
					true,
					("en el eje %s, Cyber (%s) no es mas duro que Forest (%s)")
						:format(axis, tostring(cyber), tostring(forest))
				)
			end
		end)

		Harness.it("acepta tanto el id como el numero de dificultad", function()
			-- Sin esta equivalencia, pasar "Cyber" donde se esperaba 5 daria
			-- `tonumber` nil y el Cyber seria tan facil como el Forest.
			expect.toBeClose(Diff.WorldFactor("Cyber"), Diff.WorldFactor(5), 1e-9)
			expect.toBeClose(Diff.WorldFactor("Forest"), Diff.WorldFactor(1), 1e-9)
		end)

		Harness.it("un valor inutil devuelve 1.0, no cero ni NaN", function()
			local cases = { nil, 0 / 0, "basura", {} }
			table.insert(cases, -3)

			for _, value in ipairs(cases) do
				local f = Diff.WorldFactor(value)
				expect.toBe(f >= 1, true, ("factor invalido: %s"):format(tostring(f)))
			end
		end)
	end)

	Harness.describe("Topes (FASE 38: rendimiento y jugabilidad)", function()
		Harness.it("ninguna combinacion se sale de los topes declarados", function()
			-- Se recorren los cinco mundos por las 99 noches, con y sin evento.
			-- Es la comprobacion que sustituye a "confiar en que el balance esta
			-- bien": si alguien sube un multiplicador sin subir el tope, esto
			-- falla aqui y no en un playtest con 200 NPC en pantalla.
			for _, world in ipairs(WORLDS) do
				for night = 1, 99 do
					for _, eventMul in ipairs({ 1, 1.35, 2 }) do
						local p = Diff.Resolve(world, night, eventMul, 12)

						expect.toBe(
							p.Health <= Diff.Caps.Health + 1e-9,
							true,
							("%s noche %d: vida %.2f supera el tope %.2f")
								:format(world, night, p.Health, Diff.Caps.Health)
						)
						expect.toBe(
							p.Damage <= Diff.Caps.Damage + 1e-9,
							true,
							("%s noche %d: dano %.2f supera el tope %.2f")
								:format(world, night, p.Damage, Diff.Caps.Damage)
						)
						expect.toBe(
							p.MaxAlive <= Diff.AbsoluteMaxAlive,
							true,
							("%s noche %d: %d vivos superan el tope %d")
								:format(world, night, p.MaxAlive, Diff.AbsoluteMaxAlive)
						)
					end
				end
			end
		end)

		Harness.it("la poblacion nunca crece sin limite", function()
			-- El caso patologico: una zona con poblacion base alta, en la noche
			-- 99 y con evento fuerte, es donde "poblacion dinamica" se convierte
			-- en "el servidor no responde".
			local worst = Diff.Resolve("Cyber", 99, 2, 40)
			expect.toBe(worst.MaxAlive <= Diff.AbsoluteMaxAlive, true)
			expect.toBe(worst.MaxAlive >= 1, true)
		end)
	end)
Harness.describe("Progresion", function()
		Harness.it("la dificultad CRECE al avanzar la noche, sin saltos", function()
			for _, world in ipairs(WORLDS) do
				local previous = 0

				for night = 1, 99 do
					local p = Diff.Resolve(world, night)

					expect.toBe(
						p.Count >= previous - 1e-9,
						true,
						("%s noche %d tiene menos poblacion que la anterior")
							:format(world, night)
					)

					previous = p.Count
				end
			end
		end)

		Harness.it("la noche 99 es la mas dura de todas", function()
			for _, world in ipairs(WORLDS) do
				local first = Diff.Resolve(world, 1)
				local last = Diff.Resolve(world, 99)

				expect.toBe(last.Count > first.Count, true, ("%s: noche 99 sin mas poblacion"):format(world))
				expect.toBe(last.Health > first.Health, true, ("%s: noche 99 sin mas vida"):format(world))
			end
		end)

		Harness.it("la vida sube MAS despacio que la cantidad", function()
			-- La razon de diseno del tope mas bajo de `Health`: mas enemigos se
			-- esquiva con decision de espacio; mas vida exige mas bombas de las
			-- que caben en la capacidad base del jugador.
			local first = Diff.Resolve("Forest", 1)
			local last = Diff.Resolve("Forest", 99)
			local growthCount = last.Count / first.Count
			local growthHealth = last.Health / first.Health

			expect.toBe(
				growthCount > growthHealth,
				true,
				("la cantidad crece x%.2f y la vida x%.2f: la vida deberia crecer menos")
					:format(growthCount, growthHealth)
			)
		end)

		Harness.it("un evento sube la presion pero no rompe el tope", function()
			local base = Diff.Resolve("Ice", 40, 1)
			local withEvent = Diff.Resolve("Ice", 40, 1.5)

			expect.toBe(withEvent.Count > base.Count, true, "el evento no sube la poblacion")
			expect.toBe(withEvent.MaxAlive <= Diff.AbsoluteMaxAlive, true)
			expect.toBe(withEvent.Health <= Diff.Caps.Health + 1e-9, true)
		end)

		Harness.it("la recompensa sube con la dificultad, para que compense", function()
			-- Sin esto, "cada vez mas dificil" seria una perdida neta y el
			-- jugador buscaria la noche 1 para siempre.
			local first = Diff.Resolve("Desert", 1)
			local last = Diff.Resolve("Desert", 99)

			expect.toBe(last.Reward > first.Reward, true, "la noche 99 no recompensa mas")
			expect.toBe(last.Reward <= Diff.Caps.Reward + 1e-9, true)
		end)
	end)

	Harness.describe("Aplicacion a monstruos", function()
		Harness.it("no muta la definicion original", function()
			-- Si mutara, la segunda zona veria los numeros de la primera y la
			-- escala seria ACUMULATIVA. Es el fallo mas caro del sistema y el
			-- mas dificil de ver sin esta comprobacion.
			local original = { Health = 100, Damage = 10, XP = 20, Coins = 5, MaxAlive = 8 }

			local p = Diff.Resolve("Cyber", 80, 1.5, 10)
			local scaled = Diff.ApplyToMonster(original, p)

			expect.toBe(scaled.Health > original.Health, true)
			expect.toBe(original.Health, 100, "la definicion original fue mutada")
			expect.toBe(original.Damage, 10, "la definicion original fue mutada")
			expect.toBe(original.XP, 20, "la definicion original fue mutada")
		end)

		Harness.it("nunca deja un enemigo con vida o dano cero", function()
			-- Un `Health` de 0 en un Humanoid es un enemigo que ya esta muerto y
			-- que el jugador no puede derribar: es el bug de "Health = 0 pero
			-- sigue vivo", con otro disfraz.
			local tiny = { Health = 5, Damage = 1, XP = 1, Coins = 1, MaxAlive = 2 }

			for _, world in ipairs(WORLDS) do
				for night = 1, 99 do
					local scaled = Diff.ApplyToMonster(tiny, Diff.Resolve(world, night, 2, 10))

					expect.toBe(scaled.Health >= 1, true, ("%s %d: vida %s")
						:format(world, night, tostring(scaled.Health)))
					expect.toBe(scaled.Damage >= 1, true, ("%s %d: dano %s")
						:format(world, night, tostring(scaled.Damage)))
					expect.toBe(scaled.XP >= 1, true, "recompensa XP cero")
					expect.toBe(scaled.Coins >= 1, true, "recompensa de monedas cero")
				end
			end
		end)

		Harness.it("el tope de vivos no escala con la dificultad", function()
			-- `MaxAlive` es un limite de RENDIMIENTO, no de balance: un enemigo
			-- que aguanta mas no necesita estar mas veces en pantalla.
			local p = Diff.Resolve("Cyber", 99, 2, 40)
			local scaled = Diff.ApplyToMonster(
				{ Health = 100, Damage = 10, XP = 20, Coins = 5, MaxAlive = 3 },
				p
			)

			expect.toBe(scaled.MaxAlive <= 3, true, "MaxAlive se escalo con la dificultad")
		end)
	end)

	Harness.describe("Robustez", function()
		Harness.it("acepta entradas invalidas sin romperse", function()
			-- La noche llega del perfil, de un comando de admin y de un atajo de
			-- pruebas. Un `nil` aqui significaria un perfil roto en pantalla.
			local cases = { nil, "noche", {} }
			table.insert(cases, 0 / 0)

			for _, value in ipairs(cases) do
				local p = Diff.Resolve(value, value, value, value)

				expect.toBe(p.Night >= 1, true, ("noche invalida: %s"):format(tostring(p.Night)))
				expect.toBe(p.Health >= 1, true, "vida menor que 1")
				expect.toBe(p.MaxAlive >= 1, true, "poblacion menor que 1")
			end
		end)

		Harness.it("un evento menor que 1 se trata como ausencia de evento", function()
			local p = Diff.Resolve("Forest", 30, 0.1, 10)
			local base = Diff.Resolve("Forest", 30, 1, 10)

			expect.toBe(p.Count, base.Count)
		end)
	end)
end

return describeDifficulty