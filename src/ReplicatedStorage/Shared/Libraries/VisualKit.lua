--!strict
--[[
	VisualKit
	Constructores de MODELOS VISIBLES. Sin assets: solo `Part`, `PointLight`,
	`BillboardGui` y `ParticleEmitter` sin textura.

	POR QUE EXISTE
	--------------
	Medido en PLAY (no ledo en el codigo), las tres entidades centrales del
	juego eran CAJAS:

	  Bomba    -> 1 `Part` Ball 2x2x2 Neon roja. Sin fusible, sin tapa, sin
	              radio, sin mecha visible, sin etiqueta. Crecer no es una
	              animacion de bomba: es una esfera que engorda.
	  Monstruo -> 1 `Part` 3x3x3 (`Body`) + raiz invisible. Sin ojos, sin
	              nombre, sin vida visible, sin feedback al recibir dano.
	  Explosion-> una Part invisible con dos emisores. Se ve una nube, pero
	              no se ve la ONDA ni el NUCLEO, que es lo que comunica el
	              radio.

	Este modulo es la CAPA VISUAL. La capa de juego (vida, dano, estado,
	IA) sigue en los servicios: aqui no se decide nada, solo se dibuja.

	DOS CAPAS, SIEMPRE
	------------------
	Un enemigo puede existir en el servidor y seguir siendo invisible; una
	bomba puede ser un dato valido y no verse. Por eso aqui se construye un
	`Model` con `PrimaryPart`, partes visibles, cartel y luz, no un campo de
	atributos.

	SIN ASSETS
	---------
	No se inventa ningun assetId. Todo lo que se ve aqui se ve sin subir
	nada a Roblox: formas, materiales, luces y texto.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONFIG = SHARED:WaitForChild("Config")

local GameConfig = require(CONFIG:WaitForChild("GameConfig"))
local MonsterScaleRules = require(SHARED:WaitForChild("Libraries"):WaitForChild("MonsterScaleRules"))

local VisualKit = {}

-- ---------------------------------------------------------------------------
-- PALETA
-- ---------------------------------------------------------------------------

--- Color de la bomba segun el mundo. Misma MECANICA, distinta PIEL: entrar
--- por un portal tiene que notarse, y un unico color para cinco mundos lo
--- hacia invisible.
--- @param worldId string?
--- @return { body: Color3, top: Color3, fuse: Color3, glow: Color3, ring: Color3 }
function VisualKit.BombSkin(worldId: string?): { body: Color3, top: Color3, fuse: Color3, glow: Color3, ring: Color3 }
	local id = worldId or "Forest"

	if id == "Desert" then
		return {
			body = Color3.fromRGB(196, 138, 52),
			top = Color3.fromRGB(120, 88, 40),
			fuse = Color3.fromRGB(255, 226, 140),
			glow = Color3.fromRGB(255, 190, 90),
			ring = Color3.fromRGB(255, 200, 110),
		}
	elseif id == "Ice" then
		return {
			body = Color3.fromRGB(96, 186, 232),
			top = Color3.fromRGB(56, 116, 160),
			fuse = Color3.fromRGB(220, 250, 255),
			glow = Color3.fromRGB(150, 230, 255),
			ring = Color3.fromRGB(150, 225, 255),
		}
	elseif id == "Volcano" then
		return {
			body = Color3.fromRGB(226, 78, 42),
			top = Color3.fromRGB(70, 30, 24),
			fuse = Color3.fromRGB(255, 236, 150),
			glow = Color3.fromRGB(255, 130, 50),
			ring = Color3.fromRGB(255, 140, 60),
		}
	elseif id == "Cyber" then
		return {
			body = Color3.fromRGB(64, 220, 232),
			top = Color3.fromRGB(24, 60, 84),
			fuse = Color3.fromRGB(230, 255, 255),
			glow = Color3.fromRGB(90, 240, 255),
			ring = Color3.fromRGB(80, 230, 255),
		}
	end

	-- Forest: negro grafito con banda Keshusy. Es la bomba CLASSICA.
	return {
		body = Color3.fromRGB(38, 40, 52),
		top = Color3.fromRGB(88, 96, 118),
		fuse = Color3.fromRGB(255, 226, 150),
		glow = Color3.fromRGB(255, 170, 70),
		ring = Color3.fromRGB(255, 140, 90),
	}
end

--- Medidas de la bomba en studs. Centralizadas para que "una bomba que se
--- ve desde la arena" sea una decision y no un numero escrito dos veces.
VisualKit.BOMB = {
	BodySize = 3,
	TopSize = Vector3.new(1.4, 0.9, 1.4),
	FuseSize = Vector3.new(0.28, 1.5, 0.28),
	TipSize = Vector3.new(0.7, 0.7, 0.7),
	RootSize = Vector3.new(4, 4, 4),
}

-- ---------------------------------------------------------------------------
-- PIEZAS
-- ---------------------------------------------------------------------------

--- Crea una parte anclada con las propiedades visuales ya resueltas.
--- @param name string
--- @param size Vector3
--- @param cframe CFrame
--- @param color Color3
--- @param opts table? { shape, material, transparency, collide }
--- @return Part
local function makePart(
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	opts: { shape: Enum.PartType?, material: Enum.Material?, transparency: number?, collide: boolean? }?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Anchored = true
	part.CanCollide = if opts and opts.collide ~= nil then opts.collide else false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = if opts and opts.transparency and opts.transparency > 0.5 then false else true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	if opts then
		if opts.shape then
			part.Shape = opts.shape
		end
		if opts.material then
			part.Material = opts.material
		end
		if opts.transparency then
			part.Transparency = opts.transparency
		end
	end

	return part
end

VisualKit.MakePart = makePart
-- ---------------------------------------------------------------------------
-- BOMBA
-- ---------------------------------------------------------------------------

--- Construye la BOMBA VISIBLE completa.
---
--- Devuelve un `Model` con `Root` (invisible, `PrimaryPart`), `BombBody`,
--- `BombBand`, `BombTop`, `Fuse`, `FuseGlow`, `RadiusIndicator`,
--- `Attachment` (`ExplosionOrigin`), `Particles` y `Timer` (BillboardGui).
---
--- El `RadiusIndicator` es un disco tumbado del RADIO REAL de dano: es lo
--- que ensena "dentro de esta zona me puede dano" sin una linea de tutorial.
--- @param worldId string?
--- @param position Vector3
--- @param radius number
--- @return Model?
function VisualKit.BuildBomb(worldId: string?, position: Vector3, radius: number): Model?
	local skin = VisualKit.BombSkin(worldId)
	local dims = VisualKit.BOMB

	-- Radio de explosion con suelo de 8 studs: por debajo el aro no se
	-- distingue de una mancha y el jugador aprende mal la zona de peligro.
	local safeRadius = if radius and radius >= 8 then radius else GameConfig.DefaultBombRadius

	local model = Instance.new("Model")
	model.Name = "Bomb"

	-- Raiz invisible: es la que se mueve y de la que cuelga el cartel. Sin
	-- `PrimaryPart` el modelo no se coloca de forma fiable.
	local root = makePart("Root", dims.RootSize, CFrame.new(position), Color3.new(1, 1, 1), {
		transparency = 1,
	})
	model.PrimaryPart = root
	root.Parent = model

	local body = makePart(
		"BombBody",
		Vector3.new(dims.BodySize, dims.BodySize, dims.BodySize),
		CFrame.new(position),
		skin.body,
		{ shape = Enum.PartType.Ball, material = Enum.Material.Metal }
	)
	body.Parent = model

	-- Banda Keshusy: el detalle que la hace del universo y no generica.
	local band = makePart(
		"BombBand",
		Vector3.new(dims.BodySize * 1.03, 0.5, dims.BodySize * 1.03),
		CFrame.new(position),
		skin.glow,
		{ material = Enum.Material.Neon }
	)
	band.Parent = model

	-- Tapa: sin ella la bomba es "una bola". Con ella se lee como bomba.
	local top = makePart(
		"BombTop",
		dims.TopSize,
		CFrame.new(position + Vector3.new(0, dims.BodySize / 2 + dims.TopSize.Y / 2, 0)),
		skin.top,
		{ material = Enum.Material.Metal }
	)
	top.Parent = model

	-- Fusible inclinado: la silueta que dice "esto va a explotar".
	local fuse = makePart(
		"Fuse",
		dims.FuseSize,
		CFrame.new(position + Vector3.new(0.5, dims.BodySize / 2 + dims.TopSize.Y + 0.5, 0))
			* CFrame.Angles(math.rad(-24), 0, 0),
		skin.fuse,
		{ material = Enum.Material.SmoothPlastic }
	)
	fuse.Parent = model

	local tipCFrame = CFrame.new(position + Vector3.new(1.05, dims.BodySize / 2 + dims.TopSize.Y + 1.15, 0))
	local tip = makePart("FuseGlow", dims.TipSize, tipCFrame, skin.glow, {
		shape = Enum.PartType.Ball,
		material = Enum.Material.Neon,
	})
	tip.Parent = model

	-- Luz del fusible: sin ella la punta es un punto en una arena a oscuras.
	local light = Instance.new("PointLight")
	light.Name = "FuseLight"
	light.Color = skin.glow
	light.Brightness = 2
	light.Range = 18
	light.Shadows = false
	light.Parent = tip

	-- Chispas del fusible. `Rate = 0` y emision manual desde el servicio: el
	-- servidor decide CUANDO hay chispas, no el motor por su cuenta.
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "Particles"
	sparks.Color = ColorSequence.new(skin.glow, Color3.fromRGB(90, 60, 40))
	sparks.Lifetime = NumberRange.new(0.2, 0.45)
	sparks.Speed = NumberRange.new(3, 8)
	sparks.SpreadAngle = Vector2.new(30, 30)
	sparks.Rate = 0
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparks.Parent = tip

	-- Zona de peligro. Tumbada en el suelo, translucida y SIN colision: se ve
	-- desde cualquier angulo y no estorba el juego.
	local ring = makePart(
		"RadiusIndicator",
		Vector3.new(safeRadius * 2, 0.2, safeRadius * 2),
		CFrame.new(position - Vector3.new(0, dims.BodySize / 2 - 0.4, 0)),
		skin.ring,
		{ material = Enum.Material.Neon, transparency = 0.55 }
	)
	ring.Shape = Enum.PartType.Cylinder
	ring.Orientation = Vector3.new(0, 0, 90)
	ring:SetAttribute("BombRadius", safeRadius)
	ring.Parent = model

	-- Origen de la explosion: punto unico y con nombre, para que el servicio
	-- no tenga que decidir cual de las partes es "el centro".
	local attachment = Instance.new("Attachment")
	attachment.Name = "ExplosionOrigin"
	attachment.Parent = root

	-- Mecha visible sobre la bomba. El jugador no tiene que mirar el HUD
	-- para saber cuanto le queda.
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Timer"
	billboard.Adornee = root
	billboard.Size = UDim2.fromOffset(120, 46)
	billboard.StudsOffset = Vector3.new(0, 3.4, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 220
	billboard.Parent = root

	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundColor3 = Color3.fromRGB(16, 18, 26)
	holder.BackgroundTransparency = 0.15
	holder.BorderSizePixel = 0
	holder.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = holder

	local stroke = Instance.new("UIStroke")
	stroke.Color = skin.glow
	stroke.Thickness = 1.5
	stroke.Transparency = 0.3
	stroke.Parent = holder

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBold
	label.Text = "3"
	label.TextColor3 = skin.glow
	label.TextSize = 24
	label.TextScaled = false
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = holder

	model:SetAttribute("VisualRadius", safeRadius)
	model:SetAttribute("FuseRemaining", GameConfig.DefaultBombFuseTime)

	return model
end
-- ---------------------------------------------------------------------------
-- MONSTER
-- ---------------------------------------------------------------------------

--- Forma del cuerpo por definicion. Un cubo para todos los bichos hace que el
--- jugador no distinga "un Slime" de "un Cyber Stalker" ni de un bloque.
--- @param def table
--- @return { shape: Enum.PartType, size: Vector3, accent: Color3, style: string }
local function monsterShape(def: any): { shape: Enum.PartType, size: Vector3, accent: Color3, style: string }
	local id = tostring(def.Id or "")

	if id == "Slime" then
		return {
			shape = Enum.PartType.Ball,
			size = Vector3.new(3.4, 3, 3.4),
			accent = Color3.fromRGB(240, 250, 240),
			style = "Slime",
		}
	elseif id == "BombBug" or id == "BomberMonster" then
		return {
			shape = Enum.PartType.Block,
			size = Vector3.new(3, 2.6, 3.6),
			accent = Color3.fromRGB(255, 214, 120),
			style = "Bug",
		}
	elseif id == "Shadow" then
		return {
			shape = Enum.PartType.Block,
			size = Vector3.new(2.8, 3.6, 2.8),
			accent = Color3.fromRGB(180, 120, 255),
			style = "Wisp",
		}
	elseif id == "Hunter" or id == "Guardian" then
		return {
			shape = Enum.PartType.Block,
			size = Vector3.new(4, 3.4, 4.4),
			accent = Color3.fromRGB(255, 226, 170),
			style = "Burrower",
		}
	elseif id == "IceBeast" then
		return {
			shape = Enum.PartType.Block,
			size = Vector3.new(4, 3.4, 4),
			accent = Color3.fromRGB(200, 245, 255),
			style = "Crystal",
		}
	elseif id == "FireBeast" then
		return {
			shape = Enum.PartType.Block,
			size = Vector3.new(4.2, 3.4, 4.2),
			accent = Color3.fromRGB(255, 190, 90),
			style = "Magma",
		}
	elseif id == "CyberStalker" then
		return {
			shape = Enum.PartType.Block,
			size = Vector3.new(3.2, 3.8, 3.2),
			accent = Color3.fromRGB(90, 255, 255),
			style = "Drone",
		}
	end

	return {
		shape = Enum.PartType.Block,
		size = Vector3.new(3, 3, 3),
		accent = Color3.fromRGB(240, 240, 240),
		style = "Plain",
	}
end

VisualKit.MonsterShape = monsterShape

--- Construye el MODELO VISIBLE de un monstruo.
---
--- Devuelve un `Model` con `Root` (invisible, `PrimaryPart`), `Body`, ojos,
--- `Highlight` y `NameTag` (BillboardGui con nombre y vida).
--- @param def table definicion de `MonsterDefinitions`
--- @return Model?
function VisualKit.BuildMonster(def: any): Model?
	local shape = monsterShape(def)

	-- ESCALA VISUAL.
	--
	-- El modelo se dibuja MULTIPLICADO por la escala del bicho y por la del
	-- mundo. Es la razon por la que un Guardian se ve claramente mas alto
	-- que el jugador y por la que un Cyber Stalker se ve mas imposing que
	-- un Slime del Forest.
	--
	-- El mundo se aplica aqui y NO en la hitbox: un enemigo puede verse mas
	-- grande en un mundo que en otro sin que sus colisiones cambien, y asi
	-- la dificultad se comunica sin volver los pasillos intransitables.
	--
	-- La ESCALA FINAL se mide contra el JUGADOR, no contra la forma de este
	-- bicho. Multiplicar la forma base directamente hacia que un Slime
	-- declarado 1.4 midiera 4.2 studs frente a un jugador de 5.5, es decir,
	-- mas bajo que el jugador justo cuando el diseno dice que es un 40 % mas
	-- alto. `Rules.BodySize` es quien aplica la escala; aqui solo se decide
	-- CUANTAS veces.
	local finalScale: number = (def.VisualScale or 1) * (def.WorldScale or 1)
	local bodySize = MonsterScaleRules.BodySize(shape.size, finalScale)
	local size: Vector3 = Vector3.new(bodySize.X, bodySize.Y, bodySize.Z)

	local model = Instance.new("Model")
	model.Name = ("Monster_%s"):format(tostring(def.Id))

	-- HITBOX: raiz invisible, proporcional al modelo y acotada por
	-- `MonsterScaleRules`.
	--
	-- Antes la raiz era del mismo tamano que el cuerpo, y con el cuerpo
	-- agrandado eso hacia que un Guardian bloqueara el pasillo entero. La
	-- proporcion sale de la definicion, que ya la tiene acotada, y se
	-- vuelve a acotar aqui porque este es el ULTIMO sitio donde un valor
	-- desatendido se convierte en una pared invisible.
	local hitboxRatio: number = def.HitboxScale or MonsterScaleRules.DefaultHitboxRatio
	local rootSize: Vector3 = size * math.clamp(hitboxRatio, MonsterScaleRules.MinHitboxRatio, MonsterScaleRules.MaxHitboxRatio)

	local root = makePart("Root", rootSize, CFrame.new(), Color3.new(1, 1, 1), {
		transparency = 1,
		collide = true,
	})
	root:SetAttribute("IsHitbox", true)
	root:SetAttribute("VisualScale", finalScale)
	root:SetAttribute("HitboxRatio", rootSize.Magnitude / math.max(size.Magnitude, 0.001))
	model.PrimaryPart = root
	root.Parent = model

	local body = makePart(
		"Body",
		size,
		CFrame.new(),
		def.Color or Color3.fromRGB(140, 190, 140),
		{
			shape = shape.shape,
			material = def.Material or Enum.Material.SmoothPlastic,
			collide = true,
		}
	)
	body:SetAttribute("MonsterId", def.Id)
	body.Parent = model

	-- Ojos: la diferencia entre "una criatura" y "una caja con vida". Cuelgan
	-- del root, asi que miran hacia donde mire el modelo sin codigo extra.
	--
	-- El tamano de los ojos TAMBIEN escala. Con un ojo de tamano fijo, el
	-- Guardian de 2.1 tendria unos ojos diminutos y deja de tener cara: la
	-- expresion es justo lo que hace que un bicho grande se lea como una
	-- criatura y no como un mueble.
	local eyeSize = Vector3.new(size.X * 0.15, size.Y * 0.2, size.Z * 0.09)
	local eyeHeight = size.Y * 0.18
	local eyeSpread = size.X * 0.22
	local eyeDepth = -(size.Z / 2) - 0.08

	local eyeLeft = makePart(
		"EyeLeft",
		eyeSize,
		CFrame.new(-eyeSpread, eyeHeight, eyeDepth),
		shape.accent,
		{ shape = Enum.PartType.Ball, material = Enum.Material.Neon }
	)
	eyeLeft.Parent = root

	local eyeRight = makePart(
		"EyeRight",
		eyeSize,
		CFrame.new(eyeSpread, eyeHeight, eyeDepth),
		shape.accent,
		{ shape = Enum.PartType.Ball, material = Enum.Material.Neon }
	)
	eyeRight.Parent = root

	-- Detalles por tematica: lo que separa a un mundo de otro de un vistazo.
	if shape.style == "Bug" then
		for _, side in ipairs({ -1, 1 }) do
			local antenna = makePart(
				"Antenna_" .. tostring(side),
				Vector3.new(size.X * 0.06, size.Y * 0.36, size.Z * 0.06),
				CFrame.new(side * (size.X * 0.3), size.Y * 0.5 + 0.4, 0)
					* CFrame.Angles(math.rad(side * 12), 0, 0),
				shape.accent,
				{ material = Enum.Material.Neon }
			)
			antenna.Parent = root

			local tipBall = makePart(
				"AntennaTip_" .. tostring(side),
				Vector3.new(size.X * 0.17, size.Y * 0.17, size.Z * 0.17),
				CFrame.new(side * (size.X * 0.34), size.Y * 0.5 + 0.95, 0),
				Color3.fromRGB(255, 120, 90),
				{ shape = Enum.PartType.Ball, material = Enum.Material.Neon }
			)
			tipBall.Parent = root
		end
	elseif shape.style == "Crystal" or shape.style == "Magma" then
		-- Puntas: cristales de hielo o esquirlas de magma.
		local count = 5
		local spikeShape = if shape.style == "Crystal" then Enum.PartType.Ball else Enum.PartType.Block

		for index = 1, count do
			local angle = (index / count) * math.pi * 2
			local spike = makePart(
				"Spike_" .. index,
				Vector3.new(size.X * 0.2, size.Y * 0.46, size.Z * 0.2),
				CFrame.new(
					math.cos(angle) * (size.X * 0.34),
					size.Y * 0.5 + 0.5,
					math.sin(angle) * (size.Z * 0.34)
				) * CFrame.Angles(math.rad(18), 0, 0),
				shape.accent,
				{ material = Enum.Material.Neon, shape = spikeShape }
			)
			spike.Parent = root
		end
	elseif shape.style == "Drone" then
		local visor = makePart(
			"Visor",
			Vector3.new(size.X * 0.7, 0.5, 0.25),
			CFrame.new(0, eyeHeight + 0.4, eyeDepth - 0.05),
			Color3.fromRGB(90, 255, 255),
			{ material = Enum.Material.Neon }
		)
		visor.Parent = root

		local aerial = makePart(
			"Aerial",
			Vector3.new(size.X * 0.045, size.Y * 0.53, size.Z * 0.045),
			CFrame.new(0, size.Y * 0.5 + 0.8, 0),
			Color3.fromRGB(200, 255, 255),
			{ material = Enum.Material.Neon }
		)
		aerial.Parent = root
	elseif shape.style == "Slime" then
		-- Gota interior: da volumen a un cuerpo translucido.
		local core = makePart(
			"Core",
			Vector3.new(size.X * 0.35, size.Y * 0.35, size.Z * 0.35),
			CFrame.new(0, -size.Y * 0.15, 0),
			Color3.fromRGB(60, 140, 80),
			{ shape = Enum.PartType.Ball, material = Enum.Material.SmoothPlastic }
		)
		core.Transparency = 0.35
		core.Parent = root
	elseif shape.style == "Wisp" then
		local aura = Instance.new("PointLight")
		aura.Name = "Aura"
		aura.Color = shape.accent
		aura.Brightness = 1.6
		aura.Range = 14
		aura.Shadows = false
		aura.Parent = root
	end

	-- ARO DE TELEGRAPH: se enciende cuando el monstruo AVISA de una carga.
	--
	-- Es la segunda mitad del aviso. El cartel "!" dice "va a atacar"; este aro
	-- dice "y lo hara en esta direccion y en este radio". Un enemigo que ataca
	-- de frente y a los lados no puede esquivarse solo con mirar: hay que ver
	-- el area.
	--
	-- Nace INVISIBLE (`Transparency = 1`) y no colisiona ni consulta nada:
	-- una pieza invisible que colisiona es un obstaculo fantasma, y el jugador
	-- pierde la bomba sin entender por que. `onStateChanged` lo enciende.
	local telegraph = makePart(
		"TelegraphGlow",
		Vector3.new(size.X * 2.2, 0.25, size.Z * 2.2),
		CFrame.new(0, -size.Y * 0.5 + 0.2, 0),
		Color3.fromRGB(255, 92, 72),
		{
			shape = Enum.PartType.Cylinder,
			material = Enum.Material.Neon,
			transparency = 1,
			collide = false,
		}
	)
	telegraph.CFrame = telegraph.CFrame * CFrame.Angles(0, 0, math.rad(90))
	telegraph.Parent = root

	-- Contorno: separa al monstruo del fondo. Sin assets, un `Highlight` con
	-- `FillTransparency = 1` es exactamente un borde.
	local highlight = Instance.new("Highlight")
	highlight.Name = "Highlight"
	highlight.Adornee = model
	highlight.FillTransparency = 1
	highlight.OutlineColor = shape.accent
	highlight.OutlineTransparency = 0.55
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model

	-- Cartel: NOMBRE y VIDA. Sin esto el jugador ve "algo" y no sabe si es un
	-- enemigo debil o el jefe.
	local tag = Instance.new("BillboardGui")
	tag.Name = "NameTag"
	tag.Adornee = root
	tag.Size = UDim2.fromOffset(150, 56)
	tag.StudsOffset = Vector3.new(0, size.Y * 0.5 + 1.6, 0)
	tag.AlwaysOnTop = true
	tag.MaxDistance = 140
	tag.Parent = root

	local tagFrame = Instance.new("Frame")
	tagFrame.Name = "Holder"
	tagFrame.Size = UDim2.fromScale(1, 1)
	tagFrame.BackgroundColor3 = Color3.fromRGB(14, 16, 24)
	tagFrame.BackgroundTransparency = 0.25
	tagFrame.BorderSizePixel = 0
	tagFrame.Parent = tag

	local tagCorner = Instance.new("UICorner")
	tagCorner.CornerRadius = UDim.new(0, 8)
	tagCorner.Parent = tagFrame

	local tagName = Instance.new("TextLabel")
	tagName.Name = "Name"
	tagName.Size = UDim2.new(1, 0, 0, 22)
	tagName.Position = UDim2.fromOffset(0, 0)
	tagName.BackgroundTransparency = 1
	tagName.BorderSizePixel = 0
	tagName.Font = Enum.Font.GothamBold
	tagName.Text = tostring(def.Name or def.Id)
	tagName.TextColor3 = shape.accent
	tagName.TextSize = 13
	tagName.TextScaled = false
	tagName.TextXAlignment = Enum.TextXAlignment.Center
	tagName.TextYAlignment = Enum.TextYAlignment.Center
	tagName.Parent = tagFrame

	-- CARTEL DE ESTADO: el aviso del telegraph.
	--
	-- Es la pieza que convierte la maquina de estados en algo que el jugador
	-- PUEDE LEER. Sin este cartel, la IA puede dejar 1.4 s de aviso antes de
	-- cargar (que es lo que hace justo al Bomber) y el jugador no tiene ni
	-- idea: para el es un monstruo que se para y luego te explota encima.
	--
	-- Nace OCULTO y vacio. `MonsterService.onStateChanged` es quien lo llena,
	-- y solo mientras dura un estado con aviso: un "!" permanente seria ruido.
	local stateLabel = Instance.new("TextLabel")
	stateLabel.Name = "StateLabel"
	stateLabel.Size = UDim2.new(1, 0, 0, 16)
	stateLabel.Position = UDim2.fromOffset(0, 24)
	stateLabel.BackgroundTransparency = 1
	stateLabel.BorderSizePixel = 0
	stateLabel.Font = Enum.Font.GothamBold
	stateLabel.Text = ""
	stateLabel.TextColor3 = Color3.fromRGB(255, 226, 96)
	stateLabel.TextSize = 14
	stateLabel.Visible = false
	stateLabel.Parent = tagFrame

	local hpFrame = Instance.new("Frame")
	hpFrame.Name = "HealthBar"
	hpFrame.Size = UDim2.new(1, -14, 0, 10)
	-- y = 38 (no 26) para dejar sitio al cartel de estado de arriba.
	hpFrame.Position = UDim2.fromOffset(7, 38)
	hpFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
	hpFrame.BorderSizePixel = 0
	hpFrame.Parent = tagFrame

	local hpCorner = Instance.new("UICorner")
	hpCorner.CornerRadius = UDim.new(0, 5)
	hpCorner.Parent = hpFrame

	local hpFill = Instance.new("Frame")
	hpFill.Name = "Fill"
	hpFill.Size = UDim2.fromScale(1, 1)
	hpFill.BackgroundColor3 = Color3.fromRGB(255, 92, 108)
	hpFill.BorderSizePixel = 0
	hpFill.Parent = hpFrame

	local hpFillCorner = Instance.new("UICorner")
	hpFillCorner.CornerRadius = UDim.new(0, 5)
	hpFillCorner.Parent = hpFill

	model:SetAttribute("Style", shape.style)
	model:SetAttribute("AccentR", shape.accent.R)
	model:SetAttribute("AccentG", shape.accent.G)
	model:SetAttribute("AccentB", shape.accent.B)

	-- ESCALA PUBLICADA en el modelo.
	--
	-- Se publica como atributo y no solo como tamano porque es lo que
	-- permite comprobar desde fuera, sin abrir el modelo, que un bicho
	-- sale con la escala correcta. Es lo que usan las pruebas de
	-- verificacion en runtime y lo que haria falta para detectar en un
	-- playtest que un mundo se quedo sin aplicar su multiplicador.
	model:SetAttribute("VisualScale", finalScale)
	model:SetAttribute("HitboxScale", def.HitboxScale or MonsterScaleRules.DefaultHitboxRatio)
	model:SetAttribute("VisualHeight", size.Y)
	model:SetAttribute("HitboxHeight", rootSize.Y)

	return model
end

-- ---------------------------------------------------------------------------
-- EXPLOSION
-- ---------------------------------------------------------------------------

--- Explosion completa: NUCLEO + ONDA + chispas + humo + luz.
---
--- El nucleo se ve en el frame en el que nace y la onda crece hasta el RADIO
--- REAL de dano. Esa onda es el dato que el jugador necesita para aprender a
--- poner distancia; una nube sin radio no se puede esquivar con conocimiento,
--- solo con suerte.
--- @param position Vector3
--- @param radius number
--- @param worldId string?
--- @param vfxFolder Folder
--- @return Model?
function VisualKit.BuildExplosion(
	position: Vector3,
	radius: number,
	worldId: string?,
	vfxFolder: Folder
): Model?
	if not vfxFolder or not vfxFolder.Parent then
		return nil
	end

	local safeRadius = if radius and radius > 0 then radius else GameConfig.DefaultBombRadius
	local skin = VisualKit.BombSkin(worldId)

	local model = Instance.new("Model")
	model.Name = "Explosion"

	local anchor = makePart("Core", Vector3.new(1, 1, 1), CFrame.new(position), skin.glow, {
		shape = Enum.PartType.Ball,
		material = Enum.Material.Neon,
		transparency = 0.1,
	})
	model.PrimaryPart = anchor
	anchor.Parent = model
	model.Parent = vfxFolder

	-- Onda: cilindro tumbado que crece hasta el RADIO y se desvanece.
	local wave = makePart(
		"Shockwave",
		Vector3.new(1, 0.6, 1),
		CFrame.new(position),
		skin.ring,
		{ shape = Enum.PartType.Cylinder, material = Enum.Material.Neon, transparency = 0.3 }
	)
	wave.Orientation = Vector3.new(0, 0, 90)
	wave.Parent = model

	local light = Instance.new("PointLight")
	light.Name = "Light"
	light.Color = skin.glow
	light.Brightness = 6
	light.Range = math.max(40, safeRadius * 2)
	light.Shadows = false
	light.Parent = anchor

	local flash = Instance.new("ParticleEmitter")
	flash.Name = "Flash"
	flash.Color = ColorSequence.new(Color3.fromRGB(255, 250, 220), skin.glow)
	flash.Lifetime = NumberRange.new(0.15, 0.35)
	flash.Speed = NumberRange.new(20, 45)
	flash.SpreadAngle = Vector2.new(180, 180)
	flash.Rate = 0
	flash.LightEmission = 1
	flash.Parent = anchor

	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "Smoke"
	smoke.Color = ColorSequence.new(skin.glow, Color3.fromRGB(70, 60, 55))
	smoke.Lifetime = NumberRange.new(0.4, 0.8)
	smoke.Speed = NumberRange.new(8, 22)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Rate = 0
	smoke.LightEmission = 0.5
	smoke.Parent = anchor

	model:SetAttribute("VisualRadius", safeRadius)
	return model
end

-- =========================================================================
-- POWERUPS
-- =========================================================================

--- Powerups disponibles. Se reconocen POR COLOR y POR FORMA antes de tocarlos:
--- un objeto sin icono es un objeto que el jugador ignora.
---
-- MEDIDO EN AUDITORIA: existian cinco (Bomb, Fire, Speed, Shield, Heal) y solo
-- se generaban CUATRO: `KINDS` no incluia `Fire`, asi que su modelo, su
-- efecto y su atributo existian sin que nada llegara nunca a generarlo. Es
-- codigo muerto, y el jugador lo lee como "+PODER que no existe".
--
-- La lista de aqui y la de `PowerupService.KINDS` tienen que COINCIDIR, y lo
-- comprueba `Gameplay.spec`: un powerup pintado que no se genera es un
-- fantasma; uno que se genera y no esta pintado es un cubo sin nombre.
VisualKit.POWERUPS = {
	Bomb = { color = Color3.fromRGB(255, 176, 64), shape = Enum.PartType.Ball, label = "+BOMBA" },
	Fire = { color = Color3.fromRGB(255, 96, 64), shape = Enum.PartType.Ball, label = "+PODER" },
	Speed = { color = Color3.fromRGB(120, 255, 190), shape = Enum.PartType.Block, label = "+VELOCIDAD" },
	Shield = { color = Color3.fromRGB(150, 200, 255), shape = Enum.PartType.Block, label = "ESCUDO" },
	Heal = { color = Color3.fromRGB(120, 255, 130), shape = Enum.PartType.Ball, label = "+VIDA" },
	Dash = { color = Color3.fromRGB(200, 140, 255), shape = Enum.PartType.Block, label = "IMPULSO" },
	Ghost = { color = Color3.fromRGB(220, 220, 240), shape = Enum.PartType.Ball, label = "FANTASMA" },
	Magnet = { color = Color3.fromRGB(255, 220, 120), shape = Enum.PartType.Ball, label = "IMAN" },
	Freeze = { color = Color3.fromRGB(160, 240, 255), shape = Enum.PartType.Cylinder, label = "CONGELAR" },
}

--- Construye un powerup flotante con su cartel.
--- @param kind string clave de `VisualKit.POWERUPS`
--- @param position Vector3
--- @return Model?
function VisualKit.BuildPowerup(kind: string, position: Vector3): Model?
	local spec = VisualKit.POWERUPS[kind]

	if not spec then
		return nil
	end

	local model = Instance.new("Model")
	model.Name = ("Powerup_%s"):format(kind)

	local root = makePart("Root", Vector3.new(2.4, 2.4, 2.4), CFrame.new(position), Color3.new(1, 1, 1), {
		transparency = 1,
	})
	model.PrimaryPart = root
	root.Parent = model

	local core = makePart(
		"Core",
		Vector3.new(1.6, 1.6, 1.6),
		CFrame.new(),
		spec.color,
		{ shape = spec.shape, material = Enum.Material.Neon, collide = true }
	)
	core.CanTouch = true
	core:SetAttribute("PowerupKind", kind)
	core.Parent = model

	-- Marco exterior: silueta clara aunque el powerup este en sombra.
	local halo = makePart(
		"Halo",
		Vector3.new(2.3, 2.3, 2.3),
		CFrame.new(),
		Color3.new(1, 1, 1),
		{ shape = Enum.PartType.Ball, material = Enum.Material.SmoothPlastic, transparency = 0.6 }
	)
	halo.Parent = model

	local glow = Instance.new("PointLight")
	glow.Name = "Glow"
	glow.Color = spec.color
	glow.Brightness = 2
	glow.Range = 16
	glow.Shadows = false
	glow.Parent = core

	local tag = Instance.new("BillboardGui")
	tag.Name = "Label"
	tag.Adornee = root
	tag.Size = UDim2.fromOffset(140, 30)
	tag.StudsOffset = Vector3.new(0, 2, 0)
	tag.AlwaysOnTop = true
	tag.MaxDistance = 120
	tag.Parent = root

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBold
	label.Text = spec.label
	label.TextColor3 = spec.color
	label.TextSize = 16
	label.TextScaled = false
	label.TextStrokeTransparency = 0.4
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = tag

	model:SetAttribute("PowerupKind", kind)
	return model
end

return VisualKit