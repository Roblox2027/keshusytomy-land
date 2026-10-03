-- place-bomb.lua
-- Coloca una bomba en la posicion real del personaje. Escribe estado del
-- juego a proposito: es la parte que hace la prueba, no una sonda de lectura.
local Players = game:GetService("Players")
local Round = require(game.ServerScriptService.Services.RoundService)
local Bomb = require(game.ServerScriptService.Services.BombService)

local p = Players:GetPlayers()[1]
if not p then return "no hay jugadores" end

local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
if not root then return "sin personaje" end

-- Fuera de la ronda el servidor rechaza la bomba POR DISENO: es la puerta de
-- estado funcionando, no un fallo de la cadena.
if not Round.IsPlaying() then
	return "estado=" .. tostring(Round.GetState())
end

local ok, reason = Bomb.TryPlaceBomb(p, root.Position + Vector3.new(0, 0, -8))
return string.format("colocada=%s motivo=%s", tostring(ok), tostring(reason))