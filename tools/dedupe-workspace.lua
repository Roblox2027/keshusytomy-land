-- dedupe-workspace.lua
-- Colapsa hijos duplicados en Workspace fusionando sus contenidos.
--
-- POR QUE
-- -------
-- `import_rbxm` no puede crear un segundo Workspace: envuelve el
-- arbol en un Folder. Al fusionarlo aparecieron DOS carpetas
-- `Workspace.Worlds`: el placeholder historico (5 carpetas de mundo
-- vacias, venia de `src/Workspace`, que no esta mapeado en
-- `default.project.json`) y la real de Rojo (Forest con 28 bloques).
--
-- Un duplicado NO es cosmético. `FindFirstChild("Worlds")` devuelve
-- el primero que encuentre, asi que `WorldService` podria leer el
-- Forest vacio y no ver ni un solo bloque. El contrato del mapa es
-- `Workspace.Worlds.Forest.Blocks`: tiene que existir UN solo Worlds.
--
-- `merge-workspace.lua` solo borra un destino cuando esta VACIO, por
-- lo que no resolvio este caso. Aqui se fusionan recursivamente: el
-- perdedor de cada nombre se vacia dentro del ganador y luego se
-- destruye. Es idempotente y no destructivo con el contenido.

local Workspace = game:GetService("Workspace")

local report = {}

--- Fusiona dos homonimos. Gana `keep`, se disuelve `drop`.
local function mergeInto(keep, drop, path)
	local keptNames = {}
	for _, c in keep:GetChildren() do
		keptNames[c.Name] = true
	end

	for _, child in drop:GetChildren() do
		local existing = keep:FindFirstChild(child.Name)
		if existing == nil then
			child.Parent = keep
			table.insert(report, path .. "/" .. child.Name .. " (movido)")
		elseif existing:IsA("Folder") and child:IsA("Folder") then
			mergeInto(existing, child, path .. "/" .. child.Name)
			table.insert(report, path .. "/" .. child.Name .. " (fusionado)")
		else
			-- Mismo nombre y al menos uno no es Folder: el contenido
			-- real de Rojo gana, el placeholder se descarta.
			existing:Destroy()
			child.Parent = keep
			table.insert(report, path .. "/" .. child.Name .. " (reemplazado)")
		end
	end
end

local seen = {}
local duplicates = 0
for _, child in ipairs(Workspace:GetChildren()) do
	if seen[child.Name] then
		mergeInto(seen[child.Name], child, child.Name)
		child:Destroy()
		duplicates = duplicates + 1
		table.insert(report, child.Name .. " DUPLICADO eliminado (contenido fusionado)")
	else
		seen[child.Name] = child
	end
end

local remaining = {}
for _, c in ipairs(Workspace:GetChildren()) do
	table.insert(remaining, c.Name .. "(" .. #c:GetChildren() .. ")")
end

return string.format(
	"duplicados colapsados: %d\noperaciones:\n  %s\nWorkspace ahora: %s",
	duplicates,
	#report > 0 and table.concat(report, "\n  ") or "-",
	table.concat(remaining, ", ")
)
