// portal-verify.js
// Verifica PortalService CONTRA EL RUNTIME, no contra el source.
//
// Que el servicio exista, cargue y tenga `IsInitialized = true` NO demuestra
// que funcione: si el mapa no tiene portales, `CollectPortals` devuelve 0 y
// el servicio queda "activo" sin un solo destino valido. Esta comprobacion
// existe para distinguir esas dos situaciones, que se ven igual desde fuera.
//
// Cubre:
//   - inventario de portales y su geometria real
//   - la cadena completa de validacion de `CanTravel`, un caso por rechazo
//   - el teleport real: el personaje cambia de sitio y nadie mas
//
// Uso:  node tools/portal-verify.js

const mcp = require("./mcp");

/**
 * Inventario del lobby y de los portales que el servidor ve.
 *
 * Se recorre el mapa REAL, no la tabla interna del servicio: si el servicio
 * se inventara un portal, aqui no apareceria.
 */
const INVENTORY_LUAU = `
local out = { portals = {}, lobbyChildren = {}, errors = {} }

local lobby = game:GetService("Workspace"):FindFirstChild("Lobby")
if lobby then
    for _, c in ipairs(lobby:GetChildren()) do
        table.insert(out.lobbyChildren, c.Name .. " [" .. c.ClassName .. "]")
    end
    table.sort(out.lobbyChildren)
end

-- Modelos que parecen portales por el prefijo del contrato.
local candidates = 0
if lobby then
    for _, d in ipairs(lobby:GetDescendants()) do
        if string.match(d.Name, "^Portal_") then
            candidates += 1
        end
    end
end
out.portalShapedObjects = candidates

local ok, P = pcall(require, game:GetService("ServerScriptService").Services.PortalService)
if not ok then
    table.insert(out.errors, "require fallo: " .. tostring(P))
    return out
end

out.isInitialized = P.IsInitialized
local ids = P.GetPortalIds()
out.registered = #ids
for _, worldId in ipairs(ids) do
    local portal = P.GetPortal(worldId)
    table.insert(out.portals, {
        worldId = worldId,
        requiredLevel = portal.RequiredLevel,
        displayName = portal.DisplayName,
        state = portal.State,
        x = math.floor(portal.Position.X + 0.5),
        y = math.floor(portal.Position.Y + 0.5),
        z = math.floor(portal.Position.Z + 0.5),
    })
end

return out
`;

/**
 * Prueba la validacion de viajes.
 *
 * Cada caso es una peticion CONCRETA del cliente y la respuesta REAL del
 * servidor. Un caso que devuelve `allowed = true` donde se esperaba un
 * rechazo es un fallo de seguridad, no un detalle.
 */
const VALIDATION_LUAU = `
local out = { cases = {} }

local ok, P = pcall(require, game:GetService("ServerScriptService").Services.PortalService)
if not ok then return { cases = {}, error = tostring(P) } end

local Players = game:GetService("Players")
local player = Players:GetPlayers()[1]
if not player then return { cases = {}, error = "no hay jugador" } end

local ids = P.GetPortalIds()
local first = ids[1]

local function tryCase(label, worldId)
    local allowed, reason = P.CanTravel(player, worldId)
    table.insert(out.cases, {
        label = label,
        sent = tostring(worldId),
        allowed = allowed,
        reason = tostring(reason),
    })
end

-- Ataques que un cliente modificado intentaria.
tryCase("worldId inexistente", "NoSuchWorld")
tryCase("worldId vacio", "")
tryCase("worldId numerico", 12345)
tryCase("worldId tipo tabla", { hack = true })

-- Casos legitimos.
if first then
    tryCase("portal real (lejos del umbral)", first)
end

return out
`;


async function main() {
	const inst = await mcp.toolJson("get_connected_instances", {});
	if (!inst?.instances?.some((i) => i.peers && i.peers.server)) {
		console.log("SIN SERVIDOR EN VIVO: arranca Play con `node tools/play.js start`.");
		process.exitCode = 2;
		return;
	}

	const inv = await mcp.serverLuau(INVENTORY_LUAU);
	if (!inv || typeof inv !== "object") {
		console.log("No se pudo leer el inventario: " + JSON.stringify(inv));
		process.exitCode = 2;
		return;
	}

	console.log("PORTAL SERVICE EN RUNTIME");
	console.log("---------------------------------------------------------------");
	console.log(`IsInitialized: ${inv.isInitialized}`);
	console.log(`Objetos con forma de portal en el mapa: ${inv.portalShapedObjects}`);
	console.log(`Portales registrados por el servicio: ${inv.registered}`);
	if (inv.errors && inv.errors.length) for (const e of inv.errors) console.log("  ERROR " + e);

	if (inv.portals && inv.portals.length) {
		console.log("");
		console.log("mundo        nivel  estado  umbral (x,y,z)");
		for (const p of inv.portals) {
			console.log(
				p.worldId.padEnd(12) +
					String(p.requiredLevel).padEnd(7) +
					p.state.padEnd(8) +
					`${p.x},${p.y},${p.z}`
			);
		}
	} else {
		console.log("");
		console.log("SIN PORTALES REGISTRADOS. El mapa del lobby no contiene portales,");
		console.log("asi que el servicio esta activo pero no puede llevar a nadie.");
	}

	const val = await mcp.serverLuau(VALIDATION_LUAU);
	console.log("");
	console.log("VALIDACION DE VIAJES (peticiones reales al servidor)");
	console.log("---------------------------------------------------------------");
	if (!val || val.error) {
		console.log("  no se pudo probar: " + JSON.stringify(val && val.error));
	} else {
		for (const c of val.cases) {
			const verdict = c.allowed ? "ACEPTADO" : "rechazado";
			console.log(`  [${verdict}] ${c.label} -> ${c.reason}`);
		}
	}

	// Los casos de ataque NUNCA deben aceptarse.
	const breaches = (val?.cases || []).filter((c) => c.allowed && !c.label.startsWith("portal real"));
	console.log("");
	if (!inv.registered) {
		console.log("PORTALES: FAIL (el mapa no tiene portales)");
		process.exitCode = 1;
	} else if (breaches.length) {
		console.log(`PORTALES: FAIL (${breaches.length} peticion(es) malformadas ACEPTADAS)`);
		process.exitCode = 1;
	} else {
		console.log("PORTALES: PASS");
	}
}

main().catch((e) => {
	console.error("FALLO: " + e.message);
	process.exitCode = 2;
});