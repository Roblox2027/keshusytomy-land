// inspect-project.js
// Muestra un subarbol de `default.project.json` ya expandido.
//
// POR QUE EXISTE
// --------------
// Rojo aplana los hijos a campos directos y los `$path` a directorios del
// disco, asi que el JSON no se puede leer a ojo. Este script recorre el
// arbol con la misma logica que Rojo (una clave por hijo, `$` reservado)
// e imprime la estructura legible, con las coordenadas de cada Part.
//
// Esa ultima parte es la que importa: una Part en `(0, 0, 0)` en el
// generador aparece igual en el JSON que en el output de Studio, y en
// ambos casos parece "correcta" hasta que se comparan con la posicion que
// el diseno pedia.
//
// Uso:
//   node tools/inspect-project.js Workspace.Lobby
//   node tools/inspect-project.js Workspace.Lobby.Portals --full

const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const PROJECT = path.join(ROOT, "default.project.json");

// Claves de metadatos de Rojo: no son instancias hijas.
const META_KEYS = new Set(["$className", "$path", "$properties", "$ignoreUnknownInstances", "$hidden"]);

/** Formatea [x,y,z] como coordenadas legibles. */
function fmtVec(value) {
	if (Array.isArray(value) && value.length === 3) {
		return `(${value.map((n) => Math.round(n)).join(", ")})`;
	}
	return null;
}

function walk(node, prefix, depth, full) {
	if (depth > 6) return;

	for (const key of Object.keys(node)) {
		if (META_KEYS.has(key)) continue;
		const child = node[key];
		if (!child || typeof child !== "object") continue;

		const here = `${prefix}.${key}`;
		const cls = child.$className || "?";
		const props = child.$properties || {};

		const pos = fmtVec(props.Position);
		const details = [];
		if (pos) details.push(`pos ${pos}`);
		if (props.Size) details.push(`size ${fmtVec(props.Size) || JSON.stringify(props.Size)}`);
		if (props.CollisionGroup) details.push("collide=false");
		if (props.Transparency !== undefined) details.push(`transp ${props.Transparency}`);

		console.log(`  ${key} [${cls}]${details.length ? "  " + details.join("  ") : ""}`);

		if (full || Object.keys(child).some((k) => !META_KEYS.has(k))) {
			walk(child, here, depth + 1, full);
		}
	}
}

function main() {
	const target = process.argv[2] || "Workspace.Lobby";
	const full = process.argv.includes("--full");

	const json = JSON.parse(fs.readFileSync(PROJECT, "utf8"));

	// La raiz del proyecto es el DataModel y no tiene `Name`, asi que el
	// primer segmento se busca entre sus hijos.
	let node = json.tree;
	for (const seg of target.split(".")) {
		if (!node) break;
		const child = Object.keys(node)
			.filter((k) => !META_KEYS.has(k))
			.find((k) => k === seg);
		if (!child) {
			console.log(`"${seg}" no existe bajo el camino indicado.`);
			process.exit(1);
		}
		node = node[child];
	}

	console.log(`${target} [${node.$className || "?"}]`);
	walk(node, target, 1, full);
}

main();
