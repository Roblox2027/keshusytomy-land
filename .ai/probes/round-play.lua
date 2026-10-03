-- Encadena el ciclo de ronda por su API PUBLICA (`Transition`), pasando por
-- los estados que el diagrama permite: Waiting -> Countdown ->
-- RoundStarting -> Playing.
--
-- Sin esto la ronda tarda minutos en arrancar sola durante el ensayo y la
-- bomba no se puede colocar nunca (`TryPlaceBomb` exige ronda en curso).
local services = game:GetService("ServerScriptService").Services
local roundService = require(services:WaitForChild("RoundService"))

local pasos = { "Countdown", "RoundStarting", "Playing" }
local resultados = {}

for _, estado in ipairs(pasos) do
	resultados[estado] = roundService.Transition(estado)
end

return {
	estado = roundService.GetState(),
	isPlaying = roundService.IsPlaying(),
	transiciones = string.format("%s=%s %s=%s %s=%s",
		pasos[1], tostring(resultados[pasos[1]]),
		pasos[2], tostring(resultados[pasos[2]]),
		pasos[3], tostring(resultados[pasos[3]])),
}