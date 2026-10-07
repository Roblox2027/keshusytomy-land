--!strict
--[[
	HazardService
	MECANICA CARACTERISTICA DE CADA MUNDO (MASTER MISSION V2 - FASE 3).

	QUE HACE Y QUE DELEGA
	---------------------
	NO calcula nada: el catalogo, las fases del laser, los cooldowns y el
	dano de cada paso son de `HazardRules` (puro, probado). Este servicio
	aporta lo que el motor: las zonas visibles, el hilo de medio segundo y
	la lectura de posiciones de los jugadores.

	COMO SE CONSTRUYE UNA ZONA
	--------------------------
	Las zonas son esferas semitransparentes construidas POR CODIGO en el
	centro de las primeras `MaxZonesPerWorld` zonas del mundo (mismo
	contrato de generador que `MiniBossService`: la losa `_Core`). Por
	codigo y no desde el mapa, por la misma razon que los monstruos: un
	peligro que depende de que alguien coloque una parte en Studio es un
	peligro que desaparece sin error cuando alguien edita el lugar.

	LA REGLA DE AUTORIDAD
	---------------------
	Todo el dano pasa por `CombatService.ApplyDamage`: invulnerabilidad,
	ronda en curso y muerte subita se respetan solas. La arena movediza y
	la racha tocan MOVIMIENTO, no vida: la arena pisa WalkSpeed y la
	devuelve a `HazardRules.DefaultWalkSpeed` al salir (nunca "lo que
	tuviera antes", porque los powerups de velocidad tambien lo tocan).

	RENDIMIENTO
	-----------
	Un paso cada 0.5 s, como mucho 5 mundos x 4 zonas x jugadores: la
	comprobacion es una distancia al cuadrado. No hay Heartbeat.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local UTILS = SHARED:WaitForChild("Utils")

local HazardRules = require(SHARED:WaitForChild("Libraries"):WaitForChild("HazardRules"))
local Logger = require(UTILS:WaitForChild("Logger"))

local Service = {}

Service.IsInitialized = false

-- Servicios inyectados por `ServerMain`.
Service._combatService = nil
Service._monsterService = nil

-- Zonas construidas: { { WorldId, Hazard, Position, Radius, Part, LastAmbushAt } }.
Service._zones = {}

-- Jugadores dentro de una zona de arena movediza AHORA (userId -> true).
-- El rastreo es de ENTRADA/SALIDA: pisar la velocidad cada paso pisaria
-- tambien los powerups de velocidad.
Service._slowed = {}

-- Jugadores dentro de una zona de emboscada AHORA (userId..zoneIndex).
-- La emboscada dispara en la TRANSICION de entrada, no por estar dentro:
-- quedarse quieto en el claro no puede generar enemigos infinitos.
Service._inside = {}

-- Cache de centros de zona por mundo (contrato `Zone_*_Core`).
Service._zoneCache = {}

Service._folder = nil
Service._thread = nil
Service._running = false

-- ---------------------------------------------------------------------------
-- INYECCION
-- ---------------------------------------------------------------------------

--- @param combatService any?
--- @param monsterService any?
function Service.SetDependencies(combatService: any?, monsterService: any?)
	Service._combatService = combatService
	Service._monsterService = monsterService
end

-- ---------------------------------------------------------------------------
-- CONSTRUCCION DE ZONAS
-- ---------------------------------------------------------------------------

--- Centros de zona de un mundo, ordenados por nombre para que la
--- seleccion sea DETERMINISTA: las mismas cuatro zonas son peligrosas
--- en cada servidor, y eso se puede comprobar en un playtest.
--- @param worldId string
--- @return { Vector3 }
local function zoneCenters(worldId: string): { Vector3 }
	local cache = Service._zoneCache[worldId]

	if cache then
		return cache
	end

	cache = {}
	Service._zoneCache[worldId] = cache

	local worlds = Workspace:FindFirstChild("Worlds")
	local worldFolder = worlds and worlds:FindFirstChild(worldId)
	local zones = worldFolder and worldFolder:FindFirstChild("Zones")

	if zones and zones:IsA("Folder") then
		local entries = {}

		for _, child in ipairs(zones:GetChildren()) do
			if child:IsA("Folder") and string.sub(child.Name, 1, 5) == "Zone_" then
				local core = child:FindFirstChild(child.Name .. "_Core")

				if core and core:IsA("BasePart") then
					table.insert(entries, { Name = child.Name, Position = core.Position })
				end
			end
		end

		table.sort(entries, function(a, b)
			return a.Name < b.Name
		end)

		for _, entry in ipairs(entries) do
			table.insert(cache, entry.Position)
		end
	end

	return cache
end

--- Color caracteristico del peligro. La zona tiene que VERSE: un
--- peligro invisible es una trampa injusta, no una mecanica.
--- @param kind string
--- @return Color3
local function kindColor(kind: string): Color3
	if kind == HazardRules.Kind.Quicksand then
		return Color3.fromRGB(214, 181, 110)
	end
	if kind == HazardRules.Kind.Gust then
		return Color3.fromRGB(170, 220, 255)
	end
	if kind == HazardRules.Kind.Lava then
		return Color3.fromRGB(255, 96, 40)
	end
	if kind == HazardRules.Kind.Laser then
		return Color3.fromRGB(255, 70, 90)
	end
	return Color3.fromRGB(120, 200, 120)
end

--- Construye las zonas de peligro de un mundo. Idempotente por mundo.
--- @param worldId string
--- @return number construidas
function Service.BuildWorld(worldId: string): number
	local hazard = HazardRules.ForWorld(worldId)

	if not hazard then
		return 0
	end

	for _, zone in ipairs(Service._zones) do
		if zone.WorldId == worldId then
			return 0
		end
	end

	if not Service._folder then
		local folder = Instance.new("Folder")
		folder.Name = "Hazards"
		folder.Parent = Workspace
		Service._folder = folder
	end

	local built = 0
	local centers = zoneCenters(worldId)

	for index = 1, math.min(HazardRules.MaxZonesPerWorld, #centers) do
		local part = Instance.new("Part")
		part.Name = ("Hazard_%s_%d"):format(worldId, index)
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(hazard.Radius * 2, hazard.Radius * 2, hazard.Radius * 2)
		part.Position = centers[index]
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Transparency = 0.75
		part.Color = kindColor(hazard.Kind)
		part.Material = Enum.Material.Neon
		part:SetAttribute("HazardWorld", worldId)
		part:SetAttribute("HazardKind", hazard.Kind)
		part.Parent = Service._folder

		table.insert(Service._zones, {
			WorldId = worldId,
			Hazard = hazard,
			Position = centers[index],
			Radius = hazard.Radius,
			Part = part,
			LastAmbushAt = nil,
		})

		built += 1
	end

	if built > 0 then
		Logger.Info(("HazardService: %d zonas de '%s' en %s"):format(built, hazard.Kind, worldId))
	end

	return built
end

-- ---------------------------------------------------------------------------
-- EFECTOS
-- ---------------------------------------------------------------------------

--- Jugador dentro de la zona (distancia al cuadrado: sin raiz).
--- @param root BasePart
--- @param zone any
--- @return boolean
local function isInside(root: BasePart, zone: any): boolean
	local delta = root.Position - zone.Position
	return delta:Dot(delta) <= zone.Radius * zone.Radius
end

--- Aplica el efecto de la zona a un jugador dentro.
--- @param player Player
--- @param zone any
--- @param zoneIndex number
--- @param now number
function Service.ApplyEffect(player: Player, zone: any, zoneIndex: number, now: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")

	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end

	local hazard = zone.Hazard

	if hazard.Kind == HazardRules.Kind.Quicksand then
		if not Service._slowed[player.UserId] then
			Service._slowed[player.UserId] = true
			humanoid.WalkSpeed = HazardRules.SlowedWalkSpeed(hazard)
		end

		return
	end

	if hazard.Kind == HazardRules.Kind.Lava or hazard.Kind == HazardRules.Kind.Laser then
		local damage = HazardRules.DamagePerTick(hazard, now, HazardRules.TickSeconds)

		if damage > 0 and Service._combatService and Service._combatService.ApplyDamage then
			Service._combatService.ApplyDamage(humanoid, damage, nil)
		end

		return
	end

	if hazard.Kind == HazardRules.Kind.Gust then
		-- La racha golpea a ritmo, no en cada paso: `Interval` marca el
		-- pulso y el impulso se aplica una vez por ventana.
		local slot = math.floor(now / (tonumber(hazard.Interval) or 2.5))
		local key = ("%d:%d:gust"):format(player.UserId, zoneIndex)

		if Service._inside[key] ~= slot then
			Service._inside[key] = slot

			-- La direccion es fija por zona: el viento de un sitio sopla
			-- siempre igual, y el jugador lo aprende.
			local angle = (zoneIndex * 2.4) % (math.pi * 2)
			local direction = Vector3.new(math.cos(angle), 0.15, math.sin(angle))
			local impulse = (tonumber(hazard.Impulse) or 40) * root.AssemblyMass

			root:ApplyImpulse(direction * impulse)
		end

		return
	end

	if hazard.Kind == HazardRules.Kind.Ambush then
		local key = ("%d:%d"):format(player.UserId, zoneIndex)

		if
			not Service._inside[key]
			and HazardRules.CanAmbush(zone.LastAmbushAt, hazard.Cooldown, now)
			and Service._monsterService
			and Service._monsterService.Spawn
		then
			zone.LastAmbushAt = now

			for _ = 1, tonumber(hazard.Count) or 1 do
				local spawnId = hazard.Spawns[math.random(1, #hazard.Spawns)]
				local offset = Vector3.new(math.random(-10, 10), 3, math.random(-10, 10))
				Service._monsterService.Spawn(spawnId, zone.Position + offset, zone.WorldId)
			end

			Logger.Debug(("HazardService: emboscada en %s zona %d"):format(zone.WorldId, zoneIndex))
		end

		return
	end
end

--- Devuelve la velocidad al jugador que SALIO de la arena movediza.
--- @param player Player
function Service.ClearSlow(player: Player)
	if not Service._slowed[player.UserId] then
		return
	end

	Service._slowed[player.UserId] = nil

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if humanoid and humanoid.Health > 0 then
		humanoid.WalkSpeed = HazardRules.DefaultWalkSpeed
	end
end

-- ---------------------------------------------------------------------------
-- MANTENIMIENTO
-- ---------------------------------------------------------------------------

--- Un paso del servicio: construye lo que falte y aplica efectos.
--- @param now any? reloj del servidor
function Service.Tick(now: any?)
	local t = now

	if type(t) ~= "number" or t ~= t then
		t = os.clock()
	end

	-- Los mundos se construyen por DEMANDA: un mundo cuya carpeta aun no
	-- existe (mapa no generado) no produce zonas ni errores, solo se
	-- reintenta en el siguiente paso.
	local worldsPresent: { [string]: boolean } = {}

	for _, player in ipairs(Players:GetPlayers()) do
		local worldId = player:GetAttribute("World")

		if type(worldId) == "string" then
			worldsPresent[worldId] = true
		end
	end

	for worldId in pairs(worldsPresent) do
		Service.BuildWorld(worldId)
	end

	-- Efectos: solo sobre jugadores EN un mundo con zonas construidas.
	local slowedNow: { [number]: boolean } = {}

	for _, player in ipairs(Players:GetPlayers()) do
		local worldId = player:GetAttribute("World")
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")

		if type(worldId) == "string" and root and root:IsA("BasePart") then
			for zoneIndex, zone in ipairs(Service._zones) do
				if zone.WorldId == worldId and isInside(root, zone) then
					if zone.Hazard.Kind == HazardRules.Kind.Quicksand then
						slowedNow[player.UserId] = true
					end

					Service.ApplyEffect(player, zone, zoneIndex, t)
				end
			end
		end

		-- El jugador que piso arena movediza y YA NO esta dentro recupera
		-- su velocidad aqui: el rastreo de salida es lo que impide que el
		-- jugador se quede lento para siempre por morir dentro de la zona.
		if not slowedNow[player.UserId] then
			Service.ClearSlow(player)
		end
	end

	-- Telegraph del laser: la zona se vuelve opaca cuando esta encendida.
	-- Es la UNICA parte visual que cambia por tick, y cambia dos veces por
	-- ciclo como mucho.
	for _, zone in ipairs(Service._zones) do
		if zone.Hazard.Kind == HazardRules.Kind.Laser and zone.Part then
			zone.Part.Transparency = if HazardRules.IsLaserOn(zone.Hazard, t) then 0.35 else 0.85
		end
	end
end

local function runMaintenance()
	while Service._running do
		local ok, err = pcall(Service.Tick)

		if not ok then
			Logger.Error(("HazardService: el mantenimiento fallo: %s"):format(tostring(err)))
		end

		task.wait(HazardRules.TickSeconds)
	end
end

-- ---------------------------------------------------------------------------
-- CICLO DE VIDA DEL SERVICIO
-- ---------------------------------------------------------------------------

--- Inicializacion. Idempotente.
--- @param _maid any?
--- @return boolean success
function Service.Init(_maid: any?): boolean
	if Service.IsInitialized then
		return true
	end

	Service._zones = {}
	Service._slowed = {}
	Service._inside = {}
	Service._zoneCache = {}

	Service.IsInitialized = true
	return true
end

--- Arranca el mantenimiento. Idempotente.
--- @return boolean success
function Service.Start(): boolean
	if not Service.IsInitialized then
		Logger.Error("HazardService: Start sin Init")
		return false
	end

	if Service._running then
		return true
	end

	Service._running = true
	Service._thread = task.spawn(runMaintenance)

	Logger.Info("HazardService: listo (5 mundos, mecanica propia por mundo).")
	return true
end

--- Para el servicio y retira TODAS las zonas. Idempotente.
--- @return boolean success
function Service.Destroy(): boolean
	Service._running = false

	if Service._thread then
		pcall(task.cancel, Service._thread)
		Service._thread = nil
	end

	-- Nadie se queda lento al apagar el servicio.
	for _, player in ipairs(Players:GetPlayers()) do
		Service.ClearSlow(player)
	end

	Service._slowed = {}
	Service._inside = {}
	Service._zones = {}
	Service._zoneCache = {}

	if Service._folder then
		pcall(function()
			Service._folder:Destroy()
		end)
		Service._folder = nil
	end

	Service.IsInitialized = false
	return true
end

return Service
