--!strict
--[[
	MatchService
	Orquesta la partida: teletransporta a los jugadores entre el lobby y
	la arena segun el estado de la ronda.

	Es el unico lugar que decide DONDE esta un jugador. MatchmakingService
	(FASE 20) decidira QUIEN juega; aqui solo se resuelve el traslado.

	Los destinos se leen de marcadores con nombre dentro del mapa:
		Workspace.Lobby.LobbyCenter
		Workspace.Worlds.Forest.ArenaCenter
	Los genera `tools/generate-project.js`.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONFIG = SHARED:WaitForChild("Config")
local CONSTANTS = SHARED:WaitForChild("Constants")
local UTILS = SHARED:WaitForChild("Utils")

local GameConfig = require(CONFIG:WaitForChild("GameConfig"))
local GameConstants = require(CONSTANTS:WaitForChild("GameConstants"))
local Logger = require(UTILS:WaitForChild("Logger"))

local RoundState = GameConstants.RoundState

local Service = {}

Service.IsInitialized = false

-- Servicios inyectados por ServerMain.
Service._roundService = nil
Service._playerService = nil
Service._bombService = nil
Service._destructionService = nil
Service._combatService = nil

-- QuestService: receptor del progreso de misiones (rondas ganadas).
--
-- Es OPCIONAL a proposito: sin el, las rondas funcionan igual y solo la
-- mision "ganar una ronda" no avanza.
Service._questService = nil

-- PowerupService: genera y aplica los powerups de la arena. Es OPCIONAL:
-- sin el, la ronda funciona igual y lo unico que se pierde son los objetos
-- que recoger.
Service._powerupService = nil

--- Conecta el generador de powerups.
--- @param powerupService any?
function Service.SetPowerupService(powerupService: any?)
	Service._powerupService = powerupService
end

-- Destinos por nombre: "Lobby" y "Arena_<WorldId>".
--
-- Antes solo existia `Arena`, y apuntaba SIEMPRE a Forest. Con eso, entrar por
-- el portal de Desert no llevaba a Desert: `PortalService` caia en el
-- `else` y teletransportaba al lobby. Medido en PLAY: cuatro de los cinco
-- portales no llegaban a ninguna parte.
--
-- Ahora hay un destino por mundo, `Arena_<Id>`, construido desde el marcador
-- `ArenaCenter` que el generador escribe en cada arena. `Arena` se conserva
-- como alias del mundo por defecto porque el ciclo de ronda lo usa y anadir
-- el concepto de "mundo activo" al round es un cambio mayor del que esta
-- correccion necesita.
-- Destinos por nombre: `Lobby` (llegada real al lobby), `LobbyCenter`
-- (centro geometrico), `Arena` y `Arena_<WorldId>`.
--
-- El tipo se declara en una variable LOCAL y no sobre el campo
-- (`Service._destinations: T = {}`): el analizador de este proyecto no
-- acepta la anotacion en una tabla, falla con "Expected identifier when
-- parsing method name". La variable anotada produce el mismo efecto sobre
-- la inferencia y ademas es sintaxis que Luau acepta en todas partes.
--
-- La clave es `string` a proposito: las arenas se indexan con
-- `"Arena_" .. worldId`, y un union de literales no lo admitiria.
local destinations: { [string]: BasePart } = {}
Service._destinations = destinations
-- Mundo por defecto -> id de destino. Consultado por `GetArenaKey`.
Service._defaultArenaKey = "Arena"

--- Busca los marcadores de traslado en el mapa.
---
--- BUG CORREGIDO (medido en la captura del cliente): el destino "Lobby"
--- era `LobbyCenter`, que esta en (0, 0.2, 0), es decir EN EL CENTRO
--- GEOGRAFICO DEL LOBBY. Y en ese centro esta el Keshusy Core:
---
---     CoreBase  (0, 0.5, 0)   colisiona
---     CoreDais  (0, 3.2, 0)   colisiona
---     CoreOrb   (0, 8, 0)     Neon, el corazon del juego
---
--- Al terminar una ronda, `MoveAllPlayers("Lobby")` depositaba al jugador
--- ENCIMA del nucleo. Medido: el personaje aparecia en (0, 6.9, 0), dentro
--- del orbe, y la primera imagen del juego era una esfera blanca con el
--- personaje dentro. El lobby se leia como un fallo, no como el corazon del
--- universo.
---
--- El arreglo NO es borrar `LobbyCenter` (lo leen otros comprobadores y es
--- contrato del mapa): es anadir `LobbyReturn`, un marcador de llegada
--- colocado al SUR del Core, de cara a los portales, y que sea el que se usa
--- como destino "Lobby". `LobbyCenter` se conserva como referencia del
--- centro geometrico.
--- @return number found
function Service.CollectDestinations(): number
	Service._destinations = {}

	local lobby = Workspace:FindFirstChild("Lobby")
	local lobbyCenter = lobby and lobby:FindFirstChild("LobbyCenter")
	if lobbyCenter and lobbyCenter:IsA("BasePart") then
		Service._destinations.LobbyCenter = lobbyCenter :: BasePart
	end

	local lobbyReturn = lobby and lobby:FindFirstChild("LobbyReturn")

	-- Destino de llegada al lobby. Se prefiere `LobbyReturn` y, si el mapa no
	-- lo trae, se cae a `LobbyCenter` (comportamiento anterior, mejor que
	-- dejar al jugador sin destino).
	--
	-- Se decide con ramas `if` explicitas y una variable intermedia, en vez de
	-- asignar el resultado de un `if` expresivo: esa forma produce un tipo
	-- que Luau no puede verificar (`*error-type* | ~(false?)`) y el
	-- analizador deja de poder confirmar que `lobbyTarget` es un BasePart.
	-- Ademas el destino debe quedar ANOTADO para que el resto del servicio
	-- pueda indexar `_destinations.Lobby` sin un chequeo defensivo.
	local lobbyTarget = nil :: any?

	if lobbyReturn and lobbyReturn:IsA("BasePart") then
		lobbyTarget = lobbyReturn :: BasePart
	elseif lobbyCenter and lobbyCenter:IsA("BasePart") then
		lobbyTarget = lobbyCenter :: BasePart
	end

	if lobbyTarget then
		Service._destinations.Lobby = lobbyTarget
	end

	-- Un destino por mundo. El mundo se recorre por la clave del mapa, no
	-- por una lista constante: anadir un mundo al generador lo hace
	-- jugable sin tocar este archivo.
	local worlds = Workspace:FindFirstChild("Worlds")
	local defaultWorld = Service._worldService and Service._worldService.GetDefaultWorldId()

	if worlds then
		for _, worldFolder in ipairs(worlds:GetChildren()) do
			local arenaCenter = worldFolder:FindFirstChild("ArenaCenter")

			if arenaCenter and arenaCenter:IsA("BasePart") then
				local key = "Arena_" .. worldFolder.Name
				Service._destinations[key] = arenaCenter :: BasePart

				if defaultWorld and worldFolder.Name == defaultWorld then
					-- Alias para el codigo que aun pide "Arena" a secas
					-- (el ciclo de ronda). Apunta al MISMO Part, asi que
					-- no hay dos destinos que puedan divergir.
					Service._destinations.Arena = arenaCenter :: BasePart
					Service._defaultArenaKey = key
				end
			end
		end
	end

	local found = 0
	for _ in pairs(Service._destinations) do
		found += 1
	end

	return found
end

--- Clave de destino de la arena de un mundo.
---
--- Acepta tanto el id (`Desert`) como la clave ya construida (`Arena_Desert`),
--- para que el llamante no tenga que saber como se nombra internamente.
--- @param worldId string
--- @return string key
function Service.GetArenaKey(worldId: string): string
	if worldId and worldId ~= "" and not string.match(worldId, "^Arena_") then
		return "Arena_" .. worldId
	end

	return worldId
end

--- Destino de la arena de un mundo, con caida al del mundo por defecto.
---
--- El `fallback` importa: un mundo cuyo mapa no llego al lugar debe llevar
--- al jugador a una arena REAL, no dejarlo en el lobby. Es mejor una arena
--- equivocada que ninguna.
--- @param worldId string?
--- @return BasePart?
function Service.GetWorldArena(worldId: string?): BasePart?
	if worldId then
		local arena = Service._destinations[Service.GetArenaKey(worldId)]
		if arena then
			return arena
		end
	end

	return Service._destinations.Arena
end

--- Nombre del mundo al que corresponde una clave de destino.
--- @param key string
--- @return string worldId "Lobby" si el destino es el lobby
function Service.GetWorldOfDestination(key: string): string
	if key == "Lobby" then
		return "Lobby"
	end

	local worldId = string.match(key, "^Arena_(.+)$")

	if worldId and Service._destinations["Arena_" .. worldId] then
		return worldId
	end

	return "Lobby"
end

--- Destino solicitado por nombre ("Lobby" / "Arena").
--- @param key string
--- @return BasePart?
function Service.GetDestination(key: string): BasePart?
	return Service._destinations[key]
end

--- Teletransporta el personaje de un jugador a un destino.
---
--- Mueve el MODEL entero con `PivotTo`, no solo el HumanoidRootPart:
--- mover una sola parte deja el resto del personaje colgando en el aire.
--- @param player Player
--- @param key string
--- @return boolean moved
function Service.MovePlayer(player: Player, key: string): boolean
	local destination = Service._destinations[key]
	if not destination then
		Logger.Warn(("destino '%s' no encontrado en el mapa"):format(key))
		return false
	end

	local character = player.Character
	if not character then
		return false
	end

	if not character:FindFirstChild("HumanoidRootPart") then
		return false
	end

	-- Se sube un poco para que el personaje no nazca dentro del suelo.
	character:PivotTo(destination.CFrame + Vector3.new(0, 4, 0))

	-- El estado de vida se reinicia al cambiar de zona: entrar en la
	-- arena muerto dejaria al jugador sin poder jugar.
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = humanoid.MaxHealth
	end

	-- INVULNERABILIDAD AL ENTRAR EN LA ARENA (FASE 8).
	-- El teletransporte ocurre en `RoundStarting`, y `Playing` llega
	-- justo despues. Una bomba ya plantada en la posicion de llegada
	-- explotaria en ese instante y mataria al jugador antes de que
	-- pueda moverse: es la misma razon por la que existe
	-- `SpawnProtectionTime` en el reaparicion.
	-- La invulnerabilidad se concede al entrar en CUALQUIER arena, no solo
	-- en la del mundo por defecto. La comprobacion es `GetWorldOfDestination`
	-- porque comparar contra `"Arena"` a secas solo cubria Forest: con las
	-- cinco arenas construidas, entrar por el portal de Cyber dejaba al
	-- jugador con una bomba ya plantada en el punto de llegada.
	local worldOfMove = Service.GetWorldOfDestination(key)

	if worldOfMove ~= "Lobby" and Service._combatService then
		Service._combatService.GrantInvulnerability(player, GameConfig.SpawnProtectionTime)
	end

	if Service._playerService then
		Service._playerService.SetPlayerState(player, GameConstants.PlayerState.Alive)
	end

	-- PUBLICAR EL MUNDO EN EL HUD.
	--
	-- Se hace aqui y no en el portal porque `MovePlayer` es el UNICO punto
	-- por el que pasa cualquier traslado: el del portal, el de entrada a la
	-- arena y el de vuelta al lobby. Publicarlo en el portal dejaria el
	-- atributo desactualizado en cuanto la ronda moviera a alguien, y el HUD
	-- diria "Lobby" con el jugador dentro de la arena.
	--
	-- El nombre sale de la PROPIA clave de destino, no de un literal. Antes
	-- ponia "Forest" para cualquier arena, asi que entrar en Desert hacia
	-- que el HUD dijera Forest.
	--
	-- Es un atributo que escribe el SERVIDOR: el cliente puede alterarlo en
	-- su pantalla sin consecuencia, porque no concede nada.
	local worldName = worldOfMove
	player:SetAttribute("World", worldName)

	Logger.Debug(("%s movido a %s"):format(player.Name, key))
	return true
end

--- Mueve a todos los jugadores conectados a un destino.
--- @param key string
--- @return number moved
function Service.MoveAllPlayers(key: string): number
	local moved = 0

	for _, player in ipairs(Players:GetPlayers()) do
		if Service.MovePlayer(player, key) then
			moved += 1
		end
	end

	Logger.Info(("%d jugador(es) movidos a %s"):format(moved, key))
	return moved
end

--- Reparte la recompensa de fin de ronda.
---
--- La calcula y aplica el SERVIDOR: el cliente solo muestra el mensaje
--- que se publica en `RoundResult`, nunca lo decide.
--- @return number rewarded cantidad de jugadores pagados
function Service.GrantRoundRewards()
	local rewarded = 0
	local roundId = 0

	if Service._roundService then
		roundId = Service._roundService.GetRoundNumber()
	end

	-- Sin numero de ronda no se puede garantizar idempotencia: es
	-- preferible NO pagar a pagar dos veces.
	if roundId <= 0 then
		Logger.Warn("GrantRoundRewards: sin numero de ronda; no se paga.")
		return 0
	end

	for _, player in ipairs(Players:GetPlayers()) do
		local alive = not Service._playerService or Service._playerService.IsAlive(player)

		if alive then
			-- IDEMPOTENCIA: la ronda se marca como pagada ANTES de
			-- entregar nada. Si el estado `Rewards` se visitase dos
			-- veces, la segunda no paga. La marca se escribe primero a
			-- proposito: si el proceso se cortara a mitad, es preferible
			-- perder una recompensa que duplicarla.
			local newlyMarked = false

			if Service._playerService then
				newlyMarked = Service._playerService.MarkRoundRewarded(player.UserId, roundId)
			else
				newlyMarked = true
			end

			if newlyMarked then
				if Service._playerService then
					Service._playerService.AddRewards(
						player,
						GameConfig.XPPerRound,
						GameConfig.CoinsPerRound
					)
				end

				player:SetAttribute(
					"RoundResult",
					("Ronda completada: +%d XP, +%d monedas"):format(GameConfig.XPPerRound, GameConfig.CoinsPerRound)
				)
				rewarded += 1
			end
		else
			player:SetAttribute("RoundResult", "Ronda perdida")
		end
	end

	Logger.Info(("%d jugador(es) recibieron recompensa de la ronda %d"):format(rewarded, roundId))
	return rewarded
end

--- Poblacion de monstruos de la ronda, en la arena activa.
---
--- Se lee de la DEFINICION del mundo (`SpawnRules`), no de una constante
--- aqui: anadir un mundo con sus propias criaturas no debe obligar a tocar
--- este archivo. Y se usa `CFrame.lookAt` hacia el centro para que el
--- monstruo nazca mirando hacia dentro y no de espaldas.
---
--- ANTES: la poblacion era SIEMPRE `{ Slime, Slime, BombBug, Shadow }`, la
--- de Forest, calculada sobre el `ArenaCenter` de Forest. Los otros cuatro
--- mundos, aunque existen, generaban la fauna equivocada en el sitio
--- equivocado. Ahora salen de `SpawnRules` del mundo y de SU arena.
---
--- Si un mundo no declara reglas, no se inventa poblacion: es mejor un mundo
--- sin monstruos que un mundo con slimes de otro bioma.
--- @return { { Id: string, Position: Vector3 } }
function Service.BuildMonsterSpawns(worldId: string?): { { Id: string, Position: Vector3 } }
	local spawns: { { Id: string, Position: Vector3 } } = {}

	local world = worldId
		or (Service._worldService and Service._worldService.GetDefaultWorldId())

	if not world then
		return spawns
	end

	local definition = Service._worldService and Service._worldService.GetWorld(world)

	if not definition then
		Logger.Debug(("poblacion de monstruos: el mundo '%s' no esta registrado"):format(world))
		return spawns
	end

	local rules = definition.SpawnRules or {}

	if #rules == 0 then
		Logger.Debug(("el mundo '%s' no declara SpawnRules; no hay poblacion"):format(world))
		return spawns
	end

	-- La arena es la de ESE mundo, no la del mundo por defecto.
	local arena = Service.GetWorldArena(world)

	if not arena then
		return spawns
	end

	-- Los puntos de spawn declarados en el mapa mandan sobre el anillo
	-- calculado: el generador escribe cuatro por mundo, y son la fuente de
	-- verdad de la densidad de cada arena.
	local declared = Service.CollectMonsterSpawnPoints(world)
	local origin = arena.Position

	-- El anillo sale del tamano real del suelo: hardcodear un radio echaria
	-- monstruos al vacio en cualquier arena que no sea cuadrada.
	local halfWidth = (arena.Size.X / 2) * 0.6
	local halfDepth = (arena.Size.Z / 2) * 0.6

	for index, id in ipairs(rules) do
		local position

		if declared[index] then
			position = declared[index].Position + Vector3.new(0, 2, 0)
		else
			local angle = (index / #rules) * math.pi * 2
			position = origin + Vector3.new(
				math.cos(angle) * halfWidth,
				3,
				math.sin(angle) * halfDepth
			)
		end

		table.insert(spawns, { Id = id, Position = position })
	end

	Logger.Debug(("poblacion de monstruos para el mundo %s: %d"):format(world, #spawns))

	return spawns
end

--- Puntos de spawn de monstruo declarados en el mapa de un mundo.
---
--- Los escribe `tools/worlds.js` como `MonsterSpawn_<Id>_<n>`. Se leen por
--- prefijo y no con una lista fija para que anadir un punto no obligue a tocar
--- este archivo.
--- @param worldId string
--- @return { BasePart }
function Service.CollectMonsterSpawnPoints(worldId: string): { BasePart }
	local points: { BasePart } = {}

	local worlds = Workspace:FindFirstChild("Worlds")
	local worldFolder = worlds and worlds:FindFirstChild(worldId)
	local spawnsFolder = worldFolder and worldFolder:FindFirstChild("MonsterSpawns")

	if not spawnsFolder then
		return points
	end

	for _, child in ipairs(spawnsFolder:GetChildren()) do
		if child:IsA("BasePart") then
			table.insert(points, child :: BasePart)
		end
	end

	-- Orden estable: el recorrido de `GetChildren` no esta garantizado, y
	-- el orden decide que monstruo va en que punto.
	table.sort(points, function (a, b)
		return a.Name < b.Name
	end)

	return points
end

--- Crea los monstruos de la ronda.
---
--- Es idempotente en la practica: `MonsterService.Spawn` aplica el tope por
--- tipo, asi que llamarlo dos veces no duplica la poblacion.
---
--- `worldId` permite poblar una arena distinta de la del mundo por defecto:
--- es lo que hace que entrar por el portal de Volcano tenga monstruos de
--- Volcano y no los de Forest.
--- @param worldId string?
--- @return number spawned
function Service.SpawnMonstersForRound(worldId: string?): number
	if not Service._monsterService then
		return 0
	end

	local spawned = 0

	for _, entry in ipairs(Service.BuildMonsterSpawns(worldId)) do
		if Service._monsterService.Spawn(entry.Id, entry.Position) then
			spawned += 1
		end
	end

	if spawned > 0 then
		Logger.Info(("%d monstruo(s) generados en la arena"):format(spawned))
	end

	return spawned
end

--- Genera los powerups de la ronda en el mundo indicado.
---
--- Antes no existia nada aqui: el mapa declaraba cuatro `PowerupSpawns` por
--- mundo y nadie los llenaba. Eran cuatro placas de color en el suelo, y el
--- jugador no tenia nada que recoger en toda la arena.
--- @param worldId string?
--- @return number spawned
function Service.SpawnPowerupsForRound(worldId: string?): number
	if not Service._powerupService then
		return 0
	end

	return Service._powerupService.SpawnForRound(worldId)
end

--- Reacciona a los cambios de ronda.
--- @param from string
--- @param to string
function Service.OnRoundStateChanged(from: string, to: string)
	if to == RoundState.RoundStarting then
		-- Los contadores se reinician ANTES de teletransportar. Si se
		-- hiciese despues, el HUD del jugador mostraria las kills de la
		-- ronda anterior sumadas a las de la nueva (bug corregido).
		if Service._playerService then
			for _, player in ipairs(Players:GetPlayers()) do
				Service._playerService.ResetRoundCounters(player)
			end
		end

		Service.MoveAllPlayers("Arena")

		-- Orden de la arena: primero los monstruos y despues los powerups. Un
		-- powerup ya flotando cuando aparece el enemigo dice "hay cosas que
		-- recoger aqui" en vez de "han soltado un cubo".
		Service.SpawnMonstersForRound()
		Service.SpawnPowerupsForRound()

	elseif to == RoundState.RoundEnding then
		-- Las bombas que quedaran explotando danarian a los jugadores
		-- ya devueltos al lobby.
		if Service._bombService then
			Service._bombService.ClearBombs()
		end

		-- Los monstruos se limpian ANTES de que los jugadores vuelvan al
		-- lobby. Si se limpiaran despues, un Slime podria seguir persiguiendo
		-- a un jugador ya devuelto y matarlo fuera de la arena.
		if Service._monsterService then
			local removed = Service._monsterService.ClearAll()
			Logger.Info(("%d monstruo(s) limpiados al terminar la ronda"):format(removed))
		end

		-- Los powerups tambien se limpian: si se dejaran, el jugador volveria
		-- al lobby con objetos flotando en un sitio donde no puede recogerlos.
		if Service._powerupService then
			local removedPowerups = Service._powerupService.ClearAll()

			if removedPowerups > 0 then
				Logger.Info(("%d powerup(s) limpiados al terminar la ronda"):format(removedPowerups))
			end
		end

	elseif to == RoundState.Rewards then
		Service.GrantRoundRewards()

		-- Progreso de mision: "ganar 1 ronda".
		--
		-- Se emite en `Rewards`, que es el estado donde el servidor YA ha
		-- decidido que la ronda termino bien. Emitirlo en `RoundEnding`
		-- contaria rondas perdidas, y emitirlo antes de pagar abriria la
		-- puerta a "mision completada" sin recompensa por la ronda.
		--
		-- Se recorre a los jugadores CONECTADOS, no a los que hayian
		-- dalam la arena: quien se salio antes no gano la ronda, y
		-- contarle haria que la mision se completara sola.
		if Service._questService ~= nil then
			for _, player in ipairs(Players:GetPlayers()) do
				Service._questService.RecordMetric(player, "RoundWon", 1)
			end
		end

	elseif to == RoundState.ReturningToLobby then
		Service.MoveAllPlayers("Lobby")

		-- El mapa se repara al terminar la ronda: si no, la arena se
		-- quedaria sin bloques tras varias rondas.
		if Service._destructionService then
			local restored = Service._destructionService.RestoreAll()
			Logger.Info(("%d bloques restaurados"):format(restored))
		end
	end
end

--- Conecta el receptor de progreso de misiones.
---
--- Es OPCIONAL: sin el, las rondas funcionan igual y solo la mision "ganar
--- una ronda" no avanza.
--- @param questService any?
function Service.SetQuestService(questService: any)
	Service._questService = questService
end

--- Inyecta las dependencias del servicio.
--- @param roundService any
--- @param playerService any
--- @param bombService any
--- @param destructionService any
--- @param combatService any?
function Service.SetDependencies(
	roundService: any,
	playerService: any,
	bombService: any,
	destructionService: any,
	combatService: any?,
	monsterService: any?,
	worldService: any?
)
	Service._roundService = roundService
	Service._playerService = playerService
	Service._bombService = bombService
	Service._destructionService = destructionService
	Service._combatService = combatService
	Service._monsterService = monsterService
	Service._worldService = worldService
end

--- Inicializacion del servicio. Idempotente.
--- @param maid any?
--- @return boolean success
function Service.Init(maid: any?): boolean
	if Service.IsInitialized then
		return true
	end

	local found = Service.CollectDestinations()

	if found < 2 then
		-- Sin los dos destinos la partida no puede empezar. Se registra
		-- como ERROR y NO como aviso porque el juego no seria jugable.
		Logger.Error(("MatchService: faltan marcadores de destino (%d de 2). El mapa no es jugable."):format(found))
		return false
	end

	Service.IsInitialized = true
	Logger.Info("MatchService: destinos cargados (Lobby, Arena)")
	return true
end

--- @return boolean success
function Service.Start(): boolean
	if not Service.IsInitialized then
		Logger.Error("MatchService: Start sin Init")
		return false
	end

	if not Service._roundService then
		-- BUG CRITICO QUE ESTE BLOQUE OCULTABA (auditoria de integracion):
		-- esto es un ERROR FATAL, no un aviso. Sin `RoundService` no hay
		-- maquina de estados a la que suscribirse, y por tanto NADIE se
		-- teletransporta nunca: ni a la arena ni de vuelta al lobby. El
		-- juego "arranca" y no hace absolutamente nada. Por eso devuelve
		-- false: el registro lo marca como fallo y el informe de arranque
		-- lo dice en voz alta.
		Logger.Error(
			"MatchService: RoundService no inyectado; no habra traslados y la "
			.. "ronda no tendra efecto. El juego no es jugable."
		)
		return false
	end

	-- Suscribirse ANTES de que la ronda avance es imprescindible: si se
	-- hiciera despues, la primera ronda no moveria a nadie.
	Service._roundService.OnStateChanged(Service.OnRoundStateChanged)

	-- Comprobacion de que la suscripcion ha SURGIDO EFECTO.
	--
	-- Que `OnStateChanged` no lance un error NO demuestra que el listener
	-- llegara a la lista: un `RoundService` distinto (por ejemplo, una
	-- segunda copia del modulo cacheada en otro contexto) aceptaria la
	-- llamada y jamas la invocaria. En ese caso `MatchService` queda
	-- `Started`, el arranque parece limpio y NADIE se teletransporta:
	-- el sintoma exacto de "el juego no hace nada".
	--
	-- Se comprueba la lista de listeners directamente. Es una lectura
	-- pura: no dispara transiciones ni altera el ciclo de ronda.
	local listeners = Service._roundService.GetListenerCount()

	if type(listeners) ~= "number" or listeners < 1 then
		Logger.Error(
			("MatchService: la suscripcion a los cambios de ronda NO quedo "
				.. "registrada (listeners=%s). Comprueba que el `RoundService` "
				.. "inyectado es el MISMO que corre el ciclo de ronda."):format(
				tostring(listeners)
			)
		)
		return false
	end

	Logger.Info(("MatchService listo (suscrito a los cambios de ronda; %d listeners)"):format(
		listeners
	))
	return true
end

--- Limpieza del servicio.
--- @return boolean success
function Service.Destroy(): boolean
	Service._destinations = {}
	Service._roundService = nil
	Service._playerService = nil
	Service._bombService = nil
	Service._destructionService = nil
	Service.IsInitialized = false
	return true
end

return Service
