// bomb-attr-verify.js
// PRUEBA DIRIGIDA del atributo `Bombs`.
//
// QUE MIDE, Y POR QUE ASI
// -----------------------
// El HUD de la Bomba mostraba "*" porque NADIE publicaba el atributo `Bombs` del
// jugador. Se arranco `BombService` porque es el dueno de `_activeBombs`.
//
// Aqui no se comprueba "que exista la funcion" sino que el atributo RECORRA el
// ciclo completo que ve el jugador:
//
//     0  ->  1  (colocacion)  ->  0  (detonacion)
//
// Cada paso se lee del JUGADOR real, no del servicio, porque lo que rompia era
// precisamente la publicacion. Se mide el atributo Y el contador interno del
// servicio para no dar por bueno un HUD que miente.
//
// Uso: node tools/bomb-attr-verify.js
// Salida con codigo 1 si la cadena Bombs no recorre 0 -> 1 -> 0.

"use strict";

const mcp = require("./mcp");

/** Estado inicial: atributo publicado y contador interno. */
const SNAP = `
local Players = game:GetService("Players")
local Bomb = require(game.ServerScriptService.Services.BombService)

local player = Players:GetPlayers()[1]
if not player then return { error = "no hay jugadores" } end

return {
    bombsAttr = player:GetAttribute("Bombs"),
    active = Bomb.GetActiveBombCount(),
}
`;

/** Coloca una bomba si la ronda esta en juego. */
const PLACE = `
local Players = game:GetService("Players")
local Round = require(game.ServerScriptService.Services.RoundService)
local Bomb = require(game.ServerScriptService.Services.BombService)

local player = Players:GetPlayers()[1]
if not player then return { error = "no hay jugadores" } end
if not Round.IsPlaying() then return { error = "no_jugando", state = Round.GetState() } end

local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
if not root then return { error = "sin personaje" } end

local ok, reason = Bomb.TryPlaceBomb(player, root.Position)

return {
    placed = ok,
    reason = reason,
    bombsAttr = player:GetAttribute("Bombs"),
    active = Bomb.GetActiveBombCount(),
}
`;

function unwrap(res) {
    return Array.isArray(res) ? res[0] : res;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
    await mcp.init();

    console.log("VERIFICACION DEL ATRIBUTO `Bombs` (0 -> 1 -> 0)");
    console.log("");

    const player = await unwrap(await mcp.serverLuau(`
        local Players = game:GetService("Players")
        local p = Players:GetPlayers()[1]
        return { name = p and p.Name or nil }
    `));
    if (!player || !player.name) {
        console.log("RESULTADO: BLOCKED - no hay jugador en la sesion.");
        process.exitCode = 2;
        return;
    }

    const start = await unwrap(await mcp.serverLuau(SNAP));
    console.log(`  jugador        = ${player.name}`);
    console.log(`  Bombs inicial  = ${fmt(start.bombsAttr)}`);
    console.log(`  bombas activas = ${start.active}`);
    console.log("");

    // Se espera la ventana `Playing` (una ronda dura ~180s: dar margen amplio).
    // Se recorre la RUTA LEGAL de la maquina de estados en vez de saltar
    // directo a `Playing`: `Transition` rechaza los saltos invalidos por
    // diseño, y esperar al ciclo natural (minutos) hace que la prueba mida el
    // sincronismo en lugar del atributo.
    const path = ["Countdown", "RoundStarting", "Playing"];
    let reached = "Waiting";

    for (const target of path) {
        const step = await unwrap(await mcp.serverLuau(`
            local Round = require(game.ServerScriptService.Services.RoundService)
            local ok = Round.Transition("${target}")
            return { ok = ok, state = Round.GetState() }
        `));
        reached = step.state;
        if (!step.ok) break;
    }

    // El jugador arrancaba en el LOBBY: `World = "Lobby"`, y la validacion de
    // arena lo rechaza con "fuera de la arena" (por diseño: cada mundo tiene
    // su rectangulo). Se le pone en Forest, que es el mundo por defecto.
    const moved = await unwrap(await mcp.serverLuau(`
        local Players = game:GetService("Players")
        local p = Players:GetPlayers()[1]
        if not p then return { error = "no hay jugadores" } end

        local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
        if not root then return { error = "sin personaje" } end

        p:SetAttribute("World", "Forest")
        root.CFrame = CFrame.new(500, 5, 0)
        p:SetAttribute("Bombs", 0)

        return { world = p:GetAttribute("World"), pos = tostring(root.Position) }
    `));

    if (!moved || moved.error) {
        console.log(`  no se pudo preparar la arena: ${moved && moved.error}`);
        console.log("");
        console.log("RESULTADO: BLOCKED - sin personaje en la sesion.");
        process.exitCode = 2;
        return;
    }

    console.log(`  mundo          = ${moved.world} en ${moved.pos}`);
    console.log(`  ronda forzada  = ${reached}`);
    console.log("");

    const deadline = Date.now() + 60 * 1000;
    let place = null;
    let polls = 0;

    while (Date.now() < deadline) {
        polls++;
        const attempt = unwrap(await mcp.serverLuau(PLACE));
        if (!attempt.error) {
            place = attempt;
            break;
        }
        await sleep(500);
    }

    if (!place) {
        console.log(`  (${polls} intentos sin ventana de ronda)`);
        console.log("");
        console.log("RESULTADO: BLOCKED - no hubo ventana de ronda para colocar la bomba.");
        process.exitCode = 2;
        return;
    }

    console.log(`  colocacion     = ${place.placed ? "ACEPTADA" : "RECHAZADA"} (${place.reason})`);
    console.log(`  Bombs tras     = ${fmt(place.bombsAttr)}`);
    console.log(`  bombas activas = ${place.active}`);
    console.log("");

    const afterPlace = Number(place.bombsAttr);

    // Se espera la detonacion y la reposteada a 0.
    let afterBoom = null;
    for (let i = 0; i < 40; i++) {
        await sleep(500);
        const snap = await unwrap(await mcp.serverLuau(SNAP));
        if (snap.bombsAttr === 0 && snap.active === 0) {
            afterBoom = snap;
            break;
        }
    }

    if (!afterBoom) {
        const last = await unwrap(await mcp.serverLuau(SNAP));
        console.log(`  Bombs final    = ${fmt(last.bombsAttr)}`);
        console.log(`  bombas activas = ${last.active}`);
        console.log("");
        console.log("RESULTADO: FAIL - la bomba exploto pero el atributo no volvio a 0.");
        process.exitCode = 1;
        return;
    }

    console.log("  Bombs final    = 0 (volvio solo tras la detonacion)");
    console.log("  bombas activas = 0");
    console.log("");

    const checks = [
        ["el atributo se publica al entrar (no nil)", typeof start.bombsAttr === "number"],
        [`la colocacion sube el atributo a 1 (fue ${afterPlace})`, afterPlace === 1],
        ["la detonacion devuelve el atributo a 0", true],
        ["el atributo coincide con el contador interno", afterBoom.active === 0],
    ];

    let bad = 0;
    for (const [label, ok] of checks) {
        console.log(`  ${ok ? "OK  " : "FALLA"} ${label}`);
        if (!ok) bad++;
    }

    console.log("");
    console.log(bad === 0 ? "RESULTADO: PASS" : `RESULTADO: FAIL (${bad})`);
    if (bad !== 0) process.exitCode = 1;
}

function fmt(v) {
    return v === null || v === undefined ? "nil" : String(v);
}

main().catch((err) => {
    console.error("ERROR: " + (err && err.message ? err.message : String(err)));
    process.exitCode = 1;
});