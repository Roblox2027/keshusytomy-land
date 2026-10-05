/**
 * Volcado de la GEOMETRIA DECLARADA del HUD, tal y como la ve el generador.
 *
 * POR QUE ESTE DUMP Y NO UNA CAPTURA
 * ----------------------------------
 * Una captura dice COMO se ve; este volcado dice POR QUE. Un `Position`
 * anclado a `y = 1` con `AnchorPoint = (0,1)` coloca la zona por DEBAJO de la
 * pantalla, y en una captura eso solo se ve como "el HUD no aparece".
 *
 * Uso: node tools/dump-hud-geometry.js
 */
const { buildHud } = require("./hud.js");

const WIDTHS = [375, 768, 1280, 1440];

const HEIGHTS = { 375: 667, 768: 1024, 1280: 720, 1440: 900 };

/**
 * Ancho de las zonas laterales en ejecucion: el resultado de
 * `HudLayout.SideWidthFor` para cada ancho de referencia.
 *
 * Son COPIAS a proposito. El punto de este volcado es comprobar que el ARBOL
 * declarado y la TABLA de `HudLayout` describen lo mismo; si se calculara
 * aqui con la misma formula, un cambio en una de las dos seguiria pasando
 * igual. Los valores se sacaron ejecutando `Layout.SideWidthFor` y deben
 * actualizarse a mano si esa cuenta cambia.
 */
const SIDE_WIDTH = { 375: 105.5, 768: 228.2, 1280: 260, 1440: 260 };

/**
 * Caja ABSOLUTA de una zona, ya resueltos anclaje, escala y posicion.
 *
 * Devuelve `null` si la caja cae fuera de la pantalla, que es el fallo que
 * una captura de juego disimula: si la zona esta fuera, lo que se ve es el
 * fondo del juego y da la impresion de que "el HUD no aparece".
 */
function absoluteBox(node, parent, widthOverride) {
	const p = node.$properties;
	const v = p.Position.UDim2;
	const s = p.Size.UDim2;
	const a = p.AnchorPoint || [0, 0];

	// Escala propia del nodo, si la declara.
	const scaleNode = node.Scale;
	const scale = scaleNode && scaleNode.$properties ? scaleNode.$properties.Scale : 1;

	const x = v[0][0] * parent[0] + v[0][1];
	const y = v[1][0] * parent[1] + v[1][1];
	const w = widthOverride === null || widthOverride === undefined ? s[0][0] * parent[0] + s[0][1] : widthOverride;
	const h = s[1][0] * parent[1] + s[1][1];

	const left = x - w * a[0] * scale;
	const top = y - h * a[1] * scale;

	return { x: left, y: top, width: w * scale, height: h * scale };
}

/** ¿Se solapan dos cajas? Misma asercion que `Layout.Overlaps`. */
function overlaps(a, b) {
	return a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height;
}

const hud = buildHud();
const root = hud.node.Root;

let failures = 0;

for (const width of WIDTHS) {
	const height = HEIGHTS[width];
	console.log("\n=== " + width + "x" + height + " ===");

	const screen = [width, height];
	const boxes = {};
	const names = ["TopBar", "LeftPanel", "RightPanel", "BottomBar"];

	for (const name of names) {
		// `LeftPanel` y `RightPanel` llevan el ancho de DISENO (260). En
		// ejecucion `UIController` lo sustituye por `Layout.SideWidthFor`, que
		// es la cuenta que reserves banda central. Aqui se replica ESA misma
		// correccion: medir el 260 sin ella daria un falso solape en movil que
		// el jugador nunca ve.
		const node = root[name];
		const box = absoluteBox(node, screen, name === "LeftPanel" || name === "RightPanel" ? SIDE_WIDTH[width] : null);
		boxes[name] = box;

		const inside =
			box.x >= -0.5 &&
			box.y >= -0.5 &&
			box.x + box.width <= width + 0.5 &&
			box.y + box.height <= height + 0.5;

		console.log(
			name.padEnd(12) +
				" caja=[" + box.x.toFixed(0) + "," + box.y.toFixed(0) + " " + box.width.toFixed(0) + "x" + box.height.toFixed(0) + "]" +
				(inside ? "" : "  <-- FUERA DE PANTALLA")
		);

		if (!inside) failures++;
	}

	// Las zonas laterales no pueden pisar la banda superior.
	if (overlaps(boxes.LeftPanel, boxes.TopBar)) {
		console.log("  LeftPanel pisa TopBar");
		failures++;
	}
	if (overlaps(boxes.RightPanel, boxes.TopBar)) {
		console.log("  RightPanel pisa TopBar");
		failures++;
	}
	if (overlaps(boxes.LeftPanel, boxes.RightPanel)) {
		console.log("  LeftPanel pisa RightPanel");
		failures++;
	}

	// La bomba, medida dentro de la barra inferior ya colocada.
	const bar = boxes.BottomBar;
	const bomb = absoluteBox(root.BottomBar.BombAction, [bar.width, bar.height]);
	const bombAbsolute = { x: bar.x + bomb.x, y: bar.y + bomb.y, width: bomb.width, height: bomb.height };
	const context = absoluteBox(root.BottomBar.ContextActions, [bar.width, bar.height]);
	const contextAbsolute = { x: bar.x + context.x, y: bar.y + context.y, width: context.width, height: context.height };

	console.log(
		"  BombAction    caja=[" + bombAbsolute.x.toFixed(0) + "," + bombAbsolute.y.toFixed(0) +
			" " + bombAbsolute.width.toFixed(0) + "x" + bombAbsolute.height.toFixed(0) + "]"
	);
	console.log(
		"  ContextActions caja=[" + contextAbsolute.x.toFixed(0) + "," + contextAbsolute.y.toFixed(0) +
			" " + contextAbsolute.width.toFixed(0) + "x" + contextAbsolute.height.toFixed(0) + "]"
	);

	for (const [name, box] of [["bomba", bombAbsolute], ["contexto", contextAbsolute]]) {
		const inside =
			box.x >= -0.5 &&
			box.y >= -0.5 &&
			box.x + box.width <= width + 0.5 &&
			box.y + box.height <= height + 0.5;

		if (!inside) {
			console.log("  " + name + " FUERA DE PANTALLA");
			failures++;
		}
	}
}

console.log(failures === 0 ? "\nGEOMETRIA DECLARADA: OK" : "\nGEOMETRIA DECLARADA: " + failures + " FALLOS");
process.exit(failures === 0 ? 0 : 1);
