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

--- Indica si la ronda esta EN CURSO O A PUNTO DE EMPEZAR.
---
--- BUG CORREGIDO (medido en PLAY): `IsPlaying` solo es cierta en `Playing` y
--- `SuddenDeath`, y `PlayerService` la usaba para decidir a donde va un
--- personaje que acaba de reaparecer. El teletransporte a la arena ocurre en
--- `RoundStarting`, que NO es `Playing`: durante esos 3 s, si el personaje
--- reaparecia, `bindCharacter` lo mandaba al LOBBY, deshaciendo el traslado a
--- la arena. Medido en el log, en CADA ronda:
---
---   ronda: Countdown -> RoundStarting (3s)
---   DEBUG: SiSoyPapito movido a Arena
---   DEBUG: SiSoyPapito movido a Lobby<-- aqui
---   ronda: RoundStarting -> Playing (180s)
---
--- El sintoma era un jugador que el log daba por movido a la arena pero que en
--- realidad se quedaba en el lobby, con los monstruos a 500 studs: no podia
--- jugar.
---
--- La diferencia con `IsPlaying` es INTENCIONAL y no un matiz: "se puede
--- colocar una bomba" (juego) y "el jugador pertenece a la arena" (pertenencia)
--- no son la misma pregunta.
--- @return boolean
function Service.IsRoundActive(): boolean
	local state = Service.GetState()
	return state == RoundState.RoundStarting
		or state == RoundState.Playing
		or state == RoundState.SuddenDeath
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
	-- El reloj del estado se reinicia aqui. Sin esto, un estado que se
	-- visita arrastra el tiempo del anterior y el vigilante no puede
	-- distinguir "lleva 140 s en RoundEnding" de "acabo de entrar".
	Service._stateStartedAt = os.clock()
	-- El margen de atasco se reinicia con cada estado: cuenta lo que lleva
	-- VENCIDO el nuevo, no lo que lleva existiendo.
	Service._expiredFor = 0
	Service._lastReason = ("transicion: %s -> %s"):format(previous, target)
	Service._diagnostics.LastTransitionAt = Service._stateStartedAt
	Service._diagnostics.LastReason = Service._lastReason

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

--- Pide terminar la ronda AHORA.
---
--- Esta es la via por la que el mundo exterior comunica "esta ronda ya
--- termino" sin tocar la maquina de estados a sus espaldas.
---
--- POR QUE EXISTE Y POR QUE NO BASTABA CON LLAMAR A `Transition`
--- ---------------------------------------------------------
--- `PlayerService` la usaba al morir el ultimo vivo, y ESO era el P0 de la
--- FASE 0. `Transition` se puede llamar desde cualquier hilo, y el bucle
--- duerme el plazo del estado en el que entro. Al cambiar el estado desde
--- fuera, el bucle seguia dormido con el plazo ANTERIOR: el estado era ya
--- `RoundEnding` con `remaining = 0` y el heartbeat congelado, sin un solo
--- error en el Output.
---
--- Aqui la peticion NO cambia el estado: se guarda, y el bucle la ejecuta en
--- su proxima rebanada (`GameConfig.RoundTickInterval`). Un solo escritor
--- del estado elimina por construccion la carrera entre el ciclo y quien
--- lo llama desde fuera.
--- @param reason string? por que se pide (queda en el log)
--- @return boolean accepted
function Service.RequestEnd(reason: string?): boolean
	local state = Service.GetState()

	if not Service.IsPlaying() then
		-- No se esta jugando: la peticion no aplica. Se avisa para que una
		-- llamada fuera de sitio sea visible y no un silencio.
		Logger.Debug(("RequestEnd ignorado en %s: %s"):format(state, tostring(reason)))
		return false
	end

	Service._endRequested = true
	Service._endReason = reason or "sin razon"

	Logger.Info(("se pide terminar la ronda desde %s (%s); el ciclo lo hara en "
		.. "menos de %.2fs"):format(state, Service._endReason, GameConfig.RoundTickInterval))

	return true
end

--- Indica si hay una peticion de fin pendiente.
--- @return boolean
function Service.IsEndRequested(): boolean
	return Service._endRequested == true
end

--- Tiempo restante del estado actual, en segundos.
--- @return number
function Service.GetTimeRemaining(): number
	if not Service._stateEndsAt then
		return 0
	end

	return math.max(0, Service._stateEndsAt - os.clock())
end

--- Segundos que lleva el estado actual activo.
---
--- Es distinto de `GetTimeRemaining` a proposito: `GetTimeRemaining` se
--- recorta a 0 cuando el plazo vence, asi que un estado VENCIDO y un bucle
--- MUERTO se ven IGUALES desde fuera. Eso fue exactamente el sintoma del
--- P0: `remaining = 0` no distinguia nada. Con el tiempo real transcurrido,
--- un estado que lleva 140 s vencido sobre una duracion de 3 s canta a la
--- vista.
--- @return number seconds
function Service.GetTimeSinceStateStart(): number
	if not Service._stateStartedAt then
		return 0
	end

	return math.max(0, os.clock() - Service._stateStartedAt)
end

--- Segundos que un estado puede quedarse vencido antes de considerarse atasco.
---
--- Margen deliberadamente amplio: el vigilante NO debe disparar en el
--- funcionamiento normal, solo en el patologico. Un margen pequeno
--- convertiria la red de seguridad en ruido, y una puerta que suena sola es
--- una puerta que nadie escucha.
--- @return number seconds
function Service.GetStallTimeout(): number
	return math.max(5, GameConfig.RoundTickInterval * 20)
end

--- Instantanea del ciclo, para diagnostico externo (`tools/round-probe.js`).
---
--- Expone lo necesario para responder de una vez a lo que antes exigia
--- instrumentar el codigo: ?esta vivo el bucle?, ?espera bien o espera una
--- condicion imposible?, ?hubo algun atasco?, ?hay jugadores?, ?cuantos
--- sobreviven?
--- @return { [string]: any }
function Service.GetDiagnostics(): { [string]: any }
	return {
		State = Service.GetState(),
		Round = Service._roundNumber,
		Heartbeat = Service._loopHeartbeat,
		Iteration = Service._iteration,
		Remaining = Service.GetTimeRemaining(),
		Elapsed = Service.GetTimeSinceStateStart(),
		Duration = Service.GetDuration(Service.GetState()),
		RawDelta = Service._stateEndsAt and (Service._stateEndsAt - os.clock()) or 0,
		StallCount = Service._stallCount,
		LastReason = Service._lastReason,
		AliveCount = Service.GetAliveCount(),
		PlayerCount = #Players:GetPlayers(),
		ListenerCount = #Service._listeners,
		IsInitialized = Service.IsInitialized,
		HasThread = Service._loopThread ~= nil,
	}
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
	-- Estados cortos de transicion: su duracion es balance declarado en
	-- `GameConfig`, no un numero magico aqui. Antes eran 3/3/4/4 escritos en
	-- el `if`, lo que hacia imposible ejecutar un ciclo completo en un
	-- tiempo razonable y por tanto imposible PROBAR que la ronda se repite.
	if state == RoundState.RoundStarting then
		return GameConfig.RoundStartingDuration
	end
	if state == RoundState.RoundEnding then
		return GameConfig.RoundEndingDuration
	end
	if state == RoundState.Rewards then
		return GameConfig.RewardsDuration
	end
	if state == RoundState.ReturningToLobby then
		return GameConfig.ReturningToLobbyDuration
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
	local alive = Service.GetAliveCount()

	-- Los contadores de diagnostico se refrescan aqui, a 1 Hz, y no en el
	-- bucle: no se necesita mas precision para observar, y asi el log de
	-- diagnostico no compite con el del ciclo.
	Service._diagnostics.AliveCount = alive
	Service._diagnostics.PlayerCount = #Players:GetPlayers()
	Service._diagnostics.LastReason = Service._lastReason

	for _, player in ipairs(Players:GetPlayers()) do
		player:SetAttribute("RoundState", state)
		player:SetAttribute("RoundTimeRemaining", math.floor(Service.GetTimeRemaining()))
		player:SetAttribute("RoundNumber", Service.GetRoundNumber())
		-- `AliveCount` se publica para que el HUD muestre el marcador
		-- sin calcularlo en el cliente (el cliente no es autoridad).
		player:SetAttribute("AliveCount", alive)
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
	Service._stateStartedAt = os.clock()
	Service._iteration = 0
	Service._stallCount = 0
	Service._lastReason = "inicializado"
	Service._endRequested = false
	Service._endReason = nil
	Service._expiredFor = 0
	Service._diagnostics = {
		AliveCount = 0,
		PlayerCount = 0,
		LastReason = "inicializado",
		LastTransitionAt = 0,
	}
	Service.IsInitialized = true

	return true
end

--- Jugadores que estan DENTRO de una arena, respetando el minimo configurado.
---
--- BUG CORREGIDO (medido en PLAY, no en source): esto contaba
--- `#Players:GetPlayers()`, es decir, TODO el mundo. Con
--- `MinPlayersToStart = 1` bastaba con que UN jugador entrase al servidor para
--- que la ronda arrancase sola, Moving -> Countdown -> RoundStarting, y el
--- jugador quedaba en `Playing` durante 180 s.
---
--- El efecto medido en el juego era este: `PortalService.CanTravel` rechaza
--- mientras hay ronda en curso ("hay una ronda en curso"), asi que el lobby
--- se quedaba SIN SALIDAS durante casi tres minutos. El jugador veia los
--- cinco portales, se acercaba, pulsaba E y no pasaba nada. El lobby entero
--- era un pasillo.
---
--- El error de fondo es de SEMANTICA, no de aritmetica: una ronda de combate
--- pertenece a los jugadores que estan peleando en una arena. Un jugador que
--- esta de pie en el lobby mirando los portales no participa en nada, y contar
--- su presencia hacia que el ciclo de ronda empezara sin que nadie hubiera
--- pedido entrar.
---
--- Se cuenta el atributo `World`, que escribe el SERVIDOR en
--- `MatchService.MovePlayer`. Es el unico punto por el que pasa cualquier
--- traslado (portal, entrada a la arena, vuelta al lobby), asi que el atributo
--- describe la zona real del jugador. No se mira la POSICION: el jugador puede
--- caerse o ser empujado y eso no debe contar como "entro en la ronda".
---
--- Se exige ademas un personaje con vida, para no contar a un jugador que esta
--- en la arena pero yamurio y esta esperando el reaparicion.
---
--- @return boolean enough
local function hasEnoughPlayers(): boolean
	local inArena = 0

	for _, player in ipairs(Players:GetPlayers()) do
		local world = player:GetAttribute("World")

		-- "Lobby" y `nil` (aun sin destino asignado) NO son arena.
		if type(world) == "string" and world ~= "Lobby" then
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")

			if humanoid and humanoid.Health > 0 then
				inArena += 1
			end
		end
	end

	return inArena >= GameConfig.MinPlayersToStart
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

	if current == RoundState.Playing or current == RoundState.SuddenDeath then
		-- Una peticion de fin desde el exterior manda sobre el reloj: la
		-- ronda se decide YA. Es el camino que usa `PlayerService` cuando
		-- muere el ultimo vivo.
		if Service.IsEndRequested() then
			return RoundState.RoundEnding
		end

		-- Si solo queda un jugador (o nadie), la ronda se decide ya: la
		-- muerte subita no aportaria nada con un unico sobreviviente.
		if Service.GetAliveCount() <= 1 then
			return RoundState.RoundEnding
		end

		-- MUERTE SUBITA (FASE 7): se entra cuando queda poco tiempo. Antes
		-- este estado existia en el diagrama pero NUNCA se alcanzaba,
		-- asi que era decorativo: el multiplicador de dano nunca se
		-- aplicaba. Ahora es alcanzable y consequences reales.
		if current == RoundState.Playing
			and Service.GetTimeRemaining() <= GameConfig.SuddenDeathTime then
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
--- Es la UNICA fuente de tiempo de la ronda.
---
--- POR QUE SONDEA EN REBANADAS Y NO DUERME EL PLAZO ENTERO
--- ---------------------------------------------------------
--- La version anterior hacia `task.wait(remaining)` con el `remaining` del
--- estado en el que entraba. Eso esta bien SI el estado solo lo cambia este
--- bucle, pero NO es cierto: `PlayerService` tambien cambia el estado desde
--- otro hilo (`Transition(RoundEnding)` al morir el ultimo vivo).
---
--- MEDIDO EN PLAY (no deducido), con `tools/round-probe.js`:
---   state = RoundEnding, remaining = 0, heartbeat = 46 congelado,
---   `_stateEndsAt - os.clock()` = -140 (el plazo vencio hace 140 s),
---   `coroutine.status(loopThread)` = "suspended",
---   historial = 8 ciclos COMPLETOS, y la ronda 9 nunca avanza.
---
--- El hilo estaba vivo y sano, dormido dentro de un `task.wait` calculado
--- para el `Playing` de 180 s. `task.wait` NO era la causa raiz: es la
--- consecuencia de dormir un plazo que otro hilo puede invalidar en
--- cualquier momento. Con el mismo fallo, una ronda terminada por muerte
--- del ultimo vivo tardaba hasta 180 s en llegar a `Rewards`.
---
--- El sondeo en rebanadas de `GameConfig.RoundTickInterval` hace que una
--- transicion externa se vea en menos de 0.25 s, y mantiene la garantia de
--- que un estado largo no acumula retraso: solo se recalcula el plazo.
local function runRoundLoop()
	-- CONTADOR DE LATIDO.
	--
	-- POR QUE EXISTE: sin el, "la ronda esta atascada" y "el bucle esta
	-- vivo pero bloqueado" son indistinguibles desde fuera. Medido en PLAY:
	-- la ronda se quedaba en `RoundEnding` indefinidamente y no habia forma
	-- de saber si el hilo habia muerto o si simplemente no avanzaba.
	-- Con este contador, un latido que NO cambia durante varios segundos
	-- demuestra que el hilo esta bloqueado, no que la logica este mal.
	Service._loopHeartbeat = 0

-- Iteraciones del bucle: avanza aunque no haya transicion. Junto con el
-- heartbeat separa "vivo pero quieto" de "vivo y avanzando".
Service._iteration = 0

-- Atascos REALES detectados por el vigilante. En un ciclo estable vale
-- siempre 0. Si sube, hay un estado que no pudo avanzar: se dice en el log.
Service._stallCount = 0

-- Ultima razon por la que el ciclo no transiciono. Sin esto, un atasco
-- aparece en el Output como un simple silencio.
Service._lastReason = "sin iniciar"

-- Peticion de fin de ronda pendiente. La pone el mundo exterior
-- (`RequestEnd`) y la CONSUME el bucle. Existe para que solo el bucle
-- escriba el estado de la maquina.
Service._endRequested = false
Service._endReason = nil

-- Momento (os.clock) en que entro el estado actual. Es lo que permite
-- saber si un estado lleva mas tiempo del que deberia.
Service._stateStartedAt = os.clock()

-- Contadores observables del ciclo, para diagnostico externo.
Service._diagnostics = {
	AliveCount = 0,
	PlayerCount = 0,
	LastReason = "sin iniciar",
	LastTransitionAt = 0,
}

	Service._currentDuration = Service.GetDuration(RoundState.Waiting)
	Service._stateEndsAt = os.clock() + Service._currentDuration

	while true do
		-- TODO el cuerpo va dentro de un `pcall`.
		--
		-- POR QUE: este bucle es la UNICA fuente de tiempo de la ronda y
		-- una excepcion no controlada la mata en silencio. Medido en PLAY:
		-- la ronda se quedaba en `ReturningToLobby` para siempre, sin un
		-- solo error en el Output, porque el error de una corrutina espiral
		-- abortada no se propaga a ningun `pcall` de quien la lanzo. El
		-- sintoma era "el juego se congela en un estado de ronda" sin
		-- ninguna pista de la causa.
		--
		-- Con el `pcall`, un fallo puntual se registra con su mensaje y el
		-- ciclo vuelve a sondear en vez de morir. Un estado atascado es un
		-- fallo MUCHO mas dificil de diagnosticar que un error visible.
		local ok, err = pcall(function()
		Service._loopHeartbeat += 1

			-- PLENO: cuenta de ATASCOS detectados por el vigilante. Es el
			-- numero que responde a "?el ciclo se atasca alguna vez?", no a
			-- "?el ciclo avanza?".
			Service._iteration += 1

			-- Se lee el estado ANTES de dormir y se vuelve a leer DESPUES.
			-- Si ha cambiado mientras dormiamos, el plazo que durmio el
			-- bucle era de otro estado y ya no vale: no se transiciona con
			-- datos rancios, se recalcula en la siguiente iteracion.
			local current = Service.GetState()
			local remaining = Service.GetTimeRemaining()

			if remaining > 0 then
				-- Rebanada: nunca se duerme mas que una rebanada, para que
				-- el plazo vigente siempre sea el del estado vigente.
				task.wait(math.min(remaining, GameConfig.RoundTickInterval))
			end

			-- ?Cambio el estado mientras dormiamos? Entonces lo que dormimos
			-- no era su plazo: se vuelve a medir sin transicionar.
			if Service.GetState() ~= current then
				Service._lastReason = ("estado cambiado durante el sueno: %s"):format(current)
				return
			end

			-- P0 REAL (medido en PLAY, no deducido): el bucle consultaba
			-- `decideNextState` en CADA rebanada, sin mirar si el plazo del
			-- estado habia vencido. Consecuencia medida: la ronda 1369 paso
			-- del Waiting al Rewards en menos de 15 s con `RoundDuration = 180`,
			-- y el historial mostraba 1400+ rondas completadas en minutos.
			--
			-- Por que rompia tanto: `decideNextState` incluye la regla "si
			-- solo queda un vivo, la ronda se decide ya". Con un solo jugador
			-- conectado esa condicion es CIERTA desde el primer instante de
			-- `Playing`, asi que la ronda terminaba al instante y nunca habia
			-- tiempo de jugar: ni bombas, ni monstruos, ni destruccion.
			--
			-- La regla correcta es la de cualquier juego de ronda: el estado
			-- AVANZA cuando su plazo vence, o antes si alguien pide terminar
			-- explicitamente (`RequestEnd`, que es la via de `PlayerService`
			-- al morir el ultimo vivo).
			if remaining > 0 and not Service.IsEndRequested() then
				Service._lastReason = ("esperando el plazo de %s (%.1fs)"):format(
					current,
					remaining
				)
				return
			end

			-- VIGILANTE DE ATASCO.
			--
			-- Red de seguridad, no mecanismo normal. Si el plazo del estado
			-- vencio y aun asi no se pudo transicionar (porque
			-- `decideNextState` devolvio `nil` en un estado que no es
			-- `Waiting`, o porque una transicion fue rechazada), el estado
			-- se quedaria TERMINAL para siempre. Aqui se detecta y se
			-- fuerza la salida, con la razon registrada.
			--
			-- No se oculta el fallo: se cuenta en `_stallCount` y se dice en
			-- el log. Un ciclo estable da `_stallCount = 0` siempre.
			--
			-- BUG CORREGIDO (medido en PLAY): el vigilante comparaba el
			-- tiempo TOTAL desde el inicio del estado contra el margen. Con
			-- el bucle respetando los plazos, los 180 s reales de `Playing`
			-- llegaban al vigilante con `overdue = 180`, muy por encima del
			-- margen de 5 s, y se contabilizaban como "atasco" en CADA ronda
			-- normal: el log gritaba ERROR y `_stallCount` crecia sin que
			-- hubiera ningun fallo. Un vigilante que suena en el camino
			-- normal es un vigilante que nadie oye.
			--
			-- Lo que de verdad se mide es el GRACE: cuanto tiempo lleva el
			-- estado vencido SIN que el bucle haya logrado transicionar.
			-- `remaining` ya es 0 en cuanto el plazo vence, asi que el
			-- grace se lleva con un contador que se reinicia al entrar en
			-- cada estado y avanza solo mientras el plazo esta vencido.
			if remaining > 0 then
				Service._expiredFor = 0
			else
				Service._expiredFor = (Service._expiredFor or 0) + GameConfig.RoundTickInterval
			end

			if remaining <= 0 and Service._expiredFor > Service.GetStallTimeout() then
				Service._stallCount += 1
				Logger.Error(("el estado %s lleva %.1fs vencido sin avanzar; "
					.. "se fuerza la salida (atasco %d). Ultima razon: %s"):format(
					current,
					Service._expiredFor,
					Service._stallCount,
					tostring(Service._lastReason)
				))
				Service._stateEndsAt = os.clock()
				Service._lastReason = "vigilante: forzado por atasco"
			end

			local nextState = decideNextState(current)

			if not nextState then
				-- `Waiting` sin jugadores suficientes: se sigue esperando.
				-- NO es un atasco: es la espera normal por jugadores.
				Service._stateEndsAt = os.clock() + 1
				Service._lastReason = "esperando jugadores suficientes"
				return
			end

			if nextState == RoundState.RoundStarting then
				Service._roundNumber += 1
				-- La peticion de fin se CONSUME al empezar la ronda. Si no se
				-- limpiase aqui, la ronda 2 terminaria al instante porque
				-- heredaria la peticion de la ronda 1.
				Service._endRequested = false
				Service._endReason = nil
				Logger.Info(("--- ronda %d empieza ---"):format(Service._roundNumber))
			end

			if not Service.Transition(nextState) then
				-- Una transicion rechazada dejaria el ciclo en un estado
				-- imposible. Se registra y se vuelve a sondear.
				Logger.Error(("el ciclo no pudo pasar de %s a %s"):format(current, nextState))
				Service._lastReason = ("transicion rechazada: %s -> %s"):format(current, nextState)
				Service._stateEndsAt = os.clock() + 1
			end
		end)

		if not ok then
			-- Sin este registro, el fallo anterior era invisible.
			Logger.Error(("el ciclo de ronda fallo y se reintentara: %s"):format(tostring(err)))
			Service._lastReason = ("excepcion en el ciclo: %s"):format(tostring(err))
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
