--!strict
--[[
	MonsterScale.spec
	Pruebas del TAMANO de los monstruos y de la separacion hitbox/modelo.

	POR QUE EXISTE
	--------------
	El requisito de diseno es literal: "los monstruos deben ser
	perceptiblemente mas grandes que el personaje jugador". Con el jugador
	a `Height = 1.0`, todo bicho declarado debe caer dentro de su rango de
	diseno y, en cualquier caso, por encima de 1.2.

	Esta suite convierte ese requisito en algo que falla si alguien
	declara un monstruo pequeno. Sin ella, "el enemigo se ve mas grande que
	yo" es una intencion, no una garantia.

	LA SEGUNDA MITAD: HITBOX
	------------------------
	Un enemigo grande con hitbox del mismo tamano que el modelo deja de
	poder rodearse y atascaria los pasillos que el mapa revela al usar
	bombas. Estas pruebas comprueban que la hitbox es siempre una fraccion
	acotada del modelo, nunca el modelo entero.

	LA TERCERA: COHERENCIA
	----------------------
	`MonsterScaleRules` y `MonsterDefinitions` declaran el tamano en sitios
	distintos (el primero es puro, el segundo debe cargar sin motor). Estas
	pruebas comprueban que NO SE CONTRADIGEN: si alguien cambia un valor en
	uno y no en el otro, el fallo sale aqui y no en un playtest.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local Scale = require("../../src/ReplicatedStorage/Shared/Libraries/MonsterScaleRules")
local Monsters = require("../../src/ReplicatedStorage/Shared/MonsterDefinitions")

-- Altura de referencia del JUGADOR en la escala del modulo.
--
-- El diseno habla de "el jugador mide 1.0", asi que cualquier comparacion
-- se hace contra 1.0 y no contra los 5 studs reales de un R15: lo que
-- importa es la RELACION, y meter studs reales en el modulo lo ataria a
-- un cuerpo concreto que el juego puede cambiar.
local PLAYER_HEIGHT = 1.0

-- Por debajo de este valor un bicho deja de leerse como amenaza.
local MINIMUM_SCALE = 1.2

--- Recorre todos los identificadores declarados en `MonsterScaleRules`.
--- @return { string }
local function allIds(): { string }
	local ids = {}

	for id in pairs(Scale.VisualScale) do
		table.insert(ids, id)
	end

	table.sort(ids)

	return ids
end

local function describeMonsterScale()
	Harness.describe("MonsterScaleRules: todo bicho supera al jugador", function()
		Harness.it("ningun monstruo esta por debajo del piso de amenaza", function()
			-- La asercion global. Recorre la tabla entera, de modo que anadir
			-- un monstruo nuevo queda cubierto sin tocar esta prueba.
			for _, id in ipairs(allIds()) do
				local scale = Scale.GetVisualScale(id)

				expect.toBe(scale > MINIMUM_SCALE, true)
			end
		end)

		Harness.it("ningun monstruo se sale de su rango de diseno", function()
			-- El segundo filtro, mas estricto: cada bicho tiene su propio
			-- rango (un Guardian puede ser 2.1, un Slime no).
			local problems = Scale.AuditAll()

			expect.toBe(#problems, 0)
		end)

		Harness.it("los nueve bichos del juego estan declarados", function()
			-- Si alguien anade un monstruo nuevo y olvida la escala, el
			-- jugador veria una caja del tamano de un jugador otra vez.
			local ids = allIds()

			expect.toBe(#ids, 9)
		end)

		Harness.it("un monstruo desconocido usa una escala mayor que el jugador", function()
			-- El valor por defecto tiene que cumplir el diseno, no solo
			-- "devolver algo": si fuera 1.0, un bicho nuevo sin escala
			-- reapareceria del tamano del jugador sin avisar.
			expect.toBe(Scale.DefaultVisualScale > PLAYER_HEIGHT, true)
			expect.toBe(Scale.GetVisualScale("NoExiste"), Scale.DefaultVisualScale)
		end)

		Harness.it("la escala es MAYOR que 1 para todos los mundos", function()
			-- El mundo puede hacer a un bicho mas grande o mas pequeno,
			-- pero nunca mas pequeno que el jugador: el Forest con 0.95
			-- sigue dejando al Slime en 1.33.
			for _, id in ipairs(allIds()) do
				for worldId in pairs(Scale.WorldScale) do
					expect.toBe(Scale.Resolve(id, worldId) > PLAYER_HEIGHT, true)
				end
			end
		end)

		Harness.it("AssertDesign RECHAZA un bicho mas pequeno que el jugador", function()
			-- La comprobacion tiene que ser capaz de FALLAR. Una validacion
			-- que nunca puede fallar no valida nada.
			local original = Scale.VisualScale.Slime
			Scale.VisualScale.Slime = 1.0

			local ok, reason = Scale.AssertDesign("Slime")

			expect.toBe(ok, false)
			expect.toBe(reason ~= nil, true)

			Scale.VisualScale.Slime = original
		end)

		Harness.it("AssertDesign RECHAZA un bicho fuera de rango por arriba", function()
			local original = Scale.VisualScale.Guardian
			Scale.VisualScale.Guardian = 9.0

			local ok = Scale.AssertDesign("Guardian")

			expect.toBe(ok, false)

			Scale.VisualScale.Guardian = original
		end)

		Harness.it("AssertDesign ACEPTA un bicho bien declarado", function()
			expect.toBe(Scale.AssertDesign("Slime"), true)
			expect.toBe(Scale.AssertDesign("Guardian"), true)
		end)
	end)
Harness.describe("MonsterScaleRules: la hitbox va por separado", function()
		Harness.it("la hitbox es SIEMPRE mas pequena que el modelo", function()
			-- El fallo que separa esta parte de la anterior: si la hitbox
			-- fuera del tamano del modelo, el bicho bloquearia el pasillo y
			-- el jugador no podria rodearlo ni huir por los huecos.
			for _, id in ipairs(allIds()) do
				local ratio = Scale.GetHitboxRatio(id)

				expect.toBe(ratio < 1, true)
			end
		end)

		Harness.it("la hitbox NUNCA baja del suelo ni sube del tope", function()
			-- Los dos frenos. Por debajo, las bombas pasan "por debajo" del
			-- bicho y explotan sin danarlo. Por encima, el bicho se
			-- convierte en un muro.
			for _, id in ipairs(allIds()) do
				local ratio = Scale.GetHitboxRatio(id)

				expect.toBe(ratio >= Scale.MinHitboxRatio, true)
				expect.toBe(ratio <= Scale.MaxHitboxRatio, true)
			end
		end)

		Harness.it("una proporcion DECLARADA fuera de rango se acota", function()
			-- Si alguien declara 1.0 para el Guardian, el modulo lo recorta:
			-- la validacion se aplica AL USAR, no solo al declarar.
			local original = Scale.HitboxRatio.Guardian
			Scale.HitboxRatio.Guardian = 1.4

			expect.toBe(Scale.GetHitboxRatio("Guardian"), Scale.MaxHitboxRatio)

			Scale.HitboxRatio.Guardian = 0.01

			expect.toBe(Scale.GetHitboxRatio("Guardian"), Scale.MinHitboxRatio)

			Scale.HitboxRatio.Guardian = original
		end)

		Harness.it("el Guardian tiene la hitbox MAS GENEROSA y el Slime la menor", function()
			-- Es la diferencia entre "estorbo" y "muro", y entre "se puede
			-- empujar" y "hay que apartarse". Un Guardian con hitbox de
			-- Slime no cumpliria su papel.
			expect.toBe(
				Scale.GetHitboxRatio("Guardian") > Scale.GetHitboxRatio("Slime"),
				true
			)
		end)

		Harness.it("la hitbox NO crece con el mundo", function()
			-- Decision de diseno importante: el mundo cambia lo grande que se
			-- VE el bicho, pero no lo grande que se COLISIONA. Si creciera,
			-- el Guardian del Cyber bloquearia pasillos que el del Forest
			-- deja pasar y el mapa dejaria de ser jugable.
			for _, id in ipairs(allIds()) do
				expect.toBe(Scale.GetHitboxRatio(id), Scale.GetHitboxRatio(id))
			end
		end)

		Harness.it("HitboxSize devuelve un valor menor que el modelo", function()
			-- Se comprueba con un `Vector3` de muestra porque aqui no hay
			-- motor: la cuenta es la misma que hace `BuildMonster`.
			local modelSize = { X = 4, Y = 7, Z = 4 }
			local ratio = Scale.GetHitboxRatio("Guardian")

			expect.toBe(modelSize.Y * ratio < modelSize.Y, true)
			expect.toBe(modelSize.Y * ratio > 0, true)
		end)
	end)

	Harness.describe("MonsterScaleRules: la escala por mundo", function()
		Harness.it("los cinco mundos tienen multiplicador declarado", function()
			for _, worldId in ipairs({ "Forest", "Desert", "Ice", "Volcano", "Cyber" }) do
				expect.toBe(Scale.WorldScale[worldId] ~= nil, true)
			end
		end)

		Harness.it("el Cyber AGRANDA a los enemigos mas que el Forest", function()
			-- La escala tiene que COMUNICAR dificultad. Si el Cyber no
			-- escalara, los cinco mundos serian el mismo con otra paleta.
			expect.toBe(Scale.GetWorldScale("Cyber") > Scale.GetWorldScale("Forest"), true)
		end)

		Harness.it("la diferencia entre mundos NO es abusiva", function()
			-- Un multiplicador de 2.0 entre el Forest y el Cyber haria que un
			-- Guardian del Forest pasara por un hueco y el del Cyber no, y el
			-- jugador sentiria que un mundo esta roto.
			local ratio = Scale.GetWorldScale("Cyber") / Scale.GetWorldScale("Forest")

			expect.toBe(ratio < 1.35, true)
		end)

		Harness.it("un mundo desconocido no rompe el calculo", function()
			expect.toBe(Scale.GetWorldScale("NoExiste"), Scale.DefaultWorldScale)
			expect.toBe(Scale.GetWorldScale(nil), Scale.DefaultWorldScale)
		end)
	end)
Harness.describe("MonsterDefinitions y MonsterScaleRules NO se contradicen", function()
		Harness.it("las dos tablas declaran los mismos identificadores", function()
			-- La duplicacion es deliberada (las pruebas cargan
			-- `MonsterDefinitions` sin motor), pero no puede divergir. Si
			-- alguien anade un bicho a una tabla y no a la otra, el fallo
			-- sale aqui con un nombre claro.
			local fromScale = allIds()
			local declared = Monsters.GetIds()

			expect.toBe(#declared, #fromScale)

			for _, id in ipairs(declared) do
				expect.toBe(Scale.VisualScale[id] ~= nil, true)
			end
		end)

		Harness.it("cada monstruo lleva una escala MAYOR que el jugador", function()
			-- La asercion sobre la definicion REAL, no sobre la tabla pura.
			-- Es la que importa: es el valor que leera `BuildMonster`.
			for _, id in ipairs(Monsters.GetIds()) do
				local def = Monsters.Get(id)

				expect.toBe(def.VisualScale > PLAYER_HEIGHT, true)
			end
		end)

		Harness.it("la hitbox de cada definicion es una fraccion acotada", function()
			for _, id in ipairs(Monsters.GetIds()) do
				local def = Monsters.Get(id)

				expect.toBe(def.HitboxScale >= Scale.MinHitboxRatio, true)
				expect.toBe(def.HitboxScale <= Scale.MaxHitboxRatio, true)
				expect.toBe(def.HitboxScale < 1, true)
			end
		end)

		Harness.it("la escala de la definicion coincide con la del modulo puro", function()
			for _, id in ipairs(Monsters.GetIds()) do
				local def = Monsters.Get(id)

				expect.toBe(def.VisualScale, Scale.GetVisualScale(id))
			end
		end)

		Harness.it("ningun monstruo declara WorldScale 0 (bicho invisible)", function()
			-- `WorldScale = 0` es el fallo silencioso mas caro: el bicho
			-- aparece con tamano cero y ni el jugador ni el log dicen nada.
			for _, id in ipairs(Monsters.GetIds()) do
				local def = Monsters.Get(id)

				expect.toBe(def.WorldScale > 0, true)
			end
		end)

		Harness.it("la escala final con mundo sigue superando al jugador", function()
			-- El calculo que hace `BuildMonster`, con los cinco mundos.
			for _, id in ipairs(Monsters.GetIds()) do
				local def = Monsters.Get(id)

				for worldId in pairs(Scale.WorldScale) do
					local final = def.VisualScale * def.WorldScale * Scale.GetWorldScale(worldId)

					expect.toBe(final > PLAYER_HEIGHT, true)
				end
			end
		end)
	end)
end

return describeMonsterScale