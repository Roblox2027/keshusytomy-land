-- sync-lighting.lua
-- ARCHIVO GENERADO por tools/generate-project.js. NO editar a mano: se
-- sobrescribe en cada generacion y el valor unico esta en la
-- definicion de `Lighting` de ese generador.
--
-- MEDIDO con tools/probe-lighting.lua: antes de generarse, este script
-- solo creaba el ColorCorrectionEffect y dejaba el resto del Servicio
-- con los valores de la sesion (Brightness 2.4, Haze 1.6, Threshold
-- 0.85). El lobby salia blanco y nada lo delataba.

local Lighting = game:GetService("Lighting")

-- Ajustes del propio Servicio.
Lighting.GlobalShadows = true
Lighting.ClockTime = 15.2
Lighting.Brightness = 1.05
Lighting.Ambient = Color3.fromRGB(52, 62, 78)
Lighting.OutdoorAmbient = Color3.fromRGB(74, 96, 92)
Lighting.EnvironmentDiffuseScale = 0.4
Lighting.EnvironmentSpecularScale = 0.22
Lighting.ShadowSoftness = 0.2

-- Efectos hijos.
-- Atmosphere: se reutiliza si ya existe, para no duplicar el efecto.
local fx = Lighting:FindFirstChild("Atmosphere")
if not (fx and fx:IsA("Atmosphere")) then
	fx = Instance.new("Atmosphere")
	fx.Name = "Atmosphere"
	fx.Parent = Lighting
end
	fx.Density = 0.18
	fx.Haze = 0.7
	fx.Color = Color3.fromRGB(150, 186, 180)
	fx.Decay = Color3.fromRGB(96, 124, 116)
	fx.Glare = 0.02
	fx.Offset = 0.15

-- KeshusyGrade: se reutiliza si ya existe, para no duplicar el efecto.
local fx = Lighting:FindFirstChild("KeshusyGrade")
if not (fx and fx:IsA("ColorCorrectionEffect")) then
	fx = Instance.new("ColorCorrectionEffect")
	fx.Name = "KeshusyGrade"
	fx.Parent = Lighting
end
	fx.Brightness = 0.01
	fx.Contrast = 0.16
	fx.Saturation = 0.12
	fx.TintColor = Color3.fromRGB(255, 248, 238)

-- ForestBloom: se reutiliza si ya existe, para no duplicar el efecto.
local fx = Lighting:FindFirstChild("ForestBloom")
if not (fx and fx:IsA("BloomEffect")) then
	fx = Instance.new("BloomEffect")
	fx.Name = "ForestBloom"
	fx.Parent = Lighting
end
	fx.Intensity = 0.3
	fx.Size = 24
	fx.Threshold = 1.05

return ("Lighting sincronizado: brillo %s, %d efectos"):format(
	Lighting.Brightness,
	#Lighting:GetChildren()
)
