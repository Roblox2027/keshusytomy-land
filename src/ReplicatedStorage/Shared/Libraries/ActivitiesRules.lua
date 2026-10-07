--!strict
--[[
	ActivitiesRules
	ACTIVIDADES DE EXPLORACION (MASTER MISSION V2 - FASE 3).

	POR QUE EXISTE
	--------------
	Hasta ahora el mundo se "limpia" matando todo lo que se mueve. Las
	actividades danle al jugador algo que no es solo caza: rescate,
	coleccion, mecanica de mapa, defensa contra oleadas, caza dirigida y
	descubrimiento de puntos de interes.

	QUE VIVE AQUI Y QUE NO
	----------------------
	Aqui vive la maquina de estados y el catalogo de validacion: progreso,
	completion, reclamo atomico, cooldowns, oferta determinista y auditoria.
	Es PURO: no toca el motor, asi que se prueba con `luau.exe`. El servicio
	(`ActivityService`) aporta el hilo, las partes, los ProximityPrompt y la
	lectura de posiciones: lo que no se puede probar en local.

	LA REGLA DE ORO
	---------------
	Reclamar es ATOMICO y NO se puede repetir. `Claim` MARCA el reclamo DENTRO
	de la misma operacion que lo autoriza, y si algo falla despues el reclamo
	queda hecho. Es la misma eleccion que en `QuestRules.Claim` y por el mismo
	motivo: perder una recompensa es un contratiempo; pagarla dos veces es un
	agujero.

	LA REGLA ANTI-DUPLICACION
	-------------------------
	Una actividad completada no se vuelve a OFRECER de inmediato: `Cooldown`
	despues de completarse impide farmear la misma actividad en bucle, y el
	token de secuencia en `Claim` impide reclamar dos veces la misma.

	POR QUE NO SE USA `require` AQUI
	---------------------------------
	Igual que `RemoteSchema`, `QuestRules` y `CodeRules`: en el interprete de
	pruebas `script` no existe, asi que las dependencias se INYECTAN. El
	catalogo (`ActivityCatalog`) recibe las reglas por `Configure` para
	poder normalizar ids sin un `require` circular.
]]

local Rules = {}

-- ---------------------------------------------------------------------------
-- TIPOS DE ACTIVIDAD
-- ---------------------------------------------------------------------------

Rules.ActivityType = {
	Rescue = "Rescue",
	Collection = "Collection",
	Mechanic = "Mechanic",
	Defense = "Defense",
	Hunt = "Hunt",
	Discovery = "Discovery",
}

-- Motivos de rechazo. Texto estable: la UI decide que texto mostrar.
Rules.Reject = {
	NoProfile = "no_profile",
	UnknownActivity = "unknown_activity",
	InvalidActivityId = "invalid_activity_id",
	InvalidTarget = "invalid_target",
	InvalidReward = "invalid_reward",
	InvalidType = "invalid_type",
	NotComplete = "not_complete",
	AlreadyClaimed = "already_claimed",
	OnCooldown = "on_cooldown",
}

-- ---------------------------------------------------------------------------
-- LIMITES Y RITMO
-- ---------------------------------------------------------------------------

--- Segundos que dura un "dia" de juego. Igual que `QuestRules.DAY_SECONDS`:
--- 24h reales y no el dia calendario, para que la oferta sea identica para
--- todos los jugadores del mismo dia.
Rules.DAY_SECONDS = 86400

--- Cuantas actividades ofrecer por mundo en un dia.
---
--- Tres son suficientes para que haya eleccion sin abrumar: el jugador elige
--- una y las otras dos siguen ahi si falla.
Rules.OFFER_SIZE = 3

--- Cooldown POR DEFECTO de una actividad tras completarse.
---
--- No es un numero magico: el catalogo lo puede sobreescribir por actividad.
--- Ciento veinte segundos (2 min) es el minimo que evita farmear un mismo
--- punto de interes sin bloquear una zona para un jugador lento.
Rules.DEFAULT_COOLDOWN = 120

--- Cuantas actividades completadas se conservan por tipo.
---
--- Sin tope, el perfil del jugador creceria sin limite. Se conservan las
--- ULTIMAS, que son las que el jugador puede volver a ver.
Rules.MAX_TRACKED_PER_TYPE = 60

-- ---------------------------------------------------------------------------
-- ESTADO DEL JUGADOR
-- ---------------------------------------------------------------------------

--- Crea el estado de actividades de un jugador.
---
--- Las sub-tables nacen VACIAS pero PRESENTES: una clave ausente obliga a
--- todos los lectores a preguntar "ya existe?". Con la forma siempre presente
--- se lee sin ningun `if`.
--- @param playerId number
--- @return any state
function Rules.NewPlayerState(playerId: number): any
	return {
		PlayerId = playerId,
		-- activityId (normalizado) -> { Progress: number, CompletedAt: number? }
		Progress = {},
		-- activityId (normalizado) -> numero de secuencia del reclamo
		Claims = {},
		-- activityId (normalizado) -> timestamp hasta el que no se ofrece
		CooldownUntil = {},
		-- type -> { [activityId] = true }, historial acotado de completadas
		Completed = {},
		Sequence = 0,
	}
end

-- ---------------------------------------------------------------------------
-- NORMALIZACION
-- ---------------------------------------------------------------------------

--- Normaliza el identificador de una actividad.
---
--- ES IDENTICO al criterio de `QuestRules.NormalizeId` y por el mismo motivo:
--- impide que un id ambiguo se confunda con otro, y que una cadena con
--- corchetes o comillas acabe en un log.
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

	if not trimmed:match("^[%a%d]+$") then
		return nil
	end

	return trimmed
end

-- ---------------------------------------------------------------------------
-- DEFINICION
-- ---------------------------------------------------------------------------

--- Comprueba que la definicion de una actividad es utilizable.
---
--- El `World` es opcional (una actividad puede ser global), pero si se
--- declara tiene que ser un id de mundo conocido: se comprueba contra la lista
--- que el servicio inyecta en `Audit`, no aqui, para que este modulo siga sin
--- depender de `WorldAccessRules`.
--- @param definition any
--- @return boolean valid
--- @return string? reason
function Rules.IsDefinitionValid(definition: any): (boolean, string?)
	if type(definition) ~= "table" then
		return false, Rules.Reject.UnknownActivity
	end

	if not Rules.NormalizeId(definition.Id) then
		return false, Rules.Reject.InvalidActivityId
	end

	local activityType = definition.Type

	if type(activityType) ~= "string" then
		return false, Rules.Reject.InvalidType
	end

	local known = false
	for _, kind in pairs(Rules.ActivityType) do
		if kind == activityType then
			known = true
			break
		end
	end

	if not known then
		return false, Rules.Reject.InvalidType
	end

	-- `Target` es un entero POSITIVO. Una actividad con `Target = 0` esta
	-- completada de salida; `Target < 0` no tiene sentido.
	local target = definition.Target

	if type(target) ~= "number" or target ~= target then
		return false, Rules.Reject.InvalidTarget
	end

	if target <= 0 or target % 1 ~= 0 then
		return false, Rules.Reject.InvalidTarget
	end

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

--- Devuelve la entrada de progreso de una actividad, creandola si hace falta.
---
--- El `typeof` protege contra un perfil corrupto o migrado de otra forma.
--- @param state any
--- @param activityId string id YA normalizado
--- @return any entry
	local function entryOf(state: any, activityId: string): any
	if type(state) ~= "table" then
		return nil
	end

	if type(state.Progress) ~= "table" then
		state.Progress = {}
	end

	local entry = state.Progress[activityId]

	if type(entry) ~= "table" then
		entry = { Progress = 0, CompletedAt = nil }
		state.Progress[activityId] = entry
	end

	return entry
end

-- ---------------------------------------------------------------------------
-- PROGRESO
-- ---------------------------------------------------------------------------

--- Progreso actual de una actividad.
---
--- NORMALIZA el id, igual que `Advance` y `Claim`. La coherencia no es
--- cosmetica: `Advance` guarda bajo la clave normalizada, asi que una lectura
--- sin normalizar devolveria SIEMPRE cero para un id escrito como lo escribe
--- el catalogo (`HUNT_FOREST_3`). El sintoma seria "las actividades no
--- avanzan".
--- @param state any
--- @param activityId string
--- @return number
function Rules.GetProgress(state: any, activityId: string): number
	if type(state) ~= "table" or type(state.Progress) ~= "table" then
		return 0
	end

	local id = Rules.NormalizeId(activityId)

	if not id then
		return 0
	end

	local entry = state.Progress[id]

	if type(entry) ~= "table" or type(entry.Progress) ~= "number" then
		return 0
	end

	return entry.Progress
end

--- Avanza el progreso de una actividad.
---
--- `amount` se ACOTA al objetivo: una actividad de 5 rescates que recibe un
--- evento de 50 no guarda 50, guarda 5. La razon es de persistencia: el
--- perfil guardaria un numero que no significa nada y la UI dibujaria "50/5".
---
--- Una actividad YA COMPLETADA no se vuelve a completar ni cambia su marca de
--- tiempo: si no, un jugador que farmasee una actividad terminaria cambiando
--- su `CompletedAt` y el historial dejaria de ser util.
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

	local activityId = Rules.NormalizeId(definition.Id)

	if not activityId then
		return 0, false
	end

	-- Un incremento no es un numero FINITO y positivo es ruido, no juego: se
	-- ignora en vez de propagarse. Ignorarlo es seguro porque el unico que
	-- llama con un valor real es el servidor, en un evento de juego.
	if
		type(amount) ~= "number"
		or amount ~= amount
		or amount == math.huge
		or amount == -math.huge
		or amount <= 0
	then
		return Rules.GetProgress(state, activityId), false
	end

	local entry = entryOf(state, activityId)

	if not entry then
		return 0, false
	end

	if entry.CompletedAt ~= nil then
		return entry.Progress, false
	end

	local target = definition.Target
	local next = math.min(entry.Progress + amount, target)

	-- `floor` y no `min` solo: el progreso se muestra como `n/objetivo` y
	-- un valor fraccionario se veria raro. Se redondea ABAJO para no
	-- declarar completada una actividad a la que le falta un entero.
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

--- Anota una actividad como completada en el historial acotado por tipo.
--- @param state any
--- @param definition any
function Rules._recordCompletion(state: any, definition: any)
	if type(state) ~= "table" then
		return
	end

	if type(state.Completed) ~= "table" then
		state.Completed = {}
	end

	local activityType = definition.Type

	if type(activityType) ~= "string" then
		activityType = "World"
	end

	local bucket = state.Completed[activityType]

	if type(bucket) ~= "table" then
		bucket = {}
		state.Completed[activityType] = bucket
	end

	local activityId = Rules.NormalizeId(definition.Id)

	if not activityId then
		return
	end

	bucket[activityId] = true

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

--- Indica si una actividad esta completada (y por tanto reclamable).
---
--- No necesita la definicion: el unico que la necesita es `Advance`, que ya
--- compara con `Target`. Por eso se guarda `CompletedAt` en la entrada, y no
--- el resultado de una comparacion que habria que repetir aqui.
--- @param state any
--- @param activityId string
--- @return boolean complete
function Rules.IsComplete(state: any, activityId: string): boolean
	local id = Rules.NormalizeId(activityId)

	if not id then
		return false
	end

	if type(state) ~= "table" or type(state.Progress) ~= "table" then
		return false
	end

	local entry = state.Progress[id]

	return type(entry) == "table" and entry.CompletedAt ~= nil
end

--- Indica si una actividad ya fue reclamada.
--- @param state any
--- @param activityId string
--- @return boolean claimed
function Rules.IsClaimed(state: any, activityId: string): boolean
	local id = Rules.NormalizeId(activityId)

	if not id then
		return false
	end

	if type(state) ~= "table" or type(state.Claims) ~= "table" then
		return false
	end

	return state.Claims[id] ~= nil
end

-- ---------------------------------------------------------------------------
-- COOLDOWN
-- ---------------------------------------------------------------------------

--- Indica si una actividad esta en cooldown (recien completada).
---
--- El cooldown impide que la oferta rote a la misma actividad completada en
--- bucle: farmear un punto de interes no puede ser la unica forma de jugar.
--- @param state any
--- @param activityId string
--- @param now number
--- @return boolean onCooldown
function Rules.IsOnCooldown(state: any, activityId: string, now: number): boolean
	local id = Rules.NormalizeId(activityId)

	if not id then
		return false
	end

	if type(state) ~= "table" or type(state.CooldownUntil) ~= "table" then
		return false
	end

	local until_ = state.CooldownUntil[id]

	if type(until_) ~= "number" then
		return false
	end

	local t = tonumber(now)

	if not t or t ~= t then
		return false
	end

	return t < until_
end

--- Fija el cooldown de una actividad hasta un instante dado.
--- @param state any
--- @param activityId string
--- @param untilTime number
function Rules.SetCooldown(state: any, activityId: string, untilTime: number)
	if type(state) ~= "table" then
		return
	end

	if type(state.CooldownUntil) ~= "table" then
		state.CooldownUntil = {}
	end

	local id = Rules.NormalizeId(activityId)

	if not id then
		return
	end

	state.CooldownUntil[id] = untilTime
end

-- ---------------------------------------------------------------------------
-- RECLAMO (ATOMICO)
-- ---------------------------------------------------------------------------

--- Reclama la recompensa de una actividad completada, de forma ATOMICA.
---
--- El orden importa y es el que hace imposible el pago doble:
---
---     1. el estado es valido?
---     2. la actividad existe?
---     3. esta YA reclamada?      -> no, no se toca nada
---     4. esta COMPLETADA?        -> no, no se toca nada
---     5. MARCA el reclamo
---     6. devuelve la recompensa
---
--- El paso 5 ocurre DENTRO de esta llamada: dos peticiones simultaneas del
--- mismo jugador (el doble clic, o el reintento tras perder la conexion)
--- encuentran el hueco ocupado y solo una paga.
--- @param state any
--- @param activityId any
--- @param definitions { [string]: any } catalogo indexado por id normalizado
--- @return boolean accepted
--- @return string? rejection
--- @return { [string]: number }? rewards
function Rules.Claim(
	state: any,
	activityId: any,
	definitions: { [string]: any }
): (boolean, string?, { [string]: number }?)
	if type(state) ~= "table" or type(definitions) ~= "table" then
		return false, Rules.Reject.NoProfile, nil
	end

	if type(state.Claims) ~= "table" then
		state.Claims = {}
	end

	local id = Rules.NormalizeId(activityId)

	if not id then
		return false, Rules.Reject.InvalidActivityId, nil
	end

	local definition = definitions[id]

	if not definition then
		return false, Rules.Reject.UnknownActivity, nil
	end

	-- La definicion se revalida aqui, no solo al arrancar: una entrada del
	-- catalogo modificada en caliente con una recompensa negativa haria que
	-- "reclamar" RESTARA saldo.
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
	-- consumido aunque la entrega de la recompensa falle despues.
	state.Sequence = (type(state.Sequence) == "number" and state.Sequence or 0) + 1
	state.Claims[id] = state.Sequence

	local rewards = definition.Rewards
	local granted: { [string]: number } = {}

	for currency, amount in pairs(rewards) do
		granted[currency] = amount
	end

	return true, nil, granted
end

-- ---------------------------------------------------------------------------
-- OFERTA DIARIA (determina por indice del dia)
-- ---------------------------------------------------------------------------

--- Indice del dia actual. Es el unico reloj que necesita el sistema de ofertas.
--- @param nowSeconds number reloj inyectado (epoch en segundos)
--- @return number dayIndex
function Rules.GetDayIndex(nowSeconds: number): number
	if type(nowSeconds) ~= "number" or nowSeconds ~= nowSeconds then
		return 0
	end

	return math.floor(nowSeconds / Rules.DAY_SECONDS)
end

--- Elige la oferta de actividades de HOY para un mundo, de forma DETERMINISTA.
---
--- Determinista es la palabra clave: la oferta depende SOLO del indice del
--- dia y la lista de actividades del mundo. Si dependiera de `pairs`, de un
--- contador o del estado del servidor, dos jugadores del mismo dia recibirian
--- ofertas distintas y el mismo jugador veria cambiar su lista al reconectar.
---
--- Es la razon por la que el cliente no elige: si el servidor generase la
--- oferta a partir de lo que dice el cliente, un exploit podria pedir la
--- actividad mas cara.
--- @param worldActivities { [string]: any } definiciones del mundo (id normalizado -> def)
--- @param nowSeconds number
--- @param size number? cuantas ofrecer
--- @return { string } activityIds oferta, en orden estable
function Rules.RollDailyOffer(
	worldActivities: { [string]: any },
	nowSeconds: number,
	size: number?
): { string }
	if type(worldActivities) ~= "table" then
		return {}
	end

	-- Ids ORDENADOS: sin orden, la eleccion dependeria de `pairs` y la oferta
	-- no seria reproducible entre servidores ni entre reinicios.
	local ids = {}
	for id in pairs(worldActivities) do
		table.insert(ids, id)
	end

	table.sort(ids)

	if #ids == 0 then
		return {}
	end

	local wanted = size or Rules.OFFER_SIZE

	if type(wanted) ~= "number" or wanted ~= wanted or wanted < 1 then
		wanted = 1
	end

	if wanted > #ids then
		wanted = #ids
	end

	local dayIndex = Rules.GetDayIndex(nowSeconds)
	local offer = {}

	-- La posicion de inicio rota por el indice del dia: con pocas actividades
	-- por mundo, ofrecer siempre las mismas seria aburrido.
	local offset = dayIndex % #ids

	for index = 0, wanted - 1 do
		table.insert(offer, ids[(offset + index) % #ids + 1])
	end

	return offer
end

--- Cooldown de una actividad tras completarse.
---
--- Lee `Cooldown` de la definicion; si no lo declara, usa el default. Separado
--- de `IsOnCooldown` porque es una propiedad del DATO, no del estado.
--- @param definition any
--- @return number
function Rules.CompletionCooldown(definition: any): number
	local cooldown = tonumber(definition.Cooldown)

	if
		not cooldown
		or cooldown ~= cooldown
		or cooldown <= 0
		or cooldown % 1 ~= 0
	then
		return Rules.DEFAULT_COOLDOWN
	end

	return cooldown
end

-- ---------------------------------------------------------------------------
-- AUDITORIA DEL CATALOGO
-- ---------------------------------------------------------------------------

--- Comprueba que el catalogo de actividades es coherente.
---
--- Se ejecuta al ARRANCAR (y en tests): una actividad con un tipo desconocido,
--- un objetivo <= 0 o una recompensa rota debe aparecer como fallo de arranque,
--- no como "esta actividad no existe" un dia cualquiera.
---
--- `knownWorlds` es opcional: si se pasa (lo hace `ActivityService.Init` con
--- `WorldAccessRules.WorldOrder`), la auditoria comprueba que el `World` de
--- cada actividad es un mundo real. Sin el, solo valida estructura.
--- @param definitions { [string]: any } indexado por id normalizado
--- @param knownWorlds { string }? mundos validos
--- @return { string } problemas lista vacia = todo cuadra
function Rules.Audit(definitions: { [string]: any }, knownWorlds: { string }?): { string }
	local problems: { string } = {}

	if type(definitions) ~= "table" then
		table.insert(problems, "catalogo invalido (no es tabla)")
		return problems
	end

	local worldSet: { [string]: boolean } = {}

	if knownWorlds then
		for _, id in ipairs(knownWorlds) do
			worldSet[id] = true
		end
	end

	for key, definition in pairs(definitions) do
		if Rules.NormalizeId(definition.Id) ~= key then
			table.insert(
				problems,
				("'%s': la clave '%s' no es la forma normalizada"):format(
					tostring(definition.Id),
					key
				)
			)
		end

		local valid, reason = Rules.IsDefinitionValid(definition)

		if not valid then
			table.insert(
				problems,
				("'%s': definicion invalida (%s)"):format(tostring(definition.Id), tostring(reason))
			)
		end

		if knownWorlds and type(definition.World) == "string" then
			if not worldSet[definition.World] then
				table.insert(
					problems,
					("'%s': World '%s' no es un mundo conocido"):format(
						tostring(definition.Id),
						tostring(definition.World)
					)
				)
			end
		end
	end

	-- Un mundo conocido no puede quedar sin actividades: la oferta giraria
	-- en vacío. Esa ausencia es el fallo mas silencioso, porque el servicio
	-- no errorea, solo no ofrece nada.
	if knownWorlds then
		local covered: { [string]: boolean } = {}

		for _, definition in pairs(definitions) do
			if type(definition.World) == "string" then
				covered[definition.World] = true
			end
		end

		for _, worldId in ipairs(knownWorlds) do
			if not covered[worldId] then
				table.insert(problems, ("'%s': sin actividades declaradas"):format(worldId))
			end
		end
	end

	return problems
end

return Rules
