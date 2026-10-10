// lobby-premium.js
// Plaza social PREMIUM original (no copia de ningun juego).
// Se suma al lobby radial existente sin romper contratos:
// LobbyCenter / LobbyReturn / KeshusyCore / Portals intactos.
// Todo lo nuevo: PvPArena_*, Podium_*, ShopHall_*, Plaza_*, SafeZone_*.

function buildPremiumLobby(api) {
	const { part, decor, marker } = api;
	const out = [];
	const GOLD = [255, 200, 80];
	const STONE_D = [70, 80, 96];
	const KESHUSY = [86, 214, 124];
	const TOMY = [255, 152, 72];
	const ACX = 0;
	const ACZ = 82;
	out.push(part("PvPArena_Floor", {
		position: [ACX, -0.8, ACZ], size: [66, 1.6, 46],
		material: "Concrete", color: [88, 92, 110],
	}));
	out.push(decor("PvPArena_CenterLine", {
		position: [ACX, 0.15, ACZ], size: [66, 0.2, 1.2],
		material: "Neon", color: TOMY,
	}));
	out.push(part("PvPArena_Wall_S", { position: [ACX, 4, ACZ + 23], size: [66, 8, 2], color: STONE_D }));
	out.push(part("PvPArena_Wall_E", { position: [ACX + 33, 4, ACZ], size: [2, 8, 46], color: STONE_D }));
	out.push(part("PvPArena_Wall_W", { position: [ACX - 33, 4, ACZ], size: [2, 8, 46], color: STONE_D }));
	out.push(part("PvPArena_Wall_N_L", { position: [ACX - 19.5, 4, ACZ - 23], size: [27, 8, 2], color: STONE_D }));
	out.push(part("PvPArena_Wall_N_R", { position: [ACX + 19.5, 4, ACZ - 23], size: [27, 8, 2], color: STONE_D }));
	[[33, 23], [-33, 23], [33, -23], [-33, -23]].forEach(function (c, i) {
		out.push(part("PvPArena_Pillar_" + i, {
			position: [ACX + c[0], 5, ACZ + c[1]], size: [2.5, 10, 2.5],
			material: "Metal", color: [120, 130, 148],
		}));
		out.push(decor("PvPArena_Torch_" + i, {
			position: [ACX + c[0], 10.6, ACZ + c[1]], size: [1.8, 1.8, 1.8],
			shape: "Ball", color: TOMY,
		}));
	});
	out.push(part("PvPArena_Sign", {
		position: [ACX, 11, ACZ - 23], size: [20, 2.4, 0.8],
		material: "SmoothPlastic", color: TOMY,
	}));
	out.push(marker("PvPCenter", [ACX, 0.2, ACZ], { color: [255, 170, 90] }));
	out.push(marker("PvPSpawn_A", [ACX - 22, 0.2, ACZ + 12], { color: [255, 120, 120] }));
	out.push(marker("PvPSpawn_B", [ACX + 22, 0.2, ACZ + 12], { color: [120, 180, 255] }));
	out.push(marker("PvPEntry", [ACX, 0.2, ACZ - 26], { color: [255, 220, 160] }));
	const PCX = 62;
	const PCZ = 18;
	out.push(part("Podium_Base", {
		position: [PCX, 0.25, PCZ], size: [22, 0.5, 12],
		material: "Marble", color: [150, 158, 175],
	}));
	out.push(part("Podium_2nd", {
		position: [PCX - 6, 1.5, PCZ], size: [5, 3, 6],
		material: "Metal", color: [180, 190, 205],
	}));
	out.push(part("Podium_1st", {
		position: [PCX, 2.5, PCZ], size: [5, 5, 6],
		material: "Metal", color: GOLD,
	}));
	out.push(part("Podium_3rd", {
		position: [PCX + 6, 1, PCZ], size: [5, 2, 6],
		material: "Metal", color: [170, 120, 80],
	}));
	out.push(part("Podium_Sign", {
		position: [PCX, 10, PCZ - 4], size: [16, 2, 0.8],
		material: "SmoothPlastic", color: GOLD,
	}));
	out.push(decor("Podium_Crown", {
		position: [PCX, 7.5, PCZ], size: [3, 2, 3],
		material: "Neon", color: GOLD,
	}));
	const SCX = -58;
	const SCZ = 14;
	out.push(part("ShopHall_Floor", {
		position: [SCX, 0.1, SCZ], size: [30, 0.6, 20],
		material: "WoodPlanks", color: [150, 118, 84],
	}));
	[[-13, -8], [13, -8], [-13, 8], [13, 8]].forEach(function (c, i) {
		out.push(part("ShopHall_Pillar_" + i, {
			position: [SCX + c[0], 4, SCZ + c[1]], size: [1.6, 8, 1.6],
			material: "Wood", color: [104, 78, 50],
		}));
	});
	out.push(part("ShopHall_Roof", {
		position: [SCX, 8.8, SCZ], size: [34, 1.2, 24],
		material: "Slate", color: TOMY,
	}));
	out.push(part("ShopHall_Counter", {
		position: [SCX, 1.5, SCZ - 6], size: [20, 3, 2],
		material: "Wood", color: [120, 90, 60],
	}));
	out.push(part("ShopHall_Sign", {
		position: [SCX, 11, SCZ + 9], size: [18, 2.4, 0.8],
		material: "SmoothPlastic", color: TOMY,
	}));
	out.push(marker("ShopPoint", [SCX, 0.4, SCZ + 2], { color: [255, 180, 100] }));
	out.push(decor("Plaza_Party_Rug", {
		position: [-52, 0.15, -52], size: [16, 0.3, 16],
		shape: "Cylinder", color: [120, 200, 255],
	}));
	out.push(part("Plaza_Party_Sign", {
		position: [-52, 6, -60], size: [12, 1.8, 0.8],
		material: "SmoothPlastic", color: [120, 200, 255],
	}));
	out.push(marker("PartyPoint", [-52, 0.3, -52], { color: [120, 200, 255] }));
	out.push(decor("Plaza_Codes_Rug", {
		position: [52, 0.15, -52], size: [16, 0.3, 16],
		shape: "Cylinder", color: KESHUSY,
	}));
	out.push(part("Plaza_Codes_Sign", {
		position: [52, 6, -60], size: [12, 1.8, 0.8],
		material: "SmoothPlastic", color: KESHUSY,
	}));
	out.push(marker("CodesPoint", [52, 0.3, -52], { color: [140, 240, 190] }));
	out.push(part("SafeZone_Sign", {
		position: [0, 13, 46], size: [22, 2.2, 0.8],
		material: "SmoothPlastic", color: KESHUSY,
	}));
	[[20, 46], [-20, 46], [20, -8], [-20, -8]].forEach(function (c, i) {
		out.push(decor("SafeZone_Beacon_" + i, {
			position: [c[0], 3, c[1]], size: [1.4, 6, 1.4],
			shape: "Cylinder", material: "Neon", color: KESHUSY, transparency: 0.35,
		}));
	});
	return out;
}

module.exports = { buildPremiumLobby };
