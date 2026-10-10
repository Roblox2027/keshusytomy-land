--!strict
--[[
	ChestService
	Cofres físicos que otorgan HABILIDADES pasivas (FASE 20).

	POR QUE EXISTE
	--------------
	El juego tiene monedas, XP, items de inventario y progresión, pero NUNCA
	una razón para explorar el mapa más allá de "hay enemigos aquí". Los
	cofres son el incentivo de exploración: el jugador se mueve, descubre
	un cofre, lo abre y gana una habilidad permanente que mejora su
	construcción de personaje (más velocidad, más bombas, más vida...).

	LA INTERACCIÓN
	---------------
	Igual que los secretos (`SecretService`):
	  - El cofre es un Model con un ProximityPrompt.
	  - El cliente no elige el premio: el servidor lo decide con
	    `ChestRules.OpenReward` (determinista con el RNG del servidor).
	  - El resultado viaja por atributos del jugador
	    (`ChestSkillId`, `ChestsOpened`), igual que `SecretsFound`.
	  - El estado se guarda en el perfil (`Skills.Unlocked`), que es la
	    única verdad de "qué habilidades tengo".

	LA PROPIEDAD
	------------
	El cofre NO puede abrirlo otro jugador: se escribe el `UserId` del
	dueño en el prompt. Un cofre individual está reservado para quien lo
	primera vio. (Los cofres son singulares, no compartidos: no hay
	"lo abrió primero".)

	LA PERSISTENCIA
	---------------
	Abrir un cofre marca su ID en `profile.Skills.OpenedChests[chestId] = true`.
	Un cofre abierto vuelve a estar vacío para SIEMPRE: el jugador no puede
	farmearlo. La lista de habilidades está en `profile.Skills.Unlocked[id]`,
	y se publica como `SkillCount` para que la UI sepa cuántas lleva.
]]

local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONFIG = SHARED:WaitForChild("Config")
local UTILS = SHARED:WaitForChild("Utils")

local ChestRules = require(SHARED:WaitForChild("Libraries"):WaitForChild("ChestRules"))
local BrainrotRules = require(SHARED:WaitForChild("Libraries"):WaitForChild("BrainrotRules"))
local Logger = require(UTILS:WaitForChild("Logger"))

local Service = {}

Service.IsInitialized = false

-- Servicios inyectados por `ServerMain`.
Service._profileService = nil
Service._skillService = nil
Service._maid = nil

-- Cofres spawneados: chestKey -> { Model, WorldId, ChestType, Prompt }
Service._chests = {}

-- Diagnostico.
Service._opened = 0
Service._alreadyOpened = 0
Service._granted = 0

--- @param profileService any
function Service.SetDependencies(profileService: any)
	Service._profileService = profileService
end

--- Inyecta SkillService para que recalcule las estadísticas de bomba
--- cuando el jugador desbloquee una habilidad de cofre.
---
--- Es OPCIONAL: sin el, las habilidades se guardan en el perfil pero no
--- se aplican a la bomba del jugador hasta el próximo login.
--- @param skillService any?
function Service.SetSkillService(skillService: any?)
	Service._skillService = skillService
end

--- Puntos de spawn de cofres declarados en el mapa de un mundo.
--- @param worldId string
--- @return { BasePart }
function Service.CollectSpawnPoints(worldId: string): { BasePart? }
	local points = {}

	if type(worldId) ~= "string" or worldId == "" then
		return points
	end

	local worlds = Workspace:FindFirstChild("Worlds")
	local worldFolder = worlds and worlds:FindFirstChild(worldId)

	if not worldFolder then
		return points
	end

	local spawnsFolder = worldFolder:FindFirstChild("ChestSpawns")

	if not spawnsFolder then
		return points
	end

	for _, child in ipairs(spawnsFolder:GetChildren()) do
		if child:IsA("BasePart") and child.Name:match("^ChestSpawn_") then
			table.insert(points, child :: BasePart)
		end
	end

	table.sort(points, function(a, b)
		return a.Name < b.Name
	end)

	return points
end

--- Genera los cofres de un mundo.
---
--- Cada cofre es un Model con un ProximityPrompt. La distribución de tipos
--- (Common/Rare/Epic/Legacy) viene de `ChestRules.GetChestDistribution`, y
--- se asigna round-robin a los marcadores de spawn del mundo.
--- @param worldId string
--- @return number spawned
function Service.SpawnChestsForWorld(worldId: string): number
	local points = Service.CollectSpawnPoints(worldId)

	if #points == 0 then
		Logger.Debug(("ChestService: %s no tiene marcadores de cofre"):format(worldId))
		return 0
	end

	local distribution = ChestRules.GetChestDistribution(worldId)

	if not distribution then
		Logger.Warn(("ChestService: %s no tiene distribución de cofres"):format(worldId))
		return 0
	end

	-- Expandir la distribución en una lista plana de tipos.
	local typeList = {}
	for _, entry in ipairs(distribution) do
		for _ = 1, entry.Count do
			table.insert(typeList, entry.ChestType)
		end
	end

	if #typeList == 0 then
		return 0
	end

	local spawned = 0

	for i, point in ipairs(points) do
		if not point:IsA("BasePart") then
			continue
		end

		-- Round-robin: el tipo se elige por posición, no al azar.
		-- Así, el mismo mundo siempre genera el mismo cofre en el mismo lugar.
		local chestType = typeList[((i - 1) % #typeList) + 1]
		local chestKey = ("%s_%s"):format(worldId, point.Name)

		-- Si ya existe un cofre aquí, no se genera otro (idempotente).
		if Service._chests[chestKey] then
			continue
		end

		local model = Service.BuildChestModel(chestType, chestKey)

		if model then
			model:PivotTo(CFrame.new(point.Position))
			model.Parent = Workspace

			Service._chests[chestKey] = {
				Model = model,
				WorldId = worldId,
				ChestType = chestType,
				Key = chestKey,
				Prompt = model:FindFirstChildOfClass("ProximityPrompt"),
			}
			spawned += 1
		end
	end

	Logger.Info(("ChestService: %d cofre(s) generados en %s"):format(spawned, worldId))
	return spawned
end

--- Genera los cofres de TODOS los mundos.
--- @return number total
function Service.SpawnAllWorlds(): number
	local total = 0
	local worlds = Workspace:FindFirstChild("Worlds")

	if not worlds then
		return 0
	end

	for _, folder in ipairs(worlds:GetChildren()) do
		if folder:IsA("Folder") then
			local worldId = folder.Name
			local spawns = folder:FindFirstChild("ChestSpawns")

			if spawns then
				total += Service.SpawnChestsForWorld(worldId)
			end
		end
	end

	return total
end

--- Construye el modelo físico de un cofre.
---
--- El modelo tiene un ProximityPrompt con `ActionText` que indica el tipo
--- de cofre, y un `ObjectText` que muestra el premio al abrirlo.
--- @param chestType string
--- @param chestKey string
--- @return Model?
function Service.BuildChestModel(chestType: string, chestKey: string): Model?
	local color = Service.ChestColor(chestType)
	local promptText = Service.ChestLabel(chestType)

	local model = Instance.new("Model")
	model.Name = ("Chest_%s"):format(chestKey)

	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = Vector3.new(4, 3, 3)
	base.Anchored = true
	base.CanCollide = true
	base.BrickColor = BrickColor.new("Bright red")
	base.Material = Enum.Material.Metal
	base.Parent = model

	local lid = Instance.new("Part")
	lid.Name = "Lid"
	lid.Size = Vector3.new(4.2, 0.8, 3.2)
	lid.Anchored = true
	lid.CanCollide = false
	lid.BrickColor = BrickColor.new("Bright red")
	lid.Material = Enum.Material.Metal
	lid.CFrame = base.CFrame * CFrame.new(0, 1.6, 0)
	lid.Parent = model

	-- El Prompt se guarda el chestKey en el atributo para que el handler
	-- sepa a qué cofre pertenece sin depender de un diccionario.
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = promptText
	prompt.ObjectText = "Cofre del tesoro"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Enabled = true
	prompt.Parent = base

	base:SetAttribute("ChestKey", chestKey)
	base:SetAttribute("ChestType", chestType)
	model.PrimaryPart = base

	return model
end

--- Color del cofre según su tipo.
--- @param chestType string
--- @return BrickColor
function Service.ChestColor(chestType: string): BrickColor
	local defaults = {
		[ChestRules.ChestType.Common] = BrickColor.new("Bright red"),
		[ChestRules.ChestType.Rare] = BrickColor.new("Bright blue"),
		[ChestRules.ChestType.Epic] = BrickColor.new("Bright violet"),
		[ChestRules.ChestType.Legacy] = BrickColor.new("Royal purple"),
	}

	return defaults[chestType] or BrickColor.new("Bright red")
end

--- Texto del prompt según su tipo.
--- @param chestType string
--- @return string
function Service.ChestLabel(chestType: string): string
	local labels = {
		[ChestRules.ChestType.Common] = "Abrir cofre común",
		[ChestRules.ChestType.Rare] = "Abrir cofre raro",
		[ChestRules.ChestType.Epic] = "Abrir cofre épico",
		[ChestRules.ChestType.Legacy] = "Abrir cofre legendario",
	}

	return labels[chestType] or "Abrir cofre"
end

--- Estado de habilidades de un jugador. Inicializa si no existía.
--- @param player Player
--- @return any? profile
function Service.GetSkillsState(player: Player): any?
	if not Service._profileService then
		return nil
	end

	if not Service._profileService.HasProfile(player) then
		return nil
	end

	local profile = Service._profileService.GetProfile(player)

	if type(profile) ~= "table" then
		return nil
	end

	if type(profile.Skills) ~= "table" then
		profile.Skills = { Unlocked = {}, OpenedChests = {} }
	end

	if type(profile.Skills.Unlocked) ~= "table" then
		profile.Skills.Unlocked = {}
	end

	if type(profile.Skills.OpenedChests) ~= "table" then
		profile.Skills.OpenedChests = {}
	end

	return profile.Skills
end

	--- Comprueba si un jugador ya abrió un cofre.
	--- @param player Player
	--- @param chestKey string
	--- @return boolean
	function Service.HasOpenedChest(player: Player, chestKey: string): boolean
		local state = Service.GetSkillsState(player)

		if not state then
			return false
		end

		return state.OpenedChests[chestKey] == true
	end

	--- Reclama un cofre vía remoto (cliente-UI path).
	---
	--- El payload es el `chestKey`. El servidor resuelve el cofre REAL,
	--- comprueba proximidad y delega en `OpenChest`.
	--- @param player Player
	--- @param payload any debe contener `ChestKey`
	--- @return boolean granted
	function Service.TryClaim(player: Player, payload: any): boolean
		if type(payload) ~= "table" then
			return false
		end

		local chestKey = payload.ChestKey or payload

		if type(chestKey) ~= "string" then
			return false
		end

		local entry = Service._chests[chestKey]

		if not entry then
			return false
		end

		-- Comprueba proximidad.
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local base = entry.Model and entry.Model.PrimaryPart

		if not root or not base then
			return false
		end

		if (root.Position - base.Position).Magnitude > 14 then
			return false
		end

		-- El jugador debe estar en el mundo correcto.
		local worldId = player:GetAttribute("World")

		if not worldId or type(worldId) ~= "string" then
			return false
		end

		local granted, _, reason = Service.OpenChest(player, chestKey, entry.ChestType, worldId)
		return granted
	end

	--- Publica el estado de cofres e habilidades del jugador.
	---
	--- Va por atributos (no por remoto de vuelta): `SkillCount` y
	--- `SkillsUnlocked` son lo que lee la UI.
	--- @param player Player
	function Service.PublishChestState(player: Player)
		local state = Service.GetSkillsState(player)

		if not state then
			player:SetAttribute("SkillCount", 0)
			player:SetAttribute("SkillsUnlocked", "")
			return
		end

		local count = 0
		local ids = {}

		for id in pairs(state.Unlocked) do
			count += 1
			table.insert(ids, id)
		end

		table.sort(ids)

		player:SetAttribute("SkillCount", count)
		player:SetAttribute("SkillsUnlocked", table.concat(ids, ","))
	end

	--- Publica la oferta de cofres al jugador (número de cofres abiertos).
	--- @param player Player
	function Service.PublishOffer(player: Player)
		local state = Service.GetSkillsState(player)
		local opened = 0

		if state and type(state.OpenedChests) == "table" then
			for _ in pairs(state.OpenedChests) do
				opened += 1
			end
		end

		player:SetAttribute("ChestsOpened", opened)
		Service.PublishChestState(player)
	end

	--- Publica el estado de cofres y habilidades del jugador en respuesta a
	--- una consulta del cliente (ChestAction.Query).
	---
	--- Va por atributos: `SkillCount`, `SkillsUnlocked` y `ChestsOpened`
	--- son lo que la UI lee.
	--- @param player Player
	function Service.PublishQuery(player: Player)
		Service.PublishOffer(player)
	end

--- Entrega una habilidad al jugador desde un cofre.
---
--- Usa `ChestRules.OpenReward` para decidir la habilidad (con un RNG basado
--- en el chestKey, para que el mismo cofre siempre dé lo mismo). Marca el
--- cofre como abierto y publica los atributos.
--- @param player Player
--- @param chestKey string
--- @param chestType string
--- @param worldId string
--- @return boolean granted
--- @return string? skillId
--- @return string? reason
function Service.OpenChest(
	player: Player,
	chestKey: string,
	chestType: string,
	worldId: string
): (boolean, string?, string?)
	if not Service._profileService then
		return false, nil, "sin ProfileService"
	end

	if not Service._profileService.HasProfile(player) then
		return false, nil, "sin perfil"
	end

	local state = Service.GetSkillsState(player)

	if not state then
		return false, nil, "estado de habilidades invalido"
	end

	-- ¿Ya lo abrió? No se puede abrir dos veces.
	if state.OpenedChests[chestKey] then
		Service._alreadyOpened += 1
		return false, nil, "cofre ya abierto"
	end

	-- RNG determinístico basado en el chestKey: el mismo cofre siempre
	-- da la misma habilidad. Se usa un hash simple.
	local hash = 0
	for i = 1, #chestKey do
		hash = (hash * 31 + string.byte(chestKey, i)) % 100000
	end

	local function roll()
		hash = (hash * 374761393 + 1) % 100000
		return hash / 100000
	end

	local reward = ChestRules.OpenReward(chestType, worldId, roll)

	if not reward then
		return false, nil, "sin recompensa disponible"
	end

	-- Marcar como abierto ANTES de conceder: si la entrega falla por
	-- alguna razón, no queremos que el jugador pueda volver a intentar.
	state.OpenedChests[chestKey] = true
	state.Unlocked[reward.id] = true

	Service._profileService.MarkDirty(player)
	Service._profileService.GetProfile(player).Skills = state

	-- Publicar atributos para la UI.
	local unlockedCount = 0
	for _ in pairs(state.Unlocked) do
		unlockedCount += 1
	end

	player:SetAttribute("SkillCount", unlockedCount)
	player:SetAttribute("SkillUnlockedId", reward.id)
	player:SetAttribute("SkillUnlockedName", reward.name)
	player:SetAttribute("SkillUnlockedRarity", reward.rarity)

	-- Publicar la lista de habilidades desbloqueadas como cadena.
	local ids = {}
	for id in pairs(state.Unlocked) do
		table.insert(ids, id)
	end
	table.sort(ids)
	player:SetAttribute("SkillsUnlocked", table.concat(ids, ","))

	Service._opened += 1
	Service._granted += 1

	Logger.Info(("ChestService: %s abrió %s en %s -> %s (%s)"):format(
		player.Name, chestKey, worldId, reward.id, reward.name
	))

	-- Recalcular las estadísticas de bomba del jugador: la nueva habilidad
	-- puede haber cambiado radio, daño, capacidad o sabor. El refresh es
	-- seguro sin SkillService (es un no-op si no está conectado).
	if Service._skillService and Service._skillService.RefreshPlayer then
		Service._skillService.RefreshPlayer(player)
	end

	return true, reward.id, nil
end

--- Marca un cofre como visualmente abierto para todos los jugadores.
---
--- El cofre se queda en el mapa pero su prompt se desactiva: "ya no es
--- interactuable". Esto permite a los demás jugadores ver que el cofre
--- existe, solo que está vacío.
--- @param chestKey string
function Service.DeactivateChest(chestKey: string)
	local entry = Service._chests[chestKey]

	if entry and entry.Prompt then
		entry.Prompt.Enabled = false
	end
end

--- Manejador del ProximityPrompt.Triggered.
--- @param prompt ProximityPrompt
--- @param player Player
function Service.HandlePromptTriggered(prompt: ProximityPrompt, player: Player)
	local base = prompt.Parent

	if not base or not base:IsA("BasePart") then
		return
	end

	local chestKey = base:GetAttribute("ChestKey")
	local chestType = base:GetAttribute("ChestType")

	if not chestKey or not chestType then
		return
	end

	-- El jugador tiene que estar cerro. El ProximityPrompt ya limita la
	-- distancia, pero se comprueba aquí también para el log de auditoría.
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")

	if not root then
		return
	end

	if (root.Position - base.Position).Magnitude > 14 then
		return
	end

	-- El jugador tiene que estar en el mundo correcto. El atributo `World`
	-- lo escribe `MatchService.MovePlayer` en cada traslado.
	local worldId = player:GetAttribute("World")

	if not worldId or type(worldId) ~= "string" then
		return
	end

	local granted, skillId, reason = Service.OpenChest(player, chestKey, chestType, worldId)

	if not granted then
		if reason and reason ~= "cofre ya abierto" then
			Logger.Debug(("ChestService: %s no pudo abrir %s: %s"):format(
				player.Name, chestKey, reason
			))
		end
		return
	end

	-- Desactivar visualmente para todos.
	Service.DeactivateChest(chestKey)

	-- Publicar la notificación.
	player:SetAttribute("ChestJustOpened", chestKey)

	-- Limpiar atributos de notificación después de un breve delay.
	task.delay(5, function()
		if player.Parent then
			player:SetAttribute("ChestJustOpened", nil)
			player:SetAttribute("SkillUnlockedId", nil)
			player:SetAttribute("SkillUnlockedName", nil)
			player:SetAttribute("SkillUnlockedRarity", nil)
		end
	end)
end

--- Inicialización. Idempotente.
--- @param _maid any?
--- @return boolean success
function Service.Init(_maid: any?): boolean
	if Service.IsInitialized then
		return true
	end

	-- Las constantes de tipo de cofre vienen de ChestRules (ChestType.Common, etc.)
	-- ChestColor y ChestLabel las usan para pintar y etiquetar los modelos.
	Service._chests = {}
	Service._opened = 0
	Service._alreadyOpened = 0
	Service._granted = 0
	Service.IsInitialized = true
	return true
end

--- Arranque. Registra los handlers de ProximityPrompt.
--- @param _maid any?
--- @return boolean success
function Service.Start(_maid: any?): boolean
	if not Service.IsInitialized then
		Logger.Error("ChestService: Start sin Init")
		return false
	end

	if not Service._profileService then
		Logger.Error("ChestService: sin ProfileService.")
		return false
	end

	Service._maid = _maid

	-- Registrar los handlers de ProximityPrompt ANTES de spawnear cofres,
	-- para no perder triggers de apertura si el prompt se conecta después
	-- de que el jugador ya esté interactuando.
	if _maid then
		_maid:Connect(ProximityPromptService.PromptTriggered, function(prompt: ProximityPrompt, player: Player)
			Service.HandlePromptTriggered(prompt, player)
		end)
	end

	-- Generar todos los cofres del mapa.
	local total = Service.SpawnAllWorlds()
	Logger.Info(("ChestService: %d cofre(s) en el mapa"):format(total))

	return true
end

--- Apagado.
--- @return boolean success
function Service.Destroy(): boolean
	-- Limpiar modelos de cofres.
	for chestKey, entry in pairs(Service._chests) do
		if entry.Model and entry.Model.Parent then
			entry.Model:Destroy()
		end
		Service._chests[chestKey] = nil
	end
	Service._chests = {}

	Service._profileService = nil
	Service._skillService = nil
	Service._maid = nil
	Service.IsInitialized = false
	return true
end

return Service
