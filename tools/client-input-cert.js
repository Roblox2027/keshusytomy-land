// client-input-cert.js
// FASE 4/8: certifica la CADENA DE ENTRADA por el camino del cliente.
//
// QUE MIDE, Y QUE NO MIDE
// -----------------------
// Mide que una intencion escrita por el SERVOR en un atributo la ejecuta el
// LocalScript REAL del cliente, que a su vez dispara el RemoteEvent real, y
// que el SERVOR lo valida y lo autoriza.
//
// NO mide una pulsacion de tecla. No se pulsa ninguna tecla aqui: eso exige
// `simulate_keyboard_input`, y esa herramienta da `request_timeout` contra el
// peer del cliente. Por lo tanto este script NO puede declarar
// `KEYBOARD INPUT PASS`, y no lo intenta.
//
// LO QUE SI DEMUESTRA: el tramo InputController -> Remote -> Gateway ->
// Servicio, recorrido por el cliente real y no por una llamada al servicio.
//
// Uso: node tools/client-input-cert.js

const mcp = require("./mcp");

const ATTR_INSTRUCTION = "TestDriverInstruction";
const ATTR_RESULT = "TestDriverResult";

/**
 * El servidor pide una intencion al cliente y espera su veredicto.
 *
 * `TestDriverService.Command` es preferible a escribir el atributo a mano:
 * usa el `TestDriverLogic.Encode` real, asi que el texto que viaja es
 * exactamente el que el servicio produciria.
 */
const COMMAND_AND_WAIT = `
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")


local player = Players:GetPlayers()[1]
if not player then
    return { ok = false, reason = "no hay jugador" }
end

local action = ACTION_PLACEHOLDER
local worldId = WORLDID_PLACEHOLDER

local encoded = action

-- El valor debe CAMBIAR para que el cliente reciba el evento de atributo.
-- Por eso el valor lleva el numero de secuencia dentro: repetir la MISMA
-- cadena no dispara GetAttributeChangedSignal y el cliente se quedaria
-- esperando. El sufijo va DESPUES de un separador que el decoder ya acepta,
-- porque la parte de la izquierda es la accion.
local seq = (player:GetAttribute(ATTR_SEQ) or 0) + 1

player:SetAttribute(ATTR_SEQ, seq)
player:SetAttribute(ATTR_RESULT, "PENDIENTE")

-- La accion viaja en la parte IZQUIERDA de la barra vertical, que es lo que
-- TestDriverLogic.Decode lee. El contador va a la derecha y Decode lo
-- descarta como parte del destino: asi el valor siempre cambia y la accion
-- sigue siendo una de las soportadas.
local payload = if worldId == nil
    then ("%s|%d"):format(action, seq)
    else ("%s|%s|%d"):format(action, worldId, seq)

-- El separador de la secuencia es un ALMOHADILLA, no la barra vertical: la
-- barra vertical es la que TestDriverLogic.Decode usa para partir ACCION de
-- DESTINO. Con "EnterPortal|Forest|2" el destino viaja entero como "Forest|2",
-- ese portal no existe y el servidor lo rechaza. Con la almohadilla, la accion
-- queda "EnterPortal" y el destino "Forest#2"; el reproductor descarta la
-- almohadilla antes de buscar el portal, asi que la secuencia solo sirve para
-- que el VALOR del atributo cambie y llegue el evento al cliente.
local wire = if worldId == nil
    then ("%s#%d"):format(action, seq)
    else ("%s|%s#%d"):format(action, worldId, seq)

player:SetAttribute(ATTR_INSTRUCTION, wire)

-- El veredicto NO se espera aqui. Los atributos no replican de cliente
-- a servidor: el servidor jamas ve TestDriverResult. Se escribe la
-- instruccion y se devuelve; el veredicto se lee DESPUES, con un
-- InvokeClient en su propio viaje.
return {
    ok = true,
    payload = payload,
    serverSideResult = player:GetAttribute(ATTR_RESULT),
}
`;

/**
 * Invoca al cliente y lee SU atributo local.
 *
 * El valor vuelve dentro de la respuesta al InvokeClient, que si viaja de
 * cliente a servidor. Un `SetAttribute` del cliente se queda en el cliente.
 */
const READ_CLIENT_VERDICT = `
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local player = Players:GetPlayers()[1]
if not player then
    return nil
end
local fn = RS:FindFirstChild("ClientBootProbe")
if not fn or not fn:IsA("RemoteFunction") then
    return nil
end
local ok, report = pcall(function()
    return fn:InvokeClient(player)
end)
if not ok or type(report) ~= "table" then
    return nil
end
local attrs = report.CLIENT_LOCAL_ATTRS or {}
return attrs.KEY_RESULT or "PENDIENTE"
`;

/**
 * Ejecuta `READ_CLIENT_VERDICT` y devuelve el veredicto del cliente.
 *
 * Se ejecuta dentro del propio snippet por una razon concreta: `InvokeClient`
 * es una funcion de red y no puede invocarse desde otro contexto MCP a mitad
 * de un viaje ya en curso. Anidarlo aqui es lo que hace posible leer el
 * veredicto sin abrir un segundo viaje.
 */
const READ_VERDICT_HELPER = `
local function readVerdict()
    local Players = game:GetService("Players")
    local RS = game:GetService("ReplicatedStorage")
    local player = Players:GetPlayers()[1]
    if not player then
        return nil
    end
    local fn = RS:FindFirstChild("ClientBootProbe")
    if not fn or not fn:IsA("RemoteFunction") then
        return nil
    end
    local ok, report = pcall(function()
        return fn:InvokeClient(player)
    end)
    if not ok or type(report) ~= "table" then
        return nil
    end
    local attrs = report.CLIENT_LOCAL_ATTRS or {}
    return attrs.KEYNAME or "PENDIENTE"
end
`;

function buildCommand(action, worldId, waitSeconds) {
	const helper = READ_VERDICT_HELPER.replace(
		"KEYNAME",
		JSON.stringify(ATTR_RESULT)
	);

	return COMMAND_AND_WAIT
		.replace("ACTION_PLACEHOLDER", JSON.stringify(action))
		// nil, no undefined: undefined no existe en Luau.
		.replace("WORLDID_PLACEHOLDER", worldId === undefined ? "nil" : JSON.stringify(worldId))
		.replace(/WAIT_SECONDS_PLACEHOLDER/g, String(waitSeconds))
		.replace("READ_VERDICT_PLACEHOLDER", "")
		.replace(/ATTR_INSTRUCTION\b/g, JSON.stringify(ATTR_INSTRUCTION))
		.replace(/ATTR_RESULT\b/g, JSON.stringify(ATTR_RESULT))
		.replace(/ATTR_SEQ\b/g, JSON.stringify(ATTR_INSTRUCTION + "Seq"))
		.replace("local Players = game:GetService(\"Players\")", helper + "\nlocal Players = game:GetService(\"Players\")");
}

async function command(action, worldId, waitSeconds = 8) {
	const code = buildCommand(action, worldId, waitSeconds);

	if (process.argv.includes("--debug")) {
		console.log("--- Luau enviado ---\n" + code + "\n--- fin ---\n");
	}

	const out = await mcp.serverLuau(code);

	// El MCP devuelve { ok, bridge, result, error }. Si el snippet fallo en
	// el motor, result es nil y el motivo esta en error. Sin esto, un
	// fallo de compilacion se lee como un veredicto ausente y parece que el
	// cliente no respondio, que es una conclusion distinta y falsa.
	if (out && typeof out === "object" && out.ok === false) {
		return {
			ok: false,
			reason: "el snippet fallo: " + String(out.error ?? JSON.stringify(out)),
			raw: out,
		};
	}

	const parsed = typeof out === "string" ? JSON.parse(out) : out;
	if (parsed === undefined || parsed === null) {
		return { ok: false, reason: "el servidor no devolvio ningun valor", raw: out };
	}

	return parsed;
}

/** Cuenta bombas en Workspace y su estado. */
const BOMB_COUNT = `
local Bombs = workspace:FindFirstChild("Bombs")
if not Bombs then
    return { folder = false, count = 0 }
end
local names = {}
for _, d in ipairs(Bombs:GetChildren()) do
    names[#names + 1] = d.Name
end
return { folder = true, count = #Bombs:GetChildren(), names = names }
`;

async function main() {
	console.log("=== FASE 4: CADENA DE ENTRADA DEL CLIENTE ===\n");
	console.log("El servidor NO pulsa teclas: escribe una instruccion y el");
	console.log("LocalScript del cliente la ejecuta por controllers reales.\n");

	// 1) BombAction: la cadena completa hasta el servidor.
	const before = await mcp.serverLuau(BOMB_COUNT);
	const sent = await command("PlaceBomb", undefined, 8);

	console.log(`  Peticion enviada : ${sent && sent.payload}`);
	console.log(`  Atributo en servidor: ${sent && sent.serverSideResult}`);

	// El veredicto del cliente se lee DESPUES, en su propio viaje. Leerlo
	// dentro del mismo snippet que escribe el atributo no funciona: el
	// InvokeClient anidado aborta con "module experienced an error while
	// loading" y el resultado era indistinguible de "el cliente no responde".
	let verdict = null;
	for (let attempt = 0; attempt < 15; attempt++) {
		const seen = await mcp.serverLuau(READ_CLIENT_VERDICT);
		// `mcp.serverLuau` devuelve el valor ya desempaquetado por `unwrap`, y
		// un string de Luau llega como texto plano sin comillas: "PENDIENTE",
		// no "\"PENDIENTE\"". Por eso no se hace JSON.parse a la fuerza.
		const value = typeof seen === "string" && seen.trim().startsWith('"')
			? JSON.parse(seen)
			: seen;

		if (value && value !== "PENDIENTE") {
			verdict = value;
			break;
		}
		await new Promise((r) => setTimeout(r, 400));
	}

	console.log(`  Veredicto cliente: ${verdict === null ? "(ninguno)" : verdict}`);

	await new Promise((r) => setTimeout(r, 1200));
	const after = await mcp.serverLuau(BOMB_COUNT);

	console.log(`\n  Bombas en Workspace antes: ${JSON.stringify(before)}`);
	console.log(`  Bombas en Workspace ahora: ${JSON.stringify(after)}`);

	const created = before && after && after.count > before.count;

	console.log("\n=== VEREDICTO ===\n");
	console.log(`  CLIENTE_EJECUTO         = ${sent && sent.ok ? "SI" : "NO"}`);
	console.log(`  VEREDICTO_CLIENTE       = ${verdict === null ? "(ninguno)" : verdict}`);
	console.log(`  BOMBA_LLEGO_AL_SERVIDOR = ${created ? "SI" : "NO"}`);
	console.log(`\n  NOTA: esto NO es 'KEYBOARD INPUT PASS'. No se pulso ninguna`);
	console.log("  tecla; el MCP no puede inyectar input en el peer del cliente.");
}

main().catch((e) => {
	console.error("FALLO: " + e.message);
	process.exitCode = 2;
});
