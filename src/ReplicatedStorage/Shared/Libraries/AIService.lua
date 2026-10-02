--!strict
--[[
	AIService
	LOGICA PURA de movimiento de monstruos. Sin instancias de Roblox.

	POR QUE VIVE EN `Shared/Libraries` Y NO COMO SERVICIO
	----------------------------------------------------
	Un ModuleScript en `ServerScriptService/Services` se registra en el
	ServiceRegistry y se le llama "servicio": tiene `Init`, `Start` y se le
	exige que este VIVO para que el arranque lo de por bueno. Este modulo no
	arranca nada: es una funcion con reglas.

	Si viviera ahi, contaria como el servicio 34/34 arrancado sin que un solo
	monstruo se haya movido nunca, y ademas no se podria probar sin montar
	Roblox. En `Libraries` se ejecuta con el interprete de Luau, asi que un
	caso mal cubierto se ve en la salida del test y no dos minutos despues
	durante un playtest.

	LA IA SIGUE SIENDO DEL SERVIDOR
	--------------------------------
	Pura no significa authority: el servidor es quien llama y quien mueve la
	Parte. El cliente no puede sugerir un destino.
]]

local AI = {}

--- Direccion normalizada de `from` a `to` en el plano XZ.
---
--- Se trabaja en dos dimensiones a proposito: un monstruo que persigue a
--- un jugador en un mapa con dos alturas no debe "subir" por el aire, debe
--- ir al suelo. La Y la decide el mapa.
--- @param from { x: number, z: number }
--- @param to { x: number, z: number }
--- @return number dx
--- @return number dz
function AI.Direction(from: { x: number, z: number }, to: { x: number, z: number }): (number, number)
	local dx = to.x - from.x
	local dz = to.z - from.z
	local magnitude = math.sqrt(dx * dx + dz * dz)

	if magnitude == 0 then
		return 0, 0
	end

	return dx / magnitude, dz / magnitude
end

--- Distancia horizontal entre dos puntos.
--- @param ax number
--- @param az number
--- @param bx number
--- @param bz number
--- @return number
function AI.Distance(ax: number, az: number, bx: number, bz: number): number
	local dx = bx - ax
	local dz = bz - az
	return math.sqrt(dx * dx + dz * dz)
end

--- ?Toca atacar? Un monstruo ataca cuando el objetivo esta a su alcance.
---
--- Se separa de `Step` porque son preguntas distintas con umbrales
--- distintos: se puede PERSEGUIR a alguien a 40 studs y solo poder
--- ATACARLE a 6. Confundir los dos umbrales hacia que los monstruos
--- golpeen desde lejos o que se queden quietos pegados al jugador.
--- @param distance number
--- @param attackRange number
--- @return boolean
function AI.ShouldAttack(distance: number, attackRange: number): boolean
	return distance <= attackRange
end

--- Multiplicador de velocidad del monstruo mientras persigue.
---
--- Sin este escalado, todos los monstruos son igual de rapidos y la
--- dificultad por mundo desaparece. El valor SIEMPRE esta acotado: un
--- multiplicador de 40 por un error de configuracion haria el NPC
--- instantaneamente imparable.
--- @param baseSpeed number
--- @param chaseMultiplier number
--- @return number speed
function AI.ChaseSpeed(baseSpeed: number, chaseMultiplier: number): number
	local MAX_MULTIPLIER = 3

	local multiplier = chaseMultiplier
	if multiplier < 1 then
		multiplier = 1
	elseif multiplier > MAX_MULTIPLIER then
		multiplier = MAX_MULTIPLIER
	end

	return baseSpeed * multiplier
end

--- Un paso de IA: ?mover hacia el objetivo?
---
--- Reglas:
---   - El objetivo debe estar DENTRO del rango de deteccion. Un monstruo
---     no persigue a un jugador a 400 studs: eso haria que los monstruos
---     del mapa entero convergieran en el unico jugador vivo.
---   - Un objetivo encima del monstruo NO produce movimiento: normalizar un
---     vector de distancia cero daria NaN y el NPC se quedaria clavado
---     vibrando en el sitio.
---   - La distancia devuelta es la del PLANO, no la 3D.
--- @param from any
--- @param to any
--- @param detectionRange number
--- @return table step
function AI.Step(from: any, to: any, detectionRange: number)
	local distance = AI.Distance(from.X, from.Z, to.X, to.Z)

	if distance > detectionRange then
		return { Move = false, Direction = { x = 0, y = 0, z = 0 }, Distance = distance }
	end

	if distance <= 0 then
		return { Move = false, Direction = { x = 0, y = 0, z = 0 }, Distance = 0 }
	end

	local dx, dz = AI.Direction(
		{ x = from.X, z = from.Z },
		{ x = to.X, z = to.Z }
	)

	return {
		Move = true,
		Direction = { x = dx, y = 0, z = dz },
		Distance = distance,
	}
end

return AI
