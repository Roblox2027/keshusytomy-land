// play.js
// Arranca, detiene y consulta la sesion de Play de Studio via MCP.
//
// POR QUE EXISTE
// --------------
// El codigo del servidor (ServerMain, ServiceRegistry, los servicios) solo
// se ejecuta dentro de una sesion de Play. Sin Play no hay runtime que
// auditar: los scripts existen pero no se han ejecutado nunca. Este script
// es el unico punto del repositorio que arranca y detiene esa sesion, para
// que las verificaciones (boot-state, runtime-tree, vertical-slice) tengan
// un servidor real contra el que preguntar.
//
// Uso:
//   node tools/play.js start        # arranca Play
//   node tools/play.js stop         # detiene Play
//   node tools/play.js status       # estado de la sesion
//   node tools/play.js restart      # stop + start

const mcp = require("./mcp");

/**
 * Acciona la sesion de Play.
 *
 * `mode` es OBLIGATORIO para `start` segun el esquema de la herramienta
 * (`play` = con cliente, `run` = solo servidor). Sin el, la llamada falla y
 * el servidor nunca arranca.
 */
async function soloPlaytest(action, extra = {}) {
	return mcp.toolJson("solo_playtest", Object.assign({ action }, extra));
}

/** Instancias vivas y si tienen servidor de juego. */
async function instances() {
	return mcp.toolJson("get_connected_instances", {});
}

async function showStatus() {
	const inst = await instances();
	const list = inst?.instances || [];
	if (!list.length) {
		console.log("SIN INSTANCIAS conectadas a Studio.");
		return false;
	}
	for (const i of list) {
		const peers = i.peers || {};
		const clients = Object.keys(peers).filter((p) => p.startsWith("client"));
		console.log(`lugar: ${i.placeName}`);
		console.log(`  servidor de juego: ${peers.server ? "SI" : "NO"}`);
		console.log(`  clientes: ${clients.length ? clients.join(", ") : "(ninguno)"}`);
	}
	return Boolean(list[0]?.peers?.server);
}

/** Espera a que exista un servidor de juego, con un techo de tiempo. */
async function waitForServer(timeoutMs = 45000) {
	const started = Date.now();
	while (Date.now() - started < timeoutMs) {
		if (await showStatusQuiet()) return true;
		await new Promise((r) => setTimeout(r, 1500));
	}
	return false;
}

async function showStatusQuiet() {
	const inst = await instances();
	return Boolean(inst?.instances?.some((i) => i.peers && i.peers.server));
}

async function main() {
	const action = (process.argv[2] || "status").toLowerCase();
	// `--run` arranca solo el servidor (mas rapido y estable para auditar
	// logica de servidor). Por defecto se usa `play`, con cliente, que es lo
	// necesario para verificar HUD, controlador y entorno de jugador.
	const mode = process.argv.includes("--run") ? "run" : "play";

	if (action === "status") {
		await showStatus();
		return;
	}

	if (action === "stop") {
		console.log(JSON.stringify(await soloPlaytest("stop", { timeout: 15 })));
		return;
	}

	if (action === "start") {
		console.log("arrancando Play (modo " + mode + ")...");
		console.log(JSON.stringify(await soloPlaytest("start", { mode, timeout: 60 })));
		const ok = await waitForServer();
		console.log(ok ? "SERVIDOR LISTO" : "TIMEOUT: el servidor no arranco");
		if (!ok) process.exitCode = 1;
		return;
	}

	if (action === "restart") {
		console.log("deteniendo Play...");
		await soloPlaytest("stop", { timeout: 15 });
		// Se espera a que el servidor desaparezca antes de volver a arrancar:
		// pedir `start` mientras la sesion anterior sigue viva produce dos
		// servidores y los registros que se leen serian el equivocado.
		await new Promise((r) => setTimeout(r, 3000));
		console.log("arrancando Play (modo " + mode + ")...");
		console.log(JSON.stringify(await soloPlaytest("start", { mode, timeout: 60 })));
		const ok = await waitForServer();
		console.log(ok ? "SERVIDOR LISTO" : "TIMEOUT: el servidor no arranco");
		if (!ok) process.exitCode = 1;
		return;
	}

	console.error("accion desconocida: " + action);
	process.exitCode = 2;
}

main().catch((e) => {
	console.error("FALLO: " + e.message);
	process.exitCode = 2;
});
