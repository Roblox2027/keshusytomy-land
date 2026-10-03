-- Sonda de errores: escribe SOLO los mensajes que son errores de los
-- servicios del juego, para que el informe no se llene de ruido del plugin.
local out = {}
local seen = {}

for _, message in ipairs(_G.__KES_LOG or {}) do
	table.insert(out, message)
end

return out