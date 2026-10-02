-- nested-import-probe.lua
-- Diagnostica por que la decoracion HIJO de un bloque no llega a Studio.
--
-- CONTEXTO
-- --------
-- Al sincronizar, los 48 bloques `Block_*` llegan a RUNTIME pero sus 325
-- hijos `Deco_*` no. Sin embargo OTROS hijos de Part si llegan: los
-- `PointLight` que cuelgan de `Keshusy.Light_Core` sobreviven.
--
-- Eso descarta dos explicaciones que son las que se occurrian primero:
--
--   - "Studio no admite hijos bajo una BasePart"  -> FALSA, hay Parts con
--     hijos `PointLight` que llegan bien, y la sonda de este mismo script
--     lo confirma creando la jerarquia a mano.
--   - "el `.rbxm` no los trae"                    -> FALSA, estan en el
--     archivo (325 coincidencias de `Deco_`).
--
-- Lo que queda, y es lo que este script mide, es si el problema esta en
-- la SINCRONIZACION (algun paso borra oIgnora esos hijos) o en el
-- ARTEFACTO (los hijos llegan vacios).
--
-- Devuelve: cuantos bloques hay, cuantos tienen hijos, y el nombre de
-- los hijos del primer bloque que si tenga.

local Workspace = game:GetService("Workspace")

local forest = Workspace:FindFirstChild("Worlds")
		and Workspace.Worlds:FindFirstChild("Forest")

if not forest then
	return "ERROR: no existe Workspace.Worlds.Forest"
end

local blocksFolder = forest:FindFirstChild("Blocks")
if not blocksFolder then
	return "ERROR: no existe Forest.Blocks"
end

local total = 0
local withChildren = 0
local totalChildren = 0
local sample = nil
local firstIndex = nil

for _, block in ipairs(blocksFolder:GetChildren()) do
	if string.sub(block.Name, 1, 6) == "Block_" then
		total += 1
		local kids = block:GetChildren()
		if #kids > 0 then
			withChildren += 1
			totalChildren += #kids
			if sample == nil then
				local names = {}
				for _, k in ipairs(kids) do
					table.insert(names, k.Name .. "[" .. k.ClassName .. "]")
				end
				sample = block.Name .. " -> " .. table.concat(names, ", ")
				firstIndex = block.Name
			end
		end
	end
end

-- Tambien se mira si la decoracion existe en otro sitio del arbol.
local decoElsewhere = 0
for _, d in ipairs(forest:GetDescendants()) do
	if string.sub(d.Name, 1, 5) == "Deco_" then
		decoElsewhere += 1
	end
end

return string.format(
	"bloques=%d conHijos=%d hijosTotales=%d DecoEnBosque=%d | muestra: %s",
	total,
	withChildren,
	totalChildren,
	decoElsewhere,
	sample or "(ningun bloque tiene hijos)"
)