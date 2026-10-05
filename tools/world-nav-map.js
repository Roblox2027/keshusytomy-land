"use strict";

// world-nav-map.js
// MAPA DE ALCANCE de una region, en ASCII, sobre la MISMA rejilla que
// `world-navigation-test.js`.
//
// POR QUE
// -------
// El diagnostico por zona dice QUE celda bloquea una zona. No dice por que el
// resto del mapa es inalcanzable cuando el bloqueo no aparece: ese caso es un
// salto de cota entre dos celdas caminables, y un salto no tiene bloqueador
// porque no hay pieza que lo cause. Solo se ve dibujando la rejilla.
//
// Uso: node tools/world-nav-map.js Cyber 1210 -1180

const nav = require("./world-navigation-test.js");

const WORLD = process.argv[2] || "Forest";
const CX = Number(process.argv[3] || 0);
const CZ = Number(process.argv[4] || 0);
const R = Number(process.argv[5] || 26);
const CELL = nav.constants.CELL;

/**
 * Lista las piezas de un folder del mundo con su caja.
 *
 * Es la otra mitad del mapa ASCII: el mapa dice DONDE esta el fallo y las
 * piezas dicen QUE lo causa. Con las dos se arregla sin adivinar.
 *
 * Uso: node tools/world-nav-map.js Cyber --parts Routes/Route_0_Gate_Corridor
 */
function dumpParts(worldId, folderPath) {
	const flat = nav.readTree().flat;
	const suffix = "." + folderPath.replace(/\//g, ".");
	for (const e of flat) {
		if (!e.path.startsWith("Workspace.Worlds." + worldId + ".")) continue;
		if (!e.path.endsWith(suffix) && !e.path.includes(suffix + ".")) continue;
		const p = e.node && e.node.$properties;
		if (!p || !Array.isArray(p.Position)) continue;
		const a = nav.aabbOf(e);
		if (!a) continue;
		console.log(
			e.path.split(".").pop().padEnd(34) +
			" pos=(" + p.Position[0].toFixed(1).padStart(8) + "," + p.Position[1].toFixed(1).padStart(6) + "," +
			p.Position[2].toFixed(1).padStart(8) + ")" +
			"  y " + a.y0.toFixed(1).padStart(6) + ".." + a.y1.toFixed(1).padStart(6) +
			"  coll=" + (p.CanCollide === true)
		);
	}
}

/**
 * FRONTERA DE ALCANCE: por que un area caminable no se puede alcanzar.
 *
 * El mapa ASCII dice DONDE esta el corte, pero no por que. Un area con suelo y
 * sin ningun bloqueador solo puede estar aislada por un DESNIVEL entre dos
 * celdas caminables, y un desnivel no tiene bloqueador porque no hay pieza que
 * lo cause: hay que compararlo.
 *
 * Recorre el borde del alcance y, para cada par (alcanzable, no alcanzable) que
 * son vecinos, imprime el desnivel y por que no se puede pasar. Esa es la
 * pregunta "por que esta zona esta aislada" con una respuesta.
 */
function frontier(id, cx, cz, radiusCells) {
	const flat = nav.readTree().flat;
	const grid = nav.buildGrid(flat, id);
	const mine = flat.filter((e) => e.path.startsWith("Workspace.Worlds." + id + "."));
	let spawnBox = null;
	for (const e of mine) {
		if (e.path.endsWith("SpawnPoint_" + id)) spawnBox = nav.aabbOf(e);
	}
	const spawn = nav.cellOf(grid, (spawnBox.x0 + spawnBox.x1) / 2, (spawnBox.z0 + spawnBox.z1) / 2);
	const reach = nav.reachableFrom(grid, spawn);

	const CELL = nav.constants.CELL;
	const c0 = Math.floor((cx - grid.minX) / CELL);
	const r0 = Math.floor((cz - grid.minZ) / CELL);
	const DIRS = [[-1, 0], [1, 0], [0, -1], [0, 1]];
	const rows = [];

	for (let dr = -radiusCells; dr <= radiusCells; dr++) {
		for (let dc = -radiusCells; dc <= radiusCells; dc++) {
			const r = r0 + dr;
			const c = c0 + dc;
			if (r < 0 || c < 0 || r >= grid.rows || c >= grid.cols) continue;
			const i = r * grid.cols + c;
			if (!nav.walkable(grid, i) || reach.seen[i]) continue;

			// Esta celda es caminable pero inalcanzable: alguno de sus vecinos
			// alcanzables tiene que explicar por que no se entra.
			for (const [ddr, ddc] of DIRS) {
				const jr = r + ddr;
				const jc = c + ddc;
				if (jr < 0 || jc < 0 || jr >= grid.rows || jc >= grid.cols) continue;
				const j = jr * grid.cols + jc;
				if (!reach.seen[j]) continue;
				const dy = grid.floorY[i] - grid.floorY[j];
				const px = grid.minX + (c + 0.5) * CELL;
				const pz = grid.minZ + (r + 0.5) * CELL;
				rows.push({
					px: px,
					pz: pz,
					dy: dy,
					from: grid.floorY[j],
					to: grid.floorY[i],
					why: dy > nav.constants.STEP_UP
						? "subida de " + dy.toFixed(2) + " studs (max " + nav.constants.STEP_UP + ")"
						: "descida de " + (-dy).toFixed(2) + " studs (max " + 3 + ")",
					blocker: grid.blockerPath[i] || "(sin bloqueador: el corte es el desnivel)",
				});
			}
		}
	}

	console.log("WORLD " + id + "   FRONTERA DE ALCANCE alrededor de (" + cx + ", " + cz + ")");
	console.log("");
	if (!rows.length) {
		console.log("  ninguna: o el area es alcanzable, o no hay ninguna celda caminable");
		console.log("  inalcanzable dentro del radio pedido.");
		return;
	}
	rows.sort(function (a, b) {
		return Math.abs(b.dy) - Math.abs(a.dy);
	});
	console.log("   pos                suelo_desde   suelo_hasta   desnivel   causa");
	for (const r of rows.slice(0, 24)) {
		console.log(
			"  (" + r.px.toFixed(0).padStart(7) + "," + r.pz.toFixed(0).padStart(7) + ")" +
			"   " + r.from.toFixed(2).padStart(8) + "   " + r.to.toFixed(2).padStart(9) + "   " +
			r.dy.toFixed(2).padStart(8) + "   " + r.why
		);
	}
	console.log("");
	const kinds = {};
	for (const r of rows) {
		const k = r.blocker.split(".").pop();
		kinds[k] = (kinds[k] || 0) + 1;
	}
	console.log("  bloqueadores en la frontera:");
	for (const k of Object.keys(kinds).sort(function (a, b) { return kinds[b] - kinds[a]; })) {
		console.log("    " + String(kinds[k]).padStart(4) + "  " + k);
	}
}

/**
 * QUE PIEZAS TOCAN UN PUNTO.
 *
 * La ultima pieza del diagnostico: cuando el mapa dice que una celda esta
 * bloqueada y el frontier dice que no hay desnivel, la unica pregunta que queda
 * es "que objeto ocupa esta caja", y responderla tiene que ser una consulta y
 * no una lectura de codigo.
 *
 * Uso: node tools/world-nav-map.js Cyber --at 1334 -1111
 */
function at(id, x, z, yLo, yHi) {
	const flat = nav.readTree().flat;
	for (const e of flat) {
		if (!e.path.startsWith("Workspace.Worlds." + id + ".")) continue;
		const p = e.node && e.node.$properties;
		if (!p || !Array.isArray(p.Position)) continue;
		const a = nav.aabbOf(e);
		if (!a) continue;
		if (x < a.x0 || x > a.x1 || z < a.z0 || z > a.z1) continue;
		if (yHi !== undefined && (a.y1 < yLo || a.y0 > yHi)) continue;
		console.log(
			"  y " + a.y0.toFixed(1).padStart(6) + ".." + a.y1.toFixed(1).padStart(6) +
			"  coll=" + String(p.CanCollide === true).padEnd(5) +
			"  " + e.path.replace("Workspace.Worlds." + id + ".", "")
		);
	}
}

function main() {
	if (process.argv.includes("--at")) {
		const i = process.argv.indexOf("--at");
		console.log("piezas en (" + process.argv[i + 1] + ", " + process.argv[i + 2] + ")");
		at(WORLD, Number(process.argv[i + 1]), Number(process.argv[i + 2]));
		return;
	}
	if (process.argv.includes("--frontier")) {
		const i = process.argv.indexOf("--frontier");
		frontier(WORLD, Number(process.argv[i + 1]), Number(process.argv[i + 2]), Number(process.argv[i + 3] || 14));
		return;
	}
	if (process.argv.includes("--zones")) {
		const flat = nav.readTree().flat;
		for (const e of flat) {
			if (!e.path.startsWith("Workspace.Worlds." + WORLD + ".")) continue;
			if (!/_Center$/.test(e.path)) continue;
			const p = e.node.$properties;
			const a = nav.aabbOf(e);
			const zoneName = e.path.split(".").slice(-2)[0];
			// El radio del nucleo es el radio REAL de la zona: el marcador de
			// centro mide 10x10 y no dice nada del tamano del sitio.
			const core = flat.find((q) => q.path === e.path.slice(0, -"_Center".length) + "_Core");
			const cb = core ? nav.aabbOf(core) : a;
			console.log(
				zoneName.replace(/^Zone_[A-Za-z]+_/, "").padEnd(12) +
				" pos=(" + p.Position[0].toFixed(1).padStart(9) + "," + p.Position[2].toFixed(1).padStart(9) + ")" +
				"  radio=(" + ((cb.x1 - cb.x0) / 2).toFixed(1).padStart(6) +
				"," + ((cb.z1 - cb.z0) / 2).toFixed(1).padStart(6) + ")"
			);
		}
		return;
	}
	if (process.argv.includes("--parts")) {
		const i = process.argv.indexOf("--parts");
		dumpParts(WORLD, process.argv[i + 1]);
		return;
	}
	const flat = nav.readTree().flat;
	const grid = nav.buildGrid(flat, WORLD);
	if (!grid) {
		console.log("sin geometria");
		return;
	}

	const mine = flat.filter((e) => e.path.startsWith("Workspace.Worlds." + WORLD + "."));
	let spawnBox = null;
	for (const e of mine) {
		if (e.path.endsWith("SpawnPoint_" + WORLD)) spawnBox = nav.aabbOf(e);
	}
	const spawn = nav.cellOf(grid, (spawnBox.x0 + spawnBox.x1) / 2, (spawnBox.z0 + spawnBox.z1) / 2);
	const reach = nav.reachableFrom(grid, spawn);

	const c0 = Math.floor((CX - grid.minX) / CELL);
	const r0 = Math.floor((CZ - grid.minZ) / CELL);
	console.log("WORLD " + WORLD + "   centro (" + CX + ", " + CZ + ")   spawn " + spawn +
		"   hay suelo=" + grid.floorY.length + " celdas");
	console.log("");
	console.log("  . alcanzable   , caminable pero NO alcanzable   # bloqueada   " +
		"(vacio) sin suelo   digitos = suelo_y");
	console.log("");

	const rows = [];
	for (let dr = -R; dr <= R; dr++) {
		let line = "";
		for (let dc = -R; dc <= R; dc++) {
			const r = r0 + dr;
			const c = c0 + dc;
			if (r < 0 || c < 0 || r >= grid.rows || c >= grid.cols) {
				line += "?";
				continue;
			}
			const i = r * grid.cols + c;
			if (grid.floorY[i] === -Infinity) line += " ";
			else if (grid.blocked[i]) line += "#";
			else if (reach.seen[i]) line += ".";
			else line += ",";
		}
		rows.push(String(Math.round(grid.minZ + (r0 + dr) * CELL)).padStart(7) + " " + line);
	}

	// Columna de alturas: el desnivel es lo que rompe un mapa sin muro.
	for (let dr = -R; dr <= R; dr++) {
		const r = r0 + dr;
		if (r < 0 || r >= grid.rows) continue;
		let heights = "";
		let flag = false;
		for (let dc = -R; dc <= R; dc++) {
			const c = c0 + dc;
			if (c < 0 || c >= grid.cols) {
				heights += " ";
				continue;
			}
			const y = grid.floorY[r * grid.cols + c];
			if (y === -Infinity) {
				heights += " ";
			} else if (y < 0) {
				heights += String(y);
			} else {
				heights += String(y);
				if (y > 9) flag = true;
			}
		}
		if (flag) rows.push("        " + " ".repeat(8) + "suelo_y: " + heights);
	}

	console.log(rows.join("\n"));
}

main();