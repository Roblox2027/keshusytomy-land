-- b9-world.lua (SERVIDOR)
-- BLOQUE 9: entrada a UN mundo. El id se pasa por el atajo `_ENV`.
-- Uso:  server b9-world.lua  ->  Desert
--
-- Una sola accion por llamada: entrar y reportar. Los cinco mundos se
-- certifican en cinco llamadas, no en una que dura mas que el timeout.
local Players = game:GetService("Players")
local Portal = require(game.ServerScriptService.Services.PortalService)
local Match = require(game.ServerScriptService.Services.MatchService)
local World = require(game.ServerScriptService.Services.WorldService)
local Round = require(game.ServerScriptService.Services.RoundService)

local worldId = "Desert" :: string

local out = {}
local function say(f, ...) table.insert(out, string.format(f, ...)) end

local p = Players:GetPlayers()[1]
if not p or not p.Character then return "sin jugador" end

say("=== MUNDO: %s ===", worldId)
say("WorldService registra %s = %s",
	worldId, tostring(World.IsWorldAvailable(worldId)))
say("ronda = %s | World actual = %s", tostring(Round.GetState()), tostring(p:GetAttribute("World")))

local portal = Portal.GetPortal(worldId)
if not portal then
	return table.concat(out, "\n") .. "\nNO HAY PORTAL para " .. worldId
end
say("portal = %s | estado = %s", portal.Name, tostring(portal.State))

-- Se coloca al jugador EN el portal: el portal exige proximidad.
p.Character:PivotTo(CFrame.new(portal.Position + Vector3.new(0, 3, 0)))

local ok, motivo = Portal.TryEnter(p, worldId)
say("TryEnter -> %s (%s)", tostring(ok), tostring(motivo))
say("World ahora = %s", tostring(p:GetAttribute("World")))

local root = p.Character:FindFirstChild("HumanoidRootPart")
if root then
	say("pos = (%.0f, %.0f, %.0f)", root.Position.X, root.Position.Y, root.Position.Z)
end

-- La arena de ESE mundo tiene que existir y estar donde el jugador esta.
local arena = Match.GetWorldArena(worldId)
if arena then
	say("arena de %s = (%.0f, %.0f, %.0f)", worldId,
		arena.Position.X, arena.Position.Y, arena.Position.Z)
	if root then
		local d = (root.Position - arena.Position).Magnitude
		say("distancia jugador-arena = %.0f studs", d)
	end
else
	say("NO HAY ARENA para %s", worldId)
end

return table.concat(out, "\n")
