-- Captura la explosion DESDE EL CLIENTE mientras dure.
--
-- El efecto vive 0.8 s y una llamada al cliente por MCP tarda mas, asi que
-- una sola lectura mide siempre "cero efectos". Aqui el cliente sondea
-- durante 10 s y guarda la maxima cantidad de VFX que ve.
local carpeta = workspace:FindFirstChild("ExplosionVfx")
local out = { maximo = 0, piezas = {}, luz = "-", radio = "-" }
local capturadas = {}

for _ = 1, 200 do
	local total = #carpeta:GetChildren()

	if total > out.maximo then
		out.maximo = total

		for _, child in ipairs(carpeta:GetChildren()) do
			if child:IsA("Model") then
				out.radio = tostring(child:GetAttribute("VisualRadius"))
				out.piezas = {}

				for _, part in ipairs(child:GetChildren()) do
					if part:IsA("BasePart") then
						table.insert(out.piezas, string.format("%s size=%s t=%s col=%s",
							part.Name, tostring(part.Size), tostring(part.Transparency),
							tostring(part.Color)))

						local light = part:FindFirstChildOfClass("PointLight")

						if light then
							out.luz = tostring(light.Brightness)
						end
					end
				end
			end
		end
	end

	task.wait(0.05)
end

out.visto = out.maximo > 0
return out