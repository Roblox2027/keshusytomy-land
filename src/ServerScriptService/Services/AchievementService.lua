--!strict
--[[
	AchievementService
	LOGROS y TITULOS (MASTER MISSION V2 - FASES 17 y 19).

	QUE HACE Y QUE DELEGA
	---------------------
	NO decide que es un logro: el catalogo y los umbrales son de
	`AchievementRules` (puro, probado). Este servicio aporta lo que el
	motor: el perfil, el pago y la publicacion al HUD.

	DE DONDE SALEN LAS METRICAS
	---------------------------
	`QuestService.RecordMetric` es el UNICO embudo de metricas de juego:
	aqui no se re-suscribe a seis servicios distintos. Cada metrica que
	avanza una mision alimenta TAMBIEN los logros, y asi nunca divergen.

	LA REGLA DE AUTORIDAD
	---------------------
	El desbloqueo lo decide el servidor sobre los TOTALES del perfil,
	nunca sobre lo que dice el cliente. El pago es monedas via
	`EconomyService.GrantCurrency` con requestId: un logro no se cobra
	dos veces.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local UTILS = SHARED:WaitForChild("Utils")

local AchievementRules = require(SHARED:WaitForChild("Libraries"):WaitForChild("AchievementRules"))
local Logger = require(UTILS:WaitForChild("Logger"))

local Service = {}

Service.IsInitialized = false

-- Servicios inyectados por `ServerMain`.
Service._profileService = nil
Service._economyService = nil

-- Diagnostico.
Service._unlocksGranted = 0

-- ---------------------------------------------------------------------------
-- INYECCION
-- ---------------------------------------------------------------------------

--- @param profileService any
--- @param economyService any?
function Service.SetDependencies(profileService: any, economyService: any?)
	Service._profileService = profileService
	Service._economyService = economyService
end

-- ---------------------------------------------------------------------------
-- NUCLEO
-- ---------------------------------------------------------------------------

--- Estado de logros del perfil, creado si falta.
--- @param player Player
--- @return any? estado, o nil sin perfil
local function stateOf(player: Player): any?
	local profiles = Service._profileService

	if not profiles or not profiles.HasProfile or not profiles.HasProfile(player) then
		return nil
	end

	local profile = profiles.GetProfile(player)

	if type(profile) ~= "table" then
		return nil
	end

	if type(profile.Achievements) ~= "table" then
		profile.Achievements = { Totals = {}, Unlocked = {} }
	end
	if type(profile.Achievements.Totals) ~= "table" then
		profile.Achievements.Totals = {}
	end
	if type(profile.Achievements.Unlocked) ~= "table" then
		profile.Achievements.Unlocked = {}
	end
	if type(profile.Titles) ~= "table" then
		profile.Titles = { Unlocked = {}, Equipped = "" }
	end
	if type(profile.Titles.Unlocked) ~= "table" then
		profile.Titles.Unlocked = {}
	end

	return profile
end

--- Acumula una metrica y desbloquea lo que cruce su umbral.
---
--- Es el UNICO punto de entrada, y lo llama `QuestService.RecordMetric`
--- DESPUES de registrar la metrica de mision. Un logro que se desbloquea
--- sin que la metrica suba seria un logro regalado.
--- @param player Player
--- @param metric string
--- @param amount number
function Service.RecordMetric(player: Player, metric: string, amount: number)
	local profile = stateOf(player)

	if not profile then
		return
	end

	local totals = profile.Achievements.Totals
	totals[metric] = (tonumber(totals[metric]) or 0) + amount

	-- Solo se miran los logros alimentados por ESTA metrica: recorrer el
	-- catalogo entero por cada kill es trabajo desperdiciado.
	for _, achievement in ipairs(AchievementRules.ForMetric(metric)) do
		local total = totals[metric]

		if total >= achievement.Threshold and not profile.Achievements.Unlocked[achievement.Id] then
			profile.Achievements.Unlocked[achievement.Id] = true
			Service._unlocksGranted += 1

			-- El titulo, si lo tiene, se desbloquea aqui: es parte del
			-- premio, no un sistema aparte.
			if achievement.Title then
				profile.Titles.Unlocked[achievement.Title] = true
			end

			-- El pago pasa por la via UNICA de monedas, con requestId
			-- derivado del logro: reclamar dos veces el mismo logro es
			-- la misma transaccion y se rechaza sola.
			local economy = Service._economyService

			if economy and economy.GrantCurrency then
				pcall(
					economy.GrantCurrency,
					player,
					"Coins",
					achievement.Coins,
					("logro_%s"):format(achievement.Id),
					"achievement_service",
					nil,
					("ach_%d_%s"):format(player.UserId, achievement.Id)
				)
			end

			Service._profileService.MarkDirty(player)

			-- El aviso lo publica el SERVIDOR: el HUD lo muestra tal cual.
			player:SetAttribute("AchievementUnlocked", achievement.Label)

			if achievement.Title then
				player:SetAttribute("TitleUnlocked", achievement.Title)
			end

			Logger.Info(
				("AchievementService: %s desbloqueo '%s'"):format(player.Name, achievement.Id)
			)
		end
	end

	-- El conteo publico se refresca en cada metrica: barato y siempre al dia.
	local count = 0
	for _ in pairs(profile.Achievements.Unlocked) do
		count += 1
	end

	player:SetAttribute("AchievementsCount", count)
end

--- Titulos desbloqueados del jugador (diagnostico y UI).
--- @param player any
--- @return { string }
function Service.GetTitles(player: any): { string }
	local profile = stateOf(player)

	if not profile then
		return {}
	end

	local out = {}

	for title in pairs(profile.Titles.Unlocked) do
		table.insert(out, title)
	end

	table.sort(out)
	return out
end

-- ---------------------------------------------------------------------------
-- CICLO DE VIDA DEL SERVICIO
-- ---------------------------------------------------------------------------

--- Inicializacion. Idempotente.
--- @param _maid any?
--- @return boolean success
function Service.Init(_maid: any?): boolean
	if Service.IsInitialized then
		return true
	end

	Service._unlocksGranted = 0
	Service.IsInitialized = true
	return true
end

--- Arranque. No hay hilos: el servicio responde a metricas.
--- @return boolean success
function Service.Start(): boolean
	if not Service.IsInitialized then
		Logger.Error("AchievementService: Start sin Init")
		return false
	end

	if not Service._profileService then
		Logger.Error("AchievementService: falta ProfileService.")
		return false
	end

	Logger.Info(
		("AchievementService: listo (%d logros en catalogo)."):format(#AchievementRules.Catalog)
	)
	return true
end

--- Apagado. Idempotente.
--- @return boolean success
function Service.Destroy(): boolean
	Service.IsInitialized = false
	return true
end

return Service
