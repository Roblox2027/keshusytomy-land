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

-- Prefijo de los fallos de cableado. Se compara con `#PREFIX` y no con
-- un numero fijo: un conteo mal puesto hacia que los fallos se
-- imprimieran como INFO y volvieran a ser invisibles.
local WIRING_FAIL_PREFIX = "[WIRING FAIL]"

--- Servicios sin los cuales el juego NO es jugable. Se usan para el
--- informe de arranque: si uno de estos no llega a `Started`, el
--- servidor esta en modo degradado aunque no haya ningun error rojo.
ServerMain.CriticalServices = {
	"WorldService",
	"SpawnService",
	"DestructionService",
	"RoundService",
	"CombatService",
	"PlayerService",
	"ExplosionService",
	"BombService",
	"MatchService",
	-- El Core es critico: es el corazon del lobby y sin el la pantalla
	-- de carga no tiene sentido. Si no arranca, el lobby esta degradado.
	"CoreService",
	-- VisualService no es critico para PODER JUGAR (sin el, el juego corre
	-- a oscuras pero no se rompe). Se lista igualmente entre los servicios
	-- de arranque para que su ausencia salga en el informe en vez de pasar
	-- desapercibida: un lobby sin luz es un fallo de producto, no un
	-- detalle, y tiene que verse en el log.
	"VisualService",
}

--- Resultado del cableado de dependencias de la ultima arrancada.
ServerMain.WiringReport = {}

-- Referencias a los servicios que los handlers de remotos necesitan.
-- Se llenan en `Start`, despues de arrancar el registro.
local playerService = nil
local bombService = nil
local portalService = nil
local coreService = nil

-- Registro de servicios. Cada entrada declara sus dependencias para
-- que el orden de arranque sea determinista.
--
-- El orden de las dependencias importa de verdad: quien depende de
-- otro se inicializa despues. MatchService, por ejemplo, necesita que
-- DestruccionService ya haya registrado los bloques del mapa.
local SERVICES = {
	{ name = "WorldService", module = SERVER.Services.WorldService, dependencies = {} },
	{ name = "SpawnService", module = SERVER.Services.SpawnService, dependencies = { "WorldService" } },
	{ name = "DestructionService", module = SERVER.Services.DestructionService, dependencies = { "WorldService" } },
	{ name = "RoundService", module = SERVER.Services.RoundService, dependencies = { "WorldService" } },
	-- CombatService depende de RoundService: sin el estado de ronda no
	-- puede decidir si el dano es legal (el lobby es zona segura).
	{ name = "CombatService", module = SERVER.Services.CombatService, dependencies = { "RoundService" } },
	{ name = "PlayerService", module = SERVER.Services.PlayerService, dependencies = { "RoundService", "CombatService" } },
	{ name = "ExplosionService", module = SERVER.Services.ExplosionService, dependencies = { "DestructionService", "CombatService" } },
	{ name = "BombService", module = SERVER.Services.BombService, dependencies = { "RoundService", "ExplosionService" } },
	{ name = "MatchService", module = SERVER.Services.MatchService, dependencies = { "RoundService", "PlayerService", "BombService", "DestructionService" } },
	-- PortalService depende de MatchService: para entrar a un mundo hace
	-- falta saber a donde se teletransporta al jugador, y MatchService es el
	-- unico que tiene los marcadores de traslado del mapa.
	{ name = "PortalService", module = SERVER.Services.PortalService, dependencies = { "WorldService", "MatchService", "RoundService" } },
	-- CoreService va al final: no depende de nadie, pero el resto de
	-- servicios ya estan cableados cuando arranca, y su difusion usa
	-- el mismo registro.
	{ name = "CoreService", module = SERVER.Services.CoreService, dependencies = {} },
	-- VisualService va DESPUES de WorldService: lee el mapa (lobby, Core,
	-- portales y mundos) y enciende las luces de las arenas. Encenderlas
	-- antes de que el mundo exista las haria perderse: losFolders vacios
	-- no se recorren.
	{ name = "VisualService", module = SERVER.Services.VisualService, dependencies = { "WorldService" } },
}

--- Conecta las dependencias entre servicios.
---
--- Se hace ENTRE `InitAll` y `StartAll`: antes de arrancar, pero despues
--- de que cada servicio exista. Este es el unico punto del arranque en el
--- que un servicio puede conocer a otro.
---
--- AUDITORIA: antes esta funcion NO reportaba nada. Cada `if ... then`
--- se saltaba en silencio si una dependencia era nil, de modo que un
--- servicio podia quedarse sin cablear y el juego seguia "arrancando".
--- Ahora cada salto se registra como `[WIRING FAIL]` y se devuelve un
--- informe, para que el Output diga exactamente que falta y por que.
--- @param registry any registro de servicios
--- @return { string } report una linea por conexion
local function wireDependencies(registry: any): { string }
	local report: { string } = {}
	local worldService = registry:Get("WorldService")
	local roundService = registry:Get("RoundService")
	local playerService = registry:Get("PlayerService")
	local combatService = registry:Get("CombatService")
	local explosionService = registry:Get("ExplosionService")
	local bombService = registry:Get("BombService")
	local destructionService = registry:Get("DestructionService")
	local matchService = registry:Get("MatchService")
	local spawnService = registry:Get("SpawnService")
	local portalService = registry:Get("PortalService")

	-- Declara una conexion y verifica que se pudo hacer de verdad.
	-- @param label string
	-- @param consumer any servicio que recibe
	-- @param dependencies { string } nombres de lo que se le inyecta
	-- @param setter any? funcion que hace la inyeccion
	local function connect(label: string, consumer: any, dependencies: { string }, setter: any?)
		if not consumer then
			table.insert(report, ("[WIRING FAIL] %s no existe (su Init fallo)"):format(label))
			return
		end

		local missing = {}
		for _, dependency in ipairs(dependencies) do
			if not registry:Get(dependency) then
				table.insert(missing, dependency)
			end
		end

		if #missing > 0 then
			table.insert(report, ("[WIRING FAIL] %s sin %s"):format(
				label,
				table.concat(missing, ", ")
			))
			return
		end

		if setter then
			setter(consumer)
		end

		table.insert(report, ("[WIRING OK] %s -> %s"):format(
			label,
			table.concat(dependencies, ", ")
		))
	end

	-- ExplosionService necesita a CombatService: TODOS los danos pasan
	-- por ahi (invulnerabilidad, ronda, atribucion). Sin el, la explosion
	-- no puede danar a nadie.
	connect("ExplosionService", explosionService, { "DestructionService", "CombatService" },
		function(service: any)
			service.SetDependencies(destructionService, combatService)
		end
	)

	-- CombatService notifica las muertes a PlayerService, que es quien
	-- mantiene el estado de sesion y paga al asesino.
	connect("CombatService", combatService, { "RoundService", "PlayerService" },
		function(service: any)
			service.SetDependencies(roundService, playerService)
		end
	)

	connect("BombService", bombService, { "RoundService", "ExplosionService" },
		function(service: any)
			service.SetDependencies(roundService, explosionService)
		end
	)

	-- `spawnService` se inyecta ADEMAS de los tres anteriores: sin el,
	-- `player.RespawnLocation` queda en `nil` y Roblox decide el punto de
	-- reaparicion por su cuenta (el origen, que aqui esta en mitad del
	-- vacio entre el lobby y la arena).
	connect("PlayerService", playerService, { "RoundService", "CombatService", "MatchService", "SpawnService" },
		function(service: any)
			service.SetDependencies(roundService, combatService, matchService, spawnService)
		end
	)

	-- SpawnService necesita saber en que zona esta el jugador para
	-- rescatarlo en el sitio correcto (arena si hay ronda, lobby si no).
	connect("SpawnService", spawnService, { "RoundService", "MatchService" },
		function(service: any)
			service.SetDependencies(roundService, matchService)
		end
	)

	connect("MatchService", matchService,
		{ "RoundService", "PlayerService", "BombService", "DestructionService", "CombatService" },
		function(service: any)
			service.SetDependencies(roundService, playerService, bombService, destructionService, combatService)
		end
	)

	-- PortalService necesita el mundo (para el nivel), el destino (para
	-- teletransportar), la ronda (para impedir salir durante la partida) y el
	-- jugador (para leer su nivel real y no el atributo del cliente).
	connect("PortalService", portalService,
		{ "WorldService", "MatchService", "RoundService", "PlayerService" },
		function(service: any)
			service.SetDependencies(worldService, matchService, roundService, playerService)
		end
	)

	-- MatchService necesita conocer el mundo por defecto para validar
	-- a quien puede entrar en el (FASE 18 lo hara con portales).
	if worldService then
		table.insert(report, ("[WIRING OK] mundo por defecto: %s"):format(
			tostring(worldService.GetDefaultWorldId())
		))
	end

	-- El informe se imprime aqui y no solo se devuelve: un fallo de
	-- cableado es la causa mas silenciosa de "el juego no hace nada".
	for _, line in ipairs(report) do
		if string.sub(line, 1, #WIRING_FAIL_PREFIX) == WIRING_FAIL_PREFIX then
			Logger.Error(line)
		else
			Logger.Info(line)
		end
	end

	return report
end

-- Canales remotos y sus handlers.
--
-- Un canal SIN handler sigue siendo validado y limitado, y el gateway
-- descarta la peticion en vez de ejecutarla. Es preferible a declarar
-- funciones vacias que aparenten funcionar.
--
-- Solo hay handlers para lo que el servidor puede resolver de verdad:
--	- PlayerAction.SetReady / RequestState: estado de sesion.
--	- BombAction.Place: coloca bomba con validacion en servidor.
-- El resto de canales (Shop, Inventory, Quest, Portal, Party, Settings)
-- llega en sus fases correspondientes (32, 14, 35, 18, 21, 31).
local REMOTE_CHANNELS = {
	[GameConstants.RemoteAction.Player] = {
		SetReady = function(player: Player, payload: any)
			if playerService then
				playerService.SetReady(player, payload == true)
			end
		end,

		RequestState = function(player: Player, _payload: any)
			-- Reenvia el estado al cliente que lo pide. No concede nada:
			-- solo publica informacion que el jugador ya tiene.
			if playerService then
				local session = playerService.GetSessionFromPlayer(player)
				if session then
					player:SetAttribute("Level", session.Level)
					player:SetAttribute("XP", session.XP)
					player:SetAttribute("Coins", session.Coins)
					player:SetAttribute("Gems", session.Gems)
				end
			end
		end,
	},

	[GameConstants.RemoteAction.Bomb] = {
		Place = function(player: Player, payload: any)
			if not bombService then
				Logger.Warn("BombAction.Place recibido sin BombService")
				return
			end

			local placed, reason = bombService.TryPlaceBomb(player, payload)
			if not placed then
				-- El motivo se registra SIEMPRE: un rechazo sin registro
				-- es imposible de depurar desde fuera.
				Logger.Debug(("bomba rechazada para %s: %s"):format(player.Name, tostring(reason)))
			end
		end,
	},

	[GameConstants.RemoteAction.Shop] = {},
	[GameConstants.RemoteAction.Inventory] = {},
	[GameConstants.RemoteAction.Quest] = {},

	-- El canal del Keshusy Core. Sin payload: el cliente solo pide
	-- aportar un fragmento, nunca dice cuanta carga ni que estado.
	[GameConstants.RemoteAction.Core] = {
		Interact = function(player: Player, _payload: any)
			if not coreService then
				Logger.Warn("CoreAction.Interact recibido sin CoreService")
				return
			end

			coreService.HandleInteract(player, _payload)
		end,

		RequestState = function(player: Player, _payload: any)
			if not coreService then
				return
			end

			-- Concede NADA: solo publica informacion que el nucleo
			-- ya decidio en el servidor.
			player:SetAttribute("CoreState", coreService.GetState().State)
			player:SetAttribute("CoreCharge", coreService.GetState().Charge)
		end,
	},

	-- El canal de portales es la UNICA via de entrada a un mundo. El
	-- payload es solo el `worldId` pedido: el servidor decide si el viaje
	-- procede y calcula el destino. Un cliente que invente un `worldId` no
	-- tiene portal asociado y la peticion se descarta.
	[GameConstants.RemoteAction.Portal] = {
		Enter = function(player: Player, payload: any)
			if not portalService then
				Logger.Warn("PortalAction.Enter recibido sin PortalService")
				return
			end

			portalService.HandleEnter(player, payload)
		end,
	},

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
---
--- Los errores de arranque NO se silencian: cada fallo se registra en
--- el output con su mensaje, y ademas se acumula en `ServerMain.Errors`
--- para poder consultarlo desde la consola de Studio.
--- @return boolean success
function ServerMain.Initialize(): boolean
	local errors: { string } = {}
	ServerMain.Errors = errors

	local verified, missing = ServerMain.VerifyRequiredModules()
	if not verified then
		local message = "Server initialization aborted. Missing: " .. table.concat(missing, ", ")
		Logger.Error(message)
		table.insert(errors, message)
		return false
	end

	Logger.Info(("%s v%s | server starting..."):format(
		Logger.GetGameName(),
		Logger.GetGameVersion()
	))

	-- Un unico registro por servidor. Lo consultan los servicios.
	local registry = ServiceRegistry.new()
	ServerMain.Registry = registry

	-- `SERVICES[].module` guarda la INSTANCIA ModuleScript, no el valor
	-- que devuelve. Hay que `require`la aqui.
	--
	-- AUDITORIA (P0): se pasaba `entry.module` tal cual a `Register`, y
	-- `ServiceRegistry:Register` rechaza con "modulo invalido" lo que no
	-- sea `table`. Una Instance no es una tabla, asi que los NUEVE
	-- servicios se rechazaban uno a uno: "ServiceRegistry: 0 servicios
	-- inicializados", "[BOOT FAIL] ... no arranco (estado: nil)" para
	-- todos, y ningun error rojo en el Output. El servidor arrancaba
	-- "correcto" sin un solo servicio vivo. Los tests unitarios no lo
	-- detectan porque registraban modulos de mentira que ya eran tablas.
	--
	-- El `pcall` no esconde nada: si el modulo revienta al cargarse,
	-- se registra el error REAL y el servicio queda sin registrar, que
	-- es justo lo que el informe de arranque tiene que detectar.
	for _, entry in ipairs(SERVICES) do
		local ok, module = pcall(require, entry.module)

		if not ok then
			local message = ("no se pudo cargar '%s': %s"):format(entry.name, tostring(module))
			Logger.Error(message)
			table.insert(errors, message)
		elseif type(module) ~= "table" then
			local message = ("'%s' no devuelve una tabla (devuelve %s)"):format(
				entry.name,
				type(module)
			)
			Logger.Error(message)
			table.insert(errors, message)
		else
			local registered, registerError = registry:Register(entry.name, module, entry.dependencies)
			if not registered then
				local message = ("no se pudo registrar '%s': %s"):format(entry.name, tostring(registerError))
				Logger.Error(message)
				table.insert(errors, message)
			end
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

	local registry = ServerMain.Registry

	-- ORDEN DE ARRANQUE (auditoria de integracion):
	--
	-- BUG CORREGIDO: antes se llamaba `Registry:Start()`, que hacia Init y
	-- Start en un solo paso, y las dependencias se cableaban DESPUES. Como
	-- `Registry:Get` solo devolvia instancias ya arrancadas, `MatchService`
	-- arrancaba sin `RoundService` inyectado y su `Start` devolvia false
	-- ANTES de suscribirse a `OnStateChanged`. En el juego eso significaba:
	--   - nadie se teletransportaba nunca a la arena,
	--   - `RoundService` avanzaba de estado sin nadie escuchando,
	--   - las bombas nunca podian colocarse (no habia arena),
	--   - y todo ello con el output aparentemente "limpio".
	--
	-- Ahora: Init de todo -> cablear -> Start de todo. Ese es el unico
	-- orden en el que las dependencias tienen sentido.
	local initialized = registry:InitAll()

	-- Cableado. `Get` ya devuelve los servicios inicializados, asi que
	-- esta fase ve exactamente los mismos objetos que vera `Start`.
	ServerMain.WiringReport = wireDependencies(registry)

	-- Los handlers de remotos consultan estos en caliente.
	playerService = registry:Get("PlayerService")
	bombService = registry:Get("BombService")
	-- El handler de `PortalAction.Enter` vive fuera de `wireDependencies`,
	-- asi que necesita la misma referencia a nivel de modulo que los demas.
	portalService = registry:Get("PortalService")
	-- El nucleo se inyecta igual: su handler necesita el servicio vivo.
	coreService = registry:Get("CoreService")

	-- El nucleo difunde por el mismo canal bidireccional que usa el
	-- cliente para pedir fragmentos. Se le da la FUNCION de emision y no
	-- el remoto entero, para que el servicio no dependa de como esten
	-- cableados los remotos y se pueda probar aislado.
	if coreService and coreService.SetBroadcast then
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		local coreRemote = remotes and remotes:FindFirstChild(GameConstants.RemoteAction.Core)

		if coreRemote and coreRemote:IsA("RemoteEvent") then
			coreService.SetBroadcast(function(state)
				coreRemote:FireAllClients(state)
			end)
		else
			-- Sin remoto el nucleo sigue funcionando: solo pierde la
			-- barra del cliente. Es una degradacion, no un fallo.
			Logger.Warn("CoreService: sin CoreAction; el nucleo no se difunde.")
		end
	end

	local started = registry:StartAll()

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

	-- Resumen de arranque. Se imprime SIEMPRE, no solo en fallo: sin esto
	-- no hay forma de saber desde el Output que sistema arranco y cual no.
	Logger.Info("[BOOT] SERVIDOR ARRANCADO")
	for _, line in ipairs(ServerMain.GetBootReport()) do
		Logger.Info(line)
	end

	if not initialized then
		Logger.Error("[BOOT FAIL] hay servicios cuyo Init fallo; revisa el informe de arriba.")
	end

	if not started then
		Logger.Error("[BOOT FAIL] hay servicios cuyo Start fallo; revisa el informe de arriba.")
	end

	return initialized and started
end

--- Informe del arranque: una linea por servicio con su estado real.
---
--- Es la unica forma de distinguir "todo bien" de "arranca en modo
--- degradado" leyendo el Output, sin abrir el explorador a cada paso.
--- @return { string } report
function ServerMain.GetBootReport(): { string }
	local report = {}

	if not ServerMain.Registry then
		table.insert(report, "[BOOT] no hay registro de servicios")
		return report
	end

	table.insert(report, ("[BOOT] estado del servidor: %s"):format(
		ServerMain.Registry:GetServerState()
	))

	for _, line in ipairs(ServerMain.Registry:GetReport()) do
		table.insert(report, ("[BOOT]   %s"):format(line))
	end

	local failed = 0
	for _, name in ipairs(ServerMain.CriticalServices) do
		local _, state = ServerMain.Registry:GetEntry(name)
		if tostring(state) ~= GameConstants.ServiceState.Started then
			failed += 1
			table.insert(report, ("[BOOT FAIL] %s no arranco (estado: %s)"):format(
				name,
				tostring(state)
			))
		end
	end

	if failed == 0 then
		table.insert(report, ("[BOOT] servicios criticos OK (%d)"):format(
			#ServerMain.CriticalServices
		))
	end

	return report
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
