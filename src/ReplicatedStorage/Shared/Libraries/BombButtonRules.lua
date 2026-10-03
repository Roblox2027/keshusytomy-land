--!strict
--[[
	BombButtonRules
	Logica PURA del BOTON DE BOMBA: que estado tiene y como se ve.

	POR QUE NO ES "UN TextButton ROJO CON LA PALABRA BOMBA"
	------------------------------------------------------
	Un rectangulo rojo con la palabra "BOMBA" dice QUE accion hay, pero no
	que objeto es. El jugador tiene que traducir "boton rojo = explosive".
	Una bomba dibujada se reconoce antes de leer un solo caracter, y en
	movil, donde el texto pequeno es dificil de leer, la diferencia es
	brutal.

	Este modulo NO dibuja nada: describe la geometria y el color de cada
	pieza. El `InputController` la convierte en `Frame` y `TextLabel`. La
	separacion es la misma que usan `AudioPool` y `BlockRespawnRules`: la
	decision se prueba sin motor y el controlador solo la aplica.

	QUE SE PIDE EN CADA ESTADO
	--------------------------
	  Ready     la bomba se ve entera, con su mecha encendida
	  Cooldown  la bomba se atenua y se leen los segundos que faltan
	  Blocked   no se puede usar: se apaga y explica por que
	  Pressed   el jugador acaba de pulsarla: la bomba se ACHICA

	La distincion entre `Pressed` y `Placed` importa: `Pressed` es el
	feedback instantaneo del dedo (10 ms) y `Placed` es la confirmacion de
	que el servidor ACEPTO la bomba. Con una sola alarma, una peticion
	rechazada por enfriamiento se sentiria como si la bomba se hubiera
	puesto.
]]

local Rules = {}

-- Estados posibles del boton. Son cadenas porque aparecen en logs y en el
-- inspector, y un numero no dice nada cuando se lee a mano.
Rules.State = {
	-- No hay nada que impedirlo: se puede pulsar.
	Ready = "Ready",
	-- El enfriamiento del servidor (o el bloqueo local) esta activo.
	Cooldown = "Cooldown",
	-- El jugador no puede usar la bomba: sin vida, sin personaje, sin
	-- ronda en curso, o el servidor lo ha rechazado.
	Blocked = "Blocked",
	-- Se acaba de pulsar y aun no se sabe si el servidor acepto.
	Pressed = "Pressed",
	-- El servidor ACEPTO la bomba y la puso en el mundo.
	Placed = "Placed",
}

--- Paleta del boton.
---
--- Se declara aqui y no en el controlador para que un cambio de identidad
--- visual sea un dato y no una edicion de codigo. Los colores de la bomba
--- dibujada en el mundo (`VisualKit.BombSkin`) vienen del MUNDO; los del
--- boton son de la INTERFAZ, asi que son fijos.
Rules.Palette = {
	-- Cuerpo: metal oscuro. Es lo que la distingue de un boton rojo.
	Body = { R = 34, G = 36, B = 44 },
	-- Franja clara del ecuador: da lectura de "bomba" de un vistazo.
	Band = { R = 226, G = 232, B = 240 },
	-- Tapa superior, mas clara que el cuerpo para separar las dos formas.
	Top = { R = 92, G = 100, B = 116 },
	-- Mecha: cuerda apagada.
	Fuse = { R = 138, G = 110, B = 78 },
	-- Chispa: el unico punto calido de todo el boton.
	Spark = { R = 255, G = 186, B = 64 },
	-- Etiqueta secundaria (la tecla).
	Hint = { R = 232, G = 236, B = 244 },
	-- Estado bloqueado: gris. Un boton bloqueado que sigue siendo rojo
	-- parece DISPONIBLE y el jugador lo pulsa sin entender nada.
	Muted = { R = 96, G = 100, B = 112 },
}

--- Tamano del boton en pixeles.
Rules.Size = 104

--- Resuelve el estado del boton a partir de lo que el jugador puede
--- hacer ahora mismo.
---
--- Es la funcion central del modulo: el controlador NO decide el estado
--- con sus propios `if`. Si lo hiciera, el "bloqueado" y el "enfriado"
--- acabarian mezclados en un solo `BackgroundTransparency`, que es
--- exactamente el bug que tenia el boton rojo.
---
--- @param canPlace boolean si el servidor permitiria colocar ahora
--- @param cooldownRemaining number segundos que faltan de enfriamiento
--- @param pressed boolean el jugador acaba de pulsar
--- @param placed boolean el servidor acaba de confirmar la bomba
--- @return string state
function Rules.Resolve(
	canPlace: boolean,
	cooldownRemaining: number,
	pressed: boolean,
	placed: boolean
): string
	-- El orden importa y NO es arbitrario:
	--
	-- 1. `placed` gana a todo. Es la confirmacion del servidor y debe
	--    verse aunque el enfriamiento ya haya empezado a contar.
	-- 2. `pressed` va despues: el dedo esta encima y aun no hay respuesta.
	-- 3. `blocked` antes que `cooldown`, porque "no puedes" y "espera" son
	--    mensajes distintos y confundirlos hace que el jugador espere un
	--    tiempo que no va a terminar nunca.
	-- 4. `cooldown` por ultimo: solo tiene sentido si se puede colocar.
	if placed then
		return Rules.State.Placed
	end

	if pressed then
		return Rules.State.Pressed
	end

	if not canPlace then
		return Rules.State.Blocked
	end

	if cooldownRemaining > 0 then
		return Rules.State.Cooldown
	end

	return Rules.State.Ready
end

--- Aspecto del boton en un estado.
---
--- Devuelve una tabla NUEVA en cada llamada. Si devolviera una tabla
--- compartida, el controlador que la modificara (para el temporizador de
--- la pulsacion) contaminaria a todos los demas.
---
--- @param state string estado devuelto por `Resolve`
--- @param cooldownRemaining number segundos restantes (0 si no aplica)
--- @return table appearance
function Rules.Appearance(state: string, cooldownRemaining: number): { [string]: any }
	local palette = Rules.Palette

	-- Base: el boton con los colores de la bomba ENCENDIDA.
	local body = palette.Body
	local band = palette.Band
	local top = palette.Top
	local fuse = palette.Fuse
	local spark = palette.Spark

	-- `Dim` va de 0 (color pleno) a 1 (apagado). Los colores se mezclan
	-- hacia `Muted` con esa cantidad, de modo que el mismo valor de `Dim`
	-- sirve tanto para el enfriamiento como para el bloqueo.
	local dim = 0
	local label = ""
	local showCountdown = false
	local sparkVisible = true
	local sparkScale = 1

	if state == Rules.State.Ready then
		-- Sin cambios: la bomba se ve tal cual. La etiqueta secundaria
		-- muestra la TECLA, porque en PC el boton es un atajo y el jugador
		-- quiere saber cual es sin abrir ningun menu.
		label = "F"

	elseif state == Rules.State.Cooldown then
		dim = 0.45
		-- La cuenta atras es la parte util: sin ella el boton parece roto.
		showCountdown = true
		label = ("%.1f"):format(cooldownRemaining)
		-- La chispa se apaga: la bomba esta "usandose" y ya no chisporrotea.
		sparkVisible = false

	elseif state == Rules.State.Blocked then
		dim = 1
		-- Sin cuenta atras: aqui no hay nada que esperar. Poner un numero
		-- haria pensar al jugador que el bloqueo es temporal.
		sparkVisible = false
		label = "X"

	elseif state == Rules.State.Pressed then
		-- El feedback del dedo: la bomba se aviva. NO se atenua, porque el
		-- jugador acaba de hacer algo y el boton debe responder.
		sparkScale = 1.45
		label = "F"

	elseif state == Rules.State.Placed then
		-- Confirmacion del servidor. La chispa crece: el jugador tiene que
		-- ver "salio" sin mirar el mundo.
		sparkScale = 1.8
		label = "OK"
	end

	return {
		Dim = dim,
		SparkVisible = sparkVisible,
		SparkScale = sparkScale,
		Label = label,
		ShowCountdown = showCountdown,
		Body = body,
		Band = band,
		Top = top,
		Fuse = fuse,
		Spark = spark,
	}
end

--- Geometria de las piezas de la bomba, en offsets desde el centro.
---
--- Los offsets son la razon por la que esto NO es "un circulo con un
--- texto": el cuerpo, la tapa, la mecha y la chispa estan en sitios
--- concretos y unos respetan a los otros. Un circulo no tiene mecha.
---
--- Las medidas estan en pixeles y derivan todas de `Rules.Size`, asi que
--- cambiar el tamano del boton no deja pieces descolgadas.
---
--- @return table parts
function Rules.Geometry(): { [string]: any }
	local size = Rules.Size

	return {
		-- Cuerpo: la esfera metalica, ligeramente por debajo del centro
		-- para dejar sitio a la tapa y a la mecha.
		Body = {
			Position = { X = 0, Y = 6 },
			Size = size * 0.56,
			CornerRadius = size * 0.28,
			Rotation = 0,
		},

		-- Franja ecuatorial: el detalle que la hace "bomba" y no "canica".
		Band = {
			Position = { X = 0, Y = 8 },
			Size = { X = size * 0.58, Y = size * 0.10 },
			CornerRadius = size * 0.05,
			Rotation = 0,
		},

		-- Tapa: el cuello de la bomba, encima del cuerpo.
		Top = {
			Position = { X = 0, Y = -size * 0.22 },
			Size = { X = size * 0.24, Y = size * 0.13 },
			CornerRadius = size * 0.05,
			Rotation = 0,
		},

		-- Mecha: sale de la tapa y se curva. El giro es lo que la hace
		-- reconocible: una mecha recta vertical parece un palo.
		Fuse = {
			Position = { X = size * 0.09, Y = -size * 0.33 },
			Size = { X = size * 0.055, Y = size * 0.20 },
			CornerRadius = size * 0.03,
			Rotation = -24,
		},

		-- Chispa: el extremo de la mecha. Es lo unico que ANDA.
		Spark = {
			Position = { X = size * 0.15, Y = -size * 0.43 },
			Size = size * 0.10,
			CornerRadius = size * 0.05,
			Rotation = 0,
		},
	}
end

--- Tiempos de la animacion, en segundos.
---
--- Son BALANCE, no detalles: un feedback de 2 s en un boton se siente
--- lento, y uno de 0.05 s no se ve. Salen de aqui y no del controlador
--- para que ajustarlos no obligue a tocar logica.
Rules.Timing = {
	-- Cuanto se mantiene la animacion de pulsacion. Deliberadamente corta:
	-- responde al dedo y se retira.
	PressDuration = 0.12,
	-- Cuanto dura la confirmacion de "bomba colocada".
	PlacedDuration = 0.45,
	-- Periodo del latido de la chispa en estado `Ready`.
	SparkPulsePeriod = 1.1,
	-- Cuanto crece y encoge la chispa en cada latido.
	SparkPulseAmount = 0.18,
}

--- Devuelve la escala de la chispa en un instante, para el latido.
---
--- Es una ONDA TRIANGULAR, no un seno. El seno empieza y acaba en el
--- mismo valor y se ve como un pulso lento; la triangular sube y baja en
--- linea recta, que a esta escala se lee como "chispa que titila".
---
--- @param elapsed number segundos desde el inicio del latido
--- @param period number duracion del ciclo
--- @param amount number amplitud relativa
--- @return number scale
function Rules.SparkPulse(elapsed: number, period: number, amount: number): number
	if period <= 0 then
		return 1
	end

	-- El modulo con `2 * period` hace el ciclo sin discontinuidad: en
	-- `elapsed = period` se esta en el punto medio, no en el salto.
	local phase = (elapsed % (period * 2)) / period

	-- De 0 a 2 y de 2 a 0, en linea recta.
	local triangle = if phase <= 1 then phase else 2 - phase

	return 1 + triangle * amount
end

return Rules