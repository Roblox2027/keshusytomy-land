--!strict
--[[
	ProgressionService
	XP, nivel y recompensas de subida. Autoridad del servidor.

	LA CURVA NO SE REINVENTA
	-------------------------
	Este servicio NO decide el nivel. Usa `CombatMath.LevelForXp` con la
	curva de `GameConfig`, las MISMAS que ya usaba `PlayerService`. Si
	calculase aqui su propia version, `PlayerService` y este darian
	niveles DISTINTOS para la misma XP, y el jugador veria un nivel
	mientras el servidor cobra en otro.

	EL NIVEL SE DERIVA, NO SE GUARDA COMO VERDAD
	--------------------------------------------
	El perfil guarda `Level` como CACHE para la UI. El nivel real sale
	siempre de `GetLevel`, que recalcula desde el XP. Si `Level` fuese la
	fuente de verdad, bastaria escribir 9999 en el perfil para tener el
	`MaxLevel` sin ganar nada.

	IDEMPOTENCIA: DOS COSAS DISTINTAS
	---------------------------------
	    `AddXP`         impide que la MISMA xp se conceda dos veces
	    `ClaimLevel...` impide que la RECOMPENSA de un nivel se pague dos
	                    veces

	Un jugador puede volver a alcanzar un nivel que ya habia alcanzado (por
	una correccion de balance, o por un cambio de curva) y aun asi no debe
	cobrarlo otra vez. Son dos controles distintos y confundirlos deja la
	puerta abierta a monedas infinitas.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONFIG = SHARED:WaitForChild("Config")
local UTILS = SHARED:WaitForChild("Utils")

local GameConfig = require(CONFIG:WaitForChild("GameConfig"))
local CombatMath = require(SHARED:WaitForChild("Libraries"):WaitForChild("CombatMath"))
local ProgressionRules = require(SHARED:WaitForChild("Libraries"):WaitForChild("ProgressionRules"))
local Logger = require(UTILS:WaitForChild("Logger"))

local Service = {}

Service.IsInitialized = false

-- ProfileService (estado) y EconomyService (pago de recompensas).
Service._profileService = nil
Service._economyService = nil

-- Reglas puras. La curva se inyecta desde `GameConfig`, igual que en el
-- servicio real, para que las pruebas y el juego usen los mismos numeros.
local Rules = ProgressionRules.new({
	levelForXp = CombatMath.LevelForXp,
	xpForLevel = CombatMath.XpForLevel,
	levelProgress = CombatMath.LevelProgress,
})
Service._rules = Rules

-- Curva vigente.
Service._curve = {
	xpPerLevel = GameConfig.XPPerLevel,
	exponent = GameConfig.LevelCurveExponent,
	maxLevel = GameConfig.MaxLevel,
}

-- Recompensa por nivel.
Service._rewardConfig = {
	baseCoins = GameConfig.LevelRewardBaseCoins,
	coinsPerLevel = GameConfig.LevelRewardCoinsPerLevel,
}

Service._stats = { xpGranted = 0, levelsGained = 0, rejected = 0, duplicates = 0, rewardsCoins = 0 }

-- Maid recibido en Init.
local MaidRef = nil

--- Inyecta las dependencias del servicio.
--- @param profileService any
--- @param economyService any
function Service.SetDependencies(profileService: any, economyService: any)
	Service._profileService = profileService
	Service._economyService = economyService
end

--- Inicializacion del servicio. Idempotente.
--- @param maid any?
--- @return boolean success
function Service.Init(maid: any?): boolean
	MaidRef = maid
	Service._stats = { xpGranted = 0, levelsGained = 0, rejected = 0, duplicates = 0, rewardsCoins = 0 }
	Service.IsInitialized = true
	return true
end

--- Arranque. Verifica las dependencias y la coherencia del balance.
--- @param maid any?
--- @return boolean success
function Service.Start(maid: any?): boolean
	if not Service._profileService then
		Logger.Error("ProgressionService: sin ProfileService; la progresion no puede funcionar.")
		return false
	end

	-- La curva tiene que ser MONOTONA CRECIENTE. Si un nivel costara lo
	-- mismo o menos que el anterior, `LevelForXp` (que recorre en vez de
	-- usar formula cerrada) podria quedarse en un bucle o dar niveles
	-- incoherentes. Se comprueba ahora y no con un jugador en partida.
	if Service._curve.xpPerLevel <= 0 then
		Logger.Error("ProgressionService: XPPerLevel debe ser mayor que 0.")
		return false
	end

	if Service._curve.exponent <= 0 then
		Logger.Error("ProgressionService: LevelCurveExponent debe ser mayor que 0.")
		return false
	end

	-- El nivel 2 tiene que costar mas de 0. Es la unica forma de subir de
	-- nivel, y si no se cumple `AddXP` nunca devolveria `levelsGained > 0`
	-- y la progresion pareceria rota sin ningun error visible.
	if CombatMath.XpForLevel(2, Service._curve.xpPerLevel, Service._curve.exponent, Service._curve.maxLevel) <= 0 then
		Logger.Error("ProgressionService: el nivel 2 no cuesta XP; nadie podria subir.")
		return false
	end

	Logger.Info("ProgressionService: progresion lista.")
	return true
end

--- Limpieza del servicio.
--- @return boolean success
function Service.Destroy(): boolean
	Service.IsInitialized = false
	Service._profileService = nil
	Service._economyService = nil
	MaidRef = nil
	return true
end

-- ---------------------------------------------------------------
-- API
-- ---------------------------------------------------------------

--- Estado de progresion de un jugador, o nil.
--- @param player Player?
--- @return any?
local function progressionStateOf(player: Player?): any?
	if not player or not Service._profileService then
		return nil
	end
	return Service._profileService.GetProgressionState(player)
end

--- Paga las recompensas de los niveles aun NO pagados.
---
--- Se declara ANTES de `AddXP` a proposito: Luau resuelve los locales en
--- orden de declaracion, y `AddXP` la invoca.
--- @param player Player
--- @param state any
--- @return { any } claims
local function payLevelRewards(player: Player, state: any): { any }
	local claims = Rules:ClaimLevelRewards(state, Service._curve, Service._rewardConfig)

	if #claims == 0 then
		return claims
	end

	if not Service._economyService then
		-- El nivel SUBE aunque no se pueda pagar. Perder la subida por un
		-- fallo del modulo de economia seria peor que no dar las monedas:
		-- el jugador tendria el nivel en la UI sin haberlo ganado, que es
		-- un fallo de contenido mas grave que un retraso en el pago.
		Logger.Error(("Progression: %s subio de nivel pero no hay EconomyService; no se pagan las recompensas"):format(
			player.Name
		))
		return claims
	end

	-- Nivel por nivel, cada uno con su propia peticion idempotente. Sumarlos
	-- en un unico `Grant` perderia la trazabilidad: el ledger mostraria
	-- "500 coins" sin decir de que nivel(es) son, y un jugador que subiera
	-- dos niveles no podria comprobar nada.
	for _, claim in ipairs(claims) do
		if claim.coins > 0 then
			Service._economyService.GrantCurrency(
				player,
				"Coins",
				claim.coins,
				("recompensa_nivel_%d"):format(claim.level),
				"progression",
				{ level = claim.level },
				("level-reward:%d:%d"):format(player.UserId, claim.level)
			)
			Service._stats.rewardsCoins += claim.coins
		end
	end

	return claims
end

--- XP total acumulada. 0 si no hay perfil.
--- @param player Player?
--- @return number
function Service.GetXP(player: Player?): number
	return Rules:GetXP(progressionStateOf(player))
end

--- Nivel actual, DERIVADO del XP.
--- @param player Player?
--- @return number
function Service.GetLevel(player: Player?): number
	return Rules:GetLevel(progressionStateOf(player), Service._curve)
end

--- XP que falta para el siguiente nivel. 0 en el tope.
--- @param player Player?
--- @return number
function Service.GetXPToNextLevel(player: Player?): number
	return Rules:GetXPToNextLevel(progressionStateOf(player), Service._curve)
end

--- Progreso dentro del nivel, para la barra.
--- @param player Player?
--- @return number current
--- @return number needed
function Service.GetLevelProgress(player: Player?): (number, number)
	return Rules:GetLevelProgress(progressionStateOf(player), Service._curve)
end

--- Indica si el jugador tiene XP de sobra para subir de nivel.
---
--- Es una CONSULTA. Quien la use para decidir si pagar una recompensa tiene
--- que volver a mirar despues: entre la pregunta y el cobro el XP puede
--- haber cambiado.
--- @param player Player?
--- @return boolean
function Service.CheckLevelUp(player: Player?): boolean
	local state = progressionStateOf(player)

	return Rules:GetLevel(state, Service._curve) > 1
		and Rules:GetXPToNextLevel(state, Service._curve) <= 0
end

--- Concede XP, sube de nivel si toca y PAGA la recompensa de subida.
---
--- El flujo completo en una llamada, y en este orden, porque el orden es lo
--- que evita los fallos:
---
---   1. se anade el XP (con su propia idempotencia por `requestId`)
---   2. se pagan las recompensas de TODOS los niveles cruzados
---   3. se publica el nuevo nivel para la UI
---
--- Pagar antes de calcular el nivel daria un numero de niveles equivocado, y
--- pagar solo el ULTIMO perderia las recompensas intermedias sin que nadie
--- lo notara.
--- @param player Player?
--- @param amount number
--- @param source string
--- @param requestId string?
--- @return boolean success
--- @return any? result { xp, levelBefore, levelAfter, levelsGained }
--- @return string? errorReason
function Service.AddXP(
	player: Player?,
	amount: number,
	source: string,
	requestId: string?
): (boolean, any?, string?)
	local state = progressionStateOf(player)
	if not state then
		Service._stats.rejected += 1
		return false, nil, "el jugador no tiene perfil cargado"
	end

	local ok, result, err = Rules:AddXP(
		state,
		amount,
		Service._curve,
		source,
		requestId,
		ProgressionRules.Sources.Player
	)

	if not ok then
		Service._stats.rejected += 1
		Logger.Warn(("Progression: no se pudo dar %s XP a %s: %s"):format(
			tostring(amount),
			player.Name,
			tostring(err)
		))
		return false, nil, err
	end

	-- Idempotencia: si la peticion se repitio, `levelsGained` es 0 y no se
	-- vuelve a pagar. Es exactamente para eso.
	if result.Replayed then
		Service._stats.duplicates += 1
		return true, result, nil
	end

	Service._stats.xpGranted += result.xp
	Service._stats.levelsGained += result.levelsGained
	Service._profileService.MarkDirty(player)

	if result.levelsGained > 0 then
		payLevelRewards(player, state)
		player:SetAttribute("LeveledUpTo", result.levelAfter)
		Logger.Info(("%s subio al nivel %d (+%d XP)"):format(player.Name, result.levelAfter, result.xp))
	else
		-- Se borra el atributo en vez de dejarlo: si no, la UI seguiria
		-- celebrando una subida vieja la proxima vez que se actualice.
		player:SetAttribute("LeveledUpTo", nil)
	end

	player:SetAttribute("Level", result.levelAfter)
	player:SetAttribute("XP", result.totalXp)

	return true, result, nil
end

--- Coins que se pagan por alcanzar un nivel concreto.
---
--- Es una FUNCION del nivel, no una tabla guardada. Si se guardase, un
--- jugador con un perfil viejo conservaria los valores de cuando subio y
--- cambiar el balance no tendria efecto en el mundo real.
--- @param level number
--- @return number coins
function Service.GetLevelRewardCoins(level: number): number
	return ProgressionRules.GetLevelRewardCoins(level, Service._rewardConfig)
end

--- Indica si un nivel ya esta pagado.
--- @param player Player?
--- @param level number
--- @return boolean
function Service.HasClaimedLevel(player: Player?, level: number): boolean
	return Rules:IsLevelClaimed(progressionStateOf(player), level)
end

--- Anomalias de la progresion. Lista vacia = todo cuadra.
--- @param player Player?
--- @return { string }
function Service.AuditPlayer(player: Player?): { string }
	return Rules:Audit(progressionStateOf(player), Service._curve)
end

--- Resumen para observabilidad.
--- @return { [string]: number }
function Service.GetStats(): { [string]: number }
	return {
		xpGranted = Service._stats.xpGranted,
		levelsGained = Service._stats.levelsGained,
		rejected = Service._stats.rejected,
		duplicates = Service._stats.duplicates,
		rewardsCoins = Service._stats.rewardsCoins,
	}
end

return Service
