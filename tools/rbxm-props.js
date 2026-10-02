// rbxm-props.js
// Comprueba si un `<Item>` del `.rbxm` importable trae las propiedades que
// el diseno declaro.
//
// POR QUE EXISTE
// --------------
// Cuando la geometria llega a Studio sin su posicion, hay tres etapas
// posibles donde perderse, y cada una se arregla de forma distinta:
//
//   1. `default.project.json`  (el generador no la declaro)
//   2. el `.rbxm` intermedio   (la extraccion de texto la perdio)
//   3. `import_rbxm`           (Studio la ignoro)
//
// Este script mira la etapa 2, que es la que se puede comprobar sin Studio.
// Si el `.rbxm` TIENE la posicion, el fallo es de Studio; si NO la tiene, el
// fallo es de `sync-workspace.js` y se arregla ahi.
//
// Uso:
//   node tools/rbxm-props.js PortalPanel
//   node tools/rbxm-props.js PortalPanel --file .cache/workspace-source.rbxm

const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const FILE = process.argv.includes("--file")
	? process.argv[process.argv.indexOf("--file") + 1]
	: path.join(ROOT, ".cache", "workspace-source.rbxm");

const needle = process.argv[2];
if (!needle) {
	console.error("uso: node tools/rbxm-props.js <nombre-de-Parte> [--file <rbxm>]");
	process.exit(2);
}
if (!fs.existsSync(FILE)) {
	console.error("no existe: " + FILE);
	console.error("genera uno con: node tools/sync-workspace.js");
	process.exit(2);
}

const xml = fs.readFileSync(FILE, "utf8");

/** Localiza el `<Item>` cuyo Name es exactamente el buscado. */
function findItem(name) {
	const token = `<string name="Name">${name}</string>`;
	let index = xml.indexOf(token);
	while (index !== -1) {
		const start = xml.lastIndexOf("<Item ", index);
		if (start !== -1) {
			const end = xml.indexOf("</Item>", index);
			const block = xml.slice(start, end === -1 ? index + 400 : end);
			// Un `Name` puede aparecer en un `ObjectValue` o similar; se exige
			// que el Item sea una Part.
			if (block.includes(`<Item class="Part"`)) return block;
		}
		index = xml.indexOf(token, index + 1);
	}
	return null;
}

/** Extrae el contenido de `<Vector3 name="X">...</Vector3>`. */
function vectorValue(block, prop) {
	const re = new RegExp(`<Vector3 name="${prop}">([\\s\\S]*?)</Vector3>`);
	const m = re.exec(block);
	if (!m) return null;
	const nums = [...m[1].matchAll(/<[XYZ]>(-?[\d.]+)<\/[XYZ]>/g)].map((x) => Number(x[1]));
	return nums.length === 3 ? nums : null;
}

const block = findItem(needle);
if (!block) {
	console.log(`"${needle}" no aparece como Part en ${path.basename(FILE)}`);
	console.log("  -> la extraccion de texto perdio el elemento: revisar sync-workspace.js");
	process.exit(1);
}

const pos = vectorValue(block, "Position");
const size = vectorValue(block, "size") || vectorValue(block, "Size");

console.log(`${needle} en ${path.basename(FILE)}`);
console.log(`  Position: ${pos ? `(${pos.join(", ")})` : "AUSENTE"}`);
console.log(`  Size:     ${size ? `(${size.join(", ")})` : "AUSENTE"}`);
console.log(`  Material: ${/<token name="Material">(\d+)<\/token>/.exec(block)?.[1] ?? "AUSENTE"}`);
console.log(`  Color:    ${/Color3uint8">(\d+)</.exec(block)?.[1] ?? "AUSENTE"}`);

if (pos && pos.every((n) => n === 0)) {
	console.log("");
	console.log("AVISO: la posicion es (0,0,0). Si el diseno pide otra cosa, el");
	console.log("fallo esta en el GENERADOR, no en la importacion.");
}
