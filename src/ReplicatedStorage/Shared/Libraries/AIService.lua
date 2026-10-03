--!strict
--[[
	AIService
	LOGICA PURA de movimiento de monstruos. Sin instancias de Roblox.

	POR QUE VIVE EN `Shared/Libraries` Y NO COMO SERVICIO
	----------------------------------------------------
	Un ModuleScript en `ServerScriptService/Services` se registra en el
	ServiceRegistry y se le llama "servicio": tiene `Init`, `Start` y se le
	exige que este VIVO para que el arranque lo de por bueno. Este modulo no
	arranca nada: es una funcion con reglas.

	Si viviera ahi, contaria como el servicio 34/34 arrancado sin que un solo
	monstruo se haya movido nunca, y ademas no se podria probar sin montar
	Roblox. En `Libraries` se ejecuta con el interprete de Luau, asi que un
	caso mal cubierto se ve en la salida del test y no dos minutos despues
	durante un playtest.

	LA IA SIGUE SIENDO DEL SERVIDOR
	--------------------------------
	Pura no significa authority: el servidor es quien llama y quien mueve la
	Parte. El cliente no puede sugerir un destino.

	MAQUINA DE ESTADOS Y TELEGRAPH
	-------------------------------
	La IA no es "veo al jugador y corro". Es una maquina de estados con las
	fases que el jugador PUEDE leer:

	    Idle -> Patrol -> Detect -> Warning -> Chase -> Attack -> Recovery

	Los tres estados que existen solo para que el jugador pueda reaccionar son
	`Detect` (el monstruo se ha fijado pero aun no se mueve), `Warning` (el
	telegraph previo a un ataque) y `Recovery` (el monstruo no puede volver a
	atacar todavia). Sin ellos el jugador muere sin entender que paso, que es
	exactamente el fallo de UX que el balancing no arregla.

	La velocidad depende del ESTADO, no del tipo de monstruo. Un Hunter en
	`PatrolSpeed` es lento y legible; su `ChargeSpeed` solo se usa durante una
	carga telegrafiada y con cooldown, asi que es peligroso sin ser
	imparable.
]]

local AI = {}

-- Velocidad de referencia del JUGADOR.
--
-- NUMERO FIJO a proposito. Se explica en `AI.GetPlayerSpeed`, que es donde se
-- lee; aqui solo se declara para que la regla sea visible al abrir el archivo.
local PLAYER_SPEED = 16

-- Estados posibles de un monstruo, en orden de recorrido.
--
-- Se declaran como tabla y no como cadena suelta en cada sitio porque el
-- estado se COMPARA (en MonsterService, en pruebas y en el HUD). Una cadena
-- mal escrita ("chase" en vez de "Chase") no da error de sintaxis: da un
-- monstruo que nunca ataca y nadie sabe por que.
AI.States = {
	Idle = "Idle",
	Patrol = "Patrol",
	Detect = "Detect",
	Warning = "Warning",
	Chase = "Chase",
	Attack = "Attack",
	Recovery = "Recovery",
}

--- Direccion normalizada de `from` a `to` en el plano XZ.
---
--- Se trabaja en dos dimensiones a proposito: un monstruo que persigue a
--- un jugador en un mapa con dos alturas no debe "subir" por el aire, debe
--- ir al suelo. La Y la decide el mapa.
--- @param from { x: number, z: number }
--- @param to { x: number, z: number }
--- @return number dx
--- @return number dz
function AI.Direction(from: { x: number, z: number }, to: { x: number, z: number }): (number, number)
	local dx = to.x - from.x
	local dz = to.z - from.z
	local magnitude = math.sqrt(dx * dx + dz * dz)

	if magnitude == 0 then
		return 0, 0
	end

	return dx / magnitude, dz / magnitude
end

--- Distancia horizontal entre dos puntos.
--- @param ax number
--- @param az number
--- @param bx number
--- @param bz number
--- @return number
function AI.Distance(ax: number, az: number, bx: number, bz: number): number
	local dx = bx - ax
	local dz = bz - az
	return math.sqrt(dx * dx + dz * dz)
end

--- ?Toca atacar? Un monstruo ataca cuando el objetivo esta a su alcance.
---
--- Se separa de `Step` porque son preguntas distintas con umbrales
--- distintos: se puede PERSEGUIR a alguien a 40 studs y solo poder
--- ATACARLE a 6. Confundir los dos umbrales hacia que los monstruos
--- golpeen desde lejos o que se queden quietos pegados al jugador.
--- @param distance number
--- @param attackRange number
--- @return boolean
function AI.ShouldAttack(distance: number, attackRange: number): boolean
	return distance <= attackRange
end

--- Velocidad de persecion de un monstruo, ACOTADA por la del jugador.
---
--- El multiplicador por si solo es peligroso: con el tope antiguo (3x), un
--- `Speed` de 14 con multiplicador 1.8 daba 25.2 studs/s contra un jugador de
--- 16, es decir un enemigo INBATIBLE. La bomba dejaba de ser una decision y
--- pasaba a ser una carrera perdida, y ese es el fallo exacto que este numero
--- no puede permitir.
---
--- Por eso el resultado se recorta contra `AI.MaxChaseSpeed` y no solo contra
--- un maximo de multiplicador. Con eso, la garantia es la que de verdad importa:
--- la persecucion sostenida de CUALQUIER monstruo es siempre mas lenta que el
--- jugador. El multiplicador solo sirve para nuances de velocidad DENTRO de esa
--- banda; nunca para salir de ella.
---
--- Se conserva la firma historica (`baseSpeed`, `chaseMultiplier`) porque
--- `CombatMath` y pruebas antiguas la llaman asi.
---
--- El resultado no depende del multiplicador solo, y por eso el recorte se
--- hace DESPUES: el recorte es la GARANTIA y el multiplicador es solo la
--- intencion de diseno. Si manana se sube `MAX_MULTIPLIER` a 3, el recorte
--- sigue estando y la garantia sigue valiendo: un multiplicador no puede
--- romper la regla, solo acercarse a ella.
--- @param baseSpeed number
--- @param chaseMultiplier number
--- @return number speed
function AI.ChaseSpeed(baseSpeed: number, chaseMultiplier: number): number
	local MAX_MULTIPLIER = 1.5

	local multiplier = chaseMultiplier
	if multiplier < 1 then
		multiplier = 1
	elseif multiplier > MAX_MULTIPLIER then
		multiplier = MAX_MULTIPLIER
	end

	local speed = baseSpeed * multiplier

	-- El redondeo a 2 decimales NO es cosmetico: `16 * 0.78` da
	-- 12.480000000000004 en IEEE-754, y ese numero sucio se comparaba en las
	-- pruebas con 12.48 y fallaba. Un tope de velocidad que produce numeros con
	-- ruido de coma flotante hace imposible escribir una prueba EXACTA sobre
	-- el balance, que es justo lo que hace falta para protegerlo.
	local rounded = math.floor(speed * 100 + 0.5) / 100

	local ceiling = AI.MaxChaseSpeed()
	if rounded > ceiling then
		return math.floor(ceiling * 100 + 0.5) / 100
	end

	return rounded
end

--- Velocidad del JUGADOR, la que TODA la IA se mide contra.
---
--- Es un valor FIJO a proposito, no una lectura de `GameConfig`: este modulo es
--- logica PURA y se carga con el interprete de Luau, donde no existe
--- `ReplicatedStorage`. Si se leyera la configuracion aqui, `require` fallaria
--- en las pruebas y la IA entera dejaria de ser verificable sin Roblox, que es
--- justo cuando mas falta hace.
---
--- El precio de esa decision es que el numero esta DUPLICADO (esta aqui y en
--- `GameConfig.DefaultPlayerSpeed`). Por eso `MonsterService` lo imprime al
--- arrancar y por eso la regla esta escrita con el 16 a la vista: si los dos
--- dejan de coincidir, "el monstruo no es mas rapido que el jugador" deja de
--- ser verdad aunque cada numero por separado parezca razonable. Es un fallo de
--- seguridad del balance, no un descuido.
---
--- Cuando cambie la velocidad del jugador, se cambia en LOS DOS sitios.
--- @return number
function AI.GetPlayerSpeed(): number
	return PLAYER_SPEED
end

--- Tope de velocidad de PERSECUCION como funcion de la del jugador.
---
--- Regla del balance: la persecion sostenida es siempre MAS LENTA que el
--- jugador. El jugador gana la carrera si decide bien; el peligro viene de la
--- cantidad de monstruos, de las cargas telegrafiadas y del ataque, no de una
--- velocidad absurda.
---
--- El margen baja en los mundos avanzados (`pressure`), asi que en Cyber el
--- jugador no es un simple corredor: tiene que usar los obstaculos y las
--- explosiones. Ese margen NUNCA llega a 1.0 (velocidad igual a la del
--- jugador), porque en el limite un jugador panicado deja de ganar.
--- @param pressure number? 0.55 en Forest, 0.85 en Cyber
--- @return number studsPerSecond
function AI.MaxChaseSpeed(pressure: number?): number
	local playerSpeed = AI.GetPlayerSpeed()

	local ratio = pressure or 0.78
	if ratio < 0.4 then
		ratio = 0.4
	elseif ratio > 0.92 then
		ratio = 0.92
	end

	return playerSpeed * ratio
end

--- Tope de velocidad de CARGA (ataque telegrafiado).
---
--- Aqui si se permite superar al jugador, porque la carga dura poco, se avisa
--- antes y tiene cooldown. Es lo que convierte a un enemigo rapido en una
--- amenaza FAIR en vez de en un muro.
--- @return number
function AI.MaxChargeSpeed(): number
	return AI.GetPlayerSpeed() * 1.45
end

--- Velocidad de un monstruo EN UN ESTADO CONCRETO.
---
--- Cada estado tiene su velocidad, y el nombre de la velocidad es el del
--- estado mas un sufijo de intencion (`Chase` -> `ChaseSpeed`, `Warning` ->
--- `WarningSpeed`...). La tabla de estados y la de definiciones estan
--- escritas en el mismo orden a proposito: si se anade un estado sin su
--- velocidad, aqui devuelve la velocidad de patrulla y el monstruo se queda
--- lento en vez de romperse.
---
--- La velocidad NUNCA es arbitraria: se acota con `AI.MaxChaseSpeed` /
--- `AI.MaxChargeSpeed`, de modo que cambiar la velocidad del jugador en
--- `GameConfig` reequilibra los monstruos sin tocar sus definiciones.
--- @param def table definicion de monstruo (MonsterDefinitions)
--- @param state string
--- @return number
function AI.StateSpeed(def: any, state: string): number
	if type(def) ~= "table" then
		return 0
	end

	local fieldByState = {
		[AI.States.Idle] = "IdleSpeed",
		[AI.States.Patrol] = "PatrolSpeed",
		[AI.States.Detect] = "DetectSpeed",
		[AI.States.Warning] = "WarningSpeed",
		[AI.States.Chase] = "ChaseSpeed",
		[AI.States.Attack] = "ChargeSpeed",
		[AI.States.Recovery] = "RecoverySpeed",
	}

	local field = fieldByState[state]
	local raw = if field then def[field] else nil

	-- Sin valor declarado para ese estado se cae a la velocidad base: es
	-- preferible un monstruo lento a uno con velocidad `nil` (que en una
	-- multiplicacion da NaN y lo deja clavado en el sitio).
	if type(raw) ~= "number" or raw ~= raw then
		raw = if type(def.Speed) == "number" then def.Speed else 0
	end

	local pressure = def.Pressure

	if state == AI.States.Chase then
		local ceiling = AI.MaxChaseSpeed(pressure)
		if raw > ceiling then
			return ceiling
		end
	end

	if state == AI.States.Attack then
		local ceiling = AI.MaxChargeSpeed()
		if raw > ceiling then
			return ceiling
		end
	end

	return math.max(0, raw)
end

--- Un paso de IA: ?mover hacia el objetivo?
---
--- Reglas:
---   - El objetivo debe estar DENTRO del rango de deteccion. Un monstruo
---     no persigue a un jugador a 400 studs: eso haria que los monstruos
---     del mapa entero convergieran en el unico jugador vivo.
---   - Un objetivo encima del monstruo NO produce movimiento: normalizar un
---     vector de distancia cero daria NaN y el NPC se quedaria clavado
---     vibrando en el sitio.
---   - La distancia devuelta es la del PLANO, no la 3D.
--- @param from any
--- @param to any
--- @param detectionRange number
--- @return table step
function AI.Step(from: any, to: any, detectionRange: number)
	local distance = AI.Distance(from.X, from.Z, to.X, to.Z)

	if distance > detectionRange then
		return { Move = false, Direction = { x = 0, y = 0, z = 0 }, Distance = distance }
	end

	if distance <= 0 then
		return { Move = false, Direction = { x = 0, y = 0, z = 0 }, Distance = 0 }
	end

	local dx, dz = AI.Direction(
		{ x = from.X, z = from.Z },
		{ x = to.X, z = to.Z }
	)

	return {
		Move = true,
		Direction = { x = dx, y = 0, z = dz },
		Distance = distance,
	}
end
-- ------------------------------------------------------ MAQUINA DE ESTADOS
--
-- `Think` es la funcion que decide QUE ESTADO toca. Es pura: recibe el estado
-- actual, cuanto tiempo lleva en el y lo que ve (distancia al objetivo mas si
-- lo tiene o no), y devuelve el estado siguiente. No recibe INSTANCIAS ni
-- conoce el Workspace, asi que se puede probar entero.
--
-- Las reglas, en una frase cada una:
--   - Sin objetivo visible: `Patrol` (o `Idle` si el monstruo es de los que
--     se quedan quietos, como el Guardian).
--   - Ve al objetivo por primera vez: `Detect`. NO se mueve. El jugador ve
--     que le han detectado y todavia puede elegir.
--   - `Detect` aguanta `DetectTime` y luego pasa a `Warning`.
--   - `Warning` aguanta `WarningTime` (el telegraph) y luego a `Chase`.
--   - En `Chase`, si entra en `AttackRange` y ha pasado el cooldown, a
--     `Attack` (la carga).
--   - `Attack` dura `ChargeDuration` y luego a `Recovery`.
--   - `Recovery` dura `RecoveryTime` (el cooldown) y vuelve a `Chase` si sigue
--     viendo al objetivo, o a `Patrol` si ha desaparecido.
--   - Si pierde el objetivo en `Chase` mas de `LoseTargetTime`, a `Patrol`.
--
-- Los tiempos vienen de la definicion del monstruo, no de constantes aqui:
-- un Slime avisa durante 0.6 s y un Cyber Stalker durante 1.2 s, y esa es
-- exactamente la diferencia de personalidad que el jugador tiene que aprender.

--- Duraciones por defecto de los estados, en segundos.
---
--- Se exportan para que `MonsterDefinitions` use estos numeros como valor por
--- defecto en vez de repetir literales, y para que las pruebas puedan citarlos.
AI.Defaults = {
	DetectTime = 0.45,
	WarningTime = 0.6,
	ChargeDuration = 0.5,
	RecoveryTime = 1.8,
	LoseTargetTime = 4.0,
}

--- Devuelve un valor de la definicion, o el valor por defecto indicado.
---
--- Existe porque `def` viene de una tabla de datos y no de un tipo cerrado: un
--- monstruo nuevo declarado sin `WarningTime` NO puede romper la IA con una
--- operacion sobre `nil`.
local function field(def: any, name: string, fallback: number): number
	if type(def) == "table" then
		local value = def[name]
		if type(value) == "number" and value == value and value >= 0 then
			return value
		end
	end
	return fallback
end

--- Un tick de la maquina de estados.
--- @param state string estado actual (`AI.States`)
--- @param timeInState number segundos que lleva en ese estado
--- @param def any definicion del monstruo
--- @param hasTarget boolean hay un jugador visible
--- @param distance number distancia horizontal al objetivo (o `math.huge`)
--- @return string nextState
function AI.Think(state: string, timeInState: number, def: any, hasTarget: boolean, distance: number): string
	local valid = {
		[AI.States.Idle] = true,
		[AI.States.Patrol] = true,
		[AI.States.Detect] = true,
		[AI.States.Warning] = true,
		[AI.States.Chase] = true,
		[AI.States.Attack] = true,
		[AI.States.Recovery] = true,
	}

	-- Un estado desconocido (typo, dato viejo, un estado retirado) no puede
	-- dejar al monstruo atrapado en un `if` que no existe: cae a `Patrol`,
	-- que siempre es un destino valido.
	if type(state) ~= "string" or not valid[state] then
		state = AI.States.Patrol
	end

	if type(timeInState) ~= "number" or timeInState ~= timeInState then
		timeInState = 0
	end

	if type(distance) ~= "number" or distance ~= distance then
		distance = math.huge
	end

	local S = AI.States

	if not hasTarget then
		-- Sin objetivo se abandona la persecucion, pero `Attack` y `Warning`
		-- se TERMINAN igual: cancelar la carga en mitad dejaria al monstruo
		-- girando sobre si mismo y, peor, cobraria dano sin haber avisado.
		if state == S.Attack or state == S.Warning or state == S.Detect then
			return S.Recovery
		end
		if state == S.Chase then
			return S.Patrol
		end

		-- `StillWhenIdle` es un BOOLEANO y por eso no se lee con `field()`,
		-- que solo acepta numeros. Es un fallo facil de cometer: la comprobacion
		-- `> 0` sobre `true` en Lua da un error de tipo, y el Guardian se
		-- convertia en un patrullero normal sin que nadie se enterase.
		local still = if type(def) == "table" then def.StillWhenIdle else nil

		if still == true then
			return S.Idle
		end

		return S.Patrol
	end

	if state == S.Idle or state == S.Patrol then
		return S.Detect
	end

	if state == S.Detect then
		if timeInState >= field(def, "DetectTime", AI.Defaults.DetectTime) then
			return S.Warning
		end
		return S.Detect
	end

	if state == S.Warning then
		if timeInState >= field(def, "WarningTime", AI.Defaults.WarningTime) then
			return S.Chase
		end
		return S.Warning
	end

	if state == S.Chase then
		local attackRange = field(def, "AttackRange", 6)
		local cooldown = field(def, "AttackCooldown", 1.5)

		-- El cooldown se mide con `timeInState` porque `Chase` se alcanza
		-- siempre desde `Warning`, es decir con el contador a cero.
		if distance <= attackRange and timeInState >= cooldown then
			return S.Attack
		end

		if distance > field(def, "LoseTargetRange", math.huge) then
			return S.Patrol
		end

		return S.Chase
	end

	if state == S.Attack then
		if timeInState >= field(def, "ChargeDuration", AI.Defaults.ChargeDuration) then
			return S.Recovery
		end
		return S.Attack
	end

	if state == S.Recovery then
		local recoveryTime = field(def, "RecoveryTime", AI.Defaults.RecoveryTime)
		if timeInState >= recoveryTime then
			return S.Chase
		end
		return S.Recovery
	end

	return S.Patrol
end

--- --Este estado permite mover al monstruo?
---
--- `Detect`, `Warning` y `Recovery` NO son estados en los que el monstruo se
--- mueva: son la ventana de reaccion del jugador. Si se movieran, la maquina
--- de estados seria decorativa y el telegraph no serviria de nada.
--- @param state string
--- @return boolean
function AI.CanMove(state: string): boolean
	return state == AI.States.Patrol
		or state == AI.States.Chase
		or state == AI.States.Attack
		or state == AI.States.Idle
end

--- --Este estado AVISA al jugador de un ataque inminente?
---
--- El servidor lo usa para el brillo, el sonido y la etiqueta: lo que el
--- jugador ve tiene que salir de aqui, no de un `if` duplicado.
--- @param state string
--- @return boolean
function AI.IsTelegraph(state: string): boolean
	return state == AI.States.Warning
end

--- Segundos que faltan para que termine el estado actual.
---
--- Lo consume el cartel del monstruo para mostrar "!" con el tiempo que le
--- queda, que es lo que convierte un ataque en algo aprendible en vez de en
--- un dano sin explicacion.
--- @param state string
--- @param timeInState number
--- @param def any
--- @return number
function AI.TimeLeftInState(state: string, timeInState: number, def: any): number
	local durations = {
		[AI.States.Detect] = "DetectTime",
		[AI.States.Warning] = "WarningTime",
		[AI.States.Attack] = "ChargeDuration",
		[AI.States.Recovery] = "RecoveryTime",
	}

	local fieldName = durations[state]
	if not fieldName then
		return 0
	end

	local fallback = if fieldName == "WarningTime"
		then AI.Defaults.WarningTime
		elseif fieldName == "DetectTime"
			then AI.Defaults.DetectTime
			elseif fieldName == "ChargeDuration"
				then AI.Defaults.ChargeDuration
				else AI.Defaults.RecoveryTime

	local total = field(def, fieldName, fallback)
	local left = total - (timeInState or 0)

	-- El redondeo no es cosmetico: `1.4 - 1.0` da 0.3999999999999999 en
	-- IEEE-754, y eso se imprimia TAL CUAL en el cartel del monstruo como
	-- "!0.4" -> "!0.3999999999999999". Un texto de cuenta atras con ruido de
	-- coma flotante se ve roto, y el jugador lo lee como un fallo del juego
	-- en lugar de como lo que es.
	if left <= 0 then
		return 0
	end

	return math.floor(left * 100 + 0.5) / 100
end

return AI
