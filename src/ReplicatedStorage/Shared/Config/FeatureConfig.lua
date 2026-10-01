--!strict
--[[
	FeatureConfig
	Interruptores de contenido.

	Objetivo: activar o desactivar mundos, modos, eventos o sistemas
	Sin reescribir una sola linea de logica de juego.

	Regla: un flag apagado debe hacer que el sistema NO ejecute el
	codigo de ese contenido, no que el sistema "se rompa".
]]

return {
	-- Mundos (FASE 19 los habilita uno a uno segun readiness)
	ENABLE_FOREST = true,
	ENABLE_DESERT = false,
	ENABLE_ICE = false,
	ENABLE_VOLCANO = false,
	ENABLE_CYBER = false,

	-- Modos de juego
	ENABLE_CLASSIC_PVP = true,
	ENABLE_TEAM_BATTLE = false,
	ENABLE_MONSTER_HUNT = false,
	ENABLE_BOSS_RUSH = false,
	ENABLE_CHAOS = false,
	ENABLE_RANKED = false,
	ENABLE_PRIVATE_SERVERS = false,

	-- Sistemas
	ENABLE_EVENTS = false,
	ENABLE_NEW_SHOP = false,
	ENABLE_TRADING = false,
	ENABLE_ANALYTICS = false,

	-- Monetizacion. En development debe permanecer apagada para
	-- no procesar compras reales contra un entorno de pruebas.
	ENABLE_MONETIZATION = false,

	-- Herramientas internas. Nunca visibles para jugadores normales.
	ENABLE_ADMIN_COMMANDS = true,
}