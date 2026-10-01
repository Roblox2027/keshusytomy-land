--!strict
--[[
	RoundService
	Maquina de estados de ronda y temporizadores (FASE 1).

	En esta fase se establece el ESQUELETO correcto:
	- Diagrama de transiciones explicito (nada de estados libres).
	- Los estados son legibles y visibles en el output.
	- Las transiciones invalidas se rechazan y se registran.

	La logica de ronda (jugadores, equipos, victoria, muerte) llega en
	la FASE 7. Aqui no se simula nada: `StartRound` solo mueve el estado
	y el servicio queda a la espera de las siguientes fases.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONFIG = SHARED:WaitForChild("Config")
local CONSTANTS = SHARED:WaitForChild("Constants")
local UTILS = SHARED:WaitForChild("Utils")

local GameConfig = require(CONFIG:WaitForChild("GameConfig"))
local GameConstants = require(CONSTANTS:WaitForChild("GameConstants"))
local StateMachine = require(SHARED:WaitForChild("Libraries"):WaitForChild("StateMachine"))
local Logger = require(UTILS:WaitForChild("Logger"))

local RoundState = GameConstants.RoundState

local Service = {}

Service.IsInitialized = false

local State = nil

-- Diagrama de la ronda. Las transiciones no declaradas se rechazan.
local TRANSITIONS: { [string]: { string } } = {
	[RoundState.Waiting] = { RoundState.Countdown },
	[RoundState.Countdown] = { RoundState.RoundStarting, RoundState.Waiting },
	[RoundState.RoundStarting] = { RoundState.Playing },
	[RoundState.Playing] = { RoundState.SuddenDeath, RoundState.RoundEnding },
	[RoundState.SuddenDeath] = { RoundState.RoundEnding },
	[RoundState.RoundEnding] = { RoundState.Rewards },
	[RoundState.Rewards] = { RoundState.ReturningToLobby, RoundState.Waiting },
	[RoundState.ReturningToLobby] = { RoundState.Waiting },
}

--- Estado actual de la ronda.
--- @return string
function Service.GetState(): string
	if not State then
		return RoundState.Waiting
	end
	return State:Get()
end

--- Indica si la ronda esta en curso.
--- @return boolean
function Service.IsPlaying(): boolean
	return Service.GetState() == RoundState.Playing
		or Service.GetState() == RoundState.SuddenDeath
end

--- Indica si se acepta nueva participacion.
--- @return boolean
function Service.IsAcceptingPlayers(): boolean
	return Service.GetState() == RoundState.Waiting
		or Service.GetState() == RoundState.Countdown
end

--- Intenta una transicion. Devuelve false si no esta permitida.
--- @param target string
--- @return boolean success
function Service.Transition(target: string): boolean
	if not State then
		return false
	end

	local previous = State:Get()

	if not State:Transition(target) then
		Logger.Warn(("transicion de ronda invalida: %s -> %s"):format(previous, target))
		return false
	end

	Logger.Debug(("ronda: %s -> %s"):format(previous, target))
	return true
end

--- Tiempo restante del estado actual, en segundos.
--- En esta fase no hay temporizadores por estado (FASE 7).
--- @return number
function Service.GetTimeRemaining(): number
	return 0
end

--- Duracion configurada de cada estado. La consulta centraliza el
--- balance para que la FASE 7 no repita numeros magicos.
--- @param state string
--- @return number seconds
function Service.GetDuration(state: string): number
	if state == RoundState.Countdown then
		return GameConfig.CountdownDuration
	end
	if state == RoundState.Playing then
		return GameConfig.RoundDuration
	end
	if state == RoundState.SuddenDeath then
		return GameConfig.SuddenDeathTime
	end
	return 0
end

--- Inicializacion del servicio. Idempotente.
--- @param maid any?
--- @return boolean success
function Service.Init(maid: any?): boolean
	if Service.IsInitialized then
		return true
	end

	local ok, err = pcall(function()
		State = StateMachine.new({
			initial = RoundState.Waiting,
			transitions = TRANSITIONS,
		})
	end)

	if not ok then
		Logger.Error("RoundService Init fallo: " .. tostring(err))
		return false
	end

	Service.IsInitialized = true
	return true
end

--- Comienza a servir consultas de ronda.
--- @return boolean success
function Service.Start(): boolean
	if not Service.IsInitialized then
		Logger.Error("RoundService: Start sin Init")
		return false
	end

	Logger.Info(("RoundService listo. Estado inicial: %s"):format(Service.GetState()))
	return true
end

--- Limpieza del servicio: detiene la maquina de estados.
--- @return boolean success
function Service.Destroy(): boolean
	if State then
		State:Stop()
		State = nil
	end

	Service.IsInitialized = false
	return true
end

return Service
