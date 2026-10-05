-- b4e-capacity.lua (SERVIDOR)
-- BOMBA B: distinguir COOLDOWN de CAPACIDAD MAXIMA.
--
-- El sintoma reportado era "solo puedo colocar una bomba". Son dos cosas
-- distintas y aqui se separan:
--
--   - COLOCACION: Bomba A a t=0, Bomba B a t=1.6 (cooldown = 1.5 s).
--   - CAPACIDAD: Bomba C intentada con DOS bombas VIVAS en el mundo. Con
--     `BombCapacity = 2` tiene que ACEPTAR la tercera si las dos anteriores
--     ya explotaron, y RECHAZAR una cuarta si sigue habiendo dos vivas.
local Players = game:GetService("Players")
local Bomb = require(game.ServerScriptService.Services.BombService)
local Round = require(game.ServerScriptService.Services.RoundService)
local Config = require(game.ReplicatedStorage.Shared.Config.GameConfig)

local out = {}
local function say(f, ...) table.insert(out, string.format(f, ...)) end

local p = Players:GetPlayers()[1]
if not p or not p.Character then return "sin jugador" end
local root = p.Character:FindFirstChild("HumanoidRootPart")
if not root then return "sin root" end

if not Round.IsPlaying() then
	return "no jugando, ronda = " .. tostring(Round.GetState())
end

say("BombCapacity = %s | BombCooldown = %s",
	tostring(Config.BombCapacity), tostring(Config.BombCooldown))
say("bombas vivas al empezar = %d", Bomb.GetActiveBombCount())

-- A: primera bomba.
local a0 = Bomb.GetActiveBombCount()
local okA, mA = Bomb.TryPlaceBomb(p, root.Position + Vector3.new(5, 0, 0))
say("A: ok=%s motivo=%s | %d -> %d", tostring(okA), tostring(mA), a0, Bomb.GetActiveBombCount())

-- B: INMEDIATAMENTE, sin esperar. Debe fallar por COOLDOWN, no por capacidad.
local b0 = Bomb.GetActiveBombCount()
local okB, mB = Bomb.TryPlaceBomb(p, root.Position + Vector3.new(-5, 0, 0))
say("B (inmediata): ok=%s motivo=%s | %d -> %d", tostring(okB), tostring(mB), b0, Bomb.GetActiveBombCount())
say("  -> el motivo distingue cooldown de capacidad: %s",
	tostring(mB and string.find(tostring(mB), "enfriamiento", 1, true) ~= nil))

-- C: tras el cooldown, con UNA bomba viva. Debe aceptarse.
task.wait(1.7)
local c0 = Bomb.GetActiveBombCount()
local okC, mC = Bomb.TryPlaceBomb(p, root.Position + Vector3.new(0, 0, -5))
say("C (tras cooldown): ok=%s motivo=%s | %d -> %d", tostring(okC), tostring(mC), c0, Bomb.GetActiveBombCount())

-- D: ahora hay DOS vivas. Una tercera debe RECHAZARSE por capacidad si la
-- capacidad really is 2.
task.wait(1.7)
local d0 = Bomb.GetActiveBombCount()
local okD, mD = Bomb.TryPlaceBomb(p, root.Position + Vector3.new(0, 0, 5))
say("D (con 2 vivas): ok=%s motivo=%s | %d -> %d", tostring(okD), tostring(mD), d0, Bomb.GetActiveBombCount())

return table.concat(out, "\n")