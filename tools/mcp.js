// mcp.js
// Cliente HTTP del MCP de @chrrxs/robloxstudio-mcp, reutilizable.
//
// Existe para poder pasar argumentos JSON y codigo Luau desde Node sin
// depender de como PowerShell/cmd mutilan las comillas en la linea de
// comandos. La CLI de una sola llamada (`studio-mcp.js`) queda para uso
// manual; este modulo es el que usan las auditorias y los scripts de
// verificacion, que necesitan muchas llamadas en una sola sesion MCP.
//
// Uso:
//   const mcp = require("./mcp");
//   await mcp.init();
//   await mcp.tool("search_objects", { query: "Lobby" });
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

	const res = await fetch(URL, { method: "POST", headers, body: JSON.stringify(body) });

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

/** Texto legible de un resultado MCP (contenido o structuredContent). */
function textOf(result) {
	if (!result) return null;
	if (result.error) return { error: result.error };
	const r = result.result || result;
	if (r.structuredContent) return r.structuredContent;
	if (Array.isArray(r.content)) {
		return r.content.map((c) => (c.type === "text" ? c.text : JSON.stringify(c))).join("\n");
	}
	return r;
}

/**
 * Abre la sesion MCP y carga los esquemas reales de las herramientas.
 * Idempotente: reutiliza la sesion ya abierta en este proceso.
 */
async function init() {
	if (TOOL_SCHEMAS.__loaded) return;
	await rpc("initialize", {
		protocolVersion: "2025-06-18",
		capabilities: {},
		clientInfo: { name: "keshusytomy-audit", version: "1.0.0" },
	});
	await rpc("notifications/initialized", {}, true);

	const listRes = await rpc("tools/list", {});
	const allTools = (listRes.result && listRes.result.tools) || [];
	for (const t of allTools) {
		TOOL_SCHEMAS[t.name] = (t.inputSchema && t.inputSchema.required) || [];
	}
	TOOL_SCHEMAS.__loaded = true;
	TOOL_SCHEMAS.__all = allTools;
}

/** Nombres de todas las herramientas disponibles. */
async function listTools() {
	await init();
	return TOOL_SCHEMAS.__all.map((t) => t.name);
}

/** inputSchema completo de una herramienta. */
async function schema(name) {
	await init();
	const found = TOOL_SCHEMAS.__all.find((t) => t.name === name);
	return found ? found.inputSchema : null;
}

/** Invoca una herramienta MCP y devuelve su contenido ya desempaquetado. */
async function tool(name, args) {
	await init();
	return textOf(await rpc("tools/call", { name, arguments: args || {} }));
}

/**
 * Desenvuelve las dos capas que usa el puente MCP.
 *
 * `eval_server_runtime` / `eval_client_runtime` devuelven un
 * `structuredContent` con `{ok, bridge, result}` donde `result` es el valor
 * de retorno del Luau YA serializado como texto JSON. Las demas
 * herramientas devuelven el objeto directamente. Esta funcion acepta
 * cualquiera de las dos formas y devuelve JSON.parse cuando puede.
 */
async function unwrap(out) {
	let v = out;
	// Capa structuredContent: { ok, bridge, result }.
	if (v && typeof v === "object" && !Array.isArray(v) && typeof v.result === "string") {
		v = v.result;
	}
	if (typeof v !== "string") return v;
	try {
		return JSON.parse(v);
	} catch {
		return v;
	}
}

/** Igual que `tool`, pero desenvuelve y parsea la respuesta. */
async function toolJson(name, args) {
	return unwrap(await tool(name, args));
}

/** Ejecuta Luau en el contexto del servidor y devuelve el valor ya parseado. */
async function serverLuau(code) {
	return unwrap(await tool("eval_server_runtime", { code }));
}

/** Ejecuta Luau en el contexto del cliente y devuelve el valor ya parseado. */
async function clientLuau(code) {
	return unwrap(await tool("eval_client_runtime", { code }));
}

module.exports = { init, rpc, tool, toolJson, serverLuau, clientLuau, listTools, schema, TOOL_SCHEMAS };
