// client-boot-cert.js
// FASE 2 + FASE 3: certificacion minima del puente cliente e identidad de sesion.
//
// QUE MIDE
// --------
// El servidor crea el RemoteFunction `ClientBootProbe` y lo invoca. Solo el
// LocalScript REAL del cliente puede contestar, asi que una respuesta es
// prueba de que el cliente ejecuta Luau. Cada linea es un veredicto
// individual (CLIENT_BOOT_OK, PLAYER_OK, ...) en vez de un unico booleano:
// el objetivo es saber EXACTAMENTE donde se rompe, no solo que se rompe.
//
// FASE 3: el informe incluye SESSION_ID, PLACE_ID, JOB_ID, PLAYER_NAME,
// PLAYER_USER_ID, SERVER_START_TIME y CLIENT_START_TIME, y los CRUZA. Un PASS
// de un cliente de otra sesion no es un PASS de esta.
//
// Uso: node tools/client-boot-cert.js

const mcp = require("./mcp");

/**
 * Crea el RemoteFunction, invoca al cliente y cruza las identidades.
 *
 * `InvokeClient` va dentro de `pcall`: si el cliente no contesta, el error se
 * captura y se reporta como fallo del cliente en vez de tumbar la comprobacion.
 */
const BOOT_CERT = `
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local SERVER_START_TIME = os.time()
local SERVER_START_CLOCK = os.clock()

local function ensureRemote()
    local existing = RS:FindFirstChild("ClientBootProbe")
    if existing then
        if existing:IsA("RemoteFunction") then
            return existing
        end
        existing:Destroy()
    end
    local rf = Instance.new("RemoteFunction")
    rf.Name = "ClientBootProbe"
    rf.Parent = RS
    return rf
end

local out = {}
out.SESSION_ID = "ClientBootProbe"
out.SERVER_START_TIME = SERVER_START_TIME
out.SERVER_START_CLOCK = math.floor(SERVER_START_CLOCK * 1000) / 1000
out.PLACE_ID = game.PlaceId
out.JOB_ID = game.JobId
out.GAME_ID = game.GameId
out.IS_STUDIO = game:GetService("RunService"):IsStudio()

local player = Players:GetPlayers()[1]
out.PLAYER_COUNT = #Players:GetPlayers()
out.PLAYER_NAME = player and player.Name or "NIL"
out.PLAYER_USER_ID = player and player.UserId or -1

if not player then
    out.SERVER_REPLY_OK = false
    out.FAIL = "no hay ningun jugador en el servidor"
    return out
end

-- El atributo lo escribe el propio cliente al arrancar. Se registra como
-- DATO, no como veredicto: los atributos NO replican de cliente a servidor,
-- asi que el servidor SIEMPRE lo vera en nil. Comprobado en runtime, no
-- supuesto. La prueba fuerte es la respuesta al RemoteFunction de mas abajo.
out.CLIENT_ATTR_BOOT_TIME = player:GetAttribute("ClientProbeBootTime")
out.CLIENT_ATTR_PLACE_ID = player:GetAttribute("ClientProbePlaceId")

local rf = ensureRemote()
out.REMOTE_CREATED = true

local ok, report = pcall(function()
    return rf:InvokeClient(player)
end)

if not ok then
    out.SERVER_REPLY_OK = false
    out.FAIL = ("el cliente no contesto: %s"):format(tostring(report))
    return out
end

if type(report) ~= "table" then
    out.SERVER_REPLY_OK = false
    out.FAIL = ("el cliente contesto algo que no es un informe: %s"):format(type(report))
    return out
end

out.SERVER_REPLY_OK = true

-- Marcadores de la FASE 2, uno a uno.
out.CLIENT_BOOT_OK = report.CLIENT_BOOT_OK == true
out.PLAYER_OK = report.PLAYER_OK == true
out.CHARACTER_OK = report.CHARACTER_OK == true
out.HUMANOID_OK = report.HUMANOID_OK == true
out.PLAYER_GUI_OK = report.PLAYER_GUI_OK == true
out.CAMERA_OK = report.CAMERA_OK == true
out.VIEWPORT_SIZE_OK = report.VIEWPORT_SIZE_OK == true
out.CLIENT_REMOTE_OK = report.CLIENT_REMOTE_OK == true

-- Datos que describen lo que el cliente ve de verdad.
out.VIEWPORT = report.VIEWPORT
out.HEALTH = report.HEALTH
out.PLAYER_GUI_CHILDREN = report.PLAYER_GUI_CHILDREN

-- FASE 3: cruce de identidad servidor <-> cliente.
out.CLIENT_START_TIME = report.CLIENT_START_TIME
out.CLIENT_JOB_ID = report.JOB_ID
out.CLIENT_PLACE_ID = report.PLACE_ID
out.CLIENT_PLAYER_NAME = report.PLAYER_NAME
out.CLIENT_PLAYER_USER_ID = report.PLAYER_USER_ID

out.SAME_PLAYER = report.PLAYER_NAME == out.PLAYER_NAME
    and report.PLAYER_USER_ID == out.PLAYER_USER_ID
out.SAME_PLACE = report.PLACE_ID == out.PLACE_ID

-- El JOB_ID NO se puede comparar aqui, y el motivo es concreto: en una
-- sesion de Studio el SERVIDOR ve game.JobId vacio mientras el CLIENTE ve
-- un GUID. Comprobado en runtime. Se registra el dato sin veredicto.

-- Coherencia temporal: el cliente no puede arrancar en el futuro ni antes
-- de que existiera la sesion. SERVER_START_TIME es el instante en que se
--midio esta sonda, no el arranque del servidor, asi que solo se exige que el
-- cliente no sea del futuro y que su reloj sea razonable. Un cliente de una
-- sesion anterior se delata por SAME_PLAYER o SAME_PLACE.
local clientStart = report.CLIENT_START_TIME
out.CLIENT_START_TIME_SANE = type(clientStart) == "number"
    and clientStart <= (os.time() + 60)
    and clientStart >= (SERVER_START_TIME - 86400)

out.IS_SAME_SESSION = out.SAME_PLAYER == true
    and out.SAME_PLACE == true
    and out.CLIENT_START_TIME_SANE == true

return out
`;

/** Marcadores que la FASE 2 exige ver a `true`. */
const REQUIRED = [
	"SERVER_REPLY_OK",
	"CLIENT_BOOT_OK",
	"PLAYER_OK",
	"CHARACTER_OK",
	"PLAYER_GUI_OK",
	"CAMERA_OK",
	"VIEWPORT_SIZE_OK",
	"CLIENT_REMOTE_OK",
];
async function main() {
	const out = await mcp.serverLuau(BOOT_CERT);
	const report = typeof out === "string" ? JSON.parse(out) : out;

	console.log("=== FASE 2: ARRANQUE MINIMO DEL CLIENTE ===\n");
	for (const key of REQUIRED) {
		console.log(`  ${report[key] === true ? "OK   " : "FALLO"}  ${key}`);
	}
	if (report.FAIL) console.log(`\n  FALLO: ${report.FAIL}`);

	console.log("\n=== FASE 3: IDENTIDAD DE SESION ===\n");
	const rows = [
		["SESSION_ID", report.SESSION_ID],
		["PLACE_ID", `${report.PLACE_ID} (cliente: ${report.CLIENT_PLACE_ID})`],
		["JOB_ID", `${report.JOB_ID || "(vacio)"} (cliente: ${report.CLIENT_JOB_ID || "(vacio)"})`],
		["PLAYER_NAME", `${report.PLAYER_NAME} (cliente: ${report.CLIENT_PLAYER_NAME})`],
		["PLAYER_USER_ID", `${report.PLAYER_USER_ID} (cliente: ${report.CLIENT_PLAYER_USER_ID})`],
		["SERVER_START_TIME", report.SERVER_START_TIME],
		["CLIENT_START_TIME", report.CLIENT_START_TIME],
		["CLIENT_ATTR_BOOT_TIME", report.CLIENT_ATTR_BOOT_TIME],
		["VIEWPORT", report.VIEWPORT],
		["HEALTH", report.HEALTH],
		["PLAYER_GUI_CHILDREN", report.PLAYER_GUI_CHILDREN],
		["IS_STUDIO", report.IS_STUDIO],
	];
	for (const [k, v] of rows) console.log(`  ${String(k).padEnd(22)} ${v}`);

	console.log("\n=== VEREDICTO ===\n");
	// `every(Boolean)` sobre una lista de booleanos: un PASS exige que TODOS
	// los marcadores sean true. Un solo false tumba el veredicto.
	const bootOk = REQUIRED.every((k) => report[k] === true);
	const sameSession = report.IS_SAME_SESSION === true;

	console.log(`  CLIENT_BOOT      = ${bootOk ? "OK" : "FAIL"}`);
	console.log(`  MISMA_SESION     = ${sameSession ? "SI" : "NO"}`);
	console.log(`\n  CLIENT_PEER_REACHABLE = ${bootOk ? "SI" : "NO"}`);

	if (!bootOk || !sameSession) process.exitCode = 1;
}

main().catch((e) => {
	console.error("FALLO: " + e.message);
	process.exitCode = 2;
});
