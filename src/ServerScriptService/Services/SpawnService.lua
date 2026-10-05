--!strict
--[[
	SpawnService
	Sistema de aparicion del jugador (FASE 1).

	Responsabilidad en esta fase:
	- Descubrir los SpawnLocation disponibles en el mapa.
	- Elegir un punto de aparicion valido para cada jugador.
	- Evitar que dos jugadores aparezcan en el mismo punto.

	Por que "servidor decide": la posicion de aparicion nunca se
	toma del cliente. Se elige aqui, en el servidor, y el cliente solo
	la recibe.

	Los reapariciones tras muerte, el spawn por mundo y el teletransporte
	corresponden a las fases 2, 19 y 22.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONFIG = SHARED:WaitForChild("Config")
local UTILS = SHARED:WaitForChild("Utils")

local GameConfig = require(CONFIG:WaitForChild("GameConfig"))
local WorldBoundsRules = require(SHARED:WaitForChild("Libraries"):WaitForChild("WorldBoundsRules"))
local Logger = require(UTILS:WaitForChild("Logger"))

local Service = {}

Service.IsInitialized = false

-- Lista de SpawnLocation validos del mapa.
Service._spawnLocations = {}
-- Contador de rotacion para repartir jugadores entre puntos.
Service._cursor = 0
-- Maid recibido en Init (conexiones de Players).
local MaidRef = nil

-- Servicios inyectados por ServerMain (destino de reaparicion del mundo).
Service._roundService = nil
Service._matchService = nil

-- Caja LOGICA de cada mundo (terreno + margen de seguridad). Se mide en `Init`
-- sobre la geometria real del mapa, no sobre una constante escrita a mano: si
-- el generador mueve el mundo, el limite se mueve con el.
Service._bounds = {}

-- Instante en el que cada jugador salio del area jugable, o nil. Solo lo usa la
-- red de seguridad de `enforceFallAndBounds`.
--
-- El valor es `number?` y la clave `any` a proposito: `Player` es un tipo de
-- Roblox que el analizador de este proyecto no resuelve, y con `[Player]: number`
-- la tabla entera se le queda como "sin valor conocido" y rechaza la asignacion.
Service._outOfBoundsSince = {}

-- El tipo se anota de forma explicita en cada sitio donde se escribe. Sin el, el
-- analizador infiere la tabla como "sin valor" a partir de los `= nil` de
-- limpieza y rechaza despues cualquier `= os.clock()`. Es una limitacion del
-- analizador de este proyecto (no resuelve `Player` ni las definiciones de
-- Roblox), no un fallo de la regla, asi que se anota el tipo en vez de relajar
-- el codigo.
local function markOutOfBounds(player: Player, since: number)
	Service._outOfBoundsSince[player] = since
end

--- Busca los SpawnLocation existentes en el Workspace.
--- @return { Instance } spawnLocations
function Service.CollectSpawnLocations(): { Instance }
	local collected = {}

	local workspaceService = game:GetService("Workspace")
	local spawnFolder = workspaceService:FindFirstChild("SpawnLocations")

	if not spawnFolder then
		Logger.Warn("Workspace.SpawnLocations no existe; se usara el origen.")
		return collected
	end

	for _, instance in ipairs(spawnFolder:GetDescendants()) do
		if instance:IsA("SpawnLocation") then
			table.insert(collected, instance)
		end
	end

	return collected
end

--- Cantidad de puntos de aparicion disponibles.
--- @return number
function Service.GetSpawnLocationCount(): number
	return #Service._spawnLocations
end

--- Elige un punto de aparicion. El servidor decide siempre.
--- @param player Player?
--- @return Instance? spawnLocation nil si no hay ninguno
function Service.PickSpawnLocation(player: Player?): Instance?
	local total = #Service._spawnLocations

	if total == 0 then
		Logger.Debug("PickSpawnLocation: no hay SpawnLocation; se usara Vector3.zero")
		return nil
	end

	-- Rotacion determinista: reparte sin aleatoriedad ni carrera.
	Service._cursor = (Service._cursor % total) + 1
	local spawnLocation = Service._spawnLocations[Service._cursor]

	Logger.Debug(("spawn asignado a %s: %s"):format(
		player and player.Name or "?",
		spawnLocation.Name
	))

	return spawnLocation
end

--- Posicion de aparicion calculada para un jugador.
--- @param player Player?
--- @return Vector3
function Service.GetSpawnPosition(player: Player?): Vector3
	local spawnLocation = Service.PickSpawnLocation(player)

	if not spawnLocation then
		return Vector3.new(0, 10, 0)
	end

	-- Se suma un pequeno desplazamiento vertical para que el personaje
	-- no nazca incrustado en el suelo.
	return (spawnLocation :: SpawnLocation).Position + Vector3.new(0, 3, 0)
end

--- Inicializacion del servicio. Idempotente.
--- @param maid any?
--- @return boolean success
function Service.Init(maid: any?): boolean
	if Service.IsInitialized then
		return true
	end

	local ok, err = pcall(function()
		Service._spawnLocations = Service.CollectSpawnLocations()
		Service._cursor = 0
		-- La caja logica de cada mundo se mide al arrancar. Sin ella no hay
		-- forma de distinguir "fuera del area jugable" de "en el lobby", y la
		-- red de seguridad del borde no tendria sobre que trabajar.
		Service.CollectWorldBounds()
	end)

	if not ok then
		Logger.Error("SpawnService Init fallo: " .. tostring(err))
		return false
	end

	-- Sin ningun SpawnLocation el personaje aparece en el origen y cae al
	-- vacio: es el fallo mas grave posible, asi que NO es un aviso sino
	-- un fallo de inicializacion. El registro lo vera en el output.
	if #Service._spawnLocations == 0 then
		Logger.Error(
			"SpawnService: no hay SpawnLocation en Workspace.SpawnLocations. "
				.. "El personaje caera al vacio. Ejecuta `node tools/generate-project.js` y recompila."
		)
		return false
	end

	Service.IsInitialized = true
	Logger.Info(("SpawnService: %d puntos de aparicion encontrados"):format(
		Service.GetSpawnLocationCount()
	))

	return true
end

-- Destino de REAPARICION de un jugador que ha muerto en un mundo.
--
-- P0 DEFINITIVO. Esta funcion NO se usa para "rescatar" de una caida: la caida
-- MATA y el respawn lo hace el motor. Se conserva el concepto porque responde a
-- otra pregunta legitima: si un jugador muere dentro de un mundo, ¿donde debe
-- reaparecer? La respuesta es el `SpawnPoint` de ESE mundo y no el del lobby,
-- porque reaparecer 1300 studs al lado del portal del que acaba de salir deja
-- al jugador en un sitio en el que no ha estado nunca, y romperia la regla de
-- que morir no bloquea el juego ni la de que el mundo es reentrable.
--
-- @param player Player
-- @return Vector3? target nil si no hay ningun destino valido
function Service.GetWorldRespawnPosition(player: Player): Vector3?
	local worldId = Service.GetPlayerWorldId(player)

	if worldId then
		local location = Service.FindWorldSpawnLocation(worldId)
		if location then
			return (location :: SpawnLocation).Position + Vector3.new(0, 4, 0)
		end
	end

	local spawnLocation = Service.PickSpawnLocation(player)
	if not spawnLocation then
		return nil
	end

	return (spawnLocation :: SpawnLocation).Position + Vector3.new(0, 4, 0)
end

--- `SpawnPoint` de un mundo concreto, o nil si el mapa no lo trae.
--- @param worldId string
--- @return SpawnLocation?
function Service.FindWorldSpawnLocation(worldId: string): SpawnLocation?
	local worlds = game:GetService("Workspace"):FindFirstChild("Worlds")
	if not worlds then
		return nil
	end

	local worldFolder = worlds:FindFirstChild(worldId)
	if not worldFolder then
		return nil
	end

	local location = worldFolder:FindFirstChild("SpawnPoint_" .. worldId)
	if location and location:IsA("SpawnLocation") then
		return location :: SpawnLocation
	end

	return nil
end

--- Registra la caja LOGICA de un mundo a partir de la caja de su terreno.
--
-- El margen de `WorldBoundsRules` es lo que hace que el limite sea una red y no
-- una trampa: sin el, cruzar el ultimo metro de terreno contaria como salirse
-- del mundo.
--
-- @param worldId string
-- @param box {minX:number, maxX:number, minZ:number, maxZ:number}
function Service.RegisterWorldBounds(
	worldId: string,
	box: { minX: number, maxX: number, minZ: number, maxZ: number }
)
	Service._bounds[worldId] = WorldBoundsRules.WithMargin(box)
end

--- Caja logica de un mundo, o nil si no se ha registrado.
-- @param worldId string
-- @return {minX:number, maxX:number, minZ:number, maxZ:number}?
function Service.GetWorldBounds(worldId: string): { minX: number, maxX: number, minZ: number, maxZ: number }?
	return Service._bounds[worldId]
end
--- Mide el terreno de cada mundo y registra su caja logica.
--
-- Se recorren las piezas COLISIONABLES de `Workspace.Worlds/<Id>`: la decoracion
-- no cuenta, porque el jugador la atraviesa y un limite calculado sobre
-- decoracion dejaria el limite real mas cerca de lo que es.
--
-- @return number worlds registrados
function Service.CollectWorldBounds(): number
	Service._bounds = {}

	local worlds = game:GetService("Workspace"):FindFirstChild("Worlds")
	if not worlds then
		Logger.Warn("SpawnService: Workspace.Worlds no existe; no hay limites de mundo.")
		return 0
	end

	local count = 0
	for _, worldFolder in worlds:GetChildren() do
		local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
		local seen = false

		for _, piece in worldFolder:GetDescendants() do
			if not piece:IsA("BasePart") then
				continue
			end
			if piece.CanCollide ~= true then
				continue
			end

			-- La caja se mide con el `CFrame` y no con `Size`: una losa girada
			-- ocupa mas superficie de la que mide sin rotar, y un limite
			-- calculado con el tamaño en crudo deja fuera terreno real.
			local part = piece :: BasePart
			local half = part.Size / 2
			local cf = part.CFrame
			local corner0 = cf * Vector3.new(-half.X, -half.Y, -half.Z)
			local corner1 = cf * Vector3.new(half.X, half.Y, half.Z)

			minX = math.min(minX, corner0.X, corner1.X)
			maxX = math.max(maxX, corner0.X, corner1.X)
			minZ = math.min(minZ, corner0.Z, corner1.Z)
			maxZ = math.max(maxZ, corner0.Z, corner1.Z)
			seen = true
		end

		if seen then
			Service.RegisterWorldBounds(worldFolder.Name, {
				minX = minX,
				maxX = maxX,
				minZ = minZ,
				maxZ = maxZ,
			})
			count += 1
		end
	end

	return count
end

--- Mundo en el que esta un jugador.
---
--- POR QUE HACE FALTA EL SEGUNDO CAMINO
--- --------------------------------------
--- Deducirlo de la POSICION es lo correcto mientras el jugador esta vivo y dentro
--- del terreno, y por eso es el primer camino. Pero al REAPARECER el personaje ya
--- ha nacido en el spawn por defecto, o sea en el lobby: el mundo se ha perdido y
--- el jugador caeria al vacio, reapareceria 1300 studs al lado del portal y
--- tendria que volver a entrar a mano. Eso rompe el flujo que pide el enunciado
--- (borde -> caida -> muerte -> respawn -> reentrada) justo en su ultimo paso.
---
--- Por eso, cuando la posicion no dice nada, se consulta lo que el SERVIDOR
--- publico en `MatchService.MovePlayer` (ver `GetRememberedWorldId`).
--
-- @param player Player
-- @return string? worldId nil si esta fuera de todo mundo
function Service.GetPlayerWorldId(player: Player): string?
	local character = player.Character
	if not character then
		return Service.GetRememberedWorldId(player)
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return Service.GetRememberedWorldId(player)
	end

	local position = (rootPart :: BasePart).Position
	local best = nil
	local bestArea = math.huge

	for worldId, bounds in Service._bounds do
		if WorldBoundsRules.Classify(bounds, position) == WorldBoundsRules.Zone.Playable then
			local area = bounds.maxX - bounds.minX
			if area < bestArea then
				bestArea = area
				best = worldId
			end
		end
	end

	if best then
		return best
	end

	-- El lobby esta en el origen, fuera de toda caja: si ahi esta el jugador y el
	-- ultimo destino fue un mundo, NO se recuerda. Acaba de volver al lobby y su
	-- reaparicion tiene que ser en el lobby.
	local remembered = Service.GetRememberedWorldId(player)
	if remembered and Service._bounds[remembered] then
		return remembered
	end

	return nil
end

--- Ultimo mundo al que el SERVIDOR movio a un jugador, o nil.
---
--- Se lee el atributo que escribe `MatchService.MovePlayer`, que es el unico punto
--- por el que pasa cualquier traslado: el del portal, el de entrada a la arena y
--- el de vuelta al lobby.
---
--- POR QUE ES SEGURO
--- ------------------
--- Lo escribe el servidor y no concede nada: que el cliente lo cambie en su
--- pantalla no altera la copia del servidor. Y `GetPlayerWorldId` exige ademas que
--- el mundo este REGISTRADO en `_bounds`, de modo que un valor inventado no abre
--- ningun destino nuevo: a lo sumo devuelve `nil`, que es lo mismo que no saber
--- nada.
---
--- El lobby devuelve `nil` a proposito: quedarse "en el lobby" no es un destino
--- de reaparicion de mundo, y devolverlo haria que un jugador que vuelve al lobby
--- reapareciera dentro del bosque.
---
--- @param player Player
--- @return string? worldId
function Service.GetRememberedWorldId(player: Player): string?
	local worldId = player:GetAttribute("World")

	if type(worldId) ~= "string" or worldId == "" or worldId == "Lobby" then
		return nil
	end

	return worldId
end
--- Aplica las DOS reglas del limite: CAIDA y FUERA DE LIMITES.
--
-- SON DOS REGLAS DISTINTAS, Y POR QUE
-- -----------------------------------
-- 1. CAIDA (`position.Y < FallDeathY`): el jugador ha dejado el suelo y esta
--    bajando. La respuesta es MUERTE, y la ejecuta el motor con
--    `Humanoid.Health = 0`, de modo que se disparan `Died`, `CombatService` y el
--    respawn normal. El jugador reaparece y puede volver a usar el portal.
--
-- 2. FUERA DE LIMITES (`OUT_OF_BOUNDS`): el jugador esta en una posicion que no
--    pertenece a ninguna zona segura. Aqui NO se hace nada: no se
--    teletransporta y no se mata de inmediato. Se marca y se cuenta cuanto lleva
--    fuera. Lo unico que puede pasar es que, pasado el margen de gracia, se le
--    aplique la regla 1. Ese margen existe para el caso en que el suelo
--    desapareciera bajo sus pies sin que hubiera caida: si no, el jugador
--    quedaria flotando fuera del mapa sin poder volver nunca.
--
-- P0. Antes esta funcion se llamaba `rescueFromVoid` y hacia lo contrario:
-- `character:PivotTo(...)` al destino de rescate. Eso convertia la caida en un
-- teletransporte, saltaba el ciclo de muerte y de reaparicion, y devolvia al
-- jugador al lobby estando en medio de una ronda.
--
-- @param player Player
function Service.enforceFallAndBounds(player: Player)
	local character = player.Character
	if not character then
		Service._outOfBoundsSince[player] = nil
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not (rootPart :: BasePart):IsA("BasePart") then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local position = (rootPart :: BasePart).Position

	-- REGLA 1: CAIDA. La valida el servidor; el cliente no participa.
	if position.Y < GameConfig.FallDeathY then
		Service._outOfBoundsSince[player] = nil
		player:SetAttribute("OutOfBounds", nil)
		Logger.Info(("%s ha caido al vacio (y=%.1f)"):format(player.Name, position.Y))
		humanoid.Health = 0
		return
	end

	-- REGLA 2: LIMITE LOGICO. Marca, no accion.
	--
	-- El atributo `OutOfBounds` es lo que permite a la QA (y al HUD) VER que el
	-- jugador esta fuera sin depender de un teletransporte: se marca al entrar y
	-- se limpia al volver.
	local inSafePlace = Service.GetPlayerWorldId(player) ~= nil
		or position.Y > GameConfig.OutOfBoundsY

	if inSafePlace then
		Service._outOfBoundsSince[player] = nil
		player:SetAttribute("OutOfBounds", false)
		return
	end

	local since = Service._outOfBoundsSince[player]
	if since == nil then
		markOutOfBounds(player, os.clock())
		player:SetAttribute("OutOfBounds", true)
		Logger.Info(("%s ha salido del area jugable; puede volver andando"):format(player.Name))
		return
	end

	if (os.clock() - since) < GameConfig.OutOfBoundsGraceSeconds then
		return
	end

	Service._outOfBoundsSince[player] = nil
	Logger.Warn(("%s lleva %.0f s fuera del area jugable sin caer; se le mata"):format(
		player.Name,
		GameConfig.OutOfBoundsGraceSeconds
	))
	humanoid.Health = 0
end

--- Inyecta los servicios necesarios para el rescate.
--- @param roundService any
--- @param matchService any
function Service.SetDependencies(roundService: any, matchService: any)
	Service._roundService = roundService
	Service._matchService = matchService
end

--- @return boolean success
function Service.Start(): boolean
	if not Service.IsInitialized then
		Logger.Error("SpawnService: Start sin Init")
		return false
	end

	if MaidRef then
		-- Vigilancia de CAIDA y de LIMITE LOGICO. Se comprueba con un intervalo
		-- corto y no por evento porque el vacio no genera eventos.
		--
		-- P0: esto ya no "rescata" a nadie. Antes teletransportaba al jugador de
		-- vuelta al spawn cuando pasaba por debajo del mapa; ahora aplica las dos
		-- reglas del limite: la CAIDA mata (y el respawn lo hace el motor) y salir
		-- del area jugable solo se MARCA, con un margen de gracia para poder
		-- volver andando. Ver `enforceFallAndBounds`.
		MaidRef:Add(task.spawn(function()
			while Service.IsInitialized do
				task.wait(GameConfig.FallCheckInterval)

				for _, player in ipairs(Players:GetPlayers()) do
					local ok, err = pcall(Service.enforceFallAndBounds, player)
					if not ok then
						Logger.Error(("caida de %s fallo: %s"):format(player.Name, tostring(err)))
					end
				end
			end
		end))
	end

	Logger.Info("SpawnService listo.")
	return true
end

--- @return boolean success
function Service.Destroy(): boolean
	Service.IsInitialized = false
	Service._spawnLocations = {}
	Service._cursor = 0
	Service._roundService = nil
	Service._matchService = nil
	Service._bounds = {}
	Service._outOfBoundsSince = {}
	MaidRef = nil
	return true
end

return Service