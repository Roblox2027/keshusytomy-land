// screenshot.js
// Captura REAL del cliente en marcha y la guarda como imagen en disco.
//
// Por que existe: `capture_screenshot` del MCP de Studio devuelve la imagen
// en un bloque `content` de tipo `image` (base64). El cliente de linea de
// comandos `studio-mcp.js` solo imprimia texto, asi que la evidencia visual
// se perdia y la certificacion VISUAL quedaba BLOCKED sin llevar a ningun
// sitio. Este script habla el mismo protocolo MCP, conserva el binario y
// escribe un `.png` que se puede abrir y mirar de verdad.
//
// Uso:
//   node tools/screenshot.js <salida.png> [--format png|jpeg] [--quality 90]
//
// Si Studio responde que no puede capturar ese DataModel, lo dice y sale con
// codigo 2: NO inventa una imagen.

const fs = require("fs");
const os = require("os");
const path = require("path");

const PORT = process.env.MCP_PORT || "58741";
const URL = `http://127.0.0.1:${PORT}/mcp`;
const TOKEN_PATH = path.join(os.homedir(), ".robloxstudio-mcp", "auth-token");

let sessionId = null;
let nextId = 1;

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
	if (!res.ok) throw new Error(`HTTP ${res.status}: ${text.slice(0, 300)}`);
	if (!text.trim()) return null;

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

function argValue(flag, fallback) {
	const i = process.argv.indexOf(flag);
	if (i === -1) return fallback;
	return process.argv[i + 1];
}

async function main() {
	const out = process.argv[2] || ".ai/runtime/shot.png";
	const format = argValue("--format", "png");
	const quality = Number(argValue("--quality", "92"));
	fs.mkdirSync(path.dirname(out), { recursive: true });

	await rpc("initialize", {
		protocolVersion: "2025-06-18",
		capabilities: {},
		clientInfo: { name: "keshusytomy-screenshot", version: "1.0.0" },
	});
	await rpc("notifications/initialized", {}, true);

	const res = await rpc("tools/call", {
		name: "capture_screenshot",
		arguments: { format, quality },
	});
	const r = (res && (res.result || res)) || {};
	if (r.error) throw new Error("error MCP: " + JSON.stringify(r.error));

	const content = Array.isArray(r.content) ? r.content : [];
	const img = content.find((c) => c.type === "image");
	const meta = r.structuredContent || {};

	if (!img || !img.data) {
		console.log("SIN IMAGEN. Studio respondio:");
		console.log(JSON.stringify(meta, null, 2));
		console.log(content.map((c) => (c.type === "text" ? c.text : `[${c.type}]`)).join("\n"));
		process.exit(2);
	}

	fs.writeFileSync(out, Buffer.from(img.data, "base64"));
	console.log("escrito " + out);
	console.log(JSON.stringify(meta, null, 2));
}

main().catch((e) => {
	console.error("FALLO: " + e.message);
	process.exit(1);
});