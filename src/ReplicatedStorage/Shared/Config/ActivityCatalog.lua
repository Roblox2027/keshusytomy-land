--!strict
--[[
	ActivityCatalog
	Catalogo de actividades de exploracion (FASE 3 - MASTER MISSION V2).

	POR QUE ESTA SEPARADO
	----------------------
	Mismo criterio que `QuestCatalog`: el MECANISMO esta en `ActivitiesRules`
	(logica pura) y en `ActivityService` (motor). Aqui solo vive el CONTENIDO,
	de modo que anadir o ajustar una actividad no obliga a tocar la logica que
	decide si un reclamo es valido.

	LA REGLA DE LAS CLAVES
	----------------------
	El indice va SIEMPRE en el `Id` NORMALIZADO (`ActivitiesRules.NormalizeId`):
	minuscula, sin espacios, guiones ni guiones bajos. El motivo es el mismo que
	en `QuestCatalog`: una clave escrita en mayusculas y un `Id` en minusculas
	hacen que "la actividad existe" y "no se puede reclamar" coexistan.

	LA REGLA DEL MUNDO
	------------------
	Cada actividad declara `World`: la oferta rota cada dia se elige de la
	lista de actividades de ESE mundo. Una actividad sin `World` (global) no
	sale en la oferta de ningun mundo, asi que aqui todas tienen uno. La
	ausencia de cobertura de un mundo (mundo sin actividades) se detecta en
	`ActivitiesRules.Audit` con la lista de mundos conocidos.

	POR QUE NO SE HACE `require` DE `WorldAccessRules`
	---------------------------------------------------
	Que el catalogo conozca `WorldAccessRules` lo haría dependiente de un
	módulo que, aunque hoy es puro, mañana podría tocar el motor. El catalogo
	recibe la lista de mundos por parametro en `Validate` (como `ActivityService`
	inyecta `WorldAccessRules.WorldOrder`), y asi queda comprobable en aislamiento.
]]

local ActivityCatalog = {}

--- Tipos de actividad (refleja a `ActivitiesRules.ActivityType`). Se replica
--- aqui para poder declarar actividades legibles sin importar nada.
ActivityCatalog.ActivityType = {
	Rescue = "Rescue",
	Collection = "Collection",
	Mechanic = "Mechanic",
	Defense = "Defense",
	Hunt = "Hunt",
	Discovery = "Discovery",
}

local ALL = {
	-- Forest: caza, coleccion y descubrimiento. El material es Mat_LeafEssence.
	{
		Id = "HUNT_FOREST_3",
		Title = "Caza del bosque",
		Description = "Derrota 3 cazadores del bosque.",
		Type = ActivityCatalog.ActivityType.Hunt,
		World = "Forest",
		Target = 3,
		Cooldown = 240,
		Rewards = { Coins = 60, Mat_LeafEssence = 5 },
	},
	{
		Id = "COLLECT_FOREST_6",
		Title = "Recoleccion del bosque",
		Description = "Recoge 6 esencias de hoja en el bosque.",
		Type = ActivityCatalog.ActivityType.Collection,
		World = "Forest",
		Target = 6,
		Cooldown = 240,
		Rewards = { Coins = 70, Mat_LeafEssence = 8 },
	},
	{
		Id = "DISCOVER_FOREST_2",
		Title = "Secretos del bosque",
		Description = "Descubre 2 puntos de interes en el bosque.",
		Type = ActivityCatalog.ActivityType.Discovery,
		World = "Forest",
		Target = 2,
		Cooldown = 240,
		Rewards = { Coins = 50, Mat_LeafEssence = 4 },
	},

	-- Desert: caza y coleccion. El material es Mat_SandCrystal.
	{
		Id = "HUNT_DESERT_4",
		Title = "Caza del desierto",
		Description = "Derrota 4 cazadores del desierto.",
		Type = ActivityCatalog.ActivityType.Hunt,
		World = "Desert",
		Target = 4,
		Cooldown = 240,
		Rewards = { Coins = 65, Mat_SandCrystal = 5 },
	},
	{
		Id = "COLLECTION_DESERT_5",
		Title = "Coleccion del desierto",
		Description = "Recoge 5 cristales de arena en el desierto.",
		Type = ActivityCatalog.ActivityType.Collection,
		World = "Desert",
		Target = 5,
		Cooldown = 240,
		Rewards = { Coins = 75, Mat_SandCrystal = 7 },
	},
	{
		Id = "DISCOVER_DESERT_3",
		Title = "Secretos del desierto",
		Description = "Descubre 3 puntos de interes en el desierto.",
		Type = ActivityCatalog.ActivityType.Discovery,
		World = "Desert",
		Target = 3,
		Cooldown = 240,
		Rewards = { Coins = 55, Mat_SandCrystal = 4 },
	},

	-- Ice: defensa y coleccion. El material es Mat_FrostShard.
	{
		Id = "DEFENSE_ICE_6",
		Title = "Defensa del volante",
		Description = "Sobrevive a 6 oleadas congeladas.",
		Type = ActivityCatalog.ActivityType.Defense,
		World = "Ice",
		Target = 6,
		Cooldown = 600,
		Rewards = { Coins = 90, Mat_FrostShard = 8 },
	},
	{
		Id = "COLLECT_ICE_4",
		Title = "Recoleccion del volante",
		Description = "Recoge 4 fragmentos de escarcha en la nieve.",
		Type = ActivityCatalog.ActivityType.Collection,
		World = "Ice",
		Target = 4,
		Cooldown = 240,
		Rewards = { Coins = 60, Mat_FrostShard = 6 },
	},
	{
		Id = "DISCOVER_ICE_2",
		Title = "Secretos del volante",
		Description = "Descubre 2 puntos de interes en la nieve.",
		Type = ActivityCatalog.ActivityType.Discovery,
		World = "Ice",
		Target = 2,
		Cooldown = 240,
		Rewards = { Coins = 50, Mat_FrostShard = 4 },
	},

	-- Volcano: rescate y caza. El material es Mat_EmberCore.
	{
		Id = "RESCUE_VOLCANO_1",
		Title = "Rescate en la erupcion",
		Description = "Rescata a 1 superviviente en el volcán.",
		Type = ActivityCatalog.ActivityType.Rescue,
		World = "Volcano",
		Target = 1,
		Cooldown = 600,
		Rewards = { Coins = 80, Mat_EmberCore = 4 },
	},
	{
		Id = "HUNT_VOLCANO_5",
		Title = "Caza del volcán",
		Description = "Derrota 5 cazadores del volcán.",
		Type = ActivityCatalog.ActivityType.Hunt,
		World = "Volcano",
		Target = 5,
		Cooldown = 240,
		Rewards = { Coins = 80, Mat_EmberCore = 7 },
	},
	{
		Id = "DISCOVER_VOLCANO_3",
		Title = "Secretos del volcán",
		Description = "Descubre 3 puntos de interes en el volcán.",
		Type = ActivityCatalog.ActivityType.Discovery,
		World = "Volcano",
		Target = 3,
		Cooldown = 240,
		Rewards = { Coins = 60, Mat_EmberCore = 5 },
	},

	-- Cyber: mecanica y descubrimiento. El material es Mat_CircuitChip.
	{
		Id = "MECHANIC_CYBER_4",
		Title = "Sobrecarga del núcleo",
		Description = "Activa 4 nodos de reflejo en Cyber.",
		Type = ActivityCatalog.ActivityType.Mechanic,
		World = "Cyber",
		Target = 4,
		Cooldown = 600,
		Rewards = { Coins = 90, Mat_CircuitChip = 6 },
	},
	{
		Id = "DISCOVER_CYBER_2",
		Title = "Secretos de Cyber",
		Description = "Descubre 2 puntos de interes en Cyber.",
		Type = ActivityCatalog.ActivityType.Discovery,
		World = "Cyber",
		Target = 2,
		Cooldown = 240,
		Rewards = { Coins = 65, Mat_CircuitChip = 4 },
	},
	{
		Id = "COLLECT_CYBER_5",
		Title = "Coleccion de Cyber",
		Description = "Recoge 5 microchips en Cyber.",
		Type = ActivityCatalog.ActivityType.Collection,
		World = "Cyber",
		Target = 5,
		Cooldown = 240,
		Rewards = { Coins = 75, Mat_CircuitChip = 7 },
	},
}

-- Indice por id NORMALIZADO, construido de forma PEREZA.
--
-- "Pereza" significa que el indice se construye la primera vez que se pide
-- un dato, no al cargar el modulo. La razon es que normalizar exige
-- `ActivitiesRules`, y `ActivitiesRules` no se puede cargar con `require` en
-- el interprete de pruebas (`script` no existe ahi). Un indice construido al
-- vuelo rompe el modulo entero en cuanto se lo carga una prueba, que es justo
-- lo que hay que evitar.
--
-- En el motor, `script` SI existe y la carga funciona a la primera.
local activityRules = nil
local INDEX: { [string]: any } = {}
local BY_WORLD: { [string]: { [string]: any } } = {}

--- Construye el indice con las reglas ya configuradas.
--- @param rules any
local function buildIndex(rules: any)
	INDEX = {}
	BY_WORLD = {}

	for _, definition in ipairs(ALL) do
		local id = rules.NormalizeId(definition.Id)

		if id then
			INDEX[id] = definition

			local bucket = BY_WORLD[definition.World or ""]

			if not bucket then
				bucket = {}
				BY_WORLD[definition.World or ""] = bucket
			end

			bucket[id] = definition
		end
	end
end

--- Inyecta el modulo de reglas con el que se construira el indice.
---
--- Lo llama `ActivityService.Init` en el motor, y las pruebas antes de leer
--- nada. Si no se llama, `Validate` lo dice en vez de devolver una lista de
--- problemas vacia que haria pensar que el catalogo esta bien.
--- @param injected any modulo `ActivitiesRules`
function ActivityCatalog.Configure(injected: any)
	activityRules = injected

	if type(activityRules) == "table" then
		buildIndex(activityRules)
	else
		INDEX = {}
		BY_WORLD = {}
	end
end

--- Construye el indice si hace falta, con las reglas ya configuradas.
--- @return { [string]: any }
local function index(): { [string]: any }
	if next(INDEX) ~= nil then
		return INDEX
	end

	if activityRules then
		buildIndex(activityRules)
	end

	return INDEX
end

--- Devuelve el catalogo completo, indexado por id normalizado.
--- @return { [string]: any }
function ActivityCatalog.GetAll(): { [string]: any }
	return index()
end

--- Definicion de una actividad por su id, normalizado o no.
--- @param rawId any
--- @return any?
function ActivityCatalog.Get(rawId: any): any?
	if not activityRules then
		return nil
	end

	return index()[activityRules.NormalizeId(rawId)]
end

--- Actividades de un mundo, indexadas por id normalizado.
--- @param worldId string
--- @return { [string]: any }
function ActivityCatalog.ForWorld(worldId: string): { [string]: any }
	return BY_WORLD[worldId] or {}
end

--- Lista de actividades estable, para UI.
---
--- Sin orden, la UI reordenaria las actividades en cada lectura y el jugador
--- veria la lista saltando: un refresco visual que no significa nada.
--- @param worldId string?
--- @return { any }
function ActivityCatalog.List(worldId: string?): { any }
	index()

	local source = if worldId then (BY_WORLD[worldId] or {}) else INDEX
	local list: { any } = {}

	for _, definition in pairs(source) do
		table.insert(list, definition)
	end

	table.sort(list, function(a: any, b: any): boolean
		return tostring(a.Id) < tostring(b.Id)
	end)

	return list
end

--- Comprueba que el catalogo es utilizable por el servidor.
---
--- Se llama al ARRANCAR, no al ofrecer: una actividad publicada con un tipo
--- desconocido o un mundo inexistente debe aparecer como fallo de arranque,
--- no como "esta actividad no se ofrece" un dia cualquiera.
---
--- `knownWorlds` es la lista de mundos validos (`WorldAccessRules.WorldOrder`):
--- con ella se comprueba que cada actividad apunta a un mundo real Y que
--- NINGUN mundo queda sin actividades. Sin ella, solo valida estructura.
--- @param activityRules any? modulo `ActivitiesRules`
--- @param knownWorlds { string }? mundos validos
--- @return { string } problemas lista vacia = todo cuadra
function ActivityCatalog.Validate(activityRules: any?, knownWorlds: { string }?): { string }
	local problems: { string } = {}

	-- Se acepta el modulo por parametro para poder probar contra una copia
	-- distinta del de produccion. Si no se pasa, se usa el inyectado por
	-- `Configure`.
	local rules = activityRules

	if not rules then
		table.insert(
			problems,
			"ActivityCatalog.Validate necesita el modulo ActivitiesRules (o llama Configure primero)"
		)
		return problems
	end

	-- `Audit` construye el indice de forma peresoza la primera vez, aqui.
	-- La anotacion evita que el tipo `unknown` de `rules.Audit(...)` (rules
	-- es `any` inyectado) contamine el bucle de inspeccion.
	local auditProblems: { string } = rules.Audit(index(), knownWorlds)

	for _, problem in ipairs(auditProblems) do
		table.insert(problems, problem)
	end

	return problems
end

return ActivityCatalog
