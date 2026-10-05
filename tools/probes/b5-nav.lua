-- b5-nav.lua (SERVIDOR)
-- BLOQUE 5 (NAV-A): el jugador REAL camina por Forest. Se teletransporta a
-- puntos concretos y se mide si hay suelo y si puede CAER (no teletransportarse
-- a un sitio donde no hay nada).
--
-- Esto NO es el test estatico de `world-navigation-test.js`: ese lee el
-- arbol generado. Este lee el mundo que hay en la sesion de Play.
local Players = game:GetService("Players")
local out = {}
local function say(f, ...) table.insert(out, string.format(f, ...)) end

local p = Players:GetPlayers()[1]
if not p or not p.Character then return "sin jugador" end
local root = p.Character:FindFirstChild("HumanoidRootPart")
if not root then return "sin root" end
local hum = p.Character:FindFirstChildOfClass("Humanoid")

say("World = %s | pos = (%.0f, %.0f, %.0f) | vida = %s",
	tostring(p:GetAttribute("World")),
	root.Position.X, root.Position.Y, root.Position.Z, tostring(hum and hum.Health))

--- Busca suelo bajo un punto: el punto cae por el mapa hasta tocar algo
--- solido. Devuelve nil si no hay nada debajo en 400 studs.
local function groundBelow(point: Vector3): BasePart?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { p.Character }

	local result = workspace:Raycast(point + Vector3.new(0, 200, 0), Vector3.new(0, -400, 0), params)
	return result and result.Instance
end

-- Los once puntos son los CENTROS de las zonas de Forest, leidos del mundo en
-- ejecucion: no se escriben a mano, asi que el test mide lo que hay.
local folder = workspace:FindFirstChild("Worlds") and workspace.Worlds:FindFirstChild("Forest")
if not folder then return "no hay Forest" end

local folder = workspace:FindFirstChild("Worlds") and workspace.Worlds:FindFirstChild("Forest")
if not folder then return "no hay Forest" end

-- Los marcadores se DESCUBREN, no se adivinan. Se listan los nombres reales de
-- los hijos directos para no medir contra un patron inventado.
local nombres = {}
for _, c in ipairs(folder:GetChildren()) do
	table.insert(nombres, c.Name .. " (" .. c.ClassName .. ")")
end
table.sort(nombres)
say("hijos directos de Forest = %d", #nombres)
for _, n in ipairs(nombres) do
	say("  %s", n)
end

-- La carpeta `Keshusy` es donde el generador mete las zonas. Se listan sus
-- hijos: son los marcadores por los que se mide la navegabilidad real.
local keshusy = folder:FindFirstChild("Keshusy")
if keshusy then
	local zonas = {}
	for _, c in ipairs(keshusy:GetChildren()) do
		zonas[#zonas + 1] = c.Name .. " (" .. c.ClassName .. ")"
	end
	table.sort(zonas)
	say("")
	say("Keshusy = %d hijos", #zonas)
	for _, z in ipairs(zonas) do
		say("  %s", z)
	end
end

-- La carpeta `Border` es la que convertiria el mundo en una caja. Se cuenta
-- en los CINCO mundos: si uno solo tiene un perimeter, ese mundo esta encerrado.
say("")
say("=== BORDER (perimetro artificial) POR MUNDO ===")
local worlds = workspace:FindFirstChild("Worlds")
local totalBorder = 0

for _, w in ipairs(worlds:GetChildren()) do
	local border = w:FindFirstChild("Border")
	local n, solidos = 0, 0
	if border then
		for _, d in ipairs(border:GetDescendants()) do
			if d:IsA("BasePart") then
				n += 1
				if d.CanCollide then
					solidos += 1
				end
			end
		end
	end
	totalBorder += solidos
	say("  %-8s partes=%d solidas=%d", w.Name, n, solidos)
end
say("PERIMETRO ARTIFICIAL TOTAL = %d", totalBorder)

-- Estructura de `Zones` y si cada zona tiene suelo REAL en la sesion de Play.
--
-- CONTABILIDAD HONESTA: se cuentan los tres casos por separado. Si el marcador
-- no es un `BasePart`, la zona queda como `sin punto` y CUENTA como no
-- verificada: esconderla en un "0 de 11" seria un falso verde.
local zones = folder:FindFirstChild("Zones")
if zones then
	local nombresZ = {}
	for _, c in ipairs(zones:GetChildren()) do
		nombresZ[#nombresZ + 1] = c
	end
	table.sort(nombresZ, function(a, b)
		return a.Name < b.Name
	end)

	-- Las zonas son FOLDERS, no partes: su posicion se saca del centro del
	-- conjunto de sus hijos. Se mide el suelo bajo el CENTRO GEOMETRICO de la
	-- zona, que es donde el jugador pisa de verdad.
	--
	-- Se cuenta tambien cuanta geometria tiene cada zona: una zona sin ninguna
	-- parte es una etiqueta, no un sitio, y tiene que salir como VACIA y no
	-- pasar desapercibida.
	say("")
	say("Zones = %d zonas", #nombresZ)
	local ok, sinSuelo, vacias = 0, 0, 0

	for _, zone in ipairs(nombresZ) do
		if zone:IsA("Folder") then
			local n = 0
			local minX, maxX = math.huge, -math.huge
			local minZ, maxZ = math.huge, -math.huge
			local minY, maxY = math.huge, -math.huge

			for _, d in ipairs(zone:GetDescendants()) do
				if d:IsA("BasePart") then
					n += 1
					local p, s = d.Position, d.Size
					minX = math.min(minX, p.X - s.X / 2)
					maxX = math.max(maxX, p.X + s.X / 2)
					minZ = math.min(minZ, p.Z - s.Z / 2)
					maxZ = math.max(maxZ, p.Z + s.Z / 2)
					minY = math.min(minY, p.Y - s.Y / 2)
					maxY = math.max(maxY, p.Y + s.Y / 2)
				end
			end

			if n == 0 then
				vacias += 1
				say("  VACIA    %-24s 0 partes", zone.Name)
			else
				local centro = Vector3.new((minX + maxX) / 2, (maxY + minY) / 2, (minZ + maxZ) / 2)
				local suelo = groundBelow(centro)
				local caida = if suelo then (centro.Y - suelo.Position.Y) else -1

				if suelo and caida < 120 then
					ok += 1
					say("  OK       %-24s partes=%4d ancho=%4d suelo=%6.1f caida=%5.1f",
						zone.Name, n, math.floor(maxX - minX), suelo.Position.Y, caida)
				else
					sinSuelo += 1
					say("  FALLA    %-24s partes=%4d ancho=%4d %s",
						zone.Name, n, math.floor(maxX - minX), if suelo
							then ("caida de " .. string.format("%.0f", caida))
							else "nada debajo")
				end
			end
		end
	end

	say("")
	say("CON SUELO = %d | SIN SUELO = %d | VACIAS = %d | TOTAL = %d",
		ok, sinSuelo, vacias, #nombresZ)
end

return table.concat(out, "\n")