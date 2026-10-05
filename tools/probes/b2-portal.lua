-- b2-portal.lua (SERVIDOR)
-- BLOQUE 2: una SOLA accion. Colocar al jugador junto al portal y entrar.
-- Sin esperas: si la ronda va a arrastrarlo, se mide en el bloque siguiente.
local Players = game:GetService("Players")
local Portal = require(game.ServerScriptService.Services.PortalService)
local Round = require(game.ServerScriptService.Services.RoundService)

local out = {}
local function say(f, ...) table.insert(out, string.format(f, ...)) end

local p = Players:GetPlayers()[1]
if not p or not p.Character then return "sin jugador" end

local portal = Portal.GetPortal("Forest")
if not portal then return "no hay Portal_Forest" end

say("ronda = %s | World antes = %s", tostring(Round.GetState()), tostring(p:GetAttribute("World")))

p.Character:PivotTo(CFrame.new(portal.Position + Vector3.new(0, 3, 0)))

local ok, motivo = Portal.TryEnter(p, "Forest")
say("TryEnter -> %s (%s)", tostring(ok), tostring(motivo))
say("World ahora = %s", tostring(p:GetAttribute("World")))

local r = p.Character:FindFirstChild("HumanoidRootPart")
if r then
	say("pos = (%.0f, %.0f, %.0f)", r.Position.X, r.Position.Y, r.Position.Z)
	say("dentro de Forest = %s", tostring(r.Position.X > 100))
end

return table.concat(out, "\n")