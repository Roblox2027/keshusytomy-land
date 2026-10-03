// portals.js
// Constructor de los CINCO PORTALES del lobby.
//
// POR QUE UN ARCHIVO APARTE
// -------------------------
// Los portales son lo primero que ve el jugador y lo que decide si el juego
// parece cinco mundos o cinco cajas de colores. Cada uno se construye aqui
// con una silueta propia segun el mundo al que lleva, para que se reconozca
// ANTES de leer el cartel:
//
//   Forest   arco de madera: dos troncos y copa
//   Desert   dos obeliscos de arenisca con capitel y disco solar
//   Ice      dos agujas de hielo con arco congelado
//   Volcano  dos chimeneas de basalto con boca encendida
//   Cyber    dos pilonas metalicas con anillos de neon
//
// EL CONTRATO CON EL CODIGO (no cambia)
// -------------------------------------
//   - el Model se llama `Portal_<WorldId>`;
//   - el umbral se llama `PortalPanel`;
//   - `PortalPanel` NO colisiona, para que el jugador pueda cruzarlo;
//   - el marco SI colisiona, porque delimita el umbral;
//   - existe una pieza `Sign`, que `VisualService.SetPortalSign` usa para
//     escribir el nombre del mundo y el nivel exigido.
//
// Si se cambia cualquiera de esos cuatro nombres, `PortalService` deja de
// encontrar el portal y todos los viajes se rechazan.

/**
 * Construye los cinco portales.
 *
 * @param {object} api helpers del generador ({ part, decor, model })
 * @param {Array} defs definiciones: { id, x, color, style }
 * @param {number} z coordenada Z del arco de portales
 * @returns {Array} lista de portals para `folder("Portals", ...)`
 */
function buildPortals(api, defs, z) {
const { part, decor, model } = api;

const portalModels = [];

for (const p of defs) {
const x = p.x;
const tint = p.color;
const frame = [86, 96, 114];

// Piezas comunes a los cinco: suelo, dintel, panel de energia y
// cartel. Son las que el codigo busca por nombre.
const pieces = [
part("Base", {
position: [x, 0.5, z], size: [12, 1, 8],
material: "Slate", color: frame,
}),
part("Lintel", {
position: [x, 9, z], size: [12, 1.2, 8],
material: "Slate", color: frame,
}),
decor("PortalPanel", {
position: [x, 4.75, z], size: [10, 8, 0.4],
color: tint, transparency: 0.55,
}),
decor("Glow", {
position: [x, 4.75, z], size: [7, 5, 0.3],
color: tint, transparency: 0.3,
}),
part("Sign", {
position: [x, 10.6, z], size: [10, 1.6, 0.4],
material: "SmoothPlastic", color: tint,
}),
];

const style = p.style;

if (style === "Forest") {
// Troncos con copa: se lee "bosque" a doscientas leidas.
pieces.push(
part("PostL", { position: [x - 5.5, 4.75, z], size: [1.8, 8.5, 3.4], material: "Wood", color: [104, 78, 50] }),
part("PostR", { position: [x + 5.5, 4.75, z], size: [1.8, 8.5, 3.4], material: "Wood", color: [104, 78, 50] }),
decor("Canopy", { position: [x, 9.6, z], size: [15, 4, 5], shape: "Ball", material: "Grass", color: [66, 138, 68] }),
decor("CanopyTop", { position: [x, 12, z], size: [9, 3, 3.6], shape: "Ball", material: "Grass", color: [116, 184, 82] }),
decor("Root_L", { position: [x - 7, 0.7, z], size: [5, 1.4, 2], material: "Wood", color: [74, 54, 36] }),
decor("Root_R", { position: [x + 7, 0.7, z], size: [5, 1.4, 2], material: "Wood", color: [74, 54, 36] })
);
} else if (style === "Desert") {
// Obeliscos con capitel y un disco solar sobre el dintel.
pieces.push(
part("PostL", { position: [x - 5.5, 4.75, z], size: [2.6, 8.5, 3], shape: "Cylinder", material: "Sandstone", color: [214, 190, 148] }),
part("PostR", { position: [x + 5.5, 4.75, z], size: [2.6, 8.5, 3], shape: "Cylinder", material: "Sandstone", color: [214, 190, 148] }),
decor("Capital_L", { position: [x - 5.5, 9.4, z], size: [4, 1.4, 4], shape: "Cylinder", material: "Sandstone", color: [162, 132, 92] }),
decor("Capital_R", { position: [x + 5.5, 9.4, z], size: [4, 1.4, 4], shape: "Cylinder", material: "Sandstone", color: [162, 132, 92] }),
decor("Sun_Disc", { position: [x, 12.4, z], size: [5, 5, 0.6], shape: "Cylinder", material: "Neon", color: [255, 206, 120] })
);
} else if (style === "Ice") {
// Agujas inclinadas con arco: la silueta mas "fria" del lobby.
pieces.push(
decor("PostL", { position: [x - 5.5, 4.75, z], size: [2.4, 8.5, 2.4], shape: "Cylinder", material: "Ice", color: [198, 224, 240], orientation: [0, 0, 10] }),
decor("PostR", { position: [x + 5.5, 4.75, z], size: [2.4, 8.5, 2.4], shape: "Cylinder", material: "Ice", color: [198, 224, 240], orientation: [0, 0, -10] }),
decor("Arch_Top", { position: [x, 9.8, z], size: [13, 1.8, 2.6], material: "Ice", color: [136, 170, 198] }),
decor("Shard_L", { position: [x - 7.4, 2.2, z], size: [1.4, 4.4, 1.4], shape: "Cylinder", material: "Neon", color: [178, 240, 255], orientation: [0, 0, 18] }),
decor("Shard_R", { position: [x + 7.4, 2.2, z], size: [1.4, 4.4, 1.4], shape: "Cylinder", material: "Neon", color: [178, 240, 255], orientation: [0, 0, -18] })
);
} else if (style === "Volcano") {
// Chimeneas con la boca encendida y brasas en la base.
pieces.push(
part("PostL", { position: [x - 5.5, 4.75, z], size: [2.8, 8.5, 3], material: "Basalt", color: [58, 48, 50] }),
part("PostR", { position: [x + 5.5, 4.75, z], size: [2.8, 8.5, 3], material: "Basalt", color: [58, 48, 50] }),
decor("Mouth_L", { position: [x - 5.5, 9.4, z], size: [2.4, 0.8, 2.6], material: "Neon", color: [255, 132, 44] }),
decor("Mouth_R", { position: [x + 5.5, 9.4, z], size: [2.4, 0.8, 2.6], material: "Neon", color: [255, 132, 44] }),
decor("Ember_L", { position: [x - 5.5, 1.4, z + 1.8], size: [2, 1, 2], shape: "Ball", material: "Neon", color: [255, 78, 26], transparency: 0.3 }),
decor("Ember_R", { position: [x + 5.5, 1.4, z + 1.8], size: [2, 1, 2], shape: "Ball", material: "Neon", color: [255, 78, 26], transparency: 0.3 })
);
} else if (style === "Cyber") {
// Pilonas con anillos de neon y anillos holograficos arriba.
pieces.push(
part("PostL", { position: [x - 5.5, 4.75, z], size: [1.6, 8.5, 1.6], shape: "Cylinder", material: "Metal", color: [58, 66, 96] }),
part("PostR", { position: [x + 5.5, 4.75, z], size: [1.6, 8.5, 1.6], shape: "Cylinder", material: "Metal", color: [58, 66, 96] })
);
for (let i = 0; i < 3; i++) {
pieces.push(
decor("Band_L_" + i, { position: [x - 5.5, 2 + i * 2.6, z], size: [2.4, 0.5, 2.4], shape: "Cylinder", material: "Neon", color: [86, 236, 240], transparency: 0.2 }),
decor("Band_R_" + i, { position: [x + 5.5, 2 + i * 2.6, z], size: [2.4, 0.5, 2.4], shape: "Cylinder", material: "Neon", color: [190, 108, 255], transparency: 0.2 })
);
}
pieces.push(
decor("Holo_Ring_A", { position: [x, 12, z], size: [11, 0.4, 11], shape: "Cylinder", material: "Neon", color: [206, 168, 255], transparency: 0.5 }),
decor("Holo_Ring_B", { position: [x, 13.4, z], size: [7, 0.4, 7], shape: "Cylinder", material: "Neon", color: [86, 236, 240], transparency: 0.5 })
);
}

portalModels.push(model("Portal_" + p.id, pieces));
}

return portalModels;
}

module.exports = { buildPortals };
