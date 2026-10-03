--!strict
--[[
    MonsterService
    Instanciacion, estado y eliminacion de monstruos dentro del mundo de partida.

    FASE 0 - Bootstrap: interfaz declarada, sin implementar.
    La implementacion se realiza por fases, cuando existan las
    dependencias minimas que cada servicio necesita.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONFIG = SHARED:WaitForChild("Config")
local UTILS = SHARED:WaitForChild("Utils")

local FeatureConfig = require(CONFIG:WaitForChild("FeatureConfig"))
local GameConfig = require(CONFIG:WaitForChild("GameConfig"))
local PerformanceConfig = require(CONFIG:WaitForChild("PerformanceConfig"))
local AIService = require(SHARED:WaitForChild("Libraries"):WaitForChild("AIService"))
local VisualKit = require(SHARED:WaitForChild("Libraries"):WaitForChild("VisualKit"))
local MonsterDefinitions = require(SHARED:WaitForChild("MonsterDefinitions"))
local Logger = require(UTILS:WaitForChild("Logger"))

local Service = {}

Service.IsInitialized = false

-- Servicios inyectados por ServerMain.
Service._roundService = nil
Service._combatService = nil
Service._playerService = nil
Service._worldService = nil

-- Carpeta unica donde viven los monstruos.
Service._folder = nil

-- monsterId -> { Model, Humanoid, RootPart, Def, Dead }
Service._monsters = {}
Service._nextMonsterId = 0

-- Diagnostico.
Service._spawned = 0
Service._killed = 0

-- QuestService: receptor del progreso de misiones (monstruos derrotados).
--
-- Es OPCIONAL a proposito: sin el, los monstruos mueren y pagan igual, y lo
-- UNICO que se pierde es el progreso de las misiones.
Service._questService = nil

local MaidRef = nil

--- Carpeta de monstruos, creada una sola vez.
--- @return Folder?
function Service.GetFolder(): Folder?
	if Service._folder and Service._folder.Parent then
		return Service._folder
	end

	local folder = Instance.new("Folder")
	folder.Name = "Monsters"
	folder:SetAttribute("IsMonsterFolder", true)
	folder.Parent = Workspace

	Service._folder = folder
	return folder
end

--- Inyecta las dependencias del servicio.
function Service.SetDependencies(
	roundService: any,
	combatService: any,
	playerService: any,
	worldService: any
)
	Service._roundService = roundService
	Service._combatService = combatService
	Service._playerService = playerService
	Service._worldService = worldService
end

--- Conecta el receptor de progreso de misiones.
---
--- Es OPCIONAL: sin el, los monstruos mueren y pagan igual, y solo las
--- misiones que cuentan monstruos derrotados no avanzan.
--- @param questService any?
function Service.SetQuestService(questService: any)
	Service._questService = questService
end

--- Monstruos vivos ahora mismo.
--- @return number
function Service.GetAliveCount(): number
	local count = 0
	for _ in pairs(Service._monsters) do
		count += 1
	end
	return count
end

--- Monstruos vivos de un tipo concreto.
--- @param definitionId string
--- @return number
function Service.GetCountOfType(definitionId: string): number
	local count = 0
	for _, record in pairs(Service._monsters) do
		if record.Def.Id == definitionId then
			count += 1
		end
	end
	return count
end

--- Construye el cuerpo de un monstruo POR CODIGO.
---
--- Y no desde un modelo del mapa, a proposito: un NPC que depende de un
--- .rbxm en el Workspace es un NPC que desaparece cuando alguien edita el
--- lugar, y su ausencia no produce ningun error. Aqui, si la construccion
--- falla, el spawn falla de forma visible.
--- @param def table
--- @return Model?
local function buildMonsterModel(def: any): Model?
	local folder = Service.GetFolder()
	if not folder then
		return nil
	end

	-- MEDIDO en PLAY: esto era un cubo 3x3x3 con una raiz invisible. El
	-- jugador veia "un bloque de color" y no podia distinguir un Slime de un
	-- Cyber Stalker ni saber cuanta vida le queda. La construccion visual
	-- (ojos, cartel, contorno, detalles de bioma) vive en `VisualKit`.
	local model = VisualKit.BuildMonster(def)

	if not model then
		return nil
	end

	local root = model.PrimaryPart

	if not root then
		model:Destroy()
		return nil
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = def.Health
	humanoid.Health = def.Health
	-- La velocidad del Humanoid se sincroniza con el estado: arranca en
	-- `PatrolSpeed`. `StepAI` la reescribe cada frame segun el estado, pero
	-- inicializarla aqui evita el primer frame en el que el NPC aparece con la
	-- velocidad del `Speed` base (que es la de persecucion) y el jugador ve
	-- "un monstruo que sale disparado" justo al aparecer.
	humanoid.WalkSpeed = def.PatrolSpeed or def.Speed
	humanoid.DisplayName = def.Name
	humanoid.Parent = model

	model.Parent = folder

	return model
end

--- Refleja la vida real en el cartel que lleva encima del monstruo.
---
--- El jugador tiene que ver "cuanto le queda" sin abrir nada: es la
--- diferencia entre atacar a ciegas y decidir donde poner la bomba.
--- @param record table
local function syncMonsterHealthTag(record: { [string]: any })
	local humanoid = record.Humanoid
	local tag = record.Model and record.Model:FindFirstChild("NameTag", true)

	if not humanoid or not tag then
		return
	end

	local fill = tag:FindFirstChild("Fill", true)

	if fill and fill:IsA("GuiObject") then
		local ratio = if humanoid.MaxHealth > 0 then humanoid.Health / humanoid.MaxHealth else 0
		fill.Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
	end
end

--- Destello de impacto: el monstruo se pone blanco un instante.
---
--- Sin esto el jugador no sabe si su bomba ha acertado o ha pasado al lado.
--- Es el feedback mas barato y mas efectivo que existe en un juego de
--- combate, y se hace en el servidor para que lo vean TODOS los clientes.
--- @param record table
local function flashMonster(record: { [string]: any })
	local model = record.Model
	local body = model and model:FindFirstChild("Body")

	if not body or not body:IsA("BasePart") then
		return
	end

	local original = body.Color

	task.spawn(function()
		if not body.Parent then
			return
		end

		body.Color = Color3.new(1, 1, 1)
		task.wait(0.08)

		if body.Parent then
			body.Color = original
		end
	end)
end

--- Elimina un monstruo SIN pagar recompensa.
---
--- Existe separada de `OnMonsterDied` a proposito: `ClearAll` (fin de
--- ronda) usa esta. Si `ClearAll` pagase, un jugador que espera al final de
--- la ronda cobraria el XP de todos los monstruos indefinidamente.
--- @param monsterId number
local function despawnMonster(monsterId: number)
	local record = Service._monsters[monsterId]

	if not record then
		return
	end

	Service._monsters[monsterId] = nil

	if record.Model and record.Model.Parent then
		record.Model:Destroy()
	end
end

--- Muerte VISIBLE de un monstruo: se encoge y estalla en luz.
---
--- Sin esto el enemigo desaparece entre frames y el jugador no cierra el
--- ciclo "he pegado -> se ha muerto -> he cobrado". Ademas se solapaba con el
--- siguiente spawn del mismo tipo y parecia un fallo.
--- @param record table
local function playDeathVfx(record: { [string]: any })
	local model = record.Model
	local body = model and model:FindFirstChild("Body")

	if not model or not model.Parent then
		return
	end

	local light = Instance.new("PointLight")
	light.Color = model:GetAttribute("AccentR")
		and Color3.fromRGB(
			math.floor(model:GetAttribute("AccentR") * 255),
			math.floor(model:GetAttribute("AccentG") * 255),
			math.floor(model:GetAttribute("AccentB") * 255)
		)
		or Color3.fromRGB(255, 220, 160)
	light.Brightness = 4
	light.Range = 20
	light.Shadows = false
	light.Parent = body

	task.spawn(function()
		local tag = model:FindFirstChild("NameTag", true)
		local highlight = model:FindFirstChild("Highlight")

		-- El cartel y el contorno se van ANTES: un enemigo muerto no puede
		-- seguir con nombre ni vida en pantalla.
		if tag then
			tag:Destroy()
		end

		if highlight then
			highlight:Destroy()
		end

		if body and body:IsA("BasePart") then
			local target = body.Size

			for step = 1, 4 do
				if not model.Parent then
					return
				end

				body.Size = target * (1 - (step * 0.22))
				task.wait(0.05)
			end
		end

		if model.Parent then
			model:Destroy()
		end
	end)
end

--- Elimina TODOS los monstruos vivos (fin de ronda, cambio de mundo).
---
--- NO paga recompensa: morirse porque acabo la ronda no es una muerte del
--- jugador, y pagar aqui permitiria farmear XP(selectround) sin limite.
--- @return number removed
function Service.ClearAll(): number
	local removed = Service.GetAliveCount()

	for monsterId in pairs(Service._monsters) do
		despawnMonster(monsterId)
	end

	return removed
end

--- Coloca un monstruo en la arena y lo registra.
---
--- Todo se comprueba ANTES de construir nada, para que un spawn fallido no
--- deje un NPC a medias en el Workspace:
---   - el PvE esta habilitado,
---   - la definicion existe,
---   - no se supera el tope global,
---   - no se supera el tope por definicion.
--- @param definitionId string
--- @param position Vector3
--- @return number? monsterId nil si no se pudo crear
function Service.Spawn(definitionId: string, position: Vector3): number?
	if not FeatureConfig.ENABLE_MONSTER_HUNT then
		Logger.Debug(("monstruo '%s' no creado: PvE deshabilitado"):format(definitionId))
		return nil
	end

	local def = MonsterDefinitions.Get(definitionId)

	if not def then
		Logger.Error(("definicion de monstruo inexistente: %s"):format(definitionId))
		return nil
	end

	local limits = PerformanceConfig.Limits

	if Service.GetAliveCount() >= limits.MaxMonsters then
		Logger.Warn("MonsterService: tope de monstruos alcanzado; no se genera mas.")
		return nil
	end

	if Service.GetCountOfType(definitionId) >= def.MaxAlive then
		return nil
	end

	local model = buildMonsterModel(def)

	if not model then
		Logger.Error("MonsterService: no se pudo construir el modelo del monstruo.")
		return nil
	end

	-- BUG CORREGIDO (medido en PLAY): esto buscaba `HumanoidRootPart`, que es
	-- el nombre que usa el personaje de Roblox. El modelo del MONSTRUIO lo
	-- construye `VisualKit` y su raiz se llama `Root`, asi que la busqueda
	-- devolvia `nil`, el modelo se destruia y el spawn terminaba aqui:
	--
	--     MonsterService: el modelo construido no tiene HumanoidRootPart/Humanoid.
	--
	-- Cuatro monstruos por ronda, cero monstruos en pantalla, sin un solo
	-- error de sintaxis. Se usa `PrimaryPart`, que es el CONTRATO del modelo,
	-- no un nombre literal.
	local root = model.PrimaryPart
	local humanoid = model:FindFirstChildOfClass("Humanoid")

	if not root or not humanoid then
		model:Destroy()
		Logger.Error("MonsterService: el modelo construido no tiene PrimaryPart/Humanoid.")
		return nil
	end

	Service._nextMonsterId += 1
	local monsterId = Service._nextMonsterId

	model:PivotTo(CFrame.new(position))

	-- El registro lleva su PROPIA maquina de estados. Empieza en `Patrol`
	-- (no en `Chase`): un monstruo que aparece ya persiguiendo al jugador
	-- que acaba de entrar es exactamente el fallo de "no tienes tiempo a
	-- reaccionar" que el telegraph existe para evitar.
	Service._monsters[monsterId] = {
		Id = monsterId,
		Def = def,
		Model = model,
		Humanoid = humanoid,
		RootPart = root,
		Dead = false,
		NextAttackAt = 0,
		State = AIService.States.Patrol,
		TimeInState = 0,
		AnchorPosition = Vector3.new(position.X, position.Y, position.Z),
		PatrolTarget = nil,
		PatrolIndex = 0,
		PatrolRetargetAt = 0,
	}

	model:SetAttribute("AIState", AIService.States.Patrol)

	Service._spawned += 1
	syncMonsterHealthTag(Service._monsters[monsterId])

	-- EFECTO DE APARICION: el monstruo entra escalandose desde 0.4 y con un
	-- leve giro. Sin esto aparecia de golpe en el aire, y el jugador no lo
	-- registra como "ha entrado un enemigo" sino como "habia un cubo aqui".
	task.spawn(function()
		local body = model:FindFirstChild("Body")

		if body and body:IsA("BasePart") then
			local target = body.Size
			local start = target * 0.4

			for step = 1, 5 do
				if not model.Parent then
					return
				end

				body.Size = start:Lerp(target, step / 5)
				task.wait(0.05)
			end

			body.Size = target
		end
	end)

	-- La muerte la observa ESTE servicio: el monstruo desaparece y paga
	-- aunque nadie mire.
	local connection = humanoid.Died:Connect(function()
		Service.OnMonsterDied(monsterId)
	end)

	if MaidRef then
		MaidRef:Add(connection)
	end

	Logger.Debug(("monstruo %d (%s) creado en (%.0f, %.0f, %.0f)"):format(
		monsterId,
		definitionId,
		position.X,
		position.Y,
		position.Z
	))

	return monsterId
end
--- Procesa la muerte de un monstruo y paga UNA vez.
---
--- El registro se marca `Dead` y se borra de `_monsters` ANTES de pagar:
--- una explosion en cadena puede volver a disparar `Died` sobre el mismo
--- Humanoid, y sin esa marca el XP se cobraria dos veces.
--- @param monsterId number
function Service.OnMonsterDied(monsterId: number)
	local record = Service._monsters[monsterId]

	if not record or record.Dead then
		return
	end

	record.Dead = true
	Service._killed += 1

	-- Quien lo mato lo decide el Humanoid, igual que entre jugadores. Un
	-- monstruo que muere por su propia explosion no se atribuye a nadie.
	local sourceId = record.Humanoid:GetAttribute("LastDamageSource")
	local killer = if type(sourceId) == "number" then Players:GetPlayerByUserId(sourceId) else nil
	local def = record.Def

	-- La muerte se ANIMA y se destruye sola. Antes se llamaba aqui a
	-- `despawnMonster`, que hacia `Model:Destroy()` en el mismo frame: el
	-- enemigo desaparecia de un salto y el jugador no llegaba a ver que lo ha
	-- matado. El registro se borra YA (para que la cadena de explosiones no
	-- le pague dos veces) y el modelo se queda 0.2 s mas, muriendo delante.
	Service._monsters[monsterId] = nil
	playDeathVfx(record)

	if killer and Service._playerService then
		Service._playerService.AddRewards(killer, def.XP, def.Coins)
		Logger.Debug(("%s mato a %s: +%d XP +%d monedas"):format(
			killer.Name,
			def.Id,
			def.XP,
			def.Coins
		))
	end

	-- El progreso de mision va DENTRO del bloque del asesino, y no aparte
	-- con un segundo `if killer`: si se escribiera fuera, un monstruo que
	-- muere por su propia explosion intentaria progresar la mision con
	-- `killer = nil`, que es justo el caso que NO debe contar.
	--
	-- Y va DESPUES de pagar: si el pago falla, el monstruo esta muerto y la
	-- ronda continua. Al reves, una mision que no avanza seria un fallo mas
	-- dificil de ver que uno registrado de mas.
	if killer and Service._questService ~= nil then
		Service._questService.RecordMetric(killer, "MonsterDefeated", 1)
	end

	Logger.Debug(("monstruo %d (%s) eliminado"):format(monsterId, def.Id))
end


--- ?Este Humanoid es un monstruo de este servicio?
--- @param humanoid Humanoid
--- @return boolean
function Service.IsMonsterHumanoid(humanoid: Humanoid): boolean
	for _, record in pairs(Service._monsters) do
		if record.Humanoid == humanoid then
			return true
		end
	end
	return false
end


--- Aplica dano a un monstruo.
---
--- Es la entrada que usa `ExplosionService`: comprueba que el Humanoid sea
--- de un monstruo REAL de este servicio antes de tocarlo. Sin esa
--- comprobacion, un remoto podria pedir dano para cualquier NPC del mapa.
--- @param humanoid Humanoid
--- @param amount number
--- @param sourceUserId number?
--- @return boolean applied
function Service.ApplyDamageToMonster(
	humanoid: Humanoid,
	amount: number,
	sourceUserId: number?
): boolean
	for _, record in pairs(Service._monsters) do
		if record.Humanoid == humanoid and not record.Dead then
			humanoid:TakeDamage(amount)

			if sourceUserId then
				humanoid:SetAttribute("LastDamageSource", sourceUserId)
			end

			-- El jugador tiene que ver que su bomba ha HIGIDO. Sin destello
			-- y sin barra que baje, acertar y fallar se ven igual.
			flashMonster(record)
			syncMonsterHealthTag(record)

			return true
		end
	end

	return false
end

--- Jugador vivo mas cercano dentro del radio.
---
--- La eleccion la hace el SERVIDOR sobre los Humanoids reales, y la funcion
--- NO recibe ningun payload: un cliente no puede "atraer" a un monstruo
--- pidiendo nada, porque no hay nada que pedir.
--- @param origin Vector3
--- @param radius number
--- @return Player?
function Service.FindNearestPlayer(origin: Vector3, radius: number): Player?
	local best: Player? = nil
	local bestDistance = radius

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")

		if humanoid and root and humanoid.Health > 0 then
			local distance = (root.Position - origin).Magnitude

			if distance < bestDistance then
				bestDistance = distance
				best = player
			end
		end
	end

	return best
end


-- ------------------------------------------------------- CONSTANTES DE IA
--
-- Separadas del cuerpo de `StepAI` para que el balance de la IA se lea de un
-- vistazo. Todas estan en segundos o en studs y ninguna depende del mundo.
local AI_PATROL_RADIUS_STUDS = 26
local AI_PATROL_RETARGET_SECONDS = 4.5
local AI_PATROL_ARRIVE_STUDS = 4

local AI_SLOW_FACTOR = 0.6
local AI_SLOW_DURATION = 2.0

local AI_BURN_TICKS = 3
local AI_BURN_INTERVAL = 0.5
local AI_BURN_DAMAGE = 4

local AI_FADING_HZ = 3.5

--- Angulo determinista a partir de un entero.
---
--- Sin `math.random`: un prototipo que se mueve distinto cada vez hace
--- IMPOSIBLE reproducir un fallo de IA en un test o en una sesion concreta. El
--- dato tiene que ser el mismo cuando se vuelve a ejecutar el mismo mundo.
--- @param seed number
--- @return number radianes
local function hashAngle(seed: number): number
	local h = (math.floor(seed) * 374761393) % 6283
	return (h / 6283) * math.pi * 2
end

--- Paso de PATRULLA: de donde a donde, cuando no hay objetivo.
---
--- Sin esto, "no hay jugador cerca" significaba "el monstruo se queda clavado
--- donde aparecio", que es exactamente lo que mas se parece a un mueble.
--- Patrullar convierte cada enemigo en una amenaza que se cruza sola por el
--- mapa, que es lo que hace que el jugador tenga que EXPLORAR en vez de
--- esperar sentado en unrincon.
---
--- El destino se recalcula cada `AI_PATROL_RETARGET_SECONDS` siguiendo un
--- circulo de puntos alrededor del punto de aparicion. No es navegacion
--- inteligente: el jugador no necesita que el NPC esquine obstaculos, necesita
--- que el mapa tenga enemigos que se muevan.
--- @param record table
--- @param now number
--- @return table step con la MISMA forma que devuelve AIService.Step
local function patrolStep(record: { [string]: any }, now: number)
	local root = record.RootPart
	if not root then
		return { Move = false, Direction = { x = 0, y = 0, z = 0 }, Distance = 0 }
	end

	local anchor = record.AnchorPosition or root.Position

	if not record.PatrolTarget or now >= (record.PatrolRetargetAt or 0) then
		local angle = hashAngle(record.Id + (record.PatrolIndex or 0) * 7)

		record.PatrolIndex = (record.PatrolIndex or 0) + 1
		record.PatrolTarget = Vector3.new(
			anchor.X + math.cos(angle) * AI_PATROL_RADIUS_STUDS,
			anchor.Y,
			anchor.Z + math.sin(angle) * AI_PATROL_RADIUS_STUDS
		)
		record.PatrolRetargetAt = now + AI_PATROL_RETARGET_SECONDS
	end

	local flat = record.PatrolTarget - root.Position
	flat = Vector3.new(flat.X, 0, flat.Z)

	if flat.Magnitude < AI_PATROL_ARRIVE_STUDS then
		-- Llego: no se mueve este frame; el siguiente recalcula destino.
		return { Move = false, Direction = { x = 0, y = 0, z = 0 }, Distance = 0 }
	end

	local unit = flat.Unit
	return {
		Move = true,
		Direction = { x = unit.X, y = 0, z = unit.Z },
		Distance = flat.Magnitude,
	}
end

--- Cambio de estado del monstruo: lo que el JUGADOR tiene que ver.
---
--- El telegraph (`Warning`) es lo importante de esta funcion: al entrar en ese
--- estado el enemigo se enciende y el cartel pasa a "!". Sin esto la maquina
--- de estados seria INVISIBLE, y una ventana de reaccion que el jugador no
--- puede ver no es una ventana de reaccion: es un retraso.
---
--- No se usa `task.delay` para apagar el brillo: si el monstruo muere durante
--- el telegraph, un `task.delay` intentaria escribir en una Parte ya
--- destruida.
--- @param record table
--- @param state string
--- @param def any
local function onStateChanged(record: { [string]: any }, state: string, def: any)
	local model = record.Model
	if not model or not model.Parent then
		return
	end

	local glow = model:FindFirstChild("TelegraphGlow")
	if glow and glow:IsA("BasePart") then
		glow.Transparency = if AIService.IsTelegraph(state) then 0.25 else 1
		glow.CanCollide = false
		glow.CanTouch = false
		glow.CanQuery = false
	end

	local tag = model:FindFirstChild("NameTag", true)
	if tag then
		local label = tag:FindFirstChild("StateLabel")

		if label and label:IsA("TextLabel") then
			local remaining = AIService.TimeLeftInState(state, 0, def)
			label.Text = if AIService.IsTelegraph(state)
				then ("!%.1f"):format(remaining)
				elseif state == AIService.States.Recovery
				then "-"
				else ""
			label.Visible = label.Text ~= ""
		end
	end

	-- El atributo se publica para que el HUD y las sondas de QA lean el
	-- estado SIN deducirlo de la velocidad del NPC.
	model:SetAttribute("AIState", state)
end

--- Efectos de personalidad que dependen del TIEMPO, no del estado.
---
--- El Shadow es el caso claro: se hace casi invisible mientras persigue y
--- vuelve a verse cuando no. El Guardian no necesita nada aqui porque su
--- `StillWhenIdle` ya lo resuelve la maquina de estados.
---
--- Nunca baja de 0.1 de transparencia: un enemigo que se puede perder de la
--- vista a 5 studs deja de ser una amenaza y pasa a ser una molestia.
--- @param record table
--- @param def any
--- @param hasTarget boolean
--- @param now number
--- @param dt number
local function tickPersonality(record: { [string]: any }, def: any, hasTarget: boolean, now: number, dt: number)
	local model = record.Model

	if not model or not model.Parent or not def.Vanishes then
		return
	end

	local body = model:FindFirstChild("Body")
	if not body or not body:IsA("BasePart") then
		return
	end

	local alpha = tonumber(body:GetAttribute("FlickerAlpha")) or 0.1
	local goal = if hasTarget
		then (math.sin(now * AI_FADING_HZ) + 1) * 0.25 + 0.25
		else 0.1

	alpha += (goal - alpha) * math.min(1, dt * 4)
	alpha = math.clamp(alpha, 0.1, 0.75)

	body:SetAttribute("FlickerAlpha", alpha)
	body.Transparency = alpha
end
---
--- El golpe de un monstruo: dano + personalidad.
---
--- Todo el dano pasa por `CombatService`, que es la unica autoridad del
--- servidor. Si el monstruo llamara a `TakeDamage` sobre el jugador, se saltaria
--- la invulnerabilidad y las reglas de ronda.
---
--- Ademas aplica el EFECTO de la personalidad, que es la mitad del juego de
--- estos enemigos: un Ice Beast que solo hace dano es un Slime con mas vida.
--- @param record table
--- @param targetHumanoid Humanoid
--- @param def any
local function applyMonsterHit(record: { [string]: any }, targetHumanoid: Humanoid, def: any)
	local combat = Service._combatService

	if not combat then
		return
	end

	combat.ApplyDamage(targetHumanoid, def.Damage)

	if not record.Model or not record.Model.Parent then
		return
	end

	-- QUEMADURA: el dano sigue despues del golpe. Corta a proposito (1.5 s en
	-- total) porque el objetivo no es matar por quemadura sino quitarle al
	-- jugador la ventana para colocar la bomba siguiente.
	if def.AppliesBurn then
		local combatRef = combat

		task.spawn(function()
			for _ = 1, AI_BURN_TICKS do
				task.wait(AI_BURN_INTERVAL)

				if
					not record.Model.Parent
					or not targetHumanoid.Parent
					or targetHumanoid.Health <= 0
				then
					return
				end

				combatRef.ApplyDamage(targetHumanoid, AI_BURN_DAMAGE)
			end
		end)
	end

	-- HIELO: el jugador sale del golpe por debajo de la velocidad con la que
	-- le persiguen. `AI_SLOW_DURATION` es corto a proposito: si el efecto fuera
	-- largo, un solo Ice Beast mataria sin dejar jugar.
	if def.AppliesSlow then
		local player = Players:GetPlayerFromCharacter(targetHumanoid.Parent)

		if player then
			task.spawn(function()
				local character = player.Character
				if not character then
					return
				end

				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if not humanoid or humanoid.Health <= 0 then
					return
				end

				local base = humanoid:GetAttribute("BaseWalkSpeed")
					or GameConfig.DefaultPlayerSpeed

				humanoid:SetAttribute("BaseWalkSpeed", base)
				humanoid.WalkSpeed = base * AI_SLOW_FACTOR

				task.wait(AI_SLOW_DURATION)

				if humanoid.Parent and humanoid.Health > 0 then
					humanoid.WalkSpeed = humanoid:GetAttribute("BaseWalkSpeed")
						or GameConfig.DefaultPlayerSpeed
				end
			end)
		end
	end

	Logger.Debug(("%s golpeo a un jugador (%d de dano)"):format(def.Id, def.Damage))
end

--- UN SOLO paso de IA para todos los monstruos.
---
--- EL CICLO, Y POR QUE IMPORTA
--- -----------------------------
--- Antes este metodo hacia una sola cosa: si habia un jugador dentro del
--- rango, mover hacia el y, si estaba cerca, pegarle. Eso no es una IA, es un
--- `if`. El jugador no tenia forma de saber si el enemigo iba a golpear.
---
--- Ahora cada monstruo lleva su PROPIA maquina de estados (`AIService.Think`)
--- y este metodo se limita a ejecutarla. La consecuencia de juego es la que
--- importa:
---
---   - Perseguir NO es instantaneo: hay `DetectTime` + `WarningTime` antes de
---     que el enemigo se mueva. Ese es el tiempo para poner la bomba y salir.
---   - La velocidad cambia con el estado. La persecucion sostenida es SIEMPRE
---     mas lenta que el jugador; solo la `ChargeSpeed` lo supera, y 0.5 s.
---   - Entre golpes hay `RecoveryTime`, con lo que el jugador puede volver a
---     jugar en vez de morir encadenado sin tener una sola decision.
---
--- El `dt` lo pasa quien llama en lugar de usar `Heartbeat:Wait()`: dentro de
--- un `Heartbeat` eso devolveria 0 y los monstruos no se moverian, y ademas
--- `Wait()` dentro de la conexion bloquearia a los demas.
--- @param dt number
function Service.StepAI(dt: number)
if not Service._roundService or not Service._roundService.IsPlaying() then
		return
	end

	local now = os.clock()

	for _, record in pairs(Service._monsters) do
		if not record.Dead and record.RootPart and record.RootPart.Parent then
			local def = record.Def
			local origin = record.RootPart.Position

			-- 1. PERCEPCION. El jugador mas cercano DENTRO del rango de
			-- deteccion. Es percepcion, no memoria: si no hay nadie dentro, el
			-- monstruo no recuerda a nadie.
			local target = Service.FindNearestPlayer(origin, def.DetectionRange)

			local targetRoot = target
				and target.Character
				and target.Character:FindFirstChild("HumanoidRootPart")
			local targetHumanoid = target
				and target.Character
				and target.Character:FindFirstChildOfClass("Humanoid")

			local hasTarget = targetHumanoid ~= nil
				and targetHumanoid.Health > 0
				and targetRoot ~= nil

			local distance = math.huge
			if hasTarget and targetRoot then
				distance = AIService.Distance(
					origin.X,
					origin.Z,
					targetRoot.Position.X,
					targetRoot.Position.Z
				)
			end

			-- 2. PERSISTENCIA DEL ESTADO. `TimeInState` se acumula aqui y no
			-- con `os.clock()`: al cambiar de estado hay que ponerlo a cero, y
			-- con dos relojes eso se olvida una vez y el monstruo ataca sin
			-- cooldown para siempre.
			local nextState = AIService.Think(
				record.State,
				record.TimeInState or 0,
				def,
				hasTarget,
				distance
			)

			if nextState ~= record.State then
				record.State = nextState
				record.TimeInState = 0
				onStateChanged(record, nextState, def)
			else
				record.TimeInState = (record.TimeInState or 0) + dt
			end

			-- 3. MOVIMIENTO. La velocidad la decide el ESTADO, no el tipo de
			-- monstruo, y `AIService.StateSpeed` la acota contra la velocidad
			-- real del jugador. `CanMove` es falso en `Detect` y `Warning`: son
			-- los estados en los que el monstruo esta PARADO a proposito, y por
			-- eso son la ventana de reaccion del jugador.
			local speed = AIService.StateSpeed(def, record.State)
			local step = if hasTarget and targetRoot
				then AIService.Step(origin, targetRoot.Position, math.huge)
				else patrolStep(record, now)

			if AIService.CanMove(record.State) and step.Move and speed > 0 and step.Direction then
				local moved = origin
					+ Vector3.new(step.Direction.x, 0, step.Direction.z) * speed * dt

				-- BUG CORREGIDO (medido en PLAY): esto movia SOLO `RootPart`.
				-- `Body` es hermano de la raiz, no hijo, y se quedaba en el
				-- sitio: el monstruo persiguia dejando una estela de cuerpos
				-- parados, y desde lejos parecia que no se movia.
				--
				-- Ahora se mueve el MODELO ENTERO (`PivotTo`), que es lo que el
				-- jugador ve, y se orienta hacia el objetivo para que los ojos
				-- miren a donde va.
				local lookAt = if hasTarget and targetRoot then targetRoot.Position else nil

				if lookAt and (lookAt - moved).Magnitude > 0.5 then
					record.Model:PivotTo(CFrame.lookAt(moved, lookAt))
				else
					record.Model:PivotTo(CFrame.new(moved))
				end
			end

			-- 4. ATAQUE. Solo ocurre EN EL ESTADO `Attack` y solo en su primer
			-- tick: el golpe se cobra UNA vez por carga, no una vez por frame.
			--
			-- Y solo si el jugador sigue dentro del alcance: el telegraph le dio
			-- la opcion de salir, y si salio, el golpe falla. Ese es el
			-- CONTRATO del telegraph, y por eso la distancia se comprueba
			-- DESPUES de la carga y no antes.
			if record.State == AIService.States.Attack
				and (record.TimeInState or 0) < dt * 2
				and targetHumanoid
			then
				if AIService.ShouldAttack(distance, def.AttackRange) then
					applyMonsterHit(record, targetHumanoid, def)
				else
					-- Escapaste. Es un resultado VALIDO del ataque, no un fallo
					-- del sistema, y no se registra como error.
					Logger.Debug(("%s cargo y fallo: el jugador salio de su alcance")
						:format(def.Id))
				end
			end

			-- 5. PERSONALIDAD con efecto de tiempo.
			tickPersonality(record, def, hasTarget, now, dt)
		end
	end
end


--- Estado de un monstruo, para pruebas y diagnostico.
--- @param monsterId number
--- @return table?
function Service.GetMonster(monsterId: number): any?
	local record = Service._monsters[monsterId]

	if not record then
		return nil
	end


	return {
		Id = record.Id,
		DefinitionId = record.Def.Id,
		Health = record.Humanoid.Health,
		Position = record.RootPart.Position,
	}
end

--- Identificadores de los monstruos vivos.
--- @return { number }
function Service.GetAliveIds(): { number }
	local ids = {}
	for monsterId in pairs(Service._monsters) do
		table.insert(ids, monsterId)
	end
	table.sort(ids)
	return ids
end

--- @param maid any?
--- @return boolean success
function Service.Init(maid: any?): boolean
	if Service.IsInitialized then
		return true
	end

	MaidRef = maid
	Service._monsters = {}
	Service._nextMonsterId = 0
	Service._spawned = 0
	Service._killed = 0

	if not Service.GetFolder() then
		Logger.Error("MonsterService: no se pudo crear la carpeta de monstruos.")
		return false
	end

	Service.IsInitialized = true
	Logger.Info(("MonsterService: %d definiciones de monstruo"):format(
		#MonsterDefinitions.GetIds()
	))

	-- Se comprueba el BALANCE al arrancar, no en un test aparte.
	--
	-- Las reglas (persecucion mas lenta que el jugador, ventana de reaccion
	-- minima, cooldown entre golpes) son un contrato con el balance. Si un
	-- monstruo se declara mal, el sintoma en pantalla es "el juego esta
	-- injusto", que no aparece en ningun log y no lo detecta nadie hasta que un
	-- jugador lo reporta. Aqui queda escrito, con el nombre del culpable.
	local problems = MonsterDefinitions.GetBalanceProblems()

	for _, problem in ipairs(problems) do
		Logger.Warn("MonsterService DESBALANCE: " .. problem)
	end

	if #problems == 0 then
		Logger.Info(("MonsterService: balance de velocidad correcto frente a un jugador de %d studs/s")
			:format(GameConfig.DefaultPlayerSpeed))
	end

	return true
end

--- @return boolean success
function Service.Start(): boolean
	if not Service.IsInitialized then
		Logger.Error("MonsterService: Start sin Init")
		return false
	end

	if not FeatureConfig.ENABLE_MONSTER_HUNT then
		-- No es un fallo: el PvE es una bandera de contenido. Se dice en voz
		-- alta para que "no aparecen monstruos" no se confunda con "se rompio
		-- el spawn".
		Logger.Info("MonsterService: PvE deshabilitado por FeatureConfig; no apareceran monstruos.")
		return true
	end

	-- Un unico Heartbeat para TODOS los monstruos.
	if MaidRef then
		MaidRef:Connect(RunService.Heartbeat, function(dt: number)
			Service.StepAI(dt)
		end)
	end

	Logger.Info("MonsterService listo.")
	return true
end


--- @return boolean success
function Service.Destroy(): boolean
	Service.ClearAll()

	if Service._folder and Service._folder.Parent then
		Service._folder:Destroy()
	end

	Service._folder = nil
	Service._monsters = {}
	Service._roundService = nil
	Service._combatService = nil
	Service._playerService = nil
	Service._worldService = nil
	MaidRef = nil
	Service.IsInitialized = false
	return true
end

return Service

