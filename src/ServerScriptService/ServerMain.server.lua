--!strict
--[[
	ServerMain
	Punto de entrada del servidor de KeshusyTomy-LanD.

	Responsabilidad (FASE 1 - Foundation):
	- Verificar que los modulos base existan.
	- Construir el ServiceRegistry y registrar los servicios con
	  sus dependencias declaradas.
	- Arrancar en orden topologico y apagar de forma ordenada.

	Flujo:
		ServerMain
		  -> ServiceRegistry
		    -> Services

	No debe crecer hasta convertirse en un archivo gigante:
	la logica de cada dominio vive en Services / Systems.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONFIG = SHARED:WaitForChild("Config")
local UTILS = SHARED:WaitForChild("Utils")
local SERVER = script.Parent

-- Modulos indispensables para que el servidor pueda operar.
local REQUIRED_MODULES = {
	{ name = "GameConfig", instance = CONFIG:WaitForChild("GameConfig") },
	{ name = "GameConstants", instance = SHARED:WaitForChild("Constants"):WaitForChild("GameConstants") },
	{ name = "Logger", instance = UTILS:WaitForChild("Logger") },
}

local Logger = require(UTILS:WaitForChild("Logger"))
local GameConstants = require(SHARED:WaitForChild("Constants"):WaitForChild("GameConstants"))
local ServiceRegistry = require(SERVER:WaitForChild("Systems"):WaitForChild("ServiceRegistry"))
local RemoteGateway = require(SERVER:WaitForChild("Systems"):WaitForChild("RemoteGateway"))

local ServerMain = {}

-- Registro de servicios. Cada entrada declara sus dependencias para
-- que el orden de arranque sea determinista.
local SERVICES = {
	{ name = "WorldService", module = SERVER.Services.WorldService, dependencies = {} },
	{ name = "SpawnService", module = SERVER.Services.SpawnService, dependencies = { "WorldService" } },
	{ name = "RoundService", module = SERVER.Services.RoundService, dependencies = { "WorldService" } },
	{ name = "PlayerService", module = SERVER.Services.PlayerService, dependencies = { "RoundService" } },
}

-- Canales remotos que el gateway valida desde la FASE 1.
--
-- Aqui NO se declaran handlers: las acciones de negocio (poner bomba,
-- comprar, entrar a portal) llegan en las fases 4, 18, 20 y 32.
-- Un canal sin handler sigue siendo VALIDADO y LIMITADO, y el gateway
-- descarta la peticion en lugar de ejecutarla. Es preferible a
-- declarar funciones vacias que aparenten funcionar.
--
-- Formato: canal -> {} (handlers pendientes de su fase).
local REMOTE_CHANNELS = {
	[GameConstants.RemoteAction.Player] = {},
	[GameConstants.RemoteAction.Bomb] = {},
	[GameConstants.RemoteAction.Shop] = {},
	[GameConstants.RemoteAction.Inventory] = {},
	[GameConstants.RemoteAction.Quest] = {},
	[GameConstants.RemoteAction.Portal] = {},
	[GameConstants.RemoteAction.Party] = {},
	[GameConstants.RemoteAction.Settings] = {},
}

--- Comprueba que los modulos base esten presentes y sean validos.
--- @return boolean ok
--- @return string[] missing
function ServerMain.VerifyRequiredModules(): (boolean, { string })
	local missing: { string } = {}

	for _, entry in ipairs(REQUIRED_MODULES) do
		if not entry.instance then
			table.insert(missing, entry.name)
		end
	end

	if #missing > 0 then
		Logger.Warn("Missing required modules: " .. table.concat(missing, ", "))
		return false, missing
	end

	return true, missing
end

--- Punto de inicializacion del servidor.
--- @return boolean success
function ServerMain.Initialize(): boolean
	local ok, err = pcall(function()
		local verified, missing = ServerMain.VerifyRequiredModules()
		if not verified then
			error("Server initialization aborted. Missing: " .. table.concat(missing, ", "))
		end
	end)

	if not ok then
		Logger.Warn("Initialization error: " .. tostring(err))
		return false
	end

	Logger.Info(("%s v%s | server starting..."):format(
		Logger.GetGameName(),
		Logger.GetGameVersion()
	))

	-- Un unico registro por servidor. Lo consultan los servicios.
	local registry = ServiceRegistry.new()
	ServerMain.Registry = registry

	for _, entry in ipairs(SERVICES) do
		local registered, registerError = registry:Register(entry.name, entry.module, entry.dependencies)
		if not registered then
			Logger.Error(("no se pudo registrar '%s': %s"):format(entry.name, tostring(registerError)))
		end
	end

	return true
end

--- Arranca todos los servicios registrados y el gateway de remotos.
--- @return boolean success
function ServerMain.Start(): boolean
	if not ServerMain.Initialize() then
		return false
	end

	local started = ServerMain.Registry:Start()

	-- Gateway de remotos: valida y limita TODO lo que llega del cliente.
	-- Se arranca despues de los servicios para que sus handlers ya
	-- puedan consultar el registro.
	local gateway = RemoteGateway.new()
	local registeredChannels = gateway:RegisterDefaults(REMOTE_CHANNELS)
	gateway:Start()
	ServerMain.Gateway = gateway

	Logger.Info(("RemoteGateway: %d canales validados (%s)"):format(
		#registeredChannels,
		table.concat(registeredChannels, ", ")
	))

	Logger.Info("Foundation initialized.")

	return started
end

--- Apaga el servidor de forma ordenada (regla de shutdown).
function ServerMain.Shutdown()
	if ServerMain.Gateway then
		ServerMain.Gateway:Stop()
		ServerMain.Gateway = nil
	end

	if ServerMain.Registry then
		ServerMain.Registry:Stop()
	end
end

ServerMain.Registry = nil
ServerMain.Gateway = nil

ServerMain.Start()

-- Regla de shutdown: el servidor deja de aceptar trabajo, detiene
-- los servicios en orden inverso y limpia conexiones. El bloqueo se
-- limita a un margen corto para no retener el cierre de Roblox.
game:BindToClose(function()
	local startTime = os.clock()

	ServerMain.Shutdown()

	Logger.Debug(("cierre ordenado completado en %.2fs"):format(os.clock() - startTime))
end)

return ServerMain
