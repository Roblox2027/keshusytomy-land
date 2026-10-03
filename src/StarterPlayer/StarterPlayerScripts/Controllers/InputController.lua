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
local Workspace = game:GetService("Workspace")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONSTANTS = SHARED:WaitForChild("Constants")
local UTILS = SHARED:WaitForChild("Utils")
local CONTROLLERS = script.Parent

local GameConstants = require(CONSTANTS:WaitForChild("GameConstants"))
local BombButtonRules = require(SHARED:WaitForChild("Libraries"):WaitForChild("BombButtonRules"))
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
--
-- No es un `TextButton`: es un `Frame` compuesto por las piezas de una
-- bomba dibujada (cuerpo, franja, tapa, mecha y chispa). La razon esta en
-- `BombButtonRules`: un rectangulo rojo con la palabra "BOMBA" describe
-- una ACCION, no un OBJETO, y el jugador tiene que traducirlo antes de
-- poder usarlo.
local bombButton = nil

-- Piezas del boton, resueltas una vez y refrescadas por estado. Se guardan
-- en una tabla en vez de en variables sueltas porque el refresco las
-- recorre todas juntas: si una se olvidara, la bomba se quedaria a medio
-- pintar.
local bombParts = {}

-- Estado de los avisos momentaneos (pulsado / colocado). Son apuntadores
-- a `os.clock` y no banderas: asi el bucle de refresco decide por su cuenta
-- cuando se han pasado los `Timing`, sin depender de que nadie tenga que
-- cancelar un temporizador.
local _pressedUntil = 0
local _placedUntil = 0

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

--- Convierte un color de `BombButtonRules.Palette` en `Color3`.
--- @param color table { R, G, B }
--- @return Color3
local function toColor3(color: any): Color3
    return Color3.fromRGB(color.R, color.G, color.B)
end

--- Crea una pieza dibujada de la bomba dentro del marco del boton.
---
--- @param parent Instance marco del boton
--- @param name string
--- @param spec table pieza descrita por `BombButtonRules.Geometry`
--- @param color Color3
--- @return Frame
local function makePiece(parent: Instance, name: string, spec: any, color: Color3): Frame
    local frame = Instance.new("Frame")
    frame.Name = name
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.Position = UDim2.fromOffset(spec.Position.X, spec.Position.Y)
    frame.BackgroundColor3 = color
    frame.BorderSizePixel = 0
    frame.Rotation = spec.Rotation
    frame.ZIndex = 2

    -- `Size` es un numero en cuerpo y chispa, y una tabla en el resto.
    if type(spec.Size) == "number" then
        frame.Size = UDim2.fromOffset(spec.Size, spec.Size)
    else
        frame.Size = UDim2.fromOffset(spec.Size.X, spec.Size.Y)
    end

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, spec.CornerRadius)
    corner.Parent = frame

    frame.Parent = parent

    return frame
end

--- Dibuja la BOMBA dentro del marco del boton.
---
--- El orden de creacion es el de DIBUJO (de atras hacia delante): cuerpo,
--- franja, tapa, mecha y chispa. En Roblox el ultimo hijo anadido se pinta
--- encima, asi que este orden es el unico que produce una bomba y no un
--- amasijo de rectangulos.
---
--- @param parent Instance marco del boton
--- @return table parts piezas creadas, indexadas por nombre
local function buildBombDrawing(parent: Instance): { [string]: any }
    local geometry = BombButtonRules.Geometry()
    local palette = BombButtonRules.Palette

    local parts = {}

    parts.Body = makePiece(parent, "BombBody", geometry.Body, toColor3(palette.Body))
    parts.Band = makePiece(parent, "BombBand", geometry.Band, toColor3(palette.Band))

    -- ZIndex mayor para las piezas que van ENCIMA. Sin esto, el orden de
    -- creacion no basta: el marco transparente tiene ZIndex 1 y las
    -- piezas con ZIndex 2 quedan por encima, que es lo que se quiere.
    parts.Top = makePiece(parent, "BombTop", geometry.Top, toColor3(palette.Top))
    parts.Fuse = makePiece(parent, "Fuse", geometry.Fuse, toColor3(palette.Fuse))
    parts.Spark = makePiece(parent, "FuseGlow", geometry.Spark, toColor3(palette.Spark))
    parts.Spark.ZIndex = 3

    -- HALO de la chispa: un disco translucido detras del punto calido.
    --
    -- Sin el, la chispa es un punto de 10 px que en movil no se ve. Con el,
    -- se lee como "algo ardiendo" incluso a un metro de la pantalla.
    local glow = makePiece(parent, "SparkGlow", geometry.Spark, toColor3(palette.Spark))
    glow.BackgroundTransparency = 0.55
    glow.ZIndex = 2
    glow.Size = UDim2.fromOffset(geometry.Spark.Size * 2.4, geometry.Spark.Size * 2.4)
    parts.Glow = glow

    -- ETIQUETA SECUNDARIA: la tecla, o la cuenta atras.
    --
    -- Va ABAJO de la bomba y es pequena. El texto es un detalle de apoyo,
    -- no el elemento principal: el jugador debe entender el boton sin
    -- leerlo, y esta etiqueta solo confirma el atajo en PC.
    local label = Instance.new("TextLabel")
    label.Name = "Hint"
    label.AnchorPoint = Vector2.new(0.5, 1)
    label.Position = UDim2.fromOffset(0, -2)
    label.Size = UDim2.fromOffset(BombButtonRules.Size, 22)
    label.BackgroundTransparency = 1
    label.BorderSizePixel = 0
    label.Font = Enum.Font.GothamBold
    label.Text = "F"
    label.TextColor3 = toColor3(palette.Hint)
    label.TextSize = 15
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.ZIndex = 4
    label.Parent = parent
    parts.Hint = label

    bombParts = parts

    return parts
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

    -- MARCO TRANSPARENTE que recibe los toques.
    --
    -- Es un `TextButton` por una razon tecnica, no de diseno: es el
    -- unico `GuiButton` que acepta `MouseButton1Click` conservando
    -- `AutoButtonColor = false`, y sin su texto visible. Lo que el jugador
    -- VE son las piezas dibujadas que cuelgan de el.
    --
    -- El nombre se mantiene como `BombButton` porque el resto del codigo
    -- (y las herramientas de verificacion) lo buscan por el.
    local button = Instance.new("TextButton")
    button.Name = "BombButton"
    button.AnchorPoint = Vector2.new(1, 1)
    button.Position = UDim2.new(1, -32, 1, -32)
    button.Size = UDim2.fromOffset(BombButtonRules.Size, BombButtonRules.Size)
    button.BackgroundTransparency = 1
    button.BorderSizePixel = 0
    -- El texto del marco esta VACIO a proposito: el texto del boton es
    -- un detalle pequeno (la tecla), y lo pone la etiqueta secundaria.
    button.Text = ""
    button.AutoButtonColor = false
    button.Parent = gui

    buildBombDrawing(button)

    -- `MouseButton1Click` cubre PC y el toque emulado en movil, y es la
    -- senal del PROPIO boton, no global. Por eso no puede colocar una
    -- bomba al abrir un menu o al mover la camara, que fue exactamente
    -- el bug que corrigio el `TouchTap` global.
    button.MouseButton1Click:Connect(function()
        -- La marca de "pulsado" se pone ANTES de la peticion: el jugador
        -- tiene que ver que el boton responde en el mismo frame del toque,
        -- no un instante despues. Si la peticion falla, la marca caduca
        -- sola y el boton vuelve a su estado.
        _pressedUntil = os.clock() + BombButtonRules.Timing.PressDuration

        local sent = Controller.RequestBombPlacement()

        if sent then
            -- `BombController` ya sabe si el servidor acepto. Todavia no:
            -- la ida y vuelta por la red no ha ocurrido. La confirmacion
            -- real llega cuando el servidor publica la bomba en el mundo.
            return
        end

        -- No se envio nada: se retira la marca inmediatamente para que el
        -- boton no se quede "pulsado" sin que haya pasado nada.
        _pressedUntil = 0
    end)

    -- El Maid destruye el ScreenGui completo, que incluye el boton.
    if _maid then
        _maid:Add(gui)
    end

    bombButton = button
    Logger.Info("InputController: boton de bomba dibujado (bomba, no texto).")
    return true
end

--- Pinta el estado del boton.
---
--- Convierte el estado en algo VISIBLE. Sin esto el boton acepta el
--- toque, el controller lo frena en silencio y el jugador no entiende por
--- que no ocurre nada, que es indistinguible de un boton roto.
---
--- La DECISION de que estado toca la toma `BombButtonRules.Resolve`; aqui
--- solo se aplican sus numeros. Si el estado se decidiera aqui, el
--- "bloqueado" y el "enfriado" volverian a ser el mismo boton apagado,
--- que es el bug que tenia el boton rojo.
---
--- @return boolean updated
local function refreshBombButton(): boolean
    if not bombButton or not bombButton.Parent then
        return false
    end

    local now = os.clock()
    local remaining = Controller.GetBombCooldownRemaining()

    -- `CanRequest` es la opinion del CLIENTE sobre si puede. No concede
    -- nada: el servidor sigue validando. Solo decide si el boton se ve
    -- disponible o apagado.
    local canPlace = BombController.CanRequest()

    local state = BombButtonRules.Resolve(
        canPlace,
        remaining,
        now < _pressedUntil,
        now < _placedUntil
    )
    local look = BombButtonRules.Appearance(state, remaining)

    -- COLOR: cada pieza se mezcla hacia gris segun `Dim`. Se usa el mismo
    -- valor para todas, de modo que el boton entero se apaga como uno.
    local muted = BombButtonRules.Palette.Muted

    --- @param color any
    --- @return Color3
    local function dimmed(color: any): Color3
        local t = look.Dim
        return Color3.fromRGB(
            color.R + (muted.R - color.R) * t,
            color.G + (muted.G - color.G) * t,
            color.B + (muted.B - color.B) * t
        )
    end

    if bombParts.Body then bombParts.Body.BackgroundColor3 = dimmed(look.Body) end
    if bombParts.Band then bombParts.Band.BackgroundColor3 = dimmed(look.Band) end
    if bombParts.Top then bombParts.Top.BackgroundColor3 = dimmed(look.Top) end
    if bombParts.Fuse then bombParts.Fuse.BackgroundColor3 = dimmed(look.Fuse) end

    -- CHISPA: es lo unico que ANDA, asi que lleva su propio pulso.
    --
    -- En `Placed` el factor lo fija `Appearance` (mas grande, para que se
    -- lea como fogonazo). En cualquier otro estado visible late con el
    -- tiempo. Cuando no debe verse, no se latea: llamar a `SparkPulse` en
    -- un estado apagado seria trabajo por nada.
    if bombParts.Spark and bombParts.Glow then
        local visible = look.SparkVisible
        bombParts.Spark.Visible = visible
        bombParts.Glow.Visible = visible

        local scale = look.SparkScale

        if visible and state ~= BombButtonRules.State.Placed then
            scale = BombButtonRules.SparkPulse(
                now,
                BombButtonRules.Timing.SparkPulsePeriod,
                BombButtonRules.Timing.SparkPulseAmount
            ) * look.SparkScale
        end

        local sparkBase = BombButtonRules.Geometry().Spark.Size
        local sparkSize = sparkBase * scale

        bombParts.Spark.Size = UDim2.fromOffset(sparkSize, sparkSize)
        bombParts.Spark.BackgroundColor3 = dimmed(look.Spark)
        bombParts.Glow.Size = UDim2.fromOffset(sparkSize * 2.4, sparkSize * 2.4)
        bombParts.Glow.BackgroundColor3 = dimmed(look.Spark)
    end

    -- TEXTO SECUNDARIO: la tecla, la cuenta atras o la confirmacion.
    if bombParts.Hint then
        bombParts.Hint.Text = look.Label

        -- El color del texto tambien se apaga: un texto blanco sobre un
        -- boton gris es lo mas parecido a "boton roto" que hay.
        bombParts.Hint.TextColor3 = dimmed(BombButtonRules.Palette.Hint)

        -- La cuenta atras necesita ser mas grande que la tecla: si no, el
        -- jugador no ve el numero y el enfriamiento parece no avanzar.
        bombParts.Hint.TextSize = if look.ShowCountdown then 20 else 15
    end

    -- El MARCO nunca se pinta: es invisible y solo recibe los toques.
    bombButton.BackgroundTransparency = 1

    return true
end

--- Marca el boton como "bomba colocada" durante el tiempo de confirmacion.
---
--- La llama el observador de bombas del `Workspace`, no el handler del
--- clic: la confirmacion REAL es que el servidor publico una bomba en el
--- mundo. Si se marcara al enviar la peticion, una peticion rechazada (por
--- enfriamiento, sin ronda o fuera de la arena) se sentiria como si la
--- bomba se hubiera puesto.
--- @param duration number?
function Controller.NotifyBombPlaced(duration: number?)
    _placedUntil = os.clock() + (duration or BombButtonRules.Timing.PlacedDuration)
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

    -- CONFIRMACION REAL DE LA BOMBA.
    --
    -- Se observa la carpeta `Bombs` del Workspace en vez de confiar en la
    -- peticion que acabamos de enviar. La bomba la crea y la publica el
    -- SERVIDOR, asi que su aparicion es la unica prueba de que la
    -- peticion fue aceptada: si el servidor la rechazo (por enfriamiento,
    -- sin ronda o fuera de la arena), no aparecera nada y el boton no
    -- mostrara la confirmacion.
    --
    -- Se cuentan las bombas VISTAS, no las peticiones. Asi el boton
    -- confirma tanto una bomba colocada con el dedo como una puesta con el
    -- teclado, sin duplicar el camino.
    local bombFolder = Workspace:WaitForChild("Bombs", 10)
    local seenBombs = 0

    if bombFolder then
        seenBombs = #bombFolder:GetChildren()

        connectIfActive(bombFolder.ChildAdded, function(_instance: any)
            seenBombs += 1
            Controller.NotifyBombPlaced()
        end)

        connectIfActive(bombFolder.ChildRemoved, function(_instance: any)
            seenBombs -= 1
        end)
    end

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
    -- La tabla de piezas se vacia junto con el boton: si se guardara, y
    -- `Destroy` se llamara dos veces, el segundo paso encontraria piezas
    -- ya destruidas y `refreshBombButton` escribiria sobre ellas.
    bombParts = {}
    -- Las marcas temporales se limpian para que un `Start` posterior no
    -- herede un "colocado" de hace diez segundos y avise sin motivo.
    _pressedUntil = 0
    _placedUntil = 0
    _maid = nil
    return true
end

return Controller
