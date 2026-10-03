-- Detona una bomba de inspeccion y captura, en el SERVIDOR, lo que existe
-- un instante despues: el modelo de explosion tiene que existir mientras dura.
local services = game:GetService("ServerScriptService").Services
local explosionService = require(services:WaitForChild("ExplosionService"))

local model = workspace.Bombs:FindFirstChild("Bomb_INSPECCION")

if not model or not model.PrimaryPart then
	return { error = "no hay bomba de inspeccion" }
end

local center = model.PrimaryPart.Position
explosionService.Detonate(center, 24, nil, "Forest")
model:Destroy()

-- Se mide de inmediato: el efecto dura 0.8 s y una llamada al servidor por
-- MCP tarda mas, asi que leerlo "despues" mide siempre cero.
local carpeta = workspace:FindFirstChild("ExplosionVfx")
local info = { total = #carpeta:GetChildren(), modelos = {} }

for _, child in ipairs(carpeta:GetChildren()) do
	if child:IsA("Model") then
		local piezas = {}

		for _, part in ipairs(child:GetChildren()) do
			if part:IsA("BasePart") then
				table.insert(piezas, string.format("%s size=%s t=%s",
					part.Name, tostring(part.Size), tostring(part.Transparency)))
			end
		end

		table.insert(info.modelos, child.Name .. " radio=" .. tostring(child:GetAttribute("VisualRadius"))
			.. " piezas=" .. table.concat(piezas, " | "))
	end
end

return info