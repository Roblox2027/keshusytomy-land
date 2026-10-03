-- Coloca una bomba pulsando la TECLA REAL del cliente (simulate_keyboard
-- input `F`) y despues mide el modelo DESDE EL CLIENTE. Es el camino entero:
-- F -> InputController -> BombController -> remoto -> BombService -> modelo.
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local out = {}
out.roundState = tostring(player:GetAttribute("RoundState"))
out.world = tostring(player:GetAttribute("World"))
out.bombsAntes = #workspace.Bombs:GetChildren()

local gui = player:WaitForChild("PlayerGui"):WaitForChild("KeshusyHUD")
out.hud = {
	dv = gui:FindFirstChild("DamageVignette") ~= nil,
	dn = gui:FindFirstChild("DamageNumbers") ~= nil,
	ab = gui:FindFirstChild("ActiveBombs") ~= nil,
	pr = gui:FindFirstChild("PowerupRow") ~= nil,
}

return out