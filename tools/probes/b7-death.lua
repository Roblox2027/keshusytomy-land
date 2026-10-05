-- b7-death.lua (SERVIDOR)
-- BLOQUE 7, paso 1: PROVOCAR la caida. No se espera la muerte aqui: solo se
-- deja al jugador cayendo y se mide por donde va.
local Players = game:GetService("Players")
local Spawn = require(game.ServerScriptService.Services.SpawnService)
local out = {}
local function say(f, ...) table.insert(out, string.format(f, ...)) end

local p = Players:GetPlayers()[1]
if not p or not p.Character then return "sin jugador" end
local root = p.Character:FindFirstChild("HumanoidRootPart")
local hum = p.Character:FindFirstChildOfClass("Humanoid")
if not root or not hum then return "sin root/humanoid" end

say("antes: pos = (%.0f, %.0f, %.0f) | vida = %d | World = %s",
	root.Position.X, root.Position.Y, root.Position.Z, hum.Health, tostring(p:GetAttribute("World")))
say("FallDeathY = %s | OutOfBoundsY = %s",
	tostring(require(game.ReplicatedStorage.Shared.Config.GameConfig).FallDeathY),
	tostring(require(game.ReplicatedStorage.Shared.Config.GameConfig).OutOfBoundsY))

-- Se teletransporta DEBAJO del umbral de caida. Es lo mismo queCaer por el
-- borde: la muerte tiene que decidirse por la posicion, no por un boton.
root.CFrame = CFrame.new(root.Position.X, -70, root.Position.Z)
say("")
say("teleportado a y = -70 (por debajo del umbral)")
say("OutOfBounds = %s", tostring(p:GetAttribute("OutOfBounds")))
return table.concat(out, "\n")