"use strict";

/*
	sync-all.js
	Puesta al dia COMPLETA de Roblox Studio respecto al repositorio.

	POR QUE EXISTE
	--------------
	El plugin de Rojo no esta conectado a esta sesion, asi que
	`rojo serve` no llega al lugar abierto. Peor: durante el trabajo se
	comprobo que la sesion de edicion se REVERTE sola (Workspace vuelve
	a losFolders vacios de `src/Workspace` y reaparece el
	`StarterPlayerScripts` que era un Folder). Aplicar los cambios a mano
	uno a uno no es fiable: hay que rehacerlos y volver a comprobar.

	Este script ejecuta siempre la misma secuencia, en el orden que
	exige cada paso, y es idempotente:

	  1. `rojo build`                 (fuente del arbol esperado)
	  2. `import_rbxm`                (Workspace desde el build)
	  3. `merge-workspace.lua`        (sube los hijos, borra wrappers)
	  4. `dedupe-workspace.lua`       (colapsa homonimos recursivamente)
	  5. `fix-starterscripts.lua`     (contenedor real de StarterPlayer)
	  6. `sync-scripts.js`            (fuente de los 63 scripts)
	  7. `source-runtime-diff.js`     (PRUEBA: source == runtime)

	El paso 7 es el que importa: si la sesion se revirtio otra vez, el
	informe lo dice y el comando sale con codigo 1. Nunca se da por buena
	una sincronizacion que no haya pasado esa comprobacion.

	Uso:
	  node tools/sync-all.js
*/

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const ROOT = path.join(__dirname, "..");
const CACHE = path.join(ROOT, ".cache");

/** Ejecuta un script Node hijo y propaga su salida. */
function run(script, args = []) {
	console.log("");
	console.log("=== " + path.basename(script) + " " + args.join(" ") + " ===");
	try {
		const out = execFileSync("node", [path.join(__dirname, script), ...args], {
			cwd: ROOT,
			encoding: "utf8",
			stdio: ["ignore", "pipe", "pipe"],
			maxBuffer: 128 * 1024 * 1024,
		});
		console.log(out.trimEnd());
		return true;
	} catch (err) {
		console.log((err.stdout || "").trimEnd());
		console.log("FALLO: " + (err.stderr || err.message).toString().trim());
		return false;
	}
}

/** Ejecuta un snippet Luau en Studio por MCP. */
function lua(file) {
	console.log("");
	console.log("=== " + path.basename(file) + " ===");
	const out = execFileSync("node", [path.join(__dirname, "studio-mcp.js"), "execute_luau", "--file", file], {
		cwd: ROOT,
		encoding: "utf8",
		maxBuffer: 128 * 1024 * 1024,
	});
	console.log(out.trimEnd());
}

function main() {
	fs.mkdirSync(CACHE, { recursive: true });

	// 1. El build tiene que existir antes de importar nada.
	if (!run("sync-workspace.js")) {
		console.log("");
		console.log("Sincronizacion abortada: el build de Rojo fallo.");
		process.exit(1);
	}

	// 1-bis. PURGA DEL MAPA, antes de importar.
	//
	// El orden importa: la fusion y la deduplicacion son incrementales, asi
	// que si el Workspace guarda geometria en una posicion invalida (por
	// ejemplo, toda apilada en el origen), cada pasada posterior descarta la
	// copia correcta que trae la importacion y el mapa nunca se recupera.
	// `reset-map.lua` solo purga cuando detecta ese estado; si el mapa esta
	// sano no toca nada.
	lua(path.join("tools", "reset-map.lua"));

	// El `import_rbxm` necesita la ruta ABSOLUTA del .rbxm.
	const argsFile = path.join(CACHE, "mcp-args.json");
	fs.writeFileSync(
		argsFile,
		JSON.stringify({
			source: { path: path.join(CACHE, "workspace-source.rbxm") },
			parent_path: "game.Workspace",
			target: "edit",
		}),
		"utf8"
	);
	run("studio-mcp.js", ["import_rbxm", "--jsonfile", argsFile]);

	// 3-5. Fusionar, colapsar duplicados y arreglar el contenedor.
	lua(path.join("tools", "merge-workspace.lua"));
	lua(path.join("tools", "dedupe-workspace.lua"));
	lua(path.join("tools", "fix-starterscripts.lua"));

	// 5-bis. COLOCAR LA GEOMETRIA.
	//
	// `import_rbxm` importa las Partes con su tamano pero con
	// `Position = (0,0,0)`. Se verifico con un `.rbxm` minimo de UNA sola
	// Part y XML bien formado (`tools/build-probe-rbxm.js`): la perdida no
	// depende del mapa ni del generador, ocurre dentro de Studio.
	//
	// Por eso, despues de importar, las posiciones se vuelven a colocar desde
	// `default.project.json`, que es la fuente unica. Sin este paso, el mapa
	// "sincronizado" tiene todas las Partes amontonadas en el origen y el
	// juego no es jugable aunque `source-runtime-diff` de PASS.
	run("apply-map-positions.js", ["--run"]);

	// 6. Los 63 scripts. Tarda: cada llamada MCP abre sesion propia.
	if (!run("sync-scripts.js")) {
		console.log("");
		console.log("Sincronizacion incompleta: fallaron scripts.");
		process.exit(1);
	}

	// 7. La prueba de verdad.
	const verified = run("source-runtime-diff.js");

	console.log("");
	if (verified) {
		console.log("SINCRONIZACION COMPLETA: source == runtime.");
	} else {
		console.log("SINCRONIZACION INCOMPLETA: source != runtime (ver docs/runtime-source-diff.md).");
	}
	process.exit(verified ? 0 : 1);
}

main();
