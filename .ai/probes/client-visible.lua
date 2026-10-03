-- Lo que el JUGADOR VE de un monstruo: partes visibles, cartel, ojos y
-- posicion. Un modelo que existe pero tiene `Transparency = 1` en todas sus
-- partes pasa un `IsA("Model")` y falla esto.
local out = {}
local monsters = {}

for _, model in ipairs(workspace.Monsters:GetChildren()) do
	if model:IsA("Model") then
		local visible = {}
		local total = 0

		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") then
				total += 1

				if part.Transparency < 1 and part.Size.Magnitude > 0.5 then
					table.insert(visible, part.Name)
				end
			end
		end

		local tag = model:FindFirstChild("NameTag", true)
		local label = tag and tag:FindFirstChild("Name", true)
		local highlight = model:FindFirstChild("Highlight")

		table.insert(monsters, {
			name = model.Name,
			parts = total,
			visibleParts = #visible,
			sample = visible,
			hasTag = tag ~= nil,
			tagText = if label and label:IsA("TextLabel") then label.Text else "SIN CARTEL",
			hasHighlight = highlight ~= nil,
			primary = model.PrimaryPart ~= nil,
			pos = if model.PrimaryPart then tostring(model.PrimaryPart.Position) else "-",
		})
	end
end

out.monsters = monsters

local powerups = {}

for _, model in ipairs(workspace.Powerups:GetChildren()) do
	if model:IsA("Model") then
		local core = model:FindFirstChild("Core")
		local label = model:FindFirstChild("Text", true)

		table.insert(powerups, {
			name = model.Name,
			kind = tostring(model:GetAttribute("PowerupKind")),
			coreColor = if core and core:IsA("BasePart") then tostring(core.Color) else "-",
			coreTransparency = if core and core:IsA("BasePart") then tostring(core.Transparency) else "-",
			label = if label and label:IsA("TextLabel") then label.Text else "SIN CARTEL",
			primary = model.PrimaryPart ~= nil,
		})
	end
end

out.powerups = powerups
return out