--!strict
--[[
	WorldService
	Registro de mundos jugables y fundacion de su arena (FASE 1).

	Responsabilidad en esta fase:
	- Cargar las definiciones de WorldDefinitions (solo datos).
	- Respetar FeatureConfig: un mundo deshabilitado NO se registra.
	- Exponer consultas de mundo que usaran las fases siguientes
	  (portales, matchmaking, desbloqueos).
	- Proveer el punto de aparicion por defecto de cada arena.

	La construccion del mapa, bloques, monstruos y boss corresponde a
	las fases 6, 9, 11 y 19. Anadir un mundo nuevo NO obliga a tocar
	este archivo: basta una definicion en WorldDefinitions y su
	bandera en FeatureConfig.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONFIG = SHARED:WaitForChild("Config")
local UTILS = SHARED:WaitForChild("Utils")

local FeatureConfig = require(CONFIG:WaitForChild("FeatureConfig"))
local Logger = require(UTILS:WaitForChild("Logger"))

local Service = {}

Service.IsInitialized = false

-- Mundo -> definicion.
Service._worlds = {}
-- Mundo -> punto de aparicion (Vector3). Lo define la FASE 6.
Service._spawnPoints = {}
Service._worldsFolder = nil

-- Bandera de FeatureConfig por mundo.
local WORLD_FLAGS: { [string]: string } = {
	Forest = "ENABLE_FOREST",
	Desert = "ENABLE_DESERT",
	Ice = "ENABLE_ICE",
	Volcano = "ENABLE_VOLCANO",
	Cyber = "ENABLE_CYBER",
}

-- Orden de carga. El primer mundo habilitado es el mundo inicial.
local WORLD_ORDER = { "Forest", "Desert", "Ice", "Volcano", "Cyber" }

--- Indica si el mundo esta habilitado por configuracion.
--- @param worldId string
--- @return boolean
function Service.IsWorldEnabled(worldId: string): boolean
	local flag = WORLD_FLAGS[worldId]
	if not flag then
		return false
	end
	return FeatureConfig[flag] == true
end

--- Definicion de un mundo, o nil si no esta registrado.
--- @param worldId string
--- @return any?
function Service.GetWorld(worldId: string): any?
	return Service._worlds[worldId]
end

--- Mundos registrados, en orden de carga.
--- @return { string }
function Service.GetWorldIds(): { string }
	local ids = {}
	for _, worldId in ipairs(WORLD_ORDER) do
		if Service._worlds[worldId] then
			table.insert(ids, worldId)
		end
	end
	return ids
end

--- El primer mundo habilitado. Es el destino inicial del lobby.
--- @return string?
function Service.GetDefaultWorldId(): string?
	return Service.GetWorldIds()[1]
end

--- Indica si un mundo existe y esta habilitado.
--- @param worldId string
--- @return boolean
function Service.IsWorldAvailable(worldId: string): boolean
	return Service._worlds[worldId] ~= nil
end

--- Requisito de nivel de un mundo.
--- @param worldId string
--- @return number requiredLevel 0 si el mundo no existe
function Service.GetRequiredLevel(worldId: string): number
	local world = Service._worlds[worldId]
	if not world then
		return 0
	end
	return world.RequiredLevel or 0
end

--- Indica si un jugador cumple el nivel requerido por un mundo.
--- @param worldId string
--- @param playerLevel number
--- @return boolean allowed
--- @return string? reason
function Service.CanEnterWorld(worldId: string, playerLevel: number): (boolean, string?)
	if not Service.IsWorldAvailable(worldId) then
		return false, "mundo no disponible"
	end

	local required = Service.GetRequiredLevel(worldId)
	if playerLevel < required then
		return false, ("requiere nivel %d"):format(required)
	end

	return true
end
--- Punto de aparicion por defecto de un mundo.
--- La FASE 6 lo sustituye por los puntos reales del mapa.
--- @param worldId string
--- @return Vector3?
function Service.GetSpawnPoint(worldId: string): Vector3?
	return Service._spawnPoints[worldId]
end

--- Define el punto de aparicion de un mundo.
--- @param worldId string
--- @param position Vector3
function Service.SetSpawnPoint(worldId: string, position: Vector3)
	Service._spawnPoints[worldId] = position
end

--- Carga las definiciones de mundo habilitadas.
--- @return { string } ids registrados
function Service.LoadWorlds(): { string }
	local definitions = ReplicatedStorage:WaitForChild("WorldDefinitions")
	local registered = {}

	for _, worldId in ipairs(WORLD_ORDER) do
		if Service.IsWorldEnabled(worldId) then
			local definition = definitions:FindFirstChild(worldId)

			if definition and definition:IsA("ModuleScript") then
				local ok, world = pcall(require, definition)
				if ok then
					Service._worlds[worldId] = world
					table.insert(registered, worldId)
				else
					Logger.Error(("definicion de mundo '%s' fallo: %s"):format(worldId, tostring(world)))
				end
			else
				Logger.Warn(("definicion de mundo '%s' no encontrada"):format(worldId))
			end
		else
			Logger.Debug(("mundo '%s' deshabilitado por FeatureConfig"):format(worldId))
		end
	end

	return registered
end

--- Inicializacion del servicio. Idempotente.
--- @param maid any?
--- @return boolean success
function Service.Init(maid: any?): boolean
	if Service.IsInitialized then
		return true
	end

	local ok, err = pcall(function()
		-- Origen de las arenas. Si no existe, se avisa y se continua:
		-- la ausencia de un mapa no debe impedir jugar.
		local worldsFolder = game:GetService("Workspace"):FindFirstChild("Worlds")

		if not worldsFolder then
			Logger.Warn("Workspace.Worlds no existe; las arenas no estan disponibles.")
		else
			Service._worldsFolder = worldsFolder
		end

		local registered = Service.LoadWorlds()
		Logger.Info(("WorldService: %d mundos registrados (%s)"):format(
			#registered,
			table.concat(registered, ", ")
		))
	end)

	if not ok then
		Logger.Error("WorldService Init fallo: " .. tostring(err))
		return false
	end

	Service.IsInitialized = true
	return true
end

--- Comienza a servir consultas de mundo.
--- @return boolean success
function Service.Start(): boolean
	if not Service.IsInitialized then
		Logger.Error("WorldService: Start sin Init")
		return false
	end

	Logger.Debug(("WorldService listo. Mundo por defecto: %s"):format(
		tostring(Service.GetDefaultWorldId())
	))

	return true
end

--- Limpieza del servicio.
--- @return boolean success
function Service.Destroy(): boolean
	Service.IsInitialized = false
	Service._worlds = {}
	Service._spawnPoints = {}
	Service._worldsFolder = nil
	return true
end

return Service
