--!strict
--[[
	WorldAccessRules
	ACCESO A LOS CINCO MUNDOS, sin puerta de nivel.

	POR QUE EXISTE
	--------------
	El enunciado de la expansion pide dos cosas que antes eran la misma:

	  1. los cinco mundos disponibles desde el nivel 1 (fase 3);
	  2. los cinco mundos de dificultad DISTINTA (fase 4).

	Antes esas dos cosas viajaban juntas en un solo campo, `RequiredLevel`:
	un mundo era "facil" porque se abria pronto y "dificil" porque exigia nivel
	50. Separarlas no es cosmetico: el jugador que entra en Cyber en su minuto
	uno tiene que encontrarlo duro por el CONTENIDO (mas enemigos, mas vida,
	mas tipos), no por un cartel que le dice "vuelve en nivel 50". Un cartel de
	requisito no es dificultad: es una puerta.

	EL BLOQUEO ESTA EN EL SERVIDOR, AQUI SOLO ESTA LA REGLA
	--------------------------------------------------------
	Este modulo es logica PURA y no se conecta a nada. `PortalService` lo
	consulta y decide; aqui no hay ninguna decision. Eso es lo que permite que
	`WorldAccess.spec` compruebe "los cinco mundos se abren desde nivel 1" en
	`npm test`, sin Studio y sin un jugador conectado.

	LO QUE NO SE ROMPE
	------------------
	`PortalService` sigue validando TODO lo demas: personaje vivo, portal real
	en el mapa, portal abierto, mundo habilitado, mundo existente, proximity,
	cooldown y anti-spam. Este modulo solo retira el comparador de nivel. Un
	cliente modificado que invente un `worldId` sigue sin tener a donde ir,
	porque `IsKnownWorld` y el registro del portal lo rechazan igual.
]]

local Rules = {}

-- ---------------------------------------------------------------------------
-- ORDEN Y NOMBRES
-- ---------------------------------------------------------------------------

-- Orden canonico. Es el MISMO orden que usa `WorldService` y el generador: si
-- divergen, el primer mundo de la lista deja de ser el destino por defecto y
-- el lobby manda a otra parte. Copiar el orden es mejor que mantener dos
-- listas que se desincronizan solas.
Rules.WorldOrder = { "Forest", "Desert", "Ice", "Volcano", "Cyber" }

-- Nombre que el jugador LEE. Es el mismo texto que ponian las definiciones de
-- mundo, movido aqui para que el cartel del portal y este modulo no puedan
-- discrepar.
--
-- FASE 3 (auditoria): antes decia "Frost Peaks" y "Ember Ridge", mientras las
-- definiciones (que pintan el cartel via `VisualService`) y el generador
-- (`tools/worlds.js`) decian "Frozen Tomy" y "Volcano Rage". Prevalece la
-- definicion: es la que el jugador ve en el mapa. `Audit` lo comprueba.
Rules.DisplayNameByWorld = {
	Forest = "Keshusy Forest",
	Desert = "Boom Desert",
	Ice = "Frozen Tomy",
	Volcano = "Volcano Rage",
	Cyber = "Cyber Keshusy",
}

-- ---------------------------------------------------------------------------
-- DIFICULTAD POR MUNDO (FASE 4)
-- ---------------------------------------------------------------------------
--
-- Esto NO es el requisito de entrada. Es la PRESION que el mundo ejerce una
-- vez dentro, y por eso vive aqui y no en `RequiredLevel`:
--
--   Forest   1  el jugador aprende a colocar, detonar y huir
--   Desert   2  aparece la carga telegrafiada y la cobertura real
--   Ice      3  aparece la ralentizacion y los tipos combinados
--   Volcano  4  aparece la quemadura y el peligro de terreno
--   Cyber    5  aparece la refleccion y la presion alta constante
--
-- La escala se multiplica por la noche (ver `DifficultyRules`), asi que un
-- Forest en la noche 50 es mas duro que un Cyber en la noche 1. Eso es
-- intencional y es lo que da recorrido a las 99 noches.
Rules.DifficultyByWorld = {
	Forest = 1,
	Desert = 2,
	Ice = 3,
	Volcano = 4,
	Cyber = 5,
}

-- ---------------------------------------------------------------------------
-- NIVEL DE APERTURA
-- ---------------------------------------------------------------------------
--
-- El nivel al que se abre TODO mundo. No es una tabla por mundo: es UN
-- numero, y esa unicidad es el contrato. Si alguien anade aqui `Cyber = 50`,
-- la comprobacion de `Audit` lo detecta en `npm test`.
--
-- Por que 1 y no 0: el comparador del portal es `nivel >= requerido`. Con `0`
-- un jugador recien creado (nivel 1) pasaria, pero un perfil recien
-- inicializado que aun no ha publicado `Level` leeria `nil`, y en Luau
-- `nil >= 0` es FALSO: el mundo quedaria cerrado por un bug de arranque y
-- "sin bloqueo" se convertiria en "cerrado para medio mundo".
Rules.OpenLevel = 1
-- ---------------------------------------------------------------------------
-- BANDAS DE DIFICULTAD DE LAS 99 NOCHES (FASE 8)
-- ---------------------------------------------------------------------------
--
-- LA REGLA ANTI-TRAMPOSO: la dificultad NO es `EnemyHP = Night * 100`.
--
-- Si lo fuera, la noche 50 seria imbatible por una razon que el jugador no
-- puede entender ni esquivar, y la unica estrategia seria "esperar a que
-- baje". Eso no es dificultad: es una puerta con otra etiqueta.
--
-- Aqui la curva reparte la presion en cinco ejes que se leen en el juego:
--
--   CountMul  cuantos enemigos hay a la vez
--   Aggro     cuanto se acercan antes de engaging
--   Frequency cada cuanto se repuebla la zona
--   Tier      cuantos TIPOS de enemigo entran en la rotacion
--
-- Un jugador ve crecer la noche en todas esas dimensiones a la vez, y cada
-- una admite una RESPUESTA distinta: mas enemigos -> bombas en cadena; mas
-- tipos -> aprender el contra de cada uno; mas agresividad -> elegir la ruta
-- antes que la fight.
--
-- La vida y el dano los escala `DifficultyRules`, con topes: un enemigo con
-- 40.000 de vida no es dificil, es un muro contra el que no hay decision.
Rules.Bands = {
	{ From = 1, To = 10, Label = "Exploracion", CountMul = 1.0, Tier = 1, Aggro = 0.00, Frequency = 1.00 },
	{ From = 11, To = 20, Label = "Escalada", CountMul = 1.35, Tier = 2, Aggro = 0.05, Frequency = 1.10 },
	{ From = 21, To = 30, Label = "Hordas", CountMul = 1.70, Tier = 3, Aggro = 0.12, Frequency = 1.25 },
	{ From = 31, To = 40, Label = "Elite", CountMul = 2.05, Tier = 4, Aggro = 0.18, Frequency = 1.40 },
	{ From = 41, To = 50, Label = "Marea", CountMul = 2.40, Tier = 5, Aggro = 0.24, Frequency = 1.55 },
	{ From = 51, To = 60, Label = "Avanzado", CountMul = 2.75, Tier = 6, Aggro = 0.30, Frequency = 1.70 },
	{ From = 61, To = 70, Label = "Peligro", CountMul = 3.05, Tier = 7, Aggro = 0.36, Frequency = 1.85 },
	{ From = 71, To = 80, Label = "Caceria", CountMul = 3.35, Tier = 8, Aggro = 0.42, Frequency = 2.00 },
	{ From = 81, To = 90, Label = "Extremo", CountMul = 3.65, Tier = 9, Aggro = 0.48, Frequency = 2.15 },
	{ From = 91, To = 98, Label = "Preludio", CountMul = 3.95, Tier = 10, Aggro = 0.55, Frequency = 2.30 },
	{ From = 99, To = 99, Label = "FINAL", CountMul = 4.60, Tier = 11, Aggro = 0.65, Frequency = 2.60 },
}

-- Ultima noche. El sistema no existe mas alla: una "noche 100" seria un
-- numero que no le significa nada al jugador.
Rules.MaxNight = 99

-- ---------------------------------------------------------------------------
-- CONSULTAS
-- ---------------------------------------------------------------------------

--- Ids de los mundos, en orden estable.
--- @return { string }
function Rules.GetWorldIds(): { string }
	local ids = {}
	for _, id in ipairs(Rules.WorldOrder) do
		table.insert(ids, id)
	end
	return ids
end

--- El mundo existe en el CATALOGO del juego.
---
--- Esto NO es lo mismo que "esta disponible": lo primero se responde sin
--- servidor (es una lista) y lo segundo necesita el registro de
--- `WorldService`. La separacion permite que las pruebas comprueben el catalogo
--- sin arrancar el juego.
--- @param worldId any
--- @return boolean
function Rules.IsKnownWorld(worldId: any): boolean
	if type(worldId) ~= "string" then
		return false
	end
	for _, id in ipairs(Rules.WorldOrder) do
		if id == worldId then
			return true
		end
	end
	return false
end

--- Nivel requerido para entrar. SIEMPRE `OpenLevel` (1).
---
--- La funcion se conserva porque `PortalService` la lee para PINTAR el cartel
--- del portal y porque el diagnostico la muestra. Quitar el bloqueo no es
--- quitar la informacion: el jugador sigue viendo "nivel 1" en todos los
--- portales, que es la garantia de que nadie esta pagando un requisito
--- invisible.
--- @param worldId any
--- @return number
function Rules.GetRequiredLevel(worldId: any): number
	-- Un mundo desconocido tambien devuelve `OpenLevel` y no 0: el `0` se
	-- leeria como "nivel 0" en un cartel y daria a entender que hay un atajo.
	-- Lo rechaza `CanEnter`, que es quien decide; aqui solo hay dato.
	return Rules.OpenLevel
end

--- Dificultad base de un mundo (1..5). 0 si no existe.
--- @param worldId any
--- @return number
function Rules.GetDifficulty(worldId: any): number
	if type(worldId) ~= "string" then
		return 0
	end
	return Rules.DifficultyByWorld[worldId :: string] or 0
end

--- Nombre legible de un mundo.
--- @param worldId any
--- @return string
function Rules.GetDisplayName(worldId: any): string
	if type(worldId) ~= "string" then
		return "?"
	end
	return Rules.DisplayNameByWorld[worldId :: string] or worldId
end

--- Un mundo abrible DESDE EL NIVEL 1.
---
--- Este es el unico predicado que decide la entrada. No mira el nivel del
--- jugador, y esa ausencia es DELIBERADA: es la fase 3 del enunciado.
---
--- `availableFn` es el predicado del SERVIDOR (mundo registrado y habilitado
--- en `WorldService`). Se pasa por parametro para que este modulo siga siendo
--- puro y probable sin motor; si no se pasa, se asume que todo mundo conocido
--- esta disponible.
--- @param worldId any
--- @param availableFn ((string) -> boolean)?
--- @return boolean allowed
--- @return string? reason
function Rules.CanEnter(worldId: any, availableFn: ((string) -> boolean)?): (boolean, string?)
	if not Rules.IsKnownWorld(worldId) then
		return false, "mundo desconocido"
	end

	local id = worldId :: string

	if availableFn then
		local ok, available = pcall(availableFn, id)
		if not ok or not available then
			return false, "mundo no disponible"
		end
	end

	return true, nil
end

-- ---------------------------------------------------------------------------
-- BANDAS
-- ---------------------------------------------------------------------------

export type Band = {
	From: number,
	To: number,
	Label: string,
	CountMul: number,
	Tier: number,
	Aggro: number,
	Frequency: number,
}

--- Banda de dificultad de una noche.
--- @param night number
--- @return Band?
function Rules.GetBand(night: number): Band?
	local n = Rules.ClampNight(night)

	for _, band in ipairs(Rules.Bands) do
		if n >= band.From and n <= band.To then
			return band
		end
	end

	return nil
end

--- Acota una noche al rango jugable.
---
--- Existe porque la noche llega de FUERA en varios sitios (perfil guardado,
--- comando de admin, atajo de pruebas) y un `nil`, un `0` o un `NaN` aqui se
--- colarian en las multiplicaciones. El `NaN` es el peligroso: `tonumber` lo
--- acepta, `math.floor` lo deja pasar y cualquier comparacion posterior es
--- falsa, con lo que la partida se queda SIN dificultad y sin avisar.
--- @param night any
--- @return number
function Rules.ClampNight(night: any): number
	local n = tonumber(night)

	if not n or n ~= n then
		return 1
	end

	return math.clamp(math.floor(n), 1, Rules.MaxNight)
end

--- Es la noche final.
--- @param night number
--- @return boolean
function Rules.IsFinalNight(night: number): boolean
	return Rules.ClampNight(night) == Rules.MaxNight
end

-- ---------------------------------------------------------------------------
-- AUDITORIA
-- ---------------------------------------------------------------------------

--- Comprueba que el catalogo de acceso es coherente.
---
--- La ejecuta `WorldAccess.spec`. Sin esto, un mundo olvidado en
--- `WorldOrder` con dificultad declarada pasaria desapercibido:
--- `GetDifficulty` devolveria 0 y el mundo seria mas facil que Forest.
---
--- `declared` es opcional y es la tabla que el servidor carga de
--- `WorldDefinitions`: `mundo -> { Difficulty, RequiredLevel }`. Cuando se
--- pasa, la auditoria comprueba que el generador y estas reglas NO divergen,
--- que es exactamente el fallo que produjo el nivel 50 de Cyber.
--- @param declared any?
--- @return { string } problemas lista vacia = todo cuadra
function Rules.Audit(declared: any?): { string }
	local problems: { string } = {}

	for _, id in ipairs(Rules.WorldOrder) do
		local difficulty = Rules.DifficultyByWorld[id]

		if type(difficulty) ~= "number" or difficulty < 1 or difficulty > 5 then
			table.insert(problems, ("%s: dificultad %s fuera de 1..5")
				:format(id, tostring(difficulty)))
		end

		if Rules.GetDisplayName(id) == id then
			table.insert(problems, ("%s: sin nombre legible (se mostraria el id)"):format(id))
		end
	end

	if #Rules.WorldOrder ~= 5 then
		table.insert(problems, ("se esperaban 5 mundos, hay %d"):format(#Rules.WorldOrder))
	end

	-- Las bandas tienen que cubrir 1..99 SIN huecos: un hueco seria una noche
	-- sin dificultad, que es una noche en la que el jugador no nota nada.
	local covered = {}
	for _, band in ipairs(Rules.Bands) do
		for n = band.From, band.To do
			if covered[n] then
				table.insert(problems, ("la noche %d esta en dos bandas"):format(n))
			end
			covered[n] = true
		end
	end

	for n = 1, Rules.MaxNight do
		if not covered[n] then
			table.insert(problems, ("la noche %d no esta en ninguna banda"):format(n))
		end
	end

	if declared then
		for _, id in ipairs(Rules.WorldOrder) do
			local entry = declared[id]

			if type(entry) ~= "table" then
				table.insert(problems, ("%s: WorldDefinitions no lo declara"):format(id))
			else
				if entry.Difficulty ~= Rules.DifficultyByWorld[id] then
					table.insert(problems, ("%s: Difficulty %s en WorldDefinitions, %s aqui")
						:format(id, tostring(entry.Difficulty), tostring(Rules.DifficultyByWorld[id])))
				end

				-- El bloqueo por nivel no debe volver. Esta comprobacion
				-- existe para que alguien que reinstale un `RequiredLevel = 50`
				-- lo vea rojo en `npm test` y no en un playtest.
				if entry.RequiredLevel ~= Rules.OpenLevel then
					table.insert(problems, ("%s: RequiredLevel %s vuelve a cerrar el mundo")
						:format(id, tostring(entry.RequiredLevel)))
				end

				-- El nombre legible tiene que ser el de la definicion. El
				-- cartel del portal pinta `definition.DisplayName`; si estas
				-- reglas dijeran otra cosa, el catalogo interno mostraria un
				-- nombre que no existe en el mapa (fue el caso Ice/Volcano).
				if type(entry.DisplayName) == "string"
					and entry.DisplayName ~= Rules.GetDisplayName(id) then
					table.insert(problems, ("%s: nombre '%s' aqui, '%s' en la definicion")
						:format(id, Rules.GetDisplayName(id), entry.DisplayName))
				end
			end
		end
	end

	return problems
end

return Rules