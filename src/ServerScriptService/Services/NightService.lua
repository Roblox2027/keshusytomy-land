--!strict
--[[
	NightService
	El reloj de las 99 noches (FASES 8 y 9).

	QUE HACE Y QUE NO
	-----------------
	HACE: posee el hilo del ciclo, lleva el numero de noche, resuelve la fase a
	partir del reloj REAL del servidor y publica el estado para el HUD.

	NO HACE: ninguna aritmetica. Todo el calculo de fase, de reloj y de
	progresion vive en `NightRules` y `WorldAccessRules`, que son puros y estan
	piobados. Este servicio es el "reloj de pared" que consulta una regla.

	LA RAZON DE LA SEPARACION
	-------------------------
	Porque el reloj de pared es la parte que NO se puede probar en local: depende
	de `os.clock()` y de un hilo. Si el calculo estuviera aqui, "la noche 17
	empieza a las 22:00" habria que comprobarlo esperando diecisiete minutos. Al
	estar en `NightRules`, esa pregunta se responde con una tabla.

	ESTADO Y PERSISTENCIA
	---------------------
	La noche AVANZA sola y en memoria: cada servidor tiene su propio ciclo. La
	NOCHE ALCANZADA (la mas alta que ha visto este servidor) se publica para el
	HUD, pero la que se guarda en el perfil es otra cosa, y la decide
	`ProgressionService`. Este servicio no escribe en el perfil: si lo hiciera,
	"sobrevive a 5 noches" seria una mision que el propio servidor completaria.

	SEGURIDAD
	---------
	`SetNight` es la UNICA via para cambiar de noche y esta pensada para el
	administrador y para las pruebas. Acota el valor a 1..99, con lo que ni un
	`SetNight(99999)` ni un `SetNight(-1)` dejan el sistema sin dificultad o con
	una dificultad imposible.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONFIG = SHARED:WaitForChild("Config")
local UTILS = SHARED:WaitForChild("Utils")

local PerformanceConfig = require(CONFIG:WaitForChild("PerformanceConfig"))
local NightRules = require(SHARED:WaitForChild("Libraries"):WaitForChild("NightRules"))
local WorldAccessRules = require(SHARED:WaitForChild("Libraries"):WaitForChild("WorldAccessRules"))
local Logger = require(UTILS:WaitForChild("Logger"))

local Service = {}

Service.IsInitialized = false

-- Numero de noche actual.
Service._night = 1
-- Noche mas alta alcanzada en este servidor (lo que ve el HUD).
Service._maxNight = 1
-- Fase actual del ciclo.
Service._phase = NightRules.Phase.Day
-- Instante (`os.clock`) en el que empieza la fase actual.
Service._phaseStartedAt = 0
-- Fraccion de ciclo completada, 0..1.
Service._fraction = 0
-- Arranque del servicio, para el calculo de la fraccion.
Service._startedAt = 0

Service._thread = nil
Service._running = false

-- Frecuencia con la que se publica el estado al HUD.
--
-- 0.5 s son 2 Hz: suficiente para que el reloj no parezca congelado y
-- suficiente para no enviar cuatro atributos por cliente y por frame. El reloj
-- se mide en MINUTOS de mundo, asi que a 2 Hz avanza visible pero sin parpadeo.
local PUBLISH_INTERVAL = 0.5

-- ---------------------------------------------------------------------------
-- CONSULTA DE ESTADO
-- ---------------------------------------------------------------------------

--- Numero de noche actual.
--- @return number
function Service.GetNight(): number
	return Service._night
end

--- Noche mas alta alcanzada en este servidor.
--- @return number
function Service.GetMaxNight(): number
	return Service._maxNight
end

--- Fase actual (`Day`, `Sunset`, `Night`, `Dawn`).
--- @return string
function Service.GetPhase(): string
	return Service._phase
end

--- Es de noche ahora mismo (fase `Night`).
--- @return boolean
function Service.IsNight(): boolean
	return Service._phase == NightRules.Phase.Night
end

--- Esta en una TRANSICION (atardecer o amanecer).
---
--- Es lo que el HUD usa para avisar de que la noche viene o se va. Sin esto,
--- el jugador no tendria aviso y el cambio se leeria como un fallo.
--- @return boolean
function Service.IsTransition(): boolean
	return Service._phase == NightRules.Phase.Sunset or Service._phase == NightRules.Phase.Dawn
end

--- Fraccion completada del ciclo, 0..1.
--- @return number
function Service.GetFraction(): number
	return Service._fraction
end

--- Segundos que quedan hasta la siguiente fase.
--- @return number
function Service.GetTimeToNextPhase(): number
	local elapsed = os.clock() - Service._phaseStartedAt

	return math.max(0, NightRules.DurationFor(Service._phase, Service._night) - elapsed)
end

--- Estado completo, tal y como lo consume el HUD.
--- @return { Night: number, MaxNight: number, Phase: string, PhaseLabel: string, Clock: string, IsNight: boolean, Transition: boolean }
function Service.GetState(): {
	Night: number,
	MaxNight: number,
	Phase: string,
	PhaseLabel: string,
	Clock: string,
	IsNight: boolean,
	Transition: boolean,
}
	local state = NightRules.GetClockState(Service._night, Service._fraction)

	return {
		Night = state.Night,
		MaxNight = Service._maxNight,
		Phase = state.Phase,
		PhaseLabel = state.PhaseLabel,
		Clock = state.Clock,
		IsNight = state.IsNight,
		Transition = state.Transition,
	}
end

--- Fija la noche y reinicia la fase a `Day`.
---
--- Es la via por la que cambian las noches, tanto al avanzar el ciclo como al
--- forzarla desde un comando. No reinicia el HUD por su cuenta: el proximo
--- `Publish` lo hace, que es lo que evita que dos escrituras en el mismo frame.
--- @param night any
--- @return boolean changed
function Service.SetNight(night: any): boolean
	local nextNight = WorldAccessRules.ClampNight(night)
	local changed = nextNight ~= Service._night

	Service._night = nextNight

	if nextNight > Service._maxNight then
		Service._maxNight = nextNight
	end

	if changed then
		-- Al cambiar de noche se reinicia la fase. Sin esto, un cambio de noche
		-- a mitad de la fase `Night` dejaria al jugador con la presion de la
		-- noche nueva y el reloj de la anterior, que es una combinacion que no
		-- existe en ninguna parte de la linea de tiempo.
		Service._phase = NightRules.Phase.Day
		Service._phaseStartedAt = os.clock()

		Logger.Info(("NightService: noche %d"):format(nextNight))
	end

	return changed
end

--- Fuerza una fase concreta (pruebas y administracion).
--- @param phase string
--- @return boolean success
function Service.SetPhase(phase: string): boolean
	if not NightRules.DurationFor(phase, Service._night) > 0 then
		return false
	end

	Service._phase = phase
	Service._phaseStartedAt = os.clock()

	return true
end

--- Avanza el reloj: recalcula la fraccion y cambia de fase si toca.
---
--- Se llama desde el hilo del ciclo, NO desde un `Heartbeat`. El motivo es el
--- que declara `PerformanceConfig`: un hilo propio es mas barato y no obliga a
--- pagar el coste del reloj a todos los jugadores aunque no haya nada que
--- actualizar.
--- @return boolean phaseChanged
function Service.Tick(): boolean
	local cycle = math.max(1, NightRules.CycleDuration(Service._night))
	local elapsed = os.clock() - Service._startedAt

	Service._fraction = (elapsed / cycle) % 1

	local phase = NightRules.PhaseAt(Service._fraction)

	if phase == Service._phase then
		return false
	end

	Service._phase = phase
	Service._phaseStartedAt = os.clock()

	-- La noche NUMERICA solo sube al empezar la fase `Night`, no en cada
	-- transicion. Si subiera al empezar `Sunset`, el HUD mostraria "NOCHE 18"
	-- veinte segundos antes de que llegue la noche, y el jugador contaria con
	-- una noche que todavia no ha empezado.
	if phase == NightRules.Phase.Night then
		Service.SetNight(Service._night + 1)
	end

	Logger.Info(("NightService: fase %s (noche %d, %s)")
		:format(phase, Service._night, NightRules.LabelForPhase(phase)))

	return true
end

--- Publica el estado a los atributos de cada jugador.
---
--- Los atributos son el CONTRATO con `UIController`. Se escriben los que el HUD
--- lee y NADIE mas: un atributo por frame es un envio por cliente y por frame.
---
--- Se escribe solo si el valor CAMBIO. El reloj cambia cada medio segundo y
--- el numero de noche no cambia nunca, asi que escribirlo siempre seria enviar
--- datos identicos a todo el mundo sin ningun efecto.
--- @return number atributos escritos
function Service.Publish(): number
	local state = Service.GetState()
	local written = 0

	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("Night") ~= state.Night then
			player:SetAttribute("Night", state.Night)
			written += 1
		end

		if player:GetAttribute("NightPhase") ~= state.Phase then
			player:SetAttribute("NightPhase", state.Phase)
			player:SetAttribute("NightPhaseLabel", state.PhaseLabel)
			written += 1
		end

		if player:GetAttribute("NightClock") ~= state.Clock then
			player:SetAttribute("NightClock", state.Clock)
			player:SetAttribute("NightTransition", state.Transition)
			written += 1
		end
	end

	return written
end

-- ---------------------------------------------------------------------------
-- CICLO DE VIDA DEL SERVICIO
-- ---------------------------------------------------------------------------

--- Hilo del ciclo.
---
--- Hace DOS cosas por iteracion y las dos a un ritmo distinto, porque mezclar
--- los ritmos en un solo `task.wait` es lo que produce los errores de reloj:
---
---   - `Tick` (el cambio de fase) cada `PublishInterval`, que es lo bastante
---     fino para que el cambio de fase se vea inmediato;
---   - `Publish` (los atributos del HUD) cada `PUBLISH_INTERVAL`, que es mas
---     lento porque es una red de por medio.
---
--- Se separan porque un cambio de fase tiene que verse AL INSTANTE y un reloj
--- que avanza 6:41 -> 6:42 se ve bien a 2 Hz.
local function runCycle()
	while Service._running do
		Service.Tick()
		Service.Publish()
		task.wait(PerformanceConfig.MonitorInterval)
	end
end

--- Inicializacion. Idempotente.
--- @param maid any?
--- @return boolean success
function Service.Init(maid: any?): boolean
	if Service.IsInitialized then
		return true
	end

	Service._night = 1
	Service._maxNight = 1
	Service._phase = NightRules.Phase.Day
	Service._fraction = 0
	Service._startedAt = os.clock()
	Service._phaseStartedAt = Service._startedAt

	Service.IsInitialized = true
	return true
end

--- Arranca el reloj.
---
--- La noche se publica AL ARRANCAR y no en el primer tick: si el servidor
--- aceptara jugadores antes del primer `Publish`, el HUD apareceria con "NOCHE
--- --" durante medio segundo, que es exactamente el tipo de dato roto que el
--- jugador recuerda.
--- @return boolean success
function Service.Start(): boolean
	if not Service.IsInitialized then
		Logger.Error("NightService: Start sin Init")
		return false
	end

	if Service._running then
		return true
	end

	Service._running = true
	Service._startedAt = os.clock()
	Service._phaseStartedAt = Service._startedAt
	Service.Publish()

	Service._thread = task.spawn(runCycle)

	Logger.Info(("NightService: ciclo iniciado (noche %d, ciclo de %.0f s)")
		:format(Service._night, NightRules.CycleDuration(Service._night)))

	return true
end

--- Para el reloj. Idempotente.
--- @return boolean success
function Service.Destroy(): boolean
	Service._running = false

	if Service._thread then
		pcall(task.cancel, Service._thread)
		Service._thread = nil
	end

	Service.IsInitialized = false
	return true
end

return Service
