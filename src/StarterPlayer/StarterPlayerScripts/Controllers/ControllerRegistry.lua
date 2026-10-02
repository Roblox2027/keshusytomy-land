--!strict
--[[
	ControllerRegistry
	Registro y ciclo de vida de los controllers del cliente.

	Es el equivalente cliente de ServiceRegistry, con las mismas
	garantias:
	- Un controller se registra una sola vez.
	- Un controller que falla NO detiene a los demas.
	- Start y Destroy son idempotentes y reversibles.

	Un controller expone:
		Start(maid)   -> comienza a trabajar
		Destroy(maid) -> libera todo
	El Maid se crea por controller: cada uno gestiona su limpieza.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONFIG = SHARED:WaitForChild("Config")
local UTILS = SHARED:WaitForChild("Utils")

local Logger = require(UTILS:WaitForChild("Logger"))
local Maid = require(SHARED:WaitForChild("Libraries"):WaitForChild("Maid"))

local CONTROLLERS_FOLDER = StarterPlayer:WaitForChild("StarterPlayerScripts"):WaitForChild("Controllers")

local ControllerState = {
	Registered = "Registered",
	Started = "Started",
	Failed = "Failed",
	Stopped = "Stopped",
}

export type ControllerEntry = {
	Name: string,
	Module: any,
	State: string,
	Maid: any,
	Error: string?,
}

local Registry = {}
Registry.__index = Registry

Registry.Name = "ControllerRegistry"

Registry._entries = {}
Registry._order = {}
Registry._isRunning = false

--- Crea el registro de controllers.
---
--- BUG CORREGIDO (auditoria de integracion): `new()` devolvia
--- `setmetatable({}, Registry)`, de modo que `self._entries` se resolvia
--- por `__index` hasta la tabla de clase. EsCRIBir en `self._entries`
--- mutaba la tabla COMPARTIDA entre todos los registros. Con un solo
--- registro no se notaba; con dos (o con un test) el estado se
--- contaminaba. Ahora cada registro nace con su propia tabla.
--- @return table
function Registry.new()
	return setmetatable({
		_entries = {},
		_order = {},
		_isRunning = false,
	}, Registry)
end

--- Registra un controller. No lo arranca todavia.
--- @param name string
--- @param module any
--- @param dependencies { string }?
--- @return boolean success
--- @return string? errorMessage
function Registry:Register(name: string, module: any, dependencies: { string }?): (boolean, string?)
	if type(name) ~= "string" or name == "" then
		return false, "nombre de controller invalido"
	end

	if self._entries[name] then
		return false, ("controller ya registrado: %s"):format(name)
	end

	if type(module) ~= "table" then
		return false, ("modulo invalido para '%s'"):format(name)
	end

	self._entries[name] = {
		Name = name,
		Module = module,
		State = ControllerState.Registered,
		Maid = nil,
		Error = nil,
		Dependencies = dependencies or {},
	}

	return true
end

--- Registra automaticamente todos los ModuleScript de Controllers.
--- @return { string } nombres registrados en esta llamada
function Registry:RegisterAll(): { string }
	local registered = {}

	if self._isRunning then
		return registered
	end

	local modules = {}
	for _, entry in ipairs(CONTROLLERS_FOLDER:GetChildren()) do
		if entry:IsA("ModuleScript") then
			table.insert(modules, entry)
		end
	end
	table.sort(modules, function(a, b)
		return a.Name < b.Name
	end)

	for _, moduleScript in modules do
		if not self._entries[moduleScript.Name] then
			local ok, result = pcall(require, moduleScript)
			if not ok then
				Logger.Error(("no se pudo cargar '%s': %s"):format(moduleScript.Name, tostring(result)))
				table.insert(registered, moduleScript.Name .. " (fallo al cargar)")
			else
				local registeredOk, err = self:Register(moduleScript.Name, result)
				if registeredOk then
					table.insert(registered, moduleScript.Name)
				else
					Logger.Warn(("controller '%s' rechazado: %s"):format(moduleScript.Name, tostring(err)))
				end
			end
		end
	end

	return registered
end

--- Indica si un controller esta registrado.
--- @param name string
--- @return boolean
function Registry:IsRegistered(name: string): boolean
	return self._entries[name] ~= nil
end

--- Estado de un controller.
--- @param name string
--- @return string?
function Registry:GetState(name: string): string?
	local entry = self._entries[name]
	return entry and entry.State or nil
end
--- Arranca un controller con proteccion de errores.
--- @param name string
--- @return boolean success
function Registry:_StartController(name: string): boolean
	local entry = self._entries[name]
	if not entry or entry.State ~= ControllerState.Registered then
		return false
	end

	entry.Maid = Maid.new()

	local ok, result = pcall(function()
		if entry.Module.Start then
			return entry.Module.Start(entry.Maid)
		end
		return true
	end)

	if not ok or result == false then
		entry.State = ControllerState.Failed
		entry.Error = tostring(result)
		if entry.Maid then
			pcall(function()
				entry.Maid:Destroy()
			end)
		end
		Logger.Error(("Start de '%s' fallo: %s"):format(name, tostring(result)))
		return false
	end

	entry.State = ControllerState.Started
	return true
end

--- Arranca todos los controllers en orden alfabetico.
--- @return boolean success
function Registry:StartAll(): boolean
	if self._isRunning then
		return true
	end

	local names = {}
	for name in pairs(self._entries) do
		table.insert(names, name)
	end
	table.sort(names)

	local allStarted = true
	for _, name in names do
		if not self:_StartController(name) then
			allStarted = false
		end
	end

	self._order = names
	self._isRunning = true

	Logger.Info(("ControllerRegistry: %d controllers -> %s"):format(#names, table.concat(names, ", ")))
	return allStarted
end

--- Detiene un controller con proteccion de errores.
--- @param name string
function Registry:_StopController(name: string)
	local entry = self._entries[name]
	if not entry then
		return
	end

	if entry.State ~= ControllerState.Started and entry.State ~= ControllerState.Failed then
		return
	end

	pcall(function()
		if entry.Module.Destroy then
			entry.Module.Destroy(entry.Maid)
		end
	end)

	if entry.Maid then
		pcall(function()
			entry.Maid:Destroy()
		end)
	end

	entry.State = ControllerState.Stopped
end

--- Detiene todos los controllers en orden inverso. Idempotente.
function Registry:StopAll()
	if not self._isRunning then
		return
	end

	self._isRunning = false

	local order = self._order
	if #order == 0 then
		for name in pairs(self._entries) do
			table.insert(order, name)
		end
		table.sort(order)
	end

	for index = #order, 1, -1 do
		local name = order[index]
		local ok, err = pcall(function()
			self:_StopController(name)
		end)
		if not ok then
			Logger.Error(("Stop de '%s' fallo: %s"):format(name, tostring(err)))
		end
	end

	Logger.Info("ControllerRegistry: todos los controllers detenidos.")
end

--- Resumen del estado de cada controller.
--- @return { string }
function Registry:GetReport(): { string }
	local names = {}
	for name in pairs(self._entries) do
		table.insert(names, name)
	end
	table.sort(names)

	local report = {}
	for _, name in names do
		local entry = self._entries[name]
		table.insert(report, ("  %-20s %s%s"):format(
			name,
			entry.State,
			entry.Error and (" (" .. entry.Error .. ")") or ""
		))
	end
	return report
end

return Registry