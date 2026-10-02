--!strict
--[[
    PortalController
    UNICA puerta del cliente para pedir entrar a un mundo.

    POR QUE ESTE ARCHIVO EXISTE Y QUE NO DEBE HACER
    -----------------------------------------------
    Este modulo estaba en 25 lineas de stub y por eso el vertical slice 1
    no tenia LOBBY -> PORTAL: habia cinco portales en el mapa y ninguna
    manera de usarlos. Ahora el camino real es:

        Jugador (E / X / boton)
            -> PortalController
            -> PortalAction:FireServer("Enter", worldId)
            -> RemoteGateway (valida forma + frecuencia)
            -> PortalService.TryEnter (nivel, portal, ronda, distancia)
            -> MatchService.MovePlayer (teleport del SERVIDOR)
            -> veredicto por el mismo canal

    REGLAS QUE NO SE ROMPEN
    -----------------------
    1. NUNCA se llama a `PortalService` desde el cliente. No existe en el
       cliente y no debe buscarse: el unico camino es el remoto.
    2. El cliente NO decide si el viaje es legal. Solo pide. El servidor
       responde con `accepted` y `reason`.
    3. Una interaccion NUNCA es silenciosa. Si el servidor rechaza, se
       muestra el motivo ("requiere nivel 10", "hay una ronda en curso").

    NOTA SOBRE RENDIMIENTO
    ----------------------
    Los portales se detectan por proximidad al UMBRAL (`PortalPanel`), no por
    el modelo entero, y se recorren con un latido de 10 Hz en vez de un
    `RenderStepped`. Un `GetDescendants` por frame sobre el lobby seria
    desperdicio: el lobby no cambia entre frames.

    INTERFAZ QUE CONSUME
    --------------------
    `UIController.ShowPortalFeedback(...)` muestra el cartel de mundo
    bloqueado. Este controller NO crea su propia UI de texto: asi el HUD
    tiene UN solo dueno y no se duplican los paneles.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONSTANTS = SHARED:WaitForChild("Constants")
local CONFIG = SHARED:WaitForChild("Config")
local UTILS = SHARED:WaitForChild("Utils")
local CONTROLLERS = script.Parent

local GameConstants = require(CONSTANTS:WaitForChild("GameConstants"))
local GameConfig = require(CONFIG:WaitForChild("GameConfig"))
local Logger = require(UTILS:WaitForChild("Logger"))
local UIController = require(CONTROLLERS:WaitForChild("UIController"))

local RemoteAction = GameConstants.RemoteAction

local Controller = {}

--- Indica si el controller esta activo.
Controller.IsActive = false

-- Canal de portales, resuelto una sola vez.
local portalRemote = nil

-- Instante del ultimo intento local (evita el spam antes de que el
-- servidor rechace). NO concede nada: solo evita 10 pulsaciones por segundo.
local _lastRequestAt = 0

-- Mundo para el que se pidio el viaje y cuando. Permite ignorar el
-- veredicto de un portal al que el jugador ya se alejo.
local _pendingWorld = nil
local _pendingSince = 0

-- PortalCache: worldId -> { Instance, Threshold, Position }
local _portals = {}

-- Portal cercano actual (o nil).
local _nearby = nil

local _interactButton = nil
local _maid = nil

--- Segundos que faltan para poder volver a pedir.
--- @return number
function Controller.GetCooldownRemaining(): number
	local elapsed = os.clock() - _lastRequestAt
	local remaining = GameConfig.PortalCooldown - elapsed
	return remaining > 0 and remaining or 0
end

--- Indica si se puede enviar una peticion ahora.
--- @return boolean
function Controller.CanRequest(): boolean
	if _pendingWorld ~= nil then
		return false
	end
	return Controller.GetCooldownRemaining() <= 0
end

--- La parte que ACTUA como umbral. Mismo criterio que `PortalService`:
--- el panel es la hoja central; la base esta en el suelo y el dintel en el
--- techo, y usar cualquiera de las otras daria un error de varios studs que
--- haria fallar la proximidad de forma siempre correcta pero inutil.
--- @param portal Model
--- @return BasePart?
local function findThreshold(portal: Model): BasePart?
	for _, candidate in ipairs({ "PortalPanel", "Panel", "Threshold" }) do
		local part = portal:FindFirstChild(candidate)
		if part and part:IsA("BasePart") then
			return part :: BasePart
		end
	end
	return nil
end
-- CONTINUA_EN_PARTE_2
--- Recorre el lobby y cachea los portales para la deteccion por proximidad.
---
--- Solo se usa para SABER que hay ahi y cuanto se esta de lejos. La
--- decision de viaje la toma el servidor con su propia lista.
--- @return number total
function Controller.RefreshPortals(): number
	_portals = {}

	local lobby = workspace:FindFirstChild("Lobby")
	if not lobby then
		return 0
	end

	for _, instance in ipairs(lobby:GetDescendants()) do
		local worldId = string.match(instance.Name, "^Portal_(.+)$")

		if worldId and instance:IsA("Model") then
			local panel = findThreshold(instance :: Model)
			if panel then
				_portals[worldId] = {
					Instance = instance,
					Threshold = panel,
					Position = panel.Position,
				}
			else
				Logger.Warn(("portal '%s' sin umbral; el cliente lo ignora."):format(worldId))
			end
		end
	end

	local total = 0
	for _ in pairs(_portals) do
		total += 1
	end
	return total
end

--- Portales que el cliente ha cacheado, ordenados.
--- @return { string }
function Controller.GetKnownPortalIds(): { string }
	local ids = {}
	for worldId in pairs(_portals) do
		table.insert(ids, worldId)
	end
	table.sort(ids)
	return ids
end

--- Portal mas cercano dentro del rango de interaccion.
---
--- Se usa el UMBRAL y no el modelo: el modelo incluye suelo y marco, y su
--- pivote puede estar lejos del jugador que esta de pie "dentro" del portal.
--- @return string? worldId
--- @return number distance
function Controller.FindNearbyPortal(): (string?, number)
	local player = Players.LocalPlayer
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")

	if not root then
		return nil, math.huge
	end

	local bestId, bestDistance = nil, math.huge
	local position = (root :: BasePart).Position

	for worldId, entry in pairs(_portals) do
		local distance = (position - entry.Position).Magnitude
		if distance < bestDistance then
			bestId, bestDistance = worldId, distance
		end
	end

	-- `PortalInteractionRange` es generosamente mayor que el rango del
	-- servidor a proposito: el cliente ofrece la interaccion un poco antes
	-- y es el servidor el que aplica su limite mas estricto. Asi el jugador
	-- nunca pulsa dentro del rango y ve como se rechaza sin motivo claro.
	if bestDistance and bestDistance <= GameConfig.PortalInteractionRange then
		return bestId, bestDistance
	end

	return nil, math.huge
end

--- Nivel actual publicado por el servidor.
---
--- Se lee del ATRIBUTO, no de nada local: lo escribe el servidor. Sirve
--- solo para ENSEÑAR el nivel actual en el cartel de bloqueo; la
--- comparacion real la hace `PortalService` con la sesion del servidor.
--- @return number
function Controller.GetDisplayedLevel(): number
	local player = Players.LocalPlayer
--- Envia la peticion de viaje. Es lo UNICO que el cliente pide.
--- @param worldId string
--- @return boolean sent
function Controller.RequestEnter(worldId: string): boolean
	if not portalRemote then
		Logger.Warn("PortalController: PortalAction no disponible.")
		return false
	end

	if type(worldId) ~= "string" or worldId == "" then
		return false
	end

	-- El portal tiene que existir de verdad en el mapa. No es una decision
	-- de seguridad (la toma el servidor) sino de honestidad de la interfaz:
	-- no se ofrece un boton para un portal que no esta.
	if not _portals[worldId] then
		return false
	end

	if not Controller.CanRequest() then
		return false
	end

	_lastRequestAt = os.clock()
	_pendingWorld = worldId
	_pendingSince = os.clock()

	-- Solo el NOMBRE del mundo. Nunca una posicion: el destino lo elige
	-- el servidor a partir de sus propios marcadores.
	portalRemote:FireServer("Enter", worldId)
	return true
end

--- Pide entrar al portal que tiene delante. Lo llama `InputController`.
--- @return boolean sent
function Controller.RequestEnterNearby(): boolean
	local worldId = _nearby
	if not worldId then
		return false
	end
	return Controller.RequestEnter(worldId)
end

--- Traduce el motivo del servidor al texto que ve el jugador.
---
--- El servidor manda motivos legibles y ya estables; aqui solo se evita
--- que un motivo desconocido se muestre crudo al jugador.
--- @param reason string?
--- @return string
local function humanizeReason(reason: string?): string
	if type(reason) ~= "string" or reason == "" then
		return "No se puede entrar ahora."
	end
	return reason
end

--- Muestra el cartel de un portal bloqueado o disponible.
--- @param worldId string
--- @param accepted boolean
--- @param reason string?
--- @param requiredLevel number?
--- @return boolean shown
local function showFeedback(worldId, accepted, reason, requiredLevel): boolean
	local ok = pcall(UIController.ShowPortalFeedback, {
		WorldId = worldId,
		Accepted = accepted,
		Reason = reason,
		RequiredLevel = requiredLevel or 0,
		CurrentLevel = Controller.GetDisplayedLevel(),
	})

	if not ok then
		-- Un cartel que falla NO puede tumbar el controller: el jugador
		-- perderia la interaccion por un error de presentacion.
		Logger.Error("PortalController: no se pudo mostrar el feedback del portal.")
		return false
	end

	return true
end

--- Recepcion del veredicto del servidor.
---
--- Llega por el MISMO `PortalAction`: un canal bidireccional, sin anadir
--- un remoto nuevo para una sola respuesta.
local function onServerVerdict(
	_worldId: string,
	_accepted: boolean,
	_reason: string?,
	_requiredLevel: number?
)
	-- El servidor podria responder a una peticion vieja si el jugador ya
	-- se movio. Se ignora: un cartel de un portal al que ya no estas es
	-- peor que no mostrarlo.
	if _pendingWorld ~= nil and _worldId ~= _pendingWorld then
		return
	end

	_pendingWorld = nil
	showFeedback(_worldId, _accepted == true, humanizeReason(_reason), _requiredLevel)
end

--- Refresca el portal cercano y el boton de interaccion.
local function updateNearby()
	local worldId, distance = Controller.FindNearbyPortal()
	_nearby = worldId

	if not _interactButton or not _interactButton.Parent then
		return
	end

	if not worldId then
		_interactButton.Visible = false
		return
	end

	_interactButton.Visible = true
	-- Distancia con unidades: el jugador ve que se acerca al umbral.
	_interactButton.Text = ("ENTRAR\n%s · %.0f studs"):format(worldId, distance)
end
--- Crea el boton de interaccion de portal.
---
--- Se crea SIEMPRE (no solo en tactil) por el mismo motivo que el boton de
--- bomba: en PC el jugador necesita una forma VISIBLE de interactuar, no
--- solo una tecla que no aparece en pantalla.
--- @return boolean created
local function ensureInteractButton(): boolean
	if _interactButton then
		return true
	end

	local player = Players.LocalPlayer
	if not player then
		return false
	end

	local playerGui = player:WaitForChild("PlayerGui", 10)
	if not playerGui then
		Logger.Warn("PortalController: PlayerGui no disponible; no habra boton de portal.")
		return false
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "PortalControls"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 12
	gui.Parent = playerGui

	local button = Instance.new("TextButton")
	button.Name = "PortalButton"
	button.AnchorPoint = Vector2.new(1, 0.5)
	-- Centro derecho: encima del boton de bomba (abajo a la derecha). Los
	-- dos controles no se tapan en ninguna resolucion de las del corte.
	button.Position = UDim2.new(1, -32, 0.5, 0)
	button.Size = UDim2.fromOffset(190, 72)
	button.BackgroundColor3 = Color3.fromRGB(70, 120, 220)
	button.BackgroundTransparency = 0.2
	button.BorderSizePixel = 0
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.TextSize = 15
	button.Font = Enum.Font.GothamBold
	button.TextWrapped = true
	button.Visible = false
	button.Text = "ENTRAR"
	button.Parent = gui

	button.MouseButton1Click:Connect(function()
		Controller.RequestEnterNearby()
	end)

	if _maid then
		_maid:Add(gui)
	end

	_interactButton = button
	return true
end
--- Activa el controller. Debe ser idempotente y reversible con Destroy.
--- @param maid any? Maid del registro de controllers.
--- @return boolean success
function Controller.Start(maid: any?): boolean
	if Controller.IsActive then
		return true
	end

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local remote = remotes:FindFirstChild(RemoteAction.Portal)

	if not remote or not remote:IsA("RemoteEvent") then
		Logger.Error("PortalController: ReplicatedStorage.Remotes." .. RemoteAction.Portal .. " no existe.")
		return false
	end

	portalRemote = remote
	_maid = maid
	_lastRequestAt = 0
	_pendingWorld = nil
	_nearby = nil

	local found = Controller.RefreshPortals()

	if found == 0 then
		-- Sin portales el lobby es un pasillo. Se avisa con claridad
		-- porque es un fallo de MAPA, no del controller.
		Logger.Error("PortalController: no hay portales en Workspace.Lobby; el lobby no tiene salidas.")
	else
		Logger.Info(("PortalController: %d portales en el lobby."):format(found))
	end

	ensureInteractButton()

	-- Veredicto del servidor por el mismo `PortalAction`.
	if _maid then
		_maid:Connect(portalRemote.OnClientEvent, function(
			action: any,
			worldId: any,
			accepted: any,
			reason: any,
			requiredLevel: any
		)
			if action ~= "Result" or typeof(worldId) ~= "string" then
				return
			end

			onServerVerdict(
				worldId,
				accepted == true,
				if typeof(reason) == "string" then reason else nil,
				if typeof(requiredLevel) == "number" then requiredLevel else nil
			)
		end)
	end

	-- Tecla de interaccion. Se escucha `InputBegan`, la MISMA senal que
	-- usa `InputController` para la bomba: el jugador no aprende dos
	-- mecanismos distintos. `E` y `ButtonX` cubren teclado y mando; en
	-- movil entra el boton.
	if _maid then
		_maid:Connect(UserInputService.InputBegan, function(input: any, gameProcessed: boolean)
			if gameProcessed then
				return
			end

			local isInteractKey = input.KeyCode == Enum.KeyCode.E
				or input.KeyCode == Enum.KeyCode.ButtonX

			if isInteractKey then
				Controller.RequestEnterNearby()
			end
		end)
	end

	-- Latido de proximidad a 10 Hz.
	--
	-- 10 Hz es suficiente: el jugador no nota el retardo de un cartel que
	-- aparece a 100 ms, y evita recorrer los portales en cada frame.
	local accumulator = 0
	local INTERVAL = 0.1

	if _maid then
		_maid:Connect(RunService.Heartbeat, function(deltaTime: number)
			accumulator += deltaTime
			if accumulator < INTERVAL then
				return
			end
			accumulator = 0
			updateNearby()
		end)
	end

	-- El mapa puede cambiar en caliente (un mundo recien habilitado), asi
	-- que la cache se refresca periodicamente. Cada 5 s es barato.
	if _maid then
		_maid:Add(task.spawn(function()
			while Controller.IsActive do
				task.wait(5)
				if Controller.IsActive then
					Controller.RefreshPortals()
				end
			end
		end))
	end

	-- Una peticion que el servidor nunca respondio no debe dejar el
	-- controller bloqueado para siempre. 5 s es una red de seguridad, no el
	-- mecanismo normal: normalmente el veredicto llega en milisegundos.
	if _maid then
		_maid:Add(task.spawn(function()
			while Controller.IsActive do
				task.wait(1)
				if _pendingWorld ~= nil and (os.clock() - _pendingSince) > 5 then
					local world = _pendingWorld
					_pendingWorld = nil
					showFeedback(world, false, "El servidor no respondio. Intentalo de nuevo.", 0)
				end
			end
		end))
	end

	Controller.IsActive = true
	updateNearby()

	Logger.Info("PortalController listo (E / X / boton para entrar a un portal).")
	return true
end

--- Desactiva el controller y libera sus referencias.
--- @return boolean success
function Controller.Destroy(): boolean
	Controller.IsActive = false
	portalRemote = nil
	_interactButton = nil
	_nearby = nil
	_pendingWorld = nil
	_portals = {}
	_maid = nil
	return true
end

return Controller
	if not player then
		return 1
	end

	local level = player:GetAttribute("Level")
	return type(level) == "number" and level or 1
end
-- CONTINUA_EN_PARTE_3
