--!strict
--[[
    InputController
    Lecture de entrada unificada: teclado, gamepad, touch y mouse.

    Responsabilidad real (vertical slice):
    detectar la pulsacion de "colocar bomba" y ENVIARLA al servidor por
    el canal BombAction. Nunca coloca bombas ni aplica dano: el cliente
    no es autoridad, solo envia intenciones.

    La posicion que se envia es la del personaje en ese instante. El
    servidor la vuelve a validar (distancia, ronda, cooldown), asi que
    manipularla no concede nada.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONSTANTS = SHARED:WaitForChild("Constants")
local UTILS = SHARED:WaitForChild("Utils")

local GameConstants = require(CONSTANTS:WaitForChild("GameConstants"))
local Logger = require(UTILS:WaitForChild("Logger"))

local RemoteAction = GameConstants.RemoteAction

local Controller = {}

--- Indica si el controller esta activo.
Controller.IsActive = false

-- Canal de bombas. Se resuelve una vez: si el remoto no existe, el
-- controller avisa y no se activa (fallo visible, no silencioso).
local bombRemote = nil
local _maid = nil

-- Boton tactil de bomba. Solo se crea en dispositivos con toque, y es
-- la UNICA zona de la pantalla que coloca una bomba.
local bombButton = nil

--- Peticion de colocar bomba. Se separa para poder probarla y para que
--- el registro de entrada no mezcle lectura con envio.
function Controller.RequestBombPlacement()
    local player = Players.LocalPlayer
    if not player then
        return false
    end

    local character = player.Character
    if not character then
        return false
    end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then
        return false
    end

    if not bombRemote then
        Logger.Warn("InputController: BombAction no disponible; no se pueden colocar bombas.")
        return false
    end

    -- Se envia la posicion del personaje, no la del raton: el servidor
    -- decide si es legal y por tanto no puede ser falseado.
    bombRemote:FireServer("Place", rootPart.Position)
    return true
end

--- Crea el boton tactil de bomba si el dispositivo tiene pantalla tactil.
---
--- No se crea en PC: en escritorio el teclado y el gamepad bastan, y
--- un boton flotante estorbaria. Solo se registra si HAY dispositivo
--- tactil, para no anadir un boton invisible en cada cliente.
--- @return boolean created
local function ensureBombButton(): boolean
    if bombButton then
        return true
    end

    if not UserInputService.TouchEnabled then
        return false
    end

    local player = Players.LocalPlayer

    if not player then
        return false
    end

    local playerGui = player:WaitForChild("PlayerGui", 10)

    if not playerGui then
        Logger.Warn("InputController: PlayerGui no disponible; no habra boton tactil.")
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

    -- El Maid destruye el ScreenGui completo, que incluye el boton.
    if _maid then
        _maid:Add(gui)
    end

    bombButton = button
    Logger.Info("InputController: boton tactil de bomba creado.")
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

    -- Tactil: SOLO el boton de la pantalla coloca bomba.
    --
    -- BUG CORREGIDO: antes se escuchaba `TouchTap` global, asi que
    -- CUALQUIER toque de la pantalla (abrir un menu, mover la camara,
    -- tocar un elemento de la UI) colocaba una bomba. En movil eso
    -- hacia el juego injugable y disparaba el rate limit del servidor.
    -- Ahora el toque solo cuenta si cae dentro del boton.
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
    Logger.Info("InputController listo (F / R2 / toque para colocar bomba).")

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
