-- b4d-destroy.lua (SERVIDOR)
-- BLOQUE 4D: DESTRUCCION. La bomba se coloca pegada al bloque mas cercano, no
-- a 5 studs del JUGADOR: si el bloque esta a 50 studs, no hay dano por
-- diseno, y medir ahi daria un falso negativo.
--
-- Nota sobre el falso negativo anterior: la explosion hace 120 de dano y el
-- bloque recibe el 50 % (60). Con 100 de vida, UNA bomba deja el bloque en
-- 40 y NO lo destruye. Se_placean dos bombas para medir dano real.
local Players = game:GetService("Players")
local Bomb = require(game.ServerScriptService.Services.BombService)
local Destruction = require(game.ServerScriptService.Services.DestructionService)
local Round = require(game.ServerScriptService.Services.RoundService)

local out = {}
local function say(f, ...) table.insert(out, string.format(f, ...)) end

local p = Players:GetPlayers()[1]
if not p or not p.Character then return "sin jugador" end
local root = p.Character:FindFirstChild("HumanoidRootPart")
if not root then return "sin root" end

if not Round.IsPlaying() then
	return "no jugando, ronda = " .. tostring(Round.GetState())
end

-- El bloque objetivo debe estar AL ALCANCE de colocacion: el jugador se
-- coloca junto a el. Es lo que haria un jugador real, no un teletransporte
-- del bloque.
local objetivo, mejor = nil, math.huge
for b in pairs(Destruction._blocks) do
	if b:IsA("BasePart") and Destruction.IsDestructibleBlock(b) then
		local d = (b.Position - root.Position).Magnitude
		if d < mejor then
			mejor, objetivo = d, b
		end
	end
end

if not objetivo then return "sin bloques destructibles" end

say("bloque = %s | vida inicial = %d | a %.1f studs del jugador",
	objetivo.Name, Destruction.GetBlockHealth(objetivo), mejor)

-- El jugador se acerca al bloque, como haria caminando.
root.CFrame = CFrame.new(objetivo.Position + Vector3.new(0, 4, 0))
say("jugador colocado a %.1f studs del bloque",
	(objetivo.Position - root.Position).Magnitude)

local folder = Bomb._bombFolder
local function place(pos: Vector3): (boolean, string?)
	return Bomb.TryPlaceBomb(p, pos)
end

local vida0 = Destruction.GetBlockHealth(objetivo)
local destruidos0 = Destruction.GetDestroyedBlockCount()

-- Bomba 1
local ok1, m1 = place(objetivo.Position + Vector3.new(3, 1, 0))
say("bomba 1: ok=%s motivo=%s", tostring(ok1), tostring(m1))

local function waitGone(before: number, maxTenths: number): number
	local t = 0
	while t < maxTenths do
		if #folder:GetChildren() <= before then
			return t * 0.1
		end
		task.wait(0.1)
		t += 1
	end
	return -1
end

local c1 = #folder:GetChildren()
local t1 = waitGone(c1 - 1, 45)
say("bomba 1 desaparecio a los ~%.1f s", t1)
say("vida tras bomba 1 = %d", Destruction.GetBlockHealth(objetivo))

-- Bomba 2: la capacidad es 2 y el cooldown 1.5 s ya ha pasado.
task.wait(1.6)
local ok2, m2 = place(objetivo.Position + Vector3.new(-3, 1, 0))
say("bomba 2: ok=%s motivo=%s", tostring(ok2), tostring(m2))

local c2 = #folder:GetChildren()
local t2 = waitGone(c2 - 1, 45)
say("bomba 2 desaparecio a los ~%.1f s", t2)

say("")
say("vida %d -> %d | destruidos %d -> %d | vivos = %d",
	vida0, Destruction.GetBlockHealth(objetivo),
	destruidos0, Destruction.GetDestroyedBlockCount(),
	Destruction.GetAliveBlockCount())

return table.concat(out, "\n")