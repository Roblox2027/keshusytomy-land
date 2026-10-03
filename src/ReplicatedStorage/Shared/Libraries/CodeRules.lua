--!strict
--[[
	CodeRules
	REGLAS DE CANJE DE CODIGOS. Logica pura, sin motor, sin reloj global.

	POR QUE ESTA SEPARADO DEL SERVICIO
	-----------------------------------
	El peligro real de un sistema de codigos NO es "que el codigo no se
	reconozca": es PAGAR DOS VECES. Si esa propiedad vive dentro del
	servicio, depende de Players, de DataStore y de un reloj real, no se
	puede probar de forma exhaustiva. Aqui el reloj es INYECTABLE y el
	estado es una tabla lisa, asi que cada caso limite puede comprobarse
	determinista.

	LA REGLA DE ORO
	---------------
	El canje es atomico: se comprueba la validez y se registra el uso en la
	 MISMA operacion, y si algo falla despues, el registro se revierte.
	Nunca se concede una recompensa antes de haber anotado el uso.

	Por que no basta con "un codigo por jugador": dos peticiones del mismo
	codigo llegan al servidor a la vez si el jugador pulsa dos veces. Sin un
	cerrojo, ambas ven "este codigo no se ha usado" y las dos pagan. El
	estado `Redemptions` se marca DENTRO de la funcion de canje y la
	segunda llamada lo encuentra ocupado.
]]

local Rules = {}

--- Motivos de rechazo. Estables: los tests los comparan.
Rules.Reject = {
	Empty = "empty",
	Malformed = "malformed",
	Unknown = "unknown",
	Expired = "expired",
	AlreadyUsed = "already_used",
	Exhausted = "exhausted",
}

--- Longitud maxima admitida para un codigo escrito a mano.
local MAX_CODE_LENGTH = 32

--- Normaliza lo que el jugador escribe para poder comparar.
---
--- La gente teclea "keshusy2026", " KESHUSY2026 " o "keshusy-2026" pensando
--- que son el mismo codigo. Normalizar aqui evita que un codigo valido
--- falle por mayusculas, y evita que dos codigos distintos que solo se
--- diferencian en mayusculas ocupen el mismo hueco.
--- @param raw any
--- @return string? normalized nil si no es utilizable
function Rules.Normalize(raw: any): string?
	if type(raw) ~= "string" then
		return nil
	end

	local trimmed = raw:lower():gsub("%s", ""):gsub("%-", ""):gsub("_", "")

	if #trimmed == 0 or #trimmed > MAX_CODE_LENGTH then
		return nil
	end

	-- Solo alfanumerico. Un codigo con espacios raremos, comillas o
	-- corchetes no es un codigo: es un intento de colar algo en un log o
	-- en una consulta.
	if not trimmed:match("^[%a%d]+$") then
		return nil
	end

	return trimmed
end

--- Indica si la definicion de un codigo es utilizable por el servidor.
---
--- Un codigo sin recompensa es un error de contenido, no un caso de
--- uso: se rechaza al DEFINIRLO, no al canjearlo, para que el fallo
--- aparezca en el arranque y no un martes a las tres de la manana.
--- @param definition any
--- @return boolean valid
--- @return string? reason
function Rules.IsDefinitionValid(definition: any): (boolean, string?)
	if type(definition) ~= "table" then
		return false, "not_a_table"
	end

	local code = Rules.Normalize(definition.Code)

	if not code then
		return false, "bad_code"
	end

	local rewards = definition.Rewards

	if type(rewards) ~= "table" then
		return false, "no_rewards"
	end

	local count = 0

	for currency, amount in pairs(rewards) do
		if type(currency) ~= "string" then
			return false, "bad_currency"
		end

		-- `Amount` tiene que ser un entero POSITIVO. Se exige entero
		-- porque un canje de 0.5 monedas no tiene sentido y uno negativo
		-- seria restarle saldo al jugador al "canjear" un codigo.
		if type(amount) ~= "number" or amount ~= amount then
			return false, "bad_amount"
		end

		if amount <= 0 or amount % 1 ~= 0 then
			return false, "bad_amount"
		end

		count += 1
	end

	if count == 0 then
		return false, "no_rewards"
	end

	return true, nil
end

--- Indica si un codigo sigue vigente en el instante dado.
--- @param definition any
--- @param now number
--- @return boolean active
--- @return string? reason
function Rules.IsActive(definition: any, now: number): (boolean, string?)
	if type(definition) ~= "table" then
		return false, Rules.Reject.Unknown
	end

	-- `ExpiresAt` es opcional: sin el, el codigo no caduca.
	local expiresAt = definition.ExpiresAt

	if expiresAt ~= nil then
		if type(expiresAt) ~= "number" or expiresAt ~= expiresAt then
			return false, Rules.Reject.Malformed
		end

		-- `>=` y no `>`: en el segundo exacto de la expiracion el codigo
		-- ya no vale. Es la lectura conservadora.
		if now >= expiresAt then
			return false, Rules.Reject.Expired
		end
	end

	return true, nil
end

--- Canjea un codigo de forma ATOMICA.
---
--- Este es el corazon del sistema y la unica funcion que concede algo.
--- Su garantia, en este orden:
---
---   1. Valida la FORMA de lo escrito y normaliza.
---   2. Busca el codigo. Si no existe, no se toca nada.
---   3. Comprueba vigencia y caducidad.
---   4. Comprueba el limite global (`MaxRedemptions`).
---   5. Comprueba si ESTE jugador ya lo canjeo.
---   6. MARCA EL USO y DEVUELVE la recompensa.
---
--- El paso 6 es el que hace imposible el pago doble: el uso se anota
--- dentro de la misma llamada, asi que una segunda llamada concurrente
--- encuentra el hueco ocupado. `MaxRedemptions` se incrementa en el mismo
--- paso, por lo que tampoco hay forma de superar el tope global.
---
--- `playerId` es un numero, no un `Player`: las reglas no conocen el
--- motor y asi se pueden probar con 1, 2 y 1000 jugadores falsos.
---
--- SEPARACION DE ESTADOS (y por que hay dos argumentos)
-------------------------------------------------------
--- `state` es el PERFIL del jugador: lo que se guarda con el y lo que
--- sobrevive a que se desconecte. Ahi vive `Redemptions` (que codigos ha
--- canjeado ESTE jugador) y `RedemptionCounts` (cuantos).
---
--- `global` es el CONTADOR COMPARTIDO del servidor: cuantos canjes ha
--- tenido cada codigo en total. NO puede vivir en el perfil, porque cada
--- jugador tiene el suyo y ninguno veria el canje de los demas: un codigo
--- limitado a 100 usos se podria canjear 100 veces por jugador y el
--- limite global no existiria.
---
--- Esa separacion es la que hace que "otro jugador puede canjearlo" y
--- "agotado para todos" sean dos Rechazos DISTINTOS y correctos.
---
--- @param state any perfil mutable del jugador (`Redemptions`, `RedemptionCounts`)
--- @param global any contador compartido (`RedeemedCodes`)
--- @param playerId number
--- @param rawCode any lo que el jugador escribio
--- @param now number reloj inyectado
--- @param definitions { [string]: any } catalogo de codigos
--- @return boolean accepted
--- @return string? reason motivo del rechazo (el que ve el jugador)
--- @return { [string]: number }? rewards recompensa a conceder (vacia si no se concede)
--- @return string? detail detalle tecnico para el log del servidor
function Rules.Redeem(
	state: any,
	global: any,
	playerId: number,
	rawCode: any,
	now: number,
	definitions: { [string]: any }
): (boolean, string?, { [string]: number }?, string?)
	if type(state) ~= "table" or type(global) ~= "table" then
		return false, "invalid_state", nil, nil
	end

	local code = Rules.Normalize(rawCode)

	if not code then
		return false, Rules.Reject.Malformed, nil, nil
	end

	local definition = definitions[code]

	if not definition then
		return false, Rules.Reject.Unknown, nil, nil
	end

	local validDefinition, definitionReason = Rules.IsDefinitionValid(definition)

	if not validDefinition then
		-- Un codigo publicado con una recompensa rota NO se canjea: es
		-- preferible fallar aqui que conceder una mitad y dejar al
		-- jugador con un codigo consumido y sin recompensa.
		--
		-- El motivo concreto (`bad_amount`, `no_rewards`...) se devuelve
		-- por separado para el log del servidor: distingue un codigo mal
		-- publicado de un intento del jugador, que son incidencias
		-- distintas. No se le muestra al jugador, que solo necesita saber
		-- que no puede canjearlo.
		return false, Rules.Reject.Malformed, nil, definitionReason
	end

	local active, activeReason = Rules.IsActive(definition, now)

	if not active then
		return false, activeReason, nil, nil
	end

	-- Estado del PERFIL del jugador. Se crea aqui para que un perfil
	-- migrado, que todavia no tenga la seccion, no provoque un error.
	if type(state.Redemptions) ~= "table" then
		state.Redemptions = {}
	end

	if type(state.RedemptionCounts) ~= "table" then
		state.RedemptionCounts = {}
	end

	-- Estado COMPARTIDO del servidor.
	if type(global.RedeemedCodes) ~= "table" then
		global.RedeemedCodes = {}
	end

	-- El perfil guarda el canje del JUGADOR. Sobrevive a reconexiones: es
	-- la unica memoria de que el codigo ya se entrego.
	if state.Redemptions[code] then
		return false, Rules.Reject.AlreadyUsed, nil, nil
	end

	-- Cuantos codigos ha canjeado ESTE jugador. No decide nada del canje
	-- (eso lo gobiernan `MaxRedemptions` y `Redemptions`), pero permite
	-- detectar el abuso: una cuenta que canjea cincuenta codigos por
	-- segundo esta automatizando, no jugando.
	local playerKey = tostring(playerId)
	local playerCount = state.RedemptionCounts[playerKey]

	if type(playerCount) ~= "number" then
		playerCount = 0
	end

	-- Limite global de canjes, si el codigo lo declara. El contador vive
	-- en el estado COMPARTIDO y SOLO contiene codigos normalizados, asi
	-- que un codigo nunca se confunde con una clave de jugador.
	local maxRedemptions = definition.MaxRedemptions
	local usedCount = global.RedeemedCodes[code]

	if type(usedCount) ~= "number" then
		usedCount = 0
	end

	if maxRedemptions ~= nil then
		if type(maxRedemptions) ~= "number" or maxRedemptions ~= maxRedemptions then
			return false, Rules.Reject.Malformed, nil, "bad_max_redemptions"
		end

		if usedCount >= maxRedemptions then
			return false, Rules.Reject.Exhausted, nil, nil
		end
	end

	-- PASO 6: marcar ANTES de devolver. A partir de aqui el canje esta
	-- consumido aunque la entrega de la recompensa falle despues: es
	-- preferible perder una recompensa que pagar dos.
	--
	-- El canje se registra por JUGADOR en `state.Redemptions[codigo]`, que
	-- es lo que sobrevive a la reconexion, y el contador global avanza en
	-- `global.RedeemedCodes[codigo]`.
	state.Redemptions[code] = true
	global.RedeemedCodes[code] = usedCount + 1
	state.RedemptionCounts[playerKey] = playerCount + 1

	local rewards = definition.Rewards
	local granted = {}

	for currency, amount in pairs(rewards) do
		granted[currency] = amount
	end

	return true, nil, granted
end

return Rules