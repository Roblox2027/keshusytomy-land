--!strict
--[[
	NightRules
	EL CICLO DIA / NOCHE y el reloj de las 99 noches.

	POR QUE ES UN MODULO Y NO UN SERVICIO
	--------------------------------------
	El servico (`NightService`) posee el hilo, el reloj real y los eventos. Aqui
	NO hay nada de eso: solo la ARITMETICA de cuando es de dia, cuando es de
	noche, que noche es y cuanto queda.

	La razon es que esa aritmetica es exactamente lo que hay que PROBAR, y la
	forma de probarla es poder dizer "dado este numero de segundos y esta noche,
	dime que fase es y que hora marca el reloj" sin arrancar un servidor y sin
	esperar veinte minutos. Con el codigo dentro del servicio, esa pregunta
	obligaria a un playtest; aqui es una tabla.

	LAS CUATRO FASES
	----------------
	El enunciado las pide: `Day`, `Sunset`, `Night`, `Dawn`. No son cuatro
	decorados: cada una cambia el juego.

	  Day     explorar, destruir, recoger. La poblacion es baja.
	  Sunset  aviso. La poblacion sube y el HUD marca el cambio.
	  Night   la presion maxima: hordas, eventos y mas tipos de enemigo.
	  Dawn    cierre. La presion cae y se paga la recompensa de haber aguantado.

	`Sunset` y `Dawn` existen para que el jugador tenga AVISO. Sin ellos la
	noche llega de golpe y el unico sintoma es que de pronto hay seis enemigos
	mas: eso se lee como un fallo del servidor, no como el paso del tiempo.
]]

local Rules = {}

-- ---------------------------------------------------------------------------
-- FASES
-- ---------------------------------------------------------------------------

Rules.Phase = {
	Day = "Day",
	Sunset = "Sunset",
	Night = "Night",
	Dawn = "Dawn",
}

-- Orden del ciclo. El ultimo vuelve al primero: el ciclo es cerrado.
Rules.PhaseOrder = { Rules.Phase.Day, Rules.Phase.Sunset, Rules.Phase.Night, Rules.Phase.Dawn }

--- Duracion de cada fase, en SEGUNDOS de juego.
---
-- Son los valores BASE. `Rules.DurationFor` los escala con la noche, asi que
-- en la noche 90 una noche dura mas que en la noche 1 (hay mas que aguantar)
-- y el dia dura mas tambien (hay mas que preparar). Lo que NO escala es la
-- RELACION entre fases: el atardecer siempre es una fraccion corta del dia.
--
-- Estas cuatro sumas son el presupuesto del ciclo. Si se cambian, cambia el
-- ritmo del juego entero, asi que viven aqui y no repartidas por los servicios.
Rules.BaseDurations = {
	Day = 150,
	Sunset = 20,
	Night = 90,
	Dawn = 20,
}

-- Tope del ciclo completo. Un dia de la noche 1 no puede pasar de esto: por
-- mucho que la noche escale, un ciclo que dura media hora es una desconexion
-- disfrazada.
Rules.MaxCycleDuration = 420

-- Minutos de juego que representa una noche completa. Es la escala del reloj
-- del HUD: no son minutos reales, son las horas del mundo.
Rules.MinutesPerCycle = 1440

-- ---------------------------------------------------------------------------
-- DURACION
-- ---------------------------------------------------------------------------

--- Escala de duracion de una noche concreta.
---
--- Sube con la noche pero ACOTA. Sin el tope, la noche 99 duraria casi media
--- hora con el doble de enemigos: el jugador no pierde, se aburre. Con el
--- tope, la noche 99 dura mas y trae MAS contenido, que es la diferencia
--- entre dificultad y castigo.
--- @param night any
--- @return number
function Rules.DurationScaleFor(night: any): number
	local n = tonumber(night) or 1

	if n ~= n then
		n = 1
	end

	-- De 1.0 en la noche 1 a 1.45 en la noche 99: crecimiento lento y acotado.
	local t = math.clamp((n - 1) / 98, 0, 1)
	return 1 + t * 0.45
end

--- Duracion en segundos de una fase en una noche concreta.
--- @param phase string
--- @param night any
--- @return number segundos; 0 si la fase no existe
function Rules.DurationFor(phase: string, night: any): number
	local base = Rules.BaseDurations[phase]

	if type(base) ~= "number" then
		return 0
	end

	local seconds = base * Rules.DurationScaleFor(night)

	if phase == Rules.Phase.Day or phase == Rules.Phase.Night then
		seconds = math.min(seconds, Rules.MaxCycleDuration)
	end

	return seconds
end

--- Las cuatro fases de una noche, con su duracion ya resuelta, en orden.
---
--- Devuelve una tabla NUEVA en cada llamada a proposito: el llamante la puede
--- modificar (por ejemplo para acelerar una prueba) sin corromper la
--- configuracion global.
--- @param night any
--- @return { { Phase: string, Seconds: number } }
function Rules.GetTimeline(night: any): { { Phase: string, Seconds: number } }
	local out = {}

	for _, phase in ipairs(Rules.PhaseOrder) do
		table.insert(out, {
			Phase = phase,
			Seconds = Rules.DurationFor(phase, night),
		})
	end

	return out
end

-- ---------------------------------------------------------------------------
-- EL RELOJ (FASE 9)
-- ---------------------------------------------------------------------------
--
-- El HUD tiene que mostrar:
--
--     NOCHE 17
--     03:42
--
-- `03:42` NO es la hora del sistema: es la hora del mundo. Empieza a las 06:00
-- con el amanecer, que es cuando empieza la fase `Day`, y la noche ocurre de
-- verdad entre las 22:00 y las 04:00. Esa correspondencia es lo que hace que el
-- reloj signifique algo: si el HUD dijera "14:20" durante la noche, el jugador
-- leeria un fallo.
--
-- La correspondencia se resuelve por FRACCION de ciclo, no por segundos
-- absolutos: se recorre la linea de tiempo y se pregunta "cuanto he recorrido
-- y en que fase estoy". Asi el reloj es correcto aunque las duraciones
-- cambien, y no hay que recalcular nada a mano cuando la noche 50 alarga las
-- fases.

-- Hora de inicio del ciclo, en minutos desde medianoche.
Rules.DayStartMinutes = 6 * 60

--- Minutos del mundo que equivalen a una fase.
---
--- El reparto NO es proporcional a la duracion en segundos: el dia y la noche
--- tienen duraciones parecidas pero ocupan MUCHO mas tiempo en el reloj. Eso es
--- correcto y es lo que hacen los juegos de ciclo: la noche llega pronto,
--- ocupa poco tiempo real y es el momento que el jugador recuerda.
--- @param phase string
--- @return number minutos; 0 si la fase no existe
-- Reparto ARITMETICO de los 1440 minutos del reloj, elegido para que la
	-- noche coincida con las horas oscuras:
	--
	--   06:00 -> 21:00   Day     (900 min)
	--   21:00 -> 22:00   Sunset   (60 min)
	--   22:00 -> 04:00   Night    (360 min)   <-- de noche, de verdad
	--   04:00 -> 06:00   Dawn     (120 min)
	--
	-- Los 1440 minutos tienen que cuadrar EXACTAMENTE: si el reparto sumara mas
	-- o menos, `MinutesAt` daria una hora distinta de la esperada al cerrar el
	-- ciclo y el reloj "saltaria" de las 23:59 a las 07:12.
function Rules.PhaseMinutes(phase: string): number
	if phase == Rules.Phase.Day then
		return 15 * 60
	elseif phase == Rules.Phase.Sunset then
		return 1 * 60
	elseif phase == Rules.Phase.Night then
		return 6 * 60
	elseif phase == Rules.Phase.Dawn then
		return 2 * 60
	end

	return 0
end

--- Minutos acumulados hasta el inicio de una fase.
--- @param phase string
--- @return number
function Rules.PhaseStartMinutes(phase: string): number
	local acc = 0

	for _, p in ipairs(Rules.PhaseOrder) do
		if p == phase then
			break
		end
		acc += Rules.PhaseMinutes(p)
	end

	return acc
end

--- Fraccion del ciclo en la que empieza una fase (0..1).
--- @param phase string
--- @return number
function Rules.PhaseStartFraction(phase: string): number
	local total = 0

	for _, p in ipairs(Rules.PhaseOrder) do
		total += Rules.PhaseMinutes(p)
	end

	if total <= 0 then
		return 0
	end

	return Rules.PhaseStartMinutes(phase) / total
end

--- Minutos de mundo (desde medianoche) para una fraccion de ciclo.
--- @param fraction number 0..1
--- @return number
function Rules.MinutesAt(fraction: number): number
	local f = math.clamp(fraction, 0, 1)

	-- El ultimo tramo (el que llega justo a 1.0) devuelve el inicio en vez de
	-- 1440, para que el reloj se lea `06:00` al reiniciar el ciclo y no una
	-- hora que no existe.
	if f >= 1 then
		return Rules.DayStartMinutes
	end

	return (Rules.DayStartMinutes + f * Rules.MinutesPerCycle) % Rules.MinutesPerCycle
end

--- Fase que corresponde a una fraccion de ciclo.
--- @param fraction number 0..1
--- @return string phase
function Rules.PhaseAt(fraction: number): string
	local f = math.clamp(fraction, 0, 1)

	for _, phase in ipairs(Rules.PhaseOrder) do
		local start = Rules.PhaseStartFraction(phase)
		local finish = start + Rules.PhaseMinutes(phase) / Rules.MinutesPerCycle

		-- La comparacion es `start <= f < finish` y no `>= start and <= end`:
		-- con los dos extremos cerrados, el limite entre dos fases pertenece a
		-- las dos, y un servicio que consultase el final de una y el principio
		-- de la siguiente veria DOS fases a la vez.
		if f >= start and f < finish then
			return phase
		end
	end

	-- Fuera de los tramos por precision de coma flotante: el final del ciclo
	-- es el principio del siguiente.
	return Rules.Phase.Day
end

--- Texto del reloj, `HH:MM`.
---
-- El formato es FIJO de dos digitos porque el HUD reserva el ancho para el
-- caso largo: sin el, el reloj "cambia de ancho" cada vez que pasa de las
-- 09:00 a las 10:00 y los labels de al lado bailan.
--- @param minutes number minutos desde medianoche
--- @return string
function Rules.FormatClock(minutes: number): string
	local m = math.floor(minutes)

	-- El rango se normaliza ANTES de formatear. Con un valor fuera de 0..1440,
	-- `%02d` imprimiria "25:00" en vez de "01:00", y un reloj que dice "25:00"
	-- no es un reloj: es un dato roto en pantalla.
	m = ((m % Rules.MinutesPerCycle) + Rules.MinutesPerCycle) % Rules.MinutesPerCycle

	local hours = math.floor(m / 60)
	local mins = m % 60

	return ("%02d:%02d"):format(hours, mins)
end

--- Estado completo del mundo para el HUD, resuelto desde una fraccion.
---
--- Es lo que `NightService` publica como atributos. Se devuelve TODO junto
--- para que el HUD lea un estado coherente y no tres atributos que podrian
--- pertenecer a frames distintos.
--- @param night any numero de noche
--- @param fraction any fraccion de ciclo 0..1
--- @return { Night: number, Phase: string, PhaseLabel: string, Clock: string, Fraction: number, IsNight: boolean, Transition: boolean }
function Rules.GetClockState(night: any, fraction: any): {
	Night: number,
	Phase: string,
	PhaseLabel: string,
	Clock: string,
	Fraction: number,
	IsNight: boolean,
	Transition: boolean,
}
	local n = tonumber(night)
	local f = tonumber(fraction)

	-- El `NaN` se comprueba de forma explicita porque `math.floor` lo deja
	-- pasar y `math.clamp` con un NaN devuelve NaN: sin esto, un reloj roto
	-- se.publisha como atributo y el HUD muestra "NaN:NaN" a todo el servidor.
	if not n or n ~= n then
		n = 1
	end
	if not f or f ~= f then
		f = 0
	end

	n = math.clamp(math.floor(n), 1, 99)
	f = math.clamp(f, 0, 1)

	local phase = Rules.PhaseAt(f)

	return {
		Night = n,
		Phase = phase,
		PhaseLabel = Rules.LabelForPhase(phase),
		Clock = Rules.FormatClock(Rules.MinutesAt(f)),
		Fraction = f,
		IsNight = phase == Rules.Phase.Night,
		-- `Sunset` y `Dawn` son las transiciones: el HUD las marca para que el
		-- jugador sepa que la noche viene o se va, en lugar de encontrarse
		-- con el cambio ya hecho.
		Transition = phase == Rules.Phase.Sunset or phase == Rules.Phase.Dawn,
	}
end

--- Texto de la fase, como lo ve el jugador.
---
--- Son etiquetas cortas y en mayusculas porque van en el HUD, donde el espacio
--- es el recurso escaso: "NOCHE" cabe en el ancho reservado y "Fase de la noche"
--- empujaria el resto del HUD fuera de la pantalla en movil.
--- @param phase string
--- @return string
function Rules.LabelForPhase(phase: string): string
	if phase == Rules.Phase.Day then
		return "DIA"
	elseif phase == Rules.Phase.Sunset then
		return "ATARDECER"
	elseif phase == Rules.Phase.Night then
		return "NOCHE"
	elseif phase == Rules.Phase.Dawn then
		return "AMANECE"
	end

	return tostring(phase)
end

--- Duracion total de un ciclo completo, en segundos.
---
--- El servicio la usa para saber cuanto falta hasta la siguiente noche sin
--- tener que recorrer la linea de tiempo cada frame.
--- @param night any
--- @return number
function Rules.CycleDuration(night: any): number
	local total = 0

	for _, phase in ipairs(Rules.PhaseOrder) do
		total += Rules.DurationFor(phase, night)
	end

	return total
end

return Rules