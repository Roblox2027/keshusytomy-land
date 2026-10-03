--!strict
--[[
	BombService
	Autoridad de creacion, colocacion, cuenta regresiva, cadena y
	explosion de bombas (FASES 4 y 5).

	El cliente NUNCA coloca una bomba por su cuenta: pide una posicion y
	este servicio valida en el servidor:

		1. Que la ronda este en curso.
		2. Que el jugador este vivo y tenga personaje.
		3. Que la posicion sea finita y este DENTRO de la arena.
		4. Que el jugador no este en cooldown.
		5. Que el jugador no supere su tope de bombas.

	El radio, el dano y la mecha salen SIEMPRE de GameConfig. Un cliente
	que manipule su payload no puede cambiar ninguno.

	Cadena de reaccion:
	Cuando una bomba explota, las bombas cercanas (dentro de
	`ChainReactionRadius`) explotan a su vez con un retardo proporcional
	a la distancia. El limite `MaxChainDepth` evita que un jugador que
	llene la arena genere miles de detonaciones.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
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

-- Servicios inyectados por ServerMain para evitar dependencias circulares.
Service._roundService = nil
Service._explosionService = nil

-- QuestService: receptor del progreso de misiones (bombas colocadas).
--
-- Es OPCIONAL a proposito: sin el, las bombas se colocan, explotan y danan
-- exactamente igual, y lo UNICO que se pierde es el progreso de las
-- misiones. El sistema de misiones no puede ser un punto unico de fallo
-- del combate.
Service._questService = nil

-- UserId -> momento (os.clock) en que puede volver a colocar.
Service._cooldowns = {}
-- BombId -> { Part: Part, OwnerUserId: number?, Position: Vector3, Depth: number }
Service._activeBombs = {}
Service._nextBombId = 0
-- Carpeta donde se crean las bombas visibles.
Service._bombFolder = nil

-- Maid propio, inyectado por `ServiceRegistry` en `Init`. Se guarda para
-- poder conectar `Players.PlayerAdded` y que esa conexion se limpie sola
-- en `Destroy`. Sin guardarlo, cualquier conexion creada aqui se
-- sobreviviria al apagado del servicio.
Service._maid = nil

-- Limites del mapa, learned del suelo de la arena. Se calculan al
-- arrancar para no escribir numeros magicos ni depender del generador.
Service._arenaBounds = nil

-- Rectangulo de arena POR MUNDO (worldId -> bounds).
--
-- BUG CORREGIDO (medido en PLAY): existia un unico `_arenaBounds` que cubria
-- solo el primer mundo. Las bombas quedaban imposibles en los otros cuatro.
-- Ver la nota larga en `IsInsideArena`.
Service._arenaBoundsByWorld = {}

-- Mundo al que se atribuye `_arenaBounds`, y el que se usa cuando el jugador no
-- tiene un `World` conocido.
Service._defaultArenaWorld = nil

-- Servicio de mundos. Se inyecta entre `Init` y `Start` (ver
-- `SetWorldService`). Solo se usa para saber cual es el mundo por defecto.
Service._worldService = nil

--- Rectangulo que ocupa la arena, en el plano XZ.
---
--- Sin esto, un cliente podria colocar una bomba en (999999, 0, 0):
-- pasaria la distancia al personaje si el personaje estuviera ahi, y
-- explotaria fuera del mapa.
--- @param bounds { MinX: number, MaxX: number, MinZ: number, MaxZ: number }
--- @return Vector3 centro
function Service.SetArenaBounds(bounds: { MinX: number, MaxX: number, MinZ: number, MaxZ: number }): Vector3
	Service._arenaBounds = bounds
	return Vector3.new((bounds.MinX + bounds.MaxX) / 2, 0, (bounds.MinZ + bounds.MaxZ) / 2)
end

--- Registra los limites de UNA arena concreta.
---
--- Es la puerta que usa `detectArenaBounds` para poblar `_arenaBoundsByWorld`.
--- Se separa de `SetArenaBounds` porque ese setter significa "la arena por
--- defecto" y mezclar los dos roles fue justo lo que escondia el bug.
--- @param worldId string
--- @param bounds { MinX: number, MaxX: number, MinZ: number, MaxZ: number }
function Service.SetArenaBoundsForWorld(
	worldId: string,
	bounds: { MinX: number, MaxX: number, MinZ: number, MaxZ: number }
)
	Service._arenaBoundsByWorld[worldId] = bounds
end

--- Limites registrados de una arena, o nil si ese mundo no tiene suelo.
--- @param worldId string?
--- @return any?
function Service.GetArenaBounds(worldId: string?)
	local bounds = Service._arenaBoundsByWorld[worldId or Service._defaultArenaWorld or ""]
	return bounds or Service._arenaBounds
end

--- Cuenta las arenas con limites registrados. Solo para el informe de arranque.
--- @param byWorld { [string]: any }
--- @return number
local function countBounds(byWorld: { [string]: any }): number
	local n = 0
	for _ in pairs(byWorld) do
		n += 1
	end
	return n
end

--- Inyecta los servicios de los que depende BombService.
---
--- AUDITORIA (P0): este setter NO existia. `ServerMain.wireDependencies`
--- llama `BombService.SetDependencies(round, explosion)` y el metodo no
--- estaba definido, asi que el arranque reventaba en runtime con
--- "attempt to call a nil value" (ServerMain:170) DESPUES de que los
--- nueve servicios se hubieran inicializado. El juego se quedaba a
--- medio arrancar: sin rondas, sin explosiones y sin bombas.
---
--- El servicio ya declaraba `_roundService` y `_explosionService`, ya
--- los consultaba en `TryPlaceBomb` y ya rechazaba `Start` si faltaban
--- (lineas 490 y 494): solo faltaba la puerta de entrada. Se sigue la
--- misma convencion que `SpawnService.SetDependencies`.
---
--- @param roundService any decide si se puede jugar (IsPlaying)
--- @param explosionService any detona la bomba cuando vence la mecha
function Service.SetDependencies(roundService: any, explosionService: any)
	Service._roundService = roundService
	Service._explosionService = explosionService
end

--- Inyecta el registro de mundos.
---
--- Se hace APARTE de `SetDependencies` a proposito: los limites de arena se
--- detectan en `Init`, que corre ANTES de que `ServerMain` inyecte nada. Asi
--- que en `Init` todavia no se sabe cual es el mundo por defecto y se deja
--- `_defaultArenaWorld` sin fijar; `Start` lo resuelve aqui, ya con las
--- dependencias puestas.
---
--- Sin este paso el rectangulo por defecto caia en "el primer nombre de la
--- tabla", que no tiene por que ser el mundo por defecto de `WorldService`.
--- @param worldService any
function Service.SetWorldService(worldService: any)
	Service._worldService = worldService
end

--- Conecta el receptor de progreso de misiones.
---
--- Es OPCIONAL: sin el, las bombas se colocan igual y solo las misiones que
--- cuentan bombas no avanzan.
--- @param questService any?
function Service.SetQuestService(questService: any)
	Service._questService = questService
end

--- Indica si una posicion cae dentro de la arena del mundo indicado.
---
--- BUG CORREGIDO (medido en PLAY): antes solo existia UN rectangulo,
--- `Service._arenaBounds`, y `detectArenaBounds` devolvia el `ArenaFloor` del
--- PRIMER mundo que encontraba en `Workspace.Worlds` (Forest, siempre el
--- primero). Consecuencia medida en los cinco mundos:
---
---   Forest (500, 0, 0)    -> dentro   -> la bomba se colocaba
---   Desert (-400, 400)    -> FUERA    -> "fuera de la arena"
---   Ice    (400, 400)     -> FUERA    -> "fuera de la arena"
---   Volcano(-400, -400)   -> FUERA    -> "fuera de la arena"
---   Cyber  (400, -400)    -> FUERA    -> "fuera de la arena"
---
--- Es decir: la bomba, que es el CORAZON del juego, solo funcionaba en uno de
--- los cinco mundos. Cuatro portales de cinco llevaban a una arena donde el
--- jugador no podia hacer su unica accion.
---
--- Ahora hay un rectangulo POR MUNDO y la comprobacion usa el mundo real del
--- jugador, que el servidor publica en el atributo `World`. Un jugador sin
--- mundo conocido se mide contra el rectangulo del mundo por defecto, que es
--- lo que teniamos antes.
---
--- @param position Vector3
--- @param worldId string? id del mundo; nil usa el mundo por defecto
--- @return boolean inside
function Service.IsInsideArena(position: Vector3, worldId: string?): boolean
	local bounds = Service._arenaBoundsByWorld[worldId or Service._defaultArenaWorld]
		or Service._arenaBounds

	-- Sin limites conocidos se acepta: el mapa puede no tener suelo de
	-- arena y el juego debe seguir siendo jugable.
	if not bounds then
		return true
	end

	return position.X >= bounds.MinX
		and position.X <= bounds.MaxX
		and position.Z >= bounds.MinZ
		and position.Z <= bounds.MaxZ
end

--- Valida que las componentes del payload sean utilizables.
--- @param position any
--- @return boolean valid
--- @return string? reason
local function isValidPosition(position: any): (boolean, string?)
	if typeof(position) ~= "Vector3" then
		return false, "no es Vector3"
	end

	return CombatMath.ValidatePosition(position.X, position.Y, position.Z)
end


--- Publica la cantidad de bombas vivas de un jugador.
---
--- BUG CORREGIDO (medido con probe-hud en PLAY): `UIController` mira el
--- atributo `Bombs` para pintar la fila BOMBAS del HUD, pero NINGUN punto del
--- servidor lo escribia. El atributo quedaba en `nil` para siempre y la fila
--- mostrar siempre "*", que es el marcador de "el servidor no publico esto".
--- El panel era, por tanto, informacion muerta: podia leerse bien y no
--- cambiar nunca.
---
--- Se publica DESDE aqui, que es quien tiene la verdad (`_activeBombs`), y no
--- desde el handler del remoto: si se publicara solo al recibir `Place`,
--- la cifra se quedaria congelada en 1 al detonar, porque la bomba desaparece
--- por `task.delay` y no por el remoto.
---
--- Publicar el 0 al entrar y al vaciar la arena es lo que hace que el HUD
--- diga la verdad tambien cuando el jugador no tiene ninguna bomba, en vez de
--- quedarse en el ultimo valor conocido.
---
--- @param userId number?
local function publishBombCount(userId: number?)
	if type(userId) ~= "number" then
		return
	end

	local player = Players:GetPlayerByUserId(userId)

	if not player then
		return
	end

	player:SetAttribute("Bombs", Service.GetPlayerBombCount(userId))
end

--- Publica la cuenta de bombas de todos los jugadores conectados.
local function publishAllBombCounts()
	for _, player in ipairs(Players:GetPlayers()) do
		publishBombCount(player.UserId)
	end
end

--- Detona una bomba concreta y programa la cadena de reaccion.
---
--- @param bombId number
--- @param depth number profundidad en la cadena (0 = explosion original)
local function detonateBomb(bombId: number, depth: number)
	local record = Service._activeBombs[bombId]

	if not record then
		return
	end

	local part = record.Part
	local position = record.Position
	local ownerId = record.OwnerUserId

	Logger.Debug(("[BOMB] detonate id=%d en (%.0f, %.0f, %.0f) por %s"):format(
		bombId,
		position.X,
		position.Y,
		position.Z,
		tostring(ownerId)
	))

	-- Se borra ANTES de resolver la explosion: si la cadena vuelve a
	-- mirar esta bomba, ya no la encontrara y no habra recursion.
	Service._activeBombs[bombId] = nil

	-- La cuenta del HUD baja YA, no cuando termine la cadena: el jugador
	-- ve su bomba desaparecer en el momento en que detona.
	publishBombCount(ownerId)

	if part and part.Parent then
		part:Destroy()
	end

	-- El MODELO entero se destruye aqui, no solo la raiz: sin esto la tapa,
	-- el fusible, el aro de peligro y el cartel de la mecha se quedan en
	-- pantalla flotando despues de la explosion.
	destroyBombVisual(record)

	if Service._explosionService then
		Service._explosionService.Detonate(
			position,
			GameConfig.DefaultBombRadius,
			ownerId,
			record.World
		)
	end

	-- La cadena se limita en profundidad: sin este tope, un jugador que
	-- llene la arena de bombas genera miles de detonaciones.
	if depth >= GameConfig.MaxChainDepth then
		return
	end

	local entries = {}

	for id, other in pairs(Service._activeBombs) do
		-- Una bomba ya alcanzada por la cadena no vuelve a encolarse:
		-- su Depth actua como marca de "visitada".
		if other.Depth < depth + 1 then
			table.insert(entries, {
				X = other.Position.X,
				Z = other.Position.Z,
				Id = id,
			})
		end
	end

	local chain = CombatMath.BuildChain(
		entries,
		position.X,
		position.Z,
		GameConfig.ChainReactionRadius,
		GameConfig.ChainReactionDelayPerStud
	)

	if #chain > 0 then
		Logger.Debug(("cadena desde la bomba %d: %d eslabones"):format(bombId, #chain))
	end

	for _, link in ipairs(chain) do
		local nextId = link.Id
		local nextDepth = depth + 1
		local nextRecord = Service._activeBombs[nextId]

		if nextRecord then
			nextRecord.Depth = nextDepth

			-- El retardo se aplica con `task.delay`, no con un bucle de
			-- espera: el hilo de la bomba original queda libre.
			task.delay(link.Delay, function()
				detonateBomb(nextId, nextDepth)
			end)
		end
	end
end

--- Escala TODAS las partes visibles de una bomba.
---
--- Se escala el conjunto, no solo el cuerpo: si solo creciese la esfera, la
--- tapa y el fusible se quedarian en su sitio y la bomba pareceria partirse
--- en dos a mitad de la animacion.
--- @param model Model
--- @param factor number
local function setBombScale(model: Model, factor: number)
	local base = VisualKit.BOMB

	for _, part in ipairs(model:GetChildren()) do
		if part:IsA("BasePart") and part.Name ~= "Root" and part.Name ~= "RadiusIndicator" then
			if part.Name == "BombBody" then
				part.Size = Vector3.new(base.BodySize, base.BodySize, base.BodySize) * factor
			elseif part.Name == "BombBand" then
				part.Size = Vector3.new(base.BodySize * 1.03, 0.5, base.BodySize * 1.03) * factor
			elseif part.Name == "BombTop" then
				part.Size = base.TopSize * factor
			elseif part.Name == "Fuse" then
				part.Size = base.FuseSize * factor
			elseif part.Name == "FuseGlow" then
				part.Size = base.TipSize * factor
			end
		end
	end
end

--- Destruye la bomba VISUAL de un registro, si sigue viva.
--- @param record table?
local function destroyBombVisual(record: { [string]: any }?)
	if not record then
		return
	end

	-- Antes solo se destruia `Part`. Con un `Model` eso dejaba vivos la tapa,
	-- el fusible, el aro de peligro y el cartel: la bomba "explotaba" pero
	-- seguia en pantalla.
	if record.Model and record.Model.Parent then
		record.Model:Destroy()
	elseif record.Part and record.Part.Parent then
		record.Part:Destroy()
	end
end

--- Crea la bomba fisica y programa su cuenta regresiva en el servidor.
--- @param ownerId number?
--- @param position Vector3
--- @param worldId string? mundo del dueno: decide la PIEL de la bomba
--- @return number bombId
local function spawnBomb(ownerId: number?, position: Vector3, worldId: string?): number
	local bomb = VisualKit.BuildBomb(worldId, position, GameConfig.DefaultBombRadius)

	if not bomb then
		-- Sin modelo NO hay bomba. Antes se creaba una `Part` minima y el
		-- juego continuaba con algo invisible; ahora el fallo es explicito.
		Logger.Error("BombService: no se pudo construir el modelo de la bomba.")
		return 0
	end

	Service._nextBombId += 1
	local bombId = Service._nextBombId
	bomb.Name = ("Bomb_%d"):format(bombId)
	bomb:SetAttribute("BombId", bombId)
	bomb:SetAttribute("OwnerUserId", ownerId)
	bomb:SetAttribute("World", worldId)

	local root = bomb.PrimaryPart

	if not root then
		Logger.Error("BombService: el modelo de bomba no tiene PrimaryPart.")
		bomb:Destroy()
		return 0
	end

	-- `Parent =` y NO `AddChild`.
	--
	-- ERROR REAL en runtime (FASE 2.1), reproducido en Studio:
	--     ERROR: handler BombAction.Place fallo:
	--            AddChild is not a valid member of Folder "Workspace.Bombs"
	--
	-- En esta version de Studio `AddChild` no esta disponible sobre las
	-- instancias creadas desde codigo. Medido, no supuesto: `Parent =` si
	-- funciona y produce exactamente el mismo arbol.
	bomb.Parent = Service._bombFolder
	Service._activeBombs[bombId] = {
		Part = root,
		Model = bomb,
		OwnerUserId = ownerId,
		Position = position,
		World = worldId,
		Depth = 0,
	}

	-- El HUD sube aqui, en el servidor, que es quien decide si la bomba
	-- existe. El cliente no anuncia su propia bomba: solo la pide.
	publishBombCount(ownerId)

	Logger.Debug(("bomba %d colocada en (%.0f, %.0f, %.0f) por %s"):format(
		bombId,
		position.X,
		position.Y,
		position.Z,
		tostring(ownerId)
	))

	-- APARICION: escala 0 -> 1 con rebote.
	--
	-- Antes la bomba "aparecia" ya estate y luego CRECIA durante la mecha.
	-- Eso no es una animacion de colocacion: es una esfera que engorda, y el
	-- jugador no lee un rebote como "acabas de poner una bomba".
	setBombScale(bomb, 0.05)

	task.spawn(function()
		for _, step in ipairs({ 0.45, 0.75, 1.12, 1 }) do
			task.wait(0.06)

			if bomb.Parent then
				setBombScale(bomb, step)
			end
		end
	end)

	-- MECHA VISIBLE: el cartel sobre la bomba baja de 3 a 0 y el fusible
	-- acelera. En el ultimo segundo la bomba parpadea: el jugador tiene que
	-- entender "TENGO QUE SALIR DE AQUI" sin leer nada.
	task.spawn(function()
		local timer = bomb:FindFirstChild("Timer", true)
		local labelText = if timer then timer:FindFirstChild("Label") else nil
		local sparks = bomb:FindFirstChild("Particles", true)
		local ring = bomb:FindFirstChild("RadiusIndicator", true)
		local glow = bomb:FindFirstChild("FuseGlow", true)
		local light = bomb:FindFirstChild("FuseLight", true)

		local elapsed = 0
		local total = GameConfig.DefaultBombFuseTime
		local step = 0.1

		while elapsed < total do
			if not bomb.Parent then
				return
			end

			task.wait(step)
			elapsed += step

			local remaining = math.max(0, total - elapsed)

			if labelText and labelText:IsA("TextLabel") then
				labelText.Text = tostring(math.ceil(remaining))
			end

			bomb:SetAttribute("FuseRemaining", remaining)

			-- Aviso del ultimo segundo: parpadeo rojo, cartel en rojo y mas
			-- chispas. Es la unica vez que la bomba grita, y por eso se lee.
			if remaining <= 1 then
				local on = math.floor(elapsed * 8) % 2 == 0
				local tint = if on then Color3.fromRGB(255, 70, 70) else Color3.fromRGB(255, 240, 200)

				if glow and glow:IsA("BasePart") then
					glow.Color = tint
				end

				if light and light:IsA("PointLight") then
					light.Brightness = if on then 6 else 1.5
					light.Color = tint
				end

				if labelText and labelText:IsA("TextLabel") then
					labelText.TextColor3 = tint
					labelText.Text = "!"
				end
			end

			-- El numero de chispas se decide en una variable y no en el
			-- argumento: `Emit(if ... then ... else ...)` es valido en Luau,
			-- pero es mas facil de leer aqui y no deja la decision escondida
			-- dentro de la llamada.
			local sparkCount = if remaining <= 1 then 8 else 2

			if sparks and sparks:IsA("ParticleEmitter") then
				sparks:Emit(sparkCount)
			end

			-- El aro de peligro se marca mas conforme se agota la mecha: la
			-- zona sigue siendo la MISMA, pero deja de ser decoracion pasiva.
			if ring and ring:IsA("BasePart") then
				ring.Transparency = if remaining <= 1 then 0.25 else 0.55
			end
		end
	end)

	-- La cuenta regresiva la lleva el SERVIDOR. El cliente solo ve la
	-- bomba porque se crea aqui, no porque el la haya creado.
	task.delay(GameConfig.DefaultBombFuseTime, function()
		Logger.Debug(("[BOMB] fuse agotada, detona la bomba %d"):format(bombId))
		detonateBomb(bombId, 0)
	end)

	return bombId
end

--- Numero de bombas vivas de un jugador.
--- @param userId number
--- @return number
function Service.GetPlayerBombCount(userId: number): number
	local count = 0

	for _, record in pairs(Service._activeBombs) do
		if record.OwnerUserId == userId then
			count += 1
		end
	end

	return count
end

--- Valida y coloca una bomba solicitada por un jugador.
---
--- @param player Player
--- @param position any posicion pedida por el cliente
--- @return boolean placed
--- @return string? reason motivo del rechazo
function Service.TryPlaceBomb(player: Player, position: any): (boolean, string?)
	-- Traza del camino de la bomba. Solo con DEBUG: asi se puede ver en
	-- el Output si el request LLEGA, si pasa la VALIDACION y si la bomba
	-- se CREO, sin tener que instrumentar el motor a mano.
	Logger.Debug(("[BOMB] request de %s en (%.1f, %.1f, %.1f)"):format(
		player and player.Name or "?",
		type(position) == "Vector3" and position.X or 0,
		type(position) == "Vector3" and position.Y or 0,
		type(position) == "Vector3" and position.Z or 0
	))

	-- 1. La ronda debe estar en curso. En el lobby no se coloca nada.
	if not Service._roundService then
		Logger.Debug("[BOMB] validation fallo: sin RoundService")
		return false, "servicio de ronda no disponible"
	end

	if not Service._roundService.IsPlaying() then
		Logger.Debug(("[BOMB] validation fallo: no hay ronda en curso (estado=%s)"):format(
			Service._roundService.GetState()
		))
		return false, "no hay ronda en curso"
	end

	-- 2. Personaje jugable.
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")

	if not humanoid or humanoid.Health <= 0 or not rootPart then
		Logger.Debug("[BOMB] validation fallo: personaje no jugable")
		return false, "personaje no jugable"
	end

	-- 3. Posicion finita. El gateway ya valida el tipo, pero el servicio
	--    no confia en una sola comprobacion.
	local validPosition, positionReason = isValidPosition(position)

	if not validPosition then
		Logger.Debug(("[BOMB] validation fallo: %s"):format(positionReason or "posicion invalida"))
		return false, positionReason or "posicion invalida"
	end

	-- 4. Limites del mapa. Sin esto se puede explotar fuera del mapa.
	--
	-- Se mide contra la arena del MUNDO en el que esta el jugador. Antes solo
	-- se comparaba contra el rectangulo de Forest, de modo que en Desert, Ice,
	-- Volcano y Cyber toda bomba se rechazaba con "fuera de la arena".
	--
	-- El mundo se lee del atributo que escribe el SERVIDOR. Si no hay ninguno
	-- conocido se usa `nil`, y `IsInsideArena` cae al rectangulo por defecto.
	local worldAttr = player:GetAttribute("World")
	local worldId = if type(worldAttr) == "string" then worldAttr else nil

	if not Service.IsInsideArena(position, worldId) then
		local bounds = Service.GetArenaBounds(worldId)

		if bounds then
			Logger.Debug(("[BOMB] validation fallo: fuera de la arena %s X[%.0f, %.0f] Z[%.0f, %.0f]"):format(
				tostring(worldId),
				bounds.MinX,
				bounds.MaxX,
				bounds.MinZ,
				bounds.MaxZ
			))
		else
			Logger.Debug("[BOMB] validation fallo: sin limites de arena conocidos")
		end

		return false, "fuera de la arena"
	end

	-- 5. Distancia al personaje. Sin esto, un cliente colocaria bombas
	--    a distancia sin moverse.
	local distance = (rootPart.Position - position).Magnitude

	if distance > GameConfig.BombPlacementRange then
		Logger.Debug(("[BOMB] validation fallo: fuera de rango (%.0f studs, max %.0f)"):format(
			distance,
			GameConfig.BombPlacementRange
		))
		return false, ("fuera de rango (%.0f studs)"):format(distance)
	end

	-- 6. Tope de bombas por jugador. El cooldown (1.5 s) con.mecha
	--    (3 s) permitiria 2 bombas, pero un jugador que entre y salga
	--    de ronda acumularia mas. El limite es explicito.
	local limits = PerformanceConfig.Limits

	if Service.GetPlayerBombCount(player.UserId) >= limits.MaxBombsPerPlayer then
		Logger.Debug("[BOMB] validation fallo: limite de bombas del jugador")
		return false, "limite de bombas alcanzado"
	end

	if Service.GetActiveBombCount() >= limits.MaxBombsPerWorld then
		Logger.Debug("[BOMB] validation fallo: limite de bombas del mundo")
		return false, "limite de bombas del mundo alcanzado"
	end

	-- 7. Cooldown por jugador. Se consume ANTES de colocar, para que un
	--    rechazo posterior no devuelva el tiempo al cliente.
	local now = os.clock()

	if now < (Service._cooldowns[player.UserId] or 0) then
		Logger.Debug("[BOMB] validation fallo: en cooldown")
		return false, "en cooldown"
	end
	Service._cooldowns[player.UserId] = now + GameConfig.BombCooldown

	if not Service._explosionService then
		Logger.Error("BombService: ExplosionService no inyectado")
		return false, "sin servicio de explosiones"
	end

	local bombId = spawnBomb(player.UserId, position, worldId)

	if bombId == 0 then
		-- El modelo no se pudo construir: se devuelve el cooldown para que el
		-- jugador no espere 1.5 s a un fallo que ya se ha registrado.
		Service._cooldowns[player.UserId] = now
		return false, "no se pudo crear la bomba"
	end

	Logger.Debug(("[BOMB] created id=%d por %s (mecha %.1fs)"):format(
		bombId,
		player.Name,
		GameConfig.DefaultBombFuseTime
	))

	-- Progreso de mision: se cuenta la bomba COLOCADA, no la que explota.
	-- Va DESPUES de crearla y ANTES de devolver, para que lo que el jugador
	-- ya hizo (pagar el cooldown y colocar) cuente aunque la mecha todavia
	-- no haya vencido.
	if Service._questService ~= nil then
		Service._questService.RecordMetric(player, "BombPlaced", 1)
	end

	return true, nil
end

--- Destruye TODAS las bombas activas (fin de ronda).
--- @return number removed
function Service.ClearBombs(): number
	local removed = 0

	for bombId, record in pairs(Service._activeBombs) do
		destroyBombVisual(record)

		if record and record.Model then
			removed += 1
		end
		Service._activeBombs[bombId] = nil
	end

	-- Fin de ronda: todos los contadores vuelven a 0 de verdad. Sin esto el
	-- HUD seguiria mostrando las bombas de la ronda que ya termino.
	publishAllBombCounts()

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

--- Detecta los limites de TODAS las arenas a partir de sus suelos.
---
--- Se lee del mapa, no del generador: asi el servicio funciona con
--- cualquier arena que tenga un suelo con nombre reconocible.
---
--- BUG CORREGIDO (medido en PLAY): esta funcion devolvia el `ArenaFloor` del
--- PRIMER mundo de `Workspace.Worlds` y descartaba los demas. Con cinco mundos
---Eso dejaba cuatro arenas sin limite y, por tanto, sin bombas. Ahora devuelve
--- una tabla por mundo mas el rectangulo del mundo por defecto, que es lo que
--- usan los llamantes antiguos y los jugadores sin `World` conocido.
---
--- @return { byWorld: { [string]: bounds }, default: bounds? }
local function detectArenaBounds()
	local worlds = Workspace:FindFirstChild("Worlds")

	if not worlds then
		return { byWorld = {}, default = nil }
	end

	local byWorld: { [string]: any } = {}

	for _, world in ipairs(worlds:GetChildren()) do
		local floor = world:FindFirstChild("ArenaFloor")

		if floor and floor:IsA("BasePart") then
			local part = floor :: BasePart
			local half = part.Size / 2

			byWorld[world.Name] = {
				MinX = part.Position.X - half.X,
				MaxX = part.Position.X + half.X,
				MinZ = part.Position.Z - half.Z,
				MaxZ = part.Position.Z + half.Z,
			}
		end
	end

	-- El mundo por defecto se decide por el servicio de mundos, no por el
	-- PRIMER hijo de la carpeta: el orden de `GetChildren` no es el orden de
	-- carga de `WorldService` y no tiene por que coincidir.
	local defaultWorld = Service._worldService and Service._worldService.GetDefaultWorldId()

	return {
		byWorld = byWorld,
		default = (defaultWorld and byWorld[defaultWorld]) or byWorld[next(byWorld)] or nil,
	}
end

--- @param maid any?
--- @return boolean success
function Service.Init(maid: any?): boolean
	if Service.IsInitialized then
		return true
	end

	Service._cooldowns = {}
	Service._activeBombs = {}
	Service._nextBombId = 0

	-- Se guarda el maid del registro: es lo que permite que la conexion con
	-- `Players.PlayerAdded` de `Start` se limpie al apagar el servicio.
	Service._maid = maid

	-- Las bombas se crean en una carpeta propia. El cliente puede verla
	-- (tiene que verlas para que la cuenta regresiva sea visible) pero
	-- nunca es una fuente de confianza.
	if Service._bombFolder and Service._bombFolder.Parent then
		Service._bombFolder:Destroy()
	end

	Service._bombFolder = Instance.new("Folder")
	Service._bombFolder.Name = "Bombs"
	Service._bombFolder:SetAttribute("IsBombFolder", true)
	Service._bombFolder.Parent = Workspace

	-- Limites de TODAS las arenas. Antes solo se guardaba el primero, y eso
	-- hacia que cuatro de los cinco mundos fueran injugables (ver
	-- `IsInsideArena`).
	local bounds = detectArenaBounds()

	Service._arenaBoundsByWorld = bounds.byWorld

	local defaultBounds = bounds.default

	if defaultBounds then
		Service.SetArenaBounds(defaultBounds)

		-- `_defaultArenaWorld` NO se fija aqui: en `Init` todavia no se ha
		-- inyectado `WorldService`. Lo resuelve `Start`, que corre despues de
		-- `ServerMain.wireDependencies`.
		Service._defaultArenaWorld = next(bounds.byWorld)

		Logger.Debug(("BombService: %d arena(s) con limite"):format(countBounds(bounds.byWorld)))
	else
		Logger.Warn("BombService: no se encontro ningun ArenaFloor; no habra limite de mapa.")
	end

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
		Logger.Error("BombService: sin ExplosionService; las bombas NO explotaran.")
	end

	if not Service._roundService then
		Logger.Error("BombService: sin RoundService; no se podran colocar bombas.")
	end

	-- El mundo por defecto se resuelve AQUI, no en `Init`: las dependencias se
	-- inyectan entre `Init` y `Start`, y en `Init` `_worldService` todavia no
	-- existe. Sin esto el rectangulo "por defecto" seria el primer nombre de la
	-- tabla, que no coincide con el mundo por defecto de `WorldService`.
	if Service._worldService then
		local defaultWorld = Service._worldService.GetDefaultWorldId()
		local resolved = if defaultWorld then Service._arenaBoundsByWorld[defaultWorld] else nil

		if resolved then
			Service._defaultArenaWorld = defaultWorld
			Service.SetArenaBounds(resolved)
		end
	end

	-- Un jugador que entra de nuevo empieza con 0 bombas publicadas, no con
	-- el atributo sin definir. Sin esto su HUD muestra "*" hasta que coloque
	-- su primera bomba, que se lee como "no se sabe" cuando el dato es
	-- justo un cero.
	if Service._maid then
		Service._maid:Connect(Players.PlayerAdded, function(player: Player)
			player:SetAttribute("Bombs", 0)
		end)
	end

	for _, player in ipairs(Players:GetPlayers()) do
		player:SetAttribute("Bombs", 0)
	end

	Logger.Info(("BombService listo (%d arena(s) con limite, por defecto %s)."):format(
		countBounds(Service._arenaBoundsByWorld),
		tostring(Service._defaultArenaWorld)
	))

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
	Service._arenaBounds = nil
	Service._arenaBoundsByWorld = {}
	Service._defaultArenaWorld = nil
	Service._worldService = nil
	Service._roundService = nil
	Service._explosionService = nil
	Service._questService = nil
	Service._maid = nil
	Service.IsInitialized = false

	return true
end

return Service
