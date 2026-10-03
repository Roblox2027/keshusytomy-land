-- Lo que el JUGADOR VE de una bomba: cada pieza, su color, su tamano y el
-- cartel de la mecha. Un modelo con siete partes existe y puede ser
-- invisible; esto mide si hay algo que se pueda distinguir en la arena.
local out = {}
local bombs = {}

for _, model in ipairs(workspace.Bombs:GetChildren()) do
	if model:IsA("Model") then
		local piezas = {}
		local visibles = 0

		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") then
				local seVe = part.Transparency < 1 and part.Size.Magnitude > 0.1

				if seVe then
					visibles += 1
				end

				table.insert(piezas, string.format("%s t=%s size=%s color=%s mat=%s",
					part.Name, tostring(part.Transparency), tostring(part.Size),
					tostring(part.Color), tostring(part.Material)))
			end
		end

		local timer = model:FindFirstChild("Timer", true)
		local label = timer and timer:FindFirstChild("Label")
		local glow = model:FindFirstChild("FuseGlow", true)
		local light = model:FindFirstChild("FuseLight", true)
		local ring = model:FindFirstChild("RadiusIndicator", true)
		local attachment = model:FindFirstChild("ExplosionOrigin")
		local particles = model:FindFirstChild("Particles", true)

		table.insert(bombs, {
			name = model.Name,
			primary = model.PrimaryPart ~= nil,
			partes = #piezas,
			visibles = visibles,
			piezas = piezas,
			mecha = if label and label:IsA("TextLabel") then label.Text else "SIN CARTEL",
			luz = if light and light:IsA("PointLight") then tostring(light.Brightness) else "SIN LUZ",
			glow = if glow and glow:IsA("BasePart") then tostring(glow.Color) else "SIN PUNTA",
			radio = if ring and ring:IsA("BasePart") then tostring(ring.Size) else "SIN ARO",
			origen = attachment ~= nil,
			particulas = particles ~= nil,
			fuseAttr = tostring(model:GetAttribute("FuseRemaining")),
			pos = if model.PrimaryPart then tostring(model.PrimaryPart.Position) else "-",
		})
	end
end

out.bombs = bombs
out.explosiones = #workspace:FindFirstChild("ExplosionVfx"):GetChildren()

return out