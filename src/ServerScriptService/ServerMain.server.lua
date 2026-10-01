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

-- Referencias a los servicios que los handlers de remotos necesitan.
-- Se llenan en `Start`, despues de arrancar el registro.
local playerService = nil
local bombService = nil

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
}

--- Conecta las dependencias entre servicios.
---
--- Se hace ANTES de arrancar el ciclo de ronda: si no, la primera
--- ronda empezaria sin traslados ni destruccion configurados.
--- @param registry any registro de servicios
local function wireDependencies(registry: any)
	local worldService = registry:Get("WorldService")
	local roundService = registry:Get("RoundService")
	local playerService = registry:Get("PlayerService")
	local combatService = registry:Get("CombatService")
	local explosionService = registry:Get("ExplosionService")
	local bombService = registry:Get("BombService")
	local destructionService = registry:Get("DestructionService")
	local matchService = registry:Get("MatchService")

	-- ExplosionService necesita a CombatService: TODOS los danos pasan
	-- por ahi (invulnerabilidad, ronda, atribucion). Si falta, la
	-- explosion no puede danar a nadie.
	if explosionService and destructionService and combatService then
		explosionService.SetDependencies(destructionService, combatService)
	end

	-- CombatService notifica las muertes a PlayerService, que es quien
	-- mantiene el estado de sesion y paga al asesino.
	if combatService and roundService and playerService then
		combatService.SetDependencies(roundService, playerService)
	end

	if bombService then
		bombService.SetDependencies(roundService, explosionService)
	end

	if playerService and roundService and combatService then
		playerService.SetDependencies(roundService, combatService, matchService)
	end

	if matchService then
		matchService.SetDependencies(roundService, playerService, bombService, destructionService)
	end

	-- MatchService necesita conocer el mundo por defecto para validar
	-- a quien puede entrar en el (FASE 18 lo hara con portales).
	if worldService then
		Logger.Debug(("mundo por defecto: %s"):format(tostring(worldService.GetDefaultWorldId())))
	end
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

	for _, entry in ipairs(SERVICES) do
		local registered, registerError = registry:Register(entry.name, entry.module, entry.dependencies)
		if not registered then
			local message = ("no se pudo registrar '%s': %s"):format(entry.name, tostring(registerError))
			Logger.Error(message)
			table.insert(errors, message)
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

	-- Servicios que los handlers de remotos consultan en caliente.
	playerService = ServerMain.Registry:Get("PlayerService")
	bombService = ServerMain.Registry:Get("BombService")

	-- Las dependencias se conectan DESPUES de arrancar: `Registry:Get`
	-- solo devuelve instancias ya iniciadas. Hacerlo antes devolveria
	-- nil y los servicios se quedarian sin wiring, en silencio.
	wireDependencies(ServerMain.Registry)

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
