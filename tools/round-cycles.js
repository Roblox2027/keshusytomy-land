// round-cycles.js
// CERTIFICA que el ciclo de ronda se REPETE, que es justo lo que rompia el P0.
//
// POR QUE EXISTE
// --------------
// "RoundService se queda en RoundEnding" es el sintoma de UNA ronda. La
// pregunta que de verdad importa es otra: Â¿se completa el ciclo de forma
// REPETIDA? Un servicio que completa 9 rondas y se atasca en la 10 sigue
// roto, y ninguna prueba de "una ronda funciona" lo detecta.
//
// Que el ciclo se repita es lo que separa este bloque de los anteriores,
// donde una sola vuelta se daba por buena.
//
// Uso:
//   node tools/round-cycles.js [ciclos] [timeoutTotalSegundos]
//   node tools/round-cycles.js 10
//   node tools/round-cycles.js 25 300
//
// Salida con codigo 1 si no se completan los ciclos pedidos: es una puerta,
// no un simple informe.

const mcp = require("./mcp");

// Una ronda cuenta como CICLO COMPLETO cuando se ha recorrido entera:
//   Playing -> RoundEnding -> Rewards -> ReturningToLobby -> Waiting
//
// Se cuenta por el HISTORIAL REAL de la maquina de estados, nunca por "el
// numero de rondaumento". El numero de ronda sube al ENTRAR en
// RoundStarting, asi que un numero mas alto no dice nada sobre si la ronda
// llego a terminar. Esa distincion es la que hace fiable a esta puerta.

const PROBE = `
local RoundService = require(game.ServerScriptService.Services.RoundService)
local GameConstants = require(game.ReplicatedStorage.Shared.Constants.GameConstants)

local history = RoundService.State and RoundService.State:GetHistory() or {}
local Playing = GameConstants.RoundState.Playing
local RoundEnding = GameConstants.RoundState.RoundEnding
local Rewards = GameConstants.RoundState.Rewards
local Back = GameConstants.RoundState.ReturningToLobby
local Waiting = GameConstants.RoundState.Waiting

-- Estados por los que DEBE pasar una ronda para contar como ciclo, en orden.
local required = { Playing, RoundEnding, Rewards, Back }

-- Cuenta ciclos completos EN ORDEN dentro del historial.
--
-- Se recorre de derecha a izquierda agrupando por Waiting: cada vez que
-- desde un Waiting se puede retroceder y encontrar, en orden, Back,
-- Rewards, RoundEnding y Playing, esa vuelta cuenta una. Un grupo que NO
-- cierra (la ronda en curso) no cuenta y no interrumpe la cuenta de las
-- anteriores.
local cycles = 0
local i = #history

while i >= 1 do
    if history[i] ~= Waiting then
        i -= 1
    else
        local cursor = i - 1
        local closed = true
        for k = #required, 1, -1 do
            local found = nil
            for j = cursor, 1, -1 do
                if history[j] == required[k] then
                    found = j
                    break
                end
            end
            if found then
                cursor = found - 1
            else
                closed = false
                break
            end
        end
        if closed then
            cycles += 1
            i = cursor
        else
            i = i - 1
        end
    end
end

return {
    cycles = cycles,
    round = RoundService.GetRoundNumber(),
    state = RoundService.GetState(),
    historyLength = #history,
    iteration = RoundService._iteration,
    stallCount = RoundService._stallCount,
    lastReason = RoundService._lastReason,
    alive = RoundService.GetAliveCount(),
    players = #game:GetService("Players"):GetPlayers(),
}`;

function unwrap(res) {
    return Array.isArray(res) ? res[0] : res;
}

async function main() {
    const target = Number(process.argv[2] || 10);
    const timeoutSeconds = Number(process.argv[3] || 600);

    await mcp.init();

    const start = unwrap(await mcp.serverLuau(PROBE));
    const startCycles = start.cycles || 0;

    console.log("");
    console.log("CERTIFICACION DE CICLOS DE RONDA");
    console.log("  objetivo: " + target + " ciclos completos");
    console.log(
        "  inicio  : " + startCycles + " ciclos ya completados (ronda " + start.round + ")"
    );
    console.log("  limite  : " + timeoutSeconds + " s");
    console.log("");

    const deadline = Date.now() + timeoutSeconds * 1000;
    let last = start;
    let reported = -1;

    while (Date.now() < deadline) {
        last = unwrap(await mcp.serverLuau(PROBE));
        const done = (last.cycles || 0) - startCycles;

        // El progreso solo se imprime cuando cambia: en 100 ciclos, una
        // linea por segundo seria ilegible.
        if (last.cycles !== reported) {
            reported = last.cycles;
            console.log(
                "  " +
                    String(done).padStart(4) +
                    "/" +
                    target +
                    "   ronda " +
                    String(last.round).padEnd(4) +
                    "   " +
                    String(last.state).padEnd(17) +
                    "  iter " +
                    String(last.iteration).padEnd(6) +
                    "  atascos " +
                    last.stallCount +
                    (last.stallCount > 0 ? "  <<< ATASCO" : "")
            );
        }

        if (done >= target) break;
        await new Promise((r) => setTimeout(r, 1000));
    }

    const done = (last.cycles || 0) - startCycles;

    console.log("");
    console.log("  resultado          : " + done + "/" + target + " ciclos completos");
    console.log("  iteraciones bucle  : " + last.iteration);
    console.log("  atascos detectados : " + last.stallCount);
    console.log("  ultima razon       : " + last.lastReason);

    if (done < target) {
        console.log("");
        console.log("RESULTADO: FAIL - el ciclo no se completo el numero de veces pedido.");
        console.log(
            "  Estado actual: " + last.state + ", iteracion " + last.iteration +
                ", atascos " + last.stallCount + "."
        );
        if (last.stallCount > 0) {
            console.log("  El VIGILANTE detecto un atasco: el estado no pudo avanzar solo.");
            console.log("  Razon registrada: " + last.lastReason);
        }
        process.exitCode = 1;
        return;
    }

    // Ciclos que se repiten pero con atascos NO son ciclos sanos: el
    // vigilante los tuvo que forzar, y eso significa que la logica dejo de
    // avanzar por si sola. Se declara FAIL para no vender estabilidad
    // comprada forzando la salida.
    if (last.stallCount > 0) {
        console.log("");
        console.log(
            "RESULTADO: FAIL - los ciclos se completaron, pero hubo " +
                last.stallCount + " atasco(s) que hubo que forzar."
        );
        process.exitCode = 1;
        return;
    }

    console.log("");
    console.log("RESULTADO: PASS - " + done + "/" + target + " ciclos completos, sin atascos.");
}

main();
