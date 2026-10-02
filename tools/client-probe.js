// client-probe.js
// Consulta la TELEMETRIA REAL DEL CLIENTE y, con `layout`, el mapa real.
//
// Uso:  node tools/client-probe.js          # estado del cliente
//       node tools/client-probe.js layout   # donde esta cada cosa
//
// POR QUE EXISTE
// --------------
// Todas las herramientas MCP que deberian hablar con el cliente
// (`eval_client_runtime`, `execute_luau` con target=client-1,
// `capture_screenshot`, `get_simulation_state` con target=client-1) devuelven
// `request_timeout ... stage: executing` contra el peer del cliente, aunque el
// cliente este perfectamente vivo. Esas tools dependen del puente MCP, que en
// esta instalacion no logra que el cliente ejecute lo que se le pide.
//
// Que un tool se bloquee NO significa que el cliente este roto. Este script
// obtiene la misma informacion por un camino INDEPENDIENTE: el servidor
// pregunta al cliente mediante un RemoteFunction (`ClientTelemetry`), que
// contesta `src/StarterPlayer/StarterPlayerScripts/ClientTelemetry.client.lua`.
//
// Uso:  node tools/client-probe.js

const mcp = require("./mcp");

/** Luau que mide el mapa real: donde esta cada cosa y que hay alrededor. */
const LAYOUT_PROBE = `
local out = { folders = {}, parts = {}, near = {} }

for _, child in ipairs(workspace:GetChildren()) do
    table.insert(out.folders, child.Name .. " [" .. child.ClassName .. "]")
end

-- Bounding box y numero de Parts de cada Folder del mundo.
local function describe(instance)
    if not instance then return nil end
    local count = 0
    local minv = Vector3.new(math.huge, math.huge, math.huge)
    local maxv = Vector3.new(-math.huge, -math.huge, -math.huge)
    for _, d in ipairs(instance:GetDescendants()) do
        if d:IsA("BasePart") then
            count += 1
            local p = d.Position
            minv = Vector3.new(math.min(minv.X, p.X), math.min(minv.Y, p.Y), math.min(minv.Z, p.Z))
            maxv = Vector3.new(math.max(maxv.X, p.X), math.max(maxv.Y, p.Y), math.max(maxv.Z, p.Z))
        end
    end
    if count == 0 then
        return { parts = 0 }
    end
    return {
        parts = count,
        min = string.format("%.0f,%.0f,%.0f", minv.X, minv.Y, minv.Z),
        max = string.format("%.0f,%.0f,%.0f", maxv.X, maxv.Y, maxv.Z),
        center = string.format("%.0f,%.0f,%.0f", (minv.X+maxv.X)/2, (minv.Y+maxv.Y)/2, (minv.Z+maxv.Z)/2),
    }
end

out.parts.Workspace = describe(workspace)
out.parts.Lobby = describe(workspace:FindFirstChild("Lobby"))
local worlds = workspace:FindFirstChild("Worlds")
if worlds then
    for _, w in ipairs(worlds:GetChildren()) do
        out.parts["Worlds/" .. w.Name] = describe(w)
    end
end

-- Los 20 Parts mas cercano al jugador: es lo que esta viendo de verdad.
local p = game:GetService("Players"):GetPlayers()[1]
local root = p and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
if root then
    out.near.playerPos = string.format("%.0f,%.0f,%.0f", root.Position.X, root.Position.Y, root.Position.Z)
    local list = {}
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("BasePart") then
            table.insert(list, { n = d.Name, dist = (d.Position - root.Position).Magnitude, p = d.Position })
        end
    end
    table.sort(list, function(a, b) return a.dist < b.dist end)
    local lines = {}
    for i = 1, math.min(20, #list) do
        local it = list[i]
        table.insert(lines, string.format("%s | %.0f studs | %.0f,%.0f,%.0f", it.n, it.dist, it.p.X, it.p.Y, it.p.Z))
    end
    out.near.closest = lines
end

return out
`;

/** Luau que corre en el SERVIDOR y pregunta al cliente. */
const SERVER_PROBE = `
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local out = {}
local p = Players:GetPlayers()[1]
if not p then
    return { error = "no hay jugadores" }
end

out.player = p.Name
out.hasCharacter = p.Character ~= nil
local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
out.health = hum and hum.Health or -1
local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
out.pos = root and string.format("%.1f,%.1f,%.1f", root.Position.X, root.Position.Y, root.Position.Z) or "n/a"

-- El RemoteFunction lo crea el propio servidor: no forma parte del source.
local rf = ReplicatedStorage:FindFirstChild("ClientTelemetry")
if not rf then
    rf = Instance.new("RemoteFunction")
    rf.Name = "ClientTelemetry"
    rf.Parent = ReplicatedStorage
    out.remoteCreated = true
end

local ok, data = pcall(function()
    return rf:InvokeClient(p, 8)
end)

out.clientAnswered = ok and data ~= nil
out.client = out.clientAnswered and data or nil
if not out.clientAnswered then
    out.clientError = tostring(data)
end

return out
`;

async function main() {
	const mode = (process.argv[2] || "client").toLowerCase();

	if (mode === "forest") {
		// Como es el Forest por dentro: que hay, de que material y con que
		// nombres. Es lo que decide si el jugador ve un sitio o ve cubos.
		const forest = await mcp.toolJson("eval_server_runtime", {
			code: `
local world = workspace:FindFirstChild("Worlds"):FindFirstChild("Forest")
if not world then return "sin Forest" end

local names = {}
local materials = {}
local total = 0

for _, d in ipairs(world:GetDescendants()) do
    if d:IsA("BasePart") then
        total += 1
        local base = string.gsub(d.Name, "%d+$", "")
        names[base] = (names[base] or 0) + 1
        local mat = tostring(d.Material)
        materials[mat] = (materials[mat] or 0) + 1
    end
end

local out = { totalParts = total, byBaseName = {}, byMaterial = {}, children = {} }
for n, c in pairs(names) do out.byBaseName[n] = c end
for m, c in pairs(materials) do out.byMaterial[m] = c end
for _, c in ipairs(world:GetChildren()) do
    table.insert(out.children, c.Name .. " [" .. c.ClassName .. "]")
end
return out
`,
		});
		console.log(JSON.stringify(forest, null, 2));
		return;
	}

	if (mode === "spawnfix") {
		// HIPOTESIS A PROBAR
		// -----------------
		// La camara de Roblox NO sigue la orientacion del personaje: su yaw
		// es independiente. Al arrancar, el yaw mira hacia -Z. El spawn mas
		// cercano al Core esta en (0, -24), en el lado -Z, asi que el jugador
		// aparece DE ESPALDAS al Core y lo que ve es la pared del Lobby.
		//
		// Esto orienta cada SpawnLocation para que el jugador nazca mirando
		// al Core. Se prueba en runtime antes de tocar la fuente.
		const result = await mcp.toolJson("eval_server_runtime", {
			code: `
local out = {}
local folder = workspace:FindFirstChild("SpawnLocations")
if not folder then return "sin SpawnLocations" end

for _, spawn in ipairs(folder:GetDescendants()) do
    if spawn:IsA("SpawnLocation") then
        local pos = spawn.Position
        local flat = Vector3.new(pos.X, 0, pos.Z)
        if flat.Magnitude > 0.001 then
            -- El personaje nace mirando hacia su -Z local. Para que mire
            -- al Core hay que girar ese -Z hasta apuntar al origen.
            --
            -- Se usa CFrame y no la propiedad Orientation: en esta version
            -- de Studio esa propiedad es un Vector3 y no un numero, asi que
            -- asignarle un grado falla.
            spawn.CFrame = CFrame.lookAt(pos, Vector3.new(0, pos.Y, 0))
        end
        local look = spawn.CFrame.LookVector
        table.insert(out, ("%s en %.0f,%.0f,%.0f -> mira hacia %.2f,%.2f,%.2f"):format(
            spawn.Name, pos.X, pos.Y, pos.Z, look.X, look.Y, look.Z))
    end
end

-- Reaparece el jugador para que nazca ya orientado.
local p = game:GetService("Players"):GetPlayers()[1]
if p then p:LoadCharacter() end
return table.concat(out, "\\n")
`,
		});
		console.log(result);
		await new Promise((r) => setTimeout(r, 6000));
	}

	if (mode === "drift") {
		// El peer `edit` SI responde a `execute_luau` (a diferencia del
		// cliente), asi que el arbol real de Studio se puede inspeccionar.
		const drift = await mcp.toolJson("execute_luau", {
			operation_id: "probe-startergui-1",
			target: "edit",
			code: `
local out = {}
for _, service in ipairs({
    game:GetService("StarterGui"),
    game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts"),
    game:GetService("ReplicatedStorage"),
}) do
    local kids = {}
    for _, c in ipairs(service:GetChildren()) do
        table.insert(kids, c.Name .. " [" .. c.ClassName .. "]")
    end
    out[service:GetFullName()] = kids
end
return out
`,
		});
		console.log(JSON.stringify(drift, null, 2));
		return;
	}

	if (mode === "layout") {
		console.log(
			JSON.stringify(await mcp.toolJson("eval_server_runtime", { code: LAYOUT_PROBE }), null, 2)
		);
		return;
	}

	if (mode === "lobby" || mode === "facelobby") {
		// El ciclo de ronda teletransporta a la Arena a los pocos segundos,
		// asi que el Lobby solo existe durante unos segundos tras arrancar
		// Play. Para poder mirarlo, el servidor devuelve al jugador al
		// spawn del Lobby ANTES de medir. No borra nada: es un
		// teletransporte de diagnostico y la ronda lo revierte sola.
		//
		// Con `facelobby` ademas se ORIENTA al personaje hacia el Core:
		// la camara sigue al personaje, asi que es la forma de medir si
		// el problema es "no ve el Lobby" o "no mira hacia donde debe".
		const face = mode === "facelobby";

		const moved = await mcp.toolJson("eval_server_runtime", {
			code: `
local p = game:GetService("Players"):GetPlayers()[1]
if not p then return "sin jugador" end
local folder = workspace:FindFirstChild("SpawnLocations")
local best, bestDist = nil, math.huge
if folder then
    for _, d in ipairs(folder:GetDescendants()) do
        if d:IsA("SpawnLocation") then
            local dist = d.Position.Magnitude
            if dist < bestDist then
                bestDist = dist
                best = d
            end
        end
    end
end
if not best then return "sin SpawnLocation" end
if p.Character then
    local target = best.Position + Vector3.new(0, 3, 0)
    local frame = CFrame.new(target)
    if ${face} then
        -- Mirar hacia el Core, que esta en el origen del mapa.
        frame = CFrame.lookAt(target, Vector3.new(0, best.Position.Y, 0))
    end
    p.Character:PivotTo(frame)
end
return "movido a " .. best.Name .. ${face ? ' .. ", mirando al Core"' : ""}
`,
		});
		console.log("(diagnostico) " + (moved || "sin resultado"));

		// Se espera a que el movimiento se replique al cliente.
		await new Promise((r) => setTimeout(r, 2500));
	}

	const report = await mcp.toolJson("eval_server_runtime", { code: SERVER_PROBE });

	if (report && report.error) {
		console.log("ERROR: " + report.error);
		process.exitCode = 1;
		return;
	}

	console.log("=== SERVIDOR ===");
	console.log(`jugador   : ${report.player}`);
	console.log(`character : ${report.hasCharacter ? "si" : "no"}`);
	console.log(`vida      : ${report.health}`);
	console.log(`posicion  : ${report.pos}`);

	if (!report.clientAnswered) {
		console.log("");
		console.log("=== CLIENTE ===");
		console.log("SIN RESPUESTA: " + (report.clientError || "InvokeClient devolvio nil"));
		process.exitCode = 1;
		return;
	}

	const c = report.client;
	console.log("");
	console.log("=== CLIENTE (respuesta real) ===");
	console.log(`LocalPlayer      : ${c.localPlayer}`);
	console.log(`Character        : ${c.hasCharacter ? "si" : "no"}`);
	console.log(`Vida             : ${c.health}`);
	console.log(`Posicion         : ${c.pos}`);
	console.log(`CurrentCamera    : ${c.hasCamera ? "si" : "NO"}`);
	console.log(`Camara pos       : ${c.camPos}`);
	console.log(`Camara mira      : ${c.camLook}`);
	console.log(`Campo de vision  : ${c.camFov}`);
	console.log(`Viewport         : ${c.viewport}`);
	console.log(`PlayerGui        : ${c.hasPlayerGui ? "si" : "NO"}`);
	console.log(`  hijos          : ${(c.playerGuiChildren || []).join(", ") || "(ninguno)"}`);
	console.log("");
	console.log(`Zona            : ${c.zone}`);
	console.log(`Parts en vista  : ${c.visibleParts}`);
	console.log(`Ocluidas        : ${c.occludedParts}`);
	console.log(`Tapadas por     : ${c.occluders || "(ninguna)"}`);
	console.log("");
	console.log("--- Visibilidad por region (visibles/total) ---");
	for (const [region, ratio] of Object.entries(c.visiblePerRegion || {})) {
		console.log(`  ${region.padEnd(16)} ${ratio}`);
	}
	console.log("");
	console.log("--- Iluminacion ---");
	console.log(`ClockTime        : ${c.clockTime}`);
	console.log(`Brightness       : ${c.brightness}`);
	console.log(`Ambient          : ${c.ambient}`);
	console.log(`OutdoorAmbient   : ${c.outdoorAmbient}`);
	console.log(`GlobalShadows    : ${c.globalShadows}`);
	console.log(`FogEnd           : ${c.fogEnd}`);
	console.log(`Technology       : ${c.technology}`);
	console.log(`Sky              : ${c.hasSky ? "si" : "NO"}`);
	console.log("");
	console.log(`Worlds           : ${(c.worlds || []).join(", ") || "(ninguno)"}`);
	console.log(`Descendientes WS : ${c.workspaceDescendants}`);

	// Puerta honesta: sin camara o sin nada visible, el jugador no esta
	// viendo el juego por mucho que el servidor diga PASS.
	//
	// QUE ZONA MIDE. Antes exigia `visibleLobbyParts > 0` SIEMPRE, y eso
	// daba FAIL siendo el juego correcto: el ciclo de ronda lleva al
	// jugador a la Arena (x = 500), a 500 studs del Lobby, asi que alli el
	// Lobby no tiene por que verse. Medido con `tools/lobby-teleport-check.js`
	// el teleport al Lobby funciona y a los 500 ms el personaje esta en
	// (0, 5, -24); lo revierte la ronda despues.
	//
	// La puerta ahora pregunta lo que el jugador tiene delante en la zona en
	// la que esta, y ADEMAS exige que la zona se haya podido determinar: un
	// `zone` vacio significaria que el cliente no ve el mapa, y eso si es un
	// fallo. Se sigue exigiendo la camara y el PlayerGui.
	const inLobby = (c.zone || "").indexOf("Lobby") >= 0;
	const visibleInZone = inLobby ? (c.visibleLobbyParts || 0) : (c.visibleParts || 0);

	const failures = [];
	if (!c.hasCamera) failures.push("el cliente no tiene CurrentCamera");
	if (!c.hasPlayerGui) failures.push("el cliente no tiene PlayerGui");
	if (!c.zone) failures.push("no se pudo determinar la zona del cliente");
	if (visibleInZone <= 0) {
		failures.push(
			"no ve ninguna Part de la zona en la que esta ("
			+ c.zone + ", lobby=" + (c.visibleLobbyParts || 0) + ")"
		);
	}

	const ok = failures.length === 0;
	console.log(
		"Zona medida     : " + c.zone
		+ (inLobby ? "  (criterio: partes del Lobby)" : "  (criterio: partes de la zona actual)")
	);
	console.log(`CLIENTE VISUAL VERIFICATION = ${ok ? "PASS" : "FAIL"}`);
	for (const f of failures) console.log("  - " + f);
	if (!ok) process.exitCode = 1;
}

main().catch((e) => {
	console.error("FALLO: " + e.message);
	process.exitCode = 2;
});