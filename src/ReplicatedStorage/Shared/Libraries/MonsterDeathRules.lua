--!strict
--[[
	MonsterDeathRules
	LA MAQUINA DE ESTADOS DE LA MUERTE de un enemigo.

	EL BUG QUE RESUELVE
	-------------------
	"Health = 0 pero el monstruo sigue vivo, persiguiendo y golpeando".

	La causa no era el dano: `ApplyDamageToMonster` aplicaba bien. Era que
	la muerte NO TENIA ESTADO. Habia un unico `record.Dead`, que se
	ponia a true dentro del manejador de `Humanoid.Died` y nada mas. Eso
	deja tres agujeros reales:

	1. Si `Died` no se dispara (por el motivo que sea), no hay nadie que
	   lo compruebe: el enemigo se queda con 0 de vida persiguiendo.
	2. `LastDamageSource` se escribia DESPUES de `TakeDamage`, asi que en
	   el golpe mortal el manejador leia al asesino ANTERIOR: la muerte se
	   procesaba, pero sin recompensa, o con el premio de otro.
	3. Si la animacion de muerte fallaba, el modelo se quedaba en el mapa
	   para siempre, y `record.Dead` era lo unico que lo separaba de la
	   lista de vivos.

	LA MASCARA
	----------
	    Alive  ->  Dying  ->  Dead  ->  Cleaned

	- `Alive`   : vivo. Actua, persigue, golpea, recibe dano.
	- `Dying`   : muerte YA decidida. No actua, no persigue, no recibe
	              dano y la recompensa esta comprometida.
	- `Dead`    : la recompensa se ha pagado UNA vez.
	- `Cleaned` : modelo liberado. No queda nada en el mapa.

	La transicion critica es la primera, y por eso es ATOMICA: `EnterDying`
	es la unica que concede el derecho a pagar, y solo concede si el estado
	era `Alive`. Dos llamadas simultaneas (una explosion en cadena y un
	bloque reventado en el mismo frame) producen una sola recompensa.

	POR QUE ES UN MODULO PURO
	-------------------------
	La regla "muere una sola vez" es un CONTRATO, y un contrato que solo
	existe dentro de un servicio se rompe en cuanto alguien anade un
	segundo camino de dano. Aqui se puede probar sin motor.
]]

local Rules = {}

--- Estados de la mascara de muerte.
Rules.States = {
	Alive = "Alive",
	Dying = "Dying",
	Dead = "Dead",
	Cleaned = "Cleaned",
}

--- Orden de la mascara. Se usa para comprobar que una transicion avanza
--- y nunca retrocede.
Rules.Order = {
	Rules.States.Alive,
	Rules.States.Dying,
	Rules.States.Dead,
	Rules.States.Cleaned,
}

--- Posicion de un estado en la mascara.
--- @param state string?
--- @return number index
local function indexOf(state: string?): number
	for index, candidate in ipairs(Rules.Order) do
		if candidate == state then
			return index
		end
	end

	return 0
end

--- El estado es conocido por la mascara.
--- @param state any
--- @return boolean
function Rules.IsKnown(state: any): boolean
	return indexOf(state) > 0
end

--- El enemigo puede actuar: moverse, perseguir, golpear y receber dano.
---
-- Es la unica pregunta que la IA y el sistema de dano tienen que hacer.
-- Responder "si" a un `Dying` es exactamente el sintoma reportado.
--- @param state string?
--- @return boolean
function Rules.CanAct(state: string?): boolean
	return state == Rules.States.Alive
end

--- Entra en `Dying`. Devuelve el estado NUEVO, o nil si ya estaba muerto.
---
-- Es la transicion que concede el derecho a pagar, y por eso es la
-- idempotente: la segunda llamada devuelve nil y no paga.
--- @param state string?
--- @return string? nextState nil si la muerte ya estaba decidida
function Rules.EnterDying(state: string?): string?
	if not Rules.CanAct(state) then
		return nil
	end

	return Rules.States.Dying
end

--- Marca la recompensa como pagada. Devuelve true solo la primera vez.
--- @param rewarded boolean?
--- @return boolean shouldPay
function Rules.ClaimReward(rewarded: boolean?): boolean
	return rewarded ~= true
end

--- El estado siguiente de la mascara, o nil si ya estaba en el ultimo.
--- @param state string?
--- @return string?
function Rules.Next(state: string?): string?
	local index = indexOf(state)

	if index <= 0 or index >= #Rules.Order then
		return nil
	end

	return Rules.Order[index + 1]
end

--- El estado siguiente es valido para `state`: avanza uno y solo uno.
--- @param from string?
--- @param to string?
--- @return boolean
function Rules.CanTransition(from: string?, to: string?): boolean
	local a, b = indexOf(from), indexOf(to)

	return a > 0 and b == a + 1
end

--- El enemigo ya no ocupa un sitio en el mundo.
--- @param state string?
--- @return boolean
function Rules.IsGone(state: string?): boolean
	return not Rules.CanAct(state)
end

return Rules