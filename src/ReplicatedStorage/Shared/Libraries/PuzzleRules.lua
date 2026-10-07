--!strict
--[[
	PuzzleRules
	PUZZLES CORTOS y secretos cooperativos (MASTER MISSION V2 - FASES 13/14).

	POR QUE EXISTE
	--------------
	No habia ningun puzzle en el juego. El primero es el "doble
	interruptor": dos pedestales alejados que hay que activar casi a la
	vez. Dos jugadores lo hacen facil; UN jugador puede hacerlo corriendo
	(y el dash del combate V2 ayuda), porque la ventana es generosa a
	proposito:

	  NADA del progreso principal depende de encontrar otro jugador.

	QUE VIVE AQUI
	-------------
	La ventana, el cooldown y la recompensa: puro y probado. El servicio
	(`PuzzleService`) aporta los pedestales, los prompts y el reloj.

	LA REGLA DE ANTI-GRANJA
	-----------------------
	Completado, el puzzle entra en enfriamiento LARGO por mundo: un puzzle
	que se puede repetir sin pausa es una fuente de monedas infinita con
	pasos extra.
]]

local Rules = {}

--- Segundos entre la primera y la segunda activacion.
---
--- 8 s: dos jugadores lo hacen sin hablar; uno solo necesita correr (o
--- dashear) entre los dos pedestales. Menos seria obligar a tener
--- companero; mas lo convertiria en "pulsa los dos cuando quieras", que
-- no es un puzzle.
Rules.WindowSeconds = 8

--- Segundos de enfriamiento del puzzle por mundo tras completarse.
Rules.CooldownSeconds = 300

--- Recompensa al completarlo (monedas; el descubrimiento es lo que
--- importa, la moneda es el cierre).
Rules.RewardCoins = 120

--- La ventana esta ABIERTA entre la primera activacion y ahora.
--- @param firstAt any instante de la primera activacion (nil = no hay)
--- @param now any
--- @return boolean
function Rules.IsWindowOpen(firstAt: any, now: any): boolean
	local first = tonumber(firstAt)
	local t = tonumber(now)

	if not first or not t or t ~= t then
		return false
	end

	return (t - first) <= Rules.WindowSeconds
end

--- El puzzle puede dispararse AHORA (cooldown cumplido).
--- @param completedAt any instante del ultimo completado (nil = nunca)
--- @param now any
--- @return boolean
function Rules.IsOffCooldown(completedAt: any, now: any): boolean
	local done = tonumber(completedAt)
	local t = tonumber(now)

	if not done or not t or t ~= t then
		return true
	end

	return (t - done) >= Rules.CooldownSeconds
end

return Rules
