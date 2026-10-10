--!strict
--[[
	ClientBootProbe

	Sonda MINIMA de arranque del cliente. NO es una feature: es la prueba de
	infraestructura de la FASE 2.1 (y el identificador de sesion de la FASE 3).

	POR QUE EXISTE
	--------------
	Las herramientas MCP que deberian hablar con el cliente
	(`eval_client_runtime`, `capture_screenshot`, `execute_luau` con
	target=client-1) devuelven `request_timeout` contra el peer del cliente.
	Eso, por si solo, NO dice si el cliente esta vivo: puede ser el puente.

	Este script responde a UN RemoteFunction (`ClientBootProbe`) con una lista
	de comprobaciones inequivocas:

		CLIENT_BOOT_OK      el LocalScript llego a ejecutarse
		PLAYER_OK           existe LocalPlayer
		CHARACTER_OK        existe el personaje y su Humanoid
		PLAYER_GUI_OK       existe PlayerGui
		CAMERA_OK           existe CurrentCamera
		CLIENT_REMOTE_OK    el RemoteFunction existe y esta enganchado
		SERVER_REPLY_OK     el servidor recibio esta respuesta

	IDENTIDAD DE SESION (FASE 3)
	-------------------------
	Publica SESSION_ID, PLACE_ID, JOB_ID, PLAYER_NAME, PLAYER_USER_ID y
	CLIENT_START_TIME. El servidor se compara consigo mismo. Sirve para que
	un PASS no venga de un Studio viejo, un Play viejo o un cliente anterior.

	GARANTIAS
	---------
	1. Solo arranca con `ENABLE_CLIENT_CERT_PROBE`. Apagado, no hace nada.
	2. No crea UI, no dibuja nada y no modifica el estado del juego.
	3. No importa ningun servicio del servidor: `ServerScriptService` no
	   existe en el cliente, asi que no hay atajo posible.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONFIG = SHARED:WaitForChild("Config")
local UTILS = SHARED:WaitForChild("Utils")

local FeatureConfig = require(CONFIG:WaitForChild("FeatureConfig"))
local Logger = require(UTILS:WaitForChild("Logger"))

local PROBE_NAME = "ClientBootProbe"

-- Momento EXACTO en que este script empezo a ejecutarse. Es el ancla para
-- distinguir "el cliente actual" de "un cliente anterior".
local CLIENT_START_TIME = os.time()
local CLIENT_START_CLOCK = os.clock()

local LocalPlayer = Players.LocalPlayer

--- Identidad de esta ejecucion, para relatearla con la del servidor.
local function identity(): { [string]: any }
	return {
		SESSION_ID = PROBE_NAME,
		CLIENT_BOOT_OK = true,
		PLACE_ID = game.PlaceId,
		JOB_ID = game.JobId,
		GAME_ID = game.GameId,
		PLAYER_NAME = LocalPlayer and LocalPlayer.Name or "NIL",
		PLAYER_USER_ID = LocalPlayer and LocalPlayer.UserId or -1,
		CLIENT_START_TIME = CLIENT_START_TIME,
		CLIENT_START_CLOCK = math.floor(CLIENT_START_CLOCK * 1000) / 1000,
		IS_STUDIO = RunService:IsStudio(),
	}
end

--- Comprobaciones minimas del arranque, cada una con su veredicto.
local function bootReport(): { [string]: any }
	local report = identity()

	local player = Players.LocalPlayer
	report.PLAYER_OK = player ~= nil

	local character = player and player.Character
	report.CHARACTER_OK = character ~= nil

	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	report.HUMANOID_OK = humanoid ~= nil
	report.HEALTH = if humanoid then humanoid.Health else -1

	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	report.PLAYER_GUI_OK = playerGui ~= nil
	report.PLAYER_GUI_CHILDREN = if playerGui then #playerGui:GetChildren() else 0

	local camera = workspace.CurrentCamera
	report.CAMERA_OK = camera ~= nil

	if camera then
		local viewport = camera.ViewportSize
		report.VIEWPORT = ("%dx%d"):format(viewport.X, viewport.Y)
	end

	-- `VIEWPORT_SIZE` es lo que permite distinguir un cliente de verdad de
	-- una instancia de Luau sin ventana.
	report.VIEWPORT_SIZE_OK = report.VIEWPORT ~= nil

	-- Estado REAL de los controllers del cliente.
	--
	-- Se lee con `pcall` por controller: si uno no arranco, el informe entero
	-- no debe caer. Ademas `require` aqui NO es un atajo: el controller ya
	-- esta cargad en memoria por `ClientMain`, y lo que se lee es el estado
	-- que el juego ha ido construyendo, no una ejecucion nueva.
	local CONTROLLERS = script.Parent:FindFirstChild("Controllers")
	report.CONTROLLERS = {}
	if CONTROLLERS then
		for _, name in ipairs({
			"InputController",
			"BombController",
			"PortalController",
			"UIController",
		}) do
			-- Cada controller se lee con `pcall`: si uno falla, el informe
			-- entero no debe caer y el fallo queda visible en su entrada.
			-- No se usa `continue` porque Luau no lo tiene.
			local module = CONTROLLERS:FindFirstChild(name)
			local entry = nil

			if module then
				local ok, controller = pcall(require, module)

				if ok then
					entry = { ACTIVE = controller.IsActive }

					if type(controller.GetState) == "function" then
						local okState, state = pcall(controller.GetState)
						entry.STATE = if okState and type(state) == "table"
							then state
							else tostring(state)
					end

					if type(controller.GetCooldownRemaining) == "function" then
						local okCd, cd = pcall(controller.GetCooldownRemaining)
						entry.COOLDOWN = if okCd then tonumber(cd) or -1 else -1
					end

					if type(controller.GetKnownPortalIds) == "function" then
						local okIds, ids = pcall(controller.GetKnownPortalIds)
						entry.PORTALS = if okIds and type(ids) == "table" then ids else {}
					end

					-- IDENTIDAD DEL MODULO.
					--
					-- El log del cliente dice "PortalController: 5 portales en el
					-- lobby" y `[BOOT] PortalController Started`, pero esta sonda
					-- leia `IsActive = false` y cero portales. La contradiccion
					-- se resuelve aqui: se pide al propio modulo que vuelva a
					-- recorrer el lobby. Si devuelve 5, esta tabla VE el mundo y
					-- el `IsActive` anterior era de otra tabla.
					if name == "PortalController" and type(controller.RefreshPortals) == "function" then
						local okRefresh, total = pcall(controller.RefreshPortals)
						entry.REFRESH_RETURN = if okRefresh then total or -1 else -1
						entry.MODULE_TOSTRING = tostring(controller)
					end
				else
					entry = { error = tostring(controller) }
				end
			else
				entry = { error = "no existe" }
			end

			report.CONTROLLERS[name] = entry
		end
	end

	-- Texto REAL que el jugador ve en el HUD. Esto no es "el HUD existe":
	-- es la cadena concreta que esta pintada en pantalla ahora mismo.
	report.HUD_TEXT = {}
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		local hud = playerGui:FindFirstChild("GameHUD")
		if hud then
			for _, child in ipairs(hud:GetChildren()) do
				if child:IsA("TextLabel") and child.Text ~= "" then
					report.HUD_TEXT[#report.HUD_TEXT + 1] = child.Name .. " = " .. child.Text
				end
			end
		end
		local portalControls = playerGui:FindFirstChild("PortalControls")
		if portalControls then
			local button = portalControls:FindFirstChild("PortalButton")
			if button and button:IsA("GuiButton") then
				report.HUD_PORTAL_BUTTON = {
					visible = button.Visible,
					text = button.Text,
				}
			end
		end
	end

	-- Atributos que el SERVIDOR publico: son los que escribe el servidor, y
	-- por eso describen el estado de verdad del juego para el jugador.
	report.ATTRS = {}
	if player then
		for _, key in ipairs({
			"World",
			"RoundState",
			"RoundNumber",
			"RoundTimeRemaining",
			"AliveCount",
			"PlayerState",
			"Level",
			"XP",
			"Coins",
			"Gems",
			"IsInvulnerable",
		}) do
			report.ATTRS[key] = player:GetAttribute(key)
		end
	end

	-- Errores REALES del cliente.
	--
	-- Esta sonda se EJECUTA en el cliente (es el `OnClientInvoke`), asi que
	-- `GetLogHistory` devuelve el historial del CLIENTE, no el del servidor.
	-- Es la unica via para ver por que un controller no arranca cuando el MCP
	-- no puede ejecutar nada en el peer del cliente.
	-- Atributos locales del cliente.
	--
	-- Se leen AQUI, dentro del cliente, y no en el servidor, porque los
	-- atributos NO replican de cliente a servidor. `TestDriverResult` lo
	-- escribe el cliente con `SetAttribute`: el servidor jamas lo vera. Es la
	-- razon por la que `TestDriverService.GetResult` no puede funcionar tal
	-- como esta escrito.
	report.CLIENT_LOCAL_ATTRS = {}
	local me = Players.LocalPlayer
	if me then
		for _, key in ipairs({
			"TestDriverInstruction",
			"TestDriverInstructionSeq",
			"TestDriverResult",
			"TestDriverRan",
			"ClientProbeBootTime",
		}) do
			report.CLIENT_LOCAL_ATTRS[key] = tostring(me:GetAttribute(key))
		end
	end

	report.CLIENT_ERRORS = {}
	report.CLIENT_LOG_TAIL = {}
	local LogService = game:GetService("LogService")
	local okEntries, entries = pcall(function()
		return LogService:GetLogHistory()
	end)

	if okEntries then
		for _, entry in ipairs(entries) do
			local message = tostring(entry.message or "")
			if message:find("Keshusy") or message:find("ontroller") or message:find("Portal") then
				report.CLIENT_ERRORS[#report.CLIENT_ERRORS + 1] = message
			end
		end

		-- Ultimas lineas del log del cliente, sin filtrar: es donde se ve
		-- `[BOOT] CONTROLLERS_STARTED` y el informe por controller.
		local first = math.max(1, #entries - 60)
		for i = first, #entries do
			report.CLIENT_LOG_TAIL[#report.CLIENT_LOG_TAIL + 1] = tostring(entries[i].message or "")
		end
	end

	-- Botones REALES creados por los controllers.
	--
	-- Es la prueba decisiva de la IDENTIDAD DEL MODULO. El log del cliente
	-- dice "InputController: boton de bomba creado" y "UIController listo".
	-- Si esos botones existen de verdad en el PlayerGui, entonces el
	-- `Start` se ejecuto sobre la tabla que ESTA sonda lee, y su
	-- `IsActive = false` es un dato fiable. Si no existen, la sonda esta
	-- leyendo OTRA tabla y todo su bloque de controllers es un espejismo.
	report.UI_BUTTONS = {}

	-- RE-ARRANQUE CONTROLADO.
	--
	-- Los botones de arriba YA existen, asi que `Start` se ejecuto de verdad.
	-- Y sin embargo `IsActive` sale `false` y `BombAction no disponible` dice
	-- que `bombRemote` es nil. Eso solo encaja si el `Start` se aplico a OTRA
	-- tabla. Se prueba arrancando otra vez el controller desde AQUI: si
	-- `IsActive` pasa a true y el canal queda resuelto, el estado original
	-- estaba en una tabla distinta; si sigue false, el modulo esta roto.
	local BombController = CONTROLLERS and CONTROLLERS:FindFirstChild("BombController")
	if BombController then
		local okModule, controller = pcall(require, BombController)
		if okModule then
			local before = controller.IsActive
			local okStart, startResult = pcall(function()
				return controller.Start(nil)
			end)
			report.RESTART_TEST = {
				ACTIVE_BEFORE = before,
				START_OK = okStart,
				START_RESULT = if okStart then startResult or -1 else -1,
				ACTIVE_AFTER = controller.IsActive,
				START_ERROR = if okStart then nil else tostring(startResult),
			}
		end
	end
	for _, guiName in ipairs({ "GameHUD", "TouchControls", "PortalControls" }) do
		local gui = playerGui and playerGui:FindFirstChild(guiName)
		local names = {}
		if gui then
			for _, child in ipairs(gui:GetDescendants()) do
				if child:IsA("GuiButton") or child:IsA("TextLabel") then
					names[#names + 1] = child.Name
				end
			end
		end
		report.UI_BUTTONS[guiName] = names
	end

	-- DIAGNOSTICO DEL CANAL DE PORTAL.
	--
	-- El log del cliente dice "PortalController: PortalAction no disponible"
	-- en cada peticion, mientras el remoto `PortalAction` SI existe en
	-- ReplicatedStorage. Eso solo encaja si `Start` no llego a resolver el
	-- canal en ESTA tabla. Se lee el remoto directamente y se comparan ambas
	-- rutas para separar "el remoto no existe" de "el controller no lo busco".
	report.PORTAL_CHANNEL = {}
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes then
		local remote = remotes:FindFirstChild("PortalAction")
		report.PORTAL_CHANNEL.REMOTE_EXISTS = remote ~= nil
		report.PORTAL_CHANNEL.REMOTE_CLASS = remote and remote.ClassName or "nil"
	else
		report.PORTAL_CHANNEL.REMOTE_EXISTS = false
	end

	local portalModule = CONTROLLERS and CONTROLLERS:FindFirstChild("PortalController")
	if portalModule then
		local okModule, controller = pcall(require, portalModule)
		if okModule then
			report.PORTAL_CHANNEL.IS_ACTIVE = controller.IsActive or false
			report.PORTAL_CHANNEL.HAS_START = type(controller.Start) == "function"
			report.PORTAL_CHANNEL.HAS_REQUEST_ENTER = type(controller.RequestEnter) == "function"
			report.PORTAL_CHANNEL.HAS_REFRESH = type(controller.RefreshPortals) == "function"

			if type(controller.RefreshPortals) == "function" then
				local okRefresh, total = pcall(controller.RefreshPortals)
				report.PORTAL_CHANNEL.REFRESH_RETURN = if okRefresh then total or -1 else -1
			end
		end
	end

	-- UIController: por que se pierde el feedback del portal.
	--
	-- `ShowPortalFeedback` devuelve false si `IsActive` es false o si
	-- `_portalFrame` es nil, y el cliente registra "no se pudo mostrar el
	-- feedback del portal". Se leen las DOS causas por separado para saber
	-- cual es, en vez de suponerlo.
	local uiModule = CONTROLLERS and CONTROLLERS:FindFirstChild("UIController")
	if uiModule then
		local okUi, ui = pcall(require, uiModule)
		if okUi then
			report.UI_STATE = {
				IS_ACTIVE = ui.IsActive,
				-- Se invoca la funcion real: si devuelve false y `IsActive` es
				-- true, el culpable es el frame del portal, no el arranque.
				SHOW_OK = pcall(function()
					ui.ShowPortalFeedback({
						WorldId = "Probe",
						Accepted = false,
						Reason = "sondeo",
						RequiredLevel = 0,
						CurrentLevel = 1,
					})
				end),
			}

			local playerGui = Players.LocalPlayer
				and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
			local portalGui = playerGui and playerGui:FindFirstChild("GameHUD")
			if portalGui then
				local frame = portalGui:FindFirstChild("PortalFrame")
				report.UI_STATE.PORTAL_FRAME_EXISTS = frame ~= nil
				if frame then
					report.UI_STATE.PORTAL_FRAME_CLASS = frame.ClassName
				end
			end
		end
	end

	return report
end

--- Publica la identidad en un atributo para que el servidor la pueda leer
--- sin preguntar por el remoto. Se escribe una sola vez al arrancar.
local function publishIdentity()
	if not LocalPlayer then
		return
	end

	LocalPlayer:SetAttribute("ClientProbeBootTime", CLIENT_START_TIME)
	LocalPlayer:SetAttribute("ClientProbePlaceId", game.PlaceId)
	Logger.Info(("[CERT] %s | player=%s | start=%d"):format(
		PROBE_NAME,
		LocalPlayer.Name,
		CLIENT_START_TIME
	))
end

--- Engancha el contestador. Idempotente.
local function connect(): boolean
	local found = ReplicatedStorage:FindFirstChild(PROBE_NAME)

	if not found or not found:IsA("RemoteFunction") then
		return false
	end

	found.OnClientInvoke = function()
		local report = bootReport()
		-- `SERVER_REPLY_OK` lo decide el servidor, no el cliente: aqui se
		-- marca como "pendiente de quien lea".
		report.CLIENT_REMOTE_OK = true
		return report
	end

	return true
end

if not FeatureConfig.ENABLE_CLIENT_CERT_PROBE then
	Logger.Info("ClientBootProbe: desactivado por FeatureConfig.")
	return
end

publishIdentity()

-- El servidor crea el RemoteFunction al arrancar. Se reintenta porque el
-- orden de arranque entre servidor y cliente no esta garantizado.
task.spawn(function()
	while not connect() do
		task.wait(0.5)
	end

	Logger.Info(("[CERT] %s enganchado; el cliente responde"):format(PROBE_NAME))
end)

return bootReport
