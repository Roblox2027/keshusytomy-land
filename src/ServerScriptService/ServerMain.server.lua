--!strict
--[[
	ServerMain
	Punto de entrada del servidor de KeshusyTomy-LanD.

	Responsabilidad (FASE 1 - Foundation):
	- Verificar que los modulos base existan.
	- Construir el ServiceRegistry y registrar los servicios con
	  sus dependencias declaradas.
	- Arrancar en orden topologico y apagar de forma ordenada.

	Flujo:
		ServerMain
		  -> ServiceRegistry
		    -> Services

	No debe crecer hasta convertirse en un archivo gigante:
	la logica de cada dominio vive en Services / Systems.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONFIG = SHARED:WaitForChild("Config")
local UTILS = SHARED:WaitForChild("Utils")
local SERVER = script.Parent

-- `Maid` se usa para las conexiones del perfil, que NO pertenecen al ciclo
-- de vida de ningun servicio: las crea `ServerMain` y viven mas alla del
-- registro.
local Maid = require(SHARED:WaitForChild("Libraries"):WaitForChild("Maid"))

-- Modulos indispensables para que el servidor pueda operar.
local REQUIRED_MODULES = {
	{ name = "GameConfig", instance = CONFIG:WaitForChild("GameConfig") },
	{
		name = "GameConstants",
		instance = SHARED:WaitForChild("Constants"):WaitForChild("GameConstants"),
	},
	{ name = "Logger", instance = UTILS:WaitForChild("Logger") },
}

local Logger = require(UTILS:WaitForChild("Logger"))
-- Se necesita para el limite de distancia de las bombas: el valor vive en
-- la configuracion y no debe repetirse como numero magico en el handler.
local GameConfig = require(CONFIG:WaitForChild("GameConfig"))
local GameConstants = require(SHARED:WaitForChild("Constants"):WaitForChild("GameConstants"))
local ServiceRegistry = require(SERVER:WaitForChild("Systems"):WaitForChild("ServiceRegistry"))
local RemoteGateway = require(SERVER:WaitForChild("Systems"):WaitForChild("RemoteGateway"))

local ServerMain = {}

-- Prefijo de los fallos de cableado. Se compara con `#PREFIX` y no con
-- un numero fijo: un conteo mal puesto hacia que los fallos se
-- imprimieran como INFO y volvieran a ser invisibles.
local WIRING_FAIL_PREFIX = "[WIRING FAIL]"

--- Servicios sin los cuales el juego NO es jugable. Se usan para el
--- informe de arranque: si uno de estos no llega a `Started`, el
--- servidor esta en modo degradado aunque no haya ningun error rojo.
ServerMain.CriticalServices = {
	"WorldService",
	"SpawnService",
	"DestructionService",
	"RoundService",
	"CombatService",
	"PlayerService",
	"ExplosionService",
	"BombService",
	"MatchService",
	-- El Core es critico: es el corazon del lobby y sin el la pantalla
	-- de carga no tiene sentido. Si no arranca, el lobby esta degradado.
	"CoreService",
	-- VisualService no es critico para PODER JUGAR (sin el, el juego corre
	-- a oscuras pero no se rompe). Se lista igualmente entre los servicios
	-- de arranque para que su ausencia salga en el informe en vez de pasar
	-- desapercibida: un lobby sin luz es un fallo de producto, no un
	-- detalle, y tiene que verse en el log.
	"VisualService",

	-- La columna economica. `DataService` y `ProfileService` NO son
	-- criticos para JUGAR: sin ellos el juego arranca y se juega, pero sin
	-- persistencia. Se listan para que su ausencia salga en el informe, no
	-- para tumbar el servidor: un DataStore caido no puede impedir jugar
	-- una ronda.
	--
	-- `EconomyService`, `InventoryService`, `ProgressionService` y
	-- `ShopService` si son criticos cuando existen: si arrancan a medias,
	-- hay un cableado mal hecho y eso SI hay que verlo.
	"DataService",
	"ProfileService",
	"EconomyService",
	"InventoryService",
	"ProgressionService",
	"ShopService",
}

--- Resultado del cableado de dependencias de la ultima arrancada.
ServerMain.WiringReport = {}

-- Referencias a los servicios que los handlers de remotos necesitan.
-- Se llenan en `Start`, despues de arrancar el registro.
local playerService = nil
local bombService = nil
local portalService = nil
local coreService = nil
-- `RoundService` vive aqui y NO solo en `wireDependencies`, por el mismo
-- motivo que los de abajo.
--
-- MEDIDO EN PLAY (el P0 que hacia que la bomba NUNCA apareciese):
--
--   AntiExploitService: userId=... BombAction.Place -> state_violation (suspicious)
--
-- El filtro de red estaba CORRECTO: la ronda estaba en `Playing` y `Playing`
-- estaba permitido. El fallo era que el handler le pasaba `nil`:
--
--   serverState = roundService and roundService.GetState() or nil
--
-- `roundService` era un local de `wireDependencies`, y los handlers de
-- `REMOTE_CHANNELS` se construyen en el ambito de ARCHIVO. Ahi ese nombre no
-- existe, asi que Lua lo resolvia como GLOBAL: `nil`. Y `nil` no es un estado
-- de ronda, es un estado DESCONOCIDO, asi que el filtro rechazaba la peticion
-- como violacion de estado.
--
-- El efecto era invisible desde fuera: el filtro de red no publica motivo al
-- cliente, asi que el boton solo se apagaba. Y el rechazo era
-- `state_violation` con la ronda claramente en `Playing`, que es una
-- contradicion que no lleva a ninguna parte hasta que se lee el log.
--
-- La red de seguridad NO era "quitar la comprobacion": el filtro sigue
-- exigiendo un estado jugable. Lo que se corrige es que el estado LLEGUE.
local roundService = nil

-- Los seis de la columna economica.
--
-- POR QUE SON LOCALES DE ARCHIVO Y NO DE `wireDependencies`
-- ---------------------------------------------------------
-- `wireDependencies` es una FUNCION: sus locales mueren al terminar. Si el
-- perfil y la tienda vivieran ahi, `ServerMain.Start` (otra funcion) y los
-- handlers de `REMOTE_CHANNELS` los verian como `nil`, el bloque que carga
-- el perfil no se ejecutaria nunca y los remotos de tienda e inventario
-- saldrian sin hacer nada. Todo eso SIN un solo error rojo, porque `nil` es
-- un valor valido para un `if not servicio then return end`.
local dataService = nil
local profileService = nil
local economyService = nil
local inventoryService = nil
local progressionService = nil
local shopService = nil
local codeService = nil
local questService = nil
-- ActivityService (exploracion, FASE 3). Comparte pareja economica con
-- QuestService: lee el perfil y paga con la economia.
local activityService = nil

-- AntiExploitService. Es el UNICO modulo de este archivo que se consulta
-- DENTRO de un handler de remoto, asi que necesita una referencia de
-- modulo (los locales de `wireDependencies` moririan).
local antiExploitService = nil

--- Mide la distancia entre el personaje de un jugador y un punto.
---
--- Devuelve `nil` cuando NO se puede medir, y `nil` es precisamente lo que
--- hace que la capa de anti-exploit RECHACE la peticion: un filtro que
--- aceptara "no lo pude medir" trataria como valido lo que no ha comprobado,
--- y eso es un canal abierto, no una comprobacion laxa.
---
--- No se toma jamas la distancia del payload: seria el propio atacante
--- dictandole al servidor cuanta comprobacion hacer.
--- @param player Player
--- @param position any
--- @return number?
local function measureDistance(player: Player, position: any): number?
	if typeof(position) ~= "Vector3" then
		return nil
	end

	local character = player.Character

	if not character then
		return nil
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")

	if not rootPart or not rootPart:IsA("BasePart") then
		return nil
	end

	return (rootPart.Position - position).Magnitude
end

--- Comprueba una peticion contra la capa de contexto.
---
--- Si el anti-exploit no esta disponible, se PERMITE: el juego debe seguir
--- siendo jugable sin el, igual que sin las misiones. Devolver `false`
--- dejaria a los jugadores sin bombas por un fallo de arranque.
--- @param player Player
--- @param channel string
--- @param action string
--- @param context any?
--- @return boolean allowed
--- @return string? reason
local function Service_CheckRequest(
	player: Player,
	channel: string,
	action: string,
	context: any?
): (boolean, string?)
	if not antiExploitService then
		return true, nil
	end

	return antiExploitService.Check(player.UserId, channel, action, context)
end

-- Registro de servicios. Cada entrada declara sus dependencias para
-- que el orden de arranque sea determinista.
--
-- El orden de las dependencias importa de verdad: quien depende de
-- otro se inicializa despues. MatchService, por ejemplo, necesita que
-- DestruccionService ya haya registrado los bloques del mapa.
local SERVICES = {
	-- DataService va PRIMERO de los seis: abre el DataStore y es quien
	-- puede fallar por red. Si se registrara despues, `ProfileService`
	-- arrancaria sin el, su `Start` fallaria y la economia entera se
	-- quedaria sin fuente de verdad.
	{ name = "DataService", module = SERVER.Services.DataService, dependencies = {} },

	-- ProfileService guarda el perfil en memoria. Economy, Inventory,
	-- Progression y Shop leen y escriben ahi, NUNCA a su propia sesion: por
	-- eso las cuatro dependen de el y no al reves.
	{
		name = "ProfileService",
		module = SERVER.Services.ProfileService,
		dependencies = { "DataService" },
	},

	-- La economia depende del perfil, no de la progresion: no hay ninguna
	-- razon por la que una moneda requiera un nivel.
	{
		name = "EconomyService",
		module = SERVER.Services.EconomyService,
		dependencies = { "ProfileService" },
	},

	-- El inventario depende del perfil. NO depende de la economia: un item
	-- se puede conseguir sin pagar (recompensa, codigo), y anadir esa
	-- dependencia haria que perder la economia dejase al jugador sin
	-- inventario.
	{
		name = "InventoryService",
		module = SERVER.Services.InventoryService,
		dependencies = { "ProfileService" },
	},

	-- La progresion depende del perfil Y de la economia: subir de nivel PAGA
	-- monedas, asi que necesita poder concederlas.
	{
		name = "ProgressionService",
		module = SERVER.Services.ProgressionService,
		dependencies = { "ProfileService", "EconomyService" },
	},

	-- La tienda necesita las TRES piezas: el perfil (estado), la economia
	-- (cobrar) y el inventario (entregar).
	{
		name = "ShopService",
		module = SERVER.Services.ShopService,
		dependencies = { "ProfileService", "EconomyService" },
	},

	-- CodeService puede canjear MONEDAS, asi que depende de las TRES
	-- piezas de la columna economica: perfil (donde vive el registro del
	-- canje), economia (que paga) y el propio catalogo.
	--
	-- Se declara DESPUES de ShopService porque las dos tocan el mismo
	-- ledger: el orden topologico solo garantiza que ProfileService ya
	-- arranco, no que el orden de escritura sea este.
	{
		name = "CodeService",
		module = SERVER.Services.CodeService,
		dependencies = { "ProfileService", "EconomyService" },
	},

	-- QuestService paga recompensas con la economia y guarda el progreso
	-- en el perfil, asi que depende de los dos. NO depende de
	-- `RoundService` ni de `MatchService`: no los consulta, solo RECIBE
	-- eventos de ellos a traves de `RecordMetric`.
	--
	-- Se declara despues de `CodeService` porque los dos tocan el mismo
	-- ledger, y el orden topologico no garantiza el orden de escritura.
	{
		name = "QuestService",
		module = SERVER.Services.QuestService,
		dependencies = { "ProfileService", "EconomyService" },
	},

	-- ActivityService: exploracion y recompensas por actividades (FASE 3).
	-- Comparte la columna economica con QuestService, asi que depende de las
	-- mismas bases; `PlayerService` y `WorldService` se inyectan con setters
	-- para resolver el mundo del jugador y comprobar proximidad.
	{
		name = "ActivityService",
		module = SERVER.Services.ActivityService,
		dependencies = { "ProfileService", "EconomyService", "PlayerService", "WorldService" },
	},

	{ name = "WorldService", module = SERVER.Services.WorldService, dependencies = {} },
	{
		name = "SpawnService",
		module = SERVER.Services.SpawnService,
		dependencies = { "WorldService" },
	},
	{
		name = "DestructionService",
		module = SERVER.Services.DestructionService,
		dependencies = { "WorldService" },
	},
	{
		name = "RoundService",
		module = SERVER.Services.RoundService,
		dependencies = { "WorldService" },
	},
	-- CombatService depende de RoundService: sin el estado de ronda no
	-- puede decidir si el dano es legal (el lobby es zona segura).
	{
		name = "CombatService",
		module = SERVER.Services.CombatService,
		dependencies = { "RoundService" },
	},
	{
		name = "PlayerService",
		module = SERVER.Services.PlayerService,
		dependencies = { "RoundService", "CombatService" },
	},
	{
		name = "ExplosionService",
		module = SERVER.Services.ExplosionService,
		dependencies = { "DestructionService", "CombatService" },
	},
	{
		name = "BombService",
		module = SERVER.Services.BombService,
		dependencies = { "RoundService", "ExplosionService" },
	},
	-- MatchService NO se declara aqui: se declara mas abajo, despues de
	-- MonsterService, del que ahora depende para generar la poblacion de la
	-- ronda. Declararlo en los dos sitios lo registraria DOS veces y el
	-- registro avisaria de "canal ya registrado", que es la forma mas
	-- silenciosa de dejar medio sistema sin arrancar.
	-- PortalService depende de MatchService: para entrar a un mundo hace
	-- falta saber a donde se teletransporta al jugador, y MatchService es el
	-- unico que tiene los marcadores de traslado del mapa.
	{
		name = "PortalService",
		module = SERVER.Services.PortalService,
		dependencies = { "WorldService", "MatchService", "RoundService" },
	},
	-- CoreService va al final: no depende de nadie, pero el resto de
	-- servicios ya estan cableados cuando arranca, y su difusion usa
	-- el mismo registro.
	{ name = "CoreService", module = SERVER.Services.CoreService, dependencies = {} },

	-- AntiExploitService NO depende de nadie: es una capa que compara y
	-- cuenta, no un sistema de juego. Se declara aqui para que el registro
	-- le haga su ciclo de vida y para que aparezca en el informe de arranque.
	--
	-- Los servicios de juego NO lo declaran como dependencia porque eso
	-- crearia un ciclo: el anti-exploit los OBSERVA, no los usa.
	{ name = "AntiExploitService", module = SERVER.Services.AntiExploitService, dependencies = {} },
	-- MonsterService (PvE) va DESPUES de RoundService, CombatService y
	-- PlayerService: necesita saber si hay ronda para moverse, el unico
	-- camino de dano para golpear y el servicio que paga las recompensas.
	-- El orden de arranque no es estetico: `Registry:Get` solo devuelve
	-- servicios ya arrancados, asi que declararlo antes le daria tres
	-- inyecciones `nil` sin ningun error visible.
	{
		name = "MonsterService",
		module = SERVER.Services.MonsterService,
		dependencies = { "RoundService", "CombatService", "PlayerService", "WorldService" },
	},
	-- PowerupService: los objetos que el jugador recoge en la arena. No
	-- depende de nadie para GENERARLOS (solo del mapa), asi que se declara
	-- despues de WorldService para no leer `Worlds` antes de que exista.
	{
		name = "PowerupService",
		module = SERVER.Services.PowerupService,
		dependencies = { "WorldService" },
	},
	-- MatchService se mueve DESPUES de MonsterService porque ahora genera
	-- la poblacion al empezar la ronda. La dependencia se declara de forma
	-- explicita: el registro resuelve el orden topologico y, sin ella,
	-- MatchService arrancaria con `monsterService = nil` y la ronda
	-- terminaria sin un solo monstruo sin un solo error.
	{
		name = "MatchService",
		module = SERVER.Services.MatchService,
		dependencies = {
			"RoundService",
			"PlayerService",
			"BombService",
			"DestructionService",
			"CombatService",
			"MonsterService",
			"PowerupService",
			"WorldService",
		},
	},
	-- VisualService va DESPUES de WorldService: lee el mapa (lobby, Core,
	-- portales y mundos) y enciende las luces de las arenas. Encenderlas
	-- antes de que el mundo exista las haria perderse: losFolders vacios
	-- no se recorren.
	{
		name = "VisualService",
		module = SERVER.Services.VisualService,
		dependencies = { "WorldService" },
	},

	-- NightService: el reloj de las 99 noches (FASES 8 y 9).
	--
	-- No depende de NADIE y NADIE depende de el todavia, y esa es la decision
	-- deliberada: el reloj es la fuente de verdad del tiempo del mundo, asi que
	-- tiene que arrancar antes que los sistemas que lo consulten y no puede
	-- depender de ellos (si dependiera de `WorldService`, un fallo al registrar
	-- los mundos dejaria el reloj parado y el juego entero sin ciclo).
	--
	-- NO es critico: sin el, el juego sigue siendo jugable (queda un ciclo
	-- viejo de rondas) y por eso NO esta en `CriticalServices`. Aparecera en el
	-- informe de arranque si falla, que es lo que hay que ver.
	{
		name = "NightService",
		module = SERVER.Services.NightService,
		dependencies = {},
	},

	-- HordeService: los eventos de horda (FASE 14).
	--
	-- Depende de `MonsterService` porque las hordas son enemigos y su muerte la
	-- notifica ese servicio, y de `NightService` porque el tamano y la
	-- recompensa dependen de la noche. La economia es OPCIONAL: sin ella las
	-- hordas funcionan igual y lo unico que falta es el cobro del premio, que
	-- es preferible a que no haya hordas.
	{
		name = "HordeService",
		module = SERVER.Services.HordeService,
		dependencies = { "NightService", "MonsterService" },
	},

	-- EventService: eventos mundiales por mundo (eventos de noche).
	--
	-- Depende de `NightService` porque la probabilidad y la duracion del
	-- sorteo salen del reloj. `PlayerService` y `QuestService` se pasan
	-- como OPCIONALES en `SetDependencies`: sin ellos los eventos corren
	-- igual y solo falta acreditar recompensas ligadas a jugador/mision.
	{
		name = "EventService",
		module = SERVER.Services.EventService,
		dependencies = { "NightService" },
	},

	-- HazardService: la mecanica caracteristica de cada mundo (mision
	-- V2, FASE 3): emboscadas, arenas movedizas, viento, lava y laseres.
	-- Depende de `CombatService` (autoridad de dano) y `MonsterService`
	-- (los enemigos de la emboscada). Ambos se pasan en `SetDependencies`.
	{
		name = "HazardService",
		module = SERVER.Services.HazardService,
		dependencies = { "CombatService", "MonsterService" },
	},

	-- MiniBossService: mini-bosses por zona con enfriamiento.
	--
	-- Depende de `MonsterService` porque sus NPC los genera el y porque
	-- las muertes le llegan por la flecha inversa
	-- `MonsterService -> MiniBossService` (ver `wireDependencies`).
	{
		name = "MiniBossService",
		module = SERVER.Services.MiniBossService,
		dependencies = { "MonsterService" },
	},
	{
		name = "SecretService",
		module = SERVER.Services.SecretService,
		dependencies = { "ProfileService", "EconomyService", "QuestService" },
	},

	-- LootService: drops de materiales por muerte (mision V2, FASE 23/25).
	-- Depende de `InventoryService` (entrega) y `EconomyService` (gemas
	-- de boss). No tiene hilo: responde a las muertes como observador.
	{
		name = "LootService",
		module = SERVER.Services.LootService,
		dependencies = { "InventoryService", "EconomyService" },
	},

	-- AchievementService: logros y titulos (mision V2, FASES 17/19).
	-- Recibe las metricas por reenvio de `QuestService.RecordMetric`:
	-- no hay una segunda via de metricas que pueda divergir.
	{
		name = "AchievementService",
		module = SERVER.Services.AchievementService,
		dependencies = { "ProfileService", "EconomyService" },
	},

	-- BestiaryService: coleccion de especies (mision V2, FASE 20).
	{
		name = "BestiaryService",
		module = SERVER.Services.BestiaryService,
		dependencies = { "ProfileService" },
	},

	-- PuzzleService: doble interruptor por mundo (mision V2, FASES 13/14).
	-- Depende de `EconomyService` (pago); `QuestService` es opcional.
	{
		name = "PuzzleService",
		module = SERVER.Services.PuzzleService,
		dependencies = { "EconomyService" },
	},

	-- Herramienta de pruebas. Va al final y NO es critica: sin ella el
	-- juego es exactamente igual de jugable, solo se pierde la
	-- capacidad de certificar el camino de entrada del cliente.
	--
	-- Se registra como servicio real (y no como script suelto) para que
	-- herede el ciclo de vida Init/Start/Destroy del registro y para que
	-- no pueda quedar vivo despues de apagarse el servidor.
	{
		name = "TestDriverService",
		module = SERVER.Services.TestDriverService,
		dependencies = {},
	},
}

--- Conecta las dependencias entre servicios.
---
--- Se hace ENTRE `InitAll` y `StartAll`: antes de arrancar, pero despues
--- de que cada servicio exista. Este es el unico punto del arranque en el
--- que un servicio puede conocer a otro.
---
--- AUDITORIA: antes esta funcion NO reportaba nada. Cada `if ... then`
--- se saltaba en silencio si una dependencia era nil, de modo que un
--- servicio podia quedarse sin cablear y el juego seguia "arrancando".
--- Ahora cada salto se registra como `[WIRING FAIL]` y se devuelve un
--- informe, para que el Output diga exactamente que falta y por que.
--- @param registry any registro de servicios
--- @return { string } report una linea por conexion
local function wireDependencies(registry: any): { string }
	local report: { string } = {}
	local worldService = registry:Get("WorldService")
	-- `RoundService` se ASIGNA al local de ARCHIVO (arriba), no se declara aqui.
	-- Si se declarara con `local roundService = ...` seria un NUEVO local que
	-- solo vive hasta que esta funcion termine, y los handlers de
	-- `REMOTE_CHANNELS` (que viven en el ambito de archivo) lo verian como un
	-- global inexistente. Ese fue el P0 medido: el filtro recibia `nil`.
	roundService = registry:Get("RoundService")
	local playerService = registry:Get("PlayerService")
	local combatService = registry:Get("CombatService")
	local explosionService = registry:Get("ExplosionService")
	local bombService = registry:Get("BombService")
	local destructionService = registry:Get("DestructionService")
	local matchService = registry:Get("MatchService")
	local spawnService = registry:Get("SpawnService")
	local portalService = registry:Get("PortalService")
	local monsterService = registry:Get("MonsterService")
	local powerupService = registry:Get("PowerupService")

	-- Servicios de la expansion de las 99 noches (FASES 8 y 14).
	--
	-- Se resuelven AQUI, y no mas tarde, por la misma razon que los demas: el
	-- cableado ocurre entre `InitAll` y `StartAll`, asi que un servicio
	-- registrado despues ya habria pasado su `Start`.
	local nightService = registry:Get("NightService")
	local hordeService = registry:Get("HordeService")
	local eventService = registry:Get("EventService")
	local hazardService = registry:Get("HazardService")
	local miniBossService = registry:Get("MiniBossService")
	local secretService = registry:Get("SecretService")

	-- Los seis de economia, inventario, progresion, perfil, datos y tienda.
	local dataService = registry:Get("DataService")
	local profileService = registry:Get("ProfileService")
	local economyService = registry:Get("EconomyService")
	local inventoryService = registry:Get("InventoryService")
	local progressionService = registry:Get("ProgressionService")
	local shopService = registry:Get("ShopService")
	-- CodeService y QuestService comparten pareja con la tienda, asi que se
	-- resuelven aqui y no en el bloque de `Start`.
	--
	-- BUG CORREGIDO (medido en PLAY): faltaban estas DOS lineas. `connect`
	-- recibia el local de ARCHIVO `codeService`/`questService`, que en ese
	-- momento seguian siendo `nil` porque aun no se habian asignado (se
	-- hacen mas abajo, en `Start`). La consecuencia era silenciosa y grave:
	-- `[WIRING FAIL] CodeService no existe (su Init fallo)`, el `SetDependencies`
	-- nunca se ejecutaba, y su `Start` se negaba a arrancar con "sin
	-- ProfileService/EconomyService". Los codigos de canje y las misiones
	-- quedaban muertos, y el servidor entraba en "modo degradado" sin que
	-- nada mas lo delatara.
	local codeService = registry:Get("CodeService")
	local questService = registry:Get("QuestService")
	local activityService = registry:Get("ActivityService")

	-- Declara una conexion y verifica que se pudo hacer de verdad.
	-- @param label string
	-- @param consumer any servicio que recibe
	-- @param dependencies { string } nombres de lo que se le inyecta
	-- @param setter any? funcion que hace la inyeccion
	local function connect(label: string, consumer: any, dependencies: { string }, setter: any?)
		if not consumer then
			table.insert(report, ("[WIRING FAIL] %s no existe (su Init fallo)"):format(label))
			return
		end

		local missing = {}
		for _, dependency in ipairs(dependencies) do
			if not registry:Get(dependency) then
				table.insert(missing, dependency)
			end
		end

		if #missing > 0 then
			table.insert(
				report,
				("[WIRING FAIL] %s sin %s"):format(label, table.concat(missing, ", "))
			)
			return
		end

		if setter then
			setter(consumer)
		end

		table.insert(
			report,
			("[WIRING OK] %s -> %s"):format(label, table.concat(dependencies, ", "))
		)
	end

	-- ExplosionService necesita a CombatService: TODOS los danos pasan
	-- por ahi (invulnerabilidad, ronda, atribucion). Sin el, la explosion
	-- no puede danar a nadie.
	-- --- Economia, inventario, progresion, perfil, datos y tienda --------
	--
	-- Se cablean aqui y NO dentro de cada `connect` porque forman una
	-- cadena: el perfil necesita datos, la economia y la tienda necesitan
	-- el perfil, y la progresion necesita economia para pagar al subir.
	--
	-- El ORDEN de estas llamadas no es estetico: `ProfileService` recibe
	-- `DataService` antes de que ningun otro lo use, y `EconomyService`
	-- existe antes de que `ProgressionService` lo declare. Un orden
	-- equivocado aqui deja una dependencia en `nil` sin ningun error rojo.
	connect("ProfileService", profileService, { "DataService" }, function(service: any)
		service.SetDependencies(dataService, nil)
	end)

	connect("EconomyService", economyService, { "ProfileService" }, function(service: any)
		service.SetDependencies(profileService)
	end)

	connect("InventoryService", inventoryService, { "ProfileService" }, function(service: any)
		service.SetDependencies(profileService)
	end)

	-- `playerService` se inyecta para volcar el nivel del perfil en la sesion
	-- en memoria. MEDIDO EN PLAY: sin esto, `ProgressionService.AddXP` subia
	-- el atributo `Level` pero la sesion se quedaba en 1, y como los portales
	-- leen la sesion, los cuatro mundos con nivel NO se desbloqueaban nunca.
	connect(
		"ProgressionService",
		progressionService,
		{ "ProfileService", "EconomyService", "PlayerService" },
		function(service: any)
			service.SetDependencies(profileService, economyService, playerService)
		end
	)

	connect(
		"ShopService",
		shopService,
		{ "ProfileService", "EconomyService" },
		function(service: any)
			service.SetDependencies(profileService, economyService)
		end
	)

	-- CodeService lee el perfil para anotar el canje y paga con la
	-- economia. Es la MISMA pareja que necesita la tienda: por eso se
	-- cablea aqui y no dentro de su `connect`.
	connect(
		"CodeService",
		codeService,
		{ "ProfileService", "EconomyService" },
		function(service: any)
			service.SetDependencies(profileService, economyService)
		end
	)

	-- QuestService comparte pareja con la tienda y el canje: perfil para
	-- el estado, economia para el pago.
	connect(
		"QuestService",
		questService,
		{ "ProfileService", "EconomyService" },
		function(service: any)
			service.SetDependencies(profileService, economyService)
		end
	)

	-- ActivityService comparte la columna economica con QuestService y
	-- ademas necesita saber en que mundo esta el jugador (oferta) y el
	-- servicio de mundos (default). Se inyecta en un solo connect: las
	-- dependencias declaradas garantizan que los cuatro servicios existen.
	connect(
		"ActivityService",
		activityService,
		{ "ProfileService", "EconomyService", "InventoryService", "PlayerService", "WorldService" },
		function(service: any)
			service.SetDependencies(profileService, economyService, inventoryService)
			service.SetPlayerService(playerService, worldService)
		end
	)

	connect(
		"ExplosionService",
		explosionService,
		{ "DestructionService", "CombatService" },
		function(service: any)
			service.SetDependencies(destructionService, combatService)
		end
	)

	-- CombatService notifica las muertes a PlayerService, que es quien
	-- mantiene el estado de sesion y paga al asesino. `MonsterService` va
	-- como tercero (mision V2): es quien recibe el dano del cuerpo a
	-- cuerpo sobre SU registro.
	connect(
		"CombatService",
		combatService,
		{ "RoundService", "PlayerService", "MonsterService" },
		function(service: any)
			service.SetDependencies(roundService, playerService, monsterService)
		end
	)

	connect(
		"BombService",
		bombService,
		{ "RoundService", "ExplosionService" },
		function(service: any)
			service.SetDependencies(roundService, explosionService)
			-- El registro de mundos NO es dependencia del ciclo de vida (el
			-- servicio arranca sin el), pero BombService lo necesita para saber
			-- cual es la arena por defecto. Sin esta llamada el rectangulo por
			-- defecto quedaba sin nombre y `IsInsideArena` caia al primer
			-- nombre de la tabla.
			service.SetWorldService(worldService)
		end
	)

	-- `spawnService` se inyecta ADEMAS de los tres anteriores: sin el,
	-- `player.RespawnLocation` queda en `nil` y Roblox decide el punto de
	-- reaparicion por su cuenta (el origen, que aqui esta en mitad del
	-- vacio entre el lobby y la arena).
	--
	-- `progressionService` y `economyService` van al final y son OPCIONALES:
	-- sin ellos, las recompensas caen en el camino viejo de la sesion y el
	-- juego sigue siendo jugable. Exigirlos uniria la ronda a la
	-- persistencia, y una caida del DataStore no puede tumbar la partida.
	connect(
		"PlayerService",
		playerService,
		{ "RoundService", "CombatService", "MatchService", "SpawnService" },
		function(service: any)
			service.SetDependencies(
				roundService,
				combatService,
				matchService,
				spawnService,
				progressionService,
				economyService
			)
		end
	)

	-- SpawnService necesita saber en que zona esta el jugador para
	-- rescatarlo en el sitio correcto (arena si hay ronda, lobby si no).
	connect("SpawnService", spawnService, { "RoundService", "MatchService" }, function(service: any)
		service.SetDependencies(roundService, matchService)
	end)

	connect("MatchService", matchService, {
		"RoundService",
		"PlayerService",
		"BombService",
		"DestructionService",
		"CombatService",
		"MonsterService",
		"WorldService",
	}, function(service: any)
		service.SetDependencies(
			roundService,
			playerService,
			bombService,
			destructionService,
			combatService,
			monsterService,
			worldService
		)
	end)

	-- PortalService necesita el mundo (el catalogo de acceso), el destino (para
	-- teletransportar), la ronda (para impedir salir durante la partida) y el
	-- jugador (para diagnostico de nivel; ya NO bloquea por nivel: FASE 3).
	connect(
		"PortalService",
		portalService,
		{ "WorldService", "MatchService", "RoundService", "PlayerService" },
		function(service: any)
			service.SetDependencies(worldService, matchService, roundService, playerService)
		end
	)

	-- MonsterService necesita ronda (para saber si hay partida), combate (unico
	-- camino de dano) y jugador (para pagar la recompensa del monstruo). Se
	-- cablea DESPUES de los tres, que es la unica forma de que las tres
	-- inyecciones sean `nil` en vez de un servicio a medio construir.
	connect(
		"MonsterService",
		monsterService,
		{ "RoundService", "CombatService", "PlayerService", "WorldService" },
		function(service: any)
			service.SetDependencies(roundService, combatService, playerService, worldService)
		end
	)

	-- PowerupService: solo necesita el mundo para saber cual es el
	-- directorio por defecto cuando la ronda no indica otro, y
	-- `BombService` para que el powerup "+BOMBA" conceda capacidad REAL.
	connect("PowerupService", powerupService, { "WorldService" }, function(service: any)
		service.SetDependencies(worldService, nil, bombService)
	end)

	-- HordeService (FASE 14): el reloj decide el tamano, `MonsterService` le
	-- notifica las bajas y la economia paga el premio.
	--
	-- La economia y las misiones se pasan a proposito como `nil` opcional: el
	-- `connect` de abajo exige solo los servicios que son REALMENTE necesarios
	-- para arrancar, y estos dos no lo son. Sin ellos, las hordas se cuentan y
	-- se limpian igual y lo unico que falta es el cobro, que espreferible a que
	-- no haya hordas en absoluto.
	connect(
		"HordeService",
		hordeService,
		{ "NightService", "MonsterService" },
		function(service: any)
			service.SetDependencies(monsterService, nightService, economyService, questService)
		end
	)

	-- EventService: el reloj decide si rueda y cuanto dura; jugador y
	-- misiones van como opcionales por la misma razon que en HordeService.
	-- MonsterService va como dependencia (mision V2): es quien pone el
	-- CUERPO del evento en el mapa.
	connect(
		"EventService",
		eventService,
		{ "NightService", "MonsterService" },
		function(service: any)
			service.SetDependencies(nightService, playerService, questService, monsterService)
		end
	)

	-- MiniBossService: necesita a `MonsterService` para invocar el spawn
	-- de sus NPC dentro de la zona. El resto son opcionales.
	connect("MiniBossService", miniBossService, { "MonsterService" }, function(service: any)
		service.SetDependencies(monsterService, playerService, questService, nightService)
	end)

	-- HazardService: el dano pasa por `CombatService` (autoridad unica)
	-- y la emboscada genera enemigos con `MonsterService`. Sin ellos el
	-- servicio arranca igual: las zonas se ven y lo unico que falta es
	-- el efecto, que es una degradacion visible y no un crash.
	connect(
		"HazardService",
		hazardService,
		{ "CombatService", "MonsterService" },
		function(service: any)
			service.SetDependencies(combatService, monsterService)
		end
	)

	connect(
		"SecretService",
		secretService,
		{ "ProfileService", "EconomyService", "QuestService" },
		function(service: any)
			service.SetDependencies(profileService, economyService, questService)
		end
	)

	-- LootService: entrega por inventario, gemas por economia.
	connect(
		"LootService",
		registry:Get("LootService"),
		{ "InventoryService", "EconomyService" },
		function(service: any)
			service.SetDependencies(inventoryService, economyService)
		end
	)

	-- MonsterService -> LootService y MiniBossService -> LootService:
	-- las flechas inversas que hacen que el drop EXISTA en runtime.
	-- Mismo patron pcall que el resto de observadores.
	local lootService = registry:Get("LootService")

	if monsterService and lootService then
		pcall(function()
			monsterService.SetLootService(lootService)
		end)
		table.insert(report, "[WIRING OK] MonsterService -> LootService")
	else
		table.insert(report, "[WIRING FAIL] MonsterService/LootService no disponibles")
	end

	if miniBossService and lootService then
		pcall(function()
			miniBossService.SetLootService(lootService)
		end)
		table.insert(report, "[WIRING OK] MiniBossService -> LootService")
	else
		table.insert(report, "[WIRING FAIL] MiniBossService/LootService no disponibles")
	end

	-- AchievementService: perfil y economia; y su UNICA fuente de
	-- metricas, el reenvio de QuestService.
	local achievementService = registry:Get("AchievementService")

	connect(
		"AchievementService",
		achievementService,
		{ "ProfileService", "EconomyService" },
		function(service: any)
			service.SetDependencies(profileService, economyService)
		end
	)

	if questService and achievementService then
		pcall(function()
			questService.SetAchievementService(achievementService)
		end)
		table.insert(report, "[WIRING OK] QuestService -> AchievementService")
	else
		table.insert(report, "[WIRING FAIL] QuestService/AchievementService no disponibles")
	end

	-- BestiaryService: perfil; observa muertes como el loot.
	local bestiaryService = registry:Get("BestiaryService")

	connect("BestiaryService", bestiaryService, { "ProfileService" }, function(service: any)
		service.SetDependencies(profileService)
	end)

	if monsterService and bestiaryService then
		pcall(function()
			monsterService.SetBestiaryService(bestiaryService)
		end)
		table.insert(report, "[WIRING OK] MonsterService -> BestiaryService")
	else
		table.insert(report, "[WIRING FAIL] MonsterService/BestiaryService no disponibles")
	end

	-- PuzzleService: el pago va por economia; las misiones son opcionales.
	connect(
		"PuzzleService",
		registry:Get("PuzzleService"),
		{ "EconomyService" },
		function(service: any)
			service.SetDependencies(economyService, questService)
		end
	)

	-- PowerupService -> MonsterService: la flecha que hace que CONGELAR
	-- tenga efecto.
	--
	-- MEDIDO EN AUDITORIA: sin esta flecha, `Freeze` no tenia a quien
	-- congelar. El powerup se recogia, se publicaba `PowerupFreezeUntil` y no
	-- pasaba nada: el jugador veia "CONGELAR no funciona" con razon, y el
	-- atributo en el HUD hacia que pareciese un fallo de estado y no de
	-- cableado.
	--
	-- Es al reves por el mismo motivo que la de `ExplosionService`: el
	-- registro de servicios es topologico y esta flecha seria un ciclo.
	if powerupService and monsterService then
		pcall(function()
			powerupService.SetMonsterService(monsterService)
		end)
		table.insert(report, "[WIRING OK] PowerupService -> MonsterService")
	else
		table.insert(report, "[WIRING FAIL] PowerupService/MonsterService no disponibles")
	end

	-- MatchService -> PowerupService: la ronda es quien genera los powerups
	-- de la arena. Sin esta flecha, `SpawnPowerupsForRound` devolveria 0 en
	-- silencio y nadie sabria por que no hay nada que recoger.
	if matchService and powerupService then
		matchService.SetPowerupService(powerupService)
		table.insert(report, "[WIRING OK] MatchService -> PowerupService")
	else
		table.insert(report, "[WIRING FAIL] MatchService/PowerupService no disponibles")
	end

	-- La flecha va de ExplosionService HACIA MonsterService: sin esto las
	-- explosiones no encuentro los Humanoids de los monstruos y el PvE no
	-- recibe dano. Se cablea aqui y no dentro del `connect` anterior porque
	-- es al reves: MonsterService no depende de ExplosionService, y declarar
	-- esa dependencia crearia un ciclo en el orden topologico del registro.
	if explosionService and monsterService then
		explosionService.SetMonsterService(monsterService)
		table.insert(report, "[WIRING OK] ExplosionService -> MonsterService")
	else
		table.insert(report, "[WIRING FAIL] ExplosionService/MonsterService no disponibles")
	end

	-- MonsterService -> MiniBossService: la flecha que hace que los
	-- mini-bosses EXISTAN en runtime.
	--
	-- AUDITORIA (FASE 2): `MonsterService.OnMonsterDied` avisa a su
	-- observador opcional con `pcall(Service._miniBossService.OnMonsterDied,
	-- ...)`, pero NADIE llamaba jamas a `SetMiniBossService`: el setter
	-- existia declarado y sin invocar. La consecuencia era silenciosa y
	-- completa: los tests de contrato pasaban, pero en el juego la
	-- notificacion de muerte no tenia destinatario y `MiniBossService`
	-- esperaba en balde - ningun mini-boss aparecia nunca.
	--
	-- Va con `pcall` y fuera de `connect` por el mismo motivo que
	-- `PowerupService -> MonsterService`: es una flecha inversa al orden
	-- topologico del registro.
	if monsterService and miniBossService then
		pcall(function()
			monsterService.SetMiniBossService(miniBossService)
		end)
		table.insert(report, "[WIRING OK] MonsterService -> MiniBossService")
	else
		table.insert(report, "[WIRING FAIL] MonsterService/MiniBossService no disponibles")
	end

	-- MonsterService -> EventService: la flecha que hace que las bajas
	-- de un evento CUENTEN para su objetivo (mision V2, Bloque 1).
	-- Mismo patron inverso con pcall que el de MiniBossService.
	if monsterService and eventService then
		pcall(function()
			monsterService.SetEventService(eventService)
		end)
		table.insert(report, "[WIRING OK] MonsterService -> EventService")
	else
		table.insert(report, "[WIRING FAIL] MonsterService/EventService no disponibles")
	end

	-- QuestService NO depende de los servicios de juego: al reves, son los
	-- que le AVISAN de que algo ocurrio. Se cablea con setters y no con
	-- `connect`, porque declararla como dependencia crearia un ciclo en el
	-- orden topologico del registro.
	--
	-- Se hace con un `pcall` por servicio: un fallo al cablear las misiones
	-- NO puede impedir que las bombas, las explosiones o las rondas
	-- funcionen. Perder el progreso de las misiones es una degradacion
	-- visible; perder el combate es el juego caido.
	if questService then
		for _, name in ipairs({
			"BombService",
			"ExplosionService",
			"MonsterService",
			"MatchService",
		}) do
			local target = registry:Get(name)
			local wired = pcall(function()
				if target and target.SetQuestService then
					target.SetQuestService(questService)
				end
			end)

			if wired and target and target.SetQuestService then
				table.insert(report, ("[WIRING OK] %s -> QuestService"):format(name))
			elseif target and target.SetQuestService then
				table.insert(report, ("[WIRING FAIL] %s -> QuestService"):format(name))
			end
		end
	end

	-- ActivityService (exploracion, FASE 3): MonsterService avanza las
	-- actividades de caza al notificar muertes. El push usa `pcall` por
	-- servicio, como el de QuestService: un servicio sin `SetActivityService`
	-- (Destruction/Secret/Event, en FASE 3 follow-up) se salta sin error.
	if activityService then
		if monsterService then
			pcall(function()
				if monsterService.SetActivityService then
					monsterService.SetActivityService(activityService)
				end
			end)
			table.insert(report, "[WIRING OK] MonsterService -> ActivityService (Hunt)")
		else
			table.insert(report, "[WIRING SKIP] MonsterService -> ActivityService (no MonsterService)")
		end
	end

	-- MatchService necesita conocer el mundo por defecto para validar
	-- a quien puede entrar en el (FASE 18 lo hara con portales).
	if worldService then
		table.insert(
			report,
			("[WIRING OK] mundo por defecto: %s"):format(tostring(worldService.GetDefaultWorldId()))
		)
	end

	-- El informe se imprime aqui y no solo se devuelve: un fallo de
	-- cableado es la causa mas silenciosa de "el juego no hace nada".
	for _, line in ipairs(report) do
		if string.sub(line, 1, #WIRING_FAIL_PREFIX) == WIRING_FAIL_PREFIX then
			Logger.Error(line)
		else
			Logger.Info(line)
		end
	end

	return report
end

-- Canales remotos y sus handlers.
--
-- Un canal SIN handler sigue siendo validado y limitado, y el gateway
-- descarta la peticion en vez de ejecutarla. Es preferible a declarar
-- funciones vacias que aparenten funcionar.
--
-- Solo hay handlers para lo que el servidor puede resolver de verdad:
--	- PlayerAction.SetReady / RequestState: estado de sesion.
--	- BombAction.Place: coloca bomba con validacion en servidor.
-- El resto de canales (Shop, Inventory, Quest, Portal, Party, Settings)
-- llega en sus fases correspondientes (32, 14, 35, 18, 21, 31).
local REMOTE_CHANNELS = {
	[GameConstants.RemoteAction.Player] = {
		SetReady = function(player: Player, payload: any)
			if playerService then
				playerService.SetReady(player, payload == true)
			end
		end,

		RequestState = function(player: Player, _payload: any)
			-- Reenvia el estado al cliente que lo pide. No concede nada:
			-- solo publica informacion que el jugador ya tiene.
			if playerService then
				local session = playerService.GetSessionFromPlayer(player)
				if session then
					player:SetAttribute("Level", session.Level)
					player:SetAttribute("XP", session.XP)
					player:SetAttribute("Coins", session.Coins)
					player:SetAttribute("Gems", session.Gems)
				end
			end
		end,
	},

	[GameConstants.RemoteAction.Bomb] = {
		Place = function(player: Player, payload: any)
			if not bombService then
				Logger.Warn("BombAction.Place recibido sin BombService")
				return
			end

			-- La capa de CONTEXTO va antes que el servicio de juego, y es
			-- distinta de la gateway: la gateway ya valido la forma (es un
			-- Vector3 finito). Aqui se valida el CONTEXTO, que es lo que la
			-- forma no puede saber:
			--
			--   - que haya ronda (el lobby es zona segura)
			--   - que la distancia la mida el SERVIDOR
			--   - el cooldown por accion
			--
			-- La distancia se mide aqui, en el servidor, y NUNCA se toma del
			-- payload: si el cliente mandara la distancia, el filtro
			-- comprobaria un dato que el atacante controla.
			local allowed, reason = Service_CheckRequest(player, "BombAction", "Place", {
				serverState = roundService and roundService.GetState() or nil,
				distance = measureDistance(player, payload),
				maxDistance = GameConfig.BombPlacementRange,
			})

			if not allowed then
				Logger.Debug(
					("bomba rechazada por anti-exploit para %s: %s"):format(
						player.Name,
						tostring(reason)
					)
				)
				return
			end

			local placed, bombReason = bombService.TryPlaceBomb(player, payload)
			if not placed then
				-- El motivo se registra SIEMPRE: un rechazo sin registro
				-- es imposible de depurar desde fuera.
				Logger.Debug(
					("bomba rechazada para %s: %s"):format(player.Name, tostring(bombReason))
				)
			end
		end,
	},

	-- El canal de la tienda. El payload es SOLO el `ItemId` pedido: el
	-- cliente NO manda precio, ni cantidad, ni saldo. El servidor busca el
	-- precio en el catalogo y decide si puede cobrar.
	--
	-- El `requestId` lo genera el SERVIDOR, no el cliente. Es lo que evita
	-- que un jugador compre dos veces lo mismo fingiendo que son dos
	-- compras distintas: el id lleva su `UserId` y un contador.
	[GameConstants.RemoteAction.Shop] = {
		Preview = function(player: Player, payload: any)
			if not shopService then
				Logger.Warn("ShopAction.Preview recibido sin ShopService")
				return
			end

			-- `Preview` NO compra nada: solo responde si se podria comprar.
			-- Es la peticion que la UI hace para pintar el boton, y si
			-- cobrara, el jugador perderia monedas por pasar el raton.
			local canBuy, rejection = shopService.CanBuy(player, payload)
			player:SetAttribute("ShopCanBuy", canBuy)
			player:SetAttribute("ShopRejection", rejection)
		end,

		Purchase = function(player: Player, payload: any)
			if not shopService then
				Logger.Warn("ShopAction.Purchase recibido sin ShopService")
				return
			end

			-- El id se construye en el SERVIDOR. Si lo mandara el cliente,
			-- bastaria reenviar la misma peticion con otro id para pagar dos
			-- veces, que es exactamente lo que el control de idempotencia
			-- tiene que impedir.
			shopService._nextRequestId = (shopService._nextRequestId or 0) + 1
			local requestId = ("shop:%d:%d"):format(player.UserId, shopService._nextRequestId)

			local outcome, rejection, receipt = shopService.Purchase(player, payload, requestId)

			-- La respuesta va por ATRIBUTOS, no por un remoto nuevo. Asi la
			-- UI reacciona sin que este servicio tenga que conocer ningun
			-- canal de salida, y anadir un `ShopResult` seria crear un
			-- remoto duplicado para lo que los atributos ya resuelven.
			player:SetAttribute("ShopOutcome", outcome)
			player:SetAttribute("ShopRejection", rejection)
			player:SetAttribute("ShopReceipt", receipt)
		end,
	},

	-- El canal de inventario. El payload es el `ItemId` que el jugador
	-- quiere usar o equipar, NUNCA lo que dice que tiene.
	[GameConstants.RemoteAction.Inventory] = {
		Equip = function(player: Player, payload: any)
			if not inventoryService then
				Logger.Warn("InventoryAction.Equip recibido sin InventoryService")
				return
			end

			local ok, reason = inventoryService.EquipItem(player, payload)
			player:SetAttribute("InventoryResult", ok and "equipped" or "rejected")
			player:SetAttribute("InventoryReason", reason)
		end,

		Unequip = function(player: Player, payload: any)
			if not inventoryService then
				Logger.Warn("InventoryAction.Unequip recibido sin InventoryService")
				return
			end

			-- Aqui el payload es la RANURA, no el item: desequipar es
			-- "quitar lo que hay puesto en Head", no "quitar este item".
			local ok, _, reason = inventoryService.UnequipItem(player, payload)
			player:SetAttribute("InventoryResult", ok and "unequipped" or "rejected")
			player:SetAttribute("InventoryReason", reason)
		end,
	},

	-- El canal de misiones. El payload es el `questId` que el jugador quiere
	-- reclamar, NUNCA el progreso ni la recompensa: el servidor mira SU
	-- estado y decide.
	--
	-- `ClaimDaily` NO lleva payload. El cliente no dice "es el dia 3": el
	-- servidor mira la fecha y su propio registro. Aceptar un indice de
	-- racha desde el cliente seria permitir saltarse la espera.
	[GameConstants.RemoteAction.Quest] = {
		Claim = function(player: Player, payload: any)
			if not questService then
				Logger.Warn("QuestAction.Claim recibido sin QuestService")
				return
			end

			questService.TryClaim(player, payload)
		end,

		ClaimDaily = function(player: Player, _payload: any)
			if not questService then
				Logger.Warn("QuestAction.ClaimDaily recibido sin QuestService")
				return
			end

			questService.TryClaimDaily(player)
		end,
	},

	-- Exploracion (FASE 3). El cliente pide la oferta, interactua con un
	-- punto de interes o reclama; el servidor resuelve el mundo del jugador,
	-- comprueba proximidad y decide el progreso y la recompensa. La respuesta
	-- va por atributos: `ActivityOffer`, `ActivityProgress`,
	-- `ActivityClaimOutcome`.
	[GameConstants.RemoteAction.Explore] = {
		RequestOffer = function(player: Player, payload: any)
			if not activityService then
				Logger.Warn("ExploreAction.RequestOffer recibido sin ActivityService")
				return
			end

			-- El `size` (numero) lo pide el cliente como maximo; el servidor lo
			-- acota al catalogo del mundo. El mundo NO viene del cliente: lo
			-- resuelve el servicio a partir de la sesion del jugador.
			activityService.TryRequestOffer(player, payload)
		end,

		Interact = function(player: Player, payload: any)
			if not activityService then
				Logger.Warn("ExploreAction.Interact recibido sin ActivityService")
				return
			end

			activityService.TryInteract(player, payload)
		end,

		Claim = function(player: Player, payload: any)
			if not activityService then
				Logger.Warn("ExploreAction.Claim recibido sin ActivityService")
				return
			end

			activityService.TryClaim(player, payload)
		end,
	},

	-- El canal de codigos. El payload es el TEXTO escrito por el jugador,
	-- nunca la recompensa: el cliente no dice "dame 9999 coins", dice
	-- "este codigo es X" y el servidor busca la recompensa en su catalogo.
	--
	-- La respuesta va por ATRIBUTOS (`CodeOutcome`, `CodeRejection`,
	-- `CodeReward`), igual que la compra. El servicio ya publica el
	-- resultado en `TryRedeem`; aqui solo se llama, y se registra el fallo
	-- cuando el servicio ni siquiera esta disponible, que es el caso en el
	-- que el jugador veria un silencio sin explicacion.
	[GameConstants.RemoteAction.Code] = {
		Redeem = function(player: Player, payload: any)
			if not codeService then
				Logger.Warn("CodeAction.Redeem recibido sin CodeService")
				return
			end

			codeService.TryRedeem(player, payload)
		end,
	},

	-- El canal del Keshusy Core. Sin payload: el cliente solo pide
	-- aportar un fragmento, nunca dice cuanta carga ni que estado.
	[GameConstants.RemoteAction.Core] = {
		Interact = function(player: Player, _payload: any)
			if not coreService then
				Logger.Warn("CoreAction.Interact recibido sin CoreService")
				return
			end

			coreService.HandleInteract(player, _payload)
		end,

		RequestState = function(player: Player, _payload: any)
			if not coreService then
				return
			end

			-- Concede NADA: solo publica informacion que el nucleo
			-- ya decidio en el servidor.
			player:SetAttribute("CoreState", coreService.GetState().State)
			player:SetAttribute("CoreCharge", coreService.GetState().Charge)
		end,
	},

	-- El canal de portales es la UNICA via de entrada a un mundo. El
	-- payload es solo el `worldId` pedido: el servidor decide si el viaje
	-- procede y calcula el destino. Un cliente que invente un `worldId` no
	-- tiene portal asociado y la peticion se descarta.
	[GameConstants.RemoteAction.Portal] = {
		Enter = function(player: Player, payload: any)
			if not portalService then
				Logger.Warn("PortalAction.Enter recibido sin PortalService")
				return
			end

			portalService.HandleEnter(player, payload)
		end,
	},

	[GameConstants.RemoteAction.Party] = {},
	[GameConstants.RemoteAction.Settings] = {},

	-- El canal del combate cuerpo a cuerpo (mision V2). Las acciones no
	-- llevan payload: la gateway valida la forma (ninguna) y el ritmo
	-- (rate limit), y `CombatService` valida el CONTEXTO: ronda en
	-- curso, jugador vivo y cooldown. La distancia al objetivo nunca se
	-- toma del cliente porque no HAY objetivo en el payload.
	[GameConstants.RemoteAction.Combat] = {
		Melee = function(player: Player, _payload: any)
			if combatService then
				combatService.TryMelee(player)
			end
		end,
		Dash = function(player: Player, _payload: any)
			if combatService then
				combatService.TryDash(player)
			end
		end,
		Ability = function(player: Player, _payload: any)
			if combatService then
				combatService.TryAbility(player)
			end
		end,
	},
}

--- Comprueba que los modulos base esten presentes y sean validos.
--- @return boolean ok
--- @return string[] missing
function ServerMain.VerifyRequiredModules(): (boolean, { string })
	local missing: { string } = {}

	for _, entry in ipairs(REQUIRED_MODULES) do
		if not entry.instance then
			table.insert(missing, entry.name)
		end
	end

	if #missing > 0 then
		Logger.Warn("Missing required modules: " .. table.concat(missing, ", "))
		return false, missing
	end

	return true, missing
end

--- Punto de inicializacion del servidor.
---
--- Los errores de arranque NO se silencian: cada fallo se registra en
--- el output con su mensaje, y ademas se acumula en `ServerMain.Errors`
--- para poder consultarlo desde la consola de Studio.
--- @return boolean success
function ServerMain.Initialize(): boolean
	local errors: { string } = {}
	ServerMain.Errors = errors

	local verified, missing = ServerMain.VerifyRequiredModules()
	if not verified then
		local message = "Server initialization aborted. Missing: " .. table.concat(missing, ", ")
		Logger.Error(message)
		table.insert(errors, message)
		return false
	end

	Logger.Info(
		("%s v%s | server starting..."):format(Logger.GetGameName(), Logger.GetGameVersion())
	)

	-- Un unico registro por servidor. Lo consultan los servicios.
	local registry = ServiceRegistry.new()
	ServerMain.Registry = registry

	-- `SERVICES[].module` guarda la INSTANCIA ModuleScript, no el valor
	-- que devuelve. Hay que `require`la aqui.
	--
	-- AUDITORIA (P0): se pasaba `entry.module` tal cual a `Register`, y
	-- `ServiceRegistry:Register` rechaza con "modulo invalido" lo que no
	-- sea `table`. Una Instance no es una tabla, asi que los NUEVE
	-- servicios se rechazaban uno a uno: "ServiceRegistry: 0 servicios
	-- inicializados", "[BOOT FAIL] ... no arranco (estado: nil)" para
	-- todos, y ningun error rojo en el Output. El servidor arrancaba
	-- "correcto" sin un solo servicio vivo. Los tests unitarios no lo
	-- detectan porque registraban modulos de mentira que ya eran tablas.
	--
	-- El `pcall` no esconde nada: si el modulo revienta al cargarse,
	-- se registra el error REAL y el servicio queda sin registrar, que
	-- es justo lo que el informe de arranque tiene que detectar.
	for _, entry in ipairs(SERVICES) do
		local ok, module = pcall(require, entry.module)

		if not ok then
			local message = ("no se pudo cargar '%s': %s"):format(entry.name, tostring(module))
			Logger.Error(message)
			table.insert(errors, message)
		elseif type(module) ~= "table" then
			local message = ("'%s' no devuelve una tabla (devuelve %s)"):format(
				entry.name,
				type(module)
			)
			Logger.Error(message)
			table.insert(errors, message)
		else
			local registered, registerError =
				registry:Register(entry.name, module, entry.dependencies)
			if not registered then
				local message = ("no se pudo registrar '%s': %s"):format(
					entry.name,
					tostring(registerError)
				)
				Logger.Error(message)
				table.insert(errors, message)
			end
		end
	end

	return true
end

--- Arranca todos los servicios registrados y el gateway de remotos.
--- @return boolean success
function ServerMain.Start(): boolean
	if not ServerMain.Initialize() then
		return false
	end

	local registry = ServerMain.Registry

	-- ORDEN DE ARRANQUE (auditoria de integracion):
	--
	-- BUG CORREGIDO: antes se llamaba `Registry:Start()`, que hacia Init y
	-- Start en un solo paso, y las dependencias se cableaban DESPUES. Como
	-- `Registry:Get` solo devolvia instancias ya arrancadas, `MatchService`
	-- arrancaba sin `RoundService` inyectado y su `Start` devolvia false
	-- ANTES de suscribirse a `OnStateChanged`. En el juego eso significaba:
	--   - nadie se teletransportaba nunca a la arena,
	--   - `RoundService` avanzaba de estado sin nadie escuchando,
	--   - las bombas nunca podian colocarse (no habia arena),
	--   - y todo ello con el output aparentemente "limpio".
	--
	-- Ahora: Init de todo -> cablear -> Start de todo. Ese es el unico
	-- orden en el que las dependencias tienen sentido.
	local initialized = registry:InitAll()

	-- Cableado. `Get` ya devuelve los servicios inicializados, asi que
	-- esta fase ve exactamente los mismos objetos que vera `Start`.
	ServerMain.WiringReport = wireDependencies(registry)

	-- Los handlers de remotos consultan estos en caliente.
	playerService = registry:Get("PlayerService")
	bombService = registry:Get("BombService")
	-- El handler de `PortalAction.Enter` vive fuera de `wireDependencies`,
	-- asi que necesita la misma referencia a nivel de modulo que los demas.
	portalService = registry:Get("PortalService")
	-- El nucleo se inyecta igual: su handler necesita el servicio vivo.
	coreService = registry:Get("CoreService")

	-- Los seis de la columna economica. Se asignan a los LOCALES DE
	-- ARCHIVO (declarados mas arriba), no a unos de esta funcion: el
	-- bloque que carga el perfil y los handlers de tienda e inventario
	-- los necesitan despues de que `Start` haya terminado.
	dataService = registry:Get("DataService")
	profileService = registry:Get("ProfileService")
	economyService = registry:Get("EconomyService")
	inventoryService = registry:Get("InventoryService")
	progressionService = registry:Get("ProgressionService")
	shopService = registry:Get("ShopService")
	-- El codigo se resuelve aqui, y NO dentro de `wireDependencies`: los
	-- locales de esa FUNCION mueren al terminar, y el handler del remoto
	-- lo veria como `nil` en tiempo de ejecucion. Es el mismo fallo que
	-- quedo documentado para los seis de la columna economica.
	codeService = registry:Get("CodeService")
	questService = registry:Get("QuestService")
	activityService = registry:Get("ActivityService")
	antiExploitService = registry:Get("AntiExploitService")

	for _, name in ipairs({
		"DataService",
		"ProfileService",
		"EconomyService",
		"InventoryService",
		"ProgressionService",
		"ShopService",
		"CodeService",
		"QuestService",
	}) do
		if not registry:Get(name) then
			table.insert(report, ("[WIRING FAIL] %s no arranco"):format(name))
		end
	end

	-- El nucleo difunde por el mismo canal bidireccional que usa el
	-- cliente para pedir fragmentos. Se le da la FUNCION de emision y no
	-- el remoto entero, para que el servicio no dependa de como esten
	-- cableados los remotos y se pueda probar aislado.
	if coreService and coreService.SetBroadcast then
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		local coreRemote = remotes and remotes:FindFirstChild(GameConstants.RemoteAction.Core)

		if coreRemote and coreRemote:IsA("RemoteEvent") then
			coreService.SetBroadcast(function(state)
				coreRemote:FireAllClients(state)
			end)
		else
			-- Sin remoto el nucleo sigue funcionando: solo pierde la
			-- barra del cliente. Es una degradacion, no un fallo.
			Logger.Warn("CoreService: sin CoreAction; el nucleo no se difunde.")
		end
	end

	local started = registry:StartAll()

	-- Ciclo de vida del perfil: carga al entrar, guardado al salir.
	--
	-- Se conecta DESPUES de `StartAll` porque hasta ahi no existen los
	-- servicios. Sin esta conexion, el perfil nunca se carga: la economia
	-- daria cero a todo el mundo y la tienda rechazaria todas las compras
	-- con "no_profile", sin ningun error visible.
	if profileService then
		local profileMaid = ServerMain.ProfileMaid or Maid.new()
		ServerMain.ProfileMaid = profileMaid
		ServerMain.ProfileService = profileService

		profileMaid:Connect(Players.PlayerAdded, function(player: Player)
			-- El bloqueo de sesion va ANTES de leer. Si otro servidor tiene
			-- el perfil, leerlo y guardarlo seria competir por el mismo
			-- dato. Con el bloqueo tomado, la lectura ya es segura.
			if dataService then
				local acquired, reason = dataService.AcquireLock(player.UserId)
				if not acquired then
					Logger.Warn(
						("ServerMain: %s no puede cargar su perfil: %s"):format(
							player.Name,
							tostring(reason)
						)
					)
					player:Kick(
						"Tu perfil esta siendo usado en otro servidor. Intentalo en un momento."
					)
					return
				end
			end

			profileService.LoadProfile(player)
		end)

		-- Se guarda al salir, pero NO se depende solo de este evento: si el
		-- servidor muere de golpe no se dispara. `DataService` tiene
		-- ademas autosave periodico y `BindToClose` mas abajo.
		profileMaid:Connect(Players.PlayerRemoving, function(player: Player)
			profileService.SaveProfile(player)
			profileService.UnloadProfile(player)
		end)

		-- Un jugador que YA esta conectado cuando arranca el servidor (por
		-- ejemplo en una prueba) no dispara `PlayerAdded`. Sin esto, su
		-- perfil no se cargaria nunca.
		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(function()
				if dataService then
					local acquired = dataService.AcquireLock(player.UserId)
					if not acquired then
						return
					end
				end
				profileService.LoadProfile(player)
			end)
		end
	end

	-- Gateway de remotos: valida y limita TODO lo que llega del cliente.
	-- Se arranca despues de los servicios para que sus handlers ya
	-- puedan consultar el registro.
	local gateway = RemoteGateway.new()
	local registeredChannels = gateway:RegisterDefaults(REMOTE_CHANNELS)
	gateway:Start()
	ServerMain.Gateway = gateway

	Logger.Info(
		("RemoteGateway: %d canales validados (%s)"):format(
			#registeredChannels,
			table.concat(registeredChannels, ", ")
		)
	)

	-- Resumen de arranque. Se imprime SIEMPRE, no solo en fallo: sin esto
	-- no hay forma de saber desde el Output que sistema arranco y cual no.
	Logger.Info("[BOOT] SERVIDOR ARRANCADO")
	for _, line in ipairs(ServerMain.GetBootReport()) do
		Logger.Info(line)
	end

	if not initialized then
		Logger.Error("[BOOT FAIL] hay servicios cuyo Init fallo; revisa el informe de arriba.")
	end

	if not started then
		Logger.Error("[BOOT FAIL] hay servicios cuyo Start fallo; revisa el informe de arriba.")
	end

	return initialized and started
end

--- Informe del arranque: una linea por servicio con su estado real.
---
--- Es la unica forma de distinguir "todo bien" de "arranca en modo
--- degradado" leyendo el Output, sin abrir el explorador a cada paso.
--- @return { string } report
function ServerMain.GetBootReport(): { string }
	local report = {}

	if not ServerMain.Registry then
		table.insert(report, "[BOOT] no hay registro de servicios")
		return report
	end

	table.insert(
		report,
		("[BOOT] estado del servidor: %s"):format(ServerMain.Registry:GetServerState())
	)

	for _, line in ipairs(ServerMain.Registry:GetReport()) do
		table.insert(report, ("[BOOT]   %s"):format(line))
	end

	local failed = 0
	for _, name in ipairs(ServerMain.CriticalServices) do
		local _, state = ServerMain.Registry:GetEntry(name)
		if tostring(state) ~= GameConstants.ServiceState.Started then
			failed += 1
			table.insert(
				report,
				("[BOOT FAIL] %s no arranco (estado: %s)"):format(name, tostring(state))
			)
		end
	end

	if failed == 0 then
		table.insert(
			report,
			("[BOOT] servicios criticos OK (%d)"):format(#ServerMain.CriticalServices)
		)
	end

	return report
end

--- Apaga el servidor de forma ordenada (regla de shutdown).
function ServerMain.Shutdown()
	-- Ultimo guardado, ANTES de apagar los servicios.
	--
	-- Va primero a proposito: `Registry:Stop` llama a `Destroy` de cada
	-- servicio, y `DataService.Destroy` ya guarda. Este guardado previo es
	-- la garantia de que un perfil se escribe mientras los servicios siguen
	-- vivos. Un cierre ordenado con el orden invertido perderia los cambios
	-- de la ultima partida, que es justo lo que el jugador no espera.
	if ServerMain.Registry then
		local dataEntry = ServerMain.Registry:Get("DataService")
		if dataEntry and dataEntry.SaveAll then
			local saved = dataEntry.SaveAll()
			if saved > 0 then
				Logger.Info(("ServerMain: %d perfiles guardados en el cierre"):format(saved))
			end
		end
	end

	if ServerMain.Gateway then
		ServerMain.Gateway:Stop()
		ServerMain.Gateway = nil
	end

	if ServerMain.ProfileMaid then
		pcall(function()
			ServerMain.ProfileMaid:Destroy()
		end)
		ServerMain.ProfileMaid = nil
	end

	if ServerMain.Registry then
		ServerMain.Registry:Stop()
	end
end

ServerMain.Registry = nil
ServerMain.Gateway = nil

ServerMain.Start()

-- Regla de shutdown: el servidor deja de aceptar trabajo, detiene
-- los servicios en orden inverso y limpia conexiones. El bloqueo se
-- limita a un margen corto para no retener el cierre de Roblox.
game:BindToClose(function()
	local startTime = os.clock()

	ServerMain.Shutdown()

	Logger.Debug(("cierre ordenado completado en %.2fs"):format(os.clock() - startTime))
end)

return ServerMain
