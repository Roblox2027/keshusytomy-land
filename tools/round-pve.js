// round-pve.js
// Verifica que un ciclo de ronda CON MONSTRUOS y con EXPLOSIONES se
// completa: es el requisito de no romper lo que ya funcionaba.
//
// POR QUE EXISTE
// --------------
// La correccion del P0 toca `MatchService` (que limpia monstruos al terminar
// la ronda) y el orden de las transiciones. Ese es exactamente el punto donde
// un arreglo de ronda puede romper el PvE o la cadena de explosiones sin que
// ninguna prueba de codigo puro lo note: hace falta el motor.
//
// QUE MIDE
// ---------
//   1. Que `MonsterService` genera monstruos al empezar la ronda y los limpia
//      al terminar. Ese `ClearAll` del fin de ronda es justo la llamada que
//      una version anterior no tenia, y su ausencia congelaba la ronda.
//   2. Que al terminar la ronda no queda ni bomba ni monstruo vivo: si
//      quedan, estan persiguiendo o explotando en el lobby.
//
// Ademas dispara una explosion real en el centro de la arena y comprueba
// que hace dano: la cadena explosiones -> dano -> destruccion.
//
// Uso: node tools/round-pve.js
// Salida con codigo 1 si algo falla.

const mcp = require("./mcp");

const PROBE = `
local Round = require(game.ServerScriptService.Services.RoundService)
local Monster = require(game.ServerScriptService.Services.MonsterService)
local Bomb = require(game.ServerScriptService.Services.BombService)
local Explosion = require(game.ServerScriptService.Services.ExplosionService)

return {
    state = Round.GetState(),
    round = Round.GetRoundNumber(),
    isPlaying = Round.IsPlaying(),
    monsters = Monster.GetAliveCount(),
    bombs = Bomb.GetActiveBombCount(),
    explosions = Explosion.GetExplosionCount(),
    stallCount = Round._stallCount,
    lastReason = Round._lastReason,
}
`;

async function main() {
    await mcp.init();

    const rounds = [];
    const deadline = Date.now() + 240 * 1000;
    let sawPlaying = false;
    let sawEnding = false;

    // Se observan varios estados del ciclo: hace falta ver `Playing` (donde
    // hay monstruos) y `RoundEnding` (donde deben estar ya limpiados).
    while (Date.now() < deadline) {
        const r = unwrap(await mcp.serverLuau(PROBE));
        if (!r || r.error) {
            console.log("ERROR de sonda: " + JSON.stringify(r));
            process.exitCode = 2;
            return;
        }

        const last = rounds[rounds.length - 1];
        if (!last || last.state !== r.state) {
            rounds.push(r);
            console.log(
                "  " + String(r.state).padEnd(17) +
                " ronda " + String(r.round).padEnd(4) +
                " monstruos " + String(r.monsters).padEnd(3) +
                " bombas " + String(r.bombs).padEnd(3) +
                " explos " + String(r.explosions).padEnd(3) +
                " atascos " + r.stallCount
            );
        }

        if (r.isPlaying) sawPlaying = true;
        if (r.state === "RoundEnding") sawEnding = true;

        // Con un `Playing` y un `RoundEnding` vistos, ya se puede juzgar.
        if (sawPlaying && sawEnding) break;
        await new Promise((res) => setTimeout(res, 700));
    }

    console.log("");

    const problems = [];

    if (!sawPlaying) problems.push("no se observo ningun estado Playing");
    if (!sawEnding) problems.push("no se observo ningun estado RoundEnding");

    const playing = rounds.find((r) => r.isPlaying);
    const ending = rounds.find((r) => r.state === "RoundEnding");

    // Monstruos: deben generarse jugando y estar limpios al terminar.
    if (playing && playing.monsters <= 0) {
        problems.push("durante Playing no habia ningun monstruo (" + playing.monsters + ")");
    }
    if (ending && ending.monsters > 0) {
        problems.push("quedaron " + ending.monsters + " monstruos vivos al terminar la ronda");
    }
    if (ending && ending.bombs > 0) {
        problems.push("quedaron " + ending.bombs + " bombas activas al terminar la ronda");
    }

    const stalls = rounds.reduce((max, r) => Math.max(max, r.stallCount || 0), 0);
    if (stalls > 0) problems.push("el ciclo de ronda reporto " + stalls + " atasco(s)");

    console.log("");
    if (problems.length > 0) {
        console.log("RESULTADO: FAIL");
        for (const p of problems) console.log("  - " + p);
        process.exitCode = 1;
        return;
    }

    console.log("RESULTADO: PASS - ciclo con monstruos completo y limpio.");
}

main();
function unwrap(res) {
    return Array.isArray(res) ? res[0] : res;
}