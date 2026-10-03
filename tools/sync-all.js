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

/**
 * Igual que `run`, pero con variables de entorno para el hijo.
 *
 * Existe para que `sync-workspace.js` pueda extraer OTRO subarbol (el HUD de
 * `StarterGui`) sin duplicar su recorte de XML. Se reutiliza el codigo que ya
 * funciona en lugar de copiarlo: dos extractores del mismo formato divergen en
 * cuanto uno corrige un caso limite y el otro no, y entonces el fallo aparece
 * solo en una de las ramas y cuesta el doble de tiempo.
 *
 * @param {{[string]: string}} env variables a inyectar
 * @param {string} script nombre dentro de tools/
 * @param {string[]} args
 * @returns {boolean} exito
 */
function runWithEnv(env, script, args = []) {
	console.log("");
	console.log("=== " + path.basename(script) + " " + args.join(" ") + " ===");
	try {
		const out = execFileSync("node", [path.join(__dirname, script), ...args], {
			cwd: ROOT,
			encoding: "utf8",
			stdio: ["ignore", "pipe", "pipe"],
			env: Object.assign({}, process.env, env),
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

	// 2-bis. EL HUD DE STARTERGUI.
	//
	// El paso anterior solo importa `Workspace`. El HUD vive en `StarterGui`,
	// y sin este paso se quedaba solo en el SOURCE: `source-runtime-diff`
	// reportaba 58 interfaces de menos y el script acababa en DIVERGE sin que
	// nada explicara por que. El mapa estaba sincronizado; faltaba la rama que
	// la herramienta no miraba.
	//
	// Va DESPUES del Workspace y ANTES del diff final: ese diff es el que
	// declara completa la sincronizacion, y para que pueda decirlo tiene que
	// haber recibido las dos ramas.
	const guiArgsFile = path.join(CACHE, "mcp-args-gui.json");
	fs.writeFileSync(
		guiArgsFile,
		JSON.stringify({
			source: { path: path.join(CACHE, "startergui-source.rbxm") },
			parent_path: "game.StarterGui",
			target: "edit",
		}),
		"utf8"
	);
	// La extraccion REUTILIZA `sync-workspace.js` mediante variables de
	// entorno en vez de duplicar su recorte de XML: dos copias del mismo
	// parser divergen en cuanto una corrige un caso y la otra no.
	runWithEnv(
		{
// Rojo NO emite un <Item class="StarterGui">: emite un Folder
// llamado StarterGui colgando de la raiz del build. Extraer por la
// clase del servicio fallaba con "No se encontro".
SYNC_CLASS: "Folder",
SYNC_NAME: "StarterGui",
SYNC_MATCH: "StarterGui",
SYNC_OUT: path.join(CACHE, "startergui-source.rbxm"),
},
		"sync-workspace.js"
	);
	run("studio-mcp.js", ["import_rbxm", "--jsonfile", guiArgsFile]);

	// El `import_rbxm` deja el .rbxm dentro de una carpeta envoltorio
	// (`StarterGuiSource`). Para el Workspace lo resuelve `merge-workspace.lua`;
	// aqui no habia paso equivalente y cada sincronizacion acumulaba una copia
	// mas, con los RemoteEvents duplicados dentro de StarterGui donde no los
	// busca nadie.
	lua(path.join("tools", "merge-startergui.lua"));


	// 3-5. Fusionar, colapsar duplicados y arreglar el contenedor.
	lua(path.join("tools", "merge-workspace.lua"));
	lua(path.join("tools", "dedupe-workspace.lua"));
	// El plugin de Rojo esta conectado a esta sesion y sincroniza por su
	// cuenta, mientras `sync-scripts.js` escribe a mano. Los dos caminos
	// crean instancias y el segundo deja un HOMONIMO. Sin esta pasada,
	// `Services.VisualService` (y antes `CoreRules` y `CoreAction`)
	// acababan duplicados y `FindFirstChild` podia devolver el
	// equivocado sin dar ningun error.
	lua(path.join("tools", "dedupe-code.lua"));
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

	// 5-ter. AJUSTAR LAS PROPIEDADES DE LOS SERVICIOS.
	//
	// `Lighting` NO se importa: es un Servicio, no un modelo, asi que el
	// camino `import_rbxm` que usa el resto no lo cubre. Sus ajustes (el
	// `ColorCorrectionEffect` que da el tinte y el contraste de la escena)
	// se aplican con el plugin MCP en modo edicion, que si puede escribir en
	// el DataModel.
	//
	// Sin este paso, `source-runtime-diff` reportaba el efecto como FALTANTE
	// en Studio una y otra vez y `sync-all` nunca llegaba a PASS, aunque el
	// operador rerunara el comando diez veces.
	lua(path.join("tools", "sync-lighting.lua"));

	// 6. Los 63 scripts. Tarda: cada llamada MCP abre sesion propia.
	if (!run("sync-scripts.js")) {
		console.log("");
		console.log("Sincronizacion incompleta: fallaron scripts.");
		process.exit(1);
	}

	// 6-bis. Segunda pasada de duplicados, DESPUES de escribir los scripts.
	//
	// La de antes no basta: el plugin de Rojo esta conectado y sincroniza
	// por su cuenta, asi que puede crear un homonimo en cualquier momento,
	// incluso entre los pasos 3-5 y el 6. Ejecutandolo aqui, ya con los
	// scripts en su sitio, la limpieza pisa a la ultima carrera y el paso 7
	// mide un arbol ya limpio. Sin esta segunda pasada, `CoreRules` quedaba
	// duplicado y `source-runtime-diff` no llegaba a PASS.
	lua(path.join("tools", "dedupe-code.lua"));

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
