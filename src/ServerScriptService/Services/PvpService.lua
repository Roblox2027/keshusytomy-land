--!strict
--[[
	PvpService
	Modo PvP de la arena del lobby: entra, te asignan bando y peleas.

	POR QUE EXISTE
	--------------
	La arena del lobby ya estaba construida (muros, linea central, marcadores
	`PvPSpawn_A`, `PvPSpawn_B`, `PvPCenter`, `PvPEntry`) pero NINGUN servicio la
	leia: era un cuarto bonito que no hacia nada. Este servicio es el que la
	enciende.

	COMO FUNCIONA (autoridad del servidor)
	--------------------------------------
	Un vigilante de proximidad (cada `WatchInterval`):
	  - Si un jugador pisa `PvPEntry` y no esta ya en PvP, se le asigna el bando
	    con menos gente (`PvpRules.AssignTeam`), se le teletransporta a SU spawn
	    (`PvPSpawn_A`/`B`, lados opuestos de la linea central) y se le marca con
	    los atributos `PvpActive` y `PvpTeam`.
	  - Si un jugador marcado sale de la caja de la arena, se le retiran los
	    atributos: el modo PvP se apaga y el lobby vuelve a ser zona segura.

	EL CONTRATO CON CombatService
	-----------------------------
	Este servicio no aplica dano: solo publica los atributos. `CombatService`
	los lee para decidir si el melee/habilidad puede golpear a otros jugadores y
	si `ApplyDamage` admite dano sin ronda en curso. Un atributo por jugador es
	lo unico que comparten, y vive en el propio jugador (no en una tabla global)
	para que se vaya con el.

	EL BUCLE DE LA PUERTA
	---------------------
	La entrada y la salida comparten el umbral (`PvPEntry` esta en la unica
	abertura del muro norte). Sin mas, un jugador que cruza hacia afuera
	dispararia salida y entrada en el mismo sitio y rebotaria dentro. El
	`_entryCooldown` lo evita: al salir se bloquea la re-entrada unos segundos,
	que es lo que tarda en alejarse de la puerta.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SHARED = ReplicatedStorage:WaitForChild("Shared")
local UTILS = SHARED:WaitForChild("Utils")

local PvpRules = require(SHARED:WaitForChild("Libraries"):WaitForChild("PvpRules"))
local Logger = require(UTILS:WaitForChild("Logger"))

local Service = {}

Service.IsInitialized = false

Service._maid = nil
Service._running = false

-- Marcadores del mapa. Se resuelven en Start (busqueda recursiva) para no
-- depender de la ruta exacta de la carpeta del lobby.
Service._center = nil
Service._spawnA = nil
Service._spawnB = nil
Service._entry = nil

-- Semitamano de la caja de la arena. Se deriva de `PvPArena_Floor`; si no
-- esta, cae a estas constantes (66 x 46 -> mitad 33 x 23).
Service._half = { X = 33, Z = 23 }

-- Radio a partir del cual se cuenta que el jugador piso la entrada.
Service.EntryRadius = 10
-- Cada cuanto sondea el vigilante.
Service.WatchInterval = 0.4
-- Segundos que se bloquea la re-entrada tras salir (anti-rebote en la puerta).
Service.EntryCooldown = 2

-- userId -> instante (os.clock) hasta el cual no puede volver a entrar.
Service._entryCooldown = {}

-- Kills de la sesion PvP, por userId. Las lleva el PROPIO servicio y no
-- `CombatService` a proposito: alli el contador es global de todo el servidor
-- (incluye rounds PvE), y aqui solo cuentan las kills de ESTA arena.
Service._kills = {}

-- Marcador (BillboardGui sobre el centro de la arena) y killfeed. Se construyen
-- en `Start` (`_buildScoreboard`/`_buildKillfeed`) y se destruyen en `Destroy`.
-- `_scorePart` y `_feedPart` son las piezas-ancla invisibles que sostienen cada
-- BillboardGui; los `_...Label` son los textos que se reescriben en cada kill.
Service._scorePart = nil
Service._scoreGui = nil
Service._scoreLabel = nil
Service._feedPart = nil
Service._feedGui = nil
Service._feedLabel = nil

--- Resuelve un marcador por nombre en todo el workspace.
--- @param name string
--- @return BasePart?
local function findMarker(name: string): BasePart?
	local found = Workspace:FindFirstChild(name, true)
	if found and found:IsA("BasePart") then
		return found
	end
	return nil
end

--- Deriva el semitamano de la arena a partir del suelo, con respaldo.
local function resolveHalf()
	local floor = Workspace:FindFirstChild("PvPArena_Floor", true)
	if floor and floor:IsA("BasePart") then
		return { X = floor.Size.X * 0.5, Z = floor.Size.Z * 0.5 }
	end
	return { X = 33, Z = 23 }
end

--- Raiz del personaje de un jugador, o nil.
--- @param player Player
--- @return BasePart?
local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

--- Cuenta cuantos jugadores estan ahora mismo en cada bando.
--- @return number, number countA, countB
local function countTeams(): (number, number)
	local a, b = 0, 0
	for _, player in ipairs(Players:GetPlayers()) do
		local team = player:GetAttribute("PvpTeam")
		if team == "A" then
			a += 1
		elseif team == "B" then
			b += 1
		end
	end
	return a, b
end

--- Crea el marcador de kills y el killfeed sobre la arena (una sola vez).
---
--- El marcador es la RAZON DE COMPETIR: sin el, las kills se cuentan pero no se
--- ven, y el jugador no tiene a quien "superar". Se ancla al centro (`PvPCenter`)
--- con un BillboardGui, asi que se lee desde cualquier punto de la arena.
function Service._buildScoreboard()
	if Service._scoreGui then
		return
	end

	local center = Service._center

	if not center or not center:IsA("BasePart") then
		return
	end

	-- Una pieza invisible sobre el centro sostiene el BillboardGui. Se destruye
	-- en Destroy junto con el resto.
	local anchor = Instance.new("Part")
	anchor.Name = "PvpScoreboard"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Transparency = 1
	anchor.Position = center.Position + Vector3.new(0, 14, 0)
	anchor.Parent = Service._folder
	Service._scorePart = anchor

	local gui = Instance.new("BillboardGui")
	gui.Name = "PvpScoreGui"
	gui.Size = UDim2.fromScale(16, 8)
	gui.StudsOffset = Vector3.new(0, 8, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 200
	gui.Parent = anchor
	Service._scoreGui = gui

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	frame.BackgroundTransparency = 0.25
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.Parent = frame

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 22)
	title.BackgroundTransparency = 1
	title.Text = "MARCADOR PVP"
	title.TextColor3 = Color3.fromRGB(255, 210, 90)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 20
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = frame

	local label = Instance.new("TextLabel")
	label.Name = "Scores"
	label.Size = UDim2.new(1, 0, 0, 120)
	label.BackgroundTransparency = 1
	label.Text = "Sin kills aun"
	label.TextColor3 = Color3.fromRGB(235, 235, 245)
	label.Font = Enum.Font.Gotham
	label.TextSize = 18
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextWrapped = true
	label.Parent = frame
	Service._scoreLabel = label
end

--- Crea el killfeed (lineas de "X elimino a Y") sobre la arena.
---
--- Va aparte del marcador a proposito: el marcador responde "quien va
--- ganando", el killfeed "que acaba de pasar". Es el feedback inmediato que
--- hace que un enfrentamiento se SIENTA visto.
function Service._buildKillfeed()
	if Service._feedGui then
		return
	end

	local center = Service._center

	if not center or not center:IsA("BasePart") then
		return
	end

	local feedAnchor = Instance.new("Part")
	feedAnchor.Name = "PvpKillfeed"
	feedAnchor.Size = Vector3.new(0.2, 0.2, 0.2)
	feedAnchor.Anchored = true
	feedAnchor.CanCollide = false
	feedAnchor.Transparency = 1
	feedAnchor.Position = center.Position + Vector3.new(0, 24, 0)
	feedAnchor.Parent = Service._folder
	Service._feedPart = feedAnchor

	local feed = Instance.new("BillboardGui")
	feed.Name = "PvpFeedGui"
	feed.Size = UDim2.fromScale(14, 6)
	feed.StudsOffset = Vector3.new(0, 10, 0)
	feed.AlwaysOnTop = true
	feed.MaxDistance = 200
	feed.Parent = feedAnchor
	Service._feedGui = feed

	local feedFrame = Instance.new("Frame")
	feedFrame.Size = UDim2.fromScale(1, 1)
	feedFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 22)
	feedFrame.BackgroundTransparency = 0.4
	feedFrame.BorderSizePixel = 0
	feedFrame.Parent = feed

	local feedCorner = Instance.new("UICorner")
	feedCorner.CornerRadius = UDim.new(0, 8)
	feedCorner.Parent = feedFrame

	local feedPad = Instance.new("UIPadding")
	feedPad.PaddingTop = UDim.new(0, 6)
	feedPad.PaddingLeft = UDim.new(0, 8)
	feedPad.Parent = feedFrame

	local feedLabel = Instance.new("TextLabel")
	feedLabel.Name = "Feed"
	feedLabel.Size = UDim2.new(1, -16, 1, -12)
	feedLabel.BackgroundTransparency = 1
	feedLabel.Text = ""
	feedLabel.TextColor3 = Color3.fromRGB(255, 150, 150)
	feedLabel.Font = Enum.Font.Gotham
	feedLabel.TextSize = 16
	feedLabel.TextXAlignment = Enum.TextXAlignment.Left
	feedLabel.TextYAlignment = Enum.TextYAlignment.Bottom
	feedLabel.TextWrapped = true
	feedLabel.Parent = feedFrame
	Service._feedLabel = feedLabel
end

--- Refresca el texto del marcador con las kills actuales.
---
--- El formato lo decide `PvpRules.FormatScoreboard` (puro y probado): aqui solo
--- se recolectan los datos de los jugadores PRESENTES en la arena.
function Service._refreshScoreboard()
	if not Service._scoreLabel then
		return
	end

	local entries = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("PvpActive") == true then
			table.insert(entries, { Name = player.Name, Kills = Service._kills[player.UserId] or 0 })
		end
	end

	Service._scoreLabel.Text = PvpRules.FormatScoreboard(entries)
end

--- Registra una kill en el marcador y en el killfeed.
---
--- Lo llama el listener que `CombatService` emite: alli es la AUTORIDAD del
--- killer (atribucion y contabilidad). Aqui solo se PONE a la vista. Se filtra
--- por `PvpActive` para que una muerte en una ronda PvE no contamine la arena.
--- @param killer Player
--- @param victim Player
function Service._onKill(killer: Player, victim: Player)
	if not (killer and killer:GetAttribute("PvpActive") == true) then
		return
	end

	Service._kills[killer.UserId] = (Service._kills[killer.UserId] or 0) + 1
	Service._refreshScoreboard()

	if Service._feedLabel then
		Service._feedLabel.Text = PvpRules.FormatKillLine(killer.Name, victim.Name)
	end
end

--- Reinicia el marcador y las kills de la sesion (al empezar la partida).
function Service._resetScoreboard()
	Service._kills = {}
	if Service._scoreLabel then
		Service._scoreLabel.Text = "Sin kills aun"
	end
	if Service._feedLabel then
		Service._feedLabel.Text = ""
	end
end

--- Mete a un jugador en la arena: le asigna bando, lo teletransporta a su
--- spawn, lo cura y publica los atributos.
--- @param player Player
local function enterArena(player: Player)
	local countA, countB = countTeams()
	local team = PvpRules.AssignTeam(countA, countB)
	local spawn = if team == "B" then Service._spawnB else Service._spawnA

	local root = rootOf(player)
	if not root or not spawn then
		return
	end

	-- Lados opuestos de la linea central: la separacion posicional ES la
	-- proteccion inicial, no hace falta invulnerabilidad.
	root.CFrame = CFrame.new(spawn.Position + Vector3.new(0, 3, 0))

	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = humanoid.MaxHealth
	end

	player:SetAttribute("PvpTeam", team)
	player:SetAttribute("PvpActive", true)
	Logger.Info(("%s entra al PvP (equipo %s)"):format(player.Name, team))
end

--- Saca a un jugador del PvP: retira los atributos y bloquea la re-entrada.
--- @param player Player
local function leaveArena(player: Player)
	player:SetAttribute("PvpActive", nil)
	player:SetAttribute("PvpTeam", nil)
	Service._entryCooldown[player.UserId] = os.clock() + Service.EntryCooldown
	-- La kill del que sale deja de contar en el marcador: si se quedara, un
	-- jugador que abandonara la arena seguiria en la tabla de posiciones como
	-- un fantasma. La cuenta se reinicia si vuelve a entrar, que es lo justo.
	Service._kills[player.UserId] = nil
	Service._refreshScoreboard()
	Logger.Info(("%s sale del PvP"):format(player.Name))
end

--- Un barrido del vigilante.
local function sweep()
	for _, player in ipairs(Players:GetPlayers()) do
		local root = rootOf(player)
		if root then
			local pos = root.Position
			local inside = PvpRules.IsInsideArena(pos, Service._center.Position, Service._half)
			local active = player:GetAttribute("PvpActive") == true

			if active then
				-- Marcado y fuera de la caja: se acabo el PvP.
				if not inside then
					leaveArena(player)
				end
			else
				-- Sin marcar: puede entrar si pisa la puerta y no esta en
				-- cooldown de re-entrada.
				local cooldownUntil = Service._entryCooldown[player.UserId]
				local cooling = type(cooldownUntil) == "number" and os.clock() < cooldownUntil

				if not cooling and PvpRules.IsNear(pos, Service._entry.Position, Service.EntryRadius) then
					enterArena(player)
				end
			end
		end
	end
end

--- Bucle del vigilante.
function Service._watch()
	task.spawn(function()
		while Service._running do
			local ok, err = pcall(sweep)

			if not ok then
				-- Un vigilante que muere deja la arena muerta el resto de la
				-- sesion sin decir por que. Se registra y se corta.
				Logger.Error(("PvpService: el vigilante fallo: %s"):format(tostring(err)))
				Service._running = false
				break
			end

			task.wait(Service.WatchInterval)
		end
	end)
end

--- @param maid any?
--- @return boolean success
function Service.Init(maid: any?): boolean
	if Service.IsInitialized then
		return true
	end

	Service._maid = maid
	Service.IsInitialized = true
	Logger.Info("PvpService listo.")
	return true
end

--- @return boolean success
function Service.Start(): boolean
	if not Service.IsInitialized then
		Logger.Error("PvpService: Start sin Init")
		return false
	end

	Service._center = findMarker("PvPCenter")
	Service._spawnA = findMarker("PvPSpawn_A")
	Service._spawnB = findMarker("PvPSpawn_B")
	Service._entry = findMarker("PvPEntry")

	if not (Service._center and Service._spawnA and Service._spawnB and Service._entry) then
		-- La arena aun no esta generada: no es un fallo del servidor, es un
		-- mundo sin la plaza premium. Se avisa y el servicio queda inerte.
		Logger.Warn("PvpService: faltan marcadores de la arena PvP; modo inerte.")
		return true
	end

	Service._half = resolveHalf()
	Service._running = true

	-- El marcador y el killfeed se construyen aqui, una vez, cuando la arena
	-- existe. Se apoyan en `PvPCenter`, asi que solo tienen sentido con los
	-- marcadores presentes.
	Service._buildScoreboard()
	Service._buildKillfeed()
	Service._resetScoreboard()

	Service._watch()
	Logger.Info("PvpService arrancado (arena PvP activa).")
	return true
end

--- @return boolean success
function Service.Destroy(): boolean
	Service._running = false

	for _, player in ipairs(Players:GetPlayers()) do
		player:SetAttribute("PvpActive", nil)
		player:SetAttribute("PvpTeam", nil)
	end

	Service._entryCooldown = {}
	Service._kills = {}

	-- Las piezas que sostienen el marcador y el killfeed se destruyen con el
	-- servicio; si se quedaran, el BillboardGui seguiria flotando en el lobby.
	if Service._scorePart and Service._scorePart.Parent then
		Service._scorePart:Destroy()
	end
	if Service._feedPart and Service._feedPart.Parent then
		Service._feedPart:Destroy()
	end

	Service._scorePart = nil
	Service._scoreGui = nil
	Service._scoreLabel = nil
	Service._feedPart = nil
	Service._feedGui = nil
	Service._feedLabel = nil

	Service._center = nil
	Service._spawnA = nil
	Service._spawnB = nil
	Service._entry = nil
	return true
end

return Service

