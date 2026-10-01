--!strict
--[[
    UIController
    Orquestacion de pantallas de interfaz. No contiene logica de juego.

    Responsabilidad real (vertical slice):
    mostrar el estado de la ronda, el tiempo restante y la recompensa,
    leyendo UNICAMENTE atributos publicados por el servidor.

    Regla de seguridad visual: la UI NUNCA decide nada. Todo lo que
    muestra viene de `player:GetAttribute(...)`, que solo el servidor
    puede escribir. Un cliente que manipule su propia pantalla no
    cambia el juego.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local UTILS = SHARED:WaitForChild("Utils")

local Logger = require(UTILS:WaitForChild("Logger"))

local Controller = {}

--- Indica si el controller esta activo.
Controller.IsActive = false

local _gui = nil
local _labels = {}
local _maid = nil

--- Crea el HUD en PlayerGui. Se construye por codigo para no depender
--- de un .rbxm en StarterGui que habria que mantener a mano.
--- @return ScreenGui?
local function buildGui()
    local player = Players.LocalPlayer
    if not player then
        return nil
    end

    local playerGui = player:WaitForChild("PlayerGui", 10)
    if not playerGui then
        Logger.Error("UIController: PlayerGui no disponible.")
        return nil
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "GameHUD"
    gui.ResetOnSpawn = false
    -- DisplayOrder alto para que la UI no quede bajo el GUI del juego.
    gui.DisplayOrder = 10
    gui.IgnoreGuiInset = false
    gui.Parent = playerGui

    local function makeLabel(name, size, position, textColor)
        local label = Instance.new("TextLabel")
        label.Name = name
        label.Size = size
        label.Position = position
        label.BackgroundTransparency = 1
        label.TextColor3 = textColor
        label.TextSize = 18
        label.Font = Enum.Font.GothamBold
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Text = ""
        label.Parent = gui
        _labels[name] = label
        return label
    end

    makeLabel("RoundState", UDim2.new(0, 16, 0, 12), UDim2.new(0, 0, 0, 0), Color3.fromRGB(235, 240, 255))
    makeLabel("RoundInfo", UDim2.new(0, 320, 0, 36), UDim2.new(0, 16, 0, 0), Color3.fromRGB(200, 210, 235))
    makeLabel("Stats", UDim2.new(0, 320, 1, -44), UDim2.new(0, 16, 1, 0), Color3.fromRGB(255, 214, 120))
    makeLabel("Results", UDim2.new(0, 420, 0.4, 0), UDim2.new(0.5, -210, 0, 0), Color3.fromRGB(120, 255, 170))

    return gui
end

--- Refresca las etiquetas con los valores actuales.
local function refresh()
    local player = Players.LocalPlayer
    if not player then
        return
    end

    local state = _labels.RoundState
    local info = _labels.RoundInfo
    local stats = _labels.Stats
    local results = _labels.Results

    if state then
        state.Text = "Ronda: " .. tostring(player:GetAttribute("RoundState") or "Waiting")
    end

    if info then
        local remaining = player:GetAttribute("RoundTimeRemaining")
        if type(remaining) == "number" then
            info.Text = ("Tiempo: %ds"):format(math.ceil(remaining))
        else
            info.Text = ""
        end
    end

    if stats then
        stats.Text = ("Nivel %d  |  XP %d  |  Monedas %d"):format(
            player:GetAttribute("Level") or 1,
            player:GetAttribute("XP") or 0,
            player:GetAttribute("Coins") or 0
        )
    end

    if results then
        -- El servidor publica el mensaje de resultado; si no hay, se
        -- oculta. La UI no lo redacta.
        results.Text = tostring(player:GetAttribute("RoundResult") or "")
    end
end

--- Activa el controller. Debe ser idempotente y reversible con Destroy.
--- @param maid any?
--- @return boolean success
function Controller.Start(maid: any?): boolean
    if Controller.IsActive then
        return true
    end

    local player = Players.LocalPlayer
    if not player then
        Logger.Error("UIController: no hay LocalPlayer.")
        return false
    end

    _gui = buildGui()
    if not _gui then
        return false
    end

    _maid = maid

    -- Escucha SOLO atributos del servidor. Cada cambio refresca el HUD.
    local watched = { "RoundState", "RoundTimeRemaining", "RoundResult", "Level", "XP", "Coins" }
    for _, attribute in ipairs(watched) do
        if _maid then
            _maid:Connect(player:GetAttributeChangedSignal(attribute), refresh)
        end
    end

    -- Un refresco periodico cubre el temporizador, que cambia cada
    -- segundo sin disparar eventos de atributo.
    if _maid then
        _maid:Add(task.spawn(function()
            while Controller.IsActive do
                refresh()
                task.wait(1)
            end
        end))
    end

    refresh()
    Controller.IsActive = true
    Logger.Info("UIController listo.")

    return true
end

--- Desactiva el controller y elimina todas sus conexiones.
--- @return boolean success
function Controller.Destroy(): boolean
    Controller.IsActive = false

    if _gui then
        _gui:Destroy()
        _gui = nil
    end

    _labels = {}
    _maid = nil
    return true
end

return Controller
