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

	-- Canales remotos centralizados: el cliente NUNCA es autoridad.
	RemoteAction = {
		Player = "PlayerAction",
		Bomb = "BombAction",
		Shop = "ShopAction",
		Inventory = "InventoryAction",
		Quest = "QuestAction",
		Portal = "PortalAction",
		Party = "PartyAction",
		Settings = "SettingsAction",
	},
}
