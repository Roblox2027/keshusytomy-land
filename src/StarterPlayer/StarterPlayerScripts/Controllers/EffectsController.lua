--!strict
--[[
	EffectsController
	Feedback de COMBATE en pantalla: numeros de dano, borde rojo al recibir
	dano y recompensas flotantes.

	POR QUE EXISTE
	--------------
	Medido en PLAY: el HUD mostraba la vida, pero no habia NADA que dijera
	"te han pegado 60" ni "tu bomba ha pegado". El jugador veia una barra que
	bajaba y no sabia si era una bomba, un monstruo o una caida. Eso es DANO
	INEXPLICABLE, y es la razon por la que deja de jugar.

	QUE HACE
	--------
	  1. Numero flotante sobre la entidad cuando su vida cambia.
	  2. Borde rojo breve cuando el dano lo recibe el JUGADOR.
	  3. Aviso "BOMBA" cuando aparece una bomba en el Workspace.
	  4. "+20 XP" / "+15" cuando el servidor publica recurso nuevo.

	EL CLIENTE NO DECIDE NADA
	-------------------------
	Solo ESCUCHA. El numero mostrado es la diferencia entre dos vidas que ya
	existen. Un cliente modificado puede mentir en su pantalla; no cambia el
	juego.

	SIN ASSETS
	---------
	Numeros con `TextLabel` y color. Ni una textura, ni un sonido inventado.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local UTILS = SHARED:WaitForChild("Utils")

local Logger = require(UTILS:WaitForChild("Logger"))

local Controller = {}

Controller.IsActive = false

--- Nombre del `ScreenGui` generado por `tools/hud.js`. Es CONTRATO.
local HUD_NAME = "KeshusyHUD"

local _gui = nil
local _numbers = nil
local _vignette = nil
local _live = {}
local _maid = nil

--- Ultima vida conocida por entidad, para saber CUANTO ha cambiado.
local _lastHealth = {}

--- Tope de numeros flotantes a la vez. Sin el, una cadena de explosiones en
--- una arena llena llena la pantalla de texto y deja de LEERSE.
local MAX_NUMBERS = 8
--- Crea un numero flotante en una posicion de mundo.
---
--- Se convierte a posicion de pantalla ANTES de crearse y se queda ahi: un
--- numero anclado a un objetivo que se MUEVE se lee como un glitch, no como un
--- impacto.
--- @param text string
--- @param worldPosition Vector3
--- @param color Color3
--- @param scale number? multiplicador de tamano (1 normal, 1.4 critico)
local function spawnNumber(text: string, worldPosition: Vector3, color: Color3, scale: number?)
	if not _numbers then
		return
	end

	-- El mas antiguo se retira: es el que menos informacion aporta.
	if #_live >= MAX_NUMBERS then
		local oldest = table.remove(_live, 1)

		if oldest and oldest.Parent then
			oldest:Destroy()
		end
	end

	local camera = Workspace.CurrentCamera

	if not camera then
		return
	end

	local screenPoint, onScreen = camera:WorldToScreenPoint(worldPosition)

	if not onScreen then
		return
	end

	local label = Instance.new("TextLabel")
	label.Name = "DamageNumber"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Size = UDim2.fromOffset(140, 34)
	label.Position = UDim2.fromOffset(screenPoint.X, screenPoint.Y)
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.TextColor3 = color
	label.TextSize = 22 * (scale or 1)
	label.TextScaled = false
	label.TextStrokeTransparency = 0.3
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = _numbers

	table.insert(_live, label)

	-- Sube y se desvanece. Corto a proposito: el numero informa, no decora.
	TweenService:Create(
		label,
		TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Position = UDim2.fromOffset(screenPoint.X, screenPoint.Y - 46),
			TextTransparency = 1,
		}
	):Play()

	task.delay(0.8, function()
		for index, entry in ipairs(_live) do
			if entry == label then
				table.remove(_live, index)
				break
			end
		end

		if label.Parent then
			label:Destroy()
		end
	end)
end

Controller.SpawnNumber = spawnNumber

--- Enrojece el BORDE de la pantalla un instante.
---
--- No se oscurece la pantalla completa: durante un combate el jugador
--- necesita ver la bomba que va a matarle, y tapar el centro es tapar el juego.
local function flashBorder(color: Color3, peak: number, duration: number)
	if not _vignette then
		return
	end

	local stroke = _vignette:FindFirstChildOfClass("UIStroke")

	if not stroke then
		return
	end

	stroke.Color = color
	stroke.Transparency = peak
	TweenService:Create(stroke, TweenInfo.new(duration), { Transparency = 1 }):Play()
end

--- El jugador ha recibido dano.
function Controller.FlashDamage()
	flashBorder(Color3.fromRGB(255, 40, 60), 0.35, 0.45)
end

--- El jugador se ha curado. Sin una senal POSITIVA, curarse es invisible.
function Controller.FlashHeal()
	flashBorder(Color3.fromRGB(90, 255, 150), 0.3, 0.6)

	task.delay(0.7, function()
		local stroke = _vignette and _vignette:FindFirstChildOfClass("UIStroke")

		if stroke then
			stroke.Color = Color3.fromRGB(255, 40, 60)
		end
	end)
end

--- Posicion de pantalla de una entidad con vida.
--- @param humanoid Humanoid
--- @return Vector3?
local function anchorPosition(humanoid: Humanoid): Vector3?
	local parent = humanoid.Parent

	if not parent then
		return nil
	end

	local root = parent:FindFirstChild("HumanoidRootPart")

	if root and root:IsA("BasePart") then
		return root.Position
	end

	return nil
end

--- Observa la vida de un Humanoid y muestra el cambio.
---
--- `isLocalPlayer` decide si el cambio tambien enciende el BORDE: el dano a un
--- enemigo no puede poner en rojo la pantalla de quien lo ha causado.
--- @param humanoid Humanoid
--- @param isLocalPlayer boolean
local function watchHumanoid(humanoid: Humanoid, isLocalPlayer: boolean)
	local key = humanoid

	_lastHealth[key] = humanoid.Health

	local function onHealthChanged(newHealth: number)
		local previous = _lastHealth[key]
		_lastHealth[key] = newHealth

		if previous == nil then
			return
		end

		local delta = newHealth - previous

		if math.abs(delta) < 0.5 then
			return
		end

		local position = anchorPosition(humanoid) or Vector3.zero

		if delta < 0 then
			local amount = math.floor(-delta)
			local critical = amount >= 80

			spawnNumber(
				("-%d"):format(amount),
				position,
				if critical then Color3.fromRGB(255, 150, 90) else Color3.fromRGB(255, 120, 130),
				if critical then 1.4 else 1
			)

			if isLocalPlayer then
				Controller.FlashDamage()
			end
		elseif isLocalPlayer then
			spawnNumber(("+%d"):format(math.floor(delta)), position, Color3.fromRGB(120, 255, 160))
			Controller.FlashHeal()
		end
	end

	if _maid then
		_maid:Connect(humanoid.HealthChanged, onHealthChanged)
		_maid:Connect(humanoid.Died, function()
			_lastHealth[key] = nil
		end)
	end
end

--- Muestra las recompensas cuando el SERVIDOR las publica.
local function watchRewards()
	local player = Players.LocalPlayer

	if not player or not _maid then
		return
	end

	local lastXP = player:GetAttribute("XP")
	local lastCoins = player:GetAttribute("Coins")

	--- @param text string
	--- @param color Color3
	local function announce(text: string, color: Color3)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local base = if root and root:IsA("BasePart") then root.Position else Vector3.zero
		spawnNumber(text, base + Vector3.new(0, 2.5, 0), color)
	end

	_maid:Connect(player:GetAttributeChangedSignal("XP"), function()
		local xp = player:GetAttribute("XP")

		if type(xp) == "number" and type(lastXP) == "number" and xp > lastXP then
			announce(("+%d XP"):format(xp - lastXP), Color3.fromRGB(150, 255, 190))
		end

		lastXP = xp
	end)

	_maid:Connect(player:GetAttributeChangedSignal("Coins"), function()
		local coins = player:GetAttribute("Coins")

		if type(coins) == "number" and type(lastCoins) == "number" and coins > lastCoins then
			announce(("+%d"):format(coins - lastCoins), Color3.fromRGB(255, 214, 110))
		end

		lastCoins = coins
	end)
end
--- Avisa de las bombas cuando aparecen en el Workspace.
---
--- El aviso NO depende de un remoto propio: la bomba se crea en el servidor y
--- REPLICA. El cliente solo mira "ha aparecido algo en `Bombs`", que es
--- exactamente lo que el jugador ve en pantalla.
local function watchBombs()
	local folder = Workspace:WaitForChild("Bombs", 10)

	if not folder or not _maid then
		return
	end

	--- @param instance Instance
	local function onBombAdded(instance: Instance)
		if not instance:IsA("Model") then
			return
		end

		local root = instance.PrimaryPart

		if not root then
			return
		end

		spawnNumber("BOMBA", root.Position + Vector3.new(0, 4.5, 0), Color3.fromRGB(255, 200, 90), 0.8)
	end

	_maid:Connect(folder.ChildAdded, onBombAdded)

	-- Las que ya estaban al arrancar (el jugador entra en pleno juego) se
	-- avisan igual: si no, la primera bomba de la sesion seria invisible.
	for _, child in ipairs(folder:GetChildren()) do
		onBombAdded(child)
	end
end

--- Observa los monstruos visibles para mostrar su dano.
local function watchMonsters()
	local folder = Workspace:WaitForChild("Monsters", 10)

	if not folder or not _maid then
		return
	end

	--- @param instance Instance
	local function onMonsterAdded(instance: Instance)
		if not instance:IsA("Model") then
			return
		end

		local humanoid = instance:FindFirstChildOfClass("Humanoid")

		if humanoid then
			watchHumanoid(humanoid, false)
		end
	end

	_maid:Connect(folder.ChildAdded, onMonsterAdded)

	for _, child in ipairs(folder:GetChildren()) do
		onMonsterAdded(child)
	end
end

--- @param maid any? Maid del registro de controllers.
--- @return boolean success
function Controller.Start(maid: any?): boolean
	if Controller.IsActive then
		return true
	end

	_maid = maid

	local player = Players.LocalPlayer
	local playerGui = player and player:WaitForChild("PlayerGui", 10)
	_gui = playerGui and playerGui:WaitForChild(HUD_NAME, 10)

	if not _gui then
		Logger.Error(("EffectsController: %s no existe; no habra feedback de combate."):format(HUD_NAME))
		return false
	end

	_numbers = _gui:FindFirstChild("DamageNumbers")
	_vignette = _gui:FindFirstChild("DamageVignette")

	if not _numbers then
		Logger.Error("EffectsController: el HUD no tiene el panel DamageNumbers.")
		return false
	end

	local character = player.Character

	if character then
		local humanoid = character:WaitForChild("Humanoid", 10)

		if humanoid then
			watchHumanoid(humanoid, true)
		end
	end

	-- Cada reaparicion engancha el Humanoid nuevo. Sin esto, la segunda vida
	-- del jugador se queda sin feedback de dano para siempre.
	if _maid then
		_maid:Connect(player.CharacterAdded, function(newCharacter: Model)
			local newHumanoid = newCharacter:WaitForChild("Humanoid", 10)

			if newHumanoid then
				watchHumanoid(newHumanoid, true)
			end
		end)
	end

	watchMonsters()
	watchBombs()
	watchRewards()

	Controller.IsActive = true
	Logger.Info("EffectsController listo (numeros de dano, borde y avisos).")
	return true
end

--- @return boolean success
function Controller.Destroy(): boolean
	Controller.IsActive = false

	-- Los numeros vivos se destruyen: un numero congelado en pantalla que no
	-- responde a nada es peor que no tener ninguno.
	for _, label in ipairs(_live) do
		if label and label.Parent then
			label:Destroy()
		end
	end

	table.clear(_live)
	table.clear(_lastHealth)

	_gui = nil
	_numbers = nil
	_vignette = nil
	_maid = nil
	return true
end

return Controller
