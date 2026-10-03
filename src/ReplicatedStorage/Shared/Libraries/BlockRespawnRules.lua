--!strict
--[[
	BlockRespawnRules
	Logica PURA de la reaparicion de bloques destruibles.

	POR QUE UN MODULO PURO Y NO DENTRO DE `DestructionService`
	----------------------------------------------------------
	La reaparicion aleatoria es la parte del sistema con mas formas de
	fallar en silencio: un temporizador por bloque, una copia duplicada, un
	timer que reaparece un bloque ya reparado. Todo eso es una CUENTA y una
	COMPARACION, no una llamada al motor, asi que se puede ejecutar de verdad
	con `luau.exe` y comprobar 100 destrucciones seguidas.

	Es la MISMA separacion que ya usa el proyecto con `CombatMath`,
	`CoreRules` y `AudioPool`: la regla se prueba sin motor y el servicio
	solo la aplica.

	EL FALLO QUE EVITA
	------------------
	Si el respawn se implementa con un `task.delay` por destruccion y nada
	mas, entonces:
	- dos explosiones cerca dejan DOS temporizadores para el mismo bloque;
	- la reparacion de fin de ronda deja el bloque en pie, pero el
	  temporizador sigue vivo y lo "repara" otra vez;
	- el bloque puede reaparecer en un mundo que ya no esta activo.
	Con un token por generacion (`Destroy` / `CanRespawn` / `BeginRespawn`)
	cada programacion es INVALIDABLE y el respawn es idempotente: llamarlo
	dos veces no produce dos bloques.

	POR QUE SE INYECTA LA FUNCION DE AZAR
	-------------------------------------
	`RollDelay` no llama a `Random` ni a `math.random`: recibe una funcion
	`roll(min, max) -> number`. Dos motivos:
	1. El servidor decide la SEMILLA, asi que el cliente no puede predecir
	   ni forzar el momento en que un bloque reaparece.
	2. `Random` no existe en el interprete standalone de `luau.exe` que
	   ejecuta las pruebas, y una regla que solo se puede probar dentro de
	   Roblox es una regla que no se prueba.
]]

local Rules = {}

-- Estados del ciclo de vida de un bloque. Son cadenas para poder leerlos
-- en el explorador de Studio y en los logs.
Rules.State = {
	-- El bloque esta en pie y cumple su papel normal.
	Active = "Active",
	-- Destruido por una bomba. Espera el tiempo aleatorio de reaparicion.
	Destroyed = "Destroyed",
	-- El respawn vencio y se esta comprobando si puede materializarse.
	-- Es el estado que hace idempotente el respawn.
	Respawning = "Respawning",
	-- El mundo se apago (fin de ronda, cierre). El bloque no reaparece:
	-- `Restore` lo devuelve al estado original.
	Locked = "Locked",
}

export type BlockRecord = {
	Key: string,
	State: string,
	-- Momento (os.clock) en que se programo el respawn.
	ScheduledAt: number,
	-- Momento (os.clock) en que el respawn puede ocurrir.
	ReadyAt: number,
	-- Espera ELEGIDA para esta destruccion, dentro del rango.
	Delay: number,
	-- Generacion del bloque. Cada destruccion la incrementa; un timer
	-- antiguo lleva una generacion que ya no es la buena y se descarta.
	Generation: number,
	-- Mundo al que pertenece el bloque. Un respawn de un mundo que ya no
	-- esta activo se rechaza aqui y no en un `if` repartido por el servicio.
	World: string?,
}

export type RespawnContext = {
	-- Generacion que el temporizador cree que esta reparando. `nil`
	-- significa "sin token" y se acepta (reparacion de ronda).
	generation: number?,
	-- Si el mundo sigue jugando. Un mundo apagado no admite respawns.
	worldActive: boolean,
	-- Si ya existe una copia VIVA de este bloque.
	hasActiveCopy: boolean?,
	-- Si hay una entidad incompatible en la posicion del bloque.
	hasBlockingEntity: boolean?,
}

-- ROLLO_DEFAULT: usada cuando el llamante no inyecta nada. No es
-- aleatoria, y es DELIBERADO: en produccion el servidor siempre inyecta
-- su generador con semilla. Aqui solo hace falta que el modulo se pueda
-- cargar y probar sin motor.
local function defaultRoll(min: number, _max: number): number
	return min
end

Rules.DefaultRoll = defaultRoll

--- Crea el registro de un bloque activo.
--- @param key string identificador estable del bloque
--- @param worldId string? mundo al que pertenece
--- @return BlockRecord
function Rules.NewRecord(key: string, worldId: string?): BlockRecord
	return {
		Key = key,
		State = Rules.State.Active,
		ScheduledAt = 0,
		ReadyAt = 0,
		Delay = 0,
		Generation = 0,
		World = worldId,
	}
end

--- Acota un numero al rango `[min, max]`.
---
--- El servicio nunca debe receber una espera negativa: `task.delay` con un
--- numero negativo revienta el hilo entero.
--- @param value number
--- @param min number
--- @param max number
--- @return number
local function clamp(value: number, min: number, max: number): number
	if value < min then
		return min
	end

	if value > max then
		return max
	end

	return value
end

--- Elige el tiempo de espera de UNA destruccion.
---
--- @param roll fun(min: number, max: number): number generador del servidor
--- @param min number espera minima en segundos
--- @param max number espera maxima en segundos
--- @return number seconds espera dentro de [min, max]
function Rules.RollDelay(roll: (number, number) -> number, min: number, max: number): number
	-- Rango degenerado: `max < min` se corrige en lugar de fallar, para que
	-- el llamante pueda escribir el rango en cualquier orden.
	local low = min
	local high = max

	if low > high then
		low, high = high, low
	end

	-- El suelo es CERO, no `low`. Un rango escrito en negativo
	-- (`RespawnMin = -5`) produciria un `ReadyAt` en el pasado, el bloque
	-- reapareceria en el instante de su propia destruccion y el rango
	-- "aleatorio" no existiria. Acotar aqui hace que un rango mal escrito
	-- degrade a "reaparicion inmediata" en vez de romper el sistema.
	if low < 0 then
		low = 0
	end

	if high < 0 then
		high = 0
	end

	-- Sin rango no hay aleatoriedad que aplicar. Se devuelve el minimo: la
	-- reaparicion sigue siendo valida.
	if high - low <= 0 then
		return low
	end

	-- `roll` puede devolver un valor fuera de rango (un `math.random` mal
	-- acotado, o un redondeo), asi que el resultado se acota OTRA vez. Un
	-- `ReadyAt` por encima del maximo daria un bloque que "vuelve tarde"
	-- sin explicacion, que es exactamente el bug que se quiere evitar.
	return clamp(roll(low, high), low, high)
end

--- Marca un bloque como destruido y programa su reaparicion.
---
--- Devuelve `false` si el bloque no estaba `Active`: un bloque ya
--- destruido no se vuelve a programar. Sin esta comprobacion, dos
--- explosiones seguidas sobre el mismo bloque dejarian DOS esperas
--- pendientes y el bloque reapareceria dos veces.
---
--- @param record BlockRecord
--- @param roll fun(min: number, max: number): number generador del servidor
--- @param now number os.clock actual
--- @param min number espera minima
--- @param max number espera maxima
--- @return boolean scheduled
--- @return number delay espera elegida
function Rules.Destroy(
	record: BlockRecord,
	roll: (number, number) -> number,
	now: number,
	min: number,
	max: number
): (boolean, number)
	if record.State ~= Rules.State.Active then
		return false, 0
	end

	local delay = Rules.RollDelay(roll, min, max)

	record.State = Rules.State.Destroyed
	record.Generation += 1
	record.ScheduledAt = now
	record.Delay = delay
	record.ReadyAt = now + delay

	return true, delay
end

--- Indica si el plazo del respawn ya vencio.
--- @param record BlockRecord
--- @param now number os.clock actual
--- @return boolean
function Rules.IsReady(record: BlockRecord, now: number): boolean
	return record.State == Rules.State.Destroyed and now >= record.ReadyAt
end

--- Comprueba si un respawn puede materializarse.
---
--- Cada comprobacion evita un fallo DISTINTO:
---
--- 1. `State == Destroyed` -> un bloque ya reparado no se repara dos veces.
--- 2. plazo vencido -> el bloque no reaparece antes de tiempo por un
---    redondeo del temporizador.
--- 3. mundo ACTIVO -> un timer que sobrevive a la ronda no saca bloques
---    de un mundo que ya se vacio.
--- 4. `generation` esperada -> un timer de una destruccion ANTERIOR se
---    descarta aunque su plazo ya haya vencido.
--- 5. `hasActiveCopy` -> si ya hay una copia viva de este bloque, no se
---    crea otra (el `Block_A Block_A Block_A` que se prohibe).
--- 6. `hasBlockingEntity` -> si una entidad incompatible ocupa la posicion,
---    el respawn se aplaza en vez de aparecer atravesado.
---
--- @param record BlockRecord
--- @param now number os.clock actual
--- @param context RespawnContext
--- @return boolean allowed
--- @return string? reason motivo del rechazo, util para logs y pruebas
function Rules.CanRespawn(record: BlockRecord, now: number, context: RespawnContext): (boolean, string?)
	if record.State ~= Rules.State.Destroyed then
		return false, "estado no destruido"
	end

	if now < record.ReadyAt then
		return false, "aun no ha vencido el plazo"
	end

	if context.worldActive == false then
		return false, "mundo inactivo"
	end

	-- Sin `generation` no se filtra por generacion: es el caso de un respawn
	-- sin token (por ejemplo una reparacion de ronda).
	if context.generation ~= nil and context.generation ~= record.Generation then
		return false, "generacion obsoleta"
	end

	if context.hasActiveCopy == true then
		return false, "ya existe una copia activa"
	end

	if context.hasBlockingEntity == true then
		return false, "hay una entidad en la posicion"
	end

	return true, nil
end

--- Pasa el bloque a `Respawning`.
---
--- Es un paso SEPARADO de `CanRespawn` a proposito: es lo que hace el
--- sistema idempotente. Dos tareas que superen la comprobacion en el mismo
--- frame llaman las dos a `BeginRespawn`, pero solo la PRIMERA obtiene
--- `true`: la segunda ve que el estado ya no es `Destroyed` y se retira.
--- @param record BlockRecord
--- @return boolean began
function Rules.BeginRespawn(record: BlockRecord): boolean
	if record.State ~= Rules.State.Destroyed then
		return false
	end

	record.State = Rules.State.Respawning
	return true
end

--- Cierra el respawn y devuelve el bloque a `Active`.
--- @param record BlockRecord
--- @return boolean
function Rules.FinishRespawn(record: BlockRecord): boolean
	if record.State ~= Rules.State.Respawning then
		return false
	end

	record.State = Rules.State.Active
	record.ReadyAt = 0
	record.Delay = 0
	return true
end
--- Bloquea el bloque: el mundo se apago y el respawn ya no puede ocurrir.
---
--- El paso es reversible con `Restore`, que es justo lo que hay que hacer
--- al terminar la ronda: todos los registros vuelven a `Active` y ningun
--- temporizador pendiente encuentra un bloque valido.
--- @param record BlockRecord
function Rules.Lock(record: BlockRecord)
	record.State = Rules.State.Locked
end

--- Devuelve un bloque a `Active`, cancelando cualquier respawn pendiente.
--- @param record BlockRecord
--- @return boolean restored true si el bloque no estaba ya `Active`
function Rules.Restore(record: BlockRecord): boolean
	if record.State == Rules.State.Active then
		return false
	end

	record.State = Rules.State.Active
	record.ReadyAt = 0
	record.Delay = 0
	record.ScheduledAt = 0
	return true
end

--- Cuenta bloques en un estado.
--- @param records { [string]: BlockRecord }
--- @param state string
--- @return number
function Rules.CountInState(records: { [string]: BlockRecord }, state: string): number
	local count = 0

	for _, record in pairs(records) do
		if record.State == state then
			count += 1
		end
	end

	return count
end

--- Detecta claves de bloque repetidas en una tabla de registros.
---
--- Es la comprobacion DIRECTA del requisito "es imposible terminar con
--- cuatro copias del mismo bloque". En el servicio la clave es el indice
--- del bloque dentro de su carpeta, asi que dos copias del mismo bloque en
--- la misma carpeta comparten `Key`: si se repite, hay duplicados y hay que
--- decirlo en el log en vez de dejarlo pasar.
--- @param records { [string]: BlockRecord }
--- @return { string } claves duplicadas
function Rules.FindDuplicateKeys(records: { [string]: BlockRecord }): { string }
	local seen = {}
	local duplicates = {}

	for _, record in pairs(records) do
		local keyId = record.Key

		if keyId == nil or keyId == "" then
			table.insert(duplicates, "<sin clave>")
		elseif seen[keyId] then
			table.insert(duplicates, keyId)
		else
			seen[keyId] = true
		end
	end

	return duplicates
end

return Rules