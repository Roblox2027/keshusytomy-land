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
---
--- El perdedor es SIEMPRE el arbol mas NUEVO, nunca el que ya estaba en el
--- Workspace. Es decir: `keep` es la instancia que ya vivia en el Workspace
--- (la historica) y `drop` es la que acaba de importar Rojo.
---
--- POR QUE (bug corregido en la auditoria de importacion)
--- ------------------------------------------------------
-- El orden era el contrario: se conservaba la primera en llegar y se
-- descartaba la segunda. Con `merge-workspace.lua` subiendo primero los
-- hijos del envoltorio y `dedupe-workspace.lua` ejecutandose DESPUES, la
-- instancia que sobrevivia era la del envoltorio... y esas llegaban con la
-- posicion a cero por el fallo de `<Properties>` que ya se corrigio en
-- `sync-workspace.js`. La deduplicacion se llevaba por delante la geometria
-- buena y dejaba el amontonado en el origen, de modo que el mapa se veia
-- correcto en el recuento de instancias (source == runtime) y aun asi todo
-- el lobby seguia apilado en (0, 0, 0).
--
-- Al invertir el orden, la geometria consolidada gana siempre y la
-- duplicacion reciente se descarta.
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
			-- Mismo nombre y al menos uno no es Folder: gana la instancia
			-- que ya estaba consolidada.
			child:Destroy()
			table.insert(report, path .. "/" .. child.Name .. " (duplicado descartado)")
		end
	end
end

--- Raiz del mapa: los contenedores que `default.project.json` declara como
--- hijos directos de Workspace.
---
--- Todo lo demas que cuelgue de aqui (`Bombs`, `ExplosionVfx`, el modelo del
--- jugador, restos de `src/Workspace`) es efimero y no forma parte del mapa.
local MAP_ROOTS = { "Environment", "SpawnLocations", "Lobby", "Worlds" }

-- Se decide aqui, y no con un flag, por una condicion que se puede COMPROBAR:
-- si el mapa tiene Partes pegadas al origen que el diseno no pide, el estado
-- actual no es de fiar y hay que reconstruirlo desde cero.
local function mapNeedsReset()
	for _, name in ipairs(MAP_ROOTS) do
		local container = Workspace:FindFirstChild(name)
		if container then
			for _, d in ipairs(container:GetDescendants()) do
				if d:IsA("BasePart") then
					-- Una Part en el origen con tamano grande no es una
					-- pieza de diseno: el mapa declarado coloca el lobby
					-- entre -70 y 70 y la arena alrededor de x = 500.
					if d.Position.Magnitude < 0.001 and d.Size.Magnitude > 20 then
						return true
					end
				end
			end
		end
	end
	return false
end

if mapNeedsReset() then
	-- La purga completa se hace en `reset-map.lua`, que `sync-all.js`
	-- ejecuta ANTES de importar. Aqui solo se avisa: vaciar el mapa en este
	-- punto destruiria justo lo que `merge-workspace.lua` acaba de subir y
	-- el Workspace se quedaria sin mapa hasta la siguiente pasada.
	table.insert(report, "AVISO: hay Partes grandes en el origen; ejecuta reset-map.lua antes de importar")
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

-- ENVOLTORIOS RESIDUALES
--
-- BUG CORREGIDO (auditoria de importacion)
-- ----------------------------------------
-- Tras arreglar el corte del `<Properties>` en `sync-workspace.js`, Studio
-- seguia acumulando un `Workspace.WorkspaceSource` de una importacion
-- anterior fallida. `merge-workspace.lua` ya destruye el envoltorio de la
-- importacion que el acaba de hacer, pero no sabe nada de los que quedaron
-- de EJECUCIONES PREVIAS.
--
-- El efecto era una divergencia permanente: el recuento de instancias se
-- duplicaba entero (271 en source, 462 en runtime) y `source-runtime-diff`
-- nunca volvia a dar PASS, aunque la geometria buena ya estuviera en su
-- sitio.
--
-- El envoltorio residual puede estar VACIO o Lleno. Si esta lleno, su
-- contenido es geometria duplicada de una importacion anterior, y el mapa
-- canonico ya esta en el hijo homonimo de verdad, asi que se fusiona y se
-- descarta el sobrante (el perdedor es el envoltorio, no el mapa).
local function purgeWrapper(name)
	local leftover = Workspace:FindFirstChild(name)
	if not leftover or not leftover:IsA("Folder") then
		return
	end

	-- Fusion por hijo: cada nombre del envoltorio se pasa al gemelo real.
	for _, child in ipairs(leftover:GetChildren()) do
		local real = nil
		for _, c in ipairs(Workspace:GetChildren()) do
			if c ~= leftover and c.Name == child.Name then
				real = c
				break
			end
		end

		if real then
			if real:IsA("Folder") and child:IsA("Folder") then
				mergeInto(real, child, child.Name)
				table.insert(report, name .. "/" .. child.Name .. " (fusionado en el residual)")
			else
				real:Destroy()
				child.Parent = Workspace
				table.insert(report, name .. "/" .. child.Name .. " (reemplazado por el residual)")
			end
		else
			child.Parent = Workspace
			table.insert(report, name .. "/" .. child.Name .. " (rescatado del residual)")
		end
	end

	leftover:Destroy()
	table.insert(report, name .. " envoltorio residual eliminado")
end

for _, residualName in ipairs({ "WorkspaceSource", "Workspace" }) do
	purgeWrapper(residualName)
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
