-- workspace-children.lua
-- Lista los hijos DIRECTOS de Workspace con su numero de hijos.
--
-- POR QUE EXISTE
-- --------------
-- `client-probe.js` seguia Teacher viendo `UpdateProbe` en el cliente
-- despues de haberla borrado de la sesion de edicion. Habia que saber si
-- la sonda seguia en el Workspace de EDICION (y el cliente era una copia
-- vieja) o si quedaba en el Workspace de PLAY (y de ahi seguia llegando
-- al cliente).
--
-- La diferencia decide que hay que purgar: reimportar el mapa, o limpiar
-- la sesion de Play.
--
-- Se imprime el arbol de un nivel: basta para localizar una sonda, y no
-- inunda con los 1 600 nietos del bosque.

local Workspace = game:GetService("Workspace")

local lines = {}
for _, child in ipairs(Workspace:GetChildren()) do
	local suffix = ""
	if child:IsA("Folder") or child:IsA("Model") then
		suffix = "(" .. #child:GetChildren() .. ")"
	end
	table.insert(lines, child.Name .. suffix)
end

return table.concat(lines, ", ")