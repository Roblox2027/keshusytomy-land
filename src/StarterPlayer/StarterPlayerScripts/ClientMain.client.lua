--!strict
--[[
	ClientMain
	Punto de entrada del cliente de KeshusyTomy-LanD.

	Responsabilidad (FASE 1 - Foundation):
	- Construir el ControllerRegistry.
	- Registrar y arrancar los controllers que existen en la carpeta.
	- Detenerlos de forma ordenada al salir.

	Flujo:
		ClientMain
		  -> ControllerRegistry
		    -> Controllers

	No debe crecer hasta contener UI ni logica de gameplay:
	esa responsabilidad pertenece a los Controllers.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local UTILS = SHARED:WaitForChild("Utils")

local Logger = require(UTILS:WaitForChild("Logger"))
local ControllerRegistry = require(
	StarterPlayer:WaitForChild("Controllers"):WaitForChild("ControllerRegistry")
)

local ClientMain = {}

--- Registro de controllers del cliente.
ClientMain.Registry = nil

--- Carga un controller de forma explicita y lo registra.
---
--- La FASE 1 usa RegisterAll, pero este metodo sigue siendo util
--- para registrar un controller puntual.
--- @param controllerName string
--- @return boolean loaded
function ClientMain.LoadController(controllerName: string): boolean
	if not ClientMain.Registry then
		return false
	end

	local script = StarterPlayer:WaitForChild("Controllers"):FindFirstChild(controllerName)
	if not script then
		Logger.Debug(("Controller not found: %s"):format(controllerName))
		return false
	end

	local ok, controller = pcall(require, script)
	if not ok then
		Logger.Error(("Failed to load controller %s: %s"):format(controllerName, tostring(controller)))
		return false
	end

	local registered = ClientMain.Registry:Register(controllerName, controller)
	return registered
end

--- Registra y arranca todos los controllers disponibles.
--- @return boolean success
function ClientMain.Start(): boolean
	Logger.Info("Client starting...")

	local registry = ControllerRegistry.new()
	ClientMain.Registry = registry

	local registered = registry:RegisterAll()
	if #registered == 0 then
		-- Sin controllers no hay fallo: la FASE 1 aun no tiene
		-- logica de cliente, las siguientes la anaden.
		Logger.Info("ClientMain: no hay controllers todavia.")
		return true
	end

	local started = registry:StartAll()
	Logger.Info("Foundation initialized.")

	return started
end

--- Detiene todos los controllers de forma ordenada.
function ClientMain.Shutdown()
	if ClientMain.Registry then
		ClientMain.Registry:StopAll()
	end
end

ClientMain.Registry = nil

ClientMain.Start()

return ClientMain
