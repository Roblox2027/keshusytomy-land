// luau.js
// Ejecuta Luau en el servidor o el cliente de Studio y devuelve el valor.
//
// POR QUE EXISTE
// --------------
// Pasar codigo Luau por la linea de comandos es imposible de forma fiable
// desde PowerShell y cmd: las comillas se mutilan antes de que Node las vea
// y el fragmento llega al servidor corrupto ("Malformed string; did you
// forget to finish it?"). Este script lee el codigo de un ARCHIVO y lo
// ejecuta, de modo que el Luau nunca pasa por el interprete de comandos.
//
// Uso:
//   node tools/luau.js server <archivo.lua>
//   node tools/luau.js client <archivo.lua>
//
// Imprime el valor devuelto ya parseado, y sale con codigo 1 si el propio
// snippet fallo (para poder encadenarlo como comprobacion).

const fs = require("fs");
const mcp = require("./mcp");

async function main() {
	const [role, file] = process.argv.slice(2);

	if (!role || !file) {
		console.error("uso: node tools/luau.js <server|client> <archivo.lua>");
		process.exitCode = 2;
		return;
	}

	const code = fs.readFileSync(file, "utf8");

	let out;
	if (role === "server") out = await mcp.serverLuau(code);
	else if (role === "client") out = await mcp.clientLuau(code);
	else {
		console.error("rol desconocido: " + role + " (usa server o client)");
		process.exitCode = 2;
		return;
	}

	// `ok: false` con `error` significa que el snippet fallo en el motor: el
	// valor devuelto no existe y hay que distinguirlo de un `nil` legitimo.
	if (out && typeof out === "object" && out.ok === false) {
		console.error("ERROR EN EL SNIPPET: " + out.error);
		process.exitCode = 1;
		return;
	}

	console.log(JSON.stringify(out, null, 2));
}

main().catch((e) => {
	console.error("FALLO: " + e.message);
	process.exitCode = 2;
});
