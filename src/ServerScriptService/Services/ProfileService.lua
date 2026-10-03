--!strict
--[[
	ProfileService
	Capa de perfil del jugador: lo unico que se guarda.

	QUE GUARDA Y QUE NO
	-------------------
	Guarda SOLO datos planos: numeros, cadenas, booleanos y tablas de
	ellos. NO guarda Instances, ni funciones, ni conexiones, ni
	referencias temporales. La razon es tecnica y no de estilo: el
	DataStore no serializa nada de eso, y un perfil con una referencia
	viva hace que `UpdateAsync` falle con "cannot serialize" sin decir NI
	QUE NI DONDE. `ProfileSchema.IsSerializable` lo comprueba antes de
	intentar guardar.

	LAS TRES CAPAS, Y POR QUE ESTAN SEPARADAS
	-----------------------------------------
	    ProfileService  (esta)   perfil en memoria + carga y guardado
	    DataService              DataStore, autosave, versionado
	    las reglas (Economy... ) la logica pura de cada dominio

	Separarlas no es purismo: cada capa falla de forma distinta.
	`DataService` falla cuando el DataStore falla (red, throttling), y en
	ese caso el perfil EN MEMORIA sigue siendo valido y el juego sigue
	jugandose. Si el perfil viviera dentro de `DataService`, una caida de
	red dejaria al jugador sin economia, sin inventario y sin nivel.

	EL PERFIL ES LO UNICO PERSISTENTE
	---------------------------------
	Antes, `PlayerService` tenia `Level`, `XP`, `Coins` y `Gems` en su
	sesion en memoria, y se perdian al salir. Ahora el perfil es la fuente
	de verdad y la sesion es una vista. Es el cambio que convierte el
	"economia" de esta fase en algo REAL.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local UTILS = SHARED:WaitForChild("Utils")

local CombatMath = require(SHARED:WaitForChild("Libraries"):WaitForChild("CombatMath"))
local ItemCatalog = require(SHARED:WaitForChild("Config"):WaitForChild("ItemCatalog"))
local EconomyRules = require(SHARED:WaitForChild("Libraries"):WaitForChild("EconomyRules"))
local InventoryRules = require(SHARED:WaitForChild("Libraries"):WaitForChild("InventoryRules"))
local ProgressionRules = require(SHARED:WaitForChild("Libraries"):WaitForChild("ProgressionRules"))
local ProfileSchema = require(SHARED:WaitForChild("Libraries"):WaitForChild("ProfileSchema"))
local Logger = require(UTILS:WaitForChild("Logger"))

local Service = {}

Service.IsInitialized = false

-- DataService inyectado por ServerMain.
Service._dataService = nil

-- PlayerService inyectado: publica los atributos del HUD.
Service._playerService = nil

-- UserId -> { Profile = ..., Loaded = boolean }
Service._profiles = {}

-- Reglas puras, una instancia cada una. Son SIN ESTADO COMPARTIDO entre
-- jugadores: el estado va dentro del perfil de cada uno, que es lo que se
-- pasa a `AddItem`, `AddXP` y demas.
local Inventory = InventoryRules.new(ItemCatalog)
local Progression = ProgressionRules.new({
	levelForXp = CombatMath.LevelForXp,
	xpForLevel = CombatMath.XpForLevel,
	levelProgress = CombatMath.LevelProgress,
})

Service._inventoryRules = Inventory
Service._progressionRules = Progression

-- Curva de nivel, leida del perfil para no duplicar el balance.
Service._curve = nil

-- Maid recibido en Init.
local MaidRef = nil

--- Inyecta las dependencias del servicio.
--- @param dataService any
--- @param playerService any
function Service.SetDependencies(dataService: any, playerService: any)
	Service._dataService = dataService
	Service._playerService = playerService
end

--- Inicializacion del servicio. Idempotente.
--- @param maid any?
--- @return boolean success
function Service.Init(maid: any?): boolean
	MaidRef = maid
	Service._profiles = {}
	Service.IsInitialized = true
	return true
end

--- Arranque.
--- @param maid any?
--- @return boolean success
function Service.Start(maid: any?): boolean
	local GameConfig = require(SHARED:WaitForChild("Config"):WaitForChild("GameConfig"))

	-- La version del esquema tiene que COINCIDIR con la de la
	-- configuracion. Si divergen, el codigo nuevo esta guardando perfiles
	-- que el viejo no sabe leer (o al reves), y eso solo se descubre
	-- cuando un jugador entra y su perfil aparece vacio.
	if GameConfig.DataVersion ~= ProfileSchema.CurrentVersion then
		Logger.Error(("ProfileService: DataVersion de GameConfig (%d) != la de ProfileSchema (%d)"):format(
			GameConfig.DataVersion,
			ProfileSchema.CurrentVersion
		))
		return false
	end

	-- La curva se lee UNA vez de la configuracion. Se guarda aqui para que
	-- todos los que consulten el nivel usen exactamente los mismos
	-- numeros, sin tener que pasar la configuracion por todo el codigo.
	Service._curve = {
		xpPerLevel = GameConfig.XPPerLevel,
		exponent = GameConfig.LevelCurveExponent,
		maxLevel = GameConfig.MaxLevel,
	}

	if not Service._dataService then
		Logger.Error("ProfileService: sin DataService; el perfil no se puede cargar ni guardar.")
		return false
	end

	Logger.Info("ProfileService: capa de perfil lista.")
	return true
end

--- Limpieza del servicio.
--- @return boolean success
function Service.Destroy(): boolean
	Service.IsInitialized = false
	Service._profiles = {}
	Service._dataService = nil
	Service._playerService = nil
	MaidRef = nil
	return true
end

-- ---------------------------------------------------------------
-- Acceso al perfil
-- ---------------------------------------------------------------

--- Estado de economia de un jugador, o nil si no tiene perfil.
--- @param player Player?
--- @return any?
function Service.GetEconomyState(player: Player?): any?
	local entry = Service._entryOf(player)
	if not entry then
		return nil
	end
	return entry.Economy
end

--- Estado de inventario de un jugador, o nil.
--- @param player Player?
--- @return any?
function Service.GetInventoryState(player: Player?): any?
	local entry = Service._entryOf(player)
	if not entry then
		return nil
	end
	return entry.Inventory
end

--- Estado de progresion de un jugador, o nil.
--- @param player Player?
--- @return any?
function Service.GetProgressionState(player: Player?): any?
	local entry = Service._entryOf(player)
	if not entry then
		return nil
	end
	return entry.Progression
end

--- El perfil PLANO de un jugador, o nil si no tiene.
---
--- Existe para los sistemas que guardan su estado en una seccion propia del
--- perfil y no en uno de los tres sub-estados ya existentes: el canje de
--- codigos (`Codes`) es el caso actual.
---
--- Se devuelve la tabla VIVA, no una copia: quien la recibe va a
--- escribir en ella (por ejemplo, marcar un codigo como usado), y una
--- copia perderia ese cambio. Por eso solo la usan servicios del servidor,
--- nunca el cliente, y por eso el que llama es responsable de llamar a
--- `MarkDirty` despues de escribir.
--- @param player Player?
--- @return any?
function Service.GetProfile(player: Player?): any?
	local entry = Service._entryOf(player)

	if not entry then
		return nil
	end

	return entry.Profile
end

--- Paquete { economy, inventory, progression } para la tienda.
---
--- Se devuelve un objeto NUEVO cada vez. Si devolviera el `entry` interno,
--- quien lo recibiera podria escribir en `entry.Profile`, y con el una
--- referencia a la sesion que no se limpia nunca.
--- @param player Player?
--- @return any?
function Service.GetProfileState(player: Player?): any?
	local entry = Service._entryOf(player)
	if not entry then
		return nil
	end

	return {
		economy = entry.Economy,
		inventory = entry.Inventory,
		progression = entry.Progression,
	}
end

--- Entrada interna de un jugador.
--- @param player Player?
--- @return any?
function Service._entryOf(player: Player?): any?
	if not player then
		return nil
	end
	return Service._profiles[player.UserId]
end

--- Indica si el jugador tiene un perfil CARGADO.
---
--- No es lo mismo que "esta conectado": un jugador conectado todavia
--- no tiene perfil hasta que termina la carga. Concederle economia antes
--- de eso crearia saldo en un perfil que luego se sobrescribe al cargar.
--- @param player Player?
--- @return boolean
function Service.HasProfile(player: Player?): boolean
	local entry = Service._entryOf(player)
	return entry ~= nil and entry.Loaded == true
end

--- Curva de nivel vigente.
--- @return any
function Service.GetCurve(): any
	return Service._curve
end

--- Marca el perfil como sucio: hay que guardarlo.
---
--- Se llama DESPUES de cualquier cambio. No guarda: solo avisa. Guardar
--- aqui seria un DataStore por cada kill, que es exactamente lo que el
--- autosave con `dirty` evita.
--- @param player Player?
function Service.MarkDirty(player: Player?)
	if not Service._dataService then
		return
	end

	if player then
		Service._dataService.MarkDirty(player.UserId)
	end
end

--- Cuantos perfiles hay cargados ahora mismo.
--- @return number
function Service.GetLoadedCount(): number
	local count = 0
	for _, entry in pairs(Service._profiles) do
		if entry.Loaded then
			count += 1
		end
	end
	return count
end

-- ---------------------------------------------------------------
-- Carga y guardado
-- ---------------------------------------------------------------

--- Reconstruye los sub-estados a partir del perfil plano.
---
--- El perfil guardado tiene la FORMA del esquema (`Currencies`, `Inventory`
-- con `Items`...). Las reglas esperan estado VIVO (`Balances`, `Entries`...).
--- Esta funcion es el puente entre ambas, y va en UN solo sitio: si cada
--- sistema hiciera su propia conversion, cada uno tendria una version
-- distinta de la misma verdad.
--- @param profile any
--- @param playerId number
--- @return any entry
local function buildEntry(profile: any, playerId: number): any
	return {
		Loaded = true,
		PlayerId = playerId,
		Profile = profile,
		Economy = profile.Currencies,
		Inventory = profile.Inventory,
		Progression = profile.Progression,
	}
end

--- Carga el perfil de un jugador.
---
--- El flujo es deliberadamente tolerante a fallos:
---
---   1. `DataService.LoadProfile` lee (con reintentos y con degradacion si
---      el DataStore falla).
---   2. Se MIGRA si su version es antigua. Los datos antiguos nunca se
---      borran.
---   3. Se SANAITA: un perfil roto CON DATOS se repara conservando lo que
---      tiene; uno VACIO se crea nuevo.
---   4. Se RECONSTRUYEN los sub-estados y se publica en los atributos.
---
--- Si el DataStore fallo, se crea un perfil NUEVO EN MEMORIA y el juego
--- sigue siendo jugable. No se guarda ese perfil (seria pisar el
--- guardado real de un jugador que solo tenia un fallo de red momentaneo),
--- y se avisa al jugador de que su progreso puede no guardarse.
--- @param player Player
--- @return boolean success
--- @return string? errorReason
function Service.LoadProfile(player: Player): (boolean, string?)
	if not Service._dataService then
		return false, "ProfileService no tiene DataService"
	end

	local userId = player.UserId

	local raw, loadError = Service._dataService.LoadProfile(userId)

	if raw == nil then
		-- No se pudo leer. Se juega con un perfil NUEVO EN MEMORIA para que
		-- el juego sea jugable, y se avisa de que no se esta guardando.
		local fresh = ProfileSchema.NewProfile(userId)
		Service._profiles[userId] = buildEntry(fresh, userId)

		local reason = tostring(loadError)

		if reason:find("no hay DataStore") then
			-- Modo sin persistencia: es lo esperado en un lugar sin
			-- publicar, asi que no es un ERROR sino un aviso.
			Logger.Warn(("ProfileService: '%s' juega SIN persistencia (%s)"):format(
				player.Name,
				reason
			))
		else
			Logger.Error(("ProfileService: no se pudo cargar el perfil de %s: %s"):format(
				player.Name,
				reason
			))
			Logger.Warn(("ProfileService: '%s' juega SIN persistencia hasta que el DataStore responda"):format(
				player.Name
			))
		end

		Service.PublishToPlayer(player)
		return false, reason
	end

	-- Migracion. Un perfil de version antigua se actualiza conservando sus
	-- datos; si la migracion falla, se AVISA y se sigue con el original en
	-- vez de crear uno nuevo encima (eso perderia todo).
	local migrated, notes, migrateError = ProfileSchema.Migrate(raw)

	if migrated == nil then
		Logger.Error(("ProfileService: no se pudo migrar el perfil de %s: %s"):format(
			player.Name,
			tostring(migrateError)
		))
		-- Se sigue con el dato ORIGINAL: es la mejor version disponible.
		migrated = raw
	elseif #notes > 0 then
		for _, note in ipairs(notes) do
			Logger.Info(("ProfileService: %s -> migracion: %s"):format(player.Name, note))
		end
	end

	local profile, sanitizeProblems, repaired = ProfileSchema.Sanitize(migrated, userId)

	-- Normalizacion de FORMA: un perfil de una version anterior puede tener
	-- las secciones con distinta forma. Sin esto, la economia rechazaria
	-- todas sus operaciones con "estado invalido" y el jugador tendria
	-- saldo cero para siempre, sin error visible.
	if ProfileSchema.NormalizeSections(profile, userId) then
		Logger.Warn(("ProfileService: '%s' -> el perfil se normalizo a la forma actual"):format(
			player.Name
		))
		repaired = true
	end

	if repaired then
		for _, problem in ipairs(sanitizeProblems) do
			Logger.Warn(("ProfileService: '%s' -> %s"):format(player.Name, problem))
		end
	end

	Service._profiles[userId] = buildEntry(profile, userId)

	-- `Progression` es una INSTANCIA de `ProgressionRules` (se creo con
	-- `ProgressionRules.new`), asi que sus metodos se llaman con DOS PUNTOS.
	-- Con un punto, `self` seria el estado del jugador en vez de la
	-- instancia, y dentro `GetLevel` la llamada `self:GetXP(...)` fallaria
	-- con "attempt to call missing method 'GetXP' of table".
	local progression = Service.GetProgressionState(player)

	Logger.Info(("ProfileService: perfil de %s cargado (nivel %d, %d coins)"):format(
		player.Name,
		Progression:GetLevel(progression, Service._curve),
		EconomyRules.GetBalance(Service.GetEconomyState(player), "Coins")
	))

	Service.PublishToPlayer(player)
	return true, nil
end

--- Publica el estado del perfil en los atributos que lee la UI.
--- @param player Player
function Service.PublishToPlayer(player: Player)
	local entry = Service._entryOf(player)
	if not entry then
		return
	end

	for currency, balance in pairs(EconomyRules.GetBalances(entry.Economy)) do
		player:SetAttribute(currency, balance)
	end

	-- Ojo con los dos puntos: `Progression` es una instancia creada con
	-- `ProgressionRules.new`, no el modulo en si.
	local level = Progression:GetLevel(entry.Progression, Service._curve)
	player:SetAttribute("Level", level)
	player:SetAttribute("XP", Progression:GetXP(entry.Progression))
end

--- Marca un perfil para guardar. Lo guarda el `autosave`, no aqui.
--- @param player Player?
--- @return boolean success
function Service.SaveProfile(player: Player?): boolean
	if not Service._dataService or not player then
		return false
	end

	local entry = Service._entryOf(player)
	if not entry then
		return false
	end

	local ok, err = Service._dataService.SaveProfile(player.UserId, entry.Profile)
	if ok then
		Logger.Debug(("ProfileService: perfil de %s guardado"):format(player.Name))
	end

	return ok, err
end

--- Descarga el perfil de memoria al salir el jugador.
---
--- Se guarda ANTES de borrar la entrada. Si se borrara primero, no habria
--- nada que guardar.
--- @param player Player
function Service.UnloadProfile(player: Player)
	local userId = player.UserId

	if Service._dataService then
		Service._dataService.UnloadProfile(userId)
	end

	Service._profiles[userId] = nil
	Logger.Debug(("ProfileService: perfil de %s descargado de memoria"):format(player.Name))
end

return Service
