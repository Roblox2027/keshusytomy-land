--!strict
--[[
	PowerupService
	Powerups flotantes de la arena: los ve, se recogen y hacen algo.

	POR QUE EXISTE
	--------------
	El mapa declaraba `PowerupSpawns` (cuatro marcadores por mundo) pero NADA
	los llenaba: eran cuatro placas de color en el suelo. El jugador no tenia
	que recoger nada porque no habia nada que recoger. Eso no es "una funcion de
	powerups pendiente": es contenido ausente, y el jugador lo lee como "este
	juego no tiene nada que hacer aqui".

	LA REGLA
	--------
	El servidor es la autoridad. El powerup se genera aqui, se recoge aqui y el
	efecto se aplica aqui. El cliente solo ve el modelo (que replica) y el HUD
	muestra el atributo que este servicio publica.

	EFECTOS (todos reales, ninguno decorativo)
	------------------------------------------
	  Heal   -> cura vida al personaje, ahora.
	  Speed  -> sube `WalkSpeed` durante unos segundos.
	  Shield -> reduce el dano recibido a la mitad mientras dure.
	  Bomb   -> anula el cooldown de bomba del jugador (colocar seguido).
	  Fire   -> sube el dano de sus bombas mientras dure.

	Los tres ultimos se publican como ATRIBUTOS del jugador, no como estado
	oculto: asi el HUD puede mostrarlos y el jugador ve que su efecto existe.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local UTILS = SHARED:WaitForChild("Utils")
local CONFIG = SHARED:WaitForChild("Config")

local GameConfig = require(CONFIG:WaitForChild("GameConfig"))
local VisualKit = require(SHARED:WaitForChild("Libraries"):WaitForChild("VisualKit"))
local Logger = require(UTILS:WaitForChild("Logger"))

local Service = {}

Service.IsInitialized = false

Service._folder = nil
Service._maid = nil
Service._worldService = nil
Service._playerService = nil
-- `BombService` es OPCIONAL a proposito: sin el, el powerup "+BOMBA" sigue
-- concediendo capacidad por el atributo, pero sin bonificacion persistente
-- en el servicio. Depender de el en la inicializacion haria que un fallo de
-- arranque de bombas dejara sin powerups a todo el mundo.
Service._bombService = nil
-- `MonsterService` es lo que permite que CONGELAR haga algo: sin el, el
-- powerup Freeze se recoge, se publica el atributo y no congela a nadie. Es
-- OPCIONAL por el mismo motivo que `BombService`: que falte un servicio no
-- puede romper la recogida de los demas powerups.
Service._monsterService = nil
Service._spawned = 0
Service._collected = 0

--- Duracion de los efectos temporales, en segundos.
Service.EffectDuration = 12
Service.HealAmount = 35
Service.SpeedMultiplier = 1.6
Service.ShieldReduction = 0.5

-- =========================================================================
-- AJUSTES DE LOS POWERUPS NUEVOS
--
-- Cada uno tiene su propia duracion y SU PROPIA magnitud. Compartir el
-- `EffectDuration` de 12 s hacia que "impulso", "congelar" y "+poder" fueran
-- lo mismo con distinto color: tres objetos con el mismo reloj y el jugador
-- no puede decidir cual recoger.
-- =========================================================================

-- DASH: corto y fuerte. Es una huida, no un estado.
Service.DashDuration = 2.5
Service.DashMultiplier = 2.4

-- GHOST: presentacional. 0.85 deja ver la silueta (si no, el jugador cree
-- que le han borrado el personaje) pero no se puede apuntar bien.
Service.GhostTransparency = 0.85

-- MAGNET: radio amplio y arrastre suave. 46 studs es "cruzando esta zona me
-- llega todo", no "tengo que recogerlos uno a uno".
Service.MagnetRadius = 46
Service.MagnetPullSpeed = 18

-- FREEZE: 5 s. Suficiente para cruzar una emboscada, insuficiente para
-- vaciar un mundo de enemigos.
Service.FreezeDuration = 5
Service.FreezeRadius = 55

--- Carpeta unica donde viven los powerups.
--- @return Folder?
function Service.GetFolder(): Folder?
	if Service._folder and Service._folder.Parent then
		return Service._folder
	end

	local folder = Instance.new("Folder")
	folder.Name = "Powerups"
	folder:SetAttribute("IsPowerupFolder", true)
	folder.Parent = Workspace

	Service._folder = folder
	return folder
end

--- @param worldService any
--- @param playerService any?
--- @param bombService any? `BombService`, para el powerup "+BOMBA"
function Service.SetDependencies(worldService: any, playerService: any?, bombService: any?)
	Service._worldService = worldService
	Service._playerService = playerService
	Service._bombService = bombService
end

--- Conecta `MonsterService` (para el powerup CONGELAR).
---
--- Es un setter aparte y no un cuarto argumento de `SetDependencies` porque se
--- cablea en un momento distinto: `MonsterService` se registra antes que
--- `PowerupService` en el orden de arranque, pero el cableado de dependencias
--- lo hace `ServerMain`, y ahi ya estan todos.
--- @param monsterService any?
function Service.SetMonsterService(monsterService: any?)
	Service._monsterService = monsterService
end

-- =========================================================================
-- Tipos de powerup, en el orden en que se reparten los puntos de spawn.
--
-- MEDIDO EN AUDITORIA (ARREGLO): la lista era `{ Bomb, Speed, Shield, Heal }`
-- y eso era TODO lo que el mundo generaba. Pero `VisualKit.POWERUPS` tenia
-- cinco entradas y `ApplyEffect` tenia un caso `Fire` completo: es decir,
-- "+PODER" estaba implementado, pintado y anunciado, y nunca aparecia. El
-- jugador veia el cartel de la capacidad de bomba extra, que si existia, y
-- jamas el poder de dano.
--
-- Ahora la lista es la de la especificacion (ocho) y `KINDS` es la UNICA
-- fuente: `VisualKit` se limita a PINTAR lo que esta tabla declara. Anadir un
-- powerup es una linea en `KINDS` y una en `VisualKit.POWERUPS`, y
-- `Gameplay.spec` falla si las dos se desincronizan.
-- =========================================================================
local KINDS = {
	"Bomb", "Speed", "Shield", "Heal",
	"Fire", "Dash", "Ghost", "Magnet", "Freeze",
}

--- Puntos de spawn de powerup declarados en el mapa de un mundo.
--- @param worldId string
--- @return { BasePart }
function Service.CollectSpawnPoints(worldId: string): { BasePart }
	local points: { BasePart } = {}
	local worlds = Workspace:FindFirstChild("Worlds")
	local worldFolder = worlds and worlds:FindFirstChild(worldId)
	local spawns = worldFolder and worldFolder:FindFirstChild("PowerupSpawns")

	if not spawns then
		return points
	end

	for _, child in ipairs(spawns:GetChildren()) do
		if child:IsA("BasePart") then
			table.insert(points, child :: BasePart)
		end
	end

	table.sort(points, function(a, b)
		return a.Name < b.Name
	end)

	return points
end
--- Aplica el efecto de un powerup a un jugador.
---
--- Cada efecto publica su propio atributo con el instante final. El HUD los
--- lee; ademas son la unica forma de que la PRESENTACION sepa que "ESCUDO"
--- esta activo sin preguntar a este servicio cada frame.
--- @param player Player
--- @param kind string
function Service.ApplyEffect(player: Player, kind: string)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local untilTime = os.clock() + Service.EffectDuration

	if kind == "Heal" then
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + Service.HealAmount)
		end
		return
	end

	if kind == "Speed" then
		local base = if humanoid then humanoid.WalkSpeed else 16

		if humanoid then
			humanoid.WalkSpeed = base * Service.SpeedMultiplier
		end

		player:SetAttribute("PowerupSpeedUntil", untilTime)

		task.delay(Service.EffectDuration, function()
			if player.Parent and humanoid and humanoid.Parent then
				humanoid.WalkSpeed = base
			end
		end)
		return
	end

	if kind == "Shield" then
		player:SetAttribute("PowerupShieldUntil", untilTime)

		task.delay(Service.EffectDuration, function()
			if player.Parent then
				player:SetAttribute("PowerupShieldUntil", nil)
			end
		end)
		return
	end

	if kind == "Bomb" then
		-- BOMBA EXTRA = MAS ESPACIO, no mas existencias.
		--
		-- MEDIDO: antes este powerup hacia `Bombs + 1` sobre el atributo del
		-- HUD. Ese atributo lo escribe `BombService.publishBombCount` con las
		-- bombas VIVAS, asi que el incremento se pisaba en cuanto el jugador
		-- colocaba o detonaba una bomba: el powerup no concedia nada
		-- permanente y solo se notaba durante un instante.
		--
		-- Ahora concede capacidad real y la escribe en `BombCapacity`, que el
		-- servidor aplica al validar. Si `BombService` no esta inyectado se
		-- recurre al atributo: el powerup nunca debe romper el juego por
		-- depender de otro servicio.
		local nueva = if Service._bombService and Service._bombService.AddCapacityBonus
			then Service._bombService.AddCapacityBonus(player.UserId, 1)
			else (player:GetAttribute("BombCapacity") or GameConfig.BombCapacity) + 1

		player:SetAttribute("BombCapacity", nueva)
		return
	end

	if kind == "Fire" then
		player:SetAttribute("PowerupFireUntil", untilTime)

		task.delay(Service.EffectDuration, function()
			if player.Parent then
				player:SetAttribute("PowerupFireUntil", nil)
			end
		end)
		return
	end

	-- DASH: un impulso de velocidad CORTO y potente.
	--
	-- No es "+velocidad" (ese es `Speed`): `Speed` dura 12 s a 1.6 y sirve
	-- para recorrer el mapa; `Dash` dura 2 s a 2.4 y sirve para SALIR de un
	-- golpe. Mezclarlos hacia que un jugador con `Speed` no notase la
	-- diferencia, y el efecto se leeria como decorativo.
	if kind == "Dash" then
		local base = if humanoid then humanoid.WalkSpeed else GameConfig.DefaultPlayerSpeed

		if humanoid then
			humanoid.WalkSpeed = base * Service.DashMultiplier
		end

		player:SetAttribute("PowerupDashUntil", untilTime)

		task.wait(Service.DashDuration)

		if player.Parent and humanoid and humanoid.Parent and humanoid.Health > 0 then
			humanoid.WalkSpeed = base
			player:SetAttribute("PowerupDashUntil", nil)
		end

		return
	end

	-- GHOST: transparencia y, sobre todo, invisibilidad PRACTICA.
	--
	-- El efecto es de PRESENTACION y no de colision: el jugador sigue
	-- teniendo su hitbox y sus bombas siguen impactando. Es una decision
	-- deliberada: un powerup que hace al jugador intangible permitiria
	-- atravesar el mapa sin castigo y romperia las colisiones que el juego
	-- usa para el combate.
	if kind == "Ghost" then
		local character = player.Character

		if character then
			for _, descendant in ipairs(character:GetDescendants()) do
				if descendant:IsA("BasePart") then
					descendant.Transparency = math.max(descendant.Transparency, Service.GhostTransparency)
					descendant:SetAttribute("Ghosted", true)
				end
			end
		end

		player:SetAttribute("PowerupGhostUntil", untilTime)

		task.delay(Service.EffectDuration, function()
			if not player.Parent then
				return
			end

			player:SetAttribute("PowerupGhostUntil", nil)

			local current = player.Character

			if not current then
				return
			end

			-- Se RESTAURA la transparencia, no se pone a 0: un personaje con
			-- una parte ya transparente por otro motivo (un escudo, un
			-- fantasma previo) volveria opaco.
			for _, descendant in ipairs(current:GetDescendants()) do
				if descendant:IsA("BasePart") and descendant:GetAttribute("Ghosted") then
					descendant.Transparency = 0
					descendant:SetAttribute("Ghosted", nil)
				end
			end
		end)

		return
	end

	-- MAGNET: atrae los powerups cercanos.
	--
	-- No atrae monedas ni XP porque no existen como objetos recogibles: lo
	-- que SI hay en el suelo son powerups, y exigir al jugador que los
	-- esquive uno a uno mientras le persiguen no es una decision, es ruido.
	-- El radio es generoso a proposito: el valor esta en "caminando hacia el
	-- loot, todo llega a mi".
	if kind == "Magnet" then
		player:SetAttribute("PowerupMagnetUntil", untilTime)

		task.spawn(function()
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")

			if not root then
				return
			end

			while player.Parent and player:GetAttribute("PowerupMagnetUntil") do
				for _, powerup in ipairs(Service._folder:GetChildren()) do
					local core = powerup:FindFirstChild("Core")

					if core and core:IsA("BasePart") and powerup:IsA("Model") then
						local delta = root.Position - core.Position

						if delta.Magnitude <= Service.MagnetRadius then
							-- Se atrae, no se teletransporta: el recorrido
							-- visible es lo que comunica que el iman funciona.
							core.CFrame = core.CFrame + delta.Unit * math.min(delta.Magnitude, Service.MagnetPullSpeed * 0.1)
						end
					end
				end

				task.wait(0.1)
			end
		end)

		return
	end

	-- FREEZE: congela a los enemigos cercanos durante un instante.
	--
	-- No los mata ni los borra: los paraliza lo justo para que el jugador
	-- cruce una zona con cuatro Guardian encima. Es el powerup de
	-- POSICION, y por eso dura poco: un congelado de 12 s seria un segundo
	-- `Speed` disfrazado.
	if kind == "Freeze" then
		player:SetAttribute("PowerupFreezeUntil", untilTime)

		local frozen: { Model } = {}
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")

		if root and Service._monsterService and Service._monsterService.GetFolder then
			local folder = Service._monsterService.GetFolder()

			if folder then
				for _, monster in ipairs(folder:GetChildren()) do
					local monsterRoot = monster.PrimaryPart

					if monsterRoot and (monsterRoot.Position - root.Position).Magnitude <= Service.FreezeRadius then
						local monsterHumanoid = monster:FindFirstChildOfClass("Humanoid")

						if monsterHumanoid then
							-- Se guarda la velocidad ORIGINAL: poner a 0 y
							-- restaurar a la de `PatrolSpeed` dejaba bichos
							-- con el valor de la definicion, que no es el
							-- que tenian, y se notaba al descongelar.
							monsterHumanoid:SetAttribute("FrozenSpeed", monsterHumanoid.WalkSpeed)
							monsterHumanoid.WalkSpeed = 0
							monsterHumanoid:SetAttribute("IsFrozen", true)
							table.insert(frozen, monster)
						end
					end
				end
			end
		end

		task.delay(Service.FreezeDuration, function()
			for _, monster in ipairs(frozen) do
				if monster.Parent then
					local monsterHumanoid = monster:FindFirstChildOfClass("Humanoid")

					if monsterHumanoid then
						monsterHumanoid.WalkSpeed = monsterHumanoid:GetAttribute("FrozenSpeed") or GameConfig.DefaultPlayerSpeed
						monsterHumanoid:SetAttribute("IsFrozen", nil)
						monsterHumanoid:SetAttribute("FrozenSpeed", nil)
					end
				end
			end
		end)

		return
	end
end

--- El jugador ha TOCADO un powerup.
--- @param model Model
--- @param hit BasePart
local function onTouched(model: Model, hit: BasePart)
	local player = Players:GetPlayerFromCharacter(hit.Parent)

	if not player then
		return
	end

	if not model.Parent then
		return
	end

	local kind = model:GetAttribute("PowerupKind")
	local spec = if type(kind) == "string" then VisualKit.POWERUPS[kind] else nil

	if type(kind) ~= "string" or not spec then
		model:Destroy()
		return
	end

	-- Se destruye ANTES de aplicar el efecto: si el jugador roza el powerup
	-- dos veces en el mismo frame, solo cobra una vez.
	model:Destroy()
	Service._collected += 1

	Service.ApplyEffect(player, kind)
	Logger.Debug(("%s recogio %s"):format(player.Name, kind))
end

--- Crea un powerup en un punto.
--- @param kind string
--- @param position Vector3
--- @return Model?
function Service.Spawn(kind: string, position: Vector3): Model?
	local folder = Service.GetFolder()

	if not folder then
		return nil
	end

	local model = VisualKit.BuildPowerup(kind, position)

	if not model then
		return nil
	end

	local core = model:FindFirstChild("Core")

	if not core or not core:IsA("BasePart") then
		model:Destroy()
		return nil
	end

	model.Parent = folder
	core.Touched:Connect(function(hit: BasePart)
		onTouched(model, hit)
	end)

	Service._spawned += 1

	-- Flotacion: sube, baja y gira despacio. Un powerup estatico es una
	-- decoracion; uno que flota es un objeto al que uno se acerca.
	task.spawn(function()
		local base = position
		local elapsed = 0

		while model.Parent do
			elapsed += 0.05

			if not model.PrimaryPart then
				return
			end

			local offset = math.sin(elapsed * 2) * 0.6
			model:PivotTo(CFrame.new(base + Vector3.new(0, offset, 0)) * CFrame.Angles(0, elapsed, 0))

			task.wait(0.05)
		end
	end)

	return model
end

--- Genera los powerups de la ronda en el mundo indicado.
--- @param worldId string?
--- @return number spawned
function Service.SpawnForRound(worldId: string?): number
	local world = worldId
		or (Service._worldService and Service._worldService.GetDefaultWorldId())

	if not world then
		return 0
	end

	local points = Service.CollectSpawnPoints(world)
	local spawned = 0

	for index, point in ipairs(points) do
		local kind = KINDS[((index - 1) % #KINDS) + 1]

		if Service.Spawn(kind, point.Position + Vector3.new(0, 1.5, 0)) then
			spawned += 1
		end
	end

	if spawned > 0 then
		Logger.Info(("%d powerup(s) generados en %s"):format(spawned, world))
	end

	return spawned
end

--- Borra todos los powerups vivos (fin de ronda).
--- @return number removed
function Service.ClearAll(): number
	local removed = 0

	if not Service._folder then
		return 0
	end

	for _, child in ipairs(Service._folder:GetChildren()) do
		child:Destroy()
		removed += 1
	end

	return removed
end

--- @param maid any?
--- @return boolean success
function Service.Init(maid: any?): boolean
	if Service.IsInitialized then
		return true
	end

	Service._maid = maid
	Service._spawned = 0
	Service._collected = 0

	if not Service.GetFolder() then
		Logger.Error("PowerupService: no se pudo crear la carpeta de powerups.")
		return false
	end

	Service.IsInitialized = true
	Logger.Info("PowerupService listo.")
	return true
end

--- @return boolean success
function Service.Start(): boolean
	if not Service.IsInitialized then
		Logger.Error("PowerupService: Start sin Init")
		return false
	end

	Logger.Info("PowerupService arrancado.")
	return true
end

--- @return boolean success
function Service.Destroy(): boolean
	Service.ClearAll()

	if Service._folder and Service._folder.Parent then
		Service._folder:Destroy()
	end

	Service._folder = nil
	Service._worldService = nil
	Service._playerService = nil
	Service._maid = nil
	Service.IsInitialized = false
	return true
end

return Service