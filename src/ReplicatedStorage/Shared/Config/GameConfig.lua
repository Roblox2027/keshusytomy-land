--!strict
--[[
	GameConfig
	Valores centrales de BALANCE.

	Regla: los sistemas NO deben contener numeros magicos.
	Deben leer de este modulo, de modo que ajustar el balance
	no requiera modificar logica de juego.

	Nota de arquitectura:
	Este modulo NO requiere otros modulos. Cada configuracion de
	dominio (PerformanceConfig, FeatureConfig, etc.) es un archivo
	independiente que se carga por separado. Esto mantiene cada
	configuracion testeable de forma aislada, sin dependencias.

	BUG CORREGIDO (auditoria): el archivo tenia DOS cabeceras
	concatenadas y DOS directivas `--!strict` (lineas 1-10 y 11-25). La
	segunda directiva se ignoraba con el aviso "Comment directive is
	ignored because it is placed after the first non-comment token", de modo
	que la mitad del archivo creia estar en modo estricto y la otra no.
	Los dos bloques describian ademas el mismo modulo con textos distintos.
	Se conserva solo la cabecera vigente.
]]

return {
	GameName = "KeshusyTomy-LanD",
	GameVersion = "0.1.0",
	ContentVersion = "0.1.0",
	DataVersion = 2,

	DebugMode = true,

	-- ---------------------------------------------------------------
	-- Balance
	-- ---------------------------------------------------------------
	RoundDuration = 180,
	CountdownDuration = 5,
	SuddenDeathTime = 30,

	DefaultPlayerSpeed = 16,

	-- ---------------------------------------------------------------
	-- Bombas
	-- ---------------------------------------------------------------
	-- Radio y dano se escalan por nivel mas adelante (FASE 12), asi que
	-- aqui solo viven los valores BASE que usa el servidor.
	DefaultBombRadius = 24,
	DefaultBombFuseTime = 3,
	-- El dano base DEBE superar la vida por defecto de un jugador (100).
	-- Con 45 una bomba no mataba de un golpe, asi que el PvP del vertical
	-- slice nunca mataba a nadie y no habia ronda que terminara.
	DefaultBombDamage = 120,
	-- Tiempo entre bombas del mismo jugador. El servidor lo aplica:
	-- sin esto, un cliente que spamea el remoto coloca bombas sin limite.
	BombCooldown = 1.5,
	-- Bombas que un jugador puede tener VIVAS a la vez.
	--
	-- MEDIDO EN PLAY (no deducido): el sintoma reportado era "solo puedo
	-- colocar una bomba". La causa NO era este limite (que valia 5), sino un
	-- cerrojo en el cliente que se cerraba con la primera peticion y no se
	-- abria jamas. El limite de aqui es el de DISENO, y es 2 a proposito:
	--
	--   Bomba A -> t=0
	--   Bomba B -> t=1.5   (el enfriamiento ya ha pasado)
	--   A explota -> t=3
	--
	-- Dos bombas es lo que convierte la bomba en una herramienta tactica: se
	-- coloca una para demarcar la huida y otra para cerrar la retirada. Con
	-- una sola no hay decision que tomar; con cinco el jugador llena la arena
	-- y pierde el sentido de la explosion.
	--
	-- Es la CAPACIDAD BASE. Los powerups pueden subirla (ver `PowerupService`),
	-- y el servidor sigue siendo quien la aplica: el cliente nunca concede.
	BombCapacity = 2,
	-- Distancia maxima entre el personaje y la bomba. Evita colocar
	-- bombas a distancia desde cualquier punto del mapa.
	BombPlacementRange = 18,
	-- Radio dentro del cual una explosion hace detonar las bombas
	-- cercanas. Es lo que convierte una bomba en una cadena.
	ChainReactionRadius = 12,
	-- Segundos que tarda la bomba en detonar por distancia respecto a
	-- la bomba que la disparo. Evita que la cadena sea instantanea.
	ChainReactionDelayPerStud = 0.012,
	-- Tope de eslabones de una misma cadena. Sin este limite, un
	-- jugador que llene la arena de bombas genera miles de detonaciones
	-- y tumba el servidor.
	MaxChainDepth = 6,

	-- ---------------------------------------------------------------
	-- Destruccion
	-- ---------------------------------------------------------------
	-- Los bloques destructibles se identifican por el prefijo de nombre
	-- `Block_` (contrato con tools/generate-project.js). Cada explosion
	-- aplica este dano por bloque dentro del radio.
	--
	-- Vida de un bloque. DEBE ser mayor que el dano de una sola bomba
	-- (`DefaultBombDamage * BlockDamageScale`), o una unica explosion
	-- borraria el bloque entero. Con 60 el calculo daba 60 y la arena
	-- desaparecia de un solo impacto: lo detecto `Destruction.spec`.
	-- Con 100 hacen falta 2 bombas, que es lo que hace el mapa jugable.
	BlockHealth = 100,
	-- Fraccion del dano de la explosion que recibe cada bloque. Por
	-- debajo de 1, una bomba no borra la estructura entera de un golpe.
	BlockDamageScale = 0.5,

	-- ---------------------------------------------------------------
	-- Reaparicion de bloques
	-- ---------------------------------------------------------------
	-- RANGO, no un numero fijo. Un bloque que reaparece siempre a los 8 s
	-- hace que la arena tenga un ritmo artificial y el jugador memorice un
	-- reloj en vez de jugar. Con un rango, cada destruccion es distinta.
	--
	-- El SERVIDOR SORTEA el valor con su propia semilla y lo guarda en el
	-- bloque. El cliente no propone ningun instante: si lo hiciera, podria
	-- pedir que un bloque reapareciera ya, antes de tiempo.
	BlockRespawnMin = 8,
	BlockRespawnMax = 25,

	-- Cuanto se REINTENTA un respawn rechazado por un motivo externo (por
	-- ejemplo un bloque apoyado encima). Sin este margen, el bloque se
	-- queda destruido para siempre hasta el fin de ronda.
	BlockRespawnRetryDelay = 3,

	-- Margen alrededor de un bloque dentro del cual una entidad cuenta
	-- como "ocupando la posicion". Es un poco MAS que el tope de tamano de
	-- un monstruo para que un Guardian grande tambien bloquee el sitio.
	BlockSpawnClearance = 6,

	-- ---------------------------------------------------------------
	-- Caida al vacio y limite del mundo
	--
	-- P0 DEFINITIVO. El borde del mundo es el FINAL DEL TERRENO: se corre,
	-- se acaba el suelo, se cae, se muere y se reaparece. Lo que se elimina
	-- es el "rescate": antes, `SpawnService` teletransportaba al jugador de
	-- vuelta al spawn al bajar de `VoidKillY`, y con eso la caida no era una
	-- caida sino un teletransporte punitive que ademas saltava el ciclo de
	-- muerte y la reaparicion.
	--
	-- La consecuencia de este cambio es deliberada y es la regla del juego:
	-- MORIR NO BLOQUEA EL JUEGO. Caer mata, y al morir el jugador reaparece
	-- con normalidad, puede usar el portal y puede volver a entrar al mundo.

	-- Altura por debajo de la cual se considera CAIDA. El servidor la valida
	-- y pone `Humanoid.Health = 0`: la muerte la decide el motor, no una
	-- comprobacion del cliente.
	--
	-- Antes este valor se llamaba `VoidKillY` pero NO mataba a nadie: solo
	-- teletransportaba. El nombre nuevo dice lo que hace.
	FallDeathY = -50,

	-- Cada cuanto se comprueba la caida. El vacio no genera eventos, asi que
	-- la vigilancia es por sondeo; un segundo es suficiente porque el jugador
	-- cae a 196 studs por segundo y desde la cota mas alta del mundo (~30)
	-- hasta -50 hay mas de medio segundo de margen.
	FallCheckInterval = 1,

	-- Tiempo que un jugador puede seguir FUERA del area jugable sin que se le
	-- considere perdido. Es una red de seguridad, no un muro: si el suelo
	-- faltara bajo sus pies (por ejemplo un fallo de fisica), el jugador
	-- quedaria flotando fuera del mapa para siempre sin poder volver. Pasado
	-- este tiempo sin haber vuelto a entrar, cae y muere por la regla normal.
	--
	-- No hay teletransporte de vuelta en ningun caso: la salida de esta
	-- situacion es siempre la caida y la muerte.
	OutOfBoundsGraceSeconds = 8,

	-- Altura por debajo de la cual se considera que el jugador esta en el
	-- VACIO y no simplemente en el lobby.
	--
	-- La distincion importa porque el lobby esta en el origen, que no esta
	-- dentro de ninguna caja de mundo: un jugador del lobby esta "fuera de todo
	-- mundo" y, sin este umbral, la red de seguridad lo mataria. Por debajo de
	-- esta cota no hay ningun suelo de juego, y ahi la unica salida es caer.
	OutOfBoundsY = -20,

	-- ---------------------------------------------------------------
	-- Rondas
	-- ---------------------------------------------------------------
	-- Jugadores minimos para que la ronda empiece. Con menos, el servidor
	-- espera en `Waiting`. Es 1 para que el vertical slice sea jugable en
	-- solitario desde Studio.
	MinPlayersToStart = 1,

	-- Duracion de los estados de TRANSICION.
	--
	-- BUG CORREGIDO (FASE 0, P0): estos cuatro valores estaban
	-- HARDCODED en `RoundService.GetDuration` (3, 3, 4, 4). Con un numero
	-- magico, un ciclo de ronda completo no se puede ejecutar en un tiempo
	-- razonable (7 s de transicion + 180 s de `Playing` por ronda), y sin
	-- poder ejecutar ciclos no hay forma de PROBAR que la ronda se repite.
	--
	-- Ahora son balance declarado, igual que `RoundDuration`. Se pueden
	-- bajar en un playtest para certificar 100 ciclos sin esperar horas, y
	-- los valores de produccion siguen siendo los de siempre.
	RoundStartingDuration = 3,
	RoundEndingDuration = 3,
	RewardsDuration = 4,
	ReturningToLobbyDuration = 4,

	-- Cada cuanto sondea el ciclo de ronda.
	--
	-- POR QUE NO SE DUERME EL PLAZO ENTERO (causa raiz del P0):
	-- el bucle hacia `task.wait(remaining)` con el `remaining` del estado
	-- en el que entraba. Si otro hilo cambiaba el estado a mitad (por
	-- ejemplo `PlayerService` al morir el ultimo vivo), el estado de la
	-- maquina avanzaba pero el bucle seguia dormido con el plazo del estado
	-- ANTERIOR: hasta 180 s de `Playing`. Sintoma medido en runtime:
	-- `state = RoundEnding`, `remaining = 0`, heartbeat congelado durante
	-- 155 s, sin un solo error en el Output.
	--
	-- Con sondeo en rebanadas, una transicion externa se ve en menos de
	-- `RoundTickInterval` segundos. No es mas preciso: el coste es una
	-- iteracion cada 0.25 s, que no es nada para un servidor.
	RoundTickInterval = 0.25,

	-- ---------------------------------------------------------------
	-- Ciclo de vida del jugador
	-- ---------------------------------------------------------------
	-- Tiempo que tarda Roblox en reponer el personaje tras morir.
	RespawnTime = 3,
	-- Invulnerabilidad al entrar en la arena: sin esto, una bomba que
	-- explota en el instante del teletransporte mata al jugador antes
	-- de que pueda moverse.
	SpawnProtectionTime = 2.5,
	-- El dano se multiplica en muerte subita. Es el unico multiplicador
	-- de combate: la muerte subita tiene que HERIR de verdad.
	SuddenDeathDamageMultiplier = 1.5,

	-- ---------------------------------------------------------------
	-- Portales (vertical slice 1: lobby -> mundo)
	-- ---------------------------------------------------------------
	-- Segundos entre dos intentos de viaje del mismo jugador.
	--
	-- El servidor (`PortalService.PORTAL_COOLDOWN`) impone 3 s como
	-- autoridad. Este valor es el equivalente en el cliente y coincide con
	-- el del servidor a proposito: si el cliente permitiera mas rapido, cada
	-- intento llega y se rechaza, y el jugador ve un error por haber
	-- pulsado dos veces. Que coincidan no concede nada: el servidor sigue
	-- validando por su cuenta.
	PortalCooldown = 3,
	-- Distancia a la que el cliente OFRECE la interaccion.
	--
	-- Es MAYOR que `PortalService.MAX_INTERACTION_DISTANCE` (14 studs) a
	-- proposito: el boton aparece antes de poder usarse, de modo que el
	-- jugador nunca pulsa dentro del rango del servidor y recibe un
	-- rechazo sin motivo claro. El cliente noDECIDE nada con esto.
	PortalInteractionRange = 20,

	-- ---------------------------------------------------------------
	-- Progresion
	-- ---------------------------------------------------------------
	-- XP necesaria por nivel. El nivel NO tiene tope artificial:
	-- la curva es `XP_PER_LEVEL * (nivel - 1)^LevelCurveExponent`.
	XPPerLevel = 100,
	LevelCurveExponent = 1.35,
	-- Limite duro solo para evitar que un valor corrupto (por ejemplo
	-- de una migracion) produzca un nivel de billions y rompa la UI.
	MaxLevel = 9999,

	-- ---------------------------------------------------------------
	-- Keshusy Core (el corazon del lobby)
	-- --------------------------------------------------------------
	-- Carga maxima del nucleo, en unidades de energia. Alcanzarla
	-- dispara la activacion.
	CoreMaxCharge = 100,
	-- Cuanta energia aporta cada fragmento. El fragmento lo suelta un
	-- jugador interactuando con el nucleo; la decision es del servidor.
	CoreChargePerFragment = 10,
	-- Segundos que dura la secuencia de activacion. Durante ella el
	-- nucleo no admite mas fragmentos: evita Carrera entre jugadores.
	CoreActivationDuration = 6,
	-- Cada cuanto se actualiza el estado del nucleo hacia los clientes.
	-- 0.2 s son 5 Hz: suficiente para una barra y muy barato.
	CoreBroadcastInterval = 0.2,
	-- Maximo de fragmentos que un mismo jugador puede aportar antes de
	-- que el nucleo los responda con "ya has AYUDADO lo suficiente".
	-- Es una proteccion contra el relleno de barraInstantaneo.
	CoreFragmentsPerPlayer = 20,
	-- Segundos de recarga para el jugador tras aportar un fragmento.
	CoreFragmentCooldown = 0.5,
	-- Sobrepasar la carga maxima NO da unfragmento extra: el nucleo
	-- entra en sobrecarga y pierde carga hasta volver a estar estable.
	CoreOverloadDrainPerSecond = 15,
	-- Drenaje lento del nucleo ya activado. Sin esto se quedaria en
	-- "Active" para siempre y no podria volver a cargarse.
	CoreCorePassiveDrainPerSecond = 5,
	-- ---------------------------------------------------------------
	-- Economia y progresion (autoridad del servidor)
	-- ---------------------------------------------------------------
	XPMultiplier = 1,
	CoinMultiplier = 1,
	XPPerKill = 25,
	CoinsPerKill = 10,
	-- Recompensa base por terminar la ronda, para cualquier jugador.
	XPPerRound = 50,
	CoinsPerRound = 25,

	-- Recompensa por SUBIR de nivel. Es una FUNCION del nivel, no una
	-- tabla guardada: si se guardase, un jugador con un perfil viejo
	-- conservaria para siempre los valores de cuando subio y cambiar el
	-- balance no tendria efecto en el mundo real.
	--
	-- El nivel 1 NO se premia: es el estado inicial, no un logro. El
	-- primero que se paga es el 2, con `LevelRewardBaseCoins`.
	LevelRewardBaseCoins = 100,
	LevelRewardCoinsPerLevel = 50,

	-- ---------------------------------------------------------------
	-- Persistencia
	-- ---------------------------------------------------------------
	--
	-- El NOMBRE del DataStore no se registra en ningun log: es una
	-- credencial. Solo se usa para abrirlo.
	DataStoreName = "KeshusyTomyLandProfile_v1",

	-- Cada cuanto se guardan los perfiles que tengan cambios pendientes.
	--
	-- 60 s es el punto de equilibrio: bastante corto para que un cierre
	-- abrupto pierda como mucho el ultimo minuto de juego, bastante largo
	-- para no agotar el presupuesto de escrituras. No se guarda en cada
	-- cambio: eso es throttle garantizado.
	AutosaveInterval = 60,

	-- Intentos por operacion de DataStore, con espera creciente entre
	-- ellos. El DataStore falla por throttling mas a menudo de lo que
	-- parece, y un solo intento convierte un pico de trafico en perdida
	-- de progreso.
	DataStoreRetries = 3,

	-- Tiempo que un bloqueo de sesion aguanta sin renovarse.
	--
	-- Si un servidor muere de golpe, su bloqueo sigue puesto hasta que
	-- pasa este tiempo. Es una decision de DISENO, no un parametro
	-- tecnico: define cuanto tarda un cierre abrupto en liberarse solo, y
	-- por tanto cuanto espera un jugador que entra en otro servidor.
	LockTtlSeconds = 120,
}
