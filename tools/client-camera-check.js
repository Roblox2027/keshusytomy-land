// client-camera-check.js
// Comprueba donde esta REALMENTE la camara respecto al personaje y que hay
// delante, en el cliente.
//
// POR QUE EXISTE
// --------------
// `client-probe.js facelobby` es intermitente: dos ejecuciones seguidas
// dieron `Lobby 11/98` y `Lobby 0/98` con el mismo mapa. Ademas la camara
// aparecia en y = 56.5 con el personaje en y = 3.
//
// Dos hipotesis, muy distintas:
//
//   a) la camara esta realmente a 53 studs del personaje: el jugador
//      ve otra cosa y por eso el ratio de visibilidad salta; o
//   b) la camara va bien y lo que cambia es DONDE esta el personaje,
//      porque el ciclo de ronda lo teletransporta entre medir y medir.
//
// Este script mide las dos cosas EN EL MISMO INSTANTE, que es lo que
// falta en la sonda anterior.
//
// Uso:  node tools/client-camera-check.js

const mcp = require("./mcp");
const fs = require("fs");
const path = require("path");

// El Luau vive en su propio archivo: sus comillas dobles se mutilan al
// pasar por la linea de comandos de PowerShell. Es el mismo motivo por el
// que `combat-verify.js` y `client-probe.js` lo hacen.
const SAMPLE = fs.readFileSync(path.join(__dirname, "client-camera-sample.lua"), "utf8");

const CLIENT = SAMPLE;

(async () => {
	// Varias muestras seguidas: el ciclo de ronda mueve al jugador, y una
	// sola medida no distingue "el cliente va mal" de "el jugador se movio".
	for (let i = 1; i <= 4; i++) {
		const r = await mcp.toolJson("eval_client_runtime", { code: CLIENT });
		console.log("muestra " + i + ":");
		for (const [k, v] of Object.entries(r || {})) {
			console.log("  " + k.padEnd(24) + ": " + v);
		}
		await new Promise((res) => setTimeout(res, 1200));
	}
})();