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
local CONSTANTS = SHARED:WaitForChild("Constants")
local UTILS = SHARED:WaitForChild("Utils")

local GameConstants = require(CONSTANTS:WaitForChild("GameConstants"))
local Logger = require(UTILS:WaitForChild("Logger"))

local PlayerState = GameConstants.PlayerState

local Service = {}

Service.IsInitialized = false

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
	Service.IsInitialized = false
	return true
end

return Service
