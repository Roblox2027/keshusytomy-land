--!strict
--[[
	ExplosionService
	Resolucion de dano por area de una explosion (FASE 5).

	Es la UNICA fuente de dano por explosion en el servidor. El cliente
	nunca aplica dano: solo pide colocar una bomba, y el resto lo decide
	este servicio.

	Cadena de una explosion:
		1. Recoger partes dentro del radio.
		2. Para cada personaje, comprobar linea de tiro (raycast).
		3. Dano por distancia, atenuado si hay un muro de por medio.
		4. Dano a bloques destructibles, delegando en DestructionService.

	Reglas de seguridad:
	- El RADIO NUNCA se toma del cliente: viene de GameConfig.
	- El DANO se aplica SIEMPRE a traves de CombatService, que es la
	  unica autoridad (invulnerabilidad, ronda, atribucion).
	- La cadena de bombas la resuelve BombService, no aqui.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
-- Necesario para resolver el `sourceUserId` de una explosion a un jugador
-- real. Se importa aqui y no se pasa como dependencia porque es un dato
-- de PLATAFORMA, no de dominio: cualquier servicio puede leer el jugador
-- sin que eso sea una razon para conocer a los demas servicios.
local Players = game:GetService("Players")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONFIG = SHARED:WaitForChild("Config")
local UTILS = SHARED:WaitForChild("Utils")

local GameConfig = require(CONFIG:WaitForChild("GameConfig"))
local PerformanceConfig = require(CONFIG:WaitForChild("PerformanceConfig"))
local CombatMath = require(SHARED:WaitForChild("Libraries"):WaitForChild("CombatMath"))
local VisualKit = require(SHARED:WaitForChild("Libraries"):WaitForChild("VisualKit"))
local Logger = require(UTILS:WaitForChild("Logger"))

local Service = {}

Service.IsInitialized = false

-- Servicios inyectados para no crear dependencias circulares entre
-- servicios: el registro los pasa al arrancar.
Service._destruction = nil
Service._combat = nil

-- MonsterService (inyectado por la flecha inversa que cablea
-- `ServerMain`) y QuestService. Los dos son OPCIONALES: sin ellos el
-- combate funciona igual y solo se pierde el progreso de misiones.
Service._monsters = nil
Service._questService = nil

-- Contadores (diagnostico).
Service._explosionCount = 0
Service._blockedExplosions = 0

--- Carpeta de efectos visuales. Se crea una vez y se reutiliza.
Service._vfxFolder = nil
-- Efectos vivos ahora mismo (limite duro de rendimiento).
Service._activeVFX = 0

--- Inyecta los servicios de destruccion y combate.
--- @param destructionService any
--- @param combatService any
function Service.SetDependencies(destructionService: any, combatService: any)
	Service._destruction = destructionService
	Service._combat = combatService
end

--- Inyecta MonsterService para que las explosiones danen tambien al PvE.
---
--- Es una inyeccion APARTE y no un cuarto argumento de `SetDependencies`
--- porque los monstruos llegaron despues que el cableado original: anadir
--- un parametro a un metodo que ya llamaban tres sitios habria exigido
--- tocarlos todos y el forgetting de uno daria un `nil` silencioso.
--- @param monsterService any
function Service.SetMonsterService(monsterService: any)
	Service._monsters = monsterService
end

--- Conecta el receptor de progreso de misiones.
---
--- Es OPCIONAL: sin el, las explosiones funcionan igual y solo las misiones
--- que cuentan bloques destruidos no avanzan. El sistema de misiones no
--- puede ser un punto unico de fallo del combate.
--- @param questService any?
function Service.SetQuestService(questService: any)
	Service._questService = questService
end

--- @return number
function Service.GetExplosionCount(): number
	return Service._explosionCount
end

--- Partes dentro del radio de la explosion.
---
--- `GetPartBoundsInRadius` respeta las colisiones. La oclusion real la
--- decide el raycast de `hasLineOfSight`.
--- @param center Vector3
--- @param radius number
--- @return { BasePart }
local function getPartsInRadius(center: Vector3, radius: number): { BasePart }
	local query = OverlapParams.new()
	query.FilterType = Enum.RaycastFilterType.Include
	query.FilterDescendantsInstances = { Workspace }
	query.RespectCanCollide = true

	local parts = {}

	for _, instance in ipairs(Workspace:GetPartBoundsInRadius(center, radius, query)) do
		table.insert(parts, instance :: BasePart)
	end

	return parts
end

--- Indica si hay linea libre entre la explosion y un objetivo.
---
--- El objetivo se excluye del raycast: si no, el raycast terminaria en
--- el primer centimetro y todo pareceria bloqueado.
--- @param center Vector3
--- @param targetPart BasePart
--- @return boolean
local function hasLineOfSight(center: Vector3, targetPart: BasePart): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { targetPart }

	local direction = targetPart.Position - center

	if direction.Magnitude <= 0 then
		return true
	end

	return Workspace:Raycast(center, direction, params) == nil
end

--- Dano por distancia: maximo en el centro, cero en el borde.
--- @param distance number
--- @param radius number
--- @return number damage
function Service.ComputeDamage(distance: number, radius: number): number
	return CombatMath.FalloffDamage(distance, radius, GameConfig.DefaultBombDamage)
end


--- Crea el efecto visual de una explosion.
---
--- MEDIDO en PLAY: antes era una Part INVISIBLE con dos emisores. Se veia
--- una nube, pero no el nucleo ni la onda, y sobre todo no el RADIO. El
--- jugador no puede esquivar con conocimiento lo que no puede medir.
---
--- Ahora son tres cosas que se leen de una vistazo:
---   nucleo  -> el IMPACTO (donde explota)
---   onda   -> el RADIO (hasta donde llega)
---   luz    -> la duracion (todo esto dura menos de medio segundo)
---
--- Se autodestruye. El limite `MaxVFX` evita que 100 explosiones
--- simultaneas creen cientos de instancias.
--- @param center Vector3
--- @param radius number
--- @param worldId string?
local function spawnExplosionVfx(center: Vector3, radius: number, worldId: string?)
	if not Service._vfxFolder or Service._activeVFX >= PerformanceConfig.Limits.MaxVFX then
		return
	end

	local model = VisualKit.BuildExplosion(center, radius, worldId, Service._vfxFolder)

	if not model then
		return
	end

	Service._activeVFX += 1

	local core = model:FindFirstChild("Core")
	local wave = model:FindFirstChild("Shockwave")
	local flash = model:FindFirstChild("Flash", true)
	local smoke = model:FindFirstChild("Smoke", true)
	local light = model:FindFirstChild("Light", true)

	local safeRadius = if radius and radius > 0 then radius else GameConfig.DefaultBombRadius

	-- El nucleo crece rapido y se apaga: es un flash, no una bombilla.
	if core and core:IsA("BasePart") then
		TweenService:Create(
			core,
			TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = Vector3.new(safeRadius * 0.5, safeRadius * 0.5, safeRadius * 0.5), Transparency = 1 }
		):Play()
	end

	-- La onda crece hasta el RADIO EXACTO y se desvanece. Es la informacion
	-- que convierte "me ha pegado una bomba" en "ponia la bomba aqui".
	if wave and wave:IsA("BasePart") then
		TweenService:Create(
			wave,
			TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				Size = Vector3.new(safeRadius * 2, 0.6, safeRadius * 2),
				Transparency = 1,
			}
		):Play()
	end

	if light and light:IsA("PointLight") then
		TweenService:Create(
			light,
			TweenInfo.new(0.3),
			{ Brightness = 0 }
		):Play()
	end

	-- Se emiten unas pocas particulas y se programa el borrado. Sin
	-- este `task.spawn`, cada explosion dejaria dos emitters vivos
	-- para siempre (una fuga por bomba).
	task.spawn(function()
		if smoke and smoke:IsA("ParticleEmitter") then
			smoke:Emit(24)
		end

		if flash and flash:IsA("ParticleEmitter") then
			flash:Emit(14)
		end

		-- 0.8 s, no la mecha completa (3 s): el efecto de una explosion no
		-- puede durar mas que la explosion. Antes se usaba la mecha y el
		-- Workspace acumulaba un modelo VFX por bomba durante 3 segundos.
		task.wait(0.8)

		if model.Parent then
			model:Destroy()
		end
		Service._activeVFX = math.max(0, Service._activeVFX - 1)
	end)
end


--- Resuelve una explosion en el servidor.
---
--- @param center Vector3
--- @param radius number
--- @param sourceUserId number? quien coloco la bomba (atribucion)
--- @return number affected partes afectadas
function Service.Detonate(center: Vector3, radius: number, sourceUserId: number?, worldId: string?): number
	-- Un radio no positivo o una posicion no finita indicaria un bug o
	-- un intento de exploit: se ignora sin propagar el error.
	local validPosition = CombatMath.ValidatePosition(center.X, center.Y, center.Z)

	if radius <= 0 or not validPosition then
		Service._blockedExplosions += 1
		Logger.Warn(("explosion ignorada: centro=%s radio=%s"):format(tostring(center), tostring(radius)))
		return 0
	end

	Service._explosionCount += 1
	spawnExplosionVfx(center, radius, worldId)

	local affected = 0
	-- Humanoids ya tocados: un personaje con varias partes dentro del
	-- radio solo debe recibir dano una vez.
	local damagedHumanoids = {}

	for _, part in ipairs(getPartsInRadius(center, radius)) do
		local ancestor = part.Parent

		if ancestor then
			-- Se busca el Humanoid subiendo, no solo en el padre
			-- inmediato: con tecnicas de/accessories el limbs cuelgan
			-- de subcarpetas y `FindFirstChildOfClass` fallaba.
			local humanoid = ancestor:FindFirstChildOfClass("Humanoid")

			if humanoid == nil then
				local character = ancestor:FindFirstAncestorOfClass("Model")
				humanoid = character and character:FindFirstChildOfClass("Humanoid")
			end

			if humanoid and not damagedHumanoids[humanoid] then
				damagedHumanoids[humanoid] = true

				local character = humanoid.Parent
				local rootPart = character and character:FindFirstChild("HumanoidRootPart")
				local distance = if rootPart then (rootPart.Position - center).Magnitude else 0

				-- Oclusion: un muro reduce el dano, no lo anula. Sin
				-- esto, detras de un bloque el dano seria IDENTICO.
				local sight = hasLineOfSight(center, rootPart or part)
				local damage = CombatMath.ApplyOcclusion(
					sight,
					CombatMath.FalloffDamage(distance, radius, GameConfig.DefaultBombDamage)
				)

				if damage > 0 then
					-- PRIMERO se pregunta si es un MONSTRUO. Sin esta
					-- rama, un monstruo dentro del radio no recibia dano:
					-- `CombatService.ApplyDamage` busca un Player a partir del
					-- Humanoid, y un NPC no tiene ninguno, asi que devolvia
					-- `false` y la bomba pasaba de largo. El PvE era
					-- invisible en el propio sistema que lo debia ocultar.
					if Service._monsters and Service._monsters.ApplyDamageToMonster(
						humanoid,
						damage,
						sourceUserId
					) then
						affected += 1
					elseif Service._combat then
						local applied = Service._combat.ApplyDamage(humanoid, damage, sourceUserId)

						if applied then
							affected += 1
							Logger.Debug(("explosion: %.0f de dano a %s"):format(
								damage,
								humanoid.Name
							))
						end
					end
				end
			end
		end

		-- Los bloques reciben una FRACCION del dano: con el 100% una
		-- sola bomba borraba la estructura entera.
		if Service._destruction then
			local blockDamage = CombatMath.BlockDamageFromExplosion(
				GameConfig.DefaultBombDamage * GameConfig.BlockDamageScale,
				1
			)

			if Service._destruction.ApplyDamage(part, blockDamage) then
				affected += 1

				-- Un bloque recien DESTRUIDO (no danado) avanza la metrica.
				--
				-- Aqui, y no en `DestructionService`, porque este es el
				-- UNICO sitio donde existe el dato de QUIEN lo rompio:
				-- `ApplyDamage` no recibe propietario y anadirselo obligaria
				-- a cambiar su firma y a todos sus llamantes.
				--
				-- El evento va DESPUES de aplicar el dano: si `RecordMetric`
				-- fallara, el bloque ya esta roto y la ronda continua. Al
				-- reves, una mision que no avanza seria un fallo mucho mas
				-- dificil de ver que uno que se registro de mas.
				if Service._questService ~= nil and sourceUserId ~= nil then
					local player = Players:GetPlayerByUserId(sourceUserId)

					if player then
						Service._questService.RecordMetric(player, "BlockDestroyed", 1)
					end
				end
			end
		end
	end

	Logger.Debug(("explosion resuelta: %d afectadas (radio %.1f)"):format(affected, radius))

	return affected
end

--- Crea la carpeta de efectos visuales. Se hace UNA vez: crear una
--- carpeta por explosion llenaria el Workspace.
local function ensureVfxFolder()
	if Service._vfxFolder and Service._vfxFolder.Parent then
		return
	end

	Service._vfxFolder = Instance.new("Folder")
	Service._vfxFolder.Name = "ExplosionVfx"
	Service._vfxFolder:SetAttribute("IsVfxFolder", true)
	Service._vfxFolder.Parent = Workspace
end

--- Crea el folder al arrancar. Idempotente.
--- @param maid any?
--- @return boolean success
function Service.Init(maid: any?): boolean
	if Service.IsInitialized then
		return true
	end

	Service._explosionCount = 0
	Service._blockedExplosions = 0
	Service._activeVFX = 0

	ensureVfxFolder()

	Service.IsInitialized = true
	return true
end

--- @return boolean success
function Service.Start(): boolean
	if not Service.IsInitialized then
		Logger.Error("ExplosionService: Start sin Init")
		return false
	end

	if not Service._destruction then
		Logger.Warn("ExplosionService: sin DestructionService; los bloques no se destruiran.")
	end

	if not Service._combat then
		-- Esto SI es un fallo real: sin CombatService la explosion no
		-- puede aplicar dano a nadie. Se avisa con la misma fuerza que
		-- un error para que no pase inadvertido en el output.
		Logger.Error("ExplosionService: sin CombatService; las explosiones no haranno dano.")
		return false
	end

	Logger.Info("ExplosionService listo.")
	return true
end

--- @return boolean success
function Service.Destroy(): boolean
	Service.IsInitialized = false
	Service._destruction = nil
	Service._combat = nil
	Service._explosionCount = 0
	Service._blockedExplosions = 0
	Service._activeVFX = 0

	if Service._vfxFolder then
		Service._vfxFolder:Destroy()
		Service._vfxFolder = nil
	end

	return true
end

return Service

