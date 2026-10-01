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

	DefaultBombRadius = 2,
	DefaultBombFuseTime = 3,

	XPMultiplier = 1,
	CoinMultiplier = 1,
}
