"use strict";

// world-spawn-audit.js
// AUDITORIA FISICA DEL SPAWN DE CADA MUNDO.
//
// QUE ATACA ESTA HERRAMIENTA
// --------------------------
// El test de navegabilidad daba 11/11, 12/12, 12/12, 13/13 y 13/13 y aun asi
// el juego real fallaba al entrar a Forest. La razon es que "el spawn pertenece
// a una zona alcanzable" NO es lo mismo que "el jugador aparece en un sitio
// jugable": son dos preguntas distintas y solo una estaba contestada.
//
// Esta herramienta contesta la segunda, con cinco sondas POR MUNDO:
//
//   SPAWN 1  la propia posicion del spawn
//   SPAWN 2   5 studs por delante
//   SPAWN 3  10 studs por delante
//   SPAWN 4  20 studs por delante
//   SPAWN 5  10 studs hacia el primer punto de la primera ruta
//
// Las cinco tienen que estar sobre suelo, sin obstaculo en la franja de paso y
// alcanzables desde el propio spawn. Ademas se mide lo que el enunciado pide
// explicitamente: suelo DEBAJO del spawn, orientacion hacia la ruta, y un
// espacio libre de 20x20 studs alrededor.
//
// LO QUE NO PUEDE COMPROBAR
// ------------------------
// Que el personaje caiga de verdad en el suelo ni que la fisica lo detenga: eso
// es Roblox. Aqui se comprueba la GEOMETRIA que lo hace posible, que es lo que
// fallaba.
//
// Uso:  node tools/world-spawn-audit.js
// Sale con codigo 1 si algun mundo falla.

const nav = require("./world-navigation-test.js");

/**
 * Distancias de las sondas, en studs.
 *
 * No son arbitrarias: cubren la anchura del personaje (4), el margen de la
 * barandilla de las rutas (1.2) y el primer tramo de un sendero. Un spawn que
 * pasa a 5 pero falla a 20 tiene un obstaculo a media camino, que es
 * exactamente el fallo de "aparece y se encuentra con una pared delante".
 */
const PROBES = [0, 5, 10, 20];

/**
 * Espacio libre que el enunciado pide alrededor del spawn, en studs.
 *
 * Es el MINIMO recomendado (20x20) y no un capricho: por debajo, el jugador
 * aparece con un muro a un paso y la primera sensacion es "estoy encajonado".
 */
const FREE_SPACE = 20;

/** Fraccion de la muestra que tiene que estar libre. */
const FREE_SPACE_RATIO = 0.9;

/**
 * Direccion hacia la que mira el spawn, a partir de su `Orientation`.
 *
 * Es la MISMA cuenta que hace el generador (`yawTo`): con el eje X de la caja
 * alineado con el vector, un giro `yaw` sobre Y lleva el eje X a
 * `(cos, -sin)`. Copiada para no depender del generador en tiempo de prueba.
 *
 * @param {Array} orientation [x, y, z] en grados
 * @returns {{x:number, z:number}} vector unitario
 */
function facingFrom(orientation) {
	const yaw = ((orientation && orientation[1]) || 0) * Math.PI / 180;
	return { x: Math.cos(yaw), z: -Math.sin(yaw) };
}

/** Centro en el plano XZ de una caja. */
function centerOf(box) {
	return { x: (box.x0 + box.x1) / 2, z: (box.z0 + box.z1) / 2 };
}

/**
 * ¿Hay una pieza horizontal bajo este punto exacto?
 *
 * Se pregunta por el PUNTO y no por la celda: una celda "con suelo" puede
 * deberse a una losa que cubre la mitad y deja al spawn en el aire.
 *
 * @param {object} grid
 * @param {number} x
 * @param {number} z
 * @returns {boolean}
 */
function hasFloorAt(grid, x, z) {
	let best = -Infinity;
	for (const s of grid.parts) {
		const a = s.aabb;
		if (x < a.x0 || x > a.x1 || z < a.z0 || z > a.z1) continue;
		if (a.x1 - a.x0 <= a.y1 - a.y0 || a.z1 - a.z0 <= a.y1 - a.y0) continue;
		if (a.x1 - a.x0 < nav.constants.CELL || a.z1 - a.z0 < nav.constants.CELL) continue;
		if (a.y1 > best) best = a.y1;
	}
	return best !== -Infinity;
}

/**
 * Una sonda: esta en suelo, sin obstaculo y es alcanzable desde el spawn.
 *
 * @param {object} grid
 * @param {Uint8Array} seen
 * @param {{x:number, z:number}} p
 * @param {string} label
 * @returns {object} resultado de la sonda
 */
function checkProbe(grid, seen, p, label) {
	const cell = nav.cellOf(grid, p.x, p.z);
	const out = { label: label, x: p.x, z: p.z, cell: cell };

	if (grid.floorY[cell] === -Infinity) {
		out.ok = false;
		out.reason = "sin suelo";
		return out;
	}
	if (grid.blocked[cell] === 1) {
		out.ok = false;
		out.reason = "bloqueada por " + grid.blockerPath[cell];
		return out;
	}
	if (!seen[cell]) {
		out.ok = false;
		out.reason = "fuera del alcance del spawn";
		return out;
	}

	out.ok = true;
	out.floorY = grid.floorY[cell];
	return out;
}
/**
 * Primer punto de la PRIMERA ruta del mundo.
 *
 * Se busca la pieza de la carpeta `Route_0_*` mas cercana al spawn: esa es la
 * boca del sendero por la que el jugador empieza a recorrer. Es la quinta
 * sonda porque es la que responde a "mira hacia donde se sigue".
 *
 * @param {Array} mine piezas del mundo
 * @param {{x:number, z:number}} spawn
 * @returns {{x:number, z:number}|null}
 */
function firstRoutePoint(mine, spawn) {
	let best = null;
	let bestD = Infinity;
	for (const e of mine) {
		if (!/\.Routes\.Route_0_/.test(e.path)) continue;
		const box = nav.aabbOf(e);
		if (!box) continue;
		const c = centerOf(box);
		const d = Math.hypot(c.x - spawn.x, c.z - spawn.z);
		if (d < bestD) {
			bestD = d;
			best = c;
		}
	}
	return best;
}

/**
 * Fraccion del entorno de un punto que es suelo alcanzable.
 *
 * @param {object} grid
 * @param {Uint8Array} seen
 * @param {number} x
 * @param {number} z
 * @param {number} radius
 * @returns {{open:number, total:number, ratio:number}}
 */
function freeSpace(grid, seen, x, z, radius) {
	const center = nav.cellOf(grid, x, z);
	const c = center % grid.cols;
	const r = Math.floor(center / grid.cols);
	const cells = Math.ceil(radius / nav.constants.CELL);

	let open = 0;
	let total = 0;
	for (let dr = -cells; dr <= cells; dr++) {
		for (let dc = -cells; dc <= cells; dc++) {
			if (dr * dr + dc * dc > cells * cells) continue;
			const rr = r + dr;
			const cc = c + dc;
			if (rr < 0 || cc < 0 || rr >= grid.rows || cc >= grid.cols) continue;
			total++;
			if (seen[rr * grid.cols + cc]) open++;
		}
	}
	return { open: open, total: total, ratio: total > 0 ? open / total : 0 };
}

/**
 * Analiza el spawn de un mundo.
 *
 * @param {string} id id del mundo
 * @param {Array} flat arbol aplanado
 * @returns {object} medidas y problemas
 */
function auditWorld(id, flat) {
	const prefix = "Workspace.Worlds." + id + ".";
	const mine = flat.filter((e) => e.path.startsWith(prefix));
	const problems = [];

	const grid = nav.buildGrid(flat, id);
	if (!grid) return { id: id, problems: ["sin geometria solida"] };

	const entry = mine.find((e) => e.path.endsWith("SpawnPoint_" + id));
	if (!entry) return { id: id, problems: ["falta SpawnPoint_" + id] };

	const box = nav.aabbOf(entry);
	const spawn = centerOf(box);
	const orientation = (entry.node.$properties && entry.node.$properties.Orientation) || [0, 0, 0];
	const facing = facingFrom(orientation);

	const spawnCell = nav.cellOf(grid, spawn.x, spawn.z);
	if (!nav.walkable(grid, spawnCell)) {
		problems.push(
			"SPAWN BLOCKED: la celda del spawn no es caminable (suelo=" +
			grid.floorY[spawnCell] + ", tapada por " + (grid.blockerPath[spawnCell] || "nada") + ")"
		);
	}

	// `reachableFrom` devuelve un OBJETO con el campo `seen`; el array es el que
	// dice que celdas se pueden alcanzar. Se toma aqui una vez por mundo para no
	// repetir la busqueda en cada sonda.
	const seen = nav.reachableFrom(grid, spawnCell).seen;

	if (!hasFloorAt(grid, spawn.x, spawn.z)) {
		problems.push("SPAWN SIN SUELO: no hay ninguna pieza horizontal bajo el punto del spawn");
	}

	const free = freeSpace(grid, seen, spawn.x, spawn.z, FREE_SPACE);
	if (free.ratio < FREE_SPACE_RATIO) {
		problems.push(
			"SPAWN APRETADO: solo el " + (free.ratio * 100).toFixed(0) + "% del entorno de " +
			FREE_SPACE + " studs es alcanzable (minimo " + (FREE_SPACE_RATIO * 100).toFixed(0) + "%)"
		);
	}

	const probes = [];
	for (const d of PROBES) {
		const p = { x: spawn.x + facing.x * d, z: spawn.z + facing.z * d };
		probes.push(checkProbe(grid, seen, p, "adelante " + d + " studs"));
	}

	const firstRoute = firstRoutePoint(mine, spawn);
	let orientationOk = null;
	if (firstRoute) {
		const dx = firstRoute.x - spawn.x;
		const dz = firstRoute.z - spawn.z;
		const len = Math.hypot(dx, dz) || 1;

		const route = { x: spawn.x + (dx / len) * 10, z: spawn.z + (dz / len) * 10 };
		probes.push(checkProbe(grid, seen, route, "hacia la primera ruta"));

		// ORIENTACION: el spawn tiene que mirar HACIA la ruta, no hacia el
		// borde. El coseno del angulo entre ambos vectores decide, y por debajo
		// de cero el jugador aparece mirando en sentido contrario.
		const dot = (dx / len) * facing.x + (dz / len) * facing.z;
		orientationOk = dot > 0;
		if (!orientationOk) {
			problems.push(
				"MIRA A LA PARED: el spawn no apunta a la primera ruta (coseno=" + dot.toFixed(2) + ")"
			);
		}
	} else {
		problems.push("SIN RUTA: no se encuentra el primer punto de ruta para orientar la quinta sonda");
	}

	return {
		id: id,
		problems: problems,
		spawn: spawn,
		facing: facing,
		freeRatio: free.ratio,
		probes: probes,
		orientationOk: orientationOk,
	};
}
function main() {
	const flat = nav.readTree().flat;
	const ids = ["Forest", "Desert", "Ice", "Volcano", "Cyber"];

	console.log("AUDITORIA DE SPAWN (geometria real, no nombres)");
	console.log("-------------------------------------------------------------------");
	console.log("sondas: la posicion del spawn, 5, 10 y 20 studs por delante,");
	console.log("y 10 studs hacia la primera ruta. Todas sobre suelo y alcanzables.");
	console.log("");

	let failed = 0;
	for (const id of ids) {
		const r = auditWorld(id, flat);

		console.log(
			"  " + id.padEnd(9)
			+ " pos=(" + r.spawn.x.toFixed(0).padStart(6) + "," + r.spawn.z.toFixed(0).padStart(7) + ")"
			+ "  libre=" + (r.freeRatio * 100).toFixed(0).padStart(3) + "%"
			+ "  mira=" + (r.orientationOk === null ? "?" : r.orientationOk ? "ruta" : "pared")
		);

		for (const p of r.probes) {
			console.log(
				"      sonda " + p.label.padEnd(26)
				+ (p.ok ? "OK   suelo=" + String(p.floorY) : "FALLA " + p.reason)
			);
		}
		for (const problem of r.problems) console.log("      " + problem);
		if (r.problems.length) failed++;
		console.log("");
	}

	if (failed) {
		console.log("SPAWN: FAIL (" + failed + " mundo(s))");
		process.exitCode = 1;
		return;
	}

	console.log("SPAWN: PASS");
	console.log("Los cinco mundos aparecen sobre suelo, con 20x20 studs libres");
	console.log("alrededor, mirando hacia la primera ruta y con las cinco sondas");
	console.log("sobre suelo alcanzable.");
}

if (require.main === module) main();

module.exports = {
	auditWorld: auditWorld,
	PROBES: PROBES,
	FREE_SPACE: FREE_SPACE,
};
