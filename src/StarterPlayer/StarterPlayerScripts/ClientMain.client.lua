--!strict
--[[
	ClientMain
	Punto de entrada del cliente de KeshusyTomy-LanD.

	Responsabilidad actual (FASE 0 - Bootstrap):
	- Confirmar el arranque del cliente.
	- Preparar el registro de Controllers.
	- Mostrar logs solo cuando GameConfig.DebugMode esta activo.

	No debe crecer hasta contener UI ni logica de gameplay:
	esa responsabilidad pertenece a los Controllers.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayerScripts = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(SHARED:WaitForChild("Config"):WaitForChild("GameConfig"))
local Logger = require(SHARED:WaitForChild("Utils"):WaitForChild("Logger"))

local CONTROLLERS_FOLDER = StarterPlayerScripts:WaitForChild("Controllers")

-- Registro de controllers. El nombre es la clave de activacion.
local ClientMain = {}

ClientMain.Controllers = {}

--- Carga un controller de forma segura.
--- @param controllerName string
--- @return boolean loaded
function ClientMain.LoadController(controllerName: string): boolean
	local script = CONTROLLERS_FOLDER:FindFirstChild(controllerName)
	if not script then
		Logger.Debug(("Controller not found yet: %s"):format(controllerName))
		return false
	end

	local ok, controller = pcall(require, script)
	if not ok then
		Logger.Error(("Failed to load controller %s: %s"):format(controllerName, tostring(controller)))
		return false
	end

	ClientMain.Controllers[controllerName] = controller
	return true
end

--- Carga todos los controllers presentes en la carpeta Controllers.
function ClientMain.LoadControllers()
	if not GameConfig.DebugMode then
		return
	end

	for _, entry in ipairs(CONTROLLERS_FOLDER:GetChildren()) do
		if entry:IsA("ModuleScript") then
			ClientMain.LoadController(entry.Name)
		end
	end
end

function ClientMain.Start()
	Logger.Info("Client starting...")
	ClientMain.LoadControllers()
	Logger.Info("Foundation initialized.")
end

ClientMain.Start()

return ClientMain
