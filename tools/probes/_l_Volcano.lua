-- b9-level.lua (SERVIDOR)
-- BLOQUE 9: entrada a un mundo CON EL PROGRESO CORRESPONDIENTE.
--
-- Los portales de Desert (10), Ice (20), Volcano (35) y Cyber (50) exigen
-- nivel: eso es DISENO, no un fallo, y `TryEnter` lo dice con un motivo
-- concreto. Para certificar que los cinco mundos son jugables hay que
-- llegar a ellos como lo haria un jugador que ha jugado: con el nivel puesto.
--
-- El nivel se sube por el servicio de progresion del propio juego, no
-- escribiendo el atributo a mano: asi se prueba el camino de verdad.
local Players = game:GetService("Players")
local Portal = require(game.ServerScriptService.Services.PortalService)
local Match = require(game.ServerScriptService.Services.MatchService)
local Round = require(game.ServerScriptService.Services.RoundService)

local worldId = "Volcano"
local nivel = 60

local out = {}
local function say(f, ...) table.insert(out, string.format(f, ...)) end

local p = Players:GetPlayers()[1]
if not p or not p.Character then return "sin jugador" end

-- El nivel vive en la SESION del jugador, no en el atributo. El atributo
-- `Level` es solo el espejo que publica `PlayerService` para el HUD, asi que
-- escribirlo a mano no cambia nada: el portal seguiria rechazando.
--
-- Por eso la progresion se sube por `ProgressionService.AddXP`, que es el
-- camino real que usa el juego. Si no llegara al nivel por XP, se dice, en
-- lugar de fingir que el portal deberia abrir.
local Progression = require(game.ServerScriptService.Services.ProgressionService)

local targetLevel = tonumber(worldId == "Desert" and 10 or worldId == "Ice" and 20
	or worldId == "Volcano" and 35 or 50) or 10

local actual = Portal.GetPlayerLevel(p)
say("nivel actual = %d | objetivo >= %d", actual, targetLevel)

if actual < targetLevel then
	local gained = false
	for _ = 1, 60 do
		if Progression.AddXP(p, 10000, "certificacion") then
			gained = true
		end
		if Portal.GetPlayerLevel(p) >= targetLevel then
			break
		end
	end
	say("AddXP -> %s | nivel ahora = %d", tostring(gained), Portal.GetPlayerLevel(p))
end

say("Level atributo = %s", tostring(p:GetAttribute("Level")))

local portal = Portal.GetPortal(worldId)
if not portal then return "no hay portal " .. worldId end

p.Character:PivotTo(CFrame.new(portal.Position + Vector3.new(0, 3, 0)))

local ok2, motivo = Portal.TryEnter(p, worldId)
say("")
say("TryEnter(%s) -> %s (%s)", worldId, tostring(ok2), tostring(motivo))
say("World = %s", tostring(p:GetAttribute("World")))

local root = p.Character:FindFirstChild("HumanoidRootPart")
if root then
	say("pos = (%.0f, %.0f, %.0f)", root.Position.X, root.Position.Y, root.Position.Z)
end

local arena = Match.GetWorldArena(worldId)
if arena and root then
	say("arena = (%.0f, %.0f, %.0f) | distancia = %.0f",
		arena.Position.X, arena.Position.Y, arena.Position.Z,
		(root.Position - arena.Position).Magnitude)
end

say("ronda = %s | IsPlaying = %s", tostring(Round.GetState()), tostring(Round.IsPlaying()))

return table.concat(out, "\n")