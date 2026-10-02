// verify-geometry.js
// Comprueba que la geometria del mapa esta COLOCADA, no solo presente.
//
// POR QUE EXISTE
// --------------
// `source-runtime-diff` compara el RECUENTO y el NOMBRE de las instancias.
// Las 162 Partes del mapa pueden estar todas apiladas en `(0,0,0)` y ese
// informe seguira diciendo PASS: los nombres coinciden y el numero tambien.
// Eso fue exactamente lo que ocurrio (el lobby entero amontonado en el
// origen mientras la arena conservaba sus coordenadas), y costaron varias
// horas de diagnostico dar con el.
//
// Aqui se mide lo que el recuento no ve: si cada Part esta donde el mapa
// declarado dice que esta. La fuente de verdad es la misma que usa
// `apply-map-positions.js` (que genera el Luau desde `default.project.json`),
// de modo que no hay una segunda lista que mantener.
//
// Uso:
//   node tools/verify-geometry.js

const mcp = require("./mcp");

const VERIFY_LUAU = `
local PATHS
local POSITIONS

local Workspace = game:GetService("Workspace")

local function resolve(dotted)
	local node = Workspace
	for segment in string.gmatch(dotted, "[^%.]+") do
		node = node and node:FindFirstChild(segment)
		if node == nil then
			return nil
		end
	end
	return node
end

local misplaced = {}
local missing = {}
local correct = 0

for index, dotted in ipairs(PATHS) do
	local coords = POSITIONS[index]
	local node = resolve(dotted)

	if node == nil or not node:IsA("BasePart") then
		missing[#missing + 1] = dotted
	else
		local expected = Vector3.new(coords[1], coords[2], coords[3])
		if (node.Position - expected).Magnitude > 1.0 then
			misplaced[#misplaced + 1] = {
				path = dotted,
				got = string.format("%.1f,%.1f,%.1f", node.Position.X, node.Position.Y, node.Position.Z),
				want = string.format("%.0f,%.0f,%.0f", expected.X, expected.Y, expected.Z),
			}
		else
			correct += 1
		end
	end
end

return {
	declared = #PATHS,
	correct = correct,
	misplacedCount = #misplaced,
	missingCount = #missing,
	misplaced = misplaced,
	missing = missing,
}
`;

/**
 * Carga el Luau generado por `apply-map-positions.js` y reutiliza sus dos
 * tablas de datos.
 *
 * Se leen del archivo generado y no se vuelven a derivar de
 * `default.project.json` a proposito: asi la verificacion y la correccion
 * comparten EXACTAMENTE el mismo manifiesto. Si cada una calculara el suyo,
 * un cambio en el generador podria hacer que una midiesse la medida de la
 * otra y el gate dejara de detectar nada.
 *
 * Las tablas ocupan VARIAS lineas (una Part por linea en `POSITIONS`), asi
 * que se extraen balancingando llaves y no con una expresion regular: un
 * `{[^}]*}` cortaria en la primera fila y devolveria una tabla truncada que
 * Luau aceptaria sin error pero con menos Partes de las declaradas.
 *
 * @returns {string|null} Luau listo para ejecutar, o null si falta el manifiesto
 */
function loadManifest() {
	const fs = require("fs");
	const path = require("path");
	const file = path.join(__dirname, "..", ".cache", "apply-positions.lua");

	if (!fs.existsSync(file)) {
		return null;
	}

	const text = fs.readFileSync(file, "utf8");

	/** Extrae el literal de la linea que declara `local <name> = {`. */
	const extract = (name) => {
		const marker = `local ${name} = {`;
		const start = text.indexOf(marker);
		if (start === -1) return null;

		let depth = 0;
		let inString = false;
		let escaped = false;

		for (let i = start + `local ${name} = `.length; i < text.length; i++) {
			const ch = text[i];

			if (inString) {
				if (escaped) escaped = false;
				else if (ch === "\\") escaped = true;
				else if (ch === '"') inString = false;
				continue;
			}

			if (ch === '"') inString = true;
			else if (ch === "{") depth++;
			else if (ch === "}") {
				depth--;
				if (depth === 0) return text.slice(start, i + 1);
			}
		}
		return null;
	};

	const paths = extract("PATHS");
	const positions = extract("POSITIONS");
	if (!paths || !positions) return null;

	return VERIFY_LUAU
		.replace("local PATHS\n", paths + "\n")
		.replace("local POSITIONS\n", positions + "\n");
}

async function main() {
	const code = loadManifest();
	if (!code) {
		console.log("No hay manifiesto de geometria.");
		console.log("Genera uno con: node tools/apply-map-positions.js");
		process.exitCode = 2;
		return;
	}

	const inst = await mcp.toolJson("get_connected_instances", {});
	if (!inst?.instances?.some((i) => i.peers && i.peers.server)) {
		console.log("SIN SERVIDOR EN VIVO: la geometria solo se puede medir en runtime.");
		console.log("Arranca Play con: node tools/play.js start");
		process.exitCode = 2;
		return;
	}

	const res = await mcp.serverLuau(code);
	if (!res || typeof res !== "object") {
		console.log("No se pudo medir: " + JSON.stringify(res));
		process.exitCode = 2;
		return;
	}

	console.log("GEOMETRIA DEL MAPA (posiciones reales)");
	console.log("---------------------------------------------------------------");
	console.log(`Partes declaradas: ${res.declared}`);
	console.log(`En su sitio:       ${res.correct}`);
	console.log(`Descolocadas:      ${res.misplacedCount}`);
	console.log(`Ausentes:          ${res.missingCount}`);

	if (res.misplacedCount) {
		console.log("");
		console.log("DESCOLOCADAS (primeros 15):");
		for (const m of res.misplaced.slice(0, 15)) {
			console.log(`  ${m.path}: en ${m.got}, deberia estar en ${m.want}`);
		}
	}
	if (res.missingCount) {
		console.log("");
		console.log("AUSENTES (primeros 15):");
		for (const m of res.missing.slice(0, 15)) console.log("  " + m);
	}

	console.log("");
	const ok = res.misplacedCount === 0 && res.missingCount === 0;
	console.log(ok ? "GEOMETRIA: PASS" : "GEOMETRIA: FAIL");
	if (!ok) process.exitCode = 1;
}

main().catch((e) => {
	console.error("FALLO: " + e.message);
	process.exitCode = 2;
});
