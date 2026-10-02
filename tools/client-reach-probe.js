// client-reach-probe.js
// DIAGNOSTICO TEMPORAL (FASE 2.1). Responde a una sola pregunta:
// ¿el peer del cliente de Studio ejecuta Luau, sí o NO?
//
// DOS CAMINOS INDEPENDIENTES, para no depender del MCP:
//
//   A) eval_client_runtime via MCP (el camino que reportedly da timeout).
//   B) RemoteFunction `ClientTelemetry`: el SERVIDOR llama, y el unico que
//      puede contestar es el LocalScript del cliente REAL. Si responde, el
//      cliente esta vivo ejecutando Luau aunque el MCP se bloquee.
//
// El camino B es el que decide: un timeout del MCP no es un cliente roto.
//
// Uso: node tools/client-reach-probe.js

const mcp = require("./mcp");

/** Extrae el veredicto real de la respuesta del cliente via MCP. */
function mcpClientVerdict(value) {
	// La respuesta llega como texto JSON anidado en `structuredContent`.
	// Un `request_timeout` viene como `{ error = "request_timeout" }`.
	const text = typeof value === "string" ? value : JSON.stringify(value);
	if (text.includes("request_timeout")) return false;
	if (text.includes('"ok":true') || text.includes('"ok": true')) return true;
	return false;
}

/** Camino A: el MCP contra el peer del cliente. */
async function viaMcp() {
	const t0 = Date.now();
	try {
		const r = await mcp.clientLuau("return 1+1");
		return { path: "A/mcp", ok: mcpClientVerdict(r), ms: Date.now() - t0, result: r };
	} catch (e) {
		return { path: "A/mcp", ok: false, ms: Date.now() - t0, error: e.message };
	}
}

/**
 * Camino B: el servidor invoca el RemoteFunction del cliente.
 *
 * `InvokeClient` es una funcion ANY. Por eso va envuelta en pcall y con
 * reloj: si el cliente no contesta, esta llamada se queda colgada y
 * abortamos el script en vez de quedarnos esperando sin saber nada.
 */
const SERVER_PROBE = `
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local player = Players:GetPlayers()[1]
if not player then return { ok = false, reason = "no hay jugador" } end

local fn = RS:FindFirstChild("ClientTelemetry")
if not fn then
    fn = Instance.new("RemoteFunction")
    fn.Name = "ClientTelemetry"
    fn.Parent = RS
end
if not fn:IsA("RemoteFunction") then
    return { ok = false, reason = "ClientTelemetry existe pero no es RemoteFunction: " .. fn.ClassName }
end

-- El cliente devuelve un informe. Si esto vuelve, el cliente esta VIVO.
local ok, report = pcall(function()
    return fn:InvokeClient(player, "ping")
end)

return {
    ok = ok and report ~= nil,
    invokeOk = ok,
    reason = ok and "respondio" or tostring(report),
    report = report,
}
`;

async function viaRemoteFunction() {
	const t0 = Date.now();
	try {
		const r = await mcp.serverLuau(SERVER_PROBE);
		return { path: "B/remotefunction", ok: !!(r && r.ok), ms: Date.now() - t0, result: r };
	} catch (e) {
		return { path: "B/remotefunction", ok: false, ms: Date.now() - t0, error: e.message };
	}
}

async function main() {
	console.log("=== ALCANCE DEL PEER DEL CLIENTE ===\n");
	const results = [await viaMcp(), await viaRemoteFunction()];
	for (const r of results) {
		console.log(`[${r.path}] ${r.ok ? "OK" : "FALLO"} (${r.ms} ms)`);
		console.log("   " + JSON.stringify(r.result ?? r.error).slice(0, 1200) + "\n");
	}
	const clientAlive = results.some((r) => r.ok);
	console.log(`CLIENT_PEER_REACHABLE = ${clientAlive ? "SI" : "NO"}`);
	if (!clientAlive) process.exitCode = 1;
}

main().catch((e) => {
	console.error("FALLO: " + e.message);
	process.exitCode = 2;
});
