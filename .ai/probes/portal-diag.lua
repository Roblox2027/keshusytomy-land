-- Diagnostico del portal: llama al MISMO `PortalService.TryEnter` que el
-- remoto llama y devuelve el motivo del rechazo. Asi se separa "el cliente no
-- pulso" de "el servidor lo rechazo".
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players:GetPlayers()[1]

if not player then
	return { error = "sin jugador" }
end

local servers = game:GetService("ServerScriptService").Services
local portalService = require(servers:WaitForChild("PortalService"))

local allowed, reason = portalService.TryEnter(player, "Forest")
return {
	allowed = allowed,
	reason = reason,
	canTravel = select(1, portalService.CanTravel(player, "Forest")),
	canReason = select(2, portalService.CanTravel(player, "Forest")),
	level = player:GetAttribute("Level"),
}