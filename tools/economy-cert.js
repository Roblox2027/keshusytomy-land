/**
 * Certificacion de la columna economica en el servidor EN EJECUCION.
 *
 * POR QUE ES UN SCRIPT APARTE
 * ---------------------------
 * PowerShell mutila las comillas del Luau y produce errores de compilacion
 * falsos que parecen defectos del juego. Por eso el Luau vive en un `.lua`
 * y aqui solo se pasa su contenido por `mcp.serverLuau`, igual que hace
 * `runtime-probe.js` con sus sondas.
 *
 * Que demuestra y que NO:
 *   - Que un jugador real tiene perfil cargado,Economia conectada, y que la
 *     cadena compra -> cobro -> entrega -> inventario funciona de verdad.
 *   - NO demuestra que el DataStore persista entre sesiones. Eso necesita
 *     entrar y salir del jugador, que se certifica aparte.
 */

const fs = require("fs");
const path = require("path");
const mcp = require("./mcp");

const CERT_LUA = fs.readFileSync(
	path.join(__dirname, "probes", "economy-cert.lua"),
	"utf8"
);

/** Son Luau de diagnostico del ciclo de vida del perfil. */
const DIAG_LUA = fs.readFileSync(
	path.join(__dirname, "probes", "profile-diag.lua"),
	"utf8"
);

/** Traza del libro mayor: que se concedio y por que motivo. */
const LEDGER_LUA = fs.readFileSync(
	path.join(__dirname, "probes", "ledger.lua"),
	"utf8"
);

/** Estado del ciclo de ronda, para detectar regresiones del nucleo. */
const CORE_LOOP_LUA = fs.readFileSync(
	path.join(__dirname, "probes", "core-loop.lua"),
	"utf8"
);

/** Harness de persistencia sobre el DataService real. */
const HARNESS_LUA = fs.readFileSync(
	path.join(__dirname, "probes", "persistence-harness.lua"),
	"utf8"
);

async function main() {
	await mcp.init();

	if (process.argv.includes("--harness")) {
		const h = await mcp.serverLuau(HARNESS_LUA);
		console.log(typeof h === "string" ? h : JSON.stringify(h, null, 2));
		return;
	}

	if (process.argv.includes("--core-loop")) {
		const loop = await mcp.serverLuau(CORE_LOOP_LUA);
		console.log(typeof loop === "string" ? loop : JSON.stringify(loop, null, 2));
		return;
	}

	if (process.argv.includes("--ledger")) {
		const led = await mcp.serverLuau(LEDGER_LUA);
		console.log(typeof led === "string" ? led : JSON.stringify(led, null, 2));
		return;
	}

	if (process.argv.includes("--diag")) {
		const diag = await mcp.serverLuau(DIAG_LUA);
		console.log(typeof diag === "string" ? diag : JSON.stringify(diag, null, 2));
		return;
	}

	const result = await mcp.serverLuau(CERT_LUA);
	console.log(typeof result === "string" ? result : JSON.stringify(result, null, 2));
}

main().catch((e) => {
	console.error("ERROR: " + e.message);
	process.exit(1);
});