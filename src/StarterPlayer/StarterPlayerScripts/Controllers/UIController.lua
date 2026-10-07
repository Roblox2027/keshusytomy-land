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
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local UTILS = SHARED:WaitForChild("Utils")

local Logger = require(UTILS:WaitForChild("Logger"))
local HudLayout = require(SHARED:WaitForChild("Libraries"):WaitForChild("HudLayout"))
local AudioController = require(script.Parent:WaitForChild("AudioController"))

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

--- Componentes del HUD que este controller usa.
---
--- Son RUTAS, no nombres sueltos: el HUD es un arbol de ZONAS (`Root` ->
--- `TopBar`, `LeftPanel`, ...), y un nombre suelto solo existiria en un unico
--- nivel. La ruta es el CONTRATO con `tools/hud.js`: si el generador mueve un
--- panel de zona, este controller deja de encontrarlo Y LO DICE en el log, en
--- vez de pintar un HUD a medias sin que nadie se entere.
local COMPONENTS = {
	{ key = "World", path = { "Root", "TopBar", "Bar", "PlayerInfo", "World" } },
	{ key = "Level", path = { "Root", "TopBar", "Bar", "PlayerInfo", "Level" } },
	{ key = "PlayerInfo", path = { "Root", "TopBar", "Bar", "PlayerInfo" } },
	{ key = "Currency", path = { "Root", "TopBar", "Bar", "Currency" } },
	{ key = "Mission", path = { "Root", "LeftPanel", "Mission" } },
	{ key = "MissionBody", path = { "Root", "LeftPanel", "Mission", "Body" } },
	{ key = "MissionToggle", path = { "Root", "LeftPanel", "Mission", "Toggle" } },
	{ key = "AudioToggle", path = { "Root", "LeftPanel", "Mission", "AudioToggle" } },
	{ key = "AudioSettings", path = { "Root", "Overlays", "AudioSettings" } },
	{ key = "Objective", path = { "Root", "RightPanel", "Objective" } },
	-- Ciclo dia/noche (FASES 8 y 9). Se declara como RUTA completa, no como una
	-- etiqueta suelta, porque la tarjeta tiene tres: noche, fase y reloj.
	{ key = "NightStatus", path = { "Root", "RightPanel", "NightStatus" } },
	{ key = "ActiveBombs", path = { "Root", "RightPanel", "ActiveBombs" } },
	{ key = "BombStats", path = { "Root", "BottomBar", "ContextActions", "BombStats" } },
	{ key = "PowerupRow", path = { "Root", "BottomBar", "ContextActions", "PowerupRow" } },
	{ key = "BombAction", path = { "Root", "BottomBar", "BombAction" } },
	{ key = "Notifications", path = { "Root", "CenterFeedback", "Notifications" } },
	{ key = "DamageNumbers", path = { "Root", "CenterFeedback", "DamageNumbers" } },
	{ key = "Timer", path = { "Root", "Overlays", "Timer" } },
	{ key = "BossBar", path = { "Root", "Overlays", "BossBar" } },
	{ key = "DamageVignette", path = { "Root", "Overlays", "DamageVignette" } },
}

--- Contenedores que llevan `UIScale`: una sola escala global para todo el HUD.
---
--- Un factor UNICO es lo que conserva la jerarquia entre resoluciones. Si
--- cada panel escalara por su cuenta, dos paneles que en escritorio se
--- tocaban podrian separarse en movil o montarse al reves.
---
--- LA ESCALA VA EN EL CONTENIDO, NO EN LA ZONA.
---
--- MEDIDO EN PLAY (el motivo de este cambio): la escala estaba en las ZONAS, y
--- `UIScale` encoge el rectangulo de la propia zona. Con eso:
---
---   TopBar    ocupaba 890 px de 1113 (Size = (1,0) -> 1113 * 0.80)
---   BottomBar ocupaba 702 px de 1085, y como `BombAction` se ancla al
---             CENTRO de `BottomBar`, la bomba caia en x = 365 en vez de 556
---
--- O sea: la barra no llegaba al borde derecho y la ACCION PRIMARIA no estaba
--- en el centro de la pantalla. Ninguna prueba de codigo lo detectaba, porque
--- el generador declara las zonas ANCLADAS y correctas: el encogimiento lo
--- hacia el `UIScale` en tiempo de ejecucion.
---
--- Por eso cada entrada da la RUTA del CONTENIDO que se escala y el tamano de
--- DISENO de ese contenido, no el de la zona.
local SCALED_CONTENT = {
	{ path = { "TopBar", "Bar" }, width = 640, height = 56 },
	{ path = { "LeftPanel", "Mission" }, width = 260, height = 96 },
	{ path = { "RightPanel", "Objective" }, width = 260, height = 52 },
	{ path = { "BottomBar", "BombAction" }, width = 152, height = 152 },
	{ path = { "BottomBar", "ContextActions" }, width = 300, height = 96 },
	{ path = { "CenterFeedback", "Notifications" }, width = 440, height = 168 },
	{ path = { "Overlays", "AudioSettings" }, width = 300, height = 226 },
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
	-- Ciclo dia/noche: numero de noche, fase, reloj de mundo y si la fase es
	-- una transicion (atardecer o amanecer), que es lo que avisa al jugador.
	-- Se anaden a ESTA lista y no a una aparte porque el HUD tiene un solo
	-- mecanismo para reaccionar a un cambio de atributo: separarlos haria que
	-- un reloj que se actualiza cada medio segundo no refrescara la pantalla.
	"Night",
	"NightPhase",
	"NightPhaseLabel",
	"NightClock",
	"NightTransition",
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

--- Contador monotono de avisos creados.
---
--- Solo sirve para dar un `LayoutOrder` distinto a cada aviso: el `UIListLayout`
--- los apila solo. No es un estado de juego y no se reinicia nunca.
local _notifySequence = 0

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
	-- La POSICION la pone el `UIListLayout` del panel: antes cada aviso
	-- calculaba la suya con el numero de los que habia, y dos avisos
	-- simultaneos se montaban uno encima del otro.
	--
	-- `LayoutOrder` DECRECIENTE: el mas reciente tiene el numero mas bajo, y
	-- como el layout ordena de menor a mayor, el nuevo queda ABAJO y el viejo
	-- se va hacia arriba. Es una pila de avisos, sin calcular nada.
	_notifySequence += 1
	frame.LayoutOrder = -_notifySequence

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
-- -----------------------------------------------------------------------
-- ESCALA RESPONSIVE
-- -----------------------------------------------------------------------
--
-- El HUD NO se coloca con offsets: cada zona se ancla a su esquina y el motor
-- la situa. Lo unico que hay que adaptar al viewport es el FACTOR de escala,
-- y sale de `HudLayout`, el MISMO modulo puro que recorre
-- `tests/shared/HudLayout.spec.lua`. Una sola cuenta para el HUD y para su
-- prueba: si divergieran, el responsive "pasaria" el test y fallaria en Play.
--
-- Se escala la ZONA, no cada panel: dos paneles que se tocan a escala 1 se
-- siguen tocando a escala 0.8, que es justamente la propiedad que el
-- responsive necesita conservar.

--- Localiza un nodo del HUD por su RUTA dentro de `Root`.
--- @param gui any ScreenGui
--- @param path string[] nombres anidados desde `Root`
--- @return any?
local function findByPath(gui: any, path: { string }): any?
	local root = gui and gui:FindFirstChild("Root")
	local node: any = root

	for _, step in ipairs(path) do
		node = node and node:FindFirstChild(step)
	end

	return node
end

--- Localiza la zona por su nombre dentro del HUD.
--- @param gui any ScreenGui
--- @param name string
--- @return any?
local function findZone(gui: any, name: string): any?
	return findByPath(gui, { name })
end

--- Coloca las ACCIONES DE CONTEXTO al LADO de la bomba, o ENCIMA.
---
--- MEDIDO EN PLAY: en vertical estrecho (375 px) el marco de contexto, con su
--- ancho de diseno de 300 px, se montaba ENCIMA de la bomba. Las dos acciones
--- primarias del juego acababan superpuestas y el jugador no sabia cual
--- pulsar.
---
--- La decision NO es un offset inventado aqui: sale de `HudLayout.IsCompact` y
--- `HudLayout.Zones`, que son las MISMAS funciones que recorre
--- `tests/shared/HudLayout.spec.lua`. Una regla de disposicion que viviera solo
--- en el controller seria una disposicion que las pruebas no certificarian.
---
--- Se anchors y escalas, no pixeles: en horizontal el marco se estrecha para
--- caber en el hueco que deja la bomba, y en vertical se apila encima con el
--- mismo ancho que la barra.
--- @param gui any ScreenGui del HUD
--- @param width number ancho de pantalla
local function applyContextLayout(gui: any, width: number)
	local context = findByPath(gui, { "BottomBar", "ContextActions" })

	if not context then
		return
	end

	local margin = HudLayout.MarginFor(width)
	local gap = HudLayout.Gap

	if HudLayout.IsCompact(width) then
		-- Vertical estrecho: NO hay hueco horizontal para dos columnas, asi que
		-- el contexto se apila ENCIMA de la bomba, no encima de ella.
		local bombSize = HudLayout.Metrics.BombAction
		local height = HudLayout.Metrics.BottomLeft

		context.AnchorPoint = Vector2.new(0, 1)
		context.Position = UDim2.new(0, 0, 1, -(bombSize * 0.62 + height + gap))
		context.Size = UDim2.new(1, 0, 0, height)
	else
		-- Horizontal: cabe AL LADO. El ancho es el hueco real que queda entre
		-- el margen y la bomba, con un tope, para no invadir el centro.
		local bombSize = HudLayout.Metrics.BombAction
		local available = width - margin * 2 - bombSize - gap * 2
		local contextWidth = math.max(math.min(300, available), 1)

		context.AnchorPoint = Vector2.new(0, 1)
		context.Position = UDim2.new(0, 0, 1, 0)
		context.Size = UDim2.new(0, contextWidth, 0, HudLayout.Metrics.BottomLeft)
	end
end

--- Aplica a las zonas LATERALES el ancho que corresponde al viewport.
---
--- El generador las declara con un ancho de DISENO (260 px) porque no sabe
--- el tamano de pantalla. Sin corregirlo, en 375 px dos paneles de 260 se
--- montan uno sobre otro: dos hermanos con `Position` a cada lado y un ancho
--- mayor que la mitad de la pantalla ocupan el MISMO rectangulo.
---
--- `HudLayout.SideWidthFor` es la MISMA cuenta que recorre
--- `tests/shared/HudLayout.spec.lua`, y reserva ademas una banda central
--- minima: sin ella, dos paneles que "caben" se tocan en el centro y el hueco
--- de gameplay desaparece.
--- @param gui any ScreenGui del HUD
--- @param width number ancho de pantalla
local function applySideWidths(gui: any, width: number)
	local side = HudLayout.SideWidthFor(width)

	for _, name in ipairs({ "LeftPanel", "RightPanel" }) do
		local node = findZone(gui, name)

		if node then
			node.Size = UDim2.new(0, side, node.Size.Y.Scale, node.Size.Y.Offset)
		end
	end
end

--- Aplica la escala a todas las zonas del HUD.
---
--- Es idempotente: se puede llamar en cada cambio de viewport sin que la
--- escala se multiplique.
--- @param gui any ScreenGui del HUD
local function applyHudScale(gui: any)
	if not gui then
		return
	end

	local camera = Workspace.CurrentCamera

	if not camera then
		return
	end

	local viewport = camera.ViewportSize
	local scale = HudLayout.ScaleFor(viewport.X, viewport.Y)

	-- El ancho de las zonas laterales depende del viewport, asi que se corrige
	-- ANTES de escalar: `FitScale` mide `AbsoluteSize`, y con el ancho de
	-- DISENO mediria una caja que todavia no es la real.
	applySideWidths(gui, viewport.X)
	applyContextLayout(gui, viewport.X)

	for _, entry in ipairs(SCALED_CONTENT) do
		local node = findByPath(gui, entry.path)

		if node then
			local uiScale = node:FindFirstChildOfClass("UIScale")

			if not uiScale then
				uiScale = Instance.new("UIScale")
				uiScale.Name = "Scale"
				uiScale.Parent = node
			end

			-- `FitScale` acota por el CONTENIDO REAL: si el hueco disponible no
			-- llega para el contenido de diseno, el factor baja lo justo. Es la
			-- unica cuenta que puede decir "no cabe" en vez de dejar el panel
			-- saliendose por el borde.
			uiScale.Scale = math.min(
				scale,
				HudLayout.FitScale(
					node.AbsoluteSize.X,
					node.AbsoluteSize.Y,
					entry.width,
					entry.height,
					scale
				)
			)
		else
			Logger.Warn(
				("UIController: no existe %s; no se escala."):format(table.concat(entry.path, "/"))
			)
		end
	end
end

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
	-- Cada panel del HUD generado se registra en `_panels` POR SU RUTA.
	-- `refresh` los usa por nombre, de modo que cambiar el texto del mundo no
	-- obliga a saber nada de la disposicion del resto.
	--
	-- Si una ruta no existe, se avisa al log con la ruta COMPLETA: un
	-- "falta el panel" sin ruta no dice nada, porque en un arbol de zonas
	-- hay muchisimos sitios donde puede faltar.
	-- --------------------------------------------------------------------
	for _, entry in ipairs(COMPONENTS) do
		local node: any = gui

		for _, step in ipairs(entry.path) do
			node = node and node:FindFirstChild(step)
		end

		if not node then
			Logger.Error(
				("UIController: falta '%s' en el HUD."):format(table.concat(entry.path, "/"))
			)
		else
			_panels[entry.key] = node
		end
	end

	-- ---------------------------------------------------------------
	-- ESCALA RESPONSIVE
	--
	-- El HUD ya NO se coloca por pixeles: cada zona se ancla a su esquina y
	-- el motor la situa. Lo que hay que adaptar es la ESCALA, y sale de
	-- `HudLayout`, el mismo modulo que recorre la prueba de resolapamiento.
	--
	-- MEDIDO EN PLAY (antes de esto): la columna derecha se apartaba a mano
	-- con `BombButtonLayout.ResolveRightColumn` porque la bomba vivia en otro
	-- `ScreenGui`. Con la bomba dentro de la zona `BottomBar`, las dos cosas
	-- son HIJAS del mismo arbol y no hay nada que apartar.
	--
	-- Se aplica al enlazar y en cada cambio de viewport, porque una ventana
	-- redimensionada o un movil rotado cambian el factor.
	-- ---------------------------------------------------------------
	applyHudScale(gui)

	-- El plegado de Mission: un panel de misiones que no se puede quitar de
	-- delante estorba, y en pantallas cortas el sitio es scarso.
	--
	-- Solo cambia `Visible` del cuerpo: la cabecera se queda visible para que
	-- siempre se pueda volver a abrir. Sin esto, plegar era imposible y el
	-- panel competia con el gameplay todo el rato.
	local missionToggle = _panels.MissionToggle
	local missionBody = _panels.MissionBody

	if missionToggle and missionBody and missionToggle:IsA("GuiButton") then
		local expanded = true

		if _maid then
			_maid:Connect(missionToggle.MouseButton1Click, function()
				expanded = not expanded
				missionBody.Visible = expanded

				if missionToggle:IsA("TextLabel") or missionToggle:IsA("TextButton") then
					missionToggle.Text = if expanded then "MISIONES  -" else "MISIONES  +"
				end
			end)
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
	makePortalLine(
		"PortalWorld",
		UDim2.new(0, 400, 0, 30),
		UDim2.new(0, 10, 0, 8),
		Color3.fromRGB(235, 240, 255),
		22
	)
	-- LEVEL REQUIRED: el requisito del mundo.
	makePortalLine(
		"PortalRequired",
		UDim2.new(0, 400, 0, 26),
		UDim2.new(0, 10, 0, 42),
		Color3.fromRGB(255, 190, 120),
		18
	)
	-- CURRENT LEVEL: el nivel del jugador. Sin esta linea el cartel dice
	-- "requiere 10" y el jugador no sabe si le falta mucho o poco.
	makePortalLine(
		"PortalCurrent",
		UDim2.new(0, 400, 0, 26),
		UDim2.new(0, 10, 0, 70),
		Color3.fromRGB(170, 200, 255),
		18
	)
	-- MOTIVO: la razon concreta del rechazo (ronda en curso, cooldown...).
	makePortalLine(
		"PortalReason",
		UDim2.new(0, 400, 0, 24),
		UDim2.new(0, 10, 0, 98),
		Color3.fromRGB(230, 230, 240),
		15
	)

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
	setText(
		"World",
		"",
		(if worldName then ("MUNDO: %s"):format(tostring(worldName)) else "MUNDO: --")
	)
	setText("Level", "", ("LV %d"):format(attr("Level") or 1))

	-- ------------------------------------------------------- Ciclo dia/noche
	--
	-- La tarjeta se OCULTA cuando el jugador esta en el lobby: ahi no hay
	-- noche que medir y un "NOCHE 1 / 06:00" fijo seria un dato que no cambia
	-- nunca, que es peor que no mostrarlo.
	--
	-- El reloj se escribe con el texto que publica el servidor (`NightClock`),
	-- no se calcula aqui. La UI no calcula NADA de juego: si el reloj lo
	-- compusiera el cliente, dos clientes verian horas distintas y habria que
	-- depurar el HUD para descubrir que el problema era el reloj.
	local night = attr("Night")
	local clock = attr("NightClock")
	local nightPanel = _panels and _panels.NightStatus

	if nightPanel then
		if type(night) == "number" and type(clock) == "string" then
			nightPanel.Visible = true

			local nightText = nightPanel:FindFirstChild("NightLabel")
			local phaseText = nightPanel:FindFirstChild("PhaseLabel")
			local clockText = nightPanel:FindFirstChild("Clock")

			if nightText and nightText:IsA("TextLabel") then
				-- El ciclo dia/noche sigue siendo ambiental y secundario: no se
				-- presenta como objetivo numerico ni como contador de progreso.
				nightText.Text = "AMBIENTE"
			end

			-- La transicion se marca CON EL MISMO TEXTO, no con un icono ni
			-- con un color: el texto es lo unico que se lee de un vistazo en
			-- movil, y "ATARDECER" escrito ahi avisa mas que un marco rojo.
			local label2 = attr("NightPhaseLabel")
			if phaseText and phaseText:IsA("TextLabel") then
				phaseText.Text = if attr("NightTransition") == true
					then ("%s..."):format(tostring(label2 or ""))
					else tostring(label2 or "")
			end

			if clockText and clockText:IsA("TextLabel") then
				clockText.Text = clock
			end
		else
			-- Sin datos de noche todavia (o en el lobby): no se enseña una
			-- tarjeta vacia.
			nightPanel.Visible = false
		end
	end

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
	setText(
		"Currency",
		"Coins",
		(if type(coins) == "number" then ("%d"):format(coins) else "--"),
		"Value"
	)
	setText(
		"Currency",
		"Gems",
		(if type(gems) == "number" then ("%d"):format(gems) else "--"),
		"Value"
	)

	-- ------------------------------------------------- PlayerInfo (TopBar)
	-- HP y XP viven en la BARRA SUPERIOR: son datos persistentes y el
	-- jugador los mira siempre. Antes estaban en un panel aparte abajo a la
	-- izquierda, que competia con el contador de bombas por el hueco.
	-- HP viene del Humanoid del PROPIO personaje. Es presentacion de si
	-- mismo: el valor que manda para el juego es el del servidor.
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if humanoid then
		setBar(
			"PlayerInfo",
			"HPBar",
			humanoid.Health,
			humanoid.MaxHealth,
			("%d / %d"):format(math.ceil(humanoid.Health), math.ceil(humanoid.MaxHealth))
		)
	else
		setBar("PlayerInfo", "HPBar", nil, nil, "-- / --")
	end

	-- XP. Se publica el total (`XP`) y el nivel; el progreso DENTRO del nivel
	-- no lo inventa la UI: se refleja el dato que llega. La barra queda a 0
	-- porque no hay total de nivel publicado, y el texto lleva la cifra real.
	local xp = attr("XP")
	setBar(
		"PlayerInfo",
		"XPBar",
		nil,
		nil,
		(if type(xp) == "number" then ("XP %d"):format(xp) else "XP --")
	)

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
	setText(
		"BombStats",
		"Bombs",
		(if type(bombs) == "number" then ("%d"):format(bombs) else "*"),
		"Value"
	)

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

		if
			type(attr("PowerupShieldUntil")) == "number"
			and (attr("PowerupShieldUntil") :: number) > now
		then
			table.insert(effects, "ESCUDO")
		end

		if
			type(attr("PowerupSpeedUntil")) == "number"
			and (attr("PowerupSpeedUntil") :: number) > now
		then
			table.insert(effects, "VELOCIDAD")
		end

		if
			type(attr("PowerupFireUntil")) == "number"
			and (attr("PowerupFireUntil") :: number) > now
		then
			table.insert(effects, "PODER")
		end

		-- MEDIDO EN AUDITORIA: la fila solo sabia leer TRES de los powerups
		-- que el servidor publicaba. `Dash`, `Ghost`, `Magnet` y `Freeze`
		--hacian su efecto en el servidor y no se veian en ningun sitio: el
		-- jugador recogia el objeto, notaba el cambio y no tenia forma de
		-- saber si le quedaban dos segundos o diez. Un efecto invisible que
		-- ademas caduca es indistinguible de un powerup roto.
		--
		-- La lista es la de `PowerupService.KINDS` menos los que no tienen
		-- reloj (Bomb da capacidad permanente y Heal es instantaneo), y por
		-- eso los dos que faltan aqui no son un olvido.
		local timed = {
			{ Attribute = "PowerupDashUntil", Label = "IMPULSO" },
			{ Attribute = "PowerupGhostUntil", Label = "FANTASMA" },
			{ Attribute = "PowerupMagnetUntil", Label = "IMAN" },
			{ Attribute = "PowerupFreezeUntil", Label = "CONGELAR" },
		}

		for _, entry in ipairs(timed) do
			local untilTime = attr(entry.Attribute)

			if type(untilTime) == "number" and untilTime > now then
				table.insert(effects, entry.Label)
			end
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
		setText(
			"BombStats",
			"Power",
			("%s%s"):format(
				tostring(coreState),
				if type(charge) == "number" then (" (%d)"):format(charge) else ""
			),
			"Value"
		)
	else
		setText("BombStats", "Power", "--", "Value")
	end

	-- ------------------------------------------------------------ Objective
	-- Con evento activo (mision V2) el panel muestra el EVENTO: etiqueta,
	-- objetivo y cuenta atras, todo publicado por el servidor. Sin evento,
	-- el mundo (que ademas ya esta en la TopBar). La UI no inventa reglas
	-- de juego ni calcula objetivos propios: compone atributos publicados.
	local eventLabel = attr("EventLabel")
	local eventRemaining = attr("EventRemaining")

	if type(eventLabel) == "string" and eventLabel ~= "" then
		local objective = attr("EventObjective")
		local objectiveText = if type(objective) == "string" and objective ~= ""
			then ("  ·  %s"):format(objective)
			else ""
		local timeText = if type(eventRemaining) == "number"
			then ("  ·  %ds"):format(eventRemaining)
			else ""

		setText("Objective", "Text", ("%s%s%s"):format(eventLabel, objectiveText, timeText))
	else
		setText("Objective", "Text", (if worldName then tostring(worldName) else "--"))
	end

	-- -------------------------------------------------------------- Mission
	local claimable = attr("QuestCount")
	local streak = attr("QuestStreak")
	-- El texto vive en `Mission.Body`, no en el panel: la cabecera con el
	-- plegable y el cuerpo son hermanos, y plegar es cambiar `Visible` de UN
	-- hijo en vez de reconstruir el panel.
	setText(
		"MissionBody",
		"Text",
		if type(claimable) == "number"
			then ("Misiones listas: %d%s"):format(
				claimable,
				if type(streak) == "number" and streak > 0
					then ("  racha %d"):format(streak)
					else ""
			)
			else "Misiones: --"
	)

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
			setBar(
				"BossBar",
				"Bar",
				bossHealth,
				bossMax,
				("%d / %d"):format(
					math.ceil(bossHealth),
					if type(bossMax) == "number" then math.ceil(bossMax) else 0
				)
			)
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
		requiredLabel.Text = if required > 0 then ("Requires Level %d"):format(required) else ""
	end

	if currentLabel then
		currentLabel.Text = if required > 0 then ("Current Level %d"):format(current) else ""
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

local function bindAudioSettings(): boolean
	local toggle = _panels.AudioToggle
	local panel = _panels.AudioSettings
	local closeButton = panel and panel:FindFirstChild("Close")
	if not toggle or not panel or not closeButton or not _maid then
		return false
	end

	panel.Visible = false

	local activeSlider: any = nil
	local volumes = AudioController.GetVolumes()

	local function setSliderValue(
		channel: string,
		track: any,
		fill: any,
		valueLabel: any,
		pointerX: number
	)
		local width = track.AbsoluteSize.X
		if width <= 0 then
			return
		end

		local value = math.clamp((pointerX - track.AbsolutePosition.X) / width, 0, 1)
		AudioController.SetVolume(channel, value)
		fill.Size = UDim2.fromScale(value, 1)
		valueLabel.Text = ("%d%%"):format(math.floor(value * 100 + 0.5))
	end

	for _, channel in ipairs({ "Master", "Music", "Sfx", "Ambience", "UI" }) do
		local row = panel:FindFirstChild(channel .. "Row")
		local track = row and row:FindFirstChild("Slider")
		local fill = track and track:FindFirstChild("Fill")
		local valueLabel = row and row:FindFirstChild("Value")
		if not track or not fill or not valueLabel then
			Logger.Warn(("UIController: falta el slider de audio %s."):format(channel))
			continue
		end

		local initial = volumes[channel] or 1
		fill.Size = UDim2.fromScale(initial, 1)
		valueLabel.Text = ("%d%%"):format(math.floor(initial * 100 + 0.5))

		_maid:Connect(track.InputBegan, function(input: any)
			if
				input.UserInputType ~= Enum.UserInputType.MouseButton1
				and input.UserInputType ~= Enum.UserInputType.Touch
			then
				return
			end
			activeSlider = { Channel = channel, Track = track, Fill = fill, Value = valueLabel }
			setSliderValue(channel, track, fill, valueLabel, input.Position.X)
			AudioController.PlayEvent("UiClick")
		end)
	end

	_maid:Connect(UserInputService.InputChanged, function(input: any)
		if not activeSlider then
			return
		end
		if
			input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end
		setSliderValue(
			activeSlider.Channel,
			activeSlider.Track,
			activeSlider.Fill,
			activeSlider.Value,
			input.Position.X
		)
	end)

	_maid:Connect(UserInputService.InputEnded, function(input: any)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			activeSlider = nil
		end
	end)

	_maid:Connect(toggle.Activated, function()
		panel.Visible = not panel.Visible
		AudioController.PlayEvent("UiClick")
	end)
	_maid:Connect(closeButton.Activated, function()
		panel.Visible = false
		AudioController.PlayEvent("UiClick")
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

				bindAudioSettings()
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

	-- RESPONSIVE: la ESCALA se reaplica en cada cambio de viewport.
	--
	-- Se escucha la camara y no el `ScreenGui` porque lo que cambia es el
	-- viewport: un movil que rota, una ventana redimensionada o un PC que
	-- pasa a otra pantalla. Las ZONAS ya estan ancladas, asi que lo unico que
	-- hay que reajustar es el factor de `UIScale`.
	if _gui then
		Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
			applyHudScale(_gui)
		end)

		if Workspace.CurrentCamera then
			Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				applyHudScale(_gui)
			end)
		end
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
				Controller.Notify(
					("+%d MONEDAS"):format(coins - lastCoins),
					Color3.fromRGB(255, 214, 110)
				)
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

		-- KESHUSY CORE: el servidor difunde el estado del nucleo por
		-- `CoreAction`. MEDIDO EN PLAY: NADIE escuchaba ese remoto y el motor
		-- acumulaba "Remote event invocation queue exhausted ... (512 events
		-- dropped)". Un `FireAllClients` sin `OnClientEvent` no es un canal
		-- muerto sin coste: cada difusion se encola y se tira, y el aviso
		-- crece sin limite mientras el nucleo Late.
		--
		-- Aqui se CONSUME la difusion y se convierte en informacion visible:
		-- una activacion se anuncia UNA vez (se compara el contador, no el
		-- estado, porque el nucleo puede volver a Inerte en el mismo tick).
		local lastActivations = nil
		local coreRemote = ReplicatedStorage:FindFirstChild("Remotes")
			and ReplicatedStorage:FindFirstChild("Remotes"):FindFirstChild("CoreAction")
		if coreRemote and coreRemote:IsA("RemoteEvent") then
			_maid:Connect(coreRemote.OnClientEvent, function(state)
				if type(state) ~= "table" then
					return
				end
				local activations = state.ActivationCount
				if type(activations) == "number" then
					if lastActivations ~= nil and activations > lastActivations then
						Controller.Notify("KESHUSY CORE ACTIVADO", Color3.fromRGB(120, 255, 170))
					end
					lastActivations = activations
				end
			end)
		end

		-- Entrada a un mundo. El nombre llega del servidor, asi que el aviso
		-- no puede mentir sobre donde esta el jugador.
		_maid:Connect(player:GetAttributeChangedSignal("World"), function()
			local world = player:GetAttribute("World")
			if world then
				Controller.Notify(
					("ENTRANDO EN %s"):format(tostring(world)),
					Color3.fromRGB(150, 220, 255)
				)
			end
		end)

		-- INTRO DEL BOSS (mision V2, FASE 10): la aparicion del jefe se
		-- anuncia grande. El nombre lo publica el servidor con la barra de
		-- vida, asi que el aviso no puede mentir sobre QUIEN ha salido.
		_maid:Connect(player:GetAttributeChangedSignal("BossName"), function()
			local bossName = player:GetAttribute("BossName")
			if type(bossName) == "string" and bossName ~= "" then
				Controller.Notify(("JEFE: %s"):format(bossName), Color3.fromRGB(255, 110, 100))
			end
		end)

		-- EVENTO DE MUNDO (mision V2): el servidor publica `EventActive`
		-- al abrir un evento; el aviso usa la etiqueta del servidor, que
		-- no puede mentir sobre QUE evento es.
		_maid:Connect(player:GetAttributeChangedSignal("EventActive"), function()
			local eventId = player:GetAttribute("EventActive")
			if type(eventId) == "string" and eventId ~= "" then
				local label = player:GetAttribute("EventLabel")
				Controller.Notify(
					tostring(label ~= "" and label or eventId),
					Color3.fromRGB(255, 170, 120)
				)
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
