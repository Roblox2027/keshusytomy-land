// dedupe-modules.js
// Elimina ModuleScripts duplicados en Studio, en TODA la profundidad.
//
// POR QUE NO BASTA `dedupe-scripts.js`
// ------------------------------------
// Ese script recorre los HIJOS DIRECTOS de tres servicios. Los duplicados
// que hay ahora viven dos niveles mas abajo:
//
//   ReplicatedStorage/Shared/Libraries/AIService        x2
//   ReplicatedStorage/Shared/Libraries/TestDriverLogic  x2
//   ReplicatedStorage/Shared/MonsterDefinitions         x2
//   ServerScriptService/Services/TestDriverService      x2
//
// Un recorrido de un solo nivel los declara "todo correcto", igual que un
// recuento de instancias: los dos se llaman igual y los dos existen.
//
// POR QUE "SE BORRA EL SEGUNDO" NO ES LO MISMO QUE "SE BORRA EL QUE SOBRA"
// --------------------------------------------------------------------------
// Cuando hay dos con el mismo nombre NO se puede destruir el segundo por su
// cuenta: no hay garantia de cual de los dos lleva el codigo bueno. Si el
// equivocado sobrevive, el `require` carga un modulo viejo y el sintoma es
// "el arreglo no funciona" sin ningun error.
//
// La autoridad es el REPOSITORIO: se lee `src/` y se conserva el duplicado
// cuyo `Source` coincide con el archivo del disco. Solo si ninguno coincide
// se conserva el primero, y se dice explicitamente en el informe, porque
// eso significa que el arbol de Studio esta adelantado al repositorio.
//
// QUE NO HACE
// -----------
// No borra un modulo UNICO aunque su fuente no coincida con el disco: eso es
// desincronizacion de fuente, que corresponde a `sync-scripts.js`, no un
// duplicado. Borrar el unico seria destruir codigo que Rojo puede reescribir,
// y el sintoma volveria un sinfin de veces.
//
// Uso:
//   node tools/dedupe-modules.js           # informe, no destruye
//   node tools/dedupe-modules.js --apply   # destruye los sobrantes

"use strict";

const fs = require("fs");
const path = require("path");
const mcp = require("./mcp");

const SRC = path.join(__dirname, "..", "src");
const APPLY = process.argv.includes("--apply");

/** Sufijos de Rojo que no forman parte del nombre de la instancia. */
const SUFFIXES = [".server.lua", ".client.lua", ".luau", ".lua"];

/** Raiz de `src` -> ruta en el DataModel. */
const ROOTS = [
	{ dir: "ReplicatedStorage", runtime: ["ReplicatedStorage"] },
	{ dir: "ServerScriptService", runtime: ["ServerScriptService"] },
	{ dir: "StarterPlayer/StarterPlayerScripts", runtime: ["StarterPlayer", "StarterPlayerScripts"] },
	{ dir: "StarterGui", runtime: ["StarterGui"] },
];

/** Nombre de instancia que produce un archivo de Rojo. */
function instanceName(fileName) {
	for (const suffix of SUFFIXES) {
		if (fileName.endsWith(suffix)) return fileName.slice(0, -suffix.length);
	}
	return fileName;
}

/**
 * Ruta en disco -> ruta en el DataModel, para todos los .lua de `src`.
 *
 * `path.join` produce `src\ReplicatedStorage\...` en Windows, y las barras
 * invertidas hay que traducirlas antes de comparar con las rutas del runtime,
 * que usan barra normal.
 */
function buildSourceIndex() {
	const index = new Map();

	for (const root of ROOTS) {
		const base = path.join(SRC, root.dir);
		if (!fs.existsSync(base)) continue;

		const walk = (dir, segments) => {
			for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
				const full = path.join(dir, entry.name);
				if (entry.isDirectory()) {
					walk(full, segments.concat(entry.name));
				} else if (entry.name.endsWith(".lua")) {
					const name = instanceName(entry.name);
					const source = fs.readFileSync(full, "utf8").replace(/\r\n/g, "\n");
					index.set(root.runtime.concat(segments, name).join("."), source);
				}
			}
		};

		walk(base, []);
	}

	return index;
}

/**
 * Sonda que devuelve las copias de cada modulo y los duplicados por padre.
 *
 * Se separa el codigo de cada copia de su ruta precisamente para poder
 * compararlo con el disco: elijir por nombre es elegir a ciegas.
 */
const SEP = String.fromCharCode(1);

/**
 * Tabla literal de Luau a partir de valores de JavaScript.
 *
 * `JSON.stringify(["a","b"])` devuelve `["a","b"]`, que en Luau es una EXPRESION
 * correcta, pero `ipairs()` sobre una tabla construida asi funciona solo si las
 * llaves van dentro. Se envuelve a mano y se escapan las comillas y las barras
 * invertidas de los nombres de ruta, que en Windows las traen.
 */
function luaList(values) {
	return values.map((v) => `"${String(v).replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`).join(", ");
}
const SCAN = `
local out = {}

local function scan(node, path, depth)
	if depth > 5 then return end
	local byName = {}
	for _, child in ipairs(node:GetChildren()) do
		byName[child.Name] = (byName[child.Name] or 0) + 1
		if child:IsA("LuaSourceContainer") then
			-- El separador es string.char(1) y NO "\\1": Luau rechaza una
			-- secuencia de escape mal formada dentro de un literal, y el
			-- codigo del modulo viaja entero en la cadena.
			table.insert(out, "SRC|" .. path .. "|" .. child.Name .. string.char(1) .. child.Source)
		else
			scan(child, path .. "." .. child.Name, depth + 1)
		end
	end
	for name, count in pairs(byName) do
		if count > 1 then
			table.insert(out, "DUP|" .. path .. "|" .. name)
		end
	end
end

scan(game:GetService("ReplicatedStorage"), "ReplicatedStorage", 0)
scan(game:GetService("ServerScriptService"), "ServerScriptService", 0)
local sps = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
if sps then scan(sps, "StarterPlayerScripts", 0) end
scan(game:GetService("StarterGui"), "StarterGui", 0)

table.sort(out)
return out
`;

async function main() {
	const index = buildSourceIndex();

	const scan = await mcp.toolJson("execute_luau", { code: SCAN });
	if (!scan || !scan.success) {
		console.error("La sonda de Studio fallo:", JSON.stringify(scan));
		process.exit(1);
	}

	const raw = typeof scan.returnValue === "string" ? JSON.parse(scan.returnValue) : scan.returnValue;

	// parent -> nombre -> [codigos], y la lista de duplicados declarados.
	const copiesByParent = new Map();
	const duplicateKeys = new Map();

	for (const row of raw) {
		const parts = row.split("|");
		if (parts[0] === "DUP") {
			duplicateKeys.set(parts[1] + "." + parts[2], { parent: parts[1], name: parts[2] });
		} else if (parts[0] === "SRC") {
			const parent = parts[1];
			const [name, source] = parts.slice(2).join("|").split(SEP);
			if (!copiesByParent.has(parent)) copiesByParent.set(parent, new Map());
			const list = copiesByParent.get(parent).get(name) || [];
			list.push(source);
			copiesByParent.get(parent).set(name, list);
		}
	}

	if (duplicateKeys.size === 0) {
		console.log("DUPLICADOS: 0");
		return;
	}

	const victims = [];

	for (const [key, group] of duplicateKeys) {
		const copies = (copiesByParent.get(group.parent) || new Map()).get(group.name) || [];
		const expected = index.get(key);

		console.log(`${copies.length}x ${key}`);

		if (!expected) {
			console.log("   AVISO: no hay archivo equivalente en src/");
			console.log("   se conserva la copia 1; revisa el arbol antes de aplicar");
			for (let i = 1; i < copies.length; i++) victims.push({ key, order: i });
			continue;
		}

		const matches = [];
		copies.forEach((source, i) => {
			if (source.replace(/\r\n/g, "\n") === expected) matches.push(i);
		});

		if (matches.length === 0) {
			// Studio esta adelantado al repositorio: ninguna copia es la buena.
			// Se conserva la primera y se dice, en vez de borrar al azar.
			console.log("   AVISO: ninguna copia coincide con src/ (Studio adelantado)");
			console.log("   se conserva la copia 1; ejecuta sync-scripts.js despues");
			for (let i = 1; i < copies.length; i++) victims.push({ key, order: i });
			continue;
		}

		const keep = matches[0];
		console.log(`   la copia ${keep + 1} coincide con src/ y se conserva`);

		copies.forEach((_, i) => {
			if (i === keep) return;
			const why = matches.includes(i) ? "copia identica" : "fuente distinta de src/";
			console.log(`   sobra la copia ${i + 1}: ${why}`);
			victims.push({ key, order: i });
		});
	}

	console.log(`\nDUPLICADOS: ${duplicateKeys.size} grupos, ${victims.length} copia(s) sobrante(s)`);

	if (!APPLY || victims.length === 0) {
		if (!APPLY) console.log("Borrado: NO (pasa --apply)");
		return;
	}

	// El borrado se hace por RUTA, no por indice global: entre la sonda y el
	// borrado el orden de `GetChildren()` no esta garantizado, y destruir por
	// posicion borraria la copia equivocada.
	const byParent = new Map();
	for (const v of victims) {
		const parent = duplicateKeys.get(v.key).parent;
		if (!byParent.has(parent)) byParent.set(parent, []);
		byParent.get(parent).push({ name: duplicateKeys.get(v.key).name, order: v.order });
	}

	let destroyed = 0;

// Tabla de Lua escrita a mano: JSON.stringify(entries) produciria
	// [{"name":"X","order":1}], y las llaves con dos puntos no son sintaxis de
	// Luau. El fallo sale como "Expected identifier when parsing expression" en
	// una linea que no tiene nada sospechoso.

	for (const [parent, entries] of byParent) {
		const luaEntries = entries.map((e) => `{ name = ${luaList([e.name])}, order = ${e.order} }`);
		const code = `
local node = game
for seg in string.gmatch(${luaList([parent])}, "[^.]+") do
	node = node and node:FindFirstChild(seg)
end
if not node then return {} end

local targets = {}
	for _, e in ipairs({${luaEntries.join(", ")}}) do
		-- El campo 'order' es la posicion (base 0) de la copia sobrante ENTRE
		-- las que se llaman 'e.name', contadas sobre GetChildren() en el orden
		-- en que las devuelve. Por eso se cuenta solo entre las de ese nombre y
		-- no sobre todos los hijos: 'Shared' tiene muchos y order = 1 no
		-- significaria 'la segunda' si se contaran todas.
		local seen = 0
		local victim
		for _, child in ipairs(node:GetChildren()) do
			if child.Name == e.name then
				seen += 1
				if seen == e.order + 1 then
					victim = child
					break
				end
			end
		end

		if victim then
			table.insert(targets, victim:GetFullName())
			victim:Destroy()
		else
			table.insert(targets, "NO ENCONTRADO: " .. e.name)
		end
	end

	return targets
`;

		const res = await mcp.toolJson("execute_luau", { code });
		// Se imprime el resultado crudo cuando no trae `returnValue`: sin esto un
		// fallo del puente se lee como "lista vacia" y se cuenta como si el
		// borrado hubiera ocurrido.
		if (!res || res.returnValue === undefined) {
			console.error("   SIN RESULTADO: " + JSON.stringify(res));
			if (process.env.DEDUPE_DEBUG_CODE) console.error(code);
			process.exitCode = 1;
			continue;
		}
		const list = typeof res.returnValue === "string" ? JSON.parse(res.returnValue) : res.returnValue;
		destroyed += list.length;
		for (const full of list) console.log("   DESTRUIDA: " + full);
	}

	console.log(`DESTRUIDAS: ${destroyed}`);
}

main().catch((e) => {
	console.error("FALLO:", e.message);
	process.exit(1);
});
