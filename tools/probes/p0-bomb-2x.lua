-- p0-bomb-2x.lua
-- P0 ABSOLUTO: dos bombas visibles, independientes, con mecha y explosion.
--
-- La ronda ya esta en `Playing` (esta sonda exige eso y lo dice si no).
-- Coloca A, comprueba que es REAL y SE VE, coloca B, y comprueba que las
-- dos coexisten con_positions, timers y mechas propias.

local Players = game:GetService("Players")
local Bomb = require(game.ServerScriptService.Services.BombService)
local Round = require(game.ServerScriptService.Services.RoundService)
local Explosion = require(game.ServerScriptService.Services.ExplosionService)
local cfg = require(game.ReplicatedStorage.Shared.Config.GameConfig)

local out = {}
local function say(fmt, ...) table.insert(out, string.format(fmt, ...)) end

local player = Players:GetPlayers()[1]
if not player or not player.Character then return "sin jugador" end

local root = player.Character:FindFirstChild("HumanoidRootPart")
if not root then return "sin root" end

say("Ronda = %s | mundo = %s", tostring(Round.GetState()), tostring(player:GetAttribute("World")))
say("Posicion = (%.0f, %.0f, %.0f)", root.Position.X, root.Position.Y, root.Position.Z)

if not Round.IsPlaying() then
	say("La ronda NO esta en Playing: la bomba no se puede colocar.")
	return table.concat(out, "\n")
end

local folder = Bomb._bombFolder
local function count() return #folder:GetChildren() end

say("Workspace.Bombs antes = %d", count())

-- Dos puntos distintos: A delante, B a un lado. Si compartieran posicion,
-- la prueba de "son independientes" no valdria nada.
local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
local side = Vector3.new(-look.Z, 0, look.X)
local posA = root.Position + look * 9
local posB = root.Position + look * 9 + side * 8

-- BOMBA A
local okA, motivoA = Bomb.TryPlaceBomb(player, posA)
local trasA = count()
say("")
say("BOMBA A: aceptada=%s motivo=%s | Workspace.Bombs = %d", tostring(okA), tostring(motivoA), trasA)

local function inspeccionar(model)
	if not model then return "sin instancia" end
	local partes = {}
	local solidas = 0
	local minY, maxY = math.huge, -math.huge

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			partes[#partes + 1] = d.Name
			if d.Transparency < 1 then solidas += 1 end
			minY = math.min(minY, d.Position.Y)
			maxY = math.max(maxY, d.Position.Y)
		end
	end

	table.sort(partes)
	local p = model.PrimaryPart

	return ("id=%s en (%.0f, %.0f, %.0f) partes=%d solids=%d alto=[%.1f..%.1f] mecha=%s"):format(
		tostring(model:GetAttribute("BombId")),
		p and p.Position.X or 0, p and p.Position.Y or 0, p and p.Position.Z or 0,
		#partes, solidas, minY, maxY,
		tostring(model:GetAttribute("FuseRemaining")))
end

local modelA = folder:GetChildren()[#folder:GetChildren()]
say("  A -> " .. inspeccionar(modelA))

-- BOMBA B: hay que esperar el enfriamiento. Se espera de verdad en vez de
-- asumir que el servidor lo dejaria pasar.
local espera = cfg.BombCooldown + 0.3
say("")
say("Esperando %.1f s de enfriamiento...", espera)
task.wait(espera)

local okB, motivoB = Bomb.TryPlaceBomb(player, posB)
local trasB = count()
say("BOMBA B: aceptada=%s motivo=%s | Workspace.Bombs = %d", tostring(okB), tostring(motivoB), trasB)

local hijos = folder:GetChildren()
local modelB = hijos[#hijos]
say("  B -> " .. inspeccionar(modelB))

-- INDEPENDENCIA: distintas, con mechas que NO coinciden.
if modelA and modelB and modelA ~= modelB then
	local d = (modelA.PrimaryPart.Position - modelB.PrimaryPart.Position).Magnitude
	local fa = modelA:GetAttribute("FuseRemaining")
	local fb = modelB:GetAttribute("FuseRemaining")
	say("")
	say("INDEPENDENCIA: separadas por %.1f studs | mechaA=%s mechaB=%s", d, tostring(fa), tostring(fb))
	say("  (mechas IGUALES = comparten reloj: FAIL)")
end

-- TERCERA: debe RECHAZARSE con motivo explicito de capacidad.
task.wait(espera)
local okC, motivoC = Bomb.TryPlaceBomb(player, root.Position + look * 9 - side * 8)
say("")
say("BOMBA C (debe rechazarse): aceptada=%s motivo=%s | total=%d",
	tostring(okC), tostring(motivoC), count())
say("BombRejection = %s", tostring(player:GetAttribute("BombRejection")))

-- CAPACIDAD REAL: cuantas caben segun la configuracion vigente.
say("")
say("Limite configurado por jugador = %d",
	require(game.ReplicatedStorage.Shared.Config.PerformanceConfig).Limits.MaxBombsPerPlayer)

return table.concat(out, "\n")
