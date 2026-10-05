-- qa-bomb-2x.lua
-- Prueba DEFINITIVA de destruccion por bomba: DOS bombas sobre el MISMO bloque.
--
-- Por que dos y no una: el contrato del balance es 120 de dano de explosion y
-- el bloque recibe el 50% (60), con 100 de vida. Una bomba deja al bloque en
-- 40 y NO lo destruye. Medir "una bomba" y concluir que la destruccion falla
-- seria un falso negativo.
--
-- POR QUE ESTA ESCRITA CON SONDEOS CORTOS
-- -----------------------------------------
-- La primera version esperaba a la detonacion con un unico `while` de hasta
-- 60 s por bomba. El servidor de MCP tiene timeout y la llamada moria antes
-- de devolver el informe, asi que el resultado se perdia. Aqui cada espera
-- es un bucle con tope CORTO que devuelve un estado parcial en vez de
-- colgarse: perder una linea de evidencia es mejor que perderla toda.
local Players = game:GetService("Players")
local Bomb = require(game.ServerScriptService.Services.BombService)
local Explosion = require(game.ServerScriptService.Services.ExplosionService)
local Destruction = require(game.ServerScriptService.Services.DestructionService)
local Round = require(game.ServerScriptService.Services.RoundService)

local out = {}

if not Round.IsPlaying() then
	return "no_jugando: " .. tostring(Round.GetState())
end

local p = Players:GetPlayers()[1]
if not p or not p.Character then return "sin jugador" end

local root = p.Character:FindFirstChild("HumanoidRootPart")
local target = nil
local best = math.huge

for b in pairs(Destruction._blocks) do
	if b:IsA("BasePart") and Destruction.IsDestructibleBlock(b) then
		local d = root and (b.Position - root.Position).Magnitude or math.huge
		if d < best then
			best = d
			target = b
		end
	end
end

if not target then return "sin bloques" end

local pos = target.Position + Vector3.new(0, 2, 0)
table.insert(out, string.format("objetivo=%s vida=%d a %.1f studs", target.Name, Destruction.GetBlockHealth(target), best))

local folder = workspace:FindFirstChild("ExplosionVfx")

local function countVfx()
	local n = 0
	if folder then
		for _ in pairs(folder:GetChildren()) do
			n += 1
		end
	end
	return n
end

--- Bucle de espera CORTO con presupuesto en segundos.
local function waitForDetonation(previous, seconds)
	local waited = 0

	while waited < seconds do
		if Explosion.GetExplosionCount() > previous then
			return waited
		end
		task.wait(0.1)
		waited += 0.1
	end

	return -1
end

-- Presupuesto por bomba: la mecha son 3 s (`DefaultBombFuseTime`), asi que
-- 12 s de margen sobran. Si no detonara, la sonda lo DICE con -1 en vez de
-- quedarse esperando.
local FUSE_BUDGET = 12

local explot0 = Explosion.GetExplosionCount()
local destruidos0 = Destruction.GetDestroyedBlockCount()
local vfx0 = countVfx()

local ok1, r1 = Bomb.TryPlaceBomb(p, pos)
table.insert(out, string.format("bomba 1: puesta=%s motivo=%s", tostring(ok1), tostring(r1)))

-- PARTES DE LA BOMBA: se mira la instancia recien creada, no una captura de
-- pantalla. Lo que se comprueba es que el objeto en el mundo tiene cuerpo,
-- tapon y mecha, y no un cubo con una etiqueta.
local bombsFolder = Bomb._bombFolder
local placed = nil

if bombsFolder then
	local chosenId, chosen = -1, nil

	for _, model in ipairs(bombsFolder:GetChildren()) do
		if model:IsA("Model") then
			local bombId = model:GetAttribute("BombId") or 0

			if bombId >= chosenId then
				chosenId, chosen = bombId, model
			end
		end
	end

	placed = chosen
end

if placed then
	local names = {}

	for _, child in ipairs(placed:GetChildren()) do
		table.insert(names, child.Name)
	end

	table.sort(names)
	table.insert(out, ("bomba 1 id=%s mundo=%s dueno=%s partes=[%s] mecha restante=%.2f s"):format(
		tostring(placed:GetAttribute("BombId")),
		tostring(placed:GetAttribute("World")),
		tostring(placed:GetAttribute("OwnerUserId")),
		table.concat(names, " "),
		placed:GetAttribute("FuseRemaining") or -1))
else
	table.insert(out, "bomba 1: no se encontro la instancia para inspeccionar")
end

local dt1 = waitForDetonation(explot0, FUSE_BUDGET)
table.insert(out, string.format("bomba 1 detona en ~%.1f s | vida=%d | destruidos %d -> %d",
	dt1, Destruction.GetBlockHealth(target), destruidos0, Destruction.GetDestroyedBlockCount()))
table.insert(out, string.format("VFX justo despues de detonar: %d -> %d", vfx0, countVfx()))

-- La bomba 2 espera a que pase el enfriamiento (1.5 s) sin bloquear la sonda:
-- se pide igual y, si el servicio la rechaza por cooldown, se dice cual fue el
-- motivo en vez de dar por buena una segunda bomba inexistente.
local explot1 = Explosion.GetExplosionCount()
local ok2, r2 = Bomb.TryPlaceBomb(p, pos)

if not ok2 and tostring(r2):lower():find("cooldown") then
	table.insert(out, "bomba 2: rechazada por enfriamiento, se reintenta en 1.8 s")
	task.wait(1.8)
	ok2, r2 = Bomb.TryPlaceBomb(p, pos)
end

table.insert(out, string.format("bomba 2: puesta=%s motivo=%s", tostring(ok2), tostring(r2)))

local dt2 = waitForDetonation(explot1, FUSE_BUDGET)
task.wait(0.5)

table.insert(out, string.format("bomba 2 detona en ~%.1f s", dt2))
table.insert(out, string.format("RESULTADO: vida=%d IsDestroyed=%s destruidos %d -> %d VFX=%d",
	Destruction.GetBlockHealth(target),
	tostring(target:GetAttribute("IsDestroyed")),
	destruidos0,
	Destruction.GetDestroyedBlockCount(),
	countVfx()))

-- RESPAWN: se lee el REGISTRO de `BlockRespawnRules`, que es donde vive el
-- reloj (`ReadyAt` esta en la tabla, no en un atributo del bloque). No se
-- espera a que el bloque vuelva: el respawn puede tardar hasta 25 s y volver
-- a tumbar el timeout de MCP. Lo que importa para la certificacion es que la
-- cola este PROGRAMADA, con espera sorteada dentro del rango y generacion
-- tokenizada, no que el reloj llegue a cero dentro de esta llamada.
local record = Destruction._records[target]

if record then
	table.insert(out, ("respawn: estado=%s espera=%.1f s (rango %.0f-%.0f) generacion=%d restante=%.1f s"):format(
		tostring(record.State),
		record.Delay,
		8,
		25,
		record.Generation,
		math.max(record.ReadyAt - os.clock(), 0)))
else
	table.insert(out, "respawn: SIN REGISTRO; el bloque no quedo en cola de reaparicion")
end

return table.concat(out, "\n")