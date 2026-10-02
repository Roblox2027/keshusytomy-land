-- Generado por tools/gen-lighting-lua.js. NO EDITAR A MANO.
-- Fuente de verdad: default.project.json (tools/generate-project.js).
--
-- Aplica los ajustes de Lighting que Rojo NO puede importar por el camino
-- habitual: sync-workspace.js solo extrae el subarbol Workspace, y Lighting
-- es un servicio hermano del DataModel.
--
-- Los objetos que declara el proyecto se CREAN si no existen y se BORRAN si
-- existen con otro nombre. Studio trae los suyos por defecto ("Bloom",
-- "DepthOfField", "Sky", "SunRays"), y esos se eliminan a proposito: son
-- ajustes de un proyecto vacio y compiten con los del bosque.

local Lighting = game:GetService("Lighting")

-- 1. Ajustes del servicio.
	Lighting.ClockTime = 15.2
	Lighting.Brightness = 2.4
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.4
	Lighting.ShadowSoftness = 0.25
	Lighting.GlobalShadows = true
	Lighting.Ambient = Color3.fromRGB(92, 104, 118)
	Lighting.OutdoorAmbient = Color3.fromRGB(126, 148, 138)

-- 2. Los objetos POR DEFECTO de Studio, que este proyecto no declara.
--
-- Se borran por nombre y solo si son de la clase esperada, para no tocar
-- nada si alguien ha colocado otra cosa a mano.
local DEFAULT_OBJECTS = {
	{ name = "Bloom", className = "BloomEffect" },
	{ name = "DepthOfField", className = "DepthOfFieldEffect" },
	{ name = "SunRays", className = "SunRaysEffect" },
	{ name = "Sky", className = "Sky" },
	{ name = "Clouds", className = "Clouds" },
}

local removed = {}
for _, entry in ipairs(DEFAULT_OBJECTS) do
	local existing = Lighting:FindFirstChild(entry.name)
	if existing and existing:IsA(entry.className) then
		existing:Destroy()
		table.insert(removed, entry.name)
	end
end

-- 3. Los objetos que declara el proyecto.
local created = {}

-- El argumento es el NOMBRE de la instancia, y la clase se deduce de ella
-- con una tabla. Antes se pasaba el nombre como si fuera la clase, y
-- Instance.new("ForestBloom") fallaba con "Unable to create an Instance
-- of type". El nombre y la clase son cosas distintas: "ForestBloom" es el
-- nombre que el proyecto da a un BloomEffect.
local CLASS_OF = {
	Atmosphere = "Atmosphere",
	ForestBloom = "BloomEffect",
}

local function ensure(name, values)
	local className = CLASS_OF[name]
	if className == nil then
		error("clase desconocida para '" .. name .. "'")
	end

	-- Se borra CUALQUIER cosa que ya se llame asi, sin comprobar la clase:
	-- si el nombre esta ocupado por otra clase, el proyecto manda igual.
	local existing = Lighting:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end

	local instance = Instance.new(className)
	instance.Name = name
	for property, value in pairs(values) do
		instance[property] = value
	end
	instance.Parent = Lighting
	table.insert(created, name)
end

ensure("Atmosphere", {
	Color = Color3.fromRGB(178, 206, 196),
	Decay = Color3.fromRGB(126, 152, 140),
	Density = 0.22,
	Haze = 1.6,
	Glare = 0.25,
	Offset = 0.1,
})

ensure("ForestBloom", {
	Intensity = 0.45,
	Size = 28,
	Threshold = 0.85,
})

return string.format(
	"iluminacion aplicada: ClockTime=%s; creados=[%s]; borrados=[%s]",
	tostring(Lighting.ClockTime),
	table.concat(created, ", "),
	table.concat(removed, ", ")
)
