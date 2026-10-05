-- probe-lighting.lua
-- Mide el estado REAL de la iluminacion y del suelo del lobby.

local Lighting = game:GetService("Lighting")
local out = {}

local function fmt(v)
	if typeof(v) == "number" then
		return ("%.3f"):format(v)
	end
	return tostring(v)
end

out[#out + 1] = "== Lighting =="
local props = {
	"Brightness", "ClockTime", "ExposureCompensation", "EnvironmentDiffuseScale",
	"EnvironmentSpecularScale", "GlobalShadows", "ShadowSoftness",
	"OutdoorAmbient", "Ambient", "FogColor", "FogStart", "FogEnd",
}
for _, p in ipairs(props) do
	out[#out + 1] = p .. " = " .. fmt(Lighting[p])
end

out[#out + 1] = "== hijos de Lighting =="
for _, c in ipairs(Lighting:GetChildren()) do
	local extra = ""
	if c:IsA("BloomEffect") then
		extra = (" Intensity=%s Threshold=%s Size=%s"):format(
			fmt(c.Intensity), fmt(c.Threshold), fmt(c.Size))
	elseif c:IsA("Atmosphere") then
		extra = (" Density=%s Haze=%s Offset=%s Color=%s"):format(
			fmt(c.Density), fmt(c.Haze), fmt(c.Offset), tostring(c.Color))
	elseif c:IsA("ColorCorrectionEffect") then
		extra = (" Brightness=%s Contrast=%s Saturation=%s Tint=%s"):format(
			fmt(c.Brightness), fmt(c.Contrast), fmt(c.Saturation), tostring(c.TintColor))
	end
	out[#out + 1] = c.ClassName .. " " .. c.Name .. extra
end

local world = workspace:FindFirstChild("Lobby")
if world then
	out[#out + 1] = "== suelo del lobby =="
	for _, d in ipairs(world:GetDescendants()) do
		if d:IsA("BasePart") and d.Name:lower():find("floor") then
			out[#out + 1] = ("%s Color=%s Material=%s Reflectance=%s Transparency=%s")
				:format(d.Name, tostring(d.Color), tostring(d.Material),
					fmt(d.Reflectance), fmt(d.Transparency))
		end
	end
end

return table.concat(out, "\n")