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
	return { name: name, node: { $className: "Part", $properties: props } };
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
// ---------------------------------------------------------------- LOBBY
// Zona segura. Aqui aparece el jugador al entrar al juego.
// El suelo arranca en Y = -1 con grosor 2: su cara superior queda
// exactamente en Y = 0, que es la altura de referencia del mapa.
const LOBBY_HALF = 70;

const lobbyParts = [
	part("LobbyFloor", {
		position: [0, -1, 0],
		size: [LOBBY_HALF * 2, 2, LOBBY_HALF * 2],
		material: "Concrete",
		color: [124, 134, 146],
	}),
	marker("LobbyCenter", [0, 0.2, 0], { color: [200, 220, 255] }),
	marker("LobbyNorth", [0, 0.2, -40], { color: [160, 200, 255] }),
	marker("LobbySouth", [0, 0.2, 40], { color: [160, 200, 255] }),
];

for (const p of perimeter("LobbyWall", 0, 0, LOBBY_HALF, 14, [92, 102, 118])) {
	lobbyParts.push(p);
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
function perimeter(prefix, cx, cz, half, height, colorRGB) {
	const out = [];
	out.push(part(prefix + "_N", { position: [cx, height / 2, cz - half], size: [half * 2 + 2, height, 2], color: colorRGB }));
	out.push(part(prefix + "_S", { position: [cx, height / 2, cz + half], size: [half * 2 + 2, height, 2], color: colorRGB }));
	out.push(part(prefix + "_W", { position: [cx - half, height / 2, cz], size: [2, height, half * 2 + 2], color: colorRGB }));
	out.push(part(prefix + "_E", { position: [cx + half, height / 2, cz], size: [2, height, half * 2 + 2], color: colorRGB }));
	return out;
}

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
			Lobby: folder("Lobby", lobbyParts).node,
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
