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
 * Paths cuya APARIENCIA es propiedad del runtime, no de la fuente.
 *
 * `VisualService.DecoratePortals` (VisualService.lua:442) repinta el panel de
 * los mundos deshabilitados a gris 70/74/86, sin luz y sin chispas. Ese gris
 * es la senal de juego de "aqui no se entra": depende de `FeatureConfig` en
 * cada arranque, asi que no puede venir de la fuente.
 *
 * Si este script tambien lo pintara, los dos se pelearian: el panel
 * apareceria con el color del mundo y `portal-source-audit` daria FAIL sobre
 * un runtime correcto. Medido en las dos direcciones.
 *
 * La GEOMETRIA de esas piezas (posicion, tamano, orientacion) si se sigue
 * aplicando: de eso si responde la fuente.
 */
const RUNTIME_OWNED_APPEARANCE = new Set([
	"Lobby.Portals.Portal_Desert.PortalPanel",
	"Lobby.Portals.Portal_Ice.PortalPanel",
	"Lobby.Portals.Portal_Volcano.PortalPanel",
	"Lobby.Portals.Portal_Cyber.PortalPanel",
]);

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
				// El tamano se declara junto a la posicion. Se necesita para
				// que `verify-geometry.js` pueda comprobar que la silueta
				// tambien llega intacta, no solo donde esta la pieza.
				size: Array.isArray(props.Size) && props.Size.length === 3
					? props.Size.map((n) => Math.round(n * 1000) / 1000)
					: null,
				// La orientacion en grados, como la escribe Rojo. Va en el
				// manifiesto para poder verificar que las piezas inclinadas
				// siguen inclinadas y no llegan tumbadas a la rejilla.
				orientation: Array.isArray(props.Orientation) && props.Orientation.length === 3
					? props.Orientation.map((n) => Math.round(n * 1000) / 1000)
					: null,

				// ------------------------------------------------ APARIENCIA
				//
				// Color, Material, Transparency, CanCollide y CanTouch tambien
				// viajan aqui, y existen por un defecto MEDIDO.
				//
				// `import_rbxm` no actualiza las propiedades de una instancia
				// que ya existe (ver `tools/import-update-probe.js`), asi que
				// cambiar un color en el generador NO llegaba a Studio: la
				// pieza conservaba la que tenia. El sintoma era desconcertante
				// porque el recuento de instancias daba PASS y los nombres
				// coincidian: cuatro de los cinco portales llegaban con el
				// panel en gris (70/74/86) en vez del color de su mundo,
				// porque ese gris era el color que tenian antes.
				//
				// El fallo solo se ve comparando el color pieza a pieza, que
				// es lo que hace `tools/portal-source-audit.js`.
				color: Array.isArray(props.Color) && props.Color.length === 3
					? props.Color.map((n) => Math.round(n * 10000) / 10000)
					: null,
				material: typeof props.Material === "string" ? props.Material : null,
				transparency: typeof props.Transparency === "number" ? props.Transparency : null,
				canCollide: typeof props.CanCollide === "boolean" ? props.CanCollide : null,
				canTouch: typeof props.CanTouch === "boolean" ? props.CanTouch : null,
				shape: typeof props.Shape === "string" ? props.Shape : null,

				// Marca de propiedad del runtime. Se calcula aqui porque es
				// el unico punto donde existe el path completo.
				runtimeOwns: RUNTIME_OWNED_APPEARANCE.has(here.join(".")),
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
	const sizes = entries.map((e) => e.size);
	const rotations = entries.map((e) => e.orientation);

	// Apariencia. Viaja en arrays paralelos como la geometria, y por el mismo
	// motivo: una tabla mixta de objetos no es un literal valido en Luau.
	// Los booleanos viajan como 1/0 porque `true` es una palabra clave, no un
	// literal de dato.
	// Las piezas cuya apariencia manda el runtime se marcan con `runtimeOwns`:
	// el Luau recibe `nil` y por tanto las omite. La geometria sigue
	// saliendo entera, que es lo que si responde a la fuente.
	const colors = entries.map((e) => (e.runtimeOwns ? null : e.color));
	const materials = entries.map((e) => (e.runtimeOwns ? null : e.material));
	const transparencies = entries.map((e) => (e.runtimeOwns ? null : e.transparency));
	const canCollides = entries.map((e) => (e.canCollide === null ? null : e.canCollide ? 1 : 0));
	const canTouches = entries.map((e) => (e.canTouch === null ? null : e.canTouch ? 1 : 0));
	const shapes = entries.map((e) => e.shape);

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
			// `null` se convierte en `nil`. Sin esta rama, `JSON.stringify`
			// devuelve la cadena "null" y Luau recibe un valor que no existe:
			// una pieza sin `Size` declarada compararia contra el texto
			// "null" en vez de saltarse la comprobacion.
			.map((v) => (Array.isArray(v) ? toLuauArray(v) : v === null ? "nil" : JSON.stringify(v)))
			.join(", ") +
		"}";

	const luau = `-- Generado por tools/apply-map-positions.js. NO EDITAR A MANO.
-- Fuente de verdad: default.project.json (tools/generate-project.js).

local PATHS = ${toLuauArray(paths)}
local POSITIONS = ${toLuauArray(positions)}
local SIZES = ${toLuauArray(sizes)}
local ROTATIONS = ${toLuauArray(rotations)}
local COLORS = ${toLuauArray(colors)}
local MATERIALS = ${toLuauArray(materials)}
local TRANSPARENCIES = ${toLuauArray(transparencies)}
local CAN_COLLIDES = ${toLuauArray(canCollides)}
local CAN_TOUCHES = ${toLuauArray(canTouches)}
local SHAPES = ${toLuauArray(shapes)}

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

-- TAMANO Y ORIENTACION.
--
-- POR QUE ESTA EN SU PROPIO SCRIPT Y NO DENTRO DE LA IMPORTACION
-- -----------------------------------------------------------
-- import_rbxm NO actualiza las propiedades de una instancia que ya
-- existe con el mismo nombre (medido en tools/import-update-probe.js):
-- se limita a anadir los hijos que faltan. Ademas, aunque la instancia
-- sea nueva, la importacion deja Position en (0,0,0).
--
-- Consecuencia: la geometria del mapa solo llega integra si el mapa se
-- PURGA antes de importar, y si despues se vuelven a colocar las
-- propiedades a mano. Por eso esta colocacion existe, y por eso
-- tools/remap.js purga siempre en lugar de fiarse de la salud del mapa.
--
-- El TAMANO se coloca aqui ademas porque import_rbxm tampoco lo aplica
-- de forma fiable: los bloques llegaban con 8x8x8 del mapa viejo.

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

local fixedPosition = 0
local fixedSize = 0
local fixedRotation = 0
local fixedColor = 0
local fixedMaterial = 0
local fixedTransparency = 0
local fixedCollision = 0
local alreadyCorrect = 0
local missing = 0
local examples = {}

for index, dotted in ipairs(PATHS) do
	local coords = POSITIONS[index]
	local dims = SIZES[index]
	local rot = ROTATIONS[index]
	local rgb = COLORS[index]
	local material = MATERIALS[index]
	local transparency = TRANSPARENCIES[index]
	local canCollide = CAN_COLLIDES[index]
	local canTouch = CAN_TOUCHES[index]
	local node = resolve(dotted)

	if node == nil or not node:IsA("BasePart") then
		missing += 1
	else
		local touched = false

		-- 1. Posicion.
		local target = Vector3.new(coords[1], coords[2], coords[3])
		-- Solo se mueve si difiere de verdad: cada Position asignado
		-- replica a todos los clientes, y repetirlo en cada pasada sin
		-- necesidad es trafico puro.
		if (node.Position - target).Magnitude > 0.01 then
			node.Position = target
			fixedPosition += 1
			touched = true
		end

		-- 2. Tamano.
		--
		-- Size solo puede cambiar en un BasePart ANCLADO, y se asigna
		-- DESPUES que la rotacion: si se asigna antes, Studio puede
		-- reajustar el CFrame y el resultado no es el declarado.
		if dims then
			local targetSize = Vector3.new(dims[1], dims[2], dims[3])
			if (node.Size - targetSize).Magnitude > 0.01 then
				node.Size = targetSize
				fixedSize += 1
				touched = true
			end
		end

		-- 3. Orientacion, en grados.
		--
		-- Se escribe Orientation, no el CFrame: es la propiedad que el
		-- generador declara, y escribir el CFrame exigiria recomponer los
		-- doce componentes a mano para conservar el resto de la rotacion.
		--
		-- OJO CON EL GIRO Y: Roblox lo NORMALIZA al rango (-180, 180]. Un
		-- yaw declarado de 220 grados llega como -140. No es un error: son
		-- el mismo giro, y el producto vectorial de los ejes da lo mismo.
		-- Por eso la comparacion de verify-geometry.js tiene que tratar
		-- esos dos valores como iguales, y no como una discrepancia.
		if rot then
			local function angleGap(a, b)
				-- Diferencia minima entre dos angulos, en grados. El giro
				-- de 220 y el de -140 se separan 360, asi que su diferencia
				-- cruda es 360 y la real es 0.
				local raw = math.abs(a - b) % 360
				if raw > 180 then
					raw = 360 - raw
				end
				return raw
			end

			local current = node.Orientation
			local delta = angleGap(current.X, rot[1])
				+ angleGap(current.Y, rot[2])
				+ angleGap(current.Z, rot[3])
			if delta > 0.05 then
				node.Orientation = Vector3.new(rot[1], rot[2], rot[3])
				fixedRotation += 1
				touched = true
			end
		end
-- 4. APARIENCIA: color, material, transparencia y colision.
		--
		-- Sin esto, cambiar el color de una pieza en el generador no
		-- llegaba NUNCA a Studio (ver la nota de "collectEntries").
		-- Se compara antes de escribir, por el mismo motivo que la
		-- posicion: asignar una propiedad sin necesidad replica a todos
		-- los clientes y es trafico puro.
		if rgb then
			local targetColor = Color3.new(rgb[1], rgb[2], rgb[3])
			-- Tolerancia de 1/255: los canales llegan con precision de
			-- coma flotante y comparar con == marcaria como distinta una
			-- pieza que ya tiene el color correcto.
			local delta =
				math.abs(node.Color.R - targetColor.R)
				+ math.abs(node.Color.G - targetColor.G)
				+ math.abs(node.Color.B - targetColor.B)
			-- Tolerancia de 3/255, NO de 1.
			--
			-- Roblox guarda "Color" en coma flotante de 32 bits y al
			-- releerla un canal escrito como 70/255 puede volver como 69.
			-- Con una tolerancia de 1/255 la comprobacion lo consideraba
			-- distinto, reescribia el color en cada pasada y el script
			-- NUNCA llegaba a idempotencia: informaba de 36 colores
			-- "arreglados" una y otra vez sin que nada cambiara. Se
			-- acumulan los tres canales, asi que el margen total es 3/255.
			if delta > 0.012 then
				node.Color = targetColor
				fixedColor += 1
				touched = true
			end
		end

		if material then
			-- "Material" es un enum: un nombre invalido lanzaria error y
			-- abortaria TODO el script, dejando la mitad del mapa a medio
			-- colocar. Se protege el caso con pcall.
			local okEnum, resolved = pcall(function()
				return Enum.Material[material]
			end)
			if okEnum and resolved and node.Material ~= resolved then
				node.Material = resolved
				fixedMaterial += 1
				touched = true
			end
		end

		if transparency and math.abs(node.Transparency - transparency) > 0.004 then
			node.Transparency = transparency
			fixedTransparency += 1
			touched = true
		end

		-- CanCollide se restaura SIEMPRE, tambien a false.
		--
		-- No es cosmetico: un "Block_" con la colision desactivada deja de
		-- ser un obstaculo y el contrato de destruccion se rompe sin que
		-- ninguna comprobacion de recuento lo note.
		if canCollide ~= nil and node.CanCollide ~= (canCollide == 1) then
			node.CanCollide = canCollide == 1
			fixedCollision += 1
			touched = true
		end

		if canTouch ~= nil and node.CanTouch ~= (canTouch == 1) then
			node.CanTouch = canTouch == 1
			fixedCollision += 1
			touched = true
		end

		if touched then
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
	fixedPosition = fixedPosition,
	fixedSize = fixedSize,
	fixedRotation = fixedRotation,
	fixedColor = fixedColor,
	fixedMaterial = fixedMaterial,
	fixedTransparency = fixedTransparency,
	fixedCollision = fixedCollision,
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

	// `--run-server` aplica lo MISMO sobre el servidor de Play.
	//
	// POR QUE HACE FALTA
	// ------------------
	// Studio arranca Play desde `AutoSaves/<place>_AutoRecovery_1.rbxl`, que
	// es una COPIA EN DISCO hecha al abrir el lugar. Los cambios hechos en
	// la sesion de EDICION por MCP (que es como entra todo el mapa, porque
	// el plugin de Rojo no esta conectado) NO llegan a esa copia: se
	// comprobo que la edicion tenia `Block_0` a 6x11x6 mientras el servidor
	// de Play lo tenia a 8x8x8, siendo el mismo `instanceId`.
	//
	// Es decir: `verify-geometry.js` mide el servidor, y el servidor arranca
	// de una copia obsoleta. Sin este paso, la verificacion mide siempre el
	// mapa viejo y daria FAIL aunque la fuente y la edicion sean correctas.
	//
	// Aplicar en el servidor hace que lo que se mide sea lo que se acaba de
	// colocar. No sustituye a sincronizar la edicion: ambas siguen siendo
	// necesarias, y por eso son dos pasos y no uno.
	if (process.argv.includes("--run-server")) {
		mcp.serverLuau(luau)
			.then((res) => {
				console.log("");
				console.log("=== aplicado en el SERVIDOR de Play ===");
				console.log(JSON.stringify(res, null, 2));
			})
			.catch((e) => {
				console.error("");
				console.error("No se pudo aplicar en el servidor: " + e.message);
				console.error("Comprueba que Play este arrancado: node tools/play.js start");
				process.exitCode = 1;
			});
	}
}

main();
