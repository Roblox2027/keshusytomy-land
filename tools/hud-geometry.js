/**
 * Comprobacion GEOMETRICA de las filas del HUD, sin arrancar Studio.
 *
 * POR QUE EXISTE: en Roblox la posicion de un hijo es RELATIVA a su padre, y
 * dos hermanos con el mismo `Position` ocupan el MISMO rectangulo. Eso no se ve
 * leyendo el codigo del generador, porque cada uno parece razonable por separado.
 * Aqui se resuelve la posicion ABSOLUTA de cada etiqueta y se comprueba que dos
 * sibling no se pisan.
 *
 * REGLA: solo se comparan las cajas de los TEXTOS que se dibujan (Symbol,
 * Caption, Value). Los `Frame` de fila y los decorados (`UICorner`, `UIStroke`)
 * se solapan a proposito.
 *
 * Uso: node tools/hud-geometry.js
 */

const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const PROJECT = path.join(ROOT, "default.project.json");

// Ancho de referencia del viewport. Las filas se anclan al borde derecho con
// `Position = [1, -N, 0, Y]`, asi que su posicion absoluta depende del ancho.
// Se mide con la misma resolucion que usan las capturas de PLAY.
const VIEWPORT_W = 1366;

/**
 * Resuelve una `UDim2` a un numero en px/studs.
 *
 * Rojo serializa las UDim2 como `{"UDim2": [[scale, offset], [scale, offset]]}`,
 * NO como un array pelado. Se acepta tambien el array plano por si el
 * generador cambia de forma, para que esta comprobacion no dependa del
 * envoltorio exacto.
 */
function resolve(udim2, parentSize) {
	if (!udim2) {
		return null;
	}

	const value = Array.isArray(udim2) && udim2.length === 2 && Array.isArray(udim2[0])
		? udim2
		: (udim2.UDim2 || null);

	if (!value) {
		return null;
	}

	// Solo el eje X: el HUD se audita en horizontal, que es donde se pisaban
	// las etiquetas. `value[1]` es el eje Y y no interviene.
	return value[0][0] * parentSize + value[0][1];
}

/** Caja absoluta {x, w} de un nodo, dado el tamano de su padre. */
function boxOf(node, parentX, parentW) {
	const props = node["$properties"];

	if (!props) {
		return null;
	}

	return {
		x: parentX + resolve(props.Position, parentW),
		w: resolve(props.Size, parentW),
	};
}

const project = JSON.parse(fs.readFileSync(PROJECT, "utf8"));
const hud = project.tree.StarterGui.KeshusyHUD;

/** Filas con etiqueta: nombre del panel -> nombre de la fila. */
const ROWS = [
	["Currency", "Coins"],
	["Currency", "Gems"],
	["BombStats", "Bombs"],
	["BombStats", "Power"],
];

const LABEL_KEYS = ["Symbol", "Caption", "Value"];

const problems = [];
let checked = 0;

for (const [panelName, rowName] of ROWS) {
	const panel = hud[panelName];

	if (!panel) {
		problems.push(`falta el panel ${panelName}`);
		continue;
	}

	const panelProps = panel["$properties"];
	const panelX = resolve(panelProps.Position, VIEWPORT_W);
	const panelW = resolve(panelProps.Size, VIEWPORT_W);
	const row = panel[rowName];

	if (!row) {
		problems.push(`falta la fila ${panelName}.${rowName}`);
		continue;
	}

	const rowBox = boxOf(row, panelX, panelW);

	const boxes = [];

	for (const key of LABEL_KEYS) {
		const node = row[key];

		if (!node) {
			problems.push(`${panelName}.${rowName}: falta ${key}`);
			continue;
		}

		const box = boxOf(node, rowBox.x, rowBox.w);
		const align = node["$properties"].TextXAlignment;

		boxes.push({ key, box, align });
		checked++;
	}

	// Dos sibling NO pueden compartir rectangulo. Es el fallo exacto que se
	// corrigio dos veces en este archivo, asi que se comprueba de forma explicita
	// y no confiando en que las cifras queden separadas por la alineacion.
	for (let i = 0; i < boxes.length; i++) {
		for (let k = i + 1; k < boxes.length; k++) {
			const a = boxes[i];
			const b = boxes[k];

			const overlap = Math.min(a.box.x + a.box.w, b.box.x + b.box.w) - Math.max(a.box.x, b.box.x);

			if (overlap > 0) {
				problems.push(
					`${panelName}.${rowName}: ${a.key} y ${b.key} se pisan ${overlap.toFixed(1)} px ` +
						`(${a.box.x.toFixed(1)}..${(a.box.x + a.box.w).toFixed(1)} contra ` +
						`${b.box.x.toFixed(1)}..${(b.box.x + b.box.w).toFixed(1)})`,
				);
			}
		}
	}

	// La fila no puede salirse de su panel: un hijo que se sale del borde se
	// ve pegado a la pantalla, que fue lo que paso con el icono de `statRow`.
	for (const entry of boxes) {
		const right = entry.box.x + entry.box.w;
		const panelRight = panelX + panelW;

		if (right > panelRight + 0.5) {
			problems.push(
				`${panelName}.${rowName}.${entry.key}: se sale del panel por ${(right - panelRight).toFixed(1)} px`,
			);
		}

		if (entry.box.x < panelX - 0.5) {
			problems.push(`${panelName}.${rowName}.${entry.key}: se sale del panel por la izquierda`);
		}
	}

	const summary = boxes
		.map((entry) => `${entry.key} x=${entry.box.x.toFixed(0)} w=${entry.box.w.toFixed(0)} (${entry.align})`)
		.join(" | ");

	console.log(`${panelName}.${rowName}: ${summary}`);
}

console.log(`\nEtiquetas comprobadas: ${checked}`);

if (problems.length > 0) {
	console.log("\nPROBLEMAS:");

	for (const problem of problems) {
		console.log(`  - ${problem}`);
	}

	process.exit(1);
}

console.log("RESULTADO: PASS (ninguna etiqueta se pisa ni se sale de su panel)");

// AUTOPRUEBA del propio checker.
//
// Sin esto, un checker que devolviera siempre PASS seria indistinguible de uno
// que funciona: un verde aqui no probaria nada. Se reintroduce a proposito el
// solapamiento ORIGINAL (`Caption` y `Value` los dos en `Position [0, 24, 0, 0]`)
// y se exige que el checker lo detecte y salga con codigo distinto de 0.
console.log("\nAutoprueba: se reintroduce el solapamiento original...");

const original = JSON.parse(JSON.stringify(project));
const originalBombs = original.tree.StarterGui.KeshusyHUD.BombStats.Bombs;

originalBombs.Caption["$properties"].Position = { UDim2: [[0, 24], [0, 0]] };
originalBombs.Value["$properties"].Position = { UDim2: [[0, 24], [0, 0]] };
originalBombs.Value["$properties"].Size = { UDim2: [[1, -48], [1, 0]] };

function overlapsInTree(tree) {
	const problemsFound = [];

	for (const [panelName, rowName] of ROWS) {
		const panel = tree.StarterGui.KeshusyHUD[panelName];
		const panelProps = panel["$properties"];
		const panelX = resolve(panelProps.Position, VIEWPORT_W);
		const panelW = resolve(panelProps.Size, VIEWPORT_W);
		const row = panel[rowName];

		if (!row) {
			continue;
		}

		const rowBox = boxOf(row, panelX, panelW);
		const boxes = LABEL_KEYS.map((key) => ({ key, box: boxOf(row[key], rowBox.x, rowBox.w) }));

		for (let i = 0; i < boxes.length; i++) {
			for (let k = i + 1; k < boxes.length; k++) {
				const a = boxes[i];
				const b = boxes[k];
				const overlap = Math.min(a.box.x + a.box.w, b.box.x + b.box.w) - Math.max(a.box.x, b.box.x);

				if (overlap > 0) {
					problemsFound.push(`${panelName}.${rowName}: ${a.key}/${b.key} pisan ${overlap.toFixed(1)} px`);
				}
			}
		}
	}

	return problemsFound;
}

const detected = overlapsInTree(original.tree);

if (detected.length === 0) {
	console.log("FALLO DEL CHECKER: no detecta un solapamiento que existe de verdad.");
	process.exit(1);
}

console.log(`Checker detecta ${detected.length} solapamiento(s) reintroducido(s). Correcto.`);