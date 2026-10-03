// worlds.js
// Constructor de MUNDOS JUGABLES para `generate-project.js`.
//
// POR QUE UN ARCHIVO APARTE
// -------------------------
// `generate-project.js` construye el lobby y el Forest y ya supera las 1500
// lineas. Los otros cuatro mundos (Desert, Ice, Volcano, Cyber) son
// geometria nueva con el MISMO contrato de nombres, asi que viven aqui como
// un modulo con una funcion de decoracion por mundo. El generador principal
// solo los llama.
//
// EL CONTRATO QUE NO SE TOCA
// --------------------------
// Cada mundo cuelga de `Workspace.Worlds.<Id>` y contiene:
//
//   ArenaFloor, ArenaCenter, ArenaNorth/South/East/West   marcadores
//   ArenaWall_N/S/E/W                                     muro perimetral
//   Blocks/            partes `Block_*` (destruibles por bomba)
//   CentralStructure/ Terrain/ Decoration/ Border/ Keshusy/
//   SpawnPoint_<Id>  Hazards/ MonsterSpawns/ PowerupSpawns/
//   BossSpawn_<Id>  Exit_<Id>
//
// Los servicios (`MatchService`, `VisualService`, `DestructionService`)
// resuelven esas rutas por NOMBRE. Cambiar un nombre rompe el juego, asi que
// este modulo no inventa nombres nuevos.

const v3 = (x, y, z) => [x, y, z];
const color = (r, g, b) => [r / 255, g / 255, b / 255];

// Ruido determinista, identico al de generate-project.js.
//
// Se replica en vez de importarse porque el generador lo declara con
// `function` en su propio ambito y no exporta nada: importarlo exigiria
// refactorizar el generador entero. La formula es de Wang, es corta y es
// estable, que es lo unico que importa: el mapa tiene que ser reproducible
// byte a byte entre builds.
function hash01(seed, salt) {
let h = (seed * 374761393 + (salt || 0) * 668265263) | 0;
h = (h ^ (h >>> 13)) * 1274126177;
h = h ^ (h >>> 16);
return ((h >>> 0) % 100000) / 100000;
}

function vary(seed, salt, min, max) {
return min + hash01(seed, salt) * (max - min);
}

/**
 * Paletas de los cuatro mundos.
 *
 * Cada una tiene los MISMOS roles que la de Forest (suelo, estructura,
 * acento, peligro, energia Keshusy) para que el constructor de arena pueda
 * escribirse una sola vez. Cambiar estos valores cambia la identidad visual
 * entera del mundo sin tocar una linea de logica.
 */
const PALETTES = {
Desert: {
ground: [206, 172, 112],
groundAlt: [188, 150, 96],
structure: [214, 190, 148],
structureDark: [162, 132, 92],
accent: [255, 168, 66],
hazard: [232, 96, 48],
energy: [255, 206, 120],
floorMaterial: "Sand",
structureMaterial: "Sandstone",
},
Ice: {
ground: [222, 236, 246],
groundAlt: [188, 210, 230],
structure: [198, 224, 240],
structureDark: [136, 170, 198],
accent: [122, 214, 245],
hazard: [86, 176, 232],
energy: [178, 240, 255],
floorMaterial: "Snow",
structureMaterial: "Ice",
},
Volcano: {
ground: [64, 52, 52],
groundAlt: [82, 60, 56],
structure: [58, 48, 50],
structureDark: [34, 28, 30],
accent: [255, 132, 44],
hazard: [255, 78, 26],
energy: [255, 196, 92],
floorMaterial: "Slate",
structureMaterial: "Basalt",
},
Cyber: {
ground: [46, 52, 78],
groundAlt: [38, 44, 68],
structure: [58, 66, 96],
structureDark: [30, 34, 54],
accent: [86, 236, 240],
hazard: [190, 108, 255],
energy: [206, 168, 255],
floorMaterial: "Slate",
structureMaterial: "Metal",
},
};

// ------------------------------------------------ DECORACION POR MUNDO
//
// Cada mundo tiene la SUYA, y cambia la FORMA: cactus columnares en Desert,
// agujas de hielo en Ice, torres de basalto humeantes en Volcano, pilonas y
// hologramas en Cyber. Es lo que impide que los cinco se lean como el mismo
// sitio con otro color, que es exactamente lo que la especificacion prohibe.
//
// Todas reciben el mismo contexto y empujan en `deco` (interior), `border`
// (fuera del muro) y `keshusy` (energia). Ninguna crea colision.

/** BOOM DESERT: dunas, cactus y ruinas de arenisca. */
function decorateDesert(e) {
const { cx, cz, half, palette: P, deco, border, keshusy, seedBase, vary: vr } = e;
const GREEN = [104, 142, 78];

// Dunas: esferas achatadas y muy anchas. La silueta redondeada es lo
// que hace que el suelo no lea como una losa plana.
for (let i = 0; i < 14; i++) {
const a = vr(i, 601 + seedBase, 0, Math.PI * 2);
const r = vr(i, 602 + seedBase, half * 0.3, half * 0.9);
const h = vr(i, 603 + seedBase, 2.5, 6);
deco.push(e.decor("Dune_" + i, {
position: [cx + Math.cos(a) * r, h * 0.35, cz + Math.sin(a) * r],
size: [vr(i, 604 + seedBase, 26, 48), h, vr(i, 605 + seedBase, 22, 40)],
shape: "Ball",
material: "Sand",
color: P.groundAlt,
}));
}

// Cactus: tronco columnar + dos brazos. Inconfundibles a distancia.
for (let i = 0; i < 22; i++) {
const a = vr(i, 611 + seedBase, 0, Math.PI * 2);
const r = vr(i, 612 + seedBase, half * 0.25, half * 0.85);
const x = cx + Math.cos(a) * r;
const z = cz + Math.sin(a) * r;
const h = vr(i, 613 + seedBase, 6, 12);

deco.push(e.decor("Cactus_" + i, {
position: [x, h / 2, z], size: [1.6, h, 1.6],
shape: "Cylinder", material: "Grass", color: GREEN,
}));
deco.push(e.decor("Cactus_ArmL_" + i, {
position: [x - 1.6, h * 0.62, z], size: [3.4, 1.3, 1.3],
shape: "Cylinder", material: "Grass", color: GREEN,
orientation: [0, 0, 90],
}));
deco.push(e.decor("Cactus_ArmR_" + i, {
position: [x + 1.5, h * 0.44, z], size: [3, 1.2, 1.2],
shape: "Cylinder", material: "Grass", color: GREEN,
orientation: [0, 0, 90],
}));
}

// Ruinas: columnas con capitel alrededor del perimeter. Dan un
// landmark y un motivo para construir el muro en vez de levantarlo
// plano.
for (let side = 0; side < 4; side++) {
for (let i = 0; i < 6; i++) {
const t = -half + 12 + i * ((half * 2 - 24) / 5);
const along = side % 2 === 0;
const sign = side < 2 ? -1 : 1;
const x = along ? cx + t : cx + (half - 8) * sign;
const z = along ? cz + (half - 8) * sign : cz + t;
const h = vr(i, 621 + side + seedBase, 8, 18);

deco.push(e.decor("Ruin_Column_" + side + "_" + i, {
position: [x, h / 2, z], size: [3, h, 3],
shape: "Cylinder", material: P.structureMaterial, color: P.structure,
}));
deco.push(e.decor("Ruin_Cap_" + side + "_" + i, {
position: [x, h + 0.6, z], size: [4.4, 1.2, 4.4],
shape: "Cylinder", material: P.structureMaterial, color: P.structureDark,
}));
}
}

// Borde: mesetas que cierran el horizonte del mundo.
for (let side = 0; side < 4; side++) {
for (let i = 0; i < 14; i++) {
const t = -half + 6 + i * ((half * 2 - 12) / 13);
const along = side % 2 === 0;
const sign = side < 2 ? -1 : 1;
const out = half + vr(i, 631 + side + seedBase, 4, 18);
const h = vr(i, 641 + side + seedBase, 12, 28);
border.push(e.decor("Border_Mesa_" + side + "_" + i, {
position: [along ? cx + t : cx + out * sign, h / 2 - 2, along ? cz + out * sign : cz + t],
size: [vr(i, 651 + side + seedBase, 20, 36), h, vr(i, 661 + side + seedBase, 18, 32)],
shape: "Ball",
material: "Sand",
color: P.structureDark,
}));
}
}

// Sol de energia: el acento calido del mundo, sobre el relicario.
keshusy.push(e.decor("Sun_Core_Desert", {
position: [cx, 34, cz], size: [9, 9, 9], shape: "Ball",
color: P.accent, transparency: 0.2,
}));
for (let i = 0; i < 8; i++) {
const a = (i / 8) * Math.PI * 2;
keshusy.push(e.decor("Sun_Ray_" + i, {
position: [cx + Math.cos(a) * 9, 34, cz + Math.sin(a) * 9],
size: [3, 9, 1], color: P.energy,
orientation: [0, Math.round((a * 180) / Math.PI), 0],
}));
}
}

/** FROZEN TOMY: agujas de hielo, arcos congelados y ventisca. */
function decorateIce(e) {
const { cx, cz, half, palette: P, deco, border, keshusy, seedBase, vary: vr, hash01: h01 } = e;

// Agujas de hielo: prismas inclinados, el motivo visual del mundo.
for (let i = 0; i < 40; i++) {
const a = vr(i, 701 + seedBase, 0, Math.PI * 2);
const r = vr(i, 702 + seedBase, half * 0.2, half * 0.92);
const h = vr(i, 703 + seedBase, 7, 22);
deco.push(e.decor("IceSpire_" + i, {
position: [cx + Math.cos(a) * r, h / 2, cz + Math.sin(a) * r],
size: [vr(i, 704 + seedBase, 2, 5), h, vr(i, 705 + seedBase, 2, 5)],
shape: "Cylinder",
material: "Ice",
color: h01(i, 706 + seedBase) > 0.5 ? P.structure : P.structureDark,
orientation: [
Math.round(vr(i, 707 + seedBase, -16, 16)),
Math.round(vr(i, 708 + seedBase, 0, 360)),
Math.round(vr(i, 709 + seedBase, -16, 16)),
],
}));
}

// Arcos de hielo: dos agujas con una losa encima.
for (let i = 0; i < 6; i++) {
const a = (i / 6) * Math.PI * 2 + 0.3;
const r = half * 0.7;
const x = cx + Math.cos(a) * r;
const z = cz + Math.sin(a) * r;

deco.push(e.decor("IceArch_L_" + i, { position: [x - 4, 7, z], size: [2.4, 14, 2.4], shape: "Cylinder", material: "Ice", color: P.structure }));
deco.push(e.decor("IceArch_R_" + i, { position: [x + 4, 7, z], size: [2.4, 14, 2.4], shape: "Cylinder", material: "Ice", color: P.structure }));
deco.push(e.decor("IceArch_Top_" + i, { position: [x, 14.6, z], size: [11, 1.4, 3], material: "Ice", color: P.structureDark }));
}

// Nieve acumulada: manchas planas que rompen el blanco uniforme.
for (let i = 0; i < 40; i++) {
const a = vr(i, 721 + seedBase, 0, Math.PI * 2);
const r = vr(i, 722 + seedBase, 12, half * 0.95);
deco.push(e.decor("SnowDrift_" + i, {
position: [cx + Math.cos(a) * r, 0.12, cz + Math.sin(a) * r],
size: [vr(i, 723 + seedBase, 10, 26), 0.24, vr(i, 724 + seedBase, 10, 22)],
shape: "Ball",
material: "Snow",
color: P.ground,
}));
}

// Borde: montanas heladas que cierran el mundo.
for (let side = 0; side < 4; side++) {
for (let i = 0; i < 14; i++) {
const t = -half + 6 + i * ((half * 2 - 12) / 13);
const along = side % 2 === 0;
const sign = side < 2 ? -1 : 1;
const out = half + vr(i, 731 + side + seedBase, 4, 16);
const h = vr(i, 741 + side + seedBase, 16, 34);
border.push(e.decor("Border_Mountain_" + side + "_" + i, {
position: [along ? cx + t : cx + out * sign, h / 2 - 2, along ? cz + out * sign : cz + t],
size: [vr(i, 751 + side + seedBase, 24, 44), h, vr(i, 761 + side + seedBase, 24, 40)],
shape: "Ball",
material: "Ice",
color: i % 2 === 0 ? P.structureDark : P.structure,
}));
}
}

// Ventisca: puntos blancos flotando. Se mueven en runtime, no aqui.
for (let i = 0; i < 60; i++) {
const a = vr(i, 771 + seedBase, 0, Math.PI * 2);
const r = vr(i, 772 + seedBase, 10, half * 0.9);
deco.push(e.decor("SnowFlake_" + i, {
position: [cx + Math.cos(a) * r, vr(i, 773 + seedBase, 4, 26), cz + Math.sin(a) * r],
size: [0.5, 0.5, 0.5],
shape: "Ball",
color: [255, 255, 255],
transparency: 0.35,
}));
}

// Corazon de hielo sobre el relicario.
keshusy.push(e.decor("FrostHeart_Ice", {
position: [cx, 22, cz], size: [7, 10, 7], shape: "Ball",
color: P.accent, transparency: 0.25,
}));
}

/** VOLCANO RAGE: torres de basalto, charcos de lava y columnas de fuego. */
function decorateVolcano(e) {
const { cx, cz, half, palette: P, deco, border, keshusy, seedBase, vary: vr, hash01: h01 } = e;

// Torres de basalto: columnas altas y angulosas, como chimeneas.
for (let i = 0; i < 18; i++) {
const a = vr(i, 801 + seedBase, 0, Math.PI * 2);
const r = vr(i, 802 + seedBase, half * 0.3, half * 0.9);
const h = vr(i, 803 + seedBase, 16, 34);
const x = cx + Math.cos(a) * r;
const z = cz + Math.sin(a) * r;

deco.push(e.decor("Basalt_Tower_" + i, {
position: [x, h / 2, z],
size: [vr(i, 804 + seedBase, 4, 8), h, vr(i, 805 + seedBase, 4, 8)],
shape: "Cylinder",
material: "Basalt",
color: h01(i, 806 + seedBase) > 0.5 ? P.structure : P.structureDark,
orientation: [
Math.round(vr(i, 807 + seedBase, -12, 12)),
Math.round(vr(i, 808 + seedBase, 0, 360)),
Math.round(vr(i, 809 + seedBase, -12, 12)),
],
}));

// Boca encendida: sin esto la torre es un palo negro.
deco.push(e.decor("Basalt_Mouth_" + i, {
position: [x, h + 0.4, z],
size: [vr(i, 810 + seedBase, 3, 5), 0.8, vr(i, 811 + seedBase, 3, 5)],
shape: "Cylinder",
color: P.accent,
transparency: 0.15,
}));
}

// Charcos de lava: crateres planos con un anillo brillante. Sin colision.
for (let i = 0; i < 8; i++) {
const a = vr(i, 821 + seedBase, 0, Math.PI * 2);
const r = vr(i, 822 + seedBase, half * 0.2, half * 0.8);
const x = cx + Math.cos(a) * r;
const z = cz + Math.sin(a) * r;
const size = vr(i, 823 + seedBase, 12, 24);

deco.push(e.decor("LavaPool_" + i, {
position: [x, 0.1, z], size: [size, 0.2, size],
shape: "Cylinder", color: P.hazard,
}));
deco.push(e.decor("LavaRim_" + i, {
position: [x, 0.3, z], size: [size + 3, 0.5, size + 3],
shape: "Cylinder", color: P.accent, transparency: 0.4,
}));
}

// Grietas: conectan los charcos con el centro y dan lectura de "flujo"
// sin necesidad de particulas.
for (let i = 0; i < 14; i++) {
const a = (i / 14) * Math.PI * 2;
const r = vr(i, 831 + seedBase, 8, half * 0.6);
const len = vr(i, 832 + seedBase, 10, 26);
deco.push(e.decor("LavaCrack_" + i, {
position: [cx + Math.cos(a) * r, 0.16, cz + Math.sin(a) * r],
size: [len, 0.16, 1.6],
color: P.hazard,
orientation: [0, Math.round((a * 180) / Math.PI) + 90, 0],
}));
}

// Borde: conos volcanicos, la silueta mas alta del juego.
for (let side = 0; side < 4; side++) {
for (let i = 0; i < 14; i++) {
const t = -half + 6 + i * ((half * 2 - 12) / 13);
const along = side % 2 === 0;
const sign = side < 2 ? -1 : 1;
const out = half + vr(i, 841 + side + seedBase, 4, 18);
const h = vr(i, 851 + side + seedBase, 18, 40);
const x = along ? cx + t : cx + out * sign;
const z = along ? cz + out * sign : cz + t;

border.push(e.decor("Border_Volcano_" + side + "_" + i, {
position: [x, h / 2 - 2, z],
size: [vr(i, 861 + side + seedBase, 26, 44), h, vr(i, 871 + side + seedBase, 26, 44)],
shape: "Cylinder",
material: "Basalt",
color: P.structureDark,
}));
border.push(e.decor("Border_VolcanoVent_" + side + "_" + i, {
position: [x, h - 1.6, z],
size: [8, 3, 8],
shape: "Cylinder",
color: P.hazard,
transparency: 0.25,
}));
}
}

// Columnas de fuego sobre el relicario: el acento del mundo.
for (let i = 0; i < 10; i++) {
const a = (i / 10) * Math.PI * 2;
keshusy.push(e.decor("FirePillar_" + i, {
position: [cx + Math.cos(a) * 14, 12, cz + Math.sin(a) * 14],
size: [2.4, 24, 2.4],
shape: "Cylinder",
color: i % 2 === 0 ? P.accent : P.hazard,
transparency: 0.4,
}));
}
keshusy.push(e.decor("MagmaHeart_Volcano", {
position: [cx, 18, cz], size: [10, 10, 10], shape: "Ball",
color: P.hazard, transparency: 0.15,
}));
}

/** CYBER KESHUSY: pilonas, paneles holograficos y rejilla de neon. */
function decorateCyber(e) {
const { cx, cz, half, palette: P, deco, border, keshusy, seedBase, vary: vr, hash01: h01 } = e;

// Rejilla de neon en el suelo: el motivo digital del mundo. Sin
// colision, como toda la decoracion.
for (let i = -4; i <= 4; i++) {
deco.push(e.decor("GridLine_X_" + i, {
position: [cx + i * 16, 0.1, cz], size: [0.5, 0.2, half * 1.8],
color: P.accent, transparency: 0.55,
}));
deco.push(e.decor("GridLine_Z_" + i, {
position: [cx, 0.1, cz + i * 16], size: [half * 1.8, 0.2, 0.5],
color: P.accent, transparency: 0.55,
}));
}

// Pilonas: torres metalicas con anillos de neon.
for (let i = 0; i < 20; i++) {
const a = vr(i, 901 + seedBase, 0, Math.PI * 2);
const r = vr(i, 902 + seedBase, half * 0.25, half * 0.9);
const h = vr(i, 903 + seedBase, 14, 30);
const x = cx + Math.cos(a) * r;
const z = cz + Math.sin(a) * r;

deco.push(e.decor("Pylon_" + i, {
position: [x, h / 2, z], size: [3.4, h, 3.4],
shape: "Cylinder", material: "Metal", color: P.structure,
}));
for (let b = 1; b <= 3; b++) {
deco.push(e.decor("Pylon_Band_" + i + "_" + b, {
position: [x, (h / 4) * b, z], size: [4.2, 0.7, 4.2],
shape: "Cylinder", color: b % 2 === 0 ? P.accent : P.hazard,
transparency: 0.2,
}));
}
}

// Paneles holograficos: planos verticales translucidos en linea.
for (let i = 0; i < 12; i++) {
const a = (i / 12) * Math.PI * 2;
const r = half * 0.8;
const x = cx + Math.cos(a) * r;
const z = cz + Math.sin(a) * r;
const h = vr(i, 911 + seedBase, 8, 16);

deco.push(e.decor("HoloPanel_" + i, {
position: [x, h / 2, z], size: [12, h, 0.4],
color: h01(i, 912 + seedBase) > 0.5 ? P.accent : P.energy,
transparency: 0.55,
orientation: [0, Math.round((a * 180) / Math.PI) + 90, 0],
}));
deco.push(e.decor("HoloFrame_" + i, {
position: [x, h / 2, z], size: [12.6, 0.5, 0.6],
color: P.structureDark,
orientation: [0, Math.round((a * 180) / Math.PI) + 90, 0],
}));
}

// Borde: torres de datos que cierran el mundo con skyline futurista.
for (let side = 0; side < 4; side++) {
for (let i = 0; i < 16; i++) {
const t = -half + 4 + i * ((half * 2 - 8) / 15);
const along = side % 2 === 0;
const sign = side < 2 ? -1 : 1;
const out = half + vr(i, 921 + side + seedBase, 6, 22);
const h = vr(i, 931 + side + seedBase, 20, 46);
const x = along ? cx + t : cx + out * sign;
const z = along ? cz + out * sign : cz + t;

border.push(e.decor("Border_DataTower_" + side + "_" + i, {
position: [x, h / 2 - 2, z],
size: [vr(i, 941 + side + seedBase, 6, 14), h, vr(i, 951 + side + seedBase, 6, 14)],
material: "Metal",
color: P.structureDark,
}));
border.push(e.decor("Border_DataTower_LED_" + side + "_" + i, {
position: [x, h * 0.7, z],
size: [vr(i, 961 + side + seedBase, 7, 15), 1.2, vr(i, 971 + side + seedBase, 7, 15)],
color: h01(i, 981 + seedBase) > 0.5 ? P.accent : P.hazard,
transparency: 0.25,
}));
}
}

// Nucleo holografico sobre el relicario.
for (let i = 0; i < 4; i++) {
keshusy.push(e.decor("HoloRing_Cyber_" + i, {
position: [cx, 12 + i * 4, cz],
size: [22 - i * 4, 0.4, 22 - i * 4],
shape: "Cylinder",
color: i % 2 === 0 ? P.accent : P.energy,
transparency: 0.5,
}));
}
keshusy.push(e.decor("Core_Cyber", {
position: [cx, 20, cz], size: [7, 7, 7], shape: "Ball",
color: P.energy, transparency: 0.1,
}));
}

/**
 * Constructor de arena de un mundo.
 *
 * Se le inyectan los mismos helpers que usa el generador principal en vez de
 * importarlos: son closures privadas de ahi (`part`, `decor`, `marker`,
 * `folder`, `perimeter`). Duplicar esas cinco funciones de diez lineas es
 * preferible a acoplar el generador a un modulo que a su vez lo importa.
 *
 * @param {object} api helpers del generador
 * @param {object} def definicion del mundo (ver WORLD_DEFS)
 * @returns {{name:string, node:object}} folder del mundo
 */
function buildWorld(api, def) {
const { part, decor, marker, folder, perimeter } = api;

const P = def.palette;
const cx = def.cx;
const cz = def.cz;
const half = def.half;
const wallDist = def.wallDistance;
const seedBase = def.seedBase;

// ------------------------------------------------------------- SUELO
//
// `ArenaFloor` es la UNICA pieza con colision del suelo. Todo lo demas
// (`Terrain`, `Border`) se crea con `decor()` para que no pueda hacer
// tropezar al jugador: la colision real la lleva la losa.
const arenaParts = [
part("ArenaFloor", {
position: [cx, -1, cz],
size: [half * 2, 2, half * 2],
material: P.floorMaterial,
color: P.ground,
}),
marker("ArenaCenter", [cx, 0.2, cz], { color: P.energy }),
marker("ArenaNorth", [cx, 0.2, cz - half + 30], { color: P.accent }),
marker("ArenaSouth", [cx, 0.2, cz + half - 30], { color: P.accent }),
marker("ArenaEast", [cx + half - 30, 0.2, cz], { color: P.accent }),
marker("ArenaWest", [cx - half + 30, 0.2, cz], { color: P.accent }),
];

for (const p of perimeter("ArenaWall", cx, cz, half, 26, P.structureDark)) {
arenaParts.push(p);
}

// -------------------------------------------- BLOQUES DESTRUCTIBLES
//
// Mismo prefijo `Block_` que Forest: es el contrato con
// `DestructionService.IsDestructibleBlock`. El indice lleva el nombre
// del mundo para que dos arenas no compartan numeracion y el log de
// destruccion diga de que mundo es el bloque.
//
// Tres siluetas por mundo, no una: un muro de cajas iguales es lo que
// hace que una arena parezca un prototipo.
const blocks = [];
const centralBlocks = [];
const terrainParts = [];
const decoParts = [];
const borderParts = [];
const keshusyParts = [];
const hazardParts = [];
const monsterSpawnParts = [];
const powerupParts = [];

const SHAPES = [
{ size: [6, 11, 6], material: P.structureMaterial, colors: [P.structureDark, P.structure, P.structureDark] },
{ size: [12, 4.5, 10], material: P.floorMaterial, colors: [P.ground, P.groundAlt, P.ground] },
{ size: [8, 7, 9], material: P.structureMaterial, colors: [P.structure, P.structureDark, P.structure] },
];

function restY(index) {
return SHAPES[index % SHAPES.length].size[1] / 2;
}

/** Bloque destructible del mundo, con su veta de energia encima. */
function makeBlock(x, y, z, index) {
const s = SHAPES[index % SHAPES.length];
const node = part("Block_" + def.id + "_" + index, {
position: [x, y, z],
size: s.size,
material: s.material,
color: s.colors[index % s.colors.length],
orientation: [0, Math.round(hash01(index + seedBase, 7) * 360), 0],
});

// Ornamento: una veta luminosa en la cara superior. Los hijos NUNCA
// llevan el prefijo `Block_`, o `CollectBlocks` los contaria como
// bloques y el recuento por mundo dejaria de cuadrar.
const veinName = "Deco_" + def.id + "_Vein_" + index;
node.node[veinName] = decor(veinName, {
position: [x, y + s.size[1] / 2 + 0.1, z],
size: [s.size[0] * 0.6, 0.3, s.size[2] * 0.6],
color: P.energy,
transparency: 0.3,
}).node;

return node;
}

let blockIndex = 0;

// Muralla con huecos de paso al norte y al sur.
for (let i = 0; i < 6; i++) {
const t = -wallDist / 2 + i * (wallDist / 5);

if (i !== 2 && i !== 3) {
blocks.push(makeBlock(cx + t, restY(blockIndex), cz - wallDist, blockIndex++));
blocks.push(makeBlock(cx + t, restY(blockIndex), cz + wallDist, blockIndex++));
}

blocks.push(makeBlock(cx - wallDist, restY(blockIndex), cz + t, blockIndex++));
blocks.push(makeBlock(cx + wallDist, restY(blockIndex), cz + t, blockIndex++));

// Torres en las esquinas: segundo nivel.
if (i === 0 || i === 5) {
const above = SHAPES[blockIndex % SHAPES.length];
const below = SHAPES[(blockIndex + 1) % SHAPES.length];
const y2 = restY(blockIndex) + below.size[1] / 2 + above.size[1] / 2;
blocks.push(makeBlock(cx + t, y2, cz - wallDist, blockIndex++));
blocks.push(makeBlock(cx + t, y2, cz + wallDist, blockIndex++));
}
}

// Estructura central hueca: el relicario del mundo.
const STEP = 9.25;
for (let x = 0; x < 3; x++) {
for (let y = 0; y < 3; y++) {
for (let z = 0; z < 3; z++) {
if (x === 1 && y === 1) continue;
if (x === 1 && z === 1) continue;
if (y === 1 && z === 1) continue;

// Las esquinas superiores se CAEN: perfil de monumento
// derruido en lugar de caja perfecta.
const broken = y === 2 && (x === 0 || x === 2) && (z === 0 || z === 2);
const s = SHAPES[blockIndex % SHAPES.length];
centralBlocks.push(
makeBlock(cx + (x - 1) * STEP, (s.size[1] / 2) * (broken ? 0.62 : 1), cz + (z - 1) * STEP, blockIndex++)
);
}
}
}

// ------------------------------------------------------- TERRENO
//
// Cresta interior + cuatro senderos. Igual que Forest: marcan el limite
// de la zona jugable sin anadir colision.
const RIDGE = half - 6;
terrainParts.push(
decor("Terrain_Ridge_N", { position: [cx, 0.18, cz - RIDGE], size: [RIDGE * 2, 0.36, 1.6], material: P.floorMaterial, color: P.groundAlt }),
decor("Terrain_Ridge_S", { position: [cx, 0.18, cz + RIDGE], size: [RIDGE * 2, 0.36, 1.6], material: P.floorMaterial, color: P.groundAlt }),
decor("Terrain_Ridge_W", { position: [cx - RIDGE, 0.18, cz], size: [1.6, 0.36, RIDGE * 2], material: P.floorMaterial, color: P.groundAlt }),
decor("Terrain_Ridge_E", { position: [cx + RIDGE, 0.18, cz], size: [1.6, 0.36, RIDGE * 2], material: P.floorMaterial, color: P.groundAlt })
);

for (let axis = 0; axis < 4; axis++) {
const along = axis % 2 === 0;
const sign = axis < 2 ? -1 : 1;
for (let step = 1; step <= 8; step++) {
const d = step * 9 + vary(step, axis + 60, -1.2, 1.2);
const px = along ? cx + d * sign : cx + vary(step, axis + 70, -2, 2);
const pz = along ? cz + vary(step, axis + 80, -2, 2) : cz + d * sign;
terrainParts.push(decor("Path_" + axis + "_" + step, {
position: [px, 0.06, pz],
size: along ? [7.4, 0.12, 6.2] : [6.2, 0.12, 7.4],
material: P.floorMaterial,
color: step % 2 === 0 ? P.groundAlt : P.structureDark,
}));
}
}

// ---------------------------------------------- DECORACION POR MUNDO
//
// Cada mundo tiene SU decoracion. Es lo que impide que los cinco se lean
// como el mismo sitio con otro color: aqui cambia la FORMA, no el tono.
def.decorate({
cx: cx, cz: cz, half: half, palette: P,
decor: decor,
deco: decoParts, border: borderParts, keshusy: keshusyParts,
seedBase: seedBase, vary: vary, hash01: hash01,
});

// ------------------------------------------------------- KESHUSY
//
// Cristales de energia: el elemento que los cinco mundos comparten y que
// los identifica como parte de KeshusyTomy-LanD.
for (let i = 0; i < 6; i++) {
const a = (i / 6) * Math.PI * 2 + 0.4;
const r = half * 0.62;
const x = cx + Math.cos(a) * r;
const z = cz + Math.sin(a) * r;
const h = 4 + hash01(i, 500 + seedBase) * 3;

keshusyParts.push(decor("Crystal_Shard_" + def.id + "_" + i, {
position: [x, h / 2, z], size: [1.5, h, 1.5],
shape: "Cylinder", color: P.energy,
orientation: [0, 0, Math.round(vary(i, 510 + seedBase, -16, 16))],
}));
keshusyParts.push(decor("Crystal_ShardLow_" + def.id + "_" + i, {
position: [x, h * 0.3, z], size: [1.1, h * 0.7, 1.1],
shape: "Cylinder", color: P.accent,
orientation: [0, Math.round(vary(i, 520 + seedBase, -30, 30)), 18],
}));
keshusyParts.push(decor("Crystal_Float_" + def.id + "_" + i, {
position: [
x + vary(i, 530 + seedBase, -1.5, 1.5),
h + 1.3,
z + vary(i, 540 + seedBase, -1.5, 1.5),
],
size: [0.8, 0.8, 0.8], shape: "Ball", color: P.energy, transparency: 0.2,
}));
}

// Anillos de energia sobre el relicario.
for (let i = 0; i < 2; i++) {
keshusyParts.push(decor("Energy_Ring_" + def.id + "_" + i, {
position: [cx, 10 + i * 3.2, cz], size: [24 - i * 6, 0.35, 24 - i * 6],
shape: "Cylinder", color: i === 0 ? P.energy : P.accent, transparency: 0.55,
}));
}

// Luces reales. Tres por mundo, no mas: un mundo con veinte luces no
// renderiza, y el coste lo paga toda la partida.
function pointLight(name, x, y, z, tint, range, brightness) {
const p = decor("Light_" + def.id + "_" + name, {
position: [x, y, z], size: [1, 1, 1], color: tint, transparency: 1,
});
p.node.Light = {
$className: "PointLight",
$properties: {
Color: color(tint[0], tint[1], tint[2]),
Brightness: brightness,
Range: range,
Shadows: false,
},
};
keshusyParts.push(p);
}

pointLight("Center", cx, 16, cz, P.energy, 70, 2.1);
pointLight("North", cx, 11, cz - wallDist, P.accent, 40, 1.2);
pointLight("South", cx, 11, cz + wallDist, P.hazard, 40, 1.2);

// ------------------------------------------------------- PELIGROS
//
// `Hazards` NO tiene colision: son la senal visual de "no te quedes
// aqui". El dano, si lo hubiera, lo aplica el sistema de combate, no una
// Piece invisible.
for (let i = 0; i < 5; i++) {
const a = (i / 5) * Math.PI * 2 + 0.8;
const r = half * 0.5;
hazardParts.push(decor("Hazard_" + def.id + "_" + i, {
position: [cx + Math.cos(a) * r, 0.14, cz + Math.sin(a) * r],
size: [16, 0.28, 16],
shape: "Cylinder",
color: P.hazard,
transparency: 0.45,
}));
}

// ------------------------------------------------- SPAWNS DE MONSTRUO
//
// Anillo interior. `MatchService.BuildMonsterSpawns` calcula su propio
// anillo a partir del suelo, pero tener los puntos DECLARADOS permite
// que un mundo tenga su propia densidad de poblacion sin tocar codigo.
for (let i = 0; i < 4; i++) {
const a = (i / 4) * Math.PI * 2 + 0.6;
monsterSpawnParts.push(marker(
"MonsterSpawn_" + def.id + "_" + i,
[cx + Math.cos(a) * (half * 0.45), 1.6, cz + Math.sin(a) * (half * 0.45)],
{ color: P.hazard, size: [3, 0.2, 3] }
));
}

// ------------------------------------------------ SPAWNS DE POWERUP
for (let i = 0; i < 4; i++) {
const a = (i / 4) * Math.PI * 2;
const r = half * 0.72;
powerupParts.push(marker(
"PowerupSpawn_" + def.id + "_" + i,
[cx + Math.cos(a) * r, 1.4, cz + Math.sin(a) * r],
{ color: P.energy, size: [2.4, 0.2, 2.4] }
));
}

// ------------------------------------------------------- BOSS / EXIT
//
// El boss espera en el extremo norte, lejos del spawn: el jugador tiene
// que recorrer la arena para llegar a el.
const bossPad = part("BossSpawn_" + def.id, {
position: [cx, 0.3, cz - half + 22],
size: [26, 0.6, 26],
shape: "Cylinder",
material: P.structureMaterial,
color: P.structureDark,
});
const exitPad = part("Exit_" + def.id, {
position: [cx, 0.3, cz + half - 22],
size: [16, 0.6, 16],
shape: "Cylinder",
material: P.structureMaterial,
color: P.accent,
});

keshusyParts.push(decor("Boss_Totem_" + def.id + "_A", {
position: [cx - 9, 6, cz - half + 22], size: [2.4, 12, 2.4],
shape: "Cylinder", color: P.hazard,
}));
keshusyParts.push(decor("Boss_Totem_" + def.id + "_B", {
position: [cx + 9, 6, cz - half + 22], size: [2.4, 12, 2.4],
shape: "Cylinder", color: P.hazard,
}));

// ------------------------------------------------------------ SPAWN
//
// `SpawnLocation` real dentro de la carpeta del mundo. Roblox elige el
// SpawnLocation MAS CERCANO al aparecer: como cada mundo esta a cientos
// de studs de los demas, un jugador dentro de Desert nace en Desert sin
// que ningun codigo tenga que decidirlo.
const spawn = {
name: "SpawnPoint_" + def.id,
node: {
$className: "SpawnLocation",
$properties: {
Anchored: true,
CanCollide: true,
CanTouch: false,
Neutral: true,
Enabled: true,
Duration: 0,
AllowTeamChangeOnTouch: false,
Transparency: 0.4,
Material: "Neon",
Color: color(P.energy[0], P.energy[1], P.energy[2]),
Size: v3(12, 1, 12),
Position: v3(cx, 1.6, cz + half - 40),
},
},
};

// -------------------------------------------------------- MONTAJE
//
// El orden es el orden de lectura del jugador: entrada -> suelo ->
// bloques -> terreno -> peligro -> decoracion.
return folder(def.id, arenaParts.concat([
spawn,
bossPad,
exitPad,
folder("Blocks", blocks),
folder("CentralStructure", centralBlocks),
folder("Terrain", terrainParts),
folder("Hazards", hazardParts),
folder("Decoration", decoParts),
folder("Border", borderParts),
folder("Keshusy", keshusyParts),
folder("MonsterSpawns", monsterSpawnParts),
folder("PowerupSpawns", powerupParts),
]));
}

module.exports = {
PALETTES: PALETTES,
buildWorld: buildWorld,
hash01: hash01,
vary: vary,
DECORATORS: {
Desert: decorateDesert,
Ice: decorateIce,
Volcano: decorateVolcano,
Cyber: decorateCyber,
},
};
