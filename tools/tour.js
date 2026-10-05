// tour.js
// Recorre un mundo ENTERO en la sesion de Play real y devuelve el informe.
//
// Uso:  node tools/tour.js <instancia> <mundo> [peer]
//
// Por que un archivo por mundo y no un parametro: el puente MCP de Studio no
// admite varargs (`...`) en el Luau que inyecta, asi que el nombre del mundo
// se antepone como literal delante del codigo.

const fs = require("fs");
const path = require("path");
const mcp = require("./mcp");

const INSTANCE = process.argv[2];
const WORLD = process.argv[3];
const PEER = process.argv[4] || "client-1";
const FILE = process.argv[5] || "tour-bg.lua";

(async () => {
	const code = fs.readFileSync(path.resolve(__dirname, "..", ".ai", "tmp", FILE), "utf8");
	const full = `local worldName = ${JSON.stringify(WORLD)}\n` + code;
	const out = await mcp.tool("eval_client_runtime", { code: full, target: PEER, instance_id: INSTANCE });
	console.log(typeof out === "string" ? out : JSON.stringify(out, null, 2));
})().catch((e) => {
	console.error("FALLO: " + e.message);
	process.exit(1);
});