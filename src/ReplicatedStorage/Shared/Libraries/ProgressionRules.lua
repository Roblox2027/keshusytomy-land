--!strict
--[[
	ProgressionRules
	XP, niveles y recompensas de nivel como LOGICA PURA.

	POR QUE ES PURO
	---------------
	"El nivel 950 de XP es el 3" es una FORMULA. Si vive dentro de
	`ProgressionService` no se puede probar con `luau.exe`. Este modulo
	la aisla, igual que hizo `CombatMath` con el dano.

	REUTILIZA LA FORMULA EXISTENTE
	-----------------------------
	La curva de nivel NO se reimplanta aqui: se INyecta. El proyecto ya
	tiene `CombatMath.LevelForXp` y su combinacion con
	`GameConfig.XPPerLevel` / `LevelCurveExponent` / `MaxLevel`, y cambiar
	la curva aqui dejaria a `PlayerService` y a la progresion dando niveles
	DISTINTOS para la misma XP. Eso no se puede permitir: el jugador
	veria un nivel y el servidor cobraria en otro.

	El patron es el mismo que `RemoteSchema`: la dependencia se INYECTA
	desde el consumidor porque en el interprete de pruebas `script` no
	existe y `require` no funciona con rutas de Roblox.

	SEPARACION DE FUENTES DE XP
	---------------------------
	Las fuentes se MANTIENEN SEPARADAS y no se suman en un unico numero:

	    Player XP      el XP del jugador (el unico que da nivel)
	    World Progress avance por mundos (FASE posterior)
	    Event XP       XP de evento (FASE posterior)
	    Season XP      XP de temporada (FASE posterior)

	Solo `Player.XP` alimenta el nivel. Mezclarlos seria la forma mas
	facil de "regalar XP" con una recompensa de evento que duplicase el
	avance de temporada, y nadie lo veria hasta que un jugadoriese mas
	de lo previsto.
]]

local ProgressionRules = {}
ProgressionRules.__index = ProgressionRules

--- Tope de seguridad del XP acumulado.
---
--- NO es un tope de contenido: la progresion no tiene nivel maximo de
--- juego. Es lo que impide que un dato corrupto (una migracion, un
--- `requestId` inventado) deje el perfil con un XP tan grande que ni
--- cabe en un DataStore ni se puede sumar.
ProgressionRules.MaxXP = 1e12

--- Cuantas fuentes de XP existen. Solo `Player` da nivel de momento.
ProgressionRules.Sources = {
	Player = "Player",
	World = "World",
	Event = "Event",
	Season = "Season",
}

--- Crea las reglas con las funciones de curva inyectadas.
---
--- Se exigen las DOS funciones porque son las que definen el nivel. Sin
--- ellas, este modulo no podria dar un nivel y devolveria siempre 1, que
--- es el fallo silencioso mas peligroso: el juego "funciona" y nadie
--- sube de nivel.
--- @param deps { levelForXp: (...any) -> number, xpForLevel: (...any) -> number, levelProgress: (...any) -> (number, number)? }
--- @return table
function ProgressionRules.new(deps: any): any
	assert(type(deps) == "table", "ProgressionRules.new requiere dependencias")
	assert(type(deps.levelForXp) == "function", "falta levelForXp")
	assert(type(deps.xpForLevel) == "function", "falta xpForLevel")

	return setmetatable({
		_levelForXp = deps.levelForXp,
		_xpForLevel = deps.xpForLevel,
		_levelProgress = deps.levelProgress,
	}, ProgressionRules)
end

--- Crea un estado de progresion vacio.
--- @param playerId number
--- @return any state
function ProgressionRules.NewState(playerId: number): any
	return {
		PlayerId = playerId,
		-- XP ACUMULADO. El nivel se deriva de aqui, nunca se guarda como
		-- un segundo valor: guardar XP y nivel por separado es la forma
		-- de que discrepen y de que un jugador "suba" sin motivo.
		XP = 0,
		Level = 1,
		-- Nivel YA pagado. Sin esto, una segunda visita al estado
		-- `Rewards` volveria a pagar la misma subida de nivel.
		ClaimedLevels = {},
		-- XP por fuente. Se guardan separadas a proposito (ver cabecera).
		Sources = { Player = 0, World = 0, Event = 0, Season = 0 },
		Stats = { Kills = 0, Deaths = 0, Rounds = 0 },
	}
end

-- ---------------------------------------------------------------
-- Consultas
-- ---------------------------------------------------------------

--- XP total acumulada.
--- @param state any
--- @return number
function ProgressionRules:GetXP(state: any): number
	if type(state) ~= "table" or type(state.XP) ~= "number" then
		return 0
	end
	if state.XP ~= state.XP then
		return 0
	end
	return state.XP
end

--- Nivel actual, DERIVADO del XP.
---
--- Se recalcula siempre en vez de leer `state.Level`. Recalcular es la
--- unica forma de que un XP guardado a mano no pueda fabricar niveles:
--- si `Level` fuera la fuente de verdad, bastaria escribir 9999 en el
--- perfil para tener el maximo.
--- @param state any
--- @param curve { xpPerLevel: number, exponent: number, maxLevel: number }
--- @return number
function ProgressionRules:GetLevel(state: any, curve: any): number
	local level = self._levelForXp(
		self:GetXP(state),
		curve.xpPerLevel,
		curve.exponent,
		curve.maxLevel
	)

	-- El limite se vuelve a aplicar aqui aunque la formula ya lo haga:
	-- `GetLevel` es la frontera que el resto del juego consulta, y un
	-- nivel imposible en un solo sitio es un fallo de la UI.
	if type(curve.maxLevel) == "number" and level > curve.maxLevel then
		return curve.maxLevel
	end

	return level
end

--- XP que falta para el siguiente nivel.
--- @param state any
--- @param curve { xpPerLevel: number, exponent: number, maxLevel: number }
--- @return number needed 0 si ya esta en el maximo
function ProgressionRules:GetXPToNextLevel(state: any, curve: any): number
	local xp = self:GetXP(state)
	local level = self:GetLevel(state, curve)

	if type(curve.maxLevel) == "number" and level >= curve.maxLevel then
		return 0
	end

	-- No se resta la base del nivel: `nextFloor` ya es XP TOTAL para
	-- llegar al siguiente nivel, no XP adicional. Restar el suelo aqui
	-- seria la causa clasica de "el jugador necesita mas XP del que dice
	-- la barra" en la segunda subida.
	local nextFloor = self._xpForLevel(level + 1, curve.xpPerLevel, curve.exponent, curve.maxLevel)

	return math.max(0, nextFloor - xp)
end

--- Progreso dentro del nivel actual, para la barra.
---
--- Se prefiere `CombatMath.LevelProgress` si se inyecto, porque hace una
--- sola pasada. Si no se inyecto se calcula aqui con las mismas piezas.
--- @param state any
--- @param curve { xpPerLevel: number, exponent: number, maxLevel: number }
--- @return number current
--- @return number needed
function ProgressionRules:GetLevelProgress(state: any, curve: any): (number, number)
	if self._levelProgress then
		return self._levelProgress(self:GetXP(state), curve.xpPerLevel, curve.exponent, curve.maxLevel)
	end

	local xp = self:GetXP(state)
	local level = self:GetLevel(state, curve)
	local floorXp = self._xpForLevel(level, curve.xpPerLevel, curve.exponent, curve.maxLevel)

	if type(curve.maxLevel) == "number" and level >= curve.maxLevel then
		return math.max(0, xp - floorXp), 0
	end

	local nextXp = self._xpForLevel(level + 1, curve.xpPerLevel, curve.exponent, curve.maxLevel)
	return math.max(0, xp - floorXp), math.max(1, nextXp - floorXp)
end

--- Concede XP y devuelve TODOS los niveles que se han cruzado.
---
--- Multi-nivel: una sola llamada puede cruzar varios niveles y se
--- procesan TODOS. Con un `while` que consume un nivel por vuelta, una
--- recompensa grande sube varios niveles; con un `if`, sube uno solo y el
--- jugador pierde el resto. El XP nunca se pierde: se guarda entero y el
--- nivel se deriva de el.
---
--- Idempotencia por `requestId`: si la misma recompensa llega dos veces, la
--- segunda NO vuelve a subir de nivel ni a pagar la recompensa. Es el
--- control que impide "infinitas monedas por nivel" con un listener
--- duplicado o una reconexion.
--- @param state any
--- @param amount number
--- @param curve { xpPerLevel: number, exponent: number, maxLevel: number }
--- @param source string
--- @param requestId string?
--- @param xpSource string? una de ProgressionRules.Sources
--- @return boolean success
--- @return any? result { xp, levelBefore, levelAfter, levelsGained }
--- @return string? errorReason
function ProgressionRules:AddXP(
	state: any,
	amount: number,
	curve: any,
	source: string,
	requestId: string?,
	xpSource: string?
): (boolean, any?, string?)
	if type(state) ~= "table" then
		return false, nil, "estado de progresion invalido"
	end

	-- Idempotencia ANTES de validar. Una peticion repetida devuelve su
	-- resultado y no toca el XP.
	--
	-- Se devuelve una COPIA con `levelsGained = 0` en vez del resultado
	-- guardado tal cual. Es la diferencia entre "repetir es seguro" y
	-- "repetir vuelve a subir de nivel": quien llama ve el resultado
	-- original (XP, nivel alcanzado) para poder responder al cliente, pero
	-- con `levelsGained = 0`, de modo que no vuelve a pagar la recompensa
	-- de subida. Devolver el mismo objeto, sin tocar, haria que un
	-- `if result.levelsGained > 0 then pagar()` concediera dos veces.
	if type(requestId) == "string" and requestId ~= "" then
		local previous = state.AppliedRequests and state.AppliedRequests[requestId]

		if previous then
			local replay = {}
			for key, value in previous do
				replay[key] = value
			end
			replay.levelsGained = 0
			replay.Replayed = true
			return true, replay, "peticion repetida; se devuelve el resultado anterior"
		end
	end

	-- Validacion de la cantidad. NaN e infinito salen antes de cualquier
	-- comparacion, porque en Luau `nan > 0` es false y un filtro ingenuo
	-- los dejaria pasar.
	if type(amount) ~= "number" then
		return false, nil, "XP no es un numero"
	end
	if amount ~= amount then
		return false, nil, "XP NaN"
	end
	if amount == math.huge or amount == -math.huge then
		return false, nil, "XP infinito"
	end
	if amount <= 0 then
		return false, nil, "XP no positivo"
	end

	local safeAmount = math.floor(amount)
	if safeAmount <= 0 then
		return false, nil, "XP menor que 1 tras redondear"
	end

	-- Tope de seguridad contra valores absurdos. NO es un tope de
	-- contenido: es lo que impide que un `requestId` malicioso o un bug
	-- dejen el perfil con un XP que no cabe en un DataStore.
	local maxXP = math.floor(ProgressionRules.MaxXP)
	if state.XP + safeAmount > maxXP then
		local room = maxXP - (type(state.XP) == "number" and state.XP or 0)
		if room <= 0 then
			return false, nil, "XP en el tope"
		end
		safeAmount = room
	end

	local levelBefore = self:GetLevel(state, curve)

	state.XP = self:GetXP(state) + safeAmount

	-- La fuente se acumula APARTE. Solo `Player` suma en `state.XP`.
	if type(xpSource) == "string" and state.Sources then
		state.Sources[xpSource] = (type(state.Sources[xpSource]) == "number" and state.Sources[xpSource] or 0)
			+ safeAmount
	end

	local levelAfter = self:GetLevel(state, curve)

	-- `state.Level` se escribe como CACHE para la UI. No es la fuente de
	-- verdad: `GetLevel` siempre recalcula desde el XP. Si alguien
	-- manipulase `state.Level` a mano, la siguiente lectura lo
	-- corregiria.
	state.Level = levelAfter

	local result = {
		xp = safeAmount,
		totalXp = state.XP,
		levelBefore = levelBefore,
		levelAfter = levelAfter,
		levelsGained = math.max(0, levelAfter - levelBefore),
		source = type(source) == "string" and source or "desconocido",
	}

	if type(requestId) == "string" and requestId ~= "" then
		state.AppliedRequests = state.AppliedRequests or {}
		state.AppliedRequests[requestId] = result
	end

	return true, result, nil
end
--- Recompensas por nivel, derivadas de una tabla de configuracion.
---
--- Se calcula aqui y NO se guarda en el perfil. Es una FUNCION del nivel:
--- si se guardase el premio de cada nivel, un jugador con un perfil viejo
--- conservaria para siempre los valores de cuando subio, y cambiar el
--- balance no tendria efecto en el mundo real. Ademas, guardar funciones
--- o resultados de ellas en el perfil lo llenaria de basura.
---
--- El multiplicador crece con el nivel para que subir tenga sentido sin
--- que el balance tenga que redefine cada numero.
--- @param level number
--- @param rewardConfig { baseCoins: number?, coinsPerLevel: number? }
--- @return number coins
function ProgressionRules.GetLevelRewardCoins(level: number, rewardConfig: any): number
	local resolved: { baseCoins: number?, coinsPerLevel: number? } = rewardConfig or {}
	local base = resolved.baseCoins or 0
	local perLevel = resolved.coinsPerLevel or 0

	if type(level) ~= "number" or level < 1 then
		return 0
	end

	return math.floor(base + perLevel * (level - 1))
end

--- Marca un nivel como pagado y devuelve la recompensa si no lo estaba.
---
--- La idempotencia de la RECOMPENSA vive aqui y no en `AddXP`. Son dos
--- cosas distintas que se confunden: `AddXP` impide que la MISMA xp se
--- conceda dos veces; esto impide que la RECOMPENSA de un nivel se pague
--- dos veces. Un jugador puede subir a un nivel que ya habia subido antes
--- (por una correccion de balance) y aun asi no debe cobrarlo otra vez.
--- @param state any
--- @param level number
--- @return boolean newlyClaimed
function ProgressionRules:ClaimLevel(state: any, level: number): boolean
	if type(state) ~= "table" then
		return false
	end

	if type(level) ~= "number" or level < 1 then
		return false
	end

	state.ClaimedLevels = state.ClaimedLevels or {}

	if state.ClaimedLevels[level] == true then
		return false
	end

	state.ClaimedLevels[level] = true
	return true
end

--- Indica si un nivel ya esta pagado.
--- @param state any
--- @param level number
--- @return boolean
function ProgressionRules:IsLevelClaimed(state: any, level: number): boolean
	if type(state) ~= "table" or type(state.ClaimedLevels) ~= "table" then
		return false
	end

	return state.ClaimedLevels[level] == true
end

--- Recompensa de una subida de nivel: idempotente y por nivel.
---
--- Devuelve la lista de niveles REALMENTE pagados. Si el jugador cruza
--- tres niveles, devuelve tres pagos: cobrar solo el ultimo perderia dos
--- recompensas de forma silenciosa, y es justo el fallo que hace que los
--- jugadores dejen de fiarse de subir de nivel.
--- @param state any
--- @param curve { xpPerLevel: number, exponent: number, maxLevel: number }
--- @param rewardConfig { baseCoins: number?, coinsPerLevel: number? }
--- @return { any } claims lista de { level, coins }
function ProgressionRules:ClaimLevelRewards(state: any, curve: any, rewardConfig: any): { any }
	local claims: { any } = {}

	local currentLevel = self:GetLevel(state, curve)
	if currentLevel < 2 then
		return claims
	end

	-- Se recorre del 2 al actual. El 1 no se premia: es el nivel inicial
	-- y "llegar a nivel 1" no es un logro.
	for level = 2, currentLevel do
		if self:ClaimLevel(state, level) then
			table.insert(claims, {
				level = level,
				coins = ProgressionRules.GetLevelRewardCoins(level, rewardConfig),
			})
		end
	end

	return claims
end

--- Anomalias de la progresion. Consulta pura.
---
--- Busca XP imposibles (NaN, infinito, negativo) y un `state.Level` que no
--- cuadra con el XP. Este ultimo caso es el que delata un perfil editado a
--- mano: el XP no da para el nivel guardado.
--- @param state any
--- @param curve { xpPerLevel: number, exponent: number, maxLevel: number }
--- @return { string }
function ProgressionRules:Audit(state: any, curve: any): { string }
	local problems: { string } = {}

	if type(state) ~= "table" then
		table.insert(problems, "estado de progresion invalido")
		return problems
	end

	local xp = state.XP

	if type(xp) ~= "number" then
		table.insert(problems, "XP no es un numero")
	elseif xp ~= xp then
		table.insert(problems, "XP es NaN")
	elseif xp == math.huge or xp == -math.huge then
		table.insert(problems, "XP es infinito")
	elseif xp < 0 then
		table.insert(problems, ("XP negativo (%d)"):format(xp))
	elseif xp > ProgressionRules.MaxXP then
		table.insert(problems, ("XP por encima del tope (%d)"):format(xp))
	end

	-- `Level` es una cache: si no cuadra, se regenera en la siguiente
	-- escritura. Se AVISA para que quede constancia, no se corrige aqui.
	if type(state.Level) == "number" then
		local derived = self:GetLevel(state, curve)
		if state.Level ~= derived then
			table.insert(problems, ("Level guardado (%d) no cuadra con el XP (%d)"):format(
				state.Level,
				derived
			))
		end
	end

	return problems
end

return ProgressionRules