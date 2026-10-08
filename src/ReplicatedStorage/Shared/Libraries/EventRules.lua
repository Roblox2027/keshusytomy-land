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
-- FASE 6: MAQUINA DE ESTADOS DINAMICA (5 fases)
-- ---------------------------------------------------------------------------
--
-- La maquina de FASE 6 extiende (no reemplaza) la de 3 estados anterior.
-- Un evento dinámico vive una vida completa con anuncio, actividad y enfriamiento:
--
--   IDLE      -> esperando su turno (cooldown activo o sin jugadores).
--   WARNING   -> anunciado al HUD, el jugador se prepara. No hay cuerpo activo.
--   ACTIVE    -> el cuerpo esta en el mapa, el jugador juega.
--   RECOVERY  -> el evento termino, los enemigos se limpian, efectos se apagan.
--   COOLDOWN  -> enfriamiento: no vuelve a salir hasta que pasa el cooldown.
--
-- La transicion de WARNING a ACTIVE despega el cuerpo; la de ACTIVE a RECOVERY
-- inicia el cleanup; RECOVERY a COOLDOWN cierra la ventana de enfriamiento.
-- El jugador ve los PRIMEROS TRES estados en el HUD; COOLDOWN e IDLE son
-- internos del servidor (el jugador no necesita ver "no saldra igual esta noche").
Rules.DynamicState = {
	Idle = "Idle",
	Warning = "Warning",
	Active = "Active",
	Recovery = "Recovery",
	Cooldown = "Cooldown",
}

-- ---------------------------------------------------------------------------
-- FASE 6: TIPOS DE EVENTO
-- ---------------------------------------------------------------------------
--
-- Clasifica un evento por su ambito y requisitos de jugador. La clasificacion
-- decide:
--   - si se sortea por mundo o en toda la partida (Global vs Local);
--   - si necesita jugadores minimos para abrirse (Coop);
--   - si se despacha en zona o en el mundo entero (Local)
--
-- Global:  evento mundial, afecta a todos en el mundo (ej: tormenta).
-- Local:   evento en una ZONA concreta, jugadores del mundo pueden no estar.
-- Player:  evento individual (mision V2, la actividad del jugador)
-- Coop:    evento que requiere N jugadores minimos. Si no hay suficientes,
--          no se abre (no se abre para uno y luego otro se une).
Rules.EventType = {
	Global = "Global",
	Local = "Local",
	Player = "Player",
	Coop = "Coop",
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
		{
			Id = "ForestSwarm",
			Label = "HORDA DEL BOSQUE",
			Rarity = 0.30,
			Duration = 75,
			Threat = 1.25,
		},
		{
			Id = "ForestPredators",
			Label = "ANIMALES HOSTILES",
			Rarity = 0.22,
			Duration = 60,
			Threat = 1.15,
		},
		{ Id = "ForestStorm", Label = "TORMENTA", Rarity = 0.16, Duration = 50, Threat = 1.05 },
		{
			Id = "ForestDarkness",
			Label = "BOSQUE OSCURO",
			Rarity = 0.12,
			Duration = 60,
			Threat = 1.2,
		},
		-- FASE 6: Eventos dinamicos reales (maquina de 5 estados).
		{
			Id = "ForestAmbush",
			Label = "EMBOSCADA EN EL BOSQUE",
			Rarity = 0.18,
			Weight = 0.18,
			Duration = 70,
			Cooldown = 300,
			Type = Rules.EventType.Local,
			ZoneId = "BogHollow",
			WarningDuration = 8,
			ActiveDuration = 55,
			RecoveryDuration = 5,
			Threat = 1.3,
		},
		{
			Id = "LostCreature",
			Label = "criatura perdida",
			Rarity = 0.14,
			Weight = 0.14,
			Duration = 90,
			Cooldown = 420,
			Type = Rules.EventType.Local,
			ZoneId = "RockyRidge",
			WarningDuration = 10,
			ActiveDuration = 70,
			RecoveryDuration = 8,
			Threat = 1.1,
		},
		{
			Id = "ForestRift",
			Label = "ABISAL DEL BOSQUE",
			Rarity = 0.10,
			Weight = 0.10,
			Duration = 55,
			Cooldown = 360,
			Type = Rules.EventType.Global,
			WarningDuration = 6,
			ActiveDuration = 42,
			RecoveryDuration = 5,
			Threat = 1.25,
		},
		{
			Id = "NightHunters",
			Label = "CAZADORES NOCTURNOS",
			Rarity = 0.12,
			Weight = 0.12,
			Duration = 65,
			Cooldown = 360,
			Type = Rules.EventType.Local,
			ZoneId = "DenseGrove",
			WarningDuration = 8,
			ActiveDuration = 50,
			RecoveryDuration = 5,
			Threat = 1.35,
		},
	},
	Desert = {
		{
			Id = "DesertSandstorm",
			Label = "TORMENTA DE ARENA",
			Rarity = 0.28,
			Duration = 70,
			Threat = 1.2,
		},
		{ Id = "DesertRaid", Label = "INVASION", Rarity = 0.2, Duration = 80, Threat = 1.3 },
		{
			Id = "DesertMirage",
			Label = "OASIS ESPECIAL",
			Rarity = 0.14,
			Duration = 60,
			Threat = 1.0,
		},
		-- FASE 6: Eventos dinamicos reales.
		{
			Id = "BuriedTreasure",
			Label = "TESORO ENTERRADO",
			Rarity = 0.15,
			Weight = 0.15,
			Duration = 80,
			Cooldown = 400,
			Type = Rules.EventType.Local,
			ZoneId = "Ruins",
			WarningDuration = 10,
			ActiveDuration = 60,
			RecoveryDuration = 8,
			Threat = 1.0,
		},
		{
			Id = "Caravan",
			Label = "CARAVANA ATACADA",
			Rarity = 0.13,
			Weight = 0.13,
			Duration = 75,
			Cooldown = 380,
			Type = Rules.EventType.Local,
			ZoneId = "Oasis",
			WarningDuration = 8,
			ActiveDuration = 60,
			RecoveryDuration = 5,
			Threat = 1.25,
		},
		{
			Id = "SandBeastHunt",
			Label = "CAZA DE LA BESTIA DE ARENA",
			Rarity = 0.10,
			Weight = 0.10,
			Duration = 85,
			Cooldown = 420,
			Type = Rules.EventType.Local,
			ZoneId = "Canyon",
			WarningDuration = 6,
			ActiveDuration = 70,
			RecoveryDuration = 7,
			Threat = 1.45,
		},
	},
	Ice = {
		{
			Id = "IceBlizzard",
			Label = "TORMENTA CONGELANTE",
			Rarity = 0.28,
			Duration = 70,
			Threat = 1.25,
		},
		{ Id = "IceAvalanche", Label = "AVALANCHA", Rarity = 0.2, Duration = 45, Threat = 1.3 },
		{
			Id = "IceCreatures",
			Label = "CRIATURAS DE HIELO",
			Rarity = 0.18,
			Duration = 65,
			Threat = 1.15,
		},
		-- FASE 6: Eventos dinamicos reales.
		{
			Id = "IceBreak",
			Label = "ROMPIENDO EL HIELO",
			Rarity = 0.16,
			Weight = 0.16,
			Duration = 50,
			Cooldown = 320,
			Type = Rules.EventType.Local,
			ZoneId = "Lake",
			WarningDuration = 6,
			ActiveDuration = 38,
			RecoveryDuration = 4,
			Threat = 1.25,
		},
		{
			Id = "FrozenRescue",
			Label = "RESCATE CONGELADO",
			Rarity = 0.13,
			Weight = 0.13,
			Duration = 75,
			Cooldown = 400,
			Type = Rules.EventType.Local,
			ZoneId = "Crevasse",
			WarningDuration = 8,
			ActiveDuration = 60,
			RecoveryDuration = 5,
			Threat = 1.1,
		},
		{
			Id = "FrostPack",
			Label = " MANADA DE FRIEZ",
			Rarity = 0.11,
			Weight = 0.11,
			Duration = 60,
			Cooldown = 340,
			Type = Rules.EventType.Local,
			ZoneId = "Narrows",
			WarningDuration = 7,
			ActiveDuration = 46,
			RecoveryDuration = 5,
			Threat = 1.35,
		},
	},
	Volcano = {
		{ Id = "VolcanoEruption", Label = "ERUPCION", Rarity = 0.28, Duration = 70, Threat = 1.35 },
		{ Id = "VolcanoLava", Label = "RIO DE LAVA", Rarity = 0.22, Duration = 60, Threat = 1.25 },
		{
			Id = "VolcanoRockRain",
			Label = "LLUVIA DE ROCAS",
			Rarity = 0.18,
			Duration = 50,
			Threat = 1.2,
		},
		-- FASE 6: Eventos dinamicos reales.
		{
			Id = "Rockfall",
			Label = "AVEAMIENTO DE ROCAS",
			Rarity = 0.16,
			Weight = 0.16,
			Duration = 45,
			Cooldown = 320,
			Type = Rules.EventType.Local,
			ZoneId = "Fissure",
			WarningDuration = 6,
			ActiveDuration = 34,
			RecoveryDuration = 4,
			Threat = 1.3,
		},
		{
			Id = "VolcanicEvacuation",
			Label = "EVACUACION VULCANICA",
			Rarity = 0.13,
			Weight = 0.13,
			Duration = 70,
			Cooldown = 380,
			Type = Rules.EventType.Local,
			ZoneId = "Vents",
			WarningDuration = 8,
			ActiveDuration = 55,
			RecoveryDuration = 5,
			Threat = 1.4,
		},
		{
			Id = "MagmaHunt",
			Label = "CAZA EN EL MAGMA",
			Rarity = 0.12,
			Weight = 0.12,
			Duration = 65,
			Cooldown = 360,
			Type = Rules.EventType.Local,
			ZoneId = "Platforms",
			WarningDuration = 7,
			ActiveDuration = 50,
			RecoveryDuration = 5,
			Threat = 1.45,
		},
	},
	Cyber = {
		{ Id = "CyberBlackout", Label = "APAGON", Rarity = 0.26, Duration = 60, Threat = 1.15 },
		{ Id = "CyberAlarm", Label = "ALARMA", Rarity = 0.2, Duration = 55, Threat = 1.1 },
		{ Id = "CyberOverload", Label = "SOBRECARGA", Rarity = 0.18, Duration = 55, Threat = 1.3 },
		{
			Id = "CyberInvasion",
			Label = "INVASION ROBOTICA",
			Rarity = 0.22,
			Duration = 85,
			Threat = 1.35,
		},
		-- FASE 6: Eventos dinamicos reales.
		{
			Id = "SystemFailure",
			Label = "FALLA EN EL SISTEMA",
			Rarity = 0.15,
			Weight = 0.15,
			Duration = 55,
			Cooldown = 320,
			Type = Rules.EventType.Global,
			WarningDuration = 5,
			ActiveDuration = 42,
			RecoveryDuration = 5,
			Threat = 1.1,
		},
		{
			Id = "SecurityLockdown",
			Label = "BLOQUEO DE SEGURIDAD",
			Rarity = 0.14,
			Weight = 0.14,
			Duration = 60,
			Cooldown = 340,
			Type = Rules.EventType.Local,
			ZoneId = "ServerHall",
			WarningDuration = 6,
			ActiveDuration = 48,
			RecoveryDuration = 4,
			Threat = 1.25,
		},
		{
			Id = "HackTheCore",
			Label = "HACKEA EL NUCLEO",
			Rarity = 0.10,
			Weight = 0.10,
			Duration = 90,
			Cooldown = 420,
			Type = Rules.EventType.Local,
			ZoneId = "Reactor",
			WarningDuration = 8,
			ActiveDuration = 70,
			RecoveryDuration = 8,
			Threat = 1.4,
		},
		{
			Id = "SecuritySwarm",
			Label = "ENJAMBRA DE SEGURIDAD",
			Rarity = 0.12,
			Weight = 0.12,
			Duration = 55,
			Cooldown = 360,
			Type = Rules.EventType.Local,
			ZoneId = "Conduit",
			WarningDuration = 6,
			ActiveDuration = 42,
			RecoveryDuration = 5,
			Threat = 1.35,
		},
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
	{
		Id = "LegendaryChest",
		Label = "COFRE LEGENDARIO",
		Rarity = 0.015,
		Duration = 120,
		Threat = 1.0,
	},
	{ Id = "RareMiniBoss", Label = "MINI-BOSS RARO", Rarity = 0.02, Duration = 90, Threat = 1.4 },
	{
		Id = "SecretZoneOpen",
		Label = "ZONA SECRETA ABIERTA",
		Rarity = 0.015,
		Duration = 150,
		Threat = 1.0,
	},
	{
		Id = "RewardRain",
		Label = "LLUVIA DE RECOMPENSAS",
		Rarity = 0.01,
		Duration = 60,
		Threat = 0.9,
	},
	{ Id = "TimePortal", Label = "PORTAL TEMPORAL", Rarity = 0.015, Duration = 90, Threat = 1.2 },
	{
		Id = "SurvivalTrial",
		Label = "PRUEBA DE SUPERVIVENCIA",
		Rarity = 0.02,
		Duration = 100,
		Threat = 1.35,
	},
	-- Evento MUNDIAL (mision V2, FASE 5): el cuerpo lo pone `Bodies`
	-- y la recompensa la cobran TODOS los presentes al completarse.
	{
		Id = "WorldInvasion",
		Label = "LOS MONSTRUOS ESTAN INVADIENDO EL MUNDO",
		Rarity = 0.015,
		Duration = 120,
		Threat = 1.4,
	},
}

--- Eventos UNIVERSAL (FASE 6): pueden ocurrir en cualquier mundo.
---
-- No son raros: son eventos con `Type = Global` que no pertenecen a un mundo
-- concreto sino al juego completo. Aparecen en la lista de cualquier mundo.
Rules.Universal = {
	{
		Id = "TreasureRush",
		Label = "RAFAGA DE TESOROS",
		Rarity = 0.08,
		Weight = 0.08,
		Duration = 60,
		Cooldown = 480,
		Type = Rules.EventType.Global,
		WarningDuration = 5,
		ActiveDuration = 45,
		RecoveryDuration = 5,
		Threat = 0.9,
	},
	{
		Id = "MonsterSurge",
		Label = "OLEADA DE BESTIAS",
		Rarity = 0.07,
		Weight = 0.07,
		Duration = 50,
		Cooldown = 400,
		Type = Rules.EventType.Global,
		WarningDuration = 4,
		ActiveDuration = 38,
		RecoveryDuration = 4,
		Threat = 1.3,
	},
	{
		Id = "EliteSpawn",
		Label = "ELITE RARO",
		Rarity = 0.05,
		Weight = 0.05,
		Duration = 80,
		Cooldown = 500,
		Type = Rules.EventType.Global,
		WarningDuration = 5,
		ActiveDuration = 65,
		RecoveryDuration = 6,
		Threat = 1.45,
	},
}

--- Eventos COOP (FASE 6): requieren N jugadores minimos.
---
-- Si no hay suficientes jugadores presentes, el evento NO se abre. No se
-- abre para uno y luego se escala: la promesa del COOP es que todos
-- participan desde el inicio.
Rules.Coop = {
	{
		Id = "SharedThreat",
		Label = "amenaza compartida",
		Rarity = 0.06,
		Weight = 0.06,
		Duration = 90,
		Cooldown = 420,
		Type = Rules.EventType.Coop,
		MinPlayers = 3,
		MaxPlayers = 8,
		WarningDuration = 8,
		ActiveDuration = 70,
		RecoveryDuration = 8,
		Threat = 1.4,
	},
	{
		Id = "TwinBosses",
		Label = "GEMELO JEFE",
		Rarity = 0.04,
		Weight = 0.04,
		Duration = 120,
		Cooldown = 600,
		Type = Rules.EventType.Coop,
		MinPlayers = 4,
		MaxPlayers = 8,
		WarningDuration = 10,
		ActiveDuration = 95,
		RecoveryDuration = 10,
		Threat = 1.6,
	},
	{
		Id = "Nexus",
		Label = "NEXUS PURIFICADOR",
		Rarity = 0.03,
		Weight = 0.03,
		Duration = 150,
		Cooldown = 720,
		Type = Rules.EventType.Coop,
		MinPlayers = 6,
		MaxPlayers = 8,
		WarningDuration = 12,
		ActiveDuration = 120,
		RecoveryDuration = 12,
		Threat = 1.8,
	},
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

	for _, event in ipairs(Rules.Universal) do
		table.insert(out, { Id = event.Id, WorldId = nil, Rare = false, Universal = true })
	end

	for _, event in ipairs(Rules.Coop) do
		table.insert(out, { Id = event.Id, WorldId = nil, Rare = false, Coop = true })
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

	-- FASE 6: eventos Universal y COOP pueden ocurrir en cualquier mundo.
	for _, event in ipairs(Rules.Universal) do
		table.insert(out, event)
	end

	for _, event in ipairs(Rules.Coop) do
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

	for _, event in ipairs(Rules.Universal) do
		if event.Id == id then
			return event
		end
	end

	for _, event in ipairs(Rules.Coop) do
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
 -- SELECCION PONDERADA (FASE 6): Weight como peso relativo
 -- ---------------------------------------------------------------------------
 --
 -- `Roll` usa `Rarity` como probabilidad absoluta (la suma define el corte).
 -- `WeightedRoll` usa `Weight` como peso relativo: siempre devuelve un evento
 -- (el que tenga mas peso), y la probabilidad de "ningun evento" se decide
 -- afuera, en el servicio, con el cooldown y la ventana entre sorteos.
 --
 -- Los eventos LEGACY (sin campo `Weight`) se usan como `Rarity` en el peso
 -- para que `WeightedRoll` siga funcionando con el catalogo existente.
 --- @param worldId string
 --- @param roll number 0..1
 --- @param allowRare boolean? incluir los eventos raros
 --- @param excludeCoop boolean? excluir eventos COOP (no hay jugadores suficientes)
 --- @return any? evento elegido
 function Rules.WeightedRoll(worldId: string, roll: number, allowRare: boolean?, excludeCoop: boolean?): any?
	if type(roll) ~= "number" or roll ~= roll then
		return nil
	end

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

	if excludeCoop then
		local filtered = {}
		for _, event in ipairs(candidates) do
			if not Rules.IsCoop(event.Id) then
				table.insert(filtered, event)
			end
		end
		candidates = filtered
	end

	if #candidates == 0 then
		return nil
	end

	-- El peso de cada evento: Weight si existe, Rarity como respaldo.
	local total = 0
	for _, event in ipairs(candidates) do
		local weight = tonumber(event.Weight) or tonumber(event.Rarity) or 0
		total += weight
	end

	if total <= 0 then
		return nil
	end

	local cursor = 0
	local threshold = r * total

	for _, event in ipairs(candidates) do
		local weight = tonumber(event.Weight) or tonumber(event.Rarity) or 0
		cursor += weight

		if threshold < cursor then
			return event
		end
	end

	-- Si el peso acumulado no llega a cubrir el umbral (float precision),
	-- devuelve el ultimo candidato.
	return candidates[#candidates]
 end

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
function Rules.Start(
	instanceId: number,
	event: any,
	worldId: string,
	night: any,
	now: number
): ActiveEvent
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

 -- ---------------------------------------------------------------------------
 -- FASE 6: MAQUINA DE ESTADOS DINAMICA
 -- ---------------------------------------------------------------------------

 --- Tipo extendido de ActiveEvent para la maquina de 5 estados (FASE 6).
 ---
 --- Los campos `Phase`, `PhaseStartedAt`, `WarningDuration`, `ActiveDuration`
 --- y `RecoveryDuration` son nil en los eventos LEGACY (que usan `State` y
 --- `Duration`). El servicio detecta el tipo con `IsDynamicEvent`.
 --- @class DynamicActiveEvent
 --- @field InstanceId number
 --- @field EventId string
 --- @field WorldId string
 --- @field Night number
 --- @field Phase string  (DynamicState)
 --- @field PhaseStartedAt number
 --- @field WarningDuration number
 --- @field ActiveDuration number
 --- @field RecoveryDuration number
 --- @field CooldownUntil number
 --- @field ZoneId string?
 --- @field CleanUp boolean
 --- @field ObjectiveCompleted boolean

 --- Crea un evento dinámico con la maquina de 5 estados (FASE 6).
 --- @param instanceId number
 --- @param event any definicion del catalogo
 --- @param worldId string
 --- @param night any
 --- @param now number
 --- @return table active
 function Rules.DynamicStart(
	instanceId: number,
	event: any,
	worldId: string,
	night: any,
	now: number
 ): table
	local warning = tonumber(event.WarningDuration) or 8
	local activeDur = tonumber(event.ActiveDuration) or (tonumber(event.Duration) or 45)
	local recovery = tonumber(event.RecoveryDuration) or 5

	return {
		InstanceId = instanceId,
		EventId = event.Id,
		WorldId = worldId,
		Night = tonumber(night) or 1,
		Phase = Rules.DynamicState.Warning,
		PhaseStartedAt = now,
		WarningDuration = warning,
		ActiveDuration = activeDur,
		RecoveryDuration = recovery,
		CooldownUntil = 0,
		ZoneId = event.ZoneId,
		CleanUp = false,
		ObjectiveCompleted = false,
	}
 end

 --- El siguiente estado en la maquina de 5 fases.
 --- @param phase string
 --- @return string next
 function Rules.NextPhase(phase: string): string
	if phase == Rules.DynamicState.Warning then
		return Rules.DynamicState.Active
	elseif phase == Rules.DynamicState.Active then
		return Rules.DynamicState.Recovery
	elseif phase == Rules.DynamicState.Recovery then
		return Rules.DynamicState.Cooldown
	elseif phase == Rules.DynamicState.Cooldown then
		return Rules.DynamicState.Idle
	end
	return Rules.DynamicState.Warning
 end

 --- Duracion de la fase actual en segundos.
 --- @param active table
 --- @return number
 function Rules.PhaseDuration(active: table): number
	local phase = active.Phase

	if phase == Rules.DynamicState.Warning then
		return tonumber(active.WarningDuration) or 8
	elseif phase == Rules.DynamicState.Active then
		return tonumber(active.ActiveDuration) or 45
	elseif phase == Rules.DynamicState.Recovery then
		return tonumber(active.RecoveryDuration) or 5
	end

	return 0
 end

 --- Tiempo restante en la fase actual. 0 si expiró.
 --- @param active table
 --- @param now number
 --- @return number
 function Rules.GetPhaseRemaining(active: table, now: number): number
	local elapsed = now - active.PhaseStartedAt
	return math.max(0, Rules.PhaseDuration(active) - elapsed)
 end

 --- La fase actual expiró por tiempo.
 --- @param active table
 --- @param now number
 --- @return boolean
 function Rules.IsPhaseExpired(active: table, now: number): boolean
	return Rules.GetPhaseRemaining(active, now) <= 0
 end

 --- Avanza el evento a la siguiente fase. Devuelve true si avanzó.
 --- @param active table
 --- @param now number
 --- @return boolean changed
 function Rules.AdvancePhase(active: table, now: number): boolean
	if not active.Phase or active.Phase == Rules.DynamicState.Idle then
		return false
	end

	if active.Phase == Rules.DynamicState.Cooldown then
		-- Cooldown -> Idle: el evento vuelve a estar disponible.
		active.Phase = Rules.DynamicState.Idle
		active.CooldownUntil = 0
		return true
	end

	active.Phase = Rules.NextPhase(active.Phase)
	active.PhaseStartedAt = now
	return true
 end

 --- Duracion total del evento dinámico (warning + active + recovery).
 --- @param active table
 --- @return number
 function Rules.GetTotalDuration(active: table): number
	return (Rules.PhaseDuration(active) + (tonumber(active.WarningDuration) or 0) + (tonumber(active.ActiveDuration) or 0))
 end

 --- Un evento es dinámico (FASE 6) si tiene Phase (no State).
 --- @param active any
 --- @return boolean
 function Rules.IsDynamicEvent(active: any): boolean
	return type(active) == "table" and active.Phase ~= nil
 end

 --- El evento está en fase activa o de anuncio.
 --- @param active any
 --- @return boolean
 function Rules.IsEventLive(active: any): boolean
	if not active or type(active) ~= "table" then
		return false
	end

	if Rules.IsDynamicEvent(active) then
		return active.Phase == Rules.DynamicState.Warning
			or active.Phase == Rules.DynamicState.Active
	end

	return active.State == Rules.State.Running
 end

 --- Marca el evento como completado (objetivo alcanzado en fase Active).
 --- @param active table
 --- @param now number
 --- @return boolean changed
 function Rules.CompleteObjective(active: table, now: number): boolean
	if active.ObjectiveCompleted then
		return false
	end

	active.ObjectiveCompleted = true
	return true
 end

 --- El evento cumple su objetivo y puede pasar a Recovery.
 --- @param active table
 --- @return boolean
 function Rules.IsObjectiveDone(active: table): boolean
	return active.ObjectiveCompleted == true
 end

 --- Clasifica un evento como COOP.
 --- @param eventId any
 --- @return boolean
 function Rules.IsCoop(eventId: any): boolean
	if type(eventId) ~= "string" then
		return false
	end

	for _, event in ipairs(Rules.Coop) do
		if event.Id == eventId then
			return true
		end
	end

	return false
 end

 --- Clasifica un evento como Universal.
 --- @param eventId any
 --- @return boolean
 function Rules.IsUniversal(eventId: any): boolean
	if type(eventId) ~= "string" then
		return false
	end

	for _, event in ipairs(Rules.Universal) do
		if event.Id == eventId then
			return true
		end
	end

	return false
 end

 --- Requisitos de jugador para un evento COOP.
 --- @param eventId any
 --- @return number? minPlayers
 --- @return number? maxPlayers
 function Rules.GetPlayerRequirements(eventId: any): (number?, number?)
	local def = Rules.Get(eventId)

	if not def then
		return nil, nil
	end

	return tonumber(def.MinPlayers), tonumber(def.MaxPlayers)
 end

 --- Zona de un evento LOCAL (FASE 6).
 --- @param eventId any
 --- @return string? zoneId
 function Rules.GetZone(eventId: any): string?
	local def = Rules.Get(eventId)

	if not def then
		return nil
	end

	return def.ZoneId
 end

 --- Tiempo de enfriamiento de un evento, en segundos.
 --- @param eventId any
 --- @return number
 function Rules.CooldownFor(eventId: any): number
	local def = Rules.Get(eventId)

	if not def then
		return 120
	end

	return tonumber(def.Cooldown) or 120
 end

 --- Tipo de evento (Global/Local/Player/Coop).
 --- @param eventId any
 --- @return string?
 function Rules.GetEventType(eventId: any): string?
	local def = Rules.Get(eventId)

	if not def then
		return nil
	end

	return def.Type
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
function Rules.RewardFor(
	active: ActiveEvent,
	rewardScale: any?
): { XP: number, Coins: number, Gems: number }
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

-- ---------------------------------------------------------------------------
-- CUERPO DEL EVENTO (MASTER MISSION V2 - Bloque 1)
-- ---------------------------------------------------------------------------
--
-- Hasta aqui el evento era un registro con reloj: se abria, sumaba amenaza
-- y pagaba al cerrarse, y el jugador nunca veia NADA en el mundo. El cuerpo
-- es lo que el evento PONE en el mapa: enemigos que cazar, un elite unico o
-- una amenaza que sobrevivir.
--
-- `Bodies` es una tabla APARTE del catalogo y no campos nuevos en cada
-- entrada por una razon de contrato: los tests de `Events.spec` recorren el
-- catalogo campo a campo, y un evento sin cuerpo (una tormenta ambiental) NO
-- tiene que declarar nada. "Sin cuerpo" se lee como "el evento es ambiental"
-- y no como "a este evento le falta configuracion".
--
-- LOS CUATRO TIPOS
-- ----------------
--   Hunt:    aparecen enemigos del evento y el objetivo es derrotarlos.
--            El evento se completa AL LLEGAR al objetivo, no por tiempo.
--   Boss:    aparece UN elite del mundo. El objetivo es derrotarlo.
--   Survive: no hay enemigos propios; la amenaza la sube `Threat` y el
--            objetivo es estar vivo cuando el reloj llega a cero.
--   Reward:  no hay enemigos; el evento paga su recompensa al cerrarse.

Rules.BodyKind = {
	Hunt = "Hunt",
	Boss = "Boss",
	Survive = "Survive",
	Reward = "Reward",
}

--- Maximo de enemigos VIVOS que un evento mantiene en el mundo.
---
--- Es un presupuesto de rendimiento y de lectura, no de dificultad: mas de
--- cuatro enemigos de evento a la vez tapa a la fauna normal del mundo, y el
--- jugador deja de distinguir "el evento" de "la ronda". La dificultad del
-- evento la pone el OBJETIVO (cuantos hay que derrotar), no la cantidad
-- simultanea.
Rules.MaxAlivePerEvent = 4

Rules.Bodies = {
	-- Forest
	ForestSwarm = { Kind = "Hunt", Spawns = { "Slime", "Shadow" }, BaseTarget = 8 },
	ForestPredators = { Kind = "Hunt", Spawns = { "Hunter" }, BaseTarget = 5 },
	-- Desert
	DesertRaid = { Kind = "Hunt", Spawns = { "Hunter", "Guardian" }, BaseTarget = 7 },
	-- Ice
	IceCreatures = { Kind = "Hunt", Spawns = { "IceBeast" }, BaseTarget = 5 },
	-- Cyber
	CyberAlarm = { Kind = "Hunt", Spawns = { "CyberStalker" }, BaseTarget = 5 },
	CyberInvasion = { Kind = "Hunt", Spawns = { "CyberStalker", "BomberMonster" }, BaseTarget = 8 },
	-- Raros
	RareMiniBoss = {
		Kind = "Boss",
		Spawns = { "Guardian", "IceBeast", "FireBeast", "CyberStalker" },
		BaseTarget = 1,
	},
	WorldInvasion = {
		Kind = "Hunt",
		Spawns = { "Slime", "Shadow", "Hunter", "BombBug" },
		BaseTarget = 12,
	},
}

--- Cuerpo de un evento, o nil si el evento es ambiental.
--- @param eventId any
--- @return any?
function Rules.BodyFor(eventId: any): any?
	if type(eventId) ~= "string" then
		return nil
	end

	return Rules.Bodies[eventId]
end

--- Objetivo NUMERICO del evento: cuantas bajas hay que conseguir.
---
--- Escala con la noche de forma ACOTADA: cada noche suma una baja al
--- objetivo hasta un techo de +6. Sin techo, un evento de la noche 40 pediria
-- 48 bajas en 75 segundos, que no es un desafio: es imposible, y el jugador
--- aprende a ignorar el evento.
--- @param eventId any
--- @param night any
--- @return number target 0 = evento sin objetivo de bajas
function Rules.ObjectiveTargetFor(eventId: any, night: any): number
	local body = Rules.BodyFor(eventId)

	if not body or body.Kind ~= Rules.BodyKind.Hunt and body.Kind ~= Rules.BodyKind.Boss then
		return 0
	end

	local base = tonumber(body.BaseTarget) or 1
	local bonus = math.clamp((tonumber(night) or 1) - 1, 0, 6)

	if body.Kind == Rules.BodyKind.Boss then
		return 1
	end

	return base + bonus
end

--- Cuantos enemigos del evento hay que generar AHORA.
---
--- La regla mantiene vivos `MaxAlivePerEvent` mientras queden bajas por
--- hacer, y deja de generar cuando las bajas hechas mas los vivos ya
--- alcanzan el objetivo: generar de mas crearia enemigos huerfanos que el
--- jugador no necesita para completar el evento.
--- @param eventId any
--- @param night any
--- @param kills any bajas ya contabilizadas
--- @param alive any vivos ahora mismo
--- @return number a generar (0 si no toca)
function Rules.SpawnPlanFor(eventId: any, night: any, kills: any, alive: any): number
	local body = Rules.BodyFor(eventId)

	if not body or body.Kind ~= Rules.BodyKind.Hunt and body.Kind ~= Rules.BodyKind.Boss then
		return 0
	end

	local target = Rules.ObjectiveTargetFor(eventId, night)
	local done = (tonumber(kills) or 0) + (tonumber(alive) or 0)
	local remaining = target - done

	if remaining <= 0 then
		return 0
	end

	if body.Kind == Rules.BodyKind.Boss then
		return math.min(remaining, 1)
	end

	return math.min(remaining, Rules.MaxAlivePerEvent - (tonumber(alive) or 0))
end

--- El evento PAGA cuando el reloj llega a cero.
---
--- Un evento de caza que expira sin completarse NO paga: pagar lo convertiria
--- en "espera 75 segundos y cobra", que es exactamente el evento sin cuerpo
--- que esta regla viene a eliminar. Uno de supervivencia o recompensa SI: el
--- objetivo era aguantar el reloj.
--- @param eventId any
--- @return boolean
function Rules.CompletesOnExpiry(eventId: any): boolean
	local body = Rules.BodyFor(eventId)

	if not body then
		return true
	end

	return body.Kind == Rules.BodyKind.Survive or body.Kind == Rules.BodyKind.Reward
end

--- Texto de objetivo para el HUD.
--- @param eventId any
--- @param night any
--- @param kills any
--- @return string
function Rules.ObjectiveText(eventId: any, night: any, kills: any): string
	local body = Rules.BodyFor(eventId)

	if not body then
		return ""
	end

	if body.Kind == Rules.BodyKind.Hunt then
		local target = Rules.ObjectiveTargetFor(eventId, night)
		return ("Derrota: %d/%d"):format(tonumber(kills) or 0, target)
	end

	if body.Kind == Rules.BodyKind.Boss then
		return "Derrota al elite"
	end

	if body.Kind == Rules.BodyKind.Survive then
		return "Sobrevive"
	end

	return "Recoge la recompensa"
end

--- Lista plana de eventos CON cuerpo (diagnostico y pruebas).
--- @return { { Id: string, Kind: string, Spawns: { string } } }
function Rules.GetBodies(): { any }
	local out = {}

	for id, body in pairs(Rules.Bodies) do
		table.insert(out, { Id = id, Kind = body.Kind, Spawns = body.Spawns })
	end

	table.sort(out, function(a, b)
		return a.Id < b.Id
	end)

	return out
 end

 -- ---------------------------------------------------------------------------
 -- FASE 6: CUERPOS DINAMICOS (DynamicBodies)
 -- ---------------------------------------------------------------------------
 --
 -- Los cuerpos del evento son los monstruos u objetos que aparecen en el mapa.
 -- Siguen el mismo patron que `Bodies`: tabla aparte, referenciada por `Id`,
 -- con un `Kind` (Hunt/Boss/Survive/Reward/Collect/Defense/Escort) y lista de
 -- `Spawns` de monstruos validos. Un evento sin cuerpo es ambiental.
 --
 -- Los monstruos referenciados deben existir en `MonsterDefinitions`:
 -- `DynamicBodyAudit` (las pruebas) lo comprueba, evitando la trampa de un
 -- evento que anuncia caza pero que NO pone enemigos porque el id esta mal.

 Rules.DynamicBodies = {
	-- --- FOREST ---
	ForestAmbush = { Kind = "Hunt", Spawns = { "Slime", "Shadow", "Hunter" }, BaseTarget = 6 },
	LostCreature = { Kind = "Boss", Spawns = { "ForestTronk" }, BaseTarget = 1 },
	ForestRift = { Kind = "Survive", Spawns = {}, BaseTarget = 0 },
	NightHunters = { Kind = "Hunt", Spawns = { "Shadow", "Shadow" }, BaseTarget = 5 },

	-- --- DESERT ---
	BuriedTreasure = { Kind = "Collect", Spawns = {}, BaseTarget = 3 },
	Caravan = { Kind = "Defense", Spawns = { "Hunter", "Guardian" }, BaseTarget = 8 },
	SandBeastHunt = { Kind = "Boss", Spawns = { "DesertEscorpion" }, BaseTarget = 1 },

	-- --- ICE ---
	IceBreak = { Kind = "Hunt", Spawns = { "IceBeast", "IceBeast" }, BaseTarget = 5 },
	FrozenRescue = { Kind = "Rescue", Spawns = {}, BaseTarget = 1 },
	FrostPack = { Kind = "Hunt", Spawns = { "IceBeast" }, BaseTarget = 4 },

	-- --- VOLCANO ---
	Rockfall = { Kind = "Survive", Spawns = {}, BaseTarget = 0 },
	VolcanicEvacuation = { Kind = "Escort", Spawns = {}, BaseTarget = 1 },
	MagmaHunt = { Kind = "Hunt", Spawns = { "FireBeast", "BomberMonster" }, BaseTarget = 6 },

	-- --- CYBER ---
	SystemFailure = { Kind = "Survive", Spawns = {}, BaseTarget = 0 },
	SecurityLockdown = { Kind = "Hunt", Spawns = { "CyberStalker" }, BaseTarget = 5 },
	HackTheCore = { Kind = "Objective", Spawns = {}, BaseTarget = 1 },
	SecuritySwarm = { Kind = "Hunt", Spawns = { "CyberStalker" }, BaseTarget = 7 },

	-- --- UNIVERSAL ---
	TreasureRush = { Kind = "Collect", Spawns = {}, BaseTarget = 5 },
	MonsterSurge = { Kind = "Hunt", Spawns = { "Slime", "Shadow", "Hunter", "BombBug" }, BaseTarget = 10 },
	EliteSpawn = { Kind = "Boss", Spawns = { "Guardian", "IceBeast", "FireBeast", "CyberStalker" }, BaseTarget = 1 },

	-- --- COOP ---
	SharedThreat = { Kind = "Hunt", Spawns = { "Slime", "Shadow", "Hunter", "BombBug" }, BaseTarget = 12 },
	TwinBosses = { Kind = "Boss", Spawns = { "ForestGrooty", "DesertSandBeast" }, BaseTarget = 2 },
	Nexus = { Kind = "Hunt", Spawns = { "CyberStalker", "BomberMonster", "FireBeast" }, BaseTarget = 15 },
 }

 Rules.DynamicBodyKind = {
	Hunt = "Hunt",
	Boss = "Boss",
	Survive = "Survive",
	Reward = "Reward",
	Collect = "Collect",
	Defense = "Defense",
	Escort = "Escort",
	Rescue = "Rescue",
	Objective = "Objective",
 }

 --- Cuerpo de un evento dinámico, o nil si es ambiental.
 --- @param eventId any
 --- @return any?
 function Rules.DynamicBodyFor(eventId: any): any?
	if type(eventId) ~= "string" then
		return nil
	end

	return Rules.DynamicBodies[eventId]
 end

 --- Objetivo numerico de un evento dinámico (bajas o coleccion).
 --- @param eventId any
 --- @param night any
 --- @return number target 0 = evento sin objetivo de bajas
 function Rules.DynamicObjectiveTargetFor(eventId: any, night: any): number
	local body = Rules.DynamicBodyFor(eventId)

	if not body then
		return 0
	end

	if body.Kind ~= Rules.DynamicBodyKind.Hunt and body.Kind ~= Rules.DynamicBodyKind.Boss then
		return 0
	end

	local base = tonumber(body.BaseTarget) or 1

	if body.Kind == Rules.DynamicBodyKind.Boss then
		return 1
	end

	local bonus = math.clamp((tonumber(night) or 1) - 1, 0, 8)
	return base + bonus
 end

 --- Plan de generacion para un evento dinámico.
 --- @param eventId any
 --- @param night any
 --- @param kills any
 --- @param alive any
 --- @return number a generar (0 si no toca)
 function Rules.DynamicSpawnPlanFor(eventId: any, night: any, kills: any, alive: any): number
	local body = Rules.DynamicBodyFor(eventId)

	if not body or body.Kind ~= Rules.DynamicBodyKind.Hunt and body.Kind ~= Rules.DynamicBodyKind.Boss then
		return 0
	end

	local target = Rules.DynamicObjectiveTargetFor(eventId, night)
	local done = (tonumber(kills) or 0) + (tonumber(alive) or 0)
	local remaining = target - done

	if remaining <= 0 then
		return 0
	end

	if body.Kind == Rules.DynamicBodyKind.Boss then
		return math.min(remaining, 1)
	end

	return math.min(remaining, Rules.MaxAlivePerEvent - (tonumber(alive) or 0))
 end

 --- El evento dinámico PAGA cuando el reloj llega a cero.
 --- @param eventId any
 --- @return boolean
 function Rules.DynamicCompletesOnExpiry(eventId: any): boolean
	local body = Rules.DynamicBodyFor(eventId)

	if not body then
		return true
	end

	return body.Kind == Rules.DynamicBodyKind.Survive
		or body.Kind == Rules.DynamicBodyKind.Reward
		or body.Kind == Rules.DynamicBodyKind.Defense
 end

 --- Texto de objetivo para el HUD de un evento dinámico.
 --- @param eventId any
 --- @param night any
 --- @param kills any
 --- @return string
 function Rules.DynamicObjectiveText(eventId: any, night: any, kills: any): string
	local body = Rules.DynamicBodyFor(eventId)

	if not body then
		return ""
	end

	if body.Kind == Rules.DynamicBodyKind.Hunt then
		local target = Rules.DynamicObjectiveTargetFor(eventId, night)
		return ("Derrota: %d/%d"):format(tonumber(kills) or 0, target)
	end

	if body.Kind == Rules.DynamicBodyKind.Boss then
		return "Derrota al jefe"
	end

	if body.Kind == Rules.DynamicBodyKind.Survive then
		return "Sobrevive"
	end

	if body.Kind == Rules.DynamicBodyKind.Defense then
		return "Defiende el punto"
	end

	if body.Kind == Rules.DynamicBodyKind.Escort then
		return "Escolta al objetivo"
	end

	if body.Kind == Rules.DynamicBodyKind.Rescue then
		return "Rescate completado"
	end

	if body.Kind == Rules.DynamicBodyKind.Collect then
		local target = tonumber(body.BaseTarget) or 3
		return ("Colecciona: %d/%d"):format(tonumber(kills) or 0, target)
	end

	if body.Kind == Rules.DynamicBodyKind.Objective then
		return "Completa el objetivo"
	end

	return "Recoge la recompensa"
 end

 --- Lista plana de cuerpos dinámicos (diagnostico y pruebas).
 --- @return { { Id: string, Kind: string, Spawns: { string } } }
 function Rules.GetDynamicBodies(): { any }
	local out = {}

	for id, body in pairs(Rules.DynamicBodies) do
		table.insert(out, { Id = id, Kind = body.Kind, Spawns = body.Spawns })
	end

	table.sort(out, function(a, b)
		return a.Id < b.Id
	end)

	return out
 end

 --- Todos los ids de eventos FASE 6 (no raros, no legacy).
 --- @return { string }
 function Rules.GetDynamicEventIds(): { string }
	local out = {}

	for _, event in ipairs(Rules.Universal) do
		table.insert(out, event.Id)
	end

	for _, event in ipairs(Rules.Coop) do
		table.insert(out, event.Id)
	end

	for _, events in pairs(Rules.ByWorld) do
		for _, event in ipairs(events) do
			if event.Weight ~= nil then
				table.insert(out, event.Id)
			end
		end
	end

	return out
 end

 return Rules
