-- p0-diag.lua
-- DIAGNOSTICO P0 de la cadena completa de la bomba.
--
-- Pregunta UNA cosa por etapa y NO da por buena ninguna:
--
--   INPUT -> REQUEST -> SERVER -> ACCEPT -> CREATE -> Workspace.Bombs
--   -> 3D MODEL -> FUSE -> WARNING -> EXPLOSION -> DESTRUCTION -> RESPAWN
--
-- No adivina. Cada etapa se mide y se imprime con su veredicto. Si la bomba
-- no aparece, el informe dice en que etapa se corto.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local out = {}

local function say(fmt, ...)
	table.insert(out, string.format(fmt, ...))
end

local function countChildren(folder)
	local n = 0
	if folder then
		for _ in pairs(folder:GetChildren()) do
			n += 1
		end
	end
	return n
end

-- ETAPA 0: SERVIDOR
local Bomb = require(game.ServerScriptService.Services.BombService)
local Round = require(game.ServerScriptService.Services.RoundService)

say("=== ETAPA 0: SERVIDOR ===")
say("BombService inicializado = %s", tostring(Bomb.IsInitialized))
say("ExplosionService inyectada = %s", tostring(Bomb._explosionService ~= nil))
say("RoundService inyectado = %s", tostring(Bomb._roundService ~= nil))

if Round then
	say("Ronda: estado=%s IsPlaying=%s IsRoundActive=%s",
		tostring(Round.GetState()),
		tostring(Round.IsPlaying()),
		tostring(Round.IsRoundActive()))
end

local bombsFolder = Bomb._bombFolder
say("Carpeta de bombas = %s (padre=%s) hijas=%d",
	tostring(bombsFolder and bombsFolder:GetFullName()),
	tostring(bombsFolder and bombsFolder.Parent and bombsFolder.Parent:GetFullName()),
	countChildren(bombsFolder))
say("Workspace.Bombs existe = %s", tostring(Workspace:FindFirstChild("Bombs") ~= nil))

local nArenas = 0
for _ in pairs(Bomb._arenaBoundsByWorld) do
	nArenas += 1
end
say("Arenas con limite: %d", nArenas)

for world, b in pairs(Bomb._arenaBoundsByWorld) do
	say("  arena %s: X[%.0f, %.0f] Z[%.0f, %.0f]", world, b.MinX, b.MaxX, b.MinZ, b.MaxZ)
end

-- ETAPA 1-3: JUGADOR, INPUT, REQUEST
say("")
say("=== ETAPA 1-3: JUGADOR, INPUT, REQUEST ===")

local player = Players:GetPlayers()[1]

if not player then
	say("SIN JUGADOR en la sesion. No se puede seguir.")
	return table.concat(out, "\n")
end

say("Jugador = %s mundo=%s", player.Name, tostring(player:GetAttribute("World")))

local character = player.Character
local root = character and character:FindFirstChild("HumanoidRootPart")
local humanoid = character and character:FindFirstChildOfClass("Humanoid")

say("Personaje = %s", tostring(character and character:GetFullName()))
say("HumanoidRootPart = %s", tostring(root ~= nil))
say("Vivo = %s", tostring(humanoid ~= nil and humanoid.Health > 0))

if not root then
	say("SIN HUMANOIDROOTPART: no se puede colocar nada.")
	return table.concat(out, "\n")
end

say("Posicion del jugador = (%.1f, %.1f, %.1f)", root.Position.X, root.Position.Y, root.Position.Z)

local limits = require(game.ReplicatedStorage.Shared.Config.PerformanceConfig).Limits
say("Limite de bombas por jugador = %d", limits.MaxBombsPerPlayer)
say("Limite de bombas por mundo = %d", limits.MaxBombsPerWorld)

local cfg = require(game.ReplicatedStorage.Shared.Config.GameConfig)
say("BombCooldown = %.1f s | mecha = %.1f s | rango = %d studs",
	cfg.BombCooldown, cfg.DefaultBombFuseTime, cfg.BombPlacementRange)

-- ETAPA 4-6: REQUEST -> SERVER -> CREATE
say("")
say("=== ETAPA 4-6: REQUEST -> SERVER -> CREATE ===")

local antes = countChildren(bombsFolder)
say("Workspace.Bombs ANTES = %d", antes)

-- Posicion delante del jugador: es donde un jugador colocaria una bomba
-- con la intencion de que se vea.
local look = root.CFrame.LookVector
local pediu = root.Position + Vector3.new(look.X, 0, look.Z).Unit * 8

local ok, motivo = Bomb.TryPlaceBomb(player, pediu)
say("TryPlaceBomb -> aceptada=%s motivo=%s", tostring(ok), tostring(motivo))
say("BombRejection = %s", tostring(player:GetAttribute("BombRejection")))

local despues = countChildren(bombsFolder)
say("Workspace.Bombs DESPUES = %d", despues)

if despues <= antes then
	say("VEREDICTO: la bomba NO se creo. Se corta en ETAPA 5 (CREATE).")
	say("           Motivo publicado: %s", tostring(player:GetAttribute("BombRejection")))
	return table.concat(out, "\n")
end

-- ETAPA 7: LA BOMBA ES REAL Y SE VE
say("")
say("=== ETAPA 7: LA BOMBA ES REAL Y SE VE ===")

local creada = nil
for _, model in ipairs(bombsFolder:GetChildren()) do
	if model:IsA("Model") then
		creada = model
	end
end

if not creada then
	say("VEREDICTO: hay hijas pero ninguna es un Model.")
	return table.concat(out, "\n")
end

say("Modelo = %s id=%s dueno=%s mundo=%s",
	creada.Name,
	tostring(creada:GetAttribute("BombId")),
	tostring(creada:GetAttribute("OwnerUserId")),
	tostring(creada:GetAttribute("World")))
say("Padre = %s", tostring(creada.Parent and creada.Parent:GetFullName()))
say("Visible en el mundo = %s", tostring(creada:IsDescendantOf(Workspace)))

local primary = creada.PrimaryPart
say("PrimaryPart = %s", tostring(primary and primary.Name))

if primary then
	say("Distancia bomba-jugador = %.1f studs",
		(primary.Position - root.Position).Magnitude)
end

-- Cada parte visible: si el jugador no la ve, ESTO lo dice.
say("")
say("PARTES VISIBLES:")

local anyVisible = false

for _, part in ipairs(creada:GetDescendants()) do
	if part:IsA("BasePart") then
		if part.Transparency < 1 then
			anyVisible = true
		end
		say("  %-16s pos=(%.0f,%.0f,%.0f) tam=(%.2f,%.2f,%.2f) transp=%.2f mat=%s color=(%d,%d,%d)%s",
			part.Name,
			part.Position.X, part.Position.Y, part.Position.Z,
			part.Size.X, part.Size.Y, part.Size.Z,
			part.Transparency,
			tostring(part.Material),
			math.round(part.Color.R * 255),
			math.round(part.Color.G * 255),
			math.round(part.Color.B * 255),
			part == primary and "  <- Primary" or "")
	end
end

say("")
say("Hay alguna parte NO transparente = %s", tostring(anyVisible))

-- ETAPA 8-9: MECHA Y AVISO
say("")
say("=== ETAPA 8-9: MECHA Y AVISO ===")

local antesFuse = creada:GetAttribute("FuseRemaining")

for _ = 1, 12 do
	task.wait(0.25)
	if not creada.Parent then
		break
	end
end

local despuesFuse = creada:GetAttribute("FuseRemaining")
say("FuseRemaining: antes=%s despues=%s (debe BAJAR solo)",
	tostring(antesFuse), tostring(despuesFuse))

if antesFuse and despuesFuse and despuesFuse < antesFuse then
	say("VEREDICTO: la mecha corre sola. ETAPA 8 = PASS")
else
	say("VEREDICTO: la mecha NO avanza. ETAPA 8 = FAIL")
end

say("La bomba sigue en el mundo = %s", tostring(creada.Parent ~= nil))

return table.concat(out, "\n")

