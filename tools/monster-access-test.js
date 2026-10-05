"use strict";

// monster-access-test.js
// CADA SPAWN DE MONSTRUO TIENE QUE ESTAR EN EL ESPACIO DEL JUGADOR.
//
// EL FALLO QUE ESTA HERRAMIENTA ATRAPA
// ------------------------------------
// El enunciado del P0 lo describe asi: "PLAYER OUTSIDE, MONSTERS INSIDE". Es
// un fallo real y medido: sobre el arbol generado, 13 de los 30 spawns de los
// cinco mundos caian sobre algo que no es suelo util y 2 no tenian suelo en
// absoluto.
//
//   MonsterSpawn_Forest_00    sobre Cover_Pillar_Clearing_0
//   MonsterSpawn_Forest_05    sobre el muro del canon Arena -> Grooty
//   MonsterSpawn_Desert_01    sobre la cobertura de Pillars
//   MonsterSpawn_Ice_01       en una costura entre dos losas, con el vacio debajo
//   MonsterSpawn_Cyber_00     a 1,5 studs de un Cover_Slab
//
// Ni el test de estructura ni el de navegabilidad lo ven: los dos comprueban
// que el spawn EXISTE y que las zonas se conectan. Este comprueba que el punto
// concreto es un sitio al que el jugador puede LLEGAR.
//
// LAS CINCO CONDICIONES
// ---------------------
// Para cada `MonsterSpawn_<Id>_<nn>`:
//   1. hay suelo bajo el punto EXACTO, no solo en su celda;
//   2. la celda no esta bloqueada por ninguna pieza en la franja de paso;
//   3. la celda es alcanzable desde el SPAWN DEL JUGADOR (no desde el centro de
//      la zona): sin esto, el monstruo esta dentro y el jugador fuera;
//   4. hay sitio alrededor para que aparezca y para que se le pueda rodear;
//   5. dos spawns de la misma zona no nacen uno encima del otro.
//
// EXCEPCION DOCUMENTADA
// --------------------
// El enunciado admite monstruos "especificamente disenados para una arena
// cerrada de boss o evento". En este mapa no existe todavia ninguno: los cinco
// mundos son arenas abiertas. Si algun dia lo hubiera, este test es el sitio
// donde se declara la excepcion, no donde se ignora en silencio.
//
// Uso:  node tools/monster-access-test.js
// Sale con codigo 1 si algun spawn es invalido.

const nav = require("./world-navigation-test.js");
const worlds = require("./worlds.js");

/**
 * Radios de las zonas de un mundo, para aplicar las MISMAS reglas que usa el
 * generador.
 *
 * Se leen de los `_Core` de cada zona (la losa que se pisa) y no de una copia de
 * numeros: `monsterSpawnSpacing` y `monsterSpawnClearance` se importan del
 * generador, que es quien decide donde coloca los spawns. Un verificador con sus
 * propios numeros deja de corresponded al mundo en cuanto se tocan.
 *
 * @param {Array} mine piezas del mundo
 * @returns {Array} `{name, x, z, rx, rz}`
 */
function zoneList(mine) {
	const out = [];
	const seen = new Set();

	for (const e of mine) {
		const m = /Zones\.(Zone_[A-Za-z]+_[A-Za-z0-9]+)\.(.*)$/.exec(e.path);
		if (!m) continue;
		const folder = m[1];
		if (seen.has(folder)) continue;

		const core = mine.find((q) => q.path.endsWith("Zones." + folder + "." + folder + "_Core"));
		if (!core) continue;

		const cb = nav.aabbOf(core);
		if (!cb) continue;
		seen.add(folder);

		out.push({
			name: folder.replace(/^Zone_[A-Za-z]+_/, ""),
			x: (cb.x0 + cb.x1) / 2,
			z: (cb.z0 + cb.z1) / 2,
			rx: (cb.x1 - cb.x0) / 2,
			rz: (cb.z1 - cb.z0) / 2,
		});
	}

	return out;
}

/**
 * Zona mas cercana a un punto, o null.
 *
 * Los spawns de monstruo viven en la carpeta de CONTRATO `MonsterSpawns/`, que es
 * plana: no hay ninguna carpeta de zona de la que deducir a cual pertenecen. La
 * zona se deduce por proximidad al centro, que es geometria y no una convencion
 * de nombres.
 *
 * @param {Array} zones zonas del mundo
 * @param {number} x
 * @param {number} z
 * @returns {object?} zona
 */
function nearestZone(zones, x, z) {
	let best = null;
	let bestD = Infinity;
	for (const zone of zones) {
		const d = Math.hypot(zone.x - x, zone.z - z);
		if (d < bestD) {
			bestD = d;
			best = zone;
		}
	}
	return best;
}

/**
 * Radio de holgura alrededor del spawn, en studs.
 *
 * Es el doble de la anchura del marcador (3). Un spawn sin holgura es un
 * spawn que el jugador no ve aparecer y al que no puede acercarse sin chocar.
 */
const CLEARANCE = 6;

/**
 * Separacion minima entre dos spawns de la MISMA zona, en studs.
 *
 * Es lo que permite verlos por separado. Con dos biches a 10 studs, uno aparece
 * dentro del otro y el jugador no puede decidir a cual ataca.
 */
const SPACING = 34;

/**
 * ¿Hay suelo horizontal bajo este punto exacto?
 *
 * Se pregunta por el punto y no por la celda porque el fallo de `Ice_01` fue
 * exactamente ese: la celda tenia suelo (una losa del anillo la cubria a
 * medias) y el punto caia en la costura, con el vacio debajo.
 *
 * @param {object} grid
 * @param {number} x
 * @param {number} z
 * @returns {number} cota del suelo, o -Infinity
 */
function floorAt(grid, x, z) {
	let best = -Infinity;
	for (const s of grid.parts) {
		const a = s.aabb;
		if (x < a.x0 || x > a.x1 || z < a.z0 || z > a.z1) continue;
		const ex = a.x1 - a.x0;
		const ez = a.z1 - a.z0;
		const ey = a.y1 - a.y0;
		if (ex <= ey || ez <= ey) continue;
		if (ex < nav.constants.CELL || ez < nav.constants.CELL) continue;
		if (a.y1 > best) best = a.y1;
	}
	return best;
}

/**
 * ¿Hay algun solido invadiendo el DISCO de holgura alrededor del punto?
 *
 * Se mide la MISMA cosa que mide el generador: un solido cuya caja toca el disco
 * de radio `radius` y ocupa la franja de paso. Medirlo muestreando puntos dejaba
 * pasar el borde de las piezas, y el generador colocaba spawns a 4 studs de un
 * muro; medirlo por celdas inflateba el requisito y hacia imposible tener dos
 * bichos. Caja contra disco, en los dos lados, con la misma aritmetica.
 *
 * @param {object} grid
 * @param {number} x
 * @param {number} z
 * @param {number} radius holgura exigida, en studs
 * @param {number} floorY cota del suelo bajo el punto
 * @returns {boolean}
 */
function hasClearance(grid, x, z, radius, floorY) {
	for (const s of grid.parts) {
		const b = s.aabb;
		if (b.x1 < x - radius || b.x0 > x + radius) continue;
		if (b.z1 < z - radius || b.z0 > z + radius) continue;

		const dx = Math.max(b.x0 - x, 0, x - b.x1);
		const dz = Math.max(b.z0 - z, 0, z - b.z1);
		if (dx * dx + dz * dz > radius * radius) continue;

		if (b.y1 <= floorY + nav.constants.STEP_UP) continue;
		if (b.y0 >= floorY + nav.constants.PLAYER_HEADROOM) continue;

		return false;
	}
	return true;
}
/**
 * Analiza todos los spawns de monstruo de un mundo.
 *
 * @param {string} id id del mundo
 * @param {Array} flat arbol aplanado
 * @returns {object} lista de spawns con su veredicto
 */
function auditWorld(id, flat) {
	const prefix = "Workspace.Worlds." + id + ".";
	const mine = flat.filter((e) => e.path.startsWith(prefix));

	const grid = nav.buildGrid(flat, id);
	if (!grid) return { id: id, spawns: [], fatal: "sin geometria solida" };

	const entry = mine.find((e) => e.path.endsWith("SpawnPoint_" + id));
	if (!entry) return { id: id, spawns: [], fatal: "falta SpawnPoint_" + id };
	const entryBox = nav.aabbOf(entry);

	// El alcance se mide desde el spawn del JUGADOR. Es la diferencia entre
	// "el spawn esta en el mundo" y "el jugador puede llegar a el".
	const playerCell = nav.cellOf(grid, (entryBox.x0 + entryBox.x1) / 2, (entryBox.z0 + entryBox.z1) / 2);
	const seen = nav.reachableFrom(grid, playerCell).seen;

	const arenaCenter = mine.find((e) => e.path.endsWith("." + id + ".ArenaCenter"));
	const arenaBox = arenaCenter ? nav.aabbOf(arenaCenter) : null;

	const zones = zoneList(mine);
	const out = [];
	const placed = [];

	for (const e of mine) {
		if (!/MonsterSpawns\.MonsterSpawn_/.test(e.path)) continue;
		const box = nav.aabbOf(e);
		if (!box) continue;

		const pos = e.node.$properties.Position;
		const x = pos[0];
		const z = pos[2];
		const cell = nav.cellOf(grid, x, z);
		const reasons = [];

		// 1. Suelo bajo el punto exacto.
		const floor = floorAt(grid, x, z);
		if (floor === -Infinity) reasons.push("sin suelo bajo el punto");

		// 2. Nada en la franja de paso.
		if (grid.blocked[cell] === 1) {
			reasons.push("bloqueada por " + shortName(grid.blockerPath[cell]));
		}

		// 3. Alcanzable desde el spawn del JUGADOR.
		if (!seen[cell]) reasons.push("no se puede llegar andando desde el spawn del jugador");

		// La zona decide los dos margenes, y son los del generador.
		const zone = nearestZone(zones, x, z);
		const clearance = zone ? worlds.monsterSpawnClearance(zone.rx, zone.rz) : CLEARANCE;
		const spacing = zone ? worlds.monsterSpawnSpacing(zone.rx, zone.rz) : SPACING;

		// 4. Holgura alrededor.
		if (floor !== -Infinity && !hasClearance(grid, x, z, clearance, floor)) {
			reasons.push("sin sitio alrededor para aparecer");
		}

		// 5. Separacion respecto a los spawns ya colocados DE LA MISMA ZONA.
		if (zone) {
			for (const q of placed) {
				if (q.zone !== zone.name) continue;
				if (Math.hypot(x - q.x, z - q.z) < spacing) {
					reasons.push("a " + Math.round(Math.hypot(x - q.x, z - q.z))
						+ " studs de " + q.name + " (minimo " + Math.round(spacing) + " para esta zona)");
					break;
				}
			}
		}

		const toArena = arenaBox
			? Math.hypot(x - (arenaBox.x0 + arenaBox.x1) / 2, z - (arenaBox.z0 + arenaBox.z1) / 2)
			: null;

		const name = e.path.split(".").pop();
		out.push({
			name: name,
			zone: zone ? zone.name : "?",
			x: x,
			z: z,
			floorY: floor,
			cell: cell,
			toArena: toArena,
			ok: reasons.length === 0,
			reasons: reasons,
		});

		placed.push({ name: name, zone: zone ? zone.name : "?", x: x, z: z });
	}

	return { id: id, spawns: out };
}

/**
 * Zona a la que pertenece un spawn, por el nombre de su carpeta.
 *
 * @param {string} path ruta de la pieza
 * @returns {string} nombre de la zona, o "?" si no se deduce
 */
function zoneOf(path) {
	const m = /Zones\.(Zone_[A-Za-z]+_[A-Za-z0-9]+)\./.exec(path);
	return m ? m[1].replace(/^Zone_[A-Za-z]+_/, "") : "?";
}

/**
 * Nombre corto de una pieza, sin el prefijo del mundo.
 *
 * @param {string} path
 * @returns {string}
 */
function shortName(path) {
	return String(path || "").replace(/^Workspace\.Worlds\.[A-Za-z]+\./, "");
}
function main() {
	const flat = nav.readTree().flat;
	const ids = ["Forest", "Desert", "Ice", "Volcano", "Cyber"];

	console.log("ACCESO DE MONSTRUOS (spawn vs. espacio del jugador)");
	console.log("-------------------------------------------------------------------");
	console.log("cada MonsterSpawn necesita suelo bajo el punto, franja de paso libre,");
	console.log("ruta andando desde el spawn del JUGADOR, holgura alrededor y separacion.");
	console.log("");

	let total = 0;
	let valid = 0;
	let failedWorlds = 0;

	for (const id of ids) {
		const r = auditWorld(id, flat);

		if (r.fatal) {
			console.log("  " + id.padEnd(9) + " " + r.fatal);
			failedWorlds++;
			continue;
		}

		const ok = r.spawns.filter((s) => s.ok).length;
		total += r.spawns.length;
		valid += ok;

		console.log(
			"  " + id.padEnd(9)
			+ " " + String(ok).padStart(2) + "/" + String(r.spawns.length).padStart(2) + " validos"
			+ "   (minimo " + (r.spawns.length ? Math.min.apply(null, r.spawns.map((s) => s.toArena)).toFixed(0) : "-")
			+ " studs a la arena, maximo "
			+ (r.spawns.length ? Math.max.apply(null, r.spawns.map((s) => s.toArena)).toFixed(0) : "-") + ")"
		);

		for (const s of r.spawns) {
			if (s.ok) {
				console.log(
					"      " + s.name.padEnd(26) + " OK    zona=" + s.zone.padEnd(12)
					+ " suelo=" + String(s.floorY).padStart(5)
					+ "  a la arena=" + s.toArena.toFixed(0).padStart(4) + " st"
				);
				continue;
			}
			console.log("      " + s.name.padEnd(26) + " FALLA " + s.reasons.join("; "));
		}
		if (ok !== r.spawns.length) failedWorlds++;
		console.log("");
	}

	if (failedWorlds || valid !== total) {
		console.log("MONSTER ACCESS: FAIL (" + (total - valid) + " spawn(s) invalidos)");
		process.exitCode = 1;
		return;
	}

	console.log("MONSTER ACCESS: PASS");
	console.log(valid + "/" + total + " spawns de monstruo estan en suelo, libres y son");
	console.log("alcanzables andando desde el spawn del jugador. No hay PLAYER OUTSIDE /");
	console.log("MONSTERS INSIDE en ninguno de los cinco mundos.");
}

if (require.main === module) main();

module.exports = { auditWorld: auditWorld, CLEARANCE: CLEARANCE, SPACING: SPACING };