--!strict
--[[
	DataService
	Persistencia: carga, guardado, autosave, migraciones y seguridad de
	sesion.

	POR QUE UN SERVICIO APARTE
	--------------------------
	Porque el DataStore FALLA, y cuando falla hay que decidir algo. Si el
	perfil viviera dentro de este servicio, un fallo de red dejaria al
	jugador sin economia, sin inventario y sin nivel. Separado, el perfil
	en memoria sigue siendo valido y el juego sigue siendo jugable.

	LAS CUATRO REGLAS QUE NO SE NEGOCIAN
	------------------------------------
	1. NUNCA se dice "guardado" si no se guardo. Todo `SaveProfile`
	   devuelve un booleano real y el perfil solo se marca limpio si la
	   escritura fue de verdad.

	2. NUNCA se pisa un perfil que no se pudo leer. Si `LoadProfile`
	   falla, se juega en memoria SIN persistencia, pero no se guarda
	   nada: un jugador con un fallo de red momentaneo perderia su
	   partida de meses si le sobrescribieras su perfil con uno vacio.

	3. NUNCA se guarda en cada cambio. Se marca `dirty` y el `autosave`
	   guarda cada intervalo. Un DataStore por cada kill es throttling
	   garantizado y, con el, perdida de datos garantizada.

	4. NUNCA se depende solo de `PlayerRemoving`. Si el servidor muere de
	   golpe, ese evento no se dispara. Por eso hay autosave periodico.

	SEGURIDAD DE SESION
	-------------------
	Un `UserId` no puede estar en dos servidores a la vez. El bloqueo por
	`jobId` es la garantia de que el segundo servidor NO entra a escribir
	encima del primero. Si el bloqueo falla, el servicio NO concede acceso
	al perfil y lo dice: es preferible que el jugador espere a que el otro
	servidor se vacie antes que perder su progreso.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONFIG = SHARED:WaitForChild("Config")
local UTILS = SHARED:WaitForChild("Utils")

local GameConfig = require(CONFIG:WaitForChild("GameConfig"))
local ProfileSchema = require(SHARED:WaitForChild("Libraries"):WaitForChild("ProfileSchema"))
local Logger = require(UTILS:WaitForChild("Logger"))

local Service = {}

Service.IsInitialized = false

-- `DataStoreService` se resuelve aqui y NO en la cabecera a proposito.
--
-- En un entorno donde no existe (pruebas, o un lugar sin API de datos
-- habilitada), `GetService` LANZA. Si se resolviera arriba del todo, el
-- modulo entero no cargaria y TODOS los servicios que lo requieren
-- caerian en cascada, incluida la ronda. Se resuelve aqui, dentro de un
-- `pcall`, para que su ausencia sea un modo degradado VISIBLE y no un
-- servidor muerto.
local DataStoreService = nil
local dataStoreAvailable = false

do
	local ok, service = pcall(function()
		return game:GetService("DataStoreService")
	end)

	if ok and service then
		DataStoreService = service
		dataStoreAvailable = true
	end
end

-- UserId -> { Profile = ..., Dirty = boolean, Readable = boolean }
Service._sessions = {}

-- UserId -> jobId que tiene el bloqueo. Sirve para no liberar el bloqueo
-- de otro servidor.
Service._locks = {}

-- Acumulador de autosave en segundos.
Service._autosaveAccumulator = 0

-- Contadores para observabilidad.
Service._stats = { loads = 0, saves = 0, saveFailures = 0, lockFailures = 0 }

-- Maid recibido en Init.
local MaidRef = nil

-- ---------------------------------------------------------------
-- Ciclo de vida
-- ---------------------------------------------------------------

--- Inicializacion del servicio. Idempotente.
--- @param maid any?
--- @return boolean success
function Service.Init(maid: any?): boolean
	MaidRef = maid
	Service._sessions = {}
	Service._locks = {}
	Service._autosaveAccumulator = 0
	Service._stats = { loads = 0, saves = 0, saveFailures = 0, lockFailures = 0 }
	Service.IsInitialized = true
	return true
end

--- Arranque: abre el DataStore y programa el autosave.
--- @param maid any?
--- @return boolean success
function Service.Start(maid: any?): boolean
	-- El nombre del DataStore NUNCA se registra en claro: solo se avisa de
	-- que se abrio. El identificador del DataStore es una credencial.
	if not dataStoreAvailable then
		Logger.Warn("DataService: sin DataStoreService; NO HABRA PERSISTENCIA en este servidor.")
		Logger.Warn("DataService: el juego es jugable, pero nada se guarda.")
		return true
	end

	-- OJO con los dos puntos: `DataStoreService` se llama como metodo
	-- (`:`), no como funcion suelta. Escribir `DataStoreService.GetDataStore`
	-- falla con "Expected ':' not '.' calling member function GetDataStore", y
	-- como este `Start` devuelve false, `DataService` queda en `Failed` y el
	-- perfil de NINGUN jugador llega a cargarse.
	local ok, dataStore = pcall(function()
		return DataStoreService:GetDataStore(GameConfig.DataStoreName or "KeshusyTomyLandProfile_v1")
	end)

	if not ok or not dataStore then
		-- El DataStore puede no estar disponible por razones del ENTORNO y
		-- no del codigo: en Studio hace falta PUBLICAR el lugar para usar la
		-- API de datos, y un lugar sin publicar falla SIEMPRE aqui.
		--
		-- Eso NO es motivo para tirar el servidor. El juego es jugable sin
		-- persistencia, asi que se degrada a memoria y se DICE, en vez de
		-- devolver false y dejar el perfil entero sin cargar (que es
		-- exactamente el fallo que se vio: economia a cero y compras
		-- rechazadas con "no_profile" sin motivo claro).
		Logger.Warn(("DataService: no se pudo abrir el DataStore (%s)"):format(
			tostring(dataStore)
		))
		Logger.Warn("DataService: MODO SIN PERSISTENCIA. El juego es jugable; nada se guarda al salir.")
		Service._dataStore = nil
		return true
	end

	Service._dataStore = dataStore

	-- Autosave con `Heartbeat` y un ACUMULADOR, no con un contador de
	-- frames. Un `Heartbeat` sin acumulador guardaria en cuanto `wait()`
	-- cediera el hilo, que en Roblox puede ser en el mismo frame: eso es un
	-- DataStore por frame.
	--
	-- El acumulador usa el delta REAL, asi que una caida de frames no
	-- hace guardar mas seguido por error de reloj.
	Service._autosaveInterval = GameConfig.AutosaveInterval or 60

	if MaidRef then
		MaidRef:Connect(RunService.Heartbeat, function(deltaTime)
			Service._autosaveAccumulator += deltaTime

			if Service._autosaveAccumulator >= Service._autosaveInterval then
				Service._autosaveAccumulator = 0
				Service.RunAutosave()
			end
		end)
	end

	Logger.Info(("DataService: persistencia activa, autosave cada %ds"):format(Service._autosaveInterval))
	return true
end

--- Limpieza del servicio. Intenta un ultimo guardado de lo que quede.
--- @return boolean success
function Service.Destroy(): boolean
	Service.SaveAll()
	Service.IsInitialized = false
	Service._sessions = {}
	Service._locks = {}
	Service._dataStore = nil
	MaidRef = nil
	return true
end

-- ---------------------------------------------------------------
-- Carga y guardado
-- ---------------------------------------------------------------

--- Nombre de la clave de un perfil.
---
--- Solo se usa para diagnostico. El `UserId` es publico por definicion, asi
--- que no hay dato personal en esta cadena.
--- @param userId number
--- @return string
local function profileKey(userId: number): string
	return ("player_%d"):format(userId)
end

--- Reintenta una operacion de DataStore con espera entre intentos.
---
--- El DataStore falla por throttling MUCHO mas a menudo de lo que parece.
--- Un solo intento convierte un pico de trafico en perdida de progreso, y
--- reintentar SIN esperar convierte el throttling en un bucle que agrava el
--- problema. Por eso hay backoff: cada intento espera un poco mas.
--- @param operation string nombre para el log
--- @param attempts number
--- @param fn () -> any
--- @return any? result
--- @return string? errorReason
local function withRetries(operation: string, attempts: number, fn: () -> any): (any?, string?)
	local lastError = "sin intento"

	for attempt = 1, attempts do
		local ok, result = pcall(fn)

		if ok and result ~= nil then
			return result, nil
		end

		if not ok then
			lastError = tostring(result)
		else
			lastError = ("%s devolvio nil"):format(operation)
		end

		if attempt < attempts then
			task.wait(attempt * 0.5)
		end
	end

	Logger.Error(("DataService: '%s' fallo tras %d intentos: %s"):format(operation, attempts, lastError))
	return nil, lastError
end

--- Carga el perfil crudo de un jugador.
---
--- Devuelve `nil` cuando el DataStore falla, y un perfil nuevo cuando el
--- jugador aun NO TIENE uno. Se distinguen por el segundo valor de
--- retorno y por el flag `Readable`: confundirlos lleva a sobrescribir el
--- perfil de un jugador al que solo se le caia la red.
--- @param userId number
--- @return any? profile
--- @return string? errorReason
function Service.LoadProfile(userId: number): (any?, string?)
	if not Service._dataStore then
		-- Modo sin persistencia. Aun asi se registra la sesion EN MEMORIA:
		-- asi el perfil del jugador existe, la economia funciona y el juego
		-- es jugable de verdad. Lo que no existe es el guardado, y eso se
		-- dice al jugador en vez de fingir.
		Service._sessions[userId] = { Profile = nil, Dirty = false, Readable = true, IsNew = true }
		return nil, "no hay DataStore en este servidor; el perfil no se guarda"
	end

	local raw, err = withRetries("GetAsync", GameConfig.DataStoreRetries or 3, function()
		return Service._dataStore:GetAsync(profileKey(userId))
	end)

	if raw == nil then
		-- Fallo de lectura. Se marca `Readable = false`: con ese flag,
		-- `SaveProfile` se NEGARA a escribir. Un jugador con la red caida
		-- juega en memoria, pero su partida guardada no se toca.
		Service._sessions[userId] = { Profile = nil, Dirty = false, Readable = false, IsNew = false }
		Service._stats.loads += 1
		return nil, tostring(err)
	end

	-- El DataStore devuelve `false` en una clave inexistente y `true` en
	-- una que se borro. Los dos significan "no hay perfil": es el caso
	-- normal la primera vez que entra un jugador.
	if raw == false then
		Service._sessions[userId] = { Profile = nil, Dirty = false, Readable = true, IsNew = true }
		Service._stats.loads += 1
		Logger.Info(("DataService: perfil nuevo para %d"):format(userId))
		return ProfileSchema.NewProfile(userId), nil
	end

	-- Un dato que no es una tabla esta CORRUPTO. Se devuelve tal cual para
	-- que `ProfileSchema.Sanitize` lo maneje como roto conservando lo que
	-- se pueda: es su trabajo, no el de este servicio.
	if type(raw) ~= "table" then
		Logger.Warn(("DataService: el perfil %d no es una tabla (%s); se tratara como corrupto"):format(
			userId,
			typeof(raw)
		))
		Service._sessions[userId] = { Profile = raw, Dirty = false, Readable = true, IsNew = false }
		Service._stats.loads += 1
		return raw, nil
	end

	Service._sessions[userId] = { Profile = raw, Dirty = false, Readable = true, IsNew = false }
	Service._stats.loads += 1
	Logger.Debug(("DataService: perfil %d leido"):format(userId))

	return raw, nil
end

--- Guarda el perfil de un jugador.
---
--- Usa `UpdateAsync` y NO `SetAsync`. La diferencia no es de estilo:
--- `SetAsync` sobrescribe lo que hubiera sin mirar. Con `UpdateAsync` el
--- callback recibe el estado actual y puede decidir, y sobre todo se
--- puede COMPROBAR que el perfil que hay en memoria sigue siendo el
--- nuestro.
--- @param userId number
--- @param profile any
--- @return boolean success
--- @return string? errorReason
function Service.SaveProfile(userId: number, profile: any): (boolean, string?)
	local session = Service._sessions[userId]

	-- REGLA 2: un perfil que no se pudo LEER no se guarda. Si el DataStore
	-- fallo al cargar, lo que hay en memoria es una aproximacion, y
	-- escribirlo encima del guardado real destruiria la partida.
	if session and session.Readable == false then
		Logger.Warn(("DataService: NO se guarda el perfil %d: no se pudo leer"):format(userId))
		return false, "el perfil no se pudo leer; no se sobrescribe"
	end

	if not Service._dataStore then
		return false, "no hay DataStore en este servidor"
	end

	-- Comprobacion de serializabilidad ANTES de llamar al DataStore. Un
	-- perfil con una Instance falla al guardar con "cannot serialize", y ese
	-- error no dice que campo es ni donde. Aqui si.
	local serializable, serializeError = ProfileSchema.IsSerializable(profile)
	if not serializable then
		Logger.Error(("DataService: el perfil %d NO es serializable: %s"):format(
			userId,
			tostring(serializeError)
		))
		return false, ("perfil no serializable: %s"):format(tostring(serializeError))
	end

	local saved, err = withRetries("UpdateAsync", GameConfig.DataStoreRetries or 3, function()
		return Service._dataStore:UpdateAsync(profileKey(userId), function(oldValue)
			-- Se escribe SIEMPRE el perfil de memoria. Respetar `oldValue`
			-- aqui serviria solo para perder progreso: si `oldValue` es
			-- distinto del nuestro, significa que otro servidor toco el
			-- perfil, y eso lo detecta `AcquireLock`, no este callback.
			return profile
		end)
	end)

	if saved == nil then
		Service._stats.saveFailures += 1
		-- El perfil SIGUE MARCADO SUCIO a proposito: si el siguiente
		-- autosave funciona, se guarda. Marcarlo limpio tras un fallo
		-- seria perder el progreso para siempre.
		Logger.Error(("DataService: NO se pudo guardar el perfil %d: %s"):format(userId, tostring(err)))
		return false, tostring(err)
	end

	Service._sessions[userId] = { Profile = profile, Dirty = false, Readable = true, IsNew = false }
	Service._stats.saves += 1
	Logger.Debug(("DataService: perfil %d guardado"):format(userId))

	return true, nil
end

-- ---------------------------------------------------------------
-- Estado sucio y autosave
-- ---------------------------------------------------------------

--- Marca un perfil como pendiente de guardar. NO guarda.
---
--- Esto es lo que evita un DataStore por cada kill. Guardar aqui seria
--- throttle garantizado; marcar aqui y dejar que el autosave decida es lo
--- unico que escala.
--- @param userId number
function Service.MarkDirty(userId: number)
	local session = Service._sessions[userId]

	if not session then
		return
	end

	session.Dirty = true
end

--- Indica si un perfil tiene cambios sin guardar.
--- @param userId number
--- @return boolean
function Service.IsDirty(userId: number): boolean
	local session = Service._sessions[userId]
	return session ~= nil and session.Dirty == true
end

--- Guarda todos los perfiles que tengan cambios pendientes.
---
--- Solo los SUCIOS. Guardar los limpios seria escribir en el DataStore
--- para no cambiar nada, que es la forma mas rapida de quedarse sin
--- presupuesto de escrituras.
--- @return number saved cuantos se guardaron bien
function Service.RunAutosave(): number
	local saved = 0
	local dirtyIds = {}

	for userId, session in pairs(Service._sessions) do
		if session.Dirty then
			table.insert(dirtyIds, userId)
		end
	end

	-- Se RECOLECTA primero y se guarda despues. `SaveProfile` reescribe la
	-- sesion del jugador, y hacerlo mientras `pairs` la recorre hace que el
	-- bucle dependa de como se modifico la tabla a medio camino.
	for _, userId in ipairs(dirtyIds) do
		local session = Service._sessions[userId]
		if session and session.Profile then
			local ok = Service.SaveProfile(userId, session.Profile)
			if ok then
				saved += 1
			end
		end
	end

	if saved > 0 then
		Logger.Debug(("DataService: autosave guardo %d de %d perfiles"):format(saved, #dirtyIds))
	end

	return saved
end

--- Guarda todos los perfiles pendientes sin mirar si estan sucios.
---
--- Se usa al cerrar el servidor (`BindToClose`), donde el tiempo es corto y
--- es preferible una escritura de mas a perder la sesion de alguien.
--- @return number saved
function Service.SaveAll(): number
	local saved = 0

	for userId, session in pairs(Service._sessions) do
		if session and session.Profile then
			if Service.SaveProfile(userId, session.Profile) then
				saved += 1
			end
		end
	end

	return saved
end

-- ---------------------------------------------------------------
-- Seguridad de sesion
-- ---------------------------------------------------------------
--
-- El problema que resuelve esto, con las cuatro situaciones reales:
--
--   A) el jugador entra en un servidor y carga su perfil.
--   B) el jugador sale de forma normal: se guarda y se libera el bloqueo.
--   C) el servidor MUERE de golpe: no se guarda, no se libera. El bloqueo
--      se queda puesto.
--   D) el jugador entra inmediatamente en otro servidor: el bloqueo de
--      (C) sigue existiendo.
--
-- En (C) y (D) juntos hay un conflicto real: el jugador quiere entrar y
-- su perfil esta bloqueado por un servidor muerto. La solucion NO es
-- esperar un minuto, porque eso haria que perder la sesion pareciera una
-- falta de datos. La solucion es NO ENTRAR y decirlo con claridad: es
-- preferible que el jugador espere a que el bloqueo caduque antes que
-- perder su progreso.
--
-- `LockTtlSeconds` es ese tiempo de espera. Es una decision de diseno, no
-- un parametro tecnico: define cuanto tarda un cierre abrupto en
-- liberarse solo.

--- Intenta bloquear el perfil de un jugador para ESTE servidor.
---
--- @param userId number
--- @return boolean acquired
--- @return string? reason
function Service.AcquireLock(userId: number): (boolean, string?)
	if not Service._dataStore then
		-- Sin DataStore no hay dos servidores escribiendo: es un modo
		-- degradado pero no un conflicto. Se concede para que el juego siga
		-- siendo jugable.
		return true, nil
	end

	local lockKey = ("lock_%d"):format(userId)
	local myJobId = game.JobId
	local ttl = GameConfig.LockTtlSeconds or 120

	local acquired, err = withRetries("lock", GameConfig.DataStoreRetries or 3, function()
		return Service._dataStore:UpdateAsync(lockKey, function(oldValue)
			local now = os.time()

			-- Sin bloqueo, o bloqueo NUESTRO: se toma.
			if oldValue == nil then
				return { jobId = myJobId, acquiredAt = now }
			end

			if type(oldValue) ~= "table" then
				-- Bloqueo corrupto: se ignora en lugar de dejar al jugador
				-- bloqueado para siempre.
				Logger.Warn(("DataService: bloqueo corrupto para %d; se reemplaza"):format(userId))
				return { jobId = myJobId, acquiredAt = now }
			end

			if oldValue.jobId == myJobId then
				-- Ya es nuestro. Se RENUEVA: si no, el TTL venceria
				-- mientras el jugador sigue jugando y otro servidor podria
				-- entrar a escribir su perfil.
				return { jobId = myJobId, acquiredAt = now }
			end

			local age = now - (oldValue.acquiredAt or 0)
			if age > ttl then
				-- Vencio: el otro servidor lleva mas de `ttl` sin renovar,
				-- asi que esta muerto o colgado. Se toma.
				Logger.Warn(("DataService: bloqueo de %d vencio hace %ds; se toma"):format(userId, age))
				return { jobId = myJobId, acquiredAt = now }
			end

			-- Bloqueo VIVO de otro servidor. Devolver `nil` significa "no
			-- escribas" y deja el valor intacto. Este es el punto que
			-- impide que dos servidores escriban el mismo perfil.
			return nil
		end)
	end)

	-- Fallo al COMPROBAR el bloqueo es distinto de "hay un bloqueo": aqui
	-- no se sabe. Se concede y se avisa: negar el acceso por un fallo de
	-- red dejaria fuera a todo el mundo en cada caida breve.
	if err ~= nil then
		Service._stats.lockFailures += 1
		Logger.Error(("DataService: no se pudo comprobar el bloqueo de %d: %s"):format(userId, tostring(err)))
		return true, "el bloqueo no se pudo comprobar; se concede con aviso"
	end

	-- `UpdateAsync` devuelve `nil` cuando el callback devuelve `nil`, y eso
	-- significa "otro servidor tiene el bloqueo".
	if type(acquired) ~= "table" or acquired.jobId ~= myJobId then
		Service._stats.lockFailures += 1
		Logger.Warn(("DataService: el perfil %d esta bloqueado por otro servidor"):format(userId))
		return false, "el perfil ya esta en uso en otro servidor"
	end

	Service._locks[userId] = myJobId
	return true, nil
end

--- Libera el bloqueo de un jugador. Idempotente.
--- @param userId number
function Service.ReleaseLock(userId: number)
	-- El bloqueo de OTRO servidor no se toca. Este es el unico sitio donde
	-- un error de `jobId` destruiria la sesion de un jugador sano.
	local owner = Service._locks[userId]
	if owner ~= nil and owner ~= game.JobId then
		Logger.Warn(("DataService: no se libera el bloqueo de %d: es de otro servidor"):format(userId))
		return
	end

	Service._locks[userId] = nil

	if not Service._dataStore then
		return
	end

	pcall(function()
		Service._dataStore:RemoveAsync(("lock_%d"):format(userId))
	end)
end

--- Cierra la sesion de un jugador: guarda y libera.
---
--- El guardado va ANTES de liberar el bloqueo. Al reves, otro servidor
--- podria tomar el bloqueo y escribir mientras este todavia tiene el
--- cambio sin guardar.
--- @param userId number
function Service.UnloadProfile(userId: number)
	local session = Service._sessions[userId]

	if session and session.Profile and session.Readable ~= false then
		Service.SaveProfile(userId, session.Profile)
	end

	Service.ReleaseLock(userId)
	Service._sessions[userId] = nil
end

--- Renovacion periodica de los bloqueos que tenemos.
---
--- Sin esto, un jugador que juega mas de `LockTtlSeconds` pierde su
--- bloqueo y otro servidor podria entrar a escribir su perfil.
--- @return number renewed
function Service.RenewLocks(): number
	local renewed = 0

	for userId, owner in pairs(Service._locks) do
		if owner == game.JobId then
			local ok = Service.AcquireLock(userId)
			if ok then
				renewed += 1
			end
		end
	end

	return renewed
end

--- Resumen para el informe de arranque y para observabilidad.
--- @return { [string]: number | boolean }
function Service.GetStats(): { [string]: number | boolean }
	local dirty = 0
	for _, session in pairs(Service._sessions) do
		if session.Dirty then
			dirty += 1
		end
	end

	return {
		loads = Service._stats.loads,
		saves = Service._stats.saves,
		saveFailures = Service._stats.saveFailures,
		lockFailures = Service._stats.lockFailures,
		dirty = dirty,
		persistent = Service._dataStore ~= nil,
	}
end

return Service
