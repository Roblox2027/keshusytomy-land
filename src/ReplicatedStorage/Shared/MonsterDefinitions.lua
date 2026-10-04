--!strict
--[[
	MonsterDefinitions
	DATOS de los monstruos. Ni una linea de logica aqui.

	POR QUE UN ARCHIVO APARTE
	--------------------------
	Un monstruo no es "un NPC con 30 de vida": es vida, velocidad, radio de
	agresion, alcance de ataque, dano, recompensa y un color. Si esos numeros
	viven dentro de `MonsterService`, cambiar la dificultad de un monstruo
	obliga a editar codigo, y no hay forma de comprobar que un monstruo nuevo
	no se solapa con otro.

	Aqui son una tabla. Anadir un monstruo es anadir una entrada, y
	`GetIds` permite que una prueba verifique que cada definicion tiene los
	campos obligatorios: un monstruo con `AttackRange = nil` no puede
	aparecer, y es mejor que lo diga el test y no el Output de un playtest.

	EL TOPE `MaxAlive` ES POR DEFINICION
	-----------------------------------
	No es decorativo: `MonsterService.Spawn` lo consulta. Sin el, un jugador
	que muere muchas veces con bomba de cadena deja el Workspace saturado de
	NPC, que es la forma mas rapida de matar un servidor.
]]

export type MonsterDefinition = {
	Id: string,

	-- ------------------------------------------------------- TAMANO
	--
	-- `VisualScale` multiplica el MODELO y `HitboxScale` es la
	-- PROPORCION de la hitbox respecto al modelo (0..1). Se separan porque
	-- un enemigo grande que colisiona como el jugador se atraviesa de
	-- forma visible, mientras que uno que colisiona como su modelo visual
	-- se atasca en los pasos y deja de poder rodearse.
	--
	-- Los valores salen de `MonsterScaleRules`, donde vive el contrato de
	-- diseno y los topes. La REGLA es que `VisualScale > 1`: un monstruo
	-- del mismo tamano que el jugador no se lee como amenaza.
	VisualScale: number,
	HitboxScale: number,

	-- Escala que aplica el MUNDO por encima de la del monstruo. Permite
	-- que un bicho sea mayor en un mundo que en otro sin duplicar su
	-- definicion.
	WorldScale: number,
	Name: string,
	Health: number,
	Speed: number,
	Damage: number,
	AttackRange: number,
	DetectionRange: number,
	AggroRadius: number,
	ChaseMultiplier: number,
	AttackCooldown: number,
	XP: number,
	Coins: number,
	MaxAlive: number,
	Color: Color3,
	Material: Enum.Material,

	-- ------------------------------------------------------ IA POR ESTADO
	--
	-- Los campos de arriba son el CONTRATO historico y los siguen leyendo
	-- `CombatMath`, las pruebas y el resto de servicios. Los de abajo son los
	-- que hacen que cada monstruo se comporte distinto.
	--
	-- La velocidad se declara POR ESTADO y no como un numero unico:
	--
	--   PatrolSpeed    lo lento que se pasea cuando no ve a nadie
	--   ChaseSpeed     la persecion sostenida (SIEMPRE < velocidad del jugador)
	--   ChargeSpeed    la carga del ataque, telegrafiada y corta
	--   DetectSpeed    mientras te localiza: vale 0, se queda quieto
	--   WarningSpeed   el telegraph: vale 0, para que puedas reaccionar
	--   RecoverySpeed  la pausa post-ataque
	--
	-- Un `ChaseSpeed` MAYOR que la velocidad del jugador no es un numero
	-- "dificil": es un fallo de diseno. Si el enemigo corre mas rapido de lo
	-- que corres, colocar una bomba deja de ser una decision y pasa a ser una
	-- carrera perdida. `AIService.StateSpeed` acota el valor final, pero el
	-- numero declarado aqui tiene que ser HONESTO.
	PatrolSpeed: number,
	ChaseSpeed: number,
	ChargeSpeed: number,
	DetectSpeed: number,
	WarningSpeed: number,
	RecoverySpeed: number,

	-- Tiempos de la maquina de estados, en segundos.
	DetectTime: number,
	WarningTime: number,
	ChargeDuration: number,
	RecoveryTime: number,

	-- Distancia a la que el monstruo PERDE el objetivo y vuelve a patrulla.
	--
	-- Sin este numero, un monstruo recuerda al jugador para siempre y el mapa
	-- entero se convierte en una persecucion continua sin Decision: el
	-- jugador nunca puede "quedarse tranquilo" y la bomba nunca se puede
	-- colocar sin estar perseguido. El valor por defecto es `AggroRadius`.
	LoseTargetRange: number,

	-- Presion del mundo: fraction de la velocidad del jugador que puede
	-- alcanzar en persecucion (0.55 Forest -> 0.85 Cyber). El tope real lo
	-- aplica `AIService.MaxChaseSpeed`.
	Pressure: number,

	-- Personalidad. Esto es lo que hace que dos monstruos con las mismas
	-- estadisticas NO se jueguen igual.
	StillWhenIdle: boolean,   -- Guardian: se planta y no patrulla
	Vanishes: boolean,        -- Shadow: puede desaparecer y reaparecer
	LeavesBomb: boolean,      -- Bomb Bug / Bomber: su muerte es una amenaza
	AppliesSlow: boolean,     -- Ice Beast: frena al jugador al golpear
	AppliesBurn: boolean,     -- Fire Beast: dano continuos tras el golpe
	BlocksDestroy: boolean,   -- Guardian: el jugador tiene que rodearlo
	ReflectsDamage: boolean,  -- Cyber: castiga al que ataca de cerca
}

-- ============================================================ COMPATIBILIDAD
--
-- Este modulo es DATOS PUROS y se carga en dos sitios: en Roblox (con `Color3`
-- y `Enum` reales) y con el interprete de Luau de las pruebas (donde no
-- existen). Antes de esta guarda, cargar el modulo fuera de Roblox reventaba
-- con `attempt to index nil with 'fromRGB'` en la linea 191.
--
-- No se resuelve poniendo los stubs en la prueba, porque el `require` del
-- interprete standalone ejecuta el modulo en un entorno propio: un global
-- definido en el fichero que llama NO es visible dentro del modulo requerido.
-- Es un detalle del interprete, no de Luau, y es la razon por la que los
-- stubs "antes del require" no funcionam.
--
-- La solucion es que el modulo sea autonomo: si el motor no le da `Color3`,
-- se usa un sustituto que devuelve una cadena. Ninguna prueba compara
-- colores, y el juego real si los tiene.
local Color3 = (Color3 :: any) or {
	fromRGB = function()
		return "Color3"
	end,
}

local Enum = (Enum :: any) or {
	Material = { SmoothPlastic = "SmoothPlastic" },
}

-- `MonsterScaleRules` es logica pura (no toca el motor), asi que se importa
-- con una ruta RELATIVA. Es la unica forma de que funcione en los dos sitios
-- donde se carga este modulo:
--
--   - en Roblox, donde el modulo vive en `ReplicatedStorage/Shared/`;
--   - en el interprete standalone de `luau.exe` que ejecuta las pruebas,
--     donde `script` NO existe y `script.Parent` daria nil.
--
-- Antes se intentaba un `pcall` con `script.Parent`, y por eso la tabla de
-- escalas se quedaba vacia fuera de Roblox: las pruebas veian a todos los
-- bichos con el valor por defecto. `MonsterScale.spec` lo detecta.
local MonsterScaleRules = require("./Libraries/MonsterScaleRules")

-- Definiciones por mundo. El indice es el `Id` que usa el resto del juego.
local DEFINITIONS: { [string]: MonsterDefinition } = {}

-- Velocidad de referencia del jugador (GameConfig.DefaultPlayerSpeed = 16).
--
-- Se repite aqui como CONSTANTE y no como `require` por una razon concreta:
-- `AIService` (que si lee la configuracion) es quien acota los valores en
-- tiempo de ejecucion. Estas cifras son la INTENCION de diseno escrita a
-- mano y tienen que poder leerse de un vistazo. Si las dos se desincronizasen,
-- el tope de `AIService` sigue ganando, y por eso es seguro tenerlas aqui.
local PLAYER_SPEED = 16

--- Declara un monstruo.
---
--- Los valores por defecto son REALES, no marcadores: un monstruo nuevo
--- declarado solo con `Id` y `Health` sigue siendo jugable y legible, porque
--- `PatrolSpeed`/`ChaseSpeed` caen a `Speed` y todos los tiempos tienen
--- default. Un dato a medias no puede producir un NPC con velocidad `nil`.
--- @param def table
local function define(def: { [string]: any })
	local speed = def.Speed or 8

	DEFINITIONS[def.Id] = {
		-- Contrato historico (lo leen CombatMath, pruebas y servicios).
		Id = def.Id,
		Name = def.Name or def.Id,

		-- TAMANO.
		--
		-- `MonsterScaleRules` es la fuente de verdad de estos valores, pero
		-- aqui NO se importa: este modulo esta pensado para cargarse sin
		-- Roblox (las pruebas lo hacen con los stubs de `Color3` de arriba)
		-- y un `require` a `Libraries` anadiria otra dependencia que resolver.
		--
		-- La duplicacion esta vigilada por `MonsterScale.spec`, que
		-- comprueba que ambas tablas COINCIDEN. Si un dia se decide unir
		-- los dos modulos, esa prueba avisa de lo que haya que borrar.
		VisualScale = def.VisualScale or MonsterScaleRules.GetVisualScale(def.Id),
		-- La hitbox es SIEMPRE proporcional al modelo. No se declara a mano
		-- en cada bicho porque es el valor que mas caro sale equivocarse.
		HitboxScale = MonsterScaleRules.GetHitboxRatio(def.Id),
		WorldScale = def.WorldScale or 1,
		Health = def.Health or 30,
		Speed = speed,
		Damage = def.Damage or 8,
		AttackRange = def.AttackRange or 6,
		DetectionRange = def.DetectionRange or 35,
		AggroRadius = def.AggroRadius or 40,
		ChaseMultiplier = def.ChaseMultiplier or 1.2,
		AttackCooldown = def.AttackCooldown or 1.5,
		XP = def.XP or 15,
		Coins = def.Coins or 5,
		MaxAlive = def.MaxAlive or 12,
		Color = def.Color or Color3.fromRGB(140, 190, 140),
		Material = def.Material or Enum.Material.SmoothPlastic,

		-- IA por estado. Los defaults son "se queda quieto mientras decide",
		-- que es justo lo que hace la IA legible.
		PatrolSpeed = def.PatrolSpeed or speed * 0.5,
		ChaseSpeed = def.ChaseSpeed or speed,
		ChargeSpeed = def.ChargeSpeed or speed * 1.25,
		DetectSpeed = 0,
		WarningSpeed = 0,
		RecoverySpeed = def.RecoverySpeed or speed * 0.25,

		DetectTime = def.DetectTime or 0.45,
		WarningTime = def.WarningTime or 0.6,
		ChargeDuration = def.ChargeDuration or 0.5,
		RecoveryTime = def.RecoveryTime or def.AttackCooldown or 1.8,

		-- `LoseTargetRange` cae a `AggroRadius` (y no a un numero fijo) para
		-- que un monstruo con deteccion corta tambien pierda la memoria a esa
		-- misma distancia: son la misma idea de "hasta donde le importa".
		LoseTargetRange = def.LoseTargetRange or def.AggroRadius or 40,

		Pressure = def.Pressure or 0.7,

		-- Personalidad: lo que hace que dos monstruos con las mismas
		-- estadisticas NO se jueguen igual.
		StillWhenIdle = def.StillWhenIdle or false,
		Vanishes = def.Vanishes or false,
		LeavesBomb = def.LeavesBomb or false,
		AppliesSlow = def.AppliesSlow or false,
		AppliesBurn = def.AppliesBurn or false,
		BlocksDestroy = def.BlocksDestroy or false,
		ReflectsDamage = def.ReflectsDamage or false,
	}
end

-- =========================================================================
-- FOREST (nivel 1). Presion 0.55: aqui el jugador DEBE poder huir siempre.
--
-- La idea del bioma: el Forest no mata, ENSENA. Un Slime te empuja, un
-- Bomb Bug te obliga a moverte, un Shadow te obliga a mirar atras. Si un
-- novato muere aqui sin entender por que, el juego fallo su primer minuto,
-- que es el minuto que decide si vuelve.
--
-- Aqui es donde la CURVA DE XP se ajusta (todos dan 5-8): un jugador nuevo
-- sube a nivel 3-4 jugando el Forest entero. Rapido para el numero, lento
-- para lo que significa: en el Forest ya sabes placing, detonar y huir, y eso
-- es lo que cuesta el nivel, no el relleno.
-- =========================================================================

-- SLIME: el empaquetador. Lento, tonska forma de empujar.
define({
	Id = "Slime", Name = "Slime", Health = 30, Speed = 11, Damage = 6,
	XP = 5, Coins = 2, MaxAlive = 10,
	Color = Color3.fromRGB(120, 210, 130),
	-- Patrulla 5.5, persecucion 11: contra un jugador de 16 el jugador gana
	-- la carrera con 5 studs de margen, y puede poner una bomba y salir.
	PatrolSpeed = 5.5, ChaseSpeed = 11, ChargeSpeed = 13,
	DetectionRange = 30, AggroRadius = 38, AttackRange = 6,
	AttackCooldown = 2.0, RecoveryTime = 2.0,
	DetectTime = 0.7, WarningTime = 0.8, ChargeDuration = 0.4,
	Pressure = 0.55,
})

-- BOMB BUG: el que obliga a cambiar de posicion.
--
-- Su amenaza no es su dano (10) sino que al MORIR deja una bomba. Eso obliga
-- a pelear a distancia y no a punoetazo, que es una leccion de juego distinta
-- de la de todos los demas.
define({
	Id = "BombBug", Name = "Bomb Bug", Health = 40, Speed = 12, Damage = 10,
	XP = 8, Coins = 4, MaxAlive = 8,
	Color = Color3.fromRGB(200, 90, 90),
	PatrolSpeed = 6, ChaseSpeed = 12, ChargeSpeed = 15,
	DetectionRange = 38, AggroRadius = 44, AttackRange = 6,
	AttackCooldown = 2.4, RecoveryTime = 2.4,
	DetectTime = 0.5, WarningTime = 0.7, ChargeDuration = 0.5,
	Pressure = 0.6,
	LeavesBomb = true,
})

-- SHADOW: el que se mueve cuando no lo miras.
--
-- Es el primero que usa `Vanishes`. Su dificultad NO es la velocidad (13 de
-- persecucion, claramente mas lento que el jugador) sino la INVISIBILIDAD:
-- cuando desaparece, el jugador tiene que deducir por donde va a salir. Es
-- una habilidad de observacion, no de reflejos, y por eso no necesita ser
-- rapido para ser peligroso.
define({
	Id = "Shadow", Name = "Shadow", Health = 35, Speed = 13, Damage = 9,
	XP = 8, Coins = 4, MaxAlive = 8,
	Color = Color3.fromRGB(70, 70, 100),
	PatrolSpeed = 6.5, ChaseSpeed = 13, ChargeSpeed = 16,
	DetectionRange = 42, AggroRadius = 50, AttackRange = 6.5,
	AttackCooldown = 1.8, RecoveryTime = 1.8,
	DetectTime = 0.4, WarningTime = 0.55, ChargeDuration = 0.45,
	Pressure = 0.62,
	Vanishes = true,
})

-- =========================================================================
-- DESERT (nivel 10). Presion 0.7.
--
-- Aqui aparece el primer enemigo que se acerca a la velocidad del jugador, y
-- por eso es tambien el primero con CARGA TELEGRAFIDA larga: el Hunter corre
-- rapido SOLO durante 0.55 s, avisa 0.9 s antes y tarda 6 s en volver a
-- intentarlo. Es peligroso en el momento en el que el jugador elige, no en el
-- momento en el que no puede hacer nada.
-- =========================================================================

define({
	Id = "Hunter", Name = "Hunter", Health = 70, Speed = 16, Damage = 16,
	XP = 12, Coins = 6, MaxAlive = 8,
	Color = Color3.fromRGB(210, 170, 90),
	PatrolSpeed = 11, ChaseSpeed = 15, ChargeSpeed = 23,
	DetectionRange = 50, AggroRadius = 60, AttackRange = 7,
	AttackCooldown = 6.0, RecoveryTime = 6.0,
	DetectTime = 0.35, WarningTime = 0.9, ChargeDuration = 0.55,
	Pressure = 0.7,
})

-- GUARDIAN: el muro. Lento, mucha vida, no se mueve de su sitio.
--
-- No persigue lejos (AggroRadius 30) y va a 9: se le rodea o se le distrae con
-- una bomba, nunca se le corre. Es el primer enemigo que se resuelve con
-- POSICION y no con dano bruto, que es la leccion que el Desert debe dar antes
-- de la velocidad.
define({
	Id = "Guardian", Name = "Guardian", Health = 140, Speed = 9, Damage = 24,
	XP = 12, Coins = 6, DetectionRange = 26, AggroRadius = 30,
	AttackRange = 8, MaxAlive = 5,
	Color = Color3.fromRGB(160, 130, 80),
	PatrolSpeed = 4.5, ChaseSpeed = 9, ChargeSpeed = 9,
	AttackCooldown = 3.2, RecoveryTime = 3.2,
	DetectTime = 0.6, WarningTime = 1.1, ChargeDuration = 0.3,
	Pressure = 0.7,
	StillWhenIdle = true, BlocksDestroy = true,
})

-- =========================================================================
-- FROZEN TOMY (nivel 20). Presion 0.72.
--
-- El peligro del hielo no es la velocidad: es que te FRENA. `AppliesSlow` hace
-- que un golpe duela y ademas te deje por debajo de la velocidad de persecion
-- del siguiente enemigo, con lo que la bomba deja de ser opcional. Aqui se
-- aprende a REPONER distancia, que es la habilidad que hace falta en Volcano.
-- =========================================================================

define({
	Id = "IceBeast", Name = "Ice Beast", Health = 120, Speed = 12, Damage = 22,
	XP = 12, Coins = 6, DetectionRange = 45, AggroRadius = 52,
	AttackRange = 7, MaxAlive = 8,
	Color = Color3.fromRGB(150, 210, 235),
	PatrolSpeed = 6, ChaseSpeed = 12, ChargeSpeed = 17,
	AttackCooldown = 3.0, RecoveryTime = 3.0,
	DetectTime = 0.45, WarningTime = 0.85, ChargeDuration = 0.5,
	Pressure = 0.72,
	AppliesSlow = true,
})

-- =========================================================================
-- VOLCANO RAGE (nivel 35). Presion 0.78.
--
-- El Fire Beast aplica QUEMADURA: el dano sigue despues del golpe. En un mundo
-- donde el jugador tiene que usar bombas, y por tanto se acerca, obliga a
-- ponerse a salvo antes de cerrar otra vez en vez de hacer una ronda de bombas
-- sin parar.
-- =========================================================================

define({
	Id = "FireBeast", Name = "Fire Beast", Health = 180, Speed = 13, Damage = 30,
	XP = 12, Coins = 6, DetectionRange = 46, AggroRadius = 54,
	AttackRange = 7, MaxAlive = 7,
	Color = Color3.fromRGB(230, 110, 50),
	PatrolSpeed = 6.5, ChaseSpeed = 13, ChargeSpeed = 18,
	AttackCooldown = 3.4, RecoveryTime = 3.4,
	DetectTime = 0.4, WarningTime = 0.8, ChargeDuration = 0.55,
	Pressure = 0.78,
	AppliesBurn = true,
})

-- BOMBER: el que controla el espacio.
--
-- Es el unico con la `ChargeSpeed` mas alta del juego (24 contra un jugador de
-- 16). Y aun asi se puede esquivar, porque avisa 1.4 s, corre 0.5 s y tarda 7 s
-- en repetir. Su `ChaseSpeed` es 12: lento. La dificultad esta en la
-- explosion, no en la carrera, y ese es el orden correcto: primero se aprende
-- a no estar donde explota.
define({
	Id = "BomberMonster", Name = "Bomber", Health = 90, Speed = 12, Damage = 45,
	XP = 12, Coins = 6, DetectionRange = 52, AggroRadius = 60,
	AttackRange = 9, MaxAlive = 5,
	Color = Color3.fromRGB(180, 60, 40),
	PatrolSpeed = 6, ChaseSpeed = 12, ChargeSpeed = 24,
	AttackCooldown = 7.0, RecoveryTime = 7.0,
	DetectTime = 0.4, WarningTime = 1.4, ChargeDuration = 0.5,
	Pressure = 0.78,
	LeavesBomb = true,
})

-- =========================================================================
-- CYBER KESHUSY (nivel 50). Presion 0.85.
--
-- Es el unico mundo donde el enemigo se acerca de verdad a tu velocidad (14 de
-- 15 de persecucion). Por eso el mapa tiene obstaculos y por eso `Pressure`
-- llega a 0.85 sin llegar nunca a 1: en Cyber se gana ROMPIENDO la linea de
-- vision, no corriendo en linea recta. El `ReflectsDamage` cierra el circuito:
-- pegarse al Cyber Stalker para atacarlo es la peor decision posible.
-- =========================================================================

define({
	Id = "CyberStalker", Name = "Cyber Stalker", Health = 260, Speed = 14, Damage = 38,
	XP = 12, Coins = 6, DetectionRange = 55, AggroRadius = 65,
	AttackRange = 8, MaxAlive = 6,
	Color = Color3.fromRGB(80, 230, 230),
	PatrolSpeed = 8, ChaseSpeed = 14, ChargeSpeed = 22,
	AttackCooldown = 4.5, RecoveryTime = 4.5,
	DetectTime = 0.3, WarningTime = 0.7, ChargeDuration = 0.6,
	Pressure = 0.85,
	ReflectsDamage = true,
})

-- =========================================================================
-- REGLAS DE DISENO (se comprueban en pruebas, no a ojo)
-- =========================================================================
--
-- Estas lineas NO son documentacion decorativa:
-- `tests/shared/MonsterBalance.spec.lua` recorre TODOS los monstruos definidos
-- y falla si alguna incumple. Son las reglas del balance convertidas en codigo:
--
--   1. Ningun `ChaseSpeed` supera la velocidad del jugador. Un enemigo que
--      corre mas rapido de lo que corres no es dificil: es un fallo, porque
--      la bomba deja de ser una decision y pasa a ser una carrera perdida.
--   2. La ventana de reaccion antes del primer golpe es
--      `DetectTime + WarningTime >= 0.8` s. Por debajo de eso, el jugador muere
--      sin ver por que, y eso es un fallo de UX, no de balance.
--   3. Entre dos ataques hay al menos 1.5 s (`RecoveryTime`), para que el
--      jugador tenga tiempo a colocar la bomba siguiente.
--   4. Solo la `ChargeSpeed` puede superar la velocidad del jugador, y solo
--      durante `ChargeDuration`, que es <= 0.7 s.
--   5. Todo monstruo declara recompensa (> 0) y `MaxAlive` (> 0).
--
-- `PLAYER_SPEED`, declarado mas arriba, es el 16 de `GameConfig`: si alguien
-- cambia la velocidad del jugador, estas reglas hay que actualizarlas a mano,
-- y por eso estan escritas con el numero a la vista y no escondidas en un
-- coeficiente.

local Definitions = {}

--- Validacion de DISENO de una definicion.
---
--- Devuelve una lista de problemas VACIOS cuando la definicion es jugable, y
--- un texto por cada regla incumplida cuando no lo es.
---
--- Existe DENTRO del modulo de datos y no solo en las pruebas a proposito:
--- estas reglas son un CONTRATO entre el balance y el codice, y un contrato
--- que solo existe durante `npm test` se rompe en cuanto alguien declara un
--- monstruo nuevo sin acordarse de la regla. Con esta funcion, el propio
--- servicio puede avisar en el log de arranque ("GameConfig no tiene
--- DefaultPlayerSpeed, reequilibrando a 16") en vez de fallar en silencio.
--- @param def MonsterDefinition
--- @return { string } problems
local function validate(def: MonsterDefinition): { string }
	local problems: { string } = {}
	local speed = PLAYER_SPEED

	local chase = def.ChaseSpeed
	local charge = def.ChargeSpeed

	if type(chase) == "number" and chase > speed then
		table.insert(problems, ("ChaseSpeed %.1f supera la velocidad del jugador (%.0f)")
			:format(chase, speed))
	end

	if type(charge) == "number" and charge > speed and type(def.ChargeDuration) == "number"
		and def.ChargeDuration > 0.7 then
		table.insert(problems, ("ChargeSpeed %.1f es mayor que el jugador durante %.2f s: "
			.. "una carga larga y mas rapida que el jugador no es esquivable")
			:format(charge, def.ChargeDuration))
	end

	local reaction = (def.DetectTime or 0) + (def.WarningTime or 0)
	if reaction < 0.8 then
		table.insert(problems, ("ventana de reaccion %.2f s: el jugador muere sin ver por que")
			:format(reaction))
	end

	if (def.RecoveryTime or 0) < 1.5 then
		table.insert(problems, ("RecoveryTime %.2f s: no da tiempo a la bomba siguiente")
			:format(def.RecoveryTime or 0))
	end

	if (def.XP or 0) <= 0 or (def.Coins or 0) <= 0 then
		table.insert(problems, "recompensa cero: matarlo no sirve de nada")
	end

	if (def.MaxAlive or 0) <= 0 then
		table.insert(problems, "MaxAlive cero: el monstruo no puede aparecer")
	end

	return problems
end

--- Problemas de diseno de TODAS las definiciones.
---
--- Lo ejecuta el servicio al arrancar y loLoggeduea. Un monstruo con un
--- problema no se borra del juego (seria peor: desapareceria contenido), pero
--- queda AVIADO en el log, que es como se descubre un desbalance antes de que
--- lo reporte un jugador.
--- @return { string }
function Definitions.GetBalanceProblems(): { string }
	local problems: { string } = {}

	for _, id in ipairs(Definitions.GetIds()) do
		local def = DEFINITIONS[id]
		for _, problem in ipairs(validate(def)) do
			table.insert(problems, ("[%s] %s"):format(id, problem))
		end
	end

	return problems
end

--- Definicion de un monstruo, o nil si no existe.
--- @param id string
--- @return MonsterDefinition?
function Definitions.Get(id: string): MonsterDefinition?
	return DEFINITIONS[id]
end

--- Todos los identificadores, en orden estable.
--- @return { string }
function Definitions.GetIds(): { string }
	local ids = {}
	for id in pairs(DEFINITIONS) do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

--- Tabla completa (diagnostico y pruebas).
--- @return { [string]: MonsterDefinition }
function Definitions.GetAll(): { [string]: MonsterDefinition }
	return DEFINITIONS
end

return Definitions