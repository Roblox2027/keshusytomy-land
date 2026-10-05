"use strict";

// world-rim-audit.js
// CUANTO BORDE LE QUEDA A CADA ZONA.
//
// POR QUE
// -------
// Una zona con muchas conexiones es un CRUCERO: un puente, un pasillo, una
// plaza. Cada ruta abre un hueco en su borde, y si la zona es pequena para
// las puertas que tiene, los huecos se comen el borde entero y la zona se
// queda sin muro: no es una caja, pero tampoco es un sitio con entrada y
// salida reconocibles.
//
// `tools/world-structure-test.js` ya falla cuando una zona se queda sin borde
// (`borde 0`), pero solo cuando el arbol esta GENERADO, y el aviso llega tarde
// y sin decir quantas puertas tenia la zona. Esta herramienta responde antes,
// sobre el layout, y dice que zona esta apretada y cuantas puertas tiene.
//
// Uso: node tools/world-rim-audit.js

const worlds = require("./worlds.js");

/** Degree de una zona: cuantas rutas la tocan. */
function degree(layout, id) {
	let n = 0;
	for (const r of layout.routes) {
		if (r.from === id || r.to === id) n++;
	}
	return n;
}

/**
 * Huecos de una zona, con la MISMA cuenta que dibuja el borde.
 *
 * El ancho del hueco se deriva del DECK de cada ruta, no del contrato de
 * ancho: son cosas distintas, y un hueco calculado sobre el contrato se queda
 * corto para el deck que tiene que dejar pasar. Ver la nota de `buildWorld`.
 */
function openingsOf(layout, zone) {
	const byId = {};
	for (const z of layout.zones) byId[z.id] = z;
	const out = [];
	for (const r of layout.routes) {
		if (r.from !== zone.id && r.to !== zone.id) continue;
		const other = byId[r.from === zone.id ? r.to : r.from];
		const halfStuds = Math.max(halfDeckOf(r) + 10, 16);
		out.push({
			angle: Math.atan2(other.z - zone.z, other.x - zone.x),
			halfStuds: halfStuds,
		});
	}
	return out;
}

/** Semiancho del deck de una ruta: el suelo que pisa el jugador. */
function halfDeckOf(r) {
	const walled = r.style === "bridge" || r.style === "catwalk"
		|| r.style === "canyon" || r.style === "tunnel";
	return walled ? (r.width + 12) / 2 : r.width / 2;
}

function main() {
	let bad = 0;
	for (const id of worlds.WORLD_IDS) {
		const L = worlds.LAYOUTS[id];
		console.log("WORLD " + id);
		for (const z of L.zones) {
			const doors = degree(L, z.id);
			const rims = worlds.rimKeptCount(z, openingsOf(L, z));
			const left = rims.kept;
			const flag = left < worlds.MIN_RIM_SEGMENTS ? "  APRETADA" : "";
			if (left < worlds.MIN_RIM_SEGMENTS) bad++;
			console.log(
				"  " + z.id.padEnd(12) + " puertas=" + doors +
				"  segmentos=" + String(rims.segs).padStart(3) +
				"  quedan=" + String(left).padStart(3) + flag
			);
		}
		console.log("");
	}
	console.log(bad ? "ZONAS APRETADAS: " + bad : "NINGUNA ZONA APRETADA");
	if (bad) process.exitCode = 1;
}

main();