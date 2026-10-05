"use strict";

// world-square-layout.js
// PONE CUADRADOS LOS LAYOUTS DE `tools/worlds.js`.
//
// POR QUE ES UN SCRIPT Y NO UN CAMBIO A MANO
// ------------------------------------------
// Los cinco layouts se escribieron mas altos que anchos (Forest 278x446,
// Volcano 254x438, Cyber 252x420). El generador los estira hasta 460x460 con
// una escala por eje, asi que el eje corto se estira y el largo no, y las
// zonas salen aplastadas: `Trail` con un radio de 35x18, `Exit` de 23x12.
//
// Una zona plana no es una zona. Su perimetro es una elipse de eje corto, los
// huecos de puerta se comen el borde entero y el arco de 26 studs alrededor
// del spawn cae fuera del suelo.
//
// La correccion es de DISENO: que los datos ocupen una caja cuadrada. Es un
// cambio mecanico sobre 60 lineas de coordenadas, y hacerlo a mano invita a
// equivocarse en un signo. El script lo hace con la MISMA cuenta que
// `layoutBounds`, escribe el resultado en el archivo y no vuelve a tocarlo.
//
// Uso: node tools/world-square-layout.js [--check]

const fs = require("fs");
const path = require("path");

const FILE = path.join(__dirname, "worlds.js");

/** Caja que ocupan las coordenadas de zona de un bloque de texto. */
function spansOf(block) {
	const lines = block.split("\n");
	const zones = [];
	for (const line of lines) {
		const m = line.match(/zone\(\["([^"]+)",\s*"([^"]+)",\s*(-?[\d.]+),\s*(-?[\d.]+),\s*([\d.]+),\s*([\d.]+)(?:,\s*(-?[\d.]+))?\]\)/);
		if (!m) continue;
		zones.push({
			line: line,
			id: m[1],
			x: Number(m[3]),
			z: Number(m[4]),
			rx: Number(m[5]),
			rz: Number(m[6]),
			y: m[7] === undefined ? undefined : Number(m[7]),
		});
	}
	if (!zones.length) return null;

	let x0 = Infinity, x1 = -Infinity, z0 = Infinity, z1 = -Infinity;
	for (const z of zones) {
		x0 = Math.min(x0, z.x - z.rx); x1 = Math.max(x1, z.x + z.rx);
		z0 = Math.min(z0, z.z - z.rz); z1 = Math.max(z1, z.z + z.rz);
	}
	return { zones, spanX: x1 - x0, spanZ: z1 - z0 };
}

function fmt(n) {
	return String(Math.round(n * 100) / 100);
}

function main() {
	const check = process.argv.includes("--check");
	const src = fs.readFileSync(FILE, "utf8");

	// Cada mundo es un bloque `Nombre: {` ... `},` dentro de `LAYOUTS`.
	const out = src.replace(
		/(\tForest: \{[\s\S]*?\n\t\},|\tDesert: \{[\s\S]*?\n\t\},|\tIce: \{[\s\S]*?\n\t\},|\tVolcano: \{[\s\S]*?\n\t\},|\tCyber: \{[\s\S]*?\n\t\},)/g,
		function (block) {
			const sp = spansOf(block);
			if (!sp) return block;
			const factor = sp.spanZ / sp.spanX;
			const name = (block.match(/^\t(\w+): \{/) || [, "?"])[1];
			if (Math.abs(factor - 1) < 0.005) {
				console.log("  " + name.padEnd(8) + " ya cuadrado (" + fmt(sp.spanX) + " x " + fmt(sp.spanZ) + ")");
				return block;
			}
			console.log("  " + name.padEnd(8) + " estirando X x" + fmt(factor) +
				"   (" + fmt(sp.spanX) + " x " + fmt(sp.spanZ) + ")");

			let outBlock = block;
			for (const z of sp.zones) {
				const nx = z.x * factor;
				const nrx = z.rx * factor;
				const oldTail = z.y === undefined ? "" : ", " + fmt(z.y);
				const newLine = z.line
					.replace(/(-?[\d.]+),\s*(-?[\d.]+),\s*([\d.]+),\s*([\d.]+)/,
					function (m0, a, b2, c, d) {
						return fmt(nx) + ", " + b2 + ", " + fmt(nrx) + ", " + d;
					});
				if (newLine === z.line && oldTail) {
					// La zona no tiene cota: el patron anterior no la ha tocado.
				}
				outBlock = outBlock.replace(z.line, newLine);
			}
			return outBlock;
		}
	);

	if (check) {
		const changed = out !== src;
		console.log(changed ? "HAY QUE ESTIRAR" : "LOS LAYOUTS YA ESTAN CUADRADOS");
		process.exitCode = changed ? 1 : 0;
		return;
	}

	if (out === src) {
		console.log("nada que hacer: los layouts ya son cuadrados");
		return;
	}
	fs.writeFileSync(FILE, out);
	console.log("layouts cuadrados en tools/worlds.js");
}

main();