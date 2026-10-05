-- qa-bomb-explosion.lua
-- Cadena COMPLETA de la bomba, medida en el servidor vivo:
--   peticion -> instancia en Workspace.Bombs -> mecha -> detonacion ->
--   dano a bloques -> VFX -> limpieza
--
-- Se registra el estado de la bomba placed() a placed() + 0.2 s, luego a la
-- espera de la mecha, y despues el efecto. Cada paso imprime su propia
-- evidencia: si algo falta, se ve QUE paso falta y no solo "no exploto".
local Players = game:GetService("Players")
local Bomb = require(game.ServerScriptService.Services.BombService)
local Explosion = require(game.ServerScriptService.Services.ExplosionService)
local Destruction = require(game.ServerScriptService.Services.DestructionService)
local Round = require(game.ServerScriptService.Services.RoundService)

local out = {}

local function bombsInWorld()
	local folder = workspace:FindFirstChild("Bombs")
	if not folder then return 0, "sin carpeta Bombs" end
	local n = 0
	local names = {}
	for _, c in ipairs(folder:GetDescendants()) do
		n += 1
		if #names < 12 then
			table.insert(names, c.Name .. "[" .. c.ClassName .. "]")
		end
	end
	return n, table.concat(names, ",")
end

local function vfxInWorld()
	local folder = workspace:FindFirstChild("ExplosionVfx")
	if not folder then return 0, "sin carpeta ExplosionVfx" end
	local n = 0
	for _, c in ipairs(folder:GetChildren()) do n += 1 end
	return n
end

local p = Players:GetPlayers()[1]
if not p or not p.Character then return "sin jugador" end
if not Round.IsPlaying() then return "no_jugando: " .. tostring(Round.GetState()) end

local root = p.Character:FindFirstChild("HumanoidRootPart")

-- Se coloca JUNTO A UN BLOQUE REAL: si la bomba no toca nada, no hay dano que
-- medir y la prueba no dira nada sobre la destruccion.
local target = nil
local best = math.huge
for b in pairs(Destruction._blocks) do
	if b:IsA("BasePart") and Destruction.IsDestructibleBlock(b) then
		local d = (b.Position - root.Position).Magnitude
		if d < best then best = d target = b end
	end
end

table.insert(out, string.format("ronda=%s mundo=%s bloque objetivo=%s a %.1f studs",
	tostring(Round.GetState()), tostring(p:GetAttribute("World")), target and target.Name or "n/d", best))

local antesDestruidos = Destruction.GetDestroyedBlockCount()
local pos = (target and (target.Position + Vector3.new(0, 3, 0))) or (root.Position + Vector3.new(0, 0, -8))

local placed, reason = Bomb.TryPlaceBomb(p, pos)
table.insert(out, string.format("1. peticion: puesta=%s motivo=%s", tostring(placed), tostring(reason)))

task.wait(0.2)
local n1, names1 = bombsInWorld()
table.insert(out, string.format("2. instancia en Workspace.Bombs=%d (%s)", n1, names1))
table.insert(out, string.format("   Bombs.GetActiveBombCount=%d", Bomb.GetActiveBombCount()))

-- INSTANTE DE LA DETONACION.
local explosionesAntes = Explosion.GetExplosionCount()
local vfxAntes = vfxInWorld()

-- Se espera a que la bomba detone (o a que se agote el margen).
for _ = 1, 60 do
	task.wait(0.25)
	if Explosion.GetExplosionCount() > explosionesAntes then break end
	if bombsInWorld() == 0 and _ > 4 then break end
end

local n2 = bombsInWorld()
table.insert(out, string.format("3. tras la mecha: Bombs=%d (0 = ya detono y se limpio)", n2))
table.insert(out, string.format("   ExplosionService.GetExplosionCount=%d", Explosion.GetExplosionCount()))
table.insert(out, string.format("4. VFX en Workspace.ExplosionVfx=%d", vfxInWorld()))
table.insert(out, string.format("5. bloques: destruidos %d -> %d (daño real=%s)",
	antesDestruidos, Destruction.GetDestroyedBlockCount(),
	tostring(Destruction.GetDestroyedBlockCount() > antesDestruidos or "sin cambio en este instante")))

return table.concat(out, "\n")