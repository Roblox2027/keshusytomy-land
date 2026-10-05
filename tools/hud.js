// hud.js
// Construye el HUD REAL de KeshusyTomy-LanD como ARBOL DE CONTENEDORES.
//
// POR QUE SE GENERA Y NO SE ESCRIBE A MANO
// ----------------------------------------
// La UI anterior se construia dentro de `UIController.buildGui()`, o sea por
// codigo en tiempo de ejecucion. Eso hacia que el HUD no existiera en el
// SOURCE (no se podia auditar sin entrar en juego) y que cada campo nuevo
// obliga a tocar un unico archivo monolitico.
//
// Y el fallo medido en PLAY: la BOMBA vivia en un SEGUNDO `ScreenGui`
// (`TouchControls`) creado por `InputController`, con su propia cuenta de
// posicion. Dos sistemas visuales peleaban el mismo espacio y acababan
// solapados; el jugador veia un HUD desordenado y una bomba que a veces no
// aparecia. Aqui hay UN solo `ScreenGui` y la bomba es una ZONA mas.
//
// ESTRUCTURA (zonas, no coordenadas)
// ---------------------------------
//     KeshusyHUD
//     â””â”€â”€ Root                     UIScale global
//         â”œâ”€â”€ TopBar               Mundo, Nivel, HP, XP, Monedas, Gemas
//         â”œâ”€â”€ LeftPanel            Mission (compacta y plegable)
//         â”œâ”€â”€ RightPanel           Objective, ActiveBombs
//         â”œâ”€â”€ BottomBar            ContextActions + BombAction
//         â”œâ”€â”€ CenterFeedback       Notifications, DamageNumbers
//         â””â”€â”€ Overlays             Timer, BossBar, DamageVignette
//
// Cada zona se ancla a su esquina y deja que el motor la coloque. Las medidas
// de DISENO viven aqui y las medidas REALES por viewport salen de
// `Shared.Libraries.HudLayout`, que es la MISMA tabla que recorre
// `tests/shared/HudLayout.spec.lua`: si el arbol y la tabla describieran
// disposiciones distintas, el test de solape no diria la verdad.
//
// FORMATO DE LOS VALORES EN ROJO
// -------------------------------
// Rojo serializa `UDim2` como `[xEscala, xOffset, yEscala, yOffset]` y `UDim`
// como `[escala, offset]`. Se escriben como ARRAYS: es lo que produce el resto
// del generador para `Position`/`Size` de los Partes.

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

/**
 * Crea una zona: un Frame TRANSPARENTE que ocupa una region y se ancla a su
 * esquina. La zona no se pinta; la pintan sus hijos. Asi la posicion del HUD
 * se decide UNA vez (el anclaje) y no en cada panel.
 *
 * @param {string} name nombre de la zona
 * @param {number[]} anchor [x, y] AnchorPoint
 * @param {number[]} position UDim2 del ancla
 * @param {number[]} size UDim2 del tamano
 * @param {number} zIndex prioridad visual explicita
 */
function zone(name, anchor, position, size, zIndex) {
	return {
		$className: "Frame",
		$properties: {
			AnchorPoint: anchor,
			Position: position,
			Size: size,
			BackgroundTransparency: 1,
			BorderSizePixel: 0,
			ZIndex: zIndex,
		},
	};
}

/** Crea un Frame con esquinas redondeadas y borde: una tarjeta de contenido. */
function card(name, opts) {
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
			UICorner: { $className: "UICorner", $properties: { CornerRadius: [0, 10] } },
			UIStroke: {
				$className: "UIStroke",
				$properties: { Color: THEME.accent, Thickness: 1, Transparency: 0.7 },
			},
		},
	};
}

/** Texto del HUD con la tipografia de la casa (GothamBold, sin escala). */
function label(name, opts) {
	return {
		$className: "TextLabel",
		$properties: {
			BackgroundTransparency: 1,
			BorderSizePixel: 0,
			Font: "GothamBold",
			AnchorPoint: opts.anchor || [0, 0],
			Position: opts.position,
			Size: opts.size,
			Text: opts.text === undefined ? "" : opts.text,
			TextColor3: opts.tint || THEME.text,
			TextSize: opts.size2,
			TextScaled: false,
			TextXAlignment: opts.align || "Left",
			TextYAlignment: "Center",
			TextWrapped: false,
			ZIndex: opts.zIndex || 2,
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

	return {
		name: name,
		node: {
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
					// MENTIRA visual. El jugador veria la vida al maximo antes
					// de que el servidor publicase nada.
					Size: [0, 0, 1, 0],
					Position: [0, 0, 0, 0],
					ZIndex: 1,
				},
				UICorner: { $className: "UICorner", $properties: { CornerRadius: [0, 5] } },
			},
			Label: {
				$className: "TextLabel",
				$properties: {
					BackgroundTransparency: 1,
					BorderSizePixel: 0,
					Font: "GothamBold",
					Position: [0, 0, 0, 0],
					Size: [1, 0, 1, 0],
					Text: "--",
					TextColor3: THEME.text,
					TextSize: 11,
					TextScaled: false,
					TextXAlignment: "Center",
					TextYAlignment: "Center",
					TextWrapped: false,
					ZIndex: 2,
				},
			},
		},
	};
}

/**
 * Fila de recurso: simbolo, nombre y CIFRA en columnas propias.
 *
 * MEDIDO EN PLAY (el fallo que esto evita): `Caption` y `Value` compartian
 * `Position = [0, 24, 0, 0]`, o sea ocupaban EXACTAMENTE el mismo
 * rectangulo. Solo se veian bien porque uno alineaba a la izquierda y el otro
 * a la derecha; con una etiqueta larga o una cifra ancha se pisaban. Cada
 * uno mide su posicion desde el mismo sitio, asi que no pueden solaparse por
 * construccion.
 */
function statRow(name, tint, prefix, caption) {
	return {
		name: name,
		node: {
			$className: "Frame",
			$properties: {
				BackgroundTransparency: 1,
				BorderSizePixel: 0,
				Position: [0, 0, 0, 0],
				Size: [1, 0, 0, 20],
			},
			Symbol: label("Symbol", {
				position: [0, 0, 0, 0],
				size: [0, 20, 1, 0],
				text: prefix,
				tint: tint,
				size2: 15,
			}),
			Caption: label("Caption", {
				position: [0, 22, 0, 0],
				size: [1, -58, 1, 0],
				text: caption,
				tint: THEME.textDim,
				size2: 12,
			}),
			Value: label("Value", {
				position: [1, -34, 0, 0],
				size: [0, 34, 1, 0],
				text: "--",
				tint: tint,
				size2: 16,
				align: "Right",
			}),
		},
	};
}
// ---------------------------------------------------------------------------
// ZONAS
// ---------------------------------------------------------------------------
//
// Z-INDEX EXPLICITO (requisito del diseno, no un efecto del orden de creacion)
//
//   10  paneles persistentes (TopBar, LeftPanel, RightPanel)
//   20  BottomBar: acciones de contexto y la BOMBA
//   30  feedback central (avisos, numeros de dano)
//   40  overlays (temporizador, jefe, borde de dano)
//
// La bomba esta en 20, por encima de los paneles: no hay ningun caso en el
// que `Mission` u `Objective` puedan taparla, porque el orden de dibujo no
// depende de en que archivo se declaro cada cosa.
//
// MARGENES
// Los margenes son puxeles de DISENO cerca del borde (14 px). No son la
// disposicion: la disposicion la dan los `AnchorPoint` y las escalas. El
// inset del sistema (la barra superior de Roblox) lo descuenta el propio
// `ScreenGui` con `IgnoreGuiInset = false`.
const EDGE = 14;

// ---------------------------------------------------------------------------
// LA BANDA SUPERIOR
// ---------------------------------------------------------------------------
//
// POR QUE EXISTE
// --------------
// El HUD se lee de ARRIBA abajo, y todo lo que va en la FRANJA SUPERIOR
// tiene que estar en una franja, no repartido por `y = 0`: si el panel de
// misiones, el de objetivo y el temporizador se anclan todos al borde
// superior, los tres se MONTAN sobre la barra de identidad. Medido en PLAY:
// la barra de mundo/nivel quedaba tapada por el panel de misiones.
//
// La cuenta se hace UNA vez, aqui, y las zonas la consumen:
//
//     TopBar (zona)      0 .. TOP_BAND_H   <- el ancho completo, sin pintar
//     +-- Bar            EDGE, 10         <- identidad y recursos
//     +-- Timer          EDGE + 56 + 10   <- ronda y tiempo
//     LeftPanel / RightPanel  empiezan en TOP_BAND_H
//
// `TOP_BAND_H` NO lleva `UIScale`: la altura de la banda se mide en pixeles
// de PANTALLA, y las zonas laterales se posicionan en pixeles de pantalla
// tambien. Si la banda escalara, al achicarla dejaria un hueco y al
// agrandarla montaria el panel de misiones sobre la barra. El escalado va
// dentro, en `Bar` y en `Timer`, que son los que tienen contenido.
const TOP_CARD_H = 56;
const TIMER_H = 46;
const BAND_GAP = 10;
const TOP_BAND_H = EDGE + TOP_CARD_H + BAND_GAP + TIMER_H + BAND_GAP;

/** Desplazamiento vertical de las zonas laterales, en px de pantalla. */
const SIDE_TOP = TOP_BAND_H;

// ---------------------------------------------------------------------------
// TOP BAR: Mundo, Nivel, HP, XP, Monedas, Gemas
// ---------------------------------------------------------------------------
function buildTopBar() {
	// La zona ocupa la BANDA COMPLETA y no se pinta. No lleva `UIPadding` ni
	// `UIScale`: es el marco cuya altura en pixeles de pantalla es la que
	// despues respetan `LeftPanel` y `RightPanel`.
	const zoneNode = zone("TopBar", [0, 0], [0, 0, 0, 0], [1, 0, 0, TOP_BAND_H], 10);

	const cardNode = {
		$className: "Frame",
		$properties: {
			BackgroundColor3: THEME.panel,
			BackgroundTransparency: 0.2,
			BorderSizePixel: 0,
			Position: [0, EDGE, 0, 10],
			Size: [1, -EDGE * 2, 0, TOP_CARD_H],
			ZIndex: 1,
		},
		UICorner: { $className: "UICorner", $properties: { CornerRadius: [0, 12] } },
		UIStroke: {
			$className: "UIStroke",
			$properties: { Color: THEME.accent, Thickness: 1, Transparency: 0.7 },
		},
		// `UIListLayout`: los dos bloques (identidad y recursos) se separan
		// solos. Sin el, la separacion seria un offset mas que se desincroniza
		// en cuanto uno de los dos cambia de tamano.
		Layout: {
			$className: "UIListLayout",
			$properties: {
				FillDirection: "Horizontal",
				Padding: { UDim: [0, 14] },
				SortOrder: "LayoutOrder",
				VerticalAlignment: "Center",
			},
		},
		UIPadding: {
			$className: "UIPadding",
			$properties: {
				PaddingLeft: { UDim: [0, 14] },
				PaddingRight: { UDim: [0, 14] },
				PaddingTop: { UDim: [0, 8] },
				PaddingBottom: { UDim: [0, 8] },
			},
		},
	};

	// -- Bloque de identidad: donde estoy, que soy, cuanta vida y cuanto XP.
	const playerInfo = {
		$className: "Frame",
		$properties: {
			BackgroundTransparency: 1,
			BorderSizePixel: 0,
			Size: [0, 240, 1, 0],
			LayoutOrder: 1,
			ZIndex: 1,
		},
		World: label("World", {
			position: [0, 0, 0, 0],
			size: [1, -96, 0, 18],
			text: "MUNDO: Lobby",
			tint: THEME.crystal,
			size2: 14,
		}),
		Level: label("Level", {
			position: [0, 0, 0, 20],
			size: [1, -96, 0, 18],
			text: "LV 1",
			tint: THEME.level,
			size2: 14,
		}),
		HPBar: bar("HPBar", {
			position: [0, 0, 1, -18],
			size: [1, -104, 0, 14],
			tint: THEME.hp,
			height: 14,
		}).node,
		XPBar: bar("XPBar", {
			position: [0, 0, 1, -34],
			size: [1, -104, 0, 10],
			tint: THEME.xp,
			height: 10,
		}).node,
	};
	cardNode.PlayerInfo = playerInfo;

	// -- Bloque de recursos: se gastan en cosas distintas.
	const currency = {
		$className: "Frame",
		$properties: {
			BackgroundTransparency: 1,
			BorderSizePixel: 0,
			Size: [0, 132, 1, 0],
			LayoutOrder: 2,
			ZIndex: 1,
		},
		Coins: statRow("Coins", THEME.coin, "$", "MONEDAS").node,
		Gems: statRow("Gems", THEME.gem, "*", "GEMAS").node,
	};
	currency.Coins.$properties.Position = [0, 0, 0.5, -22];
	currency.Coins.$properties.Size = [1, 0, 0, 20];
	currency.Gems.$properties.Position = [0, 0, 0.5, 2];
	currency.Gems.$properties.Size = [1, 0, 0, 20];
	cardNode.Currency = currency;

	zoneNode.Bar = cardNode;
	// `UIScale` va en el CONTENIDO (`Bar`), NO en la zona. Escalar la zona
	// encogia su propio rectangulo, asi que una barra de ancho completo se
	// quedaba en 890 de 1113 px y el lado derecho se quedaba sin HUD.
	// MEDIDO en PLAY: `TopBar` ocupaba 890 px de 1113 por un `UIScale` de 0.80
	// en la zona. La zona decide DONDE esta algo; la escala decide COMO de
	// grande se ve. Son dos cosas distintas y no pueden ser la misma instancia.
	cardNode.Scale = { $className: "UIScale", $properties: { Scale: 1 } };
	return zoneNode;
}
// ---------------------------------------------------------------------------
// PANEL IZQUIERDO: Mission
// ---------------------------------------------------------------------------
//
// Mission es SECUNDARIA: una tarjeta pequena, plegable, anclada arriba a la
// izquierda. No es una ventana permanente: un panel de misiones grande en el
// centro compite con el gameplay y con la bomba.
function buildLeftPanel() {
	// `SIDE_TOP`, no `0`: anclar el panel al borde superior lo montaba sobre
	// la barra de identidad. Medido en PLAY: "MUNDO: Lobby" quedaba debajo
	// del panel de misiones.
	const node = zone("LeftPanel", [0, 0], [0, EDGE, 0, SIDE_TOP], [0, 260, 0, 96], 10);
	// La escala va en la TARJETA, no en la zona: ver la nota de `buildTopBar`.
	// Escalar la zona encogia el panel y lo separaba de la esquina, con lo que
	// el ancho real dejaba de ser el que el generador declara.

	const missionCard = card("Mission", {
		position: [0, 0, 0, 0],
		size: [1, 0, 1, 0],
	});
	missionCard.node.$properties.ZIndex = 1;
	// Escala en la TARJETA, no en la zona: ver la nota de `buildTopBar`.
	missionCard.node.Scale = { $className: "UIScale", $properties: { Scale: 1 } };

	// Cabecera plegable. Sin esto el jugador no puede quitarse de delante lo
	// que no le importa en ese momento, y un HUD que no se aparta estorba.
	const toggle = {
		$className: "TextButton",
		$properties: {
			BackgroundTransparency: 1,
			BorderSizePixel: 0,
			Font: "GothamBold",
			Position: [0, 0, 0, 0],
			Size: [1, 0, 0, 22],
			Text: "MISIONES  -",
			TextColor3: THEME.textDim,
			TextSize: 11,
			TextScaled: false,
			TextXAlignment: "Left",
			TextYAlignment: "Center",
			TextWrapped: false,
			AutoButtonColor: false,
			ZIndex: 2,
		},
	};
	missionCard.node.Toggle = toggle;

	// El CUERPO se separa de la cabecera para que plegarla sea cambiar
	// `Visible` de un solo hijo, y no reconstruir el panel.
	const body = {
		$className: "Frame",
		$properties: {
			BackgroundTransparency: 1,
			BorderSizePixel: 0,
			Position: [0, 12, 0, 24],
			Size: [1, -24, 1, -32],
			ZIndex: 1,
		},
		Text: label("Text", {
			position: [0, 0, 0, 0],
			size: [1, 0, 1, 0],
			text: "Misiones: --",
			tint: THEME.text,
			size2: 13,
		}),
	};
	missionCard.node.Body = body;
	node.Mission = missionCard.node;
	return node;
}

// ---------------------------------------------------------------------------
// PANEL DERECHO: Objective + ActiveBombs
// ---------------------------------------------------------------------------
//
// Objective es COMPACTO y va arriba a la derecha, con una sola linea de
// texto: "que hay que hacer ahora". No es una ventana: cabe en dos lineas.
function buildRightPanel() {
	// Igual que `LeftPanel`: por debajo de la banda, no sobre ella.
	const node = zone("RightPanel", [1, 0], [1, -EDGE, 0, SIDE_TOP], [0, 260, 0, 108], 10);
	// Escala en la TARJETA, no en la zona: ver la nota de `buildTopBar`.

	const objective = card("Objective", {
		position: [0, 0, 0, 0],
		size: [1, 0, 0, 52],
	});
	objective.node.$properties.ZIndex = 1;
	// Escala en la TARJETA, no en la zona: ver la nota de `buildTopBar`.
	objective.node.Scale = { $className: "UIScale", $properties: { Scale: 1 } };
	objective.node.Title = label("Title", {
		position: [0, 12, 0, 4],
		size: [1, -24, 0, 14],
		text: "OBJETIVO",
		tint: THEME.textDim,
		size2: 11,
	});
	objective.node.Text = label("Text", {
		position: [0, 12, 0, 22],
		size: [1, -24, 0, 22],
		text: "--",
		tint: THEME.text,
		size2: 14,
	});
	node.Objective = objective.node;

	// Bombas VIVAS del jugador. Se oculta cuando no hay ninguna: un "x0"
	// permanente en pantalla es ruido que el jugador aprende a no mirar.
	const activeBombs = card("ActiveBombs", {
		position: [0, 0, 0, 60],
		size: [1, 0, 0, 40],
	});
	activeBombs.node.$properties.ZIndex = 1;
	activeBombs.node.$properties.Visible = false;
	activeBombs.node.Symbol = label("Symbol", {
		position: [0, 10, 0, 8],
		size: [0, 22, 0, 24],
		text: "B",
		tint: THEME.bomb,
		size2: 18,
	});
	activeBombs.node.Caption = label("Caption", {
		position: [0, 34, 0, 4],
		size: [1, -46, 0, 12],
		text: "ACTIVAS",
		tint: THEME.textDim,
		size2: 10,
	});
	activeBombs.node.Value = label("Value", {
		position: [0, 34, 0, 16],
		size: [1, -46, 0, 20],
		text: "x0",
		tint: THEME.bomb,
		size2: 20,
	});
	node.ActiveBombs = activeBombs.node;
	return node;
}

// ---------------------------------------------------------------------------
// BARRA INFERIOR: ContextActions + BombAction
// ---------------------------------------------------------------------------
//
// La BOMBA es una accion PRIMARIA y por eso tiene ZONA PROPIA, abajo al
// centro, con su propio `ZIndex` (20) por encima de los paneles.
//
// El marco (`BombAction`) se declara AQUI, en el SOURCE, y no lo crea
// `InputController` en otro `ScreenGui`: asi el arbol se puede auditar sin
// entrar en juego y no hay dos sistemas de interfaz compitiendo.
//
// Las PIEZAS dibujadas (cuerpo, franja, tapa, mecha, chispa) las pinta
// `InputController` dentro de `BombVisual` usando `BombButtonRules.Geometry`:
// la geometria vive en UN solo sitio, que es el modulo que la prueba.
function buildBottomBar() {
	// `Position` y = `1, -EDGE`, NO `1, 0`.
	//
	// Con `AnchorPoint = (0,1)` la posicion es el BORDE INFERIOR IZQUIERDO del
	// marco: con `1, 0` la zona empezaba en el borde inferior de la pantalla y
	// crecia HACIA ABAJO, es decir, entera fuera de la pantalla. Medido en
	// PLAY: la bomba no aparecia donde debia y el marco de contexto tampoco.
	const node = zone("BottomBar", [0, 1], [0, EDGE, 1, -EDGE], [1, -EDGE * 2, 0, 168], 20);
	// SIN `UIScale` en la zona. Es la que se ancla a los DOS bordes de ancho con
	// `Size = (1, -28)`, asi que escalarla encogia el ancho completo y la bomba,
	// que se ancla al CENTRO de esta zona, se desplazaba con el: MEDIDO en PLAY
	// la bomba quedaba en `x = 365` en vez del centro `556`. La escala va en
	// `BombAction` y en `ContextActions`, que son los que tienen contenido.

	// -- Acciones de contexto: lo que el jugador tiene AHORA (bombas, poder,
	//    powerups). Va al lado de la bomba, nunca encima.
	const context = zone("ContextActions", [0, 1], [0, 0, 1, 0], [0, 300, 0, 96], 20);
	// Escala en el CONTENIDO de la zona, no en la zona: ver la nota anterior.
	context.Scale = { $className: "UIScale", $properties: { Scale: 1 } };

	const bombStats = card("BombStats", {
		position: [0, 0, 0, 0],
		size: [1, 0, 0, 64],
	});
	bombStats.node.$properties.ZIndex = 1;
	bombStats.node.Bombs = statRow("Bombs", THEME.bomb, "B", "BOMBAS").node;
	bombStats.node.Bombs.$properties.Position = [0, 8, 0, 6];
	bombStats.node.Bombs.$properties.Size = [1, -16, 0, 20];
	bombStats.node.Power = statRow("Power", THEME.accent, "P", "PODER").node;
	bombStats.node.Power.$properties.Position = [0, 8, 0, 34];
	bombStats.node.Power.$properties.Size = [1, -16, 0, 20];
	context.BombStats = bombStats.node;

	// Powerups activos. Oculto cuando no hay ninguno.
	const powerupRow = card("PowerupRow", {
		position: [0, 0, 0, 70],
		size: [1, 0, 0, 26],
	});
	powerupRow.node.$properties.ZIndex = 1;
	powerupRow.node.$properties.Visible = false;
	powerupRow.node.Text = label("Text", {
		position: [0, 10, 0, 0],
		size: [1, -20, 1, 0],
		text: "",
		tint: THEME.crystal,
		size2: 13,
	});
	context.PowerupRow = powerupRow.node;

	node.ContextActions = context;

	// -- La BOMBA.
	const bombAction = {
		$className: "TextButton",
		$properties: {
			AnchorPoint: [0.5, 1],
			Position: [0.5, 0, 1, 0],
			Size: [0, 152, 0, 152],
			BackgroundTransparency: 1,
			BorderSizePixel: 0,
			Text: "",
			AutoButtonColor: false,
			ZIndex: 20,
		},
	};

	// Escala en la BOMBA, no en la zona: `BombAction` se ancla al centro de la
	// pantalla, asi que el `UIScale` tiene que pivotar sobre el, no sobre la
	// barra. Escalar la barra movia la bomba del centro (medido: `x = 365` de
	// 556) y la separaba del resto del HUD.
	bombAction.Scale = { $className: "UIScale", $properties: { Scale: 1 } };

	// Marco del boton: un disco oscuro detras de la bomba. Da la sensacion de
	// "control" sin necesidad de un rectangulo opaco que tape el juego.
	//
	// MEDIDO EN PLAY (`.ai/reports/shot-hud-bomb.png`): con `0.45` de
	// transparencia el disco salia `(120,122,125)` sobre el suelo claro, o sea
	// un halo GRIS lavado en vez de un disco oscuro. A `0.25` sale `(71,73,77)`
	// y la bomba se recorta contra cualquier mapa.
	//
	// Tamano 104 = `BombButtonRules.Size`: las piezas se dibujan a escala 1.0 y
	// el marco deja libre la banda del cooldown y el pie de texto.
	bombAction.Base = {
		$className: "Frame",
		$properties: {
			AnchorPoint: [0.5, 0.5],
			Position: [0.5, 0, 0.5, -24],
			Size: [0, 104, 0, 104],
			BackgroundColor3: color(10, 12, 18),
			BackgroundTransparency: 0.25,
			BorderSizePixel: 0,
			ZIndex: 19,
		},
		UICorner: { $className: "UICorner", $properties: { CornerRadius: [1, 0] } },
	};

	// Contenedor de las piezas dibujadas. Vacio en el SOURCE a proposito:
	// `InputController` lo rellena con `BombButtonRules.Geometry`, que es la
	// unica fuente de la forma de la bomba.
	bombAction.BombVisual = {
		$className: "Frame",
		$properties: {
			AnchorPoint: [0.5, 0.5],
			Position: [0.5, 0, 0.5, -24],
			Size: [0, 104, 0, 104],
			BackgroundTransparency: 1,
			BorderSizePixel: 0,
			ZIndex: 20,
		},
	};

	// Barra de enfriamiento: se vacia de izquierda a derecha. Es la unica
	// forma de ver el progreso SIN leer un numero.
	// `UDim2` aqui es [xScale, xOffset, yScale, yOffset]: la Y de esta barra es
	// un OFFSET desde el borde SUPERIOR del boton (`yScale = 0`), no la mitad.
	// MEDIDO: con `yScale = 0.5` la barra caia en `0.5 * 152 + 108 = 184`,
	// o sea 32 px POR DEBAJO de la caja del boton.
	bombAction.Cooldown = {
		$className: "Frame",
		$properties: {
			AnchorPoint: [0.5, 0],
			Position: [0.5, 0, 0, 108],
			Size: [0, 88, 0, 8],
			BackgroundColor3: color(8, 10, 16),
			BackgroundTransparency: 0.25,
			BorderSizePixel: 0,
			ZIndex: 20,
		},
		UICorner: { $className: "UICorner", $properties: { CornerRadius: [0, 4] } },
		Fill: {
			$className: "Frame",
			$properties: {
				BackgroundColor3: THEME.bomb,
				BorderSizePixel: 0,
				Size: [1, 0, 1, 0],
				Position: [0, 0, 0, 0],
				ZIndex: 21,
			},
			UICorner: { $className: "UICorner", $properties: { CornerRadius: [0, 4] } },
		},
	};

	// Tarjeta del texto de apoyo: "LISTO", "3.2", "FUERA DE LA ARENA", "F".
	//
	// MEDIDO EN PLAY, y este es el fallo que la foto destapo: las dos
	// etiquetas iban SIN fondo (`BackgroundTransparency = 1`) y directamente
	// sobre el suelo del mundo. Medido contra el suelo claro `(255,255,255)`:
	//
	//   State    texto (232,236,244)  ->  CR 1.18   (WCAG AA pide 4.5)
	//   KeyHint  texto (176,188,214)  ->  CR 1.91
	//
	// O sea "LISTO" NO se leia. El texto de apoyo no puede depender de lo que
	// haya debajo: por eso lleva su propia tarjeta oscura, como los paneles.
	//
	// Va DESPUES de la bomba (z = 21) para que la mecha no lo tape, y las dos
	// etiquetas se posicionan ENCIMA de ella. MEDIDO: antes `State` ocupaba el
	// rango de diseno 146..164 sobre una caja que acaba en 152, o sea se salia
	// 12 px por debajo del boton y quedaba pegada al borde de la pantalla.
	const caption = card("Caption", {
		position: [0.5, 0, 0, 118],
		size: [0, 132, 0, 32],
	});
	// `card` ancla arriba a la izquierda; esta se ancla por su borde SUPERIOR
	// para que el marco quede pegado al pie del boton sin parches de offsets.
	caption.node.$properties.AnchorPoint = [0.5, 0];
	caption.node.$properties.BackgroundTransparency = 0.15;
	caption.node.$properties.ZIndex = 21;
	bombAction.Caption = caption.node;

	// Estado: "LISTO", "3.2", "FUERA DE LA ARENA". Es el texto de APOYO; la
	// bomba dibujada es lo que se lee sin leer.
	//
	// Siguen siendo HIJAS DIRECTAS de `BombAction` a proposito: el
	// `InputController` las busca con `FindFirstChild("State")`, y meterlas
	// dentro de `Caption` las haria desaparecer del boton. El anclaje es
	// relativo a la tarjeta, no al mapa.
	bombAction.State = label("State", {
		position: [0.5, -66, 0, 134],
		size: [0, 132, 0, 14],
		text: "LISTO",
		tint: THEME.text,
		size2: 12,
		align: "Center",
		zIndex: 22,
	});

	// Atajo de teclado. Pequeno y ARRIBA del estado, dentro de la misma
	// tarjeta: la bomba manda, la tecla apoya.
	bombAction.KeyHint = label("KeyHint", {
		position: [0.5, -66, 0, 119],
		size: [0, 132, 0, 13],
		text: "F",
		tint: THEME.textDim,
		size2: 11,
		align: "Center",
		zIndex: 22,
	});

	node.BombAction = bombAction;
	return node;
}

// ---------------------------------------------------------------------------
// FEEDBACK CENTRAL: avisos y numeros de dano
// ---------------------------------------------------------------------------
//
// Aqui NO hay paneles permanentes. Solo overlays que aparecen y se van: los
// numeros de dano flotan sobre el impacto y los avisos se autodestruyen. El
// centro de la pantalla pertenece al gameplay.
function buildCenterFeedback() {
	const node = zone("CenterFeedback", [0, 0], [0, 0, 0, 0], [1, 0, 1, 0], 30);
	// SIN `UIScale`: es una zona de PANTALLA COMPLETA (`Size = (1,1)`) y
	// escalarla la encogia a 890x414 de 1113x518, con lo que los numeros de
	// dano de la derecha de la pantalla se perdian. La escala va en
	// `Notifications`, que es lo que tiene contenido de tamano de diseno.

	const notices = zone("Notifications", [0.5, 0], [0.5, 0, 0.24, 0], [0, 440, 0, 168], 30);
	// Escala en los AVISOS, no en la zona de pantalla completa: son 440x168 de
	// diseno y son lo unico que tiene que encogerse en pantallas pequenas.
	notices.Scale = { $className: "UIScale", $properties: { Scale: 1 } };
	// `UIListLayout`: los avisos se apilan solos. Antes cada uno calculaba su
	// `Position` con el numero de los que habia, y dos avisos simultaneos se
	// montaban.
	notices.List = {
		$className: "UIListLayout",
		$properties: {
			FillDirection: "Vertical",
			Padding: { UDim: [0, 4] },
			SortOrder: "LayoutOrder",
			HorizontalAlignment: "Center",
			VerticalAlignment: "Top",
		},
	};
	node.Notifications = notices;

	// Contenedor de numeros de dano. Ocupa toda la pantalla porque cada
	// numero se coloca en el punto del impacto.
	const numbers = zone("DamageNumbers", [0, 0], [0, 0, 0, 0], [1, 0, 1, 0], 31);
	node.DamageNumbers = numbers;

	return node;
}

// ---------------------------------------------------------------------------
// OVERLAYS: temporizador, jefe y borde de dano
// ---------------------------------------------------------------------------
function buildOverlays() {
	const node = zone("Overlays", [0, 0], [0, 0, 0, 0], [1, 0, 1, 0], 40);

	// El temporizador va DENTRO de la banda superior, justo debajo de la barra
	// de identidad. Antes se anclaba a `y = 0` y se montaba ENCIMA de ella:
	// "RONDA 0 / 00:00" caia sobre el nombre del mundo.
	const timer = card("Timer", {
		position: [0.5, 0, 0, 10 + TOP_CARD_H + BAND_GAP],
		size: [0, 180, 0, TIMER_H],
	});
	timer.node.$properties.AnchorPoint = [0.5, 0];
	timer.node.$properties.ZIndex = 1;
	timer.node.Round = label("Round", {
		position: [0, 8, 0, 4],
		size: [1, -16, 0, 16],
		text: "RONDA 0",
		tint: THEME.textDim,
		size2: 11,
		align: "Center",
	});
	timer.node.Time = label("Time", {
		position: [0, 8, 0, 20],
		size: [1, -16, 0, 22],
		text: "--:--",
		tint: THEME.ember,
		size2: 18,
		align: "Center",
	});
	node.Timer = timer.node;

	// Barra de jefe: OCULTA por defecto. Una barra de jefe vacia y permanente
	// en pantalla ensena al jugador a no mirarla, y el dia que aparezca de
	// verdad ya la esta ignorando.
	const bossBar = card("BossBar", {
		position: [0.5, 0, 0, TOP_BAND_H + BAND_GAP],
		size: [0, 440, 0, 42],
	});
	bossBar.node.$properties.AnchorPoint = [0.5, 0];
	bossBar.node.$properties.ZIndex = 1;
	bossBar.node.$properties.Visible = false;
	bossBar.node.Name = label("Name", {
		position: [0, 10, 0, 2],
		size: [1, -20, 0, 16],
		text: "",
		tint: THEME.hp,
		size2: 13,
		align: "Center",
	});
	bossBar.node.Bar = bar("Bar", {
		position: [0, 10, 0, 22],
		size: [1, -20, 0, 16],
		tint: THEME.hp,
	}).node;
	node.BossBar = bossBar.node;

	// Borde ROJO al recibir dano. Solo el BORDE: oscurecer toda la pantalla es
	// un castigo, no un aviso, y tapa justo el combate que hay que ver.
	const vignette = zone("DamageVignette", [0, 0], [0, 0, 0, 0], [1, 0, 1, 0], 41);
	vignette.UIStroke = {
		$className: "UIStroke",
		$properties: {
			Color: color(255, 40, 60),
			Thickness: 26,
			Transparency: 1,
			ApplyStrokeMode: "Border",
		},
	};
	node.DamageVignette = vignette;

	return node;
}

// ---------------------------------------------------------------------------
// MONTAJE DEL HUD
// ---------------------------------------------------------------------------
//
// UN `ScreenGui` con seis ZONAS. El orden de las claves es el orden de
// lectura del jugador: identidad arriba, contexto a los lados, la BOMBA abajo
// al centro, feedback encima de todo.
//
// `ZIndexBehavior = "Sibling"` con `ZIndex` EXPLICITO por zona: el orden de
// dibujo no depende de en que orden se declararon las cosas.
function buildHudTree() {
	const root = {
		$className: "Frame",
		$properties: {
			// Ocupa TODA la pantalla y no se pinta: es el marco comun de las
			// zonas. Si no existiera, cada zona seria hermana del `ScreenGui` y
			// el HUD no tendria una raiz de la que hablar.
			Position: [0, 0, 0, 0],
			Size: [1, 0, 1, 0],
			BackgroundTransparency: 1,
			BorderSizePixel: 0,
			ZIndex: 1,
		},
		TopBar: buildTopBar(),
		LeftPanel: buildLeftPanel(),
		RightPanel: buildRightPanel(),
		BottomBar: buildBottomBar(),
		CenterFeedback: buildCenterFeedback(),
		Overlays: buildOverlays(),
	};

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
			Root: root,
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
// Y tampoco acepta `{ "UDim2": [0, 12, 0, 10] }` aplanado. La forma buena son
// DOS PARES anidados, un UDim por eje:
//
//     "Position": { "UDim2": [ [0, 12], [0, 10] ] }
//
// Que se haga por clase y no por nombre de propiedad es deliberado: un mismo
// nombre (`Position`) es `Vector3` en un `Part` y `UDim2` en un `Frame`, y
// decidir por nombre daria `Vector3` a la interfaz.

/** Instancias cuyas propiedades geometricas son UDim/UDim2. */
const UI_2D = new Set([
	"Frame", "TextLabel", "TextButton", "TextBox", "ImageLabel", "ImageButton",
	"ScrollingFrame", "ViewportFrame",
]);

/** Envuelve un array de 4 numeros como UDim2 de Rojo: DOS pares anidados. */
function asUDim2(a) {
	return { UDim2: [[a[0], a[1]], [a[2], a[3]]] };
}

/** Envuelve un array de 2 numeros como UDim de Rojo. */
function asUDim(a) {
	return { UDim: a };
}

/**
 * Recorre el arbol y convierte Position/Size en UDim2, CornerRadius en UDim y
 * AnchorPoint en Vector2.
 *
 * @param {object} node instancia del proyecto
 */
function normalize(node) {
	if (Array.isArray(node)) {
		for (const item of node) normalize(item);
		return node;
	}
	if (!node || typeof node !== "object") return node;

	if (UI_2D.has(node.$className)) {
		const props = node.$properties;
		if (props) {
			for (const key of ["Position", "Size"]) {
				if (Array.isArray(props[key])) props[key] = asUDim2(props[key]);
			}
			// `AnchorPoint` es un Vector2: Rojo acepta un array de DOS numeros tal cual.
			if (Array.isArray(props.AnchorPoint)) props.AnchorPoint = props.AnchorPoint.slice();
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
	return normalize(buildHudTree());
}

module.exports = { buildHud: buildHud, THEME: THEME };
