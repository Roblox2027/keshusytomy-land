"use strict";

/*
	forest-verify.js
	PRUEBA ESTRUCTURAL de la reconstruccion de Keshusy Forest.

	No sustituye a mirar el juego: comprueba lo que se PUEDE comprobar con
	certeza, que son las cosas que mas caro salen si se rompen:

	  1. CONTRATO DE JUEGO  los 48 `Block_*` siguen ahi, en
	     `Workspace.Worlds.Forest.Blocks`, como `BasePart`, con colision
	     y sin hijos que TAMBIÉN empiecen por `Block_` (un hijo asi
	     contaria como bloque y el recuento pasaria de 48).
	  2. VARIEDAD         los bloques NO son 48 cubos iguales: se mide
	     cuantos tamanos, materiales, orientaciones y variantes hay.
	  3. DECORACION       toda la decoracion es `CanCollide = false`.
	  4. SPAWN            los 6 spawns miran al centro.
	  5. ILUMINACION      hay ambiente, niebla y bloom, con presupuesto.

	Uso:  node tools/forest-verify.js
	Codigo de salida 0 si todo pasa.
*/

const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..");
const proj = JSON.parse(fs.readFileSync(path.join(ROOT, "default.project.json"), "utf8"));

function children(node) {
	if (!node || typeof node !== "object") return [];
	return Object.keys(node)
		.filter((k) => k !== "$className" && k !== "$properties" && k !== "$path" && k !== "$attributes")
		.map((k) => ({ name: k, node: node[k] }));
}

function isReal(node) {
	return node && typeof node === "object" && (node["$className"] || node["$path"]);
}

function find(node, name) {
	if (!isReal(node)) return null;
	for (const c of children(node)) {
		if (c.name === name) return c.node;
		const f = find(c.node, name);
		if (f) return f;
	}
	return null;
}

/** Recorre TODO el subarbol y devuelve [{name, node}]. */
function flatten(node, out) {
	if (!isReal(node)) return out;
	for (const c of children(node)) {
		out.push({ name: c.name, node: c.node });
		flatten(c.node, out);
	}
	return out;
}

const W = proj.tree.Workspace;
const forest = find(W, "Forest");
const blocksFolder = find(forest, "Blocks");

const failures = [];

function check(label, condition, detail) {
	const line = (condition ? "  PASS  " : "  FAIL  ") + label + (detail ? "  (" + detail + ")" : "");
	console.log(line);
	if (!condition) failures.push(label);
}

// ---------------------------------------------------- 1. CONTRATO
console.log("=== 1. CONTRATO DE JUEGO ===");

const forestAll = flatten(forest, []);
const allBlocks = forestAll.filter((b) => b.name.slice(0, 6) === "Block_");
check("48 bloques con prefijo Block_ en Forest", allBlocks.length === 48, "encontrados " + allBlocks.length);

const inBlocks = children(blocksFolder).filter((b) => b.name.slice(0, 6) === "Block_");
check("Blocks contiene bloques", inBlocks.length > 0, inBlocks.length + " en Workspace.Worlds.Forest.Blocks");

const notParts = allBlocks.filter((b) => b.node["$className"] !== "Part");
check("todo bloque es una BasePart (clase Part)", notParts.length === 0, notParts.map((b) => b.name).join(","));

const noCollide = allBlocks.filter((b) => (b.node.$properties || {}).CanCollide === false);
check("todo bloque tiene CanCollide = true", noCollide.length === 0, noCollide.map((b) => b.name).join(","));

// Hijos que tambien empiecen por `Block_`: romperian el recuento.
const nestedBlockNames = allBlocks.filter((b) => children(b.node).some((c) => c.name.slice(0, 6) === "Block_"));
check("ningun hijo de bloque vuelve a llamarse Block_*", nestedBlockNames.length === 0, nestedBlockNames.map((b) => b.name).join(","));

// ---------------------------------------------------- 2. VARIEDAD
console.log("\n=== 2. VARIEDAD (ya no son 48 cubos) ===");

const sizes = new Set();
const materials = new Set();
const orientations = new Set();
const variants = new Map();

// La variante NO se lee de un atributo: Rojo 7.7.0 no soporta atributos en
	// los archivos de proyecto (ver `tools/attr-probe.js`). Viaja en el
	// nombre de la decoracion hija: `Deco_A_Leaf_12`. El `tag` es la letra
	// de variante entre `Deco_` y el tipo de pieza.
	const variantOf = (blockNode) => {
		for (const c of children(blockNode)) {
			const m = /^Deco_([A-D])_/.exec(c.name);
			if (m) return m[1];
		}
		return undefined;
	};

	for (const b of allBlocks) {
		const p = b.node.$properties || {};
		sizes.add(JSON.stringify(p.Size));
		materials.add(p.Material);
		orientations.add(JSON.stringify(p.Orientation || [0, 0, 0]));
		const v = variantOf(b.node);
		variants.set(v, (variants.get(v) || 0) + 1);
	}

check("mas de un tamano distinto", sizes.size >= 4, sizes.size + " tamanos");
check("mas de un material distinto", materials.size >= 4, materials.size + " materiales: " + [...materials].join(", "));
check("mas de una orientacion distinta", orientations.size >= 40, orientations.size + " orientaciones distintas");
check("las 4 variantes se usan", variants.size === 4, JSON.stringify([...variants]));

// Cada bloque debe llevar la letra de variante en el nombre de su
	// decoracion. Es la unica forma de que la variante sobreviva al build:
//	// Rojo 7.7.0 no escribe atributos de instancia desde el proyecto.
	const withVariantTag = allBlocks.filter((b) => variantOf(b.node) !== undefined);
	check("cada bloque declara su variante en el nombre de su decoracion", withVariantTag.length === 48, withVariantTag.length + " de 48");

// Ningun bloque debe seguir siendo el cubo 8x8x8 de la version anterior.
const legacy = allBlocks.filter((b) => {
	const s = (b.node.$properties || {}).Size;
	return s && s[0] === 8 && s[1] === 8 && s[2] === 8;
});
check("ningun bloque sigue siendo 8x8x8", legacy.length === 0, legacy.length + " supervivientes");

// ---------------------------------------------------- 3. DECORACION
console.log("\n=== 3. DECORACION SIN COLISION ===");

// Carpetas que por definicion NO colisionan.
for (const fname of ["Terrain", "Decoration", "Border", "Keshusy"]) {
	const f = find(forest, fname);
	if (!f) {
		check("existe la carpeta " + fname, false);
		continue;
	}
	const items = flatten(f, []);
	const colliding = items.filter((x) => (x.node.$properties || {}).CanCollide === true);
	check(fname + ": ninguna pieza colisiona", colliding.length === 0, items.length + " piezas, " + colliding.length + " colisionando");
}

// El terreno tiene que ser visualmente variado, no una losa.
const terrainParts = children(find(forest, "Terrain")).filter((c) => c.node["$className"] === "Part");
check("el terreno tiene varias capas", terrainParts.length >= 20, terrainParts.length + " capas");

// ---------------------------------------------------- 4. BORDES
console.log("\n=== 4. BORDE DE LA ARENA ===");
const borderCount = flatten(find(forest, "Border"), []).length;
check("el borde tiene masa visual propia", borderCount >= 60, borderCount + " piezas");

// ---------------------------------------------------- 5. SPAWN
console.log("\n=== 5. SPAWN ===");
const spawns = children(find(W, "SpawnLocations"));
check("6 spawns", spawns.length === 6, spawns.length + " spawns");

for (const s of spawns) {
	const p = s.node.$properties || {};
	const yaw = (p.Orientation || [0, 0, 0])[1];

	// Roblox mira hacia -Z en rotacion 0. Con yaw, la direccion de vista
	// es (-sin(yaw), 0, -cos(yaw)). Se comprueba que apunte al origen,
	// que es donde esta el Keshusy Core del lobby.
	const r = (yaw * Math.PI) / 180;
	const fx = -Math.sin(r);
	const fz = -Math.cos(r);
	const dx = 0 - p.Position[0];
	const dz = 0 - p.Position[2];
	const len = Math.hypot(dx, dz) || 1;
	const dot = (fx * dx + fz * dz) / len;

	// 0.97 ~ dentro de 14 grados: holgura razonable para el redondeo a
	// grados enteros que hace el generador.
	const deviation = (Math.acos(Math.min(1, dot)) * 180) / Math.PI;
	check(s.name + " mira al centro", dot > 0.97, "yaw " + yaw + " grados, desvio " + deviation.toFixed(1) + " grados");
}

// ---------------------------------------------------- 6. ILUMINACION
console.log("\n=== 6. ILUMINACION ===");
const lighting = proj.tree.Lighting;
check("Lighting declarado", !!lighting);
if (lighting) {
	const lp = lighting.$properties || {};
	check("hay ambiente y hora propia", lp.Ambient !== undefined && lp.ClockTime !== undefined, "ClockTime " + lp.ClockTime);
	check("Atmosphere (niebla/profundidad)", !!lighting.Atmosphere);
	check("BloomEffect (el Neon florece)", !!lighting.ForestBloom);

	// Presupuesto de luces: se cuentan TODAS las luces del mapa.
	const lights = flatten(proj.tree.Workspace, []).filter((x) =>
		x.node["$className"] === "PointLight" || x.node["$className"] === "SpotLight"
	);
	check("presupuesto de luces razonable", lights.length <= 12, lights.length + " luces puntuales");
}

// ---------------------------------------------------- RESUMEN
console.log("\n=== RESUMEN ===");
if (failures.length === 0) {
	console.log("TODAS LAS COMPROBACIONES ESTRUCTURALES PASAN.");
	console.log("");
	console.log("Aviso importante: esto NO es una verificacion visual. Comprueba");
	console.log("que el mapa tiene la FORMA correcta, no que se vea bien. Para eso");
	console.log("hay que entrar en Play y mirarlo; ver tools/play.js.");
	process.exit(0);
} else {
	console.log("FALLAN " + failures.length + ": " + failures.join(" | "));
	process.exit(1);
}