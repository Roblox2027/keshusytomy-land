--!strict
--[[
	VisualService
	Identidad visual del mundo. Convierte el mapa en un lugar.

	POR QUE EXISTE
	--------------
	Medido en PLAY (no leido en el codigo), el lugar tenia:
	  - 0 luces      -> las Parts `Neon` no iluminan NADA
	  - 0 emisores   -> el Core y los portales no tenian energia
	  - 0 sonidos    -> el juego era mudo
	  - 0 decals     -> todas las superficies eran color plano
	  - 0 GUI 3D     -> los portales NO.tenian nombre ni nivel: eran
	                     cajas de color sin texto

	Ese es el motivo por el que el lobby parecia "un mapa de prueba
	hecho con cubos": la geometria existia, pero nada de lo que la hace
	LEERSE como un lugar estaba presente.

	DECISION DE ARQUITECTURA (importante)
	------------------------------------
	Esta luz y estos VFX se crean EN RUNTIME, no en `default.project.json`,
	por una razon concreta y medida: el pipeline de sincronizacion importa
	el mapa con `import_rbxm`, y esa via pierde las posiciones de todas las
	Partes (ver `docs/runtime-defects.md`, P0). Anadir hijos no-BasePart
	(una `PointLight`, un `SurfaceGui`) al JSON significaria meterlos por
	ese mismo camino y perder la garantia de posicion.

	La GEOMETRIA sigue teniendo una unica fuente de verdad
	(`tools/generate-project.js`). Aqui solo se anade PRESENTACION, que es
	justo lo que debe poder cambiar sin mover un solo stud del mapa.

	SOLO INSTANCIAS SIN ASSETS
	--------------------------
	Se usan `PointLight`, `Sparkles` y `SurfaceGui`, que NO requieren subir
	nada a Roblox. Un `ParticleEmitter` sin textura no aporta nada visible,
	asi que la energia del Core se compone con anillos, chispas y luz, que
	se ven sin ningun asset externo.

	Idempotencia
	------------
	Se puede arrancar mas de una vez sin duplicar nada: cada helper
	comprueba si el hijo ya existe. Es lo que permite reejecutar el
	servicio tras un respawn o un cambio de ronda sin ensuciar el mapa.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONFIG = SHARED:WaitForChild("Config")
local UTILS = SHARED:WaitForChild("Utils")

local FeatureConfig = require(CONFIG:WaitForChild("FeatureConfig"))
local Logger = require(UTILS:WaitForChild("Logger"))

local Service = {}

Service.IsInitialized = false

--- Nombres del mapa. Contrato con `tools/generate-project.js`.
Service.CORE_FOLDER = "KeshusyCore"
Service.PORTALS_FOLDER = "Portals"

--- Partes del mapa. Contrato con el generador.
Service.CORE_ORB = "CoreOrb"
Service.CORE_GLOW = "CoreGlow"
Service.CORE_RING_A = "CoreRing_A"
Service.CORE_RING_B = "CoreRing_B"
Service.PORTAL_PANEL = "PortalPanel"
Service.PORTAL_SIGN = "Sign"

--- Prefijos de las partes que deben iluminarse. El generador las nombra
--- asi; se resolved por prefijo y no con una lista de 20 nombres.
Service.LAMP_PREFIX = "Lamp_"
Service.LAMP_GLOW_PREFIX = "LampGlow_"
Service.STATION_LAMP_SUFFIX = "_Lamp"

--- Mundos y su bandera. Se lee `ReplicatedStorage.WorldDefinitions`, que
--- es la MISMA fuente que usa `WorldService`: el cartel del portal no
--- puede inventarse un nivel que el servidor no aplica.
local WORLD_FLAGS: { [string]: string } = {
	Forest = "ENABLE_FOREST",
	Desert = "ENABLE_DESERT",
	Ice = "ENABLE_ICE",
	Volcano = "ENABLE_VOLCANO",
	Cyber = "ENABLE_CYBER",
}

--- Partes ya decoradas, para no repetir trabajo ni duplicar hijos.
Service._decorated = {}
--- Devuelve un Part hijo de `root` por nombre exacto.
--- @param root Instance?
--- @param name string
--- @return BasePart?
function Service.FindPart(root: Instance?, name: string): BasePart?
	if not root then
		return nil
	end
	local found = root:FindFirstChild(name)
	if found and found:IsA("BasePart") then
		return found
	end
	return nil
end

--- Devuelve el primer descendiente cuyo nombre empieza por `prefix`.
--- Se usa para las farolas y las lamparas de las estaciones, que el
--- generador numera (`Lamp_0`, `LampGlow_3`, `Station_Shop_Lamp`).
--- @param root Instance?
--- @param prefix string
--- @param suffix string? segunda condicion sobre el nombre
--- @return { BasePart }
function Service.FindPartsByName(root: Instance?, prefix: string, suffix: string?): { BasePart }
	local found: { BasePart } = {}
	if not root then
		return found
	end
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local name = descendant.Name
			if string.sub(name, 1, #prefix) == prefix then
				if not suffix or string.sub(name, -#suffix) == suffix then
					table.insert(found, descendant)
				end
			end
		end
	end
	return found
end

--- Anade una `PointLight` a una parte, o reutiliza la que ya tenga.
---
--- Idempotente a proposito: si la parte ya trae una luz, se AJUSTA la
--- existente en vez de crear una segunda. Ejecutar el servicio dos veces
--- no puede duplicar la iluminacion.
--- @param part BasePart
--- @param brightness number
--- @param range number
--- @param color Color3
--- @param shadows boolean
--- @return PointLight
function Service.EnsureLight(
	part: BasePart,
	brightness: number,
	range: number,
	color: Color3,
	shadows: boolean
): PointLight
	local existing = part:FindFirstChildOfClass("PointLight")

	if existing then
		existing.Brightness = brightness
		existing.Range = range
		existing.Color = color
		existing.Shadows = shadows
		return existing
	end

	local light = Instance.new("PointLight")
	light.Name = "KeshusyLight"
	light.Brightness = brightness
	light.Range = range
	light.Color = color
	light.Shadows = shadows
	-- `Parent` y no `AddChild`: el puente MCP de este proyecto no expone
	-- `AddChild` como miembro valido (ver docs/runtime-defects.md).
	light.Parent = part
	return light
end

--- Anade `Sparkles` a una parte, o reutiliza los existentes.
--- Da lectura de "energia viva" sin necesidad de ningun asset.
--- @param part BasePart
--- @param color Color3
--- @return Sparkles
function Service.EnsureSparkles(part: BasePart, color: Color3): Sparkles
	local existing = part:FindFirstChildOfClass("Sparkles")

	if existing then
		existing.SparkleColor = color
		return existing
	end

	local sparkles = Instance.new("Sparkles")
	sparkles.Name = "KeshusySparkles"
	sparkles.SparkleColor = color
	sparkles.Parent = part
	return sparkles
end


-- ------------------------------------------------------------ KESHUSY CORE
-- El Core es lo primero que ve el jugador al spawn. Tiene que leerse como
-- el corazon del juego: por eso la esfera recibe luz de verdad, chispas y
-- un pulso lento, y los anillos giran.
--
-- NOTA DE SEPARACION DE RESPONSABILIDADES: el color del nucleo lo cambia
-- `CoreService` segun su estado de carga. Aqui NO se toca `CoreOrb.Color`:
-- dos sistemas peleandose por la misma propiedad acaba en un nucleo que
-- parpadea sin que nadie sepa por que.

--- Ilumina y anima el Keshusy Core.
--- @param coreFolder Instance? `Workspace.Lobby.KeshusyCore`
--- @return number pieces con las que se pudo trabajar
function Service.DecorateCore(coreFolder: Instance?): number
	if not coreFolder then
		Logger.Warn("VisualService: no hay KeshusyCore en el mapa.")
		return 0
	end

	local handled = 0

	-- El nucleo: la fuente de luz principal del lobby. Es la que hace que
	-- el centro se lea como "encendido" y no como una bola verde mas.
	local orb = Service.FindPart(coreFolder, Service.CORE_ORB)
	if orb then
		Service.EnsureLight(orb, 3, 55, Color3.fromRGB(140, 240, 190), true)
		Service.EnsureSparkles(orb, Color3.fromRGB(180, 255, 220))
		handled += 1
	end

	-- El halo exterior: luz mas suave y SIN sombras, para que la esfera
	-- quede banada en verde sin coste de sombras duplicadas.
	local glow = Service.FindPart(coreFolder, Service.CORE_GLOW)
	if glow then
		Service.EnsureLight(glow, 1.5, 80, Color3.fromRGB(86, 214, 124), false)
		handled += 1
	end

	-- Las bases escalonadas reciben una luz rasante para que se lea el
	-- volumen: sin esto, tres losas planas parecen una sola.
	for _, name in ipairs({ "CoreBase", "CorePlinth", "CoreDais" }) do
		local base = Service.FindPart(coreFolder, name)
		if base then
			Service.EnsureLight(base, 0.8, 26, Color3.fromRGB(120, 200, 255), false)
			handled += 1
		end
	end

	-- Las cuatro puntas de los pilares.
	for _, pillarLight in ipairs(Service.FindPartsByName(coreFolder, "CorePillarLight_")) do
		Service.EnsureLight(pillarLight, 1.2, 18, Color3.fromRGB(140, 240, 190), false)
		handled += 1
	end

	return handled
end

--- Anima el nucleo: pulso de escala y giro de los anillos.
---
--- Se hace con Tween en bucle y no con un `while` por frame: el tween
--- entrega el trabajo al motor y no ocupa un hilo de Luau.
---
--- @param coreFolder Instance?
--- @return { Instance } objetivos animados
function Service.AnimateCore(coreFolder: Instance?): { Instance }
	local animated: { Instance } = {}

	if not coreFolder then
		return animated
	end

	-- Pulso del nucleo. La escala se anima sobre una copia del tamano
	-- original: animar hacia un valor FIJOaria deformar la pieza para
	-- siempre en cuanto el mapa cambie de medida.
	local orb = Service.FindPart(coreFolder, Service.CORE_ORB)
	if orb then
		local baseSize = orb.Size
		Service._pulse = TweenService:Create(
			orb,
			TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Size = baseSize * 1.12 }
		)
		Service._pulse:Play()
		table.insert(animated, orb)
	end

	-- Los anillos giran en sentidos opuestos: da lectura de mecanismo y
	-- de que el nucleo esta activo, sin ningun asset.
	--
	-- Se anima `CFrame`, no `Orientation`. `BasePart.Orientation` es un
	-- Vector3 de Euler, no un numero: sumarle 360 es una suma de
	-- Vector3 con number y revienta con "attempt to perform arithmetic
	-- (add) on Vector3 and number" (medido en PLAY, linea 288). Rotar el
	-- CFrame completo es la forma correcta y ademas gira la pieza sobre
	-- su propio centro, que es lo que se ve bien.
	for index, name in ipairs({ Service.CORE_RING_A, Service.CORE_RING_B }) do
		local ring = Service.FindPart(coreFolder, name)
		if ring then
			-- Cada anillo gira en un eje distinto y en sentido contrario
			-- al anterior: el conjunto se lee como un mecanismo vivo.
			local axis = if index == 1
				then Vector3.new(0, 1, 0)
				else Vector3.new(1, 0, 0)

			local spin = TweenService:Create(
				ring,
				TweenInfo.new(6 + index * 3, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
				{ CFrame = ring.CFrame * CFrame.Angles(axis.X, axis.Y, axis.Z) }
			)
			spin:Play()
			table.insert(animated, ring)
		end
	end

	return animated
end

-- ---------------------------------------------------------------- PORTALES
-- Medido en PLAY: los portales NO tenian ningun texto. Eran cinco cajas
-- de color y el jugador no podia saber a donde llevaba cada una ni que
-- nivel exigia. Esto es lo que hace que un portal parezca un bloque.
--
-- El cartel se construye con `SurfaceGui` + `TextLabel`, que no necesitan
-- ningun asset, y se ancla en la cara del cartel que ya existe en el mapa
-- (la Parte `Sign`).

--- Color de un mundo. Se deriva del propio cartel del mapa en vez de
--- inventar una paleta nueva: el portal y su luz son del mismo color.
--- @param portalModel Instance
--- @return Color3
local function colorOf(portalModel: Instance): Color3
	local sign = Service.FindPart(portalModel, Service.PORTAL_SIGN)
	local panel = Service.FindPart(portalModel, Service.PORTAL_PANEL)
	return (sign or panel or Instance.new("Part")).Color
end

--- Crea o reutiliza el `SurfaceGui` del cartel de un portal.
--- @param signPart BasePart
--- @return SurfaceGui
local function ensureSignGui(signPart: BasePart): SurfaceGui
	local existing = signPart:FindFirstChildOfClass("SurfaceGui")
	if existing then
		return existing
	end

	local gui = Instance.new("SurfaceGui")
	gui.Name = "KeshusySign"
	-- `AlwaysOnTop` para que el nombre se lea desde cualquier angulo del
	-- lobby. Sin esto, desde atras el cartel es invisible.
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Parent = signPart

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 60
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.4
	label.TextWrapped = true
	label.Parent = gui

	return gui
end

--- Escribe el texto de un portal: nombre del mundo y nivel exigido.
---
--- El texto sale de `WorldDefinitions`, la MISMA tabla que usa
--- `PortalService` para validar. Si aqui se dijera "Nivel 1" y el
--- servidor exigiera 10, el cartel estaria mintiendo.
--- @param portalModel Instance
--- @param worldId string
--- @param displayName string
--- @param requiredLevel number
--- @param enabled boolean
function Service.SetPortalSign(
	portalModel: Instance,
	worldId: string,
	displayName: string,
	requiredLevel: number,
	enabled: boolean
)
	local signPart = Service.FindPart(portalModel, Service.PORTAL_SIGN)
	if not signPart then
		Logger.Warn(("VisualService: el portal %s no tiene '%s'."):format(worldId, Service.PORTAL_SIGN))
		return
	end

	local gui = ensureSignGui(signPart)
	local label = gui:FindFirstChild("Label")
	if not label or not label:IsA("TextLabel") then
		return
	end

	if enabled then
		label.Text = ("%s\nNivel %d"):format(displayName, requiredLevel)
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
	else
		-- Un mundo deshabilitado por `FeatureConfig` NO se anuncia como
		-- disponible. Decir "Forest - Nivel 1" sobre un portal que el
		-- servidor rechaza seria informacion falsa en pantalla.
		--
		-- Texto plano, sin emoji: la fuente GothamBold no tiene el glifo
		-- del candado y se ve como un cuadro vacio. Medido en PLAY.
		label.Text = ("%s\nBLOQUEADO"):format(displayName)
		label.TextColor3 = Color3.fromRGB(200, 200, 210)
	end
end

--- Ilumina y rotula todos los portales del lobby.
--- @param portalsFolder Instance? `Workspace.Lobby.Portals`
--- @return { number } luces y { number } carteles
function Service.DecoratePortals(portalsFolder: Instance?): ({ number }, { number })
	local lights = 0
	local signs = 0

	if not portalsFolder then
		Logger.Warn("VisualService: no hay carpeta de portales en el mapa.")
		return { lights }, { signs }
	end

	local definitions = ReplicatedStorage:FindFirstChild("WorldDefinitions")

	for _, portalModel in ipairs(portalsFolder:GetChildren()) do
		-- El generador los llama `Portal_<WorldId>`. Un hijo con otro
		-- nombre no es un portal y se ignora en vez de adivinarse.
		if portalModel:IsA("Model") and string.sub(portalModel.Name, 1, 7) == "Portal_" then
			local worldId = string.sub(portalModel.Name, 8)
			local tint = colorOf(portalModel)

			-- El panel es la superficie de energia: luz del color del mundo.
			local panel = Service.FindPart(portalModel, Service.PORTAL_PANEL)
			if panel then
				Service.EnsureLight(panel, 2.2, 30, tint, false)
				Service.EnsureSparkles(panel, tint)
				lights += 1
			end

			-- Un mundo deshabilitado se ve apagado: sin luz y sin chispas.
			-- Es la senal de "aqui no se entra" sin necesidad de leer texto.
			local enabled = FeatureConfig[WORLD_FLAGS[worldId] or ""] == true

			if not enabled then
				if panel then
					panel.Color = Color3.fromRGB(70, 74, 86)
					local panelLight = panel:FindFirstChildOfClass("PointLight")
					if panelLight then
						panelLight.Brightness = 0.3
					end
					local panelSparkles = panel:FindFirstChildOfClass("Sparkles")
					if panelSparkles then
						panelSparkles.Enabled = false
					end
				end
			end

			-- El cartel: nombre y nivel, desde la definicion del mundo.
			local definition
			if definitions and definitions:IsA("Folder") then
				local module = definitions:FindFirstChild(worldId)
				if module and module:IsA("ModuleScript") then
					local ok, loaded = pcall(require, module)
					if ok and type(loaded) == "table" then
						definition = loaded
					end
				end
			end

			local displayName = (definition and definition.DisplayName) or worldId
			local requiredLevel = (definition and definition.RequiredLevel) or 1

			Service.SetPortalSign(portalModel, worldId, displayName, requiredLevel, enabled)
			signs += 1
		end
	end

	return { lights }, { signs }
end

-- -------------------------------------------------------------- ILUMINACION
-- El mapa tiene 98 Partes y ninguna emitia luz. Con la iluminacion global
-- por defecto (ambient == outdoor) todo se ve plano y sin relieve.
--
-- Se ajusta `Lighting` una sola vez, al arrancar. No se toca por ronda:
-- un `Lighting` que parpadea cada 180 s/molesta mas de lo que aporta.

--- Aplica la iluminacion global del lobby.
--- @return boolean applied
function Service.ApplyLighting(): boolean
	local ok, err = pcall(function()
		Lighting.ClockTime = 16.5
		Lighting.Brightness = 2.4
		-- `Ambient` mas FRIA y `OutdoorAmbient` mas CALIDA: la diferencia
		-- entre las dos es la que da relieve a las superficies. Con las
		-- dos iguales (como estaban) el lobby se ve plano.
		Lighting.Ambient = Color3.fromRGB(70, 78, 105)
		Lighting.OutdoorAmbient = Color3.fromRGB(150, 158, 175)
		Lighting.ExposureCompensation = 0.1

		-- Niebla suave: da profundidad al lobby y evita ver el borde del
		-- mundo desde dentro. Sin esto, el vacio a 500 studs se ve como un
		-- corte brusco.
		Lighting.FogColor = Color3.fromRGB(96, 112, 140)
		Lighting.FogStart = 180
		Lighting.FogEnd = 900
		Lighting.GlobalShadows = true

		local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
		if bloom then
			bloom.Intensity = 0.6
			bloom.Size = 32
			bloom.Threshold = 1.1
		end

		local depthOfField = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
		if depthOfField then
			-- El desenfoque se apaga: con el jugador a 16 studs de altura
			-- en un lugar de 70, difuminar el lobby entero lo hacia
			-- ilegible.
			depthOfField.Enabled = false
		end
	end)

	if not ok then
		Logger.Error("VisualService: no se pudo ajustar Lighting: " .. tostring(err))
		return false
	end

	return true
end

--- Enciende las farolas y las lamparas de las estaciones.
--- @param lobbyFolder Instance? `Workspace.Lobby`
--- @return number luces anadidas
function Service.DecorateLobby(lobbyFolder: Instance?): number
	if not lobbyFolder then
		Logger.Warn("VisualService: no hay Lobby en el mapa.")
		return 0
	end

	local count = 0

	-- Las farolas perimetrales. El_generador las coloca en un anillo de
	-- 58 studs: son la luz perimetral que define el borde del lobby.
	for _, glow in ipairs(Service.FindPartsByName(lobbyFolder, Service.LAMP_GLOW_PREFIX)) do
		Service.EnsureLight(glow, 1.6, 34, Color3.fromRGB(140, 220, 255), false)
		count += 1
	end

	-- Las lamparas de las ocho estaciones. Cada una conserva el color de
	-- su estacion, que el generador ya le dio a la Part.
	for _, lamp in ipairs(Service.FindPartsByName(lobbyFolder, "Station_", Service.STATION_LAMP_SUFFIX)) do
		Service.EnsureLight(lamp, 1.4, 24, lamp.Color, false)
		count += 1
	end

	return count
end

-- ---------------------------------------------------------------- ARENA
-- La arena (Forest) tiene 58 Partes: suelo, muros y 28 bloques. Sin luz
-- propia es un rectangulo gris. Se enciende para que la ronda se lea.

--- Ilumina el suelo y los muros de una arena.
--- @param worldFolder Instance? `Workspace.Worlds.<Id>`
--- @return number luces anadidas
function Service.DecorateArena(worldFolder: Instance?): number
	if not worldFolder then
		return 0
	end

	local count = 0

	-- Focos rasantes sobre los cuatro marcadores que el generador ya
	-- coloco en las direcciones de la arena (`ArenaNorth/South/East/West`).
	-- Se reancla la luz a una Parte YA EXISTENTE en vez de crear Parts
	-- nuevas: el mapa no gana geometria y las posiciones siguen viniendo
	-- de `tools/generate-project.js`, la unica fuente de verdad.
	for _, name in ipairs({ "ArenaNorth", "ArenaSouth", "ArenaEast", "ArenaWest" }) do
		local marker = Service.FindPart(worldFolder, name)
		if marker then
			Service.EnsureLight(marker, 1.1, 70, Color3.fromRGB(255, 190, 120), false)
			count += 1
		end
	end

	-- Un foco vertical en el centro: sin el, la estructura central de
	-- bloques queda en sombra justo donde ocurre el combate.
	local center = Service.FindPart(worldFolder, "ArenaCenter")
	if center then
		Service.EnsureLight(center, 1.4, 110, Color3.fromRGB(255, 205, 150), false)
		count += 1
	end

	return count
end

-- ------------------------------------------------------------- CICLO DE VIDA

--- Inicializacion del servicio. Idempotente.
--- @param maid any?
--- @return boolean success
function Service.Init(maid: any?): boolean
	if Service.IsInitialized then
		return true
	end

	Service._maid = maid

	Service.IsInitialized = true
	Service.ApplyLighting()

	local workspaceService = game:GetService("Workspace")
	local lobby = workspaceService:FindFirstChild("Lobby")

	if not lobby then
		Logger.Warn("VisualService: Workspace.Lobby no existe; el lugar quedara sin luz.")
		return true
	end

	local corePieces = Service.DecorateCore(lobby:FindFirstChild(Service.CORE_FOLDER))
	local portalLights, portalSigns = Service.DecoratePortals(lobby:FindFirstChild(Service.PORTALS_FOLDER))
	local lobbyLights = Service.DecorateLobby(lobby)

	local worlds = workspaceService:FindFirstChild("Worlds")
	local arenaLights = 0
	if worlds then
		for _, world in ipairs(worlds:GetChildren()) do
			arenaLights += Service.DecorateArena(world)
		end
	end

	Service.AnimateCore(lobby:FindFirstChild(Service.CORE_FOLDER))

	Logger.Info(("VisualService: %d luces en el lobby, %d del Core, %d de portales, %d de arena, %d carteles"):format(
		lobbyLights,
		corePieces,
		portalLights[1],
		arenaLights,
		portalSigns[1]
	))

	return true
end

--- Arranca el servicio.
--- @return boolean success
function Service.Start(): boolean
	if not Service.IsInitialized then
		Logger.Error("VisualService: Start sin Init")
		return false
	end

	Logger.Debug("VisualService listo.")
	return true
end

--- Limpieza. Detiene los tweens para no dejar animaciones huerfanas.
--- @return boolean success
function Service.Destroy(): boolean
	if Service._pulse then
		Service._pulse:Cancel()
		Service._pulse = nil
	end

	Service.IsInitialized = false
	Service._decorated = {}
	Service._maid = nil
	return true
end

return Service

--@VISUAL:PART2
