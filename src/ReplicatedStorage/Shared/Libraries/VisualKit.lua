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
local ItemCatalog = require(CONFIG:WaitForChild("ItemCatalog"))
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
--- El `flavor` ajusta el aspecto según las habilidades de bomba del jugador:
---   - "default": apariencia clásica.
---   - "capacity": banda extra y brillo envolvente.
---   - "damage": fusible más caliente (rojo naranja).
---   - "radius": aro de radio más brillante y grande.
---   - "power": combina capacity + damage + radius.
--- @param worldId string?
--- @param position Vector3
--- @param radius number
--- @param flavor string? "default"|"capacity"|"damage"|"radius"|"power"
--- @return Model?
function VisualKit.BuildBomb(
	worldId: string?,
	position: Vector3,
	radius: number,
	flavor: string?
): Model?
	local skin = VisualKit.BombSkin(worldId)
	local dims = VisualKit.BOMB
	local flavorStr = flavor or "default"

	-- Tabla de sabores visuales para la bomba.
	local FLAVOR_MODS = {
		default = { extraBand = false, hotFuse = false, brightRing = false, hotGlow = false },
		capacity = { extraBand = true, hotFuse = false, brightRing = false, hotGlow = false },
		damage = { extraBand = false, hotFuse = true, brightRing = false, hotGlow = true },
		radius = { extraBand = false, hotFuse = false, brightRing = true, hotGlow = false },
		power = { extraBand = true, hotFuse = true, brightRing = true, hotGlow = true },
	}

	local mod = FLAVOR_MODS[flavorStr] or FLAVOR_MODS.default

	-- Radio de explosion con suelo de 8 studs: por debajo el aro no se
	-- distingue de una mancha y el jugador aprende mal la zona de pelig.
	local safeRadius = if radius and radius >= 8 then radius else GameConfig.DefaultBombRadius

	-- El color del fusible varía según el sabor: "hot" = más rojo/ naranja.
	local fuseGlowColor = if mod.hotFuse or mod.hotGlow then
		Color3.fromRGB(255, 120, 60)
	else skin.glow

	local model = Instance.new("Model")
	model.Name = "Bomb"

	-- Atributo de sabor para que servicios clientes lean el tipo visual.
	model:SetAttribute("Flavor", flavorStr)

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

	-- Banda extra para sabores de capacidad: visibilidad inmediata de
	-- "una bomba mejor". Gira a un ángulo distinto para no tapar la primera.
	if mod.extraBand then
		local extraBand = makePart(
			"BombBand2",
			Vector3.new(dims.BodySize * 1.05, 0.4, dims.BodySize * 1.05),
			CFrame.new(position) * CFrame.Angles(0, math.rad(35), 0),
			skin.body,
			{ material = Enum.Material.Neon, transparency = 0.3 }
		)
		extraBand.Parent = model
	end

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
	local tipColor = if mod.hotGlow then fuseGlowColor else skin.glow
	local tipBrightness = if mod.hotGlow then 4 else 2

	local tip = makePart("FuseGlow", dims.TipSize, tipCFrame, tipColor, {
		shape = Enum.PartType.Ball,
		material = Enum.Material.Neon,
	})
	tip.Parent = model

	-- Luz del fusible: sin ella la punta es un punto en una arena a oscuras.
	local light = Instance.new("PointLight")
	light.Name = "FuseLight"
	light.Color = tipColor
	light.Brightness = tipBrightness
	light.Range = if mod.hotGlow then 24 else 18
	light.Shadows = false
	light.Parent = tip

	-- Chispas del fusible. `Rate = 0` y emision manual desde el servicio: el
	-- servidor decide CUANDO hay chispas, no el motor por su cuenta.
	local sparkColor = if mod.hotFuse then fuseGlowColor else skin.glow
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "Particles"
	sparks.Color = ColorSequence.new(sparkColor, Color3.fromRGB(90, 60, 40))
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
		{ material = Enum.Material.Neon, transparency = if mod.brightRing then 0.3 else 0.55 }
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
	-- Brainrots (FASE 20)
	elseif id == "Locotto" then
		return {
			shape = Enum.PartType.Block,
			size = Vector3.new(3.6, 2.8, 3.2),
			accent = Color3.fromRGB(80, 160, 70),
			style = "Stump",
		}
	elseif id == "Bambino" then
		return {
			shape = Enum.PartType.Block,
			size = Vector3.new(2.8, 1.8, 2.2),
			accent = Color3.fromRGB(230, 240, 250),
			style = "Flyer",
		}
	elseif id == "Bombino" then
		return {
			shape = Enum.PartType.Ball,
			size = Vector3.new(2.8, 2.6, 2.8),
			accent = Color3.fromRGB(255, 210, 100),
			style = "Mushroom",
		}
	elseif id == "Explodini" then
		return {
			shape = Enum.PartType.Block,
			size = Vector3.new(3.8, 2.8, 3.0),
			accent = Color3.fromRGB(255, 140, 50),
			style = "Charger",
		}
	elseif id == "Bailarino" then
		return {
			shape = Enum.PartType.Block,
			size = Vector3.new(3.0, 3.2, 2.8),
			accent = Color3.fromRGB(230, 210, 100),
			style = "Cactus",
		}
	elseif id == "Sandwichini" then
		return {
			shape = Enum.PartType.Block,
			size = Vector3.new(2.6, 2.0, 1.8),
			accent = Color3.fromRGB(255, 220, 130),
			style = "Ambusher",
		}
	elseif id == "Glaciacino" then
		return {
			shape = Enum.PartType.Block,
			size = Vector3.new(2.6, 2.2, 2.4),
			accent = Color3.fromRGB(190, 230, 250),
			style = "Penguin",
		}
	elseif id == "Macarronni" then
		return {
			shape = Enum.PartType.Block,
			size = Vector3.new(3.4, 3.2, 3.0),
			accent = Color3.fromRGB(230, 230, 250),
			style = "Yeti",
		}
	elseif id == "Fantasmitti" then
		return {
			shape = Enum.PartType.Ball,
			size = Vector3.new(2.4, 2.4, 2.4),
			accent = Color3.fromRGB(230, 240, 250),
			style = "Ghost",
		}
	elseif id == "Lavaccino" then
		return {
			shape = Enum.PartType.Ball,
			size = Vector3.new(2.6, 2.8, 2.6),
			accent = Color3.fromRGB(255, 130, 40),
			style = "Lava",
		}
	elseif id == "Peperoni" then
		return {
			shape = Enum.PartType.Block,
			size = Vector3.new(3.6, 2.4, 3.2),
			accent = Color3.fromRGB(255, 110, 40),
			style = "Dragon",
		}
	elseif id == "Magmatico" then
		return {
			shape = Enum.PartType.Block,
			size = Vector3.new(4.0, 3.0, 3.2),
			accent = Color3.fromRGB(255, 110, 40),
			style = "Ballista",
		}
	elseif id == "Glitchino" then
		return {
			shape = Enum.PartType.Block,
			size = Vector3.new(2.4, 2.4, 2.4),
			accent = Color3.fromRGB(100, 240, 250),
			style = "Robot",
		}
	elseif id == "Pixeloni" then
		return {
			shape = Enum.PartType.Block,
			size = Vector3.new(2.8, 2.2, 2.6),
			accent = Color3.fromRGB(210, 255, 230),
			style = "Hunter",
		}
	elseif id == "Virusini" then
		return {
			shape = Enum.PartType.Ball,
			size = Vector3.new(2.2, 2.2, 2.2),
			accent = Color3.fromRGB(230, 130, 240),
			style = "Virus",
		}
	-- Halloween Zombie Brainrots (FASE 20)
	elseif id == "Zombini" then
		return {
			shape = Enum.PartType.Block,
			size = Vector3.new(3.4, 2.8, 3.0),
			accent = Color3.fromRGB(100, 170, 70),
			style = "Zombie",
		}
	elseif id == "Mumifico" then
		return {
			shape = Enum.PartType.Block,
			size = Vector3.new(3.6, 2.8, 3.2),
			accent = Color3.fromRGB(200, 170, 110),
			style = "Mummy",
		}
	elseif id == "Congelado" then
		return {
			shape = Enum.PartType.Block,
			size = Vector3.new(3.2, 3.0, 2.8),
			accent = Color3.fromRGB(180, 230, 250),
			style = "FrozenZombie",
		}
	elseif id == "Carbonizado" then
		return {
			shape = Enum.PartType.Block,
			size = Vector3.new(3.6, 3.0, 3.2),
			accent = Color3.fromRGB(255, 120, 40),
			style = "CharredZombie",
		}
	elseif id == "Necrobyte" then
		return {
			shape = Enum.PartType.Block,
			size = Vector3.new(3.2, 2.8, 3.0),
			accent = Color3.fromRGB(200, 180, 255),
			style = "Necrobyte",
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
	-- Brainrot visual details (FASE 20)
	elseif shape.style == "Stump" then
		-- Banda de crecimiento y una grieta: lee como "tronco caído".
		local band = makePart(
			"GrowthBand",
			Vector3.new(size.X * 1.05, size.Y * 0.12, size.Z * 1.05),
			CFrame.new(0, 0, 0),
			Color3.fromRGB(100, 180, 90),
			{ material = Enum.Material.SmoothPlastic }
		)
		band.Parent = root

		local crack = makePart(
			"Crack",
			Vector3.new(size.X * 0.08, size.Y * 0.7, 0.05),
			CFrame.new(0, 0, size.Z / 2 + 0.01),
			Color3.fromRGB(40, 60, 30),
			{ material = Enum.Material.SmoothPlastic, transparency = 0.5 }
		)
		crack.Parent = root
	elseif shape.style == "Flyer" then
		-- Alas de membrana: dos triángulos translúcidos.
		for _, side in ipairs({ -1, 1 }) do
			local wing = makePart(
				"Wing_" .. tostring(side),
				Vector3.new(size.X * 0.5, size.Y * 0.08, size.Z * 0.9),
				CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(side * 15), math.rad(side * 25)),
				shape.accent,
				{ material = Enum.Material.ForceField, transparency = 0.4 }
			)
			wing.Parent = root
		end
	elseif shape.style == "Mushroom" then
		-- Láminas (gills) bajo el sombrero.
		for _, offset in ipairs({ -0.3, 0, 0.3 }) do
			local gill = makePart(
				"Gills_" .. tostring(offset),
				Vector3.new(size.X * 0.12, size.Y * 0.5, 0.05),
				CFrame.new(offset * size.X * 0.4, 0, size.Z / 2 + 0.02),
				Color3.fromRGB(255, 190, 80),
				{ material = Enum.Material.Neon }
			)
			gill.Parent = root
		end
	elseif shape.style == "Charger" then
		-- Grupa de carga: una protuberancia dorsal.
		local hump = makePart(
			"Hump",
			Vector3.new(size.X * 0.4, size.Y * 0.6, size.Z * 0.4),
			CFrame.new(0, size.Y * 0.2, 0),
			Color3.fromRGB(180, 90, 40),
			{ material = Enum.Material.SmoothPlastic }
		)
		hump.Parent = root
	elseif shape.style == "Cactus" then
		-- Espinas verticales.
		for index = 1, 5 do
			local angle = (index / 5) * math.pi * 2
			local spine = makePart(
				"Spine_" .. index,
				Vector3.new(size.X * 0.08, size.Y * 0.4, 0.08),
				CFrame.new(
					math.cos(angle) * (size.X * 0.38),
					size.Y * 0.1,
					math.sin(angle) * (size.Z * 0.38)
				),
				Color3.fromRGB(180, 190, 80),
				{ material = Enum.Material.Neon }
			)
			spine.Parent = root
		end
	elseif shape.style == "Ambusher" then
		-- Capas de sándwich: discos apilados.
		for index = 1, 3 do
			local layer = makePart(
				"Layer_" .. index,
				Vector3.new(size.X * 0.95, size.Y * 0.18, size.Z * 0.95),
				CFrame.new(0, -size.Y * 0.12 + index * size.Y * 0.1, 0),
				Color3.fromRGB(255, 215, 110),
				{ material = Enum.Material.SmoothPlastic }
			)
			layer.Parent = root
		end
	elseif shape.style == "Penguin" then
		-- Pico y aletas.
		local beak = makePart(
			"Beak",
			Vector3.new(size.X * 0.25, size.Y * 0.15, 0.2),
			CFrame.new(0, 0, -size.Z / 2 - 0.05),
			Color3.fromRGB(240, 200, 90),
			{ material = Enum.Material.SmoothPlastic }
		)
		beak.Parent = root

		for _, side in ipairs({ -1, 1 }) do
			local flipper = makePart(
				"Flipper_" .. tostring(side),
				Vector3.new(size.X * 0.15, size.Y * 0.45, 0.1),
				CFrame.new(side * size.X * 0.35, 0, 0),
				Color3.fromRGB(140, 190, 220),
				{ material = Enum.Material.SmoothPlastic }
			)
			flipper.Parent = root
		end
	elseif shape.style == "Yeti" then
		-- Bigote + garras: detalles de pelaje.
		local mustache = makePart(
			"Mustache",
			Vector3.new(size.X * 0.6, 0.08, 0.08),
			CFrame.new(0, -size.Y * 0.1, -size.Z / 2 - 0.02),
			Color3.fromRGB(200, 200, 220),
			{ material = Enum.Material.Neon, transparency = 0.3 }
		)
		mustache.Parent = root

		for _, side in ipairs({ -1, 1 }) do
			local claw = makePart(
				"Claw_" .. tostring(side),
				Vector3.new(size.X * 0.06, size.Y * 0.1, 0.12),
				CFrame.new(side * size.X * 0.32, 0, size.Z * 0.2),
				Color3.fromRGB(255, 240, 240),
				{ material = Enum.Material.SmoothPlastic }
			)
			claw.Parent = root
		end
	elseif shape.style == "Ghost" then
		-- Fantasma: translúcido con un núcleo tenue.
		body.Transparency = 0.5
		body.Material = Enum.Material.ForceField

		local coreGlow = Instance.new("PointLight")
		coreGlow.Name = "Glow"
		coreGlow.Color = shape.accent
		coreGlow.Brightness = 0.8
		coreGlow.Range = 8
		coreGlow.Shadows = false
		coreGlow.Parent = root
	elseif shape.style == "Lava" then
		-- Núcleo fundido + goteo.
		local core = makePart(
			"LavaCore",
			Vector3.new(size.X * 0.4, size.Y * 0.4, size.Z * 0.4),
			CFrame.new(0, 0, 0),
			Color3.fromRGB(255, 80, 20),
			{ shape = Enum.PartType.Ball, material = Enum.Material.Neon }
		)
		core.Transparency = 0.2
		core.Parent = root

		local lavaLight = Instance.new("PointLight")
		lavaLight.Name = "LavaLight"
		lavaLight.Color = Color3.fromRGB(255, 100, 30)
		lavaLight.Brightness = 1.5
		lavaLight.Range = 16
		lavaLight.Shadows = false
		lavaLight.Parent = root

		-- Goteo: partículas de lava.
		local drip = Instance.new("ParticleEmitter")
		drip.Name = "Drip"
		drip.Color = ColorSequence.new(Color3.fromRGB(255, 90, 20), Color3.fromRGB(255, 50, 10))
		drip.Lifetime = NumberRange.new(0.3, 0.6)
		drip.Speed = NumberRange.new(3, 6)
		drip.Rate = 4
		drip.LightEmission = 0.8
		drip.Size = NumberSequence.new(0.3)
		drip.Parent = root
	elseif shape.style == "Dragon" then
		-- Cuernos + cola.
		for _, side in ipairs({ -1, 1 }) do
			local horn = makePart(
				"Horn_" .. tostring(side),
				Vector3.new(size.X * 0.1, size.Y * 0.35, 0.1),
				CFrame.new(side * size.X * 0.25, size.Y * 0.45, 0)
					* CFrame.Angles(0, 0, math.rad(side * 25)),
				Color3.fromRGB(255, 90, 40),
				{ material = Enum.Material.Neon }
			)
			horn.Parent = root
		end

		local tail = makePart(
			"Tail",
			Vector3.new(size.X * 0.1, size.Y * 0.6, 0.1),
			CFrame.new(0, 0, size.Z * 0.5) * CFrame.Angles(0, math.rad(25), 0),
			Color3.fromRGB(255, 110, 40),
			{ material = Enum.Material.SmoothPlastic }
		)
		tail.Parent = root
	elseif shape.style == "Ballista" then
		-- Cañón que mira hacia adelante.
		local cannon = makePart(
			"Cannon",
			Vector3.new(size.X * 0.3, size.Y * 0.15, size.Z * 0.7),
			CFrame.new(0, size.Y * 0.15, 0),
			Color3.fromRGB(160, 80, 60),
			{ material = Enum.Material.Metal }
		)
		cannon.Parent = root

		local muzzle = makePart(
			"Muzzle",
			Vector3.new(size.X * 0.15, size.Y * 0.15, 0.1),
			CFrame.new(0, 0, -size.Z * 0.35),
			Color3.fromRGB(255, 130, 40),
			{ material = Enum.Material.Neon }
		)
		muzzle.Parent = root
	elseif shape.style == "Robot" then
		-- Display ocular + paneles.
		local eye = makePart(
			"EyeDisplay",
			Vector3.new(size.X * 0.2, size.Y * 0.2, 0.1),
			CFrame.new(0, 0, size.Z / 2 + 0.05),
			Color3.fromRGB(120, 255, 140),
			{ material = Enum.Material.Neon }
		)
		eye.Parent = root

		for panelIndex = 1, 3 do
			local panel = makePart(
				"Panel_" .. panelIndex,
				Vector3.new(size.X * 0.7, 0.08, 0.1),
				CFrame.new(0, -size.Y * 0.15 - panelIndex * size.Y * 0.15, size.Z / 2 + 0.02),
				Color3.fromRGB(60, 100, 140),
				{ material = Enum.Material.Metal }
			)
			panel.Parent = root
		end
	elseif shape.style == "Hunter" then
		-- Visor + hombreras.
		local visor = makePart(
			"Visor",
			Vector3.new(size.X * 0.6, 0.12, 0.1),
			CFrame.new(0, eyeHeight + 0.3, eyeDepth - 0.02),
			Color3.fromRGB(100, 255, 200),
			{ material = Enum.Material.Neon }
		)
		visor.Parent = root

		for _, side in ipairs({ -1, 1 }) do
			local pauldron = makePart(
				"Pauldron_" .. tostring(side),
				Vector3.new(size.X * 0.12, size.Y * 0.25, 0.12),
				CFrame.new(side * size.X * 0.38, size.Y * 0.25, 0),
				Color3.fromRGB(160, 220, 200),
				{ material = Enum.Material.Metal }
			)
			pauldron.Parent = root
		end
	elseif shape.style == "Virus" then
		-- Puntas de protrusión + brillo pulsátil.
		for index = 1, 4 do
			local angle = (index / 4) * math.pi * 2
			local spike = makePart(
				"Spike_" .. index,
				Vector3.new(size.X * 0.12, size.Y * 0.3, 0.12),
				CFrame.new(
					math.cos(angle) * (size.X * 0.45),
					size.Y * 0.1,
					math.sin(angle) * (size.Z * 0.45)
				) * CFrame.Angles(math.rad(30), 0, 0),
				Color3.fromRGB(200, 80, 220),
				{ material = Enum.Material.Neon }
			)
			spike.Parent = root
		end

		local pulse = Instance.new("PointLight")
		pulse.Name = "Pulse"
		pulse.Color = shape.accent
		pulse.Brightness = 1.2
		pulse.Range = 12
		pulse.Shadows = false
		pulse.Parent = root
	elseif shape.style == "Zombie" then
		-- Detalles de descomposición: raíces, grietas y un toque verde.
		for index = 1, 4 do
			local angle = (index / 4) * math.pi * 2
			local twig = makePart(
				"Root_" .. index,
				Vector3.new(size.X * 0.08, size.Y * 0.35, 0.08),
				CFrame.new(
					math.cos(angle) * (size.X * 0.38),
					-size.Y * 0.2,
					math.sin(angle) * (size.Z * 0.38)
				) * CFrame.Angles(0, 0, math.rad(25)),
				Color3.fromRGB(60, 110, 50),
				{ material = Enum.Material.SmoothPlastic }
			)
			twig.Parent = root
		end

		for index = 1, 3 do
			local crack = makePart(
				"Crack_" .. index,
				Vector3.new(size.X * 0.06, size.Y * 0.5, 0.04),
				CFrame.new(
					math.cos(index * 2.1) * size.X * 0.2,
					0,
					math.sin(index * 2.1) * size.Z * 0.2
				),
				Color3.fromRGB(40, 60, 30),
				{ material = Enum.Material.SmoothPlastic, transparency = 0.4 }
			)
			crack.Parent = root
		end

		local decayLight = Instance.new("PointLight")
		decayLight.Name = "Decay"
		decayLight.Color = Color3.fromRGB(100, 170, 70)
		decayLight.Brightness = 1.0
		decayLight.Range = 10
		decayLight.Shadows = false
		decayLight.Parent = root
	elseif shape.style == "Mummy" then
		-- Vendas enrolladas alrededor del cuerpo.
		for index = 1, 6 do
			local angle = (index / 6) * math.pi * 2
			local bandage = makePart(
				"Bandage_" .. index,
				Vector3.new(size.X * 0.12, size.Y * 1.1, 0.1),
				CFrame.new(
					math.cos(angle) * (size.X * 0.42),
					0,
					math.sin(angle) * (size.Z * 0.42)
				) * CFrame.Angles(0, 0, math.rad(15)),
				shape.accent,
				{ material = Enum.Material.SmoothPlastic }
			)
			bandage.Parent = root
		end

		-- Ojo brillante entre las vendas.
		local eyeGlow = Instance.new("PointLight")
		eyeGlow.Name = "EyeGlow"
		eyeGlow.Color = Color3.fromRGB(255, 220, 100)
		eyeGlow.Brightness = 1.8
		eyeGlow.Range = 12
		eyeGlow.Shadows = false
		eyeGlow.Parent = root
	elseif shape.style == "FrozenZombie" then
		-- Cristales de hielo sobresaliendo del cuerpo.
		for index = 1, 5 do
			local angle = (index / 5) * math.pi * 2
			local crystal = makePart(
				"IceCrystal_" .. index,
				Vector3.new(size.X * 0.08, size.Y * 0.5, 0.08),
				CFrame.new(
					math.cos(angle) * (size.X * 0.38),
					size.Y * 0.2,
					math.sin(angle) * (size.Z * 0.38)
				) * CFrame.Angles(math.rad(20), 0, 0),
				Color3.fromRGB(180, 235, 255),
				{ material = Enum.Material.ForceField, transparency = 0.2 }
			)
			crystal.Parent = root
		end

		-- Aura de frío.
		local coldAura = Instance.new("PointLight")
		coldAura.Name = "ColdAura"
		coldAura.Color = Color3.fromRGB(150, 220, 255)
		coldAura.Brightness = 1.4
		coldAura.Range = 14
		coldAura.Shadows = false
		coldAura.Parent = root
	elseif shape.style == "CharredZombie" then
		-- Brasas visibles en el cuerpo carbonizado.
		local ember = makePart(
			"Ember",
			Vector3.new(size.X * 0.2, size.Y * 0.2, 0.2),
			CFrame.new(0, 0, size.Z / 2 + 0.05),
			Color3.fromRGB(255, 100, 30),
			{ shape = Enum.PartType.Ball, material = Enum.Material.Neon }
		)
		ember.Parent = root

		local emberLight = Instance.new("PointLight")
		emberLight.Name = "EmberLight"
		emberLight.Color = Color3.fromRGB(255, 120, 40)
		emberLight.Brightness = 1.6
		emberLight.Range = 14
		emberLight.Shadows = false
		emberLight.Parent = root

		-- Partículas de brasa.
		local spark = Instance.new("ParticleEmitter")
		spark.Name = "Sparks"
		spark.Color = ColorSequence.new(Color3.fromRGB(255, 110, 30), Color3.fromRGB(100, 50, 30))
		spark.Lifetime = NumberRange.new(0.2, 0.5)
		spark.Speed = NumberRange.new(2, 5)
		spark.SpreadAngle = Vector2.new(30, 30)
		spark.Rate = 3
		spark.LightEmission = 0.7
		spark.Size = NumberSequence.new(0.2)
		spark.Parent = root
	elseif shape.style == "Necrobyte" then
		-- Paneles cibernéticos y arco eléctrico.
		for index = 1, 3 do
			local panel = makePart(
				"Panel_" .. index,
				Vector3.new(size.X * 0.6, 0.1, 0.1),
				CFrame.new(0, -size.Y * 0.1 - index * size.Y * 0.12, size.Z / 2 + 0.03),
				Color3.fromRGB(100, 120, 160),
				{ material = Enum.Material.Metal }
			)
			panel.Parent = root
		end

		-- Display ocular rojo parpadeante.
		local cyberEye = makePart(
			"CyberEye",
			Vector3.new(size.X * 0.25, size.Y * 0.18, 0.1),
			CFrame.new(0, 0, size.Z / 2 + 0.05),
			Color3.fromRGB(255, 80, 80),
			{ material = Enum.Material.Neon }
		)
		cyberEye.Parent = root

		local zapLight = Instance.new("PointLight")
		zapLight.Name = "ZapLight"
		zapLight.Color = Color3.fromRGB(180, 180, 255)
		zapLight.Brightness = 1.7
		zapLight.Range = 12
		zapLight.Shadows = false
		zapLight.Parent = root
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
--- @param flavor string? "default"|"capacity"|"damage"|"radius"|"power"
--- @return Model?
function VisualKit.BuildExplosion(
	position: Vector3,
	radius: number,
	worldId: string?,
	vfxFolder: Folder,
	flavor: string?
): Model?
	if not vfxFolder or not vfxFolder.Parent then
		return nil
	end

	local safeRadius = if radius and radius > 0 then radius else GameConfig.DefaultBombRadius
	local skin = VisualKit.BombSkin(worldId)
	local flavorStr = flavor or "default"

	-- Tabla de sabores visuales para la explosión.
	-- Cada sabor cambia color, tamaño o intensidad para que el jugador
	-- identifique el tipo de bomba de un vistazo.
	local FLAVOR_MODS = {
		default = { coreColor = skin.glow, waveColor = skin.ring, lightBright = 6, lightRange = 40, flashColor1 = Color3.fromRGB(255, 250, 220), smokeSpeed = 22, extraFlash = 0 },
		damage = { coreColor = Color3.fromRGB(255, 100, 40), waveColor = Color3.fromRGB(255, 120, 50), lightBright = 10, lightRange = 45, flashColor1 = Color3.fromRGB(255, 120, 40), smokeSpeed = 30, extraFlash = 1 },
		radius = { coreColor = skin.glow, waveColor = skin.ring, lightBright = 7, lightRange = 55, flashColor1 = Color3.fromRGB(255, 250, 220), smokeSpeed = 26, extraFlash = 0, ringExtra = true },
		capacity = { coreColor = skin.glow, waveColor = skin.ring, lightBright = 8, lightRange = 42, flashColor1 = Color3.fromRGB(255, 210, 100), smokeSpeed = 28, extraFlash = 2 },
		power = { coreColor = Color3.fromRGB(255, 80, 30), waveColor = Color3.fromRGB(255, 180, 80), lightBright = 14, lightRange = 60, flashColor1 = Color3.fromRGB(255, 100, 30), smokeSpeed = 36, extraFlash = 3, ringExtra = true },
	}

	local mod = FLAVOR_MODS[flavorStr] or FLAVOR_MODS.default

	local model = Instance.new("Model")
	model.Name = "Explosion"

	local anchor = makePart("Core", Vector3.new(1, 1, 1), CFrame.new(position), mod.coreColor, {
		shape = Enum.PartType.Ball,
		material = Enum.Material.Neon,
		transparency = 0.1,
	})
	model.PrimaryPart = anchor
	anchor.Parent = model
	model.Parent = vfxFolder

	-- Onda: cilindro tumbado que crece hasta el RADIO y se desvanece.
	-- El sabor "radius" o "power" duplica el aro secundario.
	local wave = makePart(
		"Shockwave",
		Vector3.new(1, 0.6, 1),
		CFrame.new(position),
		mod.waveColor,
		{ shape = Enum.PartType.Cylinder, material = Enum.Material.Neon, transparency = 0.25 }
	)
	wave.Orientation = Vector3.new(0, 0, 90)
	wave.Parent = model

	-- Aro secundario para sabores de radio grande: refuerza la lectura visual
	-- del área de daño.
	if mod.ringExtra then
		local ring2 = makePart(
			"Shockwave2",
			Vector3.new(1, 0.5, 1),
			CFrame.new(position),
			mod.waveColor,
			{ shape = Enum.PartType.Cylinder, material = Enum.Material.Neon, transparency = 0.55 }
		)
		ring2.Orientation = Vector3.new(0, 0, 90)
		ring2.Parent = model
	end

	local light = Instance.new("PointLight")
	light.Name = "Light"
	light.Color = mod.coreColor
	light.Brightness = mod.lightBright
	light.Range = math.max(mod.lightRange, safeRadius * 2)
	light.Shadows = false
	light.Parent = anchor

	local flash = Instance.new("ParticleEmitter")
	flash.Name = "Flash"
	flash.Color = ColorSequence.new(mod.flashColor1, mod.coreColor)
	flash.Lifetime = NumberRange.new(0.15, 0.35)
	flash.Speed = NumberRange.new(20, 45 + mod.smokeSpeed)
	flash.SpreadAngle = Vector2.new(180, 180)
	flash.Rate = 0
	flash.LightEmission = 1
	flash.Parent = anchor

	-- Chispas extra para sabores de daño: refuerzo visual del "calor".
	if mod.extraFlash > 0 then
		local extra = Instance.new("ParticleEmitter")
		extra.Name = "FlashExtra"
		extra.Color = ColorSequence.new(mod.flashColor1, Color3.fromRGB(255, 200, 80))
		extra.Lifetime = NumberRange.new(0.1, 0.25)
		extra.Speed = NumberRange.new(30, 60)
		extra.SpreadAngle = Vector2.new(180, 180)
		extra.Rate = 0
		extra.LightEmission = 0.9
		extra.Size = NumberSequence.new(0.6)
		extra.Parent = anchor
	end

	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "Smoke"
	smoke.Color = ColorSequence.new(mod.coreColor, Color3.fromRGB(70, 60, 55))
	smoke.Lifetime = NumberRange.new(0.4, 0.8)
	smoke.Speed = NumberRange.new(8, mod.smokeSpeed)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Rate = 0
	smoke.LightEmission = 0.5
	smoke.Parent = anchor

	model:SetAttribute("VisualRadius", safeRadius)
	model:SetAttribute("Flavor", flavorStr)
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

-- =========================================================================
-- ITEM DROPS (FASE 32): pickups brillantes en el mundo que cuestionan
-- Robux al recogerse. Solo items cosméticos con DeveloperProductId.
-- =========================================================================

--- Color del brillo según rareza para los pickups del mundo.
VisualKit.RARITY_GLOW = {
	[ItemCatalog.Rarity.Common]    = Color3.fromRGB(255, 226, 150),
	[ItemCatalog.Rarity.Rare]      = Color3.fromRGB(120, 200, 255),
	[ItemCatalog.Rarity.Epic]      = Color3.fromRGB(180, 120, 255),
	[ItemCatalog.Rarity.Legendary] = Color3.fromRGB(255, 120, 200),
}

-- Shape del pickup según categoría: alas = diamante, armas = hoja, etc.
VisualKit.CATEGORY_SHAPE = {
	[ItemCatalog.Category.Wings]   = { shape = Enum.PartType.Ball,  size = Vector3.new(2, 2, 2) },
	[ItemCatalog.Category.Weapon]  = { shape = Enum.PartType.Block, size = Vector3.new(0.5, 2.2, 0.5) },
	[ItemCatalog.Category.Vehicle] = { shape = Enum.PartType.Ball,  size = Vector3.new(2.4, 2.4, 2.4) },
}

--- Construye un pickup brillante para el mundo.
---
--- El modelo incluye un `Core` (BasePart con colision), un `PointLight`
--- de brillo pulsátil, un `ParticleEmitter` de chispas y un `BillboardGui`
--- con el nombre del item y el precio en Robux. El `ProximityPrompt` se
--- añade desde el servicio para mantener VisualKit sin dependencias.
--- @param definition any ItemCatalog.Get(id) — debe tener `WorldDrop = true`
--- @param position Vector3
--- @return Model?
function VisualKit.BuildItemDrop(definition: any, position: Vector3): Model?
	if type(definition) ~= "table" or not definition.Id then
		return nil
	end

	local model = Instance.new("Model")
	model.Name = ("ItemDrop_%s"):format(definition.Id)

	local rarityGlow = VisualKit.RARITY_GLOW[definition.Rarity or ItemCatalog.Rarity.Common]
		or Color3.fromRGB(255, 226, 150)

	local shapeInfo = VisualKit.CATEGORY_SHAPE[definition.Category]
		or { shape = Enum.PartType.Ball, size = Vector3.new(1.8, 1.8, 1.8) }

	-- Root invisible: PrimaryPart del modelo, con la posicion exacta.
	local root = makePart("Root", Vector3.new(4, 4, 4), CFrame.new(position), Color3.new(1, 1, 1), {
		transparency = 1,
		collide = false,
	})
	model.PrimaryPart = root
	root.Parent = model

	-- Núcleo del pickup: brilla con el color de rareza.
	local core = makePart(
		"Core",
		shapeInfo.size,
		CFrame.new(),
		rarityGlow,
		{ shape = shapeInfo.shape, material = Enum.Material.Neon, collide = true }
	)
	core.CanTouch = true
	core:SetAttribute("ItemId", definition.Id)
	core.Parent = model

	-- Luz de brillo: visible de lejos, sin sombras.
	local light = Instance.new("PointLight")
	light.Name = "Glow"
	light.Color = rarityGlow
	light.Brightness = 3
	light.Range = 20
	light.Shadows = false
	light.Parent = core

	-- Chispas que giran: comunican "esto es interactivo".
	local spark = Instance.new("ParticleEmitter")
	spark.Name = "Sparkle"
	spark.Color = ColorSequence.new(
		Color3.fromRGB(255, 255, 220),
		rarityGlow,
		Color3.fromRGB(255, 255, 255)
	)
	spark.Lifetime = NumberRange.new(0.4, 0.8)
	spark.Speed = NumberRange.new(1, 3)
	spark.SpreadAngle = Vector2.new(360, 360)
	spark.Rate = 12
	spark.LightEmission = 0.9
	spark.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 0),
	})
	spark.Parent = core

	-- BillboardGui: nombre + Robux.
	local tag = Instance.new("BillboardGui")
	tag.Name = "Label"
	tag.Adornee = root
	tag.Size = UDim2.fromOffset(160, 50)
	tag.StudsOffset = Vector3.new(0, 3.5, 0)
	tag.AlwaysOnTop = true
	tag.MaxDistance = 160
	tag.Parent = root

	local tagFrame = Instance.new("Frame")
	tagFrame.Name = "Holder"
	tagFrame.Size = UDim2.fromScale(1, 1)
	tagFrame.BackgroundColor3 = Color3.fromRGB(10, 12, 20)
	tagFrame.BackgroundTransparency = 0.25
	tagFrame.BorderSizePixel = 0
	tagFrame.Parent = tag

	local tagCorner = Instance.new("UICorner")
	tagCorner.CornerRadius = UDim.new(0, 8)
	tagCorner.Parent = tagFrame

	local tagStroke = Instance.new("UIStroke")
	tagStroke.Color = rarityGlow
	tagStroke.Thickness = 1
	tagStroke.Transparency = 0.4
	tagStroke.Parent = tagFrame

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.Size = UDim2.new(1, 0, 0, 20)
	nameLabel.Position = UDim2.fromOffset(0, 4)
	nameLabel.BackgroundTransparency = 1
	nameLabel.BorderSizePixel = 0
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Text = definition.DisplayName or definition.Id
	nameLabel.TextColor3 = Color3.fromRGB(1, 1, 1)
	nameLabel.TextSize = 14
	nameLabel.TextXAlignment = Enum.TextXAlignment.Center
	nameLabel.TextYAlignment = Enum.TextYAlignment.Center
	nameLabel.Parent = tagFrame

	local priceLabel = Instance.new("TextLabel")
	priceLabel.Name = "Price"
	priceLabel.Size = UDim2.new(1, 0, 0, 20)
	priceLabel.Position = UDim2.fromOffset(0, 26)
	priceLabel.BackgroundTransparency = 1
	priceLabel.BorderSizePixel = 0
	priceLabel.Font = Enum.Font.GothamBold
	priceLabel.Text = ("Robux %d"):format(definition.DeveloperProductId or 0)
	priceLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
	priceLabel.TextSize = 14
	priceLabel.TextXAlignment = Enum.TextXAlignment.Center
	priceLabel.TextYAlignment = Enum.TextYAlignment.Center
	priceLabel.Parent = tagFrame

	model:SetAttribute("ItemId", definition.Id)
	model:SetAttribute("DeveloperProductId", definition.DeveloperProductId)
	model:SetAttribute("Rarity", definition.Rarity or ItemCatalog.Rarity.Common)
	-- La luz pulsa: el atributo es la frecuencia, leído por un thread del servicio.
	model:SetAttribute("GlowPulse", true)

	return model
end

return VisualKit