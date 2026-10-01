--!strict
--[[
	GameConfig
	Valores centrales de configuracion.

	Regla: los sistemas NO deben contener numeros magicos.
	Deben leer de este modulo, de modo que ajustar el balance
	no requiera modificar logica de juego.
]]

return {
	GameName = "KeshusyTomy-LanD",
	GameVersion = "0.1.0",
	ContentVersion = "0.1.0",
	DataVersion = 1,

	DebugMode = true,

	MaxPlayers = 12,

	RoundDuration = 180,
	CountdownDuration = 5,
	SuddenDeathTime = 30,

	DefaultPlayerSpeed = 16,

	DefaultBombRadius = 2,
	DefaultBombFuseTime = 3,

	XPMultiplier = 1,
	CoinMultiplier = 1,

	MaxMonsters = 30,
	MaxBombs = 100,
	MaxExplosions = 100,
	MaxVFX = 200,
}
