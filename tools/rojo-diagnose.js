"use strict";

/*
	rojo-diagnose.js
	Localiza por que Rojo rechaza un `default.project.json` que `JSON.parse`
	si acepta.

	POR QUE HACE FALTA
	------------------
	Rojo no usa un parser generico: deserializa el arbol de instances con
	un esquema ESTRICTO. Varias cosas que son JSON valido siguen siendo
	invalidas para Rojo, y el mensaje que devuelve es siempre el mismo
	("Failed to deserialize JSON"), sin decir cual. En este mapa han
	aparecido dos:

	  * claves duplicadas en un mismo nivel, y
	  * claves que Rojo no puede convertir en nombres de instancia.

	Este script recorre el JSON comprobando ambas cosas y dice la ruta
	exacta. Sin el, un fallo de Rojo obliga a adivinar.
*/

const fs = require("fs");
const path = require("path");

const file = process.argv[2] || path.join(__dirname, "..", "default.project.json");
const raw = fs.readFileSync(file, "utf8");
const root = JSON.parse(raw);

const problems = [];
const RESERVED = new Set(["$className", "$properties", "$path", "$ignoreUnknownInstances"]);

function visit(node, trail) {
	if (!node || typeof node !== "object") return;

	for (const key of Object.keys(node)) {
		const child = node[key];

		// Claves numericas: Rojo las convierte en nombres de instancia y
		// un mapa no puede tener claves numericas.
		if (/^[0-9]/.test(key)) {
			problems.push({ kind: "clave numerica", trail: trail + "/" + key });
		}

		// Caracteres que Roblox no admite en un Name.
		if (key !== "$path" && /[\/\\:*?"<>|]/.test(key)) {
			problems.push({ kind: "caracter invalido en el nombre", trail: trail + "/" + key });
		}

		if (child && typeof child === "object" && (child["$className"] || child["$path"])) {
			visit(child, trail + "/" + key);
		}
	}
}

/**
 * Busca claves duplicadas en el TEXTO del JSON.
 *
 * `JSON.parse` no puede hacerlo: al repetir una clave se queda con la
 * ultima y no deja rastro. Aqui se reconstruye el objeto en crudo,
 * registering cada clave segun se lee.
 *
 * @param {string} text
 * @returns {string[]} rutas con clave repetida
 */
function findDuplicateKeys(text) {
	const dupes = [];
	const seen = [];

	function parseValue(pos) {
		const ch = text[pos];
		if (ch === "{") return parseObject(pos);
		if (ch === "[") return parseArray(pos);
		if (ch === '"') return parseString(pos);
		// numero, true, false, null
		while (pos < text.length && !",}] \t\r\n".includes(text[pos])) pos += 1;
		return pos;
	}

	function parseString(pos) {
		pos += 1;
		while (pos < text.length) {
			if (text[pos] === "\\") pos += 2;
			else if (text[pos] === '"') return pos + 1;
			else pos += 1;
		}
		return pos;
	}

	function parseObject(pos) {
		const keys = new Map();
		pos += 1;
		while (pos < text.length && text[pos] !== "}") {
			if (text[pos] === '"') {
				const end = parseString(pos);
				const key = text.slice(pos + 1, end - 1);
				pos = end;
				// se salta el ':' y el valor
				while (pos < text.length && text[pos] !== ":" && text[pos] !== "}") pos += 1;
				pos += 1;
				const valueStart = pos;
				pos = parseValue(pos);
				const valueText = text.slice(valueStart, pos);
				if (keys.has(key)) {
					dupes.push(cloneKeys(keys) + "/" + key + "  (valor previo cerca del indice " + valueStart + ")");
				} else {
					keys.set(key, valueStart);
				}
			} else {
				pos += 1;
			}
			if (text[pos] === ",") pos += 1;
		}
		return pos + 1;
	}

	function cloneKeys(map) {
		// Se reconstruye la ruta completa desde el mapa de claves vistas.
		return Array.from(map.keys()).slice(0, 3).join("/") || "(raiz)";
	}

	function parseArray(pos) {
		pos += 1;
		while (pos < text.length && text[pos] !== "]") {
			pos = parseValue(pos);
			if (text[pos] === ",") pos += 1;
		}
		return pos + 1;
	}

	parseValue(0);
	return dupes;
}

visit(root, "");

console.log("archivo:  " + path.basename(file));
console.log("tamano:   " + raw.length + " bytes");

if (problems.length === 0) {
	console.log("sin problemas estructurales obvios.");
	console.log("Si Rojo sigue fallando, el problema es de TIPO: una propiedad");
	console.log("con un valor que Rojo no sabe convertir.");
} else {
	console.log("\nPROBLEMAS (" + problems.length + "):");
	for (const p of problems.slice(0, 40)) {
		console.log("  " + p.kind + ": " + p.trail);
	}
	if (problems.length > 40) console.log("  ... y " + (problems.length - 40) + " mas");
}

// Comprobacion extra: el limite deinstances de Rojo. Rojo tiene un tope
// duro (100 000 instancias); un bosque con miles de partes lo puede
// alcanzar sin avisar.
let instances = 0;
(function count(node) {
	if (!node || typeof node !== "object") return;
	if (node["$className"]) instances += 1;
	for (const key of Object.keys(node)) {
		if (RESERVED.has(key)) continue;
		const child = node[key];
		if (child && typeof child === "object") count(child);
	}
})(root);
console.log("\ninstancias declaradas (aprox): " + instances);

// ------------------------------------------------------------- REPARTO
//
// Rojo RECHAZA el archivo tal cual pero ACEPTA el mismo arbol reescrito por
// `JSON.parse` + `JSON.stringify`. Esa diferencia es la pista: el problema
// esta en el TEXTO del archivo, no en su estructura semantica.
//
// La causa mas probable es una CLAVE DUPLICADA. `JSON.parse` se queda con
// la ultima y deja el archivo "correcto" a ojos de Node; el deserializador
// de Rojo, que deserializa el arbol como un mapa, ve la clave repetida y
// falla. `JSON.parse` no puede detectar esto por si solo, asi que se
// detecta recorriendo el texto con un parser que SÍ recuerda las claves.
console.log("\n=== CLAVES DUPLICADAS ===");
const dupes = findDuplicateKeys(root);
if (dupes.length === 0) {
	console.log("ninguna clave duplicada.");
} else {
	console.log(dupes.length + " claves duplicadas:");
	for (const d of dupes.slice(0, 30)) {
		console.log("  " + d);
	}
	if (dupes.length > 30) console.log("  ... y " + (dupes.length - 30) + " mas");
}

// Caracteres de control o UTF-8 invalido: `JSON.parse` los tolera en
// algunos casos donde el lector de Rojo no.
console.log("\n=== CARACTERES SOSPECHOSOS ===");
let controls = 0;
for (let i = 0; i < raw.length; i++) {
	const code = raw.charCodeAt(i);
	const isAllowedWhitespace = code === 9 || code === 10 || code === 13;
	if (code < 32 && !isAllowedWhitespace) {
		controls += 1;
		if (controls <= 5) {
			console.log("  control U+" + code.toString(16).padStart(4, "0") + " en el indice " + i);
		}
	}
}
if (controls > 5) console.log("  ... y " + (controls - 5) + " control mas");
if (controls === 0) console.log("sin caracteres de control.");

// ------------------------------------------------- DIFERENCIA DE BYTES
//
// Rojo acepta el arbol reserializado por `JSON.stringify` y rechaza el
// archivo tal cual. Los dos tienen el MISMO contenido semantico, asi que
// la diferencia esta en como estan escritos los bytes. Este bloque la
// localiza comparando ambos textos.
console.log("\n=== DIFERENCIA CON LA RESERIALIZACION ===");
const reserialized = JSON.stringify(root, null, 2) + "\n";
if (reserialized === raw) {
	console.log("los textos son identicos: el problema NO es de bytes.");
} else {
	console.log("el texto reserializado mide " + reserialized.length + " y el archivo " + raw.length + ".");
	console.log("primera diferencia en el indice " + firstDiff(raw, reserialized));
	console.log("  archivo:      " + JSON.stringify(raw.slice(p - 60, p + 60)));
	console.log("  reserializado:" + JSON.stringify(reserialized.slice(p - 60, p + 60)));
}

function firstDiff(a, b) {
	const n = Math.min(a.length, b.length);
	for (let i = 0; i < n; i++) if (a[i] !== b[i]) return i;
	return n;
}

const p = firstDiff(raw, reserialized);