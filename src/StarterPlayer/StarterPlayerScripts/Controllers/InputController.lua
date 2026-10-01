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

    -- Tactil: un toque en la pantalla coloca bomba. Es lo que permite
    -- jugar en movil sin teclado.
    connectIfActive(
        UserInputService.TouchTap,
        function()
            Controller.RequestBombPlacement()
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
    _maid = nil
    return true
end

return Controller
