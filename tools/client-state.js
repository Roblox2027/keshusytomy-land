// client-state.js
// Lee el estado REAL del cliente a traves del RemoteFunction `ClientBootProbe`.
//
// POR QUE EXISTE
// --------------
// El MCP no puede ejecutar Luau en el peer del cliente (`request_timeout`),
// y `simulate_keyboard_input` tampoco. Ese hueco se cubre con un RemoteFunction
// que contesta un LocalScript real, que es la unica via que queda para leer
// el cliente sin mentir sobre como se obtuvo el dato.
//
// NO sirve para declarar un PASS de input: aqui no se pulsa ninguna tecla. Sirve
// para observar lo que el cliente ya tiene: controllers arrancados, HUD
// pintado y atributos publicados por el servidor.
//
// Uso:
//   node tools/client-state.js
//   node tools/client-state.js --json

const mcp = require("./mcp");

const PROBE = `
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local player = Players:GetPlayers()[1]
if not player then
    return { ok = false, reason = "no hay jugador" }
end

local fn = RS:FindFirstChild("ClientBootProbe")
if not fn or not fn:IsA("RemoteFunction") then
    return { ok = false, reason = "no existe ClientBootProbe" }
end

local ok, report = pcall(function()
    return fn:InvokeClient(player)
end)

if not ok then
    return { ok = false, reason = tostring(report) }
end

return { ok = true, report = report }
`;

function printState(report) {
	console.log("=== CONTROLLERS DEL CLIENTE ===\n");
	const controllers = report.CONTROLLERS || {};
	for (const [name, c] of Object.entries(controllers)) {
		if (c.error) {
			console.log(`  ${name.padEnd(18)} ERROR: ${c.error}`);
			continue;
		}
		console.log(`  ${name.padEnd(18)} activo=${c.ACTIVE}  cooldown=${c.COOLDOWN}`);
		if (c.STATE && typeof c.STATE === "object") {
			for (const [k, v] of Object.entries(c.STATE)) {
				console.log(`      ${k.padEnd(18)} ${v}`);
			}
		}
		if (Array.isArray(c.PORTALS) && c.PORTALS.length) {
			console.log(`      portales conocidos: ${c.PORTALS.join(", ")}`);
		}
	}

	console.log("\n=== HUD (texto real en pantalla) ===\n");
	const hud = report.HUD_TEXT || [];
	if (hud.length === 0) console.log("  (ninguna etiqueta con texto)");
	for (const line of hud) console.log(`  ${line}`);

	if (report.HUD_PORTAL_BUTTON) {
		const b = report.HUD_PORTAL_BUTTON;
		console.log(`\n  Boton de portal: visible=${b.visible}  texto="${b.text}"`);
	}

	console.log("\n=== ATRIBUTOS PUBLICADOS POR EL SERVIDOR ===\n");
	for (const [k, v] of Object.entries(report.ATTRS || {})) {
		console.log(`  ${k.padEnd(20)} ${v}`);
	}
}

async function main() {
	const out = await mcp.serverLuau(PROBE);
	const data = typeof out === "string" ? JSON.parse(out) : out;

	if (!data || data.ok !== true) {
		console.error("FALLO: " + (data && data.reason ? data.reason : JSON.stringify(data)));
		process.exitCode = 1;
		return;
	}

	if (process.argv.includes("--json")) {
		console.log(JSON.stringify(data.report, null, 2));
		return;
	}

	printState(data.report);
}

main().catch((e) => {
	console.error("FALLO: " + e.message);
	process.exitCode = 2;
});
