-- qa-detonate.lua
-- Comprueba si `ExplosionService.Detonate` alcanza bloques de verdad y por que
-- `GetExplosionCount` no se mueve. Se llama DIRECTAMENTE, sin pasar por la
-- bomba, para separar "la bomba no detona" de "la detonacion no hace dano".
local Destruction = require(game.ServerScriptService.Services.DestructionService)
local Explosion = require(game.ServerScriptService.Services.ExplosionService)

local out = {}

-- Se busca el bloque destructible mas cercano al ORIGEN.
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

if not target then return "sin bloques destructibles" end

local center = target.Position + Vector3.new(0, 2, 0)
table.insert(out, string.format("bloque=%s pos=%s destructible=%s vida=%d",
	target.Name, tostring(target.Position), tostring(Destruction.IsDestructibleBlock(target)), Destruction.GetBlockHealth(target)))

local antes = Explosion.GetExplosionCount()
local affected = Explosion.Detonate(center, 24, nil, "Forest")
table.insert(out, string.format("Detonate -> afectadas=%d", affected))
table.insert(out, string.format("GetExplosionCount %d -> %d", antes, Explosion.GetExplosionCount()))
table.insert(out, string.format("vida del bloque tras Detonate = %d", Destruction.GetBlockHealth(target)))
table.insert(out, string.format("IsDestroyed=%s", tostring(target:GetAttribute("IsDestroyed"))))

-- Cuantas partes hay realmente en el radio con y sin `RespectCanCollide`.
local q1 = OverlapParams.new()
q1.FilterType = Enum.RaycastFilterType.Include
q1.FilterDescendantsInstances = { workspace }
q1.RespectCanCollide = true
local conColision = #workspace:GetPartBoundsInRadius(center, 24, q1)

local q2 = OverlapParams.new()
q2.FilterType = Enum.RaycastFilterType.Include
q2.FilterDescendantsInstances = { workspace }
q2.RespectCanCollide = false
local sinColision = #workspace:GetPartBoundsInRadius(center, 24, q2)

table.insert(out, string.format("partes en radio: conCanCollide=%d sinCanCollide=%d", conColision, sinColision))
table.insert(out, string.format("bloque.CanCollide=%s Transparency=%s", tostring(target.CanCollide), tostring(target.Transparency)))

return table.concat(out, "\n")