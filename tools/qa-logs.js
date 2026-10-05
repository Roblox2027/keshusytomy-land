// qa-logs.js
// Vuelca los logs de PLAY filtrando por una subcadena.
//
// Por que existe: `qa-bomb-timer`證证 que la mecha baja a 0.00, el registro
// desaparece a los 3 s (o sea que `detonateBomb` corre) y el contador de
// explosiones NO se mueve. El sintoma esta medido, la causa no. Los logs del
// servidor son donde vive la respuesta, y leerlos a mano por la consola de
// Studio no es reproducible.
//
// Uso:
//   node tools/qa-logs.js BOMB
//   node tools/qa-logs.js                    (sin filtro)
const mcp = require("./mcp");

async function main() {
	const needle = process.argv[2] || "";
	await mcp.init();

	const raw = await mcp.tool("get_runtime_logs", {
		maxLines: 300,
		...(needle ? { filter: needle } : {}),
	});

	const text = typeof raw === "string" ? raw : JSON.stringify(raw, null, 2);
	const lines = text.split(/\r?\n/);

	if (!needle) {
		console.log(lines.slice(-80).join("\n"));
		return;
	}

	const hits = lines.filter((line) => line.toLowerCase().includes(needle.toLowerCase()));

	if (hits.length === 0) {
		console.log(`sin lineas que contengan "${needle}" en las ultimas ${lines.length}`);
		return;
	}

	console.log(`${hits.length} linea(s) con "${needle}":`);
	console.log(hits.slice(-60).join("\n"));
}

main().catch((err) => {
	console.error("FALLO: " + err.message);
	process.exit(1);
});