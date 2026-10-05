-- b4-bomb.lua (SERVIDOR)
-- BLOQUE 4A/4B: UNA bomba. Colocarla y leer su anatomia. SIN ESPERAS.
--
-- Se mide a 5 studs, dentro de `BombPlacementRange` (18). En una medicion
-- anterior el bloque mas cercano estaba a 51 studs y el rechazo fue correcto:
-- el problema era la distancia de prueba, no el sistema.
local Players = game:GetService("Players")
local Bomb = require(game.ServerScriptService.Services.BombService)
local Round = require(game.ServerScriptService.Services.RoundService)
local Config = require(game.ReplicatedStorage.Shared.Config.GameConfig)

local out = {}
local function say(f, ...) table.insert(out, string.format(f, ...)) end

local p = Players:GetPlayers()[1]
if not p or not p.Character then return "sin jugador" end

local root = p.Character:FindFirstChild("HumanoidRootPart")
if not root then return "sin root" end

say("ronda = %s | World = %s", tostring(Round.GetState()), tostring(p:GetAttribute("World")))
say("pos = (%.0f, %.0f, %.0f)", root.Position.X, root.Position.Y, root.Position.Z)
say("BombCooldown = %s | BombCapacity = %s | Range = %s",
	tostring(Config.BombCooldown), tostring(Config.BombCapacity), tostring(Config.BombPlacementRange))

if not Round.IsPlaying() then
	say("AVISO: no se coloca bomba; la ronda esta en %s", tostring(Round.GetState()))
	return table.concat(out, "\n")
end

local antes = Bomb.GetActiveBombCount()
local ok, motivo = Bomb.TryPlaceBomb(p, root.Position + Vector3.new(5, 0, 0))
say("")
say("BOMBA A: ok=%s motivo=%s | activas %d -> %d",
	tostring(ok), tostring(motivo), antes, Bomb.GetActiveBombCount())
say("BombRejection = %s", tostring(p:GetAttribute("BombRejection")))

local folder = Bomb._bombFolder
say("Workspace.Bombs existe = %s", tostring(folder ~= nil))

local elegido, mejorId = nil, -1
if folder then
	for _, m in ipairs(folder:GetChildren()) do
		if m:IsA("Model") then
			local id = m:GetAttribute("BombId") or 0
			if id > mejorId then
				mejorId, elegido = id, m
			end
		end
	end
end

if not elegido then
	say("NO HAY BOMBA EN EL MUNDO")
	return table.concat(out, "\n")
end

say("")
say("=== ANATOMIA DE LA BOMBA ===")
say("instancia = %s (%s)", elegido:GetFullName(), elegido.ClassName)
say("BombId = %s | World = %s | Owner = %s",
	tostring(elegido:GetAttribute("BombId")),
	tostring(elegido:GetAttribute("World")),
	tostring(elegido:GetAttribute("OwnerUserId")))
say("FuseTime = %s | FuseRemaining = %s",
	tostring(elegido:GetAttribute("FuseTime")),
	tostring(elegido:GetAttribute("FuseRemaining")))

local piezas = {}
for _, c in ipairs(elegido:GetChildren()) do
	piezas[#piezas + 1] = c.Name .. "(" .. c.ClassName .. ")"
end
table.sort(piezas)
say("partes = %s", table.concat(piezas, ", "))

-- CUERPO, MECHA y EFECTO VISUAL se comprueban por atributo de la propia
-- instancia, no por captura de pantalla: lo que importa es que el objeto en
-- el mundo LLEVE esos componentes.
say("cuerpo = %s", tostring(elegido:GetAttribute("Body") ~= nil or
	elegido:FindFirstChild("Body") ~= nil))
say("mecha = %s", tostring(elegido:FindFirstChild("Fuse") ~= nil))
say("etiqueta = %s", tostring(elegido:FindFirstChild("Label") ~= nil))

return table.concat(out, "\n")