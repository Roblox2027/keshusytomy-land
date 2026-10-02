// runtime-tree.js
// Audita el ARBOL REAL del DataModel en Roblox Studio (no el source).
//
// Por que existe: el source de `src/` puede estar completo y aun asi el
// lugar de Studio no tener los objetos, porque Rojo no ha sincronizado, el
// objeto se creo a mano con otro nombre, o el juego lo borro en runtime.
// Este script responde a la pregunta "que ve el juego de verdad".
//
// Uso:  node tools/runtime-tree.js [--deep]

const mcp = require("./mcp");

// Paths que el proyecto exige que existan en el DataModel.
const REQUIRED = [
	["ServerScriptService", "ServerMain"],
	["ServerScriptService", "Services"],
	["ReplicatedStorage", "Remotes"],
	["ReplicatedStorage", "Shared"],
	// La configuracion vive en `Shared.Config`, NO en `ReplicatedStorage.Config`.
	//
	// Comprobado sobre los 13 modulos que cargan configuracion
	// (ServerMain, los 9 servicios con config, ServiceRegistry, Logger y
	// ControllerRegistry): todos hacen `SHARED:WaitForChild("Config")`.
	// Ninguno pide `ReplicatedStorage.Config`, asi que exigirla en el
	// contrato era un FALSO POSITIVO que reportaba como rotura algo que
	// ningun codigo necesita.
	["ReplicatedStorage", "Shared", "Config"],
	["ReplicatedStorage", "Shared", "Constants"],
	["ReplicatedStorage", "Shared", "Libraries"],
	["ReplicatedStorage", "Shared", "Utils"],
	["ReplicatedStorage", "WorldDefinitions"],
	["StarterPlayer", "StarterPlayerScripts", "ClientMain"],
	["StarterPlayer", "StarterPlayerScripts", "Controllers"],
	["Workspace", "Lobby"],
	["Workspace", "Lobby", "KeshusyCore"],
	["Workspace", "Lobby", "Portals"],
	["Workspace", "SpawnLocations"],
	["Workspace", "Worlds"],
	["Workspace", "Worlds", "Forest"],
	["Workspace", "Worlds", "Forest", "Blocks"],
];

// Clases validas por hoja del contrato. Varias porque un contenedor puede
// ser Model o Folder segun como se haya construido.
const EXPECTED_CLASS = {
	ServerMain: ["Script", "ModuleScript", "LocalScript"],
	ClientMain: ["LocalScript"],
};


/**
 * Luau que recorre el DataModel del servidor y devuelve clase y hijos de
 * cada Path solicitado.
 *
 * Se genera por codigo (no a mano) para que anadir una ruta al contrato no
 * obligue a editar una cadena Luau embebida.
 */
function buildLuau(paths) {
	const list = paths.map((p) => '{' + p.map((s) => '"' + s + '"').join(",") + '}').join(", ");
	return `
local paths = {${list}}
local results = {}
for _, segs in ipairs(paths) do
    local node = game
    local walked = {}
    local missing = nil
    for _, seg in ipairs(segs) do
        table.insert(walked, seg)
        node = node:FindFirstChild(seg)
        if node == nil then
            missing = table.concat(walked, ".")
            node = nil
            break
        end
    end
    if node == nil then
        results[#results + 1] = {
            path = table.concat(segs, "."),
            missing = missing,
            class = nil,
            children = {},
        }
    else
        local kids = {}
        for _, c in ipairs(node:GetChildren()) do
            table.insert(kids, c.Name .. " [" .. c.ClassName .. "]")
            if #kids >= 40 then table.insert(kids, "...(truncado)") break end
        end
        results[#results + 1] = {
            path = table.concat(segs, "."),
            missing = nil,
            class = node.ClassName,
            count = #node:GetChildren(),
            children = kids,
        }
    end
end


local Players_ = game:GetService("Players")
local stats = {
    playerCount = #Players_:GetPlayers(),
    servicesPresent = {},
}
for _, c in ipairs(game:GetService("ServerScriptService"):GetChildren()) do
    if c:IsA("ModuleScript") then
        table.insert(stats.servicesPresent, c.Name)
    end
end
table.sort(stats.servicesPresent)

-- Cuentos de Parts para detectar Forest vacio o ausente.
local function countDesc(root)
    if root == nil then return -1 end
    local n = 0
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("BasePart") then n = n + 1 end
    end
    return n
end
stats.lobbyParts = countDesc(game:GetService("Workspace"):FindFirstChild("Lobby"))
stats.worldParts = {}
local worlds = game:GetService("Workspace"):FindFirstChild("Worlds")
if worlds then
    for _, w in ipairs(worlds:GetChildren()) do
        stats.worldParts[w.Name] = countDesc(w)
    end
end

return { paths = results, stats = stats }
`;
}

/**
 * Paths que se declaran OK aunque no tengan hijos.
 *
 * ServerMain y ClientMain son Scripts: no pueden tener hijos por diseno,
 * asi que `[VACIO]` ahi seria un falso positivo que ocultaria incumplimientos
 * reales de los contenedores.
 */
const ALLOW_EMPTY = new Set(["ServerScriptService.ServerMain", "StarterPlayer.StarterPlayerScripts.ClientMain"]);

function classify(entry) {
	if (entry.missing) return `FALTA (falta ${entry.missing})`;
	const expected = EXPECTED_CLASS[entry.path.split(".").pop()];
	if (expected && !expected.includes(entry.class)) {
		return `CLASE-INESPERADA (${entry.class})`;
	}
	if (entry.count === 0 && !ALLOW_EMPTY.has(entry.path)) return "VACIO";
	return "OK";
}


async function main() {
	const deep = process.argv.includes("--deep");

	const instances = await mcp.toolJson("get_connected_instances", {});
	if (!instances || !instances.instances || !instances.instances.length) {
		console.log("SIN CONEXION: Studio no expone ninguna instancia.");
		process.exitCode = 2;
		return;
	}
	console.log("INSTANCIAS CONECTADAS: " + instances.instances.map((i) => i.placeName).join(", "));

	const out = await mcp.toolJson("eval_server_runtime", { code: buildLuau(REQUIRED) });
	const entries = (out && out.paths) || [];
	if (!entries.length) {
		console.log("eval_server_runtime devolvio: " + JSON.stringify(out));
		process.exitCode = 2;
		return;
	}

	let fails = 0;
	console.log("");
	console.log("PATHS EXIGIDOS POR EL CONTRATO");
	console.log("---------------------------------------------------------------");
	for (const entry of entries) {
		const status = classify(entry);
		if (status !== "OK") fails++;
		console.log(`[${status}] ${entry.path}`);
		if (entry.class) console.log(`        clase=${entry.class} hijos=${entry.count}`);
		if (entry.children && entry.children.length) {
			console.log(`        ${entry.children.join(", ")}`);
		}
	}

	const stats = out.stats;
	if (stats) {
		console.log("");
		console.log("ESTADISTICAS DE RUNTIME");
		console.log("---------------------------------------------------------------");
		console.log(`jugadores: ${stats.playerCount}`);
		if (stats.servicesPresent) console.log(`servicios: ${stats.servicesPresent.join(", ")}`);
		if (stats.lobbyParts !== undefined) console.log(`Parts en Lobby: ${stats.lobbyParts}`);
		if (stats.worldParts) console.log(`Parts por mundo: ${JSON.stringify(stats.worldParts)}`);
	}

	if (deep) {
		console.log("");
		console.log("DETALLE PROFUNDO (--deep)");
		console.log(JSON.stringify(await mcp.toolJson("get_project_structure", {}), null, 2));
	}

	console.log("");
	console.log(fails === 0 ? "CONTRATO DE DATAMODEL: PASS" : `CONTRATO DE DATAMODEL: ${fails} INCUMPLIMIENTO(S)`);
	if (fails > 0) process.exitCode = 1;
}

main().catch((e) => {
	console.error("FALLO: " + e.message);
	process.exitCode = 2;
});
