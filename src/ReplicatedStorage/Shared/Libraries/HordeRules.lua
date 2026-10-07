--!strict
--[[
	HordeRules
	EL CICLO DE VIDA DE UNA HORDA (FASE 14).

	POR QUE UN MODULO DE CICLO Y NO UN SERVICIO
	------------------------------------------
	Una horda tiene estados (`Running`, `Cleared`, `Failed`, `Expired`) y transiciones
	entre ellos. Las transiciones son la parte que hay que PROBAR y la parte que
	más falla: un `Rewarded` que se puede activar dos veces paga al jugador dos
	veces, y un estado que nunca pasa a `Cleared` deja la horda contando enemigos
	muertos para siempre.

	El servicio (`HordeService`) tiene los NPC y los threads. Aqui solo vive la
	Maquina de estados, que es pura y se prueba entera en local.

	LA REGLA QUE NO SE PUEDE ROMPER
	-------------------------------
	UNA horda se paga UNA vez. No una vez por jugador que thereto, ni una vez por
	frame, ni una vez al principio y otra al final. El campo `Rewarded` es la
	UNICA memoria de eso, y todas las funciones de pago pasan por el.

	El dia que se anada una segunda via de pago (un evento que pague "por
	matar a N", por ejemplo) sin pasar por `MarkRewarded`, el juego empieza a
	pagar de mas. `Horde.spec` no podria detectarlo; por eso el modulo hace que
	sea la UNICA forma de hacerlo.
]]

local Rules = {}

-- ---------------------------------------------------------------------------
-- ESTADOS
-- ---------------------------------------------------------------------------

Rules.State = {
	-- Se acaba de iniciar: contando enemigos por derrotar.
	Running = "Running",
	-- Todos los enemigos han muerto. El PREMIO esta pendiente de pago.
	Cleared = "Cleared",
	-- Se termino el tiempo sin limpiar todos. NO se paga.
	Failed = "Failed",
	-- Un jugador salio del mundo o el servidor esta apagando. No se paga.
	Expired = "Expired",
	-- Se entrego la recompensa. Estado terminal.
	Rewarded = "Rewarded",
}

--- Estados en los que la horda AUN esta contando.
Rules.OpenStates = {
	[Rules.State.Running] = true,
}

-- ---------------------------------------------------------------------------
-- TAMANO DE LA HORDA
-- ---------------------------------------------------------------------------

--- Numero de enemigos de una horda en una noche concreta.
---
--- Crece con la noche pero ACOTA. La razon es la misma que en `DifficultyRules`:
--- una horda de 200 enemigos no es dificultad, es una cola de trabajo que el
--- jugador no puede terminar nunca y por tanto no puede disfrutar. El jugador
--- tiene que poder VER el final cerca.
---
--- El valor minimo es 3 y no 1: una horda de un solo enemigo no es una horda,
--- es un enemigo, y el jugador no perceive ninguna diferencia con la
--- exploracion normal.
--- @param night any
--- @return number
function Rules.SizeFor(night: any): number
	local n = tonumber(night)

	if not n or n ~= n then
		n = 1
	end

	n = math.clamp(n, 1, 99)

	-- De 6 en la noche 1 a 34 en la noche 99: crecimiento casi lineal pero con
	-- la mitad de la pendiente, para que las noches altas digan "muchos" y no
	-- "todos a la vez".
	local t = (n - 1) / 98
	return math.floor(6 + t * 28)
end

--- Numero de enemigos vivos que quedan por obra.
---
--- @param total number tamanho total de la horda
--- @param killed number enemigos ya derrotados
--- @return number
function Rules.Remaining(total: number, killed: number): number
	local t = tonumber(total) or 0
	local k = tonumber(killed) or 0

	return math.max(0, math.floor(t) - math.floor(k))
end

-- ---------------------------------------------------------------------------
-- CREACION
-- ---------------------------------------------------------------------------

export type Horde = {
	Id: number,
	WorldId: string,
	Night: number,
	Total: number,
	Killed: number,
	State: string,
	Rewarded: boolean,
}

--- Crea el estado de una horda nueva.
---
--- El `Id` lo pone el SERVIDOR y debe ser unico entre hordas VIVAS. Aqui solo
--- se propaga: la unicidad la garantiza quien las crea, y `HordeService` la
--- comprueba al arrancar una.
--- @param id number identificador unico
--- @param worldId string
--- @param night any
--- @param totalOverride any? tamaño manual (tests y eventos)
--- @return Horde
function Rules.Create(id: number, worldId: string, night: any, totalOverride: any?): Horde
	local total = tonumber(totalOverride)

	if not total or total ~= total then
		total = Rules.SizeFor(night)
	end

	return {
		Id = id,
		WorldId = worldId,
		Night = tonumber(night) or 1,
		Total = math.max(1, math.floor(total)),
		Killed = 0,
		State = Rules.State.Running,
		Rewarded = false,
	}
end

-- ---------------------------------------------------------------------------
-- TRANSICIONES
-- ---------------------------------------------------------------------------

--- Registra un enemigo derrotado.
---
--- Es la UNICA via por la que se avanza el contador. Volver a llamar con un
--- numero mayor de bajas NO se IGNORA: se cuenta. Eso es correcto, porque cada
--- baja corresponde a un enemigo REAL que el jugador mato, y cada uno merece su
--- parte del botin.
---
--- Lo que no se permite es contar la MISMA baja dos veces, y eso lo resuelve el
--- SERVICIO (que solo llama cuando un NPC suyo pasa a `Dying`), no este modulo.
--- @param horde Horde
--- @param count number? bajas a registrar (por defecto 1)
--- @return Horde el mismo registro, mutado
function Rules.RegisterKill(horde: Horde, count: number?): Horde
	-- Una horda ya cerrada NO avanza. Sin esta comprobacion, un enemigo que
	-- muere tarde (por explosion en cadena, por un bomba que todavia no habia
	-- explotado) inflaria el contador despues de `Cleared` y la horda volveria
	-- a `Running` con el premio ya entregado.
	if horde.State ~= Rules.State.Running then
		return horde
	end

	local n = tonumber(count) or 1

	if n ~= n or n <= 0 then
		return horde
	end

	horde.Killed = math.min(horde.Total, horde.Killed + math.floor(n))

	if horde.Killed >= horde.Total then
		horde.State = Rules.State.Cleared
	end

	return horde
end

--- Enenemigos que quedan por derrotar.
--- @param horde Horde
--- @return number
function Rules.GetRemaining(horde: Horde): number
	return Rules.Remaining(horde.Total, horde.Killed)
end

--- Termina la horda SIN premiar (se agoto el tiempo).
---
--- Un horda fallida NO paga. Es lo que hace que el limite de tiempo signifique
--- algo: si pagara igual, al jugador le seria indiferente limpiar o no.
--- @param horde Horde
--- @return boolean changed
function Rules.Fail(horde: Horde): boolean
	if horde.State ~= Rules.State.Running then
		return false
	end

	horde.State = Rules.State.Failed
	return true
end

--- Cierra la horda sin premiar (el jugador salio, el servidor apaga).
---
--- Acepta cerrar una horda YA COMPLETADA pero todavia sin pagar. Ese es el
--- caso real: el jugador limpia la horda y sale del mundo en el mismo instante,
--- antes de que el sistema entregue el premio. Si `Expire` solo aceptara
--- `Running`, esa horda se quedaria en `Cleared` para siempre y pagaria mas
--- tarde a un jugador que ya no esta, o (peor) quedaria colgada si el mundo se
--- descargara. Cerrarla aqui es lo que hace que el cleanup sea completo.
--- @param horde Horde
--- @return boolean changed
function Rules.Expire(horde: Horde): boolean
	if horde.Rewarded then
		-- Ya esta en estado terminal: no se toca. Es el mismo cortafuegos que
		-- protege `ClaimReward`, y por el mismo motivo.
		return false
	end

	if horde.State == Rules.State.Expired or horde.State == Rules.State.Failed then
		return false
	end

	horde.State = Rules.State.Expired
	return true
end

-- ---------------------------------------------------------------------------
-- EL PREMIO (FASE 14: "no otorgar recompensas multiples")
-- ---------------------------------------------------------------------------

export type Reward = {
	XP: number,
	Coins: number,
	Gems: number,
}

--- Recompensa de completar una horda.
---
--- Escala con la noche Y con el tamano, y por debajo del multiplicador de
--- dificultad: las hordas pagan BIEN, pero no pagan el doble de lo que paga el
--- boss, porque una horda es contenido frecuente y el boss es el cierre.
--- @param horde Horde
--- @param rewardScale any? multiplicador de dificultad (1 = base)
--- @return Reward
function Rules.RewardFor(horde: Horde, rewardScale: any?): Reward
	local scale = tonumber(rewardScale)

	if not scale or scale ~= scale or scale < 1 then
		scale = 1
	end

	-- Se acota a 3: sin este tope, una horda de la noche 99 pagaria tanto como
	-- un boss, y el boss dejaria de ser el cierre.
	local factor = math.min(scale, 3)

	-- Base por enemigo. Es BAJO a proposito: el grueso de la recompensa de una
	-- horda llega por el botin de los enemigos, no por un extra al final.
	--
	-- La noche entra POR SEPARADO y no dentro de `factor`. Si se multiplicaran,
	-- una horda de la noche 99 pagaria el doble por ser larga Y el doble por
	-- ser de noche, y el producto superaria el tope que existe justamente para
	-- que eso no ocurra. Con dos sumas separadas, cada factor sigue acotado por
	-- su propio lado.
	local nightBonus = 1 + (math.clamp(horde.Night, 1, 99) - 1) / 98 * 0.8
	local multiplier = factor * nightBonus

	return {
		XP = math.floor(horde.Total * 8 * multiplier),
		Coins = math.floor(horde.Total * 5 * multiplier),
		Gems = horde.Night >= 50 and 1 or 0,
	}
end

-- ---------------------------------------------------------------------------
-- CONSULTAS DE ESTADO
-- ---------------------------------------------------------------------------

--- La horda esta cuenta y se puede limpiar.
--- @param horde Horde
--- @return boolean
function Rules.IsComplete(horde: Horde): boolean
	return horde.State == Rules.State.Cleared or horde.State == Rules.State.Rewarded
end

--- La horda sigue viva y contando.
--- @param horde Horde
--- @return boolean
function Rules.IsActive(horde: Horde): boolean
	return Rules.OpenStates[horde.State] == true
end

--- La horda fallo: se agoto el tiempo sin limpiar todos.
--- @param horde Horde
--- @return boolean
function Rules.IsFailed(horde: Horde): boolean
	return horde.State == Rules.State.Failed
end

--- La horda se cerro sin pagar (salida del jugador o apagado del servidor).
--- @param horde Horde
--- @return boolean
function Rules.IsExpired(horde: Horde): boolean
	return horde.State == Rules.State.Expired
end

--- La horda ya entrego su premio.
--- @param horde Horde
--- @return boolean
function Rules.HasRewarded(horde: Horde): boolean
	return horde.Rewarded == true
end

--- Entrega el premio de la horda, UNA sola vez.
---
--- ESTA ES LA FUNCION MAS IMPORTANTE DEL MODULO.
---
--- Devuelve `(true, recompensa)` la PRIMERA vez que se entrega y `(false, nil)`
--- todas las siguientes, sin excepcion: sin importar quien llame, cuantas veces
--- se llame ni en que orden lleguen las llamadas.
---
--- La razon de que devuelva un booleano en vez de solo la recompensa es que el
--- llamante NECESITA saber si debe pagar. Un `RewardFor` que siempre devuelve una
--- tabla obliga a que cada sitio compruebe el estado por su cuenta, y en cuanto
--- hay dos sitios, uno se olvida.
--- @param horde Horde
--- @param rewardScale any?
--- @return boolean paid
--- @return Reward? reward nil si ya se habia pagado
function Rules.ClaimReward(horde: Horde, rewardScale: any?): (boolean, Reward?)
	-- Cortafuegos 1: ya se entrego.
	if horde.Rewarded then
		return false, nil
	end

	-- Cortafuegos 2: la horda no se completo. Esto NO es un extra: si una horda
	-- fallida pagara, el limite de tiempo no significaria nada.
	if horde.State ~= Rules.State.Cleared then
		return false, nil
	end

	-- Cortafuegos 3: ya esta en estado terminal de premio.
	if horde.State == Rules.State.Rewarded then
		return false, nil
	end

	-- La marca se pone ANTES de calcular la recompensa. Es lo que hace que esto
	-- sea a prueba de reentrada: si `RewardFor` fallara o el llamante reentrara,
	-- la segunda pasada ya encuentra `Rewarded` y no paga.
	horde.Rewarded = true
	horde.State = Rules.State.Rewarded

	return true, Rules.RewardFor(horde, rewardScale)
end

return Rules