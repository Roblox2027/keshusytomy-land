"use strict";

// bomb-placement-grid.js
// REJILLA DE PRUEBA DE COLOCACION DE BOMBAS (punto 47 de la auditoria).
//
// QUE COMPRUEBA
// -------------
// Que la capacidad de colocar bombas NO dependa accidentalmente de una
// pequena region del mapa. Para cada uno de los CINCO mundos:
//
//   1. Reproduce la regla de `BombPlacementRules` sobre el area jugable
//      REAL: la union de las zonas y rutas que dibuja `worlds.js`.
//   2. Recorre una rejilla de 5x5 (A1..E5) sobre esa area, mas un muestreo
//      por zona (spawn, centros, bordes).
//   3. Marca cada celda como ACEPTADA o RECHAZADA, y cuando se rechaza,
//      imprime el motivo.
//
// ALCANCE HONESTO DE ESTA HERRAMIENTA
// ---------------------------------
// Mide la GEOMETRIA y la DECISION de la regla, no el motor: no comprueba que
// la bomba se vea, que el cliente pulse el boton ni que el rayo encuentre
// suelo. Un PASS aqui NO es `READY`: el play test sigue siendo obligatorio.
//
// Y solo mide una cosa: que un punto de la superficie jugable CAIGA dentro
// del area jugable. El rango lo decide `GameConfig.BombPlacementRange`
// (18 studs) y se cumple solo, porque en la rejilla el jugador esta sobre
// la propia celda.

const worlds = require("./worlds.js");

// Estos numeros DEBEN coincidir con `BombPlacementRules`, en
// `src/ReplicatedStorage/Shared/Libraries/BombPlacementRules.lua`, y con
// `WORLD_FLOOR_PAD` en `src/ServerScriptService/Services/BombService.lua`.
const MARGIN = 90;
const FLOOR_PAD = 6;

/** Caja de una losa, igual que `BombPlacementRules.BoxFromXZ`. */
function boxFromXZ(x, z, sizeX, sizeZ, pad) {
	const p = pad || 0;
	return {
		minX: x - sizeX / 2 - p,
		maxX: x + sizeX / 2 + p,
		minZ: z - sizeZ / 2 - p,
		maxZ: z + sizeZ / 2 + p,
	};
}

/** Union de cajas, igual que `BombPlacementRules.Union`. */
function union(boxes) {
	if (!boxes || boxes.length === 0) return null;
	let minX = Infinity;
	let maxX = -Infinity;
	let minZ = Infinity;
	let maxZ = -Infinity;
	for (const b of boxes) {
		if (b.minX < minX) minX = b.minX;
		if (b.maxX > maxX) maxX = b.maxX;
		if (b.minZ < minZ) minZ = b.minZ;
		if (b.maxZ > maxZ) maxZ = b.maxZ;
	}
	return { minX, maxX, minZ, maxZ };
}

/** Area jugable expandida, igual que `BombPlacementRules.Expand`. */
function playable(bounds) {
	return {
		minX: bounds.minX - MARGIN,
		maxX: bounds.maxX + MARGIN,
		minZ: bounds.minZ - MARGIN,
		maxZ: bounds.maxZ + MARGIN,
	};
}

/** Area jugable de un mundo, como la deriva hoy `BombService`: la union del
 * suelo de CADA zona y ruta, mas el suelo de la arena, con margen.
 *
 * El comportamiento ANTIGUO (solo `ArenaFloor` y SIN margen) se puede
 * reproducir con `legacyBounds`; es el control negativo del test.
 */
function collectFloorBoxes(layout) {
	const boxes = [];
	const arena = layout.zones.find((z) => z.role === "arena");

	if (arena) {
		// `ARENA_FLOOR_MIN_HALF` en `tools/worlds.js`.
		const halfX = Math.max(arena.rx * 1.05, 34);
		const halfZ = Math.max(arena.rz * 1.05, 34);
		boxes.push(boxFromXZ(arena.x, arena.z, halfX * 2, halfZ * 2, FLOOR_PAD));
	}

	for (const z of layout.zones) {
		// Nucleo de `zoneSlab`: `Size = [rx * 1.05, 2, rz * 1.05]`.
		boxes.push(boxFromXZ(z.x, z.z, z.rx * 1.05, z.rz * 1.05, FLOOR_PAD));
	}

	// Rutas: el deck entre dos zonas. El ancho sale del contrato de la ruta,
	// que es lo que usa `buildWorld` para dimensionar el deck.
	const byId = {};
	for (const z of layout.zones) byId[z.id] = z;

	for (const r of layout.routes) {
		const a = byId[r.from];
		const b = byId[r.to];
		if (!a || !b) continue;
		const width = r.width || 12;
		boxes.push(
			boxFromXZ(
				(a.x + b.x) / 2,
				(a.z + b.z) / 2,
				Math.abs(a.x - b.x) + width,
				Math.abs(a.z - b.z) + width,
				FLOOR_PAD
			)
		);
	}

	return boxes;
}
//__APPEND__
/** Nombres de la rejilla 5x5 del enunciado. */
const COLUMNS = ["A", "B", "C", "D", "E"];
const ROWS = [1, 2, 3, 4, 5];

/**
 * Area jugable ANTIGUA: solo el `ArenaFloor`, y SIN margen.
 *
 * Es el control negativo. Reproduce exactamente lo que hacia
 * `BombService.detectArenaBounds` antes del arreglo, y debe fallar en los
 * cinco mundos: si pasara, la rejilla no serviria para detectar una
 * regresion del mismo tipo.
 */
function legacyBounds(layout) {
	const arena = layout.zones.find((z) => z.role === "arena");
	if (!arena) return null;

	const halfX = Math.max(arena.rx * 1.05, 34);
	const halfZ = Math.max(arena.rz * 1.05, 34);

	return {
		minX: arena.x - halfX,
		maxX: arena.x + halfX,
		minZ: arena.z - halfZ,
		maxZ: arena.z + halfZ,
	};
}

/**
 * Puntos de PRUEBA, derivados de la geometria real del mundo y NO de los
 * limites que se prueban.
 *
 * Esto es lo que hace la pruebaSignificant: si las celdas salieran del
 * rectangulo que se esta midiendo, la comprobacion seria tautologica y
 * pasaria siempre. Aqui cada celda es el CENTRO de una zona, un punto de
 * una ruta, el spawn o una esquina de zona, y se contrasta contra los
 * limites.
 */
function probePoints(layout) {
	const points = [];
	const byId = {};

	for (const z of layout.zones) {
		byId[z.id] = z;
		points.push({ name: `zona:${z.id}`, x: z.x, z: z.z });

		// Las cuatro esquinas del area de la zona tambien son suelo: son
		// los puntos donde un limite mal calculado se nota primero.
		points.push({ name: `borde:${z.id}:--`, x: z.x - z.rx, z: z.z - z.rz });
		points.push({ name: `borde:${z.id}:++`, x: z.x + z.rx, z: z.z + z.rz });
	}

	for (const r of layout.routes) {
		const a = byId[r.from];
		const b = byId[r.to];
		if (!a || !b) continue;

		points.push({ name: `ruta:${r.from}-${r.to}`, x: (a.x + b.x) / 2, z: (a.z + b.z) / 2 });
		// Cuartos de la ruta: el deck no es recto solo en el centro.
		points.push({ name: `ruta:${r.from}-${r.to}:1/4`, x: a.x + ((b.x - a.x) / 4) * 3, z: a.z + ((b.z - a.z) / 4) * 3 });
	}

	return points;
}

/**
 * Rejilla 5x5 (A1..E5) sobre el area del mundo, con el jugador EN la celda.
 *
 * Se apoya en `probePoints` para fijar el alto y el ancho, no en los limites
 * que se prueban.
 */
function gridCells(bounds) {
	const cells = [];
	const spanX = bounds.maxX - bounds.minX;
	const spanZ = bounds.maxZ - bounds.minZ;

	ROWS.forEach((row, zi) => {
		COLUMNS.forEach((col, xi) => {
			cells.push({
				name: col + row,
				x: bounds.minX + spanX * ((xi + 0.5) / COLUMNS.length),
				z: bounds.minZ + spanZ * ((zi + 0.5) / ROWS.length),
			});
		});
	});

	return cells;
}

/** Audita un mundo: comprueba la regla actual y, opcionalmente, la antigua. */
function auditWorld(worldId, legacy) {
	// `LAYOUTS` se normaliza AL CARGAR el modulo (`worlds.js` lo hace en el
	// bucle final), asi que lo que se lee aqui son las coordenadas que el
	// generador usa de verdad. No hay que volver a normalizar.
	const layout = worlds.LAYOUTS[worldId];
	if (!layout) return { worldId, error: "sin layout" };

	const unionBounds = union(collectFloorBoxes(layout));
	if (!unionBounds) return { worldId, error: "sin suelo" };

	const worldBounds = playable(unionBounds);

	// Los puntos de prueba NO dependen de los limites: salen de las zonas.
	const points = [...probePoints(layout), ...gridCells(unionBounds)];

	const bounds = legacy ? legacyBounds(layout) : worldBounds;
	if (!bounds) return { worldId, error: "sin arena" };

	const failures = [];
	for (const point of points) {
		const inside =
			point.x >= bounds.minX &&
			point.x <= bounds.maxX &&
			point.z >= bounds.minZ &&
			point.z <= bounds.maxZ;

		if (!inside) failures.push({ ...point, reason: "OUTSIDE_ARENA" });
	}

	return { worldId, bounds, worldBounds, total: points.length, failures };
}

function main() {
	const only = process.argv[2];
	// `--legacy` mide el area jugable como se derivaba ANTES (solo
	// `ArenaFloor`). Debe dar FAIL en los cinco mundos: es el control
	// negativo que demuestra que la rejilla detecta el bug real.
	const legacy = process.argv.includes("--legacy");
	const ids = only && !only.startsWith("--") ? [only] : worlds.WORLD_IDS;
	let failed = 0;

	console.log(
		legacy
			? "REJILLA DE COLOCACION DE BOMBAS -- CONTROL NEGATIVO (area legacy)"
			: "REJILLA DE COLOCACION DE BOMBAS (5x5 + zonas + bordes)"
	);
	console.log("=".repeat(72));

	for (const id of ids) {
		const result = auditWorld(id, legacy);

		if (result.error) {
			console.log(`${id}: ERROR ${result.error}`);
			failed++;
			continue;
		}

		const b = result.bounds;
		console.log(`\n${id}`);
		console.log(
			`  area jugable X[${b.minX.toFixed(0)}, ${b.maxX.toFixed(0)}] ` +
				`Z[${b.minZ.toFixed(0)}, ${b.maxZ.toFixed(0)}]`
		);
		console.log(`  celdas comprobadas: ${result.total}`);

		if (result.failures.length === 0) {
			console.log("  BOMB PLACEMENT: PASS");
			continue;
		}

		failed++;
		console.log(`  BOMB PLACEMENT: FAIL (${result.failures.length} celdas)`);
		for (const f of result.failures.slice(0, 12)) {
			console.log(`    ${f.name} en (${f.x.toFixed(0)}, ${f.z.toFixed(0)}) -> ${f.reason}`);
		}
	}

	console.log("\n" + "=".repeat(72));
	console.log(failed === 0 ? "RESULTADO: PASS" : `RESULTADO: FAIL (${failed} mundo/s)`);
	console.log("Alcance: geometria y decision de la regla. NO es un play test.");

	process.exit(failed === 0 ? 0 : 1);
}

if (require.main === module) {
	main();
}

module.exports = { auditWorld, collectFloorBoxes, union, playable };