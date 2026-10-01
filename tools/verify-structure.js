"use strict";

/*
	verify-structure.js

	Comprobacion estructural de los servicios de servidor.

	Por que existe:
	Un archivo puede estar PERFECTAMENTE balanceado y aun asi estar roto.
	Ocurrio de verdad en `BombService.lua`: las definiciones de
	`spawnBomb`, `GetPlayerBombCount` y `TryPlaceBomb` estaban empalmadas
	dentro del bucle de cadena de `detonateBomb`, y el `end` de mas al
	final compensaba el desbalance.

	El resultado era un archivo que Luau aceptaba con EXIT 0 y que todos
	los tests de logica daban por bueno, pero en ejecucion
	`Service.TryPlaceBomb`, `Service.Init`, `Service.Start` y
	`Service.Destroy` nunca se definian: `ServerMain` recibia `nil` y el
	servicio no arrancaba. Ni el compilador ni los tests unitarios lo
	detectan; solo lo detecta mirar la ESTRUCTURA.

	La REGLA (misma que en tests/shared/ServiceStructure.spec.lua):
	1. La profundidad total del archivo debe ser 0 (nada de `end` de mas
	   ni bloques sin cerrar).
	2. Toda declaracion `function Service.X` / `local function Y` debe
	   estar en profundidad 0. Si esta dentro de un bloque, esa funcion
	   solo existe cuando se ejecuta ese bloque: el registro la recibe
	   como nil.
	3. El ultimo codigo del archivo debe ser `return <Servicio>`.

	La suite de Luau prueba el detector con ejemplos; este script lo
	aplica a los archivos reales, que desde `luau.exe` no se pueden leer
	(no expone `io`).

	Uso:  node tools/verify-structure.js
	Sale con codigo 1 si algo falla, para poder usarlo en integracion
	continua.
*/

const fs = require("fs");
const path = require("path");

const SERVICES_DIR = path.join(__dirname, "..", "src", "ServerScriptService", "Services");

/** Nombres de los servicios que ServerMain registra. */
const EXPECTED_SERVICES = [
	"BombService",
	"CombatService",
	"DestructionService",
	"ExplosionService",
	"MatchService",
	"PlayerService",
	"RoundService",
	"SpawnService",
	"WorldService",
];

/**
 * Elimina comentarios de bloque y de linea.
 * Los comentarios se sustituyen por espacios para no alterar el conteo
 * de lineas ni unir dos lineas en una.
 */
function stripComments(source) {
	const withoutBlocks = source.replace(/--\[\[[\s\S]*?\]\]/g, (block) =>
		block.replace(/[^\n]/g, " ")
	);
	return withoutBlocks.replace(/--[^\n]*/g, "");
}

/** Elimina cadenas de una linea para que `end` dentro de texto no cuente. */
function stripStrings(line) {
	return line.replace(/"(\\.|[^"\\])*"/g, '""').replace(/'(\\.|[^'\\])*'/g, "''");
}

/**
 * Cuenta palabras clave como palabras sueltas.
 *
 * La linea se envuelve con espacios sentinel en lugar de usar `^` / `$`
 * como ancladores, porque esos ancladores no son fiables dentro de
 * `gmatch` y producian un recuento de cero.
 */
function countWord(line, pattern) {
	const padded = ` ${line} `;
	const re = new RegExp(`[^\\w_.]${pattern}[\\s(){},;]`, "g");
	return (padded.match(re) || []).length;
}
/**
 * Cambio de profundidad que introduce una linea.
 *
 * Se descuentan el `do` de `for ... do` (no abre bloque propio) y las
 * expresiones `if ... then ... else ...` de Luau (no llevan `end`).
 *
 * Los patrones se aplican sobre la linea CON ESPACIOS SENTINELA, igual
 * que en `countWord`: sin ellos, un `for ... do` al final de la linea no
 * encuentra caracter tras `do` y el `do` se contaba como bloque abierto.
 */
function depthDelta(line) {
	const padded = ` ${line} `;

	const opens =
		countWord(line, "[Ff]unction") +
		countWord(line, "[Ii][Ff]") +
		countWord(line, "[Ff][Oo][Rr]") +
		countWord(line, "[Ww][Hh][Ii][Ll][Ee]") +
		countWord(line, "[Dd][Oo]");

	// El `do` de `for ... do` y de `while ... do` NO abre un bloque
	// propio: el bloque lo abre el `for` / el `while`. Se busca el `do`
	// seguido de un separador o del final de la linea.
	const forDo = (padded.match(/[^\w_][Ff][Oo][Rr][^\n]*\s[Dd][Oo][\s%w]/) || []).length;
	const whileDo = (
		padded.match(/[^\w_][Ww][Hh][Ii][Ll][Ee][^\n]*\s[Dd][Oo][\s%w]/) || []
	).length;

	const ifExpressions = (
		padded.match(
			/[^\w_][Ii][Ff][^\n]*?\s+[Tt][Hh][Ee][Nn][^\n]*?[^\w_][Ee][Ll][Ss][Ee][^\w]/g
		) || []
	).length;

	const ends = countWord(line, "[Ee][Nn][Dd]");

	return opens - forDo - whileDo - ifExpressions - ends;
}

/** Analiza un fuente y devuelve su estructura. */
function analyze(source) {
	const stripped = stripComments(source);
	const lines = stripped.split("\n");

	let depth = 0;
	let worstDeclarationDepth = 0;
	let worstDeclarationLine = 0;
	let lineNumber = 0;
	let lastCode = null;

	for (const raw of lines) {
		lineNumber += 1;
		const line = stripStrings(raw);

		const trimmed = raw.trim();
		if (trimmed !== "" && !trimmed.startsWith("--")) {
			lastCode = trimmed;
		}

		// Solo interesan las funciones PUBLICAS del servicio
		// (`function Service.X`). Un `local function` anidado es
		// legitimo: un closure dentro de otra funcion se define al
		// ejecutarse su contenedor, y eso es exactamente lo que se
		// quiere. Lo que rompe el registro es que `Service.Init`,
		// `Service.Start` o `Service.Destroy` no existan nunca.
		const isDeclaration = /^function\s+Service\./.test(trimmed);

		if (isDeclaration && depth > worstDeclarationDepth) {
			worstDeclarationDepth = depth;
			worstDeclarationLine = lineNumber;
		}

		depth += depthDelta(line);
	}

	return { finalDepth: depth, worstDeclarationDepth, worstDeclarationLine, lastCode };
}

function main() {
	const problems = [];
	let checked = 0;

	for (const name of EXPECTED_SERVICES) {
		const file = path.join(SERVICES_DIR, `${name}.lua`);

		if (!fs.existsSync(file)) {
			problems.push(`${name}.lua no existe`);
			continue;
		}

		checked += 1;
		const result = analyze(fs.readFileSync(file, "utf8"));
		const where = path.relative(process.cwd(), file);

		if (result.finalDepth !== 0) {
			problems.push(
				`${where}: profundidad final ${result.finalDepth} (hay un 'end' de mas o un bloque sin cerrar)`
			);
		}

		if (result.worstDeclarationDepth > 0) {
			problems.push(
				`${where}:${result.worstDeclarationLine} declaracion de nivel superior dentro de un bloque ` +
					`(profundidad ${result.worstDeclarationDepth}). Esa funcion NO existiria al ejecutar.`
			);
		}

		if (result.lastCode !== "return Service") {
			// Todos los servicios devuelven su tabla local `Service`. Si el
			// empalmamiento se lleva por delante un `return`, la ultima
			// linea deja de ser el return del modulo.
			problems.push(
				`${where}: el ultimo codigo es ${JSON.stringify(result.lastCode)}, se esperaba 'return Service'`
			);
		}
	}

	console.log(`Servicios analizados: ${checked} de ${EXPECTED_SERVICES.length}`);

	if (problems.length > 0) {
		console.log("");
		for (const problem of problems) {
			console.log(`  FALLO  ${problem}`);
		}
		console.log("");
		console.log("RESULTADO: FAIL");
		process.exit(1);
	}

	console.log("Estructura correcta: sin 'end' huerfano, funciones en nivel superior.");
	console.log("RESULTADO: PASS");
	process.exit(0);
}

main();