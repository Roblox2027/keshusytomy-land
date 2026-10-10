--!strict
--[[
	CombatRules
	COMBATE V2: ataque rapido, dash y habilidad (MASTER MISSION V2 - FASE 8/9).

	POR QUE EXISTE
	--------------
	Hasta aqui el jugador tenia UNA herramienta: la bomba. Todos los
	enfrentamientos se resolvian igual a los cinco minutos. El combate V2
	anade tres decisiones con ritmo propio:

	  - ATAQUE RAPIDO: cuerpo a cuerpo, cooldown corto, dano base.
	  - DASH: impulso con invulnerabilidad breve; la decision defensiva.
	  - HABILIDAD: golpe en area alrededor, cooldown largo; la decision
	    de "cuando vale la pena".

	QUE VIVE AQUI
	-------------
	Toda la aritmetica: cooldowns, alcance, arco, ventana de combo y dano
	por golpe. Es puro y se prueba sin motor. El servicio (`CombatService`)
	aporta la lectura de personajes y la aplicacion del dano, que es lo que
	no se puede probar en local.

	LA REGLA DE SPAM
	----------------
	La ventana de combo es lo que impide el machacabotones: encadenar tres
	golpes con ritmo premia con un golpe especial, pero el CUARTO golpe
	rapido no es otro especial: la cadena se reinicia. Recompensar el
	ritmo sin obligar a machacar es la linea entre "combo" y "spam".
]]

local Rules = {}

-- ---------------------------------------------------------------------------
-- CONFIGURACION
-- ---------------------------------------------------------------------------

--- Ataque rapido cuerpo a cuerpo.
Rules.Melee = {
	-- Segundos entre golpes. 0.45 s es rapido de verdad sin permitir
	-- que una rafaga de clics vacie la vida de un enemigo en un frame.
	Cooldown = 0.45,
	-- Alcance del golpe en studs. Cuerpo a cuerpo: mas que el brazo del
	-- personaje (para que SE SIENTA) y menos que una bomba (para que la
	-- bomba siga siendo la opcion de distancia).
	Range = 9,
	-- Producto punto minimo entre la mirada y la victima: el golpe
	-- alcanza lo que esta DELANTE, no lo que rodea. 0.35 ~ 70 grados.
	MinDot = 0.35,
	-- Dano base del golpe. Subido de 24 a 34 para que el cuerpo a cuerpo sea
	-- una decision de peso y no un rasguo: tres golpes (sin combo) tumban a un
	-- enemigo de 100 de vida, asi que plantarse a pegar es arriesgado y por
	-- tanto divertido. Se mantiene por debajo de 40 (contrato de
	-- `CombatRules.spec`) para no desplazar a la bomba como herramienta de dano.
	Damage = 34,
}

--- Dash: impulso con invulnerabilidad breve.
Rules.Dash = {
	Cooldown = 3,
	-- Velocidad del impulso en studs/s durante el golpe de dash.
	Impulse = 60,
	-- Invulnerabilidad breve: la ventana de esquiva de verdad. Mas de
	-- medio segundo convertiria el dash en un boton de "no me pegues".
	InvulnerabilitySeconds = 0.35,
}

--- Habilidad: golpe en area alrededor del jugador.
Rules.Ability = {
	Cooldown = 8,
	Range = 14,
	-- El area es circular: no hay direccion que apuntar. MinDot -1
	-- significa "cualquier direccion" en la prueba de arco.
	MinDot = -1,
	Damage = 42,
}

--- Combo: el tercer golpe encadenado es el especial.
Rules.Combo = {
	-- Segundos maximos entre golpes para no romper la cadena. Menos de
	-- un segundo exigiria machacar; mas de dos haria la cadena eterna.
	Window = 1.4,
	-- Golpe que dispara el especial (3 = golpe, golpe, ESPECIAL).
	FinisherAt = 3,
	-- Multiplicador del especial. Subido de 1.8 a 2.0: encadenar el combo debe
	-- pagar con un remate que se SIENTA (floor(34 * 2.0) = 68), no con un golpe
	-- apenas mayor que el base. El contrato solo exige que supere al golpe base.
	FinisherMultiplier = 2.0,
}

-- ---------------------------------------------------------------------------
-- ARITMETICA
-- ---------------------------------------------------------------------------

--- La accion sale del cooldown en este instante.
--- @param lastAt any instante del ultimo uso (nil = nunca)
--- @param cooldown any
--- @param now any
--- @return boolean
function Rules.IsReady(lastAt: any, cooldown: any, now: any): boolean
	local t = tonumber(now)

	if not t or t ~= t then
		return false
	end

	local last = tonumber(lastAt)

	if not last then
		return true
	end

	return (t - last) >= (tonumber(cooldown) or 0)
end

--- Paso de combo que corresponde a ESTE golpe.
---
--- La cadena vive en el servidor (nunca la manda el cliente): el golpe que
--- llega fuera de la ventana la reinicia a 1, y el especial devuelve la
--- cadena a 0 para que el cuarto golpe rapido no sea otro especial.
--- @param comboCount any pasos encadenados hasta ahora
--- @param lastHitAt any instante del ultimo golpe
--- @param now any
--- @return number nuevo paso (1..FinisherAt)
function Rules.ComboStep(comboCount: any, lastHitAt: any, now: any): number
	local t = tonumber(now)
	local last = tonumber(lastHitAt)
	local count = tonumber(comboCount) or 0

	if not t or not last or (t - last) > Rules.Combo.Window then
		return 1
	end

	if count >= Rules.Combo.FinisherAt then
		return 1
	end

	return count + 1
end

--- Dano de un golpe segun su paso de combo.
--- @param step any
--- @return number
function Rules.DamageFor(step: any): number
	if (tonumber(step) or 1) >= Rules.Combo.FinisherAt then
		return math.floor(Rules.Melee.Damage * Rules.Combo.FinisherMultiplier)
	end

	return Rules.Melee.Damage
end

--- La victima esta dentro del arco del golpe.
---
--- El alcance se mide en XZ (plano): un enemigo un poco por encima del
--- jugador (una rampa) sigue siendo alcanzable, que es lo que se espera
--- de un golpe cuerpo a cuerpo.
---
--- La aritmetica va por CAMPOS (`X`, `Z`) y no por la API de `Vector3`,
--- a proposito: asi vale igual para un `Vector3` del motor que para una
--- tabla `{X, Z}` de prueba, y la comparacion de angulo se hace con el
--- producto punto AL CUADRADO, sin una sola raiz ni normalizacion.
--- @param origin any posicion del atacante (`.X`/`.Z`)
--- @param look any direccion de la mirada
--- @param target any posicion de la victima
--- @param range number
--- @param minDot number -1 = cualquier direccion
--- @return boolean
function Rules.InArc(origin: any, look: any, target: any, range: number, minDot: number): boolean
	local dx = target.X - origin.X
	local dz = target.Z - origin.Z
	local distSq = dx * dx + dz * dz

	if distSq > range * range then
		return false
	end

	if minDot <= -1 then
		return true
	end

	if distSq < 1e-6 then
		return true
	end

	local lx = look.X
	local lz = look.Z
	local lookSq = lx * lx + lz * lz

	if lookSq < 1e-12 then
		return false
	end

	-- dot >= minDot * |a| * |b|, al cuadrado para no normalizar. El
	-- signo lo da `dot`: un minDot positivo exige estar DELANTE.
	local dot = dx * lx + dz * lz

	if minDot >= 0 and dot <= 0 then
		return false
	end

	return dot * dot >= minDot * minDot * distSq * lookSq
end

return Rules
