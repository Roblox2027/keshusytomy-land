-- recovery-world.lua (SERVIDOR)
-- Fase de RECUPERACION, parte 2: CONTENIDO DEL MUNDO y BOMBA.
--
-- Se mide con el jugador YA dentro del mundo (parte 1 lo puso) y con la ronda
-- en `Playing`. No parchea nada.

local Players = game:GetService("Players")
local Bomb = require(game.ServerScriptService.Services.BombService)
local Destruction = require(game.ServerScriptService.Services.DestructionService)
local Round = require(game.ServerScriptService.Services.RoundService)
local Config = require(game.ReplicatedStorage.Shared.Config.GameConfig)

local out = {}
local function say(fmt, ...)
	table.insert(out, string.format(fmt, ...))
end

local player = Players:GetPlayers()[1]
if not player or not player.Character then
	return "sin jugador"
end

local root = player.Character:FindFirstChild("HumanoidRootPart")

say("=== ESTADO ===")
say("Mundo = %s | ronda = %s | IsPlaying = %s",
	tostring(player:GetAttribute("World")), tostring(Round.GetState()), tostring(Round.IsPlaying()))
if root then
	say("Posicion = (%.0f, %.0f, %.0f)", root.Position.X, root.Position.Y, root.Position.Z)
end

-- ----------------------------------------------------- CONTENIDO DEL MUNDO
say("")
say("=== TEST 4: CONTENIDO DEL MUNDO ===")
for _, worldId in ipairs({ "Forest", "Desert", "Ice", "Volcano", "Cyber" }) do
	local folder = workspace.Worlds and workspace.Worlds:FindFirstChild(worldId)
	if not folder then
		say("%-8s -> NO existe", worldId)
		continue
	end
	local parts, rims, solids = 0, 0, 0
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") then
			parts += 1
			if d.Name:match("_Rim_") then
				rims += 1
				if d.CanCollide then
					solids += 1
				end
			end
		end
	end
	say("%-8s parts=%d rims=%d rims_solidos=%d", worldId, parts, rims, solids)
end

local monsters = 0
local mf = workspace:FindFirstChild("Monsters")
if mf then
	for _ in pairs(mf:GetChildren()) do
		monsters += 1
	end
end
say("Monstruos spawneados = %d", monsters)

local closest, mejor = nil, math.huge
local total = 0
for b in pairs(Destruction._blocks) do
	if b:IsA("BasePart") then
		total += 1
		if root then
			local d = (b.Position - root.Position).Magnitude
			if d < mejor then
				mejor, closest = d, b
			end
		end
	end
end
say("Bloques destructibles = %d | mas cercano = %s a %.1f studs",
	total, tostring(closest and closest.Name), mejor)

-- ------------------------------------------------------------------ BOMBA
say("")
say("=== TEST 5: BOMBA ===")
if not Round.IsPlaying() then
	say("No se mide: la ronda no esta en Playing (%s)", tostring(Round.GetState()))
	return table.concat(out, "\n")
end
if not root then
	return table.concat(out, "\n")
end

say("BombCooldown = %s | BombCapacity = %s | BombPlacementRange = %s",
	tostring(Config.BombCooldown), tostring(Config.BombCapacity), tostring(Config.BombPlacementRange))

local antes = Bomb.GetActiveBombCount()
local okA, motivoA = Bomb.TryPlaceBomb(player, root.Position + Vector3.new(6, 0, 0))
say("BOMBA A: ok=%s motivo=%s | activas %d -> %d",
	tostring(okA), tostring(motivoA), antes, Bomb.GetActiveBombCount())
say("BombRejection = %s", tostring(player:GetAttribute("BombRejection")))

-- Anatomia de la bomba: cuerpo, mecha, temporizador.
local folder = Bomb._bombFolder
local elegido, mejorId = nil, -1
if folder then
	for _, m in ipairs(folder:GetChildren()) do
		if m:IsA("Model") then
			local id = m:GetAttribute("BombId") or 0
			if id >= mejorId then
				mejorId, elegido = id, m
			end
		end
	end
end
if elegido then
	local piezas = {}
	for _, c in ipairs(elegido:GetChildren()) do
		table.insert(piezas, c.Name)
	end
	table.sort(piezas)
	say("Bomba id=%s mundo=%s dueno=%s",
		tostring(elegido:GetAttribute("BombId")),
		tostring(elegido:GetAttribute("World")),
		tostring(elegido:GetAttribute("OwnerUserId")))
	say("Partes = %s", table.concat(piezas, ", "))
	say("FuseRemaining = %s | FuseTime = %s",
		tostring(elegido:GetAttribute("FuseRemaining")), tostring(elegido:GetAttribute("FuseTime")))
else
	say("No hay modelo de bomba para inspeccionar.")
end

-- BOMBA B: distingue COOLDOWN de CAPACIDAD. Se espera a que el cooldown pase.
local esperado = 0
for _ = 1, 40 do
	if Bomb.GetActiveBombCount() > 0 then
		break
	end
	task.wait(0.25)
	esperado += 0.25
end
local antesB = Bomb.GetActiveBombCount()
local okB, motivoB = Bomb.TryPlaceBomb(player, root.Position + Vector3.new(-6, 0, 0))
say("BOMBA B (tras %.1f s): ok=%s motivo=%s | activas %d -> %d",
	esperado, tostring(okB), tostring(motivoB), antesB, Bomb.GetActiveBombCount())

return table.concat(out, "\n")