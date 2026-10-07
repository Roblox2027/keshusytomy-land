"use strict";
// forest-zones.js — capa de contenido del bosque nocturno (FASE MAPA GRANDE).
// NO toca el motor de tools/worlds.js: solo APORTA contenido original con
// prefijos nuevos (ForestPOI_, ForestHide_, ForestGlow_, ForestSpawn_,
// ForestPatrol_) que ningun test ni servicio lee. Todo decor sin colision
// salvo 2 bancos verificados. Determinista via hash01 con semilla fija.
function hash01(seed, salt) {
  let h = (seed * 374761393 + (salt || 0) * 668265263) | 0;
  h = (h ^ (h >>> 13)) * 1274126177;
  h = h ^ (h >>> 16);
  return ((h >>> 0) % 100000) / 100000;
}
const FOREST_SEED = 7700;
// 9 distritos jugables -> zonas tecnicas existentes (sin renombrar nada).
const DISTRICTS = [
  { display: "BOSQUE CENTRAL", ids: ["Trail", "Bridge"] },
  { display: "BOSQUE DENSO", ids: ["Grove", "Hollow"] },
  { display: "CLARO", ids: ["Clearing"] },
  { display: "ZONA ROCOSA", ids: ["Rocks"] },
  { display: "PANTANO", ids: ["Swamp"] },
  { display: "CAMPAMENTO ABANDONADO", ids: ["Village"] },
  { display: "ZONA DE CABANAS", ids: ["Cave", "Spring"] },
  { display: "ZONA DE RUINAS", ids: ["Ruins", "Sanctuary"] },
  { display: "ZONA OSCURA", ids: ["Nest", "Grooty", "Entrance", "Arena", "Exit"] },
];
const DISTRICT_BY_ZONE = {};
for (const d of DISTRICTS) { for (const id of d.ids) DISTRICT_BY_ZONE[id] = d.display; }


// POIs originales: fogata, refugios, cabanas, ruinas, mirador, charca.
const POIS = [
  { name: "FogataCentral", zone: "Village", dx: 0, dz: 0, kind: "campfire" },
  { name: "RefugioNorte", zone: "Village", dx: -14, dz: -12, kind: "shelter" },
  { name: "RefugioSur", zone: "Village", dx: 16, dz: 14, kind: "shelter" },
  { name: "AlmacenViejo", zone: "Village", dx: 10, dz: -14, kind: "storage" },
  { name: "CabanaMusgo", zone: "Cave", dx: 0, dz: 0, kind: "cabin" },
  { name: "CabanaClaro", zone: "Spring", dx: 6, dz: 4, kind: "cabin" },
  { name: "CabanaPerdida", zone: "Grove", dx: 10, dz: 8, kind: "cabin_ruin" },
  { name: "CabanaVigia", zone: "Hollow", dx: -12, dz: 6, kind: "cabin" },
  { name: "PortalPiedra", zone: "Ruins", dx: 0, dz: 0, kind: "ruin_gate" },
  { name: "PilarCaido", zone: "Ruins", dx: 12, dz: -8, kind: "ruin_pillar" },
  { name: "SantuarioHondo", zone: "Sanctuary", dx: 0, dz: 0, kind: "shrine" },
  { name: "MiradorRoca", zone: "Rocks", dx: 0, dz: 0, kind: "lookout" },
  { name: "CharcaPantano", zone: "Swamp", dx: 0, dz: 0, kind: "pond" },
  { name: "ClaroLuz", zone: "Clearing", dx: 0, dz: 0, kind: "meadow" },
  { name: "NidoSombras", zone: "Nest", dx: 0, dz: 0, kind: "dark_nest" },
];
const HIDES = [
  { name: "MatorralGemelo", zone: "Grove", dx: -8, dz: 4, kind: "bush" },
  { name: "TroncoHueco", zone: "Hollow", dx: 8, dz: -6, kind: "log" },
  { name: "RocasJuntas", zone: "Rocks", dx: -10, dz: 8, kind: "rocks" },
  { name: "SombraRuina", zone: "Ruins", dx: -8, dz: 6, kind: "shadow" },
  { name: "JuncosPantano", zone: "Swamp", dx: 8, dz: 6, kind: "reeds" },
  { name: "SetoCampamento", zone: "Village", dx: -10, dz: 10, kind: "hedge" },
  { name: "PinosJuntos", zone: "Trail", dx: 12, dz: -8, kind: "pines" },
  { name: "MuroCaido", zone: "Sanctuary", dx: 6, dz: -6, kind: "wall" },
];
const GLOWS = [
  { name: "LuzFogata", zone: "Village", dx: 0, dz: 0, color: [255, 150, 60] },
  { name: "LuzCabanaMusgo", zone: "Cave", dx: 0, dz: 0, color: [255, 190, 120] },
  { name: "LuzCabanaClaro", zone: "Spring", dx: 6, dz: 4, color: [255, 190, 120] },
  { name: "LuzClaro", zone: "Clearing", dx: 0, dz: 0, color: [150, 200, 255] },
  { name: "LuzRuinas", zone: "Ruins", dx: 0, dz: 0, color: [140, 170, 255] },
];
const PLAYER_SPAWNS = [
  { name: "SpawnSur", zone: "Entrance", dx: 0, dz: 6 },
  { name: "SpawnClaro", zone: "Clearing", dx: -10, dz: 0 },
  { name: "SpawnCampamento", zone: "Village", dx: 0, dz: 10 },
  { name: "SpawnPantano", zone: "Swamp", dx: -6, dz: 0 },
  { name: "SpawnRuinas", zone: "Sanctuary", dx: 0, dz: 4 },
];
const PATROLS = [
  { name: "PatrullaOscura", zone: "Nest" },
  { name: "PatrullaDensa", zone: "Hollow" },
  { name: "PatrullaRoca", zone: "Rocks" },
  { name: "PatrullaRuina", zone: "Ruins" },
  { name: "RaraSantuario", zone: "Sanctuary" },
];

function groundAt(def, x, z) {
  let best = null;
  for (const zn of def.zones || []) {
    const dx = (x - zn.x) / Math.max(1, zn.rx);
    const dz = (z - zn.z) / Math.max(1, zn.rz);
    if (dx * dx + dz * dz <= 1) { if (!best || (zn.y || 0) > (best.y || 0)) best = zn; }
  }
  return best ? best.y || 0 : 0;
}
function buildPoiPieces(api, out, poi, x, y, z, s, solidOk) {
  const base = "ForestPOI_" + poi.name;
  if (poi.kind === "campfire") {
    for (let i = 0; i < 7; i++) {
      const a = (i / 7) * Math.PI * 2 + hash01(s, i) * 0.3;
      out.deco.push(api.decor(base + "_Piedra_" + i, {
        position: [x + Math.cos(a) * 4, y + 0.8, z + Math.sin(a) * 4],
        size: [1.6, 1.2, 1.6], color: [120, 118, 112], material: "Rock",
      }));
    }
    for (let i = 0; i < 3; i++) {
      const a = (i / 3) * Math.PI * 2;
      out.deco.push(api.decor(base + "_Lena_" + i, {
        position: [x + Math.cos(a) * 1.2, y + 1, z + Math.sin(a) * 1.2],
        size: [4, 0.8, 0.8], color: [96, 66, 40], material: "Wood",
        orientation: [0, Math.round(a * 180 / Math.PI), 12],
      }));
    }
    out.deco.push(api.decor(base + "_Brasa", {
      position: [x, y + 1.2, z], size: [2.4, 1, 2.4],
      color: [255, 120, 40], material: "Neon", transparency: 0.15,
    }));
    const benches = [[-7, 3], [7, -3]];
    benches.forEach((o, bi) => {
      const bx = x + o[0]; const bz = z + o[1];
      if (!solidOk(bx, bz)) return;
      out.terrain.push(api.part(base + "_Banco_" + bi, {
        position: [bx, y + 1, bz], size: [5, 1, 1.6],
        color: [110, 78, 48], material: "WoodPlanks",
      }));
    }));
    return;
  }
  if (poi.kind === "shelter" || poi.kind === "storage") {
    const lean = poi.kind === "storage";
    const W = lean ? 10 : 9; const H = lean ? 5 : 4;
    out.deco.push(api.decor(base + "_Techo", {
      position: [x, y + H, z], size: [W, 0.6, 8],
      color: [88, 62, 40], material: "WoodPlanks",
      orientation: [18, Math.round(hash01(s, 3) * 40 - 20), 0],
    }));
    for (let i = 0; i < 2; i++) {
      out.deco.push(api.decor(base + "_Poste_" + i, {
        position: [x - W / 2 + 1 + i * (W - 2), y + H / 2, z + 3],
        size: [0.8, H, 0.8], color: [96, 66, 40], material: "Wood",
      }));
    }
    const boxes = lean ? 3 : 1;
    for (let i = 0; i < boxes; i++) {
      out.deco.push(api.decor(base + "_Caja_" + i, {
        position: [x - 2 + i * 2.4, y + 1, z - 1], size: [2, 2, 2],
        color: [140, 105, 70], material: "Wood",
        orientation: [0, Math.round(hash01(s, 10 + i) * 30 - 15), 0],
      }));
    }
    return;
  }
  buildShelterKind(api, out, base, poi.kind, x, y, z, s);
}
