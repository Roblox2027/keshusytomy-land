-- b5-rims.lua (SERVIDOR)
-- BLOQUE 5: estado REAL de los muros en la sesion de Play. SIN ESPERAS.
--
-- No decide nada: cuenta. La decision de que muros sobran se toma en el
-- generador (`tools/worlds.js`), no parcheando el mundo en caliente.
local out = {}
local function say(f, ...) table.insert(out, string.format(f, ...)) end

local worlds = workspace:FindFirstChild("Worlds")
if not worlds then return "no hay Worlds" end

say("mundo    partes   rims  rims_solidos  por_lado(N,S,E,O)")
for _, folder in ipairs(worlds:GetChildren()) do
	local parts, rims, solids = 0, 0, 0
	local lados = { N = 0, S = 0, E = 0, O = 0 }

	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") then
			parts += 1

			if string.find(d.Name, "_Rim_", 1, true) and not string.find(d.Name, "RimCap", 1, true) then
				rims += 1
				if d.CanCollide then
					solids += 1
					-- El lado se decide por donde mira el muro, no por su
					-- posicion: un muro al NORTE mira al vacio norte.
					local look = d.CFrame.LookVector
					if math.abs(look.Z) >= math.abs(look.X) then
						if look.Z > 0 then
							lados.N += 1
						else
							lados.S += 1
						end
					elseif look.X > 0 then
						lados.E += 1
					else
						lados.O += 1
					end
				end
			end
		end
	end

	say("%-8s %6d %7d %12d   %d,%d,%d,%d",
		folder.Name, parts, rims, solids, lados.N, lados.S, lados.E, lados.O)
end

return table.concat(out, "\n")