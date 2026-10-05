-- b2-state.lua (SERVIDOR)
-- Estado del jugador y de la ronda. SIN ESPERAS y SIN ACCIONES.
local Players = game:GetService("Players")
local Round = require(game.ServerScriptService.Services.RoundService)
local Match = require(game.ServerScriptService.Services.MatchService)
local Portal = require(game.ServerScriptService.Services.PortalService)

local out = {}
local function say(f, ...) table.insert(out, string.format(f, ...)) end

local p = Players:GetPlayers()[1]
if not p then return "sin jugador" end

say("ronda = %s | IsPlaying = %s | #%s", tostring(Round.GetState()),
	tostring(Round.IsPlaying()), tostring(Round.GetRoundNumber()))
say("World = %s", tostring(p:GetAttribute("World")))
say("PlayerState = %s", tostring(p:GetAttribute("PlayerState")))

local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
if r then
	say("pos = (%.0f, %.0f, %.0f)", r.Position.X, r.Position.Y, r.Position.Z)
end

local arena = Match.GetWorldArena("Forest")
say("Arena_Forest = %s", arena and ("(%.0f, %.0f, %.0f)"):format(
	arena.Position.X, arena.Position.Y, arena.Position.Z) or "-")
say("_defaultArenaKey = %s", tostring(Match._defaultArenaKey))
say("destino Arena existe = %s", tostring(Match._destinations.Arena ~= nil))

local portal = Portal.GetPortal("Forest")
say("cooldown restante = %s", tostring(portal and portal.State))

return table.concat(out, "\n")