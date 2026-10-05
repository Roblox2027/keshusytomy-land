-- qa-detonate2.lua
-- Dos detonaciones sobre el MISMO bloque, en el MISMO lugar donde cae la
-- bomba. Comprueba el ciclo entero: dano -> destruccion -> VFX -> limpieza.
--
-- Se llama a `Detonate` directamente porque el MCP corta la llamada a los
-- ~20 s y la mecha de la bomba dura 3 s: esperar dentro de la sonda agota el
-- tiempo. Aqui cada paso es instantaneo y el resultado es igualmente real,
-- porque `Detonate` es EXACTAMENTE lo que la bomba invoca al detonar.
local Destruction = require(game.ServerScriptService.Services.DestructionService)
local Explosion = require(game.ServerScriptService.Services.ExplosionService)

local out = {}

local target = nil
local best = math.huge
for b in pairs(Destruction._blocks) do
	if b:IsA("BasePart") and Destruction.IsDestructibleBlock(b) then
		local d = (b.Position - Vector3.zero).Magnitude
		if d < best then
			best = d
			target = b
		end
	end
end

if not target then return "sin bloques" end

local center = target.Position + Vector3.new(0, 2, 0)
local folder = workspace:FindFirstChild("ExplosionVfx")

local function vfx()
	local n = 0
	if folder then
		for _ in pairs(folder:GetChildren()) do
			n += 1
		end
	end
	return n
end

table.insert(out, string.format("bloque=%s destructible=%s vida=%d",
	target.Name, tostring(Destruction.IsDestructibleBlock(target)), Destruction.GetBlockHealth(target)))

local function step(label)
	table.insert(out, string.format("%s | vida=%d IsDestroyed=%s destruidos=%d VFX=%d Transparency=%s CanCollide=%s",
		label,
		Destruction.GetBlockHealth(target),
		tostring(target:GetAttribute("IsDestroyed")),
		Destruction.GetDestroyedBlockCount(),
		vfx(),
		tostring(target.Transparency),
		tostring(target.CanCollide)))
end

step("inicio")

local d0 = Destruction.GetDestroyedBlockCount()
local a1 = Explosion.Detonate(center, 24, nil, "Forest")
table.insert(out, string.format("explosion 1: afectadas=%d", a1))
step("tras explosion 1")

local a2 = Explosion.Detonate(center, 24, nil, "Forest")
table.insert(out, string.format("explosion 2: afectadas=%d", a2))
step("tras explosion 2")

table.insert(out, string.format("destruidos: %d -> %d | GetExplosionCount=%d | duplicados=[%s]",
	d0, Destruction.GetDestroyedBlockCount(), Explosion.GetExplosionCount(),
	table.concat(Destruction.AuditDuplicates(), " | ")))

return table.concat(out, "\n")