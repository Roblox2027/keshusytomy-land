--!strict
--[[
	ServiceRegistry
	Ciclo de vida y registro de los servicios del servidor.

	Por que existe (FASE 1):
	- Orden de arranque determinista: cada servicio declara sus
	  dependencias y el registro las resuelve (orden topologico).
	- Fallo aislado: un servicio que falla NO tumba el servidor ni
	  impide arrancar a los servicios independientes.
	- Apagado ordenado y siempre completo, incluso con errores.

	Ciclo de vida de cada servicio:
	  Init    -> prepara estado y conexiones. Idempotente.
	  Start   -> comienza a trabajar. Solo tras el Init de sus deps.
	  Destroy -> revierte Start y luego Init. Siempre en orden inverso.

	Regla: un servicio no require directamente a otro servicio para
	obtenerlo; lo pide al registro (`registry:Get("RoundService")`).
	Esto evita dependencias circulares y servicios duplicados.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONFIG = SHARED:WaitForChild("Config")
local UTILS = SHARED:WaitForChild("Utils")

local PerformanceConfig = require(CONFIG:WaitForChild("PerformanceConfig"))
local GameConstants = require(SHARED:WaitForChild("Constants"):WaitForChild("GameConstants"))
local Logger = require(UTILS:WaitForChild("Logger"))
local Maid = require(SHARED:WaitForChild("Libraries"):WaitForChild("Maid"))

local ServiceState = GameConstants.ServiceState
local ServerState = GameConstants.ServerState

export type Service = {
	Init: ((any) -> boolean)?,
	Start: ((any) -> boolean)?,
	Destroy: ((any) -> boolean)?,
}

export type ServiceEntry = {
	Name: string,
	Module: any,
	Dependencies: { string },
	State: string,
	Instance: any,
	Maid: any,
	Error: string?,
	StartedAt: number?,
}

local Registry = {}
Registry.__index = Registry

Registry.Name = "ServiceRegistry"

Registry._entries = {}
Registry._order = {}
Registry._state = ServerState.Starting
Registry._masterMaid = nil

--- Crea el registro. Debe existir uno solo por servidor.
---
--- BUG CORREGIDO (auditoria de integracion): antes los campos de estado
--- vivian SOLO en la tabla de clase (`Registry._entries`) y `new()`
--- devolvia `setmetatable({}, Registry)`. Como `self._entries` se
--- resolvia por `__index` hasta la clase, ESCRIBIR en `self._entries`
--- mutaba la tabla COMPARTIDA: dos registros distintos (o un test que
--- creara uno nuevo) contaminaban el estado del anterior. Ahora cada
--- registro nace con su PROPIA tabla de estado.
--- @return table
function Registry.new()
	return setmetatable({
		_entries = {},
		_order = {},
		_state = ServerState.Starting,
		_masterMaid = nil,
		_didInitAll = false,
	}, Registry)
end

--- Registra un servicio. No lo inicializa todavia.
--- @param name string
--- @param module any debe exponer Init/Start/Destroy
--- @param dependencies { string }? nombres de servicios requeridos
--- @return boolean success
--- @return string? errorMessage
function Registry:Register(name: string, module: any, dependencies: { string }?): (boolean, string?)
	if self._state ~= ServerState.Starting and self._state ~= ServerState.Running then
		return false, ("no se puede registrar '%s' en estado %s"):format(name, self._state)
	end

	if type(name) ~= "string" or name == "" then
		return false, "nombre de servicio invalido"
	end

	if self._entries[name] then
		return false, ("servicio ya registrado: %s"):format(name)
	end

	if type(module) ~= "table" then
		return false, ("modulo invalido para '%s'"):format(name)
	end

	self._entries[name] = {
		Name = name,
		Module = module,
		Dependencies = dependencies or {},
		State = ServiceState.Registered,
		Instance = nil,
		Maid = nil,
		Error = nil,
		StartedAt = nil,
	}

	return true
end

--- Indica si un servicio esta registrado.
--- @param name string
--- @return boolean
function Registry:IsRegistered(name: string): boolean
	return self._entries[name] ~= nil
end

--- Estado actual de un servicio.
--- @param name string
--- @return string?
function Registry:GetState(name: string): string?
	local entry = self._entries[name]
	return entry and entry.State or nil
end

--- Devuelve la instancia de un servicio.
---
--- BUG CORREGIDO (auditoria de integracion): antes solo devolvia la
--- instancia si el servicio habia llegado a `Started`, y ademas la
--- asignaba DENTRO de la fase de Start. Eso obligaba a que
--- `ServerMain` conectara las dependencias DESPUES de arrancar, cuando
--- ya era demasiado tarde: `MatchService.Start` se ejecutaba sin
--- `RoundService` inyectado y por eso NUNCA se suscribia a los cambios
--- de ronda. En el juego no se teletransportaba a nadie a la arena y
--- ningun sistema reaccionaba: "no funciona nada".
---
--- Ahora `Instance` se rellena en cuanto el servicio supera su `Init`,
--- de modo que las dependencias se pueden conectar ENTRE Init y Start,
--- que es el unico momento en el que tienen sentido.
--- @param name string
--- @return any? instance
function Registry:Get(name: string): any?
	local entry = self._entries[name]
	if not entry then
		Logger.Warn(("Get('%s'): servicio no registrado"):format(name))
		return nil
	end
	return entry.Instance
end

--- Devuelve la instancia de un servicio en cualquier estado en el que
--- tenga una. Util para diagnostico: distingue "no registrado" de
--- "registrado pero fallo su Init".
--- @param name string
--- @return any? instance
--- @return string? state
function Registry:GetEntry(name: string): (any?, string?)
	local entry = self._entries[name]
	if not entry then
		return nil, nil
	end
	return entry.Instance, entry.State
end

--- Maid propio de un servicio: todo lo que registre se limpia solo.
--- @param name string
--- @return any?
function Registry:GetMaid(name: string): any?
	local entry = self._entries[name]
	return entry and entry.Maid or nil
end
--- Ordena los servicios respetando dependencias.
--- @return { string } order
--- @return { string } failed servicios excluidos por ciclo o dependencia ausente
function Registry:_ResolveOrder(): ({ string }, { string })
	local order: { string } = {}
	local failed: { string } = {}

	local temporary: { [string]: boolean } = {}
	local permanent: { [string]: boolean } = {}

	local names = {}
	for name in pairs(self._entries) do
		table.insert(names, name)
	end
	table.sort(names)

	-- Orden topologico iterativo (Tarjan): evita recursion profunda.
	local function visit(name: string): boolean
		if permanent[name] then
			return true
		end

		if temporary[name] then
			Logger.Error(("ciclo de dependencias de servicios en '%s'"):format(name))
			return false
		end

		local entry = self._entries[name]
		if not entry then
			return false
		end

		temporary[name] = true

		local dependencies = table.clone(entry.Dependencies)
		table.sort(dependencies)

		for _, dependency in dependencies do
			if not self._entries[dependency] then
				Logger.Error(("servicio '%s' requiere '%s', que no esta registrado"):format(name, dependency))
				failed[#failed + 1] = name
				temporary[name] = nil
				return false
			end

			if not visit(dependency) then
				failed[#failed + 1] = name
				temporary[name] = nil
				return false
			end
		end

		temporary[name] = nil
		permanent[name] = true
		table.insert(order, name)
		return true
	end

	for _, name in names do
		visit(name)
	end

	return order, failed
end

--- Inicializa un servicio con proteccion de errores.
--- @param name string
--- @return boolean success
function Registry:_InitService(name: string): boolean
	local entry = self._entries[name]
	if not entry then
		return false
	end

	entry.Maid = Maid.new()
	-- El estado NO se marca `Initialized` todavia: se hace solo si el
	-- `Init` devuelve true. Marcarlo antes hacia que un `Init` que
	-- lanzaba una excepcion dejara al servicio marcado como bueno, y
	-- la fase de Start lo ejecutaba igualmente sin estar preparado.
	entry.State = ServiceState.Registered

	local startTime = os.clock()
	local ok, result = pcall(function()
		if entry.Module.Init then
			return entry.Module.Init(entry.Maid)
		end
		return true
	end)
	local elapsed = os.clock() - startTime

	if not ok then
		entry.State = ServiceState.Failed
		entry.Error = tostring(result)
		Logger.Error(("Init de '%s' fallo: %s"):format(name, tostring(result)))
		return false
	end

	if result == false then
		entry.State = ServiceState.Failed
		entry.Error = "Init devolvio false"
		Logger.Error(("Init de '%s' devolvio false"):format(name))
		return false
	end

	-- El servicio ya es utilizable: se publica la instancia para que
	-- `ServerMain` pueda inyectar las dependencias ENTRE Init y Start,
	-- que es el unico momento en el que el cableado significa algo.
	entry.Instance = entry.Module
	entry.State = ServiceState.Initialized

	-- Antes leia `GameConfig.Performance.WarnThreshold`, pero Performance
	-- vive en su propio modulo (GameConfig no lo expone). Ese acceso
	-- devolvia nil y rompia aqui el arranque de TODO el registro.
	local serviceInitThreshold = PerformanceConfig.WarnThreshold.ServiceInit

	if elapsed > serviceInitThreshold then
		Logger.Warn(("Init de '%s' tardo %.3fs (umbral %.3fs)"):format(
			name,
			elapsed,
			serviceInitThreshold
		))
	end

	return true
end

--- Arranca un servicio con proteccion de errores.
--- @param name string
--- @return boolean success
function Registry:_StartService(name: string): boolean
	local entry = self._entries[name]
	if not entry then
		return false
	end

	if entry.State ~= ServiceState.Initialized then
		return false
	end

	local ok, result = pcall(function()
		if entry.Module.Start then
			return entry.Module.Start(entry.Maid)
		end
		return true
	end)

	if not ok then
		entry.State = ServiceState.Failed
		entry.Error = tostring(result)
		Logger.Error(("Start de '%s' fallo: %s"):format(name, tostring(result)))
		return false
	end

	if result == false then
		entry.State = ServiceState.Failed
		entry.Error = "Start devolvio false"
		Logger.Error(("Start de '%s' devolvio false"):format(name))
		return false
	end

	entry.State = ServiceState.Started
	entry.StartedAt = os.clock()
	return true
end
--- Fase 1 del arranque: inicializa TODOS los servicios y resuelve el
--- orden topologico. No arranca ninguno.
---
--- Existe separada de `StartAll` porque las dependencias se inyectan
--- ENTRE las dos fases. `MatchService.Start` necesita `RoundService` ya
--- en la mano para suscribirse a los cambios de ronda; si el registro
--- hiciera Init y Start en un solo paso, la suscripcion se perderia.
--- @return boolean success false si algun servicio fallo
--- @return { string } failed nombres de los que no superaron su Init
function Registry:InitAll(): (boolean, { string })
	if self._state ~= ServerState.Starting then
		Logger.Warn(("InitAll ignorado: estado actual %s"):format(self._state))
		return false, {}
	end

	self._masterMaid = Maid.new()
	local order, failed = self:_ResolveOrder()

	for _, name in failed do
		local entry = self._entries[name]
		if entry then
			entry.State = ServiceState.Failed
			entry.Error = "dependencias invalidas"
		end
	end

	local allInitialized = true

	for _, name in order do
		local entry = self._entries[name]
		if entry and entry.State ~= ServiceState.Failed then
			if not self:_InitService(name) then
				allInitialized = false
			end
		elseif entry then
			allInitialized = false
		end
	end

	self._order = order
	self._didInitAll = true

	Logger.Info(("ServiceRegistry: %d servicios inicializados (%s)"):format(
		#order,
		table.concat(order, " > ")
	))

	if not allInitialized then
		for _, line in ipairs(self:GetReport()) do
			Logger.Warn(("[Init] %s"):format(line))
		end
	end

	return allInitialized, failed
end

--- Fase 2 del arranque: arranca los servicios ya inicializados.
--- @return boolean success false si algun servicio fallo
function Registry:StartAll(): boolean
	if self._state ~= ServerState.Starting then
		Logger.Warn(("StartAll ignorado: estado actual %s"):format(self._state))
		return false
	end

	if not self._didInitAll then
		Logger.Error("StartAll sin InitAll: se ejecuta InitAll automaticamente.")
		self:InitAll()
	end

	local allStarted = true

	for _, name in self._order do
		local entry = self._entries[name]
		if not entry then
			continue
		end

		if entry.State == ServiceState.Initialized then
			if not self:_StartService(name) then
				allStarted = false
			end
		elseif entry.State == ServiceState.Failed then
			allStarted = false
		end
	end

	self._state = ServerState.Running

	Logger.Info(("ServiceRegistry: %d servicios arrancados (%s)"):format(
		#self._order,
		table.concat(self._order, " > ")
	))

	if not allStarted then
		Logger.Error(
			"ServiceRegistry: HAY SERVICIOS EN FALLO; el servidor opera en modo "
			.. "degradado. El informe completo esta en ServerMain.GetBootReport()."
		)
		for _, line in ipairs(self:GetReport()) do
			Logger.Warn(("[Start] %s"):format(line))
		end
	end

	return allStarted
end

--- Arranque completo en un solo paso (Init + Start).
---
--- Se mantiene por compatibilidad, pero `ServerMain` usa `InitAll`,
--- cablea las dependencias y luego llama a `StartAll`: sin ese hueco,
--- ningun servicio puede depender de otro al arrancar.
--- @return boolean success false si algun servicio fallo
function Registry:Start(): boolean
	local initialized = self:InitAll()
	local started = self:StartAll()
	return initialized and started
end

--- Estado global del servidor.
--- @return string
function Registry:GetServerState(): string
	return self._state
end

--- Indica si el servidor acepta trabajo nuevo.
--- @return boolean
function Registry:IsAcceptingWork(): boolean
	return self._state == ServerState.Running
end

--- Detiene un servicio, con proteccion de errores.
--- @param name string
function Registry:_StopService(name: string)
	local entry = self._entries[name]
	if not entry then
		return
	end

	if entry.State ~= ServiceState.Started
		and entry.State ~= ServiceState.Initialized
		and entry.State ~= ServiceState.Failed then
		return
	end

	entry.State = ServiceState.Stopping

	pcall(function()
		if entry.Module.Destroy then
			entry.Module.Destroy(entry.Maid)
		end
	end)

	-- El Maid limpia conexiones aunque Destroy falle o no exista.
	if entry.Maid then
		pcall(function()
			entry.Maid:Destroy()
		end)
	end

	entry.State = ServiceState.Stopped
	entry.Instance = nil
end

--- Apaga todos los servicios. Idempotente y no se bloquea.
--- @return boolean success
function Registry:Stop(): boolean
	if self._state == ServerState.Stopped or self._state == ServerState.ShuttingDown then
		return true
	end

	self._state = ServerState.ShuttingDown

	local order = self._order

	if #order == 0 then
		for name in pairs(self._entries) do
			table.insert(order, name)
		end
		table.sort(order)
	end

	-- Orden inverso: quien dependia de otro se apaga primero.
	for index = #order, 1, -1 do
		local name = order[index]
		local ok, err = pcall(function()
			self:_StopService(name)
		end)
		if not ok then
			Logger.Error(("Stop de '%s' fallo: %s"):format(name, tostring(err)))
		end
	end

	if self._masterMaid then
		pcall(function()
			self._masterMaid:Destroy()
		end)
	end

	self._state = ServerState.Stopped
	Logger.Info("ServiceRegistry: todos los servicios detenidos.")
	return true
end

--- Resumen del estado de cada servicio. Util para diagnostico.
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