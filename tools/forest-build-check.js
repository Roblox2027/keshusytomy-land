"use strict";

/*
	forest-build-check.js
	Comprueba lo que hay DENTRO del `.rbxlx` que produce Rojo, y no solo
	el JSON del que sale.

	POR QUE ESTA COMPROBACION ES DISTINTA DE `forest-verify.js`
	-------------------------------------------------------------
	`forest-verify.js` lee `default.project.json` y demuestra que la
	FUENTE es correcta. No demuestra que Rojo haya construido el mapa bien,
	porque entre las dos cosas hay una traduccion que puede descartar cosas
	EN SILENCIO.

	Ese silencio ya ha pasado de verdad en este mapa: escribir
	`Attributes` dentro de `$properties` hacia que Rojo rechazara el
	proyecto entero, y escribirlo como campo suelto hacia que lo ignorara.
	En los dos casos el JSON "tenia lo que tenia" y el resultado no.

	Asi que aqui se comprueba el ARTEFACTO, no la fuente.

	Ademas comprueba que el generador es DETERMINISTA: dos ejecuciones
	seguidas tienen que producir el mismo JSON byte a byte. Si no, cada
	build seria distinto y no habria forma de comparar fuente y runtime.

	Uso:  node tools/forest-build-check.js
	Codigo de salida 0 si todo pasa.
*/

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const ROOT = path.join(__dirname, "..");
const ROJO = path.join(ROOT, "rojo", "rojo.exe");
const CACHE = path.join(ROOT, ".cache");
const BUILD = path.join(CACHE, "forest-check.rbxlx");

const failures = [];

function check(label, condition, detail) {
	console.log((condition ? "  PASS  " : "  FAIL  ") + label + (detail ? "  (" + detail + ")" : ""));
	if (!condition) {
		failures.push(label);
		// Se deja la muestra del XML para leer el formato real de Rojo:
		// suponer el formato fue lo que produjo los falsos negativos.
		if (typeof dumpSample === "function") dumpSample();
	}
}

/** Cuenta apariciones de `<string name="Name">PREFIX...`. */
function countNamed(xml, prefix) {
	const re = new RegExp('<string name="Name">' + prefix + '[^<]*</string>', "g");
	return (xml.match(re) || []).length;
}

// ------------------------------------------------- 0. DETERMINISMO
console.log("=== 0. DETERMINISMO DEL GENERADOR ===");

const projFile = path.join(ROOT, "default.project.json");
const before = fs.readFileSync(projFile, "utf8");
execFileSync("node", [path.join(__dirname, "generate-project.js")], {
	cwd: ROOT,
	stdio: ["ignore", "pipe", "pipe"],
});
const after = fs.readFileSync(projFile, "utf8");

check(
	"dos ejecuciones producen el mismo JSON",
	before === after,
	before === after ? "identico" : "DIFIERE: la geometria no es reproducible"
);

// ------------------------------------------------- 1. BUILD
console.log("\n=== 1. BUILD DE ROJO ===");
fs.mkdirSync(CACHE, { recursive: true });
try {
	execFileSync(ROJO, ["build", "default.project.json", "-o", BUILD], {
		cwd: ROOT,
		stdio: ["ignore", "pipe", "pipe"],
		maxBuffer: 512 * 1024 * 1024,
	});
} catch (err) {
	console.log("  FAIL  Rojo no pudo construir el proyecto.");
	console.log(((err.stderr || "") + (err.stdout || "")).toString().trim());
	console.log("");
	console.log("Diagnostico: node tools/rojo-bisect.js");
	process.exit(1);
}
check("Rojo construye el proyecto", true, path.relative(ROOT, BUILD));

const xml = fs.readFileSync(BUILD, "utf8");
check("el build no esta vacio", xml.length > 100000, Math.round(xml.length / 1024) + " KB");

// Cuando algo falla se deja una muestra del XML. Sirve para leer el
// formato REAL que usa Rojo: suponerlo produjo falsos negativos (0
// tamanos, 0 rotaciones) cuando los datos si estaban ahi. Si todo
// pasa, no se deja nada.
const sample = path.join(CACHE, "forest-fail-sample.txt");
function dumpSample() {
	if (fs.existsSync(sample)) return;
	const at = xml.indexOf('<string name="Name">Block_0');
	fs.writeFileSync(sample, xml.slice(Math.max(0, at - 2000), at + 5000));
}

// ------------------------------------------------- 2. BLOQUES
console.log("\n=== 2. BLOQUES DESTRUCTIBLES EN EL ARTEFACTO ===");

const blockNames = new Set(
	(xml.match(/<string name="Name">Block_[^<]*<\/string>/g) || []).map((s) => s.replace(/<[^>]+>/g, ""))
);
check("48 bloques unicos en el build", blockNames.size === 48, blockNames.size + " bloques");

// Ni un hijo decorativo puede colarse con el prefijo: `CollectBlocks`
// contaria ese hijo como bloque y el recuento pasaria de 48.
const wrong = [...blockNames].filter((n) => !/^Block_\d+$/.test(n));
check("ningun hijo vuelve a usar el prefijo Block_", wrong.length === 0, wrong.join(","));

// ------------------------------------------------- 3. VARIANTES
console.log("\n=== 3. VARIANTES (donde no deben perderse) ===");

// La variante viaja en el NOMBRE de la decoracion, no en un atributo.
// Se comprueba que esas piezas llegaron al build CON la letra de
// variante: si se perdieran, el bosque tendria forma pero perderia la
// identidad, que es exactamente el defecto que se quiere corregir.
const variantPieces = (xml.match(/<string name="Name">Deco_[A-D]_[A-Za-z]+/g) || []).map((s) => /Deco_([A-D])_/.exec(s)[1]);

check("la decoracion con letra de variante llega al build", variantPieces.length > 0, variantPieces.length + " piezas");

const counts = {};
for (const v of variantPieces) counts[v] = (counts[v] || 0) + 1;
check("hay al menos 3 variantes distintas en el build", Object.keys(counts).length >= 3, JSON.stringify(counts));

// Los atributos de instancia NO deben aparecer: Rojo 7.7.0 no los
// soporta desde el proyecto. Si aparecieran, el build seria de otra
// version de Rojo y estas comprobacioneszaiarian de estar obsoletas.
check("Rojo no ha escrito atributos de instancia (no los soporta)", xml.indexOf("ForestVariant") === -1, "sin atributos, como se espera");

// ------------------------------------------------- 4. GEOMETRIA
console.log("\n=== 4. GEOMETRIA EN EL ARTEFACTO ===");

// El formato REAL que escribe Rojo no es `<float name="X">` sino:
//
//     <Vector3 name="size">
//       <X>8</X>
//       <Y>8</Y>
//       <Z>8</Z>
//     </Vector3>
//
// Se busco primero con el formato equivocado y daba 0 tamanos, lo que
// produjo FALSOS NEGATIVOS: hacia pensar que el mapa no tenia variedad
// cuando si la tenia. El formato se ha leido del build, no supuesto.
const sizes = new Set();
const sizeRe = /<Vector3 name="size">\s*<X>([^<]+)<\/X>\s*<Y>([^<]+)<\/Y>\s*<Z>([^<]+)<\/Z>\s*<\/Vector3>/g;
let m;
while ((m = sizeRe.exec(xml)) !== null) {
	sizes.add(m[1] + "x" + m[2] + "x" + m[3]);
}
check("el mapa tiene muchos tamanos distintos", sizes.size >= 20, sizes.size + " tamanos");

// El cubo 8x8x8 identico, 48 veces, es exactamente el defecto anterior.
const legacyCount = (xml.match(/<Vector3 name="size">\s*<X>8<\/X>\s*<Y>8<\/Y>\s*<Z>8<\/Z>/g) || []).length;
check("el cubo 8x8x8 ya no es la norma", legacyCount < 20, legacyCount + " apariciones de 8x8x8 (antes eran 48 bloques)");

// ------------------------------------------------- 5. DECORACION
console.log("\n=== 5. DECORACION Y BORDES ===");

for (const prefix of ["Tree_", "Crystal_", "Firefly_", "Border_Hill_", "Sand_", "Path_", "Energy_Ring_"]) {
	const count = countNamed(xml, prefix);
	check("existe decoracion '" + prefix + "*'", count > 0, count + " piezas");
}

// ------------------------------------------------- 6. COLISION
console.log("\n=== 6. LA DECORACION NO COLISIONA ===");

// Las unicas piezas que colisionan deben ser la geometria de JUEGO: suelo,
// muros, bloques y spawns. Toda la decoracion es `CanCollide = false`.
//
// No se comprueba con un numero inventado: se LISTA quien colisiona. Un
// umbral sobreestimado daba un falso negativo ("120, demasiadas") cuando
// 120 era el numero correcto de piezas de juego.
const colliding = [];
{
	// Cada `<Item ...>` se recorre por separado y se lee su Name y su
	// CanCollide. Hace falta ASI porque el XML de Rojo escribe las
	// propiedades en orden alfabetico, no en un orden fijo util.
	const items = xml.split("<Item ");
	for (const chunk of items) {
		const propsStart = chunk.indexOf("<Properties>");
		const propsEnd = chunk.indexOf("</Properties>");
		if (propsStart === -1 || propsEnd === -1) continue;
		const props = chunk.slice(propsStart, propsEnd);

		if (props.indexOf("<bool name=\"CanCollide\">true</bool>") === -1) continue;

		const nameMatch = /<string name="Name">([^<]*)<\/string>/.exec(props);
		if (nameMatch) colliding.push(nameMatch[1]);
	}
}

// Agrupar por familia para que el resultado sea legible.
const families = {};
for (const n of colliding) {
	const key = n.replace(/[_0-9]+$/, "") || n;
	families[key] = (families[key] || 0) + 1;
}

check(
	"la decoracion no colisiona",
	Object.keys(families).every((k) => !/^(Tree_|Bush_|Flower_|Shroom_|Sand_|Path_|Border_|Crystal_|Firefly_|Energy_|Deco_|Terrain_|LampGlow_|Lamp_)/.test(k)),
	colliding.length + " colisionables"
);
console.log("      colisionan: " + JSON.stringify(families));

// ------------------------------------------------- 7. ILUMINACION
console.log("\n=== 7. ILUMINACION ===");
check("Atmosphere en el build", xml.indexOf('class="Atmosphere"') !== -1);
check("BloomEffect en el build", xml.indexOf('class="BloomEffect"') !== -1);
check("ClockTime escrito", xml.indexOf('<float name="ClockTime">') !== -1);

const pointLights = (xml.match(/class="PointLight"/g) || []).length;
check("presupuesto de luces puntuales", pointLights <= 12, pointLights + " PointLight");

// ------------------------------------------------- RESUMEN
fs.rmSync(BUILD, { force: true });

console.log("\n=== RESUMEN ===");
if (failures.length === 0) {
	console.log("EL ARTEFACTO CONSTRUIDO CONTIENE EL BOSQUE REVISADO.");
	console.log("");
	console.log("Recordatorio: esto sigue siendo una verificacion ESTRUCTURAL.");
	console.log("Que la geometria este bien escrita no dice si el bosque se ve bien.");
	process.exit(0);
} else {
	console.log("FALLAN " + failures.length + ": " + failures.join(" | "));
	process.exit(1);
}