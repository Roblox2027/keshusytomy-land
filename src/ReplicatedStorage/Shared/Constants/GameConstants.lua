--!strict
--[[
	GameConstants
	Estados y valores enumerados compartidos entre servidor y cliente.

	Son cadenas legibles para facilitar la depuracion y
	la inspeccion en el explorador de Studio.
]]

return {
	RoundState = {
		Waiting = "Waiting",
		Countdown = "Countdown",
		RoundStarting = "RoundStarting",
		Playing = "Playing",
		SuddenDeath = "SuddenDeath",
		RoundEnding = "RoundEnding",
		Rewards = "Rewards",
		ReturningToLobby = "ReturningToLobby",
	},

	PlayerState = {
		Alive = "Alive",
		Dead = "Dead",
		Spectating = "Spectating",
	},

	-- Estados del ciclo de vida del SERVIDOR (distintos de la ronda).
	-- Un unico lugar define cuando se acepta trabajo nuevo.
	ServerState = {
		Starting = "Starting",
		Running = "Running",
		ShuttingDown = "ShuttingDown",
		Stopped = "Stopped",
	},

	-- Estados de un servicio dentro del ciclo de vida del servidor.
	ServiceState = {
		Unregistered = "Unregistered",
		Registered = "Registered",
		Initialized = "Initialized",
		Started = "Started",
		Stopping = "Stopping",
		Stopped = "Stopped",
		Failed = "Failed",
	},

	-- Estados del Keshusy Core. Son excluyentes: el nucleo esta en
	-- exactamente uno en cada momento, y las transiciones validas las
	-- decide `CoreRules` (logica pura, probada sin motor).
	CoreState = {
		-- Inerte: carga por debajo del maximo. Admite fragmentos.
		Inactive = "Inactive",
		-- Cargando: se alcanzo el maximo y corre la secuencia. No admite
		-- mas fragmentos.
		Activating = "Activating",
		-- Activado y estable: el mundo siguiente queda desbloqueado.
		Active = "Active",
		-- Sobrecargado: se paso del maximo y se drena hasta estabilizarse.
		Overloaded = "Overloaded",
		-- Evento: periodo de bonificacion tras activarse.
		Event = "Event",
	},

	-- Canales remotos centralizados: el cliente NUNCA es autoridad.
	RemoteAction = {
		Player = "PlayerAction",
		Bomb = "BombAction",
		Shop = "ShopAction",
		Inventory = "InventoryAction",
		Quest = "QuestAction",
		Code = "CodeAction",
		Portal = "PortalAction",
		-- El nucleo recibe UNA peticion por fragmento. El payload es
		-- deliberadamente irrelevante: el cliente no dice cuanta carga
		-- aporta, solo pide aportar.
		Core = "CoreAction",
		Party = "PartyAction",
		Settings = "SettingsAction",
		-- Combate cuerpo a cuerpo (mision V2): ataque, dash y habilidad.
		-- Las acciones no llevan payload: el servidor decide objetivo y
		-- dano, el cliente solo pide actuar.
		Combat = "CombatAction",
		-- Exploracion, descubrimiento e interaccion (FASE 3). El cliente pide
		-- la oferta, interactua con un punto o reclama; el servidor decide el
		-- mundo, el progreso y la recompensa.
		Explore = "ExploreAction",
	},
}
