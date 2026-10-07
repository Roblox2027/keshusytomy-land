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
const Hud = require("./hud");

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
 * Enum `Material` de Roblox, tal y como lo acepta Rojo 7.
 *
 * POR QUE ESTA LISTA ESTA EN EL GENERADOR
 * ---------------------------------------
 * Rojo acepta `Material: <lo que sea>` al escribir el JSON y falla DESPUES, al
 * compilar, con un error que no senala el sitio: "Invalid value for property
 * Part.Material. Got an array of three numbers but expected a member of the
 * Material enum". Ese "array of three numbers" es un COLOR escrito en el campo
 * equivocado, y el mensaje no dice donde ni que se ha escrito un color ahi.
 *
 * Ocurrio de verdad con las rutas de los mundos: `deckMat` devolvia
 * `P.groundAlt`, que es un color. Se gasto media hora leyendo el enum de
 * Material cuando el fallo estaba en una sola linea. `checkMaterials` delata
 * eso ANTES de escribir el archivo, con el camino exacto.
 */
const VALID_MATERIALS = new Set([
	"Air", "Asphalt", "Basalt", "Brick", "Cardboard", "Carpet", "CeramicTiles",
	"Cobblestone", "Concrete", "CorrodedMetal", "DiamondPlate", "Dirt",
	"Fabric", "Foil", "ForceField", "Glass", "Glacier", "Granite", "Grass",
	"Ground", "Ice", "LeafyGrass", "Lime", "Marble", "Metal", "Mud",
	"Pavement", "Pearl", "Pine", "Plaster", "Plastic", "Rattan", "Ribbed",
	"Rock", "RoofTiles", "Rust", "Sand", "Sandstone", "SandstoneStuds",
	"Scorch", "ScratchedMetal", "Shale", "Sky", "Slate", "SmoothPlastic",
	"Snow", "Sparkle", "Steel", "Stone", "StoneBrick", "Studs", "Snowtrail",
	"Wood", "WoodPlanks", "WoodShow",

	// `Neon` y `Glass` los usa el generador desde hace tiempo y Rojo los acepta
	// en Part. Se comprobaba contra una lista que se habia escrito a mano y se
	// le habian olvidado, que es la forma habitual de que una puerta de calidad
	// termine estorbando: ahora que `checkMaterials` EXISTE, se ejecuta sobre el
	// arbol entero en cada build, asi que cualquier olvido sale a la luz en
	// segundos y no en la sesion de Rojo.
	"Neon", "Glass",
]);

/**
 * Recorre el arbol y delata cualquier `Material` que no sea del enum, o que
 * sea un array de tres numeros (un color escrito en el campo equivocado).
 *
 * @param {object} node nodo del proyecto
 * @param {string} pathPrefix camino acumulado
 * @param {Array<string>} problems salida
 */
function checkMaterials(node, pathPrefix, problems) {
	for (const key of Object.keys(node)) {
		if (key.startsWith("$")) continue;
		const child = node[key];
		if (!child || typeof child !== "object") continue;
		const here = pathPrefix ? pathPrefix + "." + key : key;
		const props = child.$properties;

		if (props && "Material" in props) {
			const mat = props.Material;
			if (Array.isArray(mat)) {
				problems.push(here + ".Material = " + JSON.stringify(mat) +
					" (es un COLOR; Material debe ser un nombre del enum)");
			} else if (typeof mat === "string" && !VALID_MATERIALS.has(mat)) {
				problems.push(here + ".Material = '" + mat + "' (no existe en el enum de Roblox)");
			}
		}

		checkMaterials(child, here, problems);
	}
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

/**
 * PointLight para iluminacion localizada de puntos de interes.
 *
 * El mapa tiene presupuesto de luces (forest-verify.js exige <= 12
 * en todo el proyecto), asi que solo se crean para los focos que
 * dan identidad a un lugar: la fogata del campamento, la linterna
 * de la torre y el resplandor del santuario. Una luz por objeto
 * hundiria el frame rate sin aportar lectura.
 */
function pointLight(name, opts) {
	return {
		name: name,
		node: {
			$className: "PointLight",
			$properties: {
				Brightness: opts.brightness !== undefined ? opts.brightness : 2,
				Range: opts.range !== undefined ? opts.range : 24,
				Color: color(...(opts.color || [255, 200, 120])),
				Enabled: true,
				Shadows: opts.shadows !== false,
			},
		},
	};
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
	// El suelo.
	//
	// MEDIDO en la captura del cliente: con `Concrete` en gris medio
	// (124,134,146) el lobby se leia como una caja iluminada desde arriba,
	// sin horizonte ni referencia. Un suelo de un sitio con cesped tiene que
	// TENER color propio, no ser el gris de un material por defecto.
	part("LobbyFloor", {
		position: [0, -1, 0],
		size: [LOBBY_HALF * 2, 2, LOBBY_HALF * 2],
		material: "Concrete",
		color: [72, 88, 78],
	}),
	// `LobbyCenter` sigue siendo el centro GEOMETRICO (lo consultan los
	// verificadores de mapa). `LobbyReturn` es donde llega el jugador.
	marker("LobbyCenter", [0, 0.2, 0], { color: [200, 220, 255] }),
	// BUG CORREGIDO (medido en la captura del cliente): `MatchService` usaba
	// `LobbyCenter` como destino de TRASLADO al lobby, y ese punto es
	// exactamente donde esta el Keshusy Core (0, 0.5, 0) con su orbe
	// neon a Y = 8. Al volver de una ronda el jugador aparecia DENTRO del
	// orbe, en (0, 6.9, 0): la primera imagen del juego era una esfera
	// blanca con el personaje dentro.
	//
	// `LobbyReturn` es el sitio de LLEGADA real: al sur del Core, mirando
	// al norte, de cara al arco de portales y con el nucleo a la vista.
	// Asi el reencuentro con el corazon del juego es la primera lectura de
	// la pantalla, no un empuje al vacio.
	//
	// `LobbyCenter` NO se borra: se conserva como referencia del centro
	// geometrico y como contrato de los verificadores de mapa.
	marker("LobbyReturn", [0, 0.2, 46], { color: [150, 240, 200] }),
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

// ------------------------------------------------------------- LOS CINCO MUNDOS
//
// POR QUE LOS CINCO SE CONSTRUYEN IGUAL
// -------------------------------------
// Antes Forest tenia su propio bloque de ~1100 lineas aqui y los otros cuatro
// usaban el generico de `tools/worlds.js`. Forest era, por tanto, el unico
// mundo que NO tenia zonas ni rutas: era una losa cuadrada de 180x180 con
// decoracion. Medido en runtime: bounding box ~211x212, 0 zonas, 0 rutas.
//
// Un mundo con motor propio es un mundo que puede volver a ser un cuadrado.
// Ahora los cinco pasan por el MISMO motor de zonas y lo unico que cambia entre
// ellos son los datos de `LAYOUTS` y la decoracion de `SCENERY`, que estan en
// `tools/worlds.js`.
//
// QUE APORTA CADA UNO (contrato con los servicios)
// ------------------------------------------------
//   Zones/                       zonas reales, con suelo, borde y obstaculos
//   Routes/                      recorridos reales entre zonas
//   Blocks/ CentralStructure/    piezas `Block_*` destruibles por bomba
//   Terrain/ Hazards/ Decoration/ Border/ Keshusy/
//   MonsterSpawns/               puntos `MonsterSpawn_<Id>_<nn>`, por zona
//   PowerupSpawns/               puntos de powerup en la zona de recompensa
//   SpawnPoint_<Id> BossSpawn_<Id> Exit_<Id>
//   ArenaFloor ArenaCenter ArenaNorth/South/East/West
//
// LOS NOMBRES NO SE TOCAN
// ----------------------
// `MatchService`, `VisualService`, `BombService`, `PowerupService` y
// `DestructionService` resuelven esas rutas por NOMBRE. Cambiar uno rompe el
// juego, y por eso el constructor de mundos no inventa ni un nombre nuevo para
// el contrato: solo anade `Zones/` y `Routes/`, que nadie leia antes.
//
// LAS POSICIONES
// --------------
// En cruz alrededor del lobby. Cada mundo mide ahora del orden de 350x400
// studs (antes 180x180), asi que la separacion entre centros es de 1200: con
// 800 los mundos se solaparian por los bordes y un jugador en Volcano veria el
// suelo de Cyber.
//
// Forest conserva su posicion historica (500, 0) por compatibilidad con las
// herramientas de verificacion que ya la tienen medida.

const WORLD_ORIGINS = [
	{ id: "Forest", cx: 500, cz: 0, seedBase: 100 },
	{ id: "Desert", cx: -1300, cz: 1300, seedBase: 1000 },
	{ id: "Ice", cx: 1300, cz: 1300, seedBase: 2000 },
	{ id: "Volcano", cx: -1300, cz: -1300, seedBase: 3000 },
	{ id: "Cyber", cx: 1300, cz: -1300, seedBase: 4000 },
];

const worldFolders = WORLD_ORIGINS.map(function (w) {
	return Worlds.buildWorld(
		{ part: part, decor: decor, marker: marker, folder: folder, light: pointLight },
		{ id: w.id, cx: w.cx, cz: w.cz, seedBase: w.seedBase }
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
// ------------------------------------------------------------------- HUD
//
// `StarterGui` se declara a mano en vez de con `$path` porque el HUD es un
// ARBOL DE INTERFACES que produce `tools/hud.js`, no un archivo suelto.
//
// Antes era `StarterGui: { $path: "src/StarterGui" }`, y lo unico que havia
// dentro era un Folder `UI` con un README. El HUD se construia por codigo
// dentro de `UIController.buildGui()`, o sea que en el SOURCE no habia
// NINGUNA interfaz que auditar: de ahi el "StarterGui = 0 hijos" del informe,
// que era cierto y a la vez la razon del problema.
//
// El `ScreenGui` va dentro de una carpeta `UI`, igual que antes, para no
// cambiar la ruta que ya leen las herramientas de auditoria.
const hudGui = Hud.buildHud();

/**
 * Convierte la definicion de `Lighting` en un script Luau para Studio.
 *
 * POR QUE HAY QUE GENERARLO
 * ------------------------
 * `Lighting` es un Servicio, no un modelo, asi que `import_rbxm` no lo
 * transporta: sus ajustes solo llegan si alguien los escribe en el DataModel
 * con el plugin MCP. Ese "alguien" es este script.
 *
 * Y tiene que ser GENERADO. La version anterior estaba escrita a mano y solo
 * sincronizaba el `ColorCorrectionEffect`; `Brightness`, `Ambient`,
 * `Atmosphere` y `BloomEffect` se quedaban con lo que hubiera en la sesion
 * (2.4 / 1.6 / 0.85) mientras el repositorio declaraba 1.05 / 0.7 / 1.05. La
 * partida se leia blanca y `source-runtime-diff` seguia dando PASS, porque ese
 * informe compara NOMBRES y CLASES, no valores. Dos listas de numeros que
 * nadie contrasta son una bomba de reloj: de ahi que la unica fuente sea la
 * definicion de `Lighting` de este mismo archivo.
 *
 * @param {object} lighting nodo `Lighting` del arbol del proyecto
 * @returns {string} contenido de tools/sync-lighting.lua
 */
function luauLightingScript(lighting) {
	const props = lighting.$properties;
	const children = Object.keys(lighting).filter((k) => !k.startsWith("$"));

	/** Sin ceros de relleno ni ruido: 1.05, no 1.0500000000000000444. */
	const toFixed = (n) => String(Math.round(n * 1000) / 1000);

	/** Valor JS -> literal Luau. Los colores llegan como [r,g,b] en 0..1. */
	const luaValue = (v) => {
		if (typeof v === "number") return toFixed(v);
		if (typeof v === "boolean") return v ? "true" : "false";
		if (typeof v === "string") return JSON.stringify(v);
		if (Array.isArray(v) && v.length === 3 && v.every((n) => typeof n === "number"))
			return `Color3.fromRGB(${Math.round(v[0] * 255)}, ${Math.round(v[1] * 255)}, ${Math.round(v[2] * 255)})`;
		if (Array.isArray(v)) return `{ ${v.map(luaValue).join(", ")} }`;
		throw new Error("sync-lighting: valor no convertible: " + JSON.stringify(v));
	};

	const propLines = Object.keys(props).map((k) => `Lighting.${k} = ${luaValue(props[k])}`);

	const childBlocks = children.map((name) => {
		const node = lighting[name];
		const cls = node.$className;
		const assigns = Object.keys(node.$properties)
			.map((k) => `\tfx.${k} = ${luaValue(node.$properties[k])}`)
			.join("\n");
		return [
			`-- ${name}: se reutiliza si ya existe, para no duplicar el efecto.`,
			`local fx = Lighting:FindFirstChild("${name}")`,
			`if not (fx and fx:IsA("${cls}")) then`,
			`\tfx = Instance.new("${cls}")`,
			`\tfx.Name = "${name}"`,
			`\tfx.Parent = Lighting`,
			`end`,
			assigns,
		].join("\n");
	});

	return [
		"-- sync-lighting.lua",
		"-- ARCHIVO GENERADO por tools/generate-project.js. NO editar a mano: se",
		"-- sobrescribe en cada generacion y el valor unico esta en la",
		"-- definicion de `Lighting` de ese generador.",
		"--",
		"-- MEDIDO con tools/probe-lighting.lua: antes de generarse, este script",
		"-- solo creaba el ColorCorrectionEffect y dejaba el resto del Servicio",
		"-- con los valores de la sesion (Brightness 2.4, Haze 1.6, Threshold",
		"-- 0.85). El lobby salia blanco y nada lo delataba.",
		"",
		'local Lighting = game:GetService("Lighting")',
		"",
		"-- Ajustes del propio Servicio.",
		propLines.join("\n"),
		"",
		"-- Efectos hijos.",
		childBlocks.join("\n\n"),
		"",
		'return ("Lighting sincronizado: brillo %s, %d efectos"):format(',
		"\tLighting.Brightness,",
		"\t#Lighting:GetChildren()",
		")",
		"",
	].join("\n");
}

const project = {
	name: "KeshusyTomy-LanD",
	tree: {
		$className: "DataModel",

		ReplicatedStorage: { $path: "src/ReplicatedStorage" },
		ServerScriptService: { $path: "src/ServerScriptService" },

		// Se declara `folder("UI", ...)` porque el HUD es un ARBOL DE
		// INTERFACES que produce `tools/hud.js`, no un archivo suelto, y con
		// `$path` solo no se puede.
		//
		// Antes era `StarterGui: { $path: "src/StarterGui" }`, y lo unico que
		// habia dentro era un Folder `UI` con un README. El HUD se construia
		// por codigo dentro de `UIController.buildGui()`, o sea que en el
		// SOURCE no habia NINGUNA interfaz que auditar: de ahi el
		// "StarterGui = 0 hijos" del informe, que era cierto y a la vez la
		// razon del problema.
		//
		// OJO con la asignacion: `StarterGui: folder("UI", [...]).node` NO
		// anade una carpeta `UI` DENTRO de StarterGui, sino que USA ese Folder
		// COMO si fuera el propio StarterGui. Rojo aplanaba un nivel y el HUD
		// acababa en `StarterGui.KeshusyHUD` mientras el script de merge lo
		// colocaba en `StarterGui.UI.KeshusyHUD`: dos rutas distintas para el
		// mismo objeto, y `source-runtime-diff` lo daba por ausente para
		// siempre. Por eso se断言 el nombre de la carpeta explicitly.
		// OJO con `$className` y con el ORDEN de `Object.assign`.
		//
		// Rojo empareja este nodo con el SERVICIO `StarterGui` del DataModel,
		// y el servicio tiene su propia clase. Declararlo `"Folder"` hace que
		// Rojo cree una CARPETA llamada `StarterGui` en vez de rellenar el
		// servicio: el `ScreenGui` llegaba al build (`rojo build` lo serializa
		// sin quejarse) pero en PLAY `StarterGui` salia VACIO, asi que
		// `EffectsController` fallaba con "KeshusyHUD no existe" y
		// `InputController` se quedaba sin boton de bomba. Fallo invisible al
		// build: solo se veia ejecutando el juego.
		//
		// Y el orden importa de verdad: `folder()` ya trae su propio
		// `$className`, asi que con
		// `Object.assign({ $className: "StarterGui" }, folder(...).node)` el
		// "Folder" de la derecha pisaba al "StarterGui" de la izquierda y el
		// arreglo no hacia NADA. Por eso se borra la clave del nodo hijo
		// antes de asignar.
		//
		// La carpeta `UI` se mantiene DENTRO del servicio (no se aplana) para
		// no cambiar la ruta que leen las herramientas de auditoria.
		StarterGui: Object.assign(
			{ $className: "StarterGui" },
			Object.assign({}, folder("UI", [hudGui]).node, { $className: undefined })
		),

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
			// Los cinco mundos se construyen con el motor de zonas de
			// `tools/worlds.js`. Antes Forest se montaba aqui con su propio
			// bloque de ~1100 lineas y los otros cuatro con el generico:
			// dos caminos para la misma idea, y solo uno con zonas.
			Worlds: folder("Worlds", worldFolders).node,
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
				// MEDIDO en la captura del cliente: con `Brightness = 2.4` el
				// lobby salia BLANCO. El suelo de Concrete (124,134,146)
				// quemado a blanco, los portales del color que tuvieran
				// perdian el tono y el Keshusy Core se leia como una mancha
				// palida sin forma. `Brightness` multiplica la luz final: por
				// encima de ~1.2 satura los canales y TODO el mapa se ve
				// igual. El valor de un lugar iluminado tiene que dejar
				// margen para que el Neon y el Bloom tienen algo que destacar.
				ClockTime: 15.2,
				Brightness: 1.05,
				// Ambiente mas bajo y mas frio que antes. Antes (92,104,118)
				// rellenaba cada sombra de gris claro, y una sombra gris
				// clara sobre un suelo claro no es sombra: es ruido. Con un
				// ambiente oscuro el contraste lo pone la luz de las piezas.
				Ambient: color(52, 62, 78),
				OutdoorAmbient: color(74, 96, 92),
				// Menos difuso y menos especular: el terreno se leia como
				// plastico encerado cuando ambos estaban altos.
				EnvironmentDiffuseScale: 0.4,
				EnvironmentSpecularScale: 0.22,
				ShadowSoftness: 0.2,
			},
			Atmosphere: {
				$className: "Atmosphere",
				$properties: {
					// `Haze = 1.6` con `Glare = 0.25` metia una lechada blanca
					// sobre las paredes lejanas. La niebla debe dar PROFUNDIDAD
					// (saber que hay algo mas alla), no borrar el color.
					Density: 0.18,
					Haze: 0.7,
					Color: color(150, 186, 180),
					Decay: color(96, 124, 116),
					Glare: 0.02,
					Offset: 0.15,
				},
			},
			// Tinte y saturacion. Sin esto el mapa se lava hacia el cyan:
			// el cielo, la niebla y el Neon comparten tono y no hay
			// jerarquia de color. El contraste-enhanced separa el
			// personaje del fondo, que es lo que hace legible una escena.
			KeshusyGrade: {
				$className: "ColorCorrectionEffect",
				$properties: {
					Brightness: 0.01,
					Contrast: 0.16,
					Saturation: 0.12,
					TintColor: color(255, 248, 238),
				},
			},
			ForestBloom: {
				$className: "BloomEffect",
				$properties: {
					// `Threshold = 0.85` con el lobby quemado hacia blanco
					// hacia que el bloom se comiera los portales enteros. Un
					// umbral por encima de 1 deja brillar SOLO lo que de
					// verdad es una fuente de luz (el Core, los cristales,
					// las explosiones) y no las superficies claras.
					Intensity: 0.3,
					Size: 24,
					Threshold: 1.05,
				},
			},
		},
	},
};

// Puerta de MATERIALES antes de escribir. Ver `checkMaterials`: Rojo falla al
// compilar con un error que no dice donde, y es media hora perdida por un
// color escrito en el campo equivocado. Aqui el error dice el camino.
const materialProblems = [];
checkMaterials(project.tree, "", materialProblems);

if (materialProblems.length) {
	console.error("MATERIALES INVALIDOS (" + materialProblems.length + "):");
	for (const p of materialProblems.slice(0, 20)) console.error("  - " + p);
	if (materialProblems.length > 20) console.error("  ... y " + (materialProblems.length - 20) + " mas");
	process.exit(1);
}

fs.writeFileSync(PROJECT, JSON.stringify(project, null, 2) + "\n");

// ---------------------------------------------------------------------------
// tools/sync-lighting.lua
//
// `Lighting` es un SERVICIO: `import_rbxm` solo trabaja con modelos, asi que
// sus ajustes NUNCA viajan a Studio por la via normal. Antes de este paso,
// `sync-lighting.lua` estaba escrito a mano y solo creaba el
// `ColorCorrectionEffect`: `Brightness`, `Ambient`, `Atmosphere` y
// `BloomEffect` se quedaban en los valores de la sesion vieja (Brightness
// 2.4, Haze 1.6, Threshold 0.85) y el lobby seguia quemado a blanco aunque
// el repositorio dijera lo contrario. MEDIDO con `tools/probe-lighting.lua`.
//
// Se GENERA desde la misma definicion de arriba en vez de escribirse a mano,
// por una sola razon: dos listas de valores siempre divergen, y aqui la
// divergencia era invisible, porque el unico sitio donde se nota es una
// captura de pantalla que nadie mira hasta tarde.
// ---------------------------------------------------------------------------
fs.writeFileSync(
	path.join(__dirname, "sync-lighting.lua"),
	luauLightingScript(project.tree.Lighting),
	"utf8"
);

console.log("default.project.json y tools/sync-lighting.lua generados.");
console.log("  mundos:", WORLD_ORIGINS.length);
for (const w of WORLD_ORIGINS) {
	const L = Worlds.LAYOUTS[w.id];
	console.log(
		`  ${w.id.padEnd(8)} zonas ${String(L.zones.length).padStart(2)}` +
		`  rutas ${String(L.routes.length).padStart(2)}`
	);
}
console.log("  parts de lobby:", lobbyParts.length);
console.log("  spawnlocations:", lobbySpawns.length);
