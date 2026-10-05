// walk.js
// Camina con el personaje REAL de la sesion de Play hacia un punto y
// devuelve el informe del Luau.
//
// Por que existe: `Humanoid:MoveTo` es la misma fisica que usa el jugador
// cuando pulsa una tecla. No teletransporta nada, y por eso es la unica forma
// valida de responder "el jugador puede LLEGAR fisicamente ahi".
//
// Uso:  node tools/walk.js <instancia> <x> <y> <z> [etiqueta] [peer]

const fs = require("fs");
const path = require("path");
const mcp = require("./mcp");

const INSTANCE = process.argv[2];
const x = process.argv[3];
const y = process.argv[4];
const z = process.argv[5];
const label = process.argv[6] || `hacia(${x},${y},${z})`;
const peer = process.argv[7] || "client-1";

(async () => {
	const code = fs.readFileSync(path.resolve(__dirname, "..", ".ai", "tmp", "walker.lua"), "utf8");
	const full =
		`local label = ${JSON.stringify(label)}\n` +
		`local tx, ty, tz = ${Number(x)}, ${Number(y)}, ${Number(z)}\n` +
		code;
	const out = await mcp.tool("eval_client_runtime", { code: full, target: peer, instance_id: INSTANCE });
	console.log(typeof out === "string" ? out : JSON.stringify(out, null, 2));
})().catch((e) => {
	console.error("FALLO: " + e.message);
	process.exit(1);
});