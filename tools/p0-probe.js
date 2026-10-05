"use strict";

// p0-probe.js
// Lanza sondas Luau contra la sesion de Play REAL (servidor y cliente) a
// traves del MCP de Roblox Studio, y saca el resultado por pantalla.
//
// Por que existe: el enunciado del P0 prohibe dar por buena una correccion
// porque `npm test` pasa. Estas sondas miden el runtime de verdad, que es
// donde fallaban la UI de la bomba y la colocacion de la bomba.
//
// Uso:
//   node tools/p0-probe.js server-state
//   node tools/p0-probe.js client-ui
//   node tools/p0-probe.js both

const fs = require("fs");
const path = require("path");
const mcp = require("./mcp");

const PROBES = path.join(__dirname, "probes");

function loadProbe(name) {
	const file = path.join(PROBES, `${name}.lua`);

	if (!fs.existsSync(file)) {
		throw new Error(`no existe la sonda: ${file}`);
	}
	return fs.readFileSync(file, "utf8");
}

async function runServer(name) {
	console.log(`\n===== SERVIDOR :: ${name} =====`);
	const r = await mcp.serverLuau(loadProbe(name));
	console.log(typeof r === "string" ? r : JSON.stringify(r, null, 2));
}

async function runClient(name) {
	console.log(`\n===== CLIENTE :: ${name} =====`);
	const r = await mcp.clientLuau(loadProbe(name));
	console.log(typeof r === "string" ? r : JSON.stringify(r, null, 2));
	return r;
}

/**
 * Cadena REAL de la bomba: pulsar el boton con el RATON y mirar si el servidor
 * publica una bomba en Workspace.Bombs.
 *
 * Por que el raton y no una llamada a Lua: el enunciado pide comprobar
 * INPUT -> REMOTE -> SERVIDOR -> Workspace.Bombs. Llamar al controller desde
 * una sonda saltaria el paso del input, que es donde estaba el defecto.
 */
async function pressBombAndWatch() {
	const geo = await mcp.clientLuau(loadProbe("p0-bomb-click"));

	if (!geo || geo.buttonFound !== true) {
		console.log("\n===== CADENA DE LA BOMBA =====");
		console.log("el boton de bomba NO existe en el cliente: no hay nada que pulsar.");
		console.log(JSON.stringify(geo, null, 2));
		return;
	}

	console.log("\n===== CADENA DE LA BOMBA =====");
	console.log(`boton en (${geo.clickX}, ${geo.clickY}) | mundo=${geo.world} ronda=${geo.roundState} bombas=${geo.serverBombs}`);

	// El clic entra por el raton, igual que el dedo del jugador.
	await mcp.tool("simulate_mouse_input", { action: "click", x: geo.clickX, y: geo.clickY });

	// Y despues se mira Workspace.Bombs, que es la prueba de aceptacion.
	const watch = await mcp.clientLuau(loadProbe("p0-bomb-watch"));
	console.log(typeof watch === "string" ? watch : JSON.stringify(watch, null, 2));
}

async function main() {
	const mode = process.argv[2] || "both";

	await mcp.init();

	if (mode === "server-state" || mode === "both") await runServer("p0-server-state");
	if (mode === "client-ui" || mode === "both") await runClient("p0-client-ui");
	if (mode === "click" || mode === "both") await pressBombAndWatch();
}

main().catch((e) => {
	console.error("FALLO: " + e.message);
	process.exit(1);
});