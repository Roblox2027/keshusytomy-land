--!strict
--[[
	GameConfig
	Valores centrales de configuracion.

	Regla: los sistemas NO deben contener numeros magicos.
	Deben leer de este modulo, de modo que ajustar el balance
	no requiera modificar logica de juego.
]]

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

	-- ---------------------------------------------------------------
	-- Destruccion
	-- ---------------------------------------------------------------
	-- Los bloques destructibles se identifican por el prefijo de nombre
	-- `Block_` (contrato con tools/generate-project.js). Cada explosion
	-- aplica este dano por bloque dentro del radio.
	BlockHealth = 60,
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
