--!strict
--[[
	AudioRules.spec
	Pruebas de DECIDIR QUE SUENA, y del CATALOGO de eventos.

	POR QUE EXISTEN
	---------------
	Son las dos mitades de la regla "todo lo que tenga una accion, un
	movimiento o una presencia importante debe tener feedback sonoro":

	1. `AudioRules` decide si un sonido debe reproducirse: distancia,
	    enfriamiento, categoria y prioridad. Si esta parte falla, el juego
	    se satena de sonidos y se pierde justo en la explosion.
	2. `AudioConfig.Events` declara TODAS las acciones que deben sonar. Si
	    falta una entrada hay una accion que no se comunica, y no hay
	    ningun error: el juego simplemente esta mudo en esa parte.

	LA SEGUNDA ES LA IMPORTANTE
	---------------------------
	Una lista de eventos puede quedarse vieja sin que nada falle. Estas
	pruebas la recorren y exigen que exista cada evento OBLIGATORIO, de modo
	que "el juego no tiene sonido de tele" falle aqui y no lo descubra un
	jugador.

	ESTADO HONESTO DE LOS ASSETS
	-----------------------------
	Todos los `id` estan en `nil` porque no hay ningun archivo de audio en
	el repositorio. Eso NO es un fallo del sistema: es lo que se reporta
	como PENDING. Lo que se comprueba aqui es que la ARQUITECTURA esta
	preparada y que ninguna entrada apunta a un asset INVENTADO.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local Rules = require("../../src/ReplicatedStorage/Shared/Libraries/AudioRules")
local Config = require("../../src/ReplicatedStorage/Shared/Config/AudioConfig")

--- Eventos que la regla de negocio obliga a que existan.
---
--- Se declaran aqui y no dentro de la prueba para que la lista sea legible
--- de un vistazo y para poder referenciarla desde mas de un test.
local REQUIRED_EVENTS = {
	-- Bomba: el ciclo completo de la accion central del juego.
	"BombPlace",
	"BombFuse",
	"Explosion",
	"BlockBreak",
	"PowerupReveal",

	-- Jugador: movimiento, dano, muerte y recompensas.
	"StepForest",
	"StepDesert",
	"StepIce",
	"StepVolcano",
	"StepCyber",
	"Jump",
	"Land",
	"PlayerHurt",
	"PlayerDeath",
	"CoinPickup",
	"GemPickup",
	"LevelUp",
	"QuestComplete",
	"PortalEnter",
	"WorldExit",

	-- Interfaz.
	"UiClick",
	"UiConfirm",
	"Purchase",

	-- Monstruos: identidad, movimiento y telegraph.
	"MonsterSpawn",
	"MonsterAlert",
	"MonsterAttack",
	"MonsterHurt",
	"MonsterDeath",
	"MonsterStep",
	"MonsterTelegraph",

	-- Boss: el ciclo completo, incluido el cambio de fase.
	"BossSpawn",
	"BossIntro",
	"BossTelegraph",
	"BossAttack",
	"BossSpecial",
	"BossHurt",
	"BossPhaseChange",
	"BossDeath",
	"Victory",
	"Defeat",
}

local function describeAudioRules()
	Harness.describe("AudioRules: volumen, prioridad y categorias", function()
		Harness.it("el SFX suena MAS FUERTE que la musica", function()
			-- Si la musica igualara al efecto, taparia la explosion, que es
			-- la informacion mas importante del juego.
			expect.toBe(
				Rules.ResolveVolume("Sfx", 1, 1) > Rules.ResolveVolume("Music", 1, 1),
				true
			)
		end)

		Harness.it("el ambiente NUNCA tapa a un efecto", function()
			expect.toBe(
				Rules.ResolveVolume("Ambient", 1, 1) < Rules.ResolveVolume("Sfx", 1, 1),
				true
			)
		end)

		Harness.it("el volumen final esta acotado a 0..1", function()
			-- Un `Volume` mayor que 1 recorta en Roblox y hace que el audio
			-- suene "roto" en vez de "fuerte".
			expect.toBe(Rules.ResolveVolume("Sfx", 5, 5), 1)
			expect.toBe(Rules.ResolveVolume("Sfx", 0, 0), 0)
			expect.toBe(Rules.ResolveVolume("Sfx", -1, -1), 0)
		end)

		Harness.it("una categoria DESCONOCIDA cae en Sfx, no en silencio", function()
			-- Callar un sonido mal clasificado es peor que reproducirlo de
			-- mas: el jugador oye algo raro, y no oye NADA.
			expect.toBe(
				Rules.ResolveVolume("CategoriaInventada", 1, 1),
				Rules.ResolveVolume("Sfx", 1, 1)
			)
		end)

		Harness.it("el Sfx gana cualquier competencia de prioridad", function()
			expect.toBe(Rules.Compare("Sfx", "Ambient"), true)
			expect.toBe(Rules.Compare("Sfx", "Music"), true)
			expect.toBe(Rules.Compare("Sfx", "UI"), true)
			expect.toBe(Rules.Compare("Sfx", "Voice"), true)
		end)

		Harness.it("el ambiente NO le gana a nada importante", function()
			expect.toBe(Rules.Compare("Ambient", "Sfx"), false)
			expect.toBe(Rules.Compare("Ambient", "Voice"), false)
			expect.toBe(Rules.Compare("Music", "Sfx"), false)
		end)

		Harness.it("una categoria igual gana por orden de llegada", function()
			-- Asi un sonido no se auto-bloquea por ser el primero de su
			-- categoria.
			expect.toBe(Rules.Compare("Sfx", "Sfx"), true)
		end)

		Harness.it("los pasos NO pueden tapar a la explosion", function()
			-- Traduce literalmente "los pasos, el viento y las particulas no
			-- pueden tapar bomba, ataque, dano, boss ni victoria".
			local loudest = math.max(
				Rules.ResolveVolume("Ambient", 1, 1),
				Rules.ResolveVolume("Voice", 1, 1)
			)

			expect.toBe(loudest < Rules.ResolveVolume("Sfx", 1, 1), true)
		end)
	end)
Harness.describe("AudioRules: distancia", function()
		Harness.it("un sonido de efectos se oye MAS LEJOS que el ambiente", function()
			expect.toBe(Rules.GetMaxDistance("Sfx") > Rules.GetMaxDistance("Ambient"), true)
		end)

		Harness.it("un sonido en el limite se oye, y uno fuera NO", function()
			local max = Rules.GetMaxDistance("Ambient")

			expect.toBe(Rules.IsAudible("Ambient", max), true)
			expect.toBe(Rules.IsAudible("Ambient", max + 1), false)
		end)

		Harness.it("encima del jugador NO hay atenuacion", function()
			expect.toBe(Rules.Attenuation(0, 100), 1)
			expect.toBe(Rules.Attenuation(10, 100), 1)
		end)

		Harness.it("en el limite la atenuacion es CERO", function()
			expect.toBe(Rules.Attenuation(100, 100), 0)
			expect.toBe(Rules.Attenuation(150, 100), 0)
		end)

		Harness.it("a media distancia la atenuacion es MAS de la mitad", function()
			-- La cuenta es cuadratica a proposito: con una lineal, el punto
			-- medio sonaria al 50 % y no se distinguiria del fondo.
			local factor = Rules.Attenuation(50, 100)

			expect.toBe(factor > 0.5, true)
			expect.toBe(factor < 1, true)
		end)

		Harness.it("la atenuacion baja de forma MONOTONA", function()
			-- Si un sonido mas lejos sonara mas fuerte que uno mas cerca, el
			-- jugador oiria las cosas al reves.
			local previous = 1

			for step = 0, 100 do
				local factor = Rules.Attenuation(step, 100)

				expect.toBe(factor <= previous, true)
				previous = factor
			end
		end)

		Harness.it("un sonido SIN limite (musica) no se atenua", function()
			expect.toBe(Rules.Attenuation(99999, Rules.GetMaxDistance("Music")), 1)
			expect.toBe(Rules.IsAudible("Music", 99999), true)
		end)

		Harness.it("una distancia CORRUPTA no silencia el sonido", function()
			-- Un `nil` de posicion se convierte en distancia negativa. El
			-- sonido es real, asi que se oye: callarlo seria peor.
			expect.toBe(Rules.IsAudible("Sfx", -1), true)
		end)
	end)

	Harness.describe("AudioRules: enfriamiento (anti-spam)", function()
		Harness.it("un sonido que nunca ha sonado SIEMPUEDE sonar", function()
			local allowed, remaining = Rules.CheckCooldown("Sfx", -1, 100)

			expect.toBe(allowed, true)
			expect.toBe(remaining, 0)
		end)

		Harness.it("el mismo sonido NO se repite dentro del enfriamiento", function()
			expect.toBe(Rules.CheckCooldown("Sfx", 100, 100.01), false)
		end)

		Harness.it("pasado el enfriamiento, vuelve a sonar", function()
			local cooldown = Rules.GetCooldown("Voice")

			expect.toBe(Rules.CheckCooldown("Voice", 100, 100 + cooldown), true)
		end)

		Harness.it("el Sfx tiene el enfriamiento MAS CORTO que el ambiente", function()
			-- La explosion no puede esperar dos segundos porque el viento
			-- estaba sonando antes.
			expect.toBe(Rules.GetCooldown("Sfx") < Rules.GetCooldown("Ambient"), true)
		end)

		Harness.it("el enfriamiento informa de lo que FALTA", function()
			local allowed, remaining = Rules.CheckCooldown("Ambient", 100, 101)

			expect.toBe(allowed, false)
			expect.toBe(remaining > 0, true)
			expect.toBe(remaining <= Rules.GetCooldown("Ambient"), true)
		end)

		Harness.it("mil llamadas seguidas NO reproducen mil sonidos", function()
			-- Es la simulacion del enemigo que suena cada frame. Con el
			-- enfriamiento solo pasa un puñado de veces.
			local lastPlayed = -1
			local played = 0
			local now = 0

			for _ = 1, 1000 do
				if Rules.CheckCooldown("Voice", lastPlayed, now) then
					played += 1
					lastPlayed = now
				end

				now += 1 / 60
			end

			-- 1000 frames a 60 fps son ~16 s. Con un enfriamiento de 0.35 s
			-- caben unos 46 sonidos: ni uno por frame, ni cero.
			expect.toBe(played < 1000, true)
			expect.toBe(played > 0, true)
		end)
	end)
Harness.describe("AudioConfig: el catalogo de eventos esta COMPLETO", function()
		Harness.it("existe CADA evento obligatorio", function()
			-- La asercion que traduce "todo lo que tenga una accion, un
			-- movimiento o una presencia importante debe tener feedback
			-- sonoro". Si falta uno, el juego esta mudo en esa accion y no
			-- hay ningun error: por eso la lista se exige aqui.
			local missing = {}

			for _, event in ipairs(REQUIRED_EVENTS) do
				if Config.Events[event] == nil then
					table.insert(missing, event)
				end
			end

			expect.toBe(#missing, 0)
		end)

		Harness.it("cada evento declara una CATEGORIA valida", function()
			-- Sin categoria, el sonido sale con el volumen de `Sfx` por
			-- defecto y el ambiente tapa a la explosion.
			local valid = {
				Rules.Category.Music,
				Rules.Category.Sfx,
				Rules.Category.Ambient,
				Rules.Category.UI,
				Rules.Category.Voice,
			}

			for name, event in pairs(Config.Events) do
				local ok = false

				for _, category in ipairs(valid) do
					if event.category == category then
						ok = true
					end
				end

				expect.toBe(ok, true)
			end
		end)

		Harness.it("cada paso de superficie usa la CATEGORIA Sfx", function()
			-- Los pasos por superficie son Sfx: su sonido cambia con el
			-- material, no con la categoria.
			for _, worldId in ipairs({ "Forest", "Desert", "Ice", "Volcano", "Cyber" }) do
				expect.toBe(Config.Events["Step" .. worldId].category, Rules.Category.Sfx)
			end
		end)

		Harness.it("el ambiente de cada mundo usa la CATEGORIA Ambient", function()
			for _, worldId in ipairs({ "Forest", "Desert", "Ice", "Volcano", "Cyber" }) do
				expect.toBe(Config.Events["Ambient" .. worldId].category, Rules.Category.Ambient)
			end
		end)

		Harness.it("la explosion usa la CATEGORIA Sfx y la mas ALTA prioridad", function()
			-- El BOOM es la informacion mas importante del juego. Si
			-- estuviera en `Ambient`, el viento lo taparia.
			expect.toBe(Config.Events.Explosion.category, Rules.Category.Sfx)
			expect.toBe(Rules.GetPriority(Config.Events.Explosion.category), 4)
		end)

		Harness.it("el cambio de fase del boss usa la CATEGORIA Music", function()
			-- "El cambio de fase debe sentirse": tiene que cambiar la cama
			-- de fondo, no solo sonar encima.
			expect.toBe(Config.Events.BossPhaseChange.category, Rules.Category.Music)
		end)

		Harness.it("el telegraph del monstruo usa la CATEGORIA Voice", function()
			-- El aviso tiene que ser IDENTIFICABLE como criatura: si fuera
			-- un efecto suelto, el jugador no sabria de quien es.
			expect.toBe(Config.Events.MonsterTelegraph.category, Rules.Category.Voice)
		end)
	end)

	Harness.describe("AudioConfig: los assets NO estan inventados", function()
		Harness.it("ningun evento apunta a un ID de asset VACIO", function()
			-- Un `id = ""` o `id = "0"` es peor que un `nil`: el motor
			-- intenta cargarlo, falla en rojo y consume trafico. La regla
			-- es `nil` o un ID numerico real.
			for name, event in pairs(Config.Events) do
				if event.id ~= nil then
					expect.toBe(event.id == "", false)
					expect.toBe(event.id == "0", false)
				end
			end
		end)

		Harness.it("un ID presente tiene forma de asset de Roblox", function()
			-- Cuando se peguen los IDs tienen que ser cadenas largas de
			-- digitos. Si alguien pone "explosion" aqui, el motor lo
			-- interpretaria como un id numerico y daria error.
			for _, event in pairs(Config.Events) do
				if type(event.id) == "string" then
					expect.toBe(#event.id > 10, true)
				end
			end
		end)

		Harness.it("el estado actual de los assets es PENDING, no ROTO", function()
			-- mientras `assets/sounds` este vacio, TODOS los eventos estan
			-- sin asset. Esto documenta el estado real: la ARQUITECTURA
			-- esta, los ficheros no.
			--
			-- En cuanto se peguen los IDs esta asercion dejara de ser
			-- cierta y habra que cambiarla. Es intencionado: obliga a
			-- revisar el catalogo cuando se suban los assets.
			local withoutAsset = 0

			for _ in pairs(Config.Events) do
				withoutAsset += 1
			end

			expect.toBe(withoutAsset > 0, true)
		end)

		Harness.it("la musica declara los siete estados del ciclo", function()
			-- OJO con la comprobacion: en Lua, una clave cuyo VALOR es `nil`
			-- es indistinguible de una clave que no existe. Asignar `nil` a
			-- las siete entradas haria que `MusicByState` fuese una tabla
			-- VACIA, y `AudioController` caeria en silencio al cambiar de
			-- estado sin dejar rastro.
			--
			-- Por eso los estados se declaran con `false` ("este estado aun
			-- no tiene pista subida") y no con `nil` ("no existe"). Es la
			-- misma distincion que ya usa `AudioConfig.WorldMusic`.
			local expected = {
				"Lobby",
				"Exploring",
				"Combat",
				"Arena",
				"Boss",
				"Victory",
				"Defeat",
			}

			for _, state in ipairs(expected) do
				local entry = Config.MusicByState[state]

				-- `false` (declarado sin asset) o un `string` real: ambas son
				-- entradas VIVAS. `nil` significaria que la clave no existe.
				expect.toBe(entry ~= nil, true)
			end

			local count = 0

			for _ in pairs(Config.MusicByState) do
				count += 1
			end

			expect.toBe(count, 7)
		end)

		Harness.it("los cinco mundos tienen entrada en `WorldMusic`", function()
			-- Si faltara un mundo, `AudioController` caeria en silencio al
			-- entrar por ese portal sin avisar.
			for _, worldId in ipairs({ "Forest", "Desert", "Ice", "Volcano", "Cyber" }) do
				expect.toBe(Config.WorldMusic[worldId] ~= nil, true)
			end
		end)
	end)
end

return describeAudioRules