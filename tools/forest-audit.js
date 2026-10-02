"use strict";

/*
	forest-audit.js
	Reconciliacion 1: que hay de verdad en la fuente del mapa.
	NO escribe nada. Solo mide y imprime, para no asumir que el
	reporte anterior sigue siendo cierto.
*/

const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..");
const proj = JSON.parse(fs.readFileSync(path.join(ROOT, "default.project.json"), "utf8"));

function children(node) {
	return Object.keys(node)
		.filter((k) => k !== "$className" && k !== "$properties" && k !== "$path")
		.map((k) => ({ name: k, node: node[k] }));
}

function isReal(node) {
	return node && typeof node === "object" && (node["$className"] || node["$path"]);
}

function walk(node, depth, acc, name) {
	if (!isReal(node)) return acc;
	const cls = node["$className"] || (node["$path"] ? "PATH:" + node["$path"] : "?");
	acc.push("  ".repeat(depth) + cls + " :: " + (name || "?"));
	for (const c of children(node)) walk(c.node, depth + 1, acc, c.name);
	return acc;
}

const W = proj.tree.Workspace;
console.log("=== ARBOL Workspace (nivel 2) ===");
for (const top of children(W)) {
	console.log((top.node["$className"] || "?") + " :: " + top.name);
	for (const c of children(top.node)) {
		console.log("   " + (c.node["$className"] || "?") + " :: " + c.name + "  [" + children(c.node).length + " hijos]");
	}
}

function collect(node, out) {
	if (!isReal(node)) return out;
	out.push(node);
	for (const c of children(node)) collect(c.node, out);
	return out;
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

console.log("\n=== RECUENTO POR CARPETA ===");
for (const top of children(W)) {
	const all = collect(top.node, []);
	const kinds = {};
	for (const n of all) {
		const k = n["$className"] || "?";
		kinds[k] = (kinds[k] || 0) + 1;
	}
	console.log(top.name + "  total=" + all.length + "  " + JSON.stringify(kinds));
}

for (const world of ["Forest", "Lobby"]) {
	const node = find(W, world);
	console.log("\n=== " + world + " ===");
	console.log(node ? walk(node, 0, [], world).join("\n") : "NO EXISTE");
}

console.log("\n=== FOREST: geometria exacta ===");
const forestNode = find(W, "Forest");
const fmt = (n) => {
	const p = n["$properties"] || {};
	return (
		JSON.stringify(p.Position || []) +
		" size=" + JSON.stringify(p.Size || []) +
		" rot=" + JSON.stringify(p.CFrameOrientation || [0, 0, 0]) +
		" mat=" + (p.Material || "-") +
		" col=" + JSON.stringify((p.Color || []).map((v) => Math.round(v * 255))) +
		" collide=" + p.CanCollide
	);
};
for (const c of children(forestNode)) {
	if (c.node["$className"] === "Folder") {
		console.log("[" + c.name + "]");
		for (const b of children(c.node)) console.log("   " + b.name.padEnd(10) + fmt(b.node));
	} else {
		console.log(c.name.padEnd(12) + fmt(c.node));
	}
}

console.log("\n=== FOREST Blocks: atributos ===");
const blocksNode = find(forestNode, "Blocks");
const firstBlock = children(blocksNode)[0].node;
console.log(JSON.stringify(firstBlock, null, 1));

console.log("\n=== PORTALES ===");
const portals = find(W, "Portals");
for (const c of children(portals)) {
	console.log(c.name + " :: " + c.node["$className"]);
	console.log(JSON.stringify(c.node).slice(0, 800));
}

console.log("\n=== KESHUSY CORE ===");
const core = find(W, "KeshusyCore");
for (const c of children(core)) {
	const p = c.node["$properties"] || {};
	console.log("   " + (c.node["$className"] || "?") + " " + c.name + " " + fmt(c.node));
}
const sl = find(W, "SpawnLocations");
for (const c of children(sl)) {
	const p = c.node["$properties"] || {};
	console.log(c.name + " pos=" + JSON.stringify(p.Position) + " size=" + JSON.stringify(p.Size) + " enabled=" + p.Enabled + " orient=" + JSON.stringify(p.CFrameOrientation || null));
}