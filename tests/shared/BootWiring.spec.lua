--!strict
--[[
	BootWiring.spec
	Regresion de los bugs de ARRANQUE que impidieron que el juego
	funcionalara dentro de Roblox Studio.

	Por que esta suite existe (y por que no bastaba la anterior):

	131 pruebas, `luau-compile` y `rojo build` pasaban mientras el juego
	NO hacia nada en Studio. Los motivos:

	1. `ServerMain` llamaba `Registry:Start()`, que hacia Init y Start en
	   un mismo paso, y cableaba las dependencias DESPUES. Como `Get` solo
	   devolvia instancias ya arrancadas, `MatchService.Start` corria sin
	   `RoundService` y devolvia false ANTES de suscribirse a la ronda.
	   Nadie se teletransportaba nunca.

	2. Los registros (`ServiceRegistry`, `ControllerRegistry`) devolvian
	   `setmetatable({}, Class)`, asi que `self._entries` se resolvia por
	   `__index` hasta la tabla de CLASE. Escribir en `self._entries`
	   mutaba una tabla compartida por todos los registros.

	Esta suite comprueba el ORDEN y el CABLEADO con dobles minimos, sin
	necesidad del motor de Roblox.

	Limite honesto: que el motor acepte estos modulos, que el personaje
	aparezca y que una bomba dane de verdad, solo se puede comprobar en
	Roblox Studio. Eso queda BLOCKED, no PASS.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

-- --- Dobles minimos -------------------------------------------------

-- Registro con el MISMO contrato que `ServiceRegistry`, pero sin
-- dependencias del motor. Reproduce la separacion Init / cableado /
-- Start que la auditoria demostro necesaria.
local function makeRegistry()
	local registry = { _entries = {}, _order = {} }

	function registry:Register(name, module, dependencies)
		self._entries[name] = {
			Name = name,
			Module = module,
			Dependencies = dependencies or {},
			State = "Registered",
			Instance = nil,
		}
		self._order[#self._order + 1] = name
		return true
	end

	-- SOLO devuelve la instancia ya inicializada. Es el comportamiento
	-- que se cambio: antes exigia `Started`.
	function registry:Get(name)
		local entry = self._entries[name]
		if not entry then
			return nil
		end
		if entry.State == "Initialized" or entry.State == "Started" then
			return entry.Instance
		end
		return nil
	end

	function registry:InitAll()
		for _, name in ipairs(self._order) do
			local entry = self._entries[name]
			local ok, result = pcall(entry.Module.Init)
			if not ok or result == false then
				entry.State = "Failed"
			else
				entry.State = "Initialized"
				-- BUG CORREGIDO: la instancia se publica en Init, no en
				-- Start. Sin esto el cableado no puede ver al servicio.
				entry.Instance = entry.Module
			end
		end
		return true
	end

	function registry:StartAll()
		for _, name in ipairs(self._order) do
			local entry = self._entries[name]
			if entry.State == "Initialized" then
				entry.Module.Start()
				entry.State = "Started"
			end
		end
		return true
	end

	return registry
end

-- Simula el doble que rompio el juego: MatchService exige RoundService
-- para arrancar, y sin el NO se suscribe a la ronda.
local function makeMatchService(subscribeLog)
	local service = { _roundService = nil, IsInitialized = false }

	function service.Init()
		service.IsInitialized = true
		return true
	end

	function service.SetDependencies(roundService)
		service._roundService = roundService
	end

	function service.Start()
		if not service._roundService then
			-- Caso real: devuelve false y no se suscribe.
			return false
		end
		service._roundService.OnStateChanged(function() end)
		subscribeLog.count += 1
		return true
	end

	return service
end

local function makeRoundService()
	local service = { listeners = {} }

	function service.OnStateChanged(fn)
		table.insert(service.listeners, fn)
		return function()
			for i, listener in ipairs(service.listeners) do
				if listener == fn then
					table.remove(service.listeners, i)
					return
				end
			end
		end
	end

	function service.GetListenerCount()
		return #service.listeners
	end

	function service.Init()
		return true
	end

	function service.Start()
		return true
	end

	return service
end
-- --- Pruebas -------------------------------------------------------

return function()
	Harness.describe("Arranque: Init antes de cablear antes de Start", function()
		Harness.it("Init publica la instancia para que se pueda cablear", function()
			local registry = makeRegistry()
			registry:Register("RoundService", makeRoundService(), {})

			registry:InitAll()

			-- Es el punto central del arreglo: entre Init y Start el
			-- servicio ya es consultable.
			expect.toBeTruthy(registry:Get("RoundService"))
		end)

		Harness.it("MatchService arranca CON RoundService ya inyectado", function()
			local subscribeLog = { count = 0 }
			local registry = makeRegistry()
			local roundService = makeRoundService()
			local matchService = makeMatchService(subscribeLog)

			registry:Register("RoundService", roundService, {})
			registry:Register("MatchService", matchService, { "RoundService" })

			registry:InitAll()

			-- Orden correcto: cablear ENTRE Init y Start.
			matchService.SetDependencies(registry:Get("RoundService"))
			registry:StartAll()

			expect.toBe(subscribeLog.count, 1)
		end)

		Harness.it("MatchService se suscribio de verdad a la ronda", function()
			-- El fallo original no era una excepcion: era una suscripcion
			-- que nunca ocurria. Se comprueba el efecto, no el codigo.
			local subscribeLog = { count = 0 }
			local registry = makeRegistry()
			local roundService = makeRoundService()
			local matchService = makeMatchService(subscribeLog)

			registry:Register("RoundService", roundService, {})
			registry:Register("MatchService", matchService, { "RoundService" })

			registry:InitAll()
			matchService.SetDependencies(registry:Get("RoundService"))
			registry:StartAll()

			-- Si esto da 0, el juego arrancaria "limpio" sin mover a
			-- nadie: exactamente el sintoma reportado.
			expect.toBe(roundService.GetListenerCount(), 1)
		end)

		Harness.it("sin RoundService, MatchService NO arranca", function()
			-- El fallo debe seguir siendo un fallo VISIBLE, no un
			-- arranque silencioso en modo degradado.
			local subscribeLog = { count = 0 }
			local registry = makeRegistry()
			local matchService = makeMatchService(subscribeLog)

			registry:Register("MatchService", matchService, {})
			registry:InitAll()
			registry:StartAll()

			expect.toBe(subscribeLog.count, 0)
		end)
	end)

	Harness.describe("Registros: estado no compartido", function()
		Harness.it("el modelo ANTIGUO compartia estado entre registros", function()
			-- Este test documenta el bug. `setmetatable({}, Class)` hace
			-- que `self._entries` se resuelva por `__index` hasta la clase,
			-- de modo que escribir en `a` MUTA la tabla de `b`.
			local class = { _entries = {} }
			class.__index = class

			local a = setmetatable({}, class)
			local b = setmetatable({}, class)

			a._entries["X"] = { Name = "X" }

			-- Se espera que `b` VE a "X": si dejara de verlo, el test
			-- estaria describiendo el modelo arreglado y no probaria nada.
			expect.toBe(b._entries["X"] ~= nil, true)
		end)

		Harness.it("el modelo NUEVO aísla el estado de cada registro", function()
			-- Esta es la forma que usan ahora `ServiceRegistry.new()` y
			-- `ControllerRegistry.new()`: tabla propia por instancia.
			local class = { _entries = { Legacy = true } }
			class.__index = class

			local fresh = setmetatable({
				_entries = {},
				_order = {},
				_isRunning = false,
			}, class)

			expect.toBe(fresh._entries["Legacy"], nil)
		end)

		Harness.it("registrar en uno no aparece en otro", function()
			local class = { _entries = {} }
			class.__index = class

			local function make()
				return setmetatable({ _entries = {}, _order = {}, _isRunning = false }, class)
			end

			local a = make()
			local b = make()
			a._entries["InputController"] = {}

			expect.toBe(b._entries["InputController"], nil)
		end)
	end)
end