--!strict
--[[
	EventRules
	EVENTOS DE MUNDO y eventos raros (FASES 17 y 18).

	LA ESTRUCTURA DE UN EVENTO
	--------------------------
	El enunciado pide que un evento tenga "inicio, duracion, fin, UI, recompensa
	y cleanup". De esos seis, aqui viven los TRES PRIMEROS y la recompensa, que
	son los que se pueden probar sin motor. La UI la decide el servicio (necesita
	`UIController`) y el cleanup es el mismo `Despawn` que usa el resto.

	La razon de separar la maquina de estados del servicio es la misma de siempre:
	"¿un evento se cierra solo, se queda colgado o paga dos veces?" es una
	pregunta que se responde en local, no en un playtest.

	LA REGLA QUE IMPORTA
	--------------------
	Un evento NUNCA deja a medio hacer su limpieza, y nunca se solapa consigo
	mismo en el mismo mundo. Un evento que se solapa consigo mismo es la forma
	classica de que el mapa se llene de NPCs de un evento anterior que ya no
	tiene dueño: no se ven, no se atacan y siguen contando para el limite global.
]]

local Rules = {}

-- ---------------------------------------------------------------------------
-- ESTADOS
-- ---------------------------------------------------------------------------

Rules.State = {
	Pending = "Pending",
	Running = "Running",
	Finished = "Finished",
	Cancelled = "Cancelled",
}

-- ---------------------------------------------------------------------------
-- CATALOGO DE EVENTOS
-- ---------------------------------------------------------------------------
--
-- Un evento por mundo y concepto, MAS una lista de eventos RAROS.
--
-- `Rarity` es la PROBABILIDAD de que ocurra, no la frecuencia: un evento con
-- `Rarity = 0.08` se sortea en el 8 % de las oportunidades. La razon de que
-- sean tan bajos es la fase 18: "no abusar, deben sentirse especiales". Un
-- evento que ocurre cada dos minutos deja de sentirse especial a los cinco.

Rules.ByWorld = {
	Forest = {
		{ Id = "ForestSwarm", Label = "HORDA DEL BOSQUE", Rarity = 0.30, Duration = 75, Threat = 1.25 },
		{ Id = "ForestPredators", Label = "ANIMALES HOSTILES", Rarity = 0.22, Duration = 60, Threat = 1.15 },
		{ Id = "ForestStorm", Label = "TORMENTA", Rarity = 0.16, Duration = 50, Threat = 1.05 },
		{ Id = "ForestDarkness", Label = "BOSQUE OSCURO", Rarity = 0.12, Duration = 60, Threat = 1.2 },
	},
	Desert = {
		{ Id = "DesertSandstorm", Label = "TORMENTA DE ARENA", Rarity = 0.28, Duration = 70, Threat = 1.2 },
		{ Id = "DesertRaid", Label = "INVASION", Rarity = 0.2, Duration = 80, Threat = 1.3 },
		{ Id = "DesertMirage", Label = "OASIS ESPECIAL", Rarity = 0.14, Duration = 60, Threat = 1.0 },
	},
	Ice = {
		{ Id = "IceBlizzard", Label = "TORMENTA CONGELANTE", Rarity = 0.28, Duration = 70, Threat = 1.25 },
		{ Id = "IceAvalanche", Label = "AVALANCHA", Rarity = 0.2, Duration = 45, Threat = 1.3 },
		{ Id = "IceCreatures", Label = "CRIATURAS DE HIELO", Rarity = 0.18, Duration = 65, Threat = 1.15 },
	},
	Volcano = {
		{ Id = "VolcanoEruption", Label = "ERUPCION", Rarity = 0.28, Duration = 70, Threat = 1.35 },
		{ Id = "VolcanoLava", Label = "RIO DE LAVA", Rarity = 0.22, Duration = 60, Threat = 1.25 },
		{ Id = "VolcanoRockRain", Label = "LLUVIA DE ROCAS", Rarity = 0.18, Duration = 50, Threat = 1.2 },
	},
	Cyber = {
		{ Id = "CyberBlackout", Label = "APAGON", Rarity = 0.26, Duration = 60, Threat = 1.15 },
		{ Id = "CyberAlarm", Label = "ALARMA", Rarity = 0.2, Duration = 55, Threat = 1.1 },
		{ Id = "CyberOverload", Label = "SOBRECARGA", Rarity = 0.18, Duration = 55, Threat = 1.3 },
		{ Id = "CyberInvasion", Label = "INVASION ROBOTICA", Rarity = 0.22, Duration = 85, Threat = 1.35 },
	},
}

--- Eventos RAROS (FASE 18). Son transversales: pueden salir en cualquier mundo.
---
-- No son "eventos mas raros": tienen una MECANICA distinta. Un cofre
-- legendario no sube la dificultad, aparece una recompensa; una zona secreta
-- abierta no sube la dificultad, aparece contenido. Por eso son parte
-- separada y no una entrada mas de `ByWorld` con `Rarity` bajo.
--
-- LA SUMA ES LA QUE IMPORTA
-- -------------------------
-- La probabilidad de un evento raro es su `Rarity` dividida entre la suma de
-- TODAS las del mundo, no su `Rarity` a secas. Con los raros en 0.05 cada uno
-- (seis eventos = 0.32) frente a unos 0.80 de eventos normales, un raro
-- saldia el 28 % de las tiradas: deja de ser raro y el jugador lo trataria
-- como un evento mas.
--
-- Los valores de abajo suman ~0.095, con lo que un raro sale en torno al 10 %
-- de las tiradas: se nota cuando pasa y no satura. `Events.spec` lo comprueba
-- recorriendo las 1000 fracciones del rango, que es la unica forma de
-- comprobar una probabilidad sin depender de que el azar coopere.
Rules.Rare = {
	{ Id = "LegendaryChest", Label = "COFRE LEGENDARIO", Rarity = 0.015, Duration = 120, Threat = 1.0 },
	{ Id = "RareMiniBoss", Label = "MINI-BOSS RARO", Rarity = 0.02, Duration = 90, Threat = 1.4 },
	{ Id = "SecretZoneOpen", Label = "ZONA SECRETA ABIERTA", Rarity = 0.015, Duration = 150, Threat = 1.0 },
	{ Id = "RewardRain", Label = "LLUVIA DE RECOMPENSAS", Rarity = 0.01, Duration = 60, Threat = 0.9 },
	{ Id = "TimePortal", Label = "PORTAL TEMPORAL", Rarity = 0.015, Duration = 90, Threat = 1.2 },
	{ Id = "SurvivalTrial", Label = "PRUEBA DE SUPERVIVENCIA", Rarity = 0.02, Duration = 100, Threat = 1.35 },
}

--- Ids de todos los eventos, con su mundo (`nil` si son raros).
--- @return { { Id: string, WorldId: string?, Rare: boolean } }
function Rules.GetAll()
	local out = {}

	for worldId, events in pairs(Rules.ByWorld) do
		for _, event in ipairs(events) do
			table.insert(out, { Id = event.Id, WorldId = worldId, Rare = false })
		end
	end

	for _, event in ipairs(Rules.Rare) do
		table.insert(out, { Id = event.Id, WorldId = nil, Rare = true })
	end

	return out
end

--- Eventos de un mundo, raros incluidos.
--- @param worldId any
--- @return { any }
function Rules.GetForWorld(worldId: any): { any }
	if type(worldId) ~= "string" then
		return {}
	end

	-- Un mundo que NO esta en el catalogo devuelve lista vacia, sin anadir los
	-- eventos raros.
	--
	-- Es la diferencia entre "este mundo tiene estos eventos" y "este mundo
	-- existe". Si un `worldId` inventado recibiera los eventos raros, un cliente
	-- que mandara un mundo falso recibiria eventos, NPC y recompensas de un
	-- lugar que no esta en el juego.
	local own = Rules.ByWorld[worldId :: string]

	if own == nil then
		return {}
	end

	local out = {}

	for _, event in ipairs(own) do
		table.insert(out, event)
	end

	for _, event in ipairs(Rules.Rare) do
		table.insert(out, event)
	end

	return out
end

--- Busqueda de un evento por id, en cualquier mundo.
--- @param id any
--- @return any?
function Rules.Get(id: any): any?
	if type(id) ~= "string" then
		return nil
	end

	for _, list in pairs(Rules.ByWorld) do
		for _, event in ipairs(list) do
			if event.Id == id then
				return event
			end
		end
	end

	for _, event in ipairs(Rules.Rare) do
		if event.Id == id then
			return event
		end
	end

	return nil
end

-- ---------------------------------------------------------------------------
-- SELECCION
-- ---------------------------------------------------------------------------

--- Tirada de seleccion para un mundo, dado un numero aleatorio en 0..1.
---
--- Se separa del `math.random` a proposito: la SELECCION es una funcion pura y
--- comprobable, y el numero aleatorio lo pone quien llama. Asi se puede
--- verificar "con 0.95 nunca sale un cofre legendario" sin depender de que el
--- azar cooperare, que es la razon por la que los tests de azar no dicen nada
--- cuando pasan.
---
--- Devuelve `nil` si ningun evento sale. Eso es LO NORMAL y no un error: con
--- rarity 0.3 en el mejor caso, la mayoria de las tiradas no dan evento. Un
--- evento por tirada seria un evento cada veinte segundos.
--- @param worldId string
--- @param roll number 0..1
--- @param allowRare boolean? incluir los eventos raros
--- @return any? evento elegido
function Rules.Roll(worldId: string, roll: number, allowRare: boolean?): any?
	if type(roll) ~= "number" or roll ~= roll then
		return nil
	end

	-- Se normaliza a 0..1. Un `roll` fuera de rango (por ejemplo un
	-- `math.random()` mal usado, que devuelve enteros) haria que el primer
	-- evento de la lista saliera SIEMPRE y el resto nunca.
	local r = math.clamp(roll, 0, 0.999999)

	local candidates = Rules.GetForWorld(worldId)

	if not allowRare then
		local filtered = {}

		for _, event in ipairs(candidates) do
			if not Rules.IsRare(event.Id) then
				table.insert(filtered, event)
			end
		end

		candidates = filtered
	end

	if #candidates == 0 then
		return nil
	end

	-- La suma de rareces define el "primer corte". Como no llega a 1 en
	-- general, el resto del rango devuelve `nil`: es el comportamiento
	-- correcto, no un error de calculo.
	local total = 0

	for _, event in ipairs(candidates) do
		total += event.Rarity
	end

	if r >= total then
		return nil
	end

	local cursor = 0

	for _, event in ipairs(candidates) do
		cursor += event.Rarity

		if r < cursor then
			return event
		end
	end

	return nil
end

-- ---------------------------------------------------------------------------
-- CICLO DE VIDA
-- ---------------------------------------------------------------------------

export type ActiveEvent = {
	InstanceId: number,
	EventId: string,
	WorldId: string,
	Night: number,
	State: string,
	StartedAt: number,
	Duration: number,
	CleanedUp: boolean,
}

--- Crea un evento activo a partir de su definicion.
--- @param instanceId number id unico de esta instancia
--- @param event any definicion de `Get` o de `Roll`
--- @param worldId string
--- @param night any
--- @param now number reloj del servidor
--- @return ActiveEvent
function Rules.Start(instanceId: number, event: any, worldId: string, night: any, now: number): ActiveEvent
	return {
		InstanceId = instanceId,
		EventId = event.Id,
		WorldId = worldId,
		Night = tonumber(night) or 1,
		State = Rules.State.Running,
		StartedAt = now,
		Duration = event.Duration or 60,
		CleanedUp = false,
	}
end

--- Cuanto le queda al evento, en segundos. 0 si ya termino.
--- @param active ActiveEvent
--- @param now number
--- @return number
function Rules.GetRemaining(active: ActiveEvent, now: number): number
	return math.max(0, active.Duration - (now - active.StartedAt))
end

--- El evento llego a su fin por tiempo.
--- @param active ActiveEvent
--- @param now number
--- @return boolean
function Rules.IsExpired(active: ActiveEvent, now: number): boolean
	return active.State == Rules.State.Running and Rules.GetRemaining(active, now) <= 0
end

--- Termina el evento y lo marca como limpiado.
---
--- Es idempotente a proposito: el servicio la llama desde el tick (por tiempo) y
--- desde el cleanup del mundo (por salida del jugador). Con una que no lo fuera,
--- el segundo paso intentaria destruir NPCs ya destruidos y dejaria avisos en el
--- log a cada salida de jugador.
--- @param active ActiveEvent
--- @param cancelled boolean? `true` si se cancela en vez de terminar natural
--- @return boolean changed
function Rules.Finish(active: ActiveEvent, cancelled: boolean?): boolean
	if active.CleanedUp then
		return false
	end

	active.CleanedUp = true
	active.State = if cancelled then Rules.State.Cancelled else Rules.State.Finished

	return true
end

--- Presion que aporta el evento a la dificultad (FASE 32).
---
--- Se pasa como multiplicador a `DifficultyRules.Resolve`, que a su vez lo
--- ACOTA. Aqui solo se limita a un rango sano para que un valor raro del
--- catalogo no empuje el perfil entero.
--- @param event any
--- @return number
function Rules.ThreatOf(event: any): number
	local threat = tonumber(event and event.Threat)

	if not threat or threat ~= threat then
		return 1
	end

	return math.clamp(threat, 0.5, 2)
end

--- Recompensa de terminar un evento.
--- @param active ActiveEvent
--- @param rewardScale any?
--- @return { XP: number, Coins: number, Gems: number }
function Rules.RewardFor(active: ActiveEvent, rewardScale: any?): { XP: number, Coins: number, Gems: number }
	local scale = tonumber(rewardScale)

	if not scale or scale ~= scale or scale < 1 then
		scale = 1
	end

	local factor = math.min(scale, 3)
	local base = if Rules.IsRare(active.EventId) then 60 else 25

	-- Un evento raro paga MAS POR RELACION, no mas en absoluto: es raro, y esa
	-- es la promesa. Si pagase mucho mas en cantidad, el jugador dejaria de
	-- jugar a los eventos normales en cuanto entendiera el promedio.
	return {
		XP = math.floor(base * factor),
		Coins = math.floor(base * 0.6 * factor),
		Gems = if Rules.IsRare(active.EventId) then 1 else 0,
	}
end

-- ---------------------------------------------------------------------------
-- LIMITES
-- ---------------------------------------------------------------------------

--- Numero maximo de eventos ACTIVOS a la vez en un mundo.
---
--- El limite es de RENDIMIENTO y de LECTURA. Dos eventos simultaneos ya son
--- mucho contenido; cuatro son ruido, porque el jugador deja de poder decidir
--- cual atender y el HUD se convierte en un anuncio permanente.
Rules.MaxActivePerWorld = 2

--- Numero maximo de eventos activos en TODO el servidor.
---
--- Es menor que "los cinco mundos por dos": cinco mundos con dos eventos cada
--- uno serian diez eventos simultaneos, con NPCs de diez fuentes distintas en
--- un servidor de doce jugadores. Es un presupuesto, no una cuenta por mundo.
Rules.MaxActiveTotal = 4

--- Un evento es RARO (FASE 18).
--- @param eventId any
--- @return boolean
function Rules.IsRare(eventId: any): boolean
	if type(eventId) ~= "string" then
		return false
	end

	for _, event in ipairs(Rules.Rare) do
		if event.Id == eventId then
			return true
		end
	end

	return false
end

--- Un evento es de un mundo concreto (no raro).
--- @param eventId any
--- @return boolean
function Rules.IsWorldEvent(eventId: any): boolean
	if type(eventId) ~= "string" then
		return false
	end

	for _, list in pairs(Rules.ByWorld) do
		for _, event in ipairs(list) do
			if event.Id == eventId then
				return true
			end
		end
	end

	return false
end

return Rules