--!strict
--[[
	PlayerService
	Ciclo de vida de jugadores y estado de sesion en memoria (FASE 1).

	Responsabilidad en esta fase:
	- Detectar entrada y salida de jugadores con handlers unicos.
	- Mantener el estado temporal de sesion (nivel, mundo, vivo/muerto).
	- Publicar atributos basicos para la interfaz.

	En esta fase el perfil NO se persiste: el DataStore definitivo
	llega en la FASE 15. El estado de aqui es de sesion y se pierde al
	salir, lo cual es intencional y esta documentado.

	Regla: nada de lo que llegue del cliente decide el estado. El
	servidor es la unica autoridad sobre el estado de un jugador.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONFIG = SHARED:WaitForChild("Config")
local CONSTANTS = SHARED:WaitForChild("Constants")
local UTILS = SHARED:WaitForChild("Utils")

local GameConfig = require(CONFIG:WaitForChild("GameConfig"))
local GameConstants = require(CONSTANTS:WaitForChild("GameConstants"))
local Logger = require(UTILS:WaitForChild("Logger"))

local PlayerState = GameConstants.PlayerState

-- XP necesaria para subir de nivel. Se declara aqui (antes de usarse)
-- porque `AddRewards` la consulta al calcular el nivel.
local XP_PER_LEVEL = 100

local Service = {}

Service.IsInitialized = false

--- Servicios inyectados por ServerMain.
Service._roundService = nil
Service._explosionService = nil

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

		WorldId = nil,
		TeamId = nil,
		JoinedAt = os.time(),
		IsReady = false,
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
function Service.SetDependencies(roundService: any)
	Service._roundService = roundService
end

--- Suma experiencia y monedas a la sesion del jugador.
--- @param player Player
--- @param xp number
--- @param coins number
--- @return boolean applied
function Service.AddRewards(player: Player, xp: number, coins: number): boolean
	local session = Service._sessions[player.UserId]
	if not session then
		return false
	end

	session.XP += math.floor(xp * GameConfig.XPMultiplier)
	session.Coins += math.floor(coins * GameConfig.CoinMultiplier)
	session.Level = 1 + math.floor(session.XP / XP_PER_LEVEL)

	publishAttributes(player, session)
	return true
end

--- Gestiona la muerte de un jugador durante la ronda.
---
--- La muerte la decide el servidor (ExplosionService), y aqui se
--- traducen sus consecuencias: marcar al jugador y premiar a quien
--- sigue vivo. No se reproduce desde el cliente.
--- @param player Player
function Service.OnPlayerDied(player: Player)
	Service.SetPlayerState(player, PlayerState.Dead)
	Logger.Info(("%s ha muerto"):format(player.Name))

	-- Si no queda nadie vivo, la ronda debe terminar. MatchService se
	-- encarga del traslado al terminar.
	if Service._roundService and Service._roundService.IsPlaying() then
		local alive = 0
		for _, other in ipairs(Players:GetPlayers()) do
			if Service.IsAlive(other) then
				alive += 1
			end
		end

		if alive == 0 then
			Service._roundService.Transition(GameConstants.RoundState.RoundEnding)
		end
	end
end

--- Conecta el ciclo de vida del personaje de un jugador.
--- @param player Player
local function bindCharacter(player: Player)
	local function onCharacter(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not humanoid then
			Logger.Error(("%s: el personaje no tiene Humanoid"):format(player.Name))
			return
		end

		Service.SetPlayerState(player, PlayerState.Alive)

		humanoid.Died:Connect(function()
			Service.OnPlayerDied(player)
		end)
	end

	-- CharacterAdded puede haberse fired antes de que nos conectemos.
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end

	player.CharacterAdded:Connect(onCharacter)
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

--- Inicializacion del servicio. Idempotente.
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

--- Arranca el servicio y engancha el ciclo de vida de jugadores.
--- @return boolean success
function Service.Start(): boolean
	if not Service.IsInitialized then
		Logger.Error("PlayerService: Start sin Init")
		return false
	end

	-- Conexiones registradas en el Maid del servicio: se limpian solas.
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

	-- Limite de jugadores: se avisa, no se bloquea. El matchmaking
	-- de la FASE 20 sera quien decida a quien acepta.
	if connected > Players.MaxPlayers then
		Logger.Warn(("hay mas jugadores que el maximo permitido (%d)"):format(Players.MaxPlayers))
	end

	return true
end

--- Limpieza del servicio.
--- @return boolean success
function Service.Destroy(): boolean
	Service._sessions = {}
	MaidRef = nil
	Service._roundService = nil
	Service._explosionService = nil
	Service.IsInitialized = false
	return true
end

return Service
