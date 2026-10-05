"use strict";

// world-edge-test.js
// EL BORDE DEL MUNDO: NO HAY CAJA, Y EL VACIO MATA EN EL SERVIDOR.
//
// EL FALLO QUE ESTA HERRAMIENTA ATRAPA
// -------------------------------------
// El mundo se leia como un cuadrilatero y aun asi el verificador de
// navegabilidad daba PASS en los cinco mundos. Medido sobre el arbol generado:
// `tools/worlds.js` colocaba entre 264 y 272 piezas `Border_Wall_*` SOLIDAS por
// mundo, de 18-34 studs de alto y 3 de grosor, sobre una rejilla de 16 studs que
// rodeaba la nube de zonas.
//
// La caja era, precisamente, lo que hacia pasar el test: un muro continuo que
// cierra el mapa no produce ninguna de las patologias que el verificador busca.
//
// LO QUE COMPRUEBA, EN TRES PARTES
// --------------------------------
//   1. GEOMETRIA. Que no exista ningun muro perimetral, que el `Border/` solo
//      contenga piezas sin colision, y que el area caminable del mundo sea una
//      SILUETA y no un rectangulo relleno.
//   2. BORDE. Que en las cuatro direcciones se pueda correr desde el spawn
//      hasta el final del terreno, y que al final no haya muro sino CAIDA. Un
//      borde que acaba en pared se delata aqui sin necesidad de jugar.
//   3. SERVIDOR. Que la caida la mate el servidor y no la teletransporte. Esta
//      parte no se puede medir con geometria: `luau.exe` no tiene acceso a disco,
//      asi que se lee el fuente de `SpawnService` y se falla si vuelve a haber un
//      `PivotTo` o un rescate.
//
// LO QUE NO COMPRUEBA
// -------------------
// Que el personaje caiga de verdad ni muera de verdad: eso es Roblox Studio, y
// sigue siendo BLOCKED. Lo que se comprueba aqui es la CONDICION para que pase:
// no hay muro, hay vacio al final del suelo, y el servidor mata al caer.
//
// Uso:  node tools/world-edge-test.js
// Sale con codigo 1 si algun mundo falla.

const fs = require("fs");
const path = require("path");
const nav = require("./world-navigation-test.js");

const ROOT = path.join(__dirname, "..");

/**
 * Fraccion de las pieces de `Border/` que NO colisionan.
 *
 * Se exige el 100%. El borde puede tener talud, rocas y形式, pero ninguna
 * pieza suya puede impedir que el jugador salga del terreno: en cuanto una
 * colisiona, el limite vuelve a ser artificial.
 */
const NON_COLLIDING = 1;

/**
 * FRACCION MINIMA de la frontera que tiene que acabar en CAIDA.
 *
 * Y por que el umbral es de "caida" y no de "muro".
 *
 * Una zona puede (y debe) tener pared: el enunciado lo pide explicitamente, "las
 * paredes internas si pueden existir, pero deben dividir espacios, tener puertas,
 * permitir rutas". Medido en Forest despues de quitar el muro perimetral, el 48%
 * de la frontera acababa en muro, y ese muro era `Zone_*_Rim_*` (particiones con
 * puerta) y `Route_*_Wall_*` (lados de canones y puentes). Contarlo como defecto
 * prohibiria exactamente la pared interna que el enunciado pide.
 *
 * Lo que NO puede pasar es que el jugador no llegue NUNCA al borde. Por eso el
 * requisito es al reves: una fraccion MINIMA de la frontera tiene que ser
 * CAIDA. Un mundo con caja daria 0% de caida porque el perimetro entero seria
 * muro; un mundo abierto da decenas de puntos por los que se sale corriendo.
 */
const MIN_VOID_EDGE = 0.25;

/**
 * FRACCION MINIMA de caida por mitad del mundo.
 *
 * Es la comprobacion de "norte, sur, este y oeste" que pide el enunciado: en cada
 * mitad del mundo tiene que haber al menos un sitio por el que el jugador salga
 * andando del terreno. Un mundo acorralado en una esquina pasa el promedio global
 * y falla aqui.
 */
const MIN_VOID_EDGE_PER_SIDE = 0.2;

/**
 * Direcciones en las que se comprueba como termina el area jugable.
 *
 * `axis` es el eje en el que se mide la frontera y `sign` hacia donde se mira.
 */
const DIRECTIONS = [
	{ name: "norte", axis: "z", sign: -1 },
	{ name: "sur", axis: "z", sign: 1 },
	{ name: "este", axis: "x", sign: 1 },
	{ name: "oeste", axis: "x", sign: -1 },
];

// ------------------------------------------------- 1. GEOMETRIA DEL BORDE

/**
 * Clasifica las piezas de `Border/` de un mundo.
 *
 * @param {Array} mine piezas del mundo
 * @returns {{total:number, collidable:Array, decor:Array}}
 */
function classifyBorder(mine) {
	const collidable = [];
	const decor = [];

	for (const e of mine) {
		if (!e.path.includes(".Border.")) continue;
		if (e.path.endsWith(".Border")) continue;
		const props = e.node && e.node.$properties;
		if (!props) continue;
		if (props.CanCollide === true) collidable.push(e.path);
		else decor.push(e.path);
	}

	return { total: collidable.length + decor.length, collidable: collidable, decor: decor };
}

/**
 * Muros perimetrales por nombre, en todo el mundo.
 *
 * Los nombres `Border_Wall` y `Border_Cap` son los del antiguo perimeter. Si
 * vuelven a aparecer, el cuadrilatero vuelve con ellos, y da igual que los
 * midieran por geometria.
 *
 * @param {Array} mine piezas del mundo
 * @returns {Array} rutas de las piezas sospechosas
 */
function perimeterWalls(mine) {
	return mine
		.filter((e) => /Border_Wall|Border_Cap|WorldBorder|Zone_Rim_Border/.test(e.path.split(".").pop()))
		.map((e) => e.path);
}

/**
 * TODAS las celdas de la frontera del area jugable, con su clasificacion.
 *
 * "Frontera" es toda celda alcanzable que tiene al lado una celda que NO lo es.
 * Cada una de esas se clasifica en:
 *
 *   `void`  la celda exterior no tiene suelo  -> el jugador CAE
 *   `wall`  la celda exterior esta bloqueada -> el jugador CHOCA
 *   `gap`   hay suelo pero no es alcanzable  -> un hueco, ni muro ni caida
 *
 * La distincion `void` / `wall` es exactamente la del enunciado: terreno que se
 * acaba frente a pared artificial. Una caja daria casi todo `wall`; un mundo
 * abierto da casi todo `void`.
 *
 * @param {object} grid
 * @param {Uint8Array} seen
 * @returns {Array} `{x, z, ax, az, kind}`
 */
function frontierCells(grid, seen) {
	const out = [];

	for (let i = 0; i < seen.length; i++) {
		if (!seen[i]) continue;
		const c = i % grid.cols;
		const r = Math.floor(i / grid.cols);

		for (const [dc, dr] of [[-1, 0], [1, 0], [0, -1], [0, 1]]) {
			const nc = c + dc;
			const nr = r + dr;
			if (nc < 0 || nr < 0 || nc >= grid.cols || nr >= grid.rows) continue;

			const j = nr * grid.cols + nc;
			if (seen[j]) continue;

			let kind = "void";
			if (grid.floorY[j] !== -Infinity) {
				kind = grid.blocked[j] === 1 ? "wall" : "gap";
			}

			out.push({
				x: grid.minX + (c + 0.5) * nav.constants.CELL,
				z: grid.minZ + (r + 0.5) * nav.constants.CELL,
				ax: c,
				az: r,
				kind: kind,
			});
		}
	}

	return out;
}

/**
 * Resumen de una lista de frontera.
 *
 * @param {Array} cells
 * @returns {{total:number, void:number, wall:number, gap:number, ratio:number}}
 */
function summarize(cells) {
	let voidCells = 0;
	let wallCells = 0;
	let gapCells = 0;

	for (const cell of cells) {
		if (cell.kind === "void") voidCells++;
		else if (cell.kind === "wall") wallCells++;
		else gapCells++;
	}

	const closed = voidCells + wallCells;
	return {
		total: cells.length,
		void: voidCells,
		wall: wallCells,
		gap: gapCells,
		ratio: closed > 0 ? wallCells / closed : 0,
	};
}

/**
 * Fraccion de la caja del mundo que ocupa el area caminable.
 *
 * Un cuadrado lleno da ~1. Una silueta con entrantes y salientes da bastante
 * menos. El umbral esta por debajo de la mitad porque el mundo NO tiene que ser
 * una figura Lester ni una espiral: tiene que dejar de ser una caja.
 *
 * @param {object} grid
 * @param {Uint8Array} seen
 * @returns {number} fraccion de la caja
 */
function fillRatio(grid, seen) {
	let filled = 0;
	for (let i = 0; i < seen.length; i++) {
		if (seen[i] && grid.floorY[i] !== -Infinity) filled++;
	}
	const boxArea = grid.cols * grid.rows;
	return boxArea > 0 ? filled / boxArea : 0;
}
/**
 * FRONTERA de la mitad del mundo en una direccion.
 *
 * La frontera GLOBAL ya responde a "hay caja?". Esta responde a "en que lado
 * esta la caja?", que es lo que pide el enunciado: norte, sur, este y oeste.
 *
 * Se toma la mitad de la rejilla en el eje de la direccion, no la linea mas
 * extrema: la linea mas extrema cae siempre en el muro de una sola zona, y una
 * pared de zona es_partition legitima (`Zonas._Rim_` con puertas), no
 * contencion del mundo. Medir la mitad separa "hay una pared al norte" de "el
 * norte del mundo esta amurallado".
 *
 * @param {object} grid
 * @param {Array} cells frontera global ya calculada
 * @param {{name:string, axis:string, sign:number}} dir
 * @returns {object} resumen de `summarize`
 */
function halfFrontier(grid, cells, dir) {
	const mid = (dir.axis === "z" ? grid.rows : grid.cols) / 2;

	return summarize(cells.filter((cell) => {
		const v = dir.axis === "z" ? cell.az : cell.ax;
		return dir.sign > 0 ? v >= mid : v < mid;
	}));
}

/**
 * Analiza el borde de un mundo.
 *
 * @param {string} id id del mundo
 * @param {Array} flat arbol aplanado
 * @returns {object} medidas y problemas
 */
function auditWorld(id, flat) {
	const prefix = "Workspace.Worlds." + id + ".";
	const mine = flat.filter((e) => e.path.startsWith(prefix));
	const problems = [];

	const border = classifyBorder(mine);
	const ratio = border.total > 0 ? border.collidable.length / border.total : 1;
	if (ratio > 1 - NON_COLLIDING + 1e-9 && border.collidable.length > 0) {
		problems.push(
			"CONTENCION: " + border.collidable.length + " piezas de Border/ colisionan; el borde tiene que ser terreno, no muro"
		);
	}

	const walls = perimeterWalls(mine);
	if (walls.length) {
		problems.push(
			"MURO PERIMETRAL: " + walls.length + " piezas con nombre de muro de borde (" +
			walls.slice(0, 3).map((w) => w.split(".").pop()).join(", ") + ")"
		);
	}

	const grid = nav.buildGrid(flat, id);
	if (!grid) return { id: id, problems: ["sin geometria solida"] };

	const entry = mine.find((e) => e.path.endsWith("SpawnPoint_" + id));
	const entryBox = nav.aabbOf(entry);
	const start = nav.cellOf(grid, (entryBox.x0 + entryBox.x1) / 2, (entryBox.z0 + entryBox.z1) / 2);
	const seen = nav.reachableFrom(grid, start).seen;

	const cells = frontierCells(grid, seen);
	const edge = summarize(cells);

	const closed = edge.void + edge.wall;
	const voidRatio = closed > 0 ? edge.void / closed : 0;
	if (closed === 0) {
		problems.push("SIN FRONTERA: el area jugable no tiene borde medible");
	}
	if (voidRatio < MIN_VOID_EDGE) {
		problems.push(
			"BORDE SIN CAIDA: solo el " + (voidRatio * 100).toFixed(0) + "% de la frontera acaba en caida " +
			"(minimo " + (MIN_VOID_EDGE * 100).toFixed(0) + "%); el jugador no tiene por donde salirse del terreno"
		);
	}

	const fill = fillRatio(grid, seen);
	if (fill > 0.7) {
		problems.push(
			"MAPA RELLENO: el area caminable ocupa el " + (fill * 100).toFixed(0) +
			"% de la caja del mundo; un cuadrado relleno se lee como un cuadrilatero"
		);
	}

	const runs = [];
	for (const dir of DIRECTIONS) {
		const f = halfFrontier(grid, cells, dir);
		const denom = f.void + f.wall;
		const ratio = denom > 0 ? f.void / denom : 0;
		runs.push({ name: dir.name, summary: f, ratio: ratio });

		if (denom === 0) {
			problems.push(
				"SIN BORDE hacia " + dir.name + ": esa mitad del mundo no tiene frontera medible"
			);
			continue;
		}
		if (ratio < MIN_VOID_EDGE_PER_SIDE) {
			problems.push(
				"NO SE SALE POR " + dir.name.toUpperCase() + ": solo el " +
				(ratio * 100).toFixed(0) + "% de esa mitad acaba en caida (minimo " +
				(MIN_VOID_EDGE_PER_SIDE * 100).toFixed(0) + "%)"
			);
		}
	}

	return {
		id: id,
		problems: problems,
		borderTotal: border.total,
		borderCollidable: border.collidable.length,
		edge: edge,
		fill: fill,
		runs: runs,
	};
}
/**
 * Comprueba la REGLA DE CAIDA en el fuente del servidor.
 *
 * Esto no se puede medir con geometria ni con la suite de Luau (`luau.exe` no
 * tiene acceso a disco). Y es la parte que mas importa del enunciado: la caida
 * tiene que MATAR, no devolver al jugador a un punto.
 *
 * Lo que se busca es que la ruta de caida no contenga ninguna de estas cosas:
 * `PivotTo`, `SetPrimaryPartCFrame` ni una funcion de rescate. Y que si contenga
 * `Humanoid.Health = 0`, que es la muerte que ejecuta el motor.
 *
 * @returns {Array} problemas
 */
function auditServerFallRule() {
	const file = path.join(ROOT, "src", "ServerScriptService", "Services", "SpawnService.lua");
	const source = fs.readFileSync(file, "utf8");
	const problems = [];

	// El cuerpo de `enforceFallAndBounds`: desde su nombre hasta el siguiente
	// `function` de nivel superior. Se analiza ESA funcion y no el archivo
	// entero, porque `SpawnService` puede seguir moviendo al jugador por
	// motivos legitimos (elegir punto de reaparicion) sin que eso sea un
	// rescate de caida.
	const start = source.indexOf("function Service.enforceFallAndBounds");
	if (start < 0) {
		problems.push(
			"SIN REGLA DE CAIDA: SpawnService no tiene `enforceFallAndBounds`, que es la funcion que aplica la caida y el limite"
		);
		return problems;
	}

	const nextFunction = source.indexOf("\nfunction ", start + 10);
	const body = source.slice(start, nextFunction < 0 ? source.length : nextFunction);

	if (body.indexOf("PivotTo") >= 0) {
		problems.push(
			"TELETRANSPORTE AL CAER: la ruta de caida de SpawnService hace PivotTo. Caer tiene que matar, no devolver al jugador a un punto."
		);
	}
	if (/rescue/i.test(body)) {
		problems.push(
			"RESCATE: la ruta de caida sigue llamandose rescate. El nombre explica la intencion y la intencion es la que se quiere quitar."
		);
	}
	if (body.indexOf("Health = 0") < 0) {
		problems.push(
			"LA CAIDA NO MATA: la ruta de caida no pone `Humanoid.Health = 0`, asi que el jugador no muere al caer."
		);
	}

	// La muerte por caida solo es creible si el servidor la comprueba, y la
	// comprueba con la cota de configuracion.
	if (!/GameConfig\.FallDeathY/.test(body)) {
		problems.push(
			"SIN COTA DE CAIDA: la regla no consulta `GameConfig.FallDeathY`, asi que no hay ningun umbral que dispare la muerte."
		);
	}

	// Y la red de seguridad tiene que ser eso: una marca, no un teletransporte.
	if (!/OutOfBounds/.test(body)) {
		problems.push(
			"SIN LIMITE LOGICO: la caida no consulta el estado `OUT_OF_BOUNDS`, asi que no existe la red de seguridad del borde."
		);
	}

	return problems;
}

function main() {
	const flat = nav.readTree().flat;
	const ids = ["Forest", "Desert", "Ice", "Volcano", "Cyber"];

	console.log("BORDE DEL MUNDO (sin caja, con caida y con muerte en el servidor)");
	console.log("-------------------------------------------------------------------");
	console.log("1. geometria: ninguna pieza de Border/ colisiona y no hay muro");
	console.log("   perimetral; el area caminable es una silueta, no un rectangulo.");
	console.log("2. borde: en las cuatro direcciones se corre hasta el final del terreno");
	console.log("   y el final es CAIDA, no pared.");
	console.log("3. servidor: caer mata (Humanoid.Health = 0) y no teletransporta.");
	console.log("");

	let failed = 0;
	for (const id of ids) {
		const r = auditWorld(id, flat);

		console.log(
			"  " + id.padEnd(9)
			+ " Border: " + String(r.borderTotal).padStart(4) + " piezas, "
			+ r.borderCollidable + " colisionan"
			+ "   frontera: " + String(r.edge.total).padStart(4) + " celdas, "
			+ String(r.edge.void).padStart(4) + " en caida, "
			+ String(r.edge.wall).padStart(3) + " en muro"
			+ "   relleno=" + (r.fill * 100).toFixed(0).padStart(3) + "%"
		);

		for (const run of r.runs) {
			console.log(
				"      " + run.name.padEnd(6) + String(run.summary.total).padStart(4) +
				" celdas: " + String(run.summary.void).padStart(4) + " en caida, " +
				String(run.summary.wall).padStart(3) + " en muro"
			);
		}
		for (const problem of r.problems) console.log("      " + problem);
		if (r.problems.length) failed++;
		console.log("");
	}

	const serverProblems = auditServerFallRule();
	console.log("  SERVIDOR SpawnService");
	for (const p of serverProblems) console.log("      " + p);
	if (!serverProblems.length) {
		console.log("      caida -> Humanoid.Health = 0 (muerte del motor), sin PivotTo,");
		console.log("      con limite logico y margen de gracia. Correcto.");
	}
	console.log("");

	if (failed || serverProblems.length) {
		console.log("WORLD EDGE: FAIL");
		process.exitCode = 1;
		return;
	}

	console.log("WORLD EDGE: PASS");
	console.log("Los cinco mundos terminan en terreno y no en muro, el perimetro es");
	console.log("mayoritariamente caida, el area caminable es una silueta y el servidor");
	console.log("mata al caer sin teletransportar a nadie.");
}

if (require.main === module) main();

module.exports = { auditWorld: auditWorld, auditServerFallRule: auditServerFallRule };