"use strict";

/*
	verify-wiring.js
	Contrato estatico entre `ServerMain` y los servicios que arranca.

	POR QUE EXISTE
	--------------
	Los dos P0 que dejaron el juego sin arrancar en Studio eran errores
	ESTATICOS, y ninguna prueba los veia porque todas usaban dobles de
	prueba que ya eran tablas correctas:

	  1. `ServerMain` pasaba `entry.module` (la INSTANCIA ModuleScript)
	     a `Registry:Register`, que rechaza lo que no sea `table`. Los
	     nueve servicios se rechazaban y el servidor arrancaba "vacío":
	     "0 servicios inicializados", sin un solo error rojo.

	  2. `wireDependencies` llamaba `BombService.SetDependencies(...)` y
	     ese metodo no existia: "attempt to call a nil value" en
	     ServerMain:170, ya DESPUES de inicializar los nueve servicios.

	Los dos comparten forma: alguien llama a algo que no existe. Es
	comprobable sin arrancar Roblox, leyendo el fuente. Eso es lo que
	hace este script, y por eso puede ir en integracion continua.

	QUE COMPRUEBA
	-------------
	  R1. Todo servicio de la tabla `SERVICES` se `require` antes de
	      registrarse. Sin `require` llega una Instance, no una tabla.
	  R2. Todo metodo invocado sobre un servicio en `wireDependencies`
	      esta declarado en ese servicio.
	  R3. Todo servicio citado en `wireDependencies` existe como archivo.

	Uso:  node tools/verify-wiring.js
	Salida con codigo 1 si algo falla.
*/

const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..");
const SERVER_MAIN = path.join(ROOT, "src", "ServerScriptService", "ServerMain.server.lua");
const SERVICES_DIR = path.join(ROOT, "src", "ServerScriptService", "Services");

/** Metodos publicos declarados por un servicio (`function Service.X`). */
function declaredMethods(file) {
	const source = fs.readFileSync(file, "utf8");
	const methods = new Set();
	const re = /^function\s+Service\.([A-Za-z_]\w*)/gm;
	let m;
	while ((m = re.exec(source)) !== null) methods.add(m[1]);
	return methods;
}

/**
 * Entradas de la tabla `SERVICES`.
 * Devuelve [{ name, module }] con `module` siendo el nombre del
 * servicio referenciado en `SERVER.Services.X`.
 */
function parseServiceTable(source) {
	const entries = [];
	const re = /\{\s*name\s*=\s*"([^"]+)"\s*,\s*module\s*=\s*SERVER\.Services\.(\w+)/g;
	let m;
	while ((m = re.exec(source)) !== null) {
		entries.push({ name: m[1], module: m[2] });
	}
	return entries;
}

/**
 * Llamadas `service.Metodo(...)` dentro de cada bloque `connect(...)`.
 * Devuelve [{ label, methods: [...] }].
 */
function parseWiringCalls(source) {
	const calls = [];
	const re = /connect\(\s*"([^"]+)"\s*,\s*(\w+)\s*,\s*\{([^}]*)\}\s*,\s*\n?\s*function\s*\(\s*service/g;
	let m;
	while ((m = re.exec(source)) !== null) {
		// Se toma el cuerpo de la funcion hasta el `end` que la cierra,
		// contando profundidad para no comerse el siguiente connect.
		let depth = 0;
		let i = m.index + m[0].length;
		let body = "";
		for (; i < source.length; i += 1) {
			const ch = source[i];
			if (ch === "(") depth += 1;
			else if (ch === ")") {
				if (depth === 0) break;
				depth -= 1;
			}
			body += ch;
		}
		const methods = [];
		const mre = /service\.([A-Za-z_]\w*)\s*\(/g;
		let mm;
		while ((mm = mre.exec(body)) !== null) methods.push(mm[1]);
		calls.push({ label: m[1], methods });
	}
	return calls;
}

function main() {
	const problems = [];

	// --- R1: los servicios se require, no se pasan en crudo ----------
	const source = fs.readFileSync(SERVER_MAIN, "utf8");
	const entries = parseServiceTable(source);

	if (entries.length === 0) {
		problems.push("ServerMain: no se encontro ninguna entrada en la tabla SERVICES");
	}

	const registerLoop = /for\s+_,\s*entry\s+in\s+ipairs\(SERVICES\)\s+do([\s\S]*?)end/;
	const loopBody = registerLoop.exec(source);
	if (!loopBody) {
		problems.push("ServerMain: no se encontro el bucle de registro de SERVICES");
	} else if (!/pcall\(\s*require/.test(loopBody[1]) || !/require\(\s*entry\.module/.test(loopBody[1])) {
		problems.push(
			"ServerMain: el bucle de registro NO hace `require(entry.module)`. " +
				"Sin eso se registra la INSTANCIA ModuleScript y `Register` la rechaza " +
				"con 'modulo invalido': los servicios nunca se inicializan."
		);
	}

	// --- R2/R3: los metodos cableados existen en su servicio ----------
	const calls = parseWiringCalls(source);
	if (calls.length === 0) {
		problems.push("ServerMain: no se encontro ningun connect() en wireDependencies");
	}

	for (const call of calls) {
		const file = path.join(SERVICES_DIR, `${call.label}.lua`);
		if (!fs.existsSync(file)) {
			problems.push(`wireDependencies: "${call.label}" no existe como servicio (${call.label}.lua)`);
			continue;
		}
		const methods = declaredMethods(file);
		for (const method of call.methods) {
			if (!methods.has(method)) {
				problems.push(
					`wireDependencies: llama a ${call.label}.${method}(...) pero ` +
						`${call.label}.lua no declara 'function Service.${method}'. ` +
						`En runtime: "attempt to call a nil value".`
				);
			}
		}
	}

	// --- Informe ------------------------------------------------------
	console.log(`Servicios en la tabla SERVICES: ${entries.length}`);
	console.log(`Conexiones en wireDependencies : ${calls.length}`);

	if (problems.length > 0) {
		console.log("");
		for (const p of problems) console.log("  FALLO  " + p);
		console.log("");
		console.log("RESULTADO: FAIL");
		process.exit(1);
	}

	console.log("Todos los servicios se cargan con require y todos los metodos cableados existen.");
	console.log("RESULTADO: PASS");
	process.exit(0);
}

main();
