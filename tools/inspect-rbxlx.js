// inspect-rbxlx.js
// Extrae del build de Rojo un fragmento del XML alrededor de un `<Item>`.
//
// POR QUE EXISTE
// --------------
// Cuando una instancia aparece en Studio sin las propiedades que el
// generador declaro (posiciones a 0, por ejemplo), hay que responder a una
// pregunta muy concreta: ¿el fallo esta en el SOURCE (Rojo no escribio la
// propiedad) o en el RUNTIME (Rojo la escribio y Studio la perdio al
// importar)? Los dos se ven igual desde fuera y se arreglan de forma
// opuesta, asi que decidirlo a ojo es adivinar.
//
// Este script imprime el XML tal cual alrededor del elemento pedido.
//
// Uso:
//   node tools/inspect-rbxlx.js PortalPanel
//   node tools/inspect-rbxlx.js PortalPanel .cache/audit.rbxlx

const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");

const needle = process.argv[2];
const file = process.argv[3] || path.join(ROOT, ".cache", "audit.rbxlx");

if (!needle) {
	console.error("uso: node tools/inspect-rbxlx.js <texto> [archivo.rbxlx]");
	process.exit(2);
}

if (!fs.existsSync(file)) {
	console.error("no existe el build: " + file);
	console.error("genera uno con: node tools/sync-workspace.js");
	process.exit(2);
}

const xml = fs.readFileSync(file, "utf8");

// Se buscan todas las coincidencias del texto y se recorta el `<Item>` que
// las contiene. Solo interesan los que declaran el nombre como PROPIEDAD
// (`<string name="Name">`), no las menciones dentro del fuente de un script.
const matches = [];
let index = xml.indexOf(needle);
while (index !== -1) {
	const before = xml.slice(Math.max(0, index - 400), index);
	if (before.includes(`<string name="Name">`)) {
		const start = xml.lastIndexOf("<Item ", index);
		if (start !== -1) matches.push(start);
	}
	index = xml.indexOf(needle, index + 1);
}

if (!matches.length) {
	console.log(`"${needle}" no aparece en ${path.basename(file)}`);
	console.log("  -> el SOURCE no declara esta instancia: el fallo esta en el generador.");
	process.exit(1);
}

console.log(`coincidencias de "${needle}" en ${path.basename(file)}: ${matches.length}`);
for (const start of matches.slice(0, 2)) {
	const end = xml.indexOf("</Item>", start);
	console.log("");
	console.log("-------------------------------------------------");
	console.log(xml.slice(start, end + 8));
}
