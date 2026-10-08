"use strict";

/**
 * Auditor de fisica estatica del mapa (FISICA DE PARTES ANCLADAS).
 *
 * Lee `default.project.json` y verifica que toda pieza fisica del mapa
 * (Part, SpawnLocation, WedgePart, CylinderPart, BallPart, UnionOperation)
 * tenga `Anchored: true`. Una pieza sin anclar cae por gravedad: es el
 * origen del reporte "el mapa se desarma y cae al vacio".
 *
 * Tambien verifica:
 *   - `StreamingEnabled` es false en Workspace (sin streaming = todo el
 *     mapa esta disponible al instante).
 *   - Ningun archivo fuente (.js o .lua) escribe `Anchored = false` /
 *     `Anchored: false` sobre piezas del mapa.
 *
 * Lee `tools/worlds.js` para obtener WORLD_IDS, por lo que el auditor
 * y el generador usan la MISMA lista de mundos.
 *
 * Uso:  node tools/audit-map-physics.js
 *
 * Escribe `tools/.map-physics-summary.json` y sale con codigo 1 si
 * hay partes sin anclar o StreamingEnabled activado.
 */

const fs = require("fs");
const path = require("path");
const Worlds = require("./worlds");

const ROOT = path.join(__dirname, "..");
const PROJECT = path.join(ROOT, "default.project.json");
const SUMMARY = path.join(__dirname, ".map-physics-summary.json");

const WORLD_IDS = Worlds.WORLD_IDS;

// Todas las clases de Roblox que son fisicamente simulables como piezas
// del mapa. Folder, Model, SpawnLocation tambien se incluyen para SpawnLocation.
const PHYSICAL_CLASSES = new Set([
	"Part",
	"SpawnLocation",
	"WedgePart",
	"CornerWedgePart",
	"CylinderPart",
	"BallPart",
	"UnionOperation",
	"MeshPart",
]);

let totalParts = 0;
let anchoredTrue = 0;
let anchoredFalse = 0;
let anchoredUnset = 0;
const problems = [];

/**
 * Recorre el arbol de default.project.json en orden plano.
 * @param {object} node
 * @param {string} prefix
 * @param {Array} out
 */
function flatten(node, prefix, out) {
	if (!node || typeof node !== "object") return;
	for (const key of Object.keys(node)) {
		if (key.startsWith("$")) continue;
		const child = node[key];
		if (child && typeof child === "object") {
			const here = prefix ? prefix + "." + key : key;
			out.push({ path: here, node: child });
			flatten(child, here, out);
		}
	}
}

const project = JSON.parse(fs.readFileSync(PROJECT, "utf8"));

const flat = [];
flatten(project.tree, "", flat);

// --- 1. Audit fisico por pieza del mapa ---
for (const entry of flat) {
	const cls = entry.node.$className;
	const props = entry.node.$properties;
	const path_ = entry.path;

	if (!cls || !PHYSICAL_CLASSES.has(cls)) continue;

	totalParts++;

	const worldMatch = path_.match(/Workspace\.Worlds\.(\w+)/);
	const worldId = worldMatch ? worldMatch[1] : "(lobby)";
	const name = path_.split(".").pop();

	if (!props) {
		anchoredUnset++;
		problems.push({ path: path_, class: cls, issue: "sin $properties", world: worldId });
		continue;
	}

	if (props.Anchored === true) {
		anchoredTrue++;
	} else if (props.Anchored === false) {
		anchoredFalse++;
		problems.push({
			path: path_, class: cls, issue: "Anchored=false", world: worldId, name: name,
			position: props.Position,
		});
	} else {
		anchoredUnset++;
		problems.push({
			path: path_, class: cls, issue: "Anchored no definido", world: worldId, name: name,
			position: props.Position,
		});
	}
}

// --- 2. StreamingEnabled ---
const workspaceEntry = flat.find((e) => e.path === "Workspace");
const streamingEnabled = workspaceEntry && workspaceEntry.node.$properties && workspaceEntry.node.$properties.StreamingEnabled;

const streamingOk = streamingEnabled === false;

// --- 3. Source-level: buscar Anchored = false / Anchored: false en .js y .lua ---
// Se excluyen comentarios y el propio auditor (que menciona el patron en su doc).
const sourceFiles = [];
function collectSource(dir) {
	if (!fs.existsSync(dir)) return;
	for (const f of fs.readdirSync(dir, { withFileTypes: true })) {
		if (f.isDirectory()) {
			collectSource(path.join(dir, f.name));
		} else if (f.name.endsWith(".js") || f.name.endsWith(".lua")) {
			sourceFiles.push(path.join(dir, f.name));
		}
	}
}
collectSource(path.join(ROOT, "tools"));
collectSource(path.join(ROOT, "src"));

function stripStrings(line, ext) {
	if (ext === ".js") {
		return line.replace(/'[^']*'/g, "''").replace(/"[^"]*"/g, '""');
	}
	if (ext === ".lua") {
		return line.replace(/"[^"]*"/g, '""').replace(/'[^']*'/, "''");
	}
	return line;
}
function isComment(line, ext) {
	const trimmed = line.trim();
	if (ext === ".js") {
		return trimmed.startsWith("//") || trimmed.startsWith("*") || trimmed.startsWith("/*");
	}
	if (ext === ".lua") {
		return trimmed.startsWith("--");
	}
	return false;
}

const sourceProblems = [];
for (const file of sourceFiles) {
	const rel = path.relative(ROOT, file);
	// Saltar el propio auditor y temporales
	if (rel.startsWith("tools/audit-map-physics.js") || rel.startsWith("tools/tmp_")) continue;

		const ext = path.extname(file);
		const lines = fs.readFileSync(file, "utf8").split("\n");
		for (let i = 0; i < lines.length; i++) {
			const line = lines[i];
			if (isComment(line, ext)) continue;
			const stripped = stripStrings(line, ext);
			if (/Anchored\s*[:=]\s*false/.test(stripped)) {
				sourceProblems.push({ file: rel, line: i + 1, text: line.trim() });
			}
		}
}

// --- Reporte ---
console.log("AUDIT DE FISICA ESTATICA DEL MAPA");
console.log("--------------------------------------------------");
console.log("Piezas fisicas totales: " + totalParts);
console.log("  Anchored = true:  " + anchoredTrue);
console.log("  Anchored = false: " + anchoredFalse);
console.log("  Anchored unset:   " + anchoredUnset);
console.log("");
console.log("StreamingEnabled: " + streamingEnabled + " -> " + (streamingOk ? "OK (false)" : "FAIL (debe ser false)"));
console.log("");
console.log("Problemas de fisica en partes del mapa: " + problems.length);
for (const p of problems) {
	console.log("  " + p.world + ": " + p.path + " (" + p.class + ") -> " + p.issue);
	if (p.position) console.log("    Position: " + JSON.stringify(p.position));
}
console.log("");
console.log("Source-level Anchored=false en .js/.lua: " + sourceProblems.length);
for (const s of sourceProblems) {
	console.log("  " + s.file + ":" + s.line + " -> " + s.text);
}

const summary = {
	timestamp: new Date().toISOString(),
	totalParts: totalParts,
	anchoredTrue: anchoredTrue,
	anchoredFalse: anchoredFalse,
	anchoredUnset: anchoredUnset,
	streamingEnabled: streamingEnabled,
	streamingOk: streamingOk,
	problems: problems,
	sourceProblems: sourceProblems,
	perWorld: {},
	overall: "PASS",
};

// Per-world breakdown
for (const id of WORLD_IDS) {
	const worldProblems = problems.filter((p) => p.world === id);
	summary.perWorld[id] = {
		unanchored: worldProblems.length,
	};
}

if (problems.length > 0 || !streamingOk || sourceProblems.length > 0) {
	summary.overall = "FAIL";
}

fs.writeFileSync(SUMMARY, JSON.stringify(summary, null, 2) + "\n");
console.log("");
console.log("Resumen: " + SUMMARY);
console.log("");

if (summary.overall === "PASS") {
	console.log("PHYSICS AUDIT: PASS (UNANCHORED_STATIC_PARTS = 0)");
} else {
	console.log("PHYSICS AUDIT: FAIL");
}

process.exitCode = summary.overall === "PASS" ? 0 : 1;
