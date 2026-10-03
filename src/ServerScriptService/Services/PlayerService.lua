--!strict
--[[
	PlayerService
	Ciclo de vida de jugadores y estado de sesion en memoria (FASE 2).

	Responsabilidad:
	- Detectar entrada y salida de jugadores con handlers unicos.
	- Conectar el ciclo del personaje: nacimiento, reaparicion y muerte.
	- Mantener el estado temporal de sesion (nivel, mundo, vivo/muerto).
	- Publicar atributos basicos para la interfaz.

	En esta fase el perfil NO se persiste: el DataStore definitivo
	llega en la FASE 15. El estado de aqui es de sesion y se pierde al
	salir, lo cual es intencional y esta documentado.

	Reglas que este servicio garantiza:
	- La MUERTE la decide el servidor (CombatService), nunca el cliente.
	- Un jugador MUERTO no vuelve a `Alive` por reaparecer: si lo
	  hiciera, cobraria dos veces la recompensa de ronda. Por eso el
	  reaparicion respeta el estado de la ronda.
	- Las recompensas son IDEMPOTENTES por ronda (`RewardedRounds`).
	- Nada de lo que llegue del cliente decide el estado.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONFIG = SHARED:WaitForChild("Config")
local CONSTANTS = SHARED:WaitForChild("Constants")
local UTILS = SHARED:WaitForChild("Utils")

local GameConfig = require(CONFIG:WaitForChild("GameConfig"))
local GameConstants = require(CONSTANTS:WaitForChild("GameConstants"))
local CombatMath = require(SHARED:WaitForChild("Libraries"):WaitForChild("CombatMath"))
local Logger = require(UTILS:WaitForChild("Logger"))

local PlayerState = GameConstants.PlayerState

-- NOTA (FASE 0, P0): `PlayerService` ya NO importa `RoundState`.
--
-- Antes decia `RoundState.RoundEnding` y lo pasaba a
-- `RoundService.Transition(...)` para terminar la ronda al morir el ultimo
-- vivo. Eso lo hacia desde SU propio hilo, y el bucle de ronda seguia
-- dormido con el plazo del `Playing` (hasta 180 s): el estado avanzaba a
-- `RoundEnding` pero el ciclo no se enteraba. Medido en runtime:
-- `RoundEnding`, `remaining = 0`, heartbeat congelado 140 s.
--
-- Ahora solo AVISA con `RequestEnd` y deja que el bucle, unico escritor
-- del estado, lo ejecute. Por eso no hace falta conocer los estados aqui:
-- quien decide el estado es el ciclo, no este servicio.

local Service = {}

Service.IsInitialized = false

-- Servicios inyectados por ServerMain.
Service._roundService = nil
Service._combatService = nil
Service._matchService = nil
Service._spawnService = nil

-- UserId -> estado de sesion.
Service._sessions = {}
-- Maid recibido en Init (conexiones de Players).
local MaidRef = nil

--- Crea el estado de sesion de un jugador.
--- @param player Player
--- @return table
local function createSession(player: Player)
	return {
		UserId = player.UserId,
		Username = player.Name,
		State = PlayerState.Alive,

		-- Valores de sesion. La persistencia llega en la FASE 15.
		Level = 1,
		XP = 0,
		Coins = 0,
		Gems = 0,

		-- Contadores de la ronda actual.
		Kills = 0,
		Deaths = 0,

		WorldId = nil,
		TeamId = nil,
		JoinedAt = os.time(),
		IsReady = false,

		-- Ids de ronda ya pagados. Es la garantia de IDEMPOTENCIA: si
		-- el estado `Rewards` se visitase dos veces (por un reload o
		-- un listener duplicado), la segunda vez no volveria a pagar.
		RewardedRounds = {},
	}
end


--- Estado de sesion de un jugador, o nil.
--- @param userId number
--- @return any?
function Service.GetSession(userId: number): any?
	return Service._sessions[userId]
end

--- Estado de sesion a partir del Player.
--- @param player Player?
--- @return any?
function Service.GetSessionFromPlayer(player: Player?): any?
	if not player then
		return nil
	end
	return Service._sessions[player.UserId]
end

--- Cantidad de jugadores con sesion activa.
--- @return number
function Service.GetSessionCount(): number
	local count = 0
	for _ in pairs(Service._sessions) do
		count += 1
	end
	return count
end

--- Cambia el estado de vida del jugador (Alive / Dead / Spectating).
--- @param player Player
--- @param newState string
--- @return boolean success
function Service.SetPlayerState(player: Player, newState: string): boolean
	local session = Service._sessions[player.UserId]

	if not session then
		return false
	end

	local valid = {
		[PlayerState.Alive] = true,
		[PlayerState.Dead] = true,
		[PlayerState.Spectating] = true,
	}

	if not valid[newState] then
		Logger.Warn(("estado de jugador invalido: %s"):format(tostring(newState)))
		return false
	end

	session.State = newState
	player:SetAttribute("PlayerState", newState)
	return true
end

--- Indica si un jugador esta vivo.
--- @param player Player?
--- @return boolean
function Service.IsAlive(player: Player?): boolean
	local session = Service.GetSessionFromPlayer(player)
	return session ~= nil and session.State == PlayerState.Alive
end

--- Publica los atributos que la interfaz necesita.
--- @param player Player
--- @param session any
local function publishAttributes(player: Player, session: any)
	player:SetAttribute("Level", session.Level)
	player:SetAttribute("XP", session.XP)
	player:SetAttribute("Coins", session.Coins)
	player:SetAttribute("Gems", session.Gems)
	player:SetAttribute("PlayerState", session.State)
	player:SetAttribute("IsReady", session.IsReady)
	player:SetAttribute("Kills", session.Kills)
	player:SetAttribute("Deaths", session.Deaths)
end

--- Marca al jugador como listo para jugar.
--- @param player Player
--- @param isReady boolean
--- @return boolean success
function Service.SetReady(player: Player, isReady: boolean): boolean
	local session = Service._sessions[player.UserId]

	if not session then
		return false
	end

	session.IsReady = isReady
	player:SetAttribute("IsReady", isReady)
	return true
end

--- Inyecta las dependencias del servicio.
--- @param roundService any
--- @param combatService any
--- @param matchService any?
--- @param spawnService any? servicio que reparte los puntos de aparicion
function Service.SetDependencies(
	roundService: any,
	combatService: any,
	matchService: any?,
	spawnService: any?,
	progressionService: any?,
	economyService: any?
)
	Service._roundService = roundService
	Service._combatService = combatService
	Service._matchService = matchService
	Service._spawnService = spawnService
	-- Los dos de la columna economica. Son OPCIONALES a proposito: sin
	-- ellos el juego sigue arrancando y las recompensas caen en el camino
	-- viejo (sesion en memoria). Exigirlos haria que un fallo del perfil
	-- tumbara tambien la ronda, que no depende de nada de esto.
	Service._progressionService = progressionService
	Service._economyService = economyService
end
--- Asigna al jugador un `SpawnLocation` de la zona segura.
---
--- POR QUE EXISTE (defecto medido en PLAY)
--- --------------------------------------
--- Con el mapa ya construido, la sesion mostraba 6 `SpawnLocation`
--- HABILITADOS en el lobby y, a la vez, `player.RespawnLocation = nil`.
--- Sin esa propiedad, Roblox decide el punto de reaparicion por su cuenta
--- y el jugador puede nacer en el ORIGEN, que esta en mitad del vacio
--- entre el lobby y la arena: cae, lo rescatan y reaparece otra vez en
--- un bucle. Ademas, al morir en la ronda, el renacimiento no vuelve
--- nunca al lobby.
---
--- Se asigna al ENTRAR y no en cada muerte: durante una ronda el jugador
--- debe reaparecer en la arena (eso lo decide `MatchService`), no en el
--- lobby. Fijar aqui el punto del lobby es lo que garantiza que el
---CharacterAutoLoads arranque en la zona segura.
--- @param player Player
function Service.AssignRespawnLocation(player: Player)
	local spawnService = Service._spawnService
	local location

	if spawnService and spawnService.PickSpawnLocation then
		location = spawnService.PickSpawnLocation(player)
	end

	-- Sin `SpawnService` (arranque degradado) se busca directamente en el
	-- mapa: es mejor un punto valido por la via larga que ninguno.
	if not location then
		local folder = game:GetService("Workspace"):FindFirstChild("SpawnLocations")
		if folder then
			location = folder:FindFirstChildWhichIsA("SpawnLocation")
		end
	end

	if location then
		player.RespawnLocation = location
		Logger.Debug(("spawn asignado a %s: %s"):format(player.Name, location.Name))
	end
end

--- Recalcula el nivel a partir del XP acumulado y notifica la subida.
---
--- El nivel NO tiene tope artificial: la curva es una potencia
--- fraccionaria que crece sin limite. `GameConfig.MaxLevel` existe solo
--- como red de seguridad ante un XP corrupto.
--- @param player Player
--- @param session any
local function refreshLevel(player: Player, session: any)
	local previousLevel = session.Level

	session.Level = CombatMath.LevelForXp(
		session.XP,
		GameConfig.XPPerLevel,
		GameConfig.LevelCurveExponent,
		GameConfig.MaxLevel
	)

	if session.Level > previousLevel then
		-- Se avisa con un atributo, no con un remoto: el cliente decide
		-- COMO celebrarlo, nunca SI se celebra.
		player:SetAttribute("LeveledUpTo", session.Level)
		Logger.Info(("%s alcanzo el nivel %d"):format(player.Name, session.Level))
	end
end

--- Suma experiencia y monedas a la sesion del jugador.
---
--- Los valores se filtran con `CombatMath.SafeRewardAmount`: un NaN o
--- un infinito dejarian el perfil corrupto de forma permanente.
--- @param player Player
--- @param xp number
--- @param coins number
--- @return boolean applied
function Service.AddRewards(player: Player, xp: number, coins: number): boolean
	local session = Service._sessions[player.UserId]

	if not session then
		return false
	end

	-- Camino NUEVO: el perfil es la fuente de verdad.
	--
	-- Solo se usa si el XP y las monedas son validos. Si vienen mal (NaN,
	-- negativos) se avisa y se cae al camino viejo, que ya filtra con
	-- `CombatMath.SafeRewardAmount`: perder una recompensa por un dato
	-- corrupto es preferible a propagar el dato corrupto al perfil.
	local validXp = CombatMath.IsFiniteNumber(xp) and xp > 0
	local validCoins = CombatMath.IsFiniteNumber(coins) and coins > 0

	if (validXp and Service._progressionService) or (validCoins and Service._economyService) then
		if validXp and Service._progressionService then
			-- NO se pasa `requestId` aqui a proposito: esta recompensa se
			-- concede UNA vez por evento, y el control que la evita repetir
			-- es `MarkRoundRewarded` mas arriba (una vez por ronda). Fabricar
			-- un id aqui por muerte haria que la SEGUNDA muerte de la misma
			-- ronda, que es legitima, no contara.
			Service._progressionService.AddXP(player, xp * GameConfig.XPMultiplier, "jugador")
		end

		if validCoins and Service._economyService then
			Service._economyService.GrantCurrency(
				player,
				"Coins",
				coins * GameConfig.CoinMultiplier,
				"recompensa_jugador",
				"player_service"
			)
		end

		-- La sesion se actualiza tambien para que el HUD y el codigo viejo
		-- sigan viendo numeros coherentes. No es la fuente de verdad: lo
		-- es el perfil.
		refreshLevel(player, session)
		publishAttributes(player, session)
		return true
	end

	-- Camino VIEJO (sesion en memoria). Se conserva como degradacion: si el
	-- perfil no esta disponible, el jugador sigue ganando XP en la ronda
	-- aunque no se guarde al salir.
	local appliedXp = CombatMath.SafeRewardAmount(xp * GameConfig.XPMultiplier, session.XP)
	local appliedCoins = CombatMath.SafeRewardAmount(coins * GameConfig.CoinMultiplier, session.Coins)

	if appliedXp == 0 and appliedCoins == 0 then
		return false
	end

	session.XP += appliedXp
	session.Coins += appliedCoins

	refreshLevel(player, session)
	publishAttributes(player, session)

	return true
end

--- Indica si una ronda ya fue pagada a este jugador.
--- @param userId number
--- @param roundId number
--- @return boolean
function Service.HasRoundReward(userId: number, roundId: number): boolean
	local session = Service._sessions[userId]

	if not session then
		return false
	end

	return session.RewardedRounds[roundId] == true
end

--- Marca una ronda como pagada. Devuelve false si ya lo estaba.
--- @param userId number
--- @param roundId number
--- @return boolean newlyMarked
function Service.MarkRoundRewarded(userId: number, roundId: number): boolean
	local session = Service._sessions[userId]

	if not session then
		return false
	end

	if session.RewardedRounds[roundId] then
		return false
	end

	session.RewardedRounds[roundId] = true
	return true
end

--- Reinicia los contadores de ronda.
--- @param player Player
function Service.ResetRoundCounters(player: Player)
	local session = Service._sessions[player.UserId]

	if not session then
		return
	end

	session.Kills = 0
	session.Deaths = 0
	publishAttributes(player, session)
end

--- Gestiona la muerte de un jugador durante la ronda.
---
--- La muerte la decide el servidor (CombatService) y aqui se traducen
--- sus consecuencias: marcar al jugador, premiar a quien lo mato y
--- terminar la ronda si no queda nadie.
--- @param player Player la victima
--- @param killer Player? quien la mato (puede ser nil)
function Service.OnPlayerDied(player: Player, killer: Player?)
	local session = Service._sessions[player.UserId]

	if not session then
		return
	end

	-- Idempotencia de la muerte: si `Died` se disparase dos veces (por
	-- una conexion duplicada), no se contaria dos veces ni se pagaria
	-- dos veces al asesino.
	if session.State == PlayerState.Dead then
		return
	end

	session.Deaths += 1
	Service.SetPlayerState(player, PlayerState.Dead)
	publishAttributes(player, session)

	Logger.Info(("%s ha muerto%s"):format(
		player.Name,
		killer and (" por " .. killer.Name) or ""
	))

	-- Recompensa por eliminacion. La concede el servidor y se marca la
	-- ronda como pagada para que `GrantRoundRewards` no la duplice.
	if killer and Service._roundService then
		local roundId = Service._roundService.GetRoundNumber()

		if roundId > 0 and Service.MarkRoundRewarded(killer.UserId, -roundId) then
			Service.AddRewards(killer, GameConfig.XPPerKill, GameConfig.CoinsPerKill)
			killer:SetAttribute("LastKillVictim", player.Name)
		end
	end

	-- Si no queda nadie vivo, la ronda debe terminar. MatchService se
	-- encarga del traslado al terminar.
	if Service._roundService and Service._roundService.IsPlaying() then
		local alive = 0

		for _, other in ipairs(Players:GetPlayers()) do
			if Service.IsAlive(other) then
				alive += 1
			end
		end
		Logger.Debug(("vivos tras la muerte de %s: %d"):format(player.Name, alive))

		-- `GetAliveCount` mira el Humanoid, que es la fuente de verdad
		-- del motor. La cuenta local sirve para el log; la decision la
		-- toma el servicio de ronda para no depender de dos fuentes.
		--
		-- Se avisa con `RequestEnd`, NO llamando a `Transition`:
		--
		--   `Transition` la puede llamar cualquiera, y quien la llama desde
		--   otro hilo deja al bucle dormido con el plazo del estado
		--   ANTERIOR. Eso fue el P0 de la FASE 0: al morir el ultimo vivo
		--   durante un `Playing` de 180 s, el estado pasaba a `RoundEnding`
		--   pero el bucle seguia esperando los 180 s del `Playing`.
		--   Medido: `RoundEnding`, `remaining = 0`, heartbeat congelado.
		--
		--   `RequestEnd` deja constancia de la INTENCION y devuelve; el
		--   bucle la ejecuta en su proxima rebanada. Un solo escritor del
		--   estado significa que nunca se compite con el.
		if Service._roundService.GetAliveCount() <= 1 then
			Service._roundService.RequestEnd(("ultimo vivo eliminado: %s"):format(player.Name))
		end
	end
end

--- Conecta el ciclo de vida del personaje de un jugador.
---
--- BUG CORREGIDO AQUI (FASE 2):
--- La version anterior llamaba a `SetPlayerState(Alive)` en CADA
--- `CharacterAdded`. Como Roblox reaparece al jugador automaticamente
--- tras morir, un muerto volvia a `Alive` a los pocos segundos: podia
--- cobrar la recompensa de ronda Y hacia que la ronda nunca terminara
--- (el recuento de vivos nunca llegaba a cero).
---
--- Ahora el reaparicion respeta la ronda:
---   - Con ronda en curso -> vuelve a la arena, `Alive`, con
---     invulnerabilidad breve.
---   - Sin ronda en curso -> al lobby, `Alive`.
---   - Si la ronda ya termino para el -> se queda `Dead` y no cobra.
---
--- @param player Player
local function bindCharacter(player: Player)
	local function onCharacter(_character: Model)
		local session = Service._sessions[player.UserId]

		if not session then
			return
		end

		-- CombatService es el que conecta `Died`. Si no esta inyectado,
		-- el servidor no se enteraria de las muertes y el PvP no
		-- terminaria: es un fallo real, no un aviso.
		if Service._combatService then
			Service._combatService.BindCharacter(player)
		else
			Logger.Error(("CombatService no inyectado: %s no tendra ciclo de muerte"):format(player.Name))
		end

		local roundService = Service._roundService
		-- BUG CORREGIDO (medido en PLAY): se usaba `IsPlaying()`, que solo es
		-- cierta en `Playing` y `SuddenDeath`. El traslado a la arena ocurre en
		-- `RoundStarting`, asi que durante esos 3 s un reaparicion mandaba al
		-- jugador al LOBBY y deshacia el traslado. El log lo repetia en cada
		-- ronda: "movido a Arena" seguido de "movido a Lobby".
		--
		-- `IsRoundActive` cubre `RoundStarting`, `Playing` y `SuddenDeath`: la
		-- pregunta correcta no es "se puede jugar ya" sino "este jugador
		-- pertenece a la arena".
		local inArena = roundService ~= nil and roundService.IsRoundActive()

		if inArena then
			Service.SetPlayerState(player, PlayerState.Alive)

			-- Invulnerabilidad breve: sin ella, una bomba que explota en
			-- el instante del teletransporte mata al jugador.
			if Service._combatService then
				Service._combatService.GrantInvulnerability(player, GameConfig.SpawnProtectionTime)
			end

			if Service._matchService then
				Service._matchService.MovePlayer(player, "Arena")
			end

			Logger.Debug(("%s reaparecio en la arena"):format(player.Name))
		elseif session.State == PlayerState.Dead and roundService then
			-- La ronda termino mientras estaba muerto: se queda fuera y
			-- NO cobra la recompensa de supervivencia.
			Service.SetPlayerState(player, PlayerState.Dead)
		else
			Service.SetPlayerState(player, PlayerState.Alive)

			if Service._matchService then
				Service._matchService.MovePlayer(player, "Lobby")
			end
		end

		publishAttributes(player, session)
	end

	-- `CharacterAdded` puede haberse disparado antes de que nos
	-- conectemos: sin esta comprobacion, un jugador que entra rapido se
	-- queda sin ciclo de vida en absoluto.
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end

	local connection = player.CharacterAdded:Connect(onCharacter)

	if MaidRef then
		MaidRef:Add(connection)
	end
end

--- Gestiona la entrada de un jugador.
--- @param player Player
function Service.OnPlayerAdded(player: Player)
	-- Idempotente: un mismo jugador no genera dos sesiones.
	if Service._sessions[player.UserId] then
		return
	end

	local session = createSession(player)
	Service._sessions[player.UserId] = session
	publishAttributes(player, session)

	-- Tiempo de reaparicion desde la configuracion: sin esto se usa el
	-- valor por defecto de Roblox y el PvP se siente lento.
	--
	-- BUG CORREGIDO (auditoria de integracion): esto escribia
	-- `player.RespawnTime`. Esa propiedad NO existe en la instancia Player
	-- y el log del playtest lo confirmaba:
	--     "RespawnTime is not a valid member of Player Players.SiSoyPapito"
	-- El error no era cosmetico: lanzaba DENTRO de OnPlayerAdded, justo
	-- antes de `bindCharacter`, asi que `CharacterAdded`/`CharacterRemoving`
	-- nunca se conectaban. El servidor se quedaba sin enterarse de las
	-- muertes por bomba: el combatimiento autoritativo no arrancaba nunca.
	--
	-- `RespawnTime` cuelga del SERVICIO Players, no del jugador. Es un
	-- ajuste global del servidor, asi que se aplica una sola vez al
	-- arrancar el servicio en vez de en cada conexion.
	if GameConfig.RespawnTime ~= nil then
		Players.RespawnTime = GameConfig.RespawnTime
	end

	-- El punto de reaparicion se fija ANTES de que nazca el personaje:
	-- sin esto, `player.RespawnLocation` queda en nil y Roblox elige el
	-- origen, que en este mapa esta en mitad del vacio.
	Service.AssignRespawnLocation(player)

	-- El ciclo del personaje (nacimiento y muerte) se conecta aqui: sin
	-- esto el servidor no se entera de las muertes por bomba.
	bindCharacter(player)

	Logger.Info(("#%d %s conectado. Sesiones activas: %d"):format(
		player.UserId,
		player.Name,
		Service.GetSessionCount()
	))
end

--- Gestiona la salida de un jugador.
---
--- Regla de shutdown: la limpieza debe ser rapida y no puede fallar
--- por datos incompletos. En esta fase no hay data que guardar.
--- @param player Player
function Service.OnPlayerRemoving(player: Player)
	Service._sessions[player.UserId] = nil
	Logger.Info(("#%d %s desconectado"):format(player.UserId, player.Name))
end

--- @param maid any?
--- @return boolean success
function Service.Init(maid: any?): boolean
	if Service.IsInitialized then
		return true
	end

	MaidRef = maid
	Service._sessions = {}

	Service.IsInitialized = true
	return true
end

--- @return boolean success
function Service.Start(): boolean
	if not Service.IsInitialized then
		Logger.Error("PlayerService: Start sin Init")
		return false
	end

	if MaidRef then
		MaidRef:Connect(Players.PlayerAdded, Service.OnPlayerAdded)
		MaidRef:Connect(Players.PlayerRemoving, Service.OnPlayerRemoving)
	end

	-- Jugadores ya conectados (posible carga tardia del script).
	for _, player in ipairs(Players:GetPlayers()) do
		Service.OnPlayerAdded(player)
	end

	local connected = #Players:GetPlayers()
	Logger.Info(("PlayerService listo. Jugadores conectados: %d"):format(connected))

	if connected > Players.MaxPlayers then
		Logger.Warn(("hay mas jugadores que el maximo permitido (%d)"):format(Players.MaxPlayers))
	end

	return true
end

--- @return boolean success
function Service.Destroy(): boolean
	Service._sessions = {}
	MaidRef = nil
	Service._roundService = nil
	Service._combatService = nil
	Service._matchService = nil
	Service._spawnService = nil
	Service.IsInitialized = false
	return true
end

return Service
