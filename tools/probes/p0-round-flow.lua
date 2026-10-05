-- p0-round-flow.lua (parte 1)
-- Mete al jugador en Forest por la via REAL y mide si la ronda arranca.
--
-- Sondeo CORTO a proposito: el servidor de MCP tiene timeout y una espera
-- larga pierde el informe entero. Cada paso devuelve lo que va sabiendo.

local Players = game:GetService("Players")
local Match = require(game.ServerScriptService.Services.MatchService)
local Bomb = require(game.ServerScriptService.Services.BombService)
local Round = require(game.ServerScriptService.Services.RoundService)
local cfg = require(game.ReplicatedStorage.Shared.Config.GameConfig)

local out = {}
local function say(fmt, ...) table.insert(out, string.format(fmt, ...)) end

local player = Players:GetPlayers()[1]
if not player or not player.Character then return "sin jugador" end

say("MinPlayersToStart = %d", cfg.MinPlayersToStart)
say("Ronda antes = %s | vivos = %d", tostring(Round.GetState()), Round.GetAliveCount())
say("Mundo antes = %s", tostring(player:GetAttribute("World")))

local okM, motivoM = Match.MovePlayer(player, "Forest")
say("MovePlayer(Forest) -> ok=%s motivo=%s", tostring(okM), tostring(motivoM))
say("Mundo ahora = %s", tostring(player:GetAttribute("World")))

local root = player.Character:FindFirstChild("HumanoidRootPart")
if root then
	say("Posicion = (%.0f, %.0f, %.0f)", root.Position.X, root.Position.Y, root.Position.Z)
end

-- Sondeo de 8 s: solo mira si la ronda AVANZA. No espera a que termine.
local visto = {}
for _ = 1, 16 do
	local s = Round.GetState()
	visto[#visto + 1] = s

	if s == "Playing" or s == "SuddenDeath" then
		break
	end

	task.wait(0.5)
end

local unico = {}
for _, s in ipairs(visto) do
	if unico[#unico + 1] ~= s then
		unico[#unico + 1] = s
	end
end

say("Estados vistos = %s", table.concat(unico, " > "))
say("Ronda final = %s IsPlaying=%s", tostring(Round.GetState()), tostring(Round.IsPlaying()))

-- Bomba A con la ronda ya activa: es la pregunta del P0.
if Round.IsPlaying() and root then
	local look = root.CFrame.LookVector
	local pedi = root.Position + Vector3.new(look.X, 0, look.Z).Unit * 8

	local antes = #Bomb._bombFolder:GetChildren()
	local ok, motivo = Bomb.TryPlaceBomb(player, pedi)
	say("")
	say("BOMBA A: ok=%s motivo=%s | Workspace.Bombs %d -> %d",
		tostring(ok), tostring(motivo), antes, #Bomb._bombFolder:GetChildren())
	say("BombRejection = %s", tostring(player:GetAttribute("BombRejection")))
end

return table.concat(out, "\n")
