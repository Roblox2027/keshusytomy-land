// studio-mcp.js
// Cliente HTTP minimo para el MCP de @chrrxs/robloxstudio-mcp.
//
// Por que existe: el servidor MCP expone su API por HTTP con
// Streamable HTTP. Para auditar el ARBOL REAL de Roblox Studio (y no solo
// el filesystem) hace falta poder llamar a las herramientas desde scripts.
//
// Uso:
//   node tools/studio-mcp.js <herramienta> <json-de-argumentos>
//   node tools/studio-mcp.js list
//
// El token vive en ~/.robloxstudio-mcp/auth-token y se envia en la
// cabecera X-MCP-Auth. NO se imprime nunca.

const fs = require("fs");
const os = require("os");
const path = require("path");

const PORT = process.env.MCP_PORT || "58741";
const URL = `http://127.0.0.1:${PORT}/mcp`;
const TOKEN_PATH = path.join(os.homedir(), ".robloxstudio-mcp", "auth-token");

let sessionId = null;
let nextId = 1;

/**
 * Campos `required` de cada herramienta, llenados por `initialize`.
 * Se consultan de verdad en vez de fijarlos a mano: si el MCP los renombra,
 * el CLI sigue funcionando sin tocar este archivo.
 */
const TOOL_SCHEMAS = {};

function authToken() {
	if (process.env.ROBLOX_STUDIO_AUTH_TOKEN) return process.env.ROBLOX_STUDIO_AUTH_TOKEN;
	return fs.readFileSync(TOKEN_PATH, "utf8").trim();
}

async function rpc(method, params, notification = false) {
	const headers = {
		"Content-Type": "application/json",
		Accept: "application/json, text/event-stream",
		"X-MCP-Auth": authToken(),
	};
	if (sessionId) headers["Mcp-Session-Id"] = sessionId;

	const body = { jsonrpc: "2.0", method, params };
	if (!notification) body.id = nextId++;

	const res = await fetch(URL, {
		method: "POST",
		headers,
		body: JSON.stringify(body),
	});

	const sid = res.headers.get("mcp-session-id");
	if (sid) sessionId = sid;

	const text = await res.text();
	if (!res.ok) throw new Error(`HTTP ${res.status}: ${text.slice(0, 400)}`);
	if (text.trim() === "") return null;

	// El transporte puede responder en JSON plano o en SSE.
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
		if (p === "") continue;
		try {
			messages.push(JSON.parse(p));
		} catch {
			messages.push({ raw: p });
		}
	}
	return messages.find((m) => m.id === body.id) || messages[messages.length - 1] || null;
}

/**
 * Coloca un valor literal en el primer campo que la herramienta exige.
 *
 * Sin esto, `node tools/studio-mcp.js search_objects Workspace` tendria que
 * saber de memoria que el campo se llama `query`. Se consulta el esquema
 * real de la herramienta y se usa el primer `required`.
 */
function guessArgs(toolName, value) {
	const schema = TOOL_SCHEMAS[toolName];
	if (!schema || !schema.length) return { query: value };
	return { [schema[0]]: value };
}

/** Texto legible de un resultado MCP (contenido o structuredContent). */
function textOf(result) {
	if (!result) return "(sin respuesta)";
	if (result.error) return "ERROR MCP: " + JSON.stringify(result.error);
	const r = result.result || result;
	if (r.structuredContent) return JSON.stringify(r.structuredContent, null, 2);
	if (Array.isArray(r.content)) {
		return r.content.map((c) => (c.type === "text" ? c.text : JSON.stringify(c))).join("\n");
	}
	return JSON.stringify(r, null, 2);
}

async function callTool(name, args) {
	return textOf(await rpc("tools/call", { name, arguments: args || {} }));
}

async function main() {
	const [tool, rawArg] = process.argv.slice(2);

	// El codigo Luau se puede pasar en un archivo con `--file <ruta>`.
	// Es la via fiable: PowerShell y cmd mutilan las comillas dobles del
	// codigo antes de que node las vea.
	//
	// `--jsonfile <ruta>` hace lo mismo para los argumentos JSON de las
	// herramientas. Passing JSON por la linea de comandos es imposible de
	// forma fiable desde PowerShell: las comillas dobles sobreviven como
	// `\"` y `JSON.parse` falla en la posicion 1. Leer el objeto desde un
	// archivo elimina de raiz esa clase de fallo.
	let arg = rawArg;
	let jsonFile = null;
	let codeFile = null;
	if (arg === "--file") {
		// `process.argv[2]` es la herramienta y `[3]` el flag `--file`.
		arg = fs.readFileSync(process.argv[4], "utf8");
	} else if (arg === "--jsonfile") {
		jsonFile = process.argv[4];
	} else if (arg === "--codefile") {
		// Igual que `--file`, pero coloca el contenido en el PRIMER
		// campo `required` de la herramienta. Lo necesitan las
		// herramientas de runtime (`eval_server_runtime`,
		// `eval_client_runtime`), cuyo parametro se llama `code` y no
		// `query`: pasarles un `--file` a pelo las llenaria con `{}`.
		codeFile = process.argv[4];
	}

	await rpc("initialize", {
		protocolVersion: "2025-06-18",
		capabilities: {},
		clientInfo: { name: "keshusytomy-audit", version: "1.0.0" },
	});
	await rpc("notifications/initialized", {}, true);

	// El esquema se carga SIEMPRE: `guessArgs` lo necesita para colocar un
	// valor literal en el campo correcto de la herramienta.
	const listRes = await rpc("tools/list", {});
	const allTools = (listRes.result && listRes.result.tools) || [];
	for (const t of allTools) {
		TOOL_SCHEMAS[t.name] = (t.inputSchema && t.inputSchema.required) || [];
	}

	if (!tool || tool === "list") {
		console.log("HERRAMIENTAS MCP (" + allTools.length + "):");
		for (const t of allTools) {
			const req = (t.inputSchema && t.inputSchema.required) || [];
			console.log(`  ${t.name}(${req.join(", ")})`);
		}
		return;
	}

	// `--schema <herramienta>` imprime el inputSchema completo.
	//
	// Por que existe: varias herramientas (import_rbxm, manage_instance,
	// set_properties...) reciben objetos anidados y el mensaje de error
	// del servidor solo dice "must be object", sin decir que forma
	// espera. Adivinar por ensayo y error desde PowerShell es lento y
	// fragile; volcar el esquema real lo responde de una vez.
	if (tool === "--schema") {
		const name = rawArg;
		const found = allTools.find((t) => t.name === name);
		if (!found) {
			console.error("Herramienta desconocida: " + name);
			process.exit(1);
		}
		console.log(JSON.stringify(found.inputSchema, null, 2));
		return;
	}

	// Un argumento que empieza por `{` se trata como literal, NO como JSON.
	// Luau usa `{ ... }` para tablas y el codigo de auditoria empieza
	// siempre por ahi, asi que interpretarlo como JSON rompe la llamada.
	// El JSON explicito se indica con el prefijo `--json `.
	let args;
	if (jsonFile) {
		args = JSON.parse(fs.readFileSync(jsonFile, "utf8"));
	} else if (codeFile) {
		const field = TOOL_SCHEMAS[tool] && TOOL_SCHEMAS[tool][0];
		if (!field) throw new Error(`la herramienta ${tool} no declara ningun campo requerido`);
		args = { [field]: fs.readFileSync(codeFile, "utf8") };
	} else if (arg === undefined) {
		args = {};
	} else if (arg.startsWith("--json ")) {
		args = JSON.parse(arg.slice("--json ".length));
	} else {
		args = guessArgs(tool, arg);
	}
	console.log(await callTool(tool, args));
}

main().catch((e) => {
	console.error("FALLO: " + e.message);
	process.exit(1);
});
