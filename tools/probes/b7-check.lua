-- b7-check.lua (SERVIDOR)
-- BLOQUE 7, pasos 2 y 3: COMPROBAR la muerte y el respawn. SIN ESPERAS:
-- la muerte y el respawn ocurren solos, asi que aqui solo se mira.
local Players = game:GetService("Players")
local out = {}
local function say(f, ...) table.insert(out, string.format(f, ...)) end

local p = Players:GetPlayers()[1]
if not p then return "sin jugador" end

say("character = %s", tostring(p.Character))

local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")

say("vida = %s | posicion = %s",
	tostring(hum and hum.Health),
	root and ("(%.0f, %.0f, %.0f)"):format(root.Position.X, root.Position.Y, root.Position.Z) or "-")
say("World = %s", tostring(p:GetAttribute("World")))
say("PlayerState = %s", tostring(p:GetAttribute("PlayerState")))
say("OutOfBounds = %s", tostring(p:GetAttribute("OutOfBounds")))
say("Deaths = %s", tostring(p:GetAttribute("Deaths")))

-- El diseno prohibe que `World` y la posicion se contradigan. El lobby esta
-- cerca del origen; los mundos, lejos. Se comprueba el caso concreto.
local enLobby = root ~= nil and math.abs(root.Position.X) < 80 and math.abs(root.Position.Z) < 80
local diceLobby = p:GetAttribute("World") == "Lobby"

if diceLobby and not enLobby then
	say("CONTRADICCION: dice Lobby pero NO esta en la zona del lobby")
elseif enLobby and not diceLobby then
	say("CONTRADICCION: esta en la zona del lobby pero dice %s", tostring(p:GetAttribute("World")))
else
	say("World y posicion = COHERENTES")
end

return table.concat(out, "\n")