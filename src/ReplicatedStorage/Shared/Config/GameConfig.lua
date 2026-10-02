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
	DataVersion = 1,

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
	-- Altura por debajo de la cual se considera caida al vacio. El
	-- servidor reubica al jugador en vez de dejar que muera sin control.
	VoidKillY = -50,

	-- ---------------------------------------------------------------
	-- Rondas
	-- ---------------------------------------------------------------
	-- Jugadores minimos para que la ronda empiece. Con menos, el servidor
	-- espera en `Waiting`. Es 1 para que el vertical slice sea jugable en
	-- solitario desde Studio.
	MinPlayersToStart = 1,

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
	-- Economia (sesion; la persistencia llega en la FASE 15)
	-- ---------------------------------------------------------------
	XPMultiplier = 1,
	CoinMultiplier = 1,
	XPPerKill = 25,
	CoinsPerKill = 10,
	-- Recompensa base por terminar la ronda, para cualquier jugador.
	XPPerRound = 50,
	CoinsPerRound = 25,
}
