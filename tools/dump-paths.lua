-- dump-paths.lua
-- Vuelca TODAS las rutas de instancias del DataModel, una por linea.
--
-- Lo usa `source-runtime-diff.js` para comparar el arbol REAL de Studio
-- con el que produce `rojo build`. Sin depth limite: una divergencia a
-- 6 niveles (un bloque dentro de Blocks dentro de Forest) tiene que
-- aparecer igual que una a nivel 1.

local ROOTS = {
	game:GetService("Workspace"),
	game:GetService("ServerScriptService"),
	game:GetService("ReplicatedStorage"),
	game:GetService("StarterGui"),
	game:GetService("StarterPlayer"),
	game:GetService("ServerStorage"),
	game:GetService("SoundService"),
	game:GetService("Lighting"),
}

local lines = {}
local count = 0

-- BUG QUE ESTE VOLCADO OCULTABA (corregido en la auditoria de integracion):
-- el recorrido emitia `ruta<TAB>ClassName` y `source-runtime-diff.js` lo
-- guardaba en un Map indexado por ruta. Con DOS hijos homonimos bajo el
-- mismo padre, la segunda entrada SOBRESCRIBIA a la primera y el informe
-- de diferencias daba "PASS" con el arbol roto: StarterPlayerScripts
-- tenia ClientMain, Controllers y Mobile duplicados (ClientMain
-- ejecutandose DOS veces) y el gate no lo veia.
--
-- La correccion es hacer el volcado AMBIGUO cuando un nombre se repite
-- entre hermanos: la primera aparicion conserva la ruta y las siguientes
-- se numeran como `ruta[2]`, `ruta[3]`. El comparador no necesita
-- cambios: las rutas numeradas no existen en el source, asi que aparecen
-- como "sobran en Studio" y el gate pasa a FAIL. La duplicacion se
-- vuelve, por fin, una divergencia que el gate puede ver.
local function walk(inst, prefix)
	local seen = {}

	for _, child in ipairs(inst:GetChildren()) do
		local base = prefix .. child.Name
		local seenCount = (seen[child.Name] or 0) + 1
		seen[child.Name] = seenCount

		local path = base
		if seenCount > 1 then
			path = ("%s[%d]"):format(base, seenCount)
		end

		count += 1
		table.insert(lines, path .. "\t" .. child.ClassName)
		walk(child, path .. ".")
	end
end

-- Los servicios se incluyen a si mismos: el volcado recorre sus
-- hijos, asi que sin esta linea el servicio raiz no aparece y el
-- informe los daria por "faltantes" cuando estan perfectamente bien.
for _, root in ipairs(ROOTS) do
	table.insert(lines, root.Name .. "\t" .. root.ClassName)
	count += 1
	walk(root, root.Name .. ".")
end

table.sort(lines)
table.insert(lines, 1, "TOTAL=" .. count)
return table.concat(lines, "\n")
