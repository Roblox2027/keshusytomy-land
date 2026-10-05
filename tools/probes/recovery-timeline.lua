-- recovery-timeline.lua (SERVIDOR)
-- Fase de RECUPERACION: OBSERVA, no cambia. Mide donde esta el jugador a lo
-- largo del ciclo de ronda para ver si la ronda lo expulsa del mundo.
--
-- No hace teleport ni llama a MatchService: solo mira. Cualquier intervencion
-- aqui invalidaria la medicion.

local Players = game:GetService("Players")
local Round = require(game.ServerScriptService.Services.RoundService)

local player = Players:GetPlayers()[1]
if not player or not player.Character then
	return "sin jugador"
end

local out = {}
local function say(fmt, ...)
	table.insert(out, string.format(fmt, ...))
end

say("t(s)  ronda             World       pos")
say("----  ---------------  ----------  ---------------------------")

local t = 0
for i = 1, 30 do
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local pos = if root then ("(%4.0f,%5.0f,%5.0f)"):format(
		root.Position.X, root.Position.Y, root.Position.Z) else "-"
	say("%4.1f  %-15s  %-10s  %s",
		t,
		tostring(Round.GetState()),
		tostring(player:GetAttribute("World")),
		pos)
	task.wait(1)
	t += 1
end

say("")
say("Ronda final = %s | World final = %s",
	tostring(Round.GetState()), tostring(player:GetAttribute("World")))
say("AliveCount = %d | PlayerCount = %d",
	Round.GetAliveCount(), Round.GetAliveCount())
say("_endRequested = %s | stallCount = %s | roundNumber = %s",
	tostring(Round._endRequested), tostring(Round._stallCount), tostring(Round.GetRoundNumber()))

return table.concat(out, "\n")