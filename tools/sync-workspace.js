"use strict";

/*
	sync-workspace.js
	Extrae el contenido de Workspace del build de Rojo a un `.rbxm`.

	POR QUE EXISTE
	--------------
	Hay una divergencia real entre SOURCE y RUNTIME:

	  default.project.json  -> 169 instancias
	  DataModel de Studio   -> 104 instancias

	El codigo (ServerMain, 31 servicios, 8 remotes, 12 controllers) SI
	esta sincronizado. Lo que falta es TODA la geometria: Workspace
	.Worlds.*, .Lobby, .Environment y .SpawnLocations estan vacios en
	Studio.

	La causa no es Rojo: `rojo build` produce las 169 instancias
	correctas, con `ArenaFloor`, `Block_1..N` y los 4 LobbySpawn. El
	problema es que el plugin de Rojo de Studio no esta sincronizando,
	y por eso hay que empujar el arbol por MCP.

	Este script no inventa nada: extrae literalmente el subarbol
	`Workspace` que Rojo acaba de construir y lo empaqueta como un
	Folder importable. Como la geometria no usa `Ref=`, ni `Asset` ni
	`Content`, el subarbol es autonomous y se puede mover entero.

	Uso:
	  node tools/sync-workspace.js          # genera .cache/workspace-source.rbxm
	  node tools/sync-workspace.js --stdout # vuelca el rbxm por stdout
*/

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const ROOT = path.join(__dirname, "..");
const ROJO = path.join(ROOT, "rojo", "rojo.exe");
const CACHE = path.join(ROOT, ".cache");
const BUILD = path.join(CACHE, "workspace-build.rbxlx");
const OUT = path.join(CACHE, "workspace-source.rbxm");

/**
 * CUAL SUBARBOL SE EXTRAE, Y DONDE SE ESCRIBE.
 *
 * Antes era fijo (`Workspace`). Se parametriza porque el proyecto tiene mas de
 * un servicio con geometria importable: el HUD vive en `StarterGui` y sin
 * importarlo nunca llegaba a Studio.
 *
 * El motivo REAL de hacerlo configurable es que `sync-all.js` daba por buena
 * una sincronizacion incompleta: `source-runtime-diff` comparaba el build con
 * el runtime y veia 58 interfaces de menos, pero el script solo importaba
 * Workspace, asi que la diferencia no se podia cerrar por mas que se
 * reintentara. No era Rojo: era que la herramienta no miraba donde estaba el
 * HUD.
 */
const TARGET_CLASS = process.env.SYNC_CLASS || "Workspace";
const TARGET_NAME = process.env.SYNC_NAME || "Workspace";
const OUT_FILE = process.env.SYNC_OUT || OUT;

/**
 * Nombre EXACTO que debe tener el Item a extraer, o "" para no filtrar.
 *
 * Es lo que distingue `ReplicatedStorage` de `StarterGui`: ambos son
 * `<Item class="Folder">`, asi que la clase sola no dice cual es cual.
 */
const TARGET_MATCH = process.env.SYNC_MATCH || "";

/** Ejecuta `rojo build` y devuelve el rbxlx como texto. */
function buildRbxlx() {
	fs.mkdirSync(CACHE, { recursive: true });
	try {
		execFileSync(ROJO, ["build", "default.project.json", "-o", BUILD], {
			cwd: ROOT,
			encoding: "utf8",
			stdio: ["ignore", "pipe", "pipe"],
		});
	} catch (err) {
		// Rojo escribe el aviso de "unknown property" en stderr pero
		// puede aun asi producir salida. Solo es fatal si no hay archivo.
		if (!fs.existsSync(BUILD)) {
			throw new Error("rojo build fallo: " + ((err.stderr || "") + (err.stdout || "")));
		}
	}
	return fs.readFileSync(BUILD, "utf8");
}

/**
 * Devuelve el subarbol `<Item ...>...</Item>` de la clase indicada.
 *
 * Si se pasa `wantedName`, busca ademas esa `<string name="Name">` DENTRO del
 * bloque de propiedades de ese mismo Item.
 *
 * POR QUE EL NOMBRE IMPORTA
 * ------------------------
 * Rojo emite varios `<Item class="Folder">` (ReplicatedStorage, StarterGui y
 * cada carpeta del Workspace). Quedarse con el PRIMERO metia el arbol
 * equivocado: al pedir "Folder" para el HUD se colaba ReplicatedStorage, se
 * importaban once RemoteEvents y el HUD se quedaba sin sincronizar otra vez,
 * con un DIVERGE que no explicaba nada.
 *
 * Se hace por texto y no con un parser XML porque hay que conservar el
 * formato EXACTO que Roblox espera, incluidas las referencias `ref="N"` y el
 * orden de las propiedades. Reescribir el documento con un parser generico las
 * perderia.
 *
 * @param {string} xml
 * @param {string} className
 * @param {string=} wantedName
 * @returns {string}
 */
function extractItem(xml, className, wantedName) {
	const openRe = new RegExp(`<Item class="${className}"(\\s[^>]*)?>`, "g");
	let match;

	while ((match = openRe.exec(xml)) !== null) {
		const start = match.index;

		if (wantedName) {
			// El nombre se busca dentro del bloque de propiedades de ESTE
			// Item, nunca en el documento entero: buscarlo globalmente daria
			// el nombre de un hijo y aceptaria el Item equivocado.
			const propsEnd = xml.indexOf("</Properties>", start);
			if (propsEnd === -1) continue;
			const nameMatch = /<string name="Name">([^<]*)<\/string>/.exec(
				xml.slice(start, propsEnd)
			);
			if (!nameMatch || nameMatch[1] !== wantedName) continue;
		}

		// El `<Item ...>` de apertura no puede anidarse en si mismo, asi que
		// se empieza a contar DESDE el siguiente caracter.
		let depth = 1;
		let i = start + match[0].length;

		while (i < xml.length && depth > 0) {
			const nextOpen = xml.indexOf("<Item ", i);
			const nextClose = xml.indexOf("</Item>", i);

			if (nextClose === -1) throw new Error("Subarbol sin cerrar: " + className);
			if (nextOpen !== -1 && nextOpen < nextClose) {
				depth += 1;
				i = nextOpen + 6;
			} else {
				depth -= 1;
				i = nextClose + 7;
			}
		}

		return xml.slice(start, i);
	}

	throw new Error(
		`No se encontro <Item class="${className}">` +
			(wantedName ? ` llamado "${wantedName}"` : "")
	);
}

function main() {
	const xml = buildRbxlx();
	const subtree = extractItem(xml, TARGET_CLASS, TARGET_MATCH);

	// El cuerpo del subarbol son sus hijos directos. Se reenvuelven en
	// un Folder para poder importarlos bajo el servicio destino sin
	// intentar crear un segundo servicio (Roblox no lo permite).
	//
	// BUG CORREGIDO (auditoria de importacion)
	// ----------------------------------------
	// El corte se hacia en el primer `>` del `<Item class="Workspace">`, que
	// es el de APERTURA del Item, de modo que el bloque de propiedades del
	// Workspace (Gravity, StreamingEnabled) quedaba PEGADO al Folder
	// envoltorio y el `.rbxm` llevaba DOS `<Properties>` dentro del MISMO
	// `<Item>`.
	//
	// Ese XML es invalido. Studio lo parsea con tolerancia y aplica lo que
	// entiende: las Partes llegaban con `Size` pero con `Position = (0,0,0)`,
	// de modo que TODO el lobby se apilaba en el origen mientras la arena,
	// declarada en el mismo archivo, conservaba sus coordenadas. La
	// divergencia era invisible en el recuento de instancias (source ==
	// runtime en numero) y solo se veía al medir posiciones.
	//
	// El corte correcto es DESPUES del `</Properties>` del Item.
	const propertiesEnd = subtree.indexOf("</Properties>");
	if (propertiesEnd === -1) {
		throw new Error("El <Item class=\"" + TARGET_CLASS + "\"> no tiene bloque <Properties>");
	}
	const bodyStart = subtree.indexOf(">", propertiesEnd) + 1;
	const bodyEnd = subtree.lastIndexOf("</Item>");
	const children = subtree.slice(bodyStart, bodyEnd);

	const rbxm =
		'<roblox version="4">\n' +
		'  <Item class="Folder">\n' +
		"    <Properties>\n" +
		'      <string name="Name">' + TARGET_NAME + 'Source</string>\n' +
		"    </Properties>\n" +
		children +
		"\n  </Item>\n" +
		"</roblox>\n";

	if (process.argv.includes("--stdout")) {
		process.stdout.write(rbxm);
		return;
	}

	fs.mkdirSync(CACHE, { recursive: true });
	fs.writeFileSync(OUT_FILE, rbxm, "utf8");

	const count = (rbxm.match(/<Item class="/g) || []).length;
	console.log("Subarbol " + TARGET_NAME + " extraido del build de Rojo.");
	console.log("  incluye la raiz Folder: " + count + " Items");
	console.log("  escrito en: " + path.relative(ROOT, OUT_FILE));

	// COMPROBACION ESTRUCTURAL (no es decorativa).
	//
	// Un `<Item>` con dos `<Properties>` es XML invalido. Studio lo acepta y
	// aplica solo lo que entiende, de modo que el fallo se manifiesta en el
	// JUEGO (geometria amontonada en el origen) y no en la importacion: el
	// comando sale con exito 0 y el recuento de instancias coincide. Por eso
	// el defecto tiene que detectarse aqui, antes de que llegue a Studio.
	//
	// Se comprueba de forma estructural y no comparando texto: se recorre el
	// documento contando aperturas y cierres de `<Properties>` por Item.
	const problems = validateRbxm(rbxm);
	if (problems.length) {
		for (const p of problems) console.log("  XML INVALIDO: " + p);
		console.log("");
		console.log("El .rbxm generado no es importable de forma fiable.");
		process.exit(1);
	}
}

/**
 * Valida que cada `<Item>` tenga como mucho un `<Properties>` y que el
 * documento este balanceado.
 *
 * @param {string} xml
 * @returns {string[]} problemas encontrados (vacio = correcto)
 */
function validateRbxm(xml) {
	const problems = [];
	const items = xml.match(/<Item [^>]*>|<Item class="[^"]*"[^>]*>/g) || [];
	let depth = 0;

	// Se recorren las APERTURAS y CIERRES de Item en orden, contando cuantos
	// `<Properties>` abiertos hay dentro de cada Item.
	let open = 0;
	let propertiesSeen = 0;
	const tokenRe = /<Item [^>]*>|<\/Item>|<Properties>|<\/Properties>/g;
	let m;

	while ((m = tokenRe.exec(xml)) !== null) {
		const t = m[0];
		if (t.startsWith("<Item ")) {
			depth += 1;
			open += 1;
			// Solo se vigila el Item mas externo: los internos se validan
			// al cerrar su padre.
			propertiesSeen = 0;
		} else if (t === "<Properties>") {
			propertiesSeen += 1;
			if (propertiesSeen > 1) {
				problems.push(`<Item> #${open} (nivel ${depth}) declara ${propertiesSeen} bloques <Properties>`);
			}
		} else if (t === "</Properties>") {
			propertiesSeen -= 1;
		} else if (t === "</Item>") {
			depth -= 1;
			open -= 1;
		}
	}

	if (depth !== 0) {
		problems.push(`desequilibrio de <Item>: quedan ${depth} sin cerrar`);
	}
	if (!xml.trimStart().startsWith("<roblox")) {
		problems.push("el documento no empieza por <roblox>");
	}
	if (!xml.trimEnd().endsWith("</roblox>")) {
		problems.push("el documento no termina en </roblox>");
	}

	return problems;
}

main();
