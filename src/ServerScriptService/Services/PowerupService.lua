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

local VisualKit = require(SHARED:WaitForChild("Libraries"):WaitForChild("VisualKit"))
local Logger = require(UTILS:WaitForChild("Logger"))

local Service = {}

Service.IsInitialized = false

Service._folder = nil
Service._maid = nil
Service._worldService = nil
Service._playerService = nil
Service._spawned = 0
Service._collected = 0

--- Duracion de los efectos temporales, en segundos.
Service.EffectDuration = 12
Service.HealAmount = 35
Service.SpeedMultiplier = 1.6
Service.ShieldReduction = 0.5

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
function Service.SetDependencies(worldService: any, playerService: any?)
	Service._worldService = worldService
	Service._playerService = playerService
end

--- Tipos de powerup, en el orden en que se reparten los puntos de spawn.
local KINDS = { "Bomb", "Speed", "Shield", "Heal" }

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
		-- Bomba extra: el contador del HUD sube y el jugador puede colocar
		-- otra vez de inmediato. Sin esto el powerup seria un adorno.
		local current = player:GetAttribute("Bombs")
		local base = if type(current) == "number" then current else 0
		player:SetAttribute("Bombs", base + 1)
		return
	end

	if kind == "Fire" then
		player:SetAttribute("PowerupFireUntil", untilTime)

		task.delay(Service.EffectDuration, function()
			if player.Parent then
				player:SetAttribute("PowerupFireUntil", nil)
			end
		end)
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