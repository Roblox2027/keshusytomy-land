// apply-map-positions.js
// Genera el Luau que coloca la geometria del mapa en su posicion declarada.
//
// POR QUE EXISTE
// --------------
// `import_rbxm` deja TODAS las Partes en `(0, 0, 0)`, con su tamano correcto.
// Se verifico con un `.rbxm` minimo de UNA sola Part y XML bien formado
// (`tools/build-probe-rbxm.js`): no depende del mapa, del generador ni del
// corte de `<Properties>`. La perdida ocurre dentro de Studio.
//
// Rojo sigue siendo el camino previsto, pero `Plugin > Rojo > Connect` es un
// paso manual que no se puede automatizar. Mientras tanto, el repositorio si
// controla el lado servidor del DataModel: las posiciones se pueden fijar
// DESPUES de importar, leyendo los mismos valores que declara
// `default.project.json`.
//
// La fuente de verdad NO se duplica. Este script lee `default.project.json`,
// que genera `tools/generate-project.js`, y produce el Luau que las aplica. Si
// el generador cambia, se ejecuta `sync-all.js` y las posiciones se vuelven a
// colocar: no hay una segunda lista que mantener.
//
// QUE NO HACE
// -----------
//   - no crea ni destruye instancias, solo mueve las existentes;
//   - no toca Scripts, Remotes ni jugadores;
//   - si una Part no aparece en el mapa, la deja donde este y la cuenta como
//     ausente, en vez de inventarle una posicion.
//
// Uso:
//   node tools/apply-map-positions.js            # escribe el .lua
//   node tools/apply-map-positions.js --run      # escribe y lo ejecuta
//   node tools/apply-map-positions.js --stats    # resumen sin escribir

const fs = require("fs");
const path = require("path");

const mcp = require("./mcp");

const ROOT = path.resolve(__dirname, "..");
const PROJECT = path.join(ROOT, "default.project.json");
const OUT = path.join(ROOT, ".cache", "apply-positions.lua");

// Claves de metadatos de Rojo: no son instancias hijas.
const META_KEYS = new Set(["$className", "$path", "$properties", "$ignoreUnknownInstances", "$hidden"]);

/**
 * Recorre el mapa declarado y devuelve una entrada por Part.
 *
 * Se recorren en ORDEN y sin filtrar por clase: cualquier hoja que declare
 * `Position` recibe una entrada. Asi, si mañana el generador mete un
 * `SpawnLocation` con coordenada propia, queda cubierto sin tocar este
 * script.
 */
function collectEntries(node, prefix, out) {
	for (const key of Object.keys(node)) {
		if (META_KEYS.has(key)) continue;
		const child = node[key];
		if (!child || typeof child !== "object") continue;

		const props = child.$properties || {};
		const here = prefix ? [...prefix, key] : [key];

		if (Array.isArray(props.Position) && props.Position.length === 3) {
			out.push({
				path: here,
				position: props.Position.map((n) => Math.round(n * 1000) / 1000),
			});
		}

		collectEntries(child, here, out);
	}
	return out;
}

function main() {
	const json = JSON.parse(fs.readFileSync(PROJECT, "utf8"));

	const worlds = json.tree.Workspace;
	const entries = [];

	// Solo `Lobby` y `Worlds`: son las dos zonas con geometria de juego.
	// `SpawnLocations` Tambien, porque sus Partes seeves aparecer en el lobby
	// y el generador les da posicion propia.
	for (const root of ["Lobby", "Worlds", "SpawnLocations"]) {
		const node = worlds[root];
		if (!node) continue;
		collectEntries(node, [root], entries);
	}

	if (process.argv.includes("--stats")) {
		console.log(`mapa declarado con posicion: ${entries.length} Partes`);
		const byRoot = {};
		for (const e of entries) {
			byRoot[e.path[0]] = (byRoot[e.path[0]] || 0) + 1;
		}
		for (const [k, v] of Object.entries(byRoot)) {
			console.log(`  ${k}: ${v}`);
		}
		return;
	}

	if (!entries.length) {
		console.error("El mapa no declara ninguna Part con Position. Revisa el generador.");
		process.exit(1);
	}

	// El Luau se genera con los datos embebidos, pero hay que traducir la
	// sintaxis: JSON usa `[...]` para arrays y Luau usa `{...}`.
	//
	// Ademas Luau NO acepta una tabla mixta (un array de objetos con claves no
	// es un literal valido), asi que los datos viajan como DOS arrays
	// paralelos:
	//
	//   PATHS[i]      -> "Lobby.Portals.Portal_Forest.Base"
	//   POSITIONS[i]  -> { x, y, z }
	//
	// Los dos son arrays puros, que Luau si admite como literales.
	const paths = entries.map((e) => e.path.join("."));
	const positions = entries.map((e) => e.position);

	/**
	 * Convierte un array JSON a literal de tabla de Luau.
	 *
	 * Los numeros conservan su representacion JSON (un entero sigue sin
	 * decimales) para que el Luau generado sea legible en el Output. Nada de
	 * esto afecta al valor.
	 *
	 * @param {any[]} list
	 * @returns {string}
	 */
	const toLuauArray = (list) =>
		"{" +
		list
			.map((v) => (Array.isArray(v) ? toLuauArray(v) : JSON.stringify(v)))
			.join(", ") +
		"}";

	const luau = `-- Generado por tools/apply-map-positions.js. NO EDITAR A MANO.
-- Fuente de verdad: default.project.json (tools/generate-project.js).

local PATHS = ${toLuauArray(paths)}
local POSITIONS = ${toLuauArray(positions)}

local Workspace = game:GetService("Workspace")

--- Resuelve una ruta "A.B.C" hasta su instancia.
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

local fixed = 0
local alreadyCorrect = 0
local missing = 0
local examples = {}

for index, dotted in ipairs(PATHS) do
	local coords = POSITIONS[index]
	local node = resolve(dotted)

	if node == nil or not node:IsA("BasePart") then
		missing += 1
	else
		local target = Vector3.new(coords[1], coords[2], coords[3])
		-- Solo se mueve si difiere de verdad: cada Position asignado
		-- replica a todos los clientes, y repetirlo en cada pasada sin
		-- necesidad es trafico puro.
		if (node.Position - target).Magnitude > 0.01 then
			node.Position = target
			fixed += 1
			if #examples < 5 then
				examples[#examples + 1] = dotted
			end
		else
			alreadyCorrect += 1
		end
	end
end

return {
	declared = #PATHS,
	fixed = fixed,
	alreadyCorrect = alreadyCorrect,
	missingFromRuntime = missing,
	examples = examples,
}
`;

	fs.mkdirSync(path.dirname(OUT), { recursive: true });
	fs.writeFileSync(OUT, luau, "utf8");
	console.log(`escrito ${path.relative(ROOT, OUT)} con ${entries.length} Partes declaradas.`);

	if (process.argv.includes("--run")) {
		// Se ejecuta sobre la sesion de EDICION: es la que `import_rbxm` y el
		// resto del pipeline modifican, y el mundo de Play se deriva de ella.
		mcp.tool("execute_luau", { code: luau })
			.then((res) => console.log(JSON.stringify(res, null, 2)))
			.catch((e) => {
				console.error("FALLO al aplicar: " + e.message);
				process.exitCode = 1;
			});
	}
}

main();
