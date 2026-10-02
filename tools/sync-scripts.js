"use strict";

/*
	sync-scripts.js
	Empuja el fuente de los scripts del repositorio al DataModel de
	Studio, usando MCP `set_script_source`.

	POR QUE EXISTE
	--------------
	El plugin de Rojo no esta conectado a esta sesion de Studio, de modo
	que `rojo serve` (puerto 34872, activo) no alcanza el lugar abierto:
	el arbol llego a Studio en su momento, pero los cambios posteriores en
	el repositorio NO se ven en runtime. Conectar el plugin es un paso
	manual (`Plugin > Rojo > Connect`) que MCP no puede ejecutar.

	Este script es el equivalente funcional para el codigo: recorre
	`src/`, mapea cada archivo a su ruta en el arbol y reescribe el
	fuente. Con el arbol ya sincronizado (ver
	`docs/runtime-source-diff.md`, resultado PASS) eso basta para que
	runtime vea exactamente el codigo del repositorio.

	NO reemplaza a Rojo. Solo reescribe FUENTES. Si cambia la FORMA del
	arbol (una carpeta nueva, una instancia), hay que ejecutar
	`node tools/sync-workspace.js`.

	Como decide la ruta de cada archivo, sin una tabla manual:
	  - `src/<Servicio>/...`  -> `game.<Servicio>.`
	  - sufijo de Rojo: `.server.lua`, `.client.lua`, `.luau` (no
	    cambia nada) y los demas `.lua` son ModuleScript.
	  - un directorio se traduce en una Folder con el mismo nombre.

	Uso:
	  node tools/sync-scripts.js            # escribe los que difieren
	  node tools/sync-scripts.js --all      # escribe todos
	  node tools/sync-scripts.js --dry      # solo informa
*/

const fs = require("fs");
const os = require("os");
const path = require("path");
const { execFileSync } = require("child_process");

const ROOT = path.join(__dirname, "..");
const SRC = path.join(ROOT, "src");

const DRY = process.argv.includes("--dry");

/**
 * Cliente MCP con UNA sola sesion.
 *
 * Por que existe: `studio-mcp.js` abre sesion, hace `initialize` y
 * `tools/list` en cada invocacion. Con 63 archivos eso son 126 procesos
 * node y 126 handshakes, y el pase tardaba minutos. Roblox Studio tambien
 * va lento: cada `set_script_source` recompila el script.
 *
 * Aqui se hace un unico `initialize` y se reutiliza el `Mcp-Session-Id`
 * para todas las llamadas. Mismo protocolo, misma validacion.
 */
class McpSession {
	constructor(port = process.env.MCP_PORT || "58741") {
		this.url = `http://127.0.0.1:${port}/mcp`;
		this.nextId = 1;
		this.sessionId = null;
		this.schemas = {};
	}

	token() {
		if (process.env.ROBLOX_STUDIO_AUTH_TOKEN) return process.env.ROBLOX_STUDIO_AUTH_TOKEN;
		const p = path.join(os.homedir(), ".robloxstudio-mcp", "auth-token");
		return fs.readFileSync(p, "utf8").trim();
	}

	async #rpc(method, params, notification = false) {
		const headers = {
			"Content-Type": "application/json",
			Accept: "application/json, text/event-stream",
			"X-MCP-Auth": this.token(),
		};
		if (this.sessionId) headers["Mcp-Session-Id"] = this.sessionId;

		const body = { jsonrpc: "2.0", method, params };
		if (!notification) body.id = this.nextId++;

		const res = await fetch(this.url, { method: "POST", headers, body: JSON.stringify(body) });
		const sid = res.headers.get("mcp-session-id");
		if (sid) this.sessionId = sid;

		const text = await res.text();
		if (!res.ok) throw new Error(`HTTP ${res.status}: ${text.slice(0, 300)}`);
		if (text.trim() === "") return null;

		const payloads = [];
		if (text.startsWith("event:") || text.startsWith("data:")) {
			for (const line of text.split(/\r?\n/)) {
				if (line.startsWith("data:")) payloads.push(line.slice(5).trim());
			}
		} else {
			payloads.push(text);
		}

		const messages = [];
		for (const p of payloads) {
			if (!p) continue;
			try {
				messages.push(JSON.parse(p));
			} catch {
				messages.push({ raw: p });
			}
		}
		return messages.find((m) => m.id === body.id) || messages[messages.length - 1] || null;
	}

	async init() {
		await this.#rpc("initialize", {
			protocolVersion: "2025-06-18",
			capabilities: {},
			clientInfo: { name: "keshusytomy-sync", version: "1.0.0" },
		});
		await this.#rpc("notifications/initialized", {}, true);
		const list = await this.#rpc("tools/list", {});
		for (const t of (list.result && list.result.tools) || []) {
			this.schemas[t.name] = (t.inputSchema && t.inputSchema.required) || [];
		}
		return this;
	}

	/** Texto legible de un resultado MCP. */
	#text(result) {
		if (!result) return "";
		if (result.error) return "ERROR MCP: " + JSON.stringify(result.error);
		const r = result.result || result;
		if (r.structuredContent) return JSON.stringify(r.structuredContent);
		if (Array.isArray(r.content)) {
			return r.content.map((c) => (c.type === "text" ? c.text : JSON.stringify(c))).join("\n");
		}
		return JSON.stringify(r);
	}

	async call(name, args = {}) {
		return this.#text(await this.#rpc("tools/call", { name, arguments: args }));
	}

	/**
	 * Igual que `call`, pero devuelve el objeto cuando la respuesta trae
	 * `structuredContent`.
	 *
	 * Hace falta porque `get_script_source` NO devuelve el fuente pelado:
	 * devuelve un objeto con `source` ya antepuesto con el numero de
	 * linea ("1: --!strict\n2: --[[..."), mas `lineCount`, `truncated` y
	 * `note`. Comparar ese texto con el archivo tal cual no coincide
	 * nunca, asi que hay que leer el campo y quitar los prefijos.
	 */
	async callObject(name, args = {}) {
		const text = await this.call(name, args);
		if (typeof text !== "string") return text;
		const start = text.indexOf("{");
		if (start === -1) return { source: text };
		try {
			return JSON.parse(text.slice(start));
		} catch {
			return { source: text };
		}
	}
}

/**
 * Quita el prefijo `N: ` que antepone `get_script_source`.
 *
 * El servidor numera cada linea ("12: \tlocal x = 1"). Sin quitarlo,
 * el texto de Studio jamas coincide con el del disco y la comprobacion
 * de "ya esta al dia" siempre da negativo: los 63 scripts se reescriben
 * en cada pase y Studio recompila todo.
 */
function stripLineNumbers(source) {
	return source.replace(/^\s*\d+:\s?/gm, "");
}

/** Llamada puntual, con sesion propia. Se usa desde `sync-all.js`. */
function mcp(tool, args) {
	const file = path.join(ROOT, ".cache", "mcp-args.json");
	fs.mkdirSync(path.dirname(file), { recursive: true });
	fs.writeFileSync(file, JSON.stringify(args), "utf8");
	const out = execFileSync("node", [path.join(__dirname, "studio-mcp.js"), tool, "--jsonfile", file], {
		cwd: ROOT,
		encoding: "utf8",
		maxBuffer: 128 * 1024 * 1024,
	});
	fs.rmSync(file, { force: true });
	return JSON.parse(out);
}

/** Lista recursivamente archivos bajo un directorio. */
function walk(dir, out = []) {
	for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
		const full = path.join(dir, entry.name);
		if (entry.isDirectory()) walk(full, out);
		else out.push(full);
	}
	return out;
}

/**
 * Texto sin espacios ni saltos de linea.
 *
 * Sirve para comparar el fuente del disco con lo que devuelve MCP:
 * `get_script_source` entrega el texto escapado dentro de un JSON, de
 * modo que un salto de linea real y un `\n` literal son cosas
 * distintas. Normalizar ambos lados elimina esa diferencia sin tener
 * que reconstruir el escapado.
 */
function normalize(text) {
	return text.replace(/\s+/g, "");
}

/**
 * Convierte una ruta de archivo en la ruta del DataModel.
 * `src/ServerScriptService/Services/BombService.lua`
 *   -> `ServerScriptService.Services.BombService`
 */
function instancePathFor(absPath) {
	const rel = path.relative(SRC, absPath).replace(/\\/g, "/");
	const parts = rel.split("/");

	const last = parts[parts.length - 1];
	const stripped = last
		.replace(/\.server\.lua$/, "")
		.replace(/\.client\.lua$/, "")
		.replace(/\.luau$/, "")
		.replace(/\.lua$/, "");

	parts[parts.length - 1] = stripped;
	return parts.join(".");
}

async function main() {
	const files = walk(SRC).filter((f) => /\.(lua|luau)$/.test(f));
	const session = await new McpSession().init();

	let written = 0;
	let same = 0;
	let dry = 0;
	const failed = [];

	for (const file of files) {
		const instancePath = "game." + instancePathFor(file);
		const source = fs.readFileSync(file, "utf8");

		// Comprobacion de "ya esta al dia".
		//
		// Se comparan los textos NORMALIZADOS COMPLETOS, no una huella
		// parcial. La version anterior comparaba solo los primeros 300
		// caracteres normalizados: como la cabecera de cada archivo (el
		// comentario de `--!strict` y el bloque `--[[ ... ]]`) es identica
		// antes y despues de cualquier cambio de logica, ese prefijo
		// SIEMPRE coincidia y el script informaba "ya iguales" sin haber
		// escrito nada. Un cambio en `Start` o en `Init` quedaba invisible
		// y el repositorio y Studio se separaban en silencio.
		//
		// Comparar el texto entero normalizado (sin espacios) hace la
		// comprobacion inmune a las dos representaciones del salto de linea
		// y a los numeros de linea que antepone `get_script_source`.
		let current = "";
		try {
			const res = await session.callObject("get_script_source", { instancePath });
			if (res && typeof res.source === "string" && !res.error) {
				current = stripLineNumbers(res.source);
			}
		} catch {
			current = "";
		}

		if (current && normalize(current) === normalize(source)) {
			same += 1;
			continue;
		}

		if (DRY) {
			dry += 1;
			console.log("DIFERENTE  " + instancePath);
			continue;
		}

		try {
			const res = await session.call("set_script_source", { instancePath, source });
			if (res.startsWith("ERROR MCP:")) throw new Error(res.slice(0, 200));
			written += 1;
			console.log("ESCRITO    " + instancePath);
		} catch (err) {
			failed.push(instancePath + ": " + err.message);
			console.log("FALLO      " + instancePath + " -> " + err.message);
		}
	}

	console.log("");
	console.log(`archivos: ${files.length}`);
	console.log(`escritos: ${written}`);
	if (DRY) console.log(`detectados como diferentes: ${dry}`);
	else console.log(`ya iguales: ${same}`);
	console.log(`fallidos: ${failed.length}`);

	if (failed.length) {
		console.log("RESULTADO: FAIL");
		process.exit(1);
	}
	console.log(DRY ? "RESULTADO: DRY-RUN" : "RESULTADO: PASS");
}

main().catch((err) => {
	console.error("FALLO: " + err.message);
	process.exit(1);
});
