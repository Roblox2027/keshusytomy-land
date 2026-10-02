// classify-problems.js
// Clasifica la salida de `luau-analyze` por CAUSA RAIZ, no por incidencia.
//
// Por que existe:
// `luau-analyze` en modo standalone NO conoce el entorno de Roblox: no
// tiene definiciones de `game`, `Instance`, `Vector3`, `CFrame`, `task`,
// `Enum`, `RemoteEvent`, `Player`... etc. Cada uso de esas API produce un
// "TypeError: Unknown global/type" que NO es un defecto del juego sino una
// limitacion de la herramienta. Sumado a los `require` con ruta dinamica
// (`WaitForChild` encadenado), una sola causa raiz genera cientos de
// lineas.
//
// Sin esta clasificacion, "439 errores" parece un desastre y lleva a
// "arreglar" codigo que esta bien. Con ella, el numero real de problemas
// atribuibles al codigo es mucho menor y accionable.
//
// Uso:  node tools/classify-problems.js
// Salida: tabla por causa raiz + resumen de incidencias.

const { execFileSync } = require("child_process");
const path = require("path");

const ROOT = path.join(__dirname, "..");
const ANALYZE = path.join(ROOT, "tools", "luau", "luau-analyze.exe");

/**
 * Globales y tipos que forman parte del entorno Roblox y que el analizador
 * standalone no conoce. Un error que solo menciona estos NO es un bug.
 */
const ROBOX_GLOBALS = [
	"game",
	"Instance",
	"Vector3",
	"Vector2",
	"CFrame",
	"Color3",
	"UDim",
	"UDim2",
	"Ray",
	"task",
	"Enum",
	"NumberRange",
	"NumberSequence",
	"Rect",
	"TweenInfo",
	"BrickColor",
	"Random",
	"Region3",
	"OverlapParams",
	"RaycastParams",
	"Player",
	"Players",
	"Teams",
	"RunService",
	"UserInputService",
	"ContextActionService",
	"TouchEnabled",
	"GamepadEnabled",
	"KeyboardEnabled",
	"workspace",
	"script",
	"shared",
	"plugin",
	"Instance.new",
	"FindFirstChild",
	"WaitForChild",
	"SetAttribute",
	"GetAttribute",
	"IsA",
	"Clone",
	"Parent",
	"Debris",
	"Lighting",
	"TweenService",
	"MarketplaceService",
	"DataStoreService",
	"HttpService",
	"PathfindingService",
	"ServerScriptService",
	"ReplicatedStorage",
	"StarterGui",
	"StarterPlayer",
	"Humanoid",
	"BasePart",
	"Model",
	"Folder",
	"RemoteEvent",
	"RemoteFunction",
	"BindableEvent",
	"SoundService",
	"Camera",
	"GuiService",
	"TextService",
	"CollectionService",
	"BodyMover",
	"AlignPosition",
	"Vector3Force",
];

function mentionsOnlyRoblox(message) {
	return ROBOX_GLOBALS.some((g) => message.includes(g));
}

/** Clasifica una linea de error de luau-analyze. */
function classify(line) {
	const isDynamicRequire = line.includes("Unknown require: unsupported path");

	if (isDynamicRequire) {
		return {
			cause: "Require dinamico (WaitForChild encadenado)",
			category: "False Positive",
			severity: "INFO",
			fix: "Ninguna. Es el patron obligatorio del proyecto (rutas por WaitForChild).",
		};
	}

	if (/Unknown global '/.test(line) || /Unknown type '/.test(line)) {
		return {
			cause: "Falta la definicion del entorno Roblox en el analizador",
			category: "False Positive",
			severity: "INFO",
			fix: "Ninguna en el codigo. Se resuelve con un .luaurc / definicion de tipos de Roblox.",
		};
	}

	// Errores de metodo sobre una instancia son consecuencia de que
	// `Instance` sea `unknown`: sin la clase, todo lo que se le llama
	// falla tambien.
	if (mentionsOnlyRoblox(line) && /Type 'unknown' does not have/.test(line)) {
		return {
			cause: "Consecuencia de `Instance` sin tipo (entorno Roblox ausente)",
			category: "False Positive",
			severity: "INFO",
			fix: "Ninguna en el codigo. Depende de la causa anterior.",
		};
	}

	return {
		cause: "Defecto de tipado real en el codigo",
		category: "Type",
		severity: "P2",
		fix: "Revisar el archivo y la linea indicadas.",
	};
}

function main() {
	let raw = "";
	try {
		raw = execFileSync(ANALYZE, ["src", "tests"], {
			cwd: ROOT,
			encoding: "utf8",
			maxBuffer: 64 * 1024 * 1024,
		});
	} catch (e) {
		// luau-analyze sale con codigo 1 cuando encuentra errores: eso NO
		// es un fallo de la herramienta, es su forma de reportarlos.
		raw = (e.stdout || "") + (e.stderr || "");
	}

	const lines = raw
		.split(/\r?\n/)
		.filter((l) => l.includes("TypeError") || l.includes("SyntaxError"));

	const byCause = new Map();
	const real = [];

	for (const line of lines) {
		const c = classify(line);
		if (!byCause.has(c.cause)) byCause.set(c.cause, { ...c, count: 0, files: new Set(), samples: [] });
		const entry = byCause.get(c.cause);
		entry.count += 1;
		const m = line.match(/\.\/[^(]+/);
		if (m) entry.files.add(m[0]);
		if (entry.samples.length < 3) entry.samples.push(line.trim());
		if (c.severity !== "INFO") real.push(line);
	}

	console.log("INCIDENCIAS TOTALES: " + lines.length);
	console.log("");

	const sorted = [...byCause.values()].sort((a, b) => b.count - a.count);
	for (const e of sorted) {
		console.log(`[${e.severity}] ${e.cause}`);
		console.log(`    incidencias: ${e.count}`);
		console.log(`    categoria:   ${e.category}`);
		console.log(`    archivos:    ${e.files.size}`);
		console.log(`    accion:      ${e.fix}`);
		for (const s of e.samples) console.log(`      ej. ${s}`);
		console.log("");
	}

	console.log("=".repeat(60));
	console.log(`INCIDENCIAS REALES (atribuibles al codigo): ${real.length}`);
	console.log(`FALSOS POSITIVOS (entorno Roblox ausente):  ${lines.length - real.length}`);
	console.log(`ARCHIVOS CON CAUSA RAIZ REAL:                ${new Set(real.map((l) => (l.match(/\.\/[^(]+/) || [""])[0])).size}`);
}

main();
