"use strict";

// p0-logs.js
// Filtra los logs de la sesion de Play por un patron, para no perderlos en el
// ruido de miles de lineas del nucleo y del cliente.
//
// Uso:
//   node tools/p0-logs.js InputController
//   node tools/p0-logs.js BOMB

const mcp = require("./mcp");

async function main() {
	const pattern = new RegExp(process.argv[2] || "BOMB", "i");
	const max = Number(process.argv[3] || 2000);

	await mcp.init();
	const raw = await mcp.tool("get_runtime_logs", { maxLines: max });
	const text = typeof raw === "string" ? raw : JSON.stringify(raw);

	// Los logs llegan como entradas con `message`. Sesac el texto de cada una
	// para poder aplicar el filtro, en vez de buscar sobre el JSON entero.
	let messages = [];
	try {
		const parsed = JSON.parse(text);
		messages = (parsed.entries || []).map((e) => `[${e.level}] ${e.message}`);
	} catch {
		messages = text.split("\\n");
	}

	const hits = messages.filter((m) => pattern.test(m));

	console.log(`lineas totales: ${messages.length} | coincidencias: ${hits.length}`);
	console.log(hits.slice(-120).join("\n") || "(sin coincidencias)");
}

main().catch((e) => {
	console.error("FALLO: " + e.message);
	process.exit(1);
});