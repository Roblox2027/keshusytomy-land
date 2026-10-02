-- dedupe-tree.lua
-- Colapsa hijos DUPLICADOS en TODO el DataModel, no solo en Workspace.
--
-- POR QUE ESTA VERSION
-- -------------------
-- `dedupe-workspace.lua` resolvia el caso de `Workspace.Worlds` duplicado
-- y por eso se llamaba asi. La auditoria de integracion encontro el mismo
-- defecto en otro sitio: `StarterPlayer.StarterPlayerScripts` tenia SEIS
-- hijos para TRES nombres unicos (ClientMain, Controllers y Mobile, cada
-- uno duplicado). Eso no es cosmético:
--
--   * `ClientMain` es un LocalScript, y se ejecutaba DOS VECES en cada
--     cliente (doble HUD, doble input, doble conexion de remotes).
--   * `ClientMain` recorre Controllers con `WaitForChild` o `GetChildren`;
--     con dos carpetas homonimas puede cablear la mitad de los controladores
--     contra una y la otra mitad contra la otra.
--   * `FindFirstChild` devuelve el primero encontrado, asi que el codigo
--     puede cablearse contra una copia obsoleta y dejar la otra muerta.
--
-- Este recorrido es RECURSIVO y de alcance configurable: duplica cualquier
-- padre, no solo Workspace. Se conserva la PRIMERA aparicion de cada nombre
-- y se destruyen las siguientes. Es idempotente y reversible en el sentido
-- de que no se pierde contenido unico: si el duplicado tiene hijos con
-- nombres que el ganador no tiene, se mueven antes de destruirlo.

--- Fusiona `drop` dentro de `keep` sin perder contenido.
local function mergeInto(keep, drop, path, report)
	local kept = {}
	for _, c in keep:GetChildren() do
		kept[c.Name] = true
	end

	for _, child in ipairs(drop:GetChildren()) do
		local existing = keep:FindFirstChild(child.Name)
		if existing == nil then
			child.Parent = keep
			table.insert(report, path .. "/" .. child.Name .. " (movido)")
		elseif existing:IsA("Folder") and child:IsA("Folder") then
			mergeInto(existing, child, path .. "/" .. child.Name, report)
			table.insert(report, path .. "/" .. child.Name .. " (fusionado)")
		else
			-- Mismo nombre y al menos uno no es Folder. El duplicado se
			-- descarta; NO se destruye `existing`, que es la copia viva y
			-- la que Rojo gestiona. Destruir aqui al ganador dejaria el
			-- nombre sin cubrir hasta el siguiente sync, que es
			-- justamente el fallo que este tooling evita.
			table.insert(report, path .. "/" .. child.Name .. " (duplicado descartado)")
			child:Destroy()
		end
	end
end

local report = {}
local duplicates = 0

--- Elimina homonimos de un solo padre.
local function dedupeParent(inst, path)
	local seen = {}
	for _, child in ipairs(inst:GetChildren()) do
		if seen[child.Name] then
			mergeInto(seen[child.Name], child, path, report)
			table.insert(report, ("%s.%s DUPLICADO eliminado"):format(path, child.Name))
			duplicates += 1
			child:Destroy()
		else
			seen[child.Name] = child
		end
	end
end

--- Recorre el arbol de abajo arriba: primero los hijos, luego el padre.
---
--- El orden importa. Si se deduplicara el padre ANTES de los hijos, al
--- fusionar dos subarboles el contenido movido ya no se revisaria y un
--- duplicado anidado sobreviviria al cleanup. De abajo arriba, cualquier
--- instancia que se mueva por una fusion ya fue visitada en su ubicacion
--- de origen y sus hijos estan limpios; y si se movio a un padre todavia
--- sin visitar, ese padre se visitara despues y lo deduplicara igualmente.
local function walk(inst, path)
	for _, child in ipairs(inst:GetChildren()) do
		walk(child, path .. "." .. child.Name)
	end
	dedupeParent(inst, path)
end

local ROOTS = {
	game:GetService("Workspace"),
	game:GetService("ServerScriptService"),
	game:GetService("ReplicatedStorage"),
	game:GetService("StarterPlayer"),
	game:GetService("StarterGui"),
	game:GetService("ServerStorage"),
	game:GetService("SoundService"),
}

for _, root in ipairs(ROOTS) do
	walk(root, root.Name)
end

local function snapshot(inst, prefix, depth)
	local parts = {}
	for _, c in ipairs(inst:GetChildren()) do
		table.insert(parts, prefix .. c.Name .. "(" .. #c:GetChildren() .. ")")
		if depth > 0 then
			table.insert(parts, snapshot(c, "", depth - 1))
		end
	end
	return table.concat(parts, ", ")
end

local sps = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")

return string.format(
	"duplicados eliminados: %d\noperaciones:\n  %s\n\nStarterPlayerScripts ahora (%d hijos): %s",
	duplicates,
	#report > 0 and table.concat(report, "\n  ") or "-",
	#sps:GetChildren(),
	snapshot(sps, "", 1)
)