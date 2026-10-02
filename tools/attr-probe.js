"use strict";

/*
	attr-probe.js
	Comprueba si esta version de Rojo escribe ATRIBUTOS de instancia, y
	en que forma exacta.

	POR QUE HACE FALTA
	------------------
	El mapa marca cada bloque con `ForestVariant` para saber que silueta
	tiene. Se han probado dos formas y las dos fallaron:

	  1. `Attributes` dentro de `$properties` -> Rojo RECHAZA el proyecto.
	  2. `$attributes` como campo de la instancia -> Rojo lo IGNORA, y
	     el atributo no aparece en el `.rbxlx`.

	Antes de decidir como llevar la variante (atributo, nombre o carpeta)
	hace falta saber que es lo que esta version de Rojo sabe leer. Este
	script genera tres proyectos minimos, uno por cada sintaxis
	candidata, y busca el atributo en el XML resultante.

	Uso:  node tools/attr-probe.js
*/

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const ROOT = path.join(__dirname, "..");
const ROJO = path.join(ROOT, "rojo", "rojo.exe");
const CACHE = path.join(ROOT, ".cache");

function baseTree() {
	return {
		$className: "DataModel",
		Folder: { $className: "Folder" },
	};
}

const candidates = [
	{
		name: "$attributes como campo de la instancia",
		tree: () => {
			const t = baseTree();
			t.Folder.Pieza = {
				$className: "Part",
				$properties: { Size: [4, 4, 4], Anchored: true },
				$attributes: { ForestVariant: "A" },
			};
			return t;
		},
	},
	{
		name: "Attributes dentro de $properties",
		tree: () => {
			const t = baseTree();
			t.Folder.Pieza = {
				$className: "Part",
				$properties: { Size: [4, 4, 4], Anchored: true, Attributes: { ForestVariant: "A" } },
			};
			return t;
		},
	},
	{
		name: "campo suelto en la propiedad (no $properties)",
		tree: () => {
			const t = baseTree();
			t.Folder.Pieza = {
				$className: "Part",
				$properties: { Size: [4, 4, 4], Anchored: true },
				ForestVariant: "A",
			};
			return t;
		},
	},
];

console.log("version de Rojo:");
try {
	console.log("  " + execFileSync(ROJO, ["--version"], { cwd: ROOT, encoding: "utf8" }).trim());
} catch (err) {
	console.log("  (no se pudo leer: " + err.message + ")");
}

console.log("");
for (const candidate of candidates) {
	const stem = "attr-" + Math.random().toString(36).slice(2, 9);
	const file = path.join(CACHE, stem + ".project.json");
	const out = path.join(CACHE, stem + ".rbxlx");
	fs.mkdirSync(CACHE, { recursive: true });
	fs.writeFileSync(file, JSON.stringify({ name: "Probe", tree: candidate.tree() }, null, 2) + "\n");

	let status;
	let xml = "";
	try {
		execFileSync(ROJO, ["build", file, "-o", out], { cwd: ROOT, stdio: ["ignore", "pipe", "pipe"] });
		xml = fs.readFileSync(out, "utf8");
		const found = xml.indexOf("ForestVariant") !== -1;
		status = found ? "ATRIBUTO PRESENTE" : "build ok, atributo AUSENTE";
	} catch (err) {
		status = "BUILD RECHAZADO: " + ((err.stderr || "").toString().trim().split("\n").pop() || "");
	}

	console.log("  " + status);
	console.log("      " + candidate.name);
	if (status.indexOf("PRESENTE") !== -1) {
		const i = xml.indexOf("ForestVariant");
		console.log("      fragmento: " + JSON.stringify(xml.slice(Math.max(0, i - 120), i + 160)));
	}

	fs.rmSync(file, { force: true });
	fs.rmSync(out, { force: true });
}

console.log("");
console.log("Ninguna sintaxis que funcione significa que hay que llevar la variante");
console.log("por otro camino (por ejemplo, deduciendola del bloque en runtime).");
console.log("Eso es una decision de DISENO, no un bug de formato: se decide aparte.");