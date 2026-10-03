-- Revision del CARTEL DE LA MECHA y del origen de explosion.
--
-- El `FindFirstChild` sin `true` solo mira hijos DIRECTOS, y tanto el cartel
-- como el `Attachment` cuelgan de la raiz (dentro del modelo), no del modelo.
-- Medir con el metodo equivocado da "SIN CARTEL" y hace pensar que falta la
-- mecha cuando lo que falta es el `true`.
local model = workspace.Bombs:FindFirstChild("Bomb_INSPECCION")

if not model then
	return { error = "no hay bomba de inspeccion" }
end

local out = { hijos = {} }

for _, child in ipairs(model:GetChildren()) do
	table.insert(out.hijos, child.Name .. " [" .. child.ClassName .. "]")
end

local timer = model:FindFirstChild("Timer", true)
local label = if timer then timer:FindFirstChild("Label", true) else nil
local origin = model:FindFirstChild("ExplosionOrigin", true)
local holder = timer and timer:FindFirstChild("Holder", true)

out.cartel = timer ~= nil
out.carton = label and label.Text or "SIN CARTEL"
out.color = if label and label:IsA("TextLabel") then tostring(label.TextColor3) else "-"
out.tamano = if label and label:IsA("TextLabel") then tostring(label.TextSize) else "-"
out.distanciaMax = if timer then tostring(timer.MaxDistance) else "-"
out.fondo = if holder then tostring(holder.BackgroundColor3) else "-"
out.origen = origin ~= nil
out.lista = out.hijos

return out