// sync-hud.js
// Empuja el HUD GENERADO (`tools/hud.js`) al DataModel de Studio.
//
// POR QUE EXISTE
// --------------
// MEDIDO (MCP, este repositorio): el `KeshusyHUD` que hay en `StarterGui` de
// Studio NO es el que describe el codigo fuente. Divergencias medidas:
//
//   TopBar.Size.Y     runtime 88    fuente 136
//   LeftPanel.Position.Y  runtime 0   fuente 136
//
// O sea: en runtime el panel de misiones arranca en `y = 0`, ENCIMA de la barra
// de identidad. Es el sintoma "HUD desorganizado" que se quiere cerrar.
//
// El plugin de Rojo no esta conectado a esta sesion (ver `tools/sync-scripts.js`),
// asi que el arbol no llega solo. Este script lo reconstruye INSTANCIA A
// INSTANCIA a partir de la MISMA salida que se serializa a `default.project.json`,
// de modo que Studio y el build no puedan decir cosas distintas.
//
// No inventa geometria: copia literalmente el generador.
//
// Uso: node tools/sync-hud.js

const mcp = require("./mcp");
const { buildHud } = require("./hud");

/** Serializa un numero de Luau sin perder precision. */
function num(n) {
	return Number.isInteger(n) ? `${n}` : `${n}`;
}

/** Color3 de un array [r,g,b] en 0..1 (asi los serializa Rojo). */
function color(arr) {
	return `Color3.fromRGB(${Math.round(arr[0] * 255)}, ${Math.round(arr[1] * 255)}, ${Math.round(arr[2] * 255)})`;
}

/**
 * Convierte un valor de propiedad del generador a Luau.
 *
 * Los formatos son los que produce Rojo: `UDim2` y `UDim` llegan envueltos en
 * un objeto, y los colores y vectores como arrays. El TIPO se decide por el
 * NOMBRE de la propiedad, no por adivinar: un `[0.5, 0.5]` es `Vector2` en
 * `AnchorPoint` y un `Color3` en `BackgroundColor3`.
 */
function value(name, v) {
	if (v && typeof v === "object" && !Array.isArray(v)) {
		if (v.UDim2) {
			const [x, y] = v.UDim2;
			return `UDim2.new(${num(x[0])}, ${num(x[1])}, ${num(y[0])}, ${num(y[1])})`;
		}
		if (v.UDim) return `UDim.new(${num(v.UDim[0])}, ${num(v.UDim[1])})`;
		return "nil";
	}
	if (name === "AnchorPoint" && Array.isArray(v)) return `Vector2.new(${num(v[0])}, ${num(v[1])})`;
	if (Array.isArray(v)) return color(v);
	if (typeof v === "string") {
		// Los ENUMS llegan como cadena porque asi los serializa Rojo, pero en
		// Luau hay que escribirlos con su prefijo. La conversion la decide la
		// LISTA de abajo, no el tipo del valor: un `Text` tambien es cadena, y
		// escribirlo como `Enum.Text...` dejaria todas las etiquetas rotas.
		const enumProp = ENUM_PROPS[name];
		if (enumProp) return `${enumProp}.${v}`;
		return JSON.stringify(v);
	}
	if (typeof v === "boolean") return v ? "true" : "false";
	if (typeof v === "number") return num(v);
	return "nil";
}

/**
 * Propiedades cuyo valor es un ENUM.
 *
 * La conversion se decide por el NOMBRE de la propiedad y no por el tipo del
 * valor, porque Rojo serializa los enums como CADENA y un `Text` tambien lo es.
 * Sin esta lista, escribir `o.Text = Enum.Text.MUNDO` dejaria todas las
 * etiquetas del HUD en blanco y el sintoma seria "el HUD disappeared".
 *
 * Si el generador anade una propiedad de enum nueva, hay que meterla aqui: si
 * no, se escribe como texto y Roblox lo acepta sin decir nada.
 */
const ENUM_PROPS = {
	ZIndexBehavior: "Enum.ZIndexBehavior",
	Font: "Enum.Font",
	SortOrder: "Enum.SortOrder",
	FillDirection: "Enum.FillDirection",
	HorizontalAlignment: "Enum.HorizontalAlignment",
	VerticalAlignment: "Enum.VerticalAlignment",
	TextXAlignment: "Enum.TextXAlignment",
	TextYAlignment: "Enum.TextYAlignment",
	ApplyStrokeMode: "Enum.ApplyStrokeMode",
};

/** Propiedades que Rojo serializa pero que no se pueden ASIGNAR en Luau. */
const SKIP = new Set(["Name"]);

/**
 * Emite las asignaciones de un nodo.
 *
 * El prefijo de la variable lo recibe por parametro (`v`) y no se deduce aqui:
 * el emisor usa una variable por nivel (`n0`, `n1`, ...) y una que hardcodease
 * `o` dejaria lineas como `o.ResetOnSpawn` en un bloque donde no existe `o`.
 */
function emitProps(node, v) {
	const lines = [];
	const props = node.$properties || {};
	for (const [k, v2] of Object.entries(props)) {
		if (SKIP.has(k)) continue;
		lines.push(`${v}.${k} = ${value(k, v2)}`);
	}
	return lines;
}

/** Cuenta los nodos de un arbol (para el resumen honesto del final). */
function count(node) {
	let n = 1;
	for (const [k, v] of Object.entries(node)) {
		if (k === "$properties") continue;
		if (Array.isArray(v)) v.forEach((c) => { n += count(c); });
		else if (v && typeof v === "object") n += count(v);
	}
	return n;
}

/**
 * Convierte el arbol del generador en Luau que lo CONSTRUYE.
 *
 * Reconstruye el HUD ENTERO en vez de parchear el que hay. Es deliberado: si
 * Studio conserve un panel viejo que el generador ya no produce, un parche lo
 * dejaria vivo y volveria a haber dos sistemas de interfaz peleandose el
 * espacio. Aqui no: lo que no se declara, no existe.
 */
/**
 * Emite un nodo y sus hijos.
 *
 * El NOMBRE no siempre viene en `node.name`: en la raiz lo pone el envoltorio
 * (`buildHud` devuelve `{ name, node }`) y en los HIJOS lo pone la CLAVE bajo la
 * que estan colgando del padre, porque Rojo usa el nombre de la clave como
 * nombre de la instancia. Por eso el nombre viaja como parametro y no se lee
 * del nodo: sin esto, `Root` y todas las zonas salian como "Hijo" y el
 * `UIController` no encontraba ninguna por su ruta.
 */
function emit(node, parentExpr, out, depth, name) {
	const pad = "\t".repeat(depth);
	const cls = node.$className;
	const v = `n${depth}`;
	out.push(`${pad}do`);
	out.push(`${pad}\tlocal ${v} = Instance.new(${JSON.stringify(cls)})`);
	out.push(`${pad}\t${v}.Name = ${JSON.stringify(name)}`);
	for (const line of emitProps(node, v)) out.push(`${pad}\t${line}`);

	// Los hijos se construyen antes de parentar al padre, como hace Rojo: el
	// padre aparece en el arbol con sus hijos ya dentro.
	for (const [k, child] of Object.entries(node)) {
		if (k === "$properties") continue;
		if (Array.isArray(child)) {
			for (const c of child) emit(c, v, out, depth + 1, c.name || k);
		} else if (child && typeof child === "object" && child.$className) {
			emit(child, v, out, depth + 1, child.name || k);
		}
	}

	out.push(`${pad}\t${v}.Parent = ${parentExpr}`);
	out.push(`${pad}end`);
}

async function main() {
	const hud = buildHud();
	await mcp.init();
	// `buildHud()` devuelve un ENVOLTORIO `{ name, node }`: el nombre de la raiz
	// ("KeshusyHUD") vive en el envoltorio, no en el nodo. Si se emitiera el
	// nodo a pelo, la raiz se crearia con nombre "Hijo" y el `UIController` no
	// encontraria el HUD por su nombre.
	const rootName = hud.name || "KeshusyHUD";
	const out = [
		"-- Generado por tools/sync-hud.js. NO editar a mano.",
		`-- Nodos del HUD: ${count(hud.node)}`,
		"local StarterGui = game:GetService(\"StarterGui\")",
		"",
		"-- Se borra el HUD anterior COMPLETO: el generador es la unica fuente",
		"-- de verdad del arbol, y un panel que quede de mas seria un segundo",
		"-- sistema visual superpuesto.",
		`local old = StarterGui:FindFirstChild(${JSON.stringify(rootName)})`,
		"if old then old:Destroy() end",
		"",
	];
	emit(hud.node, "StarterGui", out, 0, rootName);
	out.push("");
	out.push(`return ${JSON.stringify(`HUD sincronizado: ${count(hud.node)} instancias`)}`);

	const res = await mcp.toolJson("execute_luau", { code: out.join("\n") });
	console.log(typeof res === "string" ? res : JSON.stringify(res, null, 2));
}

main().catch((e) => {
	console.error("SYNC-HUD ERROR: " + e.message);
	process.exit(1);
});
