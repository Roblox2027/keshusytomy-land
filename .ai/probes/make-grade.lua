-- Borra el ColorCorrectionEffect de Lighting.
--
-- Se usa para PROBAR que `tools/sync-lighting.lua` lo recrea desde cero.
-- Si el pipeline esta bien, borrar y resincronizar debe devolver el mismo
-- arbol; si el efecto reaparece sin este script, entonces algo lo esta
-- creando por otra via y el paso de `sync-all` es redundante.
local Lighting = game:GetService("Lighting")
local grade = Lighting:FindFirstChild("KeshusyGrade")

if grade then
	grade:Destroy()
	return "KeshusyGrade BORRADO"
end

return "KeshusyGrade no estaba"