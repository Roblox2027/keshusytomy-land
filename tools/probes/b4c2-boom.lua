-- b4c2-boom.lua (SERVIDOR)
-- BLOQUE 4C completo: coloca la bomba Y la ve explotar, en UNA sola llamada
-- corta. La mecha son 3 s, asi que el presupuesto cabe en el timeout.
local Players = game:GetService("Players")
local Bomb = require(game.ServerScriptService.Services.BombService)
local Explosion = require(game.ServerScriptService.Services.ExplosionService)
local Destruction = require(game.ServerScriptService.Services.DestructionService)
local Round = require(game.ServerScriptService.Services.RoundService)

local out = {}
local function say(f, ...) table.insert(out, string.format(f, ...)) end

local p = Players:GetPlayers()[1]
if not p or not p.Character then return "sin jugador" end
local root = p.Character:FindFirstChild("HumanoidRootPart")
if not root then return "sin root" end

if not Round.IsPlaying() then
	return "no jugandoronda = " .. tostring(Round.GetState())
end

local folder = Bomb._bombFolder
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

-- Bloque objetivo: el mas cercano al jugador, para medir dano real.
local objetivo, mejor = nil, math.huge
for b in pairs(Destruction._blocks) do
	if b:IsA("BasePart") then
		local d = (b.Position - root.Position).Magnitude
		if d < mejor then
			mejor, objetivo = d, b
		end
	end
end

say("ronda = %s | bloque mas cercano = %s a %.1f studs", tostring(Round.GetState()),
	tostring(objetivo and objetivo.Name), mejor)

local explot0 = Explosion.GetExplosionCount()
local vfx0 = countVfx()
local vivos0 = Destruction.GetAliveBlockCount()
local destruidos0 = Destruction.GetDestroyedBlockCount()
local vida0 = objetivo and Destruction.GetBlockHealth(objetivo) or 0

local ok, motivo = Bomb.TryPlaceBomb(p, root.Position + Vector3.new(5, 0, 0))
say("BOMBA: ok=%s motivo=%s", tostring(ok), tostring(motivo))
if not ok then
	return table.concat(out, "\n")
end

local bomba = nil
for _, m in ipairs(folder:GetChildren()) do
	if m:IsA("Model") then
		bomba = m
	end
end
say("bomba = %s | FuseRemaining = %s",
	tostring(bomba and bomba.Name), tostring(bomba and bomba:GetAttribute("FuseRemaining")))

-- Se espera a que DESAPAREZCA. La explosion no se provoca a mano.
local goneAt = nil
for i = 1, 55 do
	if folder:FindFirstChild(bomba.Name) == nil then
		goneAt = i * 0.1
		break
	end
	task.wait(0.1)
end

say("")
if goneAt then
	say("la bomba desaparecio a los ~%.1f s", goneAt)
else
	say("la bomba SIGUE en el mundo tras 5.5 s")
end

say("explosiones = %d (+%d)", Explosion.GetExplosionCount(), Explosion.GetExplosionCount() - explot0)
say("VFX = %d (+%d)", countVfx(), countVfx() - vfx0)
say("bombas activas = %d", Bomb.GetActiveBombCount())
say("bloques vivos = %d -> %d | destruidos = %d -> %d",
	vivos0, Destruction.GetAliveBlockCount(),
	destruidos0, Destruction.GetDestroyedBlockCount())

if objetivo and objetivo.Parent then
	say("vida de %s = %d -> %d", objetivo.Name, vida0, Destruction.GetBlockHealth(objetivo))
end

return table.concat(out, "\n")