-- recovery-lobby.lua (SERVIDOR)
-- Fase de RECUPERACION, parte 1: LOBBY, PORTALES y ENTRADA.
--
-- No parchea nada: mide. Cada paso es CORTO porque el servidor de MCP tiene
-- timeout y una sonda larga pierde el informe entero.

local Players = game:GetService("Players")
local Portal = require(game.ServerScriptService.Services.PortalService)
local Round = require(game.ServerScriptService.Services.RoundService)

local out = {}
local function say(fmt, ...)
	table.insert(out, string.format(fmt, ...))
end

local player = Players:GetPlayers()[1]
if not player or not player.Character then
	return "sin jugador"
end

say("=== ESTADO INICIAL ===")
say("Mundo atributo = %s | ronda = %s | vivos = %d",
	tostring(player:GetAttribute("World")),
	tostring(Round.GetState()),
	Round.GetAliveCount())

-- ------------------------------------------------------------------ LOBBY
say("")
say("=== TEST 1: LOBBY ===")
local lobby = workspace.Lobby
say("workspace.Lobby existe = %s", tostring(lobby ~= nil))
say("Portals existe = %s", tostring(lobby and lobby:FindFirstChild("Portals") ~= nil))
say("Hijos del lobby = %d", lobby and #lobby:GetChildren() or 0)
local spawns = workspace:FindFirstChild("SpawnLocations")
say("SpawnLocations = %d", spawns and #spawns:GetChildren() or 0)

-- --------------------------------------------------------------- PORTALES
say("")
say("=== TEST 2: PORTALES ===")
for _, worldId in ipairs({ "Forest", "Desert", "Ice", "Volcano", "Cyber" }) do
	local p = Portal.GetPortal(worldId)
	if p then
		say("%-8s -> %-14s pos=(%.0f, %.0f, %.0f) estado=%s",
			worldId, p.Name, p.Position.X, p.Position.Y, p.Position.Z, tostring(p.State))
	else
		say("%-8s -> NO EXISTE", worldId)
	end
end

-- ------------------------------------------------------ ENTRADA POR PORTAL
say("")
say("=== TEST 3: ENTRADA POR PORTAL ===")
local portal = Portal.GetPortal("Forest")
if not portal then
	return table.concat(out, "\n")
end

player.Character:PivotTo(CFrame.new(portal.Position + Vector3.new(0, 4, 0)))
local ok, motivo = Portal.TryEnter(player, "Forest")
say("TryEnter(Forest) -> %s (%s)", tostring(ok), tostring(motivo))
say("Mundo tras entrar = %s", tostring(player:GetAttribute("World")))

local root = player.Character:FindFirstChild("HumanoidRootPart")
if root then
	say("Posicion = (%.0f, %.0f, %.0f)", root.Position.X, root.Position.Y, root.Position.Z)
end

-- La ronda debe arrancar sola. Sondeo CORTO: solo mira que AVANCE.
local visto = {}
for _ = 1, 24 do
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
say("Ronda = %s IsPlaying=%s", tostring(Round.GetState()), tostring(Round.IsPlaying()))

return table.concat(out, "\n")