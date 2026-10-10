--!strict
--[[
	ProfileSchema
	Esquema versionado del perfil del jugador, con MIGRACIONES.

	POR QUE EXISTE
	--------------
	Un perfil guardado hoy tiene que poder leerse dentro de seis meses,
	cuando el perfil tendra campos que hoy no existen. Sin un esquema
	versionado, la unica forma de "arreglarlo" seria reiniciar a los
	jugadores que tuvieran datos viejos, y eso significa perder la
	progresion de gente que lleva semanas jugando.

	LA REGLA INNEGOCIABLE
	---------------------
	NINGUN dato antiguo se borra al migrar. Una migracion solo:

	    - RENOMBRA   campos cuyo nombre cambio
	    - RELLENA    campos nuevos con un valor por defecto
	    - TRANSFORMA valores que cambiaron de forma

	Si al migrar hay que decidir "este jugador pierde su inventario", eso
	NO es una migracion: es una decision de diseno que requiere a alguien
	que lo haya pensado, no una funcion que se ejecuta sola.

	VERSIONADO
	----------
	    DataVersion = 1   esquema inicial
	    DataVersion = 2   + `Progression`, + `Settings`
    DataVersion = 3   + `Achievements`, + `Titles`, + `Bestiary` (mision V2)
	EN ORDEN y solo las que falten. Un perfil con version 1 guardado hoy
	llegara a la version 3 pasando por la 2, aunque la 2 ya no se use.

	POR QUE NO SE USA `require` AQUI
	---------------------------------
	Igual que `RemoteSchema` y `ProgressionRules`: en el interprete de
	pruebas `script` no existe. Las dependencias se INYECTAN.
]]

local ProfileSchema = {}

--- Version del esquema que este modulo conoce.
---
--- Es la MISMA que `GameConfig.DataVersion`. El servidor compara ambas al
--- arrancar y avisa si se desincronizan, porque un numero mayor aqui que
--- alla significa "el codigo nuevo guardara perfiles que el codigo viejo
--- no sabe leer" y al reves.
ProfileSchema.CurrentVersion = 4

--- Campos obligatorios de un perfil.
ProfileSchema.RequiredFields =
	{ "DataVersion", "Currencies", "Inventory", "Progression", "Secrets", "Skills" }

--- Secciones que un perfil debe tener siempre, aunque esten vacias.
---
--- Se guardan SIEMPRE presentes, aunque valgan `{}`: una clave ausente y
--- una clave vacia obligan a todos los lectores a preguntar "ya existe?".
--- Un perfil con la seccion siempre presente se lee sin `if`.
ProfileSchema.Sections =
	{ "Currencies", "Inventory", "Progression", "Settings", "Stats", "Codes", "Secrets", "Skills" }

--- Crea un perfil NUEVO, listo para la version actual.
--- @param playerId number
--- @return any profile
function ProfileSchema.NewProfile(playerId: number): any
	return {
		DataVersion = ProfileSchema.CurrentVersion,
		PlayerId = playerId,

		-- Secciones vacias pero PRESENTES. Ver la nota de arriba.
		--
		-- `Currencies` tiene la MISMA forma que usa `EconomyRules.NewState`,
		-- y no una forma "bonita" propia: es el estado de economia TAL CUAL.
		-- Esa es una decision deliberada. Si aqui se guardara
		-- `{ Coins = 0, Gems = 0 }` y `EconomyRules` esperara
		-- `{ Balances = {...}, Sequence = 0 }`, cada lectura tendria que
		-- TRADUCIR entre las dos formas, y el sitio donde se olvidara
		-- traducir seria un "saldo a cero sin motivo" o un "monedas
		-- regaladas", segun el sentido de la conversion.
		--
		-- Con una sola forma no hay nada que traducir, y el ledger
		-- (`Entries`, `Requests`) se guarda con el perfil, que es lo que
		-- hace que una compra repetida tras recargar no cobre dos veces.
		--
		-- Se escribe la forma a mano y no con `require` porque este modulo
		-- tiene que cargarse tambien en el interprete de pruebas, donde
		-- `script` no existe.
		Currencies = {
			PlayerId = playerId,
			Balances = { Coins = 0, Gems = 0 },
			Sequence = 0,
			Requests = {},
			Entries = {},
		},

		Inventory = {
			PlayerId = playerId,
			Items = {},
			Equipped = {},
			Requests = {},
			Entries = {},
			Sequence = 0,
		},
		Progression = {
			PlayerId = playerId,
			XP = 0,
			Level = 1,
			ClaimedLevels = {},
			Sources = { Player = 0, World = 0, Event = 0, Season = 0 },
			AppliedRequests = {},
		},
		Settings = { Volume = 1, Quality = "auto" },
		Stats = { Kills = 0, Deaths = 0, Rounds = 0, Playtime = 0 },
		-- `Codes` no viene vacio a proposito.
		--
		-- Antes era `{}`, y el canje se escribia en `Codes[codigo]` en la
		-- raiz. Eso mezclaba dos espacios de nombres: un codigo llamado
		-- `player12` ocupaba el mismo hueco que la entrada de jugador 12.
		-- Ahora la seccion tiene forma FIJA (`Redemptions` con codigos
		-- normalizados, `Counts` con `userId` en cadena) y las dos cosas ya
		-- no pueden confundirse.
		--
		-- Los perfiles VIEJOS tienen `Codes` como tabla lisa; por eso
		-- `NormalizeSections` detecta esa forma y la repara conservando los
		-- canjes que hubiera, en vez de tirar la seccion.
		Codes = {
			PlayerId = playerId,
			Redemptions = {},
			Counts = {},
		},
		Secrets = { Discovered = {} },
		-- Mision V2: logros, titulos y bestiario. Los TOTALES por metrica
		-- viven aqui y son la fuente de verdad de los logros: un logro
		-- con su propio contador se desincronizaria del perfil.
		Achievements = { Totals = {}, Unlocked = {} },
		Titles = { Unlocked = {}, Equipped = "" },
		Bestiary = { Species = {} },
		-- FASE 20: habilidades pasivas desbloqueables de cofres.
		-- `Unlocked` es un set de IDs; `OpenedChests` es un set de chestKeys.
		Skills = { Unlocked = {}, OpenedChests = {} },
	}
end

--- Rellena los campos que las reglas necesitan pero un perfil viejo no
--- tiene.
---
--- Es una MIGRACION de forma, no de datos. Un perfil guardado con una
--- version anterior puede tener `Currencies = { Coins = 0 }` en vez de
--- `{ Balances = { Coins = 0 }, ... }`. Sin esto, `EconomyRules` rechazaria
--- TODAS las operaciones con "estado de economia invalido" y el jugador
--- tendria saldo cero para siempre, sin ninguna pista de por que.
---
--- NUNCA se tira nada: si falta algo, se rellena con el valor por defecto
--- y el resto del perfil se conserva intacto.
--- @param profile any
--- @param playerId number
--- @return boolean changed
function ProfileSchema.NormalizeSections(profile: any, playerId: number): boolean
	if type(profile) ~= "table" then
		return false
	end

	local changed = false
	local defaults = ProfileSchema.NewProfile(playerId)

	if type(profile.Currencies) ~= "table" then
		profile.Currencies = defaults.Currencies
		changed = true
	elseif type(profile.Currencies.Balances) ~= "table" then
		-- Forma antigua: los saldos estaban en la propia seccion. Se
		-- MUEVEN, no se copian: dejarlos en los dos sitios significaria dos
		-- verdades, y un guardado posterior volveria a escribirlos.
		local legacy = {}
		for _, currency in ipairs({ "Coins", "Gems" }) do
			local value = profile.Currencies[currency]
			if type(value) == "number" and value == value and value >= 0 then
				legacy[currency] = value
			end
		end

		profile.Currencies.Balances = legacy
		profile.Currencies.Sequence = type(profile.Currencies.Sequence) == "number"
				and profile.Currencies.Sequence
			or 0
		profile.Currencies.Requests = type(profile.Currencies.Requests) == "table"
				and profile.Currencies.Requests
			or {}
		profile.Currencies.Entries = type(profile.Currencies.Entries) == "table"
				and profile.Currencies.Entries
			or {}
		changed = true
	end

	if type(profile.Inventory) ~= "table" then
		profile.Inventory = defaults.Inventory
		changed = true
	else
		if type(profile.Inventory.Items) ~= "table" then
			profile.Inventory.Items = {}
			changed = true
		end
		if type(profile.Inventory.Equipped) ~= "table" then
			profile.Inventory.Equipped = {}
			changed = true
		end
	end

	if type(profile.Progression) ~= "table" then
		profile.Progression = defaults.Progression
		changed = true
	else
		if
			type(profile.Progression.XP) ~= "number"
			or profile.Progression.XP ~= profile.Progression.XP
		then
			profile.Progression.XP = 0
			changed = true
		end
		if type(profile.Progression.ClaimedLevels) ~= "table" then
			profile.Progression.ClaimedLevels = {}
			changed = true
		end
		if type(profile.Progression.Sources) ~= "table" then
			profile.Progression.Sources = defaults.Progression.Sources
			changed = true
		end
	end

	-- La seccion `Codes` es la que mas formas distintas ha tenido:
	--
	--   v1  `Codes = {}`                      (sin el sistema de codigos)
	--   v2  `Codes = { keshusy = true }`      (canjes en la raiz)
	--   v3  `Codes = { Redemptions = {...}, Counts = {...} }`  (forma actual)
	--
	-- La migracion CONSERVA los canjes de la v2 en vez de tirar la
	-- seccion: si se perdieran, un jugador que ya canjeo un codigo
	-- volveria a poder canjearlo, y eso es justo el fallo que todo este
	-- sistema existe para impedir.
	if type(profile.Codes) ~= "table" then
		profile.Codes = defaults.Codes
		changed = true
	else
		if type(profile.Codes.Redemptions) ~= "table" then
			profile.Codes.Redemptions = {}
			changed = true

			-- Forma antigua: los codigos estaban en la raiz de `Codes`.
			-- Se MUELVEN, no se copian: dejarlos en los dos sitios daria
			-- dos verdades y un guardado posterior volveria a escribirlos.
			--
			-- Solo se migran las claves que parecen un codigo (cadena
			-- alfanumerica). Una clave numerica en la raiz era el contador
			-- de jugador del diseno antiguo, no un canje, y copiarla
			-- convertiria un numero suelto en "codigo ya usado".
			for key, value in pairs(profile.Codes) do
				if key ~= "Redemptions" and key ~= "Counts" and key ~= "PlayerId" then
					if type(key) == "string" and type(value) == "boolean" and value then
						profile.Codes.Redemptions[string.lower(key)] = true
					end
				end
			end
		end

		if type(profile.Codes.Counts) ~= "table" then
			profile.Codes.Counts = {}
			changed = true
		end
	end

	if type(profile.Secrets) ~= "table" then
		profile.Secrets = { Discovered = {} }
		changed = true
	elseif type(profile.Secrets.Discovered) ~= "table" then
		profile.Secrets.Discovered = {}
		changed = true
	end

	-- Mision V2: las tres secciones nuevas se rellenan si faltan.
	-- NUNCA se tira nada: un perfil v2 conserva su progreso intacto.
	if type(profile.Achievements) ~= "table" then
		profile.Achievements = { Totals = {}, Unlocked = {} }
		changed = true
	else
		if type(profile.Achievements.Totals) ~= "table" then
			profile.Achievements.Totals = {}
			changed = true
		end
		if type(profile.Achievements.Unlocked) ~= "table" then
			profile.Achievements.Unlocked = {}
			changed = true
		end
	end

	if type(profile.Titles) ~= "table" then
		profile.Titles = { Unlocked = {}, Equipped = "" }
		changed = true
	else
		if type(profile.Titles.Unlocked) ~= "table" then
			profile.Titles.Unlocked = {}
			changed = true
		end
		if type(profile.Titles.Equipped) ~= "string" then
			profile.Titles.Equipped = ""
			changed = true
		end
	end

	if type(profile.Bestiary) ~= "table" then
		profile.Bestiary = { Species = {} }
		changed = true
	elseif type(profile.Bestiary.Species) ~= "table" then
		profile.Bestiary.Species = {}
		changed = true
	end

	-- FASE 20: Skills (habilidades de cofres). Se rellena si falta.
	if type(profile.Skills) ~= "table" then
		profile.Skills = { Unlocked = {}, OpenedChests = {} }
		changed = true
	else
		if type(profile.Skills.Unlocked) ~= "table" then
			profile.Skills.Unlocked = {}
			changed = true
		end
		if type(profile.Skills.OpenedChests) ~= "table" then
			profile.Skills.OpenedChests = {}
			changed = true
		end
	end

	return changed
end

-- PLACEHOLDER_MIGRATIONS

-- ---------------------------------------------------------------
-- Migraciones
-- ---------------------------------------------------------------
--
-- `MIGRATIONS[n]` transforma un perfil de version `n` a `n + 1`.
--
-- REGLA AL ESCRIBIR UNA MIGRACION
--   1. Que funcione con un perfil de la version ANTERIOR, no con el
--      actual: si lee un campo que todavia no existe, dara nil.
--   2. Que sea IDEMPOTENTE si se puede: ejecutarla dos veces no debe
--      cambiar el resultado. Cuesta poco y evita romper el reintento.
--   3. Que NO borre nada. Si no se puede evitar un dato que se pierde,
--      el perfil tiene que ir a una copia de seguridad, no a perderse.
--
-- Cuando se anyada una version nueva hay que hacer LAS DOS COSAS:
-- subir `CurrentVersion` y declarar la migracion. Subir solo el numero
-- hace que un perfil antiguo se marque "al dia" y se lea con campos que
-- no tiene; declarar solo la migracion deja el numero viejo y la
-- migracion vuelve a aplicarse en cada carga.
local MIGRATIONS: { [number]: (any) -> (any, { string }) } = {}

MIGRATIONS[1] = function(profile: any)
	if type(profile.Secrets) ~= "table" then
		profile.Secrets = { Discovered = {} }
	elseif type(profile.Secrets.Discovered) ~= "table" then
		profile.Secrets.Discovered = {}
	end
	profile.DataVersion = 2
	return profile, { "se creo la seccion persistente de secretos" }
end

-- version 2 -> 3 (mision V2): logros, titulos y bestiario.
MIGRATIONS[2] = function(profile: any)
	local notes = {}

	if type(profile.Achievements) ~= "table" then
		profile.Achievements = { Totals = {}, Unlocked = {} }
		table.insert(notes, "se creo Achievements")
	end

	if type(profile.Titles) ~= "table" then
		profile.Titles = { Unlocked = {}, Equipped = "" }
		table.insert(notes, "se creo Titles")
	end

	if type(profile.Bestiary) ~= "table" then
		profile.Bestiary = { Species = {} }
		table.insert(notes, "se creo Bestiary")
	end

	profile.DataVersion = 3
	return profile, notes
end

-- version 3 -> 4 (FASE 20): habilidades pasivas de cofres.
MIGRATIONS[3] = function(profile: any)
	local notes = {}

	if type(profile.Skills) ~= "table" then
		profile.Skills = { Unlocked = {}, OpenedChests = {} }
		table.insert(notes, "se creo Skills")
	else
		if type(profile.Skills.Unlocked) ~= "table" then
			profile.Skills.Unlocked = {}
			table.insert(notes, "se creo Skills.Unlocked")
		end
		if type(profile.Skills.OpenedChests) ~= "table" then
			profile.Skills.OpenedChests = {}
			table.insert(notes, "se creo Skills.OpenedChests")
		end
	end

	profile.DataVersion = 4
	return profile, notes
end

-- Migracion de ejemplo, comentada a proposito. Se deja escrita para que
-- la siguiente persona copie la forma exacta en vez de inventarse una.
--
--     -- version 1 -> 2
--     MIGRATIONS[1] = function(profile)
--         local notes = { "perfil migrado de la version 1 a la 2" }
--
--         -- `Settings` no existia en la version 1.
--         if type(profile.Settings) ~= "table" then
--             profile.Settings = { Volume = 1, Quality = "auto" }
--             table.insert(notes, "se creo Settings")
--         end
--
--         profile.DataVersion = 2
--         return profile, notes
--     end

--- Aplica las migraciones que falten, EN ORDEN.
---
--- Devuelve una COPIA del perfil. El original no se toca: si la
--- migracion falla a mitad, el perfil que hay en memoria sigue siendo el
--- que se leyo del DataStore, y se podria intentar de nuevo sin haber
--- perdido nada.
--- @param profile any
--- @param options { targetVersion: number? }?
--- @return any? migrated
--- @return { string } notes que se hizo (para el log y para el soporte)
--- @return string? errorReason
function ProfileSchema.Migrate(
	profile: any,
	options: { targetVersion: number? }?
): (any?, { string }, string?)
	local notes: { string } = {}

	if type(profile) ~= "table" then
		return nil, notes, "el perfil no es una tabla"
	end

	local resolved: { targetVersion: number? } = options or {}
	local target: number = if type(resolved.targetVersion) == "number"
		then resolved.targetVersion
		else ProfileSchema.CurrentVersion

	-- Sin `DataVersion` se trata como version 1. Un perfil tan viejo que no
	-- tiene ni el numero tendria cero secciones, y empezar en 1 es lo
	-- unico que puede reconstruirse sin inventar datos.
	local version: number = if type(profile.DataVersion) == "number" then profile.DataVersion else 1
	local working = table.clone(profile)

	-- Red de seguridad: un perfil con una version FANTASMA (mayor que el
	-- codigo actual) es un perfil de una version futura. No se "migra
	-- hacia abajo": no se sabe que campos tendra, y rebajarlo
	-- automaticamente haria que el proximo guardado destruyera lo que
	-- esa version nueva guardo. Se rechaza para que lo mire alguien.
	if version > target then
		return nil, notes, ("perfil de version futura (%d > %d)"):format(version, target)
	end

	-- El bucle tiene un tope ademas de la condicion `version < target`:
	-- si una migracion escribiera una version que no avanza, el `while`
	-- seria infinito. Un tope convierte eso en un fallo visible.
	local iterations = 0
	local maxIterations = target - version + 1

	while version < target do
		iterations += 1

		if iterations > maxIterations then
			return nil, notes, "las migraciones no avanzan de version"
		end

		local migration = MIGRATIONS[version]

		if not migration then
			-- No hay paso intermedio. Se salta a la version pedida solo si
			-- los campos de las secciones ya existen; si no, se devuelve el
			-- error en vez de inventar un perfil con forma correcta y
			-- contenido falso.
			return nil,
				notes,
				("no hay migracion de la version %d a la %d"):format(version, version + 1)
		end

		local ok, result, migrationNotes = pcall(migration, working)

		if not ok then
			return nil,
				notes,
				("la migracion %d lanzo un error: %s"):format(version, tostring(result))
		end

		working = result
		for _, note in ipairs(migrationNotes or {}) do
			table.insert(notes, note)
		end

		local newVersion = working.DataVersion
		if type(newVersion) ~= "number" or newVersion <= version then
			return nil, notes, ("la migracion %d no avanzo la version"):format(version)
		end

		version = newVersion
	end

	return working, notes, nil
end

--- Comprueba que un perfil tiene la forma minima para usarse.
---
--- NO repara nada: solo dice si el perfil sirve. La reparacion es de
--- `Sanitize`, que es una funcion distinta porque una cosa es "este perfil
--- esta roto" y otra "este perfil se puede arreglar sin perder nada".
--- @param profile any
--- @return boolean valid
--- @return { string } problems
function ProfileSchema.Validate(profile: any): (boolean, { string })
	local problems: { string } = {}

	if type(profile) ~= "table" then
		table.insert(problems, "el perfil no es una tabla")
		return false, problems
	end

	if type(profile.DataVersion) ~= "number" then
		table.insert(problems, "DataVersion no es un numero")
	end

	for _, section in ipairs(ProfileSchema.Sections) do
		if type(profile[section]) ~= "table" then
			table.insert(problems, ("falta la seccion '%s'"):format(section))
		end
	end

	-- Un perfil CON DATOS es uno que no se debe descartar. Esta marca la
	-- diferencia entre "no existia" (se crea uno nuevo, correcto) y
	-- "existe pero esta roto" (no se puede tirar y crear otro sin perder
	-- la progresion).
	local hasAnyData = ProfileSchema.HasAnyData(profile)

	if #problems == 0 then
		return true, problems
	end

	if hasAnyData then
		table.insert(problems, "ATENCION: perfil con datos pero incompleto; no se puede crear otro")
	end

	return false, problems
end

--- Indica si un perfil tiene algun dato real que se pueda perder.
--- @param profile any
--- @return boolean
function ProfileSchema.HasAnyData(profile: any): boolean
	if type(profile) ~= "table" then
		return false
	end

	for _, section in ipairs(ProfileSchema.Sections) do
		if type(profile[section]) == "table" and next(profile[section]) ~= nil then
			return true
		end
	end

	return false
end

--- Devuelve un perfil utilizable, reparando lo que se pueda.
---
--- Decide entre TRES salidas, y la distincion es lo importante:
---
---   1. Perfil valido -> se devuelve tal cual.
---   2. Perfil VACIO -> se devuelve uno nuevo. Aqui no hay nada que
---      perder, asi que empezar de cero es correcto.
---   3. Perfil ROTO CON DATOS -> se devuelve una copia del original con
---      las secciones que faltan rellenadas por defecto. NUNCA se
---      descarta. Crear un perfil nuevo cuando el anterior tenia un
---      inventario seria borrar la progresion de un jugador por un fallo
---      de formato, que es justo lo que esta fase prohibe.
--- @param raw any
--- @param playerId number
--- @return any profile siempre utilizable
--- @return { string } problems
--- @return boolean wasRepaired
function ProfileSchema.Sanitize(raw: any, playerId: number): (any, { string }, boolean)
	local problems: { string } = {}

	if type(raw) ~= "table" then
		table.insert(problems, "el dato leido no es una tabla")
		return ProfileSchema.NewProfile(playerId), problems, true
	end

	local valid, validationProblems = ProfileSchema.Validate(raw)
	if valid then
		return raw, problems, false
	end

	for _, problem in ipairs(validationProblems) do
		table.insert(problems, problem)
	end

	if not ProfileSchema.HasAnyData(raw) then
		table.insert(problems, "el perfil estaba vacio; se crea uno nuevo")
		return ProfileSchema.NewProfile(playerId), problems, true
	end

	local repaired = table.clone(raw)
	repaired.DataVersion = ProfileSchema.CurrentVersion

	for _, section in ipairs(ProfileSchema.Sections) do
		if type(repaired[section]) ~= "table" then
			local defaults = ProfileSchema.NewProfile(playerId)
			repaired[section] = defaults[section]
			table.insert(problems, ("se relleno la seccion '%s'"):format(section))
		end
	end

	table.insert(problems, "perfil reparado conservando los datos existentes")
	return repaired, problems, true
end

--- Indica si un valor se puede meter en un DataStore.
---
--- El DataStore NO admite funciones, Instances, threads ni ciclos. Un
--- perfil con una referencia a un Humanoid no falla al guardar con un
--- error claro: falla con "cannot serialize", que no dice NI QUE NI DONDE.
--- Comprobarlo antes evita perder la sesion entera por un campo que
--- alguien metio sin querer.
--- @param value any
--- @param depth number?
--- @param seen any?
--- @return boolean serializable
--- @return string? reason
function ProfileSchema.IsSerializable(value: any, depth: number?, seen: any?): (boolean, string?)
	local currentDepth = depth or 0
	if currentDepth > 32 then
		return false, "el dato es demasiado profundo"
	end

	local visited = seen or {}

	if type(value) == "function" then
		return false, "contiene una funcion"
	end
	if type(value) == "thread" then
		return false, "contiene un thread"
	end
	if type(value) == "userdata" then
		-- Las Instances de Roblox son userdata. Un perfil con una Instance
		-- es un perfil que no se puede guardar.
		return false, "contiene un objeto del motor (Instance)"
	end
	if type(value) == "buffer" then
		return false, "contiene un buffer"
	end

	if type(value) ~= "table" then
		-- Los escalares (number, string, boolean, nil) son validos. Un
		-- number que sea NaN o infinito no: `DataEncode` lo acepta y
		-- `DataDecode` devuelve algo inutil.
		if type(value) == "number" then
			if value ~= value then
				return false, "contiene un NaN"
			end
			if value == math.huge or value == -math.huge then
				return false, "contiene un infinito"
			end
		end
		return true, nil
	end

	-- Ciclo: una tabla que se contiene a si misma.
	if visited[value] then
		return false, "contiene un ciclo"
	end
	visited[value] = true

	for key, item in pairs(value) do
		local keyOk, keyReason = ProfileSchema.IsSerializable(key, currentDepth + 1, visited)
		if not keyOk then
			return false, ("clave: %s"):format(tostring(keyReason))
		end

		local valueOk, valueReason = ProfileSchema.IsSerializable(item, currentDepth + 1, visited)
		if not valueOk then
			return false, ("valor de '%s': %s"):format(tostring(key), tostring(valueReason))
		end
	end

	visited[value] = nil
	return true, nil
end

return ProfileSchema
