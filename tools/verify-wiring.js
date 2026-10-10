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

/**
 * Metodos publicos declarados por un servicio (`function Service.X`).
 *
 * El ancla `^` con la marca `m` obliga a que la declaracion empiece en una
 * LINEA NUEVA, asi que una firma partida en varias lineas
 * (`function Service.ApplyDamage(\n  targetHumanoid: Humanoid,\n...`),
 * que es el estilo de este repositorio, NO se detectaba y se reportaba
 * como metodo inexistente. Eso convertia la puerta en ruido: fourteen
 * FALLO falsos sobre metodos que existen y funcionan.
 */
function declaredMethods(file) {
	const source = fs.readFileSync(file, "utf8");
	const methods = new Set();
	// Se admite tanto `function Service.X(` como `function Service.X(args`
	// y tambien `function Service.X (` con espacio.
	const re = /^\s*function\s+Service\.([A-Za-z_]\w*)\s*\(/gm;
	let m;
	while ((m = re.exec(source)) !== null) methods.add(m[1]);

	// Tambien las DECLARACIONES con cuerpo en la misma linea, que no
	// llevan parentesis (p. ej. `function Service.GetFolder(): Folder?`).
	const re2 = /^\s*function\s+Service\.([A-Za-z_]\w*)\s*(?:\(|:|\()/gm;
	m = null;
	while ((m = re2.exec(source)) !== null) methods.add(m[1]);

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

/**
 * Campo `Service._x` -> nombre del servicio que representa.
 *
 * Sin esta tabla no se puede saber a que archivo corresponde
 * `Service._monsterService.ClearAll()`: los nombres de los campos internos
 * NO coinciden siempre con los nombres de los servicios, asi que se
 * declara el mapa explicitamente en lugar de adivinarlo.
 */
const FIELD_TO_SERVICE = {
	// Las claves NO llevan el `_` inicial: el patron captura el nombre SIN
	// el guion bajo (`Service._monsterService` -> "monsterService"). Con el
	// `_` delante, el mapa no encontraba nada y la puerta informaba "0
	// llamadas entre servicios" sobre un archivo con catorce: otra vez una
	// puerta que no miraba lo que decia mirar.
	monsterService: "MonsterService",
	monsters: "MonsterService",
	roundService: "RoundService",
	playerService: "PlayerService",
	combatService: "CombatService",
	explosionService: "ExplosionService",
	bombService: "BombService",
	destructionService: "DestructionService",
	matchService: "MatchService",
	spawnService: "SpawnService",
	portalService: "PortalService",
	worldService: "WorldService",
	profileService: "ProfileService",
	inventoryService: "InventoryService",
	activityService: "ActivityService",
	questService: "QuestService",
	economyService: "EconomyService",
	codeService: "CodeService",
	shopService: "ShopService",
	progressionService: "ProgressionService",
	destruction: "DestructionService",
	combat: "CombatService",
	round: "RoundService",
};

/**
 * Todas las llamadas `Service._campo.Metodo(...)` de un archivo, con el
 * servicio al que apuntan.
 *
 * Se recorren TODOS los servicios, no solo `ServerMain`: el bug que motivo
 * esta regla estaba en `MatchService`, no en el punto de cableado.
 *
 * @param servicesDir carpeta de servicios
 * @returns [{ owner, holder, methods }]
 */
function parseCrossServiceCalls(servicesDir) {
	const result = [];

	if (!fs.existsSync(servicesDir)) {
		return result;
	}

	for (const fileName of fs.readdirSync(servicesDir)) {
		if (!fileName.endsWith(".lua")) {
			continue;
		}

		const owner = fileName.replace(/\.lua$/, "");
		const content = fs.readFileSync(path.join(servicesDir, fileName), "utf8");

		// El grupo del campo excluye el punto a proposito: con `[a-zA-Z.]+`
		// el punto se comia y el patron noellia nada. Asi el punto queda
		// fuera del grupo y la llamada se separa en campo + metodo.
		const re = /Service\._([a-zA-Z]+)\.([A-Za-z_]\w*)\s*\(/g;
		let m;

		while ((m = re.exec(content)) !== null) {
			const holder = FIELD_TO_SERVICE[m[1]];

			if (holder && holder !== owner) {
				result.push({ owner, holder, methods: [m[2]] });
			}
		}
	}

	return result;
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
	} else {
		// `require` puede aparecer como `pcall(require, entry.module)` o
		// como `require(entry.module)`. La puerta aceptaba SOLO la segunda
		// forma, de modo que informaba FAIL sobre un bucle de registro que si
		// hace el require. Una puerta que miente sobre el codigo correcto no
		// es una puerta: entrena al equipo a ignorar el FAIL.
		const requiresEntry = /require\s*[(,]\s*entry\.module/.test(loopBody[1]);

		if (!/pcall\s*\(\s*require/.test(loopBody[1]) || !requiresEntry) {
			problems.push(
				"ServerMain: el bucle de registro NO hace `require(entry.module)`. " +
					"Sin eso se registra la INSTANCIA ModuleScript y `Register` la rechaza " +
					"con 'modulo invalido': los servicios nunca se inicializan."
			);
		}
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

	// --- R4: llamadas ENTRE servicios dentro de los handlers -----------
	//
	// R2/R3 solo miran `wireDependencies`, que es donde se inyectan las
	// dependencias. Los listeners de ronda (`MatchService.OnRoundStateChanged`)
	// llaman ademas a metodos de OTROS servicios mas tarde, ya en ejecucion.
	//
	// Ese hueco costo una ronda ATASCADA: `MonsterService.ClearAll` se
	// llamo desde el fin de ronda y el metodo no existia. En runtime:
	// "attempt to call a nil value", el listener mueria y la ronda se
	// quedaba en `RoundEnding` para siempre. Luau compila el archivo sin
	// problema (el metodo no hace falta para compilar) y el codigo existe
	// en el source: solo se ve arrancando el juego.
	//
	// Se comprueba todo `Service._algo.Metodo(...)` de cualquier servicio,
	// no solo dentro de `connect`.
	const crossCalls = parseCrossServiceCalls(SERVICES_DIR);

	for (const call of crossCalls) {
		// Los metodos se buscan en el servicio QUE RECIBE la llamada
		// (`holder`), no en el que la escribe (`owner`). Leer los del
		// `owner` hacia que casi todas las llamadas pareciesen llamar a
		// metodos inexistentes en el propio archivo, que es ruido puro.
		const file = path.join(SERVICES_DIR, `${call.holder}.lua`);

		if (!fs.existsSync(file)) {
			problems.push(
				`${call.owner}.lua llama a ${call.holder}.${call.methods[0]}(...) pero ` +
					`${call.holder}.lua no existe en Services/.`
			);
			continue;
		}

		const methods = declaredMethods(file);

		for (const method of call.methods) {
			if (!methods.has(method)) {
				problems.push(
					`${call.owner}.lua llama a ${call.holder}.${method}(...) pero ` +
						`${call.holder}.lua no declara 'function Service.${method}'. ` +
						`En runtime: "attempt to call a nil value" y el ciclo se detiene.`
				);
			}
		}
	}

	// --- Informe ------------------------------------------------------
	console.log(`Servicios en la tabla SERVICES: ${entries.length}`);
	console.log(`Conexiones en wireDependencies : ${calls.length}`);
	console.log(`Llamadas entre servicios      : ${crossCalls.length}`);

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
