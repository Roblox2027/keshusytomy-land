--!strict
--[[
	CoreService
	El Keshusy Core: el corazon del lobby.

	Que hace:
	- Lee el nucleo REAL del mapa (`Workspace.Lobby.KeshusyCore`).
	- Acepta fragmentos de los jugadores y lleva la carga.
	- Decide la activacion cuando se alcanza el maximo.
	- Desbloquea el mundo siguiente al activarse.
	- Difunde el estado a los clientes para la barra.

	Autoridad: la TOTALIDAD de las decisiones son del servidor. El
	cliente solo pide "aporto un fragmento"; nunca dice cuanta carga,
	ni que estado tiene el nucleo, ni cuando se desbloquea un mundo.

	Separacion de responsabilidades:
	Las REGLAS (maquina de estados, limites, recarga) viven en
	`CoreRules`, que es logica pura y esta probada de verdad con
	`luau.exe`. Este servicio solo las aplica, las conecta con el mapa y
	con los jugadores. Esa division es la que permite que las reglas se
	prueben sin Workspace ni Players.

	Por que el nucleo no se genera en codigo:
	`tools/generate-project.js` ya lo construye como
	`Workspace.Lobby.KeshusyCore` (CoreOrb, CoreRing_A/B, CorePillar_*,
	CoreGlow, CoreBase, CoreDais, CorePlinth). Este servicio lo USA; no
	lo duplica. Si el mapa no esta, el servicio avisa y sigue vivo con
	las reglas, que es lo que permite probarlo sin mapa.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONFIG = SHARED:WaitForChild("Config")
local LIBRARIES = SHARED:WaitForChild("Libraries")

local GameConfig = require(CONFIG:WaitForChild("GameConfig"))
local FeatureConfig = require(CONFIG:WaitForChild("FeatureConfig"))
-- `GameConstants` no se requiere aqui: el nucleo no define acciones,
-- las define `RemoteSchema`. Requerirlo sin usarlo haria creer que hay
-- un contrato de estados aqui que en realidad vive en otro sitio.
local Logger = require(SHARED:WaitForChild("Utils"):WaitForChild("Logger"))
local CoreRules = require(LIBRARIES:WaitForChild("CoreRules"))

local Service = {}

Service.IsInitialized = false

--- Indica si el interruptor de contenido del Core esta activo.
--- Si esta apagado el servicio arranca igualmente, pero no acepta
--- fragmentos: un flag apagado desactiva la FUNCION, no rompe el
--- arranque del servidor.
Service.IsEnabled = FeatureConfig.ENABLE_CORE ~= false

--- Prefijo del nucleo en el mapa. Contrato con `tools/generate-project.js`.
Service.CORE_FOLDER_NAME = "KeshusyCore"

--- Parte que representa el centro del nucleo. Es la que se usa como
--- punto de referencia de distancia y la que cambia de color.
Service.CORE_ORB_NAME = "CoreOrb"

--- Distancia maxima a la que se acepta un fragmento. Coherente con
--- `PortalService.PORTAL_MAX_DISTANCE`: mismo criterio, misma magnitud.
Service.INTERACT_RANGE = 40

--- Estado actual, delegando las reglas en CoreRules.
Service._state = CoreRules.NewState()

--- Piezas del nucleo en el mapa (puede estar vacio si no hay mapa).
Service._parts = {}
Service._folder = nil

--- Funcion que difunde el estado. La inyecta ServerMain para poder
--- probarla sin depender de como estan los remotos.
Service._broadcast = nil

--- Instante de la ultima difusion, para no enviar 60 veces por segundo.
Service._lastBroadcastAt = 0

--- Ultimo error de difusion. Se registra UNA vez y no se propaga: un
--- fallo de red no puede detener el nucleo.
Service._warnedAboutBroadcast = false

--- Ultimo numero de activacion que se dio por completada. Evita contar
--- dos veces la misma si el bucle se reanuda o salta un frame.
Service._lastCompletionCount = 0

--- Conexiones vivas, para poder soltarlas todas en `Destroy`.
Service._connections = {}

--- Opciones de reglas tomadas de la configuracion, en un solo sitio.
--- @param now number
--- @return table
local function ruleOptions(now: number): any
	return {
		maxCharge = GameConfig.CoreMaxCharge,
chargePerFragment = GameConfig.CoreChargePerFragment,
		fragmentsPerPlayer = GameConfig.CoreFragmentsPerPlayer,
		fragmentCooldown = GameConfig.CoreFragmentCooldown,
		activationDuration = GameConfig.CoreActivationDuration,
		drainPerSecond = GameConfig.CoreOverloadDrainPerSecond,
		eventDuration = 0,
		passiveDrainPerSecond = GameConfig.CoreCorePassiveDrainPerSecond,
		step = 0,
		now = now,
	}
end

--- Localiza el nucleo en el mapa y guarda sus piezas.
--- Localiza el nucleo en el mapa y guarda sus piezas.
---
--- No falla si no existe: el nucleo es contenido, y un mapa sin
--- nucleo debe dejar el servidor operativo (se registra un aviso).
--- @return boolean found
function Service.CollectCore(): boolean
	Service._parts = {}
	Service._folder = nil

	local lobby = workspace:FindFirstChild("Lobby")
	if not lobby then
		Logger.Warn("Workspace.Lobby no existe; el Keshusy Core no tiene mapa.")
		return false
	end

	local folder = lobby:FindFirstChild(Service.CORE_FOLDER_NAME)
	if not folder then
		Logger.Warn(("Workspace.Lobby.%s no existe; el Keshusy Core no tiene mapa."):format(
			Service.CORE_FOLDER_NAME
		))
		return false
	end

	Service._folder = folder

	-- Se guardan las piezas por nombre para poder cambiar color y
	-- transparencia sin recorrer el arbol en cada actualizacion.
	local names = { "CoreOrb", "CoreGlow", "CoreRing_A", "CoreRing_B" }
	local found = 0
	for _, name in ipairs(names) do
		local piece = folder:FindFirstChild(name)
		if piece and piece:IsA("BasePart") then
			Service._parts[name] = piece
			found += 1
		end
	end

	if not Service._parts[Service.CORE_ORB_NAME] then
		Logger.Warn(("el nucleo no tiene '%s'; se usara el CoreBase como referencia."):format(
			Service.CORE_ORB_NAME
		))
	end

	Logger.Info(("Keshusy Core encontrado (%d piezas clave)."):format(found))

	return true
end

--- Punto de referencia del nucleo, o nil si no hay mapa.
--- @return Vector3?
function Service.GetPosition(): Vector3?
	local orb = Service._parts[Service.CORE_ORB_NAME]
	if orb then
		return orb.Position
	end

	if Service._folder then
		local base = Service._folder:FindFirstChild("CoreBase")
		if base and base:IsA("BasePart") then
			return base.Position
		end
	end

	return nil
end

--- Copia PUBLICA del estado. Se devuelve una tabla nueva para que
--- nadie de fuera pueda mutar el estado real del servicio.
--- @return table
function Service.GetState(): any
	local state = Service._state
	return {
		State = state.State,
		Charge = state.Charge,
		MaxCharge = GameConfig.CoreMaxCharge,
		ChargeFraction = CoreRules.ChargeFraction(state.Charge, GameConfig.CoreMaxCharge),
		ActivationCount = state.ActivationCount,
	}
end

--- Inyecta la funcion de difusion.
---
--- Se hace por inyeccion (y no leyendo el remoto dentro del servicio)
--- para que el nucleo no dependa del cableado de remotos y se pueda
--- probar sin montarlos.
--- @param broadcast fun(state: table)?
function Service.SetBroadcast(broadcast: any?)
	Service._broadcast = broadcast
end

--- Consulta si el nucleo esta en un estado concreto.
--- @param stateName string
--- @return boolean
function Service.IsInState(stateName: string): boolean
	return Service._state.State == stateName
end

--- Mundo siguiente en el orden de desbloqueo. Es el MISMO orden que
--- usa `WorldService`, para que "siguiente" signifique lo mismo en
--- los dos sitios.
--- @return string?
function Service.GetNextWorldId(): string?
	local order = { "Forest", "Desert", "Ice", "Volcano", "Cyber" }
	local completed = Service._state.ActivationCount

	for index, id in ipairs(order) do
		if index > completed and FeatureConfig["ENABLE_" .. string.upper(id)] then
			return id
		end
	end

	return nil
end

--- Indica si un mundo quedo accesible. El primero siempre lo esta;
--- los siguientes, uno por activacion.
--- @param worldId string
--- Comprueba que un jugador este lo bastante cerca del nucleo.
---
--- Es la mitad de la seguridad del Core: sin esta comprobacion, un
--- cliente podria aportar fragmentos desde el otro extremo del mapa
--- (o sin personaje) y llenar la barra solo.
--- @param player Player
--- @return boolean ok
--- @return string? reason
function Service.CheckInRange(player: Player): (boolean, string?)
	if not player or not player:IsDescendantOf(Players) then
		return false, "jugador invalido"
	end

	local position = Service.GetPosition()
	if not position then
		return false, "nucleo sin posicion"
	end

	local character = player.Character
	if not character then
		return false, "sin personaje"
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return false, "sin raiz"
	end

	-- Se compara en el plano: la altura no debe decidir si alguien
	-- puede tocar el nucleo (se puede estar encima de la pila).
	local dx = rootPart.Position.X - position.X
	local dz = rootPart.Position.Z - position.Z
	local distance = math.sqrt(dx * dx + dz * dz)

	if distance > Service.INTERACT_RANGE then
		return false, "demasiado lejos del nucleo"
	end

	return true, nil
end

--- Intenta aportar un fragmento al nucleo.
---
--- Toda la decision es del servidor. El cliente no envia ni cuanta
--- carga ni cantidad: solo pide aportar UN fragmento.
--- @param player Player
--- @return boolean accepted
--- @return string? reason
function Service.TryAddFragmentFor(player: Player): (boolean, string?)
	if not Service.IsInitialized then
		return false, "nucleo no inicializado"
	end

	if not Service.IsEnabled then
		return false, "nucleo deshabilitado"
	end

	if not Service.CheckInRange(player) then
		local _, reason = Service.CheckInRange(player)
		return false, reason
	end

	local now = os.clock()
	local accepted, reason, nextState = CoreRules.TryAddFragment(
		Service._state,
		player.UserId,
		ruleOptions(now)
	)

	if not accepted or not nextState then
		return false, reason
	end

	Service._state = nextState
	Logger.Debug(("%s aporto un fragmento: carga %d/%d"):format(
		player.Name,
		nextState.Charge,
		GameConfig.CoreMaxCharge
	))

	Service._applyVisuals()
	Service._broadcastState(true)

	return true, nil
end

--- Maneja la peticion del cliente por el canal de remotos.
--- @param player Player
--- @param _payload any se ignora: no hay nada que el cliente pueda aportar
function Service.HandleInteract(player: Player, _payload: any)
	local accepted, reason = Service.TryAddFragmentFor(player)

	if not accepted then
		-- El motivo se registra siempre: un rechazo sin registro es
		-- imposible de depurar desde fuera.
		Logger.Debug(("fragmento rechazado para %s: %s"):format(
			player.Name,
			tostring(reason)
		))
	end
end

--- Aplica el aspecto segun el estado. Es una FUNCIÓN PURA del nucleo:
--- cada estado tiene un color y una transparencia, y el nucleo no
--- acumula efectos: se reescribe el estado, nunca se suma.
---
--- Si el mapa no esta, no hace nada y NO es un error: el nucleo
--- funciona sin mapa (util para pruebas).
function Service._applyVisuals()
	local orb = Service._parts[Service.CORE_ORB_NAME]
	if not orb then
		return
	end

	local state = Service._state.State
	local fraction = CoreRules.ChargeFraction(Service._state.Charge, GameConfig.CoreMaxCharge)

	local color = Color3.fromRGB(60, 90, 140)
	local transparency = 0.5

	if state == CoreRules.State.Activating then
		color = Color3.fromRGB(255, 210, 90)
		transparency = 0.1
	elseif state == CoreRules.State.Active then
		color = Color3.fromRGB(120, 255, 170)
		transparency = 0.05
	elseif state == CoreRules.State.Overloaded then
		color = Color3.fromRGB(255, 90, 90)
		transparency = 0.2
	elseif state == CoreRules.State.Event then
		color = Color3.fromRGB(200, 140, 255)
		transparency = 0.1
	end

	-- La carga también se ve: el nucleo se aclara al llenarse.
	local brightness = 0.6 + (0.4 * fraction)
	orb.Color = Color3.new(
		math.min(color.R * brightness + fraction * 0.1, 1),
		math.min(color.G * brightness + fraction * 0.1, 1),
		math.min(color.B * brightness + fraction * 0.1, 1)
	)
	orb.Transparency = transparency
end

--- Difunde el estado a los clientes. Nunca propaga un error: un fallo
--- al emitir el remoto no puede detener el nucleo.
--- @param force boolean? true para saltar el limite de frecuencia
function Service._broadcastState(force: boolean?)
	if not Service._broadcast then
		return
	end

	local now = os.clock()
	if not force and (now - Service._lastBroadcastAt) < GameConfig.CoreBroadcastInterval then
		return
	end

	local ok, err = pcall(Service._broadcast, Service.GetState())
	if not ok then
		if not Service._warnedAboutBroadcast then
			Service._warnedAboutBroadcast = true
			Logger.Error(("CoreService: fallo al difundir el estado: %s"):format(tostring(err)))
		end
		return
	end

	Service._lastBroadcastAt = now
end

--- Avanza la maquina de estados y aplica sus efectos.
--- @param dt number delta de tiempo
function Service._step(dt: number)
	if not Service.IsInitialized then
		return
	end

	local now = os.clock()
	local before = Service._state

	Service._state = CoreRules.Advance(before, now, {
		maxCharge = GameConfig.CoreMaxCharge,
		drainPerSecond = GameConfig.CoreOverloadDrainPerSecond,
		passiveDrainPerSecond = GameConfig.CoreCorePassiveDrainPerSecond,
		step = dt,
		eventDuration = 0,
	})

	-- Una activacion nueva se celebra UNA vez. Se compara el contador
	-- en vez de mirar el estado, porque el nucleo pasa por Active y
	-- podria volver a Inerte en el mismo tick largo.
	if Service._state.ActivationCount > Service._lastCompletionCount then
		Service._lastCompletionCount = Service._state.ActivationCount

		local nextWorld = Service.GetNextWorldId()
		Logger.Info(("Keshusy Core activado (%d veces). Siguiente mundo: %s"):format(
			Service._state.ActivationCount,
			tostring(nextWorld)
		))
	end

	Service._applyVisuals()
	Service._broadcastState()
end

--- Indica si un mundo quedo accesible. El primero siempre lo esta;
--- los siguientes, uno por activacion.
--- @param worldId string
--- @return boolean
function Service.IsWorldUnlocked(worldId: string): boolean
	local order = { "Forest", "Desert", "Ice", "Volcano", "Cyber" }

	for index, id in ipairs(order) do
		if id == worldId then
			return index <= Service._state.ActivationCount + 1
		end
	end

	return false
end

--- Inicializacion del servicio. Idempotente.
---
--- NO comprueba dependencias aqui: el registro ejecuta `InitAll` antes
--- de cablear, igual que hacen los demas servicios.
--- @return boolean success
function Service.Init(): boolean
	if Service.IsInitialized then
		return true
	end

	Service._state = CoreRules.NewState()
	Service._parts = {}
	Service._folder = nil
	Service._lastBroadcastAt = 0
	Service._warnedAboutBroadcast = false
	Service._lastCompletionCount = 0
	Service._connections = {}

	Service.IsInitialized = true
	return true
end

--- Comienza a servir. El nucleo se busca aqui y no en `Init`, porque
--- es el primer momento en que el mapa esta disponible.
--- @return boolean success
function Service.Start(): boolean
	if not Service.IsInitialized then
		Logger.Error("CoreService: Start sin Init")
		return false
	end

	local ok, err = pcall(function()
		Service.CollectCore()
		Service._applyVisuals()

		-- Un unico bucle con Stepped: el nucleo es UN objeto y no
		-- necesita mas. El dt se limita porque un frame largo (por
		-- ejemplo al cargar una parte) no debe drenar el nucleo de golpe.
		Service._connections[#Service._connections + 1] = RunService.Heartbeat:Connect(function(dt)
			local capped = math.min(dt, 0.5)
			Service._step(capped)
		end)

		Logger.Info(("CoreService: nucleo listo (max %d, +%d por fragmento)."):format(
			GameConfig.CoreMaxCharge,
			GameConfig.CoreChargePerFragment
		))
	end)

	if not ok then
		Logger.Error("CoreService Start fallo: " .. tostring(err))
		return false
	end

	return true
end

--- Limpieza. Suelta TODAS las conexiones: un `Heartbeat` sin
--- limpiar sobrevive al apagado del servicio y sigue tickeando.
--- @return boolean success
function Service.Destroy(): boolean
	for _, connection in ipairs(Service._connections) do
		pcall(function()
			connection:Disconnect()
		end)
	end

	Service._connections = {}
	Service._broadcast = nil
	Service._parts = {}
	Service._folder = nil
	Service._state = CoreRules.NewState()
	Service.IsInitialized = false

	return true
end

return Service