--!strict
--[[
	SpawnService
	Sistema de aparicion del jugador (FASE 1).

	Responsabilidad en esta fase:
	- Descubrir los SpawnLocation disponibles en el mapa.
	- Elegir un punto de aparicion valido para cada jugador.
	- Evitar que dos jugadores aparezcan en el mismo punto.

	Por que "servidor decide": la posicion de aparicion nunca se
	toma del cliente. Se elige aqui, en el servidor, y el cliente solo
	la recibe.

	Los reapariciones tras muerte, el spawn por mundo y el teletransporte
	corresponden a las fases 2, 19 y 22.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONFIG = SHARED:WaitForChild("Config")
local UTILS = SHARED:WaitForChild("Utils")

local GameConfig = require(CONFIG:WaitForChild("GameConfig"))
local Logger = require(UTILS:WaitForChild("Logger"))

local Service = {}

Service.IsInitialized = false

-- Lista de SpawnLocation validos del mapa.
Service._spawnLocations = {}
-- Contador de rotacion para repartir jugadores entre puntos.
Service._cursor = 0
-- Maid recibido en Init (conexiones de Players).
local MaidRef = nil

--- Busca los SpawnLocation existentes en el Workspace.
--- @return { Instance } spawnLocations
function Service.CollectSpawnLocations(): { Instance }
	local collected = {}

	local workspaceService = game:GetService("Workspace")
	local spawnFolder = workspaceService:FindFirstChild("SpawnLocations")

	if not spawnFolder then
		Logger.Warn("Workspace.SpawnLocations no existe; se usara el origen.")
		return collected
	end

	for _, instance in ipairs(spawnFolder:GetDescendants()) do
		if instance:IsA("SpawnLocation") then
			table.insert(collected, instance)
		end
	end

	return collected
end

--- Cantidad de puntos de aparicion disponibles.
--- @return number
function Service.GetSpawnLocationCount(): number
	return #Service._spawnLocations
end

--- Elige un punto de aparicion. El servidor decide siempre.
--- @param player Player?
--- @return Instance? spawnLocation nil si no hay ninguno
function Service.PickSpawnLocation(player: Player?): Instance?
	local total = #Service._spawnLocations

	if total == 0 then
		Logger.Debug("PickSpawnLocation: no hay SpawnLocation; se usara Vector3.zero")
		return nil
	end

	-- Rotacion determinista: reparte sin aleatoriedad ni carrera.
	Service._cursor = (Service._cursor % total) + 1
	local spawnLocation = Service._spawnLocations[Service._cursor]

	Logger.Debug(("spawn asignado a %s: %s"):format(
		player and player.Name or "?",
		spawnLocation.Name
	))

	return spawnLocation
end

--- Posicion de aparicion calculada para un jugador.
--- @param player Player?
--- @return Vector3
function Service.GetSpawnPosition(player: Player?): Vector3
	local spawnLocation = Service.PickSpawnLocation(player)

	if not spawnLocation then
		return Vector3.new(0, 10, 0)
	end

	-- Se suma un pequeño desplazamiento vertical para que el personaje
	-- no nazca incrustado en el suelo.
	return (spawnLocation :: SpawnLocation).Position + Vector3.new(0, 3, 0)
end

--- Inicializacion del servicio. Idempotente.
--- @param maid any?
--- @return boolean success
function Service.Init(maid: any?): boolean
	if Service.IsInitialized then
		return true
	end

	local ok, err = pcall(function()
		Service._spawnLocations = Service.CollectSpawnLocations()
		Service._cursor = 0
	end)

	if not ok then
		Logger.Error("SpawnService Init fallo: " .. tostring(err))
		return false
	end

	-- Sin ningun SpawnLocation el personaje aparece en el origen y cae al
	-- vacio: es el fallo mas grave posible, asi que NO es un aviso sino
	-- un fallo de inicializacion. El registro lo vera en el output.
	if #Service._spawnLocations == 0 then
		Logger.Error(
			"SpawnService: no hay SpawnLocation en Workspace.SpawnLocations. "
				.. "El personaje caera al vacio. Ejecuta `node tools/generate-project.js` y recompila."
		)
		return false
	end

	Service.IsInitialized = true
	Logger.Info(("SpawnService: %d puntos de aparicion encontrados"):format(
		Service.GetSpawnLocationCount()
	))

	return true
end

--- Reubica a un jugador que ha caido por debajo del mapa.
---
--- Sin esto, caer fuera del mapa es una muerte injusta y el jugador
--- tiene que esperar el respawn. Se teletransporta al ultimo punto de
--- aparicion valido en vez de matarlo.
--- @param player Player
local function rescueFromVoid(player: Player)
	local character = player.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	if rootPart.Position.Y >= GameConfig.VoidKillY then
		return
	end

	local spawnLocation = Service.PickSpawnLocation(player)
	if not spawnLocation then
		return
	end

	local target = (spawnLocation :: SpawnLocation).Position + Vector3.new(0, 4, 0)
	character:PivotTo(CFrame.new(target))

	Logger.Info(("%s habia caido al vacio; devuelto a %s"):format(
		player.Name,
		spawnLocation.Name
	))
end

--- @return boolean success
function Service.Start(): boolean
	if not Service.IsInitialized then
		Logger.Error("SpawnService: Start sin Init")
		return false
	end

	if MaidRef then
		-- Vigilancia de caida al vacio. Se comprueba con un intervalo
		-- corto y no por evento porque el vacio no genera eventos.
		MaidRef:Add(task.spawn(function()
			while Service.IsInitialized do
				task.wait(1)

				for _, player in ipairs(Players:GetPlayers()) do
					local ok, err = pcall(rescueFromVoid, player)
					if not ok then
						Logger.Error(("rescate de %s fallo: %s"):format(player.Name, tostring(err)))
					end
				end
			end
		end))
	end

	Logger.Info("SpawnService listo.")
	return true
end

--- @return boolean success
function Service.Destroy(): boolean
	Service.IsInitialized = false
	Service._spawnLocations = {}
	Service._cursor = 0
	MaidRef = nil
	return true
end

return Service