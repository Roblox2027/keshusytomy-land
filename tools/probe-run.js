// probe-run.js
// Ejecuta codigo Luau en el cliente REAL de la sesion de Play de una
// instancia concreta de Studio.
//
// Por que existe: `tools/studio-mcp.js --codefile` rellena SOLO el primer campo
// `required` de la herramienta (`code`). Con dos ventanas de Studio abiertas,
// `eval_client_runtime` responde `ambiguous_target` porque necesita
// `instance_id`, y el CLI no tiene forma de injectarlo junto al codigo.
//
// Uso:  node tools/probe-run.js <instancia> <archivo.lua> [peer]

const fs = require("fs");
const path = require("path");

const INSTANCE = process.argv[2];
const FILE = process.argv[3];
const PEER = process.argv[4] || "client-1";

if (!INSTANCE || !FILE) {
	console.error("uso: node tools/probe-run.js <instance_id> <archivo.lua> [peer]");
	process.exit(1);
}

const mcp = require("./mcp");

(async () => {
	const code = fs.readFileSync(path.resolve(FILE), "utf8");
	const args = { code, target: PEER, instance_id: INSTANCE };
	const out = await mcp.tool("eval_client_runtime", args);
	console.log(typeof out === "string" ? out : JSON.stringify(out, null, 2));
})().catch((e) => {
	console.error("FALLO: " + e.message);
	process.exit(1);
});