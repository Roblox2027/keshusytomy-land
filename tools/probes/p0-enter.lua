-- p0-enter.lua
-- Entra a Forest por el PORTAL REAL (la misma funcion a la que llama el
-- jugador) y mide si la ronda arranca.
--
-- El jugador se COLOCA junto al portal antes de entrar: `CanTravel` exige
-- estar a distancia de activacion, asi que sin esto el rechazo seria el de
-- pulsar E sin haber caminado hasta el portal.
--
-- Por que `TryEnter` y no `MovePlayer`: `MovePlayer` pide la CLAVE del
-- destino (`Arena_Forest`), no el nombre del mundo. Llamarla con "Forest"
-- devuelve `false` sin decir por que, que es una trampa para diagnosticar.

local Players = game:GetService("Players")
local Portal = require(game.ServerScriptService.Services.PortalService)
local Match = require(game.ServerScriptService.Services.MatchService)
local Round = require(game.ServerScriptService.Services.RoundService)

local out = {}
local function say(fmt, ...) table.insert(out, string.format(fmt, ...)) end

local player = Players:GetPlayers()[1]
if not player or not player.Character then return "sin jugador" end

local root = player.Character:FindFirstChild("HumanoidRootPart")
if not root then return "sin root" end

say("Mundo antes = %s | ronda antes = %s",
	tostring(player:GetAttribute("World")), tostring(Round.GetState()))

local portal = Portal.GetPortal("Forest")
if not portal then
	say("NO existe el portal de Forest en el mapa.")
	return table.concat(out, "\n")
end

say("Portal Forest = %s en (%.0f, %.0f, %.0f) estado=%s",
	portal.Name,
	portal.Position.X, portal.Position.Y, portal.Position.Z,
	tostring(portal.State))

-- Caminar hasta el portal: el jugador se coloca a su lado.
local destino = portal.Position + Vector3.new(0, 4, 0)
player.Character:PivotTo(CFrame.new(destino))
say("Jugador colocado en (%.0f, %.0f, %.0f)", destino.X, destino.Y, destino.Z)

local ok, motivo = Portal.TryEnter(player, "Forest")
say("TryEnter(Forest) -> %s (%s)", tostring(ok), tostring(motivo))
say("Mundo ahora = %s", tostring(player:GetAttribute("World")))

local p = player.Character:FindFirstChild("HumanoidRootPart")
if p then
	say("Posicion = (%.0f, %.0f, %.0f)", p.Position.X, p.Position.Y, p.Position.Z)
end

-- Sondeo de la ronda (10 s). Solo mira si AVANZA, no espera a que acabe.
local visto = {}
for _ = 1, 20 do
	local s = Round.GetState()

	if visto[#visto + 1] ~= s then
		visto[#visto + 1] = s
	end

	if s == "Playing" or s == "SuddenDeath" then
		break
	end

	task.wait(0.5)
end

say("Estados = %s", table.concat(visto, " > "))
say("Ronda final = %s IsPlaying=%s vivos=%d",
	tostring(Round.GetState()), tostring(Round.IsPlaying()), Round.GetAliveCount())

-- Si la ronda esta viva, se mide cuanto aguanta: con un solo jugador el
-- codigo termina la ronda en cuanto `GetAliveCount() <= 1`, que SIEMPRE se
-- cumple, asi que `Playing` podria durar cero segundos.
if Round.IsPlaying() then
	task.wait(3)
	say("Tras 3 s de Playing, la ronda esta en %s", tostring(Round.GetState()))
end

local claves = {}
for k in pairs(Match._destinations) do
	claves[#claves + 1] = k
end
table.sort(claves)
say("Claves de destino = %s", table.concat(claves, ", "))

return table.concat(out, "\n")
