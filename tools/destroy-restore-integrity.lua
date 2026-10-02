-- destroy-restore-integrity.lua
-- Comprueba que DESTRUIR y RESTAURAR un bloque no altera su geometria.
--
-- POR QUE HACE FALTA
-- ------------------
-- La reconstruccion del bosque cambio dimensiones y giro de los bloques.
-- El servicio de destruccion los SECRETA (transparencia 1, sin colision)
-- y los restaura con `RestoreAll`. Ese ciclo es el que puede perder datos:
--
--   - `snapshotBlock` guarda `Transparency`, `CanCollide` y `CanTouch`,
--     pero NO `Size`, `Position` ni `Orientation`. Si al restaurar se
--     tocara la geometria, nadie lo detectaria.
--   - El radio de explosion se calcula por distancia entre CENTROS. Si un
--     bloque cambiara de sitio al restaurarse, las bombas empezarian a
--     golpear donde no es.
--
-- Aqui se mide la geometria ANTES y DESPUES del ciclo completo, pieza a
-- pieza, y se comparan los tres valores. Es la unica forma de demostrar
-- que "Destroy -> Restore" no pierde posicion, tamano ni orientacion.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Services = game:GetService("ServerScriptService"):FindFirstChild("Services")
if not Services then
	return "ERROR: no hay ServerScriptService.Services"
end

-- El servicio hay que REQUIRE-lo: `FindFirstChild` devuelve el ModuleScript,
-- no sus funciones. Sin este `require`, llamar a `ApplyDamage` falla con
-- "not a valid member of ModuleScript".
local Destruction = Services:FindFirstChild("DestructionService")
if not Destruction then
	return "ERROR: no hay DestructionService"
end

local okRequire, api = pcall(require, Destruction)
if not okRequire then
	return "ERROR: no se pudo cargar DestructionService: " .. tostring(api)
end

local forest = Workspace:FindFirstChild("Worlds") and Workspace.Worlds:FindFirstChild("Forest")
local blocksFolder = forest and forest:FindFirstChild("Blocks")
if not blocksFolder then
	return "ERROR: no hay Forest.Blocks"
end

-- 1. Estado INICIAL de los 48 bloques.
--
-- Se recorren LOS DOS carpetas: `Blocks` (28, el perimetro) y
-- `CentralStructure` (20, el relicario). Antes solo se miraba `Blocks`, y
-- el recuento daba 28, con lo que la comprobacion de "48 bloques" era
-- una constante escrita a mano en el script Node en lugar de medirse.
local before = {}

local function collect(folder, out)
	if not folder then
		return out
	end
	for _, block in ipairs(folder:GetChildren()) do
		if string.sub(block.Name, 1, 6) == "Block_" then
			out[#out + 1] = {
				block = block,
				size = block.Size,
				position = block.Position,
				orientation = block.Orientation,
				name = block.Name,
				children = #block:GetChildren(),
			}
		end
	end
	return out
end

-- Los nombres se ordenan para que el informe sea estable entre ejecuciones.
table.sort(before, function(a, b)
	return a.name < b.name
end)

collect(blocksFolder, before)
collect(forest:FindFirstChild("CentralStructure"), before)

table.sort(before, function(a, b)
	return a.name < b.name
end)

local original = before
if #original == 0 then
	return "ERROR: no hay bloques en Blocks ni en CentralStructure"
end

-- 2. Destruccion REAL via el servicio, no simulando el estado a mano.
--    Se usa el metodo publico del servicio para que la comprobacion mida lo
--    que mide el juego.
local destroyed = 0
for _, entry in ipairs(original) do
	local ok = api.ApplyDamage(entry.block, 100000)
	if ok then
		destroyed += 1
	end
end

local restored = api.RestoreAll()

-- 3. Comparacion. Se comparan los TRES valores geometricos y tambien el
--    numero de hijos, porque perder la decoracion seria perder identidad
--    aunque la caja siguiera en su sitio.
local problems = {}
local sizeOk = 0
local positionOk = 0
local orientationOk = 0
local childrenOk = 0

for _, entry in ipairs(original) do
	local block = entry.block

	if not block:IsDescendantOf(game) then
		table.insert(problems, entry.name .. ": la instancia ya no existe")
	else
		if (block.Size - entry.size).Magnitude > 0.001 then
			table.insert(problems, string.format(
				"%s SIZE: antes (%.2f,%.2f,%.2f) despues (%.2f,%.2f,%.2f)",
				entry.Name or entry.name, entry.size.X, entry.size.Y, entry.size.Z,
				block.Size.X, block.Size.Y, block.Size.Z))
		else
			sizeOk += 1
		end

		if (block.Position - entry.position).Magnitude > 0.001 then
			table.insert(problems, string.format(
				"%s POS: antes (%.2f,%.2f,%.2f) despues (%.2f,%.2f,%.2f)",
				entry.name, entry.position.X, entry.position.Y, entry.position.Z,
				block.Position.X, block.Position.Y, block.Position.Z))
		else
			positionOk += 1
		end

		local now = block.Orientation
		if math.abs(now.X - entry.orientation.X) > 0.001
			or math.abs(now.Y - entry.orientation.Y) > 0.001
			or math.abs(now.Z - entry.orientation.Z) > 0.001 then
			table.insert(problems, string.format(
				"%s ORIENT: antes (%.1f,%.1f,%.1f) despues (%.1f,%.1f,%.1f)",
				entry.name,
				entry.orientation.X, entry.orientation.Y, entry.orientation.Z,
				now.X, now.Y, now.Z))
		else
			orientationOk += 1
		end

		if #block:GetChildren() == entry.children then
			childrenOk += 1
		else
			table.insert(problems, string.format(
				"%s HIJOS: antes %d despues %d",
				entry.name, entry.children, #block:GetChildren()))
		end
	end
end

-- 4. El atributo de destruccion debe volver a false.
local stillDestroyed = 0
for _, entry in ipairs(original) do
	if entry.block:GetAttribute("IsDestroyed") == true then
		stillDestroyed += 1
	end
end

local lines = {}
lines[#lines + 1] = "bloquesProbados=" .. #original
lines[#lines + 1] = "destruidos=" .. destroyed
lines[#lines + 1] = "restaurados=" .. restored
lines[#lines + 1] = "sizeIgual=" .. sizeOk
lines[#lines + 1] = "posicionIgual=" .. positionOk
lines[#lines + 1] = "orientacionIgual=" .. orientationOk
lines[#lines + 1] = "hijosIguales=" .. childrenOk
lines[#lines + 1] = "siguenMarcadosDestruidos=" .. stillDestroyed
lines[#lines + 1] = "problemas=" .. #problems
for i = 1, math.min(#problems, 10) do
	lines[#lines + 1] = "P " .. problems[i]
end

return table.concat(lines, "\n")