"use strict";

// tmp-contract.js
// Comprueba el CONTRATO de nombres sobre el arbol GENERADO, sin Studio.
//
// Uso:  node tools/tmp-contract.js
//
// POR QUE NO SE USA `tools/world-contract-verify.js`
// -----------------------------------------------
// Ese script mide el runtime de Roblox Studio por MCP, asi que necesita un
// servidor en vivo. Este hace la misma comprobacion sobre
// `default.project.json`, que es la fuente de verdad: si el contrato se rompe
// aqui, se rompio antes de abrir Studio, y el fallo sale en segundos.
const fs = require("fs");
const path = require("path");

const json = JSON.parse(
	fs.readFileSync(path.join(__dirname, "..", "default.project.json"), "utf8")
);

const WORLDS = ["Forest", "Desert", "Ice", "Volcano", "Cyber"];

// Prefijos que los servicios localizan por NOMBRE.
const BLOCK_PREFIX = "Block_";
const MONSTER_PREFIX = "MonsterSpawn_";
const POWERUP_PREFIX = "PowerupSpawn_";
const HAZARD_PREFIX = "Hazard_";

/** Cuenta piezas descendiendo por el arbol. */
function countParts(node) {
	if (!node || typeof node !== "object") return 0;
	if (node.$className && /^Part$|^SpawnLocation$/.test(node.$className)) return 1;
	let n = 0;
	for (const k of Object.keys(node)) {
		if (k.startsWith("$")) continue;
		n += countParts(node[k]);
	}
	return n;
}

/** Nombres directos de un nodo. */
function children(node) {
	return node ? Object.keys(node).filter((k) => !k.startsWith("$")) : [];
}

/** Cuenta descendientes cuyo nombre empieza por `prefix`. */
function countByPrefix(node, prefix) {
	let n = 0;
	for (const k of children(node)) {
		if (k.startsWith(prefix)) n++;
		n += countByPrefix(node[k], prefix);
	}
	return n;
}

const problems = [];
const worlds = json.tree.Workspace.Worlds;

console.log("CONTRATO DE MUNDOS (sobre default.project.json)");
console.log("---------------------------------------------------------------");
console.log(
	"mundo      partes   spawn   ArenaFloor  bloques  hazards  monstruos  powerups  BossSpawn  Exit"
);

for (const id of WORLDS) {
	const w = worlds[id];
	if (!w) {
		problems.push(id + ": no existe en Workspace.Worlds");
		continue;
	}

	const parts = countParts(w);
	const spawns = children(w).filter((n) => w[n].$className === "SpawnLocation").length;
	const floor = w.ArenaFloor ? 1 : 0;
	const blocks = countByPrefix(w, BLOCK_PREFIX);
	const hazards = countByPrefix(w, HAZARD_PREFIX);
	const monsters = countByPrefix(w, MONSTER_PREFIX);
	const powerups = countByPrefix(w, POWERUP_PREFIX);
	const boss = w["BossSpawn_" + id] ? 1 : 0;
	const exit = w["Exit_" + id] ? 1 : 0;

	console.log(
		id.padEnd(10) +
		String(parts).padStart(6) +
		String(spawns).padStart(8) +
		String(floor).padStart(12) +
		String(blocks).padStart(9) +
		String(hazards).padStart(9) +
		String(monsters).padStart(11) +
		String(powerups).padStart(10) +
		String(boss).padStart(11) +
		String(exit).padStart(5)
	);

	if (spawns < 1) problems.push(id + ": sin SpawnLocation");
	if (!floor) problems.push(id + ": falta ArenaFloor (BombService no hallaria limite)");
	if (blocks < 1) problems.push(id + ": sin bloques " + BLOCK_PREFIX + " (no habria destruccion)");
	if (monsters < 1) problems.push(id + ": sin " + MONSTER_PREFIX);
	if (powerups < 1) problems.push(id + ": sin " + POWERUP_PREFIX);
	if (!boss) problems.push(id + ": falta BossSpawn_" + id);
	if (!exit) problems.push(id + ": falta Exit_" + id);

	// Las carpetas de contrato que los servicios recorren.
	for (const folderName of ["Blocks", "CentralStructure", "Terrain", "Hazards",
		"Decoration", "Border", "Keshusy", "MonsterSpawns", "PowerupSpawns",
		"Zones", "Routes"]) {
		if (!w[folderName]) problems.push(id + ": falta la carpeta '" + folderName + "'");
	}
}

// PORTALES. El contrato con `PortalService` es `Portal_<Id>` con `PortalPanel`.
console.log("");
console.log("PORTALES");
const portals = json.tree.Workspace.Lobby.Portals;
let portalCount = 0;
for (const id of WORLDS) {
	const p = portals["Portal_" + id];
	const panel = p && p.PortalPanel;
	const hasSign = p && p.Sign;
	const ok = !!(p && panel && hasSign && panel.$properties.CanCollide === false);
	portalCount += ok ? 1 : 0;
	console.log(
		"  Portal_" + id.padEnd(10) +
		(p ? " existe" : " AUSENTE") +
		"  panel " + (panel ? "si" : "NO") +
		"  cartel " + (hasSign ? "si" : "NO") +
		"  colision " + (panel && panel.$properties.CanCollide === false ? "libre" : "BLOQUEA") +
		"  " + (ok ? "PASS" : "FAIL")
	);
	if (!ok) problems.push("Portal_" + id + ": contrato incompleto");
}

// LOBBY. Los destinos que leen `MatchService`.
console.log("");
console.log("LOBBY");
for (const n of ["LobbyCenter", "LobbyReturn", "KeshusyCore", "Portals"]) {
	const exists = !!json.tree.Workspace.Lobby[n];
	console.log("  " + n.padEnd(16) + (exists ? "PASS" : "FAIL"));
	if (!exists) problems.push("Lobby: falta '" + n + "'");
}

console.log("");
if (problems.length) {
	console.log("CONTRATO: FAIL (" + problems.length + ")");
	for (const p of problems) console.log("  - " + p);
	process.exitCode = 1;
} else {
	console.log("CONTRATO: PASS");
}
