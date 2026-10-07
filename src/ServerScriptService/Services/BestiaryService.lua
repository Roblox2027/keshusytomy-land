--!strict
--[[
	BestiaryService
	COLECCION de especies derrotadas (MASTER MISSION V2 - FASE 20).

	QUE HACE Y QUE DELEGA
	---------------------
	NO clasifica nada: la rareza y la contabilidad son de `BestiaryRules`
	(puro, probado). Este servicio aporta el perfil y la publicacion.

	QUIEN LO LLAMA
	--------------
	`MonsterService.OnMonsterDied`, como observador opcional junto al
	loot: con el, matar una especie la registra; sin el, el juego es
	exactamente igual de jugable.

	ALCANCE
	-------
	El registro es por ESPECIE (definicion de monstruo), con contador de
	bajas. La evolucion funcional y los companeros (FASES 21/22) se
	evaluan despues: este servicio no los promete.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local UTILS = SHARED:WaitForChild("Utils")

local BestiaryRules = require(SHARED:WaitForChild("Libraries"):WaitForChild("BestiaryRules"))
local MonsterDefinitions = require(SHARED:WaitForChild("MonsterDefinitions"))
local Logger = require(UTILS:WaitForChild("Logger"))

local Service = {}

Service.IsInitialized = false

-- Servicios inyectados por `ServerMain`.
Service._profileService = nil

-- Diagnostico.
Service._discoveries = 0

-- ---------------------------------------------------------------------------
-- INYECCION
-- ---------------------------------------------------------------------------

--- @param profileService any
function Service.SetDependencies(profileService: any)
	Service._profileService = profileService
end

-- ---------------------------------------------------------------------------
-- OBSERVADOR
-- ---------------------------------------------------------------------------

--- Muerte de un monstruo: registra la especie para el asesino.
--- @param killer any
--- @param record any registro de `MonsterService` (lleva `Def`)
function Service.OnMonsterKilled(killer: any, record: any)
	if not killer or type(record) ~= "table" or type(record.Def) ~= "table" then
		return
	end

	local profiles = Service._profileService

	if not profiles or not profiles.HasProfile or not profiles.HasProfile(killer) then
		return
	end

	local profile = profiles.GetProfile(killer)

	if type(profile) ~= "table" then
		return
	end

	if type(profile.Bestiary) ~= "table" then
		profile.Bestiary = { Species = {} }
	end

	local defId = record.Def.Id
	local isNew, kills = BestiaryRules.RecordKill(profile.Bestiary, defId)

	if kills <= 0 then
		return
	end

	profiles.MarkDirty(killer)

	-- Publicacion: el conteo SIEMPRE (barato, un numero), y el aviso de
	-- descubrimiento solo cuando la especie es NUEVA.
	local total = #MonsterDefinitions.GetIds()
	killer:SetAttribute("BestiaryCount", BestiaryRules.CountDiscovered(profile.Bestiary))
	killer:SetAttribute("BestiaryTotal", total)

	if isNew then
		Service._discoveries += 1

		local rarity = BestiaryRules.RarityOf(record.Def)
		killer:SetAttribute(
			"BestiaryDiscovery",
			("%s (%s)"):format(tostring(record.Def.Name or defId), rarity)
		)

		Logger.Info(("BestiaryService: %s registro '%s' (nuevo)"):format(killer.Name, defId))
	end
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

	Service._discoveries = 0
	Service.IsInitialized = true
	return true
end

--- Arranque. No hay hilos: el servicio responde a muertes.
--- @return boolean success
function Service.Start(): boolean
	if not Service.IsInitialized then
		Logger.Error("BestiaryService: Start sin Init")
		return false
	end

	if not Service._profileService then
		Logger.Error("BestiaryService: falta ProfileService.")
		return false
	end

	Logger.Info("BestiaryService: listo (coleccion por especie, persistente).")
	return true
end

--- Apagado. Idempotente.
--- @return boolean success
function Service.Destroy(): boolean
	Service.IsInitialized = false
	return true
end

return Service
