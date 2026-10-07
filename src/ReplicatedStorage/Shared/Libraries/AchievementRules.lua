--!strict
--[[
	AchievementRules
	LOGROS y TITULOS (MASTER MISSION V2 - FASES 17 y 19).

	POR QUE EXISTE
	--------------
	La progresion se detenia en XP y nivel: al terminar la ronda no habia
	objetivo a largo plazo. Los logros dan ese objetivo, y los titulos son
	su cara PUBLICA: cosmeticos, visibles y desbloqueables por jugar.

	QUE VIVE AQUI
	-------------
	El catalogo y la comprobacion de desbloqueo: todo puro y medible en
	pruebas. El servicio (`AchievementService`) aporta el perfil, el pago
	y la publicacion.

	LA REGLA DE DISENO
	------------------
	Ningun logro es imposible y ningun logro se regala: cada umbral es un
	numero que un jugador normal alcanza JUGANDO, no farmeando una esquina.
	Y ningun logro paga poder: monedas y titulo, nunca dano.
]]

local Rules = {}

-- ---------------------------------------------------------------------------
-- CATALOGO DE LOGROS
-- ---------------------------------------------------------------------------
--
-- Campos:
--   Id         clave estable (persistencia; no cambiar jamas)
--   Label      texto para el jugador
--   Metric     la metrica que lo alimenta (la MISMA que `RecordMetric`)
--   Threshold  cantidad total que lo desbloquea
--   Coins      recompensa en monedas
--   Title      titulo que desbloquea (opcional)

Rules.Catalog = {
	{
		Id = "Kills50",
		Label = "Cazador",
		Metric = "MonsterDefeated",
		Threshold = 50,
		Coins = 150,
		Title = "Cazador",
	},
	{
		Id = "Kills250",
		Label = "Maestro Cazador",
		Metric = "MonsterDefeated",
		Threshold = 250,
		Coins = 400,
		Title = "Maestro",
	},
	{
		Id = "Blocks200",
		Label = "Demolition",
		Metric = "BlockDestroyed",
		Threshold = 200,
		Coins = 150,
	},
	{
		Id = "Secrets5",
		Label = "Descubridor",
		Metric = "SecretDiscovered",
		Threshold = 5,
		Coins = 200,
		Title = "Descubridor",
	},
	{
		Id = "MiniBoss5",
		Label = "Cazador de elites",
		Metric = "MiniBossDefeated",
		Threshold = 5,
		Coins = 250,
		Title = "Conquistador",
	},
	{ Id = "Boss1", Label = "Rompejefes", Metric = "BossDefeated", Threshold = 1, Coins = 300 },
	{
		Id = "Boss5",
		Label = "Leyenda",
		Metric = "BossDefeated",
		Threshold = 5,
		Coins = 600,
		Title = "Leyenda",
	},
	{
		Id = "Events10",
		Label = "Ojo del huracan",
		Metric = "EventCompleted",
		Threshold = 10,
		Coins = 250,
	},
	{
		Id = "Rounds10",
		Label = "Explorador",
		Metric = "RoundWon",
		Threshold = 10,
		Coins = 200,
		Title = "Explorador",
	},
	{ Id = "Bombs100", Label = "Artificiero", Metric = "BombPlaced", Threshold = 100, Coins = 150 },
}

-- ---------------------------------------------------------------------------
-- CONSULTA
-- ---------------------------------------------------------------------------

--- Logro por id, o nil.
--- @param id any
--- @return any?
function Rules.Get(id: any): any?
	if type(id) ~= "string" then
		return nil
	end

	for _, achievement in ipairs(Rules.Catalog) do
		if achievement.Id == id then
			return achievement
		end
	end

	return nil
end

--- Logros alimentados por una metrica.
--- @param metric any
--- @return { any }
function Rules.ForMetric(metric: any): { any }
	local out = {}

	if type(metric) ~= "string" then
		return out
	end

	for _, achievement in ipairs(Rules.Catalog) do
		if achievement.Metric == metric then
			table.insert(out, achievement)
		end
	end

	return out
end

--- Logros desbloqueados dado un mapa metrica -> total.
---
--- La comprobacion es una CONSULTA sobre totales, no un contador propio:
--- la verdad de "cuantos monstruos has matado" vive en el perfil, y un
--- logro que guardara SU cuenta podria desincronizarse de ella.
--- @param totals any { [metric] = number }
--- @return { string } ids desbloqueados
function Rules.UnlockedFor(totals: any): { string }
	local out = {}

	if type(totals) ~= "table" then
		return out
	end

	for _, achievement in ipairs(Rules.Catalog) do
		local total = tonumber(totals[achievement.Metric]) or 0

		if total >= achievement.Threshold then
			table.insert(out, achievement.Id)
		end
	end

	return out
end

--- Titulos desbloqueados dado un conjunto de logros.
--- @param unlockedIds any { [achievementId] = true } o lista de ids
--- @return { string }
function Rules.TitlesFor(unlockedIds: any): { string }
	local out = {}

	if type(unlockedIds) ~= "table" then
		return out
	end

	local function isUnlocked(id: string): boolean
		if unlockedIds[id] == true then
			return true
		end

		for _, value in ipairs(unlockedIds) do
			if value == id then
				return true
			end
		end

		return false
	end

	for _, achievement in ipairs(Rules.Catalog) do
		if achievement.Title and isUnlocked(achievement.Id) then
			table.insert(out, achievement.Title)
		end
	end

	return out
end

return Rules
