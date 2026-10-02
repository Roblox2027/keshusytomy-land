"use strict";

/*
	analyze.js
	Analizador Luau CON entorno de Roblox.

	POR QUE EXISTE
	--------------
	`luau-analyze.exe` en modo standalone no conoce Roblox. Con el codigo
	 tal cual reportaba 511 lineas, de las cuales la mayor parte eran
	`Unknown global 'warn'`, `Unknown global 'task'`, `Unknown type
	'RBXScriptSignal'` y sus cascadas (`Type 'unknown' does not have key
	'FindFirstChild'`). NO eran 511 defectos: habia una sola causa raiz.

	Se descartoistorcer el codigo para callar al analizador, que es
	exactamente lo que la regla de falsos positivos prohibe, y en su
	lugar se corrigio la CONFIGURACION del analizador:

	  - este build NO lee `.luaurc` (aliases y `lint` se ignoran;
	    comprobado empiricamente con `UnknownGlobal:false`).
	  - este build NO soporta la palabra clave `declare`.
	  - las dos vias que SI funcionan son: declarar `export type` y
	    asignar globales en el ambito superior, siempre dentro del
	    MISMO archivo que se analiza.

	ASI QUE: se concatena `tools/roblox-definitions/RobloxEnvironment.lua`
	delante de cada archivo real, se analiza el conjunto, y se reportan
	SOLO los diagnosticos cuya linea cae en la region del archivo real.
	Las lineas del preludio se descartan: son definiciones, no codigo.

	El numero de linea se reexpresa en coordenadas del archivo original
	para que las referencias sigan siendo utilizables tal cual.

	Uso:
	  node tools/analyze.js            # src/ y tests/
	  node tools/analyze.js src        # solo src/
	  node tools/analyze.js --raw src  # sin entorno (para comparar)
*/

const fs = require("fs");
const path = require("path");
const os = require("os");
const { execFileSync } = require("child_process");

const ROOT = path.join(__dirname, "..");
const ANALYZE = path.join(__dirname, "luau", "luau-analyze.exe");
const PRELUDE = path.join(__dirname, "roblox-definitions", "RobloxEnvironment.lua");

const args = process.argv.slice(2);
const RAW = args.includes("--raw");
const targets = args.filter((a) => !a.startsWith("--"));
const roots = targets.length > 0 ? targets : ["src", "tests"];

/** Lista recursivamente los .lua de un directorio. */
function luaFiles(dir) {
	const out = [];
	for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
		const full = path.join(dir, entry.name);
		if (entry.isDirectory()) {
			if (entry.name === "roblox-definitions" || entry.name.startsWith(".")) continue;
			out.push(...luaFiles(full));
		} else if (entry.name.endsWith(".lua")) {
			out.push(full);
		}
	}
	return out;
}

const files = [];
for (const r of roots) {
	const abs = path.join(ROOT, r);
	if (!fs.existsSync(abs)) continue;
	if (fs.statSync(abs).isDirectory()) files.push(...luaFiles(abs));
	else files.push(abs);
}

if (files.length === 0) {
	console.error("No se encontraron archivos .lua en: " + roots.join(", "));
	process.exit(1);
}

const prelude = RAW ? "" : fs.readFileSync(PRELUDE, "utf8");
const preludeLines = prelude === "" ? 0 : prelude.split("\n").length;

const workDir = path.join(ROOT, ".cache", "analyze");
fs.rmSync(workDir, { recursive: true, force: true });
fs.mkdirSync(workDir, { recursive: true });

const temp = path.join(workDir, "probe.lua");
const PRELUDE_STUB = "-- preludio del analizador: lineas de definicion, se descartan\n";

const MODE_DIRECTIVE = /^--!(strict|nonstrict|nocheck)\s*$/;

/**
 * Sube el `--!strict` / `--!nonstrict` del archivo real a la PRIMERA
 * linea del combinado.
 *
 * Por que hace falta: una directiva de modo solo se aplica si aparece
 * antes del primer token. Al anteponer el preludio, el `--!strict` del
 * codigo real queda en medio y el analizador lo descarta avisando con
 * `CommentDirective` (64 avisos, todos artefactos de esta concatenacion,
 * ninguno un defecto del juego). Se extrae y se reinserta arriba; asi
 * el archivo se analiza en el MISMO modo que declara.
 */
function splitMode(source) {
	const lines = source.split("\n");
	let mode = null;
	let firstCode = 0;
	for (let i = 0; i < lines.length; i += 1) {
		const m = MODE_DIRECTIVE.exec(lines[i].trim());
		if (m) {
			if (mode === null) mode = m[1];
			lines[i] = null; // se marca para eliminar
		} else if (mode !== null && lines[i].trim() !== "") {
			firstCode = i;
			break;
		}
	}
	void firstCode;
	return {
		mode,
		body: lines.filter((l) => l !== null).join("\n"),
	};
}

/** Analiza un archivo y devuelve { file, line, severity, message }. */
function analyzeOne(file) {
	const original = fs.readFileSync(file, "utf8");
	const { mode, body } = splitMode(original);

	// El archivo combinado es: [directiva de modo] + PRELUDIO + Stub +
	// fuente. El preludio ocupa `preludeLines` lineas, la Stub ocupa UNA
	// mas, y el cuerpo real empieza en `preludeLines + 2`. Restar solo
	// `preludeLines` dejaba todas las referencias desplazadas en una
	// linea, lo que hace que cada cita apunte a la linea siguiente.
	const header = mode ? `--!${mode}\n` : "";
	fs.writeFileSync(temp, header + (prelude === "" ? "" : prelude + "\n" + PRELUDE_STUB) + body, "utf8");

	// IMPORTANTE: con `--formatter=plain` este binario sale con codigo 0
	// AUNQUE haya errores, y escribe los diagnosticos en STDOUT. Por eso
	// NO se puede depender de la excepcion de execFileSync: hay que
	// leer stdout siempre. Medido: Maid.lua produce 16 lineas y exit 0.
	let raw = "";
	try {
		raw = execFileSync(ANALYZE, ["--formatter=plain", temp], {
			encoding: "utf8",
			stdio: ["ignore", "pipe", "pipe"],
			maxBuffer: 64 * 1024 * 1024,
		});
	} catch (err) {
		raw = (err.stdout || "") + (err.stderr || "");
	}

	// El formato `plain` es luacheck-compatible y de una sola linea:
	//   ruta:LINEA:COL-COL: (W0) Severidad: mensaje
	// Los mensajes con tipos largos se envuelven en varias lineas
	// fisicas, asi que las lineas que no encajan en el patron se
	// anexan a la incidencia anterior.
	const lines = raw.split(/\r?\n/);
	const results = [];
	let current = null;
	for (const line of lines) {
		const m = /^(.*?):(\d+):(\d+)-(\d+):\s*\(W\d+\)\s*(\w+):\s*([\s\S]*)$/.exec(line);
		if (m) {
			if (current) results.push(current);
			current = { line: parseInt(m[2], 10), severity: m[5], message: m[6] };
		} else if (current && line.trim() !== "") {
			current.message += "\n" + line;
		}
	}
	if (current) results.push(current);

	const rel = path.relative(ROOT, file).replace(/\\/g, "/");
	const OFFSET = preludeLines + (prelude === "" ? 0 : 1);
	return results
		.filter((r) => r.line > OFFSET)
		.map((r) => ({ file: rel, line: r.line - OFFSET, severity: r.severity, message: r.message }));
}

const diagnostics = [];
for (const f of files) diagnostics.push(...analyzeOne(f));

const SEVERITY_ORDER = { SyntaxError: 0, TypeError: 1, UnknownProperty: 2, CountMismatch: 3, other: 9 };
diagnostics.sort(
	(a, b) =>
		(SEVERITY_ORDER[a.severity] ?? 9) - (SEVERITY_ORDER[b.severity] ?? 9) ||
		a.file.localeCompare(b.file) ||
		a.line - b.line
);

console.log("Analizador: " + (RAW ? "SIN entorno Roblox (--raw)" : "CON entorno Roblox (preludio)"));
console.log("Archivos analizados: " + files.length);
console.log("Lineas de preludio descartadas por archivo: " + preludeLines);
console.log("");

const bySeverity = {};
for (const d of diagnostics) bySeverity[d.severity] = (bySeverity[d.severity] || 0) + 1;

if (diagnostics.length === 0) {
	console.log("0 incidencias.");
	console.log("RESULTADO: PASS");
	process.exit(0);
}

for (const d of diagnostics) {
	console.log(`${d.file}:${d.line}: ${d.severity}: ${d.message}`);
}

console.log("");
for (const [sev, n] of Object.entries(bySeverity).sort((a, b) => b[1] - a[1])) {
	console.log(`  ${sev}: ${n}`);
}
console.log("");
console.log("INCIDENCIAS TOTALES: " + diagnostics.length);
console.log("RESULTADO: FAIL");
process.exit(1);
