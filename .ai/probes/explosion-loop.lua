-- Repite una explosion cada 0.5 s durante 40 s para que la sonda del
-- CLIENTE tenga occasion depillarla en pantalla. El efecto real dura 0.8 s.
--
-- No es un atajo para el juego: `ExplosionService.Detonate` es la MISMA
-- funcion que ejecuta la bomba. Lo unico que se cambia es la cadencia.
local services = game:GetService("ServerScriptService").Services
local explosionService = require(services:WaitForChild("ExplosionService"))

local player = game:GetService("Players"):GetPlayers()[1]
local root = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")

if not root then
	return { error = "sin jugador" }
end

local centro = root.Position + Vector3.new(8, 0, 0)

task.spawn(function()
	for _ = 1, 80 do
		explosionService.Detonate(centro, 24, player.UserId, "Forest")
		task.wait(0.5)
	end
end)

return { centro = tostring(centro), DURACION = 40 }