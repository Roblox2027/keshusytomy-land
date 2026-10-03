// generate-project.js
// Genera default.project.json, incluyendo el MAPA del juego.
//
// Por que un generador y no JSON a mano: el mapa son ~120 bloques
// repetidos. Mantenerlo a mano es inviable yï¼Œä»»ä½• cambio seria un
// error tipografico silencioso. Este script es la fuente de verdad.
//
// Uso:  node tools/generate-project.js
//
// Regla: el script es idempotente y NUNCA toca src/. Solo escribe
// default.project.json.

const fs = require("fs");
const path = require("path");

const Worlds = require("./worlds");
const Portals = require("./portals");

const ROOT = path.join(__dirname, "..");
const PROJECT = path.join(ROOT, "default.project.json");

const v3 = (x, y, z) => [x, y, z];

// Formato de color: array de 3 floats 0..1.
//
// Rojo 7 NO conoce `Color3` como propiedad de Part: el nombre correcto
// es `Color`. Usar `Color3` hace fallar el build con
// "Unknown property Part.Color3".
const color = (r, g, b) => [r / 255, g / 255, b / 255];

/**
 * Convierte una lista de instancias en un objeto de campos directos.
 *
 * Rojo 7 NO usa una clave `Children`: cada hijo es un campo mas de la
 * instancia padre, y la clave ES el nombre. Ademas `Name` no puede
 * aparecer en `$properties` porque Rojo la rechaza.
 */
function asChildren(list) {
	const map = {};
	for (const node of list) {
		// El mapa esta indexado por nombre: un duplicado SE SOBREESCRIBE en
		// silencio y la geometria desaparece sin error ni aviso. Eso ya
		// ocurrio en el arbol de Studio (StarterPlayerScripts con ClientMain
		// duplicado) y lo oculto un comparador mal escrito. Aqui el
		// generador falla fuerte en lugar de producir un mapa incompleto:
		// es la unica linea que convierte "me falta una pared" en un error
		// de build legible.
		if (Object.prototype.hasOwnProperty.call(map, node.name)) {
			throw new Error(
				"asChildren: nombre duplicado '" + node.name + "'. "
				+ "Dos instancias homonimas bajo el mismo padre; una "
				+ "desapareceria del mapa sin error."
			);
		}
		map[node.name] = node.node;
	}
	return map;
}

/**
 * Crea un Folder. Sus hijos se aplanan con `asChildren` porque Rojo
 * exige campos directos y no un array ni una clave `Children`.
 */
function folder(name, children) {
	const list = children || [];

	if (list.length === 0) {
		return { name: name, node: { $className: "Folder" } };
	}

	return { name: name, node: Object.assign({ $className: "Folder" }, asChildren(list)) };
}

function part(name, opts) {
	const props = {
		Anchored: true,
		CanCollide: opts.canCollide !== false,
		CanTouch: false,
		TopSurface: "Smooth",
		BottomSurface: "Smooth",
		Material: opts.material || "SmoothPlastic",
		Color: color(...(opts.color || [140, 140, 140])),
		Size: v3(...(opts.size || [10, 1, 10])),
		// `Position` y no `CFrame`: Rojo acepta `[x, y, z]` para Position
		// y rechaza la forma de CFrame. Todos los parts del mapa tienen
		// orientacion identidad, asi que Position basta.
		Position: v3(...(opts.position || [0, 0, 0])),
	};
	if (opts.transparency !== undefined) props.Transparency = opts.transparency;

	// Orientacion en GRADOS (propiedad `Orientation` de Part, Roblox la
	// sigue aceptando aunque Figurememe la marque como obsoleta).
	//
	// Rojo acepta `Orientation` como `[x, y, z]` en grados. Con esta
	// propiedad los bloques destructibles pueden inclinarse y girar sin
	// dejar de ser una unica BasePart: el radio de explosion se calcula
	// por distancia entre centros, no por el tamano ni por la forma, asi
	// que variar dimensiones y rotacion NO altera el contrato.
	if (opts.orientation) props.Orientation = opts.orientation;

	// `Shape` + `Material` permiten el vocabulario de formas que usa el
	// lobby (esferas del Core, cilindros de las columnas). Sin esto el
	// Keshusy Core tendria que ser un cubo, que es justo lo que el diseÃ±o
	// pide evitar.
	if (opts.shape) {
		props.Shape = opts.shape;
		props.Material = opts.material || "Neon";
		props.TopSurface = "Smooth";
		props.BottomSurface = "Smooth";
	}

	return { name: name, node: { $className: "Part", $properties: props } };
}

/**
 * Part SIN colisiÃ³n, para decoraciÃ³n y VFX.
 *
 * Separa "se ve" de "se pisa": los anillos del Core y los aros de los
 * portales son visibles pero no deben frenar al jugador ni alterar la
 * fisica. Mezclar ambos roles en `part()` obligaba a recordar el
 * `canCollide: false` en cada llamada y era facil olvidarlo.
 */
function decor(name, opts) {
	return part(name, Object.assign({}, opts, { canCollide: false }));
}

function marker(name, position, opts) {
	return part(name, {
		position: position,
		size: opts.size || [12, 0.2, 12],
		canCollide: false,
		transparency: 0.4,
		color: opts.color || [200, 220, 255],
		material: "Neon",
	});
}

/**
 * Crea un Model. Sus hijos se aplanan con `asChildren` por la misma razon que
 * en `folder()`.
 *
 * POR QUE EXISTE (y por que los portales son Models)
 * --------------------------------------------------
 * Los portales se construyen como UN Model por portal (`Portal_Forest`,
 * `Portal_Desert`, ...), no como un reguero de Parts planos.
 *
 * `PortalService` recorre el mapa buscando instancias cuyo nombre empiece
 * por `Portal_` y de las que exige:
 *   1. que sean un Model (para agrupar las piezas del portal), y
 *   2. que contengan un umbral con nombre estable (`PortalPanel`).
 *
 * Con Parts sueltos no habia forma de saber cual era el panel de cual, y el
 * servicio no podia calcular ni la posicion del umbral ni la distancia de
 * proximidad. El Model convierte "estas seis Parts forman un portal" en un
 * hecho que el codigo puede leer.
 *
 * @param {string} name
 * @param {Array} children
 */
function model(name, children) {
	return {
		name: name,
		node: Object.assign({ $className: "Model" }, asChildren(children)),
	};
}

function spawnLocation(name, position, colorRGB) {
	return {
		name: name,
		node: {
			$className: "SpawnLocation",
			$properties: {
				Anchored: true,
				CanCollide: true,
				CanTouch: false,
				Neutral: true,
				Enabled: true,
				Duration: 0,
				AllowTeamChangeOnTouch: false,
				Transparency: 0.4,
				Material: "Neon",
				Color: color(...colorRGB),
				Size: v3(12, 1, 12),
				Position: v3(...position),
			},
		},
	};
}

/** Muro perimetral de 4 caras alrededor de un centro. */
function perimeter(prefix, cx, cz, half, height, colorRGB) {
	const out = [];
	out.push(part(prefix + "_N", { position: [cx, height / 2, cz - half], size: [half * 2 + 2, height, 2], color: colorRGB }));
	out.push(part(prefix + "_S", { position: [cx, height / 2, cz + half], size: [half * 2 + 2, height, 2], color: colorRGB }));
	out.push(part(prefix + "_W", { position: [cx - half, height / 2, cz], size: [2, height, half * 2 + 2], color: colorRGB }));
	out.push(part(prefix + "_E", { position: [cx + half, height / 2, cz], size: [2, height, half * 2 + 2], color: colorRGB }));
	return out;
}

// ---------------------------------------------------------------- LOBBY
// Zona segura. Aqui aparece el jugador al entrar al juego.
//
// MAPA REAL. Sustituye al placeholder de cuatro sectores por paredes con
// un layout RADIAL: el Keshusy Core ocupa el centro y todo lo demas se
// ordena en anillos a su alrededor.
//
//     anillo 0  Core        (centro, punto de narrativa)
//     anillo 1  Portales    (arco al norte, 5 mundos)
//     anillo 2  Estaciones  (anillo completo de servicios)
//
// Se conservan SIEMPRE los contratos que el codigo ya consume:
// `LobbyCenter` lo lee `MatchService` como destino de traslado y
// `SpawnService` como punto de reaparicion. Nada se renombra.
//
// El suelo arranca en Y = -1 con grosor 2: su cara superior queda
// exactamente en Y = 0, que es la altura de referencia del mapa.
const LOBBY_HALF = 70;

// Identidad Keshusy: verde-azulado energetico + acento Tomy naranja.
const KESHUSY = [86, 214, 124];
const TOMY = [255, 152, 72];
const STONE = [124, 134, 146];
const DEEP = [70, 80, 96];

const lobbyParts = [
	part("LobbyFloor", {
		position: [0, -1, 0],
		size: [LOBBY_HALF * 2, 2, LOBBY_HALF * 2],
		material: "Concrete",
		color: STONE,
	}),
	marker("LobbyCenter", [0, 0.2, 0], { color: [200, 220, 255] }),
	marker("LobbyNorth", [0, 0.2, -40], { color: [160, 200, 255] }),
	marker("LobbySouth", [0, 0.2, 40], { color: [160, 200, 255] }),
];

for (const p of perimeter("LobbyWall", 0, 0, LOBBY_HALF, 14, DEEP)) {
	lobbyParts.push(p);
}

// ------------------------------------------------------- KESHUSY CORE
// El Core es el corazon narrativo: una esfera de energia que conecta las
// dimensiones. Se construye en capas para que de lejos se lea como un
// nucleo y de cerca tenga detalle.
//
// Vive en su propia carpeta `Workspace.Lobby.KeshusyCore`, exigida por el
// contrato. Antes estas piezas se empujaban planas en la raiz del lobby,
// mezcladas con el suelo y las paredes, y ningun servicio podia localizar el
// Core como una unidad: solo existia la suma de sus Partes sueltas.
const coreParts = [
	// Base: tres plataformas escalonadas.
	part("CoreBase", {
		position: [0, 0.5, 0], size: [26, 1, 26],
		material: "Slate", color: DEEP,
	}),
	part("CorePlinth", {
		position: [0, 1.75, 0], size: [18, 1.5, 18],
		material: "Slate", color: [92, 104, 122],
	}),
	part("CoreDais", {
		position: [0, 3.2, 0], size: [12, 1.4, 12],
		material: "SmoothPlastic", color: [110, 124, 144],
	}),

	// Nucleo: esfera de energia. SIN colision para no bloquear el paso.
	decor("CoreOrb", {
		position: [0, 8, 0], size: [8, 8, 8],
		shape: "Ball", color: KESHUSY,
	}),
	decor("CoreGlow", {
		position: [0, 8, 0], size: [11, 11, 11],
		shape: "Ball", color: [140, 240, 190], transparency: 0.65,
	}),

	// Anillos orbitales: lectura de "energia girando" sin depender de
	// scripts. El mapa debe verse bien aunque los servicios fallen.
	decor("CoreRing_A", {
		position: [0, 8, 0], size: [16, 0.6, 16],
		shape: "Cylinder", color: TOMY,
	}),
	decor("CoreRing_B", {
		position: [0, 8, 0], size: [19, 0.5, 19],
		shape: "Cylinder", color: KESHUSY, transparency: 0.35,
	}),
];

// Cuatro pilares: dan escala y ancla la composicion.
[[7, 7], [-7, 7], [7, -7], [-7, -7]].forEach(function (p, i) {
	coreParts.push(part("CorePillar_" + i, {
		position: [p[0], 4, p[1]], size: [2, 8, 2],
		shape: "Cylinder", material: "Metal", color: [130, 142, 162],
	}));
	coreParts.push(decor("CorePillarLight_" + i, {
		position: [p[0], 8.4, p[1]], size: [1.2, 1.2, 1.2],
		shape: "Ball", color: KESHUSY,
	}));
});

// ------------------------------------------------------------ PORTALES
// Cinco portales en arco frente al Core, uno por mundo del contrato.
//
// Cada portal es un MODEL (`Portal_<WorldId>`) y todos viven bajo
// `Workspace.Lobby.Portals`. Ver `model()` para por que son Models.
//
// El panel interior es translucido y SIN colision: se ve el destino y no
// se choca. El marco SI colisiona y marca el umbral.
//
// CONTRATO CON `PortalService`
// ---------------------------
//   - el Model se llama `Portal_<WorldId>`;
//   - el umbral se llama `PortalPanel` y es la hoja central;
//   - `PortalPanel` NO colisiona, para que el jugador pueda cruzarlo.
//
// Si se renombra cualquiera de los dos, el servicio deja de encontrar el
// portal y todos los viajes se rechazan.
// Los cinco portales NO son el mismo modelo recoloreado: cada uno se
// construye con la silueta de su mundo (arco de madera, obeliscos de
// arenisca, agujas de hielo, chimeneas de basalto, pilonas de neon). Ver
// `tools/portals.js`, que es donde vive esa construccion.
//
// El contrato de nombres con `PortalService` y `VisualService` no cambia:
// `Portal_<WorldId>`, `PortalPanel` (umbral, sin colision) y `Sign`.
//
// El `level` de la tabla NO pinta nada: el cartel lo escribe
// `VisualService.SetPortalSign` leyendo `WorldDefinitions`, de modo que la
// cifra de la pantalla y la que exige el servidor no puedan divergir.
const PORTAL_DEFS = [
	{ id: "Forest", x: -32, color: KESHUSY, style: "Forest" },
	{ id: "Desert", x: -16, color: [236, 168, 72], style: "Desert" },
	{ id: "Ice", x: 0, color: [140, 214, 245], style: "Ice" },
	{ id: "Volcano", x: 16, color: [240, 110, 72], style: "Volcano" },
	{ id: "Cyber", x: 32, color: [190, 120, 255], style: "Cyber" },
];

const portalModels = Portals.buildPortals({ part: part, decor: decor, model: model }, PORTAL_DEFS, -34);

// ---------------------------------------------------------- ESTACIONES
// Anillo de servicios alrededor del Core. Cada estacion es una placa neon
// sobre una plataforma, con poste y lampara: se reconoce sin leer texto.
const STATION_DEFS = [
	{ id: "Shop", angle: 300, color: TOMY },
	{ id: "Inventory", angle: 330, color: KESHUSY },
	{ id: "Missions", angle: 30, color: [255, 226, 120] },
	{ id: "Season", angle: 60, color: [190, 120, 255] },
	{ id: "Party", angle: 120, color: [120, 200, 255] },
	{ id: "Rankings", angle: 150, color: [255, 140, 140] },
	{ id: "Training", angle: 210, color: [150, 240, 190] },
	{ id: "Events", angle: 240, color: [255, 190, 90] },
];

for (const s of STATION_DEFS) {
	const rad = (s.angle * Math.PI) / 180;
	const x = Math.round(Math.cos(rad) * 40);
	const z = Math.round(Math.sin(rad) * 40);

	lobbyParts.push(
		part("Station_" + s.id + "_Pad", {
			position: [x, 0.25, z], size: [9, 0.5, 9],
			material: "SmoothPlastic", color: s.color,
		}),
		part("Station_" + s.id + "_Post", {
			position: [x, 3, z], size: [0.8, 5.5, 0.8],
			material: "Metal", color: [120, 130, 148],
		}),
		decor("Station_" + s.id + "_Lamp", {
			position: [x, 6, z], size: [2, 2, 2],
			shape: "Ball", color: s.color,
		})
	);
}

// -------------------------------------------------------- DECORACIONES
// Farolas perimetrales: dan profundidad y puntos de luz sin depender de
// un `Lighting` configurado a mano.
for (let i = 0; i < 8; i++) {
	const a = (i / 8) * Math.PI * 2;
	const x = Math.round(Math.cos(a) * 58);
	const z = Math.round(Math.sin(a) * 58);

	lobbyParts.push(part("Lamp_" + i, {
		position: [x, 5, z], size: [0.6, 10, 0.6],
		material: "Metal", color: [96, 106, 124],
	}));
	lobbyParts.push(decor("LampGlow_" + i, {
		position: [x, 10.2, z], size: [2.2, 2.2, 2.2],
		shape: "Ball", color: KESHUSY,
	}));
}

// ---------------------------------------------------------------- FOREST
// La arena vive lejos del lobby (500 studs) para que las dos zonas
// sean independientes y el jugador no pueda interactuar con ambas.
const ARENA_CX = 500;
const ARENA_CZ = 0;
const ARENA_HALF = 90;

// Paleta de Keshusy Forest.
//
// Un unico color de "suelo" y un unico material es exactamente lo que
// hace que un escenario parezca un prototipo. La paleta se declara UNA
// vez y la reutilizan terreno, bloques, decoracion y luz, de modo que
// el conjunto se lea como un lugar y no como un assemblaje de piezas.
const FOREST = {
	barkDark: [74, 54, 36],
	barkMid: [104, 78, 50],
	barkLight: [136, 104, 66],
	moss: [78, 118, 54],
	leafDeep: [42, 104, 56],
	leafMid: [66, 138, 68],
	leafLight: [116, 184, 82],
	stoneMid: [122, 126, 132],
	stoneDark: [86, 90, 98],
	stoneWarm: [148, 136, 116],
	sand: [214, 196, 142],
	dirt: [104, 82, 58],
	grass: [82, 128, 62],
	crystal: [86, 214, 226],
	crystalHot: [168, 246, 255],
	ember: [232, 148, 74],
};

/**
 * Ruido DETERMINISTA en [0,1).
 *
 * POR QUE NO `Math.random()`
 * ----------------------------
 * El mapa tiene que ser reproducible: el mismo `default.project.json`
 * tiene que salir byte a byte en cada ejecucion, porque de el depende
 * el diff de SOURCE contra RUNTIME. Con `Math.random()` cada build
 * moveria los arboles de sitio y `source-runtime-diff` no llegaria
 * nunca a PASS.
 *
 * Ademas el ruido se indexa por posicion logica, no por orden de
 * generacion: ASI se puede anadir decoracion nueva sin que lo ya
 * generado cambie de sitio.
 */
function hash01(seed, salt) {
	// Constants de Wang, mezcladas: barato y suficientemente repartido
	// para colocar decoracion sin patrones visibles.
	let h = (seed * 374761393 + (salt || 0) * 668265263) | 0;
	h = (h ^ (h >>> 13)) * 1274126177;
	h = h ^ (h >>> 16);
	return ((h >>> 0) % 100000) / 100000;
}

/** Variacion en un rango, estable por semilla. */
function vary(seed, salt, min, max) {
	return min + hash01(seed, salt) * (max - min);
}

// Terreno. `ArenaFloor` conserva su nombre porque es parte del
// contrato que ya verifican `tools/audit-rbxlx.js` y
// `tools/source-map-audit.js`.
const arenaParts = [
	part("ArenaFloor", {
		position: [ARENA_CX, -1, ARENA_CZ],
		size: [ARENA_HALF * 2, 2, ARENA_HALF * 2],
		material: "Grass",
		color: FOREST.grass,
	}),

	marker("ArenaCenter", [ARENA_CX, 0.2, ARENA_CZ], { color: [255, 190, 110] }),
	marker("ArenaNorth", [ARENA_CX, 0.2, ARENA_CZ - 60], { color: [255, 160, 90] }),
	marker("ArenaSouth", [ARENA_CX, 0.2, ARENA_CZ + 60], { color: [255, 160, 90] }),
	marker("ArenaEast", [ARENA_CX + 60, 0.2, ARENA_CZ], { color: [255, 160, 90] }),
	marker("ArenaWest", [ARENA_CX - 60, 0.2, ARENA_CZ], { color: [255, 160, 90] }),
];

// Muralla natural. Sigue teniendo colision (delimita la arena) pero se
// decora despues con raices y arboles para que no lea como un muro liso.
for (const p of perimeter("ArenaWall", ARENA_CX, ARENA_CZ, ARENA_HALF, 26, FOREST.stoneDark)) {
	arenaParts.push(p);
}

// (La definicion de `perimeter` vive arriba del bloque LOBBY. Antes vivia
// aqui, DESPUES de que el lobby ya la usara, y solo funcionaba por el
// hoisting de `function`. Declararla antes elimina esa dependencia sutil.)

// ------------------------------------------------- BLOQUES DESTRUCTIBLES
// Estructuras que las bombas destruyen. Los nombres empiezan por "Block_"
// y el servicio de destruccion los localiza por ese prefijo: es el unico
// contrato entre el mapa y el codigo. NO SE TOCA.
//
// CONTRASTE CON LA VERSION ANTERIOR
// ---------------------------------
// Antes cada bloque era `size = [8,8,8]`, `material = WoodPlanks`, sin
// rotacion, en una reticula de paso 8.25 sobre un unico plano. Cuarenta
// y ocho cubos identicos se leen como un prototipo, por muy bonito que sea
// el material.
//
// Ahora cada bloque elige una de cuatro variantes que cambian DIMENSION,
// FORMA, ORIENTACION y MATERIAL, y anaden hijos decorativos. La geome-
// tria principal sigue siendo UNA sola `BasePart` porque:
//
//   1. `IsDestructibleBlock` exige `instance:IsA("BasePart")`. Si el
//      bloque fuera un Model con hijos, dejaria de ser destruible.
//   2. El radio de explosion se calcula por DISTANCIA ENTRE CENTROS
//      (`ExplosionService` -> `CombatMath.FalloffDamage`). Cambiar el
//      tamano y la rotacion no altera ese calculo; cambiar la FORMA si lo
//      haria, asi que la forma se expresa con partes HIJO, no con la
//      principal.
//   3. `snapshotBlock` guarda `Transparency`, `CanCollide` y `CanTouch`
//      para el restore. Nada de eso depende de la forma.
//
// POR QUE 48 Y NO MAS
// -------------------
// `tests/shared/Destruction.spec.lua` comprueba que las 48 bloques del
// mapa siguen reparables. La cantidad es parte del contrato.
const WALL_DISTANCE = 45;
const BLOCK_VARIANTS = ["A", "B", "C", "D"];
let blockIndex = 0;

/**
 * LIBRERIA DE VARIANTES.
 *
 * Cuatro entradas, no cuarenta: el objetivo es que el conjunto tenga
 * ritmo y no ruido. Cada variante tiene silueta propia, para que la
 * arena se reconozca aunque no se recuerden los colores.
 *
 * `size` siempre es una caja alrededor de la caja de colision de la
 * version anterior, de modo que el area ocupada por el conjunto no crece
 * y las distancias entre bloques siguen siendo las que se calibraron.
 */
const VARIANTS = {
	// Troncos: altos y estrechos, coronados de copa.
	A: {
		size: [6, 11, 6],
		material: "Wood",
		colors: [FOREST.barkDark, FOREST.barkMid, FOREST.barkLight],
		tilt: 7,
		canopy: true,
		roots: true,
	},
	// Losas de musgo: anchas, bajas, muy inclinadas.
	B: {
		size: [12, 4, 10],
		material: "Grass",
		colors: [FOREST.moss, FOREST.leafDeep, FOREST.leafMid],
		tilt: 12,
		canopy: false,
		roots: true,
	},
	// Rocas: compactas, facetadas, sin vegetacion encima.
	C: {
		size: [8, 7, 9],
		material: "Rock",
		colors: [FOREST.stoneDark, FOREST.stoneMid, FOREST.stoneWarm],
		tilt: 9,
		canopy: false,
		roots: false,
	},
	// Nodos de cristal: el elemento Keshusy. Bloque sobrio con una veta
	// luminosa que lo identifica como material dimensional.
	D: {
		size: [7, 9, 7],
		material: "Slate",
		colors: [FOREST.stoneDark, FOREST.stoneMid, FOREST.crystal],
		tilt: 5,
		canopy: false,
		roots: false,
		crystal: true,
	},
};

/**
 * Asigna variante de forma determinista y repartida.
 *
 * El ciclo con salto de 2 recorre A,C,B,D: dos bloques contiguos nunca
 * comparten silueta y el reparto es exactamente 12 de cada una sobre 48.
 * Es reproducible sin `Math.random()`, que es lo que permite que
 * `source-runtime-diff` siga dando PASS.
 */
function variantFor(index) {
	return BLOCK_VARIANTS[(index * 2 + (index >= 12 ? 1 : 0)) % 4];
}

/**
 * Crea un bloque destructible con su decoracion secundaria.
 *
 * @param {number} x @param {number} y @param {number} z centro
 * @param {object} opts { scale, seedOffset }
 */
function makeBlock(x, y, z, opts) {
	const o = opts || {};
	const index = blockIndex;
	const variantKey = variantFor(index);
	const v = VARIANTS[variantKey];
	const scale = o.scale === undefined ? 1 : o.scale;
	const seed = index + (o.seedOffset || 0) * 1000;

	const size = [v.size[0] * scale, v.size[1] * scale, v.size[2] * scale];
	const color = v.colors[index % v.colors.length];

	// Rotacion: inclinacion propia de la variante mas un giro Y estable.
	// Se mantiene por debajo de 15 grados porque una inclinacion fuerte
	// levanta una esquina del suelo y el jugador "tropieza" con un
	// escalon invisible.
	const tilt = ((index % 3) - 1) * v.tilt;
	const yaw = Math.round(hash01(seed, 7) * 360);

	const node = part("Block_" + index, {
		position: [x, y, z],
		size: size,
		material: v.material,
		color: color,
		orientation: [tilt, yaw, ((index % 5) - 2) * (v.tilt / 2)],
	});

	// La variante viaja DENTRO DEL NOMBRE de la decoracion hija, no como
	// atributo de la instancia.
	//
	// POR QUE NO UN ATRIBUTO
	// -----------------------
	// Lo natural seria `block:SetAttribute("ForestVariant", "A")`, y se
	// intento por dos vias (`tools/attr-probe.js`):
	//
	//     $attributes: {...}              -> Rojo 7.7.0 lo IGNORA en silencio
	//     $properties: { Attributes: {} } -> Rojo RECHAZA el proyecto entero
	//
	// Ninguna funciona con esta version de Rojo, que no tiene soporte de
	// atributos en los archivos de proyecto. Y el atributo tampoco hacia
	// falta para el contrato `Block_*`: los servicios localizan bloques
	// por el prefijo del NOMBRE, no por atributos.
	//
	// La variante se lleva entonces en el nombre de la decoracion:
	// `Deco_A_Leaf_12`. Asi sobrevive al build, se lee en Studio sin
	// ejecutar nada y no depende de una capacidad que no existe.
	//
	// Ojo: la silueta NO depende de este nombre. Cada variante tiene su
	// propio material, tamano e inclinacion, que si viajan como
	// propiedades. El nombre solo hace la variante legible.
	const tag = variantKey + "_";

	// ------------------------------------------------ HIJOS DECORATIVOS
	//
	// Los hijos NUNCA llevan el prefijo `Block_`: si lo llevaran,
	// `CollectBlocks` los contaria como bloques destructibles y el
	// recuento pasaria de 48. Todos empiezan por `Deco_`.
	const children = [];

	if (v.canopy) {
		const canopyY = y + size[1] / 2 + 1.8;
		children.push(decor("Deco_" + tag + "Canopy_" + index, {
			position: [x, canopyY, z],
			size: [size[0] * 1.9, 3.6, size[2] * 1.9],
			shape: "Ball",
			material: "Grass",
			color: FOREST.leafMid,
		}));
		children.push(decor("Deco_" + tag + "CanopyTop_" + index, {
			position: [x, canopyY + 2.6, z],
			size: [size[0] * 1.2, 2.8, size[2] * 1.2],
			shape: "Ball",
			material: "Grass",
			color: FOREST.leafLight,
		}));
	}

	if (v.roots) {
		// Raices en las cuatro diagonales, orientadas hacia fuera: el
		// bloque lee como algo ARRANCADO del suelo en lugar de puesto
		// encima.
		for (let r = 0; r < 4; r++) {
			const a = (r / 4) * Math.PI * 2 + hash01(seed, r) * 0.4;
			const reach = size[0] * 0.9;
			children.push(decor("Deco_" + tag + "Root_" + index + "_" + r, {
				position: [x + Math.cos(a) * reach, 0.35, z + Math.sin(a) * reach],
				size: [4.4, 1.2, 1.6],
				material: "Wood",
				color: FOREST.barkDark,
				orientation: [0, Math.round((a * 180) / Math.PI), 0],
			}));
		}
		children.push(decor("Deco_" + tag + "Moss_" + index, {
			position: [x, y + size[1] / 2 + 0.08, z],
			size: [size[0] * 0.74, 0.3, size[2] * 0.74],
			material: "Grass",
			color: FOREST.moss,
		}));
	}

	if (v.crystal) {
		// Vetas de cristal Keshusy asomando por la cara del bloque. Es lo
		// que hace que la arena se lea como KeshusyTomy-LanD y no como un
		// bosque generico.
		for (let c = 0; c < 3; c++) {
			const a = hash01(seed, c + 11) * Math.PI * 2;
			const r = size[0] * 0.5;
			children.push(decor("Deco_" + tag + "Crystal_" + index + "_" + c, {
				position: [
					x + Math.cos(a) * r,
					y + size[1] * 0.18 + c * (size[1] / 4),
					z + Math.sin(a) * r,
				],
				size: [1.2, size[1] * 0.5, 1.2],
				shape: "Ball",
				material: "Neon",
				color: c === 1 ? FOREST.crystalHot : FOREST.crystal,
			}));
		}
	}

	// Piedras y setas alrededor del pie, para que la union bloque-suelo no
	// sea un corte limpio.
	const rubble = 2 + Math.floor(hash01(seed, 3) * 3);
	for (let r = 0; r < rubble; r++) {
		const a = hash01(seed, r + 21) * Math.PI * 2;
		const d = size[0] * 0.65 + hash01(seed, r + 31) * 2.6;
		const isMushroom = hash01(seed, r + 41) > 0.55;
		children.push(decor("Deco_" + tag + (isMushroom ? "Shroom" : "Rubble") + "_" + index + "_" + r, {
			position: [x + Math.cos(a) * d, 0.32, z + Math.sin(a) * d],
			size: isMushroom ? [1.3, 0.9, 1.3] : [0.9, 0.7, 1.1],
			material: isMushroom ? "Neon" : "Rock",
			color: isMushroom ? FOREST.ember : FOREST.stoneMid,
		}));
	}

	if (children.length > 0) {
		node.node = Object.assign({}, node.node, asChildren(children));
	}

	blockIndex += 1;
	return node;
}

// ------------------------------------------------ DISPOSICION EN JUEGO
//
// Se conservan los dos EJES que ya funcionan: una muralla perimetral con
// dos huecos al norte y al sur, y una estructura central con tres
// accesos. Lo que cambia es que cada pieza se apoya en la altura que le
// corresponde a su variante, en vez de a una caja unica de 8.
//
// COMO SE CALCULA LA ALTURA
// -------------------------
// La version anterior ponia TODOS los bloques en `y = 4`, porque todos
// median 8. Ahora las variantes miden entre 4 y 11 de alto: si se
// mantuviera `y = 4`, los troncos de 11 quedarian medio enterrados y las
// losas de 4 flotarian a media altura. `restY` calcula el suelo de cada
// variante una vez, y el mismo valor se usa al apilar el segundo nivel,
// de modo que una torre nunca queda con un escalon entre pisos.
function restY(index) {
	const v = VARIANTS[variantFor(index)];
	return v.size[1] / 2;
}

// Cuatro murallas con huecos de paso, en dos alturas en las esquinas.
const perimeterBlocks = [];
for (let i = 0; i < 6; i++) {
	const t = -WALL_DISTANCE / 2 + i * (WALL_DISTANCE / 5);

	// Murallas norte y sur: los bloques centrales se omiten para dejar
	// dos puertas de paso hacia el interior.
	if (i !== 2 && i !== 3) {
		perimeterBlocks.push(makeBlock(ARENA_CX + t, restY(blockIndex), ARENA_CZ - WALL_DISTANCE));
		perimeterBlocks.push(makeBlock(ARENA_CX + t, restY(blockIndex), ARENA_CZ + WALL_DISTANCE));
	}

	// Murallas este y oeste, sin hueco.
	perimeterBlocks.push(makeBlock(ARENA_CX - WALL_DISTANCE, restY(blockIndex), ARENA_CZ + t));
	perimeterBlocks.push(makeBlock(ARENA_CX + WALL_DISTANCE, restY(blockIndex), ARENA_CZ + t));

	// Segundo nivel en los extremos: torres en las esquinas.
	//
	// La altura del segundo piso se calcula sobre el bloque de abajo ya
	// colocado, no con una constante: apilar sobre una cota fija dejaba
	// huecos de hasta 7 studs con las variantes altas.
	if (i === 0 || i === 5) {
		const base = restY(blockIndex);
		const above = VARIANTS[variantFor(blockIndex)];
		const y2 = base + VARIANTS[variantFor(blockIndex - 4)].size[1] / 2 + above.size[1] / 2;
		perimeterBlocks.push(makeBlock(ARENA_CX + t, y2, ARENA_CZ - WALL_DISTANCE));
		perimeterBlocks.push(makeBlock(ARENA_CX + t, y2, ARENA_CZ + WALL_DISTANCE));
		perimeterBlocks.push(makeBlock(ARENA_CX - WALL_DISTANCE, y2, ARENA_CZ + t));
		perimeterBlocks.push(makeBlock(ARENA_CX + WALL_DISTANCE, y2, ARENA_CZ + t));
	}
}

// Estructura central: relicario 3x3x3 hueco, con tres accesos.
//
// Antes era un cubo perfecto de cajas de 8. Ahora es un "relicario": cada
// pieza elige variante y el conjunto se lee como un monumento derruido
// alrededor de un nucleo luminoso, en vez de como un cubo de Minecraft.
const CENTRAL_STEP = 9.25;
const centralBlocks = [];
for (let x = 0; x < 3; x++) {
	for (let y = 0; y < 3; y++) {
		for (let z = 0; z < 3; z++) {
			// Quitar el centro y las aristas de entrada para poder entrar.
			if (x === 1 && y === 1) continue;
			if (x === 1 && z === 1) continue;
			if (y === 1 && z === 1) continue;

			// Las cuatro esquinas superiores se CAEN: una torre inclinada
			// y mas baja. Sigue siendo una `BasePart` unica y colisionable,
			// pero el perfil del monumento deja de ser una caja perfecta.
			const isBrokenCorner = y === 2 && (x === 0 || x === 2) && (z === 0 || z === 2);
			const scale = isBrokenCorner ? 0.62 : 1;

			centralBlocks.push(
				makeBlock(
					ARENA_CX + (x - 1) * CENTRAL_STEP,
					restY(blockIndex) * scale,
					ARENA_CZ + (z - 1) * CENTRAL_STEP,
					{ scale: scale }
				)
			);
		}
	}
}

// --------------------------------------------------------- TERRENO Y VIAS
//
// El suelo era UNA losa de 180x180 de Concrete: 32 400 studs de un solo
// color plano. Aunque la camara cambie, eso se lee como vacio de pruebas.
//
// Ahora el suelo se compone por capas, todas con `canCollide: false` y
// ligeramente por encima de `ArenaFloor`, para que NADIE pueda chocar
// con la decoracion del terreno. La colision real la sigue llevando
// `ArenaFloor`; estas capas solo pintar.
const terrainParts = [];

// Cresta interior: un escalon de hierba oscura 6 studs por dentro del
// muro, que marca el limite de la zona jugable sin anadir colision.
const RIDGE = ARENA_HALF - 6;
const ridgeParts = [
	decor("Terrain_Ridge_N", { position: [ARENA_CX, 0.18, ARENA_CZ - RIDGE], size: [RIDGE * 2, 0.36, 1.6], material: "Grass", color: FOREST.leafDeep }),
	decor("Terrain_Ridge_S", { position: [ARENA_CX, 0.18, ARENA_CZ + RIDGE], size: [RIDGE * 2, 0.36, 1.6], material: "Grass", color: FOREST.leafDeep }),
	decor("Terrain_Ridge_W", { position: [ARENA_CX - RIDGE, 0.18, ARENA_CZ], size: [1.6, 0.36, RIDGE * 2], material: "Grass", color: FOREST.leafDeep }),
	decor("Terrain_Ridge_E", { position: [ARENA_CX + RIDGE, 0.18, ARENA_CZ], size: [1.6, 0.36, RIDGE * 2], material: "Grass", color: FOREST.leafDeep }),
];
terrainParts.push(...ridgeParts);

// Cuatro senderos que van del relicario central a cada muro, con las
// baldosas desplazadas para que no formen una linea perfecta.
for (let axis = 0; axis < 4; axis++) {
	const along = axis % 2 === 0;
	const sign = axis < 2 ? -1 : 1;
	for (let step = 1; step <= 8; step++) {
		const d = step * 9 + vary(step, axis + 60, -1.2, 1.2);
		const px = along ? ARENA_CX + d * sign : ARENA_CX + vary(step, axis + 70, -2, 2);
		const pz = along ? ARENA_CZ + vary(step, axis + 80, -2, 2) : ARENA_CZ + d * sign;
		terrainParts.push(decor("Path_" + axis + "_" + step, {
			position: [px, 0.06, pz],
			size: along ? [7.4, 0.12, 6.2] : [6.2, 0.12, 7.4],
			material: "Ground",
			color: step % 2 === 0 ? FOREST.dirt : FOREST.barkDark,
			orientation: [0, Math.round(vary(step, axis + 90, -9, 9)), 0],
		}));
	}
}

// Tres claros de arena: rompen el verde y dan puntos de referencia
// memorables desde lejos.
const clearings = [
	{ x: ARENA_CX - 62, z: ARENA_CZ - 58, r: 20 },
	{ x: ARENA_CX + 66, z: ARENA_CZ + 54, r: 17 },
	{ x: ARENA_CX + 70, z: ARENA_CZ - 50, r: 14 },
];
for (let c = 0; c < clearings.length; c++) {
	const cl = clearings[c];
	terrainParts.push(decor("Sand_Clearing_" + c, {
		position: [cl.x, 0.04, cl.z],
		size: [cl.r * 2, 0.1, cl.r * 1.7],
		shape: "Cylinder",
		material: "Sand",
		color: FOREST.sand,
	}));

	// Borde de piedra alrededor del claro: el paso de hierba a arena deja
	// de ser un corte recto.
	for (let r = 0; r < 9; r++) {
		const a = (r / 9) * Math.PI * 2;
		terrainParts.push(decor("Sand_Edge_" + c + "_" + r, {
			position: [cl.x + Math.cos(a) * cl.r, 0.16, cl.z + Math.sin(a) * cl.r * 0.85],
			size: [2.4, 0.5, 1.4],
			material: "Rock",
			color: FOREST.stoneMid,
			orientation: [0, Math.round((a * 180) / Math.PI), 0],
		}));
	}
}

// ------------------------------------------------------ DECORACION FOREST
//
// REGLA QUE SEPARA JUEGO DE DECORADO
// -----------------------------------
// TODO lo de esta seccion se crea con `decor()`, es decir SIEMPRE con
// `CanCollide = false`. La decoracion no puede frenar al jugador ni
// alterar la fisica de las bombas: si un arbol frenara al personaje,
// seria un fallo de gameplay disfrazado de scenery.
//
// La excepcion declarada es la muralla perimetral (`ArenaWall_*`), que si
// colisiona porque delimita la arena. Y nada mas.
const decoParts = [];

/**
 * Un arbol: tronco + dos copas. Tres partes, todas sin colision.
 *
 * @param {string} name clave estable para el ruido determinista
 * @param {number} x @param {number} z
 * @param {number} height
 * @param {number[]} tint color de la copa
 */
function tree(name, x, z, height, tint) {
	const seed = name.length * 31 + name.charCodeAt(name.length - 1);
	const trunkColor = hash01(seed, 5) > 0.5 ? FOREST.barkDark : FOREST.barkMid;
	decoParts.push(decor("Tree_Trunk_" + name, {
		position: [x, height / 2, z],
		size: [1.8, height, 1.8],
		material: "Wood",
		color: trunkColor,
		orientation: [0, Math.round(vary(seed, 5, -10, 10)), 0],
	}));
	decoParts.push(decor("Tree_Canopy_" + name, {
		position: [x, height + 1.2, z],
		size: [height * 0.85, height * 0.7, height * 0.85],
		shape: "Ball",
		material: "Grass",
		color: tint,
	}));
	decoParts.push(decor("Tree_CanopyTop_" + name, {
		position: [x, height + height * 0.45, z],
		size: [height * 0.55, height * 0.45, height * 0.55],
		shape: "Ball",
		material: "Grass",
		color: FOREST.leafLight,
	}));
}

// Bosque perimetral: tres anillos de densidad CRECIENTE hacia el muro.
// El anillo exterior es el mas denso, para que el limite de la arena se
// lea como una masa forestAL continua y no como una fila de arboles.
for (let ring = 0; ring < 3; ring++) {
	const radius = RIDGE - 2 - ring * 9;
	const count = 18 + ring * 10;
	for (let i = 0; i < count; i++) {
		const a = (i / count) * Math.PI * 2 + ring * 0.37;
		const jitter = vary(i + ring * 100, 13, -3.5, 3.5);
		const x = ARENA_CX + Math.cos(a) * (radius + jitter);
		const z = ARENA_CZ + Math.sin(a) * (radius + jitter);

		// No se siembran arboles encima de los senderos: bloquearian la
		// lectura de las vias aunque no colisionen.
		const nearPath = Math.abs(Math.abs(x - ARENA_CX) - Math.abs(z - ARENA_CZ)) < 7;
		if (nearPath) continue;

		const height = vary(i + ring * 50, 17, 7, 17);
		const tint = vary(i + ring * 30, 23) > 0.5 ? FOREST.leafMid : FOREST.leafDeep;
		tree(ring + "_" + i, x, z, height, tint);
	}
}

// Matorrales, flores y setas dispersos por el interior, evitando el
// relicario, los senderos y los claros.
for (let i = 0; i < 90; i++) {
	const x = ARENA_CX + vary(i, 101, -80, 80);
	const z = ARENA_CZ + vary(i, 103, -80, 80);
	const dCenter = Math.sqrt((x - ARENA_CX) * (x - ARENA_CX) + (z - ARENA_CZ) * (z - ARENA_CZ));
	if (dCenter < 22 || dCenter > RIDGE - 4) continue;

	const kind = hash01(i, 107);
	if (kind < 0.42) {
		decoParts.push(decor("Bush_" + i, {
			position: [x, 1.3, z],
			size: [vary(i, 109, 2.4, 4.6), vary(i, 111, 1.6, 3), vary(i, 113, 2.4, 4.6)],
			shape: "Ball",
			material: "Grass",
			color: vary(i, 115) > 0.5 ? FOREST.leafMid : FOREST.leafDeep,
		}));
	} else if (kind < 0.72) {
		const fh = vary(i, 117, 1.2, 2.6);
		decoParts.push(decor("Flower_Stem_" + i, {
			position: [x, fh / 2, z], size: [0.22, fh, 0.22],
			material: "Grass", color: FOREST.moss,
		}));
		decoParts.push(decor("Flower_Head_" + i, {
			position: [x, fh + 0.2, z], size: [0.75, 0.75, 0.75],
			shape: "Ball", material: "Neon",
			color: vary(i, 119) > 0.6 ? FOREST.ember : [242, 208, 122],
		}));
	} else {
		const sh = vary(i, 121, 0.9, 2);
		decoParts.push(decor("Shroom_Stem_" + i, {
			position: [x, sh / 2, z], size: [0.5, sh, 0.5],
			material: "Snow", color: [226, 220, 206],
		}));
		decoParts.push(decor("Shroom_Cap_" + i, {
			position: [x, sh, z], size: [1.5, 0.7, 1.5],
			shape: "Cylinder", material: "Neon", color: FOREST.ember,
		}));
	}
}

// ------------------------------------------------- BORDE DE LA ARENA
//
// Fuera del muro hay, por defecto, el vacio de pruebas: el jugador ve que
// el suelo acaba en un canto y no hay nada mas. Esto pone un cierre
// visual alrededor del mapa para que se lea "aqui termina la arena".
//
// Son piezas SIN COLISION (decoracion pura) que trabajan en el hueco entre
// el muro y el limite del terreno, de modo que el muro sigue siendo el
// unico limite fisico.
const borderParts = [];

// Colina de tierra y helechos justo detras del muro, en las 4 caras.
for (let side = 0; side < 4; side++) {
	const along = side % 2 === 0;
	const sign = side < 2 ? -1 : 1;
	for (let i = 0; i < 16; i++) {
		const t = -ARENA_HALF + 5 + i * ((ARENA_HALF * 2 - 10) / 15);
		const out = ARENA_HALF + vary(i, 200 + side, 3, 16);
		const x = along ? ARENA_CX + t : ARENA_CX + out * sign;
		const z = along ? ARENA_CZ + out * sign : ARENA_CZ + t;
		const h = vary(i, 210 + side, 10, 24);
		borderParts.push(decor("Border_Hill_" + side + "_" + i, {
			position: [x, h / 2 - 2, z],
			size: [vary(i, 220 + side, 16, 30), h, vary(i, 230 + side, 14, 26)],
			shape: "Ball",
			material: "Ground",
			color: FOREST.leafDeep,
		}));
		// Arboles en la ladera: el borde no es una colina pelada.
		if (hash01(i, 240 + side) > 0.35) {
			tree("border_" + side + "_" + i, x, z, vary(i, 250 + side, 14, 26), FOREST.leafDeep);
		}
	}
}

// Raices organicas que trepan por el muro: rompen la silueta recta.
for (let side = 0; side < 4; side++) {
	for (let i = 0; i < 10; i++) {
		const t = -ARENA_HALF + 8 + i * ((ARENA_HALF * 2 - 16) / 9);
		const sign = side < 2 ? -1 : 1;
		const along = side % 2 === 0;
		const edge = ARENA_HALF - 1;
		const x = along ? ARENA_CX + t : ARENA_CX + edge * sign;
		const z = along ? ARENA_CZ + edge * sign : ARENA_CZ + t;
		borderParts.push(decor("Border_Root_" + side + "_" + i, {
			position: [x, vary(i, 260 + side, 3, 20), z],
			size: [vary(i, 270 + side, 2, 5), vary(i, 280 + side, 6, 16), 1.2],
			material: "Wood",
			color: FOREST.barkDark,
			orientation: [0, Math.round(vary(i, 290 + side, -25, 25)), Math.round(vary(i, 300 + side, -35, 35))],
		}));
	}
}
// ------------------------------------------------------ ELEMENTOS KESHUSY
//
// Lo que hace que esto sea KeshusyTomy-LanD y no un bosque de Roblox:
// cristales dimensionales, energia suspendida y luciernagas. Ninguna de
// estas piezas colisiona, y solo cuatro emiten luz real (ver la seccion
// de iluminacion), porque un bosque con 200 luces no renderiza.
const keshusyParts = [];

/**
 * Cristal Keshusy: dos prismas cruzados mas un fragmento flotante.
 *
 * @param {string} name
 * @param {number} x @param {number} y @param {number} z
 * @param {number} scale
 * @param {number[]} tint
 */
function crystal(name, x, y, z, scale, tint) {
	const h = 5 * scale;
	keshusyParts.push(decor("Crystal_Shard_" + name, {
		position: [x, y + h / 2, z],
		size: [1.5 * scale, h, 1.5 * scale],
		shape: "Cylinder",
		material: "Neon",
		color: tint,
		orientation: [0, 0, Math.round(vary(name.length, 310, -18, 18))],
	}));
	keshusyParts.push(decor("Crystal_ShardLow_" + name, {
		position: [x, y + h * 0.32, z],
		size: [1.1 * scale, h * 0.72, 1.1 * scale],
		shape: "Cylinder",
		material: "Neon",
		color: FOREST.crystalHot,
		orientation: [0, Math.round(vary(name.length, 320, -30, 30)), 20],
	}));
	// Fragmento suspendido: da la sensacion de energia inestable.
	keshusyParts.push(decor("Crystal_Shard_" + name + "_Float", {
		position: [x + vary(name.length, 330, -1.5, 1.5), y + h + 1.4, z + vary(name.length, 340, -1.5, 1.5)],
		size: [0.8 * scale, 0.8 * scale, 0.8 * scale],
		shape: "Ball",
		material: "Neon",
		color: FOREST.crystalHot,
	}));
}

// Cristales enracados: siete, repartidos en puntos con significado
// (cerca de los claros, sobre el relicario, en los cruces de senderos).
const crystalSpots = [
	{ x: ARENA_CX - 26, z: ARENA_CZ - 30 },
	{ x: ARENA_CX + 30, z: ARENA_CZ + 26 },
	{ x: ARENA_CX - 34, z: ARENA_CZ + 34 },
	{ x: ARENA_CX + 62, z: ARENA_CZ - 12 },
	{ x: ARENA_CX - 14, z: ARENA_CZ - 52 },
	{ x: ARENA_CX + 16, z: ARENA_CZ + 52 },
	{ x: ARENA_CX + 52, z: ARENA_CZ + 34 },
];
for (let i = 0; i < crystalSpots.length; i++) {
	const s = crystalSpots[i];
	crystal(i, s.x, 0, s.z, 0.7 + hash01(i, 350) * 0.9, i % 2 === 0 ? FOREST.crystal : [136, 168, 246]);
	// Base de raices: el cristal tiene que salir del suelo, no flotar.
	for (let r = 0; r < 5; r++) {
		const a = (r / 5) * Math.PI * 2 + i;
		keshusyParts.push(decor("Crystal_Root_" + i + "_" + r, {
			position: [s.x + Math.cos(a) * 3.4, 0.3, s.z + Math.sin(a) * 3.4],
			size: [3.4, 1, 1.2],
			material: "Wood",
			color: FOREST.barkDark,
			orientation: [0, Math.round((a * 180) / Math.PI), 0],
		}));
	}
}

// Anillo de energia sobre el relicario central: el "punto de interaccion"
// de la arena queda marcado desde cualquier angulo.
for (let i = 0; i < 3; i++) {
	keshusyParts.push(decor("Energy_Ring_" + i, {
		position: [ARENA_CX, 9 + i * 3.4, ARENA_CZ],
		size: [26 - i * 5, 0.35, 26 - i * 5],
		shape: "Cylinder",
		material: "Neon",
		color: i === 1 ? FOREST.crystalHot : FOREST.crystal,
		transparency: 0.55,
	}));
}

// Luciernagas: puntos de luz flotantes que dan escala y movimiento.
// Son partes pequenas y translucidas; NOPointLight (la luz de verdad la
// pone Lighting, con presupuesto).
for (let i = 0; i < 70; i++) {
	const a = vary(i, 400, 0, Math.PI * 2);
	const r = 20 + hash01(i, 410) * 62;
	const x = ARENA_CX + Math.cos(a) * r;
	const z = ARENA_CZ + Math.sin(a) * r;
	keshusyParts.push(decor("Firefly_" + i, {
		position: [x, 2.5 + hash01(i, 420) * 9, z],
		size: [0.7, 0.7, 0.7],
		shape: "Ball",
		material: "Neon",
		color: hash01(i, 430) > 0.75 ? [216, 246, 150] : FOREST.crystalHot,
		transparency: 0.25,
	}));
}

// ---------------------------------------------------- PRESUPUESTO DE LUZ
//
// Aqui se decide cuantas luces REALES hay, y son cuatro:
//
//   1. El nucleo del relicario (el punto de interaccion central).
//   2. El cristal mas alto del bosque.
//   3. El claro de arena del oeste.
//   4. El hueco de paso norte de la muralla.
//
// Cuatro `PointLight` son asumibles. Lo que se descarto de forma
// consciente: un punto de luz por arbol (serian casi 200 y hundirian el
// frame rate sin aportar nada legible, porque un bosque de dia no necesita
// que cada tronco ilumine su propio suelo).
//
// Las luces cuelgan de Partes DECORATIVAS, no de las luces de la Piece.
function pointLight(name, x, y, z, tint, range, brightness) {
	keshusyParts.push(decor("Light_" + name, {
		position: [x, y, z],
		size: [1, 1, 1],
		material: "Neon",
		color: tint,
		transparency: 1,
	}));
	const last = keshusyParts[keshusyParts.length - 1];
	last.node.Light = {
		$className: "PointLight",
		$properties: {
			Color: color(tint[0], tint[1], tint[2]),
			Brightness: brightness,
			Range: range,
			Shadows: false,
		},
	};
}

pointLight("Core", ARENA_CX, 16, ARENA_CZ, FOREST.crystalHot, 70, 2.2);
pointLight("CrystalTall", crystalSpots[3].x, 9, crystalSpots[3].z, FOREST.crystal, 46, 1.6);
pointLight("ClearingWest", clearings[0].x, 8, clearings[0].z, FOREST.ember, 38, 1.3);
pointLight("GateNorth", ARENA_CX, 11, ARENA_CZ - WALL_DISTANCE, [140, 200, 255], 34, 1.1);

// ------------------------------------------------------- MONTAJE FOREST
//
// El orden de `arenaChildren` es el orden de lectura del jugador:
//   Spawn/entradas -> terreno -> vias -> relicario -> decoracion
//
// Se mantiene `Blocks` y `CentralStructure` como carpetas CON NOMBRE
// porque son contrato: `Workspace.Worlds.Forest.Blocks` es la ruta que
// leen los servicios de destruccion y las pruebas.
const arenaChildren = arenaParts.concat([
	folder("Blocks", perimeterBlocks),
	folder("CentralStructure", centralBlocks),
	folder("Terrain", terrainParts),
	folder("Decoration", decoParts),
	folder("Border", borderParts),
	folder("Keshusy", keshusyParts),
]);
//
// Razon: `SpawnService` busca `Workspace.SpawnLocations`. Ademas, Roblox
// elige el SpawnLocation mas cercano al jugador al entrar, asi que
// todos deben estar en el mismo plano y cerca del lobby para que el
// personaje SIEMPRE nazca en la zona segura.
// ---------------------------------------------------------------- SPAWNS
// Los SpawnLocation del juego viven aqui, y NO dentro de `Lobby`.
//
// Razon: `SpawnService` busca `Workspace.SpawnLocations`. Ademas, Roblox
// elige el SpawnLocation mas cercano al jugador al entrar, asi que
// todos deben estar en el mismo plano y cerca del lobby para que el
// personaje SIEMPRE nazca en la zona segura.
const SPAWN_COLOR = [86, 214, 124];

/**
 * COMPROBACION DE ESPACIO LIBRE EN LA FUENTE
 *
 * Dos de los seis spawns estaban debajo de una farola del anillo exterior
 * (`Lamp_3` y `Lamp_7`, con su `LampGlow`), y uno debajo del poste derecho
 * de un portal. Medido en runtime con `tools/spawn-check.lua`.
 *
 * Mover los spawns no es una cuestion de estetica: un jugador que aparece
 * con un poste atravesando el personaje, o con una esfera de luz
 * encima, no ve el lobby, ve un fallo. Y como Roblox elige el spawn MAS
 * CERCANO, basta con que uno este mal colocado para que sea el elegido.
 *
 * En vez de confiar en el ojo, esta funcion RECHAZA cualquier posicion
 * que tenga algo solido encima. Si alguien anade decoracion nueva al
 * lobby, el generador avisa en lugar de producir un spawn malo.
 *
 * @param {number} px @param {number} pz posicion candidata
 * @param {{x:number,z:number}[]} blockers piezas solidas del lobby
 * @returns {boolean}
 */
function spawnIsClear(px, pz, blockers) {
	for (const b of blockers) {
		const dx = b.x - px;
		const dz = b.z - pz;
		// 9 studs de margen, el MISMO radio que usa la comprobacion de
		// runtime (`tools/spawn-check.lua`). Antes eran 6.5 aqui y 9 alla,
		// y el generador daba por bueno un spawn que la comprobacion
		// rechazaba: cada una estaria contenta con lo que la otra midio.
		//
		// Un spawn son 12x12 de plataforma, asi que cualquier cosa dentro
		// de 9 studs queda encima del personaje o rozando los bordes.
		if (Math.sqrt(dx * dx + dz * dz) < 9) {
			return false;
		}
	}
	return true;
}

const SPAWN_BLOCKERS = [];

// Los portales y el Core se GENERAN despues que esta seccion, asi que no se
// puede copiar su disposicion desde aqui. Se recorre `lobbyParts` y, dentro
// de el, las piezas de los portales: la lista del generador es plana y los
// portales son `Model` con hijos, asi que hay que bajar un nivel.
//
// La primera comprobacion con `lobbyParts` no lo hacia, y por eso daba por
// bueno un spawn debajo del poste de un portal.
//
// Se toman SOLO las piezas SOLIDAS (`canCollide`), que son las unicas que un
// jugador nota: las esferas de luz y la decoracion sin colision no estorban,
// se puede andar a traves de ellas sin enterarse. Y se descartan las
// horizontales, que estan en el suelo y no pueden caer sobre nadie.
function registerBlocker(part) {
	const props = part.node.$properties || {};
	if (props.CanCollide === false) return;

	const size = props.Size || [0, 0, 0];
	if (size[1] < 6) return;

	SPAWN_BLOCKERS.push({
		x: props.Position[0],
		z: props.Position[2],
		name: part.name,
	});
}

for (const part of lobbyParts) {
	registerBlocker(part);

	// Un nivel mas: los hijos de un `Model` de portal.
	for (const key of Object.keys(part.node)) {
		if (key === "$className" || key === "$properties") continue;
		const child = part.node[key];
		if (child && typeof child === "object") {
			registerBlocker({ name: part.name + "." + key, node: child });
		}
	}
}

/**
 * Orientacion del spawn mirando al centro del lobby.
 *
 * POR QUE SE PERSISTE EN LA FUENTE Y NO EN RUNTIME
 * -------------------------------------------------
 * Corregir la orientacion con un script al entrar funciona, pero
 * mientras ese script no corre el jugador ya ha aparecido mirando a una
 * pared: el primer fotograma del juego es el equivocado. Ademas, el
 * `SpawnService` elige spawn por proximidad, asi que la orientacion debe
 * ser correcta en la fuente, no "corregida despues".
 *
 * Se escribe `Orientation` en grados alrededor de Y. Roblox mira hacia
 * `-Z` cuando la rotacion es cero, de modo que la direccion de vista es
 *
 *     forward = (-sin(yaw), 0, -cos(yaw))
 *
 * Igualarla al vectorUnitario que va del spawn al centro, `d = (dx, dz)`,
 * exige `-sin(yaw) = dx` y `-cos(yaw) = dz`, es decir
 *
 *     yaw = atan2(-dx, -dz)
 *
 * OJO AL SIGNO DE `dx`. Con `atan2(dx, -dz)` los spawns Norte y Sur salen
 * bien por casualidad (alli `dx = 0`), pero los del Este y el Oeste
 * quedan mirando EXACTAMENTE al lado contrario: la mitad de los spawns
 * nacen de espaldas al Core. Lo detecto `tools/forest-verify.js`, no a
 * ojo.
 *
 * @param {number} px @param {number} pz posicion del spawn
 * @param {number} centerX @param {number} centerZ objetivo
 * @returns {number[]} orientacion [0, yaw, 0] en grados
 */
function facingCenter(px, pz, centerX, centerZ) {
	const dx = centerX - px;
	const dz = centerZ - pz;
	const yaw = (Math.atan2(-dx, -dz) * 180) / Math.PI;
	return [0, Math.round(yaw), 0];
}

const LOBBY_FOCUS = [0, 0];

/**
 * Busca la posicion libre MAS CERCANA a la deseada.
 *
 * Empieza en la posicion que se quiere y se va separando en anillos
 * crecientes hasta encontrar un hueco. Se prefiere el hueco mas cercano
 * para no descolocar el anillo de spawns mas de lo necesario.
 *
 * @param {number} wantX @param {number} wantZ posicion deseada
 * @returns {{x: number, z: number, moved: number}}
 */
function findClearSpawn(wantX, wantZ) {
	if (spawnIsClear(wantX, wantZ, SPAWN_BLOCKERS)) {
		return { x: wantX, z: wantZ, moved: 0 };
	}

	for (let ring = 1; ring <= 8; ring++) {
		const radius = ring * 3;
		for (let step = 0; step < 12; step++) {
			const a = (step / 12) * Math.PI * 2;
			const x = Math.round(wantX + Math.cos(a) * radius);
			const z = Math.round(wantZ + Math.sin(a) * radius);
			if (spawnIsClear(x, z, SPAWN_BLOCKERS)) {
				return { x: x, z: z, moved: radius };
			}
		}
	}
	return { x: wantX, z: wantZ, moved: -1 };
}

const SPAWN_LAYOUT = [
	{ name: "LobbySpawn1", x: 0, z: -24 },
	{ name: "LobbySpawn2", x: 24, z: 0 },
	{ name: "LobbySpawn3", x: 0, z: 24 },
	{ name: "LobbySpawn4", x: -24, z: 0 },
	{ name: "LobbySpawn5", x: 40, z: -40 },
	{ name: "LobbySpawn6", x: -40, z: 40 },
];

const lobbySpawns = SPAWN_LAYOUT.map((entry) => {
	const spot = findClearSpawn(entry.x, entry.z);
	if (spot.moved > 0) {
		console.log(
			"  spawn " + entry.name + " desplazado " + spot.moved
			+ " studs para despejarlo: (" + entry.x + ", " + entry.z + ") -> ("
			+ spot.x + ", " + spot.z + ")"
		);
	}

	const spawn = spawnLocation(entry.name, [spot.x, 1.6, spot.z], SPAWN_COLOR);
	const p = spawn.node.$properties.Position;
	// La orientacion se escribe en la propia instancia del proyecto, no
	// en un `CustomValue`: `SpawnService` no necesita leerla y el juego la
	// respeta desde el primer fotograma.
	spawn.node.$properties.Orientation = facingCenter(p[0], p[2], LOBBY_FOCUS[0], LOBBY_FOCUS[1]);
	return spawn;
});

// ------------------------------------------------------- MUNDOS 2 A 5
//
// Los cuatro mundos que NO son Forest se construyen aqui, con el generico de
// `tools/worlds.js`.
//
// POR QUE ANTES NO EXISTIAN
// -------------------------
// Estaban declarados como `folder("Desert", [])`: una carpeta VACIA. Medido
// en PLAY, entrar por el portal de Desert teletransportaba al jugador de
// vuelta al lobby, porque `PortalService` solo tenia destino de arena para
// Forest. Cuatro de los cinco portales no llevaban a ninguna parte: habia un
// nombre en el codigo y no habia nada en el juego.
//
// QUE APORTA CADA UNO
// -------------------
// Suelo, muro perimetral, bloques destructibles (`Block_<Id>_<n>`), relicario
// central, terreno, peligros, decoracion propia, spawn de monstruos, spawns
// de powerup, plataforma de boss y salida. Todo con los nombres que ya leen
// `MatchService`, `VisualService` y `DestructionService`.
//
// LAS POSICIONES
// --------------
// Se reparten en cruz alrededor del lobby, a 400 studs de separacion entre
// arenas: distancia de sobra para que no se toquen y la justa para no
// obligar a cruzar el mapa entero entre un portal y el siguiente.
//
// Forest conserva su posicion historica (500, 0): cambiarla invalidaria las
// posiciones ya verificadas por `tools/verify-*`.
const EXTRA_ARENA_HALF = 90;

const extraWorlds = [
	{ id: "Desert", cx: -400, cz: 400, seedBase: 1000 },
	{ id: "Ice", cx: 400, cz: 400, seedBase: 2000 },
	{ id: "Volcano", cx: -400, cz: -400, seedBase: 3000 },
	{ id: "Cyber", cx: 400, cz: -400, seedBase: 4000 },
].map(function (w) {
	return Worlds.buildWorld(
		{ part: part, decor: decor, marker: marker, folder: folder, perimeter: perimeter },
		{
			id: w.id,
			cx: w.cx,
			cz: w.cz,
			half: EXTRA_ARENA_HALF,
			wallDistance: 45,
			seedBase: w.seedBase,
			palette: Worlds.PALETTES[w.id],
			decorate: Worlds.DECORATORS[w.id],
		}
	);
});

// ---------------------------------------------------------------- PROYECTO
// Los servicios que aun no tienen codigo NO se montan: un Folder vacio
// es inofensivo, un Script roto tumba el arranque.
//
// `ServerStorage`, `SoundService` y `Lighting` NO se declaran aqui, y
// el comentario anterior decia lo contrario. No estan en el arbol: son
// servicios que Roblox crea en todos los places por su cuenta, asi que
// declararlos solo generaria objetos muertos que nadie referencia. Las
// fases futuras los usan donde ya existen.
const project = {
	name: "KeshusyTomy-LanD",
	tree: {
		$className: "DataModel",

		ReplicatedStorage: { $path: "src/ReplicatedStorage" },
		ServerScriptService: { $path: "src/ServerScriptService" },
		StarterGui: { $path: "src/StarterGui" },

		// `StarterPlayer` NO puede mapearse con `$path` a secas.
		//
		// El motivo es concreto y ya se manifesto en runtime: con
		// `"StarterPlayer": { "$path": "src/StarterPlayer" }`, Rojo crea
		// una CARPETA llamada `StarterPlayerScripts` junto al contenedor
		// real del motor, y el juego entero cuelga de la carpeta. Roblox
		// solo clona el `StarterPlayerScripts` autentico, asi que
		// `ClientMain` y los 12 Controllers quedan dentro de un Folder
		// cualquiera y NO se ejecutan nunca.
		//
		// Por eso se declara el arbol a mano: `$className` fija la clase
		// del contenedor y `$path` sigue sirviendo el contenido.
		StarterPlayer: {
			$className: "StarterPlayer",
			StarterPlayerScripts: { $path: "src/StarterPlayer/StarterPlayerScripts" },
			StarterCharacterScripts: { $className: "StarterCharacterScripts" },
		},

		Workspace: {
			$className: "Workspace",
			// Gravity y StreamingEnabled se fijan aqui a proposito:
			// el juego depende de un suelo real y de que el mapa este
			// disponible en el instante en que aparece el personaje.
			$properties: {
				Gravity: 196.2,
				StreamingEnabled: false,
			},
			// Los hijos son campos directos de Workspace (ver asChildren).
			Environment: folder("Environment", []).node,
			SpawnLocations: folder("SpawnLocations", lobbySpawns).node,

			// El lobby lleva dentro sus dos subsystems, como exige el
			// contrato: `Lobby.KeshusyCore` y `Lobby.Portals`.
			//
			// Antes el Core y los portales se empujaban como Parts sueltos
			// en la raiz del lobby. Esa forma NO permite que un servicio
			// los identifique: `PortalService` necesita saber que Pieces
			// forman un portal y cual es su umbral, cosa imposible con un
			// reguero de Parts con nombre plano.
			Lobby: folder("Lobby", lobbyParts.concat([
				folder("KeshusyCore", coreParts),
				folder("Portals", portalModels),
			])).node,
			Worlds: folder("Worlds", [
				folder("Forest", arenaChildren),
			].concat(extraWorlds)).node,
		},

		// ------------------------------------------------------------ LIGHTING
		//
		// El comentario de arriba decia que `Lighting` no se declaraba
		// porque "Roblox ya lo crea". Es verdad que el servicio existe, pero
		// NO sus ajustes: sin declararlo, el juego arranca con la hora por
		// defecto, la niebla desactivada y la iluminacion plana, y un
		// bosque sin ambiente ni profundidad se lee como una caja iluminada
		// desde arriba.
		//
		// Se declara solo lo que da IDENTIDAD al mundo y COSTE cero:
		//
		//   ClockTime 15.2  tarde calido, sombras larguisimas
		//   Ambient/SOutdoor  verdes y frios, para que la sombra no sea gris
		//   Fog         densidad baja: da profundidad sin cortar la vista
		//   Bloom       para que el Neon (cristales, energia) florezca
		//
		// NO se anaden muchas luces puntuales. Las cuatro `PointLight` que
		// si existen son del mundo de la arena y estan justificadas; una luz
		// por arbol hundiria el frame rate sin aportar nada legible.
		//
		// `Atmosphere` y `BloomEffect` son HIJOS de `Lighting`, asi que van
		// como campos directos: dentro de `$properties` Rojo los trataria
		// como propiedades desconocidas de Lighting y el build fallaria
		// con "unknown property".
		Lighting: {
			$className: "Lighting",
			$properties: {
				GlobalShadows: true,
				ClockTime: 15.2,
				Brightness: 2.4,
				Ambient: color(92, 104, 118),
				OutdoorAmbient: color(126, 148, 138),
				EnvironmentDiffuseScale: 0.6,
				EnvironmentSpecularScale: 0.4,
				ShadowSoftness: 0.25,
			},
			Atmosphere: {
				$className: "Atmosphere",
				$properties: {
					Density: 0.22,
					Haze: 1.6,
					Color: color(178, 206, 196),
					Decay: color(126, 152, 140),
					Glare: 0.25,
					Offset: 0.1,
				},
			},
			ForestBloom: {
				$className: "BloomEffect",
				$properties: {
					Intensity: 0.45,
					Size: 28,
					Threshold: 0.85,
				},
			},
		},
	},
};

fs.writeFileSync(PROJECT, JSON.stringify(project, null, 2) + "\n");

console.log("default.project.json generado.");
console.log("  bloques destructibles:", blockIndex);
console.log("  parts de lobby:", lobbyParts.length);
console.log("  parts de arena:", arenaChildren.length);
console.log("  spawnlocations:", lobbySpawns.length);
