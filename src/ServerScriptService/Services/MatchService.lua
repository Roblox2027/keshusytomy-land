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

-- Destinos por nombre: "Lobby" / "Arena".
Service._destinations = {}

--- Busca los marcadores de traslado en el mapa.
--- @return number found
function Service.CollectDestinations(): number
	Service._destinations = {}

	local lobby = Workspace:FindFirstChild("Lobby")
	local lobbyCenter = lobby and lobby:FindFirstChild("LobbyCenter")
	if lobbyCenter and lobbyCenter:IsA("BasePart") then
		Service._destinations.Lobby = lobbyCenter :: BasePart
	end

	local worlds = Workspace:FindFirstChild("Worlds")
	local forest = worlds and worlds:FindFirstChild("Forest")
	local arenaCenter = forest and forest:FindFirstChild("ArenaCenter")
	if arenaCenter and arenaCenter:IsA("BasePart") then
		Service._destinations.Arena = arenaCenter :: BasePart
	end

	local found = 0
	for _ in pairs(Service._destinations) do
		found += 1
	end

	return found
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
	if key == "Arena" and Service._combatService then
		Service._combatService.GrantInvulnerability(player, GameConfig.SpawnProtectionTime)
	end

	if Service._playerService then
		Service._playerService.SetPlayerState(player, GameConstants.PlayerState.Alive)
	end

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

	elseif to == RoundState.RoundEnding then
		-- Las bombas que quedaran explotando dañarian a los jugadores
		-- ya devueltos al lobby.
		if Service._bombService then
			Service._bombService.ClearBombs()
		end

	elseif to == RoundState.Rewards then
		Service.GrantRoundRewards()

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
	combatService: any?
)
	Service._roundService = roundService
	Service._playerService = playerService
	Service._bombService = bombService
	Service._destructionService = destructionService
	Service._combatService = combatService
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
		Logger.Error("MatchService: RoundService no inyectado; no habra traslados.")
		return false
	end

	-- Suscribirse ANTES de que la ronda avance es imprescindible: si se
	-- hiciera despues, la primera ronda no moveria a nadie.
	Service._roundService.OnStateChanged(Service.OnRoundStateChanged)

	Logger.Info("MatchService listo.")
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
