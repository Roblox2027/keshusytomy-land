--!strict
--[[
	QuestCatalog
	Catalogo de misiones. Solo DATOS; ninguna logica.

	POR QUE ESTA SEPARADO
	----------------------
	Mismo criterio que `ItemCatalog` y `CodeCatalog`: el MECANISMO esta en
	`QuestRules` (logica pura) y en `QuestService` (motor). Aqui solo vive
	el CONTENIDO, de modo que cambiar una mision no obliga a tocar la
	logica que decide si un reclamo es valido.

	LA REGLA DE LAS CLAVES
	----------------------
	El indice va SIEMPRE en el `Id` NORMALIZADO (`QuestRules.NormalizeId`):
	minuscula, sin espacios, guiones ni guiones bajos. Escribirlo en
	mayusculas es mas legible, pero el indice no lo es, y esa distancia es
	justo el error que hace que una mision exista y no se pueda reclamar.
	`Validate` lo comprueba al arrancar.

	POR QUE `Metric` NO ES UN TEXTO LIBRE
	--------------------------------------
	`Metric` es el CONTRATO con el juego: es el nombre que el servidor
	empieza a escuchar cuando el jugador destruye un bloque, derrota a un
	monstruo o gana una ronda. Un texto libre aqui significa una mision
	imposible de progresar, y el fallo aparece como "la mision no avanza",
	que es el tipo de incidencia mas dificil de depurar que hay.

	Si se anade una metrica nueva hay que declararla en `Metric` Y cablear
	el evento que la emite. Una metrica declarada y no cableada NO es un
	aviso: es una mision muerta.
]]

local QuestCatalog = {}

--- Tipos de mision (spec 26).
QuestCatalog.QuestType = {
	Daily = "Daily",
	Weekly = "Weekly",
	World = "World",
	Event = "Event",
	Achievement = "Achievement",
	Season = "Season",
}

--- Metricas que el servidor sabe INCREMENTAR.
---
--- Una metrica que no esta aqui no se puede progresar. Esta tabla es la
--- frontera entre el contenido y los eventos reales del juego, y por eso
--- es explicita: obliga a decidir, al anadir una mision, de donde sale el
--- numero.
QuestCatalog.Metric = {
	BlockDestroyed = "BlockDestroyed",
	MonsterDefeated = "MonsterDefeated",
	RoundWon = "RoundWon",
	BombPlaced = "BombPlaced",
	PowerupCollected = "PowerupCollected",
	BossDefeated = "BossDefeated",
	PortalUsed = "PortalUsed",
	ItemPurchased = "ItemPurchased",
	XPCollected = "XPCollected",
	-- Metricas que los servicios YA emitian sin estar declaradas aqui
	-- (mision V2): la frontera tiene que ser veraz o no es frontera.
	SecretDiscovered = "SecretDiscovered",
	EventCompleted = "EventCompleted",
	MiniBossDefeated = "MiniBossDefeated",
	-- FASE 9.7 (expansion Brainrot): derrotar a un brainrot (Locotto,
	-- Bombino, Virusini, ...) cuenta APARTE de un monstruo generico. Sin
	-- metrica propia, "derrota 10 brainrots" seria indistinguible de
	-- "derrota 10 slimes". La emite `MonsterService` al morir, consultando
	-- `BrainrotRules.IsBrainrot`.
	BrainrotDefeated = "BrainrotDefeated",
}
local ALL = {
	-- --- Mundo (permanentes) ---------------------------------------------
	{
		Id = "WORLD_DESTROY_30",
		Title = "Demoledor",
		Description = "Destruye 30 bloques.",
		Type = QuestCatalog.QuestType.World,
		Metric = QuestCatalog.Metric.BlockDestroyed,
		Target = 30,
		Rewards = { Coins = 150 },
	},
	{
		Id = "WORLD_SLAY_5",
		Title = "Cazador de sombras",
		Description = "Derrota 5 monstruos.",
		Type = QuestCatalog.QuestType.World,
		Metric = QuestCatalog.Metric.MonsterDefeated,
		Target = 5,
		Rewards = { Coins = 200, Gems = 2 },
	},
	{
		Id = "WORLD_WIN_1",
		Title = "Primera victoria",
		Description = "Gana 1 ronda.",
		Type = QuestCatalog.QuestType.World,
		Metric = QuestCatalog.Metric.RoundWon,
		Target = 1,
		Rewards = { Coins = 100 },
	},
	{
		Id = "WORLD_BOMBS_10",
		Title = "Demolucion",
		Description = "Coloca 10 bombas.",
		Type = QuestCatalog.QuestType.World,
		Metric = QuestCatalog.Metric.BombPlaced,
		Target = 10,
		Rewards = { Coins = 120 },
	},

	-- --- Misiones V2 (mision master, FASE 40) ---------------------------
	--
	-- Las misiones dejan de ser solo "mata X monstruos": explorar,
	-- descubrir, sobrevivir a eventos y derrotar elites y jefes. Todas usan
	-- metricas que los servicios YA emiten de verdad; una mision con una
	-- metrica sin emisor seria imposible y pareceria un bug.
	{
		Id = "WORLD_SECRET_1",
		Title = "Zonas ocultas",
		Description = "Descubre 1 secreto.",
		Type = QuestCatalog.QuestType.World,
		Metric = QuestCatalog.Metric.SecretDiscovered,
		Target = 1,
		Rewards = { Coins = 120 },
	},
	{
		Id = "WORLD_EVENT_2",
		Title = "El mundo esta vivo",
		Description = "Completa 2 eventos del mundo.",
		Type = QuestCatalog.QuestType.World,
		Metric = QuestCatalog.Metric.EventCompleted,
		Target = 2,
		Rewards = { Coins = 150 },
	},
	{
		Id = "WORLD_MINIBOSS_1",
		Title = "Elite",
		Description = "Derrota 1 mini-boss.",
		Type = QuestCatalog.QuestType.World,
		Metric = QuestCatalog.Metric.MiniBossDefeated,
		Target = 1,
		Rewards = { Coins = 200 },
	},
	{
		Id = "WORLD_BOSS_1",
		Title = "El jefe",
		Description = "Derrota 1 jefe de mundo.",
		Type = QuestCatalog.QuestType.World,
		Metric = QuestCatalog.Metric.BossDefeated,
		Target = 1,
		Rewards = { Coins = 300 },
	},
	{
		Id = "WORLD_POWERUP_5",
		Title = "Avido",
		Description = "Recoge 5 powerups.",
		Type = QuestCatalog.QuestType.World,
		Metric = QuestCatalog.Metric.PowerupCollected,
		Target = 5,
		Rewards = { Coins = 100 },
	},

	-- --- Expansion Brainrot (FASE 9.7) -----------------------------------
	--
	-- Misiones de progreso real sobre la fauna brainrot. La metrica
	-- `BrainrotDefeated` la emite `MonsterService` cuando mata a un brainrot
	-- (frontera `BrainrotRules.IsBrainrot`), igual que `MonsterDefeated` para
	-- un monstruo generico: son misiones que avanzan solas al jugar.
	{
		Id = "WORLD_BRAINROT_10",
		Title = "Cazador de brainrots",
		Description = "Derrota 10 brainrots repartidos por los mundos.",
		Type = QuestCatalog.QuestType.World,
		Metric = QuestCatalog.Metric.BrainrotDefeated,
		Target = 10,
		Rewards = { Coins = 250, Gems = 3 },
	},
	{
		Id = "WORLD_BRAINROT_30",
		Title = "Coleccionista de fauna",
		Description = "Derrota 30 brainrots.",
		Type = QuestCatalog.QuestType.World,
		Metric = QuestCatalog.Metric.BrainrotDefeated,
		Target = 30,
		Rewards = { Coins = 600, Gems = 8 },
	},

	-- --- Achievements (logro interno, ver spec 28) ----------------------
	--
	-- Se separan de los logros de Roblox Badge a proposito: estos son
	-- INTERNOS y no dependen de que el lugar este publicado. Los Badges
	-- de Roblox son OTRO sistema, con su propia API y su propio requisito
	-- de publicacion.
	{
		Id = "ACH_FIRST_BOMB",
		Title = "Primera bomba",
		Description = "Coloca tu primera bomba.",
		Type = QuestCatalog.QuestType.Achievement,
		Metric = QuestCatalog.Metric.BombPlaced,
		Target = 1,
		Rewards = { Coins = 25 },
	},
	{
		Id = "ACH_FIRST_MONSTER",
		Title = "Primer monstruo",
		Description = "Derrota a tu primer monstruo.",
		Type = QuestCatalog.QuestType.Achievement,
		Metric = QuestCatalog.Metric.MonsterDefeated,
		Target = 1,
		Rewards = { Coins = 25 },
	},
	{
		Id = "ACH_FIRST_WIN",
		Title = "Primer triunfo",
		Description = "Gana tu primera ronda.",
		Type = QuestCatalog.QuestType.Achievement,
		Metric = QuestCatalog.Metric.RoundWon,
		Target = 1,
		Rewards = { Coins = 25 },
	},
	{
		Id = "ACH_PORTAL_1",
		Title = "Explorador",
		Description = "Usa un portal.",
		Type = QuestCatalog.QuestType.Achievement,
		Metric = QuestCatalog.Metric.PortalUsed,
		Target = 1,
		Rewards = { Coins = 25 },
	},
	{
		Id = "ACH_PURCHASE_1",
		Title = "Primera compra",
		Description = "Compra un objeto en la tienda.",
		Type = QuestCatalog.QuestType.Achievement,
		Metric = QuestCatalog.Metric.ItemPurchased,
		Target = 1,
		Rewards = { Coins = 25 },
	},

	-- --- Daily (oferta rotativa, ver `QuestRules.RollDailyOffer`) ---------
	{
		Id = "DAILY_DESTROY_10",
		Title = "Diaria: demoledor",
		Description = "Destruye 10 bloques.",
		Type = QuestCatalog.QuestType.Daily,
		Metric = QuestCatalog.Metric.BlockDestroyed,
		Target = 10,
		Rewards = { Coins = 75 },
	},
	{
		Id = "DAILY_SLAY_3",
		Title = "Diaria: caceria",
		Description = "Derrota 3 monstruos.",
		Type = QuestCatalog.QuestType.Daily,
		Metric = QuestCatalog.Metric.MonsterDefeated,
		Target = 3,
		Rewards = { Coins = 75 },
	},
	{
		Id = "DAILY_WIN_1",
		Title = "Diaria: victoria",
		Description = "Gana 1 ronda.",
		Type = QuestCatalog.QuestType.Daily,
		Metric = QuestCatalog.Metric.RoundWon,
		Target = 1,
		Rewards = { Coins = 75 },
	},
}
-- Indice por id NORMALIZADO, construido de forma PEREZA.
--
-- "Pereza" significa que el indice se construye la primera vez que se pide
-- un dato, no al cargar el modulo. La razon es que normalizar exige
-- `QuestRules`, y `QuestRules` no se puede cargar con `require` en el
-- interprete de pruebas (`script` no existe ahi). Un indice construido al
-- vuelo rompe el modulo entero en cuanto se lo carga una prueba, que es
-- justo lo que hay que evitar.
--
-- En el motor, `script` SI existe y la carga funciona a la primera.
local questRules = nil
local INDEX: { [string]: any } = {}
local BY_TYPE: { [string]: { [string]: any } } = {}

--- Construye el indice con las reglas ya configuradas.
--- @param rules any
local function buildIndex(rules: any)
	INDEX = {}
	BY_TYPE = {}

	for _, definition in ipairs(ALL) do
		local id = rules.NormalizeId(definition.Id)

		if id then
			INDEX[id] = definition

			local bucket = BY_TYPE[definition.Type]

			if not bucket then
				bucket = {}
				BY_TYPE[definition.Type] = bucket
			end

			bucket[id] = definition
		end
	end
end

--- Inyecta el modulo de reglas con el que se construira el indice.
---
--- Lo llama `QuestService.Init` en el motor, y las pruebas antes de leer
--- nada. Si no se llama, `Validate` lo dice en vez de devolver una lista
--- de problemas vacia que haria pensar que el catalogo esta bien.
--- @param injected any modulo `QuestRules`
function QuestCatalog.Configure(injected: any)
	questRules = injected

	if type(questRules) == "table" then
		buildIndex(questRules)
	else
		INDEX = {}
		BY_TYPE = {}
	end
end

--- Construye el indice si hace falta, con las reglas ya configuradas.
--- @return { [string]: any }
local function index(): { [string]: any }
	if next(INDEX) ~= nil then
		return INDEX
	end

	if questRules then
		buildIndex(questRules)
	end

	return INDEX
end

--- Devuelve el catalogo completo, indexado por id normalizado.
--- @return { [string]: any }
function QuestCatalog.GetAll(): { [string]: any }
	return index()
end

--- Definicion de una mision por su id, normalizado o no.
--- @param rawId any
--- @return any?
function QuestCatalog.Get(rawId: any): any?
	if not questRules then
		return nil
	end

	return index()[questRules.NormalizeId(rawId)]
end

--- Misiones de un tipo, indexadas por id normalizado.
--- @param questType string
--- @return { [string]: any }
function QuestCatalog.GetByType(questType: string): { [string]: any }
	index()
	return BY_TYPE[questType] or {}
end

--- El catalogo de las misiones daily, que es el que rota cada dia.
--- @return { [string]: any }
function QuestCatalog.GetDaily(): { [string]: any }
	return QuestCatalog.GetByType(QuestCatalog.QuestType.Daily)
end

--- Lista de misiones ordenada y estable, para la UI.
--- @param questType string?
--- @return { any }
function QuestCatalog.List(questType: string?): { any }
	index()

	local source = if questType then (BY_TYPE[questType] or {}) else INDEX
	local list = {}

	for _, definition in pairs(source) do
		table.insert(list, definition)
	end

	-- Orden estable: sin el, la UI reordenaria las misiones en cada
	-- lectura y el jugador veria la lista saltando.
	table.sort(list, function(a: any, b: any): boolean
		return tostring(a.Id) < tostring(b.Id)
	end)

	return list
end

--- Comprueba que el catalogo es utilizable por el servidor.
---
--- Se llama al ARRANCAR, no al reclamar: una mision publicada con una
--- recompensa rota debe aparecer como fallo de arranque, no como "esta
--- mision no existe" un martes a las tres de la manana.
---
--- Comprueba TAMBIEN que la metrica existe: una mision con una metrica
--- inexistente es una mision que NUNCA va a progresar, y eso solo se ve
--- si se mira.
--- @param questRules any? modulo `QuestRules`
--- @return { string } problemas lista vacia = todo cuadra
function QuestCatalog.Validate(questRules: any?): { string }
	local rules = questRules
	local problems: { string } = {}

	-- Se acepta el modulo por parametro para poder probar contra una copia
	-- distinta del de produccion. Si no se pasa, se usa el que inyecto
	-- `Configure`.
	--
	-- Si no hay ninguno, se avisa en vez de devolver una lista VACIA: una
	-- lista vacia diria "el catalogo esta bien" cuando en realidad no se ha
	-- comprobado nada, y eso es peor que un fallo visible.
	if not rules then
		table.insert(
			problems,
			"QuestCatalog.Configure no se ha llamado; el catalogo esta sin comprobar"
		)
		return problems
	end

	-- Metricas conocidas, para poder detectar una mision muerta.
	local knownMetrics = {}

	for _, metric in pairs(QuestCatalog.Metric) do
		knownMetrics[metric] = true
	end

	for key, definition in pairs(index()) do
		if rules.NormalizeId(definition.Id) ~= key then
			table.insert(
				problems,
				("'%s': la clave '%s' no es la forma normalizada"):format(
					tostring(definition.Id),
					key
				)
			)
		end

		local valid, reason = rules.IsDefinitionValid(definition)

		if not valid then
			table.insert(
				problems,
				("'%s': definicion invalida (%s)"):format(tostring(definition.Id), tostring(reason))
			)
		end

		if not knownMetrics[definition.Metric] then
			table.insert(
				problems,
				("'%s': metrica desconocida ('%s'); la mision no progresara"):format(
					tostring(definition.Id),
					tostring(definition.Metric)
				)
			)
		end
	end

	return problems
end

return QuestCatalog
