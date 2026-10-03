// worlds.js
// Constructor de los CINCO MUNDOS JUGABLES para `generate-project.js`.
//
// POR QUE ESTE MODULO Y NO DENTRO DEL GENERADOR
// --------------------------------------------
// El generador principal construye el lobby y el bosque y ya supera las dos
// mil lineas. Los cinco mundos son geometria nueva con el MISMO contrato de
// nombres y el MISMO motor de zonas, asi que viven aqui. El generador solo
// los llama.
//
// QUE ES UN MUNDO (Y QUE NO LO ES)
// ---------------------------------
// La version anterior construia una losa cuadrada de 180x180 studs, un muro
// perimetral y decoracion alrededor, y lo llamaba arena. Medido en runtime
// (`.ai/probes/world-bounds.lua`): los cinco mundos con bounding box ~210x210,
// CERO zonas y CERO rutas. Eso no es un mundo: es un escenario.
//
// Un mundo jugable tiene ESTRUCTURA DE RECORRIDO, y esa estructura es
// geometria real, no carpetas:
//
//   ENTRANCE -> EXPLORATION -> FIRST ENCOUNTER -> DESTRUCTION
//             -> ROUTE A / ROUTE B -> INTERMEDIATE ENCOUNTER
//             -> REWARD -> MAIN ARENA -> BOSS -> EXIT
//
// Cada zona es una plataforma IRREGULAR (un ensamblaje de losas de sizes y
// giros distintos, no un rectangulo) con su cota, su material y sus
// obstaculos. Cada ruta es un recorrido REAL de losas con estilo propio
// (sendero, puente, canon, tunel, pasarela, galeria). El limite del mundo se
// cierra alrededor de la silueta que forman zonas y rutas, y el spawn no ve el
// resto de la experiencia: hay que recorrerla.
//
// LO QUE SE COMPARTE Y LO QUE NO
// ------------------------------
// COMPARTIDO, escrito UNA vez (contrato tecnico):
//   ArenaFloor, ArenaCenter, ArenaNorth/South/East/West
//   Blocks/ CentralStructure/ Terrain/ Hazards/ Decoration/ Border/ Keshusy/
//   MonsterSpawns/ PowerupSpawns/ Zones/ Routes/
//   SpawnPoint_<Id>  BossSpawn_<Id>  Exit_<Id>
//
// NO compartido: el LAYOUT. Cada mundo declara sus propias zonas, su propia
// topologia de rutas, su paleta y su decoracion. Dos mundos con el mismo
// esqueleto y otros numeros NO son mundos distintos: por eso los datos de cada
// uno estan escritos a mano en `LAYOUTS`, y por eso hay un test que falla si
// dos mundos acaban con la misma firma de zonas.

const v3 = (x, y, z) => [x, y, z];
const color = (r, g, b) => [r / 255, g / 255, b / 255];

/**
 * Ruido determinista en [0,1).
 *
 * Se replica en vez de importarse porque `generate-project.js` lo declara con
 * `function` en su propio ambito y no exporta nada: importarlo exigiria
 * refactorizar el generador entero. La formula es de Wang, es corta y es
 * estable, que es lo unico que importa: el mapa tiene que ser reproducible
 * byte a byte entre builds, o `source-runtime-diff` nunca llega a PASS.
 */
function hash01(seed, salt) {
	let h = (seed * 374761393 + (salt || 0) * 668265263) | 0;
	h = (h ^ (h >>> 13)) * 1274126177;
	h = h ^ (h >>> 16);
	return ((h >>> 0) % 100000) / 100000;
}

/** Variacion estable dentro de un rango. */
function vary(seed, salt, min, max) {
	return min + hash01(seed, salt) * (max - min);
}

/**
 * Grados de giro sobre Y para alinear el EJE X de una caja con el vector
 * (dx,dz) del plano XZ.
 *
 * Se usa en rutas, puentes y senderos: sin esto, un "camino" que gira 30
 * grados sigue siendo una caja recta y el mapa vuelve a leerse como una
 * rejilla alineada.
 */
function yawTo(dx, dz) {
	return Math.round((Math.atan2(-dz, dx) * 180) / Math.PI);
}

/**
 * Distancia en el plano XZ de un punto al segmento AB.
 *
 * Se usa para sembrar obstaculos y decoracion "cerca de una ruta" sin que la
 * ruta se lea como un tubo perfecto.
 */
function distToSegment(px, pz, ax, az, bx, bz) {
	const vx = bx - ax;
	const vz = bz - az;
	const len2 = vx * vx + vz * vz;
	const t = len2 === 0 ? 0 : Math.max(0, Math.min(1, ((px - ax) * vx + (pz - az) * vz) / len2));
	const dx = px - (ax + vx * t);
	const dz = pz - (az + vz * t);
	return Math.sqrt(dx * dx + dz * dz);
}

/**
 * Radio de una elipse (rx,rz) en la direccion (dx,dz), en el plano XZ.
 *
 * Es lo que permite que una ruta nazca en el BORDE de su zona y no en su
 * centro: una ruta que atraviesa el centro deja de leerse como una ruta.
 */
function ellipseRadius(rx, rz, dx, dz) {
	const a = dx / rx;
	const b = dz / rz;
	return 1 / Math.sqrt(a * a + b * b);
}

/** Distancia en el plano XZ entre dos puntos. */
function dist2d(ax, az, bx, bz) {
	return Math.sqrt((ax - bx) * (ax - bx) + (az - bz) * (az - bz));
}


// ------------------------------------------------ PALETAS POR MUNDO
//
// Cada paleta tiene los MISMOS roles (suelo, suelo alterno, estructura,
// estructura oscura, acento, peligro, energia Keshusy y los dos materiales
// base) para que el motor de zonas pueda escribirse una sola vez. Lo que cambia
// entre mundos es el VALOR: la identidad visual entera del mundo.
//
// Forest se incluye aqui aunque su decoracion historica vivia en
// `generate-project.js`: los cinco mundos se construyen con el mismo motor, y
// un mundo con motor propio es un mundo que puede volver a ser un cuadrado.

const PALETTES = {
	Forest: {
		ground: [82, 128, 62],
		groundAlt: [104, 82, 58],
		structure: [122, 126, 132],
		structureDark: [86, 90, 98],
		accent: [168, 246, 255],
		hazard: [122, 214, 96],
		energy: [86, 214, 226],
		floorMaterial: "Grass",
		structureMaterial: "Rock",
		barkDark: [74, 54, 36],
		barkMid: [104, 78, 50],
		leafDeep: [42, 104, 56],
		leafMid: [66, 138, 68],
		leafLight: [116, 184, 82],
		crystal: [86, 214, 226],
		crystalHot: [168, 246, 255],
		ember: [232, 148, 74],
		sand: [214, 196, 142],
		stoneWarm: [148, 136, 116],
		hazardName: "Poison",
	},
	Desert: {
		ground: [206, 172, 112],
		groundAlt: [188, 150, 96],
		structure: [214, 190, 148],
		structureDark: [162, 132, 92],
		accent: [255, 168, 66],
		hazard: [232, 96, 48],
		energy: [255, 206, 120],
		floorMaterial: "Sand",
		structureMaterial: "Sandstone",
		green: [104, 142, 78],
		hazardName: "Scorch",
	},
	Ice: {
		ground: [222, 236, 246],
		groundAlt: [188, 210, 230],
		structure: [198, 224, 240],
		structureDark: [136, 170, 198],
		accent: [122, 214, 245],
		hazard: [86, 176, 232],
		energy: [178, 240, 255],
		floorMaterial: "Snow",
		structureMaterial: "Ice",
		hazardName: "Frost",
	},
	Volcano: {
		ground: [64, 52, 52],
		groundAlt: [82, 60, 56],
		structure: [58, 48, 50],
		structureDark: [34, 28, 30],
		accent: [255, 132, 44],
		hazard: [255, 78, 26],
		energy: [255, 196, 92],
		floorMaterial: "Slate",
		structureMaterial: "Basalt",
		hazardName: "Lava",
	},
	Cyber: {
		ground: [46, 52, 78],
		groundAlt: [38, 44, 68],
		structure: [58, 66, 96],
		structureDark: [30, 34, 54],
		accent: [86, 236, 240],
		hazard: [190, 108, 255],
		energy: [206, 168, 255],
		floorMaterial: "Slate",
		structureMaterial: "Metal",
		hazardName: "Arc",
	},
};

//
// Cada mundo declara su PROPIA topologia. No hay una plantilla comun con otros
// numeros: los cinco tienen zonas distintas, conectadas de distinta manera, con
// recorridos de longitudes distintas y en sitios distintos.
//
// FORMATO (compacto a proposito)
// ------------------------------
//   zonas:  [id, role, x, z, rx, rz, y]
//   rutas:  [zonaA, zonaB, estilo, ancho]
//
// `role` decide que se CONSTRUYE dentro de la zona, no solo como se llama:
//
//   entrance      umbral de entrada, arco y plataforma de spawn
//   exploration   recorrido abierto, hitos y cobertura visual
//   encounter     cobertura SOLIDA + spawns de monstruo + peligro
//   destruction   estructuras DESTRUCTIBLES con bombas
//   intermediate  cobertura densa + monstruos + barricada
//   reward        pedestal de recompensa + spawns de powerup
//   arena         anillo grande, monumento y spawns
//   boss          plataforma de boss y preparacion visual
//   exit          salida y camino de vuelta
//   scenic        pieza de identidad del mundo (canon, lago, maquinas...)
//
// `y` es la COTA del suelo de la zona. Dos zonas con distinta cota obligan a
// que la ruta que las une sea una rampa o una escalera real: por eso los
// recorridos tienen relieve y no son una lamina plana.
//
// LAS DISTANCIAS NO SON DECORATIVAS
// ---------------------------------
// `tools/world-structure-test.js` mide, sobre el arbol GENERADO:
//
//   Spawn -> FirstEncounter -> Destruction -> Intermediate -> Arena -> Boss -> Exit
//
// y falla si un tramo es mas corto que un minimo, si dos tramos se solapan en la
// misma zona o si el mundo cabe entero en un radio pequeno. Por eso las
// coordenadas de abajo estan elegidas para que el recorrido se RECORRA, no para
// que se vea entero desde el spawn.

const LAYOUTS = {
	// ------------------------------------------------------------- FOREST
	// Un bosque que se recorre: se entra por el sur, se sube al claro del
	// este, se baja a las rocas, se cruza el puente sobre el arroyo y se llega
	// al hollow del oeste. El bosque denso esta al NOROESTE, al lado
	// contrario del spawn: no se ve desde la entrada.
	Forest: {
		zones: [
			zone(["Entrance", "entrance", 0, 152, 30, 22]),
			zone(["Trail", "exploration", 0, 92, 28, 26]),
			zone(["Grove", "scenic", -72, 78, 42, 34, 2]),
			zone(["Clearing", "encounter", 66, 74, 32, 28]),
			zone(["Rocks", "destruction", 104, 6, 36, 30, 4]),
			zone(["Bridge", "scenic", 30, -30, 34, 18, 6]),
			zone(["Hollow", "intermediate", -56, 10, 36, 30]),
			zone(["Spring", "reward", -108, -66, 30, 26, 3]),
			zone(["Arena", "arena", 0, -110, 58, 48]),
			zone(["Grooty", "boss", -6, -208, 42, 34]),
			zone(["Exit", "exit", 104, -120, 26, 22]),
		],
		routes: [
			route(["Entrance", "Trail", "path"]),
			route(["Trail", "Grove", "path"]),
			route(["Trail", "Clearing", "path"]),
			route(["Grove", "Hollow", "narrow"]),
			route(["Trail", "Bridge", "path"]),
			route(["Clearing", "Rocks", "path"]),
			route(["Rocks", "Bridge", "bridge"]),
			route(["Bridge", "Hollow", "bridge"]),
			route(["Bridge", "Arena", "catwalk"]),
			route(["Hollow", "Arena", "path"]),
			route(["Hollow", "Spring", "path"]),
			route(["Spring", "Arena", "bridge"]),
			route(["Arena", "Grooty", "canyon"]),
			route(["Grooty", "Exit", "path"]),
			route(["Exit", "Trail", "path"]),
		],
	},

	// -------------------------------------------------------- BOOM DESERT
	// Un desierto que se cruza en diagonal, no una arena con tono ocre.
	//
	// LA GEOGRAFIA, no la paleta, es lo que hace que esto sea un desierto:
	//
	//   Gate      entrada entre dunas, al sur
	//   Dunes     campo de dunas: la primera lectura del sitio
	//   Pillars  Ruinas de columnas al OESTE: el primer encuentro
	//   OpenField llano de arena abierta, cobertura escasa
	//   Canyon    paso excavado al ESTE, con paredes altas
	//   Ruins     planta baja derruida, llena de estructuras DESTRUCTIBLES
	//   Cover     bloque de roca a media sombra, cobertura real
	//   Oasis     agua y palmeras: un respiro antes de la arena
	//   Treasure  cache excavado al este, detras de las ruinas
	//   Arena     explanada de combate
	//   SandBeast fosa de arena al fondo: donde aparece el boss
	//   Exit      portillo de salida al fondo del mapa
	//
	// LAS DISTANCIAS ESTAN CALCULADAS, NO PROBADAS A OJO
	// -------------------------------------------------
	// Ninguna zona se pisa con otra y toda ruta deja un hueco libre de al menos
	// 12 studs. Antes se solapaban cuatro pares (Gate/Dunes, Dunes/OpenField,
	// Oasis/Arena y Arena/SandBeast), y una ruta con hueco NEGATIVO no es un
	// camino: es una pared con un cartel. Se mide con
	// `node tools/tmp-paths.js --layout Desert` y lo verifica
	// `tools/world-structure-test.js`.
	Desert: {
		zones: [
			zone(["Gate", "entrance", 0, 164, 26, 20]),
			zone(["Dunes", "exploration", 0, 100, 42, 30]),
			zone(["Pillars", "encounter", -96, 120, 28, 24]),
			zone(["OpenField", "exploration", -52, 30, 44, 36]),
			zone(["Canyon", "scenic", 98, 46, 30, 34, 2]),
			zone(["Ruins", "destruction", 100, -46, 34, 30, 4]),
			zone(["Cover", "scenic", -100, -34, 32, 28, 1]),
			zone(["Oasis", "intermediate", -26, -92, 30, 24]),
			zone(["Treasure", "reward", 52, -128, 28, 22, 4]),
			zone(["Arena", "arena", -46, -170, 48, 38]),
			zone(["SandBeast", "boss", -58, -254, 38, 30]),
			zone(["Exit", "exit", 78, -222, 24, 20]),
		],
		routes: [
			route(["Gate", "Dunes", "path"]),
			route(["Dunes", "Pillars", "path"]),
			route(["Dunes", "OpenField", "path"]),
			route(["Dunes", "Canyon", "path"]),
			route(["Pillars", "OpenField", "path"]),
			// RUTA A: por el sur, entre el campo abierto y el oasis.
			route(["OpenField", "Oasis", "catwalk"]),
			// RUTA B: por el oeste, entre las rocas. Son dos caminos distintos
			// al mismo sitio, con riesgos distintos: la A es rapida y abierta, la
			// B es estrecha y esta a la sombra de las rocas.
			route(["OpenField", "Cover", "narrow"]),
			route(["Cover", "Oasis", "narrow"]),
			route(["Canyon", "Ruins", "canyon"]),
			route(["Ruins", "Oasis", "bridge"]),
			route(["Oasis", "Treasure", "path"]),
			route(["Treasure", "Arena", "catwalk"]),
			route(["Oasis", "Arena", "path"]),
			route(["Arena", "SandBeast", "canyon"]),
			route(["SandBeast", "Exit", "path"]),
			route(["Exit", "Dunes", "path"]),
		],
	},

	// ------------------------------------------------------- FROZEN TOMY
	// Hielo: el lago se cruza por un paso estrecho al oeste, la cueva del este
	// esconde las crevasas, y la arena queda al sur con la corona del rey al
	// fondo. Los témpanos del nordeste quedan lejos de la entrada.
	Ice: {
		zones: [
			zone(["Gate", "entrance", 0, 152, 26, 20]),
			zone(["SnowPath", "exploration", 0, 100, 42, 32]),
			zone(["Shards", "encounter", 86, 110, 28, 24]),
			zone(["Lake", "scenic", -84, 86, 42, 34, 1]),
			zone(["Narrows", "scenic", 0, 24, 22, 34, 2]),
			zone(["Cave", "scenic", 86, 52, 32, 28, 3]),
			zone(["Crevasse", "destruction", 100, -30, 36, 30, 4]),
			zone(["Cache", "intermediate", -92, 4, 36, 30]),
			zone(["Aurora", "reward", 60, -96, 30, 24, 3]),
			zone(["Arena", "arena", -34, -128, 56, 46]),
			zone(["FrostKing", "boss", -40, -212, 42, 34]),
			zone(["Exit", "exit", 78, -178, 26, 22]),
		],
		routes: [
			route(["Gate", "SnowPath", "path"]),
			route(["SnowPath", "Lake", "bridge"]),
			route(["Lake", "Cache", "narrow"]),
			route(["SnowPath", "Narrows", "narrow"]),
			route(["Narrows", "Cache", "path"]),
			route(["Narrows", "Cave", "tunnel"]),
			route(["Cave", "Shards", "path"]),
			route(["Cave", "Crevasse", "path"]),
			route(["Crevasse", "Aurora", "bridge"]),
			route(["Cache", "Aurora", "catwalk"]),
			route(["Cache", "Arena", "path"]),
			route(["Aurora", "Arena", "path"]),
			route(["Arena", "FrostKing", "canyon"]),
			route(["FrostKing", "Exit", "path"]),
			route(["Exit", "SnowPath", "path"]),
		],
	},

	// ------------------------------------------------------ VOLCANO RAGE
	// Basalto y lava. Se entra por el sur, se sube por el camino de lava, y el
	// mundo se abre en dos: las plataformas al este y las rocas al oeste. El
	// puente central es el atajo y la zona mas expuesta.
	Volcano: {
		zones: [
			zone(["Gate", "entrance", 0, 154, 26, 20]),
			zone(["LavaPath", "exploration", 0, 100, 42, 32]),
			zone(["Caldera", "encounter", -92, 128, 28, 24]),
			zone(["Platforms", "scenic", 88, 72, 32, 28, 4]),
			zone(["Rocks", "scenic", -92, 72, 34, 28, 2]),
			zone(["Bridge", "scenic", -10, 30, 36, 18, 8]),
			zone(["Fissure", "intermediate", 30, -40, 30, 26]),
			zone(["Vents", "destruction", 96, 0, 36, 30, 2]),
			zone(["Forge", "reward", 86, -96, 30, 24, 4]),
			zone(["Foundry", "scenic", -98, 4, 34, 28]),
			zone(["Arena", "arena", -36, -128, 56, 46]),
			zone(["MagmaLord", "boss", -46, -214, 42, 34]),
			zone(["Exit", "exit", 76, -180, 26, 22]),
		],
		routes: [
			route(["Gate", "LavaPath", "path"]),
			route(["LavaPath", "Platforms", "catwalk"]),
			route(["LavaPath", "Rocks", "path"]),
			route(["LavaPath", "Caldera", "path"]),
			route(["Caldera", "Rocks", "narrow"]),
			route(["Platforms", "Vents", "path"]),
			route(["Vents", "Forge", "bridge"]),
			route(["Rocks", "Foundry", "narrow"]),
			route(["LavaPath", "Bridge", "bridge"]),
			route(["Bridge", "Fissure", "catwalk"]),
			route(["Bridge", "Foundry", "bridge"]),
			route(["Fissure", "Forge", "path"]),
			route(["Fissure", "Arena", "path"]),
			route(["Foundry", "Arena", "path"]),
			route(["Forge", "Arena", "catwalk"]),
			route(["Arena", "MagmaLord", "canyon"]),
			route(["MagmaLord", "Exit", "path"]),
			route(["Exit", "LavaPath", "path"]),
		],
	},

	// ------------------------------------------------------ CYBER KESHUSY
	// La geometria mas vertical: corredores, plataformas y salas de maquinas.
	// El camino de vuelta al lobby cruza el ala este, que es la zona de
	// energia, y por eso la salida no es el punto de partida.
	Cyber: {
		zones: [
			zone(["Gate", "entrance", 0, 156, 26, 20]),
			zone(["Corridor", "exploration", 0, 104, 46, 28]),
			zone(["ServerHall", "encounter", -92, 86, 36, 28, 2]),
			zone(["Platforms", "scenic", 90, 80, 32, 26, 6]),
			zone(["Conduit", "scenic", 10, 32, 28, 30, 3]),
			zone(["BlastDoors", "destruction", -92, 16, 30, 26, 1]),
			zone(["Energy", "scenic", 92, 20, 32, 28, 4]),
			zone(["Core", "intermediate", -40, -40, 34, 28]),
			zone(["Vault", "reward", 76, -70, 30, 24, 3]),
			zone(["Arena", "arena", -36, -128, 56, 46]),
			zone(["CyberCore", "boss", -40, -210, 42, 34]),
			zone(["Exit", "exit", 80, -176, 26, 22]),
		],
		routes: [
			route(["Gate", "Corridor", "tunnel"]),
			route(["Corridor", "ServerHall", "path"]),
			route(["Corridor", "Platforms", "catwalk"]),
			route(["Corridor", "Conduit", "tunnel"]),
			route(["Conduit", "Core", "narrow"]),
			route(["ServerHall", "BlastDoors", "path"]),
			route(["BlastDoors", "Core", "path"]),
			route(["Platforms", "Energy", "bridge"]),
			route(["Energy", "Vault", "narrow"]),
			route(["Energy", "Arena", "catwalk"]),
			route(["Vault", "Arena", "path"]),
			route(["Core", "Arena", "path"]),
			route(["Arena", "CyberCore", "canyon"]),
			route(["CyberCore", "Exit", "path"]),
			route(["Exit", "Corridor", "path"]),
		],
	},
};

// ---------------------------------------------------------- MOTOR DE ZONAS
//
// Todo lo que viene aqui es COMUN a los cinco mundos. Lo unico que cambia entre
// ellos son los datos de `LAYOUTS` y la decoracion de `SCENERY`.
//
// La pieza central es `zoneSlab`: una zona NO se dibuja como un rectangulo, sino
// como un ensamblaje de losas de sizes y giros distintos alrededor de un
// nucleo. Dos razones, y las dos son de juego:
//
//   1. Visualmente, un rectangulo con decoracion alrededor se lee como un
//      escenario. Un contorno irregular se lee como un lugar.
//   2. Geometricamente, un rectangulo tiene cuatro esquinas donde el jugador
//      puede quedarse encerrado. Un contorno irregular no las tiene.

/**
 * Losa de suelo de una zona: el nucleo mas un anillo de piezas inclinadas.
 *
 * @param {object} api helpers del generador
 * @param {object} z zona de `LAYOUTS`
 * @param {object} P paleta
 * @param {number} seedBase
 * @param {string} name prefijo de nombres
 * @returns {Array} piezas de suelo (colisionables)
 */
function zoneSlab(api, z, P, seedBase, name) {
	const { part } = api;
	const out = [];
	const n = Math.max(3, Math.round(z.rx / 13));

	// Nucleo: la losa que el jugador pisa. Estabiliza el centro y garantiza
	// que nunca hay un agujero bajo el monumento.
	out.push(part(name + "_Core", {
		position: [z.x, z.y - 1, z.z],
		size: [z.rx * 1.05, 2, z.rz * 1.05],
		material: P.floorMaterial,
		color: P.ground,
		orientation: [0, Math.round(vary(seedBase, 1, -8, 8)), 0],
	}));

	for (let i = 0; i < n; i++) {
		const a = (i / n) * Math.PI * 2 + vary(seedBase, i + 2, -0.3, 0.3);
		// Radio variable: es lo que rompe la circunferencia perfecta.
		const r = 0.62 + hash01(seedBase, i + 3) * 0.36;
		const w = z.rx * vary(seedBase, i + 4, 0.55, 0.9);
		const d = z.rz * vary(seedBase, i + 5, 0.55, 0.9);
		// Losas elevadas alternas: dan sombra propia y rompen la lamina plana.
		const lift = hash01(seedBase, i + 6) > 0.7 ? 1 : 0;

		out.push(part(name + "_Slab_" + i, {
			position: [z.x + Math.cos(a) * z.rx * r, z.y + lift - 1, z.z + Math.sin(a) * z.rz * r],
			size: [w, 2 + lift, d],
			material: P.floorMaterial,
			color: hash01(seedBase, i + 7) > 0.55 ? P.groundAlt : P.ground,
			orientation: [0, Math.round((a * 180) / Math.PI), 0],
		}));
	}

	return out;
}

/**
 * Borde de una zona: pared SOLIDA con huecos donde entran las rutas.
 *
 * Los huecos no son decorativos. Sin ellos, cada zona seria una caja cerrada y
 * el mundo serian once salas sin puerta; con ellos, el borde marca DIRECCION:
 * el jugador ve por que lado se sale.
 *
 * @param {object} api
 * @param {object} z zona
 * @param {object} P paleta
 * @param {number} seedBase
 * @param {string} name
 * @param {Array<{angle:number, half:number}>} openings huecos, en radianes
 */
function zoneRim(api, z, P, seedBase, name, openings) {
	const { part, decor } = api;
	const out = [];
	const segs = 26;

	// EL ANGULO, EN POLAR Y NO EN PARAMETRO DE ELIPSE
	// -------------------------------------------------
	// Antes cada segmento se colocaba en el punto (cos a * rx, sin a * rz) y se
	// comparaba `a` contra el angulo de la ruta. Esos dos angulos NO son el
	// mismo: en una elipse, el angulo polar de un punto depende de los dos
	// radios. En una zona de 56 x 38 la diferencia llega a 20 grados, que es
	// justo el ancho del hueco: el muro se comia la entrada de la ruta y el
	// jugador se encontraba con un muro donde deberia haber un paso.
	//
	// Ahora los dos lados usan el angulo POLAR. Para cada angulo `a` se calcula
	// el radio de la elipse en esa direccion (misma formula que `ellipseRadius`),
	// se coloca el muro ahi, y el hueco se comprueba sobre ese mismo angulo.
	for (let i = 0; i < segs; i++) {
		const a = (i / segs) * Math.PI * 2;

		let blocked = false;
		for (const o of openings) {
			const d = Math.abs(((a - o.angle + Math.PI * 3) % (Math.PI * 2)) - Math.PI);
			if (d < o.half) blocked = true;
		}
		if (blocked) continue;

		const rr = ellipseRadius(z.rx, z.rz, Math.cos(a), Math.sin(a));
		const x = z.x + Math.cos(a) * rr;
		const zz = z.z + Math.sin(a) * rr;
		const h = vary(seedBase, i + 40, 9, 17);
		// El ancho del segmento crece con el radio: en el lado largo de la zona
		// el muro tiene que ser mas largo o quedan costuras.
		const segW = ((Math.PI * 2) / segs) * rr * 1.15;

		// Altura variable: un muro de altura constante se lee como un molde.
		out.push(part(name + "_Rim_" + i, {
			position: [x, z.y + h / 2, zz],
			size: [segW, h, 3],
			material: P.structureMaterial,
			color: hash01(seedBase, i + 42) > 0.5 ? P.structure : P.structureDark,
			orientation: [0, Math.round((-(a * 180) / Math.PI) - 90), 0],
		}));

		// Remate: lo que hace que el muro sea de roca y no una valla.
		out.push(decor(name + "_RimCap_" + i, {
			position: [x, z.y + h + 0.5, zz],
			size: [segW * 0.85, 1.4, 4.4],
			material: P.structureMaterial,
			color: P.structureDark,
			orientation: [0, Math.round((-(a * 180) / Math.PI) - 90), 0],
		}));
	}

	return out;
}

/**
 * Ruta entre dos zonas: un recorrido REAL de losas, no una linea decorativa.
 *
 * Se recorta por los RADIOS de las zonas (no por sus centros) para que la ruta
 * empiece en el BORDE de cada zona: una ruta que atraviesa el centro de las dos
 * zonas se lee como un tubo, no como un camino. Ademas interpola la cota, de
 * modo que una ruta entre una zona a y=0 y otra a y=8 es una rampa escalonada
 * de verdad y no un plano inclinado invisible.
 *
 * @param {object} api
 * @param {object} r ruta de `LAYOUTS`
 * @param {object} a zona origen (con x,z ya desplazados al mundo)
 * @param {object} b zona destino
 * @param {object} P paleta
 * @param {number} seedBase
 * @param {number} idx indice de la ruta, para nombres unicos
 * @returns {{parts: Array, ax:number, az:number, bx:number, bz:number, yaw:number}}
 */
function routePath(api, r, a, b, P, seedBase, idx) {
	const { part, decor } = api;
	const out = [];
	const name = "Route_" + idx + "_" + r.from + "_" + r.to;

	const dx = b.x - a.x;
	const dz = b.z - a.z;
	const len = Math.sqrt(dx * dx + dz * dz);
	const ux = dx / len;
	const uz = dz / len;

	// Puntos de entrada: en el borde de cada zona, no en su centro.
	const ra = ellipseRadius(a.rx, a.rz, ux, uz) * 0.72;
	const rb = ellipseRadius(b.rx, b.rz, -ux, -uz) * 0.72;
	const ax = a.x + ux * ra;
	const az = a.z + uz * ra;
	const bx = b.x - ux * rb;
	const bz = b.z - uz * rb;

	const runLen = Math.sqrt((bx - ax) * (bx - ax) + (bz - az) * (bz - az));
	const steps = Math.max(3, Math.round(runLen / 13));
	const segLen = runLen / steps;
	const yaw = yawTo(ux, uz);
	const w = r.width;
	const steep = Math.abs(b.y - a.y) > 1.2;

	// El MATERIAL de la ruta depende del estilo, y el color va aparte. Antes
	// estas dos lineas devolvian la misma cosa: `P.groundAlt` usado como
	// material, que es un COLOR. Rojo aceptaba el arbol entero y fallaba al
	// compilar con "Invalid value for property Part.Material", un error que no
	// dice que el valor que tiene delante es un color y no un enum.
	const deckMat = r.style === "bridge" ? "WoodPlanks"
		: r.style === "catwalk" ? "Metal"
		: r.style === "tunnel" ? P.floorMaterial
		: "Ground";

	for (let i = 0; i <= steps; i++) {
		const t = i / steps;
		const x = ax + (bx - ax) * t;
		const z = az + (bz - az) * t;
		const y = a.y + (b.y - a.y) * t;

		// Escalon real cuando la ruta cambia de cota. Sin esto, una ruta con 8
		// studs de desnivel seria una rampa invisible y el jugador la
		// atravesaria por debajo del suelo.
		const step = steep ? Math.round(y) : y;
		const thick = steep ? 3 : 2;

		out.push(part(name + "_Deck_" + i, {
			position: [x, step - thick / 2, z],
			size: [segLen + 1.5, thick, w],
			material: deckMat,
			color: hash01(seedBase, i + idx * 30) > 0.6 ? P.ground : P.groundAlt,
			orientation: [0, yaw, 0],
		}));

		// Barandilla: solo donde tiene sentido. Un sendero de tierra no lleva
		// barandilla; un puente y una pasarela industrial, si.
		if (r.style === "bridge" || r.style === "catwalk") {
			for (const side of [-1, 1]) {
				out.push(part(name + "_Rail_" + side + "_" + i, {
					position: [x + uz * side * (w / 2), step + 2.4, z - ux * side * (w / 2)],
					size: [segLen + 1.5, 1.2, 0.8],
					material: deckMat,
					color: P.structureDark,
					orientation: [0, yaw, 0],
				}));
			}
			// Pilares: el puente tiene que sostenerse por algo.
			if (i % 2 === 0) {
				out.push(part(name + "_Pillar_" + i, {
					position: [x, step / 2 - 2, z],
					size: [2.4, Math.max(4, step + 4), 2.4],
					material: P.structureMaterial,
					color: P.structureDark,
					orientation: [0, yaw, 0],
				}));
			}
		}

		// Muro de canyon: colisiona, cierra el paso y da techo visual.
		if (r.style === "canyon") {
			for (const side of [-1, 1]) {
				const hh = vary(seedBase, i + 70 + side, 16, 30);
				out.push(part(name + "_Wall_" + side + "_" + i, {
					position: [x + uz * side * (w / 2 + 5), step + hh / 2 - 1, z - ux * side * (w / 2 + 5)],
					size: [segLen + 1.5, hh, 9],
					material: P.structureMaterial,
					color: side < 0 ? P.structure : P.structureDark,
					orientation: [0, yaw, 0],
				}));
			}
		}

		// Tunel: techo y laterales. Cierra la vista al otro lado.
		if (r.style === "tunnel") {
			out.push(part(name + "_Roof_" + i, {
				position: [x, step + 9, z],
				size: [segLen + 1.5, 2, w + 8],
				material: P.structureMaterial,
				color: P.structureDark,
				orientation: [0, yaw, 0],
			}));
			for (const side of [-1, 1]) {
				out.push(part(name + "_Side_" + side + "_" + i, {
					position: [x + uz * side * (w / 2 + 3), step + 4, z - ux * side * (w / 2 + 3)],
					size: [segLen + 1.5, 10, 4],
					material: P.structureMaterial,
					color: P.structure,
					orientation: [0, yaw, 0],
				}));
			}
		}
	}

	// Sendero de tierra: losas sueltas a los lados, para que no lea como una
	// cinta de asfalto.
	if (r.style === "path") {
		for (let i = 0; i < 8; i++) {
			const t = (i + 0.5) / 8;
			const side = i % 2 === 0 ? -1 : 1;
			const off = w / 2 + vary(seedBase, i + 90, 3, 9);
			out.push(decor(name + "_Kerb_" + i, {
				position: [
					ax + (bx - ax) * t + uz * side * off,
					a.y + (b.y - a.y) * t + 0.3,
					az + (bz - az) * t - ux * side * off,
				],
				size: [vary(seedBase, i + 91, 4, 8), 0.8, 3],
				material: P.floorMaterial,
				color: P.structureDark,
				orientation: [0, yaw + Math.round(vary(seedBase, i + 92, -25, 25)), 0],
			}));
		}
	}

	return { parts: out, ax: ax, az: az, bx: bx, bz: bz, yaw: yaw, width: w };
}
/** Expande una tupla de zona en objeto, con los valores por defecto. */
function zone(t) {
	return { id: t[0], role: t[1], x: t[2], z: t[3], rx: t[4], rz: t[5], y: t[6] || 0 };
}

/** Expande una tupla de ruta en objeto. */
function route(t) {
	return { from: t[0], to: t[1], style: t[2], width: t[3] || 14 };
}
// ---------------------------------------------------- CONTENIDO POR ROL
//
// Un `role` no es una etiqueta: decide que hay DENTRO de la zona. Sin esta
// seccion, las once zonas serian once plateformes vacias con un nombre
// distinto, que es exactamente el "Folder Zone1, Folder Zone2" que la
// especificacion prohibe.
//
// La REGLA de diseno que se respeta en todos los casos:
//
//   - la COBERTURA (solida) se pone donde el jugador tiene que decidir;
//   - lo DESTRUCTIBLE se pone donde la bomba tiene sentido;
//   - el PELIGRO se pone donde no hay salida facil.
//
// Nada de eso se coloca en el camino de una ruta: un obstaculo encima del
// recorrido no es una decision, es una pared injusta.

/**
 * Estructura DESTRUCTIBLE dentro de una zona.
 *
 * Estas piezas llevan el prefijo `Block_`, que es el CONTRATO con
 * `DestructionService.IsDestructibleBlock`. Sus hijos decorativos NUNCA llevan
 * ese prefijo, o `CollectBlocks` los contaria como bloques y el recuento por
 * mundo dejaria de cuadrar.
 *
 * @param {object} api
 * @param {object} z zona
 * @param {object} P paleta
 * @param {object} blockState estado compartido del contador de bloques
 * @param {string} defId id del mundo
 */
function destructibleCluster(api, z, P, blockState, defId) {
	const { part, decor } = api;
	const out = [];
	const SHAPES = [
		{ size: [6, 11, 6], material: P.structureMaterial, colors: [P.structureDark, P.structure, P.structureDark] },
		{ size: [12, 4.5, 10], material: P.floorMaterial, colors: [P.ground, P.groundAlt, P.ground] },
		{ size: [8, 7, 9], material: P.structureMaterial, colors: [P.structure, P.structureDark, P.structure] },
	];

	function make(x, y, zz, scale) {
		const index = blockState.count++;
		const s = SHAPES[index % SHAPES.length];
		const size = [s.size[0] * scale, s.size[1] * scale, s.size[2] * scale];

		const node = part("Block_" + defId + "_" + index, {
			position: [x, y, zz],
			size: size,
			material: s.material,
			color: s.colors[index % s.colors.length],
			orientation: [
				Math.round(vary(index, 3, -6, 6)),
				Math.round(hash01(index, 7) * 360),
				Math.round(vary(index, 4, -6, 6)),
			],
		});

		// Veta luminosa encima: identifica el material dimensional sin anadir
		// otra pieza destructible.
		node.node["Deco_" + defId + "_Vein_" + index] = decor("Deco_" + defId + "_Vein_" + index, {
			position: [x, y + size[1] / 2 + 0.1, zz],
			size: [size[0] * 0.6, 0.3, size[2] * 0.6],
			color: P.energy,
			transparency: 0.3,
		}).node;

		out.push(node);
		return size;
	}

	// Estructura en anillo: se lee como un recinto derruido y deja un hueco
	// interior por el que se entra y se sale. Un anillo de bloques cerrado
	// encerraria la zona; un anillo con huecos es una sala con dos puertas.
	const ring = Math.max(6, Math.round((z.rx + z.rz) / 9));
	for (let i = 0; i < ring; i++) {
		const a = (i / ring) * Math.PI * 2;
		// Se abre un sector: por ahi se entra.
		if (a > 1.1 && a < 2.0) continue;
		const r = 0.78 + hash01(i, 11) * 0.16;
		const s = SHAPES[blockState.count % SHAPES.length];
		make(z.x + Math.cos(a) * z.rx * r, z.y + s.size[1] / 2, z.z + Math.sin(a) * z.rz * r, 1);
	}

	// Pilares centrales: se rompen y dejan el monumento sin soporte. Es la
	// lectura de "destruccion" sin necesidad de un tutorial.
	const pillars = 3;
	for (let i = 0; i < pillars; i++) {
		const a = (i / pillars) * Math.PI * 2 + 0.4;
		const s = SHAPES[blockState.count % SHAPES.length];
		make(z.x + Math.cos(a) * z.rx * 0.3, z.y + s.size[1] / 2, z.z + Math.sin(a) * z.rz * 0.3, 0.8);
	}

	// Pila de dos alturas: verticalidad y mas superficie donde pensar la bomba.
	const s = SHAPES[blockState.count % SHAPES.length];
	const ax = z.x + z.rx * 0.42;
	const az = z.z - z.rz * 0.42;
	const base = make(ax, z.y + s.size[1] / 2, az, 1);
	make(ax, z.y + s.size[1] + base[1] / 2, az, 0.7);

	return out;
}

/**
 * COBERTURA solida de una zona de combate.
 *
 * Es la pieza que convierte "un sitio con monstruos" en "un sitio donde decidir
 * donde poner la bomba". Colisiona, tiene altura VARIABLE y esta repartida en
 * pinza: nunca en el centro (donde el jugador llega primero) ni pegada al
 * borde (donde no serviria de nada).
 *
 * @param {object} api
 * @param {object} z zona
 * @param {object} P paleta
 * @param {number} seedBase
 * @param {number} count numero de piezas
 */
function coverField(api, z, P, seedBase, count, tag) {
	const { part, decor } = api;
	const out = [];

	for (let i = 0; i < count; i++) {
		const a = (i / count) * Math.PI * 2 + vary(seedBase, i + 20, -0.4, 0.4);
		const r = 0.42 + hash01(seedBase, i + 21) * 0.34;
		const x = z.x + Math.cos(a) * z.rx * r;
		const zz = z.z + Math.sin(a) * z.rz * r;

		// Tres siluetas distintas. Una cobertura de cajas iguales se lee como
		// un almacen, no como un lugar donde pelear.
		const kind = i % 3;
		if (kind === 0) {
			const h = vary(seedBase, i + 22, 7, 11);
			out.push(part("Cover_Pillar_" + tag + i, {
				position: [x, z.y + h / 2, zz],
				size: [4.4, h, 4.4],
				shape: "Cylinder",
				material: P.structureMaterial,
				color: P.structure,
				orientation: [0, Math.round(hash01(seedBase, i + 23) * 360), 0],
			}));
			out.push(decor("Cover_PillarCap_" + tag + i, {
				position: [x, z.y + h + 0.5, zz],
				size: [6, 1.2, 6],
				shape: "Cylinder",
				material: P.structureMaterial,
				color: P.structureDark,
			}));
		} else if (kind === 1) {
			const h = vary(seedBase, i + 24, 4.5, 6.5);
			out.push(part("Cover_Slab_" + tag + i, {
				position: [x, z.y + h / 2, zz],
				size: [vary(seedBase, i + 25, 9, 14), h, 3.4],
				material: P.structureMaterial,
				color: P.structureDark,
				orientation: [0, Math.round((a * 180) / Math.PI + 90), Math.round(vary(seedBase, i + 26, -14, 14))],
			}));
		} else {
			const h = vary(seedBase, i + 27, 8, 14);
			out.push(part("Cover_Monolith_" + tag + i, {
				position: [x, z.y + h / 2, zz],
				size: [5.2, h, 5.2],
				material: P.structureMaterial,
				color: P.structure,
				orientation: [Math.round(vary(seedBase, i + 28, -10, 10)), Math.round(hash01(seedBase, i + 29) * 360), Math.round(vary(seedBase, i + 30, -10, 10))],
			}));
		}
	}

	return out;
}

/**
 * Peligro de una zona: charco o lazo, plano y SIN colision.
 *
 * No colisiona a proposito: el dano lo aplica el sistema de combate leyendo el
 * nombre, no una pieza invisible que empuja al jugador. Una pieza solida de
 * peligro seria un obstaculo invisible, que es peor que no tener peligro.
 */
function hazardField(api, z, P, seedBase, count, tagBase) {
	const { decor } = api;
	const out = [];

	for (let i = 0; i < count; i++) {
		const a = (i / count) * Math.PI * 2 + 0.7;
		const r = 0.5 + hash01(seedBase, i + 50) * 0.3;
		const size = vary(seedBase, i + 51, 10, 18);
		const x = z.x + Math.cos(a) * z.rx * r;
		const zz = z.z + Math.sin(a) * z.rz * r;

		out.push(decor("Hazard_" + P.hazardName + "_" + tagBase + i, {
			position: [x, z.y + 0.16, zz],
			size: [size, 0.3, size],
			shape: "Cylinder",
			material: P.floorMaterial,
			color: P.hazard,
			transparency: 0.35,
		}));

		// Burbujas: un plano translucido sin nada dentro se lee como pintura
		// pegada al suelo.
		for (let b = 0; b < 3; b++) {
			out.push(decor("Hazard_" + P.hazardName + "_" + tagBase + i + "_Bubble_" + b, {
				position: [
					x + vary(seedBase + i, 60 + b, -size * 0.3, size * 0.3),
					z.y + 0.5,
					zz + vary(seedBase + i, 70 + b, -size * 0.3, size * 0.3),
				],
				size: [1.3, 1.3, 1.3],
				shape: "Ball",
				material: "Neon",
				color: P.accent,
				transparency: 0.45,
			}));
		}
	}

	return out;
}

/**
 * Nombre de un spawn de monstruo, con indice de dos digitos.
 *
 * El padding NO es cosmetico. `MatchService.CollectMonsterSpawnPoints` ordena
 * los puntos por NOMBRE y `BuildMonsterSpawns` se come los primeros cuatro. Con
 * indices de un digito el orden alfabetico seria 0,1,10,11,2,3... y el primer
 * encuentro caeria en la zona equivocada. Con dos digitos, el orden alfabetico
 * coincide con el de generacion, que es el orden del recorrido.
 */
function monsterSpawnName(defId, index) {
	const n = String(index);
	return "MonsterSpawn_" + defId + "_" + (n.length < 2 ? "0" + n : n);
}

/**
 * MONTAJE DE UN MUNDO.
 *
 * @param {object} api helpers del generador ({part, decor, marker, folder})
 * @param {object} def {id, cx, cz, seedBase}
 * @returns {{name:string, node:object}} carpeta del mundo
 */
function buildWorld(api, def) {
	const { part, decor, marker, folder } = api;
	const P = PALETTES[def.id];
	const layout = LAYOUTS[def.id];
	const cx = def.cx;
	const cz = def.cz;
	const seedBase = def.seedBase;

	// Desplaza las zonas al mundo real. El layout se escribe en coordenadas
	// locales para que se pueda leer de un vistazo; la generacion necesita
	// absolutas.
	const zones = layout.zones.map(function (z) {
		return {
			id: z.id, role: z.role,
			x: cx + z.x, z: cz + z.z,
			lx: z.x, lz: z.z,
			rx: z.rx, rz: z.rz, y: z.y,
		};
	});
	const byId = {};
	for (const z of zones) byId[z.id] = z;

	// Huecos del borde: se calculan ANTES de construir, porque el borde de una
	// zona depende de las rutas que entran en ella. Sin esta cuenta previa cada
	// zona saldria con un muro cerrado y las rutas penetrasen la pared.
	const openings = {};
	for (const z of zones) openings[z.id] = [];

	const routeInfo = [];
	layout.routes.forEach(function (r, idx) {
		const a = byId[r.from];
		const b = byId[r.to];
		if (!a || !b) throw new Error(def.id + ": ruta hacia una zona inexistente: " + r.from + " -> " + r.to);

		const built = routePath(api, r, a, b, P, seedBase + idx * 7, idx);
		routeInfo.push({ def: r, built: built, from: a, to: b });

		// Angulo del hueco en el borde de cada zona, con margen proporcional al
		// ancho de la ruta: una ruta ancha abre un hueco ancho.
		const gap = Math.atan2(built.width * 0.75, dist2d(a.x, a.z, b.x, b.z)) + 0.22;
		openings[a.id].push({ angle: Math.atan2(b.z - a.z, b.x - a.x), half: gap });
		openings[b.id].push({ angle: Math.atan2(a.z - b.z, a.x - b.x), half: gap });
	});

	// Acumuladores de contenido. Se declaran ANTES del bucle de zonas porque
	// `buildWorld` reparte las piezas en carpetas por CONTRATO (`Hazards/`,
	// `Decoration/`, ...) y no por papel: los servicios las buscan por nombre.
	const zoneFolders = [];
	const blocks = [];
	const centralBlocks = [];
	const terrainParts = [];
	const decoParts = [];
	const borderParts = [];
	const keshusyParts = [];
	const hazardParts = [];
	const monsterSpawnParts = [];
	const powerupParts = [];
	const blockState = { count: 0 };
	let monsterIndex = 0;

	// Piezas de CONTRATO que tienen que vivir en la RAIZ del mundo.
	//
	// No es una preferencia de orden: `PortalService`, `RoundService` y las
	// herramientas de QA las localizan con `world:FindFirstChild("BossSpawn_" ..)`.
	// Si la plataforma de boss acaba dentro de `Zones/Zone_<Id>_Boss/`, el nombre
	// ya no se resuelve y el mundo se queda sin punto de boss. Por eso se
	// acumulan aparte y se montan en la raiz, igual que `ArenaFloor`.
	const bossParts = [];
	const exitParts = [];

	// ---------------------------------------------------------- POR ZONA
	for (const z of zones) {
		const nm = "Zone_" + def.id + "_" + z.id;
		const kids = [];

		// Suelo y borde. Siempre: una zona sin suelo no es una zona.
		for (const p of zoneSlab(api, z, P, seedBase + z.lx * 3 + z.lz, nm)) kids.push(p);
		for (const p of zoneRim(api, z, P, seedBase + z.lx * 5 + z.lz, nm, openings[z.id])) kids.push(p);

		// Marcador de centro. Lo leen `VisualService` y los tests para medir
		// distancias REALES, no estimadas.
		kids.push(marker(nm + "_Center", [z.x, z.y + 0.2, z.z], { color: P.accent, size: [10, 0.2, 10] }));

		// Contenido segun el papel de la zona.
		if (z.role === "encounter" || z.role === "intermediate") {
			// El indice va en el NOMBRE porque las piezas de todas las zonas
			// comparten la carpeta `Hazards/` y del cover se hace lo mismo en la
			// carpeta de la zona. Sin el sufijo, dos zonas de combate producirian
			// `Hazard_Poison_0` dos veces y `asChildren` abortaria el build:
			// una homonima se sobrescribe en silencio y la geometria desaparece.
			const tag = z.id + "_";
			for (const p of coverField(api, z, P, seedBase + z.lx, z.role === "intermediate" ? 7 : 5, tag)) kids.push(p);
			for (const p of hazardField(api, z, P, seedBase + z.lz, z.role === "intermediate" ? 2 : 1, tag)) {
				hazardParts.push(p);
			}
		} else if (z.role === "destruction") {
			for (const p of destructibleCluster(api, z, P, blockState, def.id)) blocks.push(p);
		} else if (z.role === "reward") {
			kids.push(part("Reward_Pedestal_" + def.id, {
				position: [z.x, z.y + 1.5, z.z],
				size: [10, 3, 10], shape: "Cylinder",
				material: P.structureMaterial, color: P.structure,
			}));
			kids.push(decor("Reward_Crown_" + def.id, {
				position: [z.x, z.y + 4.2, z.z],
				size: [13, 0.6, 13], shape: "Cylinder",
				material: "Neon", color: P.energy, transparency: 0.3,
			}));
			keshusyParts.push(decor("Reward_Orb_" + def.id, {
				position: [z.x, z.y + 6.4, z.z],
				size: [4, 4, 4], shape: "Ball",
				material: "Neon", color: P.energy, transparency: 0.15,
			}));
			for (let i = 0; i < 4; i++) {
				const a = (i / 4) * Math.PI * 2;
				powerupParts.push(marker("PowerupSpawn_" + def.id + "_" + i,
					[z.x + Math.cos(a) * 13, z.y + 1.4, z.z + Math.sin(a) * 13],
					{ color: P.energy, size: [2.4, 0.2, 2.4] }));
			}
		} else if (z.role === "boss") {
			bossParts.push(part("BossSpawn_" + def.id, {
				position: [z.x, z.y + 0.3, z.z],
				size: [30, 0.6, 30], shape: "Cylinder",
				material: P.structureMaterial, color: P.structureDark,
			}));
			// Dos totems y una corona: la zona esta VISUALMENTE preparada para
			// un boss. No se genera ningun boss aqui; ese trabajo viene
			// despues, y su punto de spawn ya existe y es correcto.
			for (const side of [-1, 1]) {
				bossParts.push(decor("Boss_Totem_" + def.id + (side < 0 ? "_A" : "_B"), {
					position: [z.x + side * 11, z.y + 7, z.z],
					size: [3, 14, 3], shape: "Cylinder",
					material: P.structureMaterial, color: P.hazard,
				}));
			}
			bossParts.push(decor("Boss_Crown_" + def.id, {
				position: [z.x, z.y + 15, z.z],
				size: [13, 1.4, 13], shape: "Cylinder",
				material: "Neon", color: P.accent, transparency: 0.2,
			}));
			keshusyParts.push(decor("Boss_Ground_" + def.id, {
				position: [z.x, z.y + 0.66, z.z],
				size: [21, 0.12, 21], shape: "Cylinder",
				material: "Neon", color: P.hazard, transparency: 0.45,
			}));
		} else if (z.role === "exit") {
			exitParts.push(part("Exit_" + def.id, {
				position: [z.x, z.y + 0.3, z.z],
				size: [16, 0.6, 16], shape: "Cylinder",
				material: P.structureMaterial, color: P.accent,
			}));
			for (const side of [-1, 1]) {
				exitParts.push(decor("Exit_Post_" + def.id + (side < 0 ? "_L" : "_R"), {
					position: [z.x + side * 7, z.y + 4, z.z],
					size: [2.2, 8, 2.2],
					material: P.structureMaterial, color: P.structureDark,
				}));
			}
			exitParts.push(decor("Exit_Lintel_" + def.id, {
				position: [z.x, z.y + 8.4, z.z],
				size: [18, 1.6, 2.6],
				material: P.structureMaterial, color: P.structure,
			}));
			exitParts.push(decor("Exit_Sign_" + def.id, {
				position: [z.x, z.y + 10.8, z.z],
				size: [4.4, 4.4, 0.4], shape: "Ball",
				material: "Neon", color: P.energy, transparency: 0.15,
			}));
		} else if (z.role === "arena") {
			// Monumento central: la pieza que da verticalidad al anillo.
			const STEP = 9.25;
			for (let gx = -1; gx <= 1; gx++) {
				for (let gy = 0; gy <= 1; gy++) {
					for (let gz = -1; gz <= 1; gz++) {
						if (Math.abs(gx) + Math.abs(gy) + Math.abs(gz) === 0) continue;
						if (Math.abs(gx) + Math.abs(gz) < 2 && gy === 1) continue;
						const broken = gy === 1 && Math.abs(gx) === 1 && Math.abs(gz) === 1;
						centralBlocks.push(part("Block_" + def.id + "_cs" + centralBlocks.length, {
							position: [z.x + gx * STEP, z.y + (broken ? 3 : 5.5), z.z + gz * STEP],
							size: [8, broken ? 6 : 11, 8],
							material: P.structureMaterial,
							color: broken ? P.structureDark : P.structure,
							orientation: [0, Math.round(hash01(centralBlocks.length, 12) * 360), 0],
						}));
					}
				}
			}
			keshusyParts.push(decor("Arena_Core_" + def.id, {
				position: [z.x, z.y + 12, z.z],
				size: [7, 7, 7], shape: "Ball",
				material: "Neon", color: P.energy, transparency: 0.15,
			}));
			for (let i = 0; i < 3; i++) {
				keshusyParts.push(decor("Arena_Ring_" + def.id + "_" + i, {
					position: [z.x, z.y + 8 + i * 3.4, z.z],
					size: [30 - i * 6, 0.35, 30 - i * 6], shape: "Cylinder",
					material: "Neon", color: i === 1 ? P.accent : P.energy, transparency: 0.55,
				}));
			}
		}

		// Spawns de monstruo en las zonas donde HAY combate. Se reparten por el
		// mundo, no en un anillo: el jugador se los encuentra al recorrer, y por
		// eso la geometria nueva importa de verdad para el juego.
		if (z.role === "encounter" || z.role === "intermediate" || z.role === "arena") {
			for (let i = 0; i < 2; i++) {
				const a = (i / 2) * Math.PI * 2 + 1.1;
				monsterSpawnParts.push(marker(monsterSpawnName(def.id, monsterIndex++),
					[z.x + Math.cos(a) * z.rx * 0.55, z.y + 1.6, z.z + Math.sin(a) * z.rz * 0.55],
					{ color: P.hazard, size: [3, 0.2, 3] }));
			}
		}

		// Decoracion propia del mundo, sembrada DENTRO de la zona.
		const sc = SCENERY[def.id];
		if (sc) {
			sc({ part: part, decor: decor, marker: marker }, z, P, seedBase + z.lx * 11 + z.lz * 13, {
				deco: decoParts, border: borderParts, keshusy: keshusyParts, terrain: terrainParts,
			});
		}

		zoneFolders.push(folder(nm, kids));
	}

	// ---------------------------------------------------------- POR RUTA
	const routeFolders = [];
	routeInfo.forEach(function (info, idx) {
		const rnm = "Route_" + idx + "_" + info.def.from + "_" + info.def.to;
		const kids = info.built.parts.slice();
		// Flecha en la union: senal de "por aqui se sigue el recorrido".
		kids.push(decor(rnm + "_Arrow", {
			position: [
				(info.built.ax + info.built.bx) / 2,
				(info.from.y + info.to.y) / 2 + 1.4,
				(info.built.az + info.built.bz) / 2,
			],
			size: [4, 0.4, 4], shape: "Cylinder",
			material: "Neon", color: P.energy, transparency: 0.35,
			orientation: [0, info.built.yaw, 0],
		}));
		routeFolders.push(folder(rnm, kids));
	});

	// ------------------------------------------- CIERRE DEL MUNDO (BORDE)
	//
	// El borde cierra la SILUETA que forman zonas y rutas, no un cuadrado. Se
	// recorre el perimetro de la nube de zonas y se levanta pared alli donde no
	// hay suelo: el limite aparece exactamente donde acaba lo jugable, y por
	// eso el mundo no es un rectangulo con decoracion.
	const edge = worldEdge(zones);
	for (let i = 0; i < edge.length; i++) {
		const p = edge[i];
		const h = vary(seedBase, i + 200, 18, 34);
		borderParts.push(part("Border_Wall_" + i, {
			position: [p.x, p.y + h / 2, p.z],
			size: [p.w, h, p.d],
			material: P.structureMaterial,
			color: P.structureDark,
			orientation: [0, p.yaw, 0],
		}));
		borderParts.push(decor("Border_Cap_" + i, {
			position: [p.x, p.y + h + 0.7, p.z],
			size: [p.w * 0.9, 1.6, p.d * 1.6],
			material: P.structureMaterial,
			color: P.structureDark,
			orientation: [0, p.yaw, 0],
		}));
	}

	// ------------------------------------------------------ PIEZAS DE CONTRATO
	//
	// `ArenaFloor` sigue siendo UNA pieza, pero ahora es el suelo de la zona de
	// arena y no la losa de "todo el mundo". `BombService.detectArenaBounds` ya
	// es por mundo, asi que el limite de bombas se calcula sobre la zona por la
	// que se pelea y no sobre un cuadrado de 180x180.
	const arenaZone = zones.filter(function (z) { return z.role === "arena"; })[0];
	const entranceZone = zones.filter(function (z) { return z.role === "entrance"; })[0];

	const arenaParts = [
		part("ArenaFloor", {
			position: [arenaZone.x, arenaZone.y - 1, arenaZone.z],
			size: [arenaZone.rx * 2.1, 2, arenaZone.rz * 2.1],
			material: P.floorMaterial,
			color: P.ground,
		}),
		marker("ArenaCenter", [arenaZone.x, arenaZone.y + 0.2, arenaZone.z], { color: P.energy }),
		marker("ArenaNorth", [arenaZone.x, arenaZone.y + 0.2, arenaZone.z - arenaZone.rz + 10], { color: P.accent }),
		marker("ArenaSouth", [arenaZone.x, arenaZone.y + 0.2, arenaZone.z + arenaZone.rz - 10], { color: P.accent }),
		marker("ArenaEast", [arenaZone.x + arenaZone.rx - 10, arenaZone.y + 0.2, arenaZone.z], { color: P.accent }),
		marker("ArenaWest", [arenaZone.x - arenaZone.rx + 10, arenaZone.y + 0.2, arenaZone.z], { color: P.accent }),
	];

	// El spawn va en la zona de ENTRADA y mira a la primera ruta: el jugador
	// aparece viendo por donde se sigue, no mirando una pared.
	const firstRoute = routeInfo[0];
	const spawn = {
		name: "SpawnPoint_" + def.id,
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
				Color: color(P.energy[0], P.energy[1], P.energy[2]),
				Size: v3(12, 1, 12),
				Position: v3(entranceZone.x, entranceZone.y + 1.6, entranceZone.z + entranceZone.rz * 0.45),
				Orientation: v3(0, yawTo(firstRoute.to.x - entranceZone.x, firstRoute.to.z - entranceZone.z), 0),
			},
		},
	};

	// Umbral de entrada: un arco que marca "aqui empieza el mundo".
	const gateParts = [
		decor("Entrance_Gate_" + def.id + "_L", {
			position: [entranceZone.x - 9, entranceZone.y + 5, entranceZone.z],
			size: [2.6, 10, 2.6], shape: "Cylinder",
			material: P.structureMaterial, color: P.structure,
		}),
		decor("Entrance_Gate_" + def.id + "_R", {
			position: [entranceZone.x + 9, entranceZone.y + 5, entranceZone.z],
			size: [2.6, 10, 2.6], shape: "Cylinder",
			material: P.structureMaterial, color: P.structure,
		}),
		decor("Entrance_Gate_" + def.id + "_Top", {
			position: [entranceZone.x, entranceZone.y + 10.6, entranceZone.z],
			size: [21, 2, 3],
			material: P.structureMaterial, color: P.structureDark,
		}),
		decor("Entrance_Gate_" + def.id + "_Glow", {
			position: [entranceZone.x, entranceZone.y + 5, entranceZone.z],
			size: [17, 9, 0.4], material: "Neon", color: P.energy, transparency: 0.5,
		}),
	];

	// ---------------------------------------------------------------- MONTAJE
	return folder(def.id, arenaParts.concat(
		[spawn],
		gateParts,
		bossParts,
		exitParts,
		folder("Zones", zoneFolders),
		folder("Routes", routeFolders),
		folder("Blocks", blocks),
		folder("CentralStructure", centralBlocks),
		folder("Terrain", terrainParts),
		folder("Hazards", hazardParts),
		folder("Decoration", decoParts),
		folder("Border", borderParts),
		folder("Keshusy", keshusyParts),
		folder("MonsterSpawns", monsterSpawnParts),
		folder("PowerupSpawns", powerupParts)
	));
}

/**
 * PERIMETRO REAL del mundo.
 *
 * Devuelve las piezas de muro que cierran la silueta que forman las zonas. Se
 * proyecta sobre una rejilla: cada celda que "contiene" una zona se marca, y el
 * muro aparece en la frontera entre una celda marcada y una vacia.
 *
 * POR QUE NO UN CUADRADO
 * ----------------------
 * La version anterior hacia `perimeter(cx, cz, half, ...)`: cuatro paredes
 * rectas alrededor de un rectangulo. Eso es exactamente lo que la
 * especificacion prohibe, y por eso el cierre se calcula sobre la nube de zonas
 * reales. El resultado es un contorno irregular, con entrantes y salientes, y el
 * vacio de fuera queda marcado por donde el suelo se acaba de verdad.
 *
 * @param {Array} zonas de `buildWorld`, ya desplazadas
 * @returns {Array<{x,y,z,w,d,yaw}>} piezas de muro
 */
function worldEdge(zones) {
	const CELL = 16;

	// Extremos de la nube de zonas.
	let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
	for (const z of zones) {
		minX = Math.min(minX, z.x - z.rx); maxX = Math.max(maxX, z.x + z.rx);
		minZ = Math.min(minZ, z.z - z.rz); maxZ = Math.max(maxZ, z.z + z.rz);
	}
	// Un margen fijo: el muro no puede tocar el suelo, tiene que estar fuera.
	const pad = 14;
	minX -= pad + CELL; maxX += pad + CELL; minZ -= pad + CELL; maxZ += pad + CELL;

	const cols = Math.ceil((maxX - minX) / CELL);
	const rows = Math.ceil((maxZ - minZ) / CELL);
	const filled = [];
	for (let i = 0; i < cols * rows; i++) filled.push(false);

	for (const z of zones) {
		const c0 = Math.max(0, Math.floor((z.x - z.rx - minX) / CELL));
		const c1 = Math.min(cols - 1, Math.floor((z.x + z.rx - minX) / CELL));
		const r0 = Math.max(0, Math.floor((z.z - z.rz - minZ) / CELL));
		const r1 = Math.min(rows - 1, Math.floor((z.z + z.rz - minZ) / CELL));
		for (let r = r0; r <= r1; r++) {
			for (let c = c0; c <= c1; c++) {
				// Solo se marca la celda si su CENTRO cae dentro de la elipse.
				// Marcar el rectangulo completo reintroduciria el cuadrado.
				const mx = minX + (c + 0.5) * CELL;
				const mz = minZ + (r + 0.5) * CELL;
				const dx = (mx - z.x) / z.rx;
				const dz = (mz - z.z) / z.rz;
				if (dx * dx + dz * dz <= 1.12) filled[r * cols + c] = true;
			}
		}
	}

	// El muro va en la frontera: una celda con vecino vacio ES borde.
	const out = [];
	for (let r = 0; r < rows; r++) {
		for (let c = 0; c < cols; c++) {
			if (!filled[r * cols + c]) continue;
			const x = minX + (c + 0.5) * CELL;
			const z = minZ + (r + 0.5) * CELL;

			const sides = [
				{ open: r === 0 || !filled[(r - 1) * cols + c], w: CELL, d: 3, yaw: 0 },
				{ open: r === rows - 1 || !filled[(r + 1) * cols + c], w: CELL, d: 3, yaw: 0 },
				{ open: c === 0 || !filled[r * cols + c - 1], w: 3, d: CELL, yaw: 0 },
				{ open: c === cols - 1 || !filled[r * cols + c + 1], w: 3, d: CELL, yaw: 0 },
			];
			for (const s of sides) {
				if (!s.open) continue;
				out.push({ x: x, y: -2, z: z, w: s.w, d: s.d, yaw: s.yaw });
			}
		}
	}

	return out;
}

// -------------------------------------------------------------- ESCENARIOS
//
// Lo que hace que un mundo se lea como un LUGAR y no como una arena con otro
// tono. Cada funcion siembra DENTRO de una zona concreta, con la forma del
// elemento y no solo con el color.
//
// La identidad no son las paletas: son las SILUETAS. Un cactus no es un arbol
// con color verde, y una pilona de neón no es un pilar de piedra. Por eso cada
// mundo tiene su propio constructor de elementos.

/**
 * Elemento aleatorio dentro de una zona, sin salir de ella.
 *
 * Se muestrea en coordenadas polares y se RECHAZA si el punto cae sobre una
 * ruta. Un arbol plantado en mitad de un sendero no es decoracion: es un obstac
 *culo invisible en un sitio por el que el jugador tiene que pasar.
 */
function scatterInZone(z, seedBase, salt, minR, maxR) {
	for (let attempt = 0; attempt < 8; attempt++) {
		const a = vary(seedBase + salt, attempt * 3 + 1, 0, Math.PI * 2);
		const r = vary(seedBase + salt, attempt * 3 + 2, minR, maxR);
		const x = z.x + Math.cos(a) * z.rx * r;
		const zz = z.z + Math.sin(a) * z.rz * r;
		return { x: x, z: zz, a: a, r: r, ok: true };
	}
	return { x: z.x, z: z.z, a: 0, r: 0, ok: false };
}

/** FOREST: arboles de tronco y copa, arbustos, hongos y cristales. */
function sceneryForest(api, z, P, seedBase, out) {
	const { decor } = api;

	const tree = (name, x, zz, h, tint) => {
		const trunk = hash01(seedBase + name.length, 5) > 0.5 ? P.barkDark : P.barkMid;
		out.deco.push(decor("Tree_Trunk_" + name, {
			position: [x, z.y + h / 2, zz],
			size: [1.8, h, 1.8],
			material: "Wood", color: trunk,
			orientation: [0, Math.round(vary(seedBase, 5, -10, 10)), 0],
		}));
		out.deco.push(decor("Tree_Canopy_" + name, {
			position: [x, z.y + h + 1.2, zz],
			size: [h * 0.85, h * 0.7, h * 0.85],
			shape: "Ball", material: "Grass", color: tint,
		}));
		out.deco.push(decor("Tree_CanopyTop_" + name, {
			position: [x, z.y + h + h * 0.45, zz],
			size: [h * 0.55, h * 0.45, h * 0.55],
			shape: "Ball", material: "Grass", color: P.leafLight,
		}));
	};

	// El bosque denso solo en el oeste: es la masa que no se ve desde el
	// spawn. En el resto, arbustos bajos que no tapan el suelo.
	if (z.id === "Grove" || z.id === "Hollow") {
		for (let i = 0; i < 16; i++) {
			const p = scatterInZone(z, seedBase, i, 0.35, 0.92);
			tree(z.id + i, p.x, p.z, vary(seedBase + i, 17, 8, 18), hash01(seedBase + i, 23) > 0.5 ? P.leafMid : P.leafDeep);
		}
	} else if (z.role !== "arena" && z.role !== "boss") {
		for (let i = 0; i < 6; i++) {
			const p = scatterInZone(z, seedBase, i + 40, 0.5, 0.92);
			out.deco.push(decor("Bush_" + z.id + "_" + i, {
				position: [p.x, z.y + 1.3, p.z],
				size: [vary(seedBase + i, 109, 2.4, 4.6), vary(seedBase + i, 111, 1.6, 3), vary(seedBase + i, 113, 2.4, 4.6)],
				shape: "Ball", material: "Grass",
				color: hash01(seedBase + i, 115) > 0.5 ? P.leafMid : P.leafDeep,
			}));
		}
	}

	// Cristal Keshusy: lo que hace que esto sea KeshusyTomy-LanD y no un bosque
	// de Roblox. Solo en tres zonas, como foco, no en todas.
	if (z.id === "Spring" || z.id === "Hollow" || z.id === "Trail") {
		const cx = z.x + z.rx * 0.35;
		const cz2 = z.z - z.rz * 0.3;
		out.keshusy.push(decor("Crystal_Shard_" + z.id, {
			position: [cx, z.y + 4, cz2], size: [1.8, 8, 1.8],
			shape: "Cylinder", material: "Neon", color: P.crystal,
			orientation: [0, 0, 14],
		}));
		out.keshusy.push(decor("Crystal_ShardLow_" + z.id, {
			position: [cx, z.y + 2.6, cz2], size: [1.3, 5.4, 1.3],
			shape: "Cylinder", material: "Neon", color: P.crystalHot,
			orientation: [0, 24, 20],
		}));
		out.keshusy.push(decor("Crystal_Float_" + z.id, {
			position: [cx + 1, z.y + 9.4, cz2], size: [0.9, 0.9, 0.9],
			shape: "Ball", material: "Neon", color: P.crystalHot,
		}));
	}

	// Luciernagas: puntos de luz flotantes que dan escala y movimiento.
	for (let i = 0; i < 6; i++) {
		const p = scatterInZone(z, seedBase, i + 80, 0.2, 0.95);
		out.keshusy.push(decor("Firefly_" + z.id + "_" + i, {
			position: [p.x, z.y + 2.5 + hash01(seedBase + i, 110) * 8, p.z],
			size: [0.7, 0.7, 0.7], shape: "Ball", material: "Neon",
			color: hash01(seedBase + i, 120) > 0.75 ? [216, 246, 150] : P.crystalHot,
			transparency: 0.25,
		}));
	}

	// Claros de arena: rompen el verde y dan puntos de referencia.
	if (z.id === "Clearing" || z.id === "Trail") {
		out.terrain.push(decor("Sand_Clearing_" + z.id, {
			position: [z.x, z.y + 0.05, z.z],
			size: [z.rx * 1.4, 0.1, z.rz * 1.2],
			shape: "Cylinder", material: "Sand", color: P.sand,
		}));
	}
}

/** BOOM DESERT: dunas, cactus columnares y ruinas de arenisca. */
function sceneryDesert(api, z, P, seedBase, out) {
	const { decor } = api;

	// Dunas: esferas muy achatadas. La silueta redondeada es lo que hace que
	// el suelo no lea como una losa.
	const dunes = z.id === "Dunes" || z.id === "OpenField" ? 10 : 5;
	for (let i = 0; i < dunes; i++) {
		const p = scatterInZone(z, seedBase, i, 0.2, 0.95);
		const h = vary(seedBase + i, 301, 2.5, 6);
		out.deco.push(decor("Dune_" + z.id + "_" + i, {
			position: [p.x, z.y + h * 0.3, p.z],
			size: [vary(seedBase + i, 304, 26, 48), h, vary(seedBase + i, 305, 22, 40)],
			shape: "Ball", material: "Sand", color: P.groundAlt,
			orientation: [0, Math.round(p.a * 57.3), 0],
		}));
	}

	// Cactus: tronco columnar + dos brazos. Inconfundibles a distancia.
	const cacti = z.role === "exploration" || z.id === "Ruins" ? 9 : 4;
	for (let i = 0; i < cacti; i++) {
		const p = scatterInZone(z, seedBase, i + 30, 0.45, 0.95);
		const h = vary(seedBase + i, 313, 6, 13);
		out.deco.push(decor("Cactus_" + z.id + "_" + i, {
			position: [p.x, z.y + h / 2, p.z], size: [1.6, h, 1.6],
			shape: "Cylinder", material: "Grass", color: P.green,
		}));
		out.deco.push(decor("Cactus_ArmL_" + z.id + "_" + i, {
			position: [p.x - 1.7, z.y + h * 0.62, p.z], size: [3.6, 1.3, 1.3],
			shape: "Cylinder", material: "Grass", color: P.green,
			orientation: [0, 0, 90],
		}));
		out.deco.push(decor("Cactus_ArmR_" + z.id + "_" + i, {
			position: [p.x + 1.5, z.y + h * 0.44, p.z], size: [3, 1.2, 1.2],
			shape: "Cylinder", material: "Grass", color: P.green,
			orientation: [0, 0, 90],
		}));
	}

	// Ruinas: columnas con capitel. Un landmark y un motivo para construir el
	// muro en vez de levantarlo plano.
	if (z.id === "Ruins" || z.id === "Pillars" || z.id === "Treasure") {
		const cols = z.id === "Pillars" ? 8 : 5;
		for (let i = 0; i < cols; i++) {
			const p = scatterInZone(z, seedBase, i + 60, 0.3, 0.9);
			const h = vary(seedBase + i, 321, 9, 20);
			out.deco.push(decor("Ruin_Column_" + z.id + "_" + i, {
				position: [p.x, z.y + h / 2, p.z], size: [3.4, h, 3.4],
				shape: "Cylinder", material: P.structureMaterial, color: P.structure,
			}));
			out.deco.push(decor("Ruin_Cap_" + z.id + "_" + i, {
				position: [p.x, z.y + h + 0.7, p.z], size: [4.8, 1.4, 4.8],
				shape: "Cylinder", material: P.structureMaterial, color: P.structureDark,
			}));
		}
	}

	// Charcos de calor: planos translucidos sin colision.
	for (let i = 0; i < 2; i++) {
		const p = scatterInZone(z, seedBase, i + 90, 0.3, 0.8);
		const s = vary(seedBase + i, 331, 8, 15);
		out.keshusy.push(decor("HeatPool_" + z.id + "_" + i, {
			position: [p.x, z.y + 0.12, p.z], size: [s, 0.2, s],
			shape: "Cylinder", color: P.hazard, transparency: 0.5,
		}));
	}

	// EL OASIS. Es lo que hace que este mundo sea un deserto y no un sitio
	// naranja: un lago con palmeras, el unico verde y el unico agua del mapa
	// del mundo. Ademas da un RESPIRO entre la zona de destruccion y la arena:
	// el jugador pasa de波罗 a sombra antes de la fight.
	if (z.id === "Oasis") {
		out.terrain.push(decor("Oasis_Water", {
			position: [z.x, z.y + 0.08, z.z],
			size: [z.rx * 1.5, 0.16, z.rz * 1.4],
			shape: "Cylinder",
			material: "Glass", color: [86, 176, 210], transparency: 0.35,
		}));
		for (let i = 0; i < 7; i++) {
			const a = (i / 7) * Math.PI * 2 + 0.4;
			const px = z.x + Math.cos(a) * z.rx * 0.92;
			const pz = z.z + Math.sin(a) * z.rz * 0.92;
			const th = vary(seedBase + i, 341, 8, 14);
			// Palmera: tronco inclinado y cinco hojas radiales.
			out.deco.push(decor("Palm_Trunk_" + i, {
				position: [px, z.y + th / 2, pz], size: [1.1, th, 1.1],
				shape: "Cylinder", material: "Wood", color: P.bark || [110, 84, 52],
				orientation: [Math.round(vary(seedBase + i, 342, -10, 10)), 0, Math.round(vary(seedBase + i, 343, -10, 10))],
			}));
			for (let f = 0; f < 5; f++) {
				const fa = (f / 5) * Math.PI * 2;
				out.deco.push(decor("Palm_Frond_" + i + "_" + f, {
					position: [px + Math.cos(fa) * 3.4, z.y + th + 0.6, pz + Math.sin(fa) * 3.4],
					size: [7, 0.5, 2.2],
					material: "Grass", color: P.green,
					orientation: [Math.round(vary(seedBase + i + f, 344, -22, 22)), Math.round(-fa * 57.3), 0],
				}));
			}
		}
	}

	// EL CAÑON. Estratos horizontales apilados: la forma que solo tiene un
	// barranco erosionado. Va en la zona y ademas la ruta `canyon` levanta sus
	// propias paredes, asi que el paso se lee excavado y no vallado.
	if (z.id === "Canyon") {
		for (let side = 0; side < 2; side++) {
			const sgn = side === 0 ? -1 : 1;
			for (let i = 0; i < 5; i++) {
				const h = vary(seedBase + i, 351 + side, 22, 40);
				out.deco.push(decor("Canyon_Strata_" + side + "_" + i, {
					position: [z.x + sgn * z.rx * 0.96, z.y + h / 2, z.z + (i - 2) * 15],
					size: [10, h, 17],
					material: P.structureMaterial,
					color: i % 2 === 0 ? P.structure : P.structureDark,
					orientation: [0, Math.round(vary(seedBase + i, 352, -6, 6)), 0],
				}));
			}
		}
	}
}

/** FROZEN TOMY: agujas de hielo, copas heladas y linternas de escarcha. */
function sceneryIce(api, z, P, seedBase, out) {
	const { decor } = api;

	// Agujas: prismas inclinados. La inclinacion es la diferencia con una
	// columna recta.
	const spikes = z.role === "exploration" || z.id === "Narrows" ? 11 : 6;
	for (let i = 0; i < spikes; i++) {
		const p = scatterInZone(z, seedBase, i, 0.25, 0.95);
		const h = vary(seedBase + i, 401, 7, 20);
		out.deco.push(decor("IceSpire_" + z.id + "_" + i, {
			position: [p.x, z.y + h / 2, p.z],
			size: [vary(seedBase + i, 402, 2, 4.4), h, vary(seedBase + i, 403, 2, 4.4)],
			shape: "Cylinder", material: "Ice", color: P.structure,
			orientation: [
				Math.round(vary(seedBase + i, 404, -14, 14)),
				Math.round(hash01(seedBase + i, 405) * 360),
				Math.round(vary(seedBase + i, 406, -14, 14)),
			],
		}));
	}

	// Bloques de hielo apilados: cobertura visual baja.
	for (let i = 0; i < 5; i++) {
		const p = scatterInZone(z, seedBase, i + 30, 0.4, 0.9);
		const h = vary(seedBase + i, 411, 3, 7);
		out.deco.push(decor("IceBlock_" + z.id + "_" + i, {
			position: [p.x, z.y + h / 2, p.z],
			size: [vary(seedBase + i, 412, 7, 13), h, vary(seedBase + i, 413, 7, 13)],
			shape: "Ball", material: "Ice", color: P.structure,
			orientation: [0, Math.round(hash01(seedBase + i, 414) * 360), 0],
		}));
	}

	// El lago: una lamina de hielo translucida con grietas.
	if (z.id === "Lake") {
		out.terrain.push(decor("Lake_Sheet_" + z.id, {
			position: [z.x, z.y + 0.06, z.z],
			size: [z.rx * 1.7, 0.12, z.rz * 1.7],
			shape: "Cylinder", material: "Ice", color: P.structureDark, transparency: 0.45,
		}));
		for (let i = 0; i < 9; i++) {
			const a = (i / 9) * Math.PI * 2;
			out.terrain.push(decor("Lake_Crack_" + z.id + "_" + i, {
				position: [z.x + Math.cos(a) * z.rx * 0.6, z.y + 0.16, z.z + Math.sin(a) * z.rz * 0.6],
				size: [vary(seedBase + i, 421, 12, 26), 0.14, 1.4],
				color: P.energy, transparency: 0.4,
				orientation: [0, Math.round((a * 180) / Math.PI) + 90, 0],
			}));
		}
	}

	// Aurora: la recompensa de Frozen Tomy se ve desde lejos.
	if (z.id === "Aurora") {
		for (let i = 0; i < 7; i++) {
			const a = (i / 7) * Math.PI * 2;
			out.keshusy.push(decor("Aurora_Blade_" + z.id + "_" + i, {
				position: [z.x + Math.cos(a) * 16, z.y + 9 + (i % 3) * 2, z.z + Math.sin(a) * 16],
				size: [1.6, 18, 1.6], shape: "Cylinder",
				material: "Neon", color: i % 2 === 0 ? P.accent : P.energy,
				transparency: 0.4,
				orientation: [0, 0, Math.round(vary(seedBase + i, 431, -18, 18))],
			}));
		}
	}
}

/** VOLCANO RAGE: torres de basalto, charcos de lava y columnas de fuego. */
function sceneryVolcano(api, z, P, seedBase, out) {
	const { decor } = api;

	// Torres de basalto: columnas altas y angulosas, como chimeneas.
	const towers = z.role === "exploration" || z.id === "Vents" ? 9 : 5;
	for (let i = 0; i < towers; i++) {
		const p = scatterInZone(z, seedBase, i, 0.3, 0.95);
		const h = vary(seedBase + i, 501, 15, 34);
		out.deco.push(decor("Basalt_Tower_" + z.id + "_" + i, {
			position: [p.x, z.y + h / 2, p.z],
			size: [vary(seedBase + i, 504, 4, 8), h, vary(seedBase + i, 505, 4, 8)],
			shape: "Cylinder", material: "Basalt",
			color: hash01(seedBase + i, 506) > 0.5 ? P.structure : P.structureDark,
			orientation: [
				Math.round(vary(seedBase + i, 507, -12, 12)),
				Math.round(hash01(seedBase + i, 508) * 360),
				Math.round(vary(seedBase + i, 509, -12, 12)),
			],
		}));
		// Boca encendida: sin esto la torre es un palo negro.
		out.deco.push(decor("Basalt_Mouth_" + z.id + "_" + i, {
			position: [p.x, z.y + h + 0.4, p.z],
			size: [vary(seedBase + i, 510, 3, 5), 0.8, vary(seedBase + i, 511, 3, 5)],
			shape: "Cylinder", color: P.accent, transparency: 0.15,
		}));
	}

	// Charcos de lava: crateres planos con un anillo brillante.
	for (let i = 0; i < 3; i++) {
		const p = scatterInZone(z, seedBase, i + 30, 0.2, 0.85);
		const s = vary(seedBase + i, 521, 12, 24);
		out.keshusy.push(decor("LavaPool_" + z.id + "_" + i, {
			position: [p.x, z.y + 0.1, p.z], size: [s, 0.2, s],
			shape: "Cylinder", color: P.hazard,
		}));
		out.keshusy.push(decor("LavaRim_" + z.id + "_" + i, {
			position: [p.x, z.y + 0.3, p.z], size: [s + 3, 0.5, s + 3],
			shape: "Cylinder", color: P.accent, transparency: 0.4,
		}));
	}

	// Grietas: conectan los charcos y dan lectura de "flujo" sin particulas.
	for (let i = 0; i < 5; i++) {
		const a = (i / 5) * Math.PI * 2 + 0.4;
		out.terrain.push(decor("LavaCrack_" + z.id + "_" + i, {
			position: [z.x + Math.cos(a) * z.rx * 0.5, z.y + 0.14, z.z + Math.sin(a) * z.rz * 0.5],
			size: [vary(seedBase + i, 531, 10, 26), 0.16, 1.6],
			color: P.hazard,
			orientation: [0, Math.round((a * 180) / Math.PI) + 90, 0],
		}));
	}

	// Columnas de fuego: el acento del mundo.
	if (z.id === "Forge" || z.role === "arena") {
		for (let i = 0; i < 6; i++) {
			const a = (i / 6) * Math.PI * 2;
			out.keshusy.push(decor("FirePillar_" + z.id + "_" + i, {
				position: [z.x + Math.cos(a) * 17, z.y + 12, z.z + Math.sin(a) * 17],
				size: [2.4, 24, 2.4], shape: "Cylinder",
				color: i % 2 === 0 ? P.accent : P.hazard, transparency: 0.4,
			}));
		}
	}
}

/** CYBER KESHUSY: pilonas, paneles holograficos y rejilla de neon. */
function sceneryCyber(api, z, P, seedBase, out) {
	const { decor } = api;

	// Rejilla de neon en el suelo: el motivo digital del mundo.
	for (let i = -2; i <= 2; i++) {
		out.terrain.push(decor("Grid_X_" + z.id + "_" + i, {
			position: [z.x + i * 12, z.y + 0.1, z.z],
			size: [0.5, 0.2, z.rz * 1.7], color: P.accent, transparency: 0.55,
		}));
		out.terrain.push(decor("Grid_Z_" + z.id + "_" + i, {
			position: [z.x, z.y + 0.1, z.z + i * 12],
			size: [z.rx * 1.7, 0.2, 0.5], color: P.accent, transparency: 0.55,
		}));
	}

	// Pilonas: torres metalicas con anillos de neon.
	const pylons = z.role === "exploration" || z.id === "Energy" ? 8 : 4;
	for (let i = 0; i < pylons; i++) {
		const p = scatterInZone(z, seedBase, i, 0.3, 0.95);
		const h = vary(seedBase + i, 601, 14, 30);
		out.deco.push(decor("Pylon_" + z.id + "_" + i, {
			position: [p.x, z.y + h / 2, p.z], size: [3.4, h, 3.4],
			shape: "Cylinder", material: "Metal", color: P.structure,
		}));
		for (let b = 1; b <= 3; b++) {
			out.deco.push(decor("Pylon_Band_" + z.id + "_" + i + "_" + b, {
				position: [p.x, z.y + (h / 4) * b, p.z], size: [4.2, 0.7, 4.2],
				shape: "Cylinder", color: b % 2 === 0 ? P.accent : P.hazard, transparency: 0.2,
			}));
		}
	}

	// Paneles holograficos: planos verticales translucidos.
	for (let i = 0; i < 4; i++) {
		const p = scatterInZone(z, seedBase, i + 20, 0.5, 0.9);
		const h = vary(seedBase + i, 611, 8, 16);
		out.deco.push(decor("HoloPanel_" + z.id + "_" + i, {
			position: [p.x, z.y + h / 2, p.z], size: [12, h, 0.4],
			color: hash01(seedBase + i, 612) > 0.5 ? P.accent : P.energy,
			transparency: 0.55,
			orientation: [0, Math.round((p.a * 180) / Math.PI) + 90, 0],
		}));
		out.deco.push(decor("HoloFrame_" + z.id + "_" + i, {
			position: [p.x, z.y + h / 2, p.z], size: [12.6, 0.5, 0.6],
			color: P.structureDark,
			orientation: [0, Math.round((p.a * 180) / Math.PI) + 90, 0],
		}));
	}

	// Nucleo holografico: la sala de energia y el boss.
	if (z.id === "Energy" || z.role === "boss") {
		for (let i = 0; i < 4; i++) {
			out.keshusy.push(decor("HoloRing_" + z.id + "_" + i, {
				position: [z.x, z.y + 12 + i * 4, z.z],
				size: [24 - i * 4, 0.4, 24 - i * 4], shape: "Cylinder",
				color: i % 2 === 0 ? P.accent : P.energy, transparency: 0.5,
			}));
		}
		out.keshusy.push(decor("Core_" + z.id, {
			position: [z.x, z.y + 22, z.z], size: [7, 7, 7], shape: "Ball",
			color: P.energy, transparency: 0.1,
		}));
	}
}

/**
 * ESCENARIOS por id.
 *
 * El mapa es el mecanismo de lectura: cada mundo consulta el suyo. Anadir un
 * sexto mundo es anadir una entrada aqui y un layout en `LAYOUTS`, sin tocar
 * el motor.
 */
const SCENERY = {
	Forest: sceneryForest,
	Desert: sceneryDesert,
	Ice: sceneryIce,
	Volcano: sceneryVolcano,
	Cyber: sceneryCyber,
};

module.exports = {
	PALETTES: PALETTES,
	LAYOUTS: LAYOUTS,
	WORLD_IDS: ["Forest", "Desert", "Ice", "Volcano", "Cyber"],
	buildWorld: buildWorld,
	hash01: hash01,
	vary: vary,
	dist2d: dist2d,
	SCENERY: SCENERY,
};
