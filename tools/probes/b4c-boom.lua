-- b4c-boom.lua (SERVIDOR)
-- BLOQUE 4C: la bomba EXPLOTA. Espera solo lo que dura la mecha (3 s), con
-- sondeos cortos para no comerse el timeout del puente.
local Players = game:GetService("Players")
local Bomb = require(game.ServerScriptService.Services.BombService)
local Explosion = require(game.ServerScriptService.Services.ExplosionService)
local Destruction = require(game.ServerScriptService.Services.DestructionService)

local out = {}
local function say(f, ...) table.insert(out, string.format(f, ...)) end

local p = Players:GetPlayers()[1]
if not p then return "sin jugador" end

local folder = Bomb._bombFolder
local bomba = nil
if folder then
	for _, m in ipairs(folder:GetChildren()) do
		if m:IsA("Model") then
			bomba = m
		end
	end
end

say("bomba viva = %s", tostring(bomba ~= nil))
if not bomba then return table.concat(out, "\n") end

say("BombId = %s | FuseRemaining = %s",
	tostring(bomba:GetAttribute("BombId")), tostring(bomba:GetAttribute("FuseRemaining")))

local_folder = nil
local vfxFolder = workspace:FindFirstChild("ExplosionVfx")
local function countVfx(): number
	if not vfxFolder then
		return 0
	end
	local n = 0
	for _ in pairs(vfxFolder:GetChildren()) do
		n += 1
	end
	return n
end

local explot0 = Explosion.GetExplosionCount()
local vfx0 = countVfx()

say("")
say("antes: explosiones = %d | VFX = %d", explot0, vfx0)

-- La bomba se va sola: se vigila su nombre, sin tocarlo. La explosion NO se
-- provoca a mano: lo que se quiere medir es el ciclo natural de la bomba.
local goneAt = nil
for i = 1, 55 do
	if folder:FindFirstChild(bomba.Name) == nil then
		goneAt = i * 0.1
		break
	end
	task.wait(0.1)
end

if goneAt then
	say("la bomba desaparecio del mundo a los ~%.1f s", goneAt)
else
	say("la bomba SIGUE en el mundo tras 5.5 s")
end

say("")
say("despues: explosiones = %d (+%d) | VFX = %d (+%d)",
	Explosion.GetExplosionCount(), Explosion.GetExplosionCount() - explot0,
	countVfx(), countVfx() - vfx0)
say("bomba sigue en el mundo = %s", tostring(folder:FindFirstChild(bomba.Name) ~= nil))
say("bombas activas = %d", Bomb.GetActiveBombCount())

return table.concat(out, "\n")