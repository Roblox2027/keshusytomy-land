--!strict
--[[
	PerformanceConfig
	Presupuesto de rendimiento y limites del servidor.

	Regla: los limites viven aqui, nunca como numeros magicos en el
	codigo. Cada limite existe para evitar degradacion por runaway
	(loops, IA, particulas, VFX, remotes).

	Los valores por defecto son conservadores y estan pensados para
	PC, mobile, tablet y gamepad. Ajustar el balance nunca debe
	requerir editar logica de juego.
]]

return {
	-- Muestreo de metricas. Un sample cada N segundos evita
	-- trabajo por frame innecesario.
	MetricsSampleInterval = 5,

	-- Hilos: se usa en lugar de una cadena de wait por frame.
	MonitorInterval = 1,

	-- Heartbeat compartido para logica que si necesita ir por frame
	-- (movimiento suave, camara). Se expone para que lo reutilicen
	-- los sistemas en vez de crear multiples Heartbeat.
	HeartbeatName = "GameplayHeartbeat",

	-- Tareas periodicas
	AutoSaveInterval = 300,
	IdleCheckInterval = 60,

	-- Tiempos maximos de operaciones lentas (advertencias).
	WarnThreshold = {
		ServiceInit = 0.5,
		RemoteHandler = 0.1,
		DatastoreOperation = 8,
		Teleport = 15,
	},

	-- Limites duros del mundo en ejecucion.
	Limits = {
		MaxPlayers = 12,
		-- FASE 9.5 (poblacion masiva): antes 80. Ese tope era el presupuesto
		-- GLOBAL de monstruos vivos, compartido entre la arena, los bosses y la
		-- fauna brainrot de los 5 mundos. Con la fauna expandida (hasta ~80
		-- brainrots por mundo via `BrainrotRules.GroupConfig`), 80 dejaba los
		-- mundos practicamente vacios: `MonsterService.Spawn` rechazaba el
		-- exceso en cuanto el global se llenaba. 200 da margen para que la
		-- poblacion pedida (40-80/mundo) sea real sin degradar el servidor:
		-- sigue siendo un tope DURO, solo que mas honesto con el contenido.
		MaxMonsters = 200,
		MaxBombs = 100,
		MaxExplosions = 100,
		MaxProjectiles = 200,
		MaxVFX = 200,
		MaxParticles = 300,
		MaxTempInstances = 500,
		MaxProjectilesPerPlayer = 20,
		MaxBombsPerPlayer = 5,
		MaxBombsPerWorld = 100,
		MaxExplosionsPerSecond = 30,
		MaxMonstersPerPlayer = 3,
	},

	-- Deteccion de fugas: si se superan estos contadores se avisa.
	LeakWarnings = {
		InstancesPerMinute = 600,
		RemotesPerMinute = 900,
		WarningsPerMinute = 10,
	},

	-- Calidad grafica por defecto. Los clientes pueden bajarla.
	DefaultQuality = {
		ParticlesEnabled = true,
		ShadowsEnabled = true,
		ScreenShakeEnabled = true,
	},
}