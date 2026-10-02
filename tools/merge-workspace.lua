-- merge-workspace.lua
-- Fusiona el arbol importado por `sync-workspace.js` en el Workspace real.
--
-- `import_rbxm` crea `game.Workspace.Workspace` (un Folder con el nombre
-- del sitio) porque no puede crear un segundo Workspace. Este script:
--   1. sube los hijos reales al Workspace de verdad,
--   2. elimina los placeholders vacios que losduplicaban,
--   3. destruye el Folder envoltorio.
--
-- Es idempotente: si no hay envoltorio, no hace nada.

local Workspace = game:GetService("Workspace")

local wrapper = Workspace:FindFirstChild("Workspace")
if not wrapper or not wrapper:IsA("Folder") then
	return "SIN ENVOLTORIO: nada que fusionar"
end

local moved = {}
local removed = {}

-- 1. Sustituir cada carpeta de destino por su version REAL.
for _, child in ipairs(wrapper:GetChildren()) do
	local existing = Workspace:FindFirstChild(child.Name)
	if existing then
		-- El placeholder venia de `src/Workspace`, que NO esta mapeado
		-- en `default.project.json` y por eso solo llegaba a Studio
		-- como una carpeta vacia. Se descarta: la version con contenido
		-- es la que Rojo construye desde el proyecto.
		if existing:IsA("Folder") and #existing:GetChildren() == 0 then
			existing:Destroy()
			table.insert(removed, existing.Name)
		end
	end
	child.Parent = Workspace
	table.insert(moved, child.Name)
end

wrapper:Destroy()

return string.format(
	"FUSIONADO: %d carpetas subidas (%s); %d placeholders vacios eliminados (%s); envoltorio destruido",
	#moved,
	table.concat(moved, ", "),
	#removed,
	#removed > 0 and table.concat(removed, ", ") or "-"
)
