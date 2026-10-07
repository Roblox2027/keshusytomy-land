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
local CONFIG = SHARED:WaitForChild("Config")
local CONSTANTS = SHARED:WaitForChild("Constants")
local UTILS = SHARED:WaitForChild("Utils")
local CONTROLLERS = script.Parent

local GameConstants = require(CONSTANTS:WaitForChild("GameConstants"))
local GameConfig = require(CONFIG:WaitForChild("GameConfig"))
local BombButtonRules = require(SHARED:WaitForChild("Libraries"):WaitForChild("BombButtonRules"))
local Logger = require(UTILS:WaitForChild("Logger"))
local BombController = require(CONTROLLERS:WaitForChild("BombController"))
local CombatController = require(CONTROLLERS:WaitForChild("CombatController"))

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

--- Ruta de la BOMBA dentro del HUD.
---
--- NO se crea un `ScreenGui` propio. Antes este controller construia un
--- `ScreenGui`parallel (`TouchControls`) con su propia cuenta de posicion, y
--- el HUD era un segundo sistema visual aparte: los dos se peleaban el mismo
--- espacio, el boton se tapaba con el panel de objetivos y la bomba
--- desaparecia de la vista del jugador.
---
--- Ahora el marco de la bomba lo DECLARA `tools/hud.js` dentro de la zona
--- `BottomBar`, con su `ZIndex` por encima de los paneles. Aqui solo se
--- RELLENA de piezas y se conecta el clic.
local BOMB_PATH = { "Root", "BottomBar", "BombAction" }

--- Cada cuanto se revisa que el boton enlazado siga siendo el del HUD.
---
--- El HUD se destruye y se reconstruye al reiniciar la sesion de Play, y el
--- controller puede quedar con una referencia caducada. Revisar cada 2 s
--- significa que un HUD reconstruido vuelve a funcionar en menos de lo que
-- tarda el jugador en volver a pulsar, sin convertir el refresco en un
-- sondeo continuo del arbol.
local REBIND_CHECK_INTERVAL = 2

--- Marco de la accion de bomba (del HUD, no creado aqui).
local bombButton = nil

--- Piezas dibujadas de la bomba, dentro de `BombVisual`.
---
--- Se guardan en una tabla en vez de en variables sueltas porque el refresco
--- las recorre todas juntas: si una se olvidara, la bomba se quedaria a medio
--- pintar.
local bombParts = {}

--- Marco de la barra de enfriamiento y su relleno, dentro de `BombAction`.
local bombCooldown = nil
local bombCooldownFill = nil

--- Etiquetas de estado y de tecla. Son APOYO: la bomba dibujada es lo que se
--- lee sin leer.
local bombStateLabel = nil
local bombKeyHint = nil

--- Lado del marco `BombVisual` declarado en el generador.
---
--- El generador define un tamano de DISENO y el `UIScale` de la zona lo
--- lleva a cada pantalla. Por eso las piezas se dibujan una vez, a este
--- tamano, y no hay que recolocar nada al cambiar de viewport: eso era
--- exactamente el parche de coordenadas que se elimino.
---
--- MEDIDO EN PLAY: antes valia 118 y el marco del generador tambien, o sea
--- la bomba se dibujaba a `118/104 = 1.135` de `BombButtonRules.Size`. Ahora
--- los dos son 104 y el factor es exactamente 1.0: la geometria de las reglas
--- se dibuja a la escala para la que fue DISEÑADA, sin un factor de ampliacion
--- que hay que recordar mantener en dos sitios.
local BOMB_VISUAL_SIZE = 104

-- Estado de los avisos momentaneos (pulsado / colocado). Son apuntadores
-- a `os.clock` y no banderas: asi el bucle de refresco decide por su cuenta
-- cuando se han pasado los `Timing`, sin depender de que nadie tenga que
-- cancelar un temporizador.
local _pressedUntil = 0
local _placedUntil = 0

-- Seguimiento del motivo de rechazo para poder CADUCARLO.
--
-- El atributo `BombRejection` del servidor es un ESTADO, no un evento: sigue
-- puesto hasta que la bomba se coloca. Si se pintara tal cual, el motivo se
-- quedaria pegado en el boton aunque el jugador ya estuviera en una ronda.
-- Se guardan el ultimo motivo visto y el instante en que aparecio, que es lo
-- que permite que expire sin depender de que nadie lo borre.
local _rejectionLastSeen: string? = nil
local _rejectionSeenAt: number? = nil

-- (Ya no hay estado de layout: el marco lo declara el HUD y el `UIScale` de
-- su zona lo lleva a cada pantalla. No hay posiciones que reaplicar.)

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

--- Crea una pieza dibujada de la bomba dentro de `BombVisual`.
---
--- La posicion y el tamano los ajusta despues `buildBombDrawing`, que es quien
--- conoce la escala de DISENO. Aqui solo se crea el `Frame` con su color, su
--- giro y su esquina redondeada.
---
--- @param parent Instance marco `BombVisual`
--- @param spec table pieza descrita por `BombButtonRules.Geometry`
--- @param color Color3
--- @return Frame
local function makePiece(parent: Instance, spec: any, color: Color3): Frame
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.Rotation = spec.Rotation or 0
	frame.ZIndex = 2

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, spec.CornerRadius or 0)
	corner.Parent = frame

	frame.Parent = parent

	return frame
end

--- Dibuja la BOMBA dentro de `BombVisual`.
---
--- El orden de creacion es el de DIBUJO (de atras hacia delante): cuerpo,
--- franja, tapa, mecha y chispa. En Roblox el ultimo hijo anadido se pinta
--- encima, asi que este orden es el unico que produce una bomba y no un
--- amasijo de rectangulos.
---
--- `BombVisual` tiene el tamano de DISENO declarado en el generador, y las
--- piezas se dibujan a esa escala. El `UIScale` de la zona las lleva a cada
--- pantalla, asi que NO hay que reescalar nada al cambiar de viewport: la
--- bomba se dibuja UNA vez y se ve igual de proporcionada en todas.
---
--- @param parent Instance marco `BombVisual` del HUD
--- @return table parts piezas creadas, indexadas por nombre
local function buildBombDrawing(parent: Instance): { [string]: any }
	local geometry = BombButtonRules.Geometry()
	local palette = BombButtonRules.Palette

	-- `Geometry` esta disenada para un marco de `Rules.Size` (104). El marco
	-- del generador es mayor (118), asi que se escala UNA vez aqui, por
	-- proportion, y las piezas quedan centradas en el marco real.
	local factor = BOMB_VISUAL_SIZE / BombButtonRules.Size
	local center = BOMB_VISUAL_SIZE / 2

	local parts = {}

	local function scaled(spec: any): Frame
		local frame = makePiece(parent, spec, Color3.new(1, 1, 1))
		-- BUG CORREGIDO (medido en PLAY): aqui se restaba `center`, y como la
		-- pieza ya tiene `AnchorPoint = (0.5, 0.5)`, eso la empujaba DOS veces
		-- hacia el centro: `Position` es el CENTRO de la pieza, asi que el
		-- desplazamiento del centro del marco hay que SUMARLO, no restarlo.
		--
		-- La geometria de `BombButtonRules` es relativa al CENTRO (`Body` va en
		-- `X = 0`), asi que la posicion correcta es:
		--
		--     centro del marco + desplazamiento de la pieza
		--
		-- Medicion del fallo: `BombVisual` en `[327,427]` y `BombBody` en
		-- `[267,372]`, es decir la bomba dibujada caia 60 px ARRIBA-IZQUIERDA
		-- de su propio marco, encima del HUD y no del boton. El jugador veia
		-- un boton vacio y un dibujo de bomba suelto por ahi: la bomba "no
		-- aparecia" aunque `BombVisual` existiera, fuera de pantalla y visible.
		frame.Position = UDim2.fromOffset(
			center + (spec.Position.X or 0) * factor,
			center + (spec.Position.Y or 0) * factor
		)

		if type(spec.Size) == "number" then
			frame.Size = UDim2.fromOffset(spec.Size * factor, spec.Size * factor)
		else
			frame.Size = UDim2.fromOffset((spec.Size.X or 0) * factor, (spec.Size.Y or 0) * factor)
		end

		local corner = frame:FindFirstChildOfClass("UICorner")

		if corner then
			corner.CornerRadius = UDim.new(0, (spec.CornerRadius or 0) * factor)
		end

		return frame
	end

	parts.Body = scaled(geometry.Body)
	parts.Body.Name = "BombBody"
	parts.Body.BackgroundColor3 = toColor3(palette.Body)
	parts.Band = scaled(geometry.Band)
	parts.Band.Name = "BombBand"
	parts.Band.BackgroundColor3 = toColor3(palette.Band)

	-- ZIndex mayor para las piezas que van ENCIMA: con
	-- `ZIndexBehavior = "Sibling"` el orden de creacion NO basta y el orden de
	-- siblings dentro de la zona es el que decide.
	parts.Top = scaled(geometry.Top)
	parts.Top.Name = "BombTop"
	parts.Top.BackgroundColor3 = toColor3(palette.Top)
	parts.Top.ZIndex = 3
	parts.Fuse = scaled(geometry.Fuse)
	parts.Fuse.Name = "Fuse"
	parts.Fuse.BackgroundColor3 = toColor3(palette.Fuse)
	parts.Fuse.ZIndex = 3
	parts.Spark = scaled(geometry.Spark)
	parts.Spark.Name = "FuseGlow"
	parts.Spark.BackgroundColor3 = toColor3(palette.Spark)
	parts.Spark.ZIndex = 4

	-- HALO de la chispa: un disco translucido detras del punto calido.
	--
	-- Sin el, la chispa es un punto de 10 px que en movil no se ve. Con el,
	-- se lee como "algo ardiendo" incluso a un metro de la pantalla.
	local glow = scaled(geometry.Spark)
	glow.Name = "SparkGlow"
	glow.BackgroundTransparency = 0.55
	glow.BackgroundColor3 = toColor3(palette.Spark)
	glow.ZIndex = 2
	glow.Size =
		UDim2.fromOffset(geometry.Spark.Size * factor * 2.4, geometry.Spark.Size * factor * 2.4)
	parts.Glow = glow

	-- NOTA: la etiqueta de tecla y el estado NO se dibujan aqui. Los declara
	-- el generador como `KeyHint` y `State` dentro de `BombAction`: son
	-- texto de apoyo y su posicion la decide el layout, no la geometria de la
	-- bomba.

	bombParts = parts

	return parts
end

-- -----------------------------------------------------------------------
-- ENLAZADO CON EL MARCO DEL HUD
-- -----------------------------------------------------------------------
--
-- El marco (`BombAction`) lo declara `tools/hud.js`. Aqui solo se busca por
-- su ruta, se rellenan las piezas dibujadas y se conecta el clic. NO se
-- calcula ninguna posicion: la zona del HUD ya esta anclada y escalada.
--
-- Antes este controller creaba un `ScreenGui` PROPIO con la esquina de la
-- pantalla como posicion, y `UIController` tenia que apartar sus paneles
-- para que no se taparan. Ese era el patch de coordenadas que se elimina.

--- Busca la accion de bomba dentro del HUD.
---
--- Se espera con `WaitForChild`: el HUD lo produce el arranque del lugar y
--- este controller puede despertar antes. Sin espera, un fallo de orden
--- devolveria `nil` y dejaria al jugador sin forma visible de colocar
--- bombas.
---
--- @param player Player
--- @return any? TextButton del HUD
local function findBombAction(player: Player): any?
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local hud = playerGui and playerGui:FindFirstChild("KeshusyHUD")

	if not hud then
		return nil
	end

	local node: any = hud

	for _, step in ipairs(BOMB_PATH) do
		node = node:FindFirstChild(step)

		if not node then
			return nil
		end
	end

	return node
end

--- Enlaza la accion de bomba DECLARADA por el HUD.
---
--- El boton existe en TODOS los dispositivos, no solo en tactiles: en
--- escritorio el teclado y el gamepad bastan, pero sin un control VISIBLE el
--- jugador no tiene forma de saber que la bomba es una accion del juego.
---
--- Un unico boton para PC, movil y mando es ademas menos codigo que la rama
--- condicional, y ejecuta exactamente la misma accion en los tres casos: el
--- teclado y el clic llaman a la MISMA funcion.
---
--- P0: REBUILD DEL HUD (medido, no hipotetico)
--- -----------------------------------------
--- Esta funcion tiene que poder ejecutarse MAS DE UNA VEZ. El controller
--- guarda referencias al HUD (`bombButton`, `bombCooldown`, ...), y el HUD
--- vive en `PlayerGui`: si se reconstruye entre sesiones, o si el lugar se
--- recarga, esas referencias apuntan a instancias que ya NO ESTAN en el arbol.
---
--- Un `bombButton` cacheado a una instancia destruida se comporta de la
--- peor manera posible: no es `nil`, asi que ningun chequeo lo detecta, y
--- `MouseButton1Click` sobre una instancia muerta no dispara nunca. El
--- jugador ve un boton que no hace nada y el controller parece "roto"
--- cuando lo unico que pase es que su referencia-caduco.
---
--- Por eso `ensureBombButton` NO devuelve `true` solo porque `bombButton` sea
--- no-nil: comprueba que la referencia SIGA VIVA y siga siendo la ruta
--- vigente del HUD. Si ya no lo es, la suelta y la vuelve a resolver.
---
--- Regla: `Start -> Resolve -> Connect`. Nunca `Start -> old reference`.
--- @return boolean bound
local function ensureBombButton(): boolean
	-- Referencia cacheada: solo se acepta si sigue en el arbol Y en la ruta
	-- que el HUD declara hoy. Un SimpleGate de "no es nil" daria por bueno un
	-- boton destruido, que es justo el fallo que se quiere evitar.
	if bombButton and bombButton.Parent then
		local actual = findBombAction(Players.LocalPlayer)

		if actual == bombButton then
			return true
		end

		Logger.Info("InputController: el HUD cambio; se vuelve a enlazar la accion de bomba.")
	end

	-- Lo que estaba antes se suelta SIEMPRE antes de resolver de nuevo: si no,
	-- las piezas del boton viejo se quedan en la tabla y `refreshBombButton`
	-- escribiria sobre instancias destruidas.
	bombButton = nil
	bombCooldown = nil
	bombCooldownFill = nil
	bombStateLabel = nil
	bombKeyHint = nil
	bombParts = {}

	local player = Players.LocalPlayer

	if not player then
		return false
	end

	local playerGui = player:WaitForChild("PlayerGui", 10)

	if not playerGui then
		Logger.Warn("InputController: PlayerGui no disponible; no habra boton de bomba.")
		return false
	end

	-- El HUD lo produce el arranque del lugar. Se espera a que aparezca: si
	-- este controller despertara antes y solo leyera, devolveria `nil` y el
	-- jugador se quedaria SIN forma visible de colocar una bomba.
	local deadline = os.clock() + 15
	local button = findBombAction(player)

	while not button and os.clock() < deadline do
		task.wait(0.25)
		button = findBombAction(player)
	end

	if not button then
		Logger.Error(
			("InputController: el HUD no tiene %s; no habra accion de bomba visible."):format(
				table.concat(BOMB_PATH, "/")
			)
		)
		return false
	end

	local visual = button:FindFirstChild("BombVisual")

	if not visual then
		Logger.Error("InputController: BombAction no tiene el marco BombVisual.")
		return false
	end

	-- Las piezas se dibujan UNA vez, dentro del marco que declara el
	-- generador. No hay ninguna posicion que calcular: por eso el boton ya no
	-- puede quedarse en (0, 0) "invisible" porque la camara todavia no exista.
	buildBombDrawing(visual)

	bombCooldown = button:FindFirstChild("Cooldown")
	bombCooldownFill = bombCooldown and bombCooldown:FindFirstChild("Fill") or nil
	bombStateLabel = button:FindFirstChild("State")
	bombKeyHint = button:FindFirstChild("KeyHint")

	-- `MouseButton1Click` cubre PC y el toque emulado en movil, y es la senal
	-- del PROPIO boton, no global. Por eso no puede colocar una bomba al
	-- abrir un menu o al mover la camara, que fue el bug que corrigio el
	-- `TouchTap` global.
	button.MouseButton1Click:Connect(function()
		-- La marca de "pulsado" se pone ANTES de la peticion: el jugador
		-- tiene que ver que el boton responde en el mismo frame del toque, no
		-- un instante despues. Si la peticion falla, la marca caduca sola y el
		-- boton vuelve a su estado.
		_pressedUntil = os.clock() + BombButtonRules.Timing.PressDuration

		local sent = Controller.RequestBombPlacement()

		if sent then
			-- `BombController` ya sabe si el servidor acepto. Todavia no: la
			-- ida y vuelta por la red no ha ocurrido. La confirmacion real
			-- llega cuando el servidor publica la bomba en el mundo.
			return
		end

		-- No se envio nada: se retira la marca inmediatamente para que el
		-- boton no se quede "pulsado" sin que haya pasado nada.
		_pressedUntil = 0
	end)

	-- El HUD NO se destruye aqui: pertenece al `PlayerGui` y lo borra Roblox
	-- al salir, y es el UNICO sistema visual: no hay un `ScreenGui` paralelo
	-- que limpiar.
	bombButton = button
	Logger.Info("InputController: accion de bomba enlazada al HUD (bomba dibujada, no texto).")
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
--- Motivo de rechazo vigente, o `nil` si no hay ninguno.
---
--- Lo escribe el SERVIDOR en el atributo `BombRejection` (ver
--- `BombService.publishRejection`). El cliente no lo inventa: si el atributo no
--- esta, no hay motivo, y se muestra la etiqueta normal.
---
--- El motivo caduca a los pocos segundos. Sin caducidad, un rechazo antiguo
--- se quedaria pegado en el boton aunque el jugador ya estuviera en una ronda
--- y pudiera colocar bombas sin problema: leeria "FUERA DE LA ARENA" sobre un
--- boton que funciona. Se memoriza el momento en que se vio POR PRIMERA VEZ
--- un motivo, no el del atributo, porque el atributo es un estado y no un
--- evento.
--- @return string? motivo visible
local function readBombRejection(): string?
	local player = Players.LocalPlayer

	if not player then
		return nil
	end

	local reason = player:GetAttribute("BombRejection")

	if type(reason) ~= "string" or reason == "" then
		_rejectionSeenAt = nil
		return nil
	end

	if reason ~= _rejectionLastSeen then
		_rejectionLastSeen = reason
		_rejectionSeenAt = os.clock()
	end

	if _rejectionSeenAt == nil then
		return nil
	end

	if (os.clock() - _rejectionSeenAt) > BombButtonRules.Timing.RejectionDuration then
		_rejectionSeenAt = nil
		return nil
	end

	return reason
end

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

	local state =
		BombButtonRules.Resolve(canPlace, remaining, now < _pressedUntil, now < _placedUntil)
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

	if bombParts.Body then
		bombParts.Body.BackgroundColor3 = dimmed(look.Body)
	end
	if bombParts.Band then
		bombParts.Band.BackgroundColor3 = dimmed(look.Band)
	end
	if bombParts.Top then
		bombParts.Top.BackgroundColor3 = dimmed(look.Top)
	end
	if bombParts.Fuse then
		bombParts.Fuse.BackgroundColor3 = dimmed(look.Fuse)
	end

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

		-- La chispa late sobre el TAMANO DE DISENO: el `UIScale` de la zona
		-- lleva el conjunto a la pantalla real. Reposicionar en pixeles aqui
		-- seria volver al parche de coordenadas que se elimina.
		local sparkFactor = BOMB_VISUAL_SIZE / BombButtonRules.Size
		local sparkBase = BombButtonRules.Geometry().Spark.Size * sparkFactor
		local sparkSize = sparkBase * scale

		bombParts.Spark.Size = UDim2.fromOffset(sparkSize, sparkSize)
		bombParts.Spark.BackgroundColor3 = dimmed(look.Spark)
		bombParts.Glow.Size = UDim2.fromOffset(sparkSize * 2.4, sparkSize * 2.4)
		bombParts.Glow.BackgroundColor3 = dimmed(look.Spark)
	end

	-- BARRA DE ENFRIAMIENTO.
	--
	-- Se vacia de izquierda a derecha y es el progreso que se ve SIN leer. Con
	-- `remaining = 0` se oculta entera: una barra llena permanente seria ruido.
	if bombCooldown and bombCooldownFill then
		bombCooldown.Visible = remaining > 0

		local ratio = if remaining > 0
			then math.clamp(1 - (remaining / GameConfig.BombCooldown), 0, 1)
			else 0

		bombCooldownFill.Size = UDim2.fromScale(ratio, 1)
	end

	-- TEXTO DE APOYO: estado, cuenta atras o confirmacion.
	--
	-- El motivo del servidor tiene PRIORIDAD sobre el estado normal. MEDIDO EN
	-- PLAY (antes de esto): el servidor rechazaba con `state_violation`, el
	-- log lo decia y el cliente no mostraba nada. El jugador pulsaba un boton
	-- que no respondsia y no tenia ninguna pista de por que.
	if bombStateLabel then
		local rejection = readBombRejection()

		if rejection then
			bombStateLabel.Text = rejection
			bombStateLabel.TextColor3 = Color3.fromRGB(255, 120, 120)
			bombStateLabel.TextSize = 11
		else
			bombStateLabel.Text = look.Label
			bombStateLabel.TextColor3 = dimmed(BombButtonRules.Palette.Hint)
			bombStateLabel.TextSize = if look.ShowCountdown then 15 else 12
		end
	end

	-- La tecla solo aparece cuando la bomba esta LISTA: durante el
	-- enfriamiento el numero importa mas que el atajo.
	if bombKeyHint then
		bombKeyHint.Text = if state == BombButtonRules.State.Ready then "F" else ""
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

--- Conecta una senal SOLO si el controller sigue activo.
---
--- BUG CORREGIDO (medido en PLAY; era el fallo P0 que dejaba la bomba
--- muerta): esta funcion estaba DECLARADA despues de su primer uso. Lua
--- resuelve los locales en ORDEN DE ESCRITURA, asi que en el punto en que se
--- llamaba, el nombre era un GLOBAL y salia `nil`. Error medido:
---
---     InputController:467: attempt to call a nil value
---
--- Lo que rompia no era solo una conexion perdida. `ControllerRegistry`
--- envuelve el `Start` en un `pcall`, de modo que la excepcion marcaba el
--- controller ENTERO como `Failed` y el `Start` se detenia ahi. Con el
--- controller caido:
---
---     - el teclado (F) y el mando (R2) no hacian NADA
---     - el bucle de refresco del boton no arrancaba
---     - la confirmacion "bomba colocada" nunca se escuchaba
---
--- El boton seguia existiendo y su `MouseButton1Click` (conectado antes de
--- la linea que reventaba) seguia funcionando. Por eso el jugador veia un
--- boton "que no hacia nada": la peticion salia, pero sin cooldown visible y
--- sin confirmacion. Ninguna prueba de unidad lo detectaba, porque el fallo
--- es de ALCANCE LEXICO, no de logica.
---
--- Ahora esta ANTES de cualquier uso. Si alguna vez vuelve a moverse, el
--- fallo reaparece igual de silencioso.
--- @param signal any senal de Roblox
--- @param handler function manejador
local function connectIfActive(signal: any, handler: (...any) -> ())
	if _maid then
		_maid:Connect(signal, handler)
	end
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
		Logger.Error(
			"InputController: ReplicatedStorage.Remotes." .. RemoteAction.Bomb .. " no existe."
		)
		return false
	end

	bombRemote = remote
	_maid = maid

	-- El boton se resuelve ANTES de conectar los eventos: el handler
	-- tactil lo consulta y debe existir cuando llegue el primer toque.
	--
	-- `ensureBombButton` resuelve SIEMPRE desde el arbol actual. No se
	-- salta por tener una referencia cacheada: una referencia al HUD de una
	-- sesion anterior es justo lo que deja al controller "activo" y muerto
	-- al mismo tiempo.
	local enlazado = ensureBombButton()

	if not enlazado then
		Logger.Warn(
			"InputController: el HUD no tiene la accion de bomba todavia; "
				.. "se seguira intentando desde el bucle de refresco."
		)
	end

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

	-- `InputBegan` es un unico evento y el juego ya traduce el gamepad
	-- a KeyCode, asi que teclado y mando se resuelven juntos.
	connectIfActive(UserInputService.InputBegan, function(input: any, gameProcessed: boolean)
		if gameProcessed then
			return
		end

		local isBombKey = input.KeyCode == Enum.KeyCode.F or input.KeyCode == Enum.KeyCode.ButtonR2

		if isBombKey then
			Controller.RequestBombPlacement()
		end

		-- COMBATE V2 (mision V2): golpe rapido con click / E / X del
		-- mando, dash con Q / B, habilidad con R / Y. La intencion se
		-- traduce aqui; la decision la toma el servidor.
		local isMeleeKey = input.KeyCode == Enum.KeyCode.E
			or input.KeyCode == Enum.KeyCode.ButtonX
			or input.UserInputType == Enum.UserInputType.MouseButton1

		if isMeleeKey then
			CombatController.Melee()
			return
		end

		local isDashKey = input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.ButtonB

		if isDashKey then
			CombatController.Dash()
			return
		end

		local isAbilityKey = input.KeyCode == Enum.KeyCode.R
			or input.KeyCode == Enum.KeyCode.ButtonY

		if isAbilityKey then
			CombatController.Ability()
			return
		end
	end)

	-- Tactil: el `MouseButton1Click` del propio `BombAction` ya cubre movil,
	-- y es la senal del control, no global. Un `TouchTap` global que
	-- colocara bombas en cualquier punto fue exactamente el bug que hacia
	-- el juego injugable (y disparaba el rate limit del servidor): aqui NO
	-- se escucha, porque la misma intencion entra por el boton y por el
	-- teclado.
	--
	-- El atajo de teclado NO se filtra por `bombButton`: el jugador puede
	-- soltar bombas sin que el control este visible (por ejemplo durante un
	-- overlay), y el teclado es la via principal en escritorio.

	Controller.IsActive = true

	-- Refresco del estado de la bomba. El intervalo es de 100 ms: bastante
	-- fino para que el contador no parezca congelado y bastante grueso para
	-- no poner un RenderStepped por frame en cada cliente.
	--
	-- NO hay nada que recolocar: la zona del HUD esta anclada y escalada, y
	-- el motor la coloca sola en cualquier viewport. Ese bucle antes solo
	-- "reaplicaba el layout"; ahora pinta el estado.
	-- "reaplicaba el layout"; ahora solo pinta el estado.
	task.spawn(function()
		-- Revision del enlace, separada del refresco de estado.
		--
		-- No se comprueba en CADA pasada del refresco: `ensureBombButton`
		-- vuelve a dibujar la bomba cuando el HUD cambia, y eso no debe
		-- ocurrir diez veces por segundo. Solo se mira de vez en cuando, lo
		-- bastante a menudo para que un HUD reconstruido vuelva a funcionar
		-- sin que el jugador note el corte, y lo bastante raro para no
		-- hacer trabajo inutil.
		local proximaRevision = 0

		while Controller.IsActive do
			local ahora = os.clock()

			if ahora >= proximaRevision then
				proximaRevision = ahora + REBIND_CHECK_INTERVAL
				ensureBombButton()
			end

			refreshBombButton()
			task.wait(0.1)
		end
	end)

	Logger.Info("InputController listo (F / R2 / boton del HUD para colocar bomba).")

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
	-- El motivo de rechazo tambien: si no, un `Start` posterior lo
	-- recordaria como "visto ahora" y lo pintaria aunque el servidor ya
	-- hubiera limpiado el atributo.
	_rejectionLastSeen = nil
	_rejectionSeenAt = nil
	-- Las referencias al HUD se sueltan tambien: un `Start` posterior vuelve
	-- a enlazar el marco del HUD de esa sesion. El HUD NO se destruye: es del
	-- `PlayerGui` y no es de este controller.
	bombCooldown = nil
	bombCooldownFill = nil
	bombStateLabel = nil
	bombKeyHint = nil
	_maid = nil
	return true
end

return Controller
