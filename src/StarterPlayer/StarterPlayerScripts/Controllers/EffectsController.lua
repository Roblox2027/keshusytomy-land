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
local Lighting = game:GetService("Lighting")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local UTILS = SHARED:WaitForChild("Utils")

local Logger = require(UTILS:WaitForChild("Logger"))
local CONTROLLERS = script.Parent
local AudioController = require(CONTROLLERS:WaitForChild("AudioController"))

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

-- ---------------------------------------------------------------------------
-- ILUMINACION DEL CICLO DIA/NOCHE (mision V2, FASE 38)
-- ---------------------------------------------------------------------------
--
-- El ciclo es AMBIENTAL: no hay progreso por noches ni contadores de
-- objetivo. Lo que cambia es lo que el jugador VE: la noche tiene que
-- PARECER noche, o la fase que publica el servidor es una palabra en un
-- cartel que no significa nada.
--
-- El estado lo publica el servidor (`NightPhase`); el cliente solo traduce
-- la palabra a luz. La transicion es un tween: un salto de luz instantaneo
-- se lee como un parpadeo del motor, no como un atardecer.
local NIGHT_LIGHTING = {
	Day = { ClockTime = 13, Brightness = 2, OutdoorAmbient = Color3.fromRGB(128, 128, 128) },
	Sunset = { ClockTime = 18.2, Brightness = 1.4, OutdoorAmbient = Color3.fromRGB(120, 92, 84) },
	Night = { ClockTime = 0.2, Brightness = 0.7, OutdoorAmbient = Color3.fromRGB(56, 62, 92) },
	Dawn = { ClockTime = 6.1, Brightness = 1.3, OutdoorAmbient = Color3.fromRGB(104, 100, 110) },
}

--- Ultima fase aplicada: un atributo reescrito con el mismo valor dispara
--- la senal igualmente, y rehacer el tween en curso lo reinicia a la vista.
local _lightingPhase = nil

--- Aplica la luz de una fase del ciclo. Suave y reversible.
--- @param phase any
local function applyNightLighting(phase: any)
	if type(phase) ~= "string" or phase == _lightingPhase then
		return
	end

	local target = NIGHT_LIGHTING[phase]

	if not target then
		return
	end

	_lightingPhase = phase

	TweenService
		:Create(Lighting, TweenInfo.new(4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
			ClockTime = target.ClockTime,
			Brightness = target.Brightness,
			OutdoorAmbient = target.OutdoorAmbient,
		})
		:Play()
end
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
	TweenService
		:Create(label, TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(screenPoint.X, screenPoint.Y - 46),
			TextTransparency = 1,
		})
		:Play()

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
				-- El dano al JUGADOR suena sin posicion: es el sonido del
				-- cuerpo de uno, no del mundo.
				AudioController.PlayEvent("PlayerHurt")
			else
				-- El dano a un ENEMIGO suena DONDE esta. `MonsterHurt` es el
				-- mismo para todos: lo que identifica a la criatura es su
				-- modelo y su voz, no un grunido distinto por bicho.
				AudioController.PlayEvent("MonsterHurt", position)
			end
		elseif isLocalPlayer then
			spawnNumber(("+%d"):format(math.floor(delta)), position, Color3.fromRGB(120, 255, 160))
			Controller.FlashHeal()
		end
	end

	if _maid then
		_maid:Connect(humanoid.HealthChanged, onHealthChanged)
		_maid:Connect(humanoid.Died, function()
			-- La MUERTE tiene sonido propio: es el dato que dice al jugador
			-- si ha ganado o perdido el intercambio.
			local deathPosition = anchorPosition(humanoid) or Vector3.zero

			if isLocalPlayer then
				AudioController.PlayEvent("PlayerDeath")
			else
				local model = humanoid.Parent
				if model and model:IsA("Model") and model:GetAttribute("IsBoss") == true then
					AudioController.PlayEvent("BossDeath", deathPosition)
					AudioController.SetTransientMusicState("Victory", 6)
				else
					AudioController.PlayEvent("MonsterDeath", deathPosition)
				end
			end

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
	local lastGems = player:GetAttribute("Gems")
	local lastLevel = player:GetAttribute("Level")
	local lastSecrets = player:GetAttribute("SecretsFound")

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
			AudioController.PlayEvent("CoinPickup")
		end

		lastCoins = coins
	end)

	_maid:Connect(player:GetAttributeChangedSignal("Gems"), function()
		local gems = player:GetAttribute("Gems")
		if type(gems) == "number" and type(lastGems) == "number" and gems > lastGems then
			AudioController.PlayEvent("GemPickup")
		end
		lastGems = gems
	end)

	_maid:Connect(player:GetAttributeChangedSignal("Level"), function()
		local level = player:GetAttribute("Level")
		if type(level) == "number" and type(lastLevel) == "number" and level > lastLevel then
			AudioController.PlayEvent("LevelUp")
		end
		lastLevel = level
	end)

	local lastRoundResult = player:GetAttribute("RoundResult")
	_maid:Connect(player:GetAttributeChangedSignal("RoundResult"), function()
		local result = player:GetAttribute("RoundResult")
		if type(result) ~= "string" or result == lastRoundResult then
			return
		end
		lastRoundResult = result
		if result == "Ronda perdida" then
			AudioController.PlayEvent("RoundLose")
			AudioController.SetTransientMusicState("Defeat", 5)
		elseif string.find(result, "Ronda completada", 1, true) then
			AudioController.PlayEvent("RoundWin")
			AudioController.SetTransientMusicState("Victory", 5)
		end
	end)

	_maid:Connect(player:GetAttributeChangedSignal("SecretsFound"), function()
		local secrets = player:GetAttribute("SecretsFound")
		if
			type(secrets) == "number"
			and type(lastSecrets) == "number"
			and secrets > lastSecrets
		then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local position = if root and root:IsA("BasePart") then root.Position else Vector3.zero
			spawnNumber(
				"SECRETO DESCUBIERTO",
				position + Vector3.new(0, 3, 0),
				Color3.fromRGB(120, 255, 210),
				1.1
			)
			AudioController.PlayEvent("SecretFound")
		end
		lastSecrets = secrets
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

	-- Ultima posicion conocida de cada bomba viva.
	--
	-- Existe por una razon tecnica: cuando la bomba desaparece, su instancia
	-- ya no esta en el Workspace y `PrimaryPart` es nil. Sin guardar la
	-- posicion ANTES, el BOOM no tendria sitio donde sonar y habria que
	-- emitirlo en el oido del jugador, que es justo lo que no dice nada
	-- sobre si la bomba le ha alcanzado o ha pegado al lado.
	local lastPosition: { [Instance]: Vector3 } = {}

	--- @param instance Instance
	local function onBombAdded(instance: Instance)
		if not instance:IsA("Model") then
			return
		end

		local root = instance.PrimaryPart

		if not root then
			return
		end

		spawnNumber(
			"BOMBA",
			root.Position + Vector3.new(0, 4.5, 0),
			Color3.fromRGB(255, 200, 90),
			0.8
		)

		lastPosition[instance] = root.Position

		-- `CLICK / DEPLOY`. Suena en el sitio donde se ha puesto la bomba, no
		-- en el oido: el jugador oye DONDE la ha dejado, que es informacion
		-- de juego y no un adorno.
		AudioController.PlayEvent("BombPlace", root.Position)

		-- EL TICK DE LA MECHA.
		--
		-- La bomba publica su atributo `FuseRemaining`, asi que este cliente
		-- sigue la cuenta REAL sin preguntar al servidor. El intervalo se
		-- acorta en el ultimo segundo: ahi es cuando el sonido tiene que
		-- volverse agresivo, porque de eso depende que el jugador salga.
		--
		-- No se reproduce por frame: hay un intervalo explicito entre
		-- tictacs, porque un `Sound` por frame abriria cientos por bomba.
		task.spawn(function()
			local elapsed = 0
			local lastTick = 0

			while instance.Parent and elapsed < 6 do
				task.wait(0.1)
				elapsed += 0.1

				local remaining = instance:GetAttribute("FuseRemaining")

				if type(remaining) ~= "number" then
					break
				end

				-- Ultimo segundo: tic cada 0.1. Antes: cada 0.4.
				local interval = if remaining <= 1 then 0.1 else 0.4

				if elapsed - lastTick >= interval then
					lastTick = elapsed
					AudioController.PlayEvent("BombFuse", root.Position)
				end

				if remaining <= 0 then
					break
				end
			end
		end)
	end

	-- EL BOOM.
	--
	-- Cuando la bomba sale del Workspace, el servidor ya ha detonado la
	-- explosion. Se usa la ultima posicion conocida porque en el instante
	-- del `ChildRemoved` la instancia ya no esta alli.
	_maid:Connect(folder.ChildRemoved, function(instance: Instance)
		local position = lastPosition[instance]
		lastPosition[instance] = nil

		if position ~= nil then
			AudioController.PlayEvent("Explosion", position)
		end
	end)

	_maid:Connect(folder.ChildAdded, onBombAdded)

	-- Las que ya estaban al arrancar (el jugador entra en pleno juego) se
	-- avisan igual: si no, la primera bomba de la sesion seria invisible.
	for _, child in ipairs(folder:GetChildren()) do
		onBombAdded(child)
	end
end

--- Conecta el ciclo de VOZ de un monstruo.
---
--- Se apoya en el atributo `AIState` que `MonsterService` publica: es el
--- dato REAL del servidor, no una estimacion del cliente. Cada cambio de
--- estado tiene su sonido:
---
---   Warning -> TELEGRAPH, el aviso previo al ataque
---   Charge  -> el ataque en si
---   Chase   -> ALERTA, ha visto al jugador
---
--- El telegraph es el mas importante de los tres: es lo que convierte un
--- golpe en algo a lo que el jugador puede reaccionar en vez de a algo que
--- le pasa.
---
--- Se declara ANTES de `watchMonsters` porque `onMonsterAdded` la llama, y
--- en Lua un `local function` usada antes de definirse vale `nil`.
---
--- @param monster Instance
local function watchMonsterVoice(monster: Instance)
	local lastState = monster:GetAttribute("AIState")

	if type(lastState) ~= "string" or _maid == nil then
		return
	end

	_maid:Connect(monster:GetAttributeChangedSignal("AIState"), function()
		local state = monster:GetAttribute("AIState")

		if type(state) ~= "string" or state == lastState then
			return
		end

		-- `previous` se guarda ANTES de actualizar `lastState`. Si se
		-- actualizara primero, la comprobacion de "ha entrado en Chase"
		-- compararia consigo misma y la alerta no sonaria nunca.
		local previous = lastState
		lastState = state

		local root = monster.PrimaryPart

		if root == nil then
			return
		end

		if state == "Warning" then
			AudioController.PlayEvent("MonsterTelegraph", root.Position)
		elseif state == "Charge" then
			AudioController.PlayEvent("MonsterAttack", root.Position)
		elseif state == "Chase" and previous ~= "Chase" then
			AudioController.PlayEvent("MonsterAlert", root.Position)
		end
	end)
end

--- Observa los monstruos visibles para mostrar su dano y su voz.
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

		watchMonsterVoice(instance)

		-- SONIDO DE APARICION.
		--
		-- Un monstruo que aparece sin hacer ruido es una sorpresa injusta:
		-- el jugador no ha tenido tiempo de decidir nada. El sonido de
		-- aparicion convierte "hay un bicho" en "ha entrado UN bicho aqui".
		local root = instance.PrimaryPart
		if instance:GetAttribute("IsBoss") == true then
			AudioController.PlayEvent("BossSpawn", if root ~= nil then root.Position else nil)
			AudioController.PlayEvent("BossIntro", if root ~= nil then root.Position else nil)
			AudioController.UpdateMusicState()
		else
			AudioController.PlayEvent("MonsterSpawn", if root ~= nil then root.Position else nil)
		end
	end

	_maid:Connect(folder.ChildAdded, onMonsterAdded)

	for _, child in ipairs(folder:GetChildren()) do
		onMonsterAdded(child)
	end
end

--- Observa los bloques del mapa para el sonido de ROTURA.
---
--- `DestructionService` marca cada bloque con `IsDestroyed`, asi que el
--- cliente no necesita ningun remoto: el cambio de atributo ES el evento.
--- Es el mismo criterio que con las bombas.
local function watchBlocks()
	local worlds = Workspace:FindFirstChild("Worlds")

	if worlds == nil or _maid == nil then
		return
	end

	--- @param instance Instance
	local function attach(instance: Instance)
		if not instance:IsA("BasePart") then
			return
		end

		-- Se repite el CONTRATO de prefijo de `DestructionService`. No se
		-- importa la constante porque ese servicio es de servidor y este
		-- es un cliente: la unica forma de compartirla seria un modulo mas.
		if string.sub(instance.Name, 1, #"Block_") ~= "Block_" then
			return
		end

		local block = instance :: BasePart

		_maid:Connect(block:GetAttributeChangedSignal("IsDestroyed"), function()
			if block:GetAttribute("IsDestroyed") == true then
				-- `CRACK / BREAK`, en la posicion del bloque: que es donde
				-- el jugador ha visto desaparecer la estructura.
				AudioController.PlayEvent("BlockBreak", block.Position)
			end
		end)
	end

	-- Los bloques que ya existen al arrancar se conectan aqui. Se recorre
	-- una sola vez por vida del controller: hacerlo en cada aparicion
	-- seria trabajo de mas para el mismo resultado.
	for _, world in ipairs(worlds:GetChildren()) do
		for _, instance in ipairs(world:GetDescendants()) do
			attach(instance)
		end
	end

	_maid:Connect(worlds.DescendantAdded, attach)
end

--- PASOS del jugador.
---
--- El sonido cambia con la SUPERFICIE (tierra, arena, hielo, roca, metal)
--- y se dispara por MOVIMIENTO, medido en studs recorridos y no en tiempo.
---
--- Medir distancia y no tiempo es lo que hace que el paso suene distinto
--- al correr y al andar: el jugador recorre mas studs por segundo y hace
--- mas pasos, sin necesitar dos eventos distintos.
---
--- El cooldown de `AudioRules` es la segunda red: aun si la cuenta se
--- descoloca, el motor no abre mas de un sonido cada 0.08 s.
local _lastStepDistance = 0

--- @param humanoid Humanoid
--- @param rootPart BasePart
local function watchFootsteps(humanoid: Humanoid, rootPart: BasePart)
	if _maid == nil then
		return
	end

	local lastPosition = rootPart.Position
	_maid:Connect(humanoid.StateChanged, function(_, newState)
		if newState == Enum.HumanoidStateType.Jumping then
			AudioController.PlayEvent("Jump")
		elseif newState == Enum.HumanoidStateType.Landed then
			AudioController.PlayEvent("Land")
		end
	end)

	_maid:Connect(humanoid:GetPropertyChangedSignal("MoveDirection"), function()
		local direction = humanoid.MoveDirection

		-- Quieto: no hay paso. Se resetea la cuenta para que al volver a
		-- caminar el primer paso suene de inmediato.
		if direction.Magnitude < 0.1 then
			_lastStepDistance = 0
			lastPosition = rootPart.Position
			return
		end

		local moved = (rootPart.Position - lastPosition).Magnitude
		lastPosition = rootPart.Position
		_lastStepDistance += moved

		-- Un paso cada 9 studs recorridos. Es una distancia, no un tiempo:
		-- asi correr da mas pasos por segundo que andar, que es lo que
		-- hace el sonido reconocible como "esta corriendo".
		if _lastStepDistance < 9 then
			return
		end

		_lastStepDistance = 0

		local player = Players.LocalPlayer
		local worldId = player and player:GetAttribute("World")
		local stepEvent =
			AudioController.GetStepEvent(if type(worldId) == "string" then worldId else nil)

		-- Volumen segun la velocidad: correr suena mas fuerte que andar.
		local speed = humanoid.WalkSpeed
		local volume = math.clamp(0.6 + (speed / 32) * 0.4, 0.4, 1)

		AudioController.PlayEvent(stepEvent, nil, volume)
	end)
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
		Logger.Error(
			("EffectsController: %s no existe; no habra feedback de combate."):format(HUD_NAME)
		)
		return false
	end

	-- Las rutas son el CONTRATO con `tools/hud.js`. Un `FindFirstChild` de un
	-- solo nivel ya no las encuentra: el HUD es un arbol de ZONAS.
	_numbers =
		_gui:FindFirstChild("Root"):FindFirstChild("CenterFeedback"):FindFirstChild("DamageNumbers")
	_vignette =
		_gui:FindFirstChild("Root"):FindFirstChild("Overlays"):FindFirstChild("DamageVignette")

	if not _numbers then
		Logger.Error("EffectsController: el HUD no tiene el panel DamageNumbers.")
		return false
	end

	local character = player.Character

	if character then
		local humanoid = character:WaitForChild("Humanoid", 10)
		local rootPart = character:WaitForChild("HumanoidRootPart", 10)

		if humanoid then
			watchHumanoid(humanoid, true)
		end

		-- Los pasos necesitan el `HumanoidRootPart` para medir cuanto se ha
		-- movido el jugador. Sin el, los pasos no suenan: es preferible a
		-- sonar uno por frame.
		if humanoid and rootPart and rootPart:IsA("BasePart") then
			watchFootsteps(humanoid, rootPart :: BasePart)
		end
	end

	-- Cada reaparicion engancha el Humanoid nuevo. Sin esto, la segunda vida
	-- del jugador se queda sin feedback de dano para siempre.
	if _maid then
		_maid:Connect(player.CharacterAdded, function(newCharacter: Model)
			local newHumanoid = newCharacter:WaitForChild("Humanoid", 10)
			local newRoot = newCharacter:WaitForChild("HumanoidRootPart", 10)

			if newHumanoid then
				watchHumanoid(newHumanoid, true)
			end

			if newHumanoid and newRoot and newRoot:IsA("BasePart") then
				watchFootsteps(newHumanoid, newRoot :: BasePart)
			end
		end)
	end

	watchMonsters()
	watchBombs()
	watchBlocks()
	watchRewards()

	-- CICLO DIA/NOCHE: la fase la publica el servidor por jugador y la luz
	-- la traduce este cliente. Se aplica la actual al arrancar: entrar a
	-- mitad de la noche no puede dejar el cielo de mediodia.
	applyNightLighting(player:GetAttribute("NightPhase"))

	if _maid then
		_maid:Connect(player:GetAttributeChangedSignal("NightPhase"), function()
			applyNightLighting(player:GetAttribute("NightPhase"))
		end)
	end

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
	_lightingPhase = nil

	_gui = nil
	_numbers = nil
	_vignette = nil
	_maid = nil
	return true
end

return Controller
