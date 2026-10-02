"use strict";

/*
	destroy-restore-check.js
	Ejecuta `destroy-restore-integrity.lua` en el servidor de Play y
	convierte su salida en un PASS/FAIL legible.

	POR QUE EXISTE
	--------------
	La reconstruccion del bosque cambio las dimensiones y el giro de los
	48 bloques destructibles. El ciclo "destruir -> restaurar" es el punto
	donde eso podria perderse:

	  - `snapshotBlock` guarda `Transparency`, `CanCollide` y `CanTouch`, pero
	    NO `Size`, `Position` ni `Orientation`.
	  - El radio de explosion se calcula por distancia entre CENTROS, asi
	    que un bloque que cambiara de sitio al restaurarse empezaria a
	    recibir impactos en otro punto de la arena.

	`combat-verify.js` ya comprueba que un bloque se destruye y vuelve, pero
	mira TRANSPARENCIA y COLISION, que es justamente lo que el servicio
	guarda. No mira la geometria, que es lo que este cambio del mapa ha
	alterado. Esta comprobacion cubre ese hueco.

	Uso:  node tools/destroy-restore-check.js
	Codigo de salida 0 si el ciclo conserva la geometria.
*/

const fs = require("fs");
const path = require("path");

const mcp = require("./mcp");

const LUAU = fs.readFileSync(path.join(__dirname, "destroy-restore-integrity.lua"), "utf8");

function readField(text, key) {
	const m = new RegExp("^" + key + "=(.*)$", "m").exec(text);
	return m ? m[1].trim() : null;
}

async function main() {
	const res = await mcp.serverLuau(LUAU);

	// `serverLuau` devuelve el valor ya desenvolveruelto, pero segun el
	// camino puede venir como objeto. Antes se hacia String(objeto) y
	// salia "[object Object]", con lo que todos los campos se leian como
	// nulos y la comprobacion daba FAIL sin motivo real.
	const value = res && typeof res === "object" && "value" in res ? res.value : res;
	const text = typeof value === "string" ? value : JSON.stringify(res, null, 2);

	console.log("DESTRUIR -> RESTAURAR (integridad de la geometria)");
	console.log("---------------------------------------------------------------");
	console.log(text);
	console.log("");

	if (typeof value !== "string" || !/bloquesProbados=/.test(text)) {
		console.log("El servidor no devolvio el informe. Respuesta cruda:");
		console.log(JSON.stringify(res, null, 2).slice(0, 1000));
		process.exitCode = 2;
		return;
	}

	const failures = [];
	const check = (label, ok, detail) => {
		console.log((ok ? "  PASS  " : "  FAIL  ") + label + (detail ? "  (" + detail + ")" : ""));
		if (!ok) failures.push(label);
	};

	const blocks = Number(readField(text, "bloquesProbados"));
	const destroyed = Number(readField(text, "destruidos"));
	const restored = Number(readField(text, "restaurados"));
	const problems = Number(readField(text, "problemas"));
	const childrenOk = Number(readField(text, "hijosIguales"));
	const stillDestroyed = Number(readField(text, "siguenMarcadosDestruidos"));

	check("se probaron los 48 bloques", blocks === 48, blocks + " bloques");
	check("se destruyeron todos", destroyed === 48, destroyed + " destruidos");
	check("RestoreAll los devolvio", restored === 48, restored + " restaurados");
	check("el TAMANO se conserva", readField(text, "sizeIgual") === String(blocks), readField(text, "sizeIgual"));
	check("la POSICION se conserva", readField(text, "posicionIgual") === String(blocks), readField(text, "posicionIgual"));
	check("la ORIENTACION se conserva", readField(text, "orientacionIgual") === String(blocks), readField(text, "orientacionIgual"));
	check("la decoracion sigue colgando", childrenOk === blocks, childrenOk + " de " + blocks);
	check("ningun bloque sigue marcado como destruido", stillDestroyed === 0, stillDestroyed + " marcados");
	check("sin discrepancias", problems === 0, problems + " problemas");

	if (failures.length > 0) {
		console.log("\nFALLAN " + failures.length + ".");
		process.exitCode = 1;
	} else {
		console.log("\nEl ciclo destruir/restaurar conserva posicion, tamano, orientacion");
		console.log("y decoracion en los 48 bloques.");
	}
}

main().catch((e) => {
	console.error("FALLO: " + e.message);
	process.exit(2);
});