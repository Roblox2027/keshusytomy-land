"use strict";

/*
	remap.js
	Importa el subarbol `Workspace` de Rojo en la sesion de Studio y ejecuta
	la fusion y la deduplicacion.

	POR QUE EXISTE, Y POR QUE NO BASTA CON `sync-all.js`
	---------------------------------------------------
	`reset-map.lua` decide NO purgar cuando el mapa le parece sano, y su
	criterio de salud es SOLO estructural: que haya mas de 100 Partes y que
	nada este amontonado en el origen. Un mapa puede pasar ese filtro y aun
	asi tener una version VIEJA del bosque (por ejemplo, bloques sin la
	decoracion nueva). Entonces la fusion nunca destruye el arbol antiguo,
	`dedupe-workspace.lua` se limita a descartar la copia recien importada,
	y la sincronizacion "pasa" con el mapa viejo puesto.

	Eso es justo lo que pasaba con el bosque: el mapa era antiguo pero
	sanito, la deduplicacion descartaba la copia nueva y se perdia toda la
	decoracion.

	Este script ejecuta SOLO los pasos de geometria (importar, fusionar,
	deduplicar, colocar posiciones), que es lo que hay que repetir al
	reescribir el mapa. El resto del pipeline (`sync-scripts.js`) no hace
	falta para esto.

	Uso:  node tools/remap.js
*/

const fs = require("fs");
const path = require("path");

const mcp = require("./mcp");

const ROOT = path.resolve(__dirname, "..");
const CACHE = path.join(ROOT, ".cache");
const ARGS = path.join(CACHE, "remap-args.json");
const SOURCE = path.join(CACHE, "workspace-source.rbxm");

/** Ejecuta un Luau y devuelve su valor. */
async function lua(file) {
	const code = fs.readFileSync(path.join(__dirname, file), "utf8");
	const res = await mcp.tool("execute_luau", { code });
	const value = res && res.returnValue !== undefined ? res.returnValue : JSON.stringify(res);
	console.log("\n=== " + file + " ===");
	console.log(String(value).trim().slice(0, 2000));
	return value;
}

async function main() {
	if (!fs.existsSync(SOURCE)) {
		console.error("Falta " + path.relative(ROOT, SOURCE) + ". Ejecuta antes:");
		console.error("  node tools/sync-workspace.js");
		process.exit(1);
	}

	// Se purga SIEMPRE. Es lo unico que garantiza que el mapa de Studio
	// pase a ser exactamente el que declara `default.project.json`, y con
	// el bosque eso es indispensable: la deduplicacion incremental es
	// precisamente lo que perdia la decoracion.
	console.log("=== reset-map (purgado forzado) ===");
	const purge = await mcp.tool("execute_luau", {
		code: `
-- Purga forzada: los mismos contenedores que reset-map.lua vacia, pero
-- sin la comprobacion de salud. Es lo que hace falta al REGENERAR el mapa.
local Workspace = game:GetService("Workspace")
local removed = 0
for _, name in ipairs({ "Environment", "SpawnLocations", "Lobby", "Worlds" }) do
	local container = Workspace:FindFirstChild(name)
	if container then
		for _, child in ipairs(container:GetChildren()) do
			child:Destroy()
			removed += 1
		end
	end
end
for _, name in ipairs({ "WorkspaceSource", "Workspace" }) do
	local wrapper = Workspace:FindFirstChild(name)
	if wrapper and wrapper:IsA("Folder") then
		wrapper:Destroy()
		removed += 1
	end
end
return "purgados " .. removed .. " hijos de primer nivel"
`,
	});
	console.log("  " + String(purge && purge.returnValue !== undefined ? purge.returnValue : purge));

	fs.writeFileSync(
		ARGS,
		JSON.stringify({ source: { path: SOURCE }, parent_path: "game.Workspace", target: "edit" }),
		"utf8"
	);
	await mcp.tool("import_rbxm", JSON.parse(fs.readFileSync(ARGS, "utf8")));

	await lua("merge-workspace.lua");
	await lua("dedupe-workspace.lua");

	// `sync-workspace.js` extrae SOLO el subarbol `Workspace`, asi que
	// `Lighting` (que es un servicio hermano) nunca entra por `import_rbxm`.
	// Antes de la reconstruccion no se notaba porque el proyecto no
	// declaraba Lighting y Studio traia los suyos por defecto, que ademas
	// se llaman `Bloom`, `DepthOfField`, `Sky`, `SunRays`.
	//
	// Ahora el bosque depende de una `Atmosphere` y un `BloomEffect` PROPIOS,
	// con la hora y el ambiente del atardecer. Si no se crean aqui, el
	// bosque arranca con la iluminacion por defecto de Studio y se pierde
	// justo la identidad visual que se acaba de construir.
	await lua("apply-lighting.lua");

	// 4. Tambien en el servidor de Play.
	//
	// Studio arranca Play desde una copia en DISCO
	// (`AutoSaves/<place>_AutoRecovery_1.rbxl`), no desde el arbol de la
	// sesion de edicion. Los cambios que entran por MCP (que es la unica
	// via, porque el plugin de Rojo no esta conectado) NO llegan a esa
	// copia: se comprobo que la edicion tenia `Block_0` a 6x11x6 mientras el
	// servidor lo tenia a 8x8x8.
	//
	// El cliente ve lo que ve el servidor, asi que sin aplicar aqui la
	// iluminacion, el bosque seguiria con la hora por defecto de Studio
	// (16.5) en lugar del atardecer del proyecto (15.2).
	//
	// Es el mismo motivo por el que `apply-map-positions.js` tiene
	// `--run-server`.
	const lightingOnServer = await mcp.serverLuau(
		fs.readFileSync(path.join(__dirname, "apply-lighting.lua"), "utf8")
	);
	console.log("");
	console.log("  iluminacion en el servidor: " + JSON.stringify(lightingOnServer).slice(0, 300));

	// 5. Limpieza tambien en el servidor de Play.
	//
	// Las sondas se crean por MCP, que por defecto apunta a la sesion de
	// EDICION. Pero Play corre sobre una copia distinta, y una sonda creada
	// en el servidor (o alli importada antes) sigue apareciendo en el
	// cliente: `client-probe.js` mostraba `UpdateProbe` despues de haberla
	// borrado de la edicion.
	//
	// Se purga de los dos lados, y cada uno con su propio texto, porque son
	// arboles separados.
	const cleanup = `
local probe = game:GetService("Workspace"):FindFirstChild("UpdateProbe")
if probe then
	probe:Destroy()
	return "sonda purgada"
end
return "no habia sonda"
`;

	for (const [label, fn] of [
		["edicion", () => mcp.tool("execute_luau", { code: cleanup })],
		["servidor de Play", () => mcp.serverLuau(cleanup)],
	]) {
		try {
			const res = await fn();
			const value = res && typeof res === "object" && "value" in res ? res.value : res;
			console.log("  " + label + ": " + JSON.stringify(value).slice(0, 120));
		} catch (e) {
			// No es fatal: si Play no esta arrancado, solo se limpia la
			// edicion, y el servidor se limpira en la siguiente pasada.
			console.log("  " + label + ": no disponible (" + e.message.slice(0, 60) + ")");
		}
	}

	// Las posiciones se vuelven a colocar: la importacion las deja todas en
	// el origen.
	fs.rmSync(ARGS, { force: true });
	console.log("\nMapa reconstruido. Ahora:");
	console.log("  node tools/apply-map-positions.js --run");
	console.log("  node tools/source-runtime-diff.js");
}

main().catch((e) => {
	console.error("FALLO: " + e.message);
	process.exit(2);
});