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

-- Marco del cartel de portal y el "token" del temporizador que lo oculta.
--
-- El token importa: sin el, dos rechazos seguidos dejarian DOS hilos
-- esperando y el primero ocultaria el cartel del segundo antes de tiempo.
local _portalFrame = nil
local _portalHideToken = nil

--- Segundos que el cartel de portal permanece en pantalla.
--
-- 3.5 s: suficiente para leer tres lineas (mundo, requisito, nivel) y lo
-- bastante corto para no quedar pegado a la pantalla si el jugador vuelve a
-- intentar enseguida.
local PORTAL_FEEDBACK_SECONDS = 3.5

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

    local function makeLabel(name, size, position, textColor, textSize)
        local label = Instance.new("TextLabel")
        label.Name = name
        label.Size = size
        label.Position = position
        label.BackgroundTransparency = 1
        label.TextColor3 = textColor
        -- `TextSize` y `TextScaled` se fijan de forma explicita: por
        -- defecto una TextLabel ajusta el texto al alto de la caja, y
        -- con cajas de 12 px el texto se hacia ilegible o se recortaba.
        label.TextSize = textSize or 18
        label.TextScaled = false
        label.Font = Enum.Font.GothamBold
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.TextYAlignment = Enum.TextYAlignment.Center
        label.TextWrapped = false
        label.Text = ""
        label.Parent = gui
        _labels[name] = label
        return label
    end

    -- Alturas de 24 px o mas: con 12 px el texto de 18 se recortaba.
    makeLabel("RoundState", UDim2.new(0, 320, 0, 24), UDim2.new(0, 16, 0, 8), Color3.fromRGB(235, 240, 255), 20)
    makeLabel("RoundInfo", UDim2.new(0, 320, 0, 24), UDim2.new(0, 16, 0, 32), Color3.fromRGB(200, 210, 235), 16)
    makeLabel("Scoreboard", UDim2.new(0, 320, 0, 24), UDim2.new(0, 16, 0, 56), Color3.fromRGB(255, 170, 170), 16)
    makeLabel("Stats", UDim2.new(0, 360, 0, 24), UDim2.new(0, 16, 1, -56), Color3.fromRGB(255, 214, 120), 16)
    makeLabel("Results", UDim2.new(0, 460, 0, 44), UDim2.new(0.5, -230, 0.42, 0), Color3.fromRGB(120, 255, 170), 24)

    -- ---------------------------------------------------------------
    -- HUD de PROGRESION (vertical slice 1)
    -- ---------------------------------------------------------------
    -- El HUD existia, pero solo mostraba Ronda, Vivos y Nivel/XP/Monedas.
    -- Faltaban HP, bombas, poder, gemas, mundo y estado, que son los datos
    -- que el jugador necesita para decidir si entrar a una ronda. Se
    -- anaden como su propia columna para no reescribir las etiquetas que ya
    -- funcionan: anadir campos al HUD existente es un cambio de texto, y
    -- cambiar su disposicion habria roto lo que ya se veia bien.
    --
    -- Todo sale de atributos del servidor. La UI no calcula nada.

    -- HP: se muestran vida y maxima. El Humanoid se lee en el cliente
    -- porque el jugador ve SU propio personaje; el valor de verdad para el
    -- juego sigue siendo el del servidor.
    local hpLabel = makeLabel(
        "HP",
        UDim2.new(0, 220, 0, 24),
        UDim2.new(0, 16, 1, -80),
        Color3.fromRGB(255, 120, 120),
        16
    )

    makeLabel(
        "Bombs",
        UDim2.new(0, 220, 0, 24),
        UDim2.new(0, 16, 1, -104),
        Color3.fromRGB(255, 200, 90),
        16
    )

    makeLabel(
        "Power",
        UDim2.new(0, 220, 0, 24),
        UDim2.new(0, 16, 1, -128),
        Color3.fromRGB(150, 200, 255),
        16
    )

    -- Mundo actual. Es el dato que responde "donde estoy" y es el primero
    -- que se mira al salir de un portal, asi que va separado y legible.
    makeLabel("World", UDim2.new(0, 320, 0, 24), UDim2.new(0, 16, 0, 80), Color3.fromRGB(180, 255, 220), 18)

    -- Gemas, junto a las monedas para que el jugador vea de un vistazo que
    -- son dos recursos distintos con funciones distintas.
    makeLabel("Gems", UDim2.new(0, 320, 0, 24), UDim2.new(0, 16, 1, -152), Color3.fromRGB(190, 140, 255), 16)

    -- ---------------------------------------------------------------
    -- Cartel de portal
    -- ---------------------------------------------------------------
    -- Es OBLIGATORIO: una interaccion de portal nunca puede ser silenciosa.
    -- Antes, un rechazo solo existia en el log del servidor, y para el
    -- jugador pulsaba un boton y no pasaba nada.
    --
    -- Se construye aqui y no en `PortalController` para que el HUD tenga
    -- un solo dueno: si cada controller crea su propio panel, acabaria
    -- haber varios textos superpuestos en el mismo sitio.
    local portalFrame = Instance.new("Frame")
    portalFrame.Name = "PortalFeedback"
    portalFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    portalFrame.Position = UDim2.new(0.5, 0, 0.5, -40)
    portalFrame.Size = UDim2.fromOffset(420, 130)
    portalFrame.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
    portalFrame.BackgroundTransparency = 0.15
    portalFrame.BorderSizePixel = 0
    portalFrame.Visible = false
    portalFrame.Parent = gui

    local portalCorner = Instance.new("UICorner")
    portalCorner.CornerRadius = UDim.new(0, 10)
    portalCorner.Parent = portalFrame

    local function makePortalLine(name, size, position, color, textSize)
        local label = Instance.new("TextLabel")
        label.Name = name
        label.Size = size
        label.Position = position
        label.BackgroundTransparency = 1
        label.TextColor3 = color
        label.TextSize = textSize
        label.TextScaled = false
        label.Font = Enum.Font.GothamBold
        label.TextXAlignment = Enum.TextXAlignment.Center
        label.TextYAlignment = Enum.TextYAlignment.Center
        label.TextWrapped = true
        label.Text = ""
        label.Parent = portalFrame
        _labels[name] = label
        return label
    end

    -- WORLD: el nombre del mundo. Es la linea mas grande porque es la
    -- pregunta que el jugador se hace ("que es esto").
    makePortalLine("PortalWorld", UDim2.new(0, 400, 0, 30), UDim2.new(0, 10, 0, 8), Color3.fromRGB(235, 240, 255), 22)
    -- LEVEL REQUIRED: el requisito del mundo.
    makePortalLine("PortalRequired", UDim2.new(0, 400, 0, 26), UDim2.new(0, 10, 0, 42), Color3.fromRGB(255, 190, 120), 18)
    -- CURRENT LEVEL: el nivel del jugador. Sin esta linea el cartel dice
    -- "requiere 10" y el jugador no sabe si le falta mucho o poco.
    makePortalLine("PortalCurrent", UDim2.new(0, 400, 0, 26), UDim2.new(0, 10, 0, 70), Color3.fromRGB(170, 200, 255), 18)
    -- MOTIVO: la razon concreta del rechazo (ronda en curso, cooldown...).
    makePortalLine("PortalReason", UDim2.new(0, 400, 0, 24), UDim2.new(0, 10, 0, 98), Color3.fromRGB(230, 230, 240), 15)

    _portalFrame = portalFrame
    _portalHideToken = nil

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
    local scoreboard = _labels.Scoreboard
    local stats = _labels.Stats
    local results = _labels.Results

    if state then
        state.Text = "Ronda: " .. tostring(player:GetAttribute("RoundState") or "Waiting")
    end

    if info then
        local remaining = player:GetAttribute("RoundTimeRemaining")

        if type(remaining) == "number" then
            -- El servidor publica tambien el numero de ronda y los
            -- vivos: el HUD los muestra, pero NO los calcula.
            info.Text = ("Ronda %d  |  Tiempo: %ds"):format(
                player:GetAttribute("RoundNumber") or 0,
                math.ceil(remaining)
            )
        else
            info.Text = ""
        end
    end

    if scoreboard then
        local alive = player:GetAttribute("AliveCount")
        scoreboard.Text = if type(alive) == "number" then ("Vivos: %d"):format(alive) else ""
    end

    if stats then
        stats.Text = ("Nivel %d  |  XP %d  |  Monedas %d"):format(
            player:GetAttribute("Level") or 1,
            player:GetAttribute("XP") or 0,
            player:GetAttribute("Coins") or 0
        )
    end

    -- ---------------------------------------------------------------
    -- Campos nuevos del HUD
    -- ---------------------------------------------------------------

    -- Gemas. Recurso aparte de las monedas: se paga con gemas, no con
    -- monedas, asi que mezclarlos en una sola cifra haria que el jugador
    -- no sepa con que puede pagar.
    local gems = _labels.Gems
    if gems then
        gems.Text = ("Gemas %d"):format(player:GetAttribute("Gems") or 0)
    end

    -- Mundo actual. Lo publica el servidor; si no hay atributo se muestra
    -- "Lobby" porque es el punto de partida y es mejor que un hueco vacio.
    local world = _labels.World
    if world then
        world.Text = ("MUNDO: %s"):format(tostring(player:GetAttribute("World") or "Lobby"))
    end

    -- HP. Se lee el Humanoid del PROPIO personaje. Es informacion de
    -- presentacion de si mismo: un cliente puede mentir en su pantalla sin
    -- El daño lo decide el servidor.
    --
    -- (Un cliente puede mentir en su propia pantalla sin ningun efecto: el
    -- daño, la muerte y la recompensa los resuelve el servidor.)
    local hp = _labels.HP
    if hp then
        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")

        if humanoid then
            hp.Text = ("HP %d / %d"):format(math.ceil(humanoid.Health), math.ceil(humanoid.MaxHealth))
        else
            hp.Text = "HP -- / --"
        end
    end

    -- Bombas: cuantas le quedan. El contador lo lleva el SERVIDOR
    -- (atributo `Bombs`); aqui solo se pinta. Si el atributo no existe
    -- todavia, se dice "ilimitadas" en vez de "0", porque 0 quiere decir
    -- "no te quedan" y ese dato no lo tenemos.
    local bombs = _labels.Bombs
    if bombs then
        local remaining = player:GetAttribute("Bombs")

        if type(remaining) == "number" then
            bombs.Text = ("BOMBAS %d"):format(remaining)
        else
            bombs.Text = "BOMBAS ∞"
        end
    end

    -- Poder del Core. Es el recurso del lobby: lo que el jugador aporta
    -- para desbloquear el mundo siguiente.
    local power = _labels.Power
    if power then
        local coreState = player:GetAttribute("CoreState")

        if coreState then
            local charge = player:GetAttribute("CoreCharge")
            power.Text = ("PODER %s%s"):format(
                tostring(coreState),
                if type(charge) == "number" then (" (%d)"):format(charge) else ""
            )
        else
            power.Text = "PODER --"
        end
    end

    if results then
        -- El servidor publica el mensaje de resultado; si no hay, se
        -- oculta. La UI no lo redacta ni lo decide.
        results.Text = tostring(player:GetAttribute("RoundResult") or "")
    end
end

--- Muestra el resultado de una interaccion con un portal.
---
--- Es la pieza que hace que NINGUNA interaccion sea silenciosa. La llama
--- `PortalController` cuando el servidor responde, y el contenido es lo
--- que el jugador pidio: MUNDO, NIVEL REQUERIDO, NIVEL ACTUAL y el motivo.
---
--- Firma (tabla, no muchos argumentos): asi anadir un dato nuevo no obliga
--- a cambiar la llamada ni a recordar el orden de los parametros.
--- @param info { WorldId: string, Accepted: boolean, Reason: string?, RequiredLevel: number?, CurrentLevel: number? }
--- @return boolean shown
function Controller.ShowPortalFeedback(info: any): boolean
    if not Controller.IsActive or not _portalFrame then
        Logger.Warn("UIController: se pidio feedback de portal sin HUD activo.")
        return false
    end

    if type(info) ~= "table" then
        return false
    end

    local accepted = info.Accepted == true
    local worldId = tostring(info.WorldId or "?")
    local required = tonumber(info.RequiredLevel) or 0
    local current = tonumber(info.CurrentLevel) or 1

    local worldLabel = _labels.PortalWorld
    local requiredLabel = _labels.PortalRequired
    local currentLabel = _labels.PortalCurrent
    local reasonLabel = _labels.PortalReason

    -- WORLD.
    if worldLabel then
        worldLabel.Text = worldId
        -- Verde si se puede entrar, ambar si esta bloqueado. El color
        -- refuerza el texto sin ser el unico portador del significado.
        worldLabel.TextColor3 = if accepted
            then Color3.fromRGB(120, 255, 170)
            else Color3.fromRGB(255, 210, 120)
    end

    -- LEVEL REQUIRED / CURRENT LEVEL.
    --
    -- Solo se escriben cuando hay un requisito real. Si el mundo no pide
    -- nivel, las dos lineas quedan vacias en vez de decir "Requires Level 0",
    -- que es informacion falsa.
    if requiredLabel then
        requiredLabel.Text = if required > 0
            then ("Requires Level %d"):format(required)
            else ""
    end

    if currentLabel then
        currentLabel.Text = if required > 0
            then ("Current Level %d"):format(current)
            else ""
    end

    -- MOTIVO.
    if reasonLabel then
        if accepted then
            reasonLabel.Text = "Entrando..."
            reasonLabel.TextColor3 = Color3.fromRGB(200, 255, 220)
        else
            reasonLabel.Text = tostring(info.Reason or "No se puede entrar ahora.")
            reasonLabel.TextColor3 = Color3.fromRGB(255, 170, 170)
        end
    end

    _portalFrame.Visible = true

    -- Reinicia el temporizador de ocultacion.
    --
    -- El token evita el fallo clasico: si el jugador pulsa dos veces, el
    -- primer temporizador ocultaria el cartel del SEGUNDO rechazo antes de
    -- que el jugador lo lea.
    _portalHideToken += 1
    local token = _portalHideToken

    task.spawn(function()
        task.wait(PORTAL_FEEDBACK_SECONDS)

        if _portalHideToken ~= token then
            return
        end

        if _portalFrame then
            _portalFrame.Visible = false
        end
    end)

    return true
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
    --
    -- `World`, `Bombs`, `Gems`, `CoreState` y `CoreCharge` se anaden con el
    -- resto: son los mismos datos, publicados por el mismo servidor. No se
    -- anade ningun canal nuevo para el HUD.
    local watched = {
        "RoundState",
        "RoundTimeRemaining",
        "RoundNumber",
        "AliveCount",
        "RoundResult",
        "Level",
        "XP",
        "Coins",
        "Gems",
        "World",
        "Bombs",
        "CoreState",
        "CoreCharge",
    }
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

    -- El cartel de portal se limpia con el HUD: `Destroy` lo hace
    -- desaparecer. Sin esto, un `Destroy` seguido de un `Start` dejaria el
    -- cartel visible y sin temporizador, y el jugador veria un mensaje
    -- congelado que ya no responde a nada.
    _portalFrame = nil
    _portalHideToken = (if _portalHideToken then _portalHideToken + 1 else 0)

    _labels = {}
    _maid = nil
    return true
end

return Controller
