"use strict";

/*
	source-runtime-diff.js
	Compara el arbol que produce `rojo build` con el DataModel REAL de
	Roblox Studio.

	POR QUE EXISTE
	--------------
	El reporte anterior daba SOURCE ~170 instancias y RUNTIME 6, y la
	causa era que el codigo si llega a Studio pero la GEOMETRIA no. Un
	conteo global no dice QUE falta: hace falta comparar rutas una a
	una. Este script produce exactamente esa lista.

	COMO
	----
	1. `rojo build` genera el arbol esperado y se leen sus `<Item>`.
	2. `tools/dump-paths.lua` se ejecuta en Studio por MCP y devuelve
	   `ruta<TAB>ClassName` de cada instancia real.
	3. Se comparan los conjuntos de rutas.

	Se comparan RUTAS, no solo conteos: un bloque de mas o un mundo
	entero ausente se ven en la lista, no en una cifra agregada.

	Uso:  node tools/source-runtime-diff.js
*/

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const ROOT = path.join(__dirname, "..");
const ROJO = path.join(ROOT, "rojo", "rojo.exe");
const CACHE = path.join(ROOT, ".cache");
const BUILD = path.join(CACHE, "diff-build.rbxlx");

/**
 * Contenedores que Studio anade por su cuenta y que el proyecto no
 * declara. No son divergencia: son del motor.
 *
 * `ServerStorage`, `SoundService` y `Lighting` existen en TODOS los
 * places de Roblox, vacios si no se usa nada. No tiene sentido exigirlos
 * en `default.project.json`: Rojo los crearia como objetos muertos que
 * nadie referencia.
 *
 * `StarterCharacterScripts` es el contenedor de scripts de personaje; el
 * juego no coloca nada dentro, asi que su presencia en Studio y su
 * ausencia en el proyecto son la misma realidad.
 *
 * `Terrain` y `Camera` se comprueban por SEGMENTO, no por raiz: cuelgan
 * de `Workspace`, que si declara el proyecto, pero las instancias no.
 */
const ENGINE_OWNED = new Set([
	"Terrain",
	"Camera",
	"SoundService",
	"Lighting",
	"ServerStorage",
	"StarterCharacterScripts",
]);

const RUNTIME_ONLY_CONTAINERS = new Set(["Border", "Blocks", "Zones", "Routes", "Hazards", "Decoration", "CentralStructure", "Keshusy"]);

/**
 * Categorias de instancias que existen en Studio pero NO en el rojo source.
 * No son divergencia: el pipeline las crea INTENTIONALMENTE por MCP.
 *
 * `isRuntimeImported` reconoce dos patrones:
 *
 * 1. World geometry: `Workspace.Worlds.{World}.(Border|Blocks|Zones|...).{hijo}`
 *    El source declara los folders vacios; los Parts hijos (Edge_*, Deco_*, Rim*)
 *    se importan desde .rbxmx captures por `tools/import-worlds-only.js`.
 *
 * 2. HUD: `StarterGui.KeshusyHUD.*`
 *    El source declara el HUD en `default.project.json`, pero `sync-hud.js`
 *    lo DESTRUYE y RECONSTRUYE instancia-a-instancia desde `tools/hud.js`
 *    al iniciar. Cualquier diferencia interna es del generador, no del build.
 */
function isRuntimeImported(path) {
	const parts = path.split(".");
	if (parts[0] === "StarterGui" && parts[1] === "KeshusyHUD") return true;
	if (parts[0] === "Workspace" && parts[1] === "Worlds" && parts.length > 3 && RUNTIME_ONLY_CONTAINERS.has(parts[3])) {
		return true;
	}
	return false;
}

/**
 * Diferencias de CLASE que NO son divergencia.
 *
 * MEDIDO: Rojo escribe `StarterGui` como un `Folder` plano, porque asi lo
 * declara el proyecto. El motor lo convierte en el `StarterGui` REAL al
 * arrancar: es un contenedor del juego, no un Folder cualquiera. Lo mismo
 * ocurre con `StarterPlayer`, que Rojo trata como Carpeta y Roblox como
 * `StarterPlayer`.
 *
 * No se "arregla" declarando `StarterGui` con su clase real en el proyecto:
 * Rojo no lo permite (el servicio ya existe) y el resultado seria el mismo
 * arbol con una forma que el motor va a cambiar igualmente. Exigir aqui la
 * igualdad literal convierte una diferencia SEMANTICA del motor en un FAIL
 * permanente, y un FAIL permanente es peor que ninguno: entrena a ignorar
 * el informe entero.
 *
 * La lista se limita a lo medido. Si aparece una diferencia de clase nueva,
 * se investiga: puede ser un defecto real de construccion.
 */
const CLASS_EQUIVALENT = new Map([
	["StarterGui", new Set(["Folder", "StarterGui"])],
	["StarterPlayer", new Set(["Folder", "StarterPlayer"])],
]);

/**
 * Lee el nombre de un Item dentro de su bloque `<Properties>`.
 *
 * Rojo escribe siempre `<string name="Name">X</string>`. Se limita la
 * busqueda al bloque de propiedades del propio Item: buscar en todo el
 * subarbol devuelve el nombre del PRIMER nieto, no el del Item, y
 * acabaria con todos los nodos mal nombrados.
 */
function nameOf(block) {
	const propsEnd = block.indexOf("</Properties>");
	const props = propsEnd === -1 ? block : block.slice(0, propsEnd);
	const m = /<string name="Name">([^<]*)<\/string>/.exec(props);
	return m ? m[1] : "?";
}

/**
 * Parsea el `.rbxlx` de Rojo a un mapa `ruta -> ClassName`.
 *
 * Recursivo y explicito: se avanza el indice, se lee el `<Item>` de la
 * cabecera, se consume su bloque `<Properties>` y luego sus hijos hasta
 * el `</Item>` que lo cierra. No se busca "el proximo `<Item>`" con una
 * expresion regular porque los Items se anidan y el greediness haria que
 * un hijo de un hijo se colgara del padre equivocado: justo el error
 * que hace que un bloque dentro de `Forest.Blocks` aparezca como hijo
 * directo de `Forest`.
 */
function parseItem(xml, start) {
	const open = /<Item class="([^"]+)"[^>]*>/.exec(xml.slice(start));
	if (!open) throw new Error("Item mal formado en " + start);

	const className = open[1];
	let i = start + open[0].length;

	// Bloque <Properties> (puede no existir).
	let name = null;
	const props = xml.indexOf("<Properties>", i);
	if (props !== -1 && props < xml.indexOf("</Item>", i)) {
		const propsEnd = xml.indexOf("</Properties>", props);
		const block = xml.slice(props, propsEnd);
		const nm = /<string name="Name">([^<]*)<\/string>/.exec(block);
		if (nm) name = nm[1];
		i = propsEnd + "</Properties>".length;
	}

	const children = [];
	while (i < xml.length) {
		const rest = xml.slice(i);
		if (rest.startsWith("</Item>")) {
			i += "</Item>".length;
			break;
		}
		if (rest.startsWith("<Item ")) {
			const child = parseItem(xml, i);
			children.push(child);
			i = child.end;
			continue;
		}
		i += 1;
	}

	return { className, name, children, end: i };
}

function sourcePaths() {
	fs.mkdirSync(CACHE, { recursive: true });
	execFileSync(ROJO, ["build", "default.project.json", "-o", BUILD], {
		cwd: ROOT,
		encoding: "utf8",
		stdio: ["ignore", "pipe", "pipe"],
	});
	const xml = fs.readFileSync(BUILD, "utf8");

	const map = new Map();

	const walk = (node, prefix) => {
		if (node.name === null) return;
		const path = prefix === "" ? node.name : prefix + "." + node.name;
		map.set(path, node.className);
		for (const c of node.children) walk(c, path);
	};

	// Rojo NO envuelve el `.rbxlx` en un unico Item raiz: escribe los
	// servicios (ReplicatedStorage, ServerScriptService, Workspace...)
	// como Items HERMANOS en el nivel superior. Por eso no se puede
	// parsear "el primer Item" y esperar que contenga todo el arbol:
	// habria que recorrer todos los Items de nivel superior. Leer solo
	// el primero daba SOURCE = 0 instancias.
	let i = xml.indexOf("<Item ");
	while (i !== -1) {
		const node = parseItem(xml, i);
		walk(node, "");
		i = node.end;
		// Se salta el bloque `<Ref>` y cualquier seccion que siga.
		const next = xml.indexOf("<Item ", node.end);
		if (next === -1) break;
		i = next;
	}
	return map;
}

/** Ejecuta una herramienta MCP y devuelve su texto. */
function mcp(tool, ...rest) {
	const out = execFileSync("node", [path.join(__dirname, "studio-mcp.js"), tool, ...rest], {
		cwd: ROOT,
		encoding: "utf8",
		maxBuffer: 64 * 1024 * 1024,
	});
	const parsed = JSON.parse(out);
	if (parsed.success === false) {
		throw new Error("MCP fallo: " + (parsed.error || JSON.stringify(parsed)));
	}
	return parsed;
}


/** Rutas del DataModel real, consultadas a Studio por MCP. */
function runtimePaths() {
	const res = mcp("execute_luau", "--file", path.join("tools", "dump-paths.lua"));
	const lines = res.returnValue.split("\n");
	const map = new Map();
	for (const line of lines) {
		if (line.startsWith("TOTAL=")) continue;
		const idx = line.indexOf("\t");
		if (idx === -1) continue;
		map.set(line.slice(0, idx), line.slice(idx + 1));
	}
	return { map, total: Number(lines[0].replace("TOTAL=", "")) };
}

function main() {
	const src = sourcePaths();
	const rt = runtimePaths();

	// Una ruta es "del motor" si CUALQUIERA de sus segmentos es un
	// contenedor que Studio crea por su cuenta. No basta con mirar el
	// primero: `Workspace.Camera` y `Workspace.Terrain` empiezan por
	// `Workspace`, que si lo declara el proyecto, pero las instancias
	// no. Sin esto el informe arrastraba 2 diferencias permanentes.
	const isEngineOwned = (p) => p.split(".").some((seg) => ENGINE_OWNED.has(seg));

	/**
	 * Padre de una ruta con puntos. Para un SERVICIO de primer nivel
	 * (`StarterGui`) no hay padre: el nombre es el propio segmento, porque
	 * es el contenedor del motor el que difiere, no una carpeta dentro.
	 */
	const tailOf = (p) => {
		const parts = p.split(".");
		return parts.length === 1
			? { leaf: parts[0], parent: parts[0] }
			: { leaf: parts[parts.length - 1], parent: parts[parts.length - 2] };
	};

	/**
	 * Una diferencia de clase es REAL salvo que el padre sea un contenedor
	 * del motor cuya clase Rojo no puede reproducir.
	 */
	const isSemanticClassDiff = (p, sourceCls, runtimeCls) => {
		const { parent } = tailOf(p);
		const allowed = CLASS_EQUIVALENT.get(parent);
		return allowed !== undefined && allowed.has(sourceCls) && allowed.has(runtimeCls);
	};

	const missing = []; // esta en SOURCE, no en RUNTIME
	const extra = []; // esta en RUNTIME, no en SOURCE
	const classMismatch = [];
	const semanticDiffs = [];

	for (const [path, cls] of src) {
		if (!rt.map.has(path)) missing.push(`${path} [${cls}]`);
		else if (rt.map.get(path) !== cls) {
			const line = `${path}: source=${cls} runtime=${rt.map.get(path)}`;
			if (isSemanticClassDiff(path, cls, rt.map.get(path))) semanticDiffs.push(line);
			else classMismatch.push(line);
		}
	}
	const rtOnly = [];
	for (const [path, cls] of rt.map) {
		if (!src.has(path) && !isEngineOwned(path) && !isRuntimeImported(path)) extra.push(`${path} [${cls}]`);
		else if (!src.has(path) && isRuntimeImported(path)) rtOnly.push(`${path} [${cls}]`);
	}

	const report = [];
	report.push("# SOURCE <-> RUNTIME");
	report.push("");
	report.push(`SOURCE (rojo build) : ${src.size} instancias`);
	report.push(`RUNTIME (Studio MCP): ${rt.total} instancias`);
	report.push("");
	report.push(`FALTAN EN STUDIO (en source, no en runtime): ${missing.length}`);
	report.push(`SOBRAN EN STUDIO (en runtime, no en source): ${extra.length}`);
	report.push(`CLASE DISTINTA                          : ${classMismatch.length}`);
	report.push(`CLASE EQUIVALENTE (motor)               : ${semanticDiffs.length}`);
	report.push(`RUNTIME-ONLY (ignorado, importado por MCP): ${rtOnly.length}`);
	report.push("");

	if (missing.length) {
		report.push("## Faltan en Studio");
		report.push("");
		for (const m of missing) report.push(`- ${m}`);
		report.push("");
	}
	if (extra.length) {
		report.push("## Sobran en Studio");
		report.push("");
		for (const e of extra) report.push(`- ${e}`);
		report.push("");
	}
	if (classMismatch.length) {
		report.push("## Clase distinta");
		report.push("");
		for (const c of classMismatch) report.push(`- ${c}`);
		report.push("");
	}
	if (semanticDiffs.length) {
		// No son divergencia, pero se LISTAN: si aparece una nueva, hay que
		// mirar por que. Ocultarlas del todo seria perder esa senal.
		report.push("## Clase equivalente (el motor la cambia, no es un defecto)");
		report.push("");
		for (const c of semanticDiffs) report.push(`- ${c}`);
		report.push("");
	}
	if (rtOnly.length) {
		report.push("## Runtime-only (importado por MCP, no es divergencia)");
		report.push("");
		report.push("Estas instancias existen en Studio pero no en el build de Rojo. Son importadas por MCP al iniciar:");
		report.push("- World geometry: parts bajo `Worlds.*.Border`, `Worlds.*.Blocks`, `Worlds.*.Zones` (importados desde .rbxmx).");
		report.push("- HUD: todo bajo `StarterGui.KeshusyHUD` (regenerado por `sync-hud.js`).");
		report.push("");
		report.push("Muestra las primeras 20:");
		report.push("");
		for (let i = 0; i < Math.min(rtOnly.length, 20); i++) report.push(`- ${rtOnly[i]}`);
		if (rtOnly.length > 20) report.push(`- ... (${rtOnly.length - 20} mas)`);
		report.push("");
	}

	const out = path.join(ROOT, "docs", "runtime-source-diff.md");
	fs.mkdirSync(path.dirname(out), { recursive: true });
	fs.writeFileSync(out, report.join("\n"), "utf8");

	console.log(report.slice(0, 7).join("\n"));
	console.log("informe escrito en docs/runtime-source-diff.md");
	const diverged = missing.length + extra.length + classMismatch.length;
	console.log(diverged === 0 ? "RESULTADO: PASS" : `RESULTADO: DIVERGE (${diverged} diferencias, ${rtOnly.length} runtime-only)`);
	process.exit(diverged === 0 ? 0 : 1);
}

main();
