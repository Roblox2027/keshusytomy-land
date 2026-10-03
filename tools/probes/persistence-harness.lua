-- HARNESS DE PERSISTENCIA
--
-- POR QUE ESTE ARCHIVO
-- -------------------
-- El DataStore de Roblox NO se puede usar desde un lugar sin publicar:
-- `GetDataStore` falla con "You must publish this place to the web to
-- access DataStore". Eso es una limitacion del ENTORNO, no del codigo, y
-- significa que la persistencia REAL no se puede certificar aqui.
--
-- Lo que NO se hace en esta fase: declarar "persistencia PASS" porque una
-- funcion devuelve una tabla. Eso no demuestra nada.
--
-- Lo que SI se hace: instalar un DataStore SIMULADO en el `DataService`
-- REAL y recorrer sus rutas de verdad. No se reimplementa nada: se ejercita
-- el codigo de produccion con un almacen falso, y se comprueba que escribe,
-- que NO escribe cuando debe, y que se degrada bien.
--
-- Lo que esto NO demuestra, y hay que decirlo: que el DataStore real de
-- Roblox acepte esos datos. Eso solo se prueba con el lugar publicado.
local Services = game.ServerScriptService.Services
local DataService = require(Services.DataService)
local ProfileSchema = require(game.ReplicatedStorage.Shared.Libraries.ProfileSchema)
local EconomyRules = require(game.ReplicatedStorage.Shared.Libraries.EconomyRules)

local out = {}
local function say(l)
	table.insert(out, l)
end

-- --- Almacen simulado -----------------------------------------------
-- Reproduce el contrato del DataStore de Roblox:
--   * `GetAsync` devuelve `false` si la clave no existe (NO nil)
--   * `UpdateAsync` recibe el valor viejo y devuelve el nuevo
--   * `RemoveAsync` borra
-- Ademas permite INYECTAR fallos, que es lo que hay que probar.
local function makeStore()
	local store = {
		data = {},
		writes = 0,
		reads = 0,
		failReads = false,
		failWrites = false,
	}

	function store:GetAsync(key)
		self.reads += 1
		if self.failReads then
			error("fallo simulado de lectura")
		end
		local value = self.data[key]
		if value == nil then
			return false
		end
		return value
	end

	function store:UpdateAsync(key, transform)
		if self.failWrites then
			error("fallo simulado de escritura")
		end
		local oldValue = self.data[key]
		local newValue = transform(oldValue)
		if newValue == nil then
			-- `nil` significa "no escribas": es lo que permite a
			-- `AcquireLock` rechazar a un segundo servidor.
			return self.data[key]
		end
		self.data[key] = newValue
		self.writes += 1
		return newValue
	end

	function store:RemoveAsync(key)
		self.removes += 1
		self.data[key] = nil
	end

	return store
end

local store = makeStore()
local userId = 999000111

DataService._sessions = {}
DataService._locks = {}
DataService._dataStore = store

-- --- 1. Primera carga: no existe, crea perfil ------------------------
local fresh = DataService.LoadProfile(userId)
say("1_carga_inicial_ok=" .. tostring(fresh ~= nil))
say("1_version=" .. tostring(fresh and fresh.DataVersion))

-- --- 2. Guardar un perfil con saldo y recuperarlo -------------------
local saved = ProfileSchema.NewProfile(userId)
saved.Currencies.Balances.Coins = 1234
saved.Progression.XP = 500
DataService.MarkDirty(userId)

local ok2 = DataService.SaveProfile(userId, saved)
say("2_guardado_ok=" .. tostring(ok2))
say("2_escrituras=" .. tostring(store.writes))

local reloaded2 = DataService.LoadProfile(userId)
say("2_coins_recuperados=" .. tostring(reloaded2 and reloaded2.Currencies.Balances.Coins))
say("2_xp_recuperado=" .. tostring(reloaded2 and reloaded2.Progression.XP))

-- --- 3. Autosave: guarda SOLO lo que esta sucio -----------------------
store.writes = 0
DataService._sessions[userId].Dirty = false
DataService.RunAutosave()
say("3_autosave_limpio_escrituras=" .. tostring(store.writes))

DataService.MarkDirty(userId)
store.writes = 0
DataService.RunAutosave()
say("3_autosave_sucio_escrituras=" .. tostring(store.writes))

-- --- 4. Un perfil que NO se pudo leer no se guarda encima -----------
local otherId = 999000222
DataService.LoadProfile(otherId)
DataService._sessions[otherId].Readable = false

local ok4, err4 = DataService.SaveProfile(otherId, ProfileSchema.NewProfile(otherId))
say("4_guarda_perfil_ilegible_ok=" .. tostring(ok4))
say("4_motivo=" .. tostring(err4))

-- --- 5. Un perfil NO serializable se rechaza ANTES de escribir ------
local brokenId = 999000333
DataService.LoadProfile(brokenId)
local broken = ProfileSchema.NewProfile(brokenId)
broken.Settings.Callback = function()
	return 1
end

store.writes = 0
local ok5, err5 = DataService.SaveProfile(brokenId, broken)
say("5_guarda_no_serializable_ok=" .. tostring(ok5))
say("5_motivo=" .. tostring(err5))
say("5_escrituras=" .. tostring(store.writes))

-- --- 6. Fallo de escritura: el perfil SIGUE sucio ------------------
--
-- El perfil se marca SUCIO ANTES de guardar. Sin ese `MarkDirty`, la
-- comprobacion de "sigue sucio" no probaria nada: la sesion ya estaria
-- limpia y el `false` del final no significaria nada sobre el
-- comportamiento ante un fallo.
local flakyId = 999000444
DataService.LoadProfile(flakyId)
DataService.MarkDirty(flakyId)
store.failWrites = true

local ok6 = DataService.SaveProfile(flakyId, ProfileSchema.NewProfile(flakyId))
say("6_guarda_con_fallo_ok=" .. tostring(ok6))
say("6_sigue_sucio=" .. tostring(DataService.IsDirty(flakyId)))
store.failWrites = false

-- Y con el almacen sano, el reintento si guarda y ya no queda sucio.
local ok6b = DataService.SaveProfile(flakyId, ProfileSchema.NewProfile(flakyId))
say("6_reintento_ok=" .. tostring(ok6b))
say("6_ya_no_sucio=" .. tostring(not DataService.IsDirty(flakyId)))

-- --- 7. Bloqueo de sesion: un solo servidor por perfil --------------
local lockA = DataService.AcquireLock(999000555)
say("7_bloqueo_ok=" .. tostring(lockA))

-- Se comprueba el valor GUARDADO, porque `game.JobId` no se puede cambiar
-- en caliente: lo que importa es que el bloqueo exista y lleve su jobId.
local lockKey = "lock_999000555"
local lockValue = store.data[lockKey]
say("7_bloqueo_tiene_jobid=" .. tostring(lockValue ~= nil and lockValue.jobId ~= nil))

-- Con el bloqueo de OTRO servidor vigente, `AcquireLock` no puede tomar:
-- este es el punto que impide que dos servidores escriban lo mismo.
store.data[lockKey] = { jobId = "servidor-ajeno", acquiredAt = os.time() }
DataService._locks = {}
local lockB = DataService.AcquireLock(999000555)
say("7_bloqueo_ajeno_ok=" .. tostring(lockB))

-- Con un bloqueo VENCIDO (de un servidor muerto), se puede tomar.
store.data[lockKey] = { jobId = "servidor-muerto", acquiredAt = os.time() - 99999 }
local lockC = DataService.AcquireLock(999000555)
say("7_bloqueo_vencido_ok=" .. tostring(lockC))

-- --- 8. Perfil con la forma ANTIGUA: se normaliza sin perder saldo ---
local legacyId = 999000666
store.data["player_" .. legacyId] = {
	DataVersion = 1,
	Currencies = { Coins = 777 },
	Inventory = { Items = {} },
	Progression = { XP = 300 },
	Settings = { Volume = 1, Quality = "auto" },
	Stats = {},
	Codes = {},
}

local legacy = DataService.LoadProfile(legacyId)
local normalized = ProfileSchema.NormalizeSections(legacy, legacyId)
say("8_normalizado=" .. tostring(normalized))
say("8_coins_via_economia=" .. tostring(EconomyRules.GetBalance(legacy.Currencies, "Coins")))
say("8_xp_conservado=" .. tostring(legacy.Progression.XP))

-- --- 9. Se restaura el estado real ---------------------------------
DataService._dataStore = nil
DataService._sessions = {}
DataService._locks = {}

say("harness_completo=true")
return table.concat(out, "\n")