"use strict";

/*
	server-vs-edit.js
	Lee la MISMA geometria en las dos vistas y las compara.
	
	POR QUE EXISTE
	--------------
	`block-size-probe.lua` (edit session) dice que Block_0 mide 6x11x6.
	`verify-geometry.js` (server role de Play) dice que mide 8x8x8.
	
	Las dos herramientas estan bien escritas y dan lecturas opuestas, asi
	que una de las dos esta mirando una sesion DISTINTA. Con mas de un
	playtest vivo a la vez es facil: `play.js` arranca "AutoRecovery_1",
	"AutoRecovery_2", ... y cada uno tiene su propio Workspace.
	
	Este script pide el mismo dato por los dos caminos y los imprime
	juntos. Si difieren, la conclusion no es "el mapa esta mal" sino
	"hay dos sesiones y verify-geometry esta midiendo la vieja".
	
	Uso:  node tools/server-vs-edit.js
*/

const path = require("path");
const mcp = require("./mcp");

const ROOT = path.resolve(__dirname, "..");
const fs = require("fs");

const PROBE = fs.readFileSync(path.join(__dirname, "block-size-probe.lua"), "utf8");

async function main() {
	console.log("=== LECTURA EN SERVIDOR (verify-geometry usa esta) ===");
	const server = await mcp.serverLuau(PROBE);
	console.log("  " + JSON.stringify(server));

	console.log("");
	console.log("=== LECTURA EN EDICION (studio-mcp usa esta) ===");
	const edit = await mcp.tool("execute_luau", { code: PROBE });
	console.log("  " + JSON.stringify(edit && edit.returnValue !== undefined ? edit.returnValue : edit));

	console.log("");
	console.log("=== SESIONES CONECTADAS ===");
	const inst = await mcp.toolJson("get_connected_instances", {});
	console.log(JSON.stringify(inst, null, 2).slice(0, 1200));
}

main().catch((e) => {
	console.error("FALLO: " + e.message);
	process.exit(2);
});