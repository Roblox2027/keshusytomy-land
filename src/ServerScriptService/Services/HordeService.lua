--!strict
--[[
	HordeService
	Los eventos de HORDA (FASE 14).

	QUE APORTA Y QUE DELEGA
	-----------------------
	NO calcula nada de la horda: el tamano, los estados y la UNICA entrega del
	premio son de `HordeRules`. Aqui solo seedra lo que el motor aporta: los
	NPC, los hilos y la cuenta de enemigos vivos.

	LA REGLA DE AUTORIDAD
	---------------------
	El servicio NO puede decidir ni quien muere ni cuando se paga. Registra
	bajas que `MonsterService` le notifica y PIDE el premio a `HordeRules`, que
	es quien tiene el cortafuegos de una sola entrega.

	El UNICO camino para cobrar una horda
	--------------------------------------
	`HordeRules.ClaimReward`. Si este servicio tuviera un `if killed == total
	then pay()` propio, habria dos caminos de pago y el segundo seria el que
	falla. Por eso TODOS los caminos de pago pasan por ahi, incluido el
	`HandleMonsterDeath` de abajo.

	LA FASE QUE IMPORTA
	-------------------
	Un NPC de horda tiene la MISMA maquina de muerte que cualquier otro
	monstruo: la de `MonsterDeathRules` (`Alive -> Dying -> Dead -> Cleaned`).
	Este servicio no implementa nada de eso. Si lo hiciera, el bug "Health = 0
	pero el NPC sigue vivo" reapareceria aqui con otro disfraz.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local UTILS = SHARED:WaitForChild("Utils")

local HordeRules = require(SHARED:WaitForChild("Libraries"):WaitForChild("HordeRules"))
local ZoneRules = require(SHARED:WaitForChild("Libraries"):WaitForChild("ZoneRules"))
local Logger = require(UTILS:WaitForChild("Logger"))

local Service = {}

Service.IsInitialized = false

-- HordeId -> registro de `HordeRules.Create`.
Service._hordes = {}
-- id del siguiente registro. Empieza en 1 porque 0 se lee como "sin horda" en
-- cualquier log, y un registro que se imprime como 0 no se distingue de un
-- `nil`.
Service._nextId = 1

-- Servicios inyectados por `ServerMain`.
Service._monsterService = nil
Service._nightService = nil
Service._economyService = nil
Service._questService = nil

-- Cuantas hordas puede haber vivas a la vez, en TODO el servidor.
--
-- Es un limite de RENDIMIENTO y de LECTURA, no de diseno. Tres hordas
-- simultaneas son tres conjuntos de NPC y tres lineas en el HUD; con mas, el
-- jugador deja de poder atender a ninguna.
Service.MaxActive = 2

-- Segundos que una horda puede seguir abierta antes de fallar.
--
-- Es lo que hace que el limite signifique algo: sin el, una horda se queda
-- contando enemigos para siempre y el contador del HUD es un numero que no
-- baja nunca. Ademas, es la UNICA defensa frente a un jugador que se esconde y
-- espera: la horda se cierra sola y el sistema no acumula hordas muertas.
Service.MaxDuration = 180

-- ---------------------------------------------------------------------------
-- INYECCION DE DEPENDENCIAS
-- ---------------------------------------------------------------------------

--- @param monsterService any
--- @param nightService any
--- @param economyService any?
--- @param questService any?
function Service.SetDependencies(
	monsterService: any,
	nightService: any,
	economyService: any?,
	questService: any?
)
	Service._monsterService = monsterService
	Service._nightService = nightService
	Service._economyService = economyService
	Service._questService = questService
end

-- ---------------------------------------------------------------------------
-- CONSULTA
-- ---------------------------------------------------------------------------

--- Numero de hordas VIVAS (contando).
--- @return number
function Service.GetActiveCount(): number
	local count = 0

	for _, horde in pairs(Service._hordes) do
		if HordeRules.IsActive(horde) then
			count += 1
		end
	end

	return count
end

--- Una horda por id.
--- @param hordeId any
--- @return any?
function Service.Get(hordeId: any): any?
	if type(hordeId) ~= "number" then
		return nil
	end

	return Service._hordes[hordeId]
end

--- La horda viva de un mundo, o nil.
---
--- Solo puede haber UNA por mundo, y esa es la razon por la que existe la
--- funcion: si un mundo tuviera dos hordas, cada muerte sumaria en las dos y
--- ambas terminarian a la vez con la mitad de enemigos vivos en la escena.
--- @param worldId any
--- @return any?
--- La horda viva de un mundo, o nil.
---
--- Solo puede haber UNA por mundo, y esa es la razon por la que existe la
--- funcion: si un mundo tuviera dos hordas, cada muerte sumaria en las dos y
--- ambas terminarian a la vez con la mitad de enemigos vivos en la escena.
--- @param worldId any
--- @return any?
function Service.GetByWorld(worldId: any): any?
	for _, horde in pairs(Service._hordes) do
		if HordeRules.IsActive(horde) and horde.WorldId == worldId then
			return horde
		end
	end

	return nil
end

-- ---------------------------------------------------------------------------
-- CICLO DE VIDA
-- ---------------------------------------------------------------------------

--- Crea una horda nueva en un mundo.
---
--- Se NECESITA el mundo porque una horda es un evento MUNDIAL: la comparten
--- todos los jugadores que esten dentro. Por eso el registro es por mundo y no
--- por jugador (fase 36).
--- @param worldId string
--- @param night any? noche actual (se toma del reloj si no se pasa)
--- @return any? la horda creada, o nil si no se pudo
function Service.StartHorde(worldId: string, night: any?): any?
	if type(worldId) ~= "string" then
		return nil
	end

	-- Limite de hordas simultaneas.
	if Service.GetActiveCount() >= Service.MaxActive then
		return nil
	end

	-- Una horda por mundo.
	local existing = Service.GetByWorld(worldId)

	if existing then
		return existing
	end

	local n = night

	if n == nil and Service._nightService and Service._nightService.GetNight then
		n = Service._nightService.GetNight()
	end

	local id = Service._nextId
	Service._nextId += 1

	local horde = HordeRules.Create(id, worldId, n)

	Service._hordes[id] = horde

	Logger.Info(("HordeService: '%s' iniciada en %s (noche %d, %d enemigos)")
		:format(worldId, worldId, horde.Night, horde.Total))

	return horde
end

--- Registra la muerte de un enemigo que PERTENECE a una horda.
---
--- Este es el unico punto por el que una horda avanza, y es el que la conecta
--- con `MonsterService`. Como es la UNICA via, aqui no se puede colar una baja
--- de mas ni una de menos.
--- @param hordeId number
--- @return boolean completed
function Service.HandleMonsterDeath(hordeId: number): boolean
	local horde = Service._hordes[hordeId]

	if not horde then
		return false
	end

	-- Se registra la baja SOLO si la horda sigue contando. `RegisterKill` ya
	-- protege de esto, pero se comprueba aqui para no seguir la cadena de
	-- llamadas en una horda que ya no cuenta.
	if not HordeRules.IsActive(horde) then
		return false
	end

	HordeRules.RegisterKill(horde)

	if not HordeRules.IsComplete(horde) then
		return false
	end

	-- Se llego al final. Se pide el premio al modulo, que decide si es la
	-- PRIMERA vez. Este servicio no mira `Rewarded` ni paga: solo reenvia.
	local paid, reward = HordeRules.ClaimReward(horde)

	if paid and reward then
		Service.PayReward(horde, reward)
	end

	Logger.Info(("HordeService: '%s' completada (%d enemigos)")
		:format(horde.WorldId, horde.Total))

	return true
end

--- Entrega el premio de una horda a los jugadores del mundo.
---
--- La recompensa es COMPARTIDA (fase 36): la horda es un evento mundial y todos
--- los que estan dentro han aiderado. Por eso se recorre a los jugadores del
--- mundo y no hay un unico "dueno" de la horda.
--- @param horde any
--- @param reward any
function Service.PayReward(horde: any, reward: any)
	local economy = Service._economyService

	if not economy or not economy.GrantReward then
		return
	end

	-- Cada jugador recibe la MISMA cantidad. Dividirla entre los presentes
	-- haria que anadir un jugador al mundo RESTARA recompensa a los demas, que
	-- es un efecto perverso y muy facil de convertir en un farm.
	local targets = Service.GetPlayersInWorld(horde.WorldId)

	for _, player in ipairs(targets) do
		pcall(economy.GrantReward, player, reward.XP, reward.Coins, reward.Gems)
	end
end

--- Jugadores que estan dentro de un mundo.
---
--- No se pide a `MatchService` aqui para no crear una dependencia circular
--- (el puede necesitar a este servicio). Se resuelve por el atributo `World`,
--- que es lo que escribe `MatchService.MovePlayer` en cada traslado.
--- @param worldId any
--- @return { Player }
function Service.GetPlayersInWorld(worldId: any): { Player }
	local out = {}

	if type(worldId) ~= "string" then
		return out
	end

	local players = game:GetService("Players")

	for _, player in ipairs(players:GetPlayers()) do
		if player:GetAttribute("World") == worldId then
			table.insert(out, player)
		end
	end

	return out
end

--- Cierra las hordas que se pasaron de tiempo.
---
--- Es la parte del ciclo que impide que las hordas se acumulen. Un jugador que
--- se esconde en una esquina y espera no puede acumular hordas: al llegar el
--- limite, la horda FALLA (sin premio) y desaparece del registro.
---
--- @param now any? reloj del servidor; se toma de `os.clock` si no se pasa
--- @return number hordas cerradas
function Service.Tick(now: any?): number
	local t = now

	if type(t) ~= "number" or t ~= t then
		t = os.clock()
	end

	local closed = 0

	-- Se copia el indice antes de tocarlo: `HandleMonsterDeath` puede cerrar y
	-- borrar entradas mientras se recorre, y modificar una tabla mientras se
	-- itera salta elementos sin avisar.
	for id, horde in pairs(Service._hordes) do
		if HordeRules.IsActive(horde) then
			if t - horde.StartedAt >= Service.MaxDuration then
				HordeRules.Fail(horde)

				-- `Fail` NO paga. El jugador no termino la horda, y si pagara
				-- igual el limite de tiempo no significaria nada.
				Logger.Info(("HordeService: '%s' fallo por tiempo (%d/%d)")
					:format(horde.WorldId, horde.Killed, horde.Total))

				closed += 1
			end
		else
			-- Ya cerrada y pagada (o fallida): sale del registro. Es la UNICA
			-- razon por la que un registro desaparece, y por eso `Rewarded` se
			-- respeta antes de borrar.
			if not HordeRules.HasRewarded(horde) and not HordeRules.IsFailed(horde) then
				-- Cerrada por otro motivo (el mundo se descargo): se expira sin
				-- pagar, porque el jugador ya no esta.
				HordeRules.Expire(horde)
			end

			Service._hordes[id] = nil
			closed += 1
		end
	end

	return closed
end

--- Cierra TODAS las hordas, sin pagar.
---
--- Lo llama el apagado del servidor y la salida de un mundo. No se paga nada:
--- lo que el jugador estaba haciendo en un mundo que ya no existe no se cobra.
--- @return number hordas cerradas
function Service.ClearAll(): number
	local total = 0

	for id, horde in pairs(Service._hordes) do
		HordeRules.Expire(horde)
		Service._hordes[id] = nil
		total += 1
	end

	if total > 0 then
		Logger.Info(("HordeService: %d hordas cerradas sin pagar"):format(total))
	end

	return total
end

--- Estado de las hordas, para diagnostico.
--- @return { Active: number, Total: number }
function Service.GetDiagnostics(): { Active: number, Total: number }
	local total = 0

	for _ in pairs(Service._hordes) do
		total += 1
	end

	return {
		Active = Service.GetActiveCount(),
		Total = total,
	}
end

-- ---------------------------------------------------------------------------
-- CICLO DE VIDA DEL SERVICIO
-- ---------------------------------------------------------------------------

Service._thread = nil
Service._running = false

--- Hilo de mantenimiento.
---
--- Solo hace una cosa: cerrar hordas caducadas. No hay `Heartbeat`, no hay
--- decision de juego y no hay lectura del mundo: es el trabajo minimo que
--- mantiene el sistema acotado sin coste por frame.
local function runMaintenance()
	while Service._running do
		Service.Tick()

		-- Un cuarto de segundo es suficiente porque lo UNICO que cambia aqui es
		-- una caducidad de 180 s: no hay nada que perder por mirarlo mas tarde.
		task.wait(0.25)
	end
end

--- Inicializacion. Idempotente.
--- @param maid any?
--- @return boolean success
function Service.Init(maid: any?): boolean
	if Service.IsInitialized then
		return true
	end

	Service._hordes = {}
	Service._nextId = 1

	Service.IsInitialized = true
	return true
end

--- Arranca el mantenimiento.
--- @return boolean success
function Service.Start(): boolean
	if not Service.IsInitialized then
		Logger.Error("HordeService: Start sin Init")
		return false
	end

	if Service._running then
		return true
	end

	Service._running = true
	Service._thread = task.spawn(runMaintenance)

	Logger.Info("HordeService: listo (max %d hordas activas)", Service.MaxActive)
	return true
end

--- Para el servicio y cierra todo sin pagar. Idempotente.
--- @return boolean success
function Service.Destroy(): boolean
	Service._running = false

	if Service._thread then
		pcall(task.cancel, Service._thread)
		Service._thread = nil
	end

	Service.ClearAll()
	Service.IsInitialized = false

	return true
end

return Service
