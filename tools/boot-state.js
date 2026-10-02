// boot-state.js
// Lee del runtime, y no del source, si el juego ARRANCO.
//
// Por que existe: tener 31 ModuleScripts en Studio no demuestra que
// ServerMain llego a llamar a ServiceRegistry.InitAll/StartAll. Este script
// interroga al servidor vivo.
//
// Como funciona: Roblox cachea `require`, asi que.require(servicio) desde
// aqui devuelve EXACTAMENTE la misma tabla que ServerMain inicializo. Es la
// unica forma de observar el estado real sin instrumentar el codigo fuente.
//
// Uso:  node tools/boot-state.js
//
// Sale con codigo 1 si el juego no arranco, para poder encadenarlo como gate.

const mcp = require("./mcp");

const SERVER_PROBE = `
local out = { services = {}, errors = {} }

local SSS = game:GetService("ServerScriptService")
local servicesFolder = SSS:FindFirstChild("Services")

-- 1) Estado real de cada servicio, leido de la tabla viva.
if servicesFolder then
    for _, mod in ipairs(servicesFolder:GetChildren()) do
        if mod:IsA("ModuleScript") then
            local entry = { name = mod.Name }
            local ok, res = pcall(require, mod)
            if not ok then
                entry.error = tostring(res)
                table.insert(out.errors, mod.Name .. ": require fallo -> " .. tostring(res))
            else
                entry.isInitialized = res.IsInitialized
                entry.isStarted = res.IsStarted
                entry.state = res.State
                -- Un stub de FASE 0 solo tiene IsInitialized/Destroy.
                entry.hasStart = type(res.Start) == "function"
                entry.hasInit = type(res.Init) == "function"
            end
            table.insert(out.services, entry)
        end
    end
end
table.sort(out.services, function(a, b) return a.name < b.name end)

-- 2) Jugadores: un character con Humanoid vivo demuestra que el boot
--    llego hasta PlayerService y el juego es realmente jugable.
local players = {}
for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
    local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
    local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
    table.insert(players, {
        name = p.Name,
        hasCharacter = p.Character ~= nil,
        hasHumanoid = hum ~= nil,
        health = hum and hum.Health or -1,
        pos = root and string.format("%.0f,%.0f,%.0f", root.Position.X, root.Position.Y, root.Position.Z) or "n/a",
    })
end
out.players = players

-- 3) Estado del mundo observable desde el servidor.
local function partsIn(root)
    if not root then return -1 end
    local n = 0
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("BasePart") then n = n + 1 end
    end
    return n
end
local WS = game:GetService("Workspace")
out.workspace = {}
for _, c in ipairs(WS:GetChildren()) do
    table.insert(out.workspace, c.Name .. " [" .. c.ClassName .. "] parts=" .. partsIn(c))
end
table.sort(out.workspace)

return out
`;

async function main() {
	const inst = await mcp.toolJson("get_connected_instances", {});
	const hasServer = inst?.instances?.some((i) => i.peers && i.peers.server);
	console.log("SERVIDOR DE JUEGO EN VIVO: " + (hasServer ? "SI" : "NO (sin sesion Play)"));
	if (!hasServer) {
		console.log("Arranca Play en Studio para poder leer el estado de boot.");
		process.exitCode = 1;
		return;
	}

	const probe = await mcp.serverLuau(SERVER_PROBE);
	if (!probe || typeof probe !== "object") {
		console.log("No se pudo leer el runtime: " + JSON.stringify(probe));
		process.exitCode = 2;
		return;
	}

	console.log("");
	console.log("ESTADO REAL DE LOS SERVICIOS (leido del require cacheado)");
	console.log("---------------------------------------------------------------");
	const header = ["servicio", "Init", "Start", "IsInitialized"];
	console.log(header.map((h) => h.padEnd(22)).join(""));
	for (const s of probe.services) {
		const fmt = (v) => (v === true ? "si" : v === false ? "no" : "-");
		console.log(
			s.name.padEnd(22) +
				fmt(s.hasInit).padEnd(9) +
				fmt(s.hasStart).padEnd(9) +
				fmt(s.isInitialized)
		);
		if (s.error) {
			console.log("    ERROR require: " + s.error);
		}
	}

	console.log("");
	console.log("JUGADORES EN LA SESION");
	if (!probe.players.length) console.log("  (ninguno)");
	for (const p of probe.players) {
		console.log(`  ${p.name}: character=${p.hasCharacter} humanoid=${p.hasHumanoid} health=${p.health} pos=${p.pos}`);
	}

	console.log("");
	console.log("PARTES POR CONTENEDOR DE WORKSPACE");
	for (const w of probe.workspace) console.log("  " + w);

	const alive = probe.players.some((p) => p.hasHumanoid);
	const noStart = probe.services.filter((s) => s.hasInit && !s.hasStart).map((s) => s.name);

	console.log("");
	console.log(`servicios sin require error: ${probe.services.length - probe.errors.length}/${probe.services.length}`);
	console.log(`servicios sin Start(): ${noStart.length} (${noStart.join(", ") || "ninguno"})`);
	console.log("");

	// NOTA SOBRE LA COLUMNA "arrancado"
	// ---------------------------------
	// Ningun servicio de este proyecto publica un campo `IsStarted`: el
	// ciclo de vida real lo lleva `ServiceRegistry` (`State` por servicio), que
	// es un objeto local de `ServerMain` y no se expone por ningun canal.
	//
	// Antes esta comprobacion leia `res.IsStarted` y lo imprimia como si
	// significara algo: daba `nil` para TODOS los servicios, de modo que la
	// linea "servicios no arrancados" los listaba a los 31 y provocaba el
	// fallo del gate con un servicio (PortalService) que si habia arrancado.
	//
	// Se contrasta con el estado que el juego SI publica por jugador
	// (`IsInitialized`) y con la evidencia observable: si el jugador tiene
	// personaje, Humanoid y vida, el arranque llego hasta el final.
	const initializedCount = probe.services.filter((s) => s.isInitialized === true).length;
	console.log(`servicios con IsInitialized = true: ${initializedCount}/${probe.services.length}`);
	console.log(
		initializedCount === probe.services.length
			? "arranque: TODOS los servicios inicializados"
			: `arranque: ${probe.services.length - initializedCount} servicio(s) sin inicializar`
	);
	console.log(alive ? "JUEGO ARRANCADO: PASS" : "JUEGO ARRANCADO: SIN JUGADOR VIVO");
	if (!alive) process.exitCode = 1;
}

main().catch((e) => {
	console.error("FALLO: " + e.message);
	process.exitCode = 2;
});
