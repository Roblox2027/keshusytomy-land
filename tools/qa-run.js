// qa-run.js
// Ejecuta una sonda Luau en el SERVIDOR o el CLIENTE de la sesion de Play.
//
// Por que existe: `studio-mcp.js execute_luau` corre en el DataModel de
// EDICION, donde no hay jugadores ni ronda. Cualquier afirmacion sobre PLAY
// tiene que salir de `eval_server_runtime` / `eval_client_runtime`.
//
// Uso:
//   node tools/qa-run.js server tools/probes/qa-bomb-explosion.lua
//   node tools/qa-run.js client tools/probes/qa-hud.lua

const fs = require("fs");
const path = require("path");
const mcp = require("./mcp");

async function main() {
	const target = process.argv[2] === "client" ? "client" : "server";
	const file = process.argv[3];

	if (!file) {
		console.error("uso: node tools/qa-run.js [server|client] <archivo.lua>");
		process.exit(2);
	}

	const code = fs.readFileSync(path.resolve(file), "utf8");
	await mcp.init();

	const result = target === "client" ? await mcp.clientLuau(code) : await mcp.serverLuau(code);
	console.log(typeof result === "string" ? result : JSON.stringify(result, null, 2));
}

main().catch((err) => {
	console.error("FALLO: " + err.message);
	process.exit(1);
});