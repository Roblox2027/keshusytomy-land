--!strict
--[[
	SkillService
	Autoridad de aplicar habilidades pasivas desbloqueadas por cofres.

	POR QUE EXISTE
	--------------
	`SkillCatalog` define efectos (BombCapacity, BombDamageMult,
	BombRadiusMult) y `ChestService` los guarda en el perfil. Pero
	BombService y ExplosionService usaban siempre valores hardcoded de
	GameConfig: las habilidades existían como datos pero NO afectaban
	el juego.

	Este servicio CERRA ESA BRECHA: lee el perfil del jugador, calcula
	las estadísticas de bomba con `SkillRules`, las cachea y las expone
	tanto como atributos replicados (para la UI) como como API interna
	(para BombService y ExplosionService).

	NO ES EL PROPIETARIO DE LOS DATOS: el único dueño del perfil es
	ProfileService. SkillService LO LEE y CACHEA; si el perfil cambia
	(chest abierto, login), debe pedirse un refresh.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local LIBRARIES = SHARED:WaitForChild("Libraries")
local CONFIG = SHARED:WaitForChild("Config")

local GameConfig = require(CONFIG:WaitForChild("GameConfig"))
local SkillCatalog = require(CONFIG:WaitForChild("SkillCatalog"))
local SkillRules = require(LIBRARIES:WaitForChild("SkillRules"))
local Logger = require(ReplicatedStorage:WaitForChild("Utils"):WaitForChild("Logger"))

local Service = {}

Service.IsInitialized = false

-- Servicios inyectados.
Service._profileService = nil
Service._maid = nil

-- UserId -> { capacity, radiusMult, damageMult, flavor }
Service._cache = {}

-- ---------------------------------------------------------------------------
-- API INTERNA
-- ---------------------------------------------------------------------------

--- Extrae la lista de IDs de habilidades desbloqueadas del perfil.
--- @param profile any
--- @return { string }
local function extractUnlockedIds(profile: any): { string }
	local ids = {}

	if type(profile) ~= "table" then
		return ids
	end

	local skills = profile.Skills
	if type(skills) ~= "table" then
		return ids
	end

	local unlocked = skills.Unlocked
	if type(unlocked) ~= "table" then
		return ids
	end

	for id in pairs(unlocked) do
		if type(id) == "string" then
			table.insert(ids, id)
		end
	end

	return ids
end

--- Calcula y cachea las estadísticas de bomba de un jugador.
---
--- Se llama en login y tras abrir un cofre. Si no hay perfil aún, no hace
--- nada (el jugador recibirá el refresh cuando el perfil cargue).
--- @param player Player
function Service.RefreshPlayer(player: Player)
	if not Service._profileService or not Service._profileService.HasProfile(player) then
		return
	end

	local profile = Service._profileService.GetProfile(player)
	local ids = extractUnlockedIds(profile)
	local stats = SkillRules.ComputeBombStats(ids, SkillCatalog)

	Service._cache[player.UserId] = stats

	-- Atributos replicados: la UI lee estos valores. El servidor sigue siendo
	-- la autoridad (BombService consulta `GetBombStats`), pero publicar
	-- atributos evita un remoto extra para la UI.
	player:SetAttribute("BombSkillCapacity", stats.capacity)
	player:SetAttribute("BombSkillRadiusMult", stats.radiusMult)
	player:SetAttribute("BombSkillDamageMult", stats.damageMult)
	player:SetAttribute("BombSkillFlavor", stats.flavor)
	player:SetAttribute("BombCapacity", GameConfig.BombCapacity + stats.capacity)

	Logger.Debug(("[SKILL] %s bomba: capacidad+%d radio%+.0f%% daño%+.0f%% flavor=%s"):format(
		player.Name,
		stats.capacity,
		stats.radiusMult * 100,
		stats.damageMult * 100,
		stats.flavor
	))
end

--- Devuelve las estadísticas de bomba cacheadas de un jugador.
---
--- Si el jugador no está en caché (ej: aún no ha cargado el perfil),
--- devuelve valores neutros. Nunca devuelve nil: los llamantes no deben
--- tener que validar.
--- @param userId number
--- @return { capacity: number, radiusMult: number, damageMult: number, flavor: string }
function Service.GetBombStats(userId: number): {
	capacity: number,
	radiusMult: number,
	damageMult: number,
	flavor: string,
}
	return Service._cache[userId] or {
		capacity = 0,
		radiusMult = 0,
		damageMult = 0,
		flavor = SkillRules.Flavors.Default,
	}
end

--- Devuelve las estadísticas de bomba cacheadas de un jugador.
--- @param player Player
--- @return { capacity: number, radiusMult: number, damageMult: number, flavor: string }
function Service.GetBombStatsForPlayer(player: Player): {
	capacity: number,
	radiusMult: number,
	damageMult: number,
	flavor: string,
}
	if not player then
		return Service.GetBombStats(0)
	end
	return Service.GetBombStats(player.UserId)
end

--- Radio efectivo de explosión para un jugador (base * (1 + mult)).
--- @param userId number
--- @return number
function Service.GetEffectiveBombRadius(userId: number): number
	local stats = Service.GetBombStats(userId)
	return GameConfig.DefaultBombRadius * (1 + stats.radiusMult)
end

--- Multiplicador de daño efectivo (1 + mult).
--- @param userId number
--- @return number
function Service.GetEffectiveDamageMult(userId: number): number
	local stats = Service.GetBombStats(userId)
	return 1 + stats.damageMult
end

--- Sabor visual efectivo para un jugador.
--- @param userId number
--- @return string
function Service.GetEffectiveFlavor(userId: number): string
	return Service.GetBombStats(userId).flavor
end

-- ---------------------------------------------------------------------------
-- INYECCIÓN DE DEPENDENCIAS
-- ---------------------------------------------------------------------------

--- Inyecta ProfileService para leer habilidades desbloqueadas.
--- @param profileService any
function Service.SetDependencies(profileService: any)
	Service._profileService = profileService
end

-- ---------------------------------------------------------------------------
-- CICLO DE VIDA
-- ---------------------------------------------------------------------------

--- @param maid any?
--- @return boolean success
function Service.Init(maid: any?): boolean
	if Service.IsInitialized then
		return true
	end

	Service._cache = {}
	Service._maid = maid

	Service.IsInitialized = true
	Logger.Info("SkillService listo.")

	return true
end

--- @return boolean success
function Service.Start(): boolean
	if not Service.IsInitialized then
		Logger.Error("SkillService: Start sin Init")
		return false
	end

	if not Service._profileService then
		Logger.Warn("SkillService: sin ProfileService; las habilidades no se aplicarán.")
	end

	-- OnLogin: refresh cuando el perfil se cargue.
	if Service._maid then
		Service._maid:Connect(Players.PlayerAdded, function(player: Player)
			-- El perfil se carga asíncronamente; retrasamos el refresh para
			-- darle tiempo a ProfileService a registrarlo.
			task.delay(1, function()
				if Service._profileService and Service._profileService.HasProfile(player) then
					Service.RefreshPlayer(player)
				end
			end)
		end)

		-- OnLogout: limpia la caché para evitar que crezca indefinidamente.
		Service._maid:Connect(Players.PlayerRemoving, function(player: Player)
			Service._cache[player.UserId] = nil
		end)
	end

	Logger.Info("SkillService listo.")
	return true
end

--- @return boolean success
function Service.Destroy(): boolean
	Service._cache = {}
	Service._profileService = nil
	Service._maid = nil
	Service.IsInitialized = false

	return true
end

return Service
