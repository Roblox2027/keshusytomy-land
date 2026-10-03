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
 * Lee la firma del fuente REAL de un script dentro de Studio.
 *
 * POR QUE NO SE USA `get_script_source`
 * -------------------------------------
 * Esa herramienta esta capada a 300 lineas y antepone numeros de linea, asi
 * que no permite afirmar nada sobre el final del archivo, que es justo donde
 * vive el `return` que decide que modulo se carga. Con ella, `EconomyRules`
 * (787 lineas) daba FALLO aunque estuviera escrito y fuera IDENTICO, porque
 * la comprobacion era de prefijo y el final se escapaba sin verificar.
 *
 * Aqui se lee `Script.Source`, que no tiene ese limite, y se devuelve solo
 * la longitud y el hash: traer 26 KB por la red en cada comparacion no
 * hace falta para saber si el archivo es el del disco.
 *
 * TRAMPA DEL SANDBOX: el codigo se compila en un entorno que NO acepta
 * operadores de bits (`~`, `&`) ni `table.concat` sobre una tabla de numeros.
 * Por eso el hash es aritmetico puro y se hace en una sola pasada. Cuando
 * la sonda no compila se AVISA en vez de devolver `null` en silencio: si no,
 * un error de compilacion se camuflaba como "el script no existe" y hacia
 * falta un falso positivo mucho mas dificil de ver.
 *
 * @param {object} session Sesion MCP viva.
 * @param {string} instancePath Ruta en el DataModel.
 * @returns {Promise<{chars: number, hash: string}|null>}
 */
async function readSourceSignature(session, instancePath) {
	const code = [
		`local inst = ${instancePath}`,
		`if not inst then return "AUSENTE" end`,
		`if not inst:IsA("LuaSourceContainer") then return "NOESFUENTE" end`,
		`local s = inst.Source`,
		// Studio no normaliza los saltos de linea de forma uniforme: unos
		// scripts quedan con CRLF y otros con LF segun como se escribieron.
		// Sin quitar los CR la comparacion fallaba por el retorno de carro y
		// no por el codigo.
		`local h = 5381`,
		`local P = 1000000007`,
		`local n = 0`,
		`for i = 1, #s do`,
		`	local b = s:byte(i)`,
		`	if b ~= 13 then`,
		`		n = n + 1`,
		`		h = (h * 33 + b) % P`,
		`	end`,
		`end`,
		`return tostring(n) .. ":" .. tostring(h)`,
	].join("\n");

	try {
		const obj = await session.callObject("execute_luau", { code });
		if (obj && obj.success === false) {
			warnOnce("la sonda de fuente no compila: " + (obj.error || "?"));
			return null;
		}
		const value = obj && typeof obj.returnValue === "string" ? obj.returnValue : null;
		if (!value) {
			warnOnce("la sonda de fuente no devolvio valor");
			return null;
		}
		const sep = value.indexOf(":");
		if (sep === -1) {
			warnOnce("la sonda de fuente devolvio un formato raro: " + value);
			return null;
		}
		return { chars: Number(value.slice(0, sep)), hash: value.slice(sep + 1) };
	} catch (err) {
		warnOnce("la sonda de fuente lanzo: " + err.message);
		return null;
	}
}

/** Informa un problema de la sonda una sola vez, para no inundar la salida. */
function warnOnce(message) {
	if (warnOnce.done) return;
	warnOnce.done = true;
	console.log("AVISO: " + message);
}

/**
 * Firma del fuente tal como se mide dentro de Studio: BYTES UTF-8, sin CR.
 *
 * Studio cuenta bytes (`#s`, `s:byte`), no caracteres, asi que en JS hay que
 * trabajar sobre los bytes UTF-8 y no sobre el string: con acentos o un BOM
 * (3 bytes) las dos cuentas difieren y el gate reportaba una divergencia que
 * no existia. Los CR se quitan por el mismo motivo que en la sonda.
 *
 * @param {string} text Texto del disco.
 * @returns {{chars: number, hash: string}}
 */
function diskSignature(text) {
	const bytes = Buffer.from(text.replace(/\r\n?/g, "\n"), "utf8");

	// djb2 con un primo: el mismo algoritmo que corre dentro de Studio.
	const P = 1000000007;
	let h = 5381;
	for (let i = 0; i < bytes.length; i += 1) {
		h = (h * 33 + bytes[i]) % P;
	}

	return { chars: bytes.length, hash: String(h) };
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
		// El fuente se lee TAL CUAL, sin recortar.
		//
		// MEDIDO: Studio NO normaliza el texto al guardarlo. Un archivo del
		// disco que acaba en "\n" se queda con ese "\n" en Studio, y uno que
		// no lo tiene se queda sin el. Por eso el archivo se compara contra
		// si mismo y no contra una forma " canonica": si aqui se hiciera
		// `.trim()`, el hash de un archivo con salto final jamas podria
		// coincidir con el de Studio, y el sincronizador declararia
		// divergente un archivo byte a byte identico.
		const source = fs.readFileSync(file, "utf8");

		// Comprobacion de "ya esta al dia", por hash del fuente completo.
		//
		// ANTES (1): una huella de 300 CARACTERES. La cabecera de cada archivo
		// (`--!strict` y el bloque `--[[ ... ]]`) es identica antes y despues
		// de cualquier cambio de logica, asi que el prefijo SIEMPRE coincidia y
		// el script informaba "ya iguales" sin escribir nada. Seis divergencias
		// reales siguieron invisibles durante varias pasadas.
		//
		// ANTES (2): `get_script_source`, que esta capada a 300 lineas. Todo
		// archivo mayor se declaraba divergido y se reescribia en cada pase,
		// recalculando Studio entero sin motivo, y aun asi el final del
		// archivo se quedaba sin verificar.
		//
		// AHORA: hash del texto completo leido DENTRO de Studio. Exacto en los
		// dos sentidos: no se pierde ninguna divergencia y no se reescribe lo
		// que ya esta bien.
		const live = await readSourceSignature(session, instancePath);
		const disk = diskSignature(source);

		if (live && live.chars === disk.chars && live.hash === disk.hash) {
			same += 1;
			continue;
		}

		if (DRY) {
			dry += 1;
			console.log("DIFERENTE  " + instancePath + (live ? "" : "  [no existe en Studio]"));
			continue;
		}

		try {
			const res = await session.call("set_script_source", { instancePath, source });
			if (res.startsWith("ERROR MCP:")) throw new Error(res.slice(0, 200));

			// COMPROBACION DE INTEGRIDAD POST-ESCRITURA.
			//
			// Se comprueba el hash del fuente REAL contra el del disco. Con
			// `get_script_source` esto no era posible de conclusion: la
			// herramienta esta capada a 300 lineas, asi que la comparacion era
			// de prefijo y el final del archivo (donde vive el `return`) se
			// escapaba sin verificar. Por eso `EconomyRules` daba FALLO
			// estando escrito y siendo identico.
			//
			// Comparar el hash entero sube el liston en vez de bajarlo: ahora
			// el gate afirma, con fundamento, que lo que corre en Studio es el
			// archivo del repositorio.
			const check = await readSourceSignature(session, instancePath);
			if (!check) {
				throw new Error("no se pudo leer el fuente real en Studio para verificar la escritura");
			}
			if (check.chars !== disk.chars || check.hash !== disk.hash) {
				throw new Error(
					`el fuente en Studio no es el del disco (Studio ${check.chars} bytes / ${check.hash}, ` +
						`disco ${disk.chars} bytes / ${disk.hash})`,
				);
			}

			written += 1;
			console.log("ESCRITO    " + instancePath + "  [" + disk.chars + " bytes verificados]");
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

	// Cada escritura se verifico por hash contra el fuente real de Studio, y
	// cada "ya igual" tambien. No queda nada sin comprobar, asi que ya no hace
	// falta el aviso de "verificacion parcial" que se emitia antes, cuando la
	// lectura truncada dejaba el final de cada archivo grande sin verificar.

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
