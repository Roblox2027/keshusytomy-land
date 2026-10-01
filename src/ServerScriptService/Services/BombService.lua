--!strict
--[[
	BombService
	Autoridad de creacion, colocacion, cuenta regresiva y explosion de
	bombas.

	El cliente NUNCA coloca una bomba por su cuenta: pide una posicion y
	este servicio valida en el servidor:

		1. Que la ronda este en curso.
		2. Que el jugador este vivo y tenga personaje.
		3. Que la posicion este dentro del rango permitido.
		4. Que el jugador no este en cooldown.

	El radio, el dano y la mecha salen SIEMPRE de GameConfig. Un cliente
	que manipule su payload no puede cambiar ninguno de los tres.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONFIG = SHARED:WaitForChild("Config")
local UTILS = SHARED:WaitForChild("Utils")

local GameConfig = require(CONFIG:WaitForChild("GameConfig"))
local Logger = require(UTILS:WaitForChild("Logger"))

local Service = {}

Service.IsInitialized = false

-- Servicios inyectados por ServerMain para evitar dependencias circulares.
Service._roundService = nil
Service._explosionService = nil

-- UserId -> momento (os.clock) en que puede volver a colocar.
Service._cooldowns = {}
-- Bombas activas: id -> parte.
Service._activeBombs = {}
Service._nextBombId = 0
-- Carpeta donde se crean las bombas visibles.
Service._bombFolder = nil

local function isFiniteVector3(value: any): boolean
	return typeof(value) == "Vector3"
		and value.X == value.X
		and value.Y == value.Y
		and value.Z == value.Z
end

--- Inyecta las dependencias del servicio.
--- @param roundService any
--- @param explosionService any
function Service.SetDependencies(roundService: any, explosionService: any)
	Service._roundService = roundService
	Service._explosionService = explosionService
end
--- Crea la bomba fisica y programa su cuenta regresiva en el servidor.
--- @param ownerId number?
--- @param position Vector3
local function spawnBomb(ownerId: number?, position: Vector3)
	local bomb = Instance.new("Part")
	bomb.Name = "Bomb"
	bomb.Shape = Enum.PartType.Ball
	bomb.Size = Vector3.new(2, 2, 2)
	bomb.Position = position
	bomb.Anchored = true
	bomb.CanCollide = false
	bomb.Material = Enum.Material.Neon
	bomb.Color = Color3.fromRGB(220, 60, 60)

	Service._nextBombId += 1
	local bombId = Service._nextBombId
	bomb:SetAttribute("BombId", bombId)

	Service._bombFolder:AddChild(bomb)
	Service._activeBombs[bombId] = bomb

	Logger.Debug(("bomba %d colocada en (%.0f, %.0f, %.0f)"):format(
		bombId,
		position.X,
		position.Y,
		position.Z
	))

	-- La cuenta regresiva la lleva el SERVIDOR. El cliente solo ve la
	-- bomba porque la creamos aqui, no porque el la haya creado.
	task.delay(GameConfig.DefaultBombFuseTime, function()
		local current = Service._activeBombs[bombId]
		if not current then
			return
		end

		Service._activeBombs[bombId] = nil
		local detonationPosition = current.Position
		current:Destroy()

		if Service._explosionService then
			Service._explosionService.Detonate(detonationPosition, GameConfig.DefaultBombRadius)
		end
	end)
end

--- Valida y coloca una bomba solicitada por un jugador.
--- @param player Player
--- @param position any posicion pedida por el cliente
--- @return boolean placed
--- @return string? reason motivo del rechazo
function Service.TryPlaceBomb(player: Player, position: any): (boolean, string?)
	if not Service.IsInitialized then
		return false, "servicio no inicializado"
	end

	-- 1. La ronda debe estar en curso. Colocar bombas en el lobby
	--    permitiria destruir el mapa antes de empezar.
	if Service._roundService and not Service._roundService.IsPlaying() then
		return false, "no hay ronda en curso"
	end

	-- 2. El jugador debe estar vivo y tener personaje.
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")

	if not humanoid or humanoid.Health <= 0 or not rootPart then
		return false, "personaje no jugable"
	end

	-- 3. La posicion debe ser un Vector3 finito. El gateway ya valida el
	--    tipo, pero el servicio no confía en una sola comprobacion.
	if not isFiniteVector3(position) then
		return false, "posicion invalida"
	end

	-- 4. Distancia al personaje. Sin esto, un cliente colocaria bombas
	--    a distancia sin moverse.
	local distance = (rootPart.Position - position).Magnitude
	if distance > GameConfig.BombPlacementRange then
		return false, ("fuera de rango (%.0f studs)"):format(distance)
	end

	-- 5. Cooldown por jugador. Se consume ANTES de colocar, para que un
	--    rechazo posterior no devuelva el tiempo al cliente.
	local now = os.clock()
	if now < (Service._cooldowns[player.UserId] or 0) then
		return false, "en cooldown"
	end
	Service._cooldowns[player.UserId] = now + GameConfig.BombCooldown

	if not Service._explosionService then
		Logger.Error("BombService: ExplosionService no inyectado")
		return false, "sin servicio de explosiones"
	end

	spawnBomb(player.UserId, position)

	return true, nil
end

--- Destruye todas las bombas activas (fin de ronda).
--- @return number removed
function Service.ClearBombs(): number
	local removed = 0

	for bombId, bomb in pairs(Service._activeBombs) do
		if bomb and bomb.Parent then
			bomb:Destroy()
			removed += 1
		end
		Service._activeBombs[bombId] = nil
	end

	return removed
end

--- Numero de bombas activas.
--- @return number
function Service.GetActiveBombCount(): number
	local count = 0
	for _ in pairs(Service._activeBombs) do
		count += 1
	end
	return count
end

--- Inicializacion del servicio. Idempotente.
--- @param maid any?
--- @return boolean success
function Service.Init(maid: any?): boolean
	if Service.IsInitialized then
		return true
	end

	Service._cooldowns = {}
	Service._activeBombs = {}
	Service._nextBombId = 0

	-- Las bombas se crean en una carpeta propia. El cliente puede verla
	-- (tiene que verlas para que la cuenta regresiva sea visible) pero
	-- nunca es una fuente de confianza.
	Service._bombFolder = Instance.new("Folder")
	Service._bombFolder.Name = "Bombs"
	Service._bombFolder:SetAttribute("IsBombFolder", true)
	Service._bombFolder.Parent = Workspace

	Service.IsInitialized = true
	Logger.Info("BombService listo.")

	return true
end

--- @return boolean success
function Service.Start(): boolean
	if not Service.IsInitialized then
		Logger.Error("BombService: Start sin Init")
		return false
	end

	if not Service._explosionService then
		Logger.Warn("BombService: sin ExplosionService; las bombas no explotaran.")
	end

	return true
end

--- Limpieza: destruye las bombas vivas y suelta las dependencias.
--- @return boolean success
function Service.Destroy(): boolean
	Service.ClearBombs()

	if Service._bombFolder then
		Service._bombFolder:Destroy()
		Service._bombFolder = nil
	end

	Service._cooldowns = {}
	Service._roundService = nil
	Service._explosionService = nil
	Service.IsInitialized = false

	return true
end

return Service
