--!strict
--[[
	ServerMain
	Punto de entrada del servidor de KeshusyTomy-LanD.

	Responsabilidad actual (FASE 0 - Bootstrap):
	- Confirmar el arranque del servidor.
	- Verificar que los modulos base requeridos existan.
	- Dejar un punto de inicializacion para las fases siguientes.

	No debe crecer hasta convertirse en un archivo gigante:
	la logica de cada dominio vive en Services / Systems.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONFIG = SHARED:WaitForChild("Config")
local UTILS = SHARED:WaitForChild("Utils")

-- Modulos indispensables para que el servidor pueda operar.
local REQUIRED_MODULES = {
	{ name = "GameConfig", instance = CONFIG:WaitForChild("GameConfig") },
	{ name = "GameConstants", instance = SHARED:WaitForChild("Constants"):WaitForChild("GameConstants") },
	{ name = "Logger", instance = UTILS:WaitForChild("Logger") },
}

local ServerMain = {}

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
		warn("[KeshusyTomy-LanD] Missing required modules: " .. table.concat(missing, ", "))
		return false, missing
	end

	return true, missing
end

local Logger = require(UTILS:WaitForChild("Logger"))

--- Punto de inicializacion del servidor.
--- Las fases siguientes registraran aqui sus servicios.
function ServerMain.Initialize()
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
	Logger.Info("Foundation initialized.")

	return true
end

function ServerMain.Start()
	if not ServerMain.Initialize() then
		return false
	end

	-- FASE 1+ : ServerMain registrara aqui Services / Systems.
	return true
end

ServerMain.Start()

return ServerMain
