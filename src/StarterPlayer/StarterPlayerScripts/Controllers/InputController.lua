--!strict
--[[
    InputController
    Lecture de entrada unificada: teclado, gamepad, touch y mouse.

    Responsabilidad real (vertical slice):
    traducir un evento de DISPOSITIVO a una INTENCION y entregarla al
    controller que le corresponde. No envia nada al servidor por su cuenta.

    RECONCILIACION FASE 1 REAL - division corregida
    -------------------------------------------------
    Antes este modulo resolvia `BombAction` y hacia `FireServer` por su
    cuenta, mientras `BombController` estaba vacio. Eso hacia que el
    controller de bomba no existiera como realidad y que la cadena real
    fuera:

        Tecla -> InputController -> Remote -> Servidor

    Ahora la cadena es la documentada, y el teclado, el boton tactil y el
    mando desembocan TODOS en la misma funcion:

        Dispositivo -> InputController -> BombController -> Remote -> Servidor

    Consecuencia honesta: una prueba que ejecute `BombController`
    reproduce el camino real del jugador. No es una via paralela ni un
    atajo, porque es la MISMA funcion a la que llama el teclado.

    El cliente sigue sin ser autoridad: no comprueba ronda, arena ni
    distancia. Eso lo decide `BombService` en el servidor.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONSTANTS = SHARED:WaitForChild("Constants")
local UTILS = SHARED:WaitForChild("Utils")
local CONTROLLERS = script.Parent

local GameConstants = require(CONSTANTS:WaitForChild("GameConstants"))
local Logger = require(UTILS:WaitForChild("Logger"))
local BombController = require(CONTROLLERS:WaitForChild("BombController"))

local RemoteAction = GameConstants.RemoteAction

local Controller = {}

--- Indica si el controller esta activo.
Controller.IsActive = false

-- Canal de bombas. SOLO se usa para comprobar que el canal existe al
-- arrancar y para avisar con claridad si falta. El ENVIO lo hace
-- `BombController`; mantener aqui el remoto era lo que duplicaba la
-- responsabilidad y dejaba a `BombController` sin existir.
local bombRemote = nil
local _maid = nil

-- Boton tactil de bomba. Solo se crea en dispositivos con toque, y es
-- la UNICA zona de la pantalla que coloca una bomba.
local bombButton = nil

--- Peticion de colocar bomba. Delega en `BombController`.
---
--- Se conserva el nombre `RequestBombPlacement` porque es la superficie
--- que usan el teclado, el mando, el boton tactil y el reproductor de
--- pruebas. Que todos llamen a la MISMA funcion es precisamente lo que
--- hace que la prueba signifique algo.
--- @return boolean sent
function Controller.RequestBombPlacement(): boolean
	local ok, sent = pcall(BombController.RequestPlace)

	if not ok then
		Logger.Error(("InputController: la peticion de bomba fallo: %s"):format(tostring(sent)))
		return false
	end

	return sent == true
end

--- Cooldown restante segun el controller de bomba (para el boton).
--- @return number
function Controller.GetBombCooldownRemaining(): number
	local ok, remaining = pcall(BombController.GetCooldownRemaining)

	if not ok then
		return 0
	end

	return remaining or 0
end

--- Crea el boton tactil de bomba si el dispositivo tiene pantalla tactil.
---
--- No se crea en PC: en escritorio el teclado y el gamepad bastan, y
--- un boton flotante estorbaria. Solo se registra si HAY dispositivo
--- tactil, para no anadir un boton invisible en cada cliente.
--- @return boolean created
local function ensureBombButton(): boolean
    -- El boton se crea en TODOS los dispositivos, no solo en tactiles.
    --
    -- Por que: antes el boton solo existia con `TouchEnabled`, asi que
    -- en PC el jugador no tenia ninguna forma VISIBLE de colocar una
    -- bomba aunque el teclado funcionara. Un unico boton para PC,
    -- movil y mando es menos codigo que la rama condicional, y ejecuta
    -- exactamente la misma accion en los tres casos.
    if bombButton then
        return true
    end

    local player = Players.LocalPlayer

    if not player then
        return false
    end

    local playerGui = player:WaitForChild("PlayerGui", 10)

    if not playerGui then
        Logger.Warn("InputController: PlayerGui no disponible; no habra boton de bomba.")
        return false
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "TouchControls"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 11
    gui.IgnoreGuiInset = false
    gui.Parent = playerGui

    local button = Instance.new("TextButton")
    button.Name = "BombButton"
    button.AnchorPoint = Vector2.new(1, 1)
    button.Position = UDim2.new(1, -32, 1, -32)
    button.Size = UDim2.fromOffset(96, 96)
    button.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
    button.BackgroundTransparency = 0.25
    button.BorderSizePixel = 0
    button.Text = "BOMBA"
    button.TextColor3 = Color3.fromRGB(255, 255, 255)
    button.TextSize = 18
    button.Font = Enum.Font.GothamBold
    button.AutoButtonColor = true
    button.Parent = gui

    -- `MouseButton1Click` cubre PC y el toque emulado en movil, y es la
    -- senal del PROPIO boton, no global. Por eso no puede colocar una
    -- bomba al abrir un menu o al mover la camara, que fue exactamente
    -- el bug que corrigio el `TouchTap` global.
    button.MouseButton1Click:Connect(function()
        Controller.RequestBombPlacement()
    end)

    -- El Maid destruye el ScreenGui completo, que incluye el boton.
    if _maid then
        _maid:Add(gui)
    end

    bombButton = button
    Logger.Info("InputController: boton de bomba creado.")
    return true
end

--- Refresca el boton: lo atenua y muestra el cooldown restante.
---
--- Convierte el cooldown en algo VISIBLE. Sin esto el boton acepta el
--- toque, el controller lo frena en silencio y el jugador no entiende
--- por que no ocurre nada, que es indistinguible de un boton roto.
local function refreshBombButton(): boolean
    if not bombButton or not bombButton.Parent then
        return false
    end

    local remaining = Controller.GetBombCooldownRemaining()

    if remaining > 0 then
        bombButton.BackgroundTransparency = 0.6
        bombButton.Text = ("%.1fs"):format(remaining)
        bombButton.AutoButtonColor = false
    else
        bombButton.BackgroundTransparency = 0.25
        bombButton.Text = "BOMBA"
        bombButton.AutoButtonColor = true
    end

    return true
end

--- Activa el controller. Debe ser idempotente y reversible con Destroy.
--- @return boolean success
function Controller.Start(maid: any?): boolean
    if Controller.IsActive then
        return true
    end

    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    local remote = remotes:FindFirstChild(RemoteAction.Bomb)

    if not remote or not remote:IsA("RemoteEvent") then
        Logger.Error("InputController: ReplicatedStorage.Remotes." .. RemoteAction.Bomb .. " no existe.")
        return false
    end

    bombRemote = remote
    _maid = maid

    -- El boton se crea ANTES de conectar los eventos: el handler
    -- tactil lo consulta y debe existir cuando llegue el primer toque.
    ensureBombButton()

    local function connectIfActive(signal: any, handler: (...any) -> ())
        if _maid then
            _maid:Connect(signal, handler)
        end
    end

    -- `InputBegan` es un unico evento y el juego ya traduce el gamepad
    -- a KeyCode, asi que teclado y mando se resuelven juntos.
    connectIfActive(
        UserInputService.InputBegan,
        function(input: any, gameProcessed: boolean)
            if gameProcessed then
                return
            end

            local isBombKey = input.KeyCode == Enum.KeyCode.F
                or input.KeyCode == Enum.KeyCode.ButtonR2

            if isBombKey then
                Controller.RequestBombPlacement()
            end
        end
    )

    -- Tactil: RESERVA, no via principal.
    --
    -- El boton tiene su propio `MouseButton1Click`, que ya cubre movil.
    -- Este `TouchTap` se conserva unicamente como respaldo por si el
    -- motor no entrega el toque al boton, y por eso se exige que el
    -- punto caiga DENTRO del boton.
    --
    -- BUG CORREGIDO antes: se escuchaba `TouchTap` global sin mirar el
    -- boton, de modo que CUALQUIER toque (abrir un menu, mover la
    -- camara, tocar la UI) colocaba una bomba. En eso el juego era
    -- injugable y ademas se disparaba el rate limit del servidor.
    connectIfActive(
        UserInputService.TouchTap,
        function(touchPositions: any, gameProcessed: boolean)
            -- `gameProcessed` es true cuando el toque lo consumio la UI.
            if gameProcessed then
                return
            end

            if not bombButton then
                return
            end

            local touch = touchPositions and touchPositions[1]

            if not touch then
                return
            end

            local point = touch.Position
            local buttonPos = bombButton.AbsolutePosition
            local buttonSize = bombButton.AbsoluteSize

            local inside =
                point.X >= buttonPos.X
                and point.X <= buttonPos.X + buttonSize.X
                and point.Y >= buttonPos.Y
                and point.Y <= buttonPos.Y + buttonSize.Y

            if inside then
                Controller.RequestBombPlacement()
            end
        end
    )

    Controller.IsActive = true

    -- Refresco del cooldown del boton. El intervalo es de 100 ms:
    -- bastante fino para que el contador no parezca congelado y bastante
    -- grueso para no poner un RenderStepped por frame en cada cliente.
    --
    -- El bucle se lanza DESPUES de activar `IsActive` a proposito: si se
    -- lanzara antes, la condicion `while IsActive` seria falsa en la
    -- primera vuelta y el hilo terminaria sin refresher nunca.
    task.spawn(function()
        while Controller.IsActive do
            refreshBombButton()
            task.wait(0.1)
        end
    end)

    Logger.Info("InputController listo (F / R2 / boton o toque para colocar bomba).")

    return true
end

--- Desactiva el controller y elimina todas sus conexiones.
--- @return boolean success
function Controller.Destroy(): boolean
    Controller.IsActive = false
    bombRemote = nil
    bombButton = nil
    _maid = nil
    return true
end

return Controller
