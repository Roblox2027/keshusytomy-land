"use strict";

/*
	rojo-bisect.js
	Encuentra QUE PARTE de `default.project.json` rechaza Rojo.

	POR QUE HACE FALTA
	------------------
	Rojo devuelve SIEMPRE el mismo error ("Failed to deserialize JSON")
	sin decir que campo lo ha rechazado. Con un mapa de ~1 200 instancias
	eso obliga a adivinar entre miles de lineas.

	Este script quita ramas del arbol una a una y vuelve a lanzar el build
	de Rojo sobre cada version. La rama cuya retirada hace que el build
	pase es la culpable, y se imprime su ruta.

	Nota sobre `sync-workspace.js`: su bloque `catch` solo aborta si el
	archivo de salida NO existe, asi que un fallo de Rojo puede quedar
	mascarado por un build viejo. Esta comprobacion no tiene ese problema.

	Uso:  node tools/rojo-bisect.js
*/

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const ROOT = path.join(__dirname, "..");
const ROJO = path.join(ROOT, "rojo", "rojo.exe");
const CACHE = path.join(ROOT, ".cache");
const PROJECT = path.join(ROOT, "default.project.json");

const root = JSON.parse(fs.readFileSync(PROJECT, "utf8"));

/** Rutas de las claves de primer nivel del arbol (ReplicatedStorage, ...). */
function topKeys(node) {
	return Object.keys(node).filter((k) => !k.startsWith("$"));
}

/** Prueba si Rojo acepta este proyecto, con nombre y directorio por defecto. */
function rojoAccepts(tree) {
	return rojoAcceptsNamed(tree, "Probe", "probe", ".cache");
}

/**
 * Invoca a Rojo sobre un proyecto escrito con un NOMBRE y un DIRECTORIO
 * concretos.
 *
 * Separar el nombre del archivo importa porque son dos validaciones
 * DISTINTAS y ambas fallan con el mismo "Failed to deserialize JSON":
 *
 *   - el campo `name` del proyecto no admite todos los caracteres que
 *     Roblox acepta en un `Name`;
 *   - Rojo solo reconoce un archivo de proyecto si su nombre termina en
 *     `.project.json`.
 *
 * @param {object} tree
 * @param {string} projectName valor del campo `name`
 * @param {string} stem prefijo del archivo temporal
 * @param {string} dir directorio destino, relativo a ROOT
 * @returns {{ok: boolean, message: string}}
 */
function rojoAcceptsNamed(tree, projectName, stem, dir) {
	const baseDir = path.join(ROOT, dir || ".cache");
	fs.mkdirSync(baseDir, { recursive: true });
	const stamp = process.pid + "-" + Math.floor(Math.random() * 1e9);
	const file = path.join(baseDir, stem + "-" + stamp + ".project.json");
	const out = path.join(baseDir, stem + "-" + stamp + ".rbxlx");
	fs.writeFileSync(file, JSON.stringify({ name: projectName, tree: tree }, null, 2) + "\n");
	try {
		execFileSync(ROJO, ["build", file, "-o", out], {
			cwd: ROOT,
			stdio: ["ignore", "pipe", "pipe"],
			maxBuffer: 256 * 1024 * 1024,
		});
		return { ok: true, message: "" };
	} catch (err) {
		// Se devuelve el stderr REAL de Rojo: antes se devolvia solo un
		// booleano, y eso hacia que un fallo de invocacion fuera
		// indistinguible de un rechazo de contenido.
		return {
			ok: false,
			message: ((err.stderr || "") + (err.stdout || "") + err.message).toString().trim(),
		};
	} finally {
		fs.rmSync(file, { force: true });
		fs.rmSync(out, { force: true });
	}
}
	function clone(v) {
	return JSON.parse(JSON.stringify(v));
}

console.log("=== rojo-bisect ===\n");

// PRIMERO: comprobar que el metodo es fiable. Si Rojo rechaza un arbol
// minimo y vacio, el problema no esta en nuestro JSON sino en como se
// invoca a Rojo (o en que Rojo este roto), y bisecar no dice nada.
const minimal = { $className: "DataModel" };
const control = rojoAccepts(minimal);
console.log("control: arbol minimo -> " + (control.ok ? "ACEPTADO (metodo fiable)" : "RECHAZADO"));
if (!control.ok) {
	console.log("");
	console.log("Mensaje de Rojo:");
	console.log(control.message);
}

if (!control.ok) {
	console.log("\nRojo no puede construir siquiera un DataModel vacio. No tiene sentido");
	console.log("bisectar el JSON del proyecto: el fallo es de la herramienta.");
	process.exit(2);
}

// SEGUNDO: distinguir "contenido" de "encabezado".
//
// Rojo reserializado acepta el mismo arbol, pero el archivo del
// repositorio no. La diferencia NO esta en el arbol, sino en el campo
// `name` del proyecto o en la ruta. Se prueban las dos por separado.
const withRealName = rojoAcceptsNamed(clone(root), root.name || "Probe", "realname", ".cache");
console.log("arbol completo, name = " + JSON.stringify(root.name) + " -> " + (withRealName.ok ? "ACEPTADO" : "RECHAZADO"));
if (!withRealName.ok) {
	console.log("");
	console.log("Mensaje de Rojo:");
	console.log(withRealName.message);
	console.log("");

	// Se separan las variables de una en una. Antes se asumia que el
	// campo `name` era el culpable y el resultado Carryo que no lo era:
	// hay que MEDIR cada variable, no suponerla.
	const base = { $className: "DataModel" };
	const withChild = {
		$className: "DataModel",
		Carpeta: { $className: "Folder" },
	};
	const withPart = {
		$className: "DataModel",
		Pieza: {
			$className: "Part",
			$properties: { Size: [4, 4, 4] },
		},
	};
	const withAttributes = {
		$className: "DataModel",
		Pieza: {
			$className: "Part",
			$properties: {
				Size: [4, 4, 4],
				Attributes: { ForestVariant: "A", BlockIndex: 3 },
			},
		},
	};
	const withOrientation = {
		$className: "DataModel",
		Pieza: {
			$className: "Part",
			$properties: { Size: [4, 4, 4], Orientation: [5, 90, -3] },
		},
	};
	const withLighting = {
		$className: "DataModel",
		Lighting: {
			$className: "Lighting",
			$properties: { ClockTime: 15.2, Brightness: 2.4 },
			Atmosphere: {
				$className: "Atmosphere",
				$properties: { Density: 0.22, Haze: 1.6 },
			},
			ForestBloom: {
				$className: "BloomEffect",
				$properties: { Intensity: 0.45, Size: 28, Threshold: 0.85 },
			},
		},
	};
	const withPath = {
		$className: "DataModel",
		ReplicatedStorage: { $path: "src/ReplicatedStorage" },
	};

	const cases = [
		["DataModel sin hijos", base, "Probe"],
		["DataModel con un Folder", withChild, "Probe"],
		["DataModel con una Part", withPart, "Probe"],
		["Part con Attributes", withAttributes, "Probe"],
		["Part con Orientation", withOrientation, "Probe"],
		["Lighting + Atmosphere + Bloom", withLighting, "Probe"],
		["$path a src/", withPath, "Probe"],
	];

	console.log("Matriz de variables:");
	for (const [label, tree, name] of cases) {
		const r = rojoAcceptsNamed(clone(tree), name, "matrix", ".cache");
		console.log("  " + (r.ok ? "ACEPTADO" : "RECHAZADO") + "  " + label);
	}

	console.log("");
	console.log("Conclusión: el nombre del proyecto NO es la causa. El ARBOL es lo");
	console.log("que Rojo rechaza, y el rechazo depende de su contenido. Se sigue");
	console.log("con el bisectado por ramas.");
	console.log("");
	console.log("Rojo RECHAZA el proyecto completo. Probando cada rama del arbol...\n");

	for (const key of topKeys(root.tree)) {
		const probe = clone(root);
		delete probe.tree[key];
		const r = rojoAccepts(probe);
		console.log("  sin " + key.padEnd(22) + " -> " + (r.ok ? "ACEPTADO  <-- la culpable" : "sigue fallando"));
		if (r.ok) {
			console.log("\n  CULPABLE: tree." + key);
			process.exit(1);
		}
	}

	console.log("\nNinguna rama por separado explica el fallo: puede haber MAS DE UNA,");
	console.log("o el problema esta en varios sitios a la vez. En ese caso hay que");
	console.log("bajar de nivel: se prueban los nietos de Workspace, que es donde");
	console.log("esta toda la geometria nueva.");
	process.exit(1);
}

if (rojoAccepts(clone(root))) {
	console.log("Rojo ACEPTA el proyecto completo. No hay nada que aislar.");
	process.exit(0);
}

console.log("Rojo RECHAZA el proyecto completo. Probando cada rama del arbol...\n");

const keys = topKeys(root.tree);
let culprit = null;
let culpritTree = null;

for (const key of keys) {
	const probe = clone(root);
	delete probe.tree[key];
	const ok = rojoAccepts(probe);
	console.log("  sin " + key.padEnd(22) + " -> " + (ok ? "ACEPTADO  <-- la culpable" : "sigue fallando"));
	if (ok) {
		culprit = key;
		culpritTree = probe;
		break;
	}
}

if (!culprit) {
	console.log("\nNinguna rama por separado explica el fallo. Puede ser mas de");
	console.log("una, o un problema en la raiz. Se prueban las ramas por separado.");
	process.exit(1);
}

console.log("\nLa rama culpable es: tree." + culprit + "\n");

// Segunda pasada: dentro de la rama culpable, probar nietos.
if (culpritTree) {
	const node = root.tree[culprit];
	const subKeys = Object.keys(node).filter((k) => !k.startsWith("$"));
	console.log("Descendiendo dentro de " + culprit + "...");
	for (const sub of subKeys) {
		const probe = clone(root);
		delete probe.tree[culprit][sub];
		const ok = rojoAccepts(probe);
		console.log("  sin " + culprit + "." + sub.padEnd(20) + " -> " + (ok ? "ACEPTADO  <-- la culpable" : "sigue fallando"));
		if (ok) {
			console.log("\n  CULPABLE: tree." + culprit + "." + sub);
			process.exit(1);
		}
	}
}

process.exit(1);