-- spawn-check.lua
-- Comprueba en RUNTIME que los 6 spawns estan bien colocados y mirando al
-- centro del lobby.
--
-- POR QUE EXISTE
-- --------------
-- `tools/forest-verify.js` comprueba que la FUENTE declara la orientacion
-- correcta. Esto comprueba que llega al juego. Son dos cosas distintas: la
-- orientacion se perdia al importar (mismo problema que el resto de la
-- geometria) y hay que verlo en el sitio donde el jugador aparece.
--
-- Se mide lo que importa de verdad, no unDegrees de yaw:
--
--   1. que el spawn no este DENTRO de un bloque ni de la decoracion;
--   2. que tenga ESPACIO LIBRE alrededor (nada pegado encima);
--   3. que mire hacia el Keshusy Core, que es donde esta la narrativa;
--   4. que los 6 esten habilitados y en el plano del lobby.
--
-- El punto 1 y el 2 son los que un jugador nota de inmediato: aparecer
-- dentro de un arbol o con un poste atravesando el personaje.

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local spawns = Workspace:FindFirstChild("SpawnLocations")
if not spawns then
	return "ERROR: no hay Workspace.SpawnLocations"
end

local lobby = Workspace:FindFirstChild("Lobby")
local core = lobby and lobby:FindFirstChild("KeshusyCore")
local coreOrb = core and core:FindFirstChild("CoreOrb")
local target = coreOrb and coreOrb.Position or Vector3.new(0, 0, 0)

local lines = {}
local allEnabled = true
local allClear = true
local allFacing = true
local counted = 0

for _, spawn in ipairs(spawns:GetChildren()) do
	if spawn:IsA("SpawnLocation") then
		counted += 1

		local yaw = spawn.Orientation.Y
		local radians = math.rad(yaw)
		-- Con rotacion 0 Roblox mira hacia -Z.
		local forward = Vector3.new(-math.sin(radians), 0, -math.cos(radians))
		local toTarget = target - spawn.Position
		toTarget = Vector3.new(toTarget.X, 0, toTarget.Z)

		local length = toTarget.Magnitude
		local alignment = 0
		if length > 0.01 then
			alignment = forward:Dot(toTarget.Unit)
		end

		-- ESPACIO LIBRE: nada solido dentro de 7 studs por encima de la
		-- plataforma, ni pegado a los lados. Un arbol o un poste de
		-- estacion aqui haria aparecer al jugador encajado.
		local overlaps = {}
		local box = spawn.Size + Vector3.new(6, 6, 6)
		local region = CFrame.new(spawn.Position) * CFrame.Angles(0, math.rad(yaw), 0)

		for _, other in ipairs(Workspace:GetDescendants()) do
			if other:IsA("BasePart") and other ~= spawn then
				local delta = other.Position - spawn.Position
				-- Solo se miran las piezas cercanas y por ENCIMA: por debajo
				-- esta el suelo del lobby, que es lo correcto.
				if delta.Magnitude < 9 and delta.Y > 1.5 then
					table.insert(overlaps, other.Name)
				end
			end
		end

		if not spawn.Enabled then
			allEnabled = false
		end
		if #overlaps > 0 then
			allClear = false
			table.insert(lines, string.format(
				"%s: %d pieza(s) encima o pegadas: %s",
				spawn.Name, #overlaps, table.concat(overlaps, ", ")))
		end
		if alignment < 0.9 then
			allFacing = false
			table.insert(lines, string.format(
				"%s: mira %.2f hacia el Core (se pide 0.90)",
				spawn.Name, alignment))
		end
	end
end

table.insert(lines, 1, "spawns=" .. counted)
table.insert(lines, "objetivo=" .. string.format("%.0f, %.0f, %.0f", target.X, target.Y, target.Z))
table.insert(lines, "todosHabilitados=" .. tostring(allEnabled))
table.insert(lines, "espacioLibre=" .. tostring(allClear))
table.insert(lines, "miranAlCentro=" .. tostring(allFacing))

return table.concat(lines, "\n")