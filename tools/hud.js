// hud.js
// Construye el HUD REAL de KeshusyTomy-LanD como arbol de interfaces.
//
// POR QUE SE GENERA Y NO SE ESCRIBE A MANO
// ----------------------------------------
// La UI anterior se construia dentro de `UIController.buildGui()`, o sea por
// codigo en tiempo de ejecucion. Eso tiene dos fallos reales:
//
//   1. El arbol no existe en el SOURCE. El Workspace se podia auditar, pero
//      el HUD no: no se podia abrir el lugar y MIRAR el HUD sin entrar en
//      juego, y ningun verificador de estructura podia contarlo. Por eso el
//      informe decia "StarterGui = 0 hijos" sin que nada fallara.
//   2. Un HUD entero dentro de un controller es MONOLITO: cada campo nuevo
//      obliga a tocar el mismo archivo y no hay componente reutilizable.
//
// Aqui el HUD es un `ScreenGui` de verdad con componentes separados
// (TopBar, PlayerStats, Currency, BombStats, Objective, Mission, Timer,
// BossBar, Notifications), y `UIController` se limita a ENLAZARLOS a los
// atributos que publica el servidor. La UI no decide nada: muestra.
//
// FORMATO DE LOS VALORES EN ROJO
// -------------------------------
// Rojo serializa `UDim2` como `[xEscala, xOffset, yEscala, yOffset]` y `UDim`
// como `[escala, offset]`. Se escriben como ARRAYS, no como objetos: es lo
// que produce el resto del generador para `Position`/`Size` de los Partes.

const color = (r, g, b) => [r / 255, g / 255, b / 255];

// Paleta del HUD, centralizada para que ningun panel invente su propio tono.
const THEME = {
	panel: color(16, 19, 28),
	accent: color(120, 190, 255),
	crystal: color(150, 220, 255),
	ember: color(255, 176, 90),
	hp: color(255, 96, 110),
	bomb: color(255, 200, 90),
	xp: color(150, 255, 190),
	coin: color(255, 214, 110),
	gem: color(196, 150, 255),
	level: color(255, 236, 150),
	text: color(236, 241, 255),
	textDim: color(176, 188, 214),
};

/** Crea un Frame con esquinas redondeadas y borde: el contenedor del HUD. */
function panel(name, opts) {
	return {
		name: name,
		node: {
			$className: "Frame",
			$properties: {
				BackgroundColor3: THEME.panel,
				BackgroundTransparency: 0.2,
				BorderSizePixel: 0,
				Position: opts.position,
				Size: opts.size,
			},
			UICorner: {
				$className: "UICorner",
				$properties: { CornerRadius: [0, 10] },
			},
			UIStroke: {
				$className: "UIStroke",
				$properties: { Color: THEME.accent, Thickness: 1, Transparency: 0.7 },
			},
		},
	};
}

/**
 * Barra de progreso (HP, XP, boss).
 *
 * Se construye con la tecnica del marco: un relleno `Fill` que se escala en X
 * desde la izquierda. Escalar es mejor que cambiar `Size` porque el ancho del
 * marco no se toca y el valor 0 se ve como una barra VACIA y no como un
 * panel que desaparece.
 */
function bar(name, opts) {
	const h = opts.height || 14;
	const inner = h - 6;

	const node = {
		$className: "Frame",
		$properties: {
			BackgroundColor3: color(8, 10, 16),
			BackgroundTransparency: 0.3,
			BorderSizePixel: 0,
			Position: opts.position,
			Size: opts.size,
		},
		UICorner: { $className: "UICorner", $properties: { CornerRadius: [0, 7] } },
		Fill: {
			$className: "Frame",
			$properties: {
				BackgroundColor3: opts.tint || THEME.accent,
				BorderSizePixel: 0,
				// ESCALA 0 al empezar: una barra llena sin datos seria una
				// MENTIRA visual. El jugador veria la vida al maximo y el XP
				// completo antes de que el servidor publicase nada.
				//
				// OJO al orden: es [xEscala, xOffset, yEscala, yOffset]. Lo que
				// va a 1 es el OFFSET del alto, no la escala del ancho: poner
				// el 1 en la escala llenaria la barra entera.
				Size: [0, 0, 0, inner],
				Position: [0, 3, 0, 3],
			},
			UICorner: { $className: "UICorner", $properties: { CornerRadius: [0, 5] } },
		},
		Text: {
			$className: "TextLabel",
			$properties: {
				BackgroundTransparency: 1,
				BorderSizePixel: 0,
				Font: "GothamBold",
				Position: [0, 8, 0, 0],
				Size: [1, -16, 1, 0],
				Text: "",
				TextColor3: THEME.text,
				TextSize: 11,
				TextScaled: false,
				TextXAlignment: "Center",
				TextYAlignment: "Center",
				TextWrapped: false,
				ZIndex: 2,
			},
		},
	};

	return { name: name, node: node };
}

// ---------------------------------------------------------------------------
// COMPONENTES
// ---------------------------------------------------------------------------
//
// Cada componente es un Frame hermano dentro del ScreenGui. No se anidan
// unos dentro de otros salvo donde tiene sentido (barras dentro de su marco).
// Motivo: un HUD anidado obliga a recorrer el arbol entero para cambiar un
// icono; con hermanos, `UIController` localiza cada panel por nombre y
// actualiza sin depender de la estructura interna de los demas.

// MEDIDO con `tools/probe-hud.js` (shot-04): antes esta fila era un unico
// TextLabel con `Position = [0, 26, 0, y]` y el prefijo como HIJO en
// `[0, 0, 0, 0]`. Un hijo con posicion CERO se coloca en el ORIGEN de su
// padre, no en el del panel: los dos acababan en el MISMO pixel
//
//   Bombs [TextLabel] pos=(38,330)
//     Icon [TextLabel] pos=(38,330)
//
// y la letra "B" tapaba la cifra entera. La pantalla muestrava solo "B" y "P".
//
// El arreglo NO es restar 26 px: es dejar de anidar. La fila pasa a ser un Frame
// hermano con `Icon` y `Value` COLGANDO DEL PANEL, igual que ya hace
// `currencyPanel`. Asi cada uno mide su posicion desde el mismo sitio y no
// pueden solaparse por construccion.
function statRow(name, y, tint, prefix, caption) {
	return {
		name: name,
		node: {
			$className: "Frame",
			$properties: {
				BackgroundTransparency: 1,
				BorderSizePixel: 0,
				Position: [0, 12, 0, y],
				Size: [1, -24, 0, 22],
			},
			Symbol: {
				$className: "TextLabel",
				$properties: {
					BackgroundTransparency: 1,
					BorderSizePixel: 0,
					Font: "GothamBold",
					Position: [0, 0, 0, 0],
					Size: [0, 22, 1, 0],
					Text: prefix,
					TextColor3: tint,
					TextSize: 15,
					TextScaled: false,
					TextXAlignment: "Left",
					TextYAlignment: "Center",
					TextWrapped: false,
				},
			},
			// El nombre del recurso es lo que hace legible la cifra: una "B"
			// suelta no dice si es un contador de bombas o un boton.
			Caption: {
				$className: "TextLabel",
				$properties: {
					BackgroundTransparency: 1,
					BorderSizePixel: 0,
					Font: "GothamBold",
					Position: [0, 24, 0, 0],
					Size: [1, -80, 1, 0],
					Text: caption,
					TextColor3: THEME.textDim,
					TextSize: 12,
					TextScaled: false,
					TextXAlignment: "Left",
					TextYAlignment: "Center",
					TextWrapped: false,
				},
			},
			// El prefijo viaja como hermano, no dentro del texto. Asi el icono
			// se puede cambiar sin reescribir la cadena del valor.
			Value: {
				$className: "TextLabel",
				$properties: {
					BackgroundTransparency: 1,
					BorderSizePixel: 0,
					Font: "GothamBold",
					// La cifra vive en su PROPIA columna, anclada a la derecha.
					//
					// BUG CORREGIDO (medido con probe-hud en PLAY): `Caption` y
					// `Value` compartian `Position = [0, 24, 0, 0]`, o sea los dos
					// ocupan exactamente el mismo rectangulo. Solo se veia bien
					// porque `Caption` va a la izquierda y `Value` a la derecha:
					// con una etiqueta larga o una cifra ancha se pisaban. Es el
					// mismo fallo que se corrigio anadiendo `Symbol`, repetido un
					// nivel mas abajo, asi que la separacion se hace aqui de
					// verdad y no por alineacion.
					Position: [1, -52, 0, 0],
					Size: [0, 52, 1, 0],
					Text: "--",
					TextColor3: tint,
					TextSize: 16,
					TextScaled: false,
					TextXAlignment: "Right",
					TextYAlignment: "Center",
					TextWrapped: false,
				},
			},
		},
	};
}

/** Panel de monedas y gemas: recursos que se gastan en cosas distintas. */
function currencyPanel() {
	const p = panel("Currency", {
		position: [1, -196, 0, 12],
		size: [0, 184, 0, 72],
	});

	// Fila de recurso: un icono y su cifra.
	//
	// MEDIDO en la captura del cliente: los dos labels de texto salian
	// SUELTOS ("0" y "0" sin ninguna pista de que era cada uno) y el icono
	// de `statRow` se salia del panel por `Position = [0, -24, ...]`,
	// dejandolo pegado al borde de la pantalla. Un recurso sin etiqueta es
	// un numero que el jugador no sabe interpretar, asi que cada cifra
	// lleva delante su simbolo y su nombre.
	const resourceRow = function(name, y, tint, symbol, caption) {
		return {
			$className: "Frame",
			$properties: {
				BackgroundTransparency: 1,
				BorderSizePixel: 0,
				Position: [0, 12, 0, y],
				Size: [1, -24, 0, 22],
			},
			Symbol: {
				$className: "TextLabel",
				$properties: {
					BackgroundTransparency: 1, BorderSizePixel: 0,
					Font: "GothamBold",
					Position: [0, 0, 0, 0], Size: [0, 22, 1, 0],
					Text: symbol, TextColor3: tint, TextSize: 17,
					TextScaled: false, TextXAlignment: "Left",
					TextYAlignment: "Center", TextWrapped: false,
				},
			},
			// El NOMBRE del recurso es lo que hace legible la cifra. Sin
			// el, "0" y "0" son dos numeros sin significado.
			Caption: {
				$className: "TextLabel",
				$properties: {
					BackgroundTransparency: 1, BorderSizePixel: 0,
					Font: "GothamBold",
					Position: [0, 24, 0, 0], Size: [1, -62, 1, 0],
					Text: caption, TextColor3: THEME.textDim, TextSize: 12,
					TextScaled: false, TextXAlignment: "Left",
					TextYAlignment: "Center", TextWrapped: false,
				},
			},
			Value: {
				$className: "TextLabel",
				$properties: {
					BackgroundTransparency: 1, BorderSizePixel: 0,
					Font: "GothamBold",
					// Columna propia, anclada a la derecha: `Caption` y `Value`
					// NO pueden compartir rectangulo. Mismo criterio que en
					// `statRow`, y el motivo esta medido con probe-hud: antes
					// los dos ocupaban `Position = [0, 24, 0, 0]` y solo se
					// veian separados porque uno alinea a la izquierda y el
					// otro a la derecha.
					Position: [1, -34, 0, 0], Size: [0, 34, 1, 0],
					Text: "--", TextColor3: tint, TextSize: 16,
					TextScaled: false, TextXAlignment: "Right",
					TextYAlignment: "Center", TextWrapped: false,
				},
			},
		};
	};

	// `Coins` y `Gems` cuelgan DIRECTAMENTE del panel, no de un contenedor
	// intermedio. Rojo exige que todo nodo del proyecto tenga `$className`, y
	// un Folder "Stat" sin clase lo hacia fallar el build entero.
	//
	// Cada uno es un Frame con `Symbol`, `Caption` y `Value`. El nombre de
	// la fila es `Coins`/`Gems` (el que busca `UIController`) y la cifra
	// vive en `Value`.
	p.node.Coins = resourceRow("Coins", 6, THEME.coin, "$", "MONEDAS");
	p.node.Gems = resourceRow("Gems", 34, THEME.gem, "◆", "GEMAS");
	return p;
}

/**
 * MONTAJE DEL HUD
 *
 * Devuelve UN `ScreenGui` con nueve componentes hermanos. El orden es el
 * orden de lectura del jugador: identidad arriba a la izquierda, recursos
 * arriba a la derecha, vida y bombas abajo a la izquierda, objetivo y mision
 * abajo a la derecha, temporizador arriba al centro, jefe encima de todo y
 * notificaciones al centro.
 */
function buildHudTree() {
	// ---- TopBar: mundo actual + nivel. Son las dos respuestas a "donde
	// estoy" y "que soy", y lo primero que se mira al salir de un portal.
	const topBar = panel("TopBar", {
		position: [0, 12, 0, 10],
		size: [0, 260, 0, 58],
	});
	topBar.node.World = {
		$className: "TextLabel",
		$properties: {
			BackgroundTransparency: 1, BorderSizePixel: 0, Font: "GothamBold",
			Position: [0, 12, 0, 6], Size: [1, -24, 0, 24],
			Text: "MUNDO: Lobby", TextColor3: THEME.crystal, TextSize: 17,
			TextScaled: false, TextXAlignment: "Left", TextYAlignment: "Center",
			TextWrapped: false,
		},
	};
	topBar.node.Level = {
		$className: "TextLabel",
		$properties: {
			BackgroundTransparency: 1, BorderSizePixel: 0, Font: "GothamBold",
			Position: [0, 12, 0, 30], Size: [1, -24, 0, 20],
			Text: "LV 1", TextColor3: THEME.level, TextSize: 14,
			TextScaled: false, TextXAlignment: "Left", TextYAlignment: "Center",
			TextWrapped: false,
		},
	};

	// ---- PlayerStats: vida y XP. Son barras porque un numero suelto no dice
	// "cuanto me queda": la barra responde de un vistazo.
	const playerStats = panel("PlayerStats", {
		position: [0, 12, 1, -104],
		size: [0, 260, 0, 92],
	});
	playerStats.node.Title = {
		$className: "TextLabel",
		$properties: {
			BackgroundTransparency: 1, BorderSizePixel: 0, Font: "GothamBold",
			Position: [0, 12, 0, 4], Size: [1, -24, 0, 16],
			Text: "ESTADO", TextColor3: THEME.textDim, TextSize: 11,
			TextScaled: false, TextXAlignment: "Left", TextYAlignment: "Center",
			TextWrapped: false,
		},
	};
	playerStats.node.HPBar = bar("HPBar", {
		position: [0, 12, 0, 22], size: [1, -24, 0, 18], tint: THEME.hp,
	}).node;
	playerStats.node.XPBar = bar("XPBar", {
		position: [0, 12, 0, 46], size: [1, -24, 0, 18], tint: THEME.xp,
	}).node;

	// ---- BombStats: bombas y poder del Core.
	const bombStats = panel("BombStats", {
		position: [0, 12, 1, -196],
		size: [0, 260, 0, 72],
	});
	// Estas filas son Frames con `Symbol`, `Caption` y `Value`, igual que las
	// de `Currency`: el icono NO es hijo de la cifra (ver `statRow`).
	bombStats.node.Bombs = statRow("Bombs", 6, THEME.bomb, "B", "BOMBAS").node;
	bombStats.node.Power = statRow("Power", 34, THEME.accent, "P", "PODER").node;

	// ---- ActiveBombs: las bombas VIVAS del jugador.
	//
	// "BOMBAS" ya cuenta las que tiene colocadas. Lo que falta para el jugador
	// es "cuantas de esas me van a explotar encima", y confundirlas con el
	// contador de disponibles es como se pierde la nocion de peligro.
	//
	// Se oculta por defecto: un "x0" permanente es ruido.
	//
	// COLOCACION (medida contra el boton tactil): el boton de bomba que crea
	// `InputController` ocupa `(1, -32)` con 96x96, o sea X [-128, -32] y
	// Y [-128, -32]. Este panel se pone a la IZQUIERDA de ese boton
	// (X [-260, -140]) para que el contador de bombas activas no tape el
	// control que coloca bombas: un HUD que tapa el boton es un HUD roto.
	const activeBombs = panel("ActiveBombs", {
		position: [1, -260, 1, -40],
		size: [0, 120, 0, 40],
	});
	activeBombs.node.$properties.Visible = false;
	activeBombs.node.Symbol = {
		$className: "TextLabel",
		$properties: {
			BackgroundTransparency: 1, BorderSizePixel: 0, Font: "GothamBold",
			Position: [0, 10, 0, 8], Size: [0, 22, 0, 24],
			Text: "B", TextColor3: THEME.bomb, TextSize: 18,
			TextScaled: false, TextXAlignment: "Left", TextYAlignment: "Center",
			TextWrapped: false,
		},
	};
	activeBombs.node.Caption = {
		$className: "TextLabel",
		$properties: {
			BackgroundTransparency: 1, BorderSizePixel: 0, Font: "GothamBold",
			Position: [0, 34, 0, 4], Size: [1, -46, 0, 12],
			Text: "ACTIVAS", TextColor3: THEME.textDim, TextSize: 10,
			TextScaled: false, TextXAlignment: "Left", TextYAlignment: "Center",
			TextWrapped: false,
		},
	};
	activeBombs.node.Value = {
		$className: "TextLabel",
		$properties: {
			BackgroundTransparency: 1, BorderSizePixel: 0, Font: "GothamBold",
			Position: [0, 34, 0, 16], Size: [1, -46, 0, 20],
			Text: "0", TextColor3: THEME.bomb, TextSize: 20,
			TextScaled: false, TextXAlignment: "Left", TextYAlignment: "Center",
			TextWrapped: false,
		},
	};

	// ---- DamageVignette: borde ROJO al recibir dano.
	//
	// Oscurecer TODA la pantalla es un castigo, no un aviso. Aqui solo se
	// enrojece el BORDE y se desvanece solo: dice "te han pegado" sin tapar
	// el combate, que es justo lo que el jugador necesita ver en ese
	// instante.
	const damageVignette = panel("DamageVignette", {
		position: [0, 0, 0, 0],
		size: [1, 0, 1, 0],
	});
	damageVignette.node.$properties.BackgroundTransparency = 1;
	damageVignette.node.$properties.Active = false;
	damageVignette.node.$properties.ZIndex = 30;
	damageVignette.node.UIStroke.$properties.Transparency = 1;
	damageVignette.node.UIStroke.$properties.Thickness = 26;
	damageVignette.node.UIStroke.$properties.Color = color(255, 40, 60);
	damageVignette.node.UIStroke.$properties.ApplyStrokeMode = "Border";

	// ---- DamageNumbers: contenedor de numeros flotantes.
	//
	// Vacio de serie: los numeros aparecen al recibir o hacer dano y se
	// autodestruyen. Un contenedor permanente con texto permanente satura la
	// pantalla.
	const damageNumbers = panel("DamageNumbers", {
		position: [0, 0, 0, 0],
		size: [1, 0, 1, 0],
	});
	damageNumbers.node.$properties.BackgroundTransparency = 1;
	damageNumbers.node.$properties.Active = false;
	damageNumbers.node.$properties.ZIndex = 25;
	damageNumbers.node.UIStroke.$properties.Transparency = 1;

	// ---- PowerupRow: efectos temporales activos (ESCUDO, VELOCIDAD...).
	//
	// Sin esta fila el powerup se recoge, hace algo invisible y el jugador
	// cree que no funciona. El HUD es quien convierte un efecto invisible
	// en un efecto creible.
	//
	// Va en la columna IZQUIERDA, justo encima del panel de bombas y debajo
	// del de vida, porque los tres cuentan "lo que tengo ahora".
	const powerupRow = panel("PowerupRow", {
		position: [0, 12, 1, -124],
		size: [0, 260, 0, 26],
	});
	powerupRow.node.$properties.Visible = false;
	powerupRow.node.Text = {
		$className: "TextLabel",
		$properties: {
			BackgroundTransparency: 1, BorderSizePixel: 0, Font: "GothamBold",
			Position: [0, 12, 0, 4], Size: [1, -24, 0, 18],
			Text: "", TextColor3: THEME.crystal, TextSize: 13,
			TextScaled: false, TextXAlignment: "Left", TextYAlignment: "Center",
			TextWrapped: false,
		},
	};

	// ---- Objective: que hay que hacer ahora.
	//
	// POSICION (medida en la captura del cliente): antes estaba en
	// `[1, -292, 1, -104]`, es decir en la franja Y [-104, -56]. Ahi vive el
	// boton `BOMBA` de 96x96 anclado en (1,-32,1,-32), que ocupa
	// Y [-128, -32]: los dos se solapaban y el boton tapaba el objetivo. Se
	// sube la columna derecha para que nada se pise.
	const objective = panel("Objective", {
		position: [1, -292, 1, -152],
		size: [0, 280, 0, 48],
	});
	objective.node.Title = {
		$className: "TextLabel",
		$properties: {
			BackgroundTransparency: 1, BorderSizePixel: 0, Font: "GothamBold",
			Position: [0, 12, 0, 4], Size: [1, -24, 0, 16],
			Text: "OBJETIVO", TextColor3: THEME.textDim, TextSize: 11,
			TextScaled: false, TextXAlignment: "Left", TextYAlignment: "Center",
			TextWrapped: false,
		},
	};
	objective.node.Text = {
		$className: "TextLabel",
		$properties: {
			BackgroundTransparency: 1, BorderSizePixel: 0, Font: "GothamBold",
			Position: [0, 12, 0, 22], Size: [1, -24, 0, 20],
			Text: "", TextColor3: THEME.text, TextSize: 14, TextScaled: false,
			TextXAlignment: "Left", TextYAlignment: "Center", TextWrapped: false,
		},
	};

	// ---- Mission: progreso de misiones (dato real de `QuestService`).
	//
	// Antes en `[1, -292, 1, -156]`: caia ENCIMA de `Objective` (que ocupaba
	// Y [-104, -56]) y ambos se pisaban. Ahora la columna derecha es una
	// pila limpia: Mission arriba, Objective debajo, y el boton de bomba
	// debajo de las dos sin tocarlas.
	const mission = panel("Mission", {
		position: [1, -292, 1, -204],
		size: [0, 280, 0, 44],
	});
	mission.node.Text = {
		$className: "TextLabel",
		$properties: {
			BackgroundTransparency: 1, BorderSizePixel: 0, Font: "GothamBold",
			Position: [0, 12, 0, 10], Size: [1, -24, 0, 24],
			Text: "", TextColor3: THEME.text, TextSize: 14, TextScaled: false,
			TextXAlignment: "Left", TextYAlignment: "Center", TextWrapped: false,
		},
	};

	// ---- Timer: cuenta atras arriba al centro. El servidor publica
	// `RoundTimeRemaining`; el cliente solo lo formatea a mm:ss.
	const timer = panel("Timer", {
		position: [0.5, -90, 0, 10],
		size: [0, 180, 0, 44],
	});
	timer.node.Round = {
		$className: "TextLabel",
		$properties: {
			BackgroundTransparency: 1, BorderSizePixel: 0, Font: "GothamBold",
			Position: [0, 8, 0, 4], Size: [1, -16, 0, 18],
			Text: "RONDA 0", TextColor3: THEME.textDim, TextSize: 12,
			TextScaled: false, TextXAlignment: "Center", TextYAlignment: "Center",
			TextWrapped: false,
		},
	};
	timer.node.Time = {
		$className: "TextLabel",
		$properties: {
			BackgroundTransparency: 1, BorderSizePixel: 0, Font: "GothamBold",
			Position: [0, 8, 0, 20], Size: [1, -16, 0, 20],
			Text: "--:--", TextColor3: THEME.ember, TextSize: 18,
			TextScaled: false, TextXAlignment: "Center", TextYAlignment: "Center",
			TextWrapped: false,
		},
	};

	// ---- BossBar: oculta por defecto. Una barra de jefe VACIA permanentemente
	// en pantalla es peor que ninguna: ensena al jugador a no mirarla, y el dia
	// que aparezca de verdad ya la esta ignorando.
	const bossBar = panel("BossBar", {
		position: [0.5, -220, 0, 78],
		size: [0, 440, 0, 40],
	});
	bossBar.node.$properties.Visible = false;
	bossBar.node.Name = {
		$className: "TextLabel",
		$properties: {
			BackgroundTransparency: 1, BorderSizePixel: 0, Font: "GothamBold",
			Position: [0, 10, 0, 2], Size: [1, -20, 0, 16],
			Text: "", TextColor3: THEME.hp, TextSize: 13, TextScaled: false,
			TextXAlignment: "Center", TextYAlignment: "Center", TextWrapped: false,
		},
	};
	bossBar.node.Bar = bar("Bar", {
		position: [0, 10, 0, 20], size: [1, -20, 0, 16], tint: THEME.hp,
	}).node;

	// ---- Notifications: contenedor VACIO. Los avisos se crean y se destruyen
	// en runtime (`UIController.Notify`); no hay ninguno de serie porque un
	// texto de arranque es ruido, no informacion.
	const notifications = panel("Notifications", {
		position: [0.5, -190, 0, 300],
		size: [0, 380, 0, 200],
	});
	notifications.node.$properties.BackgroundTransparency = 1;
	notifications.node.UIStroke.$properties.Transparency = 1;

	const map = {};
	for (const c of [
		topBar,
		currencyPanel(),
		playerStats,
		bombStats,
		activeBombs,
		powerupRow,
		damageNumbers,
		damageVignette,
		objective,
		mission,
		timer,
		bossBar,
		notifications,
	]) {
		map[c.name] = c.node;
	}

	return {
		name: "KeshusyHUD",
		node: {
			$className: "ScreenGui",
			$properties: {
				// `ResetOnSpawn = false`: el HUD debe sobrevivir a la muerte
				// del personaje. Con true, Roblox lo recrea en cada reaparicion
				// y el jugador ve parpadear toda la interfaz.
				ResetOnSpawn: false,
				IgnoreGuiInset: false,
				DisplayOrder: 20,
				ZIndexBehavior: "Sibling",
				Enabled: true,
			},
			...map,
		},
	};
}

// ---------------------------------------------------------------------------
// CONVERSION A LA FORMA QUE ENTIENDE ROJO
// ---------------------------------------------------------------------------
//
// Rojo NO acepta `[0, 12, 0, 10]` para un `UDim2`. Rechaza el build entero
// con:
//
//     Wrong type of value for property TextLabel.Position.
//     Expected UDim2, got an array of four numbers
//
// Y tampoco acepta `{ "UDim2": [0, 12, 0, 10] }` aplanado: eso lo rechaza
// antes incluso de resolver propiedades ("Failed to deserialize JSON").
// La forma buena son DOS PARES anidados, un UDim por eje:
//
//     "Position": { "UDim2": [ [0, 12], [0, 10] ] }
//
// Medido con `tools/udim-probe.js`, que prueba cada forma por separado: un
// fallo aqui no dice cual es la buena, asi que medir es mas rapido que
// adivinar.
//
// Que se este haciendo por clase y no por nombre de propiedad es
// deliberado: un mismo nombre (`Position`) es `Vector3` en un `Part` y
// `UDim2` en un `Frame`, y decidir por nombre daria `Vector3` a la interfaz.

/** Instancias cuyas propiedades geometricas son UDim/UDim2. */
const UI_2D = new Set(["Frame", "TextLabel", "TextButton", "TextBox", "ImageLabel", "ImageButton", "ScrollingFrame", "ViewportFrame"]);

/** Envuelve un array de 4 numeros como UDim2 de Rojo: DOS pares anidados. */
function asUDim2(a) {
	return { UDim2: [[a[0], a[1]], [a[2], a[3]]] };
}

/** Envuelve un array de 2 numeros como UDim de Rojo. */
function asUDim(a) {
	return { UDim: a };
}

/**
 * Recorre el arbol y convierte Position/Size en UDim2, y CornerRadius en UDim.
 *
 * @param {object} node instancia del proyecto
 */
function normalize(node) {
	if (Array.isArray(node)) {
		for (const item of node) normalize(item);
		return node;
	}
	if (!node || typeof node !== "object") return node;

	if (node.$properties && UI_2D.has(node.$className)) {
		const props = node.$properties;
		for (const key of ["Position", "Size"]) {
			if (Array.isArray(props[key])) props[key] = asUDim2(props[key]);
		}
	}

	for (const key of Object.keys(node)) {
		if (key === "$properties") continue;
		const child = node[key];
		if (Array.isArray(child)) {
			for (const c of child) normalize(c);
		} else if (child && typeof child === "object" && child.$className) {
			if (child.$properties && child.$properties.CornerRadius) {
				const cr = child.$properties.CornerRadius;
				if (Array.isArray(cr)) child.$properties.CornerRadius = asUDim(cr);
			}
			normalize(child);
		}
	}
	return node;
}

function buildHud() {
	const built = buildHudTree();
	return normalize(built);
}

module.exports = { buildHud: buildHud, THEME: THEME };
