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
