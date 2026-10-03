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
	humanoid.WalkSpeed = def.Speed
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

	Service._monsters[monsterId] = {
		Id = monsterId,
		Def = def,
		Model = model,
		Humanoid = humanoid,
		RootPart = root,
		Dead = false,
		NextAttackAt = 0,
	}

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


--- UN SOLO paso de IA para todos los monstruos.
---
--- Se llama desde UN Heartbeat del servidor, no uno por monstruo: 30
--- monstruos con 30 corrutinas moviendose cada frame es la forma rapida de
--- hundir un servidor, y aqui se evita por construccion.
---
--- El `dt` lo pasa quien llama en lugar de usar `Heartbeat:Wait()`: dentro
--- de un `Heartbeat` eso devolveria 0 y los monstruos no se moverian, y
--- ademas `Wait()` dentro de la conexion bloquearia a los demas.
--- @param dt number
function Service.StepAI(dt: number)
	if not Service._roundService or not Service._roundService.IsPlaying() then
		return
	end

	for _, record in pairs(Service._monsters) do
		if not record.Dead and record.RootPart and record.RootPart.Parent then
			local def = record.Def
			local origin = record.RootPart.Position
			local target = Service.FindNearestPlayer(origin, def.DetectionRange)

			if target and target.Character then
				local targetRoot = target.Character:FindFirstChild("HumanoidRootPart")
				local targetHumanoid = target.Character:FindFirstChildOfClass("Humanoid")

				if targetRoot and targetHumanoid and targetHumanoid.Health > 0 then
					local step = AIService.Step(origin, targetRoot.Position, def.DetectionRange)

					if step.Move then
						local speed = AIService.ChaseSpeed(def.Speed, def.ChaseMultiplier)
						local moved = origin
							+ Vector3.new(step.Direction.x, 0, step.Direction.z) * speed * dt

						-- BUG CORREGIDO (medido en PLAY): esto movia SOLO
						-- `RootPart`. `Body` es hermano de la raiz, no hijo, y
						-- se quedaba en el sitio: el monstruo persiguia al
						-- jugador dejando una estela de cuerpos parados, y
						-- desde lejos parecia que no se movia.
						--
						-- Ahora se mueve el MODELO ENTERO (`PivotTo`), que es
						-- lo que el jugador ve, y se orienta hacia el objetivo
						-- para que los ojos miren a donde va.
						local lookAt = targetRoot.Position

						if (lookAt - moved).Magnitude > 0.5 then
							record.Model:PivotTo(CFrame.lookAt(moved, lookAt))
						else
							record.Model:PivotTo(CFrame.new(moved))
						end
					end

					-- Ataque por contacto, con su propio tiempo de recarga.
					--
					-- El ataque pasa SIEMPRE por CombatService: es la unica
					-- autoridad de dano del servidor. Si el monstruo
					-- llamara a TakeDamage sobre el jugador, se saltarian la
					-- invulnerabilidad y la regla de ronda.
					if
						Service._combatService
						and AIService.ShouldAttack(step.Distance, def.AttackRange)
						and os.clock() >= (record.NextAttackAt or 0)
					then
						record.NextAttackAt = os.clock() + def.AttackCooldown
						Service._combatService.ApplyDamage(targetHumanoid, def.Damage)
					end
				end
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

