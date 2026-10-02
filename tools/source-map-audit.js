// source-map-audit.js
// Compara el MAPA declarado en default.project.json con el mapa que el
// juego ve de verdad en Studio.
//
// Por que existe: los dos pueden discrepar sin que nada falle. Rojo puede
// tener un proyecto adjunto distinto, el lugar puede haberse editado a mano,
// o el generador puede haberse ejecutado despues de la ultima
// sincronizacion. Este script imprime los dos lados para que la diferencia
// sea evidente en vez de inferida.
//
// Uso:  node tools/source-map-audit.js

const fs = require("fs");
const path = require("path");
const mcp = require("./mcp");

const ROOT = path.resolve(__dirname, "..");

// Claves de metadatos de Rojo: no son instancias hijas.
const META_KEYS = new Set(["$className", "$path", "$properties", "$ignoreUnknownInstances", "$hidden"]);

/**
 * Devuelve los hijos reales de un nodo del proyecto.
 *
 * Rojo 7 NO usa una clave `Children`: cada hijo es un CAMPO mas de la
 * instancia padre y la clave ES su nombre. Por eso un recorrido que busque
 * `node.children` no encuentra NADA y hace parecer que el mapa no esta
 * declarado cuando si lo esta.
 */
function nodeChildren(node) {
	if (!node || typeof node !== "object") return [];
	return Object.keys(node)
		.filter((k) => !META_KEYS.has(k))
		.map((name) => ({ Name: name, node: node[name] }));
}

/** Aplana el arbol de `default.project.json` a rutas "A.B.C". */
function flattenProject(node, prefix, out, depth = 0) {
	// `$path` mapea un DIRECTORIO: sus hijos reales estan en el disco, no en
	// el JSON. Sin este corte el recorrido intenta descender por la cadena
	// `$properties`/`$path` y se desborda la pila.
	if (depth > 12) return out;
	if (!node || typeof node !== "object") return out;

	if (node.$path) {
		out.push((prefix ? prefix + " -> " : "") + "$path " + node.$path);
		return out;
	}

	if (node.Name) out.push(prefix ? `${prefix}.${node.Name}` : node.Name);
	for (const child of nodeChildren(node)) flattenProject(child, prefix, out, depth + 1);
	return out;
}

/** Lee los nombres de hijos reales de un contenedor del runtime. */
async function runtimeChildren(pathStr) {
	return mcp.serverLuau(`
local node = game
for _, seg in ipairs({${pathStr.split(".").map((s) => `"${s}"`).join(",")}}) do
    node = node:FindFirstChild(seg)
    if node == nil then return { missing = true } end
end
local out = {}
for _, c in ipairs(node:GetChildren()) do
    table.insert(out, c.Name)
end
return { missing = false, children = out }
`);
}

/** Nombres declarados bajo un path del proyecto. */
function projectChildrenUnder(pathStr) {
	const json = JSON.parse(fs.readFileSync(path.join(ROOT, "default.project.json"), "utf8"));
	const segs = pathStr.split(".");

	// La raiz (`tree`) es el DataModel: no tiene `Name`, asi que el primer
	// segmento se busca entre sus hijos.
	let node = json.tree;
	for (let i = 0; i < segs.length; i++) {
		if (!node) return null;
		const child = nodeChildren(node).find((c) => c.Name === segs[i]);
		if (!child) return null;
		node = child.node;
	}
	if (!node) return null;
	return nodeChildren(node).map((c) => c.Name);
}

async function compare(label, pathStr) {
	const declared = projectChildrenUnder(pathStr);
	const live = await runtimeChildren(pathStr);

	console.log("");
	console.log(`${label}  (${pathStr})`);
	if (declared === null) {
		console.log("  SOURCE: el path no existe en default.project.json");
	} else {
		console.log(`  SOURCE declara ${declared.length} hijos`);
	}

	if (!live || live.missing) {
		console.log("  RUNTIME: el contenedor NO EXISTE");
		return { declared, live: null };
	}

	const liveNames = live.children;
	console.log(`  RUNTIME tiene ${liveNames.length} hijos`);
	const declaredSet = new Set(declared || []);
	const liveSet = new Set(liveNames);

	const missingInStudio = (declared || []).filter((n) => !liveSet.has(n));
	const extraInStudio = liveNames.filter((n) => !declaredSet.has(n));

	if (missingInStudio.length) {
		console.log(`  FALTAN EN STUDIO (${missingInStudio.length}): ${missingInStudio.slice(0, 25).join(", ")}`);
		if (missingInStudio.length > 25) console.log("      ...");
	}
	if (extraInStudio.length) {
		console.log(`  SOLO EN STUDIO (${extraInStudio.length}): ${extraInStudio.slice(0, 25).join(", ")}`);
	}
	if (!missingInStudio.length && !extraInStudio.length) console.log("  SIN DIVERGENCIA");

	return { declared, live: liveNames };
}

async function main() {
	const json = JSON.parse(fs.readFileSync(path.join(ROOT, "default.project.json"), "utf8"));
	console.log("SOURCE OF TRUTH: default.project.json (" + flattenProject(json.tree, "", []).length + " nodos)");

	const inst = await mcp.toolJson("get_connected_instances", {});
	const hasServer = inst?.instances?.some((i) => i.peers && i.peers.server);
	if (!hasServer) {
		console.log("SIN SERVIDOR EN VIVO: no se puede leer el runtime.");
		process.exitCode = 2;
		return;
	}

	await compare("LOBBY", "Workspace.Lobby");
	await compare("WORLDS", "Workspace.Worlds");
	await compare("FOREST", "Workspace.Worlds.Forest");
	await compare("FOREST/BLOCKS", "Workspace.Worlds.Forest.Blocks");
	await compare("SPAWNS", "Workspace.SpawnLocations");

	// `default.project.json` solo declara el mapa si el generador lo escribio
	// dentro del arbol; si el mapa vive fuera, esto avisa en vez de callar.
	const flat = flattenProject(json.tree, "", []).join("\n");
	const inTree = ["Portal_Forest_Base", "CoreOrb", "ArenaFloor", "Block_0"];
	console.log("");
	console.log("MAPA DENTRO DEL ARBOL DE ROJO (default.project.json.tree)");
	for (const n of inTree) {
		console.log(`  ${flat.includes(n) ? "SI" : "NO "}  ${n}`);
	}
}

main().catch((e) => {
	console.error("FALLO: " + e.message);
	process.exitCode = 2;
});
