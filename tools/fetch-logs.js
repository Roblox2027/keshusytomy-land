"use strict";

/*
	fetch-logs.js
	Descarga el log del playtest por MCP y lo filtra.

	POR QUE EXISTE
	--------------
	`get_runtime_logs` devuelve TODO: el plugin de Rojo emite cientos de
	entradas `INFO` por cada sincronizacion y entierran los errores reales
	del juego. Volcarlas tal cual a consola no sirve de nada.

	Este script deja pasar solo lo que importa:
	  * cualquier entrada `ERR` (o `WARN`) que NO venga de Rojo, y
	  * un resumen por script.

	Uso: node tools/fetch-logs.js [filtro]
	      el filtro es un substring opcional sobre el mensaje.
*/

const { execFileSync } = require("child_process");
const path = require("path");

const ROOT = path.join(__dirname, "..");

function mcp(tool, ...rest) {
	const out = execFileSync("node", [path.join(__dirname, "studio-mcp.js"), tool, ...rest], {
		cwd: ROOT,
		encoding: "utf8",
		maxBuffer: 64 * 1024 * 1024,
	});
	return JSON.parse(out);
}

const needle = process.argv[2] || "";

// El MCP devuelve un objeto por instancia conectada; se concatenan todas.
let raw;
try {
	raw = mcp("get_runtime_logs");
} catch (e) {
	console.log("SIN LOGS: " + e.message);
	process.exit(0);
}

const buckets = Array.isArray(raw) ? raw : [raw];

const isRojo = (s) => /Rojo|RbxDom|ChangeBatcher|rbxdom|Plugin/i.test(s);
const isNoise = (s) => /Stack Begin|Stack End|^\s*$/.test(s);

const errors = [];
const warnings = [];
const counts = new Map();

for (const b of buckets) {
	for (const e of b.entries || []) {
		const msg = String(e.message || "");
		if (isNoise(msg) || isRojo(msg)) continue;
		const level = String(e.level || "").toUpperCase();
		// El nombre del script suele venir en el mensaje; se usa como clave
		// para agrupar y no repetir 200 veces la misma linea.
		const m = /Script '([^']+)'/.exec(msg) || /^([A-Za-z0-9_.]+)\.lua/.exec(msg);
		const who = m ? m[1] : "(sin script)";
		counts.set(who, (counts.get(who) || 0) + 1);
		const record = { level, who, msg };
		if (level === "ERR") errors.push(record);
		else if (level === "WARN") warnings.push(record);
		else if (needle && msg.includes(needle)) errors.push(record);
	}
}

console.log("=== ERRORES (" + errors.length + ") ===");
const seen = new Set();
for (const e of errors) {
	const key = e.who + "|" + e.msg;
	if (seen.has(key)) continue;
	seen.add(key);
	console.log("[" + e.who + "] " + e.msg);
}

console.log("\n=== WARNINGS (" + warnings.length + ") ===");
const seenW = new Set();
for (const e of warnings) {
	const key = e.who + "|" + e.msg;
	if (seenW.has(key)) continue;
	seenW.add(key);
	console.log("[" + e.who + "] " + e.msg);
}

console.log("\n=== MENSAJES POR SCRIPT ===");
for (const [who, n] of [...counts].sort((a, b) => b[1] - a[1])) {
	console.log(String(n).padStart(4) + "  " + who);
}