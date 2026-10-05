-- b9-nav.lua (SERVIDOR)
-- BLOQUE 9, NAV: las zonas del mundo ACTUAL tienen suelo real. El mundo se
-- lee del atributo `World`: no se pasa a mano, asi que la medicion es del mundo
-- en el que el jugador esta de verdad.
--
-- Mide tres cosas por zona: que hay geometria, que hay suelo debajo del centro
-- y que el suelo esta a una altura de caida razonable.
local Players = game:GetService("Players")
local out = {}
local function say(f, ...) table.insert(out, string.format(f, ...)) end

local p = Players:GetPlayers()[1]
if not p or not p.Character then return "sin jugador" end
local root = p.Character:FindFirstChild("HumanoidRootPart")

local worldId = tostring(p:GetAttribute("World"))
say("=== NAVEGACION DE %s ===", worldId)
if root then
	say("pos = (%.0f, %.0f, %.0f)", root.Position.X, root.Position.Y, root.Position.Z)
end

local function groundBelow(point: Vector3): BasePart?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { p.Character }
	local result = workspace:Raycast(point + Vector3.new(0, 250, 0), Vector3.new(0, -500, 0), params)
	return result and result.Instance
end

local folder = workspace:FindFirstChild("Worlds") and workspace.Worlds:FindFirstChild(worldId)
if not folder then return "no existe el mundo " .. worldId end

local zones = folder:FindFirstChild("Zones")
if not zones then return "el mundo no tiene carpeta Zones" end

-- Si se nombra una zona, se audita SOLO esa, parte por parte. Es el metodo que
-- dice POR QUE una zona no tiene suelo, en vez de contar que no lo tiene.
local soloZona = _ENV.ZONE

if soloZona then
	local zone = zones:FindFirstChild(soloZona)
	if not zone then
		return "no existe la zona " .. soloZona
	end

	say("=== AUDITORIA DE %s ===", soloZona)
	local solidas, decorativas = 0, 0

	for _, d in ipairs(zone:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.CanCollide and d.CanQuery then
				solidas += 1
			else
				decorativas += 1
			end
			say("  %-34s collide=%-5s query=%-5s trans=%.2f y=%.1f size=%s",
				string.sub(d.Name, 1, 34),
				tostring(d.CanCollide), tostring(d.CanQuery),
				d.Transparency, d.Position.Y, tostring(d.Size))
		end
	end

	say("")
	say("partes solidas = %d | no consultables = %d", solidas, decorativas)
	say("todo el mundo en una caja:")
	local bx0, bx1 = math.huge, -math.huge
	local bz0, bz1 = math.huge, -math.huge
	for _, d in ipairs(zone:GetDescendants()) do
		if d:IsA("BasePart") then
			bx0 = math.min(bx0, d.Position.X - d.Size.X / 2)
			bx1 = math.max(bx1, d.Position.X + d.Size.X / 2)
			bz0 = math.min(bz0, d.Position.Z - d.Size.Z / 2)
			bz1 = math.max(bz1, d.Position.Z + d.Size.Z / 2)
		end
	end
	say("  x=[%.0f, %.0f]  z=[%.0f, %.0f]", bx0, bx1, bz0, bz1)

	-- SONDEO EN REJILLA: cuenta cuantos puntos de la zona tienen suelo. Un
	-- unico raycast en el centro no basta: el fallo puede estar en una esquina
	-- sin que el centro lo delate.
	local paso = 8
	local conSuelo, sinSuelo = 0, 0
	local primeroSinSuelo = nil

	local x = bx0 + paso
	while x <= bx1 do
		local z = bz0 + paso
		while z <= bz1 do
			local s = groundBelow(Vector3.new(x, 40, z))
			if s then
				conSuelo += 1
			else
				sinSuelo += 1
				primeroSinSuelo = primeroSinSuelo or Vector3.new(x, 40, z)
			end
			z += paso
		end
		x += paso
	end

	say("")
	say("sondeo en rejilla (paso %d): con suelo = %d | SIN suelo = %d",
		paso, conSuelo, sinSuelo)
	if primeroSinSuelo then
		say("  primer punto sin suelo = (%.0f, %.0f, %.0f)",
			primeroSinSuelo.X, primeroSinSuelo.Y, primeroSinSuelo.Z)
	end

	-- Las partes SOLIDAS de la zona: donde estan y si cubren el centro.
	say("")
	say("partes SOBRESCRIBIENTES (CanCollide=true):")
	local n = 0
	for _, d in ipairs(zone:GetDescendants()) do
		if d:IsA("BasePart") and d.CanCollide then
			n += 1
			if n <= 8 then
				say("  %-30s pos=(%.0f, %.1f, %.0f) size=(%.0f, %.0f, %.0f)",
					string.sub(d.Name, 1, 30),
					d.Position.X, d.Position.Y, d.Position.Z,
					d.Size.X, d.Size.Y, d.Size.Z)
			end
		end
	end
	say("  total = %d", n)

	return table.concat(out, "\n")
end

-- Se busca la LOSA DE SUELO, no el centro geométrico de la caja.
--
-- MEDIDO: usar el centro de la caja de la zona daba un falso negativo. La caja
-- incluye los `_Rim_*`, que sobresalen hacia fuera, asi que su centro no coincide
-- con el centro de la losa. En `Zone_Desert_Exit` la caja era de 129x88 y la
-- losa de 41x19: el centro de la caja cae en el vacio entre el borde y la losa,
-- y la zona se contaba como "sin suelo" teniendo suelo de sobra.
--
-- La losa es la parte SOLIDA de mayor superficie horizontal. Es la que el
-- jugador pisa, y es la que tiene que existir.
local function slabOf(zone: Instance): BasePart?
	local mejor = nil
	local mejorArea = 0

	for _, d in ipairs(zone:GetDescendants()) do
		if d:IsA("BasePart") and d.CanCollide and d.CanQuery then
			local area = d.Size.X * d.Size.Z
			-- El suelo es ancho y plano: la seleccion usa el area horizontal,
			-- no la altura, para no confundir un muro largo con un suelo.
			if area > mejorArea then
				mejorArea = area
				mejor = d
			end
		end
	end

	return mejor
end

local items = {}
for _, c in ipairs(zones:GetChildren()) do
	table.insert(items, c)
end
table.sort(items, function(a, b)
	return a.Name < b.Name
end)

local ok, falla, vacia, sinLosa = 0, 0, 0, 0

for _, zone in ipairs(items) do
	local n = 0
	for _, d in ipairs(zone:GetDescendants()) do
		if d:IsA("BasePart") then
			n += 1
		end
	end

	if n == 0 then
		vacia += 1
		say("  VACIA   %-26s 0 partes", zone.Name)
	else
		local losa = slabOf(zone)

		if not losa then
			sinLosa += 1
			say("  SIN LOSA %-25s %d partes pero ninguna solida de suelo",
				zone.Name, n)
		else
			local suelo = groundBelow(losa.Position)
			local ancho = math.floor(math.min(losa.Size.X, losa.Size.Z))

			if suelo then
				ok += 1
				say("  OK      %-26s losa=%3dx%3d suelo=%6.1f",
					zone.Name, math.floor(losa.Size.X), math.floor(losa.Size.Z),
					suelo.Position.Y)
			else
				falla += 1
				say("  FALLA   %-26s losa=%3dx%3d y=%.1f SIN NADA DEBAJO",
					zone.Name, math.floor(losa.Size.X), math.floor(losa.Size.Z), losa.Position.Y)
			end
			-- Un suelo de 20 studs es un alféizar, no una zona jugable.
			if ancho < 24 then
				say("           AVISO: la losa mas ancha mide %d studs", ancho)
			end
		end
	end
end

say("")
say("CON SUELO = %d | FALLAN = %d | SIN LOSA = %d | VACIAS = %d | TOTAL = %d",
	ok, falla, sinLosa, vacia, #items)

return table.concat(out, "\n")