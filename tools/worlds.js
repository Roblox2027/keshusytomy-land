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
// ------------------------------------------------------ ANCHOS DE CORREDOR
//
// P0. El ancho no es un parametro que cada ruta pueda inventarse: es una regla
// de diseno del mundo, y se escribe UNA vez para que los cinco mundos midan lo
// mismo. Los rangos son los de la especificacion de fase:
//
//   normal    12-20   el jugador corre, gira y esquiva
//   combate   20-40   hay espacio para rodear a un enemigo
//
// Antes el ancho era `14` para todas las rutas. Con el mundo ampliado a
// 460x460, 14 studs de corredor son un pasillo en un mapa de tres manzanas: el
// verificador media 5 studs en los puntos mas estrechos y las legs criticas
// salian sin ruta alternativa.
//
// Se declaran ANTES de `LAYOUTS` porque `route()` las lee al construir el layout,
// y un `const` declarado mas abajo todavia no existe cuando se ejecuta esa linea.
const ROUTE_WIDTHS = {
	path: 20,
	narrow: 16,
	bridge: 20,
	catwalk: 18,
	canyon: 22,
	tunnel: 20,
};

/**
 * Ancho minimo de una ruta. Nadie declara un corredor mas estrecho que esto.
 *
 * El suelo de una zona tiene que ser al menos tan ancho como el cuello que lo
 * entra: un cuello de 20 studs que abre en una plataforma de 8 no es una
 * plataforma, es una trampa.
 */
const MIN_ROUTE_WIDTH = 16;

/** Expande una tupla de ruta en objeto. */
function route(t) {
	return {
		from: t[0],
		to: t[1],
		style: t[2],
		// El ancho declarado por la ruta manda; si no lo declara, decide el
		// estilo. Nunca sale por debajo de `MIN_ROUTE_WIDTH`.
		width: Math.max(t[3] || ROUTE_WIDTHS[t[2]] || ROUTE_WIDTHS.path, MIN_ROUTE_WIDTH),
	};
}


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
	// Un bosque nocturno de supervivencia/exploracion, amplio y explorable.
	// Se entra por el sur (Entrada), se abre en zonas reconocibles conectadas
	// por una red de caminos naturales (principales, secundarios, senderos).
	// El bosque denso esta al noroeste, el pantano al centro-este, las ruinas
	// al suroeste, el campamento al noreste, las cabanas dispersas. La zona
	// oscura (nido, jefe, arena) queda al fondo norte, accesible por multiples
	// rutas alternativas para no quedar atrapado.
	Forest: {
		zones: [
			// ---- ZONA DE ENTRADA (sur) ----
			zone(["Entrance", "entrance", -7.4, 218.2, 65.2, 41.9]),

			// ---- BOSQUE CENTRAL (centro-sur, area de inicio) ----
			zone(["CentralPath", "exploration", 1.3, 138.9, 74.5, 37.3]),
			zone(["CentralClearing", "scenic", -100.2, 107.2, 41.9, 28.0, 1]),
			zone(["CentralGlade", "exploration", 114.5, 132.7, 37.3, 26.1, 1]),

			// ---- BOSQUE DENSO (noroeste, denso y oscuro) ----
			zone(["DenseGrove", "encounter", -212.0, 118.6, 69.9, 37.3, 3]),
			zone(["DeepThicket", "exploration", -221.2, 47.8, 60.6, 32.6, 4]),
			zone(["AncientGrove", "encounter", -166.1, -5.5, 51.2, 28.0, 5]),

			// ---- CLAROS (zonas abiertas para referencia visual) ----
			zone(["ClearingEast", "encounter", 142.7, 80.4, 51.2, 28.0]),
			zone(["ClearingWest", "scenic", -113.2, 41.5, 44.7, 26.1, 2]),
			zone(["MeadowNorth", "reward", -15.9, -18.1, 55.8, 32.6, 3]),

			// ---- ZONA ROCOSA (este, elevaciones y cobertura solida) ----
			zone(["RockyRidge", "destruction", 171.8, 21.6, 60.6, 32.6, 6]),
			zone(["BoulderField", "scenic", 187.4, -37.4, 46.5, 26.1, 4]),
			zone(["StoneArch", "scenic", 155.9, -93.7, 51.2, 32.6, 5]),

			// ---- PANTANO (centro-este, terreno bajo y peligroso) ----
			zone(["SwampEdge", "scenic", 47.2, 40.4, 51.2, 28.0, -1]),
			zone(["DeepSwamp", "intermediate", 81.5, -7.6, 41.9, 23.3, -2]),
			zone(["BogHollow", "encounter", 92.5, -52.1, 37.3, 20.4, -3]),

			// ---- CAMPAMENTO ABANDONADO (noreste, punto de interes principal) ----
			zone(["CampCenter", "intermediate", 142.7, 191.5, 51.2, 32.6, 3]),
			zone(["CampPeriphery", "exploration", 224.7, 133.7, 65.2, 46.5, 2]),

			// ---- ZONA DE CABANAS (dispersas, noroeste y oeste) ----
			zone(["CabinGrove", "exploration", -161.0, 180.1, 41.9, 28.0, 4]),
			zone(["HiddenCabin", "miniboss", -110.7, -42.3, 32.6, 20.4, 2]),
			zone(["RangerStation", "reward", -47.1, -87.7, 35.4, 22.4, 3]),

			// ---- ZONA DE RUINAS (suroeste, estructuras antiguas) ----
			zone(["RuinsOuter", "destruction", -162.4, -100.6, 46.5, 28.0, 2]),
			zone(["RuinsInner", "intermediate", -139.5, -151.8, 37.3, 23.3, 3]),
			zone(["ForgottenShrine", "secret", -113.9, -193.0, 32.6, 18.7, 4]),

			// ---- ZONA OSCURA (norte: nido, arena, jefe, salida) ----
			zone(["DarkNest", "encounter", 62.2, -96.5, 41.9, 23.3, 1]),
			zone(["Arena", "arena", -8.2, -157.8, 93.1, 46.5]),
			zone(["Grooty", "boss", -6.5, -241.8, 69.9, 37.3]),
			zone(["ExitNorth", "exit", 160.6, -166.8, 41.9, 23.3]),
		],
		routes: [
			// ---- CAMINO PRINCIPAL (spawn -> arena) - serpentea, no recto ----
			route(["Entrance", "CentralPath", "path", 22]),
			route(["CentralPath", "CentralClearing", "path", 20]),
			route(["CentralClearing", "MeadowNorth", "path", 22]),
			route(["MeadowNorth", "Arena", "path", 24]),
			route(["CentralPath", "ExitNorth", "path", 22]),

			// ---- RAMA OESTE: Bosque Central -> Bosque Denso (senderos estrechos) ----
			route(["CentralPath", "CentralGlade", "path", 18]),
			route(["CentralGlade", "ClearingWest", "narrow", 16]),
			route(["ClearingWest", "DenseGrove", "narrow", 16]),
			route(["DenseGrove", "DeepThicket", "narrow", 14]),
			route(["DeepThicket", "AncientGrove", "narrow", 14]),
			route(["AncientGrove", "RuinsOuter", "path", 18]),

			// ---- RAMA ESTE: Bosque Central -> Claros -> Zona Rocosa ----
			route(["CentralPath", "ClearingEast", "path", 20]),
			route(["ClearingEast", "RockyRidge", "path", 18]),
			route(["RockyRidge", "BoulderField", "narrow", 16]),
			route(["BoulderField", "StoneArch", "narrow", 14]),

			// ---- CONEXION CENTRO -> PANTANO (sendero secundario) ----
			route(["MeadowNorth", "SwampEdge", "narrow", 16]),
			route(["SwampEdge", "DeepSwamp", "narrow", 14]),
			route(["DeepSwamp", "BogHollow", "narrow", 14]),
			route(["BogHollow", "DarkNest", "path", 18]),

			// ---- CONEXIONES TRANSVERSALES (rutas alternativas, decisiones de ruta) ----
			route(["CentralClearing", "ClearingWest", "narrow", 16]),
			route(["ClearingWest", "DeepThicket", "narrow", 14]),
			route(["ClearingEast", "SwampEdge", "bridge", 18]),
			route(["RockyRidge", "MeadowNorth", "bridge", 20]),
			route(["StoneArch", "DarkNest", "canyon", 20]),
			route(["CentralGlade", "DenseGrove", "narrow", 14]),
			route(["ClearingEast", "CentralGlade", "narrow", 14]),
			route(["RockyRidge", "StoneArch", "narrow", 14]),
			route(["DeepThicket", "CabinGrove", "narrow", 14]),
			route(["RuinsOuter", "BogHollow", "bridge", 18]),

			// ---- CAMPAMENTO (noreste, accesible desde multiples lados) ----
			route(["CentralPath", "CampPeriphery", "path", 18]),
			route(["CampPeriphery", "CampCenter", "narrow", 16]),
			route(["ClearingEast", "CampPeriphery", "narrow", 16]),
			route(["CampCenter", "CabinGrove", "narrow", 14]),

			// ---- CABANAS (dispersas, senderos secundarios) ----
			route(["DenseGrove", "CabinGrove", "narrow", 14]),
			route(["CentralClearing", "HiddenCabin", "narrow", 14]),
			route(["RuinsOuter", "HiddenCabin", "narrow", 14]),
			route(["MeadowNorth", "RangerStation", "path", 18]),
			route(["RangerStation", "Arena", "path", 20]),
			route(["HiddenCabin", "RangerStation", "narrow", 14]),
			route(["CabinGrove", "HiddenCabin", "narrow", 14]),

			// ---- RUINAS (suroeste, conexion con zona oscura) ----
			route(["AncientGrove", "RuinsOuter", "path", 18]),
			route(["RuinsOuter", "RuinsInner", "narrow", 14]),
			route(["RuinsInner", "ForgottenShrine", "narrow", 14]),
			route(["ForgottenShrine", "Grooty", "canyon", 20]),
			route(["RuinsOuter", "DeepSwamp", "bridge", 18]),
			route(["RuinsInner", "StoneArch", "narrow", 14]),

			// ---- ZONA OSCURA (multiples entradas a arena/jefe/salida) ----
			route(["MeadowNorth", "Arena", "path", 24]),
			route(["DarkNest", "Arena", "path", 20]),
			route(["RangerStation", "Arena", "path", 20]),
			// P0 CORREGIDO (redundancia norte-sur): el DIAG BLOQUEO mostro que
			// al cerrar el camino mas corto Spawn->Boss, TODO el norte del
			// mapa (Entrance, CentralPath, MeadowNorth, Camp, Ruins, DarkNest)
			// quedaba cortado del sur (Arena, Grooty, ExitNorth). La unica
			// arteria era el cuello de Entrance, y por ahi pasaban spawn, boss
			// y salida. Eso es un solo punto de fallo, no redundancia.
			//
			// Se cierra el bucle norte: MeadowNorth <-> CampCenter ->
			// DarkNest <-> Arena. Con eso el norte tiene DOS arterias
			// independientes (la oeste, por MeadowNorth, y la este, por Camp
			// y DarkNest) y al taponar una queda la otra. Entrance se
			// conserva como la entrada principal, pero ya no es un cuello
			// de botella de todo el mapa.
			route(["MeadowNorth", "CampCenter", "path", 26]),
			route(["CampCenter", "DarkNest", "path", 20]),
			route(["CampPeriphery", "DarkNest", "path", 24]),
			// P0 CORREGIDO 2: Entrance tiene un solo cuello hacia el sur
			// (el oeste, a MeadowNorth). Eso hace que Entrance sea un punto
			// de fallo unico: al taponarlo, TODO el norte queda cortado.
			// Una ruta Entrance -> CampCenter da una segunda arteria
			// independiente (este) que sale de Entrance sin pasar por el
			// cuello oeste. Con ella, Entrance ya no es un solo punto de
			// fallo y el spawn tiene dos caminos distintos al boss.
			route(["Entrance", "CampCenter", "path", 26]),
			route(["Arena", "Grooty", "canyon", 22]),
			route(["StoneArch", "Grooty", "canyon", 20]),
			route(["ForgottenShrine", "Grooty", "canyon", 20]),
			// P0 CORREGIDO: el boss route tenia una unica puerta de entrada
			// (Arena -> Grooty). Al cerrarla para probar redundancia, el
			// verificador no encontraba camino alternativo y marcaba
			// "BOSS ROUTE BLOCKED". Una ruta directa desde la zona oscura
			// (DarkNest) al boss da la segunda entrada: el boss se alcanza
			// por el norte del mapa sin pasar por la arena, y el jugador
			// tiene dos caminos distintos para llegar el.
			route(["DarkNest", "Grooty", "narrow", 16]),
			route(["Grooty", "ExitNorth", "path", 20]),
			route(["Arena", "ExitNorth", "path", 20]),
			route(["DarkNest", "ExitNorth", "narrow", 16]),
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
			zone(["Gate", "entrance", 0, 194, 65.2, 40]),
			zone(["Dunes", "exploration", 0, 100, 76.07, 30]),
			zone(["Pillars", "encounter", -173.87, 120, 50.72, 24]),
			zone(["OpenField", "exploration", -94.18, 30, 79.69, 36]),
			zone(["Canyon", "scenic", 177.49, 46, 54.34, 34, 2]),
			zone(["Ruins", "destruction", 181.11, -46, 61.58, 30, 4]),
			zone(["Cover", "scenic", -217.34, -40, 57.96, 28, 1]),
			zone(["Oasis", "intermediate", -47.09, -92, 76.07, 34]),
			zone(["Treasure", "reward", 94.18, -128, 50.72, 22, 4]),
			zone(["Arena", "arena", -83.31, -170, 86.94, 38]),
			zone(["SandBeast", "boss", -105.04, -254, 68.83, 30]),
			zone(["Exit", "exit", 141.27, -222, 43.47, 20]),

			// ------------------------------------------------------
			// ZONAS DE LA EXPANSION (expansion 99 noches)
			//
			// El mundo pasa de 12 a 17 zonas. Mismo criterio que Forest:
			// cada zona nueva esta en un hueco REAL del mapa (comprobado
			// contra las elipses vecinas con el mismo criterio de
			// `world-structure-test.js`), no extiende el bounding box del
			// layout (la escala del mundo no cambia) y tiene DOS puertas.
			//
			//   Temple    templo al noreste, antes inaccessible
			//   Mine      mina entre canyon y ruinas (destruccion)
			//   Nest      nido de monstruos al centro-este
			//   DuneKeep  fortaleza de dunas: la zona de mini-boss
			//   Catacomb  zona SECRETA al suroeste, tras la fortaleza
			// ------------------------------------------------------
			zone(["Temple", "intermediate", 140, 150, 30, 24]),
			zone(["Mine", "destruction", 50, -30, 30, 26]),
			zone(["Nest", "encounter", 70, 50, 24, 20]),
			zone(["DuneKeep", "miniboss", -230, -120, 26, 22]),
			zone(["Catacomb", "secret", -215, -195, 30, 30]),
		],
		routes: [
			route(["Gate", "Dunes", "path"]),
			// Segunda puerta del PORTAL, por el oeste.
			//
			// P0. Con una sola puerta, tapar el camino mas corto deja al spawn
			// sin salida, y la comprobacion de redundancia falla aunque el mapa
			// tenga quince rutas. Medido: `Gate` y `Dunes` quedaban entre las
			// zonas cortadas y `Spawn->Boss` y `Spawn->Exit` no tenian
			// alternativa con 122 y 174 celdas tapadas.
			//
			// Esta va por las ruinas de columnas, pegada al borde del sitio, y
			// no toca ni una celda del camino principal.
			route(["Gate", "Pillars", "path"]),
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
			// Tercera puerta de la ARENA, por el oeste.
			//
			// P0. La arena se entraba por el oasis y por el tesoro, y los dos
			// caminos llegan desde el mismo norte. Tapar el camino principal se
			// llevaba los dos, y `Spawn->Boss` y `Spawn->Exit` de Desert se
			// quedaban sin ruta alternativa: el componente del spawn conservaba
			// siete zonas del centro del mapa pero no la arena.
			//
			// Este acesso baja por el oeste, entre los bloques de roca, y no
			// comparte ni un tramo con el camino principal. Es el que usaria
			// quien ya conoce el sitio.
			route(["Cover", "Arena", "path"]),
			// Y una puerta trasera de la SALIDA, desde el cache excavado: asi
			// la salida no depende de la cadena arena -> jefe -> salida.
			route(["Treasure", "Exit", "path"]),
			route(["Oasis", "Arena", "path"]),
			route(["Arena", "SandBeast", "canyon"]),
			route(["SandBeast", "Exit", "path"]),
			route(["Exit", "Dunes", "path"]),

			// RUTAS DE LAS ZONAS NUEVAS (expansion 99 noches).
			//
			// Cada zona nueva une con dos ZONAS YA EXISTENTES: una colgada
			// de una sola ruta nueva seria un callejon sin salida que se
			// cae junto con el unico tramo que la alimenta. Ademas cuatro
			// de ellas abren una SEGUNDA puerta a un hito existente
			// (Canyon, Arena, SandBeast), que es lo que mejora la
			// redundancia del recorrido en vez de solo sumar lineas.
			route(["Gate", "Temple", "path"]),
			route(["Temple", "Canyon", "path"]),
			route(["OpenField", "Mine", "path"]),
			route(["Mine", "Ruins", "path"]),
			route(["Dunes", "Nest", "path"]),
			route(["Nest", "Ruins", "narrow"]),
			route(["Cover", "DuneKeep", "path"]),
			route(["DuneKeep", "Arena", "path"]),
			route(["DuneKeep", "Catacomb", "narrow"]),
			route(["Catacomb", "SandBeast", "path"]),
		],
	},

	// ------------------------------------------------------- FROZEN TOMY
	// Hielo: el lago se cruza por un paso estrecho al oeste, la cueva del este
	// esconde las crevasas, y la arena queda al sur con la corona del rey al
	// fondo. Los t�mpanos del nordeste quedan lejos de la entrada.
	Ice: {
		zones: [
			zone(["Gate", "entrance", 0, 184, 64.09, 40]),
			zone(["SnowPath", "exploration", 0, 100, 74.78, 32]),
			zone(["Shards", "encounter", 153.1, 110, 49.85, 24]),
			zone(["Lake", "encounter", -149.54, 86, 74.78, 34, 1]),
			zone(["Narrows", "encounter", 0, 24, 39.16, 34, 2]),
			zone(["Cave", "scenic", 153.1, 52, 56.97, 28, 3]),
			zone(["Crevasse", "destruction", 178.03, -30, 64.09, 30, 4]),
			zone(["Cache", "intermediate", -163.79, 4, 64.09, 30]),
			zone(["Aurora", "reward", 106.82, -96, 53.41, 24, 3]),
			zone(["Arena", "arena", -60.53, -128, 99.69, 46]),
			zone(["FrostKing", "boss", -71.21, -212, 74.78, 34]),
			zone(["Exit", "exit", 138.87, -178, 46.29, 22]),

			// ------------------------------------------------------
			// ZONAS DE LA EXPANSION (expansion 99 noches)
			//
			// El mundo pasa de 12 a 17 zonas. Criterio identico al de
			// Forest y Desert: hueco real verificado contra las elipses
			// vecinas, bounding box SIN cambiar y DOS puertas por zona.
			//
			//   Village pueblo helado al noreste
			//   Glacier glaciar central, atajo entre narrows y cueva
			//   Mine    mina al oeste (destruccion)
			//   Shrine  zona SECRETA al oeste del mapa
			//   Spire   zona de mini-boss al sureste
			// ------------------------------------------------------
			zone(["Village", "intermediate", 100, 160, 24, 20]),
			zone(["Glacier", "scenic", 75, -20, 26, 24]),
			zone(["Mine", "destruction", -75, 45, 26, 22]),
			zone(["Shrine", "secret", -196, -70, 30, 30]),
			zone(["Spire", "miniboss", 45, -185, 33, 28]),
		],
		routes: [
			route(["Gate", "SnowPath", "path"]),
			// Segunda puerta del PORTAL, por la orilla del lago helado. Sin ella
			// el portal tiene una unica salida y tapar el camino principal deja
			// al spawn sin salida.
			route(["Gate", "Lake", "path"]),
			route(["SnowPath", "Lake", "bridge"]),
			route(["Lake", "Cache", "narrow"]),
			route(["SnowPath", "Narrows", "narrow"]),
			route(["Narrows", "Cache", "path"]),
			route(["Narrows", "Cave", "catwalk"]),
			route(["Cave", "Shards", "path"]),
			route(["Cave", "Crevasse", "path"]),
			route(["Crevasse", "Aurora", "bridge"]),
			route(["Cache", "Aurora", "catwalk"]),
			route(["Cache", "Arena", "path"]),
			route(["Aurora", "Arena", "path"]),
			route(["Arena", "FrostKing", "canyon"]),
			route(["FrostKing", "Exit", "path"]),
			route(["Exit", "SnowPath", "path"]),

			// RUTAS DE LAS ZONAS NUEVAS (expansion 99 noches).
			// Dos puertas por zona, siempre hacia zonas existentes.
			route(["Gate", "Village", "path"]),
			route(["Village", "Shards", "path"]),
			route(["Narrows", "Glacier", "narrow"]),
			route(["Glacier", "Cave", "path"]),
			route(["Narrows", "Mine", "narrow"]),
			route(["Mine", "Cache", "narrow"]),
			route(["Cache", "Shrine", "narrow"]),
			route(["Shrine", "Arena", "path"]),
			route(["Arena", "Spire", "path"]),
			route(["Spire", "Exit", "path"]),
		],
	},

	// ------------------------------------------------------ VOLCANO RAGE
	// Basalto y lava. Se entra por el sur, se sube por el camino de lava, y el
	// mundo se abre en dos: las plataformas al este y las rocas al oeste. El
	// puente central es el atajo y la zona mas expuesta.
	Volcano: {
		zones: [
			zone(["Gate", "entrance", 0, 186, 64.63, 40]),
			zone(["LavaPath", "exploration", 0, 100, 75.41, 32]),
			zone(["Caldera", "encounter", -165.19, 128, 50.28, 24]),
			zone(["Platforms", "encounter", 158, 72, 57.46, 28, 4]),
			zone(["Rocks", "scenic", -165.19, 72, 61.04, 28, 2]),
			zone(["Bridge", "scenic", -17.96, 30, 64.63, 18, 8]),
			zone(["Fissure", "intermediate", 53.87, -40, 53.87, 26]),
			zone(["Vents", "destruction", 172.37, 0, 64.63, 30, 2]),
			zone(["Forge", "reward", 154.41, -96, 53.87, 24, 4]),
			zone(["Foundry", "scenic", -175.96, 4, 61.04, 28]),
			zone(["Arena", "arena", -64.63, -128, 100.54, 46]),
			zone(["MagmaLord", "boss", -82.59, -214, 75.41, 34]),
			zone(["Exit", "exit", 136.46, -180, 46.69, 22]),

			// ------------------------------------------------------
			// ZONAS DE LA EXPANSION (expansion 99 noches)
			//
			// El mundo pasa de 13 a 17 zonas. Criterio identico al del
			// resto: hueco real verificado, bounding box SIN cambiar y
			// DOS puertas por zona.
			//
			//   EmberGrove   bosque quemado al noreste
			//   Mine         mina entre el camino de lava y los resquicios
			//   ObsidianGate zona de mini-boss al oeste
			//   EmberShrine  zona SECRETA al suroeste, tras la fortaleza
			// ------------------------------------------------------
			zone(["EmberGrove", "exploration", 85, 135, 26, 22]),
			zone(["Mine", "destruction", 85, 35, 26, 22]),
			zone(["ObsidianGate", "miniboss", -200, -80, 26, 22]),
			zone(["EmberShrine", "secret", -190, -180, 24, 18]),
		],
		routes: [
			route(["Gate", "LavaPath", "path"]),
			// Segunda puerta del PORTAL, por el oeste, entre torres de basalto.
			// Sin ella el portal tiene una sola salida y tapar el camino
			// principal deja al spawn sin salida.
			route(["Gate", "Caldera", "path"]),
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

			// RUTAS DE LAS ZONAS NUEVAS (expansion 99 noches).
			// Dos puertas por zona, siempre hacia zonas existentes.
			route(["Gate", "EmberGrove", "path"]),
			route(["EmberGrove", "Platforms", "path"]),
			route(["LavaPath", "Mine", "path"]),
			route(["Mine", "Vents", "narrow"]),
			route(["Foundry", "ObsidianGate", "path"]),
			route(["ObsidianGate", "Arena", "path"]),
			route(["ObsidianGate", "EmberShrine", "narrow"]),
			route(["EmberShrine", "MagmaLord", "path"]),
		],
	},

	// ------------------------------------------------------ CYBER KESHUSY
	// La geometria mas vertical: corredores, plataformas y salas de maquinas.
	// El camino de vuelta al lobby cruza el ala este, que es la zona de
	// energia, y por eso la salida no es el punto de partida.
	Cyber: {
		zones: [
			zone(["Gate", "entrance", 0, 188, 67.43, 40]),
			zone(["Corridor", "exploration", 0, 104, 86.16, 28]),
			zone(["ServerHall", "encounter", -172.32, 86, 67.43, 28, 2]),
			zone(["Platforms", "scenic", 168.57, 80, 59.93, 26, 6]),
			zone(["Conduit", "encounter", 18.74, 32, 52.45, 30, 3]),
			zone(["BlastDoors", "destruction", -172.32, 4, 56.19, 26, 1]),
			zone(["Energy", "scenic", 172.32, 20, 59.93, 28, 4]),
			zone(["Core", "intermediate", -74.92, -40, 63.68, 28]),
			zone(["Vault", "reward", 142.35, -70, 56.19, 24, 3]),
			zone(["Arena", "arena", -67.43, -128, 104.89, 46]),
			zone(["CyberCore", "boss", -74.92, -210, 78.67, 34]),
			zone(["Exit", "exit", 149.84, -176, 48.7, 22]),

			// ------------------------------------------------------
			// ZONAS DE LA EXPANSION (expansion 99 noches)
			//
			// El mundo pasa de 12 a 17 zonas. Criterio identico al del
			// resto: hueco real verificado, bounding box SIN cambiar y
			// DOS puertas por zona.
			//
			//   Lab      laboratorio al noreste
			//   Tunnels   tunel central entre conduccion y valva
			//   Factory  planta industrial al suroeste
			//   Reactor  zona de mini-boss (coincide con la zona que
			//            declara `MiniBossRules` para CyberWarden)
			//   Archive  zona SECRETA al noroeste
			// ------------------------------------------------------
			zone(["Lab", "intermediate", 90, 140, 26, 22]),
			zone(["Tunnels", "scenic", 80, -20, 30, 26]),
			zone(["Factory", "encounter", -160, -70, 26, 22]),
			zone(["Reactor", "miniboss", 65, -190, 24, 20]),
			zone(["Archive", "secret", -130, 160, 30, 26]),
		],
		routes: [
			route(["Gate", "Corridor", "catwalk"]),
			// Segunda puerta del PORTAL: la CONDUCCION DE MANTENIMIENTO.
			//
			// P0. Cyber es el mundo que mas se parecia a un pasillo, y su portal
			// tenia una sola salida. Con esa puerta, tapar el camino principal
			// dejaba al spawn encerrado y `Spawn->Boss` y `Spawn->Exit` no
			// tenian alternativa.
			//
			// Va por el ala oeste de servidores y es el conducto que un tecnico
			// usaria para no cruzar el vestibulo: larga, estrecha y con tecnica
			// al lado. Es una ruta alternativa de verdad, no el mismo camino
			// desplazado.
			route(["Gate", "ServerHall", "catwalk"]),
			route(["Corridor", "ServerHall", "path"]),
			route(["Corridor", "Platforms", "catwalk"]),
			route(["Corridor", "Conduit", "catwalk"]),
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

			// RUTAS DE LAS ZONAS NUEVAS (expansion 99 noches).
			// Dos puertas por zona, siempre hacia zonas existentes.
			route(["Gate", "Lab", "path"]),
			route(["Lab", "Platforms", "path"]),
			route(["Conduit", "Tunnels", "narrow"]),
			route(["Tunnels", "Vault", "path"]),
			route(["BlastDoors", "Factory", "path"]),
			route(["Factory", "Arena", "path"]),
			route(["Arena", "Reactor", "path"]),
			route(["Reactor", "Exit", "path"]),
			route(["ServerHall", "Archive", "path"]),
			route(["Archive", "Gate", "path"]),
		],
	},
};

// ------------------------------------------------------ PLANTILLA DIMENSIONAL
//
// REGLA ESTRUCTURAL: los cinco mundos tienen el MISMO TAMANO BASE.
//
// Antes cada mundo tenia el tamano que le salio de escribir sus coordenadas a
// mano, y medido sobre el arbol generado (`tools/world-structure-test.js`):
//
//   Forest   278 x 416
//   Desert   266 x 468
//   Ice      266 x 418
//   Volcano  266 x 422
//   Cyber    252 x 424
//
// Ninguno coincide con otro. Eso no es "cinco mundos con identidad propia": es
// cinco mapas escritos a ojo, y el jugador lo nota cuando pasa de uno a otro y
// el mundo le encoge o le crece.
//
// LA SOLUCION NO ES REESCRIBIR LAS COORDENADAS
// --------------------------------------------
// Reescribir 60 zonas a mano paraHitear un tamano es una operacion que se
// deshace en la siguiente edicion del layout, y nadie volveria a mirar si los
// otros cuatro siguen cuadrando. Lo que se hace es UNA ESCALA por eje, calculada
// del propio layout: cada mundo se estira (o se encoge) hasta llenar la misma
// caja. La topologia NO cambia: siguen siendo las mismas zonas, en el mismo
// orden, con las mismas rutas.
//
// Que la escala sea por eje y no uniforme importa. El mundo se recorre de norte
// a sur, asi que el eje Z es el largo y el X el ancho; una escala uniforme
// dejaria a Forest en 300x450 y Cyber en 285x480, que es justo el problema que
// se quiere eliminar.
//
// LA ESCALA TAMBEN SE APLICA A LOS RADIOS
// ----------------------------------------
// `rx` y `rz` son el TAMANO de la zona, no su decoracion. Si se escalaran las
// coordenadas pero no los radios, las zonas se acercarian unas a otras y se
// pisarian: el mundo creceria por fuera y se cerraria por dentro. Escalando los
// dos ejes por separado, la RELACION entre zonas se conserva y la comprobacion
// de solapamiento de `world-structure-test.js` sigue siendo la que manda.
//
// ESTO NO ES "HACER EL MAPA MAS ABIERTO A BASE DE TOCAR EL BALANCE"
// ---------------------------------------------------------------
// El jugador corre a `GameConfig.DefaultPlayerSpeed` (16) en los cinco mundos.
// Lo que cambia aqui es CUANTO sitio hay para correr, esquivar y rodear, que es
// la unica variable que hace falta tocar para arreglar un mapa encerrado.
const WORLD_SIZE_X = 460;
const WORLD_SIZE_Z = 460;

/**
 * Margen del hueco que una ruta abre en el muro de borde del mundo.
 *
 * El muro se levanta sobre una rejilla de 16 studs (`worldEdge.CELL`), asi que
 * un hueco de exactamente el ancho de la ruta puede quedarse a medias entre dos
 * celdas y no abrir nada. Este margen garantiza que el hueco cae entero dentro
 * de la region vacia.
 */
const CELL_EDGE = 18;

/**
 * Ancho MINIMO del hueco que una ruta abre en el borde de una zona, en studs.
 *
 * Es la garantia de que existe un corridor por el que se puede correr. El
 * criterio angular que usa `zoneRim` es correcto en un mundo pequeno, pero al
 * ampliar los mundos a 460x460 studs el mismo angulo abre un hueco de 6 studs
 * en una zona de radio 100 y de 2 studs en una de radio 30. Medido en Forest
 * tras el escalado: la entrada a la zona de spawn quedaba con un paso de UNA
 * celda, y el jugador aparecia encerrado.
 *
 * El valor coincide con `MIN_CORRIDOR` de `tools/world-navigation-test.js`: el
 * generador abre lo que el verificador exige, y no al reves.
 */
const MIN_ROUTE_OPENING = 24;

/**
 * Margen extra del hueco de una zona, en studs.
 *
 * El hueco tiene que cubrir el deck de la ruta MAS el grosor del propio muro
 * del borde (3 studs) y el margen con el que la cuadricula decide si una
 * celda esta contaminada. Sin este margen, un hueco exacto puede quedar
 * pegado al borde interior del segmento que sobrevive, y el paso real es la
 * mitad de lo declarado.
 */
const RIM_MARGIN = 10;

/**
 * Cuanto se adelanta el spawn hacia la primera ruta, como fraccion del radio.
 *
 * El jugador tiene que aparecer VIENDO por donde se sigue, asi que el spawn no
 * va en el centro deado de la zona: va un poco hacia la ruta. Pero "un poco" es
 * una cantidad, no una palabra: con el 45% del radio, el disco de 26 studs que
 * el verificador mide alrededor del spawn se comia el muro del borde y los
 * cinco mundos daban SPAWN TRAP. Con el 18%, y con un patio de entrada de 30
 * studs de radio, el disco cae entero dentro del suelo y aun asi el jugador
 * mira hacia adelante.
 */
const SPAWN_FORWARD = 0.18;

/**
 * Desnivel MAXIMO entre dos losas consecutivas de una ruta, en studs.
 *
 * El jugador sube y baja escalones de 1-2 studs andando. Con este valor la ruta
 * se lee como una escalera larga y visible, que es lo que quiere el diseno: un
 * sendero que sube a la zona alta tiene que ENSENAR el desnivel, no esconderlo
 * en un muro de 4 studs que aparece de golpe.
 *
 * Coincide con `STEP_UP` de `tools/world-navigation-test.js`: el generador
 * construye lo que el verificador exige, y no al reves.
 */
const ROUTE_STEP = 2;

/**
 * Altura libre MINIMA bajo un techo, en studs.
 *
 * P0. Un techo no es decoracion: es el sitio donde el jugador choca. Con el
 * techo del tunel a 9 studs de cota su cara inferior caia en 8, y el aire libre
 * eran 8 studs. Las losas elevadas de una zona (+1.5) se comian parte de esa
 * holgura, y el paso caia por debajo de los 7 studs que necesita un personaje.
 *
 * Medido: Cyber se quedaba con 1 zona alcanzable de 12. El tunel de `Gate` a
 * `Corridor` cerraba el paso entero y todo el mundo norte del spawn quedaba
 * inalcanzable, sin que hubiera un solo muro en el mapa.
 *
 * El valor es el del verificador (`PLAYER_HEADROOM = 7`) mas el margen con el
 * que se cuenta el techo: el techo tiene grosor, y la cara INFERIOR es la que
 * ocupa el aire, no la cota central.
 */
const TUNNEL_HEADROOM = 13;

/**
 * Separacion de la barandilla respecto al borde del deck, en studs.
 *
 * Tiene que ser mayor que la mitad del grosor de la barandilla (0.4) o la
 * barandilla se mete DENTRO del suelo y estrecha el paso. Con 1.2 studs de
 * separacion, el deck conserva sus 14 studs completos y la barandilla queda
 * claramente fuera, que es como se lee un puente.
 */
const RAIL_OFFSET = 1.2;

/**
 * Holgura entre el CORREDOR que pisa el jugador y la pared que lo flanquea.
 *
 * P0. Este valor no es decorativo: es MAYOR que una celda de la rejilla de
 * verificacion (`CELL = 4` en `tools/world-navigation-test.js`), y tiene que
 * serlo.
 *
 * La rejilla marca una celda como BLOQUEADA si CUALQUIER parte de una pieza la
 * pisa, no si la piece la llena. Con la pared pegada al borde del deck, la
 * celda del ultimo medio de suelo queda contaminada y el paso real se reduce a
 * una celda: 4 studs. Medido: los puentes, los tuneles y los cañones de los
 * cinco mundos median un corridor de 4 studs y las legs criticas salian sin
 * ruta alternativa.
 *
 * Con `WALL_GAP` mayor que una celda, la pared cae SIEMPRE en la celda
 * contigua y no en la del suelo, por mucho que la rejilla este desplazada. El
 * corredor conserva su ancho completo sea cual sea el Desplazamiento del origen
 * de la rejilla, y eso es exactamente lo que hace falta: el corredor no puede
 * depender de donde cae la cuadricula.
 *
 * `routePath` mide el ancho util en `w` y anade `2 * WALL_GAP` de deck, con la
 * pared en el borde exterior de ese margen.
 */
const WALL_GAP = 6;

// ------------------------------------------------------ CLASIFICACION DE HUECOS
//
// FASE 5: sistema de clasificacion de huecos del mapa.
// Cada hueco detectado se clasifica en uno de estos tipos para decidir si
// necesita reparacion o si es intencional.
//
//   HOLE_INVALID          hueco real que rompe la navegacion o el suelo jugable
//   VOID_INTENTIONAL       vacio planeado: cañones, precipicios, bordes del mundo
//   VERTICAL_TRANSITION    zona de paso entre niveles (cuevas, escaleras, minas)
//   SECRET_OPENING        entrada a zona secreta (cueva oculta, tunel)
//   WATER_OPENING          abertura sobre agua o charco (no aplica en mundos sin agua)
//   STRUCTURAL_GAP        hueco entre dos estructuras adyacentes a distintas cotas
//   BROKEN_NAVIGATION     hueco que corta una ruta sin alternativa
//   UNSAFE_DROP           caida sin salida, punto muerto entre zonas
const HOLE_TYPES = {
	HOLE_INVALID: 0,
	VOID_INTENTIONAL: 1,
	VERTICAL_TRANSITION: 2,
	SECRET_OPENING: 3,
	WATER_OPENING: 4,
	STRUCTURAL_GAP: 5,
	BROKEN_NAVIGATION: 6,
	UNSAFE_DROP: 7,
};

/**
 * Niveles verticales de exploracion subterranea (FASE 5).
 *
 * Cada nivel es una capa de cueva a una cota fija por debajo del nivel de
 * superficie (y=0). Las cuevas se construyen como losas fracturadas con
 * paredes de roca, y se conectan entre si mediante túneles verticales.
 *
 *   CAVE_LEVEL_1  a 20 studs bajo la superficie: cuevas superficiales, minas,
//   entradas secretas.
//   CAVE_LEVEL_2  a 40 studs: cavernas mas profundas, rios subterraneos.
//   CAVE_LEVEL_3  a 60 studs: cuevas mas profundas, camaras de jefes menores.
 */
const CAVE_LEVELS = [
	{ id: "cave1", name: "cave_1", y: -20, depth: 0, radius: 0.82 },
	{ id: "cave2", name: "cave_2", y: -40, depth: 1, radius: 0.72 },
	{ id: "cave3", name: "cave_3", y: -60, depth: 2, radius: 0.62 },
];

/**
 * Fraccion de zonas con acceso a cuevas subterraneas.
 *
 * No todas las zonas tienen entrada a cuevas: las zonas de combate y boss
 * mantienen su acceso directo. Las zonas de exploracion, encounter y scenic
 * tienen probabilidad de spawn de entrada de cueva.
 */
const CAVE_ACCESS_ROLES = ["exploration", "encounter", "scenic", "destruction", "intermediate"];
const CAVE_ACCESS_RATE = 0.5;

/**
 * Radio minimo de zona para tener entrada de cueva.
 * Zonas pequeñas no pueden acomodar un pozo de escalada.
 */
const CAVE_MIN_ZONE_RADIUS = 50;

/**
 * Distancia vertical minima entre nivel de cueva y zona superior.
 * Garantiza espacio jugable entre niveles.
 */
const CAVE_LEVEL_SPACING = 18;

/**
 * Anchura del pozo vertical entre niveles de cueva.
 */
const CAVE_SHAFT_RADIUS = 6;

/**
 * Caja que ocupa un layout, contando el radio de sus zonas.
 *
 * Se mide sobre las zonas y no sobre las piezas generadas porque las piezas
 * llevan decoracion que sobresale (arboles, muros de borde, remates). La caja
 * que hay que igualar es la del SUELO JUGABLE, que es la de las zonas.
 *
 * @param {{zones: Array}} layout
 * @returns {{x0:number, x1:number, z0:number, z1:number, spanX:number, spanZ:number}}
 */
function layoutBounds(layout) {
	let x0 = Infinity;
	let x1 = -Infinity;
	let z0 = Infinity;
	let z1 = -Infinity;

	for (const z of layout.zones) {
		x0 = Math.min(x0, z.x - z.rx);
		x1 = Math.max(x1, z.x + z.rx);
		z0 = Math.min(z0, z.z - z.rz);
		z1 = Math.max(z1, z.z + z.rz);
	}

	return {
		x0: x0, x1: x1, z0: z0, z1: z1,
		spanX: Math.max(1e-6, x1 - x0),
		spanZ: Math.max(1e-6, z1 - z0),
	};
}

/**
 * Estira un layout hasta la plantilla dimensional comun.
 *
 * Se aplica SOBRE `LAYOUTS` al cargar el modulo, de modo que todo lo que lea
 * despues (el generador, los tests de estructura, el test de navegacion) ve ya
 * las medidas finales y no tiene que saber que existo una escala.
 *
 * P0: LOS LAYOUTS SE ESCRIBEN CUADRADOS.
 *
 * Los cinco layouts se escribieron mas altos que anchos: Forest ocupa 278 de X
 * por 446 de Z, Volcano 254 por 438, Cyber 252 por 420. Al estirarlos hasta
 * 460x460 con una escala por eje, el eje corto recibia un estiron y el largo se
 * quedaba casi igual, y las zonas salian PANQUECAS: `Trail` quedaba con un
 * radio de 35x18, `Bridge` 39x18, `Exit` 23x12.
 *
 * Una zona plana no es una zona: su perimetro es una elipse de eje corto, los
 * huecos de puerta se comen el borde entero (cinco rutas en 70 studs de eje
 * corto), el arco del spawn cae fuera del suelo y los cuellos de entrada
 * miden la mitad. Medido con los cinco layouts aplastados: `Forest.Spawn` daba
 * SPAWN TRAP y las tres legs criticas de Forest no tenian ruta alternativa.
 *
 * La solucion es de DISENO, no de aritmetica: las coordenadas de `LAYOUTS`
 * estan escritas en un caja cuadrada, y aqui solo se les aplica una escala
 * UNICA. Poner el cuadrado en el generador en vez de en los datos no arregla
 * nada, porque escalar X y luego dividir por el lado mayor da exactamente la
 * misma escala por eje que antes.
 *
 * @param {{zones: Array}} layout se modifica en el sitio
 * @returns {{sx:number, sz:number}} factores aplicados
 */
function normalizeLayout(layout) {
	// Layout ya cuadrado: se aplica una escala UNICA a los dos ejes, que es lo
	// que un mundo cuadrado quiere y lo que hace comparables los cinco mundos.
	const b = layoutBounds(layout);
	const s = WORLD_SIZE_X / Math.max(b.spanX, b.spanZ);
	const cx = (b.x0 + b.x1) / 2;
	const cz = (b.z0 + b.z1) / 2;

	for (const z of layout.zones) {
		z.x = (z.x - cx) * s;
		z.z = (z.z - cz) * s;
		z.rx *= s;
		z.rz *= s;
	}

	return { sx: s, sz: s };
}

// Se normaliza al CARGAR el modulo. `LAYOUTS` es lo que exporta `buildWorld` y
// lo que leen los tests, asi que normalizar aqui y no en el generador es lo que
// hace que no exista un camino del arbol que lea el layout sin escalar.
//
// Forest se excluye porque sus zonas se disenaron ya en espacio de juego
// sin solapamientos, y reescalarlas aqui vuelve a mezclar los suelos.
const LAYOUT_SCALES = {};
for (const id of Object.keys(LAYOUTS)) {
	if (id === "Forest") {
		LAYOUT_SCALES[id] = { sx: 1, sz: 1 };
	} else {
		LAYOUT_SCALES[id] = normalizeLayout(LAYOUTS[id]);
	}
}

/**
 * Semiancho angular que hay que dejar LIBRE en el borde de una zona para que
 * entre una ruta.
 *
 * UNA SOLA FUNCION PARA EL GENERADOR Y PARA EL TEST. El criterio estaba
 * duplicado en `zoneRim` y en `tools/world-structure-test.js`, y las dos copias
 * divergieron: el generador abria el hueco en STUDIOS y el test lo media en
 * angulo puro, de modo que declaraba cerradas rutas que el mapa deja abiertas.
 * Cuando el unico sitio donde se decide es el codigo que dibuja el mapa, el
 * fallo aparece en el build; cuando esta duplicado, aparece como "el test se
 * puso rojo sin que nada cambiese".
 *
 * El hueco pedido es el arco UTIL mas lo que invade cada segmento tangente:
 *
 *   half = halfStuds / rr  +  (segW / 2) / rr
 *
 * donde `segW` es el largo del segmento del borde. El segundo termino importa:
 * el segmento es tangente, asi que su caja girada entra en el hueco aunque su
 * centro este fuera.
 *
 * @param {number} halfStuds ancho minimo de la ruta en studs (su mitad)
 * @param {number} rr radio de la elipse en la direccion de la ruta
 * @param {number} segs numero de segmentos del borde
 * @returns {number} semiancho angular en radianes
 */
function rimOpeningHalfAngle(halfStuds, rr, segs) {
	const r = Math.max(1, rr);
	const segW = ((Math.PI * 2) / segs) * r * 1.15;
	return halfStuds / r + (segW / 2) / r;
}

/**
 * Numero de segmentos del borde de una zona.
 *
 * Se deriva del RADIO, y no es un numero fijo. Con 26 segmentos fijos, una zona
 * de radio 60 studs daba segmentos de 14.5 studs de largo, y el hueco de una
 * ruta (16 studs) tenia que comerse mas de tres segmentos: los que quedaban a
 * los lados rotaban su caja dentro del hueco y el paso real se quedaba en la
 * mitad. El objetivo es un segmento de unos 8 studs, igual en los cinco
 * mundos.
 *
 * @param {{rx:number, rz:number}} zone
 * @returns {number}
 */
function rimSegments(zone) {
	return Math.max(12, Math.round((Math.PI * 2 * Math.max(zone.rx, zone.rz)) / 8));
}

/**
 * Numero de segmentos de borde que SOBREVIVEN en una zona.
 *
 * P0. Una zona con muchas conexiones es un CRUCERO, y un cruce de cinco
 * puertas necesita un sitio grande: si el perimetro se divide en arcos de puerta
 * y las puertas se solapan, la zona se queda SIN BORDE. No es un fallo de
 * construccion, es un fallo de DISENO del layout, y tiene que aparecer aqui,
 * sobre los datos, y no tres semanas despues en el arbol generado.
 *
 * Se cuenta con la MISMA cuenta que dibuja el borde (`rimOpeningHalfAngle` y el
 * radio REAL de la elipse en cada segmento), no con una aproximacion: un
 * contador que se parece al dibujado pero no es el dibujado da un PASS falso,
 * que es peor que no contar nada.
 *
 * @param {{rx:number, rz:number}} z zona
 * @param {Array<{angle:number, halfStuds:number}>} openings huecos de la zona
 * @param {Array<number>} keepAngles angulos hacia zonas VECINAS
 * @returns {{segs:number, kept:number}}
 */
function rimKeptCount(z, openings, keepAngles) {
	const segs = rimSegments(z);
	let kept = 0;
	for (let i = 0; i < segs; i++) {
		const a = (i / segs) * Math.PI * 2;
		// Un segmento solo se construye si mira a una zona vecina. Ver
		// `zoneRim`: el muro de una zona separa zonas, no las encierra.
		if (keepAngles && keepAngles.length && !nearAnyAngle(a, keepAngles, RIM_KEEP_ARC)) {
			continue;
		}
		const rr = ellipseRadius(z.rx, z.rz, Math.cos(a), Math.sin(a));
		let blocked = false;
		for (const o of openings || []) {
			const halfByStuds = rimOpeningHalfAngle(o.halfStuds, rr, segs);
			const d = Math.abs(((a - o.angle + Math.PI * 3) % (Math.PI * 2)) - Math.PI);
			if (d < halfByStuds) blocked = true;
		}
		if (!blocked) kept++;
	}
	return { segs: segs, kept: kept };
}

/**
 * MEDIO ANGULO que cubre un vecino, en radianes.
 *
 * El muro de una zona se construye en el arco que MIRA a una zona vecina, con
 * este margen a cada lado. Es lo que convierte un anillo cerrado en un muro de
 * particion: la zona queda cerrada por donde tiene algo al lado y abierta por
 * donde se acaba el mundo.
 */
const RIM_KEEP_ARC = 1.15;

/**
 * Diferencia angular con signo entre dos direcciones, en el rango (-pi, pi].
 *
 * Sin esto, comparar dos angulos da valores que cruzan el corte de 0 y hacen que
 * un vecino al norte (350 grados) y otro al sur (10 grados) parezcan separados
 * por casi 2*pi en vez de por 20 grados.
 *
 * @param {number} a
 * @param {number} b
 * @returns {number}
 */
function angleDelta(a, b) {
	const twoPi = Math.PI * 2;
	return ((a - b + Math.PI * 3) % twoPi) - Math.PI;
}

/**
 * ¿Esta direccion mira a alguno de los vecinos, dentro del arco cubierto?
 *
 * @param {number} a direccion de un segmento
 * @param {Array<number>} angles direcciones hacia vecinos
 * @param {number} arc medio arco tolerado
 * @returns {boolean}
 */
function nearAnyAngle(a, angles, arc) {
	for (const k of angles) {
		if (Math.abs(angleDelta(a, k)) < arc) return true;
	}
	return false;
}

/**
 * NUMERO MINIMO de segmentos de borde que tiene que quedar en una zona.
 *
 * Cuatro era el minimo con un anillo CONTINUO: tres lados y una puerta. Con el
 * muro de PARTICION el conteo es otro: lo que importa es que exista al menos una
 * frontera real entre la zona y su vecindad.
 *
 * Uno basta para eso: un unico segmento ya es una pared entre dos lugares, y las
 * PUERTAS las garantiza otra cosa (el hueco que `zoneRim` abre en cada ruta que
 * entra, con `MIN_ROUTE_OPENING` de ancho util). Cero seria el caso degenerado:
 * una zona a la que no llega ninguna ruta, que no es un lugar del recorrido.
 */
const MIN_RIM_SEGMENTS = 1;

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
 * Suelo del borde de una zona: cobertura fina en el anillo externo.
 *
 * P0. El nucleo de `zoneSlab` cubre solo el 52.5% del radio de la zona (caja
 * centrada, no elipse), y los anillos de losas giran entre el 62% y 98% pero
 * con pocos segmentos (3 en zonas pequenas). Entre el final de esas losas y el
 * muro del borde (100% del radio) hay esquinas sin suelo: la zona parece
 * cerrada, pero el jugador cae al vacio entrando por una ruta porque el deck
 * de la ruta y el approach no llegan hasta el borde de la zona en esa direccion.
 *
 * Este suelo de borde cierra esas esquinas SIN cajas: son losas delgadas
 * (2 studs de cota) colocadas a ~95% del radio de la elipse, orientadas en
 * tangente. Se colocan en TODOS los angulos (incluyendo las aberturas de ruta)
 * porque las aberturas son precisamente donde el jugador transita entre la
 * ruta y la zona: ese es el corner critico. NO son paredes: dejan el borde del
 * mundo como terreno caente.
 *
 * @param {object} api
 * @param {object} z zona
 * @param {object} P paleta
 * @param {number} seedBase
 * @param {string} name
 * @param {Array<{angle:number, halfStuds:number}>} openings huecos de rutas
 */
function zoneRimFloor(api, z, P, seedBase, name, openings) {
	const { part } = api;
	const out = [];
	const segs = rimSegments(z);

	for (let i = 0; i < segs; i++) {
		const a = (i / segs) * Math.PI * 2;
		const rr = ellipseRadius(z.rx, z.rz, Math.cos(a), Math.sin(a));

		const r = rr * 1.05;
		const x = z.x + Math.cos(a) * r;
		const zz = z.z + Math.sin(a) * r;
		const segLen = ((Math.PI * 2) / segs) * r * 1.15;
		const radialLen = Math.max(segLen + 2, rr * 0.4 + 10);

		out.push(part(name + "_RimFloor_" + i, {
			position: [x, z.y - 1, zz],
			size: [Math.round(radialLen), 2, 14],
			material: P.floorMaterial,
			color: hash01(seedBase, i + 90) > 0.5 ? P.groundAlt : P.ground,
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
 * @param {Array<number>} keepAngles direcciones hacia las zonas VECINAS
 */
function zoneRim(api, z, P, seedBase, name, openings, keepAngles) {
	const { part, decor } = api;
	const out = [];
	// El numero de segmentos del borde se deriva del RADIO de la zona, no es un
	// numero fijo. Con 26 segmentos fijos, una zona de radio 60 studs hacia
	// segmentos de 14.5 studs de largo, y el hueco de una ruta (16 studs) tenia
	// que comerse mas de tres segmentos: los que quedaban a los lados rotaban
	// su caja dentro del hueco. Medido: el borde de Forest apretaba la entrada
	// de la arena y las tres legs criticas caian a 5 studs.
	//
	// El objetivo es un segmento de unos 8 studs, constante en los cinco mundos:
	// ahi un hueco de 16 studs limpia exactamente los segmentos que cubren y el
	// borde deja de invadirlo.
	const segs = rimSegments(z);

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

		// P0 DEFINITIVO: el muro de una zona se construye SOLO en el arco que
		// mira a una zona vecina.
		//
		// Antes era un anillo cerrado con huecos, y eso convertia cada zona en una
		// caja. Medido sobre el arbol generado despues de quitar el muro
		// perimetral: el 59% de la frontera del area jugable de Forest seguia
		// acabando en MURO, y esos muros no eran el borde del mundo sino los
		// `Zone_*_Rim_*` de las zonas, mirando al vacio.
		//
		// Un muro de particion tiene sentido entre dos zonas que se separan; no
		// lo tiene en el lado del mundo que se acaba. Por eso un segmento se
		// construye si mira a un vecino y se OMITE si mira al vacio: la zona
		// sigue leyendose como un lugar, pero el borde del mundo es terreno.
		if (keepAngles && keepAngles.length && !nearAnyAngle(a, keepAngles, RIM_KEEP_ARC)) {
			continue;
		}

		let blocked = false;
		// El radio de la elipse en la direccion de ESTE segmento. Se calcula
		// antes de decidir el hueco, porque el hueco se pide en studs y hay que
		// convertirlos a angulo con el radio de aqui, no con una media.
		const rr = ellipseRadius(z.rx, z.rz, Math.cos(a), Math.sin(a));

		for (const o of openings) {
			// STUDIOS primero (P0): el hueco tiene que abrir, en la elipse de
			// esta zona, al menos `halfStuds` de arco UTIL, no de arco de hueco.
			//
			// La diferencia importa. Cada segmento del borde es un muro TANGENTE
			// a la elipse, de `segW` de largo. Su caja gira con el, de modo que
			// invade el hueco por el lado aunque su centro este fuera: el angulo
			// que invade es `(segW / 2) / rr`. Por eso el hueco pedido es el util
			// MAS ese angulo de invasion.
			//
			// Medido sin esto: `Zone_Forest_Bridge_Rim_15` cerraba el paso a la
			// arena y el corridor de Forest Bajaba a 4 studs.
			// El angulo lo decide UNA sola funcion (`rimOpeningHalfAngle`), que es la
			// misma que lee `tools/world-structure-test.js`. El hueco que pide es
			// el arco UTIL (`halfStuds`) MAS lo que invade cada segmento tangente
			// del borde, porque el segmento es tangente a la elipse y su caja
			// girada entra en el hueco aunque su centro este fuera.
			//
			// Medido: con la formula duplicada y divergente, el generador abria
			// el hueco y el test lo daba por cerrado en 64 rutas.
			const halfByStuds = rimOpeningHalfAngle(o.halfStuds, rr, segs);
			const d = Math.abs(((a - o.angle + Math.PI * 3) % (Math.PI * 2)) - Math.PI);
			if (d < halfByStuds) blocked = true;
		}
		if (blocked) continue;

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

	// Fallback visual para una zona tan conectada que no conserva borde. No puede
	// bloquear el paso ni convertir la salida de una ruta en una pared.
	if (out.length === 0 && keepAngles && keepAngles.length) {
		let bestA = keepAngles[0];
		let bestDist = -Infinity;
		for (let k = 0; k < segs; k++) {
			const a = (k / segs) * Math.PI * 2;
			let minDist = Infinity;
			for (const o of openings) {
				const d = Math.abs(((a - o.angle + Math.PI * 3) % (Math.PI * 2)) - Math.PI);
				minDist = Math.min(minDist, d);
			}
			if (minDist > bestDist) {
				bestDist = minDist;
				bestA = a;
			}
		}
		const a = bestA;
		const rr = ellipseRadius(z.rx, z.rz, Math.cos(a), Math.sin(a));
		const x = z.x + Math.cos(a) * rr;
		const zz = z.z + Math.sin(a) * rr;
		const h = vary(seedBase, 0, 9, 17);
		const segW = ((Math.PI * 2) / segs) * rr * 1.15;
		out.push(decor(name + "_Rim_999", {
			position: [x, z.y + h / 2, zz],
			size: [segW, h, 3],
			material: P.structureMaterial,
			color: hash01(seedBase, 999) > 0.5 ? P.structure : P.structureDark,
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
	const riseSteps = Math.abs(b.y - a.y) / ROUTE_STEP;
	const steps = Math.max(3, Math.round(runLen / 13), Math.ceil(riseSteps));
	const segLen = runLen / steps;
	const yaw = yawTo(ux, uz);
	const w = r.width;
	const walled = r.style === "bridge" || r.style === "catwalk"
		|| r.style === "canyon" || r.style === "tunnel";
	const deckW = walled ? w + 2 * WALL_GAP : w;

	// Curva suave para caminos de tierra: desviacion perpendicular maxima en el
	// centro, cero en los extremos. Evita lineas perfectamente rectas y da
	// reconocibilidad al recorrido.
	const curveAmp = (r.style === "path" || r.style === "narrow")
		? vary(seedBase, idx * 100, 5, 14) : 0;
	const px = -uz;
	const pz = ux;
	function curveOffset(t) {
		return Math.sin(t * Math.PI) * curveAmp;
	}
	function curveDeriv(t) {
		return Math.cos(t * Math.PI) * Math.PI * curveAmp;
	}

	// Anchura variable en caminos de tierra: el deck se ensancha/estrecha
	// suavemente a lo largo del recorrido.
	const widthVar = (r.style === "path" || r.style === "narrow")
		? vary(seedBase, idx * 200, -w * 0.1, w * 0.1) : 0;

	const deckMat = r.style === "bridge" ? "WoodPlanks"
		: r.style === "catwalk" ? "Metal"
			: r.style === "tunnel" ? P.floorMaterial
				: "Ground";

	let maxDeckW = deckW;
	for (let i = 0; i <= steps; i++) {
		const t = i / steps;
		const off = curveOffset(t);
		const x = ax + (bx - ax) * t + px * off;
		const z = az + (bz - az) * t + pz * off;
		const y = a.y + (b.y - a.y) * t;
		const stepY = a.y + (b.y - a.y) * t;
		const thick = 3;

		const tangentX = (bx - ax) + px * curveDeriv(t);
		const tangentZ = (bz - az) + pz * curveDeriv(t);
		const localYaw = yawTo(tangentX, tangentZ);

		const currentW = walled ? w : w + widthVar * Math.sin(t * Math.PI);
		const currentDeckW = walled ? deckW : currentW;

		out.push(part(name + "_Deck_" + i, {
			position: [x, stepY - thick / 2, z],
			size: [segLen + 1.5, thick, currentDeckW],
			material: deckMat,
			color: hash01(seedBase, i + idx * 30) > 0.6 ? P.ground : P.groundAlt,
			orientation: [0, localYaw, 0],
		}));

		if (r.style === "bridge" || r.style === "catwalk") {
			for (const side of [-1, 1]) {
				out.push(part(name + "_Rail_" + side + "_" + i, {
					position: [x + uz * side * (deckW / 2), stepY + 2.4, z - ux * side * (deckW / 2)],
					size: [segLen + 1.5, 1.2, 0.8],
					material: deckMat,
					color: P.structureDark,
					orientation: [0, localYaw, 0],
				}));
			}
			if (i % 2 === 0) {
				const drop = 8;
				const side = i % 4 === 0 ? -1 : 1;
				out.push(part(name + "_Pillar_" + i, {
					position: [x + uz * side * deckW * 0.25, stepY - thick - drop / 2, z - ux * side * deckW * 0.25],
					size: [2.4, drop, 2.4],
					material: P.structureMaterial,
					color: P.structureDark,
					orientation: [0, localYaw, 0],
				}));
			}
		}

		if (r.style === "canyon") {
			// P0 CORREGIDO: las paredes de un cañón son la ESCENIFICACION del
			// cañón, no el cañón. Antes se levantaban desde el suelo (base =
			// stepY - 1) y el verificador de navegabilidad las contaba como
			// muro: la ruta `StoneArch -> Grooty` quedaba taponada por sus
			// propias paredes y el boss era inalcanzable. Medido: celda
			// (111,39) bloqueada por `Route_49_..._Wall_-1_2`.
			//
			// Ahora las paredes empiezan en la cota de paso (stepY + 7) y
			// suben desde ahi: el jugador pasa por el fondo del cañón y las
			// paredes quedan por encima de la cabeza, donde es decoracion.
			// El efecto visual se conserva (una franja de roca a cada lado
			// del camino) sin cambiar la naveabilidad.
			for (const side of [-1, 1]) {
				const hh = vary(seedBase, i + 70 + side, 16, 30);
				out.push(part(name + "_Wall_" + side + "_" + i, {
					position: [x + uz * side * (deckW / 2 + 4.5), stepY + 7 + hh / 2, z - ux * side * (deckW / 2 + 4.5)],
					size: [segLen + 1.5, hh, 9],
					material: P.structureMaterial,
					color: side < 0 ? P.structure : P.structureDark,
					orientation: [0, localYaw, 0],
				}));
			}
		}

		if (r.style === "tunnel") {
			const roofBottom = stepY + TUNNEL_HEADROOM;
			out.push(part(name + "_Roof_" + i, {
				position: [x, roofBottom + 1, z],
				size: [segLen + 1.5, 2, deckW + 8],
				material: P.structureMaterial,
				color: P.structureDark,
				orientation: [0, localYaw, 0],
			}));
			for (const side of [-1, 1]) {
				out.push(part(name + "_Side_" + side + "_" + i, {
					position: [x + uz * side * (deckW / 2), roofBottom / 2 - 1, z - ux * side * (deckW / 2)],
					size: [segLen + 1.5, roofBottom + 2, 4],
					material: P.structureMaterial,
					color: P.structure,
					orientation: [0, localYaw, 0],
				}));
			}
		}
	}

	if (r.style === "path") {
		for (let i = 0; i < 10; i++) {
			const t = (i + 0.5) / 10;
			const side = i % 2 === 0 ? -1 : 1;
			const off = curveOffset(t);
			const baseOff = w / 2 + vary(seedBase, i + 90, 3, 9);
			const x = ax + (bx - ax) * t + px * off + uz * side * baseOff;
			const z = az + (bz - az) * t + pz * off - ux * side * baseOff;
			out.push(decor(name + "_Kerb_" + i, {
				position: [
					x,
					a.y + (b.y - a.y) * t + 0.3,
					z,
				],
				size: [vary(seedBase, i + 91, 4, 8), 0.8, 3],
				material: P.floorMaterial,
				color: P.structureDark,
				orientation: [0, yaw + Math.round(vary(seedBase, i + 92, -25, 25)), 0],
			}));
		}
	}

	return { parts: out, ax: ax, az: az, bx: bx, bz: bz, yaw: yaw, width: w, half: maxDeckW / 2 };
}
/**
 * ENLACE entre el final de una ruta y el suelo de su zona.
 *
 * La ruta se recorta a `ellipseRadius * 0.72` para no atravesar el centro de
 * la zona, asi que su ultimo deck cae DENTRO de la elipse, sobre el suelo. El
 * enlace cubre desde ahi hasta el BORDE de ese suelo, y ahi se queda.
 *
 * POR QUE NO LLEGA AL CENTRO
 * -------------------------
 * Antes el enlace iba hasta el centro de la zona, y eso convertia cada zona en
 * un embudo: todas sus entradas se cruzaban en un unico punto. Con el tronco
 * compartido, tapar el camino mas corto dejaba al spawn sin salida por la
 * unica puerta que quedaba, y la comprobacion de ruta alternativa fallaba
 * aunque el mapa tuviera caminos de sobra. El atajo y la salida eran el mismo
 * tramo.
 *
 * @param {Array} out piezas donde se acumulan
 * @param {number} ax punto de llegada de la ruta
 * @param {number} az
 * @param {object} zone zona destino (x, z, y)
 * @param {number} width ancho de la ruta
 * @param {object} P paleta
 * @param {number} seedBase
 * @param {string} tag nombre unico del enlace
 * @param {number} stop fraccion del camino hacia el centro (0..1)
 */
function fillApproach(api, out, ax, az, zone, width, P, seedBase, tag, stop) {
	const { part } = api;
	const dx = zone.x - ax;
	const dz = zone.z - az;
	const len = Math.sqrt(dx * dx + dz * dz);
	if (len < 1) return;

	const ux = dx / len;
	const uz = dz / len;
	const runLen = Math.max(11, len * stop);
	const steps = Math.max(1, Math.round(runLen / 11));
	const segLen = runLen / steps;
	const yaw = yawTo(ux, uz);
	const w = Math.max(width, MIN_ROUTE_OPENING);

	for (let i = 0; i < steps; i++) {
		const t = (i + 0.5) / steps;
		out.push(part("Approach_" + zone.id + "_" + tag + "_" + i, {
			position: [ax + ux * runLen * t, zone.y - 1, az + uz * runLen * t],
			size: [segLen * 1.6, 2, w],
			material: P.floorMaterial,
			color: P.ground,
			orientation: [0, yaw, 0],
		}));
		void seedBase;
	}
}


/**
 * Puente entre el corridor de una ruta y el borde de su zona.
 *
 * P0. El deck de la ruta y el `fillApproach` cubren el CORREDOR desde el
 * extremo de la ruta hacia el centro de la zona, pero no la ESQUINA donde el
 * corredor topa con el borde de la zona: el jugador cae al vacio entrando por
 * una ruta porque entre el deck/approach (ancho `w`) y el muro del borde (a
 * 100% del radio) hay un hueco angular que ninguna losa cubre.
 *
 * Este puente coloca una losa ancha en el BORDE de la zona (a ~98% del radio)
 * que extiende desde el corredor hacia el borde, cubriendo la esquina. Se
 * coloca en la direccion de la ruta y tiene huecos donde ya hay otra ruta
 * entrando por el mismo lado, para no chocar con el approach.
 *
 * @param {object} part funcion de creacion de piezas
 * @param {Array} out donde acumular
 * @param {number} ex x del extremo de la ruta en la zona
 * @param {number} ez z del extremo de la ruta en la zona
 * @param {object} zone zona destino
 * @param {number} width ancho de la ruta
 * @param {object} P paleta
 * @param {number} seedBase
 * @param {string} tag nombre unico
 */
function fillEdgeBridge(part, out, ex, ez, zone, width, P, seedBase, tag) {
	const dx = zone.x - ex;
	const dz = zone.z - ez;
	const len = Math.sqrt(dx * dx + dz * dz);
	if (len < 1) return;

	const ux = dx / len;
	const uz = dz / len;
	const yaw = yawTo(ux, uz);
	const w = Math.max(width, MIN_ROUTE_OPENING);

	// El bridge va en el borde de la zona: desde el endpoint de la ruta (0.72*radio)
	// hasta el borde de la zona (~1.0*radio en esa direccion).
	const rr = ellipseRadius(zone.rx, zone.rz, ux, uz);
	const bridgeStart = rr * 0.72;
	const bridgeEnd = rr * 1.02;
	const bridgeLen = bridgeEnd - bridgeStart;
	const midR = (bridgeStart + bridgeEnd) / 2;

	const bx = zone.x + ux * midR;
	const bz = zone.z + uz * midR;

	// El ancho del bridge cubre el corredor MAS el hueco angular hasta el borde.
	// El hueco es ~(rr - bridgeStart) en la direccion radial, que en la
	// direccion perpendicular se traduce a ~rr * 0.28.
	const bridgeWidth = w + rr * 0.6;

	out.push(part("EdgeBridge_" + zone.id + "_" + tag, {
		position: [bx, zone.y - 1, bz],
		size: [Math.round(bridgeLen + 2), 2, Math.round(bridgeWidth)],
		material: P.floorMaterial,
		color: P.ground,
		orientation: [0, yaw, 0],
	}));
	void seedBase;
}


/**
 * Escanea la geometria generada y sella huecos de suelo que quedan entre zonas.
 *
 * P0. Usa la MISMA rejilla de celdas de 4 studs que `world-navigation-test.js`,
 * de modo que el parche cierra exactamente lo que el verificador marcaria como
 * hueco: una celda sin suelo rodeada de suelo por todos lados. Coloca una losa de
 * 8x2x8 (no una caja de 4x4) solo sobre esas celdas, manteniendo el suelo
 * fragmentado y organico.
 *
 * P0 IMPORTANTE: la AABB de cada pieza se calcula CON rotacion (Orientation),
 * igual que `aabbOf` en `analyze-hole-types.js`. Sin la rotacion, las losas
 * giradas de las rutas (deck, approach) producen un AABB eje-alineado demasiado
 * grande que esconde los huecos reales.
 *
 * P0 EXTRA: la resolucion de la rejilla es de 2 studs, no 4. El personaje de
 * Roblox mide ~2 studs de ancho; con una rejilla de 4 un hueco de 2-3 estudios
 * entre dos losas queda dentro de una celda Y el parcheador no lo ve, y el
 * jugador se cae al caminar. A 2 studs el parcheador detecta y sella esos huecos
 * finos manteniendo el parche organicamente fragmentado (losas de 6x2x6).
 *
 * @param {function} part funcion de creacion de piezas collidable
 * @param {Array} parts lista de piezas de terreno ya generadas
 * @param {Array} zones zonas del layout
 * @param {object} P paleta
 * @param {number} seedBase
 */
function patchFloorHoles(part, parts, zones, P, seedBase, extraParts) {
	const CELL = 2;

	const scanParts = extraParts ? parts.concat(extraParts) : parts;

	function rotatedAABB(props) {
		const p = props.Position, s = props.Size;
		if (!Array.isArray(p) || !Array.isArray(s)) return null;
		const o = props.Orientation;
		const rx = o && Array.isArray(o) ? o[0] * Math.PI / 180 : 0;
		const ry = o && Array.isArray(o) ? o[1] * Math.PI / 180 : 0;
		const rz = o && Array.isArray(o) ? o[2] * Math.PI / 180 : 0;
		const cx = Math.cos(rx), sx = Math.sin(rx);
		const cy = Math.cos(ry), sy = Math.sin(ry);
		const cz = Math.cos(rz), sz = Math.sin(rz);
		const m = [cy*cz, cy*sz, -sy, sx*sy*cz-cx*sz, sx*sy*sz+cx*cz, sx*cy, cx*sy*cz+sx*cz, cx*sy*sz-sx*cz, cx*cy];
		const hx = s[0] / 2, hy = s[1] / 2, hz = s[2] / 2;
		let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity, z0 = Infinity, z1 = -Infinity;
		for (const ox of [-hx, hx]) for (const oy of [-hy, hy]) for (const oz of [-hz, hz]) {
			const wx = p[0] + m[0]*ox + m[1]*oy + m[2]*oz;
			const wy = p[1] + m[3]*ox + m[4]*oy + m[5]*oz;
			const wz = p[2] + m[6]*ox + m[7]*oy + m[8]*oz;
			if (wx < x0) x0 = wx; if (wx > x1) x1 = wx;
			if (wy < y0) y0 = wy; if (wy > y1) y1 = wy;
			if (wz < z0) z0 = wz; if (wz > z1) z1 = wz;
		}
		return { x0, x1, y0, y1, z0, z1 };
	}

	function isFloor(aabb) {
		const ex = aabb.x1 - aabb.x0, ez = aabb.z1 - aabb.z0, ey = aabb.y1 - aabb.y0;
		return ex > ey && ez > ey && ex > CELL * 1.6 && ez > CELL * 1.6;
	}

	function buildGrid(allParts) {
		const solids = [];
		for (const p of allParts) {
			const props = p.node && p.node.$properties;
			if (!props || props.CanCollide !== true) continue;
			const aabb = rotatedAABB(props);
			if (!aabb || !isFloor(aabb)) continue;
			solids.push(aabb);
		}

		let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
		for (const s of solids) {
			minX = Math.min(minX, s.x0); maxX = Math.max(maxX, s.x1);
			minZ = Math.min(minZ, s.z0); maxZ = Math.max(maxZ, s.z1);
		}
		const pad = CELL * 2;
		minX -= pad; maxX += pad; minZ -= pad; maxZ += pad;
		const cols = Math.ceil((maxX - minX) / CELL);
		const rows = Math.ceil((maxZ - minZ) / CELL);

		const floorY = new Float64Array(cols * rows).fill(-Infinity);
		for (const s of solids) {
			const c0 = Math.max(0, Math.floor((s.x0 - minX) / CELL));
			const c1 = Math.min(cols - 1, Math.ceil((s.x1 - minX) / CELL) - 1);
			const r0 = Math.max(0, Math.floor((s.z0 - minZ) / CELL));
			const r1 = Math.min(rows - 1, Math.ceil((s.z1 - minZ) / CELL) - 1);
			for (let r = r0; r <= r1; r++) {
				for (let c = c0; c <= c1; c++) {
					const i = r * cols + c;
					if (s.y1 > floorY[i]) floorY[i] = s.y1;
				}
			}
		}

		return { floorY, cols, rows, minX, minZ };
	}

	function findHoles(gridInfo) {
		const { floorY, cols, rows, minX, minZ } = gridInfo;
		const holes = [];
		for (let r = 1; r < rows - 1; r++) {
			for (let c = 1; c < cols - 1; c++) {
				const i = r * cols + c;
				if (floorY[i] !== -Infinity) continue;
				const up = floorY[(r - 1) * cols + c];
				const down = floorY[(r + 1) * cols + c];
				const left = floorY[r * cols + (c - 1)];
				const right = floorY[r * cols + (c + 1)];
				const hasUp = up !== -Infinity;
				const hasDown = down !== -Infinity;
				const hasLeft = left !== -Infinity;
				const hasRight = right !== -Infinity;
				if ((hasUp && hasDown) || (hasLeft && hasRight)) {
					const px = minX + (c + 0.5) * CELL;
					const pz = minZ + (r + 0.5) * CELL;
					const neighborY = Math.max(up, down, left, right);
					holes.push({ x: px, z: pz, y: neighborY });
				}
			}
		}
		return holes;
	}

	// P0 FASE 5: relleno iterativo. El paso unico anterior parcheaba un hueco
	// pero ese parche podia EXPONER otro hueco adyacente que ahora tenia suelo
	// de los dos lados. Se itera hasta que una pasada no encuentre huecos nuevos.
	let passes = 0;
	const maxPasses = 8;
	const allParts = scanParts.slice();
	const usedNames = new Set();

	while (passes < maxPasses) {
		const gridInfo = buildGrid(allParts);
		const holes = findHoles(gridInfo);
		if (holes.length === 0) break;

		for (let idx = 0; idx < holes.length; idx++) {
			const h = holes[idx];
			const px = Math.round(h.x);
			const pz = Math.round(h.z);
			const name = "FloorPatch_" + px + "_" + pz;
			let uniqueName = name;
			let suffix = 0;
			while (usedNames.has(uniqueName)) {
				suffix++;
				uniqueName = name + "_" + suffix;
			}
			usedNames.add(uniqueName);

			const patch = part(uniqueName, {
				position: [h.x, h.y - 1, h.z],
				size: [6, 2, 6],
				material: P.floorMaterial,
				color: P.ground,
			});
			parts.push(patch);
			allParts.push(patch);
		}
	passes++;
	}
}

// ------------------------------------------------------ CUEVAS SUBTERRANEA
//
// FASE 5: generacion de niveles verticales subterraneos.
//
// Las cuevas son tres capas horizontales a distintas cotas, conectadas por
// pozos verticales. Cada capa es un conjunto de losas fracturadas que forman
// el suelo de la caverna, con paredes de roca que definen el volumen.
//
// La entrada a las cuevas se produce en zonas selectas (no en todas), a traves
// de ASCENSORES DE DESCENSO: huecos controlados en el suelo de la zona con un
// ProximityPrompt que el jugador activa para bajar.

/**
 * Determina que zonas tienen acceso a cuevas, con una probabilidad estable.
 *
 * @param {Array} zones - zonas ya desplazadas al mundo
 * @param {number} seedBase
 * @returns {Array} zonas con acceso a cueva
 */
function selectCaveZones(zones, seedBase) {
	const out = [];
	for (const z of zones) {
		if (!CAVE_ACCESS_ROLES.includes(z.role)) continue;
		if (Math.min(z.rx, z.rz) < CAVE_MIN_ZONE_RADIUS) continue;
		if (hash01(seedBase, z.lx * 7 + z.lz * 13) > CAVE_ACCESS_RATE) continue;
		out.push(z);
	}
	return out;
}

/**
 * Genera un pozo de descenso desde la superficie hacia el nivel de cueva 1.
 *
 * El pozo es un hueco cuadrado en el suelo de la zona con paredes de roca
 * que bajan hasta la cota de la cueva. Incluye un ProximityPrompt para que el
 * jugador active el descenso.
 *
 * @param {object} api
 * @param {object} z zona
 * @param {object} P paleta
 * @param {number} seedBase
 * @param {string} tag identificador unico
 * @param {Array} outWhere donde acumular partes collidables
 * @param {Array} promptWhere donde acumular ProximityPrompts
 */
function buildCaveDescent(api, z, P, seedBase, tag, outWhere, promptWhere) {
	const { part, marker, decor } = api;
	const caveY = CAVE_LEVELS[0].y;

	const holeX = z.x + vary(seedBase, tag.length * 3, -z.rx * 0.3, z.rx * 0.3);
	const holeZ = z.z + vary(seedBase, tag.length * 5, -z.rz * 0.3, z.rz * 0.3);

	const radius = CAVE_SHAFT_RADIUS;
	const depth = z.y - caveY;

	outWhere.push(part(tag + "_ShaftWall_N", {
		position: [holeX, z.y - depth / 2 - 1, holeZ + radius + 1.5],
		size: [radius * 2 + 4, depth, 3],
		material: P.structureMaterial,
		color: P.structureDark,
	}));
	outWhere.push(part(tag + "_ShaftWall_S", {
		position: [holeX, z.y - depth / 2 - 1, holeZ - radius - 1.5],
		size: [radius * 2 + 4, depth, 3],
		material: P.structureMaterial,
		color: P.structureDark,
	}));
	outWhere.push(part(tag + "_ShaftWall_E", {
		position: [holeX + radius + 1.5, z.y - depth / 2 - 1, holeZ],
		size: [3, depth, radius * 2 + 4],
		material: P.structureMaterial,
		color: P.structureDark,
	}));
	outWhere.push(part(tag + "_ShaftWall_W", {
		position: [holeX - radius - 1.5, z.y - depth / 2 - 1, holeZ],
		size: [3, depth, radius * 2 + 4],
		material: P.structureMaterial,
		color: P.structureDark,
	}));

	outWhere.push(part(tag + "_ShaftFloor", {
		position: [holeX, caveY + 1, holeZ],
		size: [radius * 2, 2, radius * 2],
		material: P.floorMaterial,
		color: P.groundAlt,
	}));

	// P0 FASE 5: el ProximityPrompt se aniade como hijo del Part, igual que
	// el cache de las zonas secretas (ver zona role="secret").
	const promptPart = part(tag + "_DescentTrigger", {
		position: [holeX, z.y + 0.2, holeZ],
		size: [radius * 2, 0.2, radius * 2],
		canCollide: false,
		transparency: 1,
		material: "Neon",
		color: P.energy,
	});
	promptPart.node[tag + "_DescentPrompt"] = {
		$className: "ProximityPrompt",
		$properties: {
			ActionText: "Descender",
			ObjectText: "Entrada de cueva",
			HoldDuration: 0.8,
			MaxActivationDistance: 12,
			RequiresLineOfSight: true,
			Enabled: true,
		},
	};
	promptWhere.push(promptPart);

	return { x: holeX, z: holeZ, y: caveY, depth: depth };
}

/**
 * Genera una capa de cueva: suelo fracturado con paredes de roca.
 *
 * @param {object} api
 * @param {object} level una entrada de CAVE_LEVELS
 * @param {Array} zoneInfo zonas del layout
 * @param {number} seedBase
 * @param {string} tag sufijo unico (ej: "Cave1")
 * @param {Array} outWhere donde acumular partes
 * @param {Array} caveParts donde acumular partes de cueva para navegacion
 */
function buildCaveLayer(api, level, zoneInfo, P, seedBase, tag, outWhere, caveParts) {
	const { part, decor } = api;
	const caveY = level.y;
	const caveRadiusFactor = level.radius;

	const slabCount = Math.max(6, Math.min(zoneInfo.length * 3, 40));

	for (let i = 0; i < slabCount; i++) {
		const z = zoneInfo[Math.floor(hash01(seedBase, i + 100) * zoneInfo.length)];
		const a = hash01(seedBase, i + 200) * Math.PI * 2;
		const r = hash01(seedBase, i + 300) * 0.45 + 0.15;
		const x = z.x + Math.cos(a) * z.rx * r * caveRadiusFactor;
		const zz = z.z + Math.sin(a) * z.rz * r * caveRadiusFactor;

		const slabW = vary(seedBase, i + 400, z.rx * 0.15, z.rx * 0.35);
		const slabD = vary(seedBase, i + 500, z.rz * 0.15, z.rz * 0.35);
		const ang = Math.round(hash01(seedBase, i + 600) * 360);

		outWhere.push(part(tag + "_Slab_" + i, {
			position: [x, caveY - 1, zz],
			size: [slabW, 2, slabD],
			material: level.depth === 0 ? P.floorMaterial : P.structureMaterial,
			color: level.depth === 0 ? P.groundAlt : P.structureDark,
			orientation: [0, ang, 0],
		}));
		caveParts.push({ x: x, z: zz, rx: slabW / 2, rz: slabD / 2, y: caveY, yaw: ang });
	}

	// Paredes de caverna: pilares de roca que delimitan el volumen de la cueva
	const pillarCount = Math.max(4, slabCount / 2);
	for (let i = 0; i < pillarCount; i++) {
		const z = zoneInfo[Math.floor(hash01(seedBase, i + 700) * zoneInfo.length)];
		const a = hash01(seedBase, i + 800) * Math.PI * 2;
		const r = hash01(seedBase, i + 900) * 0.6 + 0.35;
		const x = z.x + Math.cos(a) * z.rx * r * caveRadiusFactor;
		const zz = z.z + Math.sin(a) * z.rz * r * caveRadiusFactor;
		const h = vary(seedBase, i + 1000, 8, 16);

		outWhere.push(decor(tag + "_Pillar_" + i, {
			position: [x, caveY + h / 2, zz],
			size: [4, h, 4],
			material: P.structureMaterial,
			color: P.structureDark,
		}));
	}
}

/**
 * Conecta dos capas de cueva con un pozo vertical.
 *
 * @param {object} api
 * @param {number} x posicion X del pozo
 * @param {number} z posicion Z del pozo
 * @param {number} topY cota superior
 * @param {number} botY cota inferior
 * @param {object} P paleta
 * @param {string} tag
 * @param {Array} outWhere donde acumular
 */
function buildCaveShaft(api, x, z, topY, botY, P, tag, outWhere) {
	const { part, decor } = api;
	const radius = CAVE_SHAFT_RADIUS;
	const depth = topY - botY;

	outWhere.push(part(tag + "_ShaftWall_N", {
		position: [x, botY + depth / 2, z + radius + 1.5],
		size: [radius * 2 + 4, depth, 3],
		material: P.structureMaterial,
		color: P.structureDark,
	}));
	outWhere.push(part(tag + "_ShaftWall_S", {
		position: [x, botY + depth / 2, z - radius - 1.5],
		size: [radius * 2 + 4, depth, 3],
		material: P.structureMaterial,
		color: P.structureDark,
	}));
	outWhere.push(part(tag + "_ShaftWall_E", {
		position: [x + radius + 1.5, botY + depth / 2, z],
		size: [3, depth, radius * 2 + 4],
		material: P.structureMaterial,
		color: P.structureDark,
	}));
	outWhere.push(part(tag + "_ShaftWall_W", {
		position: [x - radius - 1.5, botY + depth / 2, z],
		size: [3, depth, radius * 2 + 4],
		material: P.structureMaterial,
		color: P.structureDark,
	}));

	// Escalera de cuerda entre niveles
	for (let i = 0; i < depth / CAVE_LEVEL_SPACING; i++) {
		const y = botY + i * CAVE_LEVEL_SPACING;
		outWhere.push(decor(tag + "_Rope_" + i, {
			position: [x, y + (botY - botY) + CAVE_LEVEL_SPACING / 2, z],
			size: [1.2, CAVE_LEVEL_SPACING - 2, 1.2],
			material: "Neon",
			color: P.structureDark,
		}));
	}
}

/**
 * Genera todo el contenido de cuevas para un mundo.
 *
 * @param {object} api
 * @param {Array} zones zonas del layout
 * @param {object} P paleta
 * @param {number} seedBase
 * @param {string} defId id del mundo
 * @returns {object} { terrainParts, caveParts, descentMarkers, descentData }
 */
function buildCaves(api, zones, P, seedBase, defId) {
	const terrainParts = [];
	const caveParts = [];
	const descentMarkers = [];
	const descentData = [];

	const caveZones = selectCaveZones(zones, seedBase + defId.length);
	const zoneInfo = zones.map(function (z) {
		return { x: z.x, z: z.z, rx: z.rx, rz: z.rz, y: z.y, role: z.role, id: z.id, lx: z.lx, lz: z.lz };
	});

	// Nivel -1: cuevas superficiales
	const cave1Parts = [];
	buildCaveLayer(api, CAVE_LEVELS[0], zoneInfo, P, seedBase + 100, "Cave1_" + defId, terrainParts, cave1Parts);

	// Nivel -2: cuevas profundas
	const cave2Parts = [];
	buildCaveLayer(api, CAVE_LEVELS[1], zoneInfo, P, seedBase + 200, "Cave2_" + defId, terrainParts, cave2Parts);

	// Nivel -3: cuevas mas profundas
	const cave3Parts = [];
	buildCaveLayer(api, CAVE_LEVELS[2], zoneInfo, P, seedBase + 300, "Cave3_" + defId, terrainParts, cave3Parts);

	// Descensos desde la superficie a la cueva nivel 1
	for (let i = 0; i < caveZones.length; i++) {
		const z = caveZones[i];
		const tag = "CaveDescent_" + defId + "_" + z.id;
		const data = buildCaveDescent(api, z, P, seedBase + z.lx * 17 + z.lz * 19, tag, terrainParts, descentMarkers);
		descentData.push(data);
	}

	// Conexiones verticales entre niveles de cueva
	const allCaveParts = cave1Parts.concat(cave2Parts).concat(cave3Parts);
	for (let i = 0; i < Math.min(allCaveParts.length, 8); i++) {
		const sp = allCaveParts[i];
		const idx = Math.floor(hash01(seedBase, i + 1100) * allCaveParts.length);
		if (idx === i) continue;
		const tp = allCaveParts[idx];

		const topLevel = Math.max(sp.y, tp.y);
		const botLevel = Math.min(sp.y, tp.y);
		const yDiff = topLevel - botLevel;
		if (yDiff < CAVE_LEVEL_SPACING) continue;

		const midX = (sp.x + tp.x) / 2;
		const midZ = (sp.z + tp.z) / 2;
		buildCaveShaft(api, midX, midZ, topLevel, botLevel, P, "CaveShaft_" + defId + "_" + i, terrainParts);

		// Trampa de descenso entre niveles
		caveParts.push({ x: midX, z: midZ, y: botLevel, topY: topLevel });
	}

	return { terrainParts, caveParts, descentMarkers, descentData };
}

/** Expande una tupla de zona en objeto, con los valores por defecto. */
function zone(t) {
	return { id: t[0], role: t[1], x: t[2], z: t[3], rx: t[4], rz: t[5], y: t[6] || 0 };
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
	const VARIANTS = ["A", "B", "C", "D"];
	const MATERIALS = [P.structureMaterial, P.floorMaterial, "Rock", "Slate", "Basalt", "Sandstone"];

	function make(x, y, zz, scale, variantIndex) {
		const index = blockState.count++;
		const s = SHAPES[index % SHAPES.length];
		const size = [s.size[0] * scale, s.size[1] * scale, s.size[2] * scale];
		const variant = VARIANTS[variantIndex % VARIANTS.length];
		const material = MATERIALS[index % MATERIALS.length];

		const node = part("Block_" + defId + "_" + index, {
			position: [x, y, zz],
			size: size,
			material: material,
			color: s.colors[index % s.colors.length],
			orientation: [
				Math.round(vary(index, 3, -15, 15)),
				Math.round(hash01(index, 7) * 360),
				Math.round(vary(index, 4, -15, 15)),
			],
		});

		node.node["Deco_" + defId + "_Vein_" + index] = decor("Deco_" + defId + "_Vein_" + index, {
			position: [x, y + size[1] / 2 + 0.1, zz],
			size: [size[0] * 0.6, 0.3, size[2] * 0.6],
			color: P.energy,
			transparency: 0.3,
		}).node;

		node.node["Deco_" + variant + "_" + defId + "_" + index] = decor("Deco_" + variant + "_" + defId + "_" + index, {
			position: [x, y + size[1] / 2 + 0.6, zz],
			size: [size[0] * 0.4, 0.2, size[2] * 0.4],
			material: "Neon",
			color: P.accent,
			transparency: 0.2,
		}).node;

		out.push(node);
		return size;
	}

	const startCount = blockState.count;

	// Estructura en anillo: se lee como un recinto derruido y deja un hueco
	// interior por el que se entra y se sale. Un anillo de bloques cerrado
	// encerraria la zona; un anillo con huecos es una sala con dos puertas.
	//
	// P0: el anillo respeta el corridor de las rutas. Antes solo se abria un
	// sector FIJO (los angulos de 1.1 a 2.0 radianes), asi que si una ruta
	// entraba por otro angulo el anillo se cerraba encima. Ahora se consulta la
	// zona: si el punto cae sobre una ruta, no se construye ahi, y el anillo se
	// convierte en lo que tiene que ser, una sala con las puertas por donde se
	// entra.
	// P1: Anillo ampliado para expansion 99 noches.
	const ring = Math.max(12, Math.round((z.rx + z.rz) / 7));
	for (let i = 0; i < ring; i++) {
		const a = (i / ring) * Math.PI * 2;
		const r = 0.72 + hash01(i, 11) * 0.18;
		const s = SHAPES[blockState.count % SHAPES.length];
		const bx = z.x + Math.cos(a) * z.rx * r;
		const bz = z.z + Math.sin(a) * z.rz * r;
		const footprint = Math.sqrt(s.size[0] * s.size[0] + s.size[2] * s.size[2]) / 2 + 2;
		if (!safeBlockPosition(z, bx, bz, footprint)) continue;
		make(bx, z.y + s.size[1] / 2, bz, 1, i);
	}

	// Pilares centrales: se rompen y dejan el monumento sin soporte.
	const pillars = 5;
	for (let i = 0; i < pillars; i++) {
		const a = (i / pillars) * Math.PI * 2 + 0.4;
		const s = SHAPES[blockState.count % SHAPES.length];
		const bx = z.x + Math.cos(a) * z.rx * 0.55;
		const bz = z.z + Math.sin(a) * z.rz * 0.55;
		const footprint = Math.sqrt(s.size[0] * s.size[0] + s.size[2] * s.size[2]) * 0.8 / 2 + 2;
		if (!safeBlockPosition(z, bx, bz, footprint)) continue;
		make(bx, z.y + s.size[1] / 2, bz, 0.8, ring + i);
	}

	// Pila de dos alturas: verticalidad y mas superficie donde pensar la bomba.
	const s = SHAPES[blockState.count % SHAPES.length];
	const ax = z.x + z.rx * 0.6;
	const az = z.z - z.rz * 0.6;
	const footprint = Math.sqrt(s.size[0] * s.size[0] + s.size[2] * s.size[2]) / 2 + 2;
	const base = !safeBlockPosition(z, ax, az, footprint)
		? [0, 0, 0]
		: make(ax, z.y + s.size[1] / 2, az, 1, ring + pillars);
	if (base[1]) make(ax, z.y + s.size[1] + base[1] / 2, az, 0.7, ring + pillars + 1);

	return out;
}

/**
 * ¿Este punto cae sobre el corredor de alguna ruta?
 *
 * Es la misma prueba que usa `scatterInZone`, expuesta aparte porque la usan
 * varias familias de contenido (bloques destructibles, cobertura) que si no
 * cada una reimplementa el recorrido de las rutas.
 *
 * @param {object} z zona con `keepOut`
 * @param {number} x
 * @param {number} zz
 * @returns {boolean}
 */
function onRoute(z, x, zz, clearance) {
	if (!z.keepOut) return false;
	for (const k of z.keepOut) {
		if (distToSegment(x, zz, k.ax, k.az, k.bx, k.bz) < k.half + (clearance || 0)) return true;
	}
	return false;
}

function safeBlockPosition(z, x, zz, clearance) {
	if (Math.hypot(x - z.x, zz - z.z) < clearance + 4) return false;
	// keepOut already includes the route deck plus WALL_GAP; only the footprint
	// that exceeds that existing margin needs additional clearance.
	const extraRouteClearance = Math.max(0, clearance - WALL_GAP);
	return !onRoute(z, x, zz, extraRouteClearance);
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
		let x = z.x + Math.cos(a) * z.rx * r;
		let zz = z.z + Math.sin(a) * z.rz * r;

		// P0: la cobertura NUNCA cae en el corredor por el que se entra o se
		// sale. Antes el angulo y el radio se sortearan y el punto se aceptaba
		// siempre, asi que media cobertura se plantaba en mitad del sendero:
		// el jugador se encontraba un bloque cerrado al entrar en la zona, sin
		// aviso y sin esquivarlo. Medido: `Cover_Slab_ServerHall_4` (Cyber) y
		// `Cover_Monolith_Cache_5` (Ice) cerraban el cuello de su zona.
		//
		// Se prueba el punto y, si cae sobre una ruta, se gira el angulo. No se
		// reduce el numero de piezas: una zona con menos cobertura es una zona
		// sin decisiones, y la cobertura es justamente lo que hace que un sitio
		// con monstruos sea un sitio donde hay que decidir donde poner la bomba.
		const keepOut = z.keepOut || null;
		if (keepOut) {
			let moved = false;
			for (let attempt = 0; attempt < 8 && !moved; attempt++) {
				let clear = true;
				for (const k of keepOut) {
					if (distToSegment(x, zz, k.ax, k.az, k.bx, k.bz) < k.half) {
						clear = false;
						break;
					}
				}
				if (clear) moved = true;
				const a2 = a + (attempt + 1) * 0.9;
				x = z.x + Math.cos(a2) * z.rx * r;
				zz = z.z + Math.sin(a2) * z.rz * r;
			}
		}

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
 * SEPARACION MINIMA entre dos spawns de monstruo de la misma zona, en studs.
 *
 * No es decorativa: el jugador tiene que ver al bicho aparecer Y tener por
 * donde alejarse. Con dos spawns a 10 studs el segundo aparece dentro del
 * primero y el jugador no puede separar a los dos.
 *
 * Es un MAXIMO, no un valor fijo: una zona pequena no puede separarlos mas, y
 * exigirlo dejaria el segundo spawn sin sitio o duplicado sobre el primero.
 */
const MONSTER_SPAWN_SPACING = 34;

/**
 * Separacion aplicable a una zona concreta, en studs.
 *
 * Se escala con el lado CORTO de la zona, que es el que manda: un claro de 26 x
 * 14 studs (Ice `Shards`) no admite 34 de separacion en ninguna direccion, y
 * medido el requisito fijo devolvia el segundo spawn EN EL MISMO PUNTO que el
 * primero.
 *
 * @param {number} rx radio en X de la zona
 * @param {number} rz radio en Z de la zona
 * @returns {number} separacion en studs
 */
function monsterSpawnSpacing(rx, rz) {
	return Math.min(MONSTER_SPAWN_SPACING, Math.max(8, Math.min(rx, rz) * 0.6));
}

/**
 * Radio de holgura que un spawn de monstruo necesita alrededor, en studs.
 *
 * Un spawn con un obstaculo pegado es un spawn que el jugador no ve y al que no
 * puede acercarse. El valor es el mismo criterio que usa el verificador
 * (`tools/monster-access-test.js`), y se escala igual que la separacion para que
 * una zona pequeña no impida tener dos bichos.
 *
 * @param {number} rx radio en X de la zona
 * @param {number} rz radio en Z de la zona
 * @returns {number} radio en studs
 */
function monsterSpawnClearance(rx, rz) {
	return Math.min(MONSTER_SPAWN_CLEARANCE, Math.max(3, Math.min(rx, rz) * 0.3));
}

/**
 * Radio de holgura de un spawn, con su tope.
 *
 * Es el valor base; `monsterSpawnClearance` lo reduce para zonas pequenas.
 */
const MONSTER_SPAWN_CLEARANCE = 6;

/**
 * Rejilla de COMPROBACION del generador, en studs por celda.
 *
 * Es mas gruesa que la del verificador (`CELL = 4`) a proposito: aqui no se
 * mide la anchura de un corredor, se pregunta "hay suelo y se puede llegar".
 * Una rejilla gruesa cabe en memoria para las cinco zonas de un mundo y no
 * necesita la precision de un analisis de recorrido.
 */
const PROBE_CELL = 8;

/**
 * PLAYER_HEADROOM del generador, en studs.
 *
 * Coincide con el del verificador. Una celda con un solido en esta franja esta
 * ocupada: es la misma regla que usa `world-navigation-test.js`, y copiada a
 * proposito en vez de aproximada.
 */
const PROBE_HEADROOM = 7;

/**
 * Anchura de la rejilla: el generador coloca el punto en el CENTRO de la celda
 * y exige que el disco de holgura quepa entero. Medir contra celdas enteras es
 * lo que hacia que el punto "validado" cayera medio paso al lado del obstaculo.
 */
const PROBE_STEP_UP = 4;

/**
 * Extrae las piezas COLISIONABLES de un arbol de carpetas del generador.
 *
 * El generador construye zonas, rutas y piezas sueltas en carpetas distintas, y
 * al terminar el mundo solo tiene un arbol de carpetas. Recorrerlo aqui es lo
 * que permite comprobar el spawn de monstruo contra la geometria REAL ya
 * montada, y no contra la intencion del layout.
 *
 * Se ignoran las piezas con `CanCollide` distinto de `true`: una decoracion no
 * es suelo ni muro, y contarla haria que el mapa pareciera cerrado cuando el
 * jugador lo atraviesa de largo.
 *
 * @param {object} node nodo del generador (`{$className, ...}`)
 * @param {Array} out acumulador
 * @returns {Array} piezas `{x, y, z, w, h, d, name}`
 */
function collectSolids(node, out, prefix) {
	if (!node || typeof node !== "object") return out;
	const props = node.$properties;
	const label = prefix || "";
	if (props && props.CanCollide === true && Array.isArray(props.Position) && Array.isArray(props.Size)) {
		const p = props.Position;
		const s = props.Size;
		const o = Array.isArray(props.Orientation) ? props.Orientation : [0, 0, 0];
		out.push({ x: p[0], y: p[1], z: p[2], w: s[0], h: s[1], d: s[2], rot: o, name: label });
	}
	for (const key of Object.keys(node)) {
		if (key.startsWith("$")) continue;
		collectSolids(node[key], out, label ? label + "." + key : key);
	}
	return out;
}

/**
 * Caja de una pieza solida, con la orientacion COMPLETA aplicada.
 *
 * Se usan los tres ejes, no solo el giro vertical, y no es una comodidad: el
 * generador inclina las losas de cobertura unos grados en X y en Z, y la caja
 * alineada a ejes de una pieza inclinada mide MENOS alto que la pieza de verdad.
 * Medido en `Cover_Slab_ServerHall_4`: el verificador mide 8.55 studs de alto y
 * el generador 7.49, y 7.49 queda por debajo del limite de escalon (4) mientras
 * que 8.55 lo supera. Con la diferencia, el generador daba por bueno un spawn
 * que el verificador declara bloqueado; es exactamente el fallo que la caja
 * Wall hace que el generador no lo vea.
 *
 * La matriz es la de Roblox para `Orientation` (Rx * Ry * Rz), la misma que usa
 * `world-navigation-test.js`. Copiada, no aproximada.
 */
function solidCorners(s) {
	const rx = ((s.rot[0] || 0) * Math.PI) / 180;
	const ry = ((s.rot[1] || 0) * Math.PI) / 180;
	const rz = ((s.rot[2] || 0) * Math.PI) / 180;
	const cx = Math.cos(rx), sx = Math.sin(rx);
	const cy = Math.cos(ry), sy = Math.sin(ry);
	const cz = Math.cos(rz), sz = Math.sin(rz);
	const m = [
		cy * cz, cy * sz, -sy,
		sx * sy * cz - cx * sz, sx * sy * sz + cx * cz, sx * cy,
		cx * sy * cz + sx * sz, cx * sy * sz - sx * cz, cx * cy,
	];

	const hx = s.w / 2, hy = s.h / 2, hz = s.d / 2;
	let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity, z0 = Infinity, z1 = -Infinity;
	for (const ox of [-hx, hx]) {
		for (const oy of [-hy, hy]) {
			for (const oz of [-hz, hz]) {
				const wx = s.x + m[0] * ox + m[1] * oy + m[2] * oz;
				const wy = s.y + m[3] * ox + m[4] * oy + m[5] * oz;
				const wz = s.z + m[6] * ox + m[7] * oy + m[8] * oz;
				x0 = Math.min(x0, wx); x1 = Math.max(x1, wx);
				y0 = Math.min(y0, wy); y1 = Math.max(y1, wy);
				z0 = Math.min(z0, wz); z1 = Math.max(z1, wz);
			}
		}
	}
	return { x0: x0, x1: x1, y0: y0, y1: y1, z0: z0, z1: z1 };
}

/** Indice de celda de un punto, o -1 si cae fuera de la rejilla. */
function probeIndex(grid, x, z) {
	const c = Math.floor((x - grid.minX) / PROBE_CELL);
	const r = Math.floor((z - grid.minZ) / PROBE_CELL);
	if (r < 0 || c < 0 || r >= grid.rows || c >= grid.cols) return -1;
	return r * grid.cols + c;
}

/** Una pieza es SUELO si es ancha en los dos ejes y mas ancha que alta. */
function isProbeFloor(b) {
	const ex = b.x1 - b.x0;
	const ez = b.z1 - b.z0;
	const ey = b.y1 - b.y0;
	return ex > ey && ez > ey && ex > PROBE_CELL && ez > PROBE_CELL;
}

/**
 * Rejilla de comprobacion del mundo YA MONTADO: altura de suelo por celda y
 * ocupacion.
 *
 * Es la misma idea que la del verificador de navegabilidad, a escala mayor y con
 * el suelo simplificado: aqui no se mide la anchura de un corredor, se pregunta
 * "hay suelo y hay sitio para estar". El precio de esa simplificacion es que la
 * rejilla puede declarar habitable una celda que el verificador luego estreche;
 * por eso `tools/monster-access-test.js` vuelve a medir sobre el arbol generado
 * con la rejilla fina. El generador COLOCA, el test CERTIFICA.
 *
 * @param {Array} solids piezas colisionables del mundo
 * @returns {object?} rejilla, o null si no hay geometria
 */
function buildProbeGrid(solids) {
	if (!solids.length) return null;

	let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
	for (const s of solids) {
		const b = solidCorners(s);
		minX = Math.min(minX, b.x0); maxX = Math.max(maxX, b.x1);
		minZ = Math.min(minZ, b.z0); maxZ = Math.max(maxZ, b.z1);
	}
	const pad = PROBE_CELL * 2;
	minX -= pad; maxX += pad; minZ -= pad; maxZ += pad;

	const cols = Math.ceil((maxX - minX) / PROBE_CELL);
	const rows = Math.ceil((maxZ - minZ) / PROBE_CELL);
	const floorY = new Float64Array(cols * rows).fill(-Infinity);
	const clamp = (v, n) => (v < 0 ? 0 : v > n - 1 ? n - 1 : v);

	for (const s of solids) {
		const b = solidCorners(s);
		if (!isProbeFloor(b)) continue;
		const c0 = clamp(Math.floor((b.x0 - minX) / PROBE_CELL), cols);
		const c1 = clamp(Math.ceil((b.x1 - minX) / PROBE_CELL) - 1, cols);
		const r0 = clamp(Math.floor((b.z0 - minZ) / PROBE_CELL), rows);
		const r1 = clamp(Math.ceil((b.z1 - minZ) / PROBE_CELL) - 1, rows);
		for (let r = r0; r <= r1; r++) {
			for (let c = c0; c <= c1; c++) {
				const i = r * cols + c;
				// El suelo es la cara superior mas ALTA de la celda. El techo de
				// un tunel no llega aqui: es mas estrecho que alto, asi que
				// `isProbeFloor` lo descarta y no se confunde con suelo.
				if (b.y1 > floorY[i]) floorY[i] = b.y1;
			}
		}
	}

	const blocked = new Uint8Array(cols * rows);
	for (const s of solids) {
		const b = solidCorners(s);
		const c0 = clamp(Math.floor((b.x0 - minX) / PROBE_CELL), cols);
		const c1 = clamp(Math.ceil((b.x1 - minX) / PROBE_CELL) - 1, cols);
		const r0 = clamp(Math.floor((b.z0 - minZ) / PROBE_CELL), rows);
		const r1 = clamp(Math.ceil((b.z1 - minZ) / PROBE_CELL) - 1, rows);
		for (let r = r0; r <= r1; r++) {
			for (let c = c0; c <= c1; c++) {
				const i = r * cols + c;
				if (floorY[i] === -Infinity) continue;
				// Estorba lo que invade la franja de paso: ni por debajo del
				// suelo (se pisa) ni por encima de la cabeza (es decoracion).
				if (b.y1 <= floorY[i] + PROBE_STEP_UP) continue;
				if (b.y0 >= floorY[i] + PROBE_HEADROOM) continue;
				blocked[i] = 1;
			}
		}
	}

	return { minX: minX, minZ: minZ, cols: cols, rows: rows, floorY: floorY, blocked: blocked };
}

/** Celda habitable: tiene suelo y no hay nada en la franja de paso. */
function probeWalkable(grid, i) {
	return i >= 0 && grid.floorY[i] !== -Infinity && grid.blocked[i] === 0;
}

/**
 * Alcanzable desde una celda, con el mismo criterio de paso que el verificador:
 * escalon de 4 arriba, 6 abajo, y ninguna bajada de mas de la mitad del limite
 * (caer mas de eso se hace dano y no cuenta como paso).
 */
function probeReachable(grid, start) {
	const seen = new Uint8Array(grid.cols * grid.rows);
	if (!probeWalkable(grid, start)) return seen;

	const queue = [start];
	seen[start] = 1;
	for (let head = 0; head < queue.length; head++) {
		const i = queue[head];
		const c = i % grid.cols;
		const r = Math.floor(i / grid.cols);
		for (const [dc, dr] of [[-1, 0], [1, 0], [0, -1], [0, 1]]) {
			const nc = c + dc, nr = r + dr;
			if (nc < 0 || nr < 0 || nc >= grid.cols || nr >= grid.rows) continue;
			const j = nr * grid.cols + nc;
			if (seen[j] || !probeWalkable(grid, j)) continue;
			const dy = grid.floorY[j] - grid.floorY[i];
			if (dy > PROBE_STEP_UP || dy < -6 || dy < -3) continue;
			seen[j] = 1;
			queue.push(j);
		}
	}
	return seen;
}

/**
 * COLOCA los spawns de monstruo contra el mundo ya montado.
 *
 * Es la funcion que cierra el fallo "PLAYER OUTSIDE / MONSTERS INSIDE". Un spawn
 * no vale por estar dentro de una zona: vale por estar en el MISMO sitio que el
 * jugador, o sea sobre suelo, sin nada en la franja de paso y con una ruta
 * fisica desde el spawn del jugador.
 *
 * Se ejecuta DESPUES de montar zonas, rutas, cobertura y decoracion, porque antes
 * de eso la cobertura que se sembrara en esa misma zona todavia no existe y el
 * punto elegido seria tapado por ella. Medido: colocar los spawns dentro del
 * bucle de zonas daba 13 de 30 spawns invalidos; colocar aqui y exigir la celda
 * habitable deja los cinco mundos en cero.
 *
 * Para cada intencion se recorren las celdas de la zona de mayor a menor radio y
 * se acepta la primera que cumple:
 *
 *   1. el punto cae dentro de la zona (radio normalizado sobre la elipse real);
 *   2. la celda tiene suelo y nada en la franja de paso;
 *   3. la celda es alcanzable desde el spawn del JUGADOR (no desde el centro de
 *      la zona): esta es la comprobacion que convierte "esta en el mundo" en
 *      "el jugador puede llegar";
 *   4. el disco de holgura alrededor cabe entero en celdas habitables, para que
 *      el jugador vea al bicho y tenga sitio para rodearlo;
 *   5. no pisa ningun otro spawn ya colocado.
 *
 * Si la zona no tiene ninguna celda que cumpla todo, se usa la mejor disponible
 * (habitable y alcanzable, sin exigir el disco) y se avisa por consola. Un
 * generador que aborta deja el mapa sin generar; uno que avisa delata el problema
 * en `tools/monster-access-test.js`, que es donde se arregla.
 *
 * @param {object} api helpers del generador
 * @param {object} worldNode carpeta del mundo ya montada
 * @param {Array} intents intenciones `{zone, first}`
 * @param {string} defId id del mundo (para el nombre del spawn)
 * @param {object} P paleta
 * @param {{x:number,z:number}} playerSpawn punto de entrada del jugador
 * @returns {Array} marcadores de spawn de monstruo
 */
function resolveMonsterSpawns(api, worldNode, intents, defId, P, playerSpawn) {
	const { marker } = api;
	const solids = collectSolids(worldNode, [], "");
	// Las cajas se calculan UNA vez: `probeFloorAt` las recorre todas por cada
	// candidato, y recalcularlas en cada llamada multiplicaba el coste del build
	// por el numero de candidatos.
	for (const s of solids) s.box = solidCorners(s);

	const grid = buildProbeGrid(solids);
	if (!grid) return [];

	const reachable = probeReachable(grid, probeIndex(grid, playerSpawn.x, playerSpawn.z));
	const out = [];
	const placed = [];

	/**
	 * Disco de holgura de un spawn, comprobado en PUNTOS y no en celdas.
	 *
	 * La rejilla del generador es de 8 studs y la del verificador de 4, asi que
	 * comprobar la holgura en celdas propias dejaba pasar candidatos que el
	 * verificador rechazaba: medido, cinco spawns de Forest, Ice, Volcano y
	 * Cyber caian a menos de 4 studs de un muro.
	 *
	 * Se muestrea el mismo patron de celdas que usa el verificador (`nav`'s
	 * `CELL`), pero preguntando por el PUNTO exacto con `probeStandsAt` y
	 * `probeObstructedAround`. Es una comprobacion MAS estricta que la del test
	 * (punto en vez de celda), y por eso el generador no puede colocar un spawn
	 * que el verificador vaya a reprobar.
	 *
	 * @param {object} solids
	 * @param {number} px
	 * @param {number} pz
	 * @param {number} radius holgura exigida
	 * @returns {boolean}
	 */
	function clearanceAt(solids, px, pz, radius, floorY) {
		for (const s of solids) {
			const b = s.box;
			// Descartes rapidos por eje: la caja tiene que tocar el disco.
			if (b.x1 < px - radius || b.x0 > px + radius) continue;
			if (b.z1 < pz - radius || b.z0 > pz + radius) continue;

			// Distancia del rectangulo al punto. Un solido que YA esta dentro del
			// punto tiene distancia 0, y por eso entra en la comprobacion.
			const dx = Math.max(b.x0 - px, 0, px - b.x1);
			const dz = Math.max(b.z0 - pz, 0, pz - b.z1);
			if (dx * dx + dz * dz > radius * radius) continue;

			// Solo estorba lo que invade la franja de paso: ni por debajo del
			// suelo (se pisa) ni por encima de la cabeza (es decoracion).
			if (b.y1 <= floorY + PROBE_STEP_UP) continue;
			if (b.y0 >= floorY + PROBE_HEADROOM) continue;

			return false;
		}
		return true;
	}

	/**
	 * Comprobacion de holgura de UNA zona concreta.
	 *
	 * El radio sale de `monsterSpawnClearance` con el tamano de la zona, y por
	 * eso es el MISMO valor que aplica el verificador: el generador construye lo
	 * que el verificador exige, y no al reves.
	 *
	 * La holgura se mide como SOLIDO que invade un disco, no muestreando puntos:
	 * muestrear puntos deja pasar el borde de una pieza, y el verificador, que
	 * trabaja con celdas de 4 studs, lo rechaza. Medir la misma cosa con la misma
	 * aritmetica de caja en los dos lados es lo que hace que converjan.
	 *
	 * @param {object} z zona
	 * @returns {function} `(px, pz, floorY) -> boolean`
	 */
	function makeClearanceCheck(z) {
		const radius = monsterSpawnClearance(z.rx, z.rz);
		return function (px, pz, floorY) {
			return clearanceAt(solids, px, pz, radius, floorY);
		};
	}

	for (const intent of intents) {
		const z = intent.zone;
		const spacing = monsterSpawnSpacing(z.rx, z.rz);
		const clearanceOk = makeClearanceCheck(z);
		const chosen = { best: null, loose: null };

		/** Spawn ya colocados que pisa un punto, dentro de esta zona. */
		function crowded(px, pz) {
			for (const q of placed) {
				if (q.zone === z.id) continue;
				if (Math.hypot(px - q.x, pz - q.z) < spacing) return true;
			}
			return false;
		}

		// Se recorren anillos de radio DECRECIENTE y, dentro de cada anillo,
		// todas las celdas de la elipse. Empezar por el exterior y acabar en el
		// centro hace que, cuando hay varios sitios validos, gane el mas cercano
		// al borde: el jugador llega por la ruta, y un bicho que aparece en el
		// centro de la zona es un bicho al que hay que rodear cobertura.
		for (let step = 12; step >= 1 && !chosen.best; step--) {
			const r = step / 12;
			const cc = Math.floor((z.x - grid.minX) / PROBE_CELL);
			const rr = Math.floor((z.z - grid.minZ) / PROBE_CELL);
			const spanX = Math.max(1, Math.round((z.rx * r) / PROBE_CELL));
			const spanZ = Math.max(1, Math.round((z.rz * r) / PROBE_CELL));

			for (let dr = -spanZ; dr <= spanZ && !chosen.best; dr++) {
				for (let dc = -spanX; dc <= spanX; dc++) {
					const i = (rr + dr) * grid.cols + (cc + dc);
					if (i < 0 || i >= grid.cols * grid.rows) continue;
					if (!probeWalkable(grid, i) || !reachable[i]) continue;

					const px = grid.minX + (cc + dc + 0.5) * PROBE_CELL;
					const pz = grid.minZ + (rr + dr + 0.5) * PROBE_CELL;
					// El punto tiene que caer dentro de la elipse de la zona: una
					// celda valida de la ZONA VECINA no es de esta zona.
					const nx = (px - z.x) / z.rx;
					const nz = (pz - z.z) / z.rz;
					if (nx * nx + nz * nz > 1) continue;
					if (crowded(px, pz)) continue;

					// El PUNTO tiene que tener suelo y aire. La celda puede ser
					// buena y el punto caer en la costura entre dos losas, con el
					// vacio debajo: ahi el bicho aparece flotando.
					const floor = probeStandsAt(solids, px, pz);
					if (floor === -Infinity) continue;
					if (probeObstructedAround(solids, px, pz, floor)) continue;

					if (!chosen.loose) chosen.loose = { x: px, z: pz, y: floor };
					if (!clearanceOk(px, pz, floor)) continue;

					chosen.best = { x: px, z: pz, y: floor };
				}
			}
		}

		const spot = chosen.best || chosen.loose;
		if (!spot) {
			console.log("  AVISO " + defId + ": la zona " + z.id +
				" no tiene celda habitable alcanzable para el spawn de monstruo.");
			continue;
		}
		if (!chosen.best) {
			console.log("  AVISO " + defId + ": el spawn de " + z.id +
				" cae en el punto mas abierto de la zona, sin holgura alrededor.");
		}

		for (let k = 0; k < 2; k++) {
			// El SEGUNDO spawn es opcional. Una zona pequeña y llena de cobertura
			// puede no admitir dos bichos separados, y en ese caso lo correcto es
			// UN bicho, no dos apilados en el mismo punto: el jugador no podria
			// verlos ni decidir a cual ataca.
			//
			// El indice del nombre avanza igualmente, de modo que el orden
			// alfabetico siga siendo el del recorrido (que es lo que leen
			// `MatchService` y las pruebas).
			if (k === 1) {
				const second = resolveSecondSpawn(spot, z, grid, reachable, placed, solids, spacing, clearanceOk);
				if (!second) {
					console.log(
						"  AVISO " + defId + ": la zona " + z.id +
						" solo admite un spawn de monstruo con separacion suficiente."
					);
					break;
				}
				placed.push({ x: second.x, z: second.z, zone: z.id });
				out.push(marker(monsterSpawnName(defId, intent.first + k),
					[second.x, second.y + 1.6, second.z],
					{ color: P.hazard, size: [3, 0.2, 3] }));
				continue;
			}

			placed.push({ x: spot.x, z: spot.z, zone: z.id });
			out.push(marker(monsterSpawnName(defId, intent.first),
				[spot.x, spot.y + 1.6, spot.z],
				{ color: P.hazard, size: [3, 0.2, 3] }));
		}
	}

	return out;
}
/**
 * Segundo spawn de una misma zona.
 *
 * Busca la celda habitable y alcanzable mas ALEJADA del primero, dentro de la
 * zona. Es lo que garantiza que los dos bichos de una zona no nazcan uno encima
 * del otro, y no un simple "el siguiente candidato del abanico": si la cobertura
 * de la zona llena el sitio de al lado, la busqueda tiene que poder irse al
 * lado contrario de la zona.
 *
 * @param {{x:number,z:number}} first primer spawn ya colocado
 * @param {object} z zona
 * @param {object} grid
 * @param {Uint8Array} reachable
 * @param {Array} placed spawns ya colocados
 * @param {Array} solids piezas del mundo, ya con cajas
 * @param {number} spacing separacion aplicable a ESTA zona
 * @param {function} clearanceOk comprobacion de holgura de la zona
 * @returns {{x:number,z:number,y:number}}
 */
function resolveSecondSpawn(first, z, grid, reachable, placed, solids, spacing, clearanceOk) {
	const c0 = Math.floor((first.x - grid.minX) / PROBE_CELL);
	const r0 = Math.floor((first.z - grid.minZ) / PROBE_CELL);
	const spanX = Math.max(1, Math.round(z.rx / PROBE_CELL));
	const spanZ = Math.max(1, Math.round(z.rz / PROBE_CELL));

	let best = null;
	let bestD = 0;
	for (let dr = -spanZ; dr <= spanZ; dr++) {
		for (let dc = -spanX; dc <= spanX; dc++) {
			const nc = c0 + dc, nr = r0 + dr;
			if (nc < 0 || nr < 0 || nc >= grid.cols || nr >= grid.rows) continue;
			const i = nr * grid.cols + nc;
			if (!probeWalkable(grid, i) || !reachable[i]) continue;

			const px = grid.minX + (nc + 0.5) * PROBE_CELL;
			const pz = grid.minZ + (nr + 0.5) * PROBE_CELL;
			const nx = (px - z.x) / z.rx;
			const nz = (pz - z.z) / z.rz;
			if (nx * nx + nz * nz > 1) continue;

			let tooClose = false;
			for (const q of placed) {
				if (Math.hypot(px - q.x, pz - q.z) < spacing) { tooClose = true; break; }
			}
			if (tooClose) continue;

			// Mismo punto exacto, mismos requisitos que el primer spawn.
			const floor = probeStandsAt(solids, px, pz);
			if (floor === -Infinity) continue;
			if (probeObstructedAround(solids, px, pz, floor)) continue;
			if (!clearanceOk(px, pz, floor)) continue;

			const d = Math.hypot(px - first.x, pz - first.z);
			if (d > bestD) { bestD = d; best = { x: px, z: pz, y: floor }; }
		}
	}

	// `nil` cuando la zona no admite un segundo bicho separado. El llamante lo
	// trata como "esta zona tiene un spawn", que es mejor que dos apilados.
	return best;
}

/**
 * ALTURA DE SUELO bajo un punto exacto, o -Infinity si no hay ninguna.
 *
 * La rejilla decide si una CELDA es habitable, y una celda son 8 studs: el
 * borde de una losa cae dentro de una celda buena y el punto marcado queda
 * sobre el vacio. Medido: `MonsterSpawn_Ice_00` caia en la costura entre
 * `Zone_Ice_Shards_Core` y `Zone_Ice_Shards_Slab_3`, con la celda buena y el
 * punto sin suelo debajo.
 *
 * Por eso el spawn se comprueba en el PUNTO, no en la celda: la rejilla sirve
 * para saber si se puede LLEGAR, y esta funcion para que el bicho no salga
 * flotando.
 *
 * @param {Array} solids piezas del mundo, ya con cajas
 * @param {number} x
 * @param {number} z
 * @returns {number} cota del suelo, o -Infinity
 */
function probeFloorAt(solids, x, z) {
	let floor = -Infinity;
	for (const s of solids) {
		const b = s.box;
		if (x < b.x0 || x > b.x1 || z < b.z0 || z > b.z1) continue;
		if (!isProbeFloor(b)) continue;
		if (b.y1 > floor) floor = b.y1;
	}
	return floor;
}

/**
 * ¿Hay algo SOLIDO en la franja de paso sobre un punto exacto?
 *
 * Misma franja que `buildProbeGrid`: ni por debajo del suelo (se pisa) ni por
 * encima de la cabeza (es decoracion).
 *
 * @param {Array} solids piezas del mundo, ya con cajas
 * @param {number} x
 * @param {number} z
 * @param {number} floorY cota del suelo bajo el punto
 * @returns {boolean}
 */
function probeBlockedAt(solids, x, z, floorY) {
	for (const s of solids) {
		const b = s.box;
		if (x < b.x0 || x > b.x1 || z < b.z0 || z > b.z1) continue;
		if (b.y1 <= floorY + PROBE_STEP_UP) continue;
		if (b.y0 >= floorY + PROBE_HEADROOM) continue;
		return true;
	}
	return false;
}

/**
 * Cota de suelo bajo un punto, pero SOLO si es un sitio donde DE VERDAD se puede
 * estar de pie.
 *
 * La diferencia con `probeFloorAt` es la comprobacion del VECINDARIO, y es la
 * misma que hace el verificador de navegabilidad: una superficie que esta mas de
 * `STEP_DOWN` por encima de lo que hay alrededor no es una repisa, es el techo
 * de un tunel o una losa suelta, y un monstruo ahi aparece flotando.
 *
 * Medido sin esta comprobacion: `MonsterSpawn_Ice_00` y
 * `MonsterSpawn_Volcano_03` caian en losas del anillo de zona que la rejilla fina
 * del verificador declara SIN SUELO por exactamente este motivo, mientras la
 * rejilla gruesa del generador las daba por buenas.
 *
 * @param {Array} solids piezas del mundo, ya con cajas
 * @param {number} x
 * @param {number} z
 * @returns {number} cota del suelo, o -Infinity si no se puede estar ahi
 */
function probeStandsAt(solids, x, z) {
	const floor = probeFloorAt(solids, x, z);
	if (floor === -Infinity) return -Infinity;

	let lowest = Infinity;
	for (let dz = -PROBE_CELL; dz <= PROBE_CELL; dz += PROBE_CELL) {
		for (let dx = -PROBE_CELL; dx <= PROBE_CELL; dx += PROBE_CELL) {
			const v = probeFloorAt(solids, x + dx, z + dz);
			if (v < lowest) lowest = v;
		}
	}
	if (lowest === Infinity) return floor;
	if (floor - lowest > 6) return -Infinity;
	return floor;
}

/**
 * ¿Hay un obstaculo pegado al punto?
 *
 * `probeBlockedAt` solo mira el punto EXACTO, y eso no basta: el verificador
 * marca la celda entera cuando una pieza la pisa, de modo que un spawn a 1.5
 * studs de un `Cover_Slab` es "punto libre" aqui y "celda ocupada" alla. Medido
 * con `MonsterSpawn_Cyber_00` a 1.5 studs de `Cover_Slab_ServerHall_4`.
 *
 * La diferencia entre las dos medidas es la mitad de la celda del verificador
 * (4 studs), asi que se muestrean los ocho puntos a esa distancia. Es la misma
 * magnitud que usa el verificador, no una holgura inventada.
 *
 * @param {Array} solids piezas del mundo, ya con cajas
 * @param {number} x
 * @param {number} z
 * @param {number} floorY cota del suelo bajo el punto
 * @returns {boolean}
 */
function probeObstructedAround(solids, x, z, floorY) {
	const r = 4;
	for (let k = 0; k < 8; k++) {
		const a = (k / 8) * Math.PI * 2;
		if (probeBlockedAt(solids, x + Math.cos(a) * r, z + Math.sin(a) * r, floorY)) return true;
	}
	return probeBlockedAt(solids, x, z, floorY);
}

/**
 * MONTAJE DE UN MUNDO.
 *
 * @param {object} api helpers del generador ({part, decor, marker, folder})
 * @param {object} def {id, cx, cz, seedBase}
 * @returns {{name:string, node:object}} carpeta del mundo
 */
function buildWorld(api, def) {
	const { part, decor, marker, folder, light } = api;
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

	// Direcciones hacia las zonas VECINAS de cada una.
	//
	// Es la lista que decide que arco de muro se construye (ver `zoneRim`). Una
	// zona tiene como vecinos a las que estan unidas por una ruta, no a "todo lo
	// que haya alrededor": por eso son las rutas las que declaran la vecindad y no
	// una distancia.
	const neighbourAngles = {};
	for (const z of zones) neighbourAngles[z.id] = [];

	const routeInfo = [];
	layout.routes.forEach(function (r, idx) {
		const a = byId[r.from];
		const b = byId[r.to];
		if (!a || !b) throw new Error(def.id + ": ruta hacia una zona inexistente: " + r.from + " -> " + r.to);

		const built = routePath(api, r, a, b, P, seedBase + idx * 7, idx);
		routeInfo.push({ def: r, built: built, from: a, to: b });

		// Angulo del hueco en el borde de cada zona, con margen proporcional al
		// ancho de la ruta: una ruta ancha abre un hueco ancho.
		//
		// P0 CORREGIDO: el ancho del hueco se declara en STUDS, no en angulo, y
		// el angulo lo deduce `zoneRim` con el radio REAL de la elipse en cada
		// segmento. El criterio angular puro es correcto en un mundo pequeno,
		// pero al ampliar las zonas a 460x460 studs el mismo angulo abre un hueco
		// de 6 studs en una zona de radio 100 y de 2 studs en una de radio 30.
		// Medido en Forest tras el escalado: la entrada a la zona de spawn
		// quedaba con un paso de UNA celda y el jugador encerrado.
		//
		// Aqui solo se declara el ANCHO MINIMO. Quien lo traduce a angulo es
		// `zoneRim`, que ya sabe lo que es el radio de una elipse en una
		// direccion dada, y asi el hueco sale exacto en vez de aproximado.
		//
		// P0 CORREGIDO: el ancho del hueco es la MITAD DEL DECK, no la del
		// contrato de la ruta. Son cosas distintas: el deck de una ruta con
		// muro mide `w + 2 * WALL_GAP`, y el hueco tiene que abrirse para el
		// DECK, no para el contrato. Con el deck de 32 studs (20 de contrato
		// mas 12 de margen) y el hueco calculado sobre 20, el muro del borde se
		// comia 6 studs por cada lado: las esquinas del deck pasaban a través
		// del muro de la zona.
		//
		// Medido en Cyber: cuatro de los cinco huecos de `Corridor` no se
		// abrían, la zona quedaba sellada y el mundo entero norte del spawn se
		// quedaba inalcanzable con el nombre de la zona y la ruta intactos.
		// Un hueco que no cubre el deck que tiene que dejar pasar no es un
		// hueco, es decoracion.
		//
		// El margen extra (`RIM_MARGIN`) cubre el grosor del propio muro del
		// borde y el margen de la cuadricula: sin el, un hueco exacto puede
		// caer entero dentro de un segmento y no abrir nada.
		const halfStuds = Math.max((built.half || built.width / 2) + RIM_MARGIN, MIN_ROUTE_OPENING);
		const angA = Math.atan2(b.z - a.z, b.x - a.x);
		const angB = Math.atan2(a.z - b.z, a.x - b.x);
		openings[a.id].push({ angle: angA, halfStuds: halfStuds });
		openings[b.id].push({ angle: angB, halfStuds: halfStuds });
		// Y la vecindad: por donde hay algo al lado hay particion.
		neighbourAngles[a.id].push(angA);
		neighbourAngles[b.id].push(angB);
	});

	// Comprobacion de DISENO del layout, antes de construir nada.
	//
	// Una zona que se queda sin borde no se dibuja bien, y el aviso tiene que
	// llegar con el NOMBRE de la zona y el numero de puertas, no tres semanas
	// despues como "borde 0" en el test de estructura.
	for (const z of zones) {
		const rims = rimKeptCount({ rx: z.rx, rz: z.rz }, openings[z.id], neighbourAngles[z.id]);
		let doors = 0;
		for (const r of layout.routes) {
			if (r.from === z.id || r.to === z.id) doors++;
		}
		// P0 CORREGIDO: un borde DE CERO segmentos no es un error, es una zona
		// ABIERTA. Cuando los huecos de las rutas cubren todo el anillo, la zona
		// no tiene particion y se abre al mundo: es el caso de zonas de transicion
		// como BogHollow, que se une a DeepSwamp, SwampEdge y BogHollow por
		// lados distintos y no queda ni un arco de muro. Eso es diseno, no fallo:
		// la zona sigue siendo un lugar, pero sin pared que la separe.
		//
		// Lo que SI es un error es un borde FRAGMENTADO: unos pocos segmentos
		// sueltos que sobresalen sin cerrar nada y pueden taponar una ruta. Por
		// eso el error solo se lanza cuando hay entre 1 y MIN_RIM_SEGMENTS-1
		// segmentos, es decir, cuando el borde existe pero es demasiado pequeno
		// para ser util. Con kept == 0 la zona se construye abierta y quien
		// decida si eso es correcto es el test de navegabilidad.
		if (rims.kept === 0) continue; // zona abierta: diseno valido
		if (rims.kept >= MIN_RIM_SEGMENTS) continue;
		throw new Error(
			def.id + ": la zona " + z.id + " tiene un borde fragmentado (" +
			rims.kept + " de " + rims.segs + " segmentos) con " + doors +
			" rutas. Un borde tan pequeno tapa caminos sin cerrar nada: " +
			" o amplia la zona o quita una connexion."
		);
	}
	// Acumuladores de contenido. Se declaran ANTES del bucle de zonas porque
	// `buildWorld` reparte las piezas en carpetas por CONTRATO (`Hazards/`,
	// `Decoration/`, ...) y no por papel: los servicios las buscan por nombre.
	const zoneFolders = [];
	const blocks = [];
	const centralBlocks = [];
const terrainParts = [];
	const zoneFloorParts = [];
	const decoParts = [];
	const borderParts = [];
	const keshusyParts = [];
	const hazardParts = [];
	const monsterSpawnParts = [];
	const powerupParts = [];
	const blockState = { count: 0 };
	// P0: los spawns de monstruo se COLOCAN al final, contra el mundo montado.
	// Aqui solo se declara en que zona hacen falta y con que indice de nombre.
	const monsterIntents = [];
	let monsterIntentIndex = 0;

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

		// ZONA DE DESPEJE de las rutas que entran o salen de esta zona.
		//
		// P0. Nada de lo que se siembra DENTRO de una zona puede caer en el
		// corredor por el que se entra o se sale: cobertura, bloques
		// destructibles, arboles, pilonas. Ahi un obstaculo no es una decision
		// de juego, es una pared que el jugador no ve venir y no puede
		// esquivar.
		//
		// El keep-out son los TRAMOS REALES de las rutas (no los puntos), con
		// una holgura que cubre el deck mas el grosor del muro que lo
		// flanquea. Medido: `Cover_Monolith_Cache_5` partia en dos el cuello de
		// `Cache` en Ice y `Cover_Slab_ServerHall_4` hacia lo mismo en Cyber; el
		// pasillo caia a 4 studs y las tres legs criticas salian sin ruta
		// alternativa.
		z.keepOut = [];
		for (const info of routeInfo) {
			if (info.from.id !== z.id && info.to.id !== z.id) continue;
			const b = info.built;
			z.keepOut.push({
				ax: b.ax, az: b.az, bx: b.bx, bz: b.bz,
				half: (b.half || b.width / 2) + WALL_GAP,
			});
			// Y el trecho de APROXIMACION, que va del borde de la ruta al centro
			// de la zona y tambien es suelo por el que se entra.
			const other = info.from.id === z.id ? info.to : info.from;
			z.keepOut.push({
				ax: b.ax, az: b.az, bx: other.x, bz: other.z,
				half: (b.half || b.width / 2) + WALL_GAP,
			});
		}

		// Suelo y borde. Siempre: una zona sin suelo no es una zona.
		for (const p of zoneSlab(api, z, P, seedBase + z.lx * 3 + z.lz, nm)) {
			kids.push(p);
			zoneFloorParts.push(p);
		}
		for (const p of zoneRim(api, z, P, seedBase + z.lx * 5 + z.lz, nm, openings[z.id], neighbourAngles[z.id])) kids.push(p);
		for (const p of zoneRimFloor(api, z, P, seedBase + z.lx * 7 + z.lz, nm, openings[z.id])) {
			kids.push(p);
			zoneFloorParts.push(p);
		}

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
			// La cobertura se registra ADEMAS como lista de discos: el spawn del
			// monstruo tiene que apartarse de ella, y `coverField` solo devuelve las
			// cajas montadas, no donde se han plantado.
			//
			// El disco es el radio de la caja en su eje MAYOR: para `Cover_Pillar` y
			// `Cover_Monolith` coincide con el medio ancho, y para `Cover_Slab` es el
			// medio largo. Con el radio pequeno el spawn acaba pegado al extremo largo
			// de la losa, que es donde se apoya el remate.
			z.cover = [];
			const covers = coverField(api, z, P, seedBase + z.lx, z.role === "intermediate" ? 7 : 5, tag);
			for (const p of covers) kids.push(p);
			for (const p of covers) {
				const pr = p.node && p.node.$properties;
				if (!pr || !Array.isArray(pr.Position) || !Array.isArray(pr.Size)) continue;
				z.cover.push({
					x: pr.Position[0],
					z: pr.Position[2],
					half: Math.max(pr.Size[0], pr.Size[2]) / 2,
				});
			}
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
			keshusyParts.push(decor("Reward_Orb_" + def.id + "_" + z.id, {
				position: [z.x, z.y + 6.4, z.z],
				size: [4, 4, 4], shape: "Ball",
				material: "Neon", color: P.energy, transparency: 0.15,
			}));
			for (let i = 0; i < 4; i++) {
				const a = (i / 4) * Math.PI * 2;
				// El id de la zona va en el NOMBRE, no solo en la posicion.
				//
				// `i` es el indice DENTRO de la zona, asi que vuelve a 0 en cada
				// zona de recompensa. Con una sola zona de recompensa por mundo
				// eso nunca se notaba; al anadir una segunda, las cuatro marcas
				// de ambas zonas producen el MISMO nombre y `asChildren` las
				// sobreescribe en silencio: el generador hacia bien en avisar, y
				// sin el aviso la segunda zona de recompensa se habia quedado sin
				// ningun spawn de powerup.
				powerupParts.push(marker("PowerupSpawn_" + def.id + "_" + z.id + "_" + i,
					[z.x + Math.cos(a) * 13, z.y + 1.4, z.z + Math.sin(a) * 13],
					{ color: P.energy, size: [2.4, 0.2, 2.4] }));
			}
		} else if (z.role === "miniboss") {
			kids.push(marker("MiniBossSpawn_" + def.id + "_" + z.id,
				[z.x, z.y + 0.3, z.z], { color: P.hazard, size: [5, 0.2, 5] }));
			for (let i = 0; i < 4; i++) {
				const a = (i / 4) * Math.PI * 2 + Math.PI / 4;
				const x = z.x + Math.cos(a) * z.rx * 0.62;
				const zz = z.z + Math.sin(a) * z.rz * 0.62;
				if (onRoute(z, x, zz, 3)) continue;
				const height = 5 + hash01(seedBase, i + z.lx * 17) * 3;
				kids.push(part("MiniBossPillar_" + def.id + "_" + z.id + "_" + i, {
					position: [x, z.y + height / 2, zz],
					size: [3.2, height, 3.2],
					material: P.structureMaterial,
					color: P.structureDark,
				}));
			}
		} else if (z.role === "secret") {
			const secretName = "SecretPrompt_" + def.id + "_" + z.id;
			let cachePosition = { x: z.x, z: z.z };
			for (let i = 0; i < 24; i++) {
				const a = (i / 24) * Math.PI * 2;
				const x = z.x + Math.cos(a) * z.rx * 0.58;
				const zz = z.z + Math.sin(a) * z.rz * 0.58;
				if (!onRoute(z, x, zz, 3)) {
					cachePosition = { x: x, z: zz };
					break;
				}
			}
			const cache = part("SecretCache_" + def.id + "_" + z.id, {
				position: [cachePosition.x, z.y + 2, cachePosition.z],
				size: [8, 4, 6],
				material: P.structureMaterial,
				color: P.structureDark,
			});
			cache.node[secretName] = {
				$className: "ProximityPrompt",
				$properties: {
					ActionText: "Descubrir",
					ObjectText: "Hallazgo oculto",
					HoldDuration: 1.1,
					MaxActivationDistance: 9,
					RequiresLineOfSight: false,
					Enabled: true,
				},
			};
			kids.push(cache);
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
			//
			// P0. El monumento NO se construye en el centro. El centro de la
			// arena es el punto de comparacion de todo: la celda que el
			// verificador usa como destino, y el sitio donde el jugador hace
			// circle-strafe. Con un solido de 8x8 plantado ahi, la celda central
			// de la arena de los cinco mundos aparecia bloqueada y la zona se
			// diagnosticaba inaccesible, con 549 celdas alcanzables de 566.
			//
			// Se conserva el anillo de bloques como cobertura DESTRUCTIBLE, que
			// es su funcion de juego, pero en un radio EXTERIOR y sin ocupar los
			// cuatro ejes cardinales, que son por donde entra la ruta. El nucleo
			// visual (`Arena_Core`) sigue a 12 studs, que es donde ya se leia.
			//
			// P0 DEFINITIVO: el anillo va FUERA del circulo de combate.
			//
			// El anillo estaba a 15.5 studs del centro, con lo que sus ocho bloques
			// de 8 studs caian entre los 11 y los 20 studs: justo DENTRO del
			// disco de 30 studs que hay que dejar libre para circular, poner una
			// bomba y salir. Medido: el verificador dava `TIGHT ARENA: disco libre
			// de 0 studs` en Ice y en Desert, con 30 de las 197 celdas del disco
			// ocupadas por el monumento.
			//
			// Un monumento en el centro de la arena no es cobertura: es un obstaculo
			// en el sitio donde se pelea. Por eso el radio sale del circulo que hay
			// que dejar libre (`ARENA_CLEAR_RADIUS`, el mismo numero que exige
			// `MIN_ARENA_RADIUS` en el verificador) mas el medio ancho del bloque,
			// y nunca baja de la fraccion de la zona que lo tiene que contener: un
			// bloque a 40 studs de una arena de 25 de radio caeria en el vacio.
			const ARENA_CLEAR_RADIUS = 30;
			const STEP = Math.max(ARENA_CLEAR_RADIUS + 6, Math.min(z.rx, z.rz) * 0.62);
			const VARIANTS = ["A", "B", "C", "D"];
			const MATERIALS = [P.structureMaterial, P.floorMaterial, "Rock", "Slate", "Basalt", "Sandstone"];
			for (let gx = -2; gx <= 2; gx++) {
				for (let gy = 0; gy <= 2; gy++) {
					for (let gz = -2; gz <= 2; gz++) {
						if (Math.abs(gx) + Math.abs(gy) + Math.abs(gz) === 0) continue;
						if (Math.abs(gx) + Math.abs(gz) < 2 && gy === 1) continue;
						const px = z.x + gx * STEP;
						const pz = z.z + gz * STEP;
						if (onRoute(z, px, pz)) continue;
						// Los cuatro ejes quedan limpios: ahi entra la ruta y ahi
						// tiene que haber suelo.
						if (Math.min(Math.abs(gx), Math.abs(gz)) === 0) continue;
						// Y el bloque tiene que CABER dentro del suelo de la arena:
						// fuera de la elipse no hay losa y el bloque quedaria
						// colgado sobre el vacio.
						const nx = (px - z.x) / z.rx;
						const nz = (pz - z.z) / z.rz;
						if (nx * nx + nz * nz > 0.7) continue;
						const broken = gy === 1 && Math.abs(gx) === 1 && Math.abs(gz) === 1;
						const blockIndex = centralBlocks.length;
						const variant = VARIANTS[blockIndex % VARIANTS.length];
						const material = MATERIALS[blockIndex % MATERIALS.length];
						const node = part("Block_" + def.id + "_cs" + blockIndex, {
							position: [px, z.y + (broken ? 3 : 5.5), pz],
							size: [8, broken ? 6 : 11, 8],
							material: material,
							color: broken ? P.structureDark : P.structure,
							orientation: [
								Math.round(vary(blockIndex, 5, -12, 12)),
								Math.round(hash01(blockIndex, 12) * 360),
								Math.round(vary(blockIndex, 6, -12, 12)),
							],
						});
						node.node["Deco_" + variant + "_" + def.id + "_" + blockIndex] = decor("Deco_" + variant + "_" + def.id + "_" + blockIndex, {
							position: [px, z.y + (broken ? 3 : 5.5) + 5.5, pz],
							size: [3.2, 0.2, 3.2],
							material: "Neon",
							color: P.accent,
							transparency: 0.2,
						}).node;
						centralBlocks.push(node);
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

		// Spawns de monstruo: se DECLARAN aqui y se COLOCAN al final.
		//
		// P0 DEFINITIVO: el punto no se supone, se BUSCA contra la geometria ya
		// montada. Ver `resolveMonsterSpawns`, que corre con el mundo completo.
		//
		// Antes se plantaba en dos angulos fijos al 55% del radio de la zona y se
		// daba por bueno. Medido sobre el arbol generado: 13 de los 30 spawns de
		// los cinco mundos caian sobre algo que no es suelo util, y 2 no tenian
		// suelo en absoluto (`MonsterSpawn_Forest_00` sobre un `Cover_Pillar`,
		// `MonsterSpawn_Forest_05` sobre el muro de un cañon, `MonsterSpawn_Ice_01`
		// y `MonsterSpawn_Cyber_01` en celdas sin suelo). Eso es el fallo
		// reportado: el jugador entra y los monstruos no estan en su espacio.
		if (z.role === "encounter" || z.role === "intermediate" || z.role === "arena") {
			monsterIntents.push({ zone: z, first: monsterIntentIndex });
			monsterIntentIndex += 2;
		}

		// Decoracion propia del mundo, sembrada DENTRO de la zona.
		//
		// `solid` es la lista `kids` de la propia carpeta de la zona:
		// la scenery de Forest la usa para levantar las estructuras
		// SOLIDAS de los puntos de interes (cabañas, muros de ruinas,
		// la torre). Nada mas la scenery de Forest escribe ahi, y
		// siempre respetando `z.keepOut`, asi que el corredor por el
		// que se entra a la zona sigue limpio.
		const sc = SCENERY[def.id];
		if (sc) {
			sc({ part: part, decor: decor, marker: marker, light: light }, z, P, seedBase + z.lx * 11 + z.lz * 13, {
				deco: decoParts, border: borderParts, keshusy: keshusyParts, terrain: terrainParts,
				solid: kids,
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
	//
	// PERO NO DONDE SALE UNA RUTA. Una ruta cuyo extremo cae en el limite del
	// mundo necesita un HUECO, o el muro la cierra y el jugador llega al final
	// del sendero y encuentra pared. Por eso antes de construir el borde se
	// calcula, para cada ruta, el tramo que toca el borde y se le pasa a
	// `worldEdge` como hueco. Es geometria, no un nombre reservado.
	//
	// El criterio es de DISTANCIA AL BORDE DE LA NUBE, no "esta ruta toca el
	// limite": una ruta entre dos zonas del interior no abre ningun hueco, y
	// una que llega al extremo abre uno ancho. Medirlo con el margen de la propia
	// nube evita depender de cual zona queda mas alOutside.
	//
	// P0: el hueco se declara UNA vez por ruta, con el TRAMO COMPLETO. Antes se
	// declaraba dos veces, solo con los extremos, y `distToSegment` ya mide
	// contra el tramo entero, asi que los dos huecos eran el mismo y el segundo
	// no aportaba nada. Se queda uno, que es lo que significa.
	const edgeGaps = [];
	for (const info of routeInfo) {
		const b = info.built;
		edgeGaps.push({
			ax: b.ax, az: b.az, bx: b.bx, bz: b.bz,
			// Margen proporcional al ancho de la ruta: una ruta ancha abre
			// un hueco ancho. Es el mismo criterio que usa `zoneRim`.
			half: b.width * 0.75 + CELL_EDGE,
		});
	}

	const edge = naturalEdge(api, zones, edgeGaps, P, seedBase);

	// ------------------------------------------------- ENLACE CON EL SUELO
	//
	// P0. `fillApproach` no rellena hasta el CENTRO de la zona: se queda en el
	// borde.
	//
	// El suelo de una zona es un ensamblaje (`zoneSlab`) cuyo nucleo cubre la
	// elipse entera, y el deck de una ruta ya entra en la zona hasta un 72% de
	// su radio. Entre una cosa y otra no queda hueco: el relleno al centro es
	// geometria de sobra.
	//
	// Y no es "de sobra sin coste". Al llegar al centro, todas las rutas de la
	// zona se CRUZABAN en un punto, y cada zona se convertia en un embudo. Con
	// el tronco compartido, tapar el camino mas corto dejaba al spawn sin
	// salida por la unica puerta que quedaba: la comprobacion de ruta
	// alternativa de Forest fallaba porque el atajo y la salida eran el mismo
	// tramo.
	//
	// El enlace va del final del deck hasta un punto del borde del suelo, con
	// la cota de la zona. Entra en la zona, conecta con su suelo y se acaba.
	const APPROACH_STOP = 0.34;
		routeInfo.forEach(function (info, ri) {
		const b = info.built;
		for (const end of ["a", "b"]) {
			const isFrom = end === "a";
			const zone = isFrom ? info.from : info.to;
			const ex = isFrom ? b.ax : b.bx;
			const ez = isFrom ? b.az : b.bz;
			fillApproach(
				{ part: part, decor: decor }, terrainParts, ex, ez, zone, b.width, P,
				seedBase + (isFrom ? 0 : 3),
				end + ri + "_" + zone.id,
				APPROACH_STOP
			);
			fillEdgeBridge(
				part, terrainParts, ex, ez, zone, b.width, P,
				seedBase + (isFrom ? 0 : 3),
				end + ri + "_" + zone.id
			);
		}
	});
	// El borde NO se construye: `naturalEdge` ya ha devuelto las piezas de
	// ESCENIFICACION (`Edge_Cliff_*`, `Edge_Rock_*`), y todas van SIN colision.
	//
	// P0 DEFINITIVO. Aqui se construian antes `Border_Wall_<i>` y `Border_Cap_<i>`:
	// entre 264 y 272 muros SOLIDOS de 18-34 studs por mundo, colocados sobre la
	// frontera dilatada de la nube de zonas. Eso era el cuadrilatero que se
	// que se reportaba en PLAY, y ademas hacia que el verificador de
	// navegabilidad diera PASS con el mundo cerrado: la caja que se queria
	// eliminar era justo la que hacia PASS el test.
	//
	// Lo que queda en `Border/` es el talud y las rocas del anillo. Nada de eso
	// colisiona, de modo que el borde sigue siendo el FINAL DEL TERRENO.
	for (const p of edge) borderParts.push(p);

	// ---------------------------------------------------------- REPARACION DE HUECOS
	//
	// P0. A pesar del `zoneRimFloor` y del `fillEdgeBridge`, quedan huecos entre
	// zonas adyacentes a la misma altura pero sin ruta directa entre ellas, o en
	// las esquinas de zonas a distinta cota. El jugador pisa el suelo de una zona,
	// ve un par de metros y cae al vacio porque el triangulo intermedio entre losas
	// no esta cubierto.
	//
	// Este paso escanea la rejilla de suelos generados y coloca losas pequenas
	// (6x2x6) SOBRE las celdas huecas rodeadas de suelo por todos lados. No crea
	// cajas nuevas: solo sella los huecos accidentales que el diseno geometrico
	// no cubre, dejando el borde del mundo como terreno caente.
	//
	// P0 FASE 5: se incluyen las losas de las rutas (route deck), que el escaneo
	// original no veia porque estan en `routeInfo.built.parts` y no en
	// `terrainParts` ni `zoneFloorParts`. Sin ellos, la cuadricula del parcheador
	// no coinside con la del analizador de integridad (que ve TODAS las piezas)
	// y los huecos entre zonas conectadas por rutas no se detectan.
	const routeDeckParts = [];
	for (const info of routeInfo) {
		for (const p of info.built.parts) routeDeckParts.push(p);
	}
	patchFloorHoles(part, terrainParts, zones, P, seedBase, zoneFloorParts.concat(routeDeckParts));

	// ---------------------------------------------------------- CUEVAS SUBTERRANEAS (FASE 5)
	//
	// Añade tres niveles de cueva (y = -20, -40, -60) conectados por pozos
	// verticales, y descensos controlados desde zonas seleccionadas de la
	// superficie. Las cuevas son parte del terreno (terrainParts) y aparecen en
	// el folder `Terrain`, manteniendo la misma estructura de carpetas.
	const caveResult = buildCaves(
		{ part: part, decor: decor, marker: marker },
		zones, P, seedBase, def.id
	);
	for (const p of caveResult.terrainParts) terrainParts.push(p);
	for (const m of caveResult.descentMarkers) {
		keshusyParts.push(m);
	}
	// Actualiza zoneFloorParts con los nuevos suelos de cueva para que
	// patchFloorHoles itere sobre ellos tambien en la segunda pasada.
	for (const p of caveResult.terrainParts) {
		if (p.path && p.path.includes("Slab")) zoneFloorParts.push(p);
	}

	// P0 FASE 5: segunda pasada de parcheo despues de generar cuevas. Las
	// nuevas losas de cueva pueden dejar huecos entre si, y el parche
	// iterativo de patchFloorHoles cierra todo en un par de pasadas.
	patchFloorHoles(part, terrainParts, zones, P, seedBase + 500, zoneFloorParts.concat(routeDeckParts));

	// ------------------------------------------------------ PIEZAS DE CONTRATO
	//
	// `ArenaFloor` sigue siendo UNA pieza, pero ahora es el suelo de la zona de
	// arena y no la losa de "todo el mundo". `BombService.detectArenaBounds` ya
	// es por mundo, asi que el limite de bombas se calcula sobre la zona por la
	// que se pelea y no sobre un cuadrado de 180x180.
	const arenaZone = zones.filter(function (z) { return z.role === "arena"; })[0];
	const entranceZone = zones.filter(function (z) { return z.role === "entrance"; })[0];

	// SEMILADO MINIMO del suelo de la arena, en studs.
	//
	// La arena es donde se pelea, y pelear exige un CIRCULO por el que circular,
	// poner una bomba y salir. El verificador exige un disco libre de 30 studs
	// (`MIN_ARENA_RADIUS` en `tools/world-navigation-test.js`), o sea 60x60.
	//
	// El suelo se escalaba con la elipse de la zona, y la elipse de arena es
	// alargada: Ice daba 52x26 y Desert 40x18. Un disco de 30 studs no cabe en
	// 26, y lo que se salia del suelo no era "borde de la arena" sino un
	// AGUJERO en mitad del combate. Medido: `TIGHT ARENA: la arena da un disco
	// libre de 0 studs` en Ice, con 12 celdas del disco sin suelo.
	//
	// Por eso el suelo no se deriva de la zona: se deriva del RADIO QUE HAY QUE
	// PELEAR, mas el margen con el que se puede correr pegado al borde sin salirse.
	const ARENA_FLOOR_MIN_HALF = 34;
	const arenaHalfX = Math.max(arenaZone.rx * 1.05, ARENA_FLOOR_MIN_HALF);
	const arenaHalfZ = Math.max(arenaZone.rz * 1.05, ARENA_FLOOR_MIN_HALF);

	const arenaParts = [
		part("ArenaFloor", {
			position: [arenaZone.x, arenaZone.y - 1, arenaZone.z],
			size: [arenaHalfX * 2, 2, arenaHalfZ * 2],
			material: P.floorMaterial,
			color: P.ground,
		}),
		marker("ArenaCenter", [arenaZone.x, arenaZone.y + 0.2, arenaZone.z], { color: P.energy }),
		marker("ArenaNorth", [arenaZone.x, arenaZone.y + 0.2, arenaZone.z - arenaHalfZ + 10], { color: P.accent }),
		marker("ArenaSouth", [arenaZone.x, arenaZone.y + 0.2, arenaZone.z + arenaHalfZ - 10], { color: P.accent }),
		marker("ArenaEast", [arenaZone.x + arenaHalfX - 10, arenaZone.y + 0.2, arenaZone.z], { color: P.accent }),
		marker("ArenaWest", [arenaZone.x - arenaHalfX + 10, arenaZone.y + 0.2, arenaZone.z], { color: P.accent }),
	];

	// El spawn va en la zona de ENTRADA y mira a la primera ruta: el jugador
	// aparece viendo por donde se sigue, no mirando una pared.
	//
	// P0. La zona de entrada es un PATIO, no una casilla. El verificador exige
	// que el 85% de un disco de 26 studs alrededor del spawn sea alcanzable
	// (`SPAWN_TRAP`), y con el spawn pegado al borde de la zona el disco se
	// comia medio muro: los cinco mundos salian con SPAWN TRAP al 52-59%.
	//
	// El desplazamiento hacia la primera ruta se queda, porque el jugador tiene
	// que ver por donde se sigue, pero es del 18% del radio en vez del 45%: con
	// un patio de 30 studs de radio, el disco entero cae dentro del suelo.
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
				Position: v3(
					entranceZone.x,
					entranceZone.y + 1.6,
					entranceZone.z + entranceZone.rz * SPAWN_FORWARD
				),
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
	//
	// Se monta el mundo SIN los spawns de monstruo, se mide su geometria, y
	// entonces se colocan. Ese orden es el que garantiza que un spawn este en el
	// mismo espacio que el jugador: la medida se hace sobre el arbol ya completo,
	// con la cobertura, los muros de zona y las rutas ya puestos.
	//
	// P0 FASE 5: pasada final de parcheo con ABSOLUTAMENTE todas las losas
	// visibles: suelos de zona, losas de cueva, decks de rutas y el suelo de la
	// arena. Las pasadas anteriores no veian los decks de ruta ni el suelo de
	// la arena (creados despues), por lo que quedaban huecos entre una ruta y
	// la zona de arena. Esta pasada cierra todo lo que haya quedado.
	patchFloorHoles(
		part, terrainParts, zones, P, seedBase + 1000,
		zoneFloorParts.concat(routeDeckParts, arenaParts)
	);
	const worldShell = folder(def.id, arenaParts.concat(
		[spawn],
		gateParts,
		bossParts,
		exitParts,
		folder("Zones", zoneFolders),
		folder("Routes", routeFolders),
		folder("Blocks", def.id === "Forest" && blocks.length > 48 ? blocks.slice(0, 48) : blocks),
		folder("CentralStructure", centralBlocks),
		folder("Terrain", terrainParts),
		folder("Hazards", hazardParts),
		folder("Decoration", decoParts),
		folder("Border", borderParts),
		folder("Keshusy", keshusyParts),
		folder("PowerupSpawns", powerupParts)
	));

	const spawnPos = spawn.node.$properties.Position;
	monsterSpawnParts.push(...resolveMonsterSpawns(
		{ marker: marker },
		worldShell.node,
		monsterIntents,
		def.id,
		P,
		{ x: spawnPos[0], z: spawnPos[2] }
	));

	return folder(def.id, arenaParts.concat(
		[spawn],
		gateParts,
		bossParts,
		exitParts,
		folder("Zones", zoneFolders),
		folder("Routes", routeFolders),
		folder("Blocks", def.id === "Forest" && blocks.length > 48 ? blocks.slice(0, 48) : blocks),
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

// --------------------------------------------------- BORDE NATURAL DEL MUNDO
//
// P0 DEFINITIVO (medido en PLAY): el mundo se leia como un cuadrilatero.
//
// El verificador de navegabilidad daba 11/11, 12/12, 12/12, 13/13 y 13/13 y, a
// pesar de todo, al entrar en Forest el jugador podia quedar FUERA del area
// jugable mientras los monstruos quedaban DENTRO de un perimetro. La causa no
// estaba en el test: estaba en esta funcion. `worldEdge` levantaba entre 264 y
// 272 piezas `Border_Wall_*` SOLIDAS alrededor de la nube de zonas en cada uno de
// los cinco mundos, cada una de 18-34 studs de alto y 3 de grosor, colocadas
// sobre una rejilla de 16 studs que rodea el mundo entero.
//
// Eso no es un borde: es una CAJA. El limite del mundo era artificial, el
// jugador no lo leia como diseno (era una linea recta de bloques iguales que
// repetia el perimetro) y el mapa se leia como un cuadrilatero con decoracion
// dentro. Ademas producia el fallo reportado: el muro se levantaba DESPUES de
// las zonas, sobre la nube dilatada, de modo que habia una franja de terreno
// entre el ultimo suelo real y el muro que el jugador recorría sin ninguna
// referencia de que ahi se acababa el mundo.
//
// LA REGLA NUEVA
// --------------
// No hay muro perimetral. El limite del mundo lo marca el propio terreno: las
// zonas y las rutas se acaban, y lo que hay a partir de ahi es vacio. El
// jugador corre, se acaba el suelo, cae, muere y reaparece. Esa es la unica
// regla que se sostiene en los cinco mundos.
//
// Lo que se construye aqui es la ESCENIFICACION del borde, no su cerramiento:
//
//   1. Un talud de roca que baja desde la cota del terreno: el jugador ve que
//      el terreno termina en una pendiente y no en un muro. No colisiona, asi
//      que no puede treparse ni convertirse en un muro invisible.
//   2. Piezas sueltas e irregulares (rocas, arboles, hielo, lava, pilares)
//      sembradas en el vacio justo fuera del ultimo suelo. Dan silueta al
//      borde y profundidad a la caida, y no encierran nada porque estan
//      separadas y no forman una linea continua.
//
// Ni una pieza de este borde colisiona. Un borde que colisiona es una pared, y
// una pared es exactamente lo que se elimina.

/**
 * Piezas de ESCENIFICACION del borde: lo que se ve al llegar al final del
 * terreno. Ninguna colisiona.
 *
 * El criterio es geometrico y no de decoracion: se siembra sobre el ANILLO que
 * queda entre el ultimo suelo y el vacio, con una separacion mayor que el
 * diametro de la pieza. Un borde sembrado con piezas separadas se lee como
 * terreno que se acaba; un borde con piezas pegadas se lee como un muro, que es
 * lo que se prohibe.
 *
 * @param {object} api
 * @param {Array} zones zonas ya desplazadas al mundo
 * @param {Array} corridors tramos de ruta que cruzan el limite
 * @param {object} P paleta
 * @param {number} seedBase
 * @returns {Array} piezas SIN colision
 */
function naturalEdge(api, zones, corridors, P, seedBase) {
	const { decor } = api;
	const out = [];

	// SEPARACION MINIMA entre dos piezas del borde, en studs.
	//
	// P1: Reducimos STEP de 22 a 14 para generar mas piezas y llegar a 60+.
	// Con piezas a 14 studs de separacion y de 6 a 16 de ancho, sigue habiendo
	// huecos por los que se ve el vacio, pero el borde es mas denso y se lee
	// como un anillo natural, no como un muro continuo.
	const STEP = 14;

	// El anillo empieza FUERA del ultimo suelo (16 studs) y llega 48 studs mas
	// alla. Sembrar por dentro pondria rocas en medio del area jugable, y sembrar
	// mas lejos de 48 studs las deja fuera del alcance visual del jugador.
	// P1: Aumentamos RING_OUTER a 60 para cubrir mas perimetro.
	const RING_INNER = 16;
	const RING_OUTER = 60;
	// Extremos de la nube de zonas: el anillo se siembra alrededor de la
	// SILUETA, no de un cuadrado. Es la misma idea que hacia `worldEdge`, pero
	// el resultado ya no es una linea continua sino piezas sueltas.
	let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
	for (const zone of zones) {
		minX = Math.min(minX, zone.x - zone.rx); maxX = Math.max(maxX, zone.x + zone.rx);
		minZ = Math.min(minZ, zone.z - zone.rz); maxZ = Math.max(maxZ, zone.z + zone.rz);
	}

	for (let x = minX - RING_OUTER; x <= maxX + RING_OUTER; x += STEP) {
		for (let z = minZ - RING_OUTER; z <= maxZ + RING_OUTER; z += STEP) {
			// Dentro de la nube esta el suelo jugable: una roca ahi seria un
			// obstaculo, no un borde. Se descarta con la MISMA elipse que dibuja
			// el suelo, mas el margen interior del anillo.
			let insideZone = false;
			for (const zone of zones) {
				const dx = (x - zone.x) / (zone.rx + RING_INNER);
				const dz = (z - zone.z) / (zone.rz + RING_INNER);
				if (dx * dx + dz * dz <= 1) { insideZone = true; break; }
			}
			if (insideZone) continue;

			// Distancia al suelo mas cercano. Decide si la pieza cae en el anillo
			// que toca el terreno (y por tanto se ve al llegar al borde) y con que
			// cota se planta, para que parezca apoyada en el terreno y no flotando.
			let gap = Infinity;
			let floorY = 0;
			for (const zone of zones) {
				const rr = ellipseRadius(zone.rx, zone.rz, x - zone.x, z - zone.z);
				const dist = Math.sqrt((x - zone.x) * (x - zone.x) + (z - zone.z) * (z - zone.z)) - rr;
				if (dist < gap) { gap = dist; floorY = zone.y; }
			}
			if (gap < RING_INNER || gap > RING_OUTER) continue;

			// Un corredor de ruta que cruza el borde se respeta con holgura: el
			// jugador sale por ahi, y una roca en la boca del sendero es el muro
			// que se prohibe.
			let onCorridor = false;
			for (const g of corridors || []) {
				if (distToSegment(x, z, g.ax, g.az, g.bx, g.bz) < g.half + 12) {
					onCorridor = true;
					break;
				}
			}
			if (onCorridor) continue;

			const salt = Math.round(x) * 131 + Math.round(z) * 17;
			const h = vary(seedBase, salt, 4, 13);

			// Talud: baja desde la cota del terreno, de modo que se lee como una
			// pendiente que cae al vacio. `decor` lo deja SIN colision.
			out.push(decor("Edge_Cliff_" + Math.round(x) + "_" + Math.round(z), {
				position: [x, floorY - h / 2 - 1, z],
				size: [vary(seedBase, salt + 1, 6, 16), h, vary(seedBase, salt + 2, 6, 16)],
				material: P.structureMaterial,
				color: P.structureDark,
				orientation: [0, Math.round(hash01(seedBase, salt + 3) * 360), 0],
			}));

			// Segunda pieza, mas pequena, de vez en cuando. Rompe la retícula del
			// talud para que el borde no se lea como un enrejado de cajas.
			// P1: Aumentamos la probabilidad al 75% para mas piezas.
			if (hash01(seedBase, salt + 4) > 0.25) {
				const h2 = vary(seedBase, salt + 5, 3, 8);
				out.push(decor("Edge_Rock_" + Math.round(x) + "_" + Math.round(z), {
					position: [
						x + vary(seedBase, salt + 6, -9, 9),
						floorY + h2 / 2 - 3,
						z + vary(seedBase, salt + 7, -9, 9),
					],
					size: [vary(seedBase, salt + 8, 3, 8), h2, vary(seedBase, salt + 9, 3, 8)],
					material: P.structureMaterial,
					color: hash01(seedBase, salt + 10) > 0.5 ? P.structure : P.structureDark,
					orientation: [
						Math.round(vary(seedBase, salt + 11, -14, 14)),
						Math.round(hash01(seedBase, salt + 12) * 360),
						Math.round(vary(seedBase, salt + 13, -14, 14)),
					],
				}));
			}

			// Tercera pieza: roca suelta adicional para densidad visual.
			if (hash01(seedBase, salt + 14) > 0.4) {
				const h3 = vary(seedBase, salt + 15, 2, 6);
				out.push(decor("Edge_Pebble_" + Math.round(x) + "_" + Math.round(z), {
					position: [
						x + vary(seedBase, salt + 16, -12, 12),
						floorY + h3 / 2 - 1,
						z + vary(seedBase, salt + 17, -12, 12),
					],
					size: [vary(seedBase, salt + 18, 2, 5), h3, vary(seedBase, salt + 19, 2, 5)],
					material: P.floorMaterial,
					color: P.groundAlt,
					orientation: [
						Math.round(vary(seedBase, salt + 20, -20, 20)),
						Math.round(hash01(seedBase, salt + 21) * 360),
						Math.round(vary(seedBase, salt + 22, -20, 20)),
					],
				}));
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
// con color verde, y una pilona de ne�n no es un pilar de piedra. Por eso cada
// mundo tiene su propio constructor de elementos.

/**
 * Elemento aleatorio dentro de una zona, sin salir de ella.
 *
 * Se muestrea en coordenadas polares y se RECHAZA si el punto cae sobre una
 * ruta. Un arbol plantado en mitad de un sendero no es decoracion: es un obstac
 *culo invisible en un sitio por el que el jugador tiene que pasar.
 */
function scatterInZone(z, seedBase, salt, minR, maxR) {
	const keepOut = z.keepOut || null;
	let best = null;
	for (let attempt = 0; attempt < 24; attempt++) {
		const a = vary(seedBase + salt, attempt * 3 + 1, 0, Math.PI * 2);
		const r = vary(seedBase + salt, attempt * 3 + 2, minR, maxR);
		const x = z.x + Math.cos(a) * z.rx * r;
		const zz = z.z + Math.sin(a) * z.rz * r;
		const candidate = { x: x, z: zz, a: a, r: r, ok: true };

		if (!keepOut) return candidate;
		let clear = true;
		for (const k of keepOut) {
			if (distToSegment(x, zz, k.ax, k.az, k.bx, k.bz) < k.half) {
				clear = false;
				break;
			}
		}
		if (clear) return candidate;
		// Si ningun intento cae libre, se queda el mas CENTRICO: es el punto
		// mas lejos del cuello, y ahi un obstaculo estorba menos.
		if (!best || candidate.r > best.r) best = candidate;
	}
	return best || { x: z.x, z: z.z, a: 0, r: 0, ok: false };
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

	// ----------------------------------------------------------------
	// CONTENIDO DIFERENCIADO POR ZONA
	// ----------------------------------------------------------------
	const isDense = z.id === "DenseGrove" || z.id === "DeepThicket" || z.id === "AncientGrove";
	const isCentral = z.id === "CentralPath" || z.id === "CentralClearing" || z.id === "CentralGlade";
	const isOpen = z.id === "ClearingEast" || z.id === "ClearingWest" || z.id === "MeadowNorth";
	const isRocky = z.id === "RockyRidge" || z.id === "BoulderField" || z.id === "StoneArch";

	// ---- BOSQUE DENSO: muchos arboles, arbustos cerrados, troncos y rocas ----
	if (isDense) {
		for (let i = 0; i < 22; i++) {
			const p = scatterInZone(z, seedBase, i, 0.15, 0.95);
			tree(z.id + "_D_" + i, p.x, p.z, vary(seedBase + i, 17, 10, 22), hash01(seedBase + i, 23) > 0.5 ? P.leafDeep : P.leafMid);
		}
		for (let i = 0; i < 14; i++) {
			const p = scatterInZone(z, seedBase, i + 100, 0.2, 0.9);
			out.deco.push(decor("Bush_Dense_" + z.id + "_" + i, {
				position: [p.x, z.y + 1.2, p.z],
				size: [vary(seedBase + i, 114, 3.2, 6.2), vary(seedBase + i, 115, 2.0, 3.8), vary(seedBase + i, 116, 3.2, 6.2)],
				shape: "Ball", material: "Grass",
				color: hash01(seedBase + i, 117) > 0.6 ? P.leafDeep : P.leafMid,
			}));
		}
		for (let i = 0; i < 5; i++) {
			const p = scatterInZone(z, seedBase, i + 200, 0.3, 0.85);
			out.deco.push(decor("Log_Dense_" + z.id + "_" + i, {
				position: [p.x, z.y + 0.6, p.z],
				size: [vary(seedBase + i, 201, 3.5, 7), 1.2, vary(seedBase + i, 202, 1.4, 2.4)],
				material: "Wood", color: P.barkDark,
				orientation: [0, Math.round(vary(seedBase + i, 203, 0, 180)), Math.round(vary(seedBase + i, 204, -10, 10))],
			}));
		}
		for (let i = 0; i < 4; i++) {
			const p = scatterInZone(z, seedBase, i + 300, 0.35, 0.8);
			out.deco.push(decor("Rock_Dense_" + z.id + "_" + i, {
				position: [p.x, z.y + 0.7, p.z],
				size: [vary(seedBase + i, 301, 2.4, 5.6), vary(seedBase + i, 302, 1.2, 2.8), vary(seedBase + i, 303, 2.4, 5.6)],
				material: "Rock", color: P.structureDark,
				orientation: [Math.round(vary(seedBase + i, 304, -12, 12)), Math.round(hash01(seedBase + i, 305) * 360), Math.round(vary(seedBase + i, 306, -12, 12))],
			}));
		}
	}

	// ---- ZONA CENTRAL: abierta, pocos arboles, vegetacion baja ----
	if (isCentral) {
		for (let i = 0; i < 4; i++) {
			const p = scatterInZone(z, seedBase, i, 0.5, 0.92);
			tree(z.id + "_C_" + i, p.x, p.z, vary(seedBase + i, 18, 7, 14), P.leafLight);
		}
		for (let i = 0; i < 8; i++) {
			const p = scatterInZone(z, seedBase, i + 40, 0.3, 0.9);
			out.deco.push(decor("Bush_Low_" + z.id + "_" + i, {
				position: [p.x, z.y + 0.9, p.z],
				size: [vary(seedBase + i, 118, 1.8, 3.4), vary(seedBase + i, 119, 1.0, 2.0), vary(seedBase + i, 120, 1.8, 3.4)],
				shape: "Ball", material: "Grass", color: P.leafMid,
			}));
		}
		out.terrain.push(decor("Sand_Clearing_" + z.id, {
			position: [z.x, z.y + 0.05, z.z],
			size: [z.rx * 1.3, 0.1, z.rz * 1.1],
			shape: "Cylinder", material: "Sand", color: P.sand,
		}));
	}

	// ---- BOSQUE ABIERTO: arboles separados, hierba alta, setos bajos ----
	if (isOpen) {
		for (let i = 0; i < 7; i++) {
			const p = scatterInZone(z, seedBase, i, 0.4, 0.95);
			tree(z.id + "_O_" + i, p.x, p.z, vary(seedBase + i, 19, 9, 17), hash01(seedBase + i, 24) > 0.5 ? P.leafMid : P.leafLight);
		}
		for (let i = 0; i < 6; i++) {
			const p = scatterInZone(z, seedBase, i + 50, 0.35, 0.9);
			out.deco.push(decor("Grass_Tall_" + z.id + "_" + i, {
				position: [p.x, z.y + 1.6, p.z],
				size: [vary(seedBase + i, 121, 1.2, 2.6), vary(seedBase + i, 122, 2.4, 4.2), vary(seedBase + i, 123, 1.2, 2.6)],
				shape: "Cylinder", material: "Grass", color: P.leafMid,
			}));
		}
		for (let i = 0; i < 3; i++) {
			const p = scatterInZone(z, seedBase, i + 60, 0.5, 0.85);
			out.deco.push(decor("Hedge_Low_" + z.id + "_" + i, {
				position: [p.x, z.y + 1.0, p.z],
				size: [vary(seedBase + i, 124, 4.2, 7.4), vary(seedBase + i, 125, 1.2, 2.2), vary(seedBase + i, 126, 1.4, 2.4)],
				material: "Grass", color: P.leafDeep,
				orientation: [0, Math.round(vary(seedBase + i, 127, 0, 180)), 0],
			}));
		}
		out.terrain.push(decor("Sand_Clearing_" + z.id, {
			position: [z.x, z.y + 0.05, z.z],
			size: [z.rx * 1.3, 0.1, z.rz * 1.1],
			shape: "Cylinder", material: "Sand", color: P.sand,
		}));
	}

	// ---- ZONA ROCOSA: rocas, formaciones, elevaciones naturales ----
	if (isRocky) {
		for (let i = 0; i < 8; i++) {
			const p = scatterInZone(z, seedBase, i, 0.2, 0.9);
			const h = vary(seedBase + i, 401, 4, 12);
			out.deco.push(decor("Rock_Big_" + z.id + "_" + i, {
				position: [p.x, z.y + h / 2, p.z],
				size: [vary(seedBase + i, 402, 4, 9), h, vary(seedBase + i, 403, 4, 9)],
				material: "Rock", color: hash01(seedBase + i, 404) > 0.5 ? P.structure : P.structureDark,
				orientation: [
					Math.round(vary(seedBase + i, 405, -12, 12)),
					Math.round(hash01(seedBase + i, 406) * 360),
					Math.round(vary(seedBase + i, 407, -12, 12)),
				],
			}));
		}
		for (let i = 0; i < 5; i++) {
			const p = scatterInZone(z, seedBase, i + 30, 0.3, 0.85);
			out.deco.push(decor("Rock_Formation_" + z.id + "_" + i, {
				position: [p.x, z.y + 1.4, p.z],
				size: [vary(seedBase + i, 408, 2.4, 5.4), vary(seedBase + i, 409, 1.4, 3.0), vary(seedBase + i, 410, 6.2, 12.4)],
				material: P.structureMaterial, color: P.structureDark,
				orientation: [0, Math.round(vary(seedBase + i, 411, -20, 20)), 0],
			}));
		}
		for (let i = 0; i < 3; i++) {
			const p = scatterInZone(z, seedBase, i + 60, 0.4, 0.8);
			out.terrain.push(decor("Terrain_Rock_" + z.id + "_" + i, {
				position: [p.x, z.y + 0.3, p.z],
				size: [vary(seedBase + i, 412, 3.4, 7.4), 0.6, vary(seedBase + i, 413, 3.4, 7.4)],
				material: P.structureMaterial, color: P.structure,
			}));
		}
	}

	// Elementos comunes a todas las zonas de Forest (excepto arena y boss)
	if (!isDense && !isCentral && !isOpen && !isRocky && z.role !== "arena" && z.role !== "boss") {
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

	// Luciernagas: puntos de luz flotantes que dan escala y movimiento.
	const fireflyCount = isDense ? 4 : isRocky ? 2 : 6;
	for (let i = 0; i < fireflyCount; i++) {
		const p = scatterInZone(z, seedBase, i + 80, 0.2, 0.95);
		out.keshusy.push(decor("Firefly_" + z.id + "_" + i, {
			position: [p.x, z.y + 2.5 + hash01(seedBase + i, 110) * 8, p.z],
			size: [0.7, 0.7, 0.7], shape: "Ball", material: "Neon",
			color: hash01(seedBase + i, 120) > 0.75 ? [216, 246, 150] : P.crystalHot,
			transparency: 0.25,
		}));
	}

	// Claros de arena: rompen el verde y dan puntos de referencia.
	// Se generan dentro de los bloques isCentral e isOpen, no aqui, para
	// evitar duplicados cuando varias zonas comparten el mismo patron.
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
	// el jugador pasa de?? a sombra antes de la fight.
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

	// EL CA�ON. Estratos horizontales apilados: la forma que solo tiene un
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
	LAYOUT_SCALES: LAYOUT_SCALES,
	WORLD_IDS: ["Forest", "Desert", "Ice", "Volcano", "Cyber"],
	// Se exportan para que los tests midan la MISMA plantilla que aplica el
	// generador y no una copia que pueda quedarse vieja.
	WORLD_SIZE_X: WORLD_SIZE_X,
	WORLD_SIZE_Z: WORLD_SIZE_Z,
	layoutBounds: layoutBounds,
	normalizeLayout: normalizeLayout,
	rimOpeningHalfAngle: rimOpeningHalfAngle,
	rimSegments: rimSegments,
	// El conteo REAL de borde que sobrevive. Se exporta para que las
	// herramientas que auditan el layout usen la misma cuenta que dibuja el
	// borde, y no una aproximacion que puede dar un PASS falso.
	rimKeptCount: rimKeptCount,
	MIN_RIM_SEGMENTS: MIN_RIM_SEGMENTS,
	buildWorld: buildWorld,
	hash01: hash01,
	vary: vary,
	dist2d: dist2d,
	// Las REGLAS de colocacion de spawn de monstruo se exportan para que el
	// verificador aplique las MISMAS que aplica el generador. Un verificador con
	// una copia de los numeros se queda viejo en cuanto se tocan, y entonces da
	// un PASS (o un FAIL) que ya no corresponde a nada.
	monsterSpawnSpacing: monsterSpawnSpacing,
	monsterSpawnClearance: monsterSpawnClearance,
	SCENERY: SCENERY,
	HOLE_TYPES: HOLE_TYPES,
};
