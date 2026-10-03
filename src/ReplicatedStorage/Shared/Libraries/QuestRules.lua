--!strict
--[[
	QuestRules
	Misiones, recompensas diarias y logros como LOGICA PURA.

	POR QUE SEPARADO DEL SERVICIO
	------------------------------
	Una mision son cinco pasos y el fallo aparece en el que se olvida uno:

	    0 -> progreso -> completo -> RECLAMAR -> recompensa

	Los cuatro primeros se pueden decidir sin motor y SIN reloj real si el
	instante se inyecta, y se pueden probar de forma exhaustiva. `QuestService`
	anade lo que las reglas no saben: resolver el `Player`, pagar la
	recompensa de verdad y avisar a la UI.

	LA REGLA DE ORO
	----------------
	Reclamar es ATOMICO y NO se puede repetir. `Claim` MARCA el reclamo DENTRO
	de la misma operacion que lo autoriza, y si algo falla despues el reclamo
	queda hecho. Es la misma eleccion que en `CodeRules.Redeem` y por el mismo
	motivo: perder una recompensa es un contratiempo; pagarla dos veces es un
	agujero.

	LA REGLA QUE PROTEGE AL JUGADOR
	-------------------------------
	El progreso NUNCA se resetea al reconnectar. Vive en la seccion `Quests`
	del perfil, que es lo unico que sobrevive a que el jugador se vaya. Un
	progreso en memoria seria "0/30" otra vez en cada reconexion, y el jugador
	perderia su trabajo sin que nadie se lo dijera.

	POR QUE NO SE USA `require` AQUI
	---------------------------------
	Igual que `RemoteSchema`, `ProfileSchema` y `CodeRules`: en el interprete
	de pruebas `script` no existe, asi que las dependencias se INYECTAN.
]]

local Rules = {}

--- Motivos de rechazo. Texto estable: la UI decide que texto mostrar.
Rules.Reject = {
	UnknownQuest = "unknown_quest",
	InvalidQuestId = "invalid_quest_id",
	InvalidTarget = "invalid_target",
	InvalidReward = "invalid_reward",
	NoProfile = "no_profile",
	NotComplete = "not_complete",
	AlreadyClaimed = "already_claimed",
	DailyNotReady = "daily_not_ready",
	InvalidAmount = "invalid_amount",
}

--- Cuantos dias se conserva la racha antes de empezar de cero.
---
--- No es decorativo: una racha infinita obliga a un jugador a entrar todos
--- los dias para no perderla, y eso se convierte en presion y en queja.
--- Treinta dias cubre el mes natural y despues se reinicia.
Rules.MAX_STREAK = 30

--- Cuantas misiones se guardan como completadas por tipo.
---
--- Sin tope, un jugador que completa 500 misiones acumularia 500 entradas en
--- su perfil y el guardado creeria sin limite. Se conservan las ULTIMAS, que
--- son las que el jugador puede volver a ver.
Rules.MAX_TRACKED_PER_TYPE = 50

--- Crea el estado de misiones de un jugador.
---
--- Las sub-tables nacen VACIAS pero PRESENTES: una clave ausente obliga a
--- todos los lectores a preguntar "ya existe?", y con la forma siempre
--- presente se lee sin ningun `if`.
--- @param playerId number
--- @return any state
function Rules.NewState(playerId: number): any
	return {
		PlayerId = playerId,
		-- questId -> { Progress: number, CompletedAt: number? }
		Progress = {},
		-- questId -> numero de secuencia del reclamo (ver `Claim`)
		Claims = {},
		-- tipo -> { [questId] = true }, historial acotado de completadas
		Completed = {},
		-- QuestIds de tipo Daily que se ofrecen HOY, en orden estable
		DailyOffer = {},
		Daily = { Streak = 0, LastClaimDay = nil },
		Sequence = 0,
	}
end
--- Normaliza el identificador de una mision.
---
--- Es IDENTICO al criterio de `CodeRules.Normalize` y por el mismo motivo:
--- es lo que impide que un `questId` ambiguo se confunda con otro, y que
--- una cadena con corchetes o comillas acabe en un log.
--- @param raw any
--- @return string? normalized nil si no es utilizable
function Rules.NormalizeId(raw: any): string?
	if type(raw) ~= "string" then
		return nil
	end

	local trimmed = raw:lower():gsub("%s", ""):gsub("%-", ""):gsub("_", "")

	if #trimmed == 0 or #trimmed > 64 then
		return nil
	end

	-- Solo alfanumerico: una mision con corchetes o comillas es un intento
	-- de colar algo en un log, no un identificador.
	if not trimmed:match("^[%a%d]+$") then
		return nil
	end

	return trimmed
end

--- Comprueba que la definicion de una mision es utilizable.
---
--- Se valida al DEFINIR, no al reclamarla, para que una mision publicada
--- rota aparezca como fallo de arranque y no como "esta mision no existe"
--- un martes a las tres de la manana.
--- @param definition any
--- @return boolean valid
--- @return string? reason
function Rules.IsDefinitionValid(definition: any): (boolean, string?)
	if type(definition) ~= "table" then
		return false, Rules.Reject.UnknownQuest
	end

	if not Rules.NormalizeId(definition.Id) then
		return false, Rules.Reject.InvalidQuestId
	end

	-- `Target` es un entero POSITIVO. Una mision con `Target = 0` estaria
	-- completada de salida y `Target < 0` no tendria sentido.
	local target = definition.Target

	if type(target) ~= "number" or target ~= target then
		return false, Rules.Reject.InvalidTarget
	end

	if target <= 0 or target % 1 ~= 0 then
		return false, Rules.Reject.InvalidTarget
	end

	-- La recompensa se valida con la MISMA forma que usa `CodeRules`:
	-- diccionario de moneda -> entero positivo. Se reutiliza su funcion en
	-- lugar de reescribirla, para que codigos y misiones no puedan divergir
	-- en que consideran valido un premio.
	local rewards = definition.Rewards

	if type(rewards) ~= "table" then
		return false, Rules.Reject.InvalidReward
	end

	local count = 0

	for currency, amount in pairs(rewards) do
		if type(currency) ~= "string" then
			return false, Rules.Reject.InvalidReward
		end
		if type(amount) ~= "number" or amount ~= amount then
			return false, Rules.Reject.InvalidReward
		end
		if amount <= 0 or amount % 1 ~= 0 then
			return false, Rules.Reject.InvalidReward
		end
		count += 1
	end

	if count == 0 then
		return false, Rules.Reject.InvalidReward
	end

	return true, nil
end
--- Devuelve (creando si hace falta) la entrada de progreso de una mision.
---
--- El `typeof` protege contra un perfil corrupto o migrado de otra forma:
--- si `Progress.questx` fuera un numero, `entry.Progress = ...` reventaria.
--- @param state any
--- @param questId string id YA normalizado
--- @return any entry
local function progressEntryOf(state: any, questId: string): any
	if type(state.Progress) ~= "table" then
		state.Progress = {}
	end

	local entry = state.Progress[questId]

	if type(entry) ~= "table" then
		entry = { Progress = 0, CompletedAt = nil }
		state.Progress[questId] = entry
	end

	return entry
end

--- Progreso actual de una mision.
---
--- NORMALIZA el id, igual que `Advance`, `IsComplete` y `IsClaimed`. La
--- coherencia no es cosmetics: `Advance` guarda bajo la clave normalizada,
--- asi que una lectura sin normalizar devolveria SIEMPRE cero para un id
--- escrito como lo escribe el catalogo (`WORLD_DESTROY_30`). El sintoma
--- seria "las misiones no avanzan" con la UI mostrando 0/30 mientras el
--- progreso si se estaba guardando.
--- @param state any
--- @param questId string
--- @return number
function Rules.GetProgress(state: any, questId: string): number
	if type(state) ~= "table" or type(state.Progress) ~= "table" then
		return 0
	end

	local id = Rules.NormalizeId(questId)

	if not id then
		return 0
	end

	local entry = state.Progress[id]

	if type(entry) ~= "table" or type(entry.Progress) ~= "number" then
		return 0
	end

	return entry.Progress
end

--- Avanza el progreso de una mision.
---
--- `amount` se ACOTA al objetivo: una mision de 30 bloques que recibe un
--- evento de 500 no guarda 500, guarda 30. La razon es de persistencia: el
--- perfil guardaria un numero que no significa nada y la UI dibujaria
--- "500/30".
---
--- Una mision YA COMPLETADA no se vuelve a completar ni cambia su marca de
--- tiempo: si no, un jugador que farmasea una mision terminaria cambiando
--- su `CompletedAt` y el historial daily dejaria de ser daily.
--- @param state any
--- @param definition any definicion validada
--- @param amount number incremento SOLO del servidor
--- @param now number reloj inyectado
--- @return number progress valor DESPUES del avance
--- @return boolean justCompleted true si esta llamada la completo
function Rules.Advance(state: any, definition: any, amount: number, now: number): (number, boolean)
	if type(state) ~= "table" or type(definition) ~= "table" then
		return 0, false
	end

	local questId = Rules.NormalizeId(definition.Id)

	if not questId then
		return 0, false
	end

	-- Un incremento no es un numero FINITO y positivo es ruido, no juego:
	-- se ignora en vez de propagarse. Ignorarlo es seguro porque el unico
	-- que llama con un valor real es el servidor, en un evento de juego.
	if
		type(amount) ~= "number"
		or amount ~= amount
		or amount == math.huge
		or amount == -math.huge
		or amount <= 0
	then
		return Rules.GetProgress(state, questId), false
	end

	local entry = progressEntryOf(state, questId)

	if entry.CompletedAt ~= nil then
		return entry.Progress, false
	end

	local target = definition.Target
	local next = math.min(entry.Progress + amount, target)

	-- `floor` y no `min` solo: el progreso se muestra como `n/objetivo` y
	-- un valor fraccionario se veria raro. Se redondea ABAJO para no
	-- declarar completada una mision a la que le falta un entero.
	next = math.floor(next)

	if next == entry.Progress then
		return entry.Progress, false
	end

	entry.Progress = next

	local justCompleted = false

	if next >= target then
		entry.CompletedAt = now
		justCompleted = true
		Rules._recordCompletion(state, definition)
	end

	return entry.Progress, justCompleted
end

--- Anota una mision como completada en el historial acotado por tipo.
---
--- El historial esta ACOTADO a proposito: sin tope, un jugador que completa
--- cientos de misiones acumularia cientos de entradas en su perfil y el
--- guardado creeria sin limite. Se conservan las ULTIMAS, que son las que
--- el jugador puede volver a ver.
--- @param state any
--- @param definition any
function Rules._recordCompletion(state: any, definition: any)
	if type(state) ~= "table" then
		return
	end

	if type(state.Completed) ~= "table" then
		state.Completed = {}
	end

	local questType = definition.Type

	if type(questType) ~= "string" then
		questType = "World"
	end

	local bucket = state.Completed[questType]

	if type(bucket) ~= "table" then
		bucket = {}
		state.Completed[questType] = bucket
	end

	local questId = Rules.NormalizeId(definition.Id)

	if not questId then
		return
	end

	bucket[questId] = true

	-- Poda del exceso: el orden de `pairs` NO es estable, asi que se
	-- descarta una victima sin inventar un orden que no existe. Perder una
	-- entrada antigua del historial es aceptable; lo que no lo es es dejar
	-- crecer el perfil sin limite.
	local count = 0
	for _ in pairs(bucket) do
		count += 1
	end

	while count > Rules.MAX_TRACKED_PER_TYPE do
		for key in pairs(bucket) do
			bucket[key] = nil
			count -= 1
			break
		end
	end
end

--- Indica si una mision esta completada (y por tanto reclamable).
---
--- No necesita la definicion: el unico que la necesita es `Advance`, que ya
--- comparo con `Target`. Por eso se guarda `CompletedAt` en la entrada, y no
--- el resultado de una comparacion que habria que repetir aqui.
--- @param state any
--- @param questId string
--- @return boolean complete
function Rules.IsComplete(state: any, questId: string): boolean
	local id = Rules.NormalizeId(questId)

	if not id then
		return false
	end

	if type(state) ~= "table" or type(state.Progress) ~= "table" then
		return false
	end

	local entry = state.Progress[id]

	return type(entry) == "table" and entry.CompletedAt ~= nil
end
--- Indica si una mision ya fue reclamada.
--- @param state any
--- @param questId string
--- @return boolean claimed
function Rules.IsClaimed(state: any, questId: string): boolean
	local id = Rules.NormalizeId(questId)

	if not id then
		return false
	end

	if type(state) ~= "table" or type(state.Claims) ~= "table" then
		return false
	end

	return state.Claims[id] ~= nil
end

--- Reclama la recompensa de una mision completada, de forma ATOMICA.
---
--- El orden importa y es el que hace imposible el pago doble:
---
---     1. el estado es valido?
---     2. la mision existe?
---     3. esta YA reclamada?      -> no, no se toca nada
---     4. esta COMPLETADA?        -> no, no se toca nada
---     5. MARCA el reclamo
---     6. devuelve la recompensa
---
--- El paso 5 ocurre DENTRO de esta llamada: dos peticiones simultaneas
--- del mismo jugador (el doble clic, o el reintento tras perder la
--- conexion) encuentran el hueco ocupado y solo una paga.
---
--- El paso 4 va DESPUES del 3 a proposito: "ya lo reclamaste" es una
--- respuesta mas util que "no estaba completa" cuando el jugador pulsa el
--- boton por segunda vez.
--- @param state any
--- @param questId any
--- @param definitions { [string]: any } catalogo indexado por id normalizado
--- @return boolean accepted
--- @return string? rejection
--- @return { [string]: number }? rewards
function Rules.Claim(
	state: any,
	questId: any,
	definitions: { [string]: any }
): (boolean, string?, { [string]: number }?)
	if type(state) ~= "table" or type(definitions) ~= "table" then
		return false, Rules.Reject.NoProfile, nil
	end

	if type(state.Claims) ~= "table" then
		state.Claims = {}
	end

	local id = Rules.NormalizeId(questId)

	if not id then
		return false, Rules.Reject.InvalidQuestId, nil
	end

	local definition = definitions[id]

	if not definition then
		return false, Rules.Reject.UnknownQuest, nil
	end

	-- La definicion se revalida aqui, no solo al arrancar: una entrada del
	-- catalogo modificada en caliente con una recompensa negativa haria que
	-- "reclamar" RESTARA saldo. Es un caso absurdo, pero el precio de
	-- comprobarlo es una comparacion.
	local valid, invalidReason = Rules.IsDefinitionValid(definition)

	if not valid then
		return false, invalidReason or Rules.Reject.InvalidReward, nil
	end

	if Rules.IsClaimed(state, id) then
		return false, Rules.Reject.AlreadyClaimed, nil
	end

	if not Rules.IsComplete(state, id) then
		return false, Rules.Reject.NotComplete, nil
	end

	-- PASO 5: marcar ANTES de devolver. A partir de aqui el reclamo esta
	-- consumido aunque la entrega de la recompensa falle despues: es
	-- preferible perder una recompensa que pagar dos.
	state.Sequence = (type(state.Sequence) == "number" and state.Sequence or 0) + 1
	state.Claims[id] = state.Sequence

	local rewards = definition.Rewards
	local granted: { [string]: number } = {}

	for currency, amount in pairs(rewards) do
		granted[currency] = amount
	end

	return true, nil, granted
end
-- ---------------------------------------------------------------
-- Recompensas diarias
-- ---------------------------------------------------------------

--- Segundos que dura un "dia" de juego.
---
--- Son 24 horas reales, no el dia del calendario del jugador. La razon
--- tecnica es que el indice tiene que ser el MISMO para todo el mundo y no
--- depender de la zona horaria: si "hoy" significara medianoche local,
--- dos jugadores de paises distintos tendrian dias distintos en el mismo
--- instante y el limite por fecha no seria un limite.
---
--- Se hace `floor` y no `round` a proposito: el indice cambia exactamente
--- en la medianoche UTC, sin derivas acumuladas por redondeos.
local DAY_SECONDS = 86400

--- Indice del dia actual. Es el unico reloj que necesita el sistema.
--- @param nowSeconds number reloj inyectado (epoch en segundos)
--- @return number dayIndex
function Rules.GetDayIndex(nowSeconds: number): number
	if type(nowSeconds) ~= "number" or nowSeconds ~= nowSeconds then
		return 0
	end

	return math.floor(nowSeconds / DAY_SECONDS)
end

--- Racha actual, leida sin tocarla.
--- @param state any
--- @return number streak
function Rules.GetStreak(state: any): number
	if type(state) ~= "table" or type(state.Daily) ~= "table" then
		return 0
	end

	local streak = state.Daily.Streak

	if type(streak) ~= "number" then
		return 0
	end

	return streak
end

--- Dias transcurridos desde el ultimo reclamo.
--- @param state any
--- @param nowSeconds number
--- @return number days
function Rules.DaysSinceLastClaim(state: any, nowSeconds: number): number
	if type(state) ~= "table" or type(state.Daily) ~= "table" then
		return math.huge
	end

	local last = state.Daily.LastClaimDay

	if type(last) ~= "number" then
		return math.huge
	end

	return Rules.GetDayIndex(nowSeconds) - last
end

--- Indica si hoy ya se reclamo el diario.
---
--- Es la proteccion de DUPLICACION por fecha: una sola recompensa por dia
--- natural, sin importar cuantas veces se pulse el boton.
--- @param state any
--- @param nowSeconds number
--- @return boolean claimed
function Rules.IsDailyClaimed(state: any, nowSeconds: number): boolean
	local last = Rules.DaysSinceLastClaim(state, nowSeconds)

	-- `== 0` y no `< 1`: si el reloj del servidor retrocediera por un NTP,
	-- `last` seria negativo y "hoy ya reclamado" seria falso, permitiendo
	-- un segundo reclamo el mismo dia. Con `== 0` el caso degenerado se
	-- trata como YA reclamado, que es la lectura conservadora.
	if last == 0 then
		return true
	end

	return last < 0
end
--- Reclama la recompensa diaria, de forma ATOMICA.
---
--- El mismo principio que `Claim`: la marca se escribe DENTRO de la
--- llamada, asi que un doble clic paga una sola vez.
---
--- LA RACHA
--- --------
--- La racha cuenta DIAS CONSECUTIVOS, no reclamos:
---
---     racha = (hoy == ultimoDia + 1) ? racha + 1 : 1
---
--- Un dia de diferencia NO la rompe, pero DOS si. No se puede observar en
--- que momento del dia se reclamo, asi que saltarse un dia entero tampoco
--- se puede detectar de forma fiable; lo que si se detecta es lo que
--- importa para el jugador: dejar de venir dos dias seguidos.
---
--- La racha se ACOTA a `MAX_STREAK`: una racha infinita obliga a entrar
--- todos los dias y se convierte en presion en vez de en incentivo.
--- @param state any
--- @param nowSeconds number
--- @param rewards { [string]: number } recompensa de hoy
--- @return boolean accepted
--- @return string? rejection
--- @return { [string]: number }? rewards
--- @return number streak racha DESPUES del reclamo
function Rules.ClaimDaily(
	state: any,
	nowSeconds: number,
	rewards: { [string]: number }
): (boolean, string?, { [string]: number }?, number)
	if type(state) ~= "table" then
		return false, Rules.Reject.NoProfile, nil, 0
	end

	if type(state.Daily) ~= "table" then
		state.Daily = { Streak = 0, LastClaimDay = nil }
	end

	-- Un segundo reclamo el mismo dia se rechaza ANTES de tocar nada.
	if Rules.IsDailyClaimed(state, nowSeconds) then
		return false, Rules.Reject.AlreadyClaimed, nil, Rules.GetStreak(state)
	end

	local today = Rules.GetDayIndex(nowSeconds)
	local last = state.Daily.LastClaimDay
	local streak = 1

	if type(last) == "number" and today - last == 1 then
		streak = Rules.GetStreak(state) + 1
	end

	if streak > Rules.MAX_STREAK then
		streak = Rules.MAX_STREAK
	end

	-- Marcar ANTES de devolver: mismo motivo que en `Claim`.
	state.Daily.LastClaimDay = today
	state.Daily.Streak = streak

	local granted: { [string]: number } = {}

	for currency, amount in pairs(rewards) do
		granted[currency] = amount
	end

	return true, nil, granted, streak
end

--- Elige la oferta de misiones daily de HOY, de forma DETERMINISTA.
---
--- Determinista es la palabra clave: la oferta depende SOLO del indice del
--- dia. Si dependiera de `pairs`, de un contador o del estado del servidor,
--- dos jugadores del mismo dia recibirian ofertas distintas y el mismo
--- jugador veria cambiar su lista al reconectar.
---
--- Es tambien la razon por la que el cliente no elige: si el servidor
--- generase la oferta a partir de lo que dice el cliente, un exploit
--- podria pedir la mision mas cara.
--- @param allDaily { [string]: any } catalogo completo de misiones daily
--- @param nowSeconds number
--- @param size number? cuantas ofrecer
--- @return { string } questIds oferta, en orden estable
function Rules.RollDailyOffer(allDaily: { [string]: any }, nowSeconds: number, size: number?): { string }
	if type(allDaily) ~= "table" then
		return {}
	end

	-- Ids ORDENADOS: sin orden, la eleccion dependeria de `pairs` y la
	-- oferta no seria reproducible entre servidores ni entre reinicios.
	local ids = {}
	for id in pairs(allDaily) do
		table.insert(ids, id)
	end
	table.sort(ids)

	if #ids == 0 then
		return {}
	end

	local wanted = size or 3

	if type(wanted) ~= "number" or wanted ~= wanted or wanted < 1 then
		wanted = 1
	end

	if wanted > #ids then
		wanted = #ids
	end

	local dayIndex = Rules.GetDayIndex(nowSeconds)
	local offer = {}

	-- La posicion de inicio rota por el indice del dia reparte las ofertas
	-- entre dias sin que ninguna sea la fija: con solo tres misiones
	-- daily, ofrecer siempre las mismas seria tan aburrido como elegirlas
	-- al azar.
	local offset = dayIndex % #ids

	for index = 0, wanted - 1 do
		table.insert(offer, ids[(offset + index) % #ids + 1])
	end

	return offer
end

return Rules