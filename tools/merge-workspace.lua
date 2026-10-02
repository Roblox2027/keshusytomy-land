-- merge-workspace.lua
-- Fusiona el arbol importado por `sync-workspace.js` en el Workspace real.
--
-- `import_rbxm` no puede crear un segundo Workspace, asi que el arbol llega
-- envuelto en un Folder. Este script sube sus hijos al Workspace de verdad y
-- destruye el envoltorio.
--
-- Se aceptan LOS DOS nombres posibles del envoltorio:
--   - `Workspace`  (el nombre que usa `sync-workspace.js`);
--   - `WorkspaceSource` (el nombre que declara el Folder raiz del `.rbxm`).
--
-- BUG CORREGIDO (auditoria de importacion)
-- ---------------------------------------
-- El script solo buscaba un envoltorio llamado `Workspace`. Como el Folder
-- raiz del `.rbxm` se llama `WorkspaceSource`, la fusion se salia entera y
-- devolvia "SIN ENVOLTORIO" sin hacer nada. El arbol importado se quedaba
-- colgando dentro de `Workspace.WorkspaceSource`, con la geometria duplicada
-- y el lobby authenticamente amontonado en el origen.
--
-- Con ambos nombres reconocidos, el envoltorio se encuentra y se destruye.
--
-- Es idempotente: si no hay envoltorio, no hace nada.

local Workspace = game:GetService("Workspace")

--- Busca el Folder envoltorio de la importacion, sea cual sea su nombre.
--- @return Folder?
local function findWrapper()
	for _, name in ipairs({ "WorkspaceSource", "Workspace" }) do
		local candidate = Workspace:FindFirstChild(name)
		if candidate and candidate:IsA("Folder") then
			return candidate
		end
	end
	return nil
end

local wrapper = findWrapper()
if not wrapper then
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
	"FUSIONADO: %d carpetas subidas (%s); %d placeholders vacios eliminados (%s); envoltorio '%s' destruido",
	#moved,
	table.concat(moved, ", "),
	#removed,
	#removed > 0 and table.concat(removed, ", ") or "-",
	wrapper.Name
)
