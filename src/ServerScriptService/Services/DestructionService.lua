--!strict
--[[
	DestructionService
	Gestiona la vida y la destruccion de los bloques del mapa.

	Un bloque es destruible si su nombre empieza por `Block_`. Ese
	prefijo es el CONTRATO con `tools/generate-project.js`, que genera
	el mapa: si el prefijo cambia, hay que cambiarlo aqui tambien.

	El servicio NO decide quien recibe el dano: eso lo hace
	ExplosionService, que llama a `ApplyDamage` sobre lo que esta dentro
	del radio. Aqui solo se aplica dano, se destruye y se repara.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONFIG = SHARED:WaitForChild("Config")
local UTILS = SHARED:WaitForChild("Utils")

local GameConfig = require(CONFIG:WaitForChild("GameConfig"))
local CombatMath = require(SHARED:WaitForChild("Libraries"):WaitForChild("CombatMath"))
local BlockRespawn = require(SHARED:WaitForChild("Libraries"):WaitForChild("BlockRespawnRules"))
local VisualKit = require(SHARED:WaitForChild("Libraries"):WaitForChild("VisualKit"))
local Logger = require(UTILS:WaitForChild("Logger"))

local Service = {}

Service.IsInitialized = false

--- Prefijo de nombre que marca un bloque como destruible.
Service.BLOCK_PREFIX = "Block_"

--- Atributo que declara si una pieza se puede romper.
---
--- Se lee ANTES que el nombre, de modo que vale tanto para marcar una pieza
-- como destruible (`true`) como para blindar una que se llama `Block_*`
--- pero no debe romperse nunca (`false`).
Service.DESTRUCTIBLE_ATTRIBUTE = "Destructible"

-- QuestService: recibe el evento "un bloque ha sido destruido" para
-- avanzar las misiones que lo escuchan.
--
-- Es UNA referencia a un servicio de dominio, no una conexion a un evento:
-- el patron es el mismo que `ExplosionService.SetMonsterService`, y evita
-- que `DestructionService` tenga que saber que existen las misiones.
--
-- Es OPCIONAL a proposito: sin el, la destruccion sigue funcionando igual y
-- solo las misiones no avanzan. Un fallo del sistema de misiones no puede
-- tumbar la destruccion, que es de lo que depende la ronda.
--
-- NOTA: `DestructionService` NO emite el evento de "bloque destruido".
-- El metodo `ApplyDamage` no sabe QUIEN rompio el bloque, y anadirle un
-- parametro de propietario obligaria a cambiar su firma y a todos sus
-- llamantes. El evento se emite donde el dato existe: `ExplosionService`,
-- que ya recibe el `sourceUserId` de la bomba. Aqui se conserva el setter
-- por si el dia que exista el propietario se cablee desde aqui.
Service._questService = nil

--- Conecta el receptor de progreso de misiones.
--- @param questService any?
function Service.SetQuestService(questService: any)
	Service._questService = questService
end

-- Bloque -> vida restante.
Service._blocks = {}
-- Bloque -> estado original (vida, transparencia, colision, material).
--
-- POR QUE EXISTE ESTA TABLA Y NO UNA DE "POSICIONES":
-- La version anterior hacia `block:Destroy()` al destruirlo y borraba
-- su origen. `RestoreAll` solo restauraba los bloques que seguian
-- vivos, asi que tras la primera ronda la arena se quedaba VACIA para
-- siempre: no habia nada que restaurar. El bloque ahora se SECRETA
-- (transparente y sin colision) en lugar de destruirse, y esta tabla
-- conserva su estado original para poder repararlo.
Service._originals = {}

-- Bloque -> registro de REAPARICION (`BlockRespawnRules`).
--
-- Es una tabla APARTE de `_blocks` a proposito. `_blocks` guarda la vida
-- (un numero) y `_originals` el aspecto (para repararlo). La reaparicion
-- necesita un TERCER dato que no cabe en ninguno de los dos: el instante
-- sorteado, la generacion y el mundo. Si se metiera dentro de `_blocks`,
-- su valor pasaria de ser un numero a ser una tabla y medio juego
-- (comparaciones, aritmetica) dejaria de funcionar sin avisar.
--
-- El TIPO va con `::` en la DECLARACION y no en cada reasignacion
-- (`Init` y `Destroy` la vacian) porque `::` solo se admite una vez. Sin
-- el, Luau deduce `{ [BasePart]: {} }`, `record.World` pasa a valer
-- `unknown` y cada uso posterior genera un error NUEVO en cascada.
--
-- El valor es `any` y no `BlockRespawn.BlockRecord` a proposito: el
-- analizador de este proyecto (`tools/analyze.js`) no resuelve los
-- `require` con `WaitForChild` y daria `Unknown type` por el nombre
-- exportado. El tipo real lo aplica `ensureRecord`.
Service._records = {} :: { [BasePart]: any }

-- Semilla del SORTEO de la reaparicion.
--
-- Es un LOCAL y no un campo de `Service` a proposito: `Service` se declara
-- como `local Service = {}` sin tipos, de modo que `Service._roll = nil`
-- hace que Luau deduzca el campo como `nil` y luego asignarle una funcion
-- daria `Expected this to be 'nil'`. Un local con tipo explicito no tiene
-- ese problema y ademas deja claro que es estado PRIVADO del servicio.
--
-- Se genera UNA vez al arrancar. Es la garantia de que el cliente no
-- decide cuando reaparece un bloque: no tiene esta semilla, y aunque la
-- tuviera el servidor volveria a validarlo con `BlockRespawn.CanRespawn`.
local _roll: ((number, number) -> number)? = nil

-- Si el mundo sigue admitting reapariciones. Se apaga al terminar la ronda
-- para que ningun temporizador sobreviva al mapa.
Service._worldActive = true

--- Identificador estable de un bloque dentro de su mapa.
---
--- Dos bloques con el MISMO nombre pueden vivir en carpetas distintas, y
--- por eso la clave incluye la ruta. Sin ella, dos copias del mismo bloque
-- en zonas diferentes se contarian como duplicados, que es un falso
-- positivo en la unica comprobacion que caza duplicados de verdad.
--- @param block BasePart
--- @return string
local function blockKey(block: BasePart): string
	local parts = {}
	local current: Instance? = block

	while current and current ~= Workspace do
		table.insert(parts, 1, current.Name)
		current = current.Parent
	end

	return table.concat(parts, "/")
end

--- Devuelve (y crea si hace falta) el registro de reaparicion de un bloque.
--- @param block BasePart
--- @return any
local function ensureRecord(block: BasePart): any
	local record = Service._records[block]

	if record == nil then
		-- El mundo se deduce de la ruta: los bloques cuelgan de
		-- `Workspace.Worlds.<Mundo>.<Zona>`, asi que el primer segmento
		-- DESPUES de `Worlds` es el identificador del mundo.
		local worldId = string.match(blockKey(block), "Worlds/([^/]+)")
		record = BlockRespawn.NewRecord(blockKey(block), worldId)
		Service._records[block] = record
	end

	return record
end

--- Indica si un respawn rechazado debe reintentarse mas tarde.
---
--- Un rechazo por "mundo inactivo" NO se reintenta: el mundo esta apagado y
--- no volvera a encenderse en esta ronda. Los rechazos por entidad en la
--- posicion SI se reintentan, porque esa situacion se deshace sola.
--- @param reason string?
--- @return boolean
local function shouldRetry(reason: string?): boolean
	if reason == nil then
		return false
	end

	return reason ~= "mundo inactivo" and reason ~= "estado no destruido"
end
--- @param block BasePart
--- @return { Health: number, Transparency: number, Anchored: boolean, CanCollide: boolean, CanTouch: boolean }
local function snapshotBlock(block: BasePart)
	return {
		Health = GameConfig.BlockHealth,
		Transparency = block.Transparency,
		Anchored = block.Anchored,
		CanCollide = block.CanCollide,
		CanTouch = block.CanTouch,
	}
end

--- Indica si una instancia es un bloque destruible del mapa.
---
--- Hay DOS formas de declararlo, y las dos cuentan:
---
--- 1. El atributo `Destructible == true`. Es la forma EXPLICITA y la que
---    se prefiere: deja escrito en la propia pieza que se puede romper.
--- 2. El prefijo de nombre `Block_`. Es el CONTRATO con
---    `tools/generate-project.js`, que nombra asi las piezas del mapa.
---
--- El atributo `false` VENCE al prefijo: un bloque que se llama `Block_*`
--- pero lleva `Destructible = false` es indestructible, porque el mapa
--- necesita estructuras que la bomba no puede abrir (el suelo de la arena,
--- los limites, los cimientos). Sin esa excepcion, "cualquier bloque con
--- ese nombre" seria destruible y el mapa no tendria nada fijo.
--- @param instance Instance?
--- @return boolean
function Service.IsDestructibleBlock(instance: Instance?): boolean
	if not instance or not instance:IsA("BasePart") then
		return false
	end

	-- El atributo explicito manda sobre el nombre, en los dos sentidos.
	local flag = instance:GetAttribute(Service.DESTRUCTIBLE_ATTRIBUTE)

	if flag ~= nil then
		return flag == true
	end

	return string.sub(instance.Name, 1, #Service.BLOCK_PREFIX) == Service.BLOCK_PREFIX
end

--- Marca un bloque como indestructible de forma EXPLICITA.
---
--- Se usa al generar el mapa, no en runtime: sirve para dejar escrito que
--- una pieza que parece decorativa (o que comparte prefijo por comodidad)
--- no se rompe nunca.
--- @param block BasePart
function Service.MarkIndestructible(block: BasePart)
	block:SetAttribute(Service.DESTRUCTIBLE_ATTRIBUTE, false)
end

--- Marca un bloque como destruible de forma EXPLICITA.
--- @param block BasePart
function Service.MarkDestructible(block: BasePart)
	block:SetAttribute(Service.DESTRUCTIBLE_ATTRIBUTE, true)
end

--- Localiza todos los bloques destruibles del Workspace.
--- @return number total
function Service.CollectBlocks(): number
	local total = 0

	for _, instance in ipairs(Workspace:GetDescendants()) do
		if Service.IsDestructibleBlock(instance) then
			total += 1
		end
	end

	return total
end

--- Vida actual de un bloque. 0 si ya fue destruido o no es bloque.
--- @param block BasePart
--- @return number
function Service.GetBlockHealth(block: BasePart): number
	return Service._blocks[block] or 0
end

--- Aplica dano a un bloque y lo destruye si llega a 0.
---
--- Al destruirse NO se llama a `Destroy()`: el bloque se oculta y deja
--- de colisionar. Se conserva en el Workspace para que la ronda
--- siguiente pueda repararlo. Destruirlo de verdad hacia que la arena
--- se quedase vacia tras la primera ronda.
--- @param block BasePart
--- @param amount number
--- @return boolean destroyed true si este golpe lo destruyo
function Service.ApplyDamage(block: BasePart, amount: number): boolean
	if not Service.IsDestructibleBlock(block) or not block.Parent then
		return false
	end

	-- Un bloque sin registro (creado despues del arranque) se registra
	-- aqui con su estado original.
	local health = Service._blocks[block]
	if health == nil then
		health = GameConfig.BlockHealth
		Service._originals[block] = snapshotBlock(block)
	end

	health = CombatMath.ApplyBlockDamage(health, amount)
	Service._blocks[block] = health

	if health > 0 then
		return false
	end

	-- Destruido: invisible e intangible, pero presente en el mapa.
	--
	-- Antes de desaparecer del todo, el bloque AVISA: se rompe en
	-- fragmentos y se apaga. Un bloque que se borra en el mismo frame en
	-- que la bomba explota no se lee como "lo has roto": se lee como un
	-- fallo de render. El feedback es lo que convierte una explosion en
	-- una decision del jugador.
	local record = Service._records[block]
	-- El mundo del bloque vive en su registro de reaparicion. Se resuelve
	-- con un `if` y no con `record and record.World or nil` porque el
	-- analizador no estrecha ese patron, y porque un `World` vacio debe
	-- quedarse en `nil` (es "sin mundo conocido"), no en cadena vacia.
	local worldId: string? = nil

	if record ~= nil and record.World ~= nil and record.World ~= "" then
		worldId = record.World
	end

	block.Transparency = 1
	block.CanCollide = false
	block.CanTouch = false
	block:SetAttribute("IsDestroyed", true)

	Service.spawnBreakVfx(block.Position, block.Size, worldId)

	local respawnDelay: number = Service.scheduleRespawn(block)

	Logger.Debug(("bloque destruido: %s (reaparece en %.1fs)"):format(
		block.Name,
		respawnDelay
	))
	return true
end

--- Programa la reaparicion ALEATORIA de un bloque destruido.
---
--- El respawn NO usa `task.delay(delay)` a pelo. Con `task.delay` a secas el
--- temporizador no lleva token, asi que un bloque reparado a mano (fin de
--- ronda) y su temporizador pendiente siguen los dos vivos: el bloque puede
--- materializarse dos veces. Aqui el temporizador lleva la GENERACION del
--- registro, que es lo que hace idempotente el sistema.
--- @param block BasePart
--- @return number delay espera sorteada, 0 si no se programo
function Service.scheduleRespawn(block: BasePart): number
	local record = Service._records[block]
	-- El generador se copia a una local CON TIPO. Sin el tipo explicito el
	-- analizador lo trataria como `unknown` al pasarlo a `Destroy`.
	local roll: ((number, number) -> number)? = _roll

	if record == nil or roll == nil then
		return 0
	end

	local scheduled, delay = BlockRespawn.Destroy(
		record,
		roll,
		os.clock(),
		GameConfig.BlockRespawnMin,
		GameConfig.BlockRespawnMax
	)

	if not scheduled then
		return 0
	end

	-- Se captura la GENERACION de este preciso temporizador. Si el bloque
	-- se destruye otra vez antes, la generacion cambia y este temporizador
	-- se descarta al vencer, en vez de resucitar un bloque ya nuevo.
	local generation = record.Generation

	task.delay(delay, function()
		Service.tryMaterialize(block, generation)
	end)

	return delay
end

--- Indica si hay algo incompatible ocupando la posicion de un bloque.
---
--- Solo se miran los HERMANOS del bloque, no todo el Workspace: recorrer el
--- mapa entero en cada reaparicion seria O(n) por bloque destruido, y en
--- una cadena de explosiones son decenas por segundo.
---
--- Lo que bloquea es un MONSTRUO o una BOMBA encima. Un decorado que
--- coincida en posicion NO lo impide (y no debe, o el mapa se quedaria con
--- huecos permanentes), pero un Guardian grande encima de la pieza haria que
--- reapareciera atravesado.
---
--- `monsters` y `bombs` se anotan como `Instance?`: si `FindFirstChild`
--- devuelve `nil` (la carpeta todavia no existe) el operador `and` devuelve
--- nil y el `or` lo convierte. Sin el tipo explicito, el analizador trata
--- el resultado como `unknown` y encadena errores por todo el bucle.
--- @param block BasePart
--- @return boolean
function Service.hasBlockingEntity(block: BasePart): boolean
	local container: Instance? = block.Parent

	if container == nil then
		return false
	end

	local position = block.Position
	local clearance: number = GameConfig.BlockSpawnClearance
	local monsters: Instance? = Workspace:FindFirstChild("Monsters")
	local bombs: Instance? = Workspace:FindFirstChild("Bombs")

	-- `children` se anota como `Instance[]`. Sin el tipo explicito el
	-- analizador infiere `unknown` para cada elemento y produce un error
	-- NUEVO por cada propiedad que se lee de el (`IsA`, `PrimaryPart`...),
	-- que es como un archivo pasa de 12 avisos a 25 sin que el codigo haya
	-- cambiado de verdad.
	local children: { Instance } = container:GetChildren()

	for _, sibling in ipairs(children) do
		if sibling == block or not sibling:IsA("Model") then
			continue
		end

		local isEntity: boolean = (monsters ~= nil and sibling:IsDescendantOf(monsters))
			or (bombs ~= nil and sibling:IsDescendantOf(bombs))

		if not isEntity then
			continue
		end

		local model: Model = sibling :: Model
		local root: BasePart? = model.PrimaryPart

		-- Sin `PrimaryPart` no se puede saber donde esta: se ignora en vez
		-- de bloquear el respawn de un bloque que si podria volver.
		if root ~= nil and (root.Position - position).Magnitude <= clearance then
			return true
		end
	end

	return false
end

--- Intenta materializar un bloque cuyo plazo de reaparicion ha vencido.
---
--- Es IDEMPOTENTE por construccion: las comprobaciones de `CanRespawn`
--- filtran los casos invalidos y `BeginRespawn` garantiza que dos llamadas
--- simultaneas sobre el mismo bloque solo produzcan UNA pieza.
--- @param block BasePart
--- @param generation number generacion que el temporador cree reparar
--- @return boolean materialized
function Service.tryMaterialize(block: BasePart, generation: number): boolean
	local record = Service._records[block]

	if record == nil then
		return false
	end

	-- El bloque desaparecio del Workspace (borrado desde el editor o por
	-- `StreamingEnabled`). Se limpia su registro para no retener una
	-- referencia muerta durante toda la partida.
	if block.Parent == nil then
		Service._blocks[block] = nil
		Service._originals[block] = nil
		Service._records[block] = nil
		return false
	end

	-- `IsDestroyed` es la verdad de campo: si ya vale false, el bloque esta
	-- en pie y materializarlo otra vez SERIA el duplicado que se prohibe.
	local alreadyVisible = block:GetAttribute("IsDestroyed") == false

	local allowed, reason = BlockRespawn.CanRespawn(record, os.clock(), {
		generation = generation,
		worldActive = Service._worldActive,
		hasActiveCopy = alreadyVisible,
		hasBlockingEntity = Service.hasBlockingEntity(block),
	})

	if not allowed then
		Logger.Debug(("respawn aplazado (%s): %s"):format(tostring(reason), block.Name))

		-- Un rechazo por entidad en la posicion se reintenta: esa situacion
		-- se deshace sola. Los demas no tienen sentido reintentarlos.
		if shouldRetry(reason) then
			task.delay(GameConfig.BlockRespawnRetryDelay, function()
				Service.tryMaterialize(block, generation)
			end)
		end

		return false
	end

	-- El token. Sin esta llamada, dos tareas que hubieran pasado
	-- `CanRespawn` fabricarian DOS bloques del mismo.
	if not BlockRespawn.BeginRespawn(record) then
		return false
	end

	local original = Service._originals[block]

	if original then
		block.Transparency = original.Transparency
		block.Anchored = original.Anchored
		block.CanCollide = original.CanCollide
		block.CanTouch = original.CanTouch
	end

	block:SetAttribute("IsDestroyed", false)
	Service._blocks[block] = if original then original.Health else GameConfig.BlockHealth

	BlockRespawn.FinishRespawn(record)

	Logger.Debug(("bloque reaparecido: %s"):format(block.Name))
	return true
end
--- Efectos de DESTRUCCION de un bloque.
---
--- No es un adorno: es la mitad del feedback. Sin esto el jugador ve que el
--- bloque desaparece y no sabe si su bomba ha acertado, ha pasado al lado, o
--- el mapa ha fallado.
---
--- Los fragmentos se lanzan con impulso REAL (`ApplyImpulse`) y caen por
--- gravedad: se leen como trozos de material, no como imagenes pegadas. Y se
--- destruyen solos, porque un Workspace que crece con cada bloque roto
--- acaba cayendo en la cadena de explosiones.
--- @param position Vector3
--- @param size Vector3
--- @param worldId string?
function Service.spawnBreakVfx(position: Vector3, size: Vector3, worldId: string?)
	local folder = Workspace:FindFirstChild("BlockVFX")

	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = "BlockVFX"
		folder:SetAttribute("IsVfxFolder", true)
		folder.Parent = Workspace
	end

	local skin = VisualKit.BombSkin(worldId)
	-- La lista se anota como `Instance[]` porque `VisualKit.MakePart` esta
	-- expuesta sin tipo de retorno y sus elementos saldrian `unknown`.
	local created: { Instance } = {}

	-- FRAGMENTOS: se lanzan hacia fuera y caen.
	for index = 1, 6 do
		local angle = (index / 6) * math.pi * 2
		local shard = VisualKit.MakePart(
			("Shard_%d"):format(index),
			Vector3.new(size.X * 0.25, size.Y * 0.25, size.Z * 0.25),
			CFrame.new(position) * CFrame.Angles(0, angle, 0),
			skin.glow,
			{ material = Enum.Material.Neon, transparency = 0.15 }
		)

		shard:SetAttribute("IsBlockShard", true)
		shard.Parent = folder
		table.insert(created, shard)

		-- El impulso lo decide el SERVIDOR con el tamano del bloque: un
		-- bloque pequeno no salta tan lejos como uno grande, y por eso no
		-- hay numeros magicos aqui sino una proporcion del tamano.
		shard:ApplyImpulse(
			Vector3.new(math.cos(angle), 0, math.sin(angle)) * (size.Magnitude * 8)
				+ Vector3.new(0, size.Magnitude * 20, 0)
		)
	end

	-- Onda de choque: aro que crece desde cero hasta el tamano del bloque.
	local ring = VisualKit.MakePart(
		"BreakRing",
		Vector3.new(0.5, 0.4, 0.5),
		CFrame.new(position),
		skin.ring,
		{ material = Enum.Material.Neon, transparency = 0.2 }
	)
	ring.Shape = Enum.PartType.Cylinder
	ring.Orientation = Vector3.new(0, 0, 90)
	ring:SetAttribute("IsBlockShard", true)
	ring.Parent = folder
	table.insert(created, ring)

	-- Destello breve en el punto del impacto.
	local light = Instance.new("PointLight")
	light.Brightness = 4
	light.Range = 22
	light.Shadows = false
	light.Color = skin.glow
	light.Parent = ring

	-- Crecimiento del aro, de 0.5 hasta el tamano REAL del bloque: la onda
	-- no puede mentir sobre el alcance de lo que se ha roto.
	task.spawn(function()
		local target = math.max(size.X, size.Z)
		local elapsed = 0
		local duration = 0.35

		while elapsed < duration do
			if ring.Parent == nil then
				return
			end

			task.wait(0.05)
			elapsed += 0.05

			local t = math.clamp(elapsed / duration, 0, 1)
			local scale = target * t
			ring.Size = Vector3.new(math.max(0.5, scale), 0.4, math.max(0.5, scale))
			ring.Transparency = 0.2 + t * 0.6
		end
	end)

	-- Limpieza. Se guardan las instancias CREADAS en una lista en vez de
	-- barrer la carpeta entera: la comparten todos los bloques del mapa, y
	-- borrar "los fragmentos" sin filtro se llevaria por delante los de
	-- otra destruccion simultanea.
	task.delay(1.5, function()
		for _, instance in ipairs(created) do
			if instance.Parent then
				instance:Destroy()
			end
		end
	end)
end

--- Repara TODOS los bloques y cancela sus reapariciones pendientes.
---
--- El orden importa: primero se BLOQUEA el mundo, luego se reparan los
--- bloques. Si se repararan primero, un temporizador que venza en ese
--- mismo instante encontraria un bloque `Active` y no haria nada, pero si
--- el mundo ya esta bloqueado el rechazo es explicito y no depende del
--- orden de los dos `if`.
--- @return number restored
function Service.RestoreAll(): number
	local restored = 0

	Service._worldActive = false

	for block, original in pairs(Service._originals) do
		-- Un bloque que ya no existe (borrado desde el editor o por
		-- StreamingEnabled) se descarta de la tabla para no retener una
		-- referencia muerta durante toda la partida.
		if block.Parent then
			block.Transparency = original.Transparency
			block.Anchored = original.Anchored
			block.CanCollide = original.CanCollide
			block.CanTouch = original.CanTouch
			block:SetAttribute("IsDestroyed", false)

			Service._blocks[block] = original.Health

			-- `Restore` deja el registro en `Active` y borra el instante
			-- sorteado: el temporizador de ese bloque, cuando venza, se
			-- encontrara con un estado que ya no es `Destroyed` y no
			-- materializara nada.
			local record = Service._records[block]

			if record then
				BlockRespawn.Restore(record)
			end

			restored += 1
		else
			Service._originals[block] = nil
			Service._blocks[block] = nil
			Service._records[block] = nil
		end
	end

	return restored
end

--- Vuelve a admitir reapariciones y prepara la siguiente ronda.
--- @return number restored
function Service.ResumeRound(): number
	Service._worldActive = true
	return Service.RestoreAll()
end

--- Auditoria de DUPLICADOS.
---
--- No es decorativa: es la comprobacion en vivo de que el mapa no lleva
--- dos copias del mismo bloque. Un `Block_A Block_A Block_A` no se
--- detecta con logica: se PREVIENE, pero hace falta una forma de
--- DEMOSTRAR que no esta pasando y de avisar si alguna vez pasa.
--- @return { string } claves duplicadas
function Service.AuditDuplicates(): { string }
	return BlockRespawn.FindDuplicateKeys(Service._records)
end

--- Cantidad de bloques todavia en pie.
--- @return number
function Service.GetAliveBlockCount(): number
	local count = 0
	for _ in pairs(Service._blocks) do
		count += 1
	end
	return count
end

--- Cantidad de bloques destruidos y pendientes de reparar.
--- @return number
function Service.GetDestroyedBlockCount(): number
	local destroyed = 0

	for block, health in pairs(Service._blocks) do
		if health <= 0 and block.Parent then
			destroyed += 1
		end
	end

	return destroyed
end

function Service.Init(maid: any?): boolean
	if Service.IsInitialized then
		return true
	end

	Service._blocks = {}
	Service._originals = {}
	Service._records = {}
	Service._worldActive = true

	-- SEMILLA DEL SERVIDOR.
	--
	-- `Random.new()` sin argumentos usa una semilla distinta en cada
	-- servidor. Es justo lo que se quiere: el tiempo de reaparicion NO
	-- puede ser adivinado por el cliente, ni salirse del rango, ni
	-- reproducirse para saber cuando vuelve un bloque.
	--
	-- Se envuelve en una funcion `roll` porque `BlockRespawnRules` no
	-- depende del motor: recibe la funcion y asi se puede probar entero
	-- con el interprete de `luau.exe`.
	local generator = Random.new()
	local roll = function(min: number, max: number): number
		return generator:NextNumber(min, max)
	end

	-- El generador se guarda en el local `_roll`, que ya tiene tipo.
	_roll = roll

	local total = Service.CollectBlocks()
	Logger.Info(("DestructionService: %d bloques destructibles en el mapa"):format(total))

	if total == 0 then
		-- No es un error fatal: la arena puede no tener bloques todavia.
		-- Se avisa para que el fallo sea visible y no silencioso.
		Logger.Warn("DestructionService: el mapa no tiene bloques 'Block_'; la destruccion no tendra efecto.")
		Service.IsInitialized = true
		return true
	end

	-- Registrar vida, estado original y reaparicion de cada bloque. Se
	-- recorre el mapa en lugar de usar el generador para que el servicio
	-- funcione con cualquier mapa que cumpla el contrato.
	for _, instance in ipairs(Workspace:GetDescendants()) do
		if Service.IsDestructibleBlock(instance) then
			local block = instance :: BasePart
			Service._blocks[block] = GameConfig.BlockHealth
			Service._originals[block] = snapshotBlock(block)
			block:SetAttribute("IsDestroyed", false)
			ensureRecord(block)
		end
	end

	-- La auditoria se hace al arrancar, no solo al destruir. Si el mapa
	-- se duplicase una vez al GENERARSE, en runtime ya seria tarde: el
	-- error estaria en el `.rbxlx`, no en este servicio.
	local duplicates = Service.AuditDuplicates()

	if #duplicates > 0 then
		Logger.Warn(("DestructionService: %d bloques con clave duplicada: %s"):format(
			#duplicates,
			table.concat(duplicates, ", ")
		))
	end

	Service.IsInitialized = true
	Logger.Info(("DestructionService: %d bloques registrados (respawn %.0f-%.0fs)"):format(
		Service.GetAliveBlockCount(),
		GameConfig.BlockRespawnMin,
		GameConfig.BlockRespawnMax
	))

	return true
end

function Service.Start(): boolean
	if not Service.IsInitialized then
		Logger.Error("DestructionService: Start sin Init")
		return false
	end

	return true
end

function Service.Destroy(): boolean
	Service.IsInitialized = false
	Service._blocks = {}
	Service._originals = {}
	Service._records = {}
	_roll = nil
	Service._worldActive = false
	return true
end

return Service