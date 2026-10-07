--!strict
--[[
    MonsterService
    Instanciacion, estado y eliminacion de monstruos dentro del mundo de partida.

    FASE 0 - Bootstrap: interfaz declarada, sin implementar.
    La implementacion se realiza por fases, cuando existan las
    dependencias minimas que cada servicio necesita.
]]

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
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
local MonsterDeathRules =
	require(SHARED:WaitForChild("Libraries"):WaitForChild("MonsterDeathRules"))
local MonsterScaleRules =
	require(SHARED:WaitForChild("Libraries"):WaitForChild("MonsterScaleRules"))
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

-- MiniBossService: observador de muertes (FASE 15). Opcional:
-- sin el, los mini-bosses son fauna jugable; con el, cobran su
-- recompensa de tier y arrancan el enfriamiento de su zona.
Service._miniBossService = nil

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

--- Inyecta el `MiniBossService` (FASE 15).
---
--- Es un OBSERVADOR de las muertes, no una dependencia de
--- ciclo de vida: se inyecta con `pcall` desde `ServerMain`
--- por la misma razon que `PowerupService.SetMonsterService`
--- (la flecha iria al reves y crearia un ciclo topologico).
--- @param miniBossService any
function Service.SetMiniBossService(miniBossService: any)
	Service._miniBossService = miniBossService
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
	-- `BreakJointsOnDeath` se DESACTIVA a proposito.
	--
	-- Con el valor por defecto (true), el motor rompe las articulaciones
	-- del modelo en el instante de morir. Aqui eso no produce un cadaver
	-- creible: produce un modelo deshecho que `playDeathVfx` ya no puede
	-- encoger, y en un `Model` sin `Motor6D` deja al Humanoid en un estado
	-- en el que el servicio ya no puede ni congelarlo ni limpiarlo.
	--
	-- La muerte visible la hace ESTE servicio, con un plazo maximo, y para
	-- eso el modelo tiene que seguir intacto un momento.
	humanoid.BreakJointsOnDeath = false
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
---
--- Aun asi marca la muerte como `Dying`: si el `Died` del Humanoid llegara
--- tarde (por ejemplo, el mismo frame en que acaba la ronda), el registro
--- ya no esta en `_monsters` y no puede pagar nada.
--- @param monsterId number
local function despawnMonster(monsterId: number)
	local record = Service._monsters[monsterId]

	if not record then
		return
	end

	Service._monsters[monsterId] = nil
	record.Dead = true
	record.DeathState = MonsterDeathRules.States.Dying
	record.Rewarded = true

	if record.Model and record.Model.Parent then
		record.Model:Destroy()
	end
end

--- Tiempo maximo que un cadaver puede quedarse en el mapa, en segundos.
---
-- La animacion de muerte dura ~0.2 s. El plazo es cuatro veces eso: da
-- margen a un frame lento sin dejar un enemigo muerto visible ni un solo
-- frame mas de la cuenta.
local DEATH_CLEANUP_DEADLINE = 0.8

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

	-- PLAZO MAXIMO DE VIDA DEL CADAVER.
	--
	-- Es la garantia dura de que ningun enemigo muerto queda en el mapa.
	-- La animacion dura ~0.2 s; si no ha terminado para entonces (porque
	-- el modelo desaparecio a medias, porque `Body` no existe, o porque
	-- el hilo se atoro), el modelo se destruye igual.
	--
	-- Sin este `task.delay`, un enemigo que no puede morir VISIBLE se
	-- quedaba para siempre en el Workspace: es exactamente el sintoma
	-- "muere pero no desaparece", con el agravante de que ya no estaba en
	-- `_monsters`, asi que nada lo volvia a mirar.
	task.delay(DEATH_CLEANUP_DEADLINE, function()
		if model.Parent then
			model:Destroy()
		end
	end)

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
-- ---------------------------------------------------------------------------
-- BOSS: barra de vida del HUD y FASES
--
-- MEDIDO EN AUDITORIA: el HUD ya tenia panel de boss y lo leia de tres
-- atributos (`BossName`, `BossHealth`, `BossMaxHealth`), pero NINGUN punto del
-- servidor los escribia. El panel existia, era correcto, y no se encendia
-- nunca porque no habia boss. Un panel que nunca aparece es indistinguible de
-- un panel roto, asi que la escritura va AQUI, que es donde vive la verdad.
--
-- La barra se publica SOLO a los jugadores que estan en el mundo del boss.
-- Publicarla a todos haria que un jugador en Forest viera la vida del Cyber
-- Core mientras pelea con slimes.
-- ---------------------------------------------------------------------------

--- Boss vivo por mundo: worldId -> monsterId.
Service._bossesByWorld = {}

--- Fase actual de un boss y el multiplicador que aplica.
--
-- FASES, y por que existen: un boss con una sola fase es un monstruo grande.
-- Al bajar del 60 % y del 30 % de vida sube la presion: mas dano, mas
-- velocidad de persecucion y menos recuperacion. El jugador ve que el duelo
-- ha cambiado sin que nadie le avise, que es la forma en que se comunica
-- "ahora hace falta mas que una bomba".
local BOSS_PHASES = {
	{ At = 1.0, Damage = 1.0, Speed = 1.0, Recovery = 1.0, Name = "" },
	{ At = 0.6, Damage = 1.25, Speed = 1.15, Recovery = 0.85, Name = "FURIA" },
	{ At = 0.3, Damage = 1.5, Speed = 1.3, Recovery = 0.7, Name = "FURIA" },
}

--- Fase que corresponde a una fraccion de vida.
--- @param ratio number 0..1
--- @return number indice de fase (1..#BOSS_PHASES)
local function phaseFor(ratio: number): number
	local index = 1

	for i, phase in ipairs(BOSS_PHASES) do
		if ratio <= phase.At then
			index = i
		end
	end

	return index
end

--- Publica (o retira) la barra de vida del boss de un mundo.
---
--- Se recorre SIEMPRE a todos los jugadores, tambien a los que no estan en el
--- mundo del boss: son ellos los que necesitan que la barra se APAGUE. Un
--- `continue` antes de limpiar dejaria la barra encendida en el HUD de quien
--- salio del mundo, que es la clase de estado fantasma que el jugador
--- reporta como "el juego va raro".
--- @param worldId string
--- @param record table? nil retira la barra
local function publishBossBar(worldId: string, record: { [string]: any }?)
	local humanoid = record and record.Humanoid

	for _, player in ipairs(Players:GetPlayers()) do
		-- El atributo `World` lo escribe `MatchService.MovePlayer` en cada
		-- traslado, asi que es la verdad de "donde estoy" sin preguntas.
		local isHere = humanoid ~= nil and player:GetAttribute("World") == worldId

		if not isHere then
			player:SetAttribute("BossName", nil)
			player:SetAttribute("BossHealth", nil)
			player:SetAttribute("BossMaxHealth", nil)
			continue
		end

		player:SetAttribute("BossName", record.Def.Name)
		player:SetAttribute("BossHealth", humanoid.Health)
		player:SetAttribute("BossMaxHealth", humanoid.MaxHealth)
	end
end

--- Refresca la barra del boss: vida Y fase.
---
--- Se llama desde el impacto de la bomba y desde el latido, porque la vida
--- tambien baja por cosas que no son una bomba (la quemadura del Magma Lord,
--- un bloque que el boss rompe). Publicar solo en el impacto dejaba la barra
--- congelada cuando el dano venia de otro sitio.
--- @param record table
local function syncBossBar(record: { [string]: any })
	if not record.IsBoss then
		return
	end

	local humanoid = record.Humanoid

	if not humanoid or not record.WorldId then
		return
	end

	local max = if humanoid.MaxHealth > 0 then humanoid.MaxHealth else 1
	local ratio = math.clamp(humanoid.Health / max, 0, 1)
	local phase = phaseFor(ratio)

	if record.Phase ~= phase then
		record.Phase = phase

		-- El nombre de la fase viaja en el MISMO atributo que el nombre del
		-- boss: el HUD ya lo sabe pintar y no hace falta un panel nuevo. Es lo
		-- que hace que el jugador lea "FURIA" sin instrucciones.
		local suffix = BOSS_PHASES[phase].Name
		record.DisplayName = if suffix ~= ""
			then ("%s - %s"):format(record.Def.Name, suffix)
			else record.Def.Name

		if humanoid.DisplayName ~= record.DisplayName then
			humanoid.DisplayName = record.DisplayName
		end

		Logger.Info(("boss %s en fase %d (%s)"):format(record.Def.Id, phase, record.DisplayName))
	end

	publishBossBar(record.WorldId, record)
end

--- Elimina TODOS los monstruos vivos (fin de ronda, cambio de mundo).
---
--- NO paga recompensa: morirse porque acabo la ronda no es una muerte del
--- jugador, y pagar aqui permitiria farmear XP(selectround) sin limite.
--- @return number removed
function Service.ClearAll(): number
	local removed = Service.GetAliveCount()

	-- MEDIDO EN AUDITORIA: `ClearAll` borraba los monstruos pero no apagaba
	-- la barra del boss. Volviendo al lobby con el boss de Cyber a media vida
	-- en el HUD, el panel se quedaba encendido para siempre.
	Service._bossesByWorld = {}

	for worldId in pairs(MonsterScaleRules.BossByWorld) do
		publishBossBar(worldId, nil)
	end

	for monsterId in pairs(Service._monsters) do
		despawnMonster(monsterId)
	end

	return removed
end

--- Boss vivo de un mundo, o nil si todavia no ha aparecido.
---
--- Lo consultan `MatchService` (para no generar dos) y las sondas de QA.
--- @param worldId string
--- @return number? monsterId
function Service.GetBossId(worldId: string): number?
	return Service._bossesByWorld[worldId]
end

--- Registro completo del boss de un mundo. Solo para diagnostico.
--- @param worldId string
--- @return { [string]: any }?
function Service.GetBoss(worldId: string): { [string]: any }?
	local monsterId = Service._bossesByWorld[worldId]

	if not monsterId then
		return nil
	end

	return Service._monsters[monsterId]
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
--- Genera un monstruo.
---
--- El `worldId` es OPCIONAL y no es decorativo: decide la escala. El
--- multiplicador de mundo vive en `MonsterScaleRules` y se aplica al
--- modelo, nunca a la hitbox, para que un enemigo mas grande en el Cyber
--- no convierta los pasillos en muros.
---
--- @param definitionId string
--- @param position Vector3
--- @param worldId string? mundo al que pertenece la arena
--- @return number? monsterId
function Service.Spawn(definitionId: string, position: Vector3, worldId: string?): number?
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

	-- Se aplica el multiplicador de MUNDO sobre una COPIA de la definicion.
	--
	-- Se copia y no se modifica la original porque `MonsterDefinitions` es
	-- una tabla COMPARTIDA: si `Spawn` escribiera `def.WorldScale` ahi, el
	-- primer monstruo del Cyber dejaria al Slime del Forest con escala de
	-- Cyber para siempre, y el orden de aparicion decidiria el tamano de
	-- los bichos.
	local worldMultiplier = MonsterScaleRules.GetWorldScale(worldId)
	local spawnDef = def

	if worldMultiplier ~= 1 then
		spawnDef = {}
		for key, value in pairs(def) do
			spawnDef[key] = value
		end

		spawnDef.WorldScale = worldMultiplier
	end

	local model = buildMonsterModel(spawnDef)

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
		-- Mascara de muerte. `Alive` es el unico estado en el que el
		-- enemigo actua, recibe dano y puede cobrar recompensa. `Dead`
		-- se conserva como espejo por compatibilidad con las sondas de QA
		-- y los verificadores, que han leido siempre ese campo.
		DeathState = MonsterDeathRules.States.Alive,
		Rewarded = false,
		NextAttackAt = 0,
		State = AIService.States.Patrol,
		TimeInState = 0,
		AnchorPosition = Vector3.new(position.X, position.Y, position.Z),
		PatrolTarget = nil,
		PatrolIndex = 0,
		PatrolRetargetAt = 0,
		Path = nil,
		PathIndex = 0,
		PathGoal = nil,
		PathPending = false,
		PathGeneration = 0,
		PathRefreshAt = 0,
		PathRetryAt = 0,

		-- Boss. `IsBoss` NO se deduce del tamano: lo declara la definicion.
		-- `WorldId` se guarda porque la barra del HUD se publica por mundo, y
		-- `Phase` arranca en 1 (la calma) para que el primer impacto ya
		-- compruebe si hay que cambiar de fase.
		IsBoss = def.IsBoss == true,
		WorldId = worldId or def.World,
		Phase = 1,
		DisplayName = def.Name,
	}

	local record = Service._monsters[monsterId]

	if record.IsBoss and record.WorldId then
		Service._bossesByWorld[record.WorldId] = monsterId
		-- El atributo `IsBoss` lo leen las sondas de QA y las herramientas de
		-- diagnostico para no contar un jefe como fauna.
		model:SetAttribute("IsBoss", true)
		syncBossBar(record)
	end

	model:SetAttribute("AIState", AIService.States.Patrol)

	Service._spawned += 1
	syncMonsterHealthTag(record)

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

	Logger.Debug(
		("monstruo %d (%s) creado en (%.0f, %.0f, %.0f)"):format(
			monsterId,
			definitionId,
			position.X,
			position.Y,
			position.Z
		)
	)

	return monsterId
end
--- Procesa la muerte de un monstruo y paga UNA vez.
---
--- BUG CORREGIDO (auditoria global de gameplay: "Health = 0 pero el
--- monstruo sigue vivo, persiguiendo y golpeando").
---
--- La causa NO era el dano: era que la muerte no tenia ESTADO. Habia un
--- unico `record.Dead`, que se ponia a true DENTRO del manejador de
--- `Humanoid.Died` y en ningun otro sitio. De ahi salian tres fallos:
---
---  1. Si `Died` no se disparaba, nadie lo comprobaba. Ahora la funcion
---     es publica y hay un BARRIDO (`SweepDead`) que la llama cada latido
---     sobre cualquier enemigo con `Health <= 0`: la muerte vive en el
---     servicio, no en manos de un unico evento.
---  2. `LastDamageSource` se escribia DESPUES de `TakeDamage`, y
---     `TakeDamage` dispara `Died` de forma sincrona: el manejador leia
---     al asesino ANTERIOR. La muerte se procesaba sin paga, o con el
---     premio de otro jugador. Corregido en `ApplyDamageToMonster`.
---  3. Si la animacion de muerte fallaba, el modelo se quedaba en el
---     mapa para siempre. Ahora el cleanup tiene un PLAZO MAXIMO: un
---     enemigo que no puede morir visible desaparece igualmente.
---
--- El estado vive en `MonsterDeathRules` (Alive -> Dying -> Dead ->
--- Cleaned), que es logica pura y se prueba sin motor.
---
--- @param monsterId number
--- @return boolean died true si ESTA llamada proceso la muerte
function Service.OnMonsterDied(monsterId: number): boolean
	local record = Service._monsters[monsterId]

	if not record then
		return false
	end

	-- ATOMICIDAD. `EnterDying` concede el derecho a pagar UNA sola vez.
	-- Dos golpes simultaneos (una bomba y un bloque reventado en el
	-- mismo frame) llegan los dos aqui: solo el primero obtiene `Dying`.
	if not MonsterDeathRules.EnterDying(record.DeathState) then
		return false
	end

	record.DeathState = MonsterDeathRules.States.Dying
	record.Dead = true
	Service._killed += 1

	-- CONGELACION INMEDIATA, antes de pagar y antes de animar.
	--
	-- En el frame en que un enemigo muere le queda todavia un latido de
	-- `Heartbeat` por delante. Sin esto, un monstruo al que una cadena de
	-- bombas mata durante su propio `Attack` puede completar el golpe y
	-- mover el modelo antes de desaparecer.
	if record.Humanoid then
		record.Humanoid.WalkSpeed = 0
		record.Humanoid.JumpPower = 0
		record.Humanoid.AutoRotate = false
		pcall(function()
			record.Humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		end)
	end

	-- Se anula el objetivo y el punto de patrulla: un enemigo en `Dying`
	-- no puede recordar a nadie ni volver a su sitio.
	record.State = AIService.States.Recovery
	record.TimeInState = 0
	record.PatrolTarget = nil
	record.NextAttackAt = math.huge

	-- Quien lo mato lo decide el Humanoid, igual que entre jugadores. Un
	-- monstruo que muere por su propia explosion no se atribuye a nadie.
	local sourceId = record.Humanoid and record.Humanoid:GetAttribute("LastDamageSource")
	local killer = if type(sourceId) == "number" then Players:GetPlayerByUserId(sourceId) else nil
	local def = record.Def

	-- El registro se borra ANTES de pagar: para que la cadena de explosiones
	-- no lo encuentre, y para que `StepAI` deje de moverlo ya.
	Service._monsters[monsterId] = nil

	-- La barra del boss se APAGA aqui, antes de pagar y antes de la
	-- animacion: el jugador mataba al boss, cobraba, y volvia al lobby con
	-- una barra de jefe al 4 % pegada en la pantalla.
	if record.IsBoss and record.WorldId then
		if Service._bossesByWorld[record.WorldId] == monsterId then
			Service._bossesByWorld[record.WorldId] = nil
		end

		publishBossBar(record.WorldId, nil)
	end

	record.DeathState = MonsterDeathRules.States.Dead

	-- La muerte se ANIMA y se destruye sola, con un PLAZO MAXIMO.
	--
	-- El plazo no es estetico: es la garantia de que ningun enemigo queda
	-- en el mapa. Si el modelo desaparece antes, el cleanup no hace nada;
	-- si la animacion se atasca, `task.delay` lo elimina igualmente.
	playDeathVfx(record)

	-- La recompensa se cobra UNA vez. `ClaimReward` es la segunda mitad de
	-- la atomicidad: aunque `OnMonsterDied` se llamara dos veces por un
	-- error de alguien, el XP no se paga dos veces.
	if MonsterDeathRules.ClaimReward(record.Rewarded) then
		record.Rewarded = true

		if killer and Service._playerService then
			Service._playerService.AddRewards(killer, def.XP, def.Coins)
			Logger.Debug(
				("%s mato a %s: +%d XP +%d monedas"):format(killer.Name, def.Id, def.XP, def.Coins)
			)
		end

		-- El progreso de mision va DENTRO del bloque del asesino, y no
		-- aparte con un segundo `if killer`: un monstruo que muere por su
		-- propia explosion intentaria progresar con `killer = nil`, que es
		-- justo el caso que NO debe contar.
		--
		-- Y va DESPUES de pagar: si el pago falla, el monstruo esta muerto
		-- y la ronda continua.
		if killer and Service._questService ~= nil then
			Service._questService.RecordMetric(killer, "MonsterDefeated", 1)
		end
	end

	-- MINI-BOSSES (FASE 15).
	--
	-- La notificacion va AQUI, dentro de `ClaimReward` y ANTES de
	-- liberar el registro: `MiniBossService` necesita saber QUE
	-- murio (`record.Def.Id`), en QUE mundo (`record.WorldId`) y si
	-- la muerte ya cobro (`record.Rewarded`) para decidir si paga
	-- SU recompensa escalada y arranca el enfriamiento de la zona.
	--
	-- El aviso es OPCIONAL por la misma razon que las flechas de
	-- `PowerupService`: un servicio que observa no puede impedir
	-- que el juego funcione sin el. Sin `MiniBossService`, los
	-- mini-bosses mueren como fauna normal (el `MonsterDefinitions`
	-- de arriba los declara jugables); con el, ademas cobran su
	-- recompensa de tier y activan el cooldown de su zona.
	if Service._miniBossService then
		pcall(Service._miniBossService.OnMonsterDied, monsterId, record)
	end

	-- Liberacion de referencias. Un registro de muerte que conserve el
	-- Humanoid y el modelo es una fuga por cada enemigo muerto en la ronda.
	record.Humanoid = nil
	record.RootPart = nil
	record.DeathState = MonsterDeathRules.States.Cleaned

	Logger.Debug(("monstruo %d (%s) eliminado"):format(monsterId, def.Id))
	return true
end

--- Detecta enemigos con `Health <= 0` a los que la muerte NO ha llegado.
---
--- Es la RED DE SEGURIDAD del bug "0 de vida y vivo". `Humanoid.Died` es
--- un evento: si no se dispara, no hay nadie que reaccione. Este barrido
--- corre en CADA latido y es idempotente, asi que un `Died` perdido se
--- recupera en cuanto se nota, y un `Died` duplicado no hace nada.
---
--- @return number swept enemigos cuya muerte se ha procesado aqui
function Service.SweepDead(): number
	local swept = 0

	for monsterId, record in pairs(Service._monsters) do
		if MonsterDeathRules.CanAct(record.DeathState) then
			local humanoid = record.Humanoid
			local health = if humanoid then humanoid.Health else 0

			-- Tres senales de "este enemigo deberia estar muerto": vida
			-- cero, sin Humanoid o sin modelo. Las tres son el mismo
			-- contrato: `Alive` sin nada que lo justifique.
			local broken = health <= 0
				or humanoid == nil
				or record.Model == nil
				or not record.Model.Parent

			if broken and Service.OnMonsterDied(monsterId) then
				swept += 1
				Logger.Debug(
					("barrido: monstruo %d figuraba vivo con %.0f de vida; muerte forzada"):format(
						monsterId,
						health
					)
				)
			end
		end
	end

	return swept
end

--- ?Este Humanoid es un monstruo de este servicio?
--- @param humanoid Humanoid
--- @return boolean
function Service.IsMonsterHumanoid(humanoid: Humanoid): boolean
	for _, record in pairs(Service._monsters) do
		if record.Humanoid == humanoid and MonsterDeathRules.CanAct(record.DeathState) then
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
	-- Un dano que no es un numero positivo no es dano. Antes pasaba al
	-- `TakeDamage` y devolvia `true`, y el llamante contaba una victima mas
	-- de las que habia.
	if type(amount) ~= "number" or amount <= 0 or amount ~= amount then
		return false
	end

	for _, record in pairs(Service._monsters) do
		if record.Humanoid == humanoid and MonsterDeathRules.CanAct(record.DeathState) then
			-- ATRIBUCION ANTES DEL DANO.
			--
			-- `TakeDamage` dispara `Died` de forma SINCRONA cuando baja la
			-- vida a cero, y `Died` es quien decide a quien se paga. Si el
			-- atributo se escribiera despues (que era lo que hacia), en el
			-- GOLPE MORTAL el manejador leeria al asesino ANTERIOR: la
			-- muerte se procesaba sin paga, o con el premio de otro jugador.
			--
			-- Es un fallo invisible: el enemigo moria igual, el contador de
			-- bajas subia, y el XP no llegaba.
			if sourceUserId then
				humanoid:SetAttribute("LastDamageSource", sourceUserId)
			end

			humanoid:TakeDamage(amount)

			-- El jugador tiene que ver que su bomba ha HIGIDO. Sin destello
			-- y sin barra que baje, acertar y fallar se ven igual.
			flashMonster(record)
			syncMonsterHealthTag(record)
			-- La barra del boss se refresca AQUI, en el impacto, y no solo en
			-- el latido: el efecto de "mi bomba ha pegado en el jefe" tiene que
			-- verse en el MISMO instante de la explosion.
			syncBossBar(record)

			-- RED DE SEGURIDAD: si el Humanoid llegara a 0 y `Died` no se
			-- hubiera disparado todavia, la muerte se procesa aqui mismo en
			-- lugar de esperar al siguiente latido. Es idempotente, asi que
			-- cuando `Died` llegue un instante despues no hara nada.
			if humanoid.Health <= 0 then
				Service.OnMonsterDied(record.Id)
			end

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
local AI_PATH_REFRESH_SECONDS = 1.6
local AI_PATH_TARGET_SHIFT_STUDS = 14
local AI_PATH_RETRY_SECONDS = 1.25
local AI_PATH_GLOBAL_INTERVAL = 0.1
local AI_PATH_MAX_CONCURRENT = 2
local _activePathComputations = 0
local _nextPathRequestAt = 0

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
		return { Move = false, Target = nil, Distance = 0 }
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
		return { Move = false, Target = record.PatrolTarget, Distance = 0 }
	end

	return {
		Move = true,
		Target = record.PatrolTarget,
		Distance = flat.Magnitude,
	}
end

local function requestPath(record: { [string]: any }, destination: Vector3, now: number)
	local root = record.RootPart
	if not root or not root.Parent or record.PathPending or now < (record.PathRetryAt or 0) then
		return
	end

	local previousGoal = record.PathGoal
	local goalShifted = not previousGoal
		or (destination - previousGoal).Magnitude >= AI_PATH_TARGET_SHIFT_STUDS
	local pathMissing = not record.Path or (record.PathIndex or 0) > #record.Path
	local expired = now >= (record.PathRefreshAt or 0)
	if not pathMissing and not goalShifted and not expired then
		return
	end
	if _activePathComputations >= AI_PATH_MAX_CONCURRENT or now < _nextPathRequestAt then
		return
	end

	record.PathGeneration = (record.PathGeneration or 0) + 1
	local generation = record.PathGeneration
	record.PathPending = true
	record.PathGoal = destination
	record.PathRefreshAt = now + AI_PATH_REFRESH_SECONDS
	_activePathComputations += 1
	_nextPathRequestAt = now + AI_PATH_GLOBAL_INTERVAL

	local start = root.Position
	local body = record.Model and record.Model:FindFirstChild("Body")
	local bodySize = if body and body:IsA("BasePart") then body.Size else root.Size
	local radius =
		math.clamp(math.max(root.Size.X, root.Size.Z, bodySize.X, bodySize.Z) * 0.5 + 0.5, 1.5, 7)
	local height = math.max(root.Size.Y, bodySize.Y, 5)
	task.spawn(function()
		local path: any = nil
		local ok = pcall(function()
			path = PathfindingService:CreatePath({
				AgentRadius = radius,
				AgentHeight = height,
				AgentCanJump = false,
				AgentCanClimb = false,
				WaypointSpacing = 8,
			})
			path:ComputeAsync(start, destination)
		end)
		_activePathComputations = math.max(0, _activePathComputations - 1)

		if Service._monsters[record.Id] ~= record or record.PathGeneration ~= generation then
			return
		end
		record.PathPending = false
		if ok and path and path.Status == Enum.PathStatus.Success then
			local waypoints = path:GetWaypoints()
			if #waypoints >= 2 then
				record.Path = waypoints
				record.PathIndex = 2
				return
			end
		end

		record.Path = nil
		record.PathIndex = 0
		record.PathRefreshAt = 0
		record.PathRetryAt = os.clock() + AI_PATH_RETRY_SECONDS
	end)
end

local function pathStep(record: { [string]: any }, destination: Vector3, now: number)
	requestPath(record, destination, now)
	local root = record.RootPart
	local waypoints = record.Path
	if not root or type(waypoints) ~= "table" then
		return { Move = false, Direction = { x = 0, y = 0, z = 0 }, Distance = 0 }
	end

	local index = record.PathIndex or 2
	while index <= #waypoints do
		local offset = waypoints[index].Position - root.Position
		local horizontal = Vector3.new(offset.X, 0, offset.Z)
		if horizontal.Magnitude >= AI_PATROL_ARRIVE_STUDS or math.abs(offset.Y) > 4 then
			break
		end
		index += 1
	end
	record.PathIndex = index
	if index > #waypoints then
		record.Path = nil
		return { Move = false, Direction = { x = 0, y = 0, z = 0 }, Distance = 0 }
	end
	local step = AIService.Step(root.Position, waypoints[index].Position, math.huge)
	step.TargetY = waypoints[index].Position.Y + root.Size.Y * 0.5
	return step
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
	record.PathGeneration = (record.PathGeneration or 0) + 1
	record.PathPending = false
	record.Path = nil
	record.PathIndex = 0
	record.PathGoal = nil
	record.PathRefreshAt = 0
	record.PathRetryAt = 0

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
				elseif state == AIService.States.Recovery then "-"
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
local function tickPersonality(
	record: { [string]: any },
	def: any,
	hasTarget: boolean,
	now: number,
	dt: number
)
	local model = record.Model

	if not model or not model.Parent or not def.Vanishes then
		return
	end

	local body = model:FindFirstChild("Body")
	if not body or not body:IsA("BasePart") then
		return
	end

	local alpha = tonumber(body:GetAttribute("FlickerAlpha")) or 0.1
	local goal = if hasTarget then (math.sin(now * AI_FADING_HZ) + 1) * 0.25 + 0.25 else 0.1

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

	-- El danio de la FASE. Un boss golpea mas fuerte cuanto mas le queda
	-- poco, y eso se aplica aqui, en el unico punto por el que pasa TODO el
	-- dano de un monstruo: si se multiplicase en `Spawn`, la fase nunca
	-- tendria efecto porque el multiplicador se calcula al generar.
	--
	-- Con `record.Phase` ya resuelto por `syncBossBar`, el cambio de fase y
	-- el golpe que lo dispara son el MISMO frame: el jugador ve "FURIA" y
	-- recibe el golpe mas fuerte a la vez, que es lo que hace que la fase
	-- se entienda sin instrucciones.
	local phase = BOSS_PHASES[if record.Phase then record.Phase else 1]
	local damage = if record.IsBoss then def.Damage * phase.Damage else def.Damage

	combat.ApplyDamage(targetHumanoid, damage)

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

				local base = humanoid:GetAttribute("BaseWalkSpeed") or GameConfig.DefaultPlayerSpeed

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
	-- EL BARRIDO DE MUERTE corre PRIMERO y FUERA del filtro de ronda.
	--
	-- Que este antes no es estetico: es la garantia de que un enemigo con
	-- 0 de vida deja de actuar en el MISMO latido en que se le vacia la
	-- vida, y no "en cuanto vuelva a haber ronda".
	--
	-- Que este fuera del filtro tampoco: un enemigo que muere en el
	-- ultimo instante de la ronda tiene que limpiarse igual, o se queda
	-- congelado en el mapa hasta la siguiente.
	Service.SweepDead()

	if not Service._roundService or not Service._roundService.IsPlaying() then
		return
	end

	local now = os.clock()

	for _, record in pairs(Service._monsters) do
		if
			MonsterDeathRules.CanAct(record.DeathState)
			and record.RootPart
			and record.RootPart.Parent
		then
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
			local nextState =
				AIService.Think(record.State, record.TimeInState or 0, def, hasTarget, distance)

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
			local patrol = if not hasTarget then patrolStep(record, now) else nil
			local destination = if hasTarget and targetRoot
				then targetRoot.Position
				else patrol and patrol.Move and patrol.Target or nil
			local step = if AIService.CanMove(record.State) and destination
				then pathStep(record, destination, now)
				else { Move = false, Direction = { x = 0, y = 0, z = 0 }, Distance = 0 }

			if AIService.CanMove(record.State) and step.Move and speed > 0 and step.Direction then
				local planar = Vector3.new(step.Direction.x, 0, step.Direction.z) * speed * dt
				local targetY = if type(step.TargetY) == "number" then step.TargetY else origin.Y
				local verticalRate = math.min(speed * 0.35, 3)
				local moved = Vector3.new(
					origin.X + planar.X,
					origin.Y + math.clamp(targetY - origin.Y, -verticalRate * dt, verticalRate * dt),
					origin.Z + planar.Z
				)

				-- BUG CORREGIDO (medido en PLAY): esto movia SOLO `RootPart`.
				-- `Body` es hermano de la raiz, no hijo, y se quedaba en el
				-- sitio: el monstruo persiguia dejando una estela de cuerpos
				-- parados, y desde lejos parecia que no se movia.
				--
				-- Ahora se mueve el MODELO ENTERO (`PivotTo`), que es lo que el
				-- jugador ve, y se orienta hacia el objetivo para que los ojos
				-- miren a donde va.
				local lookAt = destination

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
			if
				record.State == AIService.States.Attack
				and (record.TimeInState or 0) < dt * 2
				and targetHumanoid
			then
				if AIService.ShouldAttack(distance, def.AttackRange) then
					applyMonsterHit(record, targetHumanoid, def)
				else
					-- Escapaste. Es un resultado VALIDO del ataque, no un fallo
					-- del sistema, y no se registra como error.
					Logger.Debug(
						("%s cargo y fallo: el jugador salio de su alcance"):format(def.Id)
					)
				end
			end

			-- 5. PERSONALIDAD con efecto de tiempo.
			tickPersonality(record, def, hasTarget, now, dt)

			-- 6. BARRA DEL BOSS.
			--
			-- Se refresca en el LATIDO y no solo en el impacto de la bomba
			-- porque el boss tambien pierde vida por otras vias (la quemadura
			-- del Magma Lord, el hielo del Frost King, un bloque que le
			-- revienta encima). Con la barra congelada, el jugador ve un 100 %
			-- permanente y concluye que su bomba no hace nada: el sintoma
			-- "las bombas no funcionan contra el boss" sin que las bombas
			-- estuvieran rotas.
			if record.IsBoss then
				syncBossBar(record)
			end
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
		Health = record.Humanoid and record.Humanoid.Health or 0,
		DeathState = record.DeathState,
		Position = record.RootPart and record.RootPart.Position or Vector3.zero,
	}
end

--- Informe de la mascara de muerte. Diagnostico para QA.
---
--- La pregunta que responde es "deberia haber enemigos vivos aqui?", y la
--- respuesta tiene que poder contarse sin abrir el Workspace a mano.
--- @return { alive: number, dying: number, dead: number, cleaned: number }
function Service.GetDeathReport()
	local report = { alive = 0, dying = 0, dead = 0, cleaned = 0 }

	for _, record in pairs(Service._monsters) do
		local state = record.DeathState

		if state == MonsterDeathRules.States.Alive then
			report.alive += 1
		elseif state == MonsterDeathRules.States.Dying then
			report.dying += 1
		elseif state == MonsterDeathRules.States.Dead then
			report.dead += 1
		elseif state == MonsterDeathRules.States.Cleaned then
			report.cleaned += 1
		end
	end

	return report
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
	Service._bossesByWorld = {}
	Service._nextMonsterId = 0
	Service._spawned = 0
	Service._killed = 0

	if not Service.GetFolder() then
		Logger.Error("MonsterService: no se pudo crear la carpeta de monstruos.")
		return false
	end

	Service.IsInitialized = true
	Logger.Info(
		("MonsterService: %d definiciones de monstruo"):format(#MonsterDefinitions.GetIds())
	)

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
		Logger.Info(
			("MonsterService: balance de velocidad correcto frente a un jugador de %d studs/s"):format(
				GameConfig.DefaultPlayerSpeed
			)
		)
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
	Service._bossesByWorld = {}
	Service._roundService = nil
	Service._combatService = nil
	Service._playerService = nil
	Service._worldService = nil
	MaidRef = nil
	Service.IsInitialized = false
	return true
end

return Service
