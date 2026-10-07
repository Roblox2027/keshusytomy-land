"use strict";

// world-navigation-test.js
// VALIDACION DE NAVEGABILIDAD POR GEOMETRIA, no por nombres.
//
// EL PROBLEMA QUE ESTE SCRIPT ATRAPA
// ----------------------------------
// Un verificador de contrato (que existan `ArenaCenter`, `BossSpawn_*`, `Exit_*`)
// y un verificador de estructura (que haya 11 zonas y 15 rutas) pueden dar PASS
// sobre un mundo donde el jugador no puede pasar de la entrada a la arena. Es un
// fallo real, no hipotetico: basta con que el borde de una zona se cierre en el
// angulo por donde entra la ruta, y la zona queda sellada. El nombre de la zona
// sigue ahi, la ruta sigue ahi, y el jugador se queda delante de un muro.
//
// LA REGLA DE ORO
// ---------------
// Nada de esto se decide por NOMBRE. Se decide RELLENANDO una rejilla con las
// PIEZAS REALES del arbol generado y preguntando si se puede caminar de un punto
// a otro. Un verificador que lee nombres no puede ver un deadlock; uno que lee
// geometria, si.
//
// EL MODELO DE SUELO (2.5D)
// --------------------------
// Los mundos tienen cotas distintas (el bosque sube a y=6, el desierto a y=4),
// asi que una rejilla 2D plana no basta. Por eso cada celda guarda la ALTURA DEL
// SUELO: la de la cara superior de la pieza horizontal mas alta que la cubre.
// Encima de esa altura se comprueba si hay algo que estorbe.
//
// No se simula el motor de Roblox. Se simula lo que el motor hace de forma
// relevante para "el jugador puede pasar por aqui":
//
//   1. el suelo mas alto gana (no se cae por debajo del suelo que hay encima);
//   2. cualquier pieza solida que ocupe la franja [suelo - MIN_DROP,
//      suelo + PLAYER_HEADROOM] BLOQUEA la celda;
//   3. el paso necesita aire libre encima.
//
// QUE MIDE, Y POR QUE CADA COSA ES UN FAIL
// -----------------------------------------
//   CRITICAL PATH BLOCKED   no se llega de spawn a arena
//   BOSS ROUTE BLOCKED      el jefe es inalcanzable
//   EXIT ROUTE BLOCKED      la salida es inalcanzable (el mundo es una ratonera)
//   SPAWN TRAP              el jugador aparece encerrado
//   GIANT WALL DEADLOCK     un muro recto separa el mundo en dos mitades
//   TINY ARENA              la arena no da espacio para pelear
//   TUNNEL WORLD            casi todo el mapa es inalcanzable
//   SINGLE-CORRIDOR WORLD   las rutas criticas son de 1-2 celdas de ancho
//
// LA RUTA ALTERNATIVA SE MIDE DE VERDAD
// ------------------------------------
// No basta con contar que hay dos rutas declaradas: pueden ser dos caminos al
// mismo sitio. Aqui se calculan dos caminos optimos distintos (el de mayor
// anchura y el mas corto) y se comprueba que sigue habiendo camino cuando se TAPA
// el mas corto, que es la forma de demostrar redundancia real.
//
// TODO SE MIDE SOBRE `default.project.json`
// ----------------------------------------
// El arbol GENERADO, no el runtime, por el mismo motivo que en
// `world-structure-test.js`: un fallo de navegabilidad debe romper el build, no
// aparecer tres semanas despues en una captura de pantalla.
//
// Uso:  node tools/world-navigation-test.js
// Sale con codigo 1 si algun mundo falla.

const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..");
const PROJECT = path.join(ROOT, "default.project.json");

const WORLD_IDS = ["Forest", "Desert", "Ice", "Volcano", "Cyber"];

/**
 * Resolucion de la rejilla, en studs por celda.
 *
 * 4 studs es grueso pero suficiente: el jugador mide 4 de ancho y una celda de 4
 * no deja "colarse" por un hueco que un jugador real no cruza. Afinar a 2
 * duplicaria el coste sin cambiar ningun veredicto, porque los obstaculos del
 * mapa se miden en decenas de studs.
 */
const CELL = 4;

/**
 * Aire libre MINIMO sobre el suelo, en studs.
 *
 * El personaje de Roblox mide unos 5 studs de alto. 7 deja pasar con dos studs
 * de margen, que es lo que hace falta para que un jugador normal no se atasque.
 *
 * El valor es un CONTRATO con el generador, no una cifra arbitraria. Los tuneles
 * de Cyber tienen el techo a 8 studs: eso es un paso de verdad, no un tunnel, y
 * con un limite de 10 el verificador los daba por cerrados y Cyber se quedaba
 * con UNA zona alcanzable de doce. Medido: `Gate` alcanzable y `Corridor` no.
 *
 * Por encima de esta altura el jugador no esta: es decoracion, DSM, cornisas o
 * copas de arbol. Contarlas como obstaculo convertiria un bosque en una caja.
 */
const PLAYER_HEADROOM = 7;

/**
 * Margen bajo el suelo por debajo del cual el hueco es un SOCAVON, no un paso.
 *
 * El suelo mas alto manda. Si la siguiente losa esta dos studs mas abajo se baja
 * andando; si esta diez mas abajo, es un precipicio.
 */
const MIN_DROP = 2.5;

/**
 * Desnivel que el jugador sube y baja caminando, en studs.
 *
 * Es una regla de DISENO, no una medicion del motor. El personaje de Roblox
 * sube Escaleras y escalones de 1-2 studs sin saltar; 4 es el limite conservador
 * para que el test no exija saltar por un escalon decorativo, y al mismo tiempo
 *no deje pasar una pared disfrazada de rampilla.
 */
const STEP_UP = 4;

/**
 * Altura a partir de la cual una pieza deja de ser un ESCALON y pasa a ser MURO.
 *
 * Esta es la regla que hace que el modelo no se rompa con los objetos que el
 * generador pone tumbados sobre el suelo: el `SpawnLocation` es una plataforma
 * de 1 stud encima de la losa de la zona, y las losas elevadas del borde de zona
 * suben 1 stud. Medidas como muro, cada una cerraba su propia celda y el mundo
 * entero quedaba "inalcanzable" en el test sin que hubiera un solo muro de verdad.
 */
const STEP_TOLERANCE = 1.5;

/**
 * Ancho de corredor aceptable, en studs.
 *
 * Dos celdas. Por debajo el jugador no puede rodear a un enemigo ni esquivar una
 * explosion: esta encerrado en un pasillo y la decision de donde poner la bomba
 * desaparece.
 */
const MIN_CORRIDOR = 8;

/**
 * Desnivel que el jugador sube Y BAJA.
 *
 * Sube 4, pero BAJA 6, y no es arbitrario. En Roblox, bajar un escalon de mas
 * de la altura del personaje (5 studs) no es caminar: es caerse. Con el mismo
 * limite en las dos direcciones, una bajada de 6 studs cortaba el paso y las
 * zonas bajas quedaban inalcanzables desde las altas. Medido en Forest: `Bridge`
 * esta a y=6 y `Hollow` a y=0, y la bajada de 6 studs era una pared.
 *
 * Sube 4 y no mas porque el limite alto lo pone `ROUTE_STEP` del generador (2
 * studs por losa): una rampa mas empinada seria un muro disfrazado.
 */
const STEP_DOWN = 6;

/**
 * Longitud a partir de la cual un muro recto se considera gigante.
 *
 * Un muro de 120 studs en linea recta parte el mapa en dos mitades. No es
 * automaticamente un FAIL: un mundo puede tener un rio con un puente. Es un FAIL
 * cuando el spawn solo alcanza un lado.
 */
const GIANT_WALL_LENGTH = 120;

/** Radio alrededor del spawn que debe quedar libre, en studs. */
const SPAWN_TRAP_RADIUS = 26;

/** Radio de la arena que debe quedar libre, en studs. */
const ARENA_RADIUS = 30;

/** Area libre minima de la arena, en studs2. */
const MIN_ARENA_AREA = 900;

/**
 * Radio libre MINIMO de la arena, en studs.
 *
 * La especificacion de fase pide arenas de "aproximadamente 60x60 studs". Un
 * area suelta no dice eso: un disco de 30 studs dentro de una explanada mas
 * grande pasa el area y no dice nada del margen que tiene el jugador para
 * poner una bomba y salir.
 *
 * El radio libre es el mayor disco alrededor del centro de la arena que sigue
 * siendo SUELO ALCANZABLE en su practica totalidad. Se busca por pasos de 2
 * studs desde el minimo hacia arriba, y el primero que se cumple es el
 * radio libre: a partir de ahi el jugador tiene sitio para moverse en circle
 * y para decidir donde poner la bomba.
 */
const MIN_ARENA_RADIUS = 30;

/**
 * Fraccion del disco de la arena que tiene que ser suelo alcanzable.
 *
 * No es 1.0 y no es arbitrario: el centro de la arena tiene el monumento de
 * bloques DESTRUCTIBLES, que es la cobertura por la que se pelea y por la que
 * se rompen las bombas. Un 8x8 en un disco de 30 son 9 puntos de un total de
 * 180. Exigir el 100% obligaria a vaciar la arena de su unico obstaculo, que
 * es justo lo contrario de lo que quiere la especificacion.
 *
 * Al 80% quedan cuatro bloques centrales sobre mas de 180 celdas: se puede
 * circular alrededor de un enemigo y se puede poner una bomba y salir, que es
 * lo que se pide. Por debajo de eso la arena ya no es un sitio donde pelear.
 */
const ARENA_COVERAGE = 0.8;

/**
 * Radio libre de la arena: el mayor disco casi entero alcanzable.
 *
 * La tolerancia del 10% existe porque el borde de una zona es un ensambleje
 * irregular y siempre hay alguna losa elevada o un remate que muerde el
 * perimetro. Lo que se mide es el sitio de PELEAR, no el contorno del mapa.
 *
 * @param {object} grid
 * @param {Uint8Array} seen alcance desde el spawn
 * @param {number} centerCell celda del centro de la arena
 * @returns {number} radio en studs
 */
function freeArenaRadius(grid, seen, centerCell) {
	const c = centerCell % grid.cols;
	const r0 = Math.floor(centerCell / grid.cols);

	for (let radius = MIN_ARENA_RADIUS; radius <= 90; radius += 2) {
		const cells = Math.max(1, Math.round(radius / CELL));
		let total = 0;
		let open = 0;
		for (let dr = -cells; dr <= cells; dr++) {
			for (let dc = -cells; dc <= cells; dc++) {
				if (dr * dr + dc * dc > cells * cells) continue;
				const rr = r0 + dr;
				const cc = c + dc;
				if (rr < 0 || cc < 0 || rr >= grid.rows || cc >= grid.cols) continue;
				total++;
				if (seen[rr * grid.cols + cc]) open++;
			}
		}
		if (total > 0) {
			const ratio = open / total;
			if (ratio >= ARENA_COVERAGE) {
				if (process.argv.includes("--why")) {
					console.log("  AROMA: disco libre de " + radius +
						" studs (" + (radius * 2) + "x" + (radius * 2) + ") con " +
						(ratio * 100).toFixed(0) + "% de cobertura");
				}
				return radius;
			}
		}
	}
	return 0;
}

/** Fraccion minima de suelo alcanzable desde el spawn. */
const MIN_REACHABLE_RATIO = 0.4;

/** Fraccion minima del entorno del spawn que debe ser alcanzable. */
const MIN_SPAWN_OPEN_RATIO = 0.85;
// ---------------------------------------------------------- LECTURA DEL ARBOL

/** Aplana el proyecto a una lista de {path, node}. */
function readTree() {
	const json = JSON.parse(fs.readFileSync(PROJECT, "utf8"));
	const out = [];

	(function walk(node, prefix) {
		for (const key of Object.keys(node)) {
			if (key.startsWith("$")) continue;
			const child = node[key];
			if (!child || typeof child !== "object") continue;
			const here = prefix ? prefix + "." + key : key;
			out.push({ path: here, node: child });
			walk(child, here);
		}
	})(json.tree, "");

	return { flat: out };
}

/**
 * Caja alineada a ejes de una pieza, en coordenadas ABSOLUTAS.
 *
 * LA ROTACION SE APLICA DE VERDAD. La primera version de este archivo ignoraba
 * `Orientation` y por eso declaraba el mundo entero bloqueado. El motivo es
 * concreto: los muros de borde de zona son segmentos TANGENCIALES a una elipse,
 * de 14 studs de largo y girados con la tangente. Sin rotar, un segmento a 45
 * grados se midia como una caja alineada de 14x14 en vez de una tira de 14x3, y
 * cada esquina de cada zona quedaba cerrada. Eso no es conservador: es
 * exactamente lo contrario, y hacia falso FAIL.
 *
 * Se calculan los OCHO VERTICES y seRotan con la matriz de `Orientation`
 * (grados, orden de Roblox R = Rx * Ry * Rz), y la caja sale de sus extremos. Es
 * la mejor aproximacion posible con una caja: puede Sobrestimar el volumen de una
 * pieza muy inclinada (caso limite, una pieza a 45 grados en los dos ejes), pero
 * en este mapa las inclinaciones son de grados y la diferencia es despreciable.
 *
 * @returns {{x0:number,x1:number,y0:number,y1:number,z0:number,z1:number}|null}
 */
function aabbOf(entry) {
	const props = entry.node && entry.node.$properties;
	if (!props) return null;

	const p = props.Position;
	const s = props.Size;
	if (!Array.isArray(p) || !Array.isArray(s)) return null;

	const o = props.Orientation;
	const rx = ((Array.isArray(o) ? o[0] : 0) * Math.PI) / 180;
	const ry = ((Array.isArray(o) ? o[1] : 0) * Math.PI) / 180;
	const rz = ((Array.isArray(o) ? o[2] : 0) * Math.PI) / 180;

	const cx = Math.cos(rx), sx = Math.sin(rx);
	const cy = Math.cos(ry), sy = Math.sin(ry);
	const cz = Math.cos(rz), sz = Math.sin(rz);

	// R = Rx * Ry * Rz, que es el orden que usa Roblox en `Orientation`.
	const m = [
		cy * cz, cy * sz, -sy,
		sx * sy * cz - cx * sz, sx * sy * sz + cx * cz, sx * cy,
		cx * sy * cz + sx * sz, cx * sy * sz - sx * cz, cx * cy,
	];

	const hx = s[0] / 2, hy = s[1] / 2, hz = s[2] / 2;
	let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity, z0 = Infinity, z1 = -Infinity;

	for (const ox of [-hx, hx]) {
		for (const oy of [-hy, hy]) {
			for (const oz of [-hz, hz]) {
				const wx = p[0] + m[0] * ox + m[1] * oy + m[2] * oz;
				const wy = p[1] + m[3] * ox + m[4] * oy + m[5] * oz;
				const wz = p[2] + m[6] * ox + m[7] * oy + m[8] * oz;
				if (wx < x0) x0 = wx;
				if (wx > x1) x1 = wx;
				if (wy < y0) y0 = wy;
				if (wy > y1) y1 = wy;
				if (wz < z0) z0 = wz;
				if (wz > z1) z1 = wz;
			}
		}
	}

	return { x0: x0, x1: x1, y0: y0, y1: y1, z0: z0, z1: z1 };
}

/**
 * ¿Es esta pieza un suelo caminable?
 *
 * Criterio: esta TUMBADA y es ANCHA EN LOS DOS EJES. Las dos condiciones hacen
 * falta y las dos se comprueban:
 *
 *   1. tumbada (mas ancha que alta): descarta muros, columnas y barandillas
 *      verticales;
 *   2. ancha en los dos ejes: descarta las PIEZAS LINEALES.
 *
 * La segunda condicion no era opcional. La barandilla de un puente mide 14x1.2x0.8:
 * es larga (mas ancha que alta) y delgada (0.8 en un eje), asi que la regla de
 * "tumbada" la aceptaba como suelo. Su cara superior esta 3 studs por encima del
 * deck, de modo que la celda de la barandilla quedaba con suelo a 9 studs, el
 * deck de al lado con suelo a 6, y la diferencia de 3 studs hacia abajo se
 * conta como CAIDA: el puente quedaba cortado. Medido en Forest: los tres
 * puentes eran intransitables y su corridor media 4 studs.
 *
 * Un suelo de verdad tiene area: es una superficie, no una linea.
 *
 * @param {{x0:number,x1:number,y0:number,y1:number,z0:number,z1:number}} aabb
 * @returns {boolean}
 */
function isFloorPart(aabb) {
	// Se exige ANCHO EN LOS DOS EJES, no solo tumbada. Sin la segunda
	// condicion, las PIEZAS LINEALES se contaban como suelo: la barandilla de un
	// puente (larga y de 0.8 de grosor) era aceptada, y su cara superior, 3 studs
	// por encima del deck, se tomaba como el suelo de ESA celda. El deck
	// vecino quedaba 3 studs mas abajo y la diferencia se conta como caida: el
	// puente quedaba cortado y su corridor media 4 studs.
	//
	// Un suelo de verdad tiene area: es una superficie, no una linea. El umbral
	// es 1.6 celdas porque una pieza mas pequeña que eso deja la celda pisable
	// por su otra mitad.
	const ex = aabb.x1 - aabb.x0;
	const ez = aabb.z1 - aabb.z0;
	const ey = aabb.y1 - aabb.y0;
	return ex > ey && ez > ey && ex > CELL * 1.6 && ez > CELL * 1.6;
}

/**
 * Datos de una pieza en su SISTEMA LOCAL: posicion, semilado y matriz.
 *
 * Es la pieza que se necesita para medir distancias sin sobreestimarlas. La
 * caja alineada a ejes (`aabbOf`) se conserva para decidir si una pieza BLOQUEA
 * una celda, porque ahi ser conservador es lo correcto; pero para MEDIR cuanto
 * espacio hay alrededor hace falta la pieza de verdad.
 *
 * @returns {{pos:number[], half:number[], m:number[]}}
 */
function orientedOf(entry) {
	const props = entry.node && entry.node.$properties;
	if (!props) return null;
	const p = props.Position;
	const s = props.Size;
	if (!Array.isArray(p) || !Array.isArray(s)) return null;
	const o = props.Orientation;
	const rx = ((Array.isArray(o) ? o[0] : 0) * Math.PI) / 180;
	const ry = ((Array.isArray(o) ? o[1] : 0) * Math.PI) / 180;
	const rz = ((Array.isArray(o) ? o[2] : 0) * Math.PI) / 180;
	const cx = Math.cos(rx), sx = Math.sin(rx);
	const cy = Math.cos(ry), sy = Math.sin(ry);
	const cz = Math.cos(rz), sz = Math.sin(rz);
	return {
		pos: p,
		half: [s[0] / 2, s[1] / 2, s[2] / 2],
		m: [
			cy * cz, cy * sz, -sy,
			sx * sy * cz - cx * sz, sx * sy * sz + cx * cz, sx * cy,
			cx * sy * cz + sx * sz, cx * sy * sz - sx * cz, cx * cy,
		],
	};
}

/**
 * DISTANCIA REAL de un punto a una pieza, con la rotacion aplicada.
 *
 * P0. La caja alineada a ejes de una pieza girada SOBREESTIMA su volumen, y
 * aqui importa: el campo de espacio libre se construye con la distancia al
 * solido mas cercano, asi que una barandilla de 0.8 de grosor puesta a 45
 * grados ocupaba un cuadrado de 11x11 en vez de una tira, y el corredor que
 * bordeaba se media a la mitad.
 *
 * Medido: `Route_7_Bridge_Hollow_Rail_-1_4` salia a 4.4 studs del eje del
 * puente y el corredor de Forest bajaba a 9. La barandilla esta a 16 del eje,
 * que es lo que ocupa de verdad, y el paso es el que el jugador ve.
 *
 * La distancia se calcula llevando el punto al sistema LOCAL de la pieza y
 * la caja local es exacta para cualquier giro.
 *
 * @param {{pos:number[], half:number[], m:number[]}} o pieza orientada
 * @param {number} px
 * @param {number} py
 * @param {number} pz
 * @returns {number}
 */
function orientedDistance(o, px, py, pz) {
	if (!o) return Infinity;
	const dx = px - o.pos[0];
	const dy = py - o.pos[1];
	const dz = pz - o.pos[2];
	// `m` esta en ORDEN POR COLUMNAS, asi que `m^T * v` da las componentes
	// locales de `v`.
	const lx = o.m[0] * dx + o.m[3] * dy + o.m[6] * dz;
	const ly = o.m[1] * dx + o.m[4] * dy + o.m[7] * dz;
	const lz = o.m[2] * dx + o.m[5] * dy + o.m[8] * dz;
	const ex = Math.max(Math.abs(lx) - o.half[0], 0);
	const ey = Math.max(Math.abs(ly) - o.half[1], 0);
	const ez = Math.max(Math.abs(lz) - o.half[2], 0);
	return Math.sqrt(ex * ex + ey * ey + ez * ez);
}

/**
 * Celda del CENTRO de cada zona, para el diagnostico de bloqueo.
 *
 * El bloqueo de la ruta mas corto imprime que zonas siguen viva y cuales se
 * han cortado. Sin la celda de cada zona no hay forma de decirlo, porque
 * "inalcanzable" es de la celda y el nombre de la zona es del arbol.
 *
 * @param {Array} flat arbol aplanado
 * @param {string} id id del mundo
 * @returns {Array<{name:string, cell:number}>}
 */
function zoneCells(flat, id) {
	const prefix = "Workspace.Worlds." + id + ".";
	const out = [];
	const seen = new Set();
	for (const e of flat) {
		if (!e.path.startsWith(prefix + "Zones.Zone_" + id + "_")) continue;
		if (!e.path.endsWith("_Center")) continue;
		const box = aabbOf(e);
		if (!box) continue;
		const name = e.path.split(".").slice(-2)[0].replace(/^Zone_[A-Za-z]+_/, "");
		if (seen.has(name)) continue;
		seen.add(name);
		// La celda se resuelve despues, cuando ya existe la rejilla: aqui solo
		// se guarda la posicion y `analyzeWorld` la convierte.
		out.push({ name: name, x: (box.x0 + box.x1) / 2, z: (box.z0 + box.z1) / 2, cell: -1 });
	}
	return out;
}

// ------------------------------------------------- CONSTRUCCION DE LA REJILLA

/**
 * Construye la rejilla de un mundo: altura de suelo por celda y bloqueo.
 *
 * @param {Array} flat arbol aplanado
 * @param {string} id id del mundo
 * @returns {object?} rejilla, o null si el mundo no tiene geometria solida
 */
function buildGrid(flat, id) {
	const prefix = "Workspace.Worlds." + id + ".";
	const mine = flat.filter((e) => e.path.startsWith(prefix));

	// Solo cuentan las piezas SOLIDES. Una decoracion con CanCollide false es
	// una aparicion: el jugador la atraviesa, y tratarla como muro daria el falso
	// positivo opuesto (un mundo que parece cerrado y no lo esta).
	const solids = [];
	for (const e of mine) {
		const props = e.node && e.node.$properties;
		if (!props || props.CanCollide !== true) continue;
		const aabb = aabbOf(e);
		if (!aabb) continue;
		solids.push({ aabb: aabb, path: e.path, oriented: orientedOf(e) });
	}
	if (!solids.length) return null;

	let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
	for (const s of solids) {
		minX = Math.min(minX, s.aabb.x0); maxX = Math.max(maxX, s.aabb.x1);
		minZ = Math.min(minZ, s.aabb.z0); maxZ = Math.max(maxZ, s.aabb.z1);
	}

	const pad = CELL * 2;
	minX -= pad; maxX += pad; minZ -= pad; maxZ += pad;

	const cols = Math.ceil((maxX - minX) / CELL);
	const rows = Math.ceil((maxZ - minZ) / CELL);

	// SUELO de cada celda, en dos pasos.
	//
	// P0. Un suelo NO es "la cara superior mas alta de la celda". Un tunel tiene
	// el techo 10 studs por encima del suelo, y si ese techo se toma como suelo,
	// la celda queda con altura 10 y el paso se lee como una subida imposible:
	// el mundo entero se declara inalcanzable. Medido en Cyber: `Gate`
	// alcanzable y `Corridor` no, con `subida 10.0` en la frontera.
	//
	// Tampoco vale "la mas baja": las losas elevadas del borde de zona estan 1
	// stud por encima del nucleo, y tomar la mas baja las convierte en obstaculo.
	//
	// La regla correcta es la de un jugador: se pisa la superficie MAS ALTA que
	// se puede ALCANZAR A PIE. Por eso se calculan las dos y se elige la mas
	// alta que no supere `STEP_UP` por encima de la mas baja. Con eso:
	//
	//   losa elevada +1 stud   -> se pisa (alcanzable andando)
	//   SpawnLocation +0.1     -> se pisa
	//   techo de tunel +10     -> NO es suelo: es techo
	//
	// -Infinity = sin suelo: no se puede estar ahi.
	const floorY = new Float64Array(cols * rows).fill(-Infinity);
	const floorCandidates = new Float64Array(cols * rows).fill(-Infinity);
	for (const s of solids) {
		if (!isFloorPart(s.aabb)) continue;
		const c0 = clampIdx(Math.floor((s.aabb.x0 - minX) / CELL), cols);
		const c1 = clampIdx(Math.ceil((s.aabb.x1 - minX) / CELL) - 1, cols);
		const r0 = clampIdx(Math.floor((s.aabb.z0 - minZ) / CELL), rows);
		const r1 = clampIdx(Math.ceil((s.aabb.z1 - minZ) / CELL) - 1, rows);
		for (let r = r0; r <= r1; r++) {
			for (let c = c0; c <= c1; c++) {
				const i = r * cols + c;
				if (s.aabb.y1 > floorCandidates[i]) floorCandidates[i] = s.aabb.y1;
			}
		}
	}

	// El suelo "de verdad" es el MAS BAJO de los que hay en la celda, y solo si
	// no es un techo suelto por encima del suelo del vecindario.
	//
	// POR QUE EL MAS BAJO Y NO EL MAS ALTO
	// ----------------------------------
	// Un tunel tiene DOS superficies horizontales en la misma celda: el deck, que
	// se pisa, y el techo, que se aguanta. Con "el mas alto que este a un paso
	// del mas bajo" las dos se emparejan (dentro del tunel ambas celdas tienen el
	// techo a la misma altura), asi que el suelo acaba siendo el TECHO: +10
	// studs, y el paso se lee como una subida de 10 que nadie puede subir.
	// Medido: Cyber se quedaba con 1 zona alcanzable de 12 y el tunel de Gate a
	// Corridor era el cuello.
	//
	// La regla de un jugador es la buena: en un tunel se pisa el deck. El techo
	// no es una plataforma, es lo que hay arriba. Asi que el suelo es el mas BAJO
	// de la celda, y que no sea un techo se comprueba contra el suelo del
	// VECINDARIO: si la celda solo tiene superficies mas de un `STEP_DOWN` por
	// encima del suelo de al lado, no hay donde pisar ahi y se queda SIN suelo,
	// en vez de convertirse en un falso plataforma flotante.
	//
	// P0. Ese criterio hay que aplicarlo CON UN MATIZ, y el matiz es si la
	// superficie esta APOYADA en algo.
	//
	// Sin el matiz, el techo de un bloque de destruccion se tomaba por suelo
	// flotante y se perdia. Medido: los `CentralStructure/Block_*_cs*` de la
	// arena miden 8x11x8 apoyados en el suelo, y su cara superior queda 11 studs
	// por encima del suelo de al lado, que es exactamente el caso que la regla
	// queria descartar. Con ella, doce celdas del disco de combate de la arena
	// quedaban SIN SUELO y el verificador declaraba `TIGHT ARENA: disco libre de
	// 0 studs` en una arena perfectamente llana.
	//
	// La diferencia entre un techo y la cima de un bloque es que el bloque esta
	// SOSTENIDO: hay un solido que llega desde su cara superior hasta el suelo.
	// El techo de un tunel flota. Por eso, cuando la diferencia con el vecindario
	// es grande, se exige que exista ese apoyo antes de declarar la celda sin
	// suelo.
	const floorPath = new Array(cols * rows).fill("");
	for (let i = 0; i < floorCandidates.length; i++) {
		if (floorCandidates[i] === -Infinity) continue;
		const low = lowestFloor(floorCandidates, cols, rows, i);
		const cand = floorCandidates[i];

		if (cand - low > STEP_DOWN && !supportedFloor(solids, cols, minX, minZ, i, cand, low)) {
			continue;
		}
		floorY[i] = cand;
	}

	// Bloqueo por celda: hay algo solido en la franja de paso.
	const blocked = new Uint8Array(cols * rows);
	const blockerPath = new Array(cols * rows).fill("");
	// POR QUE esta celda esta bloqueada. `buildGrid` ya sabe que caja estorba y
	// en que franja; guardar el MOTIVO aqui evita que el diagnostico tenga que
	// re-evaluar las piezas y permite decir "techo" y no solo "hay algo ahi".
	//
	// Los cuatro motivos, y lo que cada uno obliga a hacer:
	//
	//   wall        un solido ocupa la franja de paso      -> hay que abrirla
	//   ceiling     un techo BAJA dentro de la franja      -> subir el techo
	//   floor-step  un suelo que se mete por debajo del peldaño -> emparejar cotas
	//   solid-deck  el propio suelo counted twice          -> bug del generador
	const blockerKind = new Array(cols * rows).fill("");

	for (const s of solids) {
		const a = s.aabb;
		const c0 = clampIdx(Math.floor((a.x0 - minX) / CELL), cols);
		const c1 = clampIdx(Math.ceil((a.x1 - minX) / CELL) - 1, cols);
		const r0 = clampIdx(Math.floor((a.z0 - minZ) / CELL), rows);
		const r1 = clampIdx(Math.ceil((a.z1 - minZ) / CELL) - 1, rows);

		for (let r = r0; r <= r1; r++) {
			for (let c = c0; c <= c1; c++) {
				const i = r * cols + c;
				if (floorY[i] === -Infinity) continue;

				// LA FRANJA DE PASO, en una sola regla
				// --------------------------------
				// Una pieza estorba al CUERPO si cumple las dos cosas:
				//
				//   1. es demasiado ALTA para pisarla de un escalon
				//      (`y1 > suelo + STEP_UP`), y
				//   2. llega a la altura del CUERPO
				//      (`y0 < suelo + PLAYER_HEADROOM`).
				//
				// Lo que queda fuera no estorba, y cada exclusion tiene un motivo
				// de juego, no tecnico:
				//
				//   - el suelo de la celda y las losas de debajo: es lo que se pisa
				//   - un escalon de hasta 4 studs: se sube andando, no es muro
				//   - un techo a mas de 7 studs: no esta la cabeza, es decoracion
				//
				// Antes esta franja era `suelo - 1.5` hasta `suelo + 7`, y por el
				// lado de abajo contaba como muro la propia losa sobre la que se
				// pisa. Medido con la regla nueva: Forest pasa de 7/11 zonas a
				// 10/11 y los cinco bosses y las cinco salidas dejan de declarar
				// bloqueados por su propio suelo.
				const upOk = floorY[i] + STEP_UP;
				const head = floorY[i] + PLAYER_HEADROOM;

				if (a.y1 <= upOk || a.y0 >= head) continue;
				blocked[i] = 1;
				if (!blockerPath[i]) {
					blockerPath[i] = s.path;
					// El motivo se decide con la CAJA, no con el nombre: el mismo
					// prefijo puede ser un muro, un techo o un remate segun su
					// altura, y decidir por el nombre daria el diagnostico
					// equivocado justo en el caso que hay que arreglar.
					blockerKind[i] = a.y0 >= floorY[i] + 2 ? "ceiling" : "wall";
				}
			}
		}
	}

	return {
		id: id,
		minX: minX, minZ: minZ,
		cols: cols, rows: rows,
		floorY: floorY,
		floorPath: floorPath,
		blocked: blocked,
		blockerPath: blockerPath,
		blockerKind: blockerKind,
		zones: zoneCells(flat, id),
		parts: solids,
	};
}

/**
 * Superficie de suelo mas BAJA de una celda y de sus vecinas.
 *
 * La celda sola no basta: un techo de tunel esta en la misma celda que su suelo,
 * pero la superficie baja puede estar en la celda de al lado (allí solo esta el
 * suelo, sin techo). Por eso se mira el vecindario de 8, que es justo el
 * neighbourhoods que usa el resto del analisis.
 *
 * @param {Float64Array} candidates
 * @param {number} cols
 * @param {number} rows
 * @param {number} i celda
 * @returns {number} cota mas baja, o Infinity si no hay ninguna
 */
function lowestFloor(candidates, cols, rows, i) {
	const c = i % cols;
	const r = Math.floor(i / cols);
	let lowest = Infinity;
	for (let dr = -1; dr <= 1; dr++) {
		for (let dc = -1; dc <= 1; dc++) {
			const nc = c + dc;
			const nr = r + dr;
			if (nc < 0 || nr < 0 || nc >= cols || nr >= rows) continue;
			const v = candidates[nr * cols + nc];
			// P0. Una celda VECINA SIN SUELO no es una superficie a -infinito: es
			// la ausencia de superficie. Contarla como la mas baja hacia que
			// `floorCandidates[i] - low` fuese infinito y que la celda perdiese SU
			// propio suelo por tener un agujero al lado.
			//
			// Medido: con el borde perimetral eliminado (que es lo correcto), las
			// celdas del suelo de la arena de Ice tienen al lado celdas del anillo
			// exterior sin losa, y las doce quedaban como `SIN SUELO` dentro del
			// disco de combate. El verificador declaraba `TIGHT ARENA: disco libre
			// de 0 studs` en un mundo cuya arena estaba perfectamente llana. El
			// mapa no tenia un agujero: el criterio de "techo suelto por encima" no
			// puede apoyarse en celdas donde no hay nada.
			if (v === -Infinity) continue;
			if (v < lowest) lowest = v;
		}
	}
	return lowest;
}

/**
 * ¿La cara superior de una celda esta APOYADA en el suelo?
 *
 * Es la diferencia entre la cima de un bloque y el techo de un tunel. La cima de
 * un bloque tiene un solido que baja desde ella hasta el suelo de al lado: se
 * puede subir andando. El techo de un tunel no tiene nada debajo dentro de la
 * franja: es decoracion colgada.
 *
 * Se recorre la columna vertical de la celda buscando un solido cuya cara
 * superior llega a la cota candidata y cuya cara inferior esta a menos de un
 * `STEP_DOWN` del suelo del vecindario.
 *
 * @param {Array} solids piezas solidas del mundo
 * @param {number} cols columnas de la rejilla
 * @param {number} minX origen X de la rejilla
 * @param {number} minZ origen Z de la rejilla
 * @param {number} i celda
 * @param {number} cand cota candidata
 * @param {number} low cota del suelo del vecindario
 * @returns {boolean}
 */
function supportedFloor(solids, cols, minX, minZ, i, cand, low) {
	const c = i % cols;
	const px = minX + (c + 0.5) * CELL;
	const r = Math.floor(i / cols);
	const pz = minZ + (r + 0.5) * CELL;
	const from = low === Infinity ? cand - STEP_DOWN : low;

	for (const s of solids) {
		const a = s.aabb;
		if (px < a.x0 || px > a.x1 || pz < a.z0 || pz > a.z1) continue;
		if (a.y1 < cand - 0.5) continue;
		if (a.y0 > from + STEP_DOWN) continue;
		return true;
	}
	return false;
}

function clampIdx(i, n) {
	if (i < 0) return 0;
	if (i > n - 1) return n - 1;
	return i;
}

/** Celda que contiene un punto del mundo. */
function cellOf(grid, x, z) {
	const c = clampIdx(Math.floor((x - grid.minX) / CELL), grid.cols);
	const r = clampIdx(Math.floor((z - grid.minZ) / CELL), grid.rows);
	return r * grid.cols + c;
}

/** Celda caminable: tiene suelo y no esta bloqueada. */
function walkable(grid, i) {
	return grid.floorY[i] !== -Infinity && grid.blocked[i] === 0;
}

/** ¿Se puede pasar de la celda `a` a la celda `b` en un paso? */
function stepOk(grid, a, b) {
	if (!walkable(grid, b)) return false;
	const dy = grid.floorY[b] - grid.floorY[a];
	if (dy > STEP_UP) return false;
	if (dy < -STEP_DOWN) return false;
	// BAJADA PELIGROSA: caer mas de la mitad del limite es una caida, no un
	// escalon, aunque el limite lo permita. Un jugador que baja 6 studs de una
	// vez cae y se hace dano; el mapa no puede contar eso como "paso".
	if (dy < -STEP_DOWN / 2) return false;
	return true;
}

// ----------------------------------------------------------------- BUSQUEDAS

/**
 * Campo de ESPACIO LIBRE: separacion REAL, en studs, entre el centro de cada
 * celda y la superficie solida mas cercana.
 *
 * POR QUE NO ES LA DISTANCIA ENTRE CELDAS
 * ---------------------------------------
 * La primera version usaba una transformada de distancia sobre la rejilla (en
 * celdas, Chebyshev). Medir asiroducia un FALSO que no existe en el mapa: la
 * rejilla bloquea una celda si CUALQUIER parte de una pieza la pisa, de modo
 * que un corredor de 14 studs con la pared a 2 studs del borde se media como
 * un corredor de 4. Los cinco mundos daban "4 studs" en todas sus rutas, y la
 * cifra no describia el mapa sino la cuadricula.
 *
 * Aqui la distancia se calcula contra la GEOMETRIA: para cada celda se busca el
 * solido mas cercano y se mide la distancia de su punto central a la caja, en
 * studs. El resultado no depende de donde caiga la rejilla, y es la cifra que
 * responde a la pregunta que hace el jugador: "¿cabe mi personaje aqui?".
 *
 * Se resta el radio del jugador (`PLAYER_RADIUS`), porque lo que interesa no
 * es la distancia al muro sino el espacio LIBRE para un cuerpo de 2 studs.
 *
 * @param {object} grid
 * @returns {{studs: Float64Array, cells: Int32Array}} dos campos: la separacion
 *   real en studs y la de celdas, que se usa como cota superior barata.
 */
function freeSpaceField(grid) {
	const { cols, rows } = grid;
	const studs = new Float64Array(cols * rows).fill(Infinity);

	// FASE 1: separacion contra la geometria, celda a celda.
	//
	// Solo se miran los solidos cuyo AABB, ampliado por el alcance maximo
	// considerado, puede alcanzar la celda. La ampliacion es `MAX_REACH`: mas alla
	// de esa distancia el campo ya esta saturado y no aporta informacion, asi
	// que la busca se acota y el coste es lineal en el area realmente ocupada.
	const MAX_REACH = 40;

	// Se usan solo los solidos que ESTORBAN: los muros, las columnas, las
	// barandillas y la decoracion solida. Los que son SUELO se excluyen, y no
	// por una cuestion de rendimiento.
	//
	// Si se incluye el suelo, la distancia de cada celda a su propia losa es 0,
	// el campo entero vale 0 y el camino mas holgado no existe. Ese suelo es
	// precisamente lo que el jugador PISA, no lo que lo frena: la pregunta es
	// "cuanto espacio hay alrededor", y el suelo no ocupa espacio al lado.
	for (const s of grid.parts) {
		const a = s.aabb;
		// Rango de celdas que este solido puede llegar a influenciar. Solo las que estan
		// dentro de MAX_REACH de la caja; fuera, ya hay otro solido mas cerca o
		// el campo esta saturado.
		const c0 = clampIdx(Math.floor((a.x0 - MAX_REACH - grid.minX) / CELL), cols);
		const c1 = clampIdx(Math.ceil((a.x1 + MAX_REACH - grid.minX) / CELL) - 1, cols);
		const r0 = clampIdx(Math.floor((a.z0 - MAX_REACH - grid.minZ) / CELL), rows);
		const r1 = clampIdx(Math.ceil((a.z1 + MAX_REACH - grid.minZ) / CELL) - 1, rows);

		for (let r = r0; r <= r1; r++) {
			for (let c = c0; c <= c1; c++) {
				const i = r * cols + c;
				if (grid.floorY[i] === -Infinity) continue;

				// P0 CORREGIDO: lo que acota el ancho de un corredor es lo que
				// ESTORBA AL CUERPO, y se decide con la MISMA regla que decide
				// si una celda esta bloqueada. Es decir: una pieza acota el
				// ancho si es demasiado alta para pisarla de un escalon Y sigue
				// ocupando la franja hasta la cabeza.
				//
				// Antes la exclusion era `isFloorPart`, que solo apartaba el
				// suelo. Se colaban dos cosas que no acortan un paso:
				//
				//   - el PILAR de un puente, que cuelga 8 studs POR DEBAJO del
				//     deck. Un pilar que sostiene un puente no estrecha un
				//     puente. Medido: a 4.5 studs del eje partia el corredor en
				//     dos y los puentes de Forest median 9.
				//
				//   - la LOSA ELEVADA de una zona (1.5 studs), que el jugador
				//     pisa de un escalon y sigue andando. Medido: en el cuello
				//     entre `Trail` y `Bridge` el campo la contaba a 6.9 studs
				//     y los cinco mundos caian a 2-3 de corredor.
				//
				// Lo que si acota es la barandilla, el muro y el techo bajo, y
				// los tres cumplen la regla.
				const blocksBody = a.y1 > grid.floorY[i] + STEP_UP
					&& a.y0 < grid.floorY[i] + PLAYER_HEADROOM;
				if (!blocksBody) continue;

				const px = grid.minX + (c + 0.5) * CELL;
				const pz = grid.minZ + (r + 0.5) * CELL;

				// Distancia punto-pieza en 3D, con la ROTACION de la pieza. Es la
				// separacion horizontal; la altura la decide el filtro de
				// `buildGrid`, que ya ha marcado la celda como bloqueada si el
				// solido estorba.
				//
				// Se mide en el sistema LOCAL de la pieza y no con la caja
				// alineada: una barandilla de 0.8 de grosor girada 45 grados
				// ocupa 0.8x0.8, pero su caja alineada ocupa 11x11 y el
				// corredor que la bordeaba se media a menos de la mitad.
				// Medido: los puentes de Forest median 9 studs de corredor con
				// la caja y 18 con la rotacion aplicada.
				const d = orientedDistance(s.oriented, px, grid.floorY[i], pz);
				if (d < studs[i]) studs[i] = d;
			}
		}
	}

	// FASE 2: sin restar el radio del jugador. La magnitud que se guarda es la
	// DISTANCIA AL MURO, y el ancho del corredor sale de multiplicarla por dos en
	// `widestPath`. Restar aqui el radio hacia que una celda pegada a la pared
	// valiera 0, y con el minimo por camino todos los mundos daban ancho 0.
	for (let i = 0; i < studs.length; i++) {
		if (!(studs[i] < Infinity)) {
			// Sin ningun solido cerca: la celda esta en campo abierto y el
			// valor es el tope de busqueda, no infinito. Un `Infinity` real
			// contaminaria `best` en el Dijkstra y devolveria `NaN` como ancho.
			studs[i] = MAX_REACH;
		}
	}

	// Se devuelve la DISTANCIA AL SOLIDO MAS CERCANO, en studs, sin restar el radio
	// del jugador.
	//
	// Por que se mide asi y no como "espacio libre para el cuerpo": la magnitud
	// que describe un corridor es su ANCHO, y el ancho de un corredor es el
	// DOBLE de la distancia de su eje al muro. Restando el radio del jugador y
	// tomando el minimo por el camino, una celda pegada a una pared daba 0 y
	// todos los mundos median "ancho 0".
	//
	// La conversion es `ancho = 2 * separacion` (ver `widestPath`). Con eso:
	//
	//   corredor de 8 studs  -> eje a 4 del muro -> ancho 8  (PASA)
	//   corredor de 4 studs  -> eje a 2 del muro -> ancho 4  (FALLA)
	//   campo abierto        -> tope de busqueda   -> ancho alto (PASA)
	//
	// que es exactamente la pregunta que se le hace a un mapa.
	//
	// El campo transversal en celdas se elimino: valia 0 en toda celda pegada a
	// un muro y contaminaba el resultado.
	return studs;
}

/**
 * Radio del cuerpo del jugador, en studs.
 *
 * El personaje de Roblox mide ~2 studs de ancho. Es lo que se resta a la
 * separacion: 6 studs hasta el muro son 4 studs libres de paso, y asi es como
 * lo lee el verificador y como lo lee el jugador.
 */
const PLAYER_RADIUS = 2;

/** Campo de ALCANCE desde un origen, respetando el desnivel. */
function reachableFrom(grid, start) {
	const { cols, rows } = grid;
	const seen = new Uint8Array(cols * rows);
	if (start < 0 || start >= seen.length || !walkable(grid, start)) return { seen: seen, count: 0 };

	const queue = new Int32Array(cols * rows);
	let head = 0;
	let tail = 0;
	queue[tail++] = start;
	seen[start] = 1;

	while (head < tail) {
		const i = queue[head++];
		const c = i % cols;
		const r = Math.floor(i / cols);
		for (const [dr, dc] of [[-1, 0], [1, 0], [0, -1], [0, 1]]) {
			const nc = c + dc;
			const nr = r + dr;
			if (nc < 0 || nr < 0 || nc >= cols || nr >= rows) continue;
			const j = nr * cols + nc;
			if (seen[j] || !stepOk(grid, i, j)) continue;
			seen[j] = 1;
			queue[tail++] = j;
		}
	}

	return { seen: seen, count: tail };
}

/**
 * Camino mas ANCHO de `a` a `b`.
 *
 * Maximiza el ancho libre minimo del recorrido. Es la version de "sal por el
 * camino mas holgado", y el ancho que devuelve decide si el mapa es un pasillo o
 * un sitio donde pelear.
 */
function widestPath(grid, free, a, b) {
	const { cols, rows } = grid;
	const n = cols * rows;
	if (a === b) {
		return { ok: walkable(grid, a), width: free[a] * 2, length: 1, cells: [a] };
	}
	if (!walkable(grid, a) || !walkable(grid, b)) {
		return { ok: false, width: 0, length: 0, cells: null };
	}

	// El campo `free` esta en STUDS y es float. El ancho del camino es el menor
	// espacio libre que se encuentra por el camino, y se devuelve en studs
	// directamente (ya no multiplicado por `CELL`).
	//
	// El sentinel es `-Infinity`: `free` puede valer 0 en una celda transitable
	// pegada a un muro, y un sentinel de -1 haria que esa celda no relajara
	// nunca. Con -Infinity, 0 la supera y "sin visitar" sigue siendo peor que 0.
	// El campo `free` es la DISTANCIA AL MURO en studs. El ANCHO del corredor es el
	// DOBLE de esa distancia: el eje de un corridor esta a la mitad de su anchura
	// de cada muro. La conversion va aqui, una sola vez, para que ningun
	// consumidor tenga que acordarse de multiplicar por dos.
	//
	//   corredor de 8 studs -> eje a 4 del muro -> ancho 8 (PASA)
	//   corredor de 4 studs -> eje a 2 del muro -> ancho 4 (FALLA)
	//
	// El sentinel es `-Infinity`: la distancia puede valer 0 en una celda
	// transitable pegada a un muro, y con sentinel -1 esa celda no relajaria
	// nunca, vaciando el frente en el primer paso.
	const best = new Float64Array(n).fill(-Infinity);
	const from = new Int32Array(n).fill(-1);
	const queued = new Uint8Array(n);
	best[a] = free[a];

	// Cola con busqueda lineal del maximo. Las rejillas de estos mundos tienen
	// del orden de 100k celdas y el frente activo es pequeno; un heap completo no
	// aportaria nada medible aqui.
	const queue = [a];
	queued[a] = 1;
	let guard = 0;
	let countVisited = 0;

	while (queue.length && guard++ < n * 4) {
		let bestPos = 0;
		for (let k = 1; k < queue.length; k++) {
			if (best[queue[k]] > best[queue[bestPos]]) bestPos = k;
		}
		const i = queue.splice(bestPos, 1)[0];
		queued[i] = 0;
		countVisited++;
		if (i === b) break;

		const c = i % cols;
		const r = Math.floor(i / cols);
		for (const [dr, dc] of [[-1, 0], [1, 0], [0, -1], [0, 1]]) {
			const nc = c + dc;
			const nr = r + dr;
			if (nc < 0 || nr < 0 || nc >= cols || nr >= rows) continue;
			const j = nr * cols + nc;
			if (!stepOk(grid, i, j)) continue;
			const w = Math.min(best[i], free[j]);
			// `best` arranca en `-Infinity` (sin visitar), no en -1. `free` puede valer 0
			// en una celda transitable pegada a un muro, y con sentinel -1 un ancho
			// de 0 no superaria nunca el valor inicial: el frente se vaciaba en el
			// primer paso ("procesadas 1") y ningun mundo tenia ruta. Con
			// `-Infinity`, 0 lo supera y "sin visitar" sigue siendo peor que 0.
			if (w > best[j]) {
				best[j] = w;
				from[j] = i;
				if (!queued[j]) {
					queued[j] = 1;
					queue.push(j);
				}
			}
		}
	}

	// `best` es el mejor ANCHO encontrado; `-Infinity` significa "sin visitar". Un
	// ancho real de 0 (celda pegada a un muro, pero transitable) es un resultado
	// VALIDO, asi que el fallo se decide por el sentinel y no por el ancho: usar
	// `best[b] <= 0` declaraba "sin ruta" a caminos que si existen.
	if (best[b] === -Infinity) {
		// Diagnostico: el destino no se ha visitado. Solo se imprime con `--why`,
		// porque es la unica linea que distingue "no hay camino" de "el
		// algoritmo se ha quedado sin pasos".
		if (process.argv.includes("--why")) {
			console.log(`  DIAG: destino sin visitar, procesadas ${countVisited}, cola ${queue.length}`);
		}
		return { ok: false, width: 0, length: 0, cells: null };
	}

	// Reconstruccion del camino. Se limita a `n` celdas porque `from` usa un
	// sentinel y, si el sentinel se confundiera con un indice, el recorrido
	// entraria en bucle. `n` es la cota correcta: un camino mas largo que la
	// rejilla entera no existe.
	const cells = [];
	for (let i = b; i !== -1 && cells.length <= n; i = from[i]) {
		cells.push(i);
		if (i === a) break;
	}
	cells.reverse();

	return { ok: true, width: best[b] * 2, length: cells.length, cells: cells };
}
/** Camino mas CORTO en celdas (BFS). Sirve para comparar con el mas ancho. */
function shortestPath(grid, a, b) {
	const { cols, rows } = grid;
	const n = cols * rows;
	if (!walkable(grid, a) || !walkable(grid, b)) return null;

	const prev = new Int32Array(n).fill(-2);
	const queue = new Int32Array(n);
	let head = 0;
	let tail = 0;
	queue[tail++] = a;
	prev[a] = -1;

	while (head < tail) {
		const i = queue[head++];
		if (i === b) break;
		const c = i % cols;
		const r = Math.floor(i / cols);
		for (const [dr, dc] of [[-1, 0], [1, 0], [0, -1], [0, 1]]) {
			const nc = c + dc;
			const nr = r + dr;
			if (nc < 0 || nr < 0 || nc >= cols || nr >= rows) continue;
			const j = nr * cols + nc;
			if (prev[j] !== -2 || !stepOk(grid, i, j)) continue;
			prev[j] = i;
			queue[tail++] = j;
		}
	}

	if (prev[b] === -2) return null;
	const cells = [];
	for (let i = b; i !== -1; i = prev[i]) {
		cells.push(i);
		if (i === a) break;
	}
	cells.reverse();
	return cells;
}

/**
 * Comprueba que sigue habiendo camino cuando se TAPA el camino mas corto.
 *
 * Es la comprobacion de redundancia de verdad. Un mundo con dos rutas declaradas
 * que en realidad se cruzan en el mismo cuello de botella no tiene ruta
 * alternativa; este test lo detecta porque tapa el cuello y pregunta.
 *
 * Solo se tapan las celdas INTERMEDIAS: la meta tiene que seguir existiendo, y
 * las celdas de entrada y de meta no son el cuello de botella.
 */
function pathSurvivesBlockade(grid, cells) {
	if (!cells || cells.length < 3) return { ok: true, checked: 0 };

	const blockedCopy = grid.blocked.slice();
	let checked = 0;
	for (let k = 1; k < cells.length - 1; k++) {
		if (!blockedCopy[cells[k]]) checked++;
		blockedCopy[cells[k]] = 1;
	}
	if (!checked) return { ok: true, checked: 0 };

	const saved = grid.blocked;
	grid.blocked = blockedCopy;
	try {
		const alt = widestPath(grid, freeSpaceField(grid), cells[0], cells[cells.length - 1]);
		// Diagnostico de la BLOQUEO. Sin esto, "sin ruta alternativa" dice
		// que el mapa no tiene segundo camino, y no dice si el segundo camino
		// no existe o si el bloqueo se llevo por delante el tramo que ambos
		// compartian. Son dos fallos de diseño distintos con el mismo mensaje.
		if (process.argv.includes("--why") && !alt.ok) {
			const seen = reachableFrom(grid, cells[0]);
			const b = cells[cells.length - 1];
			const bx = grid.minX + ((b % grid.cols) + 0.5) * CELL;
			const bz = grid.minZ + (Math.floor(b / grid.cols) + 0.5) * CELL;

			// Que zonas SIGUEN alcanzables. Sin esta lista, "sin ruta
			// alternativa" no dice si al mapa le falta un camino o si el bloqueo
			// se llevo por delante la mitad del mundo: son dos fallos de
			// diseño distintos con el mismo mensaje.
			const alive = [];
			const gone = [];
			const zonesEntry = grid.zones || [];
			for (const zn of zonesEntry) {
				(seen.seen[zn.cell] ? alive : gone).push(zn.name);
			}
			console.log(
				"  DIAG BLOQUEO: celdas tapadas=" + checked +
				"  componente_del_spawn=" + seen.count +
				"  destino=(" + bx.toFixed(0) + ", " + bz.toFixed(0) + ")" +
				"  destino_alcanzable=" + (seen.seen[b] ? "si" : "NO")
			);
			if (zonesEntry.length) {
				console.log("        siguen viva: " + (alive.join(", ") || "(ninguna)"));
				console.log("        cortada:     " + (gone.join(", ") || "(ninguna)"));
			}
		}
		return { ok: alt.ok, checked: checked };
	} finally {
		grid.blocked = saved;
	}
}

/** Mayor componente conexo de celdas con campo libre >= `minStuds`. */
function largestOpenArea(grid, free, minStuds) {
	const n = grid.cols * grid.rows;
	const seen = new Uint8Array(n);
	const queue = new Int32Array(n);
	let best = 0;

	for (let i = 0; i < n; i++) {
		if (seen[i] || grid.floorY[i] === -Infinity || grid.blocked[i]) continue;
		if (free[i] * 2 < minStuds) continue;

		let head = 0;
		let tail = 0;
		queue[tail++] = i;
		seen[i] = 1;

		while (head < tail) {
			const j = queue[head++];
			const c = j % grid.cols;
			const r = Math.floor(j / grid.cols);
			for (const [dr, dc] of [[-1, 0], [1, 0], [0, -1], [0, 1]]) {
				const nc = c + dc;
				const nr = r + dr;
				if (nc < 0 || nr < 0 || nc >= grid.cols || nr >= grid.rows) continue;
				const k = nr * grid.cols + nc;
				if (seen[k] || grid.floorY[k] === -Infinity || grid.blocked[k]) continue;
				if (free[k] * 2 < minStuds) continue;
				seen[k] = 1;
				queue[tail++] = k;
			}
		}

		if (tail > best) best = tail;
	}

	return { cells: best, area: best * CELL * CELL };
}
/**
 * Muros GIGANTES: tirada recta de bloqueo que atraviesa el mapa entero.
 *
 * Se recorren filas y columnas buscando tiradas consecutivas de celdas
 * bloqueadas de `GIANT_WALL_LENGTH` studs o mas. Un muro asi, por definicion,
 * separa el mapa en dos mitades: si ademas el alcance desde el spawn no cubre las
 * dos, es un DEADLOCK y no una pared.
 */
function giantWalls(grid, reach) {
	const { cols, rows, blocked } = grid;
	const found = [];

	const scan = (horizontal) => {
		const lines = horizontal ? rows : cols;
		const len = horizontal ? cols : rows;

		for (let l = 0; l < lines; l++) {
			let runStart = -1;
			for (let k = 0; k < len; k++) {
				const i = horizontal ? l * cols + k : k * cols + l;
				if (blocked[i] === 1) {
					if (runStart < 0) runStart = k;
					continue;
				}
				// Fin de tirada.
				if (runStart >= 0) {
					const studs = (k - runStart) * CELL;
					if (studs >= GIANT_WALL_LENGTH) {
						const a = horizontal ? l * cols + runStart : runStart * cols + l;
						const b = horizontal ? l * cols + (k - 1) : (k - 1) * cols + l;
						found.push({
							horizontal: horizontal,
							line: l,
							length: studs,
							aSide: reach[a] ? "reachable" : "cut-off",
							bSide: reach[b] ? "reachable" : "cut-off",
						});
					}
					runStart = -1;
				}
			}
		}
	};

	scan(true);
	scan(false);

	for (const w of found) w.deadlock = w.aSide !== w.bSide;
	return found;
}

// --------------------------------------------------------- PUNTOS DE INTERES

/** Caja de la pieza cuya ruta termina en `suffix`. */
function findPiece(mine, suffix) {
	for (const e of mine) {
		if (e.path.endsWith(suffix)) return aabbOf(e);
	}
	return null;
}

/** Centro en el plano XZ de una caja. */
function mid(b) {
	return { x: (b.x0 + b.x1) / 2, z: (b.z0 + b.z1) / 2 };
}

/** Dos listas de celdas son el MISMO camino si coinciden en al menos un 80%. */
function sameCells(a, b) {
	if (!a || !b) return false;
	const set = new Set(a);
	let common = 0;
	for (const i of b) if (set.has(i)) common++;
	return common / Math.max(a.length, b.length) >= 0.8;
}

// Celdas alcanzables dentro de un disco, y total de celdas del disco.
function diskStats(grid, seen, centerCell, radius) {
	const c = centerCell % grid.cols;
	const r = Math.floor(centerCell / grid.cols);
	const rad = Math.ceil(radius / CELL);
	let open = 0;
	let total = 0;
	let bestOpen = 0;
	let bestCell = -1;

	for (let rr = r - rad; rr <= r + rad; rr++) {
		for (let cc = c - rad; cc <= c + rad; cc++) {
			if (rr < 0 || cc < 0 || rr >= grid.rows || cc >= grid.cols) continue;
			const dx = (cc - c) * CELL;
			const dz = (rr - r) * CELL;
			if (dx * dx + dz * dz > radius * radius) continue;
			total++;
			if (seen[rr * grid.cols + cc]) {
				open++;
				// Se recuerda la celda alcanzable MAS CERCANA al centro. Importa
				// porque el centro exacto de la arena esta bajo el monumento
				// (que es solido por diseno) y, por tanto, nunca es
				// "alcanzable". Preguntar solo por el centro daria TINY ARENA en
				// un mundo donde la arena esta perfectamente abierta.
				const d = dx * dx + dz * dz;
				if (d < bestOpen || bestCell < 0) {
					bestOpen = d;
					bestCell = rr * grid.cols + cc;
				}
			}
		}
	}

	return {
		open: open,
		total: total,
		area: open * CELL * CELL,
		nearestCell: bestCell,
		nearestOffset: Math.sqrt(bestOpen),
	};
}
// --------------------------------------------------------------- POR MUNDO

// --------------------------------------------------------- POR MUNDO

/**
 * Las piezas SOLIDES MAS CERCANAS a una celda, con su separacion.
 *
 * `blockerPath` solo dice que pieza BLOQUEA una celda, y el ancho del corredor
 * no lo decide una pieza que bloquea: lo decide la pieza mas cercana, que
 * puede ser una barandilla que no llega a tapar la celda pero acorta el paso
 * igual. Sin esta lista, "el corridor mide 6 studs" no dice NADA de que pieza
 * lo cierra.
 *
 * @param {object} grid
 * @param {number} i celda
 * @param {number} max numero de piezas
 * @returns {Array<{path:string, d:number, aabb:object}>}
 */
function nearestSolids(grid, i, max) {
	const c = i % grid.cols;
	const r = Math.floor(i / grid.cols);
	const px = grid.minX + (c + 0.5) * CELL;
	const pz = grid.minZ + (r + 0.5) * CELL;
	const out = [];
	for (const s of grid.parts) {
		out.push({
			path: s.path,
			d: orientedDistance(s.oriented, px, grid.floorY[i], pz),
			aabb: s.aabb,
		});
	}
	out.sort(function (x, y) { return x.d - y.d; });
	return out.slice(0, max);
}

/**
 * Analiza un mundo y devuelve sus medidas y sus problemas.
 *
 * @param {string} id id del mundo
 * @param {Array} flat arbol aplanado
 * @returns {object} medidas, rutas y problemas
 */
function analyzeWorld(id, flat) {
	const prefix = "Workspace.Worlds." + id + ".";
	const c = i % grid.cols;
	const r = Math.floor(i / grid.cols);
	const px = grid.minX + (c + 0.5) * CELL;
	const pz = grid.minZ + (r + 0.5) * CELL;
	const out = [];
	for (const s of grid.parts) {
		const a = s.aabb;
		const dx = Math.max(a.x0 - px, 0, px - a.x1);
		const dz = Math.max(a.z0 - pz, 0, pz - a.z1);
		const d = Math.sqrt(dx * dx + dz * dz);
		out.push({ path: s.path, d: d, aabb: a });
	}
	out.sort(function (x, y) { return x.d - y.d; });
	return out.slice(0, max);
}

function analyzeWorld(id, flat) {
	const prefix = "Workspace.Worlds." + id + ".";
	const mine = flat.filter((e) => e.path.startsWith(prefix));
	const problems = [];

	const grid = buildGrid(flat, id);
	if (!grid) return { id: id, problems: ["sin geometria solida: no hay donde caminar"] };

	const spawnBox = findPiece(mine, "SpawnPoint_" + id);
	const arenaBox = findPiece(mine, "." + id + ".ArenaCenter");
	const bossBox = findPiece(mine, "." + id + ".BossSpawn_" + id);
	const exitBox = findPiece(mine, "." + id + ".Exit_" + id);

	if (!spawnBox) problems.push("falta SpawnPoint_" + id);
	if (!arenaBox) problems.push("falta ArenaCenter");
	if (!bossBox) problems.push("falta BossSpawn_" + id);
	if (!exitBox) problems.push("falta Exit_" + id);
	if (problems.length) return { id: id, problems: problems };

	const spawn = cellOf(grid, mid(spawnBox).x, mid(spawnBox).z);
	const arena = cellOf(grid, mid(arenaBox).x, mid(arenaBox).z);
	const boss = cellOf(grid, mid(bossBox).x, mid(bossBox).z);
	const exit = cellOf(grid, mid(exitBox).x, mid(exitBox).z);

	if (!walkable(grid, spawn)) {
		problems.push(`SPAWN TRAP: el spawn esta sobre una celda no caminable (suelo=${grid.floorY[spawn]}, bloqueada=${grid.blocked[spawn]}, tapada por ${grid.blockerPath[spawn] || "nada"})`);
	}

	const free = freeSpaceField(grid);
	const reach = reachableFrom(grid, spawn);

	// La celda de cada zona se resuelve aqui, cuando la rejilla ya existe.
	for (const zn of grid.zones) zn.cell = cellOf(grid, zn.x, zn.z);

	// Estructura del mundo por LEG: la zona de cada rol y si es alcanzable. Es
	// la tabla que dice DONDE se rompe el recorrido, y se imprime siempre (no
	// solo con `--why`) porque un FAIL sin esto obliga a volver a mirar codigo.
	const zoneReach = [];
	{
		const zonesEntry = mine.find((e) => e.path.endsWith(".Zones"));
		if (zonesEntry) {
			for (const zn of Object.keys(zonesEntry.node)) {
				if (zn.startsWith("$")) continue;
				const center = mine.find((e) => e.path.endsWith("Zones." + zn + "." + zn + "_Center"));
				if (!center) continue;
				const box = aabbOf(center);
				const cx = (box.x0 + box.x1) / 2;
				const cz = (box.z0 + box.z1) / 2;
				const c = cellOf(grid, cx, cz);

				// Radio de trabajo de la zona: el de SU NUCLE, no el del marcador.
				//
				// El marcador `_Center` mide 10x10, asi que con el radio que
				// salia de el se miraban 7x7 celdas: 49 celdas en el centro de
				// una zona de 60 studs de radio. Eso hace que una zona rodeada de
				// muro se diagnostique como "sin ninguna celda bloqueada", que es
				// justo la conclusion equivocada.
				//
				// El nucleo (`Zone_*_Core`) es la losa que se pisa, y mide lo que
				// mide la zona. El radio sale de ahi.
				const core = mine.find((e) => e.path.endsWith("Zones." + zn + "." + zn + "_Core"));
				const coreBox = core ? aabbOf(core) : box;
				const rad = Math.ceil(Math.max(coreBox.x1 - coreBox.x0, coreBox.z1 - coreBox.z0) / 2 / CELL);
				const cc = c % grid.cols;
				const rr = Math.floor(c / grid.cols);
				let withFloor = 0;
				let walk = 0;
				let got = 0;
				let nearestOffset = Infinity;
				let first = null;

				for (let dr = -rad; dr <= rad; dr++) {
					for (let dc = -rad; dc <= rad; dc++) {
						const rj = rr + dr;
						const cj = cc + dc;
						if (rj < 0 || cj < 0 || rj >= grid.rows || cj >= grid.cols) continue;
						const j = rj * grid.cols + cj;
						const dist = Math.sqrt(dr * dr + dc * dc) * CELL;
						if (grid.floorY[j] === -Infinity) continue;
						withFloor++;
						if (grid.blocked[j] === 0) walk++;
						if (reach.seen[j]) {
							got++;
							if (dist < nearestOffset) nearestOffset = dist;
							continue;
						}
						if (!first && grid.blocked[j] === 1) {
							first = {
								col: cj,
								row: rj,
								x: grid.minX + (cj + 0.5) * CELL,
								z: grid.minZ + (rj + 0.5) * CELL,
								y: grid.floorY[j],
								kind: grid.blockerKind[j] || "wall",
								by: grid.blockerPath[j],
							};
						}
					}
				}

				const zoneResult = {
					zone: zn.replace(/^Zone_[A-Za-z]+_/, ""),
					ok: c >= 0 && c < reach.seen.length && reach.seen[c] === 1,
					withFloor: withFloor,
					walkable: walk,
					reached: got,
					nearest: nearestOffset === Infinity ? null : Math.round(nearestOffset * 10) / 10,
					first: first,
				};
				zoneReach.push(zoneResult);

				if (!zoneResult.ok) {
					problems.push(`ZONE INACCESSIBLE: ${id}.${zoneResult.zone} center is not walkable from spawn`);
				}
			}
		}
	}

	const legs = [];

	/**
	 * Un tramo critico: mide la ruta, comprueba el ancho y exige redundancia.
	 *
	 * `rule` es el nombre del FAIL que se imprime si algo falla. No es
	 * decorativo: es lo que permite decir "BOSS ROUTE BLOCKED" en lugar de
	 * "la tercera fila dice que algo va mal".
	 */
	function leg(label, rule, from, to) {
		const wide = widestPath(grid, free, from, to);
		if (!wide.ok) {
			problems.push(`${rule}: ${label} NO HAY RUTA`);
			legs.push({ label: label, rule: rule, ok: false, width: 0, cells: 0, altPath: false });
			return;
		}

		const short = shortestPath(grid, from, to);
		const alt = pathSurvivesBlockade(grid, short);

		// Diagnostico opcional: donde se estrecha el camino. Se imprime solo
		// con `--why`, porque en un mundo que falla es la unica linea que dice
		// QUE lo estrecha (una barandilla, un poste, el remate de un muro).
		if (process.argv.includes("--why")) {
			let worst = 9999;
			let worstIdx = 0;
			for (let k = 0; k < wide.cells.length; k++) {
				if (free[wide.cells[k]] < worst) {
					worst = free[wide.cells[k]];
					worstIdx = k;
				}
			}
			const wc = wide.cells[worstIdx] % grid.cols;
			const wr = Math.floor(wide.cells[worstIdx] / grid.cols);
			console.log(`  POR QUE ${id} ${label}: t=${(worstIdx / Math.max(1, wide.cells.length - 1)).toFixed(2)} libre=${worst} y=${grid.floorY[wide.cells[worstIdx]]}`);
			// El punto en coordenadas del mundo. Sin el, las lineas que siguen
			// describen una foto de la rejilla que no se puede consultar con
			// `--at`, y el diagnostico obliga a buscar a ojo.
			console.log("      pos=(" +
				(grid.minX + (wc + 0.5) * CELL).toFixed(1) + ", " +
				(grid.minZ + (wr + 0.5) * CELL).toFixed(1) + ")");
			for (let dr = -2; dr <= 2; dr++) {
				let line = "";
				for (let dc = -8; dc <= 8; dc++) {
					const jj = (wr + dr) * grid.cols + (wc + dc);
					if (jj < 0 || jj >= grid.blocked.length) { line += "?"; continue; }
					line += grid.blocked[jj] ? "#" : grid.floorY[jj] === -Infinity ? " " : reach.seen[jj] ? "." : ",";
				}
				console.log("      " + line);
			}
			// Se listan los obstaculos que rodenan el punto mas estrecho. La
			// celda itself no esta bloqueada (por eso `libre` es 1 y no 0), asi
			// que hay que mirar el VECINDARIO para saber que lo estrecha.
			const near = [];
			for (let dr = -2; dr <= 2; dr++) {
				for (let dc = -2; dc <= 2; dc++) {
					const jj = (wr + dr) * grid.cols + (wc + dc);
					if (jj < 0 || jj >= grid.blocked.length) continue;
					if (!grid.blocked[jj] || !grid.blockerPath[jj]) continue;
					const p = grid.blockerPath[jj];
					if (near.indexOf(p) < 0) near.push(p);
				}
			}
			console.log("      obstaculos cercanos:");
			for (const p of near.slice(0, 6)) console.log("        " + p);
			// Y las piezas mas CERCANAS, que son las que miden el ancho: una
			// barandilla puede no bloquear la celda y aun asi ser la que deja
			// el paso en la mitad.
			console.log("      piezas mas cercanas (miden el ancho):");
			for (const s of nearestSolids(grid, wide.cells[worstIdx], 6)) {
				console.log(
					"        " + s.d.toFixed(1).padStart(6) + " studs  " +
					"y " + s.aabb.y0.toFixed(1).padStart(6) + ".." + s.aabb.y1.toFixed(1).padStart(6) +
					"  " + s.path
				);
			}
		}
		legs.push({
			label: label,
			rule: rule,
			ok: true,
			width: wide.width,
			cells: wide.length,
			area: wide.length * CELL * CELL,
			altPath: alt.ok,
			altCells: alt.checked,
			sameAsShortest: sameCells(short, wide.cells),
		});

		if (wide.width < MIN_CORRIDOR) {
			problems.push(
				`${rule}: ${label} corridor de ${wide.width} studs (minimo ${MIN_CORRIDOR})`
			);
		}
		if (!alt.ok) {
			problems.push(`${rule}: ${label} sin ruta alternativa al cerrar el camino mas corto`);
		}
	}

	leg("Spawn->Arena", "CRITICAL PATH BLOCKED", spawn, nearestReachable(arena));
	leg("Spawn->Boss", "BOSS ROUTE BLOCKED", spawn, nearestReachable(boss));
	leg("Spawn->Exit", "EXIT ROUTE BLOCKED", spawn, nearestReachable(exit));

	// El CENTRO EXACTO de la arena esta bajo el monumento, que es solido por
	// diseno. Por eso las tres legs van a la celda alcanzable MAS CERCANA, no al
	// centro geometrico: preguntar por el centro daria "SIN RUTA" en un mundo
	// donde la arena esta abierta y solo tiene un pilar en medio.
	function nearestReachable(centerCell) {
		if (reach.seen[centerCell]) return centerCell;
		const d = diskStats(grid, reach.seen, centerCell, ARENA_RADIUS);
		return d.nearestCell >= 0 ? d.nearestCell : centerCell;
	}
	// SPAWN TRAP: el jugador no puede aparecer encerrado.
	const spawnDisk = diskStats(grid, reach.seen, spawn, SPAWN_TRAP_RADIUS);
	const spawnRatio = spawnDisk.total > 0 ? spawnDisk.open / spawnDisk.total : 0;
	if (spawnRatio < MIN_SPAWN_OPEN_RATIO) {
		problems.push(
			`SPAWN TRAP: solo el ${(spawnRatio * 100).toFixed(0)}% del entorno de ` +
			`${SPAWN_TRAP_RADIUS} studs es alcanzable`
		);
	}

	// TINY ARENA: la arena tiene que dar sitio para pelear, no ser una losa.
	const arenaDisk = diskStats(grid, reach.seen, arena, ARENA_RADIUS);
	if (arenaDisk.area < MIN_ARENA_AREA) {
		problems.push(
			`TINY ARENA: ${arenaDisk.area} studs2 alcanzables en la arena (minimo ${MIN_ARENA_AREA})`
		);
	}

	// TIGHT ARENA: el area puede pasar y el sitio ser pequeno. La arena tiene
	// que dar un disco de `MIN_ARENA_RADIUS` (60x60) por el que se pueda
	// circular, poner una bomba y salir. Es la comprobacion que responde a "se
	// puede escapar de una bomba aqui", que un area suelta no responde.
	const arenaRadius = freeArenaRadius(grid, reach.seen, arena);
	if (arenaRadius < MIN_ARENA_RADIUS) {
		problems.push(
			`TIGHT ARENA: la arena da un disco libre de ${arenaRadius} studs ` +
			`(minimo ${MIN_ARENA_RADIUS}, es decir 60x60)`
		);
	}

	// TUNNEL WORLD: mucho decorado y poco jugable.
	let floorCells = 0;
	let reachableFloor = 0;
	for (let i = 0; i < grid.floorY.length; i++) {
		if (grid.floorY[i] === -Infinity) continue;
		floorCells++;
		if (reach.seen[i]) reachableFloor++;
	}
	const reachableRatio = floorCells > 0 ? reachableFloor / floorCells : 0;
	if (reachableRatio < MIN_REACHABLE_RATIO) {
		problems.push(
			`TUNNEL WORLD: solo el ${(reachableRatio * 100).toFixed(0)}% del suelo es ` +
			`alcanzable desde el spawn (minimo ${(MIN_REACHABLE_RATIO * 100).toFixed(0)}%)`
		);
	}

	// SINGLE-CORRIDOR WORLD: promedio, no minimo. Un tramo estrecho entre arena y
	// boss es aceptable; tres tramos estrechos no.
	const widths = legs.filter((l) => l.ok).map((l) => l.width);
	const avgWidth = widths.length ? widths.reduce((a, b) => a + b, 0) / widths.length : 0;
	if (avgWidth < MIN_CORRIDOR * 1.5) {
		problems.push(
			`SINGLE-CORRIDOR WORLD: ancho medio ${avgWidth.toFixed(0)} studs ` +
			`(minimo ${(MIN_CORRIDOR * 1.5).toFixed(0)})`
		);
	}

	// GIANT WALL DEADLOCK.
	const walls = giantWalls(grid, reach.seen);
	for (const w of walls) {
		if (!w.deadlock) continue;
		problems.push(
			`GIANT WALL DEADLOCK: muro recto de ${w.length} studs ` +
			`${w.horizontal ? "horizontal" : "vertical"} parte el mundo y un lado ` +
			`queda sin acceso desde el spawn`
		);
	}

	// Mayor area abierta: el dato que dice si el mundo tiene donde pelear.
	const open = largestOpenArea(grid, free, MIN_CORRIDOR);

	// Callejones sin salida: celdas alcanzables y anchas con un solo vecino
	// alcanzable. Solo cuentan las que tienen aire de sobra, porque un hueco de
	// una celda entre dos bloques es decoracion, no un callejon.
	let deadEnds = 0;
	for (let i = 0; i < grid.blocked.length; i++) {
		if (!reach.seen[i] || free[i] * 2 < MIN_CORRIDOR) continue;
		const c = i % grid.cols;
		const r = Math.floor(i / grid.cols);
		let neighbors = 0;
		for (const [dr, dc] of [[-1, 0], [1, 0], [0, -1], [0, 1]]) {
			const nc = c + dc;
			const nr = r + dr;
			if (nc < 0 || nr < 0 || nc >= grid.cols || nr >= grid.rows) continue;
			if (reach.seen[nr * grid.cols + nc]) neighbors++;
		}
		if (neighbors <= 1) deadEnds++;
	}

	return {
		id: id,
		problems: problems,
		cols: grid.cols,
		rows: grid.rows,
		cells: grid.cols * grid.rows,
		parts: grid.parts.length,
		legs: legs,
		spawnRatio: spawnRatio,
		arenaArea: arenaDisk.area,
		reachableRatio: reachableRatio,
		avgWidth: avgWidth,
		openArea: open.area,
		openCells: open.cells,
		giantWalls: walls,
		deadEnds: deadEnds,
		floorCells: floorCells,
		zoneReach: zoneReach,
	};
}
// -------------------------------------------------------------------- MAIN

function main() {
	if (!fs.existsSync(PROJECT)) {
		console.log("No existe default.project.json. Genera el proyecto primero con:");
		console.log("  node tools/generate-project.js");
		process.exitCode = 2;
		return;
	}

	const { flat } = readTree();
	const results = WORLD_IDS.map((id) => analyzeWorld(id, flat));

	console.log("NAVEGABILIDAD DE LOS MUNDOS (geometria real, no nombres)");
	console.log("-------------------------------------------------------------------");
	console.log(
		`rejilla ${CELL} studs | aire util ${PLAYER_HEADROOM} studs | ` +
		`escalon ${STEP_UP} studs | corredor min ${MIN_CORRIDOR} studs`
	);
	console.log("");
	console.log("mundo        celdas   spawn    arena    tunel   corredor  area abierta  callejon");

	let failed = 0;
	for (const r of results) {
		const ok = r.problems.length === 0;
		if (!ok) failed++;
		console.log(
			r.id.padEnd(10) +
			String(r.cells).padStart(9) +
			((r.spawnRatio * 100).toFixed(0) + "%").padStart(10) +
			String(Math.round(r.arenaArea)).padStart(9) +
			((r.reachableRatio * 100).toFixed(0) + "%").padStart(9) +
			(r.avgWidth.toFixed(0) + " st").padStart(11) +
			String(Math.round(r.openArea)).padStart(15) +
			String(r.deadEnds).padStart(10)
		);
	}

	console.log("");
	console.log("RUTAS CRITICAS (ancho libre minimo del camino mas holgado)");
	for (const r of results) {
		if (!r.legs || !r.legs.length) continue;
		console.log("  " + r.id + ":");
		for (const l of r.legs) {
			if (!l.ok) {
				console.log(`    X ${l.label.padEnd(14)} ${l.rule}: SIN RUTA`);
				continue;
			}
			console.log(
				`      ${l.label.padEnd(14)} ancho ${l.width.toFixed(0).padStart(4)} studs` +
				`  largo ${String(l.cells).padStart(4)} celdas` +
				`  area ${String(Math.round(l.area)).padStart(6)} studs2` +
				`  alternativa ${l.altPath ? "si" : "NO"}`
			);
		}
	}

	console.log("");
	console.log("ZONAS ALCANZABLES DESDE EL SPAWN");
	for (const r of results) {
		if (!r.zoneReach || !r.zoneReach.length) continue;
		const si = r.zoneReach.filter((z) => z.ok).length;
		console.log("WORLD: " + r.id + "   " + si + "/" + r.zoneReach.length);
		for (const z of r.zoneReach) {
			if (z.ok) {
				// Una zona alcanzable tambien dice cuanto de ella se puede
				// recorrer: una zona "alcanzable" con 4 celdas caminables de 400
				// es un pasadizo, no una zona, y por eso se imprime siempre.
				console.log(
					"  ZONE " + z.zone.padEnd(11) + " reachable=YES   " +
					"suelo=" + String(z.withFloor).padStart(5) +
					"  caminable=" + String(z.walkable).padStart(5) +
					"  alcanzable=" + String(z.reached).padStart(5)
				);
				continue;
			}
			console.log("  ZONE " + z.zone.padEnd(11) + " reachable=NO");
			console.log(
				"        suelo=" + String(z.withFloor).padStart(5) +
				"  caminable=" + String(z.walkable).padStart(5) +
				"  alcanzable=" + String(z.reached).padStart(5) +
				"  celda_alcanzable_mas_cercana=" + (z.nearest === null ? "ninguna" : z.nearest + " studs")
			);
			if (z.first) {
				console.log("        first_blocked   celda (" + z.first.col + "," + z.first.row + ")  pos=(" +
					z.first.x.toFixed(1) + ", " + z.first.z.toFixed(1) + ")  suelo_y=" + z.first.y);
				console.log("        kind            " + z.first.kind);
				console.log("        blocked_by      " + (z.first.by || "(sin pieza)"));
			} else {
				console.log("        first_blocked   (ninguna celda bloqueada dentro de la zona)");
				console.log("        causa           la zona no tiene suelo caminable o esta fuera de la rejilla");
			}
		}
		console.log("");
	}

	console.log("");
	console.log("MUROS GIGANTES");
	let anyWall = false;
	for (const r of results) {
		if (!r.giantWalls || !r.giantWalls.length) continue;
		anyWall = true;
		for (const w of r.giantWalls) {
			console.log(
				`  ${r.id.padEnd(9)} ${String(w.length).padStart(4)} studs ` +
				`${w.horizontal ? "horizontal" : "vertical  "} ` +
				`extremos ${w.aSide} / ${w.bSide} ` +
				(w.deadlock ? "DEADLOCK" : "con paso")
			);
		}
	}
	if (!anyWall) console.log("  ninguno");

	console.log("");
	if (failed) {
		console.log(`PROBLEMAS DE NAVEGABILIDAD (${failed} mundo(s)):`);
		for (const r of results) {
			for (const p of r.problems) console.log(`  - ${p}`);
		}
		console.log("");
		console.log("NAVEGABILIDAD: FAIL");
		process.exitCode = 1;
		return;
	}

	console.log("NAVEGABILIDAD: PASS");
	console.log("Spawn alcanza arena, boss y exit por caminos mas anchos que el minimo,");
	console.log("existe ruta alternativa al tapar el camino mas corto, y ningun muro");
	console.log("recto parte el mundo dejando un lado sin acceso.");
}

// El export es para que las sondas de `tools/` puedan reutilizar el MISMO
// constructor de rejilla. Si este archivo se ejecuta como programa, corre `main`.
if (require.main === module) {
	main();
}

module.exports = {
	buildGrid: buildGrid,
	readTree: readTree,
	freeSpaceField: freeSpaceField,
	reachableFrom: reachableFrom,
	widestPath: widestPath,
	cellOf: cellOf,
	walkable: walkable,
	aabbOf: aabbOf,
	constants: {
		CELL: CELL,
		PLAYER_HEADROOM: PLAYER_HEADROOM,
		MIN_DROP: MIN_DROP,
		STEP_UP: STEP_UP,
		MIN_CORRIDOR: MIN_CORRIDOR,
	},
};
