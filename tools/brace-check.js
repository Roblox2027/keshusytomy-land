"use strict";

/*
	brace-check.js
	Ayuda minima de desarrollo: informa de la PROFUNDIDAD de llaves al
	final del archivo y de la primera linea donde se vuelve negativa.
	Un generador de 1 400 lineas falla con "Unexpected end of input"
	cuando le falta un `}`, y no dice cual.
*/

const fs = require("fs");
const path = require("path");

const file = process.argv[2] || path.join(__dirname, "generate-project.js");
const lines = fs.readFileSync(file, "utf8").split(/\r?\n/);

let depth = 0;
let firstNegative = null;
let lastZeroLine = 0;

lines.forEach((line, i) => {
	// Se ignoran los delimitadores que aparecen dentro de cadenas o
	// comentarios, que en este generador son abundantes (los nombres de
	// instancia son claves JSON y los comentarios explican codigo).
	const code = line.replace(/"(\\.|[^"\\])*"/g, '""').replace(/'(\\.|[^'\\])*'/g, "''").replace(/\/\/.*$/, "");
	for (const ch of code) {
		if (ch === "{") depth += 1;
		if (ch === "}") depth -= 1;
	}
	if (depth < 0 && firstNegative === null) firstNegative = i + 1;
	if (depth === 0) lastZeroLine = i + 1;
});

console.log("archivo:        " + path.basename(file));
console.log("lineas:         " + lines.length);
console.log("profundidad:    " + depth);
console.log("primer negativo: " + (firstNegative === null ? "ninguno" : firstNegative));
console.log("ultimo 0:       " + lastZeroLine);

if (depth !== 0) {
	console.log("\nFALTAN " + (depth > 0 ? depth + " llaves de cierre" : -depth + " llaves de apertura") + ".");
	console.log("La ultima linea con profundidad 0 es la " + lastZeroLine + ": el bloque sin cerrar empieza despues de ahi.");
	process.exit(1);
}

console.log("\nLlaves balanceadas.");