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
local SIZES
local ROTATIONS

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
local wrongSize = {}
local wrongRotation = {}
local correct = 0

-- Se mide ademas la VARIEDAD. Es la comprobacion que distingue un bosque de
-- una rejilla de cubos identicos: si aqui aparecieran cuatro o cinco
-- tamanos, la arena habria llegado bien pero seguiria siendo un prototipo.
--
-- Sin esta medicion, este script solo diria "todo esta colocado" y no
-- dira nada de si el mapa ha cambiado de forma, que es justo lo que se
-- cambio a proposito.
local sizeSet = {}
local rotatedCount = 0

for index, dotted in ipairs(PATHS) do
	local coords = POSITIONS[index]
	local dims = SIZES[index]
	local rot = ROTATIONS[index]
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

		-- TAMANO. La rotacion no altera Size, asi que se compara directo.
		-- Importa porque la reconstruccion cambio las dimensiones de los
		-- bloques: si el tamano no llegara, la silueta seria la de antes.
		--
		-- EXCEPCION: una Part con Shape = Ball o Cylinder tiene el
		-- tamano atado. Roblox fuerza que las tres componentes coincidan y
		-- ajusta el valor a la altura que le da el motor, asi que exigir
		-- exactitud marcaria como error una pieza que esta bien.
		--
		-- Eso pasaba con CoreOrb: se declara 8x8x8 y Roblox lo entrega en
		-- 8.6x8.6x8.6. La diferencia no es un defecto del mapa, es la
		-- esfera recalculandose. Se acepta una tolerancia del 12 % solo
		-- para esas formas, y se sigue exigiendo exactitud en las cajas.
		if dims then
			local expectedSize = Vector3.new(dims[1], dims[2], dims[3])
			local isRounded = node:IsA("Part")
				and (node.Shape == Enum.PartType.Ball or node.Shape == Enum.PartType.Cylinder)
			local tolerance = isRounded and (expectedSize.Magnitude * 0.12) or 0.05

			if (node.Size - expectedSize).Magnitude > tolerance then
				wrongSize[#wrongSize + 1] = {
					path = dotted,
					got = string.format("%.1fx%.1fx%.1f", node.Size.X, node.Size.Y, node.Size.Z),
					want = string.format("%.0fx%.0fx%.0f", expectedSize.X, expectedSize.Y, expectedSize.Z),
				}
			end
			sizeSet[string.format("%.1fx%.1fx%.1f", node.Size.X, node.Size.Y, node.Size.Z)] = true
		end

		-- ORIENTACION.
		--
		-- Se comparan los ejes del CFrame, que es lo que dice si la pieza
		-- esta erguida o inclinada. La inclinacion es lo que rompe la lectura
		-- de "cajas alineadas en una rejilla".
		--
		-- El yaw se NORMALIZA: Roblox lo expresa en (-180, 180], asi que un
		-- giro declarado de 220 grados se mide como -140. Son el mismo giro.
		-- Compararlos en crudo daba 360 grados de diferencia y marcaba como
		-- incorrectas 32 piezas que estaban bien.
		--
		-- Las piezas inclinadas se cuentan por su rotacion REAL (el eje Y del
		-- mundo deja de ser 1), no comparando la orientacion declarada contra
		-- si misma, que era lo que hacia antes y por eso contaba cero.
		if rot then
			local function angleGap(a, b)
				local raw = math.abs(a - b) % 360
				if raw > 180 then
					raw = 360 - raw
				end
				return raw
			end

			local current = node.Orientation
			local upY = node.CFrame:VectorToWorldSpace(Vector3.new(0, 1, 0)).Y

			local gap = angleGap(current.X, rot[1])
				+ angleGap(current.Y, rot[2])
				+ angleGap(current.Z, rot[3])
			if gap > 1.5 then
				wrongRotation[#wrongRotation + 1] = {
					path = dotted,
					got = string.format("%.0f,%.0f,%.0f", current.X, current.Y, current.Z),
					want = string.format("%.0f,%.0f,%.0f", rot[1], rot[2], rot[3]),
				}
			end
			if upY <= 0.999 then
				rotatedCount += 1
			end
		end
	end
end

local sizeCount = 0
for _ in pairs(sizeSet) do
	sizeCount += 1
end

return {
	declared = #PATHS,
	correct = correct,
	misplacedCount = #misplaced,
	missingCount = #missing,
	wrongSizeCount = #wrongSize,
	wrongRotationCount = #wrongRotation,
	distinctSizes = sizeCount,
	rotatedParts = rotatedCount,
	misplaced = misplaced,
	missing = missing,
	wrongSize = wrongSize,
	wrongRotation = wrongRotation,
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
	const sizes = extract("SIZES");
	const rotations = extract("ROTATIONS");
	if (!paths || !positions || !sizes || !rotations) return null;

	return VERIFY_LUAU
		.replace("local PATHS\n", paths + "\n")
		.replace("local POSITIONS\n", positions + "\n")
		.replace("local SIZES\n", sizes + "\n")
		.replace("local ROTATIONS\n", rotations + "\n");
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
	console.log(`Tamano incorrecto: ${res.wrongSizeCount}`);
	console.log(`Orientacion mal:   ${res.wrongRotationCount}`);
	console.log("");
	console.log(`Tamanos distintos: ${res.distinctSizes}`);
	console.log(`Piezas inclinadas: ${res.rotatedParts}`);

	if (res.wrongSizeCount) {
		console.log("");
		console.log("TAMANO INCORRECTO (primeros 10):");
		for (const m of res.wrongSize.slice(0, 10)) {
			console.log(`  ${m.path}: mide ${m.got}, deberia medir ${m.want}`);
		}
	}
	if (res.wrongRotationCount) {
		console.log("");
		console.log("ORIENTACION INCORRECTA (primeros 10):");
		for (const m of res.wrongRotation.slice(0, 10)) {
			console.log(`  ${m.path}: eje X en ${m.got} grados, deberia estar en ${m.want}`);
		}
	}

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
	const ok =
		res.misplacedCount === 0 &&
		res.missingCount === 0 &&
		res.wrongSizeCount === 0 &&
		res.wrongRotationCount === 0;

	// La variedad no es un PASS/FAIL: es una MEDIDA. Se imprime siempre,
	// incluso cuando todo esta correctamente colocado, porque es lo que
	// responde a la pregunta de si el mapa sigue siendo un prototipo.
	// Un "todo en su sitio" con cuatro tamanos significaria que la
	// sincronizacion funciona pero que el bosque no existe.
	console.log("VARIEDAD (medida, no veredicto):");
	console.log(`  tamanos distintos: ${res.distinctSizes}`);
	console.log(`  piezas inclinadas: ${res.rotatedParts}`);
	if (res.distinctSizes < 20) {
		console.log("  AVISO: muy pocos tamanos distintos; el mapa puede seguir siendo una rejilla.");
	}
	if (res.rotatedParts < 10) {
		console.log("  AVISO: casi nada inclinado; el mapa puede seguir alineado a la rejilla.");
	}

	console.log("");
	console.log(ok ? "GEOMETRIA: PASS" : "GEOMETRIA: FAIL");
	if (!ok) process.exitCode = 1;
}

main().catch((e) => {
	console.error("FALLO: " + e.message);
	process.exitCode = 2;
});
