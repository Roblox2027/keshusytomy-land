"use strict";

/*
	gen-lighting-lua.js
	Genera `tools/apply-lighting.lua` a partir de `default.project.json`.

	POR QUE HACE FALTA
	------------------
	El pipeline de sincronizacion (`sync-workspace.js` -> `import_rbxm`)
	extrae e importa SOLO el subarbol `Workspace`. `Lighting` es un
	SERVICIO HERMANO del DataModel, asi que nunca entra por esa via, y el
	`source-runtime-diff` lo senalaba como la ultima instancia que faltaba.

	Antes de reconstruir el bosque esto no importaba: el proyecto no
	declaraba `Lighting` y Studio traia los suyos por defecto, ademas
	llamados `Bloom` o `SunRays`. Ahora el bosque declara una `Atmosphere` y
	un `BloomEffect` propios, y sin este paso arrancaria con la
	iluminacion por defecto de Studio: sin tarde calido, sin niebla y sin
	florecer el Neon. Justo lo contrario de lo buscado.

	Se GENERA y no se escribe a mano para no crear una segunda fuente de
	verdad: si el generador cambia la hora o la niebla, este archivo se
	reescribe solo y no puede quedarse viejo.

	Uso:  node tools/gen-lighting-lua.js
*/

const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const PROJECT = path.join(ROOT, "default.project.json");
const OUT = path.join(__dirname, "apply-lighting.lua");

const proj = JSON.parse(fs.readFileSync(PROJECT, "utf8"));
const lighting = proj.tree.Lighting;

if (!lighting) {
	console.error("El proyecto no declara Lighting. Nada que aplicar.");
	process.exit(1);
}

const props = lighting.$properties || {};

/**
 * Convierte un `[r, g, b]` de floats 0..1 a la expression Luau.
 * @param {number[]} rgb
 */
const colorLuau = (rgb) =>
	"Color3.fromRGB(" + rgb.map((c) => Math.round(c * 255)).join(", ") + ")";

/** Tabla de propiedades escalares, en el orden que se escriben. */
const SCALARS = [
	["ClockTime", "number"],
	["Brightness", "number"],
	["EnvironmentDiffuseScale", "number"],
	["EnvironmentSpecularScale", "number"],
	["ShadowSoftness", "number"],
	["GlobalShadows", "boolean"],
];

const scalarLines = [];
for (const [key, kind] of SCALARS) {
	if (props[key] === undefined) continue;
	const value = kind === "boolean" ? String(props[key]) : String(props[key]);
	scalarLines.push("\tLighting." + key + " = " + value);
}

const luau = `-- Generado por tools/gen-lighting-lua.js. NO EDITAR A MANO.
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
${scalarLines.join("\n")}
${props.Ambient ? "\tLighting.Ambient = " + colorLuau(props.Ambient) : ""}
${props.OutdoorAmbient ? "\tLighting.OutdoorAmbient = " + colorLuau(props.OutdoorAmbient) : ""}

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

${lighting.Atmosphere ? `ensure("Atmosphere", {
	Color = ${colorLuau(lighting.Atmosphere.$properties.Color)},
	Decay = ${colorLuau(lighting.Atmosphere.$properties.Decay)},
	Density = ${lighting.Atmosphere.$properties.Density},
	Haze = ${lighting.Atmosphere.$properties.Haze},
	Glare = ${lighting.Atmosphere.$properties.Glare},
	Offset = ${lighting.Atmosphere.$properties.Offset},
})` : "-- El proyecto no declara Atmosphere."}

${lighting.ForestBloom ? `ensure("ForestBloom", {
	Intensity = ${lighting.ForestBloom.$properties.Intensity},
	Size = ${lighting.ForestBloom.$properties.Size},
	Threshold = ${lighting.ForestBloom.$properties.Threshold},
})` : "-- El proyecto no declara ForestBloom."}

return string.format(
	"iluminacion aplicada: ClockTime=%s; creados=[%s]; borrados=[%s]",
	tostring(Lighting.ClockTime),
	table.concat(created, ", "),
	table.concat(removed, ", ")
)
`;

fs.writeFileSync(OUT, luau, "utf8");
console.log("escrito " + path.relative(ROOT, OUT));
console.log("  ClockTime: " + props.ClockTime);
console.log("  objetos del proyecto: " + Object.keys(lighting).filter((k) => !k.startsWith("$")).join(", "));