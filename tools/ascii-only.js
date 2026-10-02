// ascii-only.js
// Traduce a ASCII el fuente de `src/` y avisa de lo que ya es ASCII puro.
//
// MEDIDO, NO SUP UESTO
// ---------------------
// `mojibake-transport-tmp.js` escribio en Studio un ModuleScript con UN solo
// U+00BF y lo releyo con U+00C2 delante (`len=48 C2BF=1` en lugar de
// `len=47 C2BF=0`). Es decir: la herramienta MCP `set_script_source` anade un
// byte de mas delante de cada caracter de doble ancho, y `sync-scripts.js` la
// usa en cada archivo.
//
// Consecuencia: cualquier tilde, raya o simbolo del repositorio llega
// DOBLEMENTE codificado a Studio. El juego no se rompe por ello, pero los
// comentarios quedan ilegibles justo en las reglas de seguridad
// (`RemoteGateway`), que es donde mas cuesta leerlos.
//
// POR QUE ASCII Y NO "ARREGLAR LA HERRAMIENTA"
// --------------------------------------------
// El plugin MCP esta fuera del repositorio y su version no es nuestra. Un
// ASCII sin acentos atraviesa su codificacion intacto, y el resto del codigo
// de este proyecto ya esta escrito asi ("esta", "aqui", "codigo"). Esta
// herramienta deja el source en el mismo idioma que ya se usa, sin depender
// de un componente que no controlamos.
//
// USO
// ---
//   node tools/ascii-only.js          # informe
//   node tools/ascii-only.js --fix    # traduce y reescribe
//
// Ejecutar sin `--fix` devuelve codigo 1 si hay algo que arreglar, para poder
// usarse como puerta en integracion continua.
const fs = require("fs");
const path = require("path");

const FIX = process.argv.includes("--fix");

/**
 * Mapa de equivalencia.
 *
 * `n` con virgulilla delante de vocal NECESITA el signo para no leerse como
 * otra letra, asi que ahi se quita la virgulilla ("pequeno", no "pequeno" con
 * n suelta). En el resto basta con borrar el acento: es la misma palabra
 * escrita sin tilde, no otra palabra.
 */
const MAP = new Map(
	Object.entries({
		"\u00e1": "a", // a acentuada
		"\u00e9": "e", // e acentuada
		"\u00ed": "i", // i acentuada
		"\u00f3": "o", // o acentuada
		"\u00fa": "u", // u acentuada
		"\u00f1": "n", // enye
		"\u00e0": "a", // a grave
		"\u00e8": "e", // e grave
		"\u00ec": "i", // i grave
		"\u00f2": "o", // o grave
		"\u00f9": "u", // u grave
		"\u00c1": "A",
		"\u00c9": "E",
		"\u00cd": "I",
		"\u00d3": "O",
		"\u00da": "U",
		"\u00d1": "N",
		"\u00bf": "?", // interrogacion de apertura
		"\u00a1": "!", // exclamacion de apertura
		"\u00ab": '"', // comillas angulares de apertura
		"\u00bb": '"', // comillas angulares de cierre
		"\u2014": "-", // raya larga
		"\u2013": "-", // raya corta
		"\u2018": "'",
		"\u2019": "'",
		"\u201c": '"',
		"\u201d": '"',
		"\u00b7": "-", // punto medio
		"\u2192": "->", // flecha
		"\u221e": "*", //riel
		"\u00a0": " ", // espacio duro
		// Secuencia medida en `RoundService.lua:564`. El texto es
		// "el error de una corrutina espiral abortada": la palabra "espiral"
		// llego como U+B098 U+C120 (bytes EB 82 98 EC 84 A0), seis bytes por
		// cinco letras. No hay una regla que lo revierta de forma general, y
		// ademas no hace falta: la palabra se deduce del sentido de la frase y
		// se sustituye entera. Un comentario que dice "corrutina espiral
		// abortada" explica por que la ronda se quedaba colgada; el mismo
		// comentario con dos simbolos no explica nada.
		"\uB098\uC120": "espiral",
	})
);

/**
 * Sustituye el texto usando el mapa.
 *
 * El orden importa y NO es un detalle: las secuencias de mas de un caracter
 * (la de `espiral`) tienen que resolverse ANTES de pasar caracter a
 * caracter, porque en un recorrido `for ... of` cada `U+00D9` se consumiria
 * por su cuenta y la secuencia jamas se veria junta.
 *
 * Se recorre por el indice de la cadena, no con `split("")`, precisamente
 * para que el codigo de un caracter mayor que BMP (un emoji, por ejemplo) no
 * se parta en dos.
 */
function toAscii(text) {
	// 1. Secuencias largas, de una pasada y con un mapa que se indexa por
	//    longitud para que la mas larga gane: si "ab" y "abc" estuvieran,
	//    whichever se mire primero decidiria el resultado.
	const sequences = [...MAP.entries()]
		.filter(([key]) => key.length > 1)
		.sort((a, b) => b[0].length - a[0].length);

	// 2. Despues, los caracteres sueltos.
	const singles = new Map([...MAP.entries()].filter(([key]) => key.length === 1));

	let out = "";
	let i = 0;

	while (i < text.length) {
		const match = sequences.find(([key]) => text.startsWith(key, i));
		if (match) {
			out += match[1];
			i += match[0].length;
			continue;
		}

		const ch = String.fromCodePoint(text.codePointAt(i));
		i += ch.length;

		const replacement = singles.get(ch);
		if (replacement === undefined) {
			// Sin equivalencia conocida: se deja el caracter y se informa, en vez
			// de borrarlo. Perder texto de un comentario es peor que un aviso.
			out += ch;
			continue;
		}
		out += replacement;
	}

	return out;
}

function walk(dir, out = []) {
	for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
		const p = path.join(dir, entry.name);
		if (entry.isDirectory()) walk(p, out);
		else if (p.endsWith(".lua")) out.push(p);
	}
	return out;
}

const root = path.join(__dirname, "..", "src");
const unknown = new Map();
const touched = [];

for (const file of walk(root)) {
	const before = fs.readFileSync(file, "utf8");
	const after = toAscii(before);

	// Lo que NO se pudo traducir se busca en `after`, no en `before`: en el
	// texto original la secuencia de `espiral` aparece como dos caracteres sueltos
	// que el mapa de uno en uno no reconoce, y el aviso diria "sin traduccion"
	// de algo que la funcion SÍ sabe arreglar. El aviso tiene que describir la
	// salida, que es lo que se acaba escribiendo en el archivo.
	for (const ch of after) {
		if (ch.codePointAt(0) > 127) unknown.set(ch, (unknown.get(ch) || 0) + 1);
	}

	if (after !== before) {
		touched.push(path.relative(root, file));
		if (FIX) fs.writeFileSync(file, after, "utf8");
	}
}

if (unknown.size > 0) {
	console.log("SIN TRADUCCION (revisar a mano):");
	for (const [ch, n] of unknown) {
		console.log(`  U+${ch.codePointAt(0).toString(16).toUpperCase()} x${n}`);
	}
}

console.log(`ARCHIVOS CON NO ASCII: ${touched.length}`);
for (const f of touched) console.log("  " + f);

if (FIX) {
	console.log(touched.length === 0 ? "ASCII: ya todo correcto" : "corregidos: SI");
} else {
	console.log(touched.length === 0 ? "ASCII: ya todo correcto" : "corregidos: NO (pasa --fix)");
	process.exitCode = touched.length === 0 ? 0 : 1;
}