--!strict
--[[
	AudioPool
	Logica PURA del prestamo de sonidos. Sin Roblox, sin estado global.

	POR QUE ESTA SEPARADO DEL CONTROLLER
	------------------------------------
	`AudioController` necesita `SoundService` e `Instance.new`, que no
	existen fuera de Roblox. Pero la parte que de verdad tiene una relacion
	con el rendimiento es una cuenta: cual de los sonidos libres se presta
	despues, y cuando hay que reciclar uno que ya suena.

	Esa cuenta va aqui, en un modulo que `luau.exe` puede ejecutar de
	verdad. Es la MISMA separacion que ya usa el proyecto con
	`CoreRules` (reglas del nucleo) y `CombatMath` (calculo de combate):
	la regla se prueba sin motor, y el servicio solo la aplica.

	EL FALLO QUE EVITA
	------------------
	Sin tope, una cadena de explosiones abre un `Sound` por detonacion. Con
	`MaxExplosionsPerSecond = 30`, el cliente llega a manejar cientos de
	sonidos simultaneos y se atasca. Aqui el numero de ranuras esta
	ACOTADO por construccion y `Take` devuelve siempre un indice valido.
]]

local AudioPool = {}

export type PoolStats = {
	Requested: number,
	Played: number,
	Recycled: number,
}

--- Crea un conjunto de prestamo de `size` ranuras.
---
--- `size` se acota a 1 como minimo: un conjunto de cero ranuras haria que
--- `Take` no tuviera nada que devolver, y el controller tendria que
--- comprobar `nil` en cada llamada.
--- @param size number numero de ranuras
--- @return { size: number, index: number, stats: PoolStats }
function AudioPool.new(size: number)
	local bounded = if size < 1 then 1 else math.floor(size)

	return {
		size = bounded,
		-- Indice de la ultima ranura prestada. Empieza en 0 para que el
		-- primer `Take` devuelva la primera ranura, no la ultima.
		index = 0,
		stats = {
			Requested = 0,
			Played = 0,
			Recycled = 0,
		},
	}
end

--- Presta la siguiente ranura del conjunto.
---
--- Es CIRCULAR: al llegar al final vuelve a la primera. Asi el conjunto
--- se llena siempre por igual y el sonido mas antiguo es el primero en
--- reciclarse, que es justo el que ya ha terminado de sonar.
---
--- @param pool { size: number, index: number, stats: PoolStats }
--- @return number index indice de la ranura prestada (siempre >= 1)
--- @return boolean recycled true si la ranura ya estaba ocupada
function AudioPool.Take(pool: { size: number, index: number, stats: PoolStats }): (number, boolean)
	pool.stats.Requested += 1

	-- `IsPlaying` se consulta al controller: aqui solo se decide el
	-- indice. Separar "cual ranura" de "esta ocupada" es lo que permite
	-- probar el reparto sin saber nada de sonidos.
	local recycled = pool.index ~= 0
	if recycled then
		pool.stats.Recycled += 1
	end

	pool.index = (pool.index % pool.size) + 1
	return pool.index, recycled
end

--- Registra que una ranura se ha reproducido de verdad.
--- @param pool { size: number, index: number, stats: PoolStats }
function AudioPool.MarkPlayed(pool: { size: number, index: number, stats: PoolStats })
	pool.stats.Played += 1
end

--- Reinicia el conjunto. Se usa al apagar el controller.
--- @param pool { size: number, index: number, stats: PoolStats }
function AudioPool.Reset(pool: { size: number, index: number, stats: PoolStats })
	pool.index = 0
	pool.stats.Requested = 0
	pool.stats.Played = 0
	pool.stats.Recycled = 0
end

return AudioPool