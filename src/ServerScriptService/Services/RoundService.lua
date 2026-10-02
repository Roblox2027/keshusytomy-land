--!strict
--[[
	RoundService
	Maquina de estados de ronda y temporizadores (FASE 1).

	En esta fase se establece el ESQUELETO correcto:
	- Diagrama de transiciones explicito (nada de estados libres).
	- Los estados son legibles y visibles en el output.
	- Las transiciones invalidas se rechazan y se registran.

	La logica de ronda (equipos, victoria, muerte) llega en las fases
	posteriores. Aqui el CICLO de estados ya corre de verdad: `Start`
	lanza una corrutina que avanza con temporizadores y avisa a los
	otros servicios en cada cambio.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

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

-- Numero de ronda, para registro y resultados.
Service._roundNumber = 0
-- Corrutina del ciclo de ronda. Se cancela en Destroy.
Service._loopThread = nil
-- Momento en que termina el estado actual (os.clock).
Service._stateEndsAt = nil
Service._currentDuration = 0
-- Callbacks que otros servicios usan para reaccionar a los cambios.
Service._listeners = {}

-- Maquina de estados de la ronda. Se expone en el servicio para que
-- las consultas de estado no dependan de una variable local.
Service.State = nil

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
	if not Service.State then
		return RoundState.Waiting
	end
	return Service.State:Get()
end

--- Indica si la ronda esta en curso.
--- @return boolean
function Service.IsPlaying(): boolean
	local state = Service.GetState()
	return state == RoundState.Playing or state == RoundState.SuddenDeath
end

--- Jugadores conectados que siguen VIVOS en la ronda actual.
---
--- Se cuenta por el Humanoid, no por el estado de sesion: el estado
--- lo cambia PlayerService, y depender de el aqui crearia un ciclo
--- RoundService -> PlayerService -> RoundService. El Humanoid es la
--- fuente de verdad del motor y no depende de nuestro codigo.
---
--- @return number alive
function Service.GetAliveCount(): number
	local alive = 0

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character

		if character then
			local humanoid = character:FindFirstChildOfClass("Humanoid")

			if humanoid and humanoid.Health > 0 then
				alive += 1
			end
		end
	end

	return alive
end

--- Indica si queda al menos un jugador con vida en la ronda.
--- @return boolean
function Service.HasAlivePlayers(): boolean
	return Service.GetAliveCount() > 0
end

--- Indica si se acepta nueva participacion.
--- @return boolean
function Service.IsAcceptingPlayers(): boolean
	local state = Service.GetState()
	return state == RoundState.Waiting or state == RoundState.Countdown
end

--- Registra un callback que se ejecuta en cada cambio de estado.
--- Lo usan MatchService, BombService y la UI para reaccionar sin que
--- RoundService tenga que conocerlos (evita dependencias circulares).
--- @param listener (from: string, to: string) -> ()
--- @return () -> () unsubscribe
function Service.OnStateChanged(listener: (string, string) -> ()): () -> ()
	table.insert(Service._listeners, listener)

	return function()
		for index = #Service._listeners, 1, -1 do
			if Service._listeners[index] == listener then
				table.remove(Service._listeners, index)
				return
			end
		end
	end
end

--- Numero de listeners registrados en los cambios de estado.
---
--- Lo usa `MatchService` para PROBAR que su suscripcion quedo
--- registrada de verdad: que la llamada no lance error no significa que
--- el listener se vaya a invocar. Es una lectura pura, no altera el
--- ciclo de ronda.
--- @return number count
function Service.GetListenerCount(): number
	return #Service._listeners
end

--- Numero de ronda en curso (0 antes de la primera).
--- @return number
function Service.GetRoundNumber(): number
	return Service._roundNumber
end

--- Intenta una transicion. Devuelve false si no esta permitida.
--- @param target string
--- @return boolean success
function Service.Transition(target: string): boolean
	if not Service.State then
		return false
	end

	local previous = Service.State:Get()

	if not Service.State:Transition(target) then
		Logger.Warn(("transicion de ronda invalida: %s -> %s"):format(previous, target))
		return false
	end

	Service._currentDuration = Service.GetDuration(target)
	Service._stateEndsAt = os.clock() + Service._currentDuration

	Logger.Info(("ronda: %s -> %s (%ds)"):format(previous, target, Service._currentDuration))

	-- Los callbacks no pueden tumbar el ciclo: un fallo aqui se registra
	-- y el ciclo continua.
	for _, listener in ipairs(Service._listeners) do
		local ok, err = pcall(listener, previous, target)
		if not ok then
			Logger.Error(("listener de ronda fallo en %s -> %s: %s"):format(previous, target, tostring(err)))
		end
	end

	return true
end

--- Tiempo restante del estado actual, en segundos.
--- @return number
function Service.GetTimeRemaining(): number
	if not Service._stateEndsAt then
		return 0
	end

	return math.max(0, Service._stateEndsAt - os.clock())
end

--- Duracion configurada de cada estado. La consulta centraliza el
--- balance para que nadie mas repita numeros magicos.
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
	-- Estados cortos de transicion: no tienen valor de balance propio.
	if state == RoundState.RoundStarting or state == RoundState.RoundEnding then
		return 3
	end
	if state == RoundState.Rewards or state == RoundState.ReturningToLobby then
		return 4
	end
	-- `Waiting` espera a que haya jugadores: se comprueba cada segundo
	-- en el ciclo, asi que 1 es un valor de sondeo, no un balance.
	return 1
end

--- Sincroniza el estado de ronda en los atributos de cada jugador.
---
--- El HUD (UIController) lee unicamente estos atributos: es la unica
--- via por la que el cliente se entera del estado de la ronda, y solo
--- el servidor puede escribirlos.
local function publishRoundState(state: string)
	for _, player in ipairs(Players:GetPlayers()) do
		player:SetAttribute("RoundState", state)
		player:SetAttribute("RoundTimeRemaining", math.floor(Service.GetTimeRemaining()))
		player:SetAttribute("RoundNumber", Service.GetRoundNumber())
		-- `AliveCount` se publica para que el HUD muestre el marcador
		-- sin calcularlo en el cliente (el cliente no es autoridad).
		player:SetAttribute("AliveCount", Service.GetAliveCount())
	end
end

--- Recorre a los jugadores publicando el tiempo restante.
---
--- El atributo se actualiza a baja frecuencia (1 Hz) porque el HUD solo
--- muestra segundos: replicarlo cada frame seria trafico inutil.
local function startTimeBroadcaster()
	while Service.IsInitialized do
		publishRoundState(Service.GetState())
		task.wait(1)
	end
end

--- Inicializacion del servicio. Idempotente.
--- @param maid any?
--- @return boolean success
function Service.Init(maid: any?): boolean
	if Service.IsInitialized then
		return true
	end

	local ok, err = pcall(function()
		Service.State = StateMachine.new({
			initial = RoundState.Waiting,
			transitions = TRANSITIONS,
		})
	end)

	if not ok then
		Logger.Error("RoundService Init fallo: " .. tostring(err))
		return false
	end

	Service._roundNumber = 0
	Service._currentDuration = 0
	Service._stateEndsAt = nil
	Service.IsInitialized = true

	return true
end

--- Jugadores conectados, respetando el minimo configurado.
--- @return boolean enough
local function hasEnoughPlayers(): boolean
	local connected = #Players:GetPlayers()
	return connected >= GameConfig.MinPlayersToStart
end

--- Decide el siguiente estado a partir del actual.
---
--- El diagrama de transiciones ya prohibe caminos imposibles; aqui solo
--- se decide QUE estado conviene, no si es legal (eso lo valida la
--- maquina de estados).
--- @param current string
--- @return string? next
local function decideNextState(current: string): string?
	if current == RoundState.Waiting then
		-- No se arranca la ronda hasta que haya jugadores suficientes.
		if not hasEnoughPlayers() then
			return nil
		end
		return RoundState.Countdown
	end

	if current == RoundState.Countdown then
		-- Si todos se fueron durante la cuenta atras, se cancela.
		if not hasEnoughPlayers() then
			return RoundState.Waiting
		end
		return RoundState.RoundStarting
	end

	if current == RoundState.Playing then
		-- Si solo queda un jugador (o nadie), la ronda se decide ya: la
		-- muerte subita no aportaria nada con un unico sobreviviente.
		if Service.GetAliveCount() <= 1 then
			return RoundState.RoundEnding
		end

		-- MUERTE SUBITA (FASE 7): se entra cuando queda poco tiempo. Antes
		-- este estado existia en el diagrama pero NUNCA se alcanzaba,
		-- asi que era decorativo: el multiplicador de dano nunca se
		-- aplicaba. Ahora es alcanzable y consequences reales.
		if Service.GetTimeRemaining() <= GameConfig.SuddenDeathTime then
			return RoundState.SuddenDeath
		end

		return RoundState.RoundEnding
	end

	if current == RoundState.RoundStarting then
		return RoundState.Playing
	end

	if current == RoundState.RoundEnding then
		return RoundState.Rewards
	end

	if current == RoundState.Rewards then
		return RoundState.ReturningToLobby
	end

	if current == RoundState.ReturningToLobby then
		return RoundState.Waiting
	end

	return nil
end

--- Corrutina que hace avanzar la ronda.
---
--- Es la UNICA fuente de tiempo de la ronda. No usa `wait` en bucle
--- sobre el estado: duerme lo que falta del estado actual, asi que un
--- estado largo no acumula retraso ni se desincroniza.
local function runRoundLoop()
	Service._currentDuration = Service.GetDuration(RoundState.Waiting)
	Service._stateEndsAt = os.clock() + Service._currentDuration

	while true do
		local remaining = Service.GetTimeRemaining()
		if remaining > 0 then
			task.wait(remaining)
		end

		local current = Service.GetState()
		local nextState = decideNextState(current)

		if not nextState then
			-- `Waiting` sin jugadores suficientes: se sigue esperando.
			Service._stateEndsAt = os.clock() + 1
			continue
		end

		if nextState == RoundState.RoundStarting then
			Service._roundNumber += 1
			Logger.Info(("--- ronda %d empieza ---"):format(Service._roundNumber))
		end

		if not Service.Transition(nextState) then
			-- Una transicion rechazada dejaria el ciclo en un estado
			-- imposible. Se registra y se vuelve a sondear.
			Logger.Error(("el ciclo no pudo pasar de %s a %s"):format(current, nextState))
			Service._stateEndsAt = os.clock() + 1
		end
	end
end

--- Arranca el ciclo de ronda.
--- @return boolean success
function Service.Start(): boolean
	if not Service.IsInitialized then
		Logger.Error("RoundService: Start sin Init")
		return false
	end

	if Service._loopThread then
		return true
	end

	Service._loopThread = task.spawn(runRoundLoop)
	-- Difusion del estado a los clientes. Va en un hilo aparte para que
	-- el temporizador siga vivo aunque el ciclo se detenga.
	task.spawn(startTimeBroadcaster)

	Logger.Info(("RoundService listo. Estado inicial: %s"):format(Service.GetState()))
	return true
end

--- Limpieza del servicio: detiene el ciclo y la maquina de estados.
--- @return boolean success
function Service.Destroy(): boolean
	if Service._loopThread then
		pcall(task.cancel, Service._loopThread)
		Service._loopThread = nil
	end

	if Service.State then
		Service.State:Stop()
		Service.State = nil
	end

	Service._listeners = {}
	Service._stateEndsAt = nil
	Service._currentDuration = 0
	Service.IsInitialized = false

	return true
end

return Service
