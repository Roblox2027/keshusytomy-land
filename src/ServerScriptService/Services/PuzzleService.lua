--!strict
--[[
	PuzzleService
	PUZZLES CORTOS y secretos cooperativos (MASTER MISSION V2 - FASES 13/14).

	QUE HACE Y QUE DELEGA
	---------------------
	NO calcula la ventana ni el cooldown: eso es `PuzzleRules` (puro,
	probado). Este servicio aporta lo que el motor: los pedestales, los
	prompts, el reloj y el pago.

	COMO FUNCIONA EL DOBLE INTERRUPTOR
	----------------------------------
	Dos pedestales por mundo, en las dos zonas MAS ALEJADAS entre si (el
	puzzle es el viaje entre ellos). Activar el primero abre una ventana;
	activar el segundo dentro de la ventana completa el puzzle y paga a
	quienes participaron.

	COOPERATIVO JUSTO
	-----------------
	La ventana es generosa a proposito: dos jugadores lo hacen facil y un
	jugador solo puede hacerlo corriendo. NADA del progreso principal pasa
	por aqui: es un premio de mundo, no una puerta.

	RENDIMIENTO
	-----------
	No hay hilo: el puzzle responde a los prompts y el cooldown se
	comprueba en la activacion, no en un sondeo.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local UTILS = SHARED:WaitForChild("Utils")

local PuzzleRules = require(SHARED:WaitForChild("Libraries"):WaitForChild("PuzzleRules"))
local Logger = require(UTILS:WaitForChild("Logger"))

local Service = {}

Service.IsInitialized = false

-- Servicios inyectados por `ServerMain`.
Service._economyService = nil
Service._questService = nil

-- Estado por mundo: { FirstAt = number?, FirstBy = number?, CompletedAt = number? }.
Service._state = {}

-- Pedestales construidos: worldId -> true.
Service._built = {}

-- Cache de centros de zona por mundo (contrato `Zone_*_Core`).
Service._zoneCache = {}

-- ---------------------------------------------------------------------------
-- INYECCION
-- ---------------------------------------------------------------------------

--- @param economyService any?
--- @param questService any?
function Service.SetDependencies(economyService: any?, questService: any?)
	Service._economyService = economyService
	Service._questService = questService
end

-- ---------------------------------------------------------------------------
-- CONSTRUCCION
-- ---------------------------------------------------------------------------

--- Centros de zona de un mundo: { { Id, Position } }, ordenados por
--- nombre para determinismo.
--- @param worldId string
--- @return { any }
local function zoneEntries(worldId: string): { any }
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
		for _, child in ipairs(zones:GetChildren()) do
			if child:IsA("Folder") and string.sub(child.Name, 1, 5) == "Zone_" then
				local core = child:FindFirstChild(child.Name .. "_Core")

				if core and core:IsA("BasePart") then
					table.insert(cache, { Id = child.Name, Position = core.Position })
				end
			end
		end

		table.sort(cache, function(a, b)
			return a.Id < b.Id
		end)
	end

	return cache
end

--- Las DOS zonas mas alejadas entre si: el puzzle es el viaje.
--- @param worldId string
--- @return Vector3? first
--- @return Vector3? second
local function farthestPair(worldId: string): (Vector3?, Vector3?)
	local entries = zoneEntries(worldId)

	if #entries < 2 then
		return nil, nil
	end

	local bestA = nil
	local bestB = nil
	local bestDistance = -1

	for i = 1, #entries do
		for j = i + 1, #entries do
			local distance = (entries[i].Position - entries[j].Position).Magnitude

			if distance > bestDistance then
				bestDistance = distance
				bestA = entries[i].Position
				bestB = entries[j].Position
			end
		end
	end

	return bestA, bestB
end

--- Construye el doble interruptor de un mundo. Idempotente.
--- @param worldId string
--- @return boolean built
function Service.BuildWorld(worldId: string): boolean
	if Service._built[worldId] then
		return false
	end

	local first, second = farthestPair(worldId)

	if not first or not second then
		return false
	end

	local state = { FirstAt = nil, FirstBy = nil, CompletedAt = nil }
	Service._state[worldId] = state

	for index, position in ipairs({ first, second }) do
		local pedestal = Instance.new("Part")
		pedestal.Name = ("PuzzleSwitch_%s_%d"):format(worldId, index)
		pedestal.Size = Vector3.new(3, 3, 3)
		pedestal.Position = position + Vector3.new(0, 1.5, 0)
		pedestal.Anchored = true
		pedestal.Color = Color3.fromRGB(140, 120, 255)
		pedestal.Material = Enum.Material.Neon
		pedestal:SetAttribute("PuzzleWorld", worldId)
		pedestal:SetAttribute("PuzzleIndex", index)
		pedestal.Parent = Workspace

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Activar"
		prompt.ObjectText = "INTERRUPTOR"
		prompt.HoldDuration = 0.4
		prompt.MaxActivationDistance = 10
		prompt.Parent = pedestal

		prompt.Triggered:Connect(function(player: Player)
			Service.OnSwitchTriggered(worldId, index, player)
		end)
	end

	Service._built[worldId] = true
	Logger.Info(("PuzzleService: doble interruptor construido en %s"):format(worldId))
	return true
end

-- ---------------------------------------------------------------------------
-- LOGICA DE ACTIVACION
-- ---------------------------------------------------------------------------

--- Activacion de un interruptor. El SERVIDOR decide la ventana: el
--- reloj es suyo y el cliente no manda tiempos.
--- @param worldId string
--- @param index number
--- @param player Player
function Service.OnSwitchTriggered(worldId: string, index: number, player: Player)
	local state = Service._state[worldId]

	if not state then
		return
	end

	local now = os.clock()

	-- Cooldown: un puzzle completado no se repite al instante.
	if not PuzzleRules.IsOffCooldown(state.CompletedAt, now) then
		return
	end

	if state.FirstAt == nil then
		-- Primera activacion: abre la ventana.
		state.FirstAt = now
		state.FirstBy = player.UserId
		state.LastIndex = index
		player:SetAttribute("PuzzleWindow", worldId)
		return
	end

	-- Segunda activacion del MISMO pedestal: no completa nada (el puzzle
	-- es el viaje entre DOS interruptores).
	local sameSwitchTwice = state.LastIndex == index and state.FirstBy == player.UserId

	if sameSwitchTwice then
		return
	end

	if not PuzzleRules.IsWindowOpen(state.FirstAt, now) then
		-- Ventana caducada: esta activacion ABRE una nueva.
		state.FirstAt = now
		state.FirstBy = player.UserId
		state.LastIndex = index
		return
	end

	-- COMPLETADO: la segunda activacion llego a tiempo.
	state.FirstAt = nil
	state.FirstBy = nil
	state.LastIndex = nil
	state.CompletedAt = now

	Service.PayReward(worldId, player)
end

--- Paga el puzzle a los jugadores PRESENTES en el mundo.
---
--- Es mundial como los eventos: el puzzle es del mundo y lo cobran los
--- que estan dentro. El requestId es por mundo y completado, asi que el
--- mismo puzzle no se cobra dos veces aunque dos jugadores pulsen a la
--- vez.
--- @param worldId string
--- @param _triggeredBy Player
function Service.PayReward(worldId: string, _triggeredBy: Player)
	local economy = Service._economyService

	if not economy or not economy.GrantCurrency then
		return
	end

	local state = Service._state[worldId]
	local stamp = math.floor((state and state.CompletedAt) or 0)

	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("World") == worldId then
			pcall(
				economy.GrantCurrency,
				player,
				"Coins",
				PuzzleRules.RewardCoins,
				"puzzle_doble_interruptor",
				"puzzle_service",
				{ WorldId = worldId },
				("puzzle_%s_%d"):format(worldId, stamp)
			)

			player:SetAttribute("PuzzleSolved", worldId)

			if Service._questService and Service._questService.RecordMetric then
				Service._questService.RecordMetric(player, "EventCompleted", 1)
			end
		end
	end

	Logger.Info(("PuzzleService: puzzle de %s completado"):format(worldId))
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

	Service._state = {}
	Service._built = {}
	Service._zoneCache = {}
	Service.IsInitialized = true
	return true
end

--- Arranque: construye los puzzles de los mundos presentes.
--- @return boolean success
function Service.Start(): boolean
	if not Service.IsInitialized then
		Logger.Error("PuzzleService: Start sin Init")
		return false
	end

	-- Construccion por demanda: los mundos presentes AHORA reciben su
	-- puzzle; el que llegue despues lo recibe cuando su carpeta exista.
	-- No hay hilo: `MatchService` mueve jugadores y los prompts esperan.
	for _, player in ipairs(Players:GetPlayers()) do
		local worldId = player:GetAttribute("World")

		if type(worldId) == "string" then
			Service.BuildWorld(worldId)
		end
	end

	Logger.Info("PuzzleService: listo (doble interruptor por mundo).")
	return true
end

--- Apagado. Idempotente.
--- @return boolean success
function Service.Destroy(): boolean
	Service._state = {}
	Service._built = {}
	Service._zoneCache = {}
	Service.IsInitialized = false
	return true
end

return Service
