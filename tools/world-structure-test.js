"use strict";

// world-structure-test.js
// Verifica que los CINCO MUNDOS son mundos jugables y no arenas cuadradas.
//
// POR QUE ESTE SCRIPT EXISTE
// --------------------------
// La version anterior de los cinco mundos era esto:
//
//   losa cuadrada de 180x180 + decoracion + Arena + BossSpawn
//
// Todo el arbol de nombres estaba bien, el contrato con los servicios se
// cumplia, `world-contract-verify` daba PASS y Rojo compilaba. Y aun asi era un
// FAIL: bounding box ~210x210, 0 zonas, 0 rutas, un unico punto de decision.
//
// Un verificador de CONTRATO no puede detectar eso, porque un cuadrado lleno de
// decoracion cumple el contrato igual que un mundo. Lo que este script mide es
// ESTRUCTURA DE JUEGO:
//
//   - cuantas zonas hay y si cada una tiene geometria real;
//   - cuantas rutas hay y si de verdad conectan zonas DISTINTAS;
//   - encuentros, destruccion, recompensa, arena, boss y salida;
//   - las DISTANCIAS del recorrido principal, para que las zonas no esten
//     concentradas en un solo punto del mapa.
//
// TODO SE MIDE SOBRE `default.project.json`
// ----------------------------------------
// El arbol GENERADO, no el runtime. Motivo: el generador es la fuente de verdad
// y un fallo de estructura debe romper el build, no aparecer tres semanas
// despues en una captura de pantalla. `tools/world-contract-verify.js` sigue
// siendo la puerta de RUNTIME; esta es la de FUENTE.
//
// Uso:  node tools/world-structure-test.js
// Sale con codigo 1 si algun mundo falla.

const fs = require("fs");
const path = require("path");
const Worlds = require("./worlds");

const ROOT = path.join(__dirname, "..");
const PROJECT = path.join(ROOT, "default.project.json");

const WORLD_IDS = ["Forest", "Desert", "Ice", "Volcano", "Cyber"];

/**
 * MINIMOS por mundo.
 *
 * No son arbitros: son la cantidad por debajo de la cual un mapa deja de
 * ofrecer recorrido. Un mundo con 2 zonas tiene una decision; uno con 11 tiene
 * una estructura.
 */
const MIN = {
	zoneCount: 8,
	routeCount: 8,
	encounterCount: 2,
	// Distancia minima de cada tramo del recorrido principal, en studs. Un tramo
	// mas corto significa que dos hitos estan uno encima del otro: el jugador no
	// percibe que avanza.
	legSpawnToFirst: 70,
	legFirstToDestruction: 70,
	legDestructionToIntermediate: 70,
	legIntermediateToArena: 70,
	legArenaToBoss: 60,
	legBossToExit: 60,
	// Radio minimo del mundo: por debajo, cabe entero en una sola pantalla.
	minRadius: 170,
	// Espacio libre MINIMO entre los bordes de dos zonas que una ruta une. Por
	// debajo, la ruta atraviesa pared: no es un camino, es decoracion.
	minRouteGap: 12,
};

/** Aplana el proyecto a una lista de {path, node, className}. */
function readTree() {
	const json = JSON.parse(fs.readFileSync(PROJECT, "utf8"));
	const out = [];

	(function walk(node, prefix) {
		for (const key of Object.keys(node)) {
			if (key.startsWith("$")) continue;
			const child = node[key];
			if (!child || typeof child !== "object") continue;
			const here = prefix ? prefix + "." + key : key;
			out.push({ path: here, node: child, className: child.$className || "?" });
			walk(child, here);
		}
	})(json.tree, "");

	return { flat: out, json: json };
}

/** Posicion de una pieza, o null si el nodo no es una pieza. */
function posOf(entry) {
	const p = entry.node && entry.node.$properties && entry.node.$properties.Position;
	return Array.isArray(p) ? p : null;
}

/** Distancia en el plano XZ, que es la que ve el jugador al caminar. */
function dist(a, b) {
	return Math.sqrt((a[0] - b[0]) * (a[0] - b[0]) + (a[2] - b[2]) * (a[2] - b[2]));
}

// ------------------------------------------------------- POR MUNDO

/**
 * Analiza un mundo del arbol GENERADO y devuelve sus medidas y sus problemas.
 *
 * @param {string} id id del mundo
 * @param {Array} flat arbol aplanado de `readTree`
 * @returns {object} medidas y lista de problemas
 */
function analyzeWorld(id, flat) {
	const prefix = "Workspace.Worlds." + id + ".";
	const mine = flat.filter((e) => e.path.startsWith(prefix));
	const problems = [];
	const layout = Worlds.LAYOUTS[id];

	const zonesEntry = mine.find((e) => e.path === prefix + "Zones");
	const routesEntry = mine.find((e) => e.path === prefix + "Routes");

	const zoneNames = zonesEntry
		? Object.keys(zonesEntry.node).filter((k) => !k.startsWith("$"))
		: [];
	const routeNames = routesEntry
		? Object.keys(routesEntry.node).filter((k) => !k.startsWith("$"))
		: [];

	// Cada zona debe tener geometria REAL: suelo, borde y piezas solidas. Una
	// carpeta llamada `Zone1` con tres decoraciones dentro es exactamente el
	// caso que hay que rechazar, y por eso se cuentan PIEZAS y no nombres.
	//
	// El minimo de BORDE baja de 3 a 1 porque el muro de una zona ya no es un
	// anillo cerrado (ver `zoneRim` en `tools/worlds.js`): se construye solo en
	// el arco que mira a una zona vecina, porque un muro que mira al vacio es
	// contencion, que es justo lo que este P0 elimina. Una zona-hoja (una
	// salida, un claro sin continuacion) tiene una sola particion y sigue siendo
	// un lugar jugable con suelo, borde y solidas.
	let zonesWithFloor = 0;
	for (const zn of zoneNames) {
		const zprefix = prefix + "Zones." + zn + ".";
		const kids = mine.filter((e) => e.path.startsWith(zprefix));
		const floor = kids.filter((e) => /_Core$|_Slab_\d+$/.test(e.path));
		const rim = kids.filter((e) => /_Rim_\d+$/.test(e.path));
		const zoneId = zn.replace(/^Zone_[A-Za-z]+_/, "");
		const zoneSpec = layout.zones.find((zone) => zone.id === zoneId);
		const core = mine.find((entry) => entry.path === zprefix + zn + "_Core");
		const coreBounds = core ? require("./world-navigation-test").aabbOf(core) : null;
		const containsCenter = (entry) => {
			const position = posOf(entry);
			return !!(position && coreBounds
				&& position[0] >= coreBounds.x0 && position[0] <= coreBounds.x1
				&& position[2] >= coreBounds.z0 && position[2] <= coreBounds.z1);
		};
		let roleContent = true;
		let roleContentReason = "";
		if (zoneSpec) {
			switch (zoneSpec.role) {
				case "encounter":
				case "intermediate":
					roleContent = kids.some((entry) => /\.Cover_/.test(entry.path));
					roleContentReason = "combat cover missing";
					break;
				case "destruction": {
					const blocks = mine.filter((entry) => entry.path.includes(".Blocks.Block_") && containsCenter(entry));
					roleContent = blocks.length >= 3;
					roleContentReason = `only ${blocks.length} destructible blocks in zone bounds`;
					break;
				}
				case "reward":
					roleContent = kids.some((entry) => entry.path.endsWith("Reward_Pedestal_" + id));
					roleContentReason = "reward pedestal missing";
					break;
				case "miniboss":
					roleContent = kids.some((entry) => entry.path.endsWith("MiniBossSpawn_" + id + "_" + zoneId));
					roleContentReason = "miniboss spawn marker missing";
					break;
				case "secret":
					roleContent = kids.some((entry) => entry.className === "ProximityPrompt"
						&& entry.path.includes("SecretPrompt_" + id + "_" + zoneId));
					roleContentReason = "secret interaction prompt missing";
					break;
				case "exit":
					roleContent = mine.some((entry) => entry.path === prefix + "Exit_" + id && containsCenter(entry));
					roleContentReason = "exit marker missing or outside zone bounds";
					break;
				case "boss":
					roleContent = mine.some((entry) => entry.path === prefix + "BossSpawn_" + id && containsCenter(entry));
					roleContentReason = "boss spawn missing or outside zone bounds";
					break;
				case "arena":
					roleContent = mine.some((entry) => entry.path === prefix + "ArenaFloor" && containsCenter(entry));
					roleContentReason = "arena floor missing or outside zone bounds";
					break;
				case "entrance":
					roleContent = mine.some((entry) => entry.path === prefix + "SpawnPoint_" + id && containsCenter(entry));
					roleContentReason = "player spawn missing or outside zone bounds";
					break;
			}
		}
		if (floor.length >= 2 && rim.length >= 1 && roleContent) {
			zonesWithFloor++;
		} else {
			problems.push(
				`${id}.Zones.${zn}: no es una zona jugable ` +
				`(rol ${zoneSpec ? zoneSpec.role : "missing"}, suelo ${floor.length}, borde ${rim.length}, ` +
				`contenido ${roleContent ? "ok" : roleContentReason})`
			);
		}
	}

	// Cada ruta debe tener OBOS en zonas DISTINTAS y un recorrido con suelo. Una
	// ruta con tres losas es decoracion, no una ruta.
	const routes = [];
	for (const rn of routeNames) {
		const m = /^Route_(\d+)_(.+?)_(.+)$/.exec(rn);
		if (!m) {
			problems.push(`${id}.Routes.${rn}: nombre ilegible`);
			continue;
		}
		if (m[2] === m[3]) problems.push(`${id}.Routes.${rn}: conecta una zona consigo misma`);
		const deck = mine.filter(
			(e) => e.path.startsWith(prefix + "Routes." + rn + ".") && /_Deck_\d+$/.test(e.path)
		);
		if (deck.length < 3) {
			problems.push(`${id}.Routes.${rn}: solo ${deck.length} losas; no es un recorrido`);
		}
		routes.push({ name: rn, from: m[2], to: m[3], decks: deck.length });
	}

	// Que cada zona sea ALCANZABLE. Una zona sin ninguna ruta es una isla: el
	// jugador no puede llegar, y por tanto no existe como contenido.
	const touched = {};
	for (const r of routes) {
		touched[r.from] = (touched[r.from] || 0) + 1;
		touched[r.to] = (touched[r.to] || 0) + 1;
	}
	for (const zn of zoneNames) {
		const short = zn.replace(/^Zone_[A-Za-z]+_/, "");
		if (!touched[short]) problems.push(`${id}.Zones.${zn}: no hay ninguna ruta que llegue`);
	}

	// Recorrido principal: el mundo declara su propia secuencia en
	// `LAYOUTS`, y aqui se comprueba que esa secuencia existe en el ARBOL.
	// Se toma de los papeles reales del rol, no de una lista escrita aqui: si un
	// mundo dejara de tener zona de recompensa, el test lo notaria.
	const byRole = {};
	for (const z of layout.zones) if (!byRole[z.role]) byRole[z.role] = z;

	const required = ["entrance", "exploration", "encounter", "destruction",
		"intermediate", "reward", "arena", "boss", "exit"];
	for (const role of required) {
		if (!byRole[role]) problems.push(`${id}: falta la zona con papel '${role}'`);
	}

	// SOLAPAMIENTO entre zonas. Dos elipses que se pisan mezclan sus suelos y
	// sus bordes: el mundo declara N zonas y en el mapa hay menos, y ademas las
	// rutas que las unen atraviesan pared. Es el fallo que mas se cuela, asi que
	// se mide para TODOS los pares y no solo para los que unen una ruta.
	let overlaps = 0;
	for (let i = 0; i < layout.zones.length; i++) {
		for (let k = i + 1; k < layout.zones.length; k++) {
			const a = layout.zones[i];
			const b = layout.zones[k];
			const dx = b.x - a.x;
			const dz = b.z - a.z;
			const d = Math.sqrt(dx * dx + dz * dz);
			if (d === 0) {
				overlaps++;
				problems.push(`${id}: zonas '${a.id}' y '${b.id}' en el mismo punto`);
				continue;
			}
			const ux = dx / d;
			const uz = dz / d;
			// Radio de cada elipse EN LA DIRECCION que las separa.
			const ra = 1 / Math.sqrt((ux / a.rx) ** 2 + (uz / a.rz) ** 2);
			const rb = 1 / Math.sqrt((ux / b.rx) ** 2 + (uz / b.rz) ** 2);
			if (d < ra + rb) {
				overlaps++;
				problems.push(
					`${id}: '${a.id}' y '${b.id}' se pisan ${(ra + rb - d).toFixed(0)} studs`
				);
			}
		}
	}

	// Verifica que el BORDE de cada zona este ABIERTO por donde entra una ruta.
	// Esta es la comprobacion de "el jugador puede pasar de verdad": si hay una
	// pieza `_Rim_i` en el angulo de la ruta, la ruta termina en un muro.
	//
	// OJO CON LAS COORDENADAS: las piezas del ARBOL estan en posicion ABSOLUTA
	// (ya desplazadas al mundo) y las zonas del `LAYOUTS` en LOCALES. Comparar
	// unas con otras daria un angulo sin sentido y marcaria rutas abiertas como
	// cerradas. Por eso el centro se lee del propio ARBOL, de la pieza
	// `Zone_<Id>_<Zona>_Center` que `buildWorld` escribe.
	const rimByZone = {};
	const centerByZone = {};
	for (const zn of zoneNames) {
		rimByZone[zn] = mine.filter(
			(e) => e.path.startsWith(prefix + "Zones." + zn + ".") && /_Rim_\d+$/.test(e.path)
		);
		const c = mine.find((e) => e.path === prefix + "Zones." + zn + "." + zn + "_Center");
		if (c) centerByZone[zn] = posOf(c);
	}

	// EL HUECO SE MIDE IGUAL QUE EN EL GENERADOR
	// --------------------------------------------
	// Esta comprobacion tiene que replicar el criterio de `zoneRim`, no uno mas
	// estricto. Medido: al abrir el hueco en STUDIOS (y no solo en angulo) el
	// generador dejo pasar rutas que esta prueba daba por cerradas, y el suite
	// entero se puso en rojo sin que el mapa hubiera cambiado.
	//
	// El generador abre `halfStuds / rr + (segW / 2) / rr`, donde `halfStuds` es
	// el ancho minimo de la ruta y el segundo termino es el angulo que invade
	// cada segmento tangente del borde.
	const layoutZones = {};
	for (const z of Worlds.LAYOUTS[id].zones) layoutZones[z.id] = z;

	for (const r of routes) {
		for (const side of ["from", "to"]) {
			const zoneShort = r[side];
			const ownFolder = "Zone_" + id + "_" + zoneShort;
			const ownCenter = centerByZone[ownFolder];
			const otherCenter = centerByZone[side === "from" ? "Zone_" + id + "_" + r.to : "Zone_" + id + "_" + r.from];
			if (!ownCenter || !otherCenter) continue;

			const zone = layoutZones[zoneShort];
			if (!zone) continue;

			const ang = Math.atan2(otherCenter[2] - ownCenter[2], otherCenter[0] - ownCenter[0]);

			// EL HUECO SE EVALUA SEGUNDO A SEGMENTO
			// --------------------------------------
			// El radio de la elipse cambia con la direccion, asi que el semiancho
			// angular que hay que abrir TAMBIEN. Calcularlo una sola vez, con el
			// radio en la direccion de la ruta, daba un valor MAYOR que el real
			// en los lados largos de la zona: el test declaraba cerrado un borde
			// que el generador abre. Medido en Forest: 64 rutas marcadas como
			// cerradas con el mapa ya corregido.
			//
			// Por eso `need` se calcula DENTRO del filtro, con el radio propio de
			// cada pieza, y por eso la funcion compartida recibe `rr` y no el
			// angulo.
			const halfStuds = Math.max(14 * 0.75, 16);
			const segs = Worlds.rimSegments(zone);

			const rims = rimByZone[ownFolder] || [];

			const blocking = rims.filter((e) => {
				const p = posOf(e);
				if (!p) return false;
				const a = Math.atan2(p[2] - ownCenter[2], p[0] - ownCenter[0]);
				const rrSeg = 1 / Math.sqrt(
					(Math.cos(a) / zone.rx) ** 2 + (Math.sin(a) / zone.rz) ** 2
				);
				const need = Worlds.rimOpeningHalfAngle(halfStuds, rrSeg, segs);
				const d = Math.abs(((a - ang + Math.PI * 3) % (Math.PI * 2)) - Math.PI);
				return d < need;
			});

			if (blocking.length > 0) {
				if (process.argv.includes("--why")) {
					const rims2 = rimByZone[ownFolder] || [];
					const list = rims2.map((e) => {
						const p = posOf(e);
						const a = Math.atan2(p[2] - ownCenter[2], p[0] - ownCenter[0]);
						const d = Math.abs(((a - ang + Math.PI * 3) % (Math.PI * 2)) - Math.PI);
						return { name: e.path.split(".").pop(), d: d.toFixed(4) };
					}).sort((x, y2) => Number(x.d) - Number(y2.d));
					console.log(
						`  WHY ${id} ${zoneShort}->${side === "from" ? r.to : r.from}: ang=${ang.toFixed(4)}` +
						` need=${need.toFixed(4)} rr=${rr.toFixed(1)} segs=${Worlds.rimSegments(zone)}` +
						` medioAngulo=${(Math.PI / Worlds.rimSegments(zone)).toFixed(4)}`
					);
					console.log("    mas cercanos: " + list.slice(0, 4).map((x) => `${x.name}@${x.d}`).join(" "));
				}
				problems.push(
					`${id}: el borde de '${zoneShort}' cierra la entrada a '${r.name}' ` +
					`(${blocking.length} muro(s) en el angulo de la ruta)`
				);
			}
		}
	}

	const centerOf = (role) => {
		const z = byRole[role];
		return z ? [z.x, z.y, z.z] : null;
	};

	// Distancias del recorrido. Se miden sobre las coordenadas del layout, que
	// son las que se escriben en el arbol: `buildWorld` solo les suma el origen
	// del mundo, y una traslacion no cambia una distancia.
	const legs = [];
	function leg(label, aRole, bRole, min) {
		const a = centerOf(aRole);
		const b = centerOf(bRole);
		if (!a || !b) return;
		const d = dist(a, b);
		legs.push({ label, dist: d, min });
		if (d < min) {
			problems.push(`${id}: tramo ${label} mide ${d.toFixed(0)} studs (minimo ${min})`);
		}
	}

	leg("Spawn->FirstEncounter", "entrance", "encounter", MIN.legSpawnToFirst);
	leg("FirstEncounter->Destruction", "encounter", "destruction", MIN.legFirstToDestruction);
	leg("Destruction->Intermediate", "destruction", "intermediate", MIN.legDestructionToIntermediate);
	leg("Intermediate->Arena", "intermediate", "arena", MIN.legIntermediateToArena);
	leg("Arena->Boss", "arena", "boss", MIN.legArenaToBoss);
	leg("Boss->Exit", "boss", "exit", MIN.legBossToExit);

	// Extension del mundo: bounding box de las piezas con posicion.
	let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
	let parts = 0;
	for (const e of mine) {
		const p = posOf(e);
		if (!p) continue;
		parts++;
		minX = Math.min(minX, p[0]); maxX = Math.max(maxX, p[0]);
		minZ = Math.min(minZ, p[2]); maxZ = Math.max(maxZ, p[2]);
	}
	const spanX = maxX - minX;
	const spanZ = maxZ - minZ;
	const radius = Math.max(spanX, spanZ) / 2;
	if (radius < MIN.minRadius) {
		problems.push(
			`${id}: bounding box ${spanX.toFixed(0)}x${spanZ.toFixed(0)}; ` +
			`cabe entero en ${MIN.minRadius} studs de radio`
		);
	}

	// La silueta debe ser IRREGULAR. Un cuadrado de 350x350 con todo dentro es
	// un cuadrado, por muy decorado que este: se mide que proporcion de las
	// piezas cae fuera del rectangulo central que lo contiene.
	const cxBox = (minX + maxX) / 2;
	const czBox = (minZ + maxZ) / 2;
	let outside = 0;
	for (const e of mine) {
		const p = posOf(e);
		if (!p) continue;
		if (Math.abs(p[0] - cxBox) > spanX * 0.41 || Math.abs(p[2] - czBox) > spanZ * 0.41) outside++;
	}
	const irregularRatio = parts > 0 ? outside / parts : 0;

	// Contrato de nombres. Si esto falla, los servicios no encuentran nada:
	// `MatchService` busca `ArenaCenter`, `BombService` busca `ArenaFloor`,
	// `PowerupService` busca `PowerupSpawns`, `DestructionService` el prefijo
	// `Block_`, y asi los demas.
	const contract = [
		"ArenaFloor", "ArenaCenter", "ArenaNorth", "ArenaSouth", "ArenaEast", "ArenaWest",
		"SpawnPoint_" + id, "BossSpawn_" + id, "Exit_" + id,
		"Blocks", "CentralStructure", "Terrain", "Hazards", "Decoration",
		"Border", "Keshusy", "MonsterSpawns", "PowerupSpawns",
	];
	for (const c of contract) {
		if (!mine.find((e) => e.path === prefix + c)) {
			problems.push(`${id}: falta el contrato '${c}'`);
		}
	}

	// Los separadores de `readTree` son PUNTOS, no barras: los caminos reales son
	// `Workspace.Worlds.Desert.Blocks.Block_Desert_0`, no `Desert/Blocks/...`.
	// Se cuentan por el nombre de la CARPETA de contrato seguido de un punto, que
	// es la unica forma de no contar como bloque un decorativo que lleve `Block_`
	// en medio de su nombre.
	const blocks = mine.filter((e) => e.path.startsWith(prefix + "Blocks.Block_") && e.className === "Part").length;
	const centralBlocks = mine.filter(
		(e) => e.path.startsWith(prefix + "CentralStructure.Block_") && e.className === "Part"
	).length;
	const monsterSpawns = mine.filter(
		(e) => e.path.startsWith(prefix + "MonsterSpawns.MonsterSpawn_")
	).length;
	const powerups = mine.filter(
		(e) => e.path.startsWith(prefix + "PowerupSpawns.PowerupSpawn_")
	).length;
	const encounters = layout.zones.filter(
		(z) => z.role === "encounter" || z.role === "intermediate"
	).length;

	if (zoneNames.length < MIN.zoneCount) {
		problems.push(`${id}: ${zoneNames.length} zonas (minimo ${MIN.zoneCount})`);
	}
	if (routes.length < MIN.routeCount) {
		problems.push(`${id}: ${routes.length} rutas (minimo ${MIN.routeCount})`);
	}
	if (encounters < MIN.encounterCount) {
		problems.push(`${id}: ${encounters} zonas de encuentro (minimo ${MIN.encounterCount})`);
	}
	if (blocks < 8) problems.push(`${id}: solo ${blocks} bloques destructibles`);
	if (monsterSpawns < 4) problems.push(`${id}: solo ${monsterSpawns} spawns de monstruo`);
	if (powerups < 4) problems.push(`${id}: solo ${powerups} spawns de powerup`);

	return {
		id, problems,
		zoneCount: zoneNames.length,
		routeCount: routes.length,
		encounterCount: encounters,
		zonesWithFloor,
		blocks: blocks + centralBlocks,
		monsterSpawns, powerups,
		spanX, spanZ, radius,
		irregularRatio,
		parts,
		legs,
		overlaps,
	};
}

// ------------------------------------------------------------- MAIN

function main() {
	if (!fs.existsSync(PROJECT)) {
		console.log("No existe default.project.json. Genera el proyecto primero con:");
		console.log("  node tools/generate-project.js");
		process.exitCode = 2;
		return;
	}

	const { flat } = readTree();
	const results = WORLD_IDS.map((id) => analyzeWorld(id, flat));

	console.log("ESTRUCTURA DE LOS MUNDOS (sobre default.project.json)");
	console.log("---------------------------------------------------------------");
	console.log("mundo      zonas  rutas  ging  dim. aproximada      radio  irreg.  probl.");

	let failed = 0;
	for (const r of results) {
		const ok = r.problems.length === 0;
		if (!ok) failed++;
		console.log(
			r.id.padEnd(10) +
			String(r.zoneCount).padStart(4) + "  " +
			String(r.routeCount).padStart(4) + "  " +
			String(r.zonesWithFloor).padStart(4) + "  " +
			(`${r.spanX.toFixed(0)} x ${r.spanZ.toFixed(0)}`).padEnd(16) +
			r.radius.toFixed(0).padStart(9) +
			(r.irregularRatio * 100).toFixed(1).padStart(7) + "%" +
			(ok ? "     0" : String(r.problems.length).padStart(9))
		);
	}

	console.log("");
	console.log("RECORRIDO PRINCIPAL (studs; el minimo va en parentesis)");
	for (const r of results) {
		console.log("  " + r.id + ":");
		for (const l of r.legs) {
			const mark = l.dist >= l.min ? " " : "!";
			console.log(
				`    ${mark} ${l.label.padEnd(30)} ${l.dist.toFixed(0).padStart(5)}  (min ${l.min})`
			);
		}
	}

	console.log("");
	console.log("CONTENIDO POR MUNDO");
	for (const r of results) {
		console.log(
			`  ${r.id.padEnd(8)} bloques ${String(r.blocks).padStart(3)}` +
			`  monstruos ${String(r.monsterSpawns).padStart(3)}` +
			`  powerups ${String(r.powerups).padStart(3)}` +
			`  piezas ${String(r.parts).padStart(4)}`
		);
	}

	console.log("");
	if (failed) {
		console.log(`PROBLEMAS REALES (${failed} mundo(s) no cumplen la estructura):`);
		for (const r of results) {
			for (const p of r.problems) console.log("  - " + p);
		}
		console.log("");
		console.log("ESTRUCTURA DE MUNDOS: FAIL");
		process.exitCode = 1;
		return;
	}

	console.log("ESTRUCTURA DE MUNDOS: PASS");
	console.log("Los cinco tienen zonas con geometria real, rutas que conectan zonas");
	console.log("distintas, encuentros, destruccion, recompensa, arena, boss y salida,");
	console.log("con el recorrido repartido por el mapa y no concentrado en un punto.");
}

main();
