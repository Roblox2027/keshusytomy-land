// generate-project.js
// Genera default.project.json, incluyendo el MAPA del juego.
//
// Por que un generador y no JSON a mano: el mapa son ~120 bloques
// repetidos. Mantenerlo a mano es inviable y，任何 cambio seria un
// error tipografico silencioso. Este script es la fuente de verdad.
//
// Uso:  node tools/generate-project.js
//
// Regla: el script es idempotente y NUNCA toca src/. Solo escribe
// default.project.json.

const fs = require("fs");
const path = require("path");

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

	// `Shape` + `Material` permiten el vocabulario de formas que usa el
	// lobby (esferas del Core, cilindros de las columnas). Sin esto el
	// Keshusy Core tendria que ser un cubo, que es justo lo que el diseño
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
 * Part SIN colisión, para decoración y VFX.
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
const PORTAL_DEFS = [
	{ id: "Forest", x: -32, level: 1, color: KESHUSY },
	{ id: "Desert", x: -16, level: 10, color: TOMY },
	{ id: "Ice", x: 0, level: 20, color: [140, 214, 245] },
	{ id: "Volcano", x: 16, level: 35, color: [240, 110, 72] },
	{ id: "Cyber", x: 32, level: 50, color: [190, 120, 255] },
];

const portalModels = [];

for (const p of PORTAL_DEFS) {
	const z = -34;
	const frame = [86, 96, 114];

	portalModels.push(
		model("Portal_" + p.id, [
			part("Base", {
				position: [p.x, 0.5, z], size: [12, 1, 8],
				material: "Slate", color: frame,
			}),
			part("Lintel", {
				position: [p.x, 9, z], size: [12, 1.2, 8],
				material: "Slate", color: frame,
			}),
			part("PostL", {
				position: [p.x - 5.5, 4.75, z], size: [1.2, 8.5, 8],
				material: "Slate", color: frame,
			}),
			part("PostR", {
				position: [p.x + 5.5, 4.75, z], size: [1.2, 8.5, 8],
				material: "Slate", color: frame,
			}),

			// El umbral: la hoja central, translucida y sin colision.
			decor("PortalPanel", {
				position: [p.x, 4.75, z], size: [10, 8, 0.4],
				color: p.color, transparency: 0.55,
			}),
			decor("Glow", {
				position: [p.x, 4.75, z], size: [7, 5, 0.3],
				color: p.color, transparency: 0.3,
			}),

			// Rotulo del nivel exigido: visible en el cartel, no en un
			// atributo invisible. `PortalService` lo lee para validar
			// server-side.
			part("Sign", {
				position: [p.x, 10.6, z], size: [10, 1.6, 0.4],
				material: "SmoothPlastic", color: p.color,
			}),
		])
	);
}

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

// ---------------------------------------------------------------- ARENA
// La arena vive lejos del lobby (500 studs) para que las dos zonas
// sean independientes y el jugador no pueda interactuar con ambas.
const ARENA_CX = 500;
const ARENA_CZ = 0;
const ARENA_HALF = 90;

const arenaParts = [
	part("ArenaFloor", {
		position: [ARENA_CX, -1, ARENA_CZ],
		size: [ARENA_HALF * 2, 2, ARENA_HALF * 2],
		material: "Concrete",
		color: [96, 106, 96],
	}),
	marker("ArenaCenter", [ARENA_CX, 0.2, ARENA_CZ], { color: [255, 190, 110] }),
	marker("ArenaNorth", [ARENA_CX, 0.2, ARENA_CZ - 60], { color: [255, 160, 90] }),
	marker("ArenaSouth", [ARENA_CX, 0.2, ARENA_CZ + 60], { color: [255, 160, 90] }),
	marker("ArenaEast", [ARENA_CX + 60, 0.2, ARENA_CZ], { color: [255, 160, 90] }),
	marker("ArenaWest", [ARENA_CX - 60, 0.2, ARENA_CZ], { color: [255, 160, 90] }),
];

for (const p of perimeter("ArenaWall", ARENA_CX, ARENA_CZ, ARENA_HALF, 26, [74, 82, 74])) {
	arenaParts.push(p);
}

// (La definicion de `perimeter` vive arriba del bloque LOBBY. Antes vivia
// aqui, DESPUES de que el lobby ya la usara, y solo funcionaba por el
// hoisting de `function`. Declararla antes elimina esa dependencia sutil.)

// ------------------------------------------------- BLOQUES DESTRUCTIBLES
// Estructuras de bloques que las bombas destruyen. Los nombres empiezan
// por "Block_" y el servicio de destruccion los localiza por ese
// prefijo: es el unico contrato entre el mapa y el codigo.
const BLOCK_SIZE = 8;
const BLOCK_STEP = BLOCK_SIZE + 0.25;
const WALL_DISTANCE = 45;
const BLOCK_COLORS = [
	[186, 122, 78],
	[132, 160, 100],
	[104, 142, 194],
	[178, 152, 96],
];

let blockIndex = 0;

function block(x, y, z) {
	const name = "Block_" + blockIndex;
	blockIndex += 1;
	return part(name, {
		position: [x, y, z],
		size: [BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE],
		material: "WoodPlanks",
		color: BLOCK_COLORS[blockIndex % BLOCK_COLORS.length],
	});
}

// Cuatro murallas con huecos de paso, en dos alturas en las esquinas.
const perimeterBlocks = [];
const midY = BLOCK_SIZE / 2;
for (let i = 0; i < 6; i++) {
	const t = -WALL_DISTANCE / 2 + i * (WALL_DISTANCE / 5);

	// Murallas norte y sur: los bloques centrales se omiten para dejar
	// dos puertas de paso hacia el interior.
	if (i !== 2 && i !== 3) {
		perimeterBlocks.push(block(ARENA_CX + t, midY, ARENA_CZ - WALL_DISTANCE));
		perimeterBlocks.push(block(ARENA_CX + t, midY, ARENA_CZ + WALL_DISTANCE));
	}

	// Murallas este y oeste, sin hueco.
	perimeterBlocks.push(block(ARENA_CX - WALL_DISTANCE, midY, ARENA_CZ + t));
	perimeterBlocks.push(block(ARENA_CX + WALL_DISTANCE, midY, ARENA_CZ + t));

	// Segundo nivel en los extremos: torres en las esquinas.
	if (i === 0 || i === 5) {
		const topY = midY + BLOCK_SIZE + 0.25;
		perimeterBlocks.push(block(ARENA_CX + t, topY, ARENA_CZ - WALL_DISTANCE));
		perimeterBlocks.push(block(ARENA_CX + t, topY, ARENA_CZ + WALL_DISTANCE));
		perimeterBlocks.push(block(ARENA_CX - WALL_DISTANCE, topY, ARENA_CZ + t));
		perimeterBlocks.push(block(ARENA_CX + WALL_DISTANCE, topY, ARENA_CZ + t));
	}
}

// Estructura central: cubo 3x3x3 hueco, con tres accesos.
const centralBlocks = [];
for (let x = 0; x < 3; x++) {
	for (let y = 0; y < 3; y++) {
		for (let z = 0; z < 3; z++) {
			// Quitar el centro y las aristas de entrada para poder entrar.
			if (x === 1 && y === 1) continue;
			if (x === 1 && z === 1) continue;
			if (y === 1 && z === 1) continue;

			centralBlocks.push(
				block(
					ARENA_CX + (x - 1) * BLOCK_STEP,
					BLOCK_SIZE / 2 + y * BLOCK_STEP,
					ARENA_CZ + (z - 1) * BLOCK_STEP
				)
			);
		}
	}
}

const arenaChildren = arenaParts.concat([
	folder("Blocks", perimeterBlocks),
	folder("CentralStructure", centralBlocks),
]);
// ---------------------------------------------------------------- SPAWNS
// Los SpawnLocation del juego viven aqui, y NO dentro de `Lobby`.
//
// Razon: `SpawnService` busca `Workspace.SpawnLocations`. Ademas, Roblox
// elige el SpawnLocation mas cercano al jugador al entrar, asi que
// todos deben estar en el mismo plano y cerca del lobby para que el
// personaje SIEMPRE nazca en la zona segura.
const SPAWN_COLOR = [86, 214, 124];
const lobbySpawns = [
	spawnLocation("LobbySpawn1", [0, 1.6, -24], SPAWN_COLOR),
	spawnLocation("LobbySpawn2", [24, 1.6, 0], SPAWN_COLOR),
	spawnLocation("LobbySpawn3", [0, 1.6, 24], SPAWN_COLOR),
	spawnLocation("LobbySpawn4", [-24, 1.6, 0], SPAWN_COLOR),
	spawnLocation("LobbySpawn5", [40, 1.6, -40], SPAWN_COLOR),
	spawnLocation("LobbySpawn6", [-40, 1.6, 40], SPAWN_COLOR),
];

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
			// Los cinco mundos del contrato se declaran TODOS aqui.
			//
			// Antes solo se declaraba `Forest` y los otros cuatro existian
			// unicamente como carpetas vacias en `src/Workspace/`, que no
			// esta mapeado en `default.project.json` (no tiene `$path`) y
			// por eso Rojo nunca las entrega. El resultado era una
			// divergencia SOURCE/RUNTIME real: el build tenia 1 mundo y el
			// mundo vacio tampoco, pero el contrato y `WorldService`
			// esperan los cinco.
			//
			// Un mundo sin contenido es un Folder vacio: es inocuo, no
			// rompe el arranque y da destino a las fases futuras. Es
			// exactamente el mismo criterio que ya se aplica a los
			// servicios sin codigo.
			Worlds: folder("Worlds", [
				folder("Forest", arenaChildren),
				folder("Desert", []),
				folder("Ice", []),
				folder("Volcano", []),
				folder("Cyber", []),
			]).node,
		},
	},
};

fs.writeFileSync(PROJECT, JSON.stringify(project, null, 2) + "\n");

console.log("default.project.json generado.");
console.log("  bloques destructibles:", blockIndex);
console.log("  parts de lobby:", lobbyParts.length);
console.log("  parts de arena:", arenaChildren.length);
console.log("  spawnlocations:", lobbySpawns.length);
