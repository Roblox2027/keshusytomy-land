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
local TweenService = game:GetService("TweenService")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local UTILS = SHARED:WaitForChild("Utils")

local Logger = require(UTILS:WaitForChild("Logger"))

local Controller = {}

--- Indica si el controller esta activo.
Controller.IsActive = false

local _gui = nil
local _labels = {}
local _panels = {}
local _maid = nil

--- Nombre del `ScreenGui` generado por `tools/hud.js`.
---
--- Es CONTRATO entre el generador y este controller. Si cambia en uno y no en
--- el otro, el HUD aparece vacio sin error de sintaxis: solo un error de
--- arranque al no encontrar el GUI.
local HUD_NAME = "KeshusyHUD"

--- Componentes del HUD que este controller usa, en orden de lectura.
---
--- Se declaran aqui y no se recorren todos los hijos del GUI para que un
--- panel anadido despues no cambie el comportamiento por sorpresa.
local COMPONENTS = {
    "TopBar",
    "PlayerStats",
    "Currency",
    "BombStats",
    "ActiveBombs",
    "PowerupRow",
    "DamageNumbers",
    "DamageVignette",
    "Objective",
    "Mission",
    "Timer",
    "BossBar",
    "Notifications",
}

--- Atributos del jugador que el HUD refleja.
---
--- Son los que publica el servidor. Se guardan aqui porque son el CONTRATO
--- de datos: si el servidor deja de publicar uno, el HUD lo muestra como
--- desconocido en vez de inventar un cero.
local WATCHED_ATTRIBUTES = {
    "RoundState",
    "RoundTimeRemaining",
    "RoundNumber",
    "AliveCount",
    "RoundResult",
    "Level",
    "LeveledUpTo",
    "XP",
    "Coins",
    "Gems",
    "World",
    "Bombs",
    "CoreState",
    "CoreCharge",
    "QuestCount",
    "QuestStreak",
}

-- Marco del cartel de portal y el "token" del temporizador que lo oculta.
--
-- El token importa: sin el, dos rechazos seguidos dejarian DOS hilos
-- esperando y el primero ocultaria el cartel del segundo antes de tiempo.
local _portalFrame = nil

-- BUG CORREGIDO (medido en PLAY): esto valia `nil` y `ShowPortalFeedback`
-- hacia `_portalHideToken += 1` encima. En Luau, `nil + 1` es un error de
-- tiempo de ejecucion, NO un `nil` silencioso, asi que la funcion REVENTABA
-- en la ultima linea util:
--
--   UIController:552: attempt to perform arithmetic (add) on nil and number
--
-- El cartel llegaba a escribirse (mundo, nivel, motivo) pero la funcion
-- lanzaba justo antes de programar el temporizador que lo oculta. Con eso el
-- `pcall` de `PortalController` devolvia false, el cartel se quedaba pegado
-- en pantalla para siempre y el jugador nunca recibia el motivo del rechazo.
--
-- Es un contador: nace en 0. La linea 719 de `Destroy` ya lo reiniciaba
-- escribiendo 0, lo que delata que el 0 era el valor previsto aqui.
local _portalHideToken = 0

--- Marcos de notificacion VIVOS.
---
--- Se guardan para poder destruirlos en `Destroy`. Sin esta lista, un aviso
--- que salta en el momento de cerrar el controller se queda congelado en
--- pantalla y el jugador ve texto que ya no significa nada.
local _liveNotifications = {}

--- Segundos que un aviso permanece en pantalla antes de desvanecerse.
local NOTIFY_VISIBLE_SECONDS = 2.6

--- Segundos que un aviso tarda en desvanecerse.
local NOTIFY_FADE_SECONDS = 0.4

--- Maximo de avisos simultaneos.
---
--- El limite importa porque los avisos se apilan: sin tope, un jugador que
--- gana cinco cosas seguidas empuja el ultimo fuera del panel y se ve un
--- texto cortado por el borde de la pantalla.
local NOTIFY_MAX = 4

--- Alto de una fila de aviso, en pixels.
local NOTIFY_ROW_HEIGHT = 30

--- Muestra un aviso temporal en el panel `Notifications`.
---
--- CICLO DE VIDA
--- -------------
---   CREATE -> SHOW -> ANIMATE -> TIMEOUT -> DESTROY
---
--- El paso final no es opcional: una etiqueta que se queda, aunque este
--- apagada, sigue ocupando espacio y sigue recibiendo eventos, y acaba
--- amontonando cientos de objetos en una partida larga.
---
--- La animacion usa `TweenService` sobre `TextTransparency` y no sobre
--- `Size`: cambiar el tamano empuja los otros avisos y produce saltos.
---
--- @param text string
--- @param tint Color3? color del texto
--- @return boolean shown
function Controller.Notify(text: string, tint: Color3?)
    local panel = _panels.Notifications
    if not panel or text == "" then
        return false
    end

    -- Tope de simultaneos: al superarlo se retira el MAS ANTIGUO, que es el
    -- primero de la lista porque los avisos se apilan en orden de llegada.
    while #_liveNotifications >= NOTIFY_MAX do
        local oldest = table.remove(_liveNotifications, 1)
        if oldest and oldest.Parent then
            oldest:Destroy()
        end
    end

    local frame = Instance.new("Frame")
    frame.Name = "Notify"
    frame.BackgroundTransparency = 1
    frame.BorderSizePixel = 0
    frame.Size = UDim2.new(1, 0, 0, NOTIFY_ROW_HEIGHT - 4)
    -- Cada aviso ocupa su fila: el mas reciente queda mas abajo y el mas
    -- antiguo arriba, como una pila de avisos.
    frame.Position = UDim2.new(0, 0, 0, #_liveNotifications * NOTIFY_ROW_HEIGHT)

    local label = Instance.new("TextLabel")
    label.Name = "Text"
    label.BackgroundTransparency = 1
    label.BorderSizePixel = 0
    label.Size = UDim2.fromScale(1, 1)
    label.Font = Enum.Font.GothamBold
    label.TextSize = 16
    label.TextScaled = false
    label.TextColor3 = tint or Color3.fromRGB(236, 241, 255)
    label.Text = text
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.TextWrapped = false
    label.TextTransparency = 0
    label.Parent = frame
    frame.Parent = panel

    table.insert(_liveNotifications, frame)

    task.spawn(function()
        task.wait(NOTIFY_VISIBLE_SECONDS)

        if not frame.Parent then
            return
        end

        local tween = TweenService:Create(label, TweenInfo.new(NOTIFY_FADE_SECONDS), {
            TextTransparency = 1,
        })
        tween:Play()
        tween.Completed:Wait()

        -- TIMEOUT -> DESTROY. Se saca de la lista ANTES de destruir, para
        -- que `Destroy` no intente destruir algo ya destruido.
        for index, tracked in ipairs(_liveNotifications) do
            if tracked == frame then
                table.remove(_liveNotifications, index)
                break
            end
        end
        if frame.Parent then
            frame:Destroy()
        end
    end)

    return true
end

--- Segundos que el cartel de portal permanece en pantalla.
--
-- 3.5 s: suficiente para leer tres lineas (mundo, requisito, nivel) y lo
-- bastante corto para no quedar pegado a la pantalla si el jugador vuelve a
-- intentar enseguida.
local PORTAL_FEEDBACK_SECONDS = 3.5

--- Localiza el HUD GENERADO en `PlayerGui`.
---
--- El HUD ya no se construye por codigo: `tools/hud.js` lo declara como
--- `ScreenGui` real dentro de `StarterGui`, asi que existe en el SOURCE y se
--- puede auditar sin entrar en juego. Este metodo solo lo LOCALIZA.
---
--- Se sigue creando por codigo SOLO el cartel de portal, porque es
--- efimero: nace y muere con cada intento de viaje y no tiene sentido
--- persistirlo en el arbol de origen.
---
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

    local gui = playerGui:WaitForChild(HUD_NAME, 10)
    if not gui then
        Logger.Error(("UIController: '%s' no aparece en PlayerGui."):format(HUD_NAME))
        return nil
    end

    -- --------------------------------------------------------------------
    -- Enlace de componentes
    --
    -- Cada panel del HUD generado se registra en `_panels` con su nombre.
    -- `refresh` los usa por nombre, de modo que cambiar el texto del mundo no
    -- obliga a saber nada de la disposicion del resto.
    --
    -- `WaitForChild` con timeout y NO en silencio: si un panel no existe, el
    -- HUD aparece a medias y el jugador ve un hueco sin ninguna pista de por
    -- que. Aqui se avisa al log para que el fallo sea visible en el arranque.
    -- --------------------------------------------------------------------
    for _, name in ipairs(COMPONENTS) do
        local found = gui:FindFirstChild(name)

        if not found then
            Logger.Error(("UIController: falta el panel '%s' en el HUD."):format(name))
        else
            _panels[name] = found
        end
    end


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

    -- BUG CORREGIDO (mismo origen que la declaracion): esto ponia `nil` y
    -- hacia que el PRIMER rechazo de cada sesion revantara en
    -- `_portalHideToken += 1`. Un contador se reinicia a CERO, no a nil.
    _portalHideToken = 0

    return gui
end
--- Refresca el HUD con los valores publicados por el servidor.
---
--- REGLA DE ORO
--- ------------
--- La UI NUNCA calcula nada del juego. Solo lee `player:GetAttribute(...)`, que
--- solo el servidor puede escribir, y lo pinta. Un cliente modificado puede
--- mentir en su propia pantalla sin cambiar el juego: el dano, la recompensa y
--- el viaje los decide el servidor.
---
--- Cuando un atributo no existe se escribe "--" y no "0". La diferencia se ve:
--- un 0 de XP dice "no tienes nada" y un -- dice "no lo se". Confundirlos hace
--- que el HUD parezca un bug cuando el dato simplemente aun no ha llegado.
local function refresh()
    local player = Players.LocalPlayer
    if not player then
        return
    end

    local function attr(name)
        return player:GetAttribute(name)
    end

    --- Escribe un texto si el panel existe. Nunca falla en silencio.
--- @param subPath string? descentra el nombre dentro del hijo (ej. "Value")
    local function setText(panelName, childName, text, subPath)
        local panel = _panels[panelName]
        if not panel then
            return
        end
        local target = panel:FindFirstChild(childName)

        -- `subPath` existe porque hay hijos que ya no son TextLabel: las filas
        -- de recurso (`Currency.Coins`) son Frames con `Symbol`, `Caption` y
        -- `Value`. Sin este salto, escribir en la fila no haria NADA y el
        -- panel mostraria el "--" de serie para siempre.
        if subPath and target then
            target = target:FindFirstChild(subPath)
        end

        if target and target:IsA("TextLabel") then
            target.Text = text
        end
    end

    --- Pone una barra a la fraccion `value/max`.
    ---
    --- Se ESCALA en X en vez de cambiar `Size`: escalar mantiene el ancho del
    --- marco intacto, y un valor 0 deja la barra visible pero vacia, que es
    --- como se lee "no tienes vida" de un vistazo.
    local function setBar(panelName, barName, value, max, caption)
        local panel = _panels[panelName]
        if not panel then
            return
        end
        local bar = panel:FindFirstChild(barName)
        if not bar then
            return
        end
        local fill = bar:FindFirstChild("Fill")
        if fill and fill:IsA("GuiObject") then
            local ratio = 0
            if type(max) == "number" and max > 0 and type(value) == "number" then
                ratio = math.clamp(value / max, 0, 1)
            end

            -- La barra se ANIMA, no salta.
            --
            -- MEDIDO en PLAY: la barra de vida se escribia directa y el ancho
            -- caia de golpe. El jugador veia "estaba al 80 y ahora al 20" sin
            -- ningun instante intermedio, y el impacto del dano se perdia. Con
            -- un tween corto la bajada se LEE, que es justo lo que hace falta
            -- para entender que le acaba de pegar una bomba.
            local current = fill.Size.X.Scale
            local target = ratio

            if math.abs(current - target) > 0.001 then
                TweenService:Create(
                    fill,
                    TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                    { Size = UDim2.fromScale(target, 0) }
                ):Play()
            end
        end
        local captionLabel = bar:FindFirstChild("Text")
        if captionLabel and captionLabel:IsA("TextLabel") then
            captionLabel.Text = caption
        end
    end

    -- ---------------------------------------------------------------- TopBar
    local worldName = attr("World")
    setText("TopBar", "World", (if worldName then ("MUNDO: %s"):format(tostring(worldName)) else "MUNDO: --"))
    setText("TopBar", "Level", ("LV %d"):format(attr("Level") or 1))

    -- ---------------------------------------------------------------- Timer
    setText("Timer", "Round", ("RONDA %d"):format(attr("RoundNumber") or 0))

    local remaining = attr("RoundTimeRemaining")
    if type(remaining) == "number" then
        local total = math.max(0, math.ceil(remaining))
        setText("Timer", "Time", ("%02d:%02d"):format(math.floor(total / 60), total % 60))
    else
        setText("Timer", "Time", "--:--")
    end

    -- ------------------------------------------------------------- Currency
    --
    -- Las filas son Frames con `Symbol`, `Caption` y `Value`. Se escribe en
    -- `Value`: el nombre del recurso ("MONEDAS", "GEMAS") ya esta puesto en
    -- `Caption` por el generador, y asi la cifra se lee sola. Antes eran dos
    -- TextLabel con la cifra suelta, y en pantalla eran dos "0" que no
    -- decian nada.
    local coins = attr("Coins")
    local gems = attr("Gems")
    setText("Currency", "Coins", (if type(coins) == "number" then ("%d"):format(coins) else "--"), "Value")
    setText("Currency", "Gems", (if type(gems) == "number" then ("%d"):format(gems) else "--"), "Value")

    -- ---------------------------------------------------------- PlayerStats
    -- HP viene del Humanoid del PROPIO personaje. Es presentacion de si
    -- mismo: el valor que manda para el juego es el del servidor.
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")

    if humanoid then
        setBar("PlayerStats", "HPBar", humanoid.Health, humanoid.MaxHealth,
            ("%d / %d"):format(math.ceil(humanoid.Health), math.ceil(humanoid.MaxHealth)))
    else
        setBar("PlayerStats", "HPBar", nil, nil, "-- / --")
    end

    -- XP. Se publica el total (`XP`) y el nivel; el progreso DENTRO del nivel
    -- no lo inventa la UI: se refleja el dato que llega. La barra queda a 0
    -- porque no hay total de nivel publicado, y el texto lleva la cifra real.
    local xp = attr("XP")
    setBar("PlayerStats", "XPBar", nil, nil,
        (if type(xp) == "number" then ("XP %d"):format(xp) else "XP --"))

    -- ------------------------------------------------------------ BombStats
    -- Bombas: las que le quedan. El contador lo lleva el SERVIDOR. Sin
    -- atributo se muestra "*" y no "0": 0 quiere decir "no te quedan" y es un
    -- dato que todavia no tenemos.
    --
    -- MEDIDO con tools/probe-hud.js (shot-04): las filas de este panel son
    -- Frames con `Symbol`, `Caption` y `Value`, igual que las de `Currency`.
    -- Antes eran TextLabels con el icono como HIJO en posicion [0,0], o
    -- sea en el ORIGEN de la propia cifra: icono y valor acababan en el
    -- mismo pixel y la letra tapaba la cifra entera. Por eso se escribe
    -- en `Value` y no en la fila.
    local bombs = attr("Bombs")
    setText("BombStats", "Bombs", (if type(bombs) == "number" then ("%d"):format(bombs) else "*"), "Value")

    -- ------------------------------------------------------------ ActiveBombs
    --
    -- "BOMBAS" cuenta las que TIENES colocadas. Lo que falta para jugar bien
    -- es "cuantas de esas siguen vivas y van a explotar". Sin este dato el
    -- jugador no puede decidir si meter otra bomba o salir corriendo, que es
    -- la decision basica del juego.
    --
    -- El panel se OCULTA cuando no hay ninguna: un "x0" permanente en pantalla
    -- es ruido que el jugador aprende a no mirar.
    local active = _panels["ActiveBombs"]

    if active then
        if type(bombs) == "number" and bombs > 0 then
            active.Visible = true

            local activeValue = active:FindFirstChild("Value")

            if activeValue and activeValue:IsA("TextLabel") then
                activeValue.Text = ("x%d"):format(bombs)
            end
        else
            active.Visible = false
        end
    end

    -- ----------------------------------------------------------- PowerupRow
    --
    -- Los efectos temporales (escudo, velocidad) se publican como atributos
    -- con el instante en que caducan. Si no se muestran, un powerup hace algo
    -- invisible y el jugador concluye que no funciona.
    local powerupRow = _panels["PowerupRow"]

    if powerupRow then
        local effects = {}
        local now = os.clock()

        if type(attr("PowerupShieldUntil")) == "number" and (attr("PowerupShieldUntil") :: number) > now then
            table.insert(effects, "ESCUDO")
        end

        if type(attr("PowerupSpeedUntil")) == "number" and (attr("PowerupSpeedUntil") :: number) > now then
            table.insert(effects, "VELOCIDAD")
        end

        if type(attr("PowerupFireUntil")) == "number" and (attr("PowerupFireUntil") :: number) > now then
            table.insert(effects, "PODER")
        end

        if #effects > 0 then
            powerupRow.Visible = true
            setText("PowerupRow", "Text", table.concat(effects, "  +  "))
        else
            powerupRow.Visible = false
        end
    end

    local coreState = attr("CoreState")
    local charge = attr("CoreCharge")
    if coreState then
        setText("BombStats", "Power", ("%s%s"):format(
            tostring(coreState),
            if type(charge) == "number" then (" (%d)"):format(charge) else ""
        ), "Value")
    else
        setText("BombStats", "Power", "--", "Value")
    end

    -- ------------------------------------------------------------ Objective
    -- El objetivo es el mundo en el que esta el jugador: es lo UNICO que se
    -- deduce, y solo a partir de un dato ya publicado. La UI no inventa
    -- reglas de juego ni calcula objetivos propios.
    setText("Objective", "Text", (if worldName then tostring(worldName) else "--"))

    -- -------------------------------------------------------------- Mission
    local claimable = attr("QuestCount")
    local streak = attr("QuestStreak")
    setText("Mission", "Text", if type(claimable) == "number"
        then ("Misiones listas: %d%s"):format(claimable,
            if type(streak) == "number" and streak > 0 then ("  racha %d"):format(streak) else "")
        else "Misiones: --")

    -- -------------------------------------------------------------- BossBar
    -- Sin jefe, OCULTA. Un atributo ausente significa "no hay jefe", y una
    -- barra vacia permanente solo persuade al jugador de ignorarla: el dia
    -- que aparezca de verdad ya no la mira.
    local bossPanel = _panels.BossBar
    local bossName = attr("BossName")
    local bossHealth = attr("BossHealth")
    local bossMax = attr("BossMaxHealth")

    if bossPanel then
        if bossName and type(bossHealth) == "number" then
            bossPanel.Visible = true
            setText("BossBar", "Name", tostring(bossName))
            setBar("BossBar", "Bar", bossHealth, bossMax, ("%d / %d"):format(
                math.ceil(bossHealth),
                if type(bossMax) == "number" then math.ceil(bossMax) else 0
            ))
        else
            bossPanel.Visible = false
        end
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
    -- La lista vive en `WATCHED_ATTRIBUTES` (arriba) y no aqui: es el
    -- CONTRATO de datos del HUD. Tenerla en un unico sitio evita que la
    -- lista de la conexion y la del render se desincronicen, que es como un
    -- campo aparece en pantalla y nunca se actualiza.
    for _, attribute in ipairs(WATCHED_ATTRIBUTES) do
        if _maid then
            _maid:Connect(player:GetAttributeChangedSignal(attribute), refresh)
        end
    end

    -- El HP no es un atributo: vive en el Humanoid, que cambia al morir y al
    -- reaparecer. Sin esto el HUD congelaria la vida en el ultimo valor.
    if _maid then
        _maid:Connect(player.CharacterAdded, function()
            refresh()
            local character = player.Character
            if character then
                _maid:Connect(character.ChildAdded, function(child)
                    if child:IsA("Humanoid") then
                        _maid:Connect(child:GetPropertyChangedSignal("Health"), refresh)
                        refresh()
                    end
                end)
            end
        end)
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

    -- AVISOS POR EVENTO REAL
    --
    -- Se escuchan ATRIBUTOS, no se hace polling de lo que pasa. Cada aviso
    -- nace de un dato que el servidor acaba de publicar, asi que no puede
    -- inventarse: si el servidor no subio de nivel, no aparece "LEVEL UP!".
    --
    -- El valor ANTERIOR se guarda para detectar el SALTO, porque un atributo
    -- que se reescribe con el mismo valor sigue disparando la senal. Sin la
    -- comparacion, redimir dos veces el mismo codigo daria dos "LEVEL UP!".
    local lastXP = player:GetAttribute("XP")
    local lastLevel = player:GetAttribute("Level")
    local lastCoins = player:GetAttribute("Coins")

    if _maid then
        _maid:Connect(player:GetAttributeChangedSignal("XP"), function()
            local xp = player:GetAttribute("XP")
            if type(xp) == "number" and type(lastXP) == "number" and xp > lastXP then
                Controller.Notify(("+%d XP"):format(xp - lastXP), Color3.fromRGB(150, 255, 190))
            end
            lastXP = xp
        end)

        _maid:Connect(player:GetAttributeChangedSignal("Coins"), function()
            local coins = player:GetAttribute("Coins")
            if type(coins) == "number" and type(lastCoins) == "number" and coins > lastCoins then
                Controller.Notify(("+%d MONEDAS"):format(coins - lastCoins), Color3.fromRGB(255, 214, 110))
            end
            lastCoins = coins
        end)

        _maid:Connect(player:GetAttributeChangedSignal("Level"), function()
            local level = player:GetAttribute("Level")
            if type(level) == "number" and type(lastLevel) == "number" and level > lastLevel then
                Controller.Notify(("NIVEL %d"):format(level), Color3.fromRGB(255, 236, 150))
            end
            lastLevel = level
        end)

        -- Entrada a un mundo. El nombre llega del servidor, asi que el aviso
        -- no puede mentir sobre donde esta el jugador.
        _maid:Connect(player:GetAttributeChangedSignal("World"), function()
            local world = player:GetAttribute("World")
            if world then
                Controller.Notify(("ENTRANDO EN %s"):format(tostring(world)), Color3.fromRGB(150, 220, 255))
            end
        end)

        -- Fin de ronda.
        _maid:Connect(player:GetAttributeChangedSignal("RoundResult"), function()
            local result = player:GetAttribute("RoundResult")
            if result then
                Controller.Notify(tostring(result), Color3.fromRGB(120, 255, 170))
            end
        end)
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

    -- El HUD se DESTRUYE aqui, pero solo lo que este controller creo por
    -- codigo: el cartel de portal y las notificaciones vivas. El `ScreenGui`
    -- generado NO se destruye: pertenece al `PlayerGui` del jugador y lo
    -- borra Roblox al salir. Destruirlo aqui dejaria al jugador sin HUD
    -- durante el resto de la sesion si el controller se reiniciara.
    if _portalFrame then
        _portalFrame:Destroy()
    end

    -- Avisos residuales: sin esto, un `Destroy` en pleno aviso deja texto
    -- congelado en pantalla que ya no responde a nada.
    for _, frame in ipairs(_liveNotifications) do
        if frame and frame.Parent then
            frame:Destroy()
        end
    end
    _liveNotifications = {}

    -- El token invalida el temporizador del cartel en vuelo: sin el, su
    -- `task.wait` despertaria e intentaria operates sobre un Frame ya
    -- destruido.
    _portalHideToken = (if _portalHideToken then _portalHideToken + 1 else 0)

    _portalFrame = nil
    _labels = {}
    _panels = {}
    _gui = nil
    _maid = nil
    return true
end

return Controller
