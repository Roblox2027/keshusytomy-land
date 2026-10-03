"use strict";

/*
	runtime-scan.js

	Escaneo de estado RUNTIME real via MCP de Roblox Studio.

	Por que existe de esta forma:
	El fallo historico de este proyecto fue una herramienta que reportaba
	PASS porque habia leido un archivo. Leer el filesystem NO dice nada
	sobre el juego en ejecucion.

	Este script hace lo contrario:
	  1. Habla con `tools/studio-mcp.js` de verdad.
	  2. Si Studio no responde, NO inventa estado: marca BLOCKED.
	  3. Si responde, consulta el arbol y los scripts reales y COMPARA
	     contra el source y reporta la diferencia.

	Nunca devuelve PASS por defecto. El unico PASS legitimo es el de
	Studio contestando.

	Uso:  node tools/diagnostics/runtime-scan.js
	Salida: 0 si Studio respondio, 2 si esta BLOCKED, 1 si hay error.
*/

const fs = require("fs");
const path = require("path");
const cp = require("child_process");

const root = process.cwd();

function mcp(args) {
	try {
		return cp
			.execSync(`node tools/studio-mcp.js ${args}`, {
				cwd: root,
				encoding: "utf8",
				stdio: ["ignore", "pipe", "pipe"]
			})
			.trim();
	} catch (e) {
		return null;
	}
}

const result = {
	timestamp: new Date().toISOString(),
	project: root,
	runtimeVerified: false,
	status: "BLOCKED"
};

// 1. Conectividad MCP. Sin esto no se afirma NADA.
const tools = mcp("list");
if (tools === null) {
	result.reason = "Studio/MCP no responde en el puerto configurado.";
	result.hint =
		"Abrir Roblox Studio con el plugin MCP activo y el proyecto conectado " +
		"(\`rojo serve default.project.json\` o el lugar abierto).";
	console.log(JSON.stringify(result, null, 2));
	console.error("RUNTIME: BLOCKED (Studio no responde)");
	process.exit(2);
}

result.mcpTools = (tools.match(/\n/g) || []).length + 1;
result.status = "CONECTADO";

// 2. Estado real del lugar abierto.
const placeInfo = mcp("get_place_info");
if (placeInfo) {
	try {
		result.placeInfo = JSON.parse(placeInfo);
	} catch (e) {
		result.placeInfo = placeInfo;
	}
}

// 3. Conteo de scripts REALES por comparacion de NOMBRES, no por cantidad.
//
//    Por que nombre y no cantidad: `search_objects "Services"` busca por
//    NOMBRE y devuelve coincidencias parciales en cualquier parte del
//    arbol (por ejemplo `game.Stats...languageServices/async`). Medido:
//    devolvia 4 resultados que no eran servicios, y la conclusion fue
//    "Studio tiene 4 servicios". Era FALSO: tiene 33, los mismos que el
//    source. Un conteo mal implementado produce un FAIL inventado, que
//    es peor que no medir.
//
//    `get_project_structure` con `path` explicito si describe el subarbol
//    real, asi que se comparan conjuntos de nombres: eso si se puede
//    afirmar en un veredicto.
const counts = {};
const folders = [
	["servicios", "game.ServerScriptService.Services"],
	["controllers", "game.StarterPlayer.StarterPlayerScripts.Controllers"],
	["remotes", "game.ReplicatedStorage.Remotes"]
];

// `studio-mcp.js` acepta `--jsonfile <ruta>`. El archivo se escribe SIN
// BOM a proposito: con BOM, `JSON.parse` falla con "Unexpected token" y
// la comprobacion se pierde sin avisar. El archivo es temporal y se
// borra al terminar, para no dejar basura en `.ai/runtime`.
const argFile = path.join(root, ".ai/runtime/_mcp-args.json");
fs.mkdirSync(path.dirname(argFile), { recursive: true });
process.on("exit", () => {
	try {
		fs.unlinkSync(argFile);
	} catch (e) {
		/* si no existe, no hay nada que limpiar */
	}
});

// Total REAL de hijos de una carpeta.
//
//    MEDIDO: el MCP es INCONSISTENTE. Para `ServerScriptService.Services`
//    devuelve `childSummary` con `count`; para
//    `StarterPlayerScripts.Controllers` y `ReplicatedStorage.Remotes` NO lo
//    devuelve. Y cuando lo devuelve, `children` sigue TRUNCADO (3 nombres
//    + el texto "... N more ModuleScript objects"), asi que
//    `children.length` jamas es el total.
//
//    Por eso aqui NO se deduce un numero de un array truncado: se leen
//    las claves que el servidor entrego y, si no hay ninguna fiable, se
//    devuelve null. Un `null` honesto es preferible a un numero falso,
//    porque un numero falso produce un FAIL inventado.
function studioChildCount(instancePath) {
	fs.writeFileSync(
		argFile,
		JSON.stringify({ path: instancePath, maxDepth: 1, scriptsOnly: false }),
		"utf8"
	);
	const raw = mcp(`get_project_structure --jsonfile "${argFile}"`);
	if (raw === null) return null;
	try {
		const parsed = JSON.parse(raw);
		const groups = parsed.childSummary;
		if (Array.isArray(groups)) {
			let total = 0;
			for (const g of groups) total += g.count || 0;
			if (total > 0) return total;
		}
		return null;
	} catch (e) {
		return null;
	}
}


// 4. Contraste con el source. Esto SI se puede hacer sin Studio: son las
//    cifras de disco, y se etiquetan como tales, nunca como runtime.
function countFiles(dir, filter) {
	const full = path.join(root, dir);
	if (!fs.existsSync(full)) return 0;
	let n = 0;
	for (const item of fs.readdirSync(full, { withFileTypes: true })) {
		const p = path.join(full, item.name);
		if (item.isDirectory()) n += countFiles(path.join(dir, item.name), filter);
		else if (filter(p)) n++;
	}
	return n;
}

// 4. Contraste NOMBRE a NOMBRE entre Studio y el source.
//
//    MEDICION PROPIA, IMPORTANTE: `get_project_structure` TRUNCA la lista
//    de hijos. Devuelve 3 nombres mas un pseudo-hijo de texto
//    ("... 30 more ModuleScript objects"). Confiar en ese array daria
//    "4 servicios" y un FAIL inventado: eso hacia la primera version de
//    este script. El total real solo esta en `childSummary.count`.
//
//    Ademas el source se llama `XService.lua` y en Studio `XService`, asi
//    que hay que quitar la extension antes de comparar.
function namesIn(dir, filter) {
	const full = path.join(root, dir);
	if (!fs.existsSync(full)) return [];
	const out = [];
	for (const item of fs.readdirSync(full, { withFileTypes: true })) {
		const p = path.join(full, item.name);
		if (item.isDirectory()) out.push(...namesIn(path.join(dir, item.name), filter));
		else if (filter(p)) out.push(item.name.replace(/\.lua$/, ""));
	}
	return out;
}

const sourceServices = namesIn("src/ServerScriptService", (f) => f.endsWith("Service.lua"));
const sourceControllers = namesIn("src/StarterPlayer", (f) => /Controller\.lua$/.test(f));

result.sourceFiles = {
	services: sourceServices.length,
	controllers: sourceControllers.length,
	shared: countFiles("src/ReplicatedStorage", (f) => f.endsWith(".lua"))
};

// Existencia real de cada modulo del source dentro de su carpeta.
// `search_objects` busca por NOMBRE en todo el arbol, asi que solo se
// acepta el acierto cuya ruta caiga exactamente bajo el padre esperado:
// un `CoreService` en otra carpeta no cuenta.
function presentIn(folder, name) {
	const raw = mcp(`search_objects ${name}`);
	if (raw === null) return null;
	try {
		const parsed = JSON.parse(raw);
		if (!Array.isArray(parsed.results)) return false;
		return parsed.results.some((r) => r.path === folder + "." + name);
	} catch (e) {
		return null;
	}
}

function checkFolder(folder, names) {
	const missing = [];
	let ilegible = false;
	for (const name of names) {
		const ok = presentIn(folder, name);
		if (ok === null) ilegible = true;
		else if (ok === false) missing.push(name);
	}
	return { missing: missing, ilegible: ilegible };
}

const serviceCheck = checkFolder("game.ServerScriptService.Services", sourceServices);
const controllerCheck = checkFolder(
	"game.StarterPlayer.StarterPlayerScripts.Controllers",
	sourceControllers
);

// Conteos de Studio. `null` significa "el MCP no entrego un total fiable",
// NO cero. Ver la nota de `studioChildCount`: el veredicto NO depende de
// estos numeros, depende de la comprobacion nombre a nombre de arriba.
result.studioObjects = {
	servicios: studioChildCount("game.ServerScriptService.Services"),
	controllers: studioChildCount("game.StarterPlayer.StarterPlayerScripts.Controllers"),
	remotes: studioChildCount("game.ReplicatedStorage.Remotes"),
	notaConteos:
		"null = el MCP no entrego childSummary para esa carpeta. No es 0. " +
		"El veredicto se basa en la verificacion nombre a nombre, no aqui."
};

result.diff = {
	serviciosAusentesEnStudio: serviceCheck.missing,
	controllersAusentesEnStudio: controllerCheck.missing
};


// 5. Veredicto.
//    PASS    Studio contesto y NINGUN modulo del source falta en Studio.
//    FAIL    Studio contesto y hay modulos del source ausentes: se nombran.
//    BLOCKED Studio no respondio o no permitio leer el arbol: no se
//            inventa nada. "No se pudo comprobar" y "se comprobo que esta
//            mal" son cosas distintas y confundirlas fue el fallo historico
//            de este repositorio.
const ilegible = serviceCheck.ilegible || controllerCheck.ilegible;
const ausentes = result.diff.serviciosAusentesEnStudio.concat(
	result.diff.controllersAusentesEnStudio
);

if (ilegible) {
	result.runtimeVerified = false;
	result.verdict =
		"BLOCKED: Studio no permitio consultar uno o mas modulos. " +
		"Sin lectura completa NO se afirma nada sobre el runtime.";
} else if (ausentes.length > 0) {
	result.runtimeVerified = true;
	result.verdict =
		"FAIL: " +
		ausentes.length +
		" modulo(s) del source NO existen en el lugar abierto en Studio: [" +
		ausentes.join(", ") +
		"]. El source describe un estado que Studio no tiene.";
} else {
	result.runtimeVerified = true;
	result.verdict =
		"PASS: los " +
		sourceServices.length +
		" servicios y " +
		sourceControllers.length +
		" controllers del source existen en el lugar abierto en Studio.";
}


fs.mkdirSync(path.join(root, ".ai/runtime"), { recursive: true });
fs.writeFileSync(
	path.join(root, ".ai/runtime/runtime-scan.json"),
	JSON.stringify(result, null, 2),
	"utf8"
);

console.log(JSON.stringify(result, null, 2));

// Codigo de salida: 0 verificado, 1 FAIL real, 2 BLOCKED.
// Se distinguen porque "no se pudo comprobar" y "se comprobo que esta
// mal" no son lo mismo, y confundirlos fue el fallo historico.
if (!result.runtimeVerified) {
	console.error("RUNTIME: " + result.verdict);
	process.exit(2);
}

if (result.verdict.startsWith("FAIL")) {
	console.error("RUNTIME: " + result.verdict);
	process.exit(1);
}

console.log("RUNTIME: " + result.verdict);
