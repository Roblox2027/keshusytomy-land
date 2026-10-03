// probe.js
// Ejecuta un fichero .lua de tools/probes/ dentro del RUNTIME REAL de Studio
// via MCP y devuelve su texto de salida.
//
// POR QUE EXISTE
// --------------
// Las fases anteriores leiaron archivos y llamaron a eso "runtime". Leer el
// source no dice nada sobre el juego en ejecucion. Este script habla de verdad
// con el servidor/cliente de Studio y devuelve lo que those scripts imprimen.
//
// Uso:
//   node tools/probe.js tools/probes/snapshot.lua
//   node tools/probe.js tools/probes/snapshot.lua client
//   node tools/probe.js tools/probes/ledger.lua server
//
// Codigo de salida: 0 si respondio, 2 si el runtime esta BLOCKED, 1 si hay error.

const fs = require("fs");
const path = require("path");
const mcp = require("./mcp");

const file = process.argv[2];
const target = (process.argv[3] || "server").toLowerCase();

if (!file) {
	console.error("Uso: node tools/probe.js <fichero.lua> [server|client]");
	process.exit(1);
}

const full = path.resolve(process.cwd(), file);
if (!fs.existsSync(full)) {
	console.error(`No existe el fichero: ${full}`);
	process.exit(1);
}

const code = fs.readFileSync(full, "utf8");
const tool = target === "client" ? "eval_client_runtime" : "eval_server_runtime";

(async () => {
	try {
		await mcp.init();
		const out = target === "client" ? await mcp.clientLuau(code) : await mcp.serverLuau(code);
		if (out === null || out === undefined) {
			console.error(`RUNTIME: BLOCKED (${target} no devolvio nada)`);
			process.exit(2);
		}
		if (out && typeof out === "object" && (out.ok === false || out.error)) {
			console.error(`ERROR ${target}: ${JSON.stringify(out).slice(0, 2000)}`);
			process.exit(1);
		}
		console.log(typeof out === "string" ? out : JSON.stringify(out, null, 2));
		process.exit(0);
	} catch (e) {
		console.error(`RUNTIME: BLOCKED (${e.message})`);
		process.exit(2);
	}
})();
