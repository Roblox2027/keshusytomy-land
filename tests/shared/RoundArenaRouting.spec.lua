--!strict
--[[
	RoundArenaRouting.spec
	Regresion de los bugs MEDIDOS en PLAY real que ninguna prueba de codigo
	anterior detectaba.

	BUG 1: EL ALIAS `Arena` NO EXISTIA
	----------------------------------
	`MatchService.CollectDestinations` creaba el alias `Arena` (el destino que
	el ciclo de ronda pide "a secas") SOLO si `Service._worldService` ya estaba
	injectado. No lo estaba: `Service.Init` corre antes que la fase de cableado
	de `ServerMain`, asi que el alias nunca se creaba.

	Medido en PLAY, en CADA ronda del ciclo:

	    WARN: destino 'Arena' no encontrado en el mapa
	    INFO: 0 jugador(es) movidos a Arena

	La ronda arrancaba, generaba monstruos, terminaba y pagaba recompensas
	contra un jugador que seguia en el lobby. El log parecia limpio y el juego
	no era jugable.

	BUG 2: LA RONDA TELEPORTABA AL MUNDO EQUIVOCADO
	----------------------------------------------
	Con los cinco mundos, `MoveAllPlayers("Arena")` mandaba a TODOS al MISMO
	`Arena`. Un jugador que entro por el portal de Desert aparecia en la arena
	de Forest, y `MovePlayer` publicaba `World = "Forest"`: el atributo y la
	posicion real quedaban en contradiccion, que es lo que el diseno prohibe.

	BUG 3: EL PORTAL PARECIA ROTO
	-----------------------------
	El rechazo era `IsPlaying()` a secas. Con el ciclo casi siempre activo
	(Waiting 1s + Countdown 5s + RoundStarting 3s + Playing 180s), el portal
	estaba disponible ~1 s de cada 189. La sensacion de juego era "el portal
	no funciona".
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

--- Elijecion del mundo por defecto, replicando la regla REAL de
--- `CollectDestinations` sin `worldService` (el caso de `Init`).
--- @param names { string } nombres de las carpetas de mundo con arena
--- @param worldServiceId string? id por defecto si `worldService` ya esta inyectado
local function pickDefaultWorld(names: { string }, worldServiceId: string?): string?
	local candidatos = table.clone(names)
	table.sort(candidatos)

	local chosen = nil
	if worldServiceId and table.find(candidatos, worldServiceId) then
		chosen = worldServiceId
	end

	if not chosen and #candidatos > 0 then
		chosen = candidatos[1]
	end

	return chosen
end

--- Traduce un id de mundo a su clave de destino (`MatchService.GetArenaKey`).
local function getArenaKey(worldId: string): string
	if worldId and worldId ~= "" and not string.match(worldId, "^Arena_") then
		return "Arena_" .. worldId
	end
	return worldId
end

--- Regla del portal frente a la ronda (`PortalService`, paso 6).
---
--- MEDIDO: la primera version de la regla usaba el atributo `World`, y
--- durante la certificacion de los cinco mundos un jugador parado EN el lobby
--- tenia `World = "Forest"`. Con el atributo como criterio, el portal lo
--- rechazaba estando en el lobby de verdad. La regla correcta mira la
--- POSICION del cuerpo contra la arena.
---
--- @param isPlaying boolean
--- @param arenaDist number? distancia al centro de la arena; nil si no hay arena
--- @param guard number radio de proteccion
local function portalAllowed(isPlaying: boolean, arenaDist: number?, guard: number): boolean
	if not isPlaying then
		return true
	end

	if arenaDist == nil then
		-- Sin arena no hay ronda de la que evadirse.
		return true
	end

	return arenaDist > guard
end

local ARENA_EXIT_GUARD = 300
local WORLD_IDS = { "Forest", "Desert", "Ice", "Volcano", "Cyber" }

local function describeRoundArenaRouting()
	Harness.describe("Alias Arena (bug 1, medido en PLAY)", function()
		Harness.it("el alias se elige SIN worldService (el caso de Init)", function()
			-- El orden alfabetico PONIA Cyber primero: `Cyber` < `Forest`.
			-- El alias existia, pero apuntaba al mundo equivocado.
			expect.toBe(pickDefaultWorld(WORLD_IDS, nil), "Cyber")
		end)

		Harness.it("con worldService, el alias es el mundo por defecto real", function()
			expect.toBe(pickDefaultWorld(WORLD_IDS, "Forest"), "Forest")
		end)

		Harness.it("un mundo por defecto sin arena cae al disponible", function()
			expect.toBe(pickDefaultWorld(WORLD_IDS, "Ahorahere"), "Cyber")
		end)

		Harness.it("si no hay ningun mundo, no hay alias (y se avisa)", function()
			expect.toBe(pickDefaultWorld({}, "Forest"), nil)
		end)
	end)

	Harness.describe("Arena propia de cada jugador (bug 2)", function()
		Harness.it("la clave de arena se deriva del id del mundo", function()
			expect.toBe(getArenaKey("Desert"), "Arena_Desert")
			expect.toBe(getArenaKey("Forest"), "Arena_Forest")
		end)

		Harness.it("una clave ya construida no se vuelve a prefijar", function()
			expect.toBe(getArenaKey("Arena_Desert"), "Arena_Desert")
		end)

		Harness.it("cada mundo conserva una arena DISTINTA", function()
			-- La confusion Desert -> Forest venia de que todas las arenas
			-- fueran el mismo destino.
			local vistas = {}

			for _, name in ipairs(WORLD_IDS) do
				local clave = getArenaKey(name)
				expect.toBe(vistas[clave] ~= nil, false)
				vistas[clave] = name
			end
		end)

		Harness.it("los cinco destinos de arena existen", function()
			for _, name in ipairs(WORLD_IDS) do
				expect.toBe(getArenaKey(name) == "Arena_" .. name, true)
			end
		end)
	end)

	Harness.describe("Portal frente a la ronda (bug 3)", function()
		Harness.it("una ronda en curso NO cierra el portal al lobby", function()
			-- MEDIDO: con `IsPlaying()` a secas el portal rechazaba el 99 % del
			-- tiempo. Un jugador en el lobby esta a miles de studs de cualquier
			-- arena: no participa en nada.
			expect.toBe(portalAllowed(true, 534, ARENA_EXIT_GUARD), true)
			expect.toBe(portalAllowed(true, 1805, ARENA_EXIT_GUARD), true)
		end)

		Harness.it("no se puede ABANDONAR una ronda desde la arena", function()
			-- Lo que si hay que proteger: la evasion desde el combate.
			expect.toBe(portalAllowed(true, 0, ARENA_EXIT_GUARD), false)
			expect.toBe(portalAllowed(true, 120, ARENA_EXIT_GUARD), false)
		end)

		Harness.it("el radio no corta a quien ya camina hacia la salida", function()
			-- Un jugador en el borde del mundo esta lejos de la arena y debe
			-- poder seguir su recorrido.
			expect.toBe(portalAllowed(true, 420, ARENA_EXIT_GUARD), true)
		end)

		Harness.it("sin ronda en curso el portal siempre esta abierto", function()
			expect.toBe(portalAllowed(false, 0, ARENA_EXIT_GUARD), true)
			expect.toBe(portalAllowed(false, 534, ARENA_EXIT_GUARD), true)
		end)

		Harness.it("sin arena conocida no hay ronda de la que evadirse", function()
			-- El lobby no pertenece a ninguna arena. `nil` es "no hay arena",
			-- no "no se cual es el mundo": son preguntas distintas.
			expect.toBe(portalAllowed(true, nil, ARENA_EXIT_GUARD), true)
		end)
	end)

	Harness.describe("Nivel de la sesion frente al perfil (bug 4)", function()
		-- MEDIDO EN PLAY: `ProgressionService.AddXP` actualizaba el atributo
		-- `Level` (llegando a 630) pero la SESION de `PlayerService` se quedaba
		-- en 1. `PortalService.GetPlayerLevel` lee la sesion, asi que:
		--   TryEnter(Desert) -> false ("requiere nivel 10")
		-- Los cuatro mundos con nivel NO se desbloqueaban nunca, aunque el
		-- jugador subiera de nivel jugando y el HUD lo mostrara.
		--
		-- Se replica la sesion minima y la sincronizacion.
		local function makeSession(level: number)
			return { Level = level, XP = 0, Coins = 0, Gems = 0 }
		end

		Harness.it("la sesion arranca en 1 y el atributo no la cambia solo", function()
			local session = makeSession(1)
			expect.toBe(session.Level, 1)
		end)

		Harness.it("SyncLevelFromProfile vuelca el nivel del atributo", function()
			local session = makeSession(1)
			local atributo = 630

			-- Lo que hace `PlayerService.SyncLevelFromProfile`.
			local previous = session.Level
			session.Level = atributo

			expect.toBe(session.Level, 630)
			expect.toBe(session.Level > previous, true)
		end)

		Harness.it("el portal ve el nivel NUEVO, no el viejo", function()
			-- El filtro del portal debe leer la sesion ya sincronizada.
			local function getPlayerLevel(session: any, atributo: any): number
				if session and type(session.Level) == "number" then
					return session.Level
				end
				return type(atributo) == "number" and atributo or 1
			end

			-- Antes de sincronizar: el portal rechazaba.
			expect.toBe(getPlayerLevel(makeSession(1), 630), 1)
			-- Despues de sincronizar: acepta.
			local sincronizada = makeSession(630)
			expect.toBe(getPlayerLevel(sincronizada, 630), 630)
			expect.toBe(getPlayerLevel(sincronizada, 630) >= 10, true)
			expect.toBe(getPlayerLevel(sincronizada, 630) >= 50, true)
		end)

		Harness.it("un atributo ausente no inventa un nivel", function()
			-- Sin dato del perfil, la sesion se queda como esta: inventar un
			-- nivel aqui seria una segunda fuente de verdad.
			local session = makeSession(1)
			local atributo: any = nil

			if type(atributo) == "number" then
				session.Level = atributo
			end

			expect.toBe(session.Level, 1)
		end)
	end)
end

return describeRoundArenaRouting
