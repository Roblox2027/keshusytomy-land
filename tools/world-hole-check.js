"use strict";

// world-hole-check.js
// VERIFICACION DE HUESCOS FINOS EN EL SUELO DE LOS MUNDOS
//
// POR QUE EXISTE
// ---------------
// `patchFloorHoles` (tools/worlds.js) sella huecos con una rejilla de 4 studs.
// El personaje de Roblox mide ~2 studs de ancho; con una rejilla de 4 un hueco
// de 2-3 estudios entre dos losas queda dentro de una celda Y el parcheador
// no lo detecta, y el jugador se cae al caminar.
//
// Este test usa UNA REJILLA DE 2 STUDS (no 4) y reproduce la misma logica de
// `patchFloorHoles`: una celda sin suelo rodeada de suelo por ambos lados opuestos
// es un hueco ENCLAVADO que el parcheador deberia haber sellado. Si el test lo
// encuentra, `patchFloorHoles` tiene un bug.
//
// Uso:  node tools/world-hole-check.js
// Sale con codigo 1 si algun mundo tiene huecos encerrados a 2 studs.

const nav = require("./world-navigation-test.js");

const WORLD_IDS = ["Forest", "Desert", "Ice", "Volcano", "Cyber"];
const CELL = 2;

function main() {
	const { flat } = nav.readTree();
	let totalHoles = 0;

	for (const worldId of WORLD_IDS) {
		const prefix = "Workspace.Worlds." + worldId + ".";
		const worldParts = flat.filter((e) => e.path.startsWith(prefix));

		const grid = nav.buildGrid(flat, worldId);
		if (!grid) continue;

		// buildGrid uses CELL=4. We need our own 2-stud scan.
		const floors = [];
		for (const e of worldParts) {
			const props = e.node.$properties;
			if (!props || props.CanCollide !== true) continue;
			const a = nav.aabbOf(e);
			if (!a) continue;
			const ex = a.x1 - a.x0, ez = a.z1 - a.z0, ey = a.y1 - a.y0;
			if (ex > ey && ez > ey && ex > CELL * 1.6 && ez > CELL * 1.6) {
				floors.push(a);
			}
		}

		let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
		for (const f of floors) {
			minX = Math.min(minX, f.x0); maxX = Math.max(maxX, f.x1);
			minZ = Math.min(minZ, f.z0); maxZ = Math.max(maxZ, f.z1);
		}
		const pad = CELL * 2;
		minX -= pad; maxX += pad; minZ -= pad; maxZ += pad;
		const cols = Math.ceil((maxX - minX) / CELL);
		const rows = Math.ceil((maxZ - minZ) / CELL);

		const floorY = new Array(cols * rows).fill(-Infinity);
		for (const f of floors) {
			const c0 = Math.max(0, Math.floor((f.x0 - minX) / CELL));
			const c1 = Math.min(cols - 1, Math.ceil((f.x1 - minX) / CELL) - 1);
			const r0 = Math.max(0, Math.floor((f.z0 - minZ) / CELL));
			const r1 = Math.min(rows - 1, Math.ceil((f.z1 - minZ) / CELL) - 1);
			for (let r = r0; r <= r1; r++) {
				for (let c = c0; c <= c1; c++) {
					const i = r * cols + c;
					if (f.y1 > floorY[i]) floorY[i] = f.y1;
				}
			}
		}

		const holes = [];
		for (let r = 1; r < rows - 1; r++) {
			for (let c = 1; c < cols - 1; c++) {
				const i = r * cols + c;
				if (floorY[i] !== -Infinity) continue;
				const up = floorY[(r - 1) * cols + c];
				const dn = floorY[(r + 1) * cols + c];
				const lf = floorY[r * cols + (c - 1)];
				const rt = floorY[r * cols + (c + 1)];
				const hasUp = up !== -Infinity, hasDn = dn !== -Infinity;
				const hasLf = lf !== -Infinity, hasRt = rt !== -Infinity;
				if ((hasUp && hasDn) || (hasLf && hasRt)) {
					const px = minX + (c + 0.5) * CELL;
					const pz = minZ + (r + 0.5) * CELL;
					holes.push({ x: px, z: pz, y: Math.max(
						hasUp ? up : 0, hasDn ? dn : 0, hasLf ? lf : 0, hasRt ? rt : 0
					)});
				}
			}
		}

		if (holes.length > 0) {
			totalHoles += holes.length;
			console.log("  HOLES en " + worldId + ": " + holes.length);
			for (const h of holes.slice(0, 10)) {
				console.log("    (" + Math.round(h.x) + ", " + Math.round(h.z) + ") y=" + h.y.toFixed(1));
			}
		} else {
			console.log("  " + worldId + ": OK (0 huecos a " + CELL + " studs)");
		}
	}

	console.log("");
	if (totalHoles === 0) {
		console.log("WORLD HOLE CHECK: PASS (0 huecos encerrados a " + CELL + " studs en los 5 mundos)");
	} else {
		console.log("WORLD HOLE CHECK: FAIL (" + totalHoles + " huecos encerrados, el parcheador no los sello)");
		process.exitCode = 1;
	}
}

main();
