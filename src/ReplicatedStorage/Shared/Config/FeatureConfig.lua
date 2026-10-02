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

	-- Keshusy Core (el corazon del lobby)
	ENABLE_CORE = true,

	-- Modos de juego
	ENABLE_CLASSIC_PVP = true,
	ENABLE_TEAM_BATTLE = false,
	-- PvE: monstruos en la arena. Con esto apagado, `MonsterService` arranca
	-- pero no genera nada, y "no aparecen monstruos" es una decision de
	-- contenido, no un fallo del spawn.
	ENABLE_MONSTER_HUNT = true,
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

	-- Reproductor de pruebas del cliente (FASE 1 REAL).
	--
	-- Es la pieza que permite certificar `CLIENT INPUT PATH VERIFIED`
	-- cuando el MCP no puede enviar teclas al cliente. Apagado por
	-- defecto en produccion: con esto encendido, el servidor puede
	-- pedirle al cliente que ejecute una intencion de jugador.
	--
	-- Lo que el reproductor NO puede hacer (y por eso no es un atajo):
	-- llamar a `BombService`, a `PortalService` o a cualquier servicio.
	-- Solo invoca controllers del cliente, que a su vez usan los
	-- remotos reales. Por tanto el camino probado es el del jugador.
	ENABLE_CLIENT_TEST_DRIVER = false,
}