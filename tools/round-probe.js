// round-probe.js
// OBSERVA el ciclo de ronda en el servidor VIVO de Studio.
//
// POR QUE EXISTE
// --------------
// "RoundService se queda en RoundEnding" es un sintoma que el source NO
// puede confirmar ni desmentir: el archivo se lee bien y compila. Lo unico
// que separa "el hilo murio", "el hilo espera una condicion imposible" y
// "el hilo espera correctamente" es el valor de los campos vivos del
// servicio en dos instantes distintos.
//
// Este script MIDE, no supone:
//   - estado actual de la maquina de estados;
//   - `_loopHeartbeat` (avanza si el hilo del ciclo esta vivo);
//   - `remaining` e `elapsed` del estado actual;
//   - numero de jugadores y de vivos;
//   - numero de listeners y de rondas.
//
// Uso:
//   node tools/round-probe.js               observar (6 muestras, 1 s)
//   node tools/round-probe.js 10 500       observar con otro ritmo
//   node tools/round-probe.js --interrupt  experimento: Â¿una transicion
//                                           externa despierta al bucle?
//
// Uso del cliente MCP: `mcp.serverLuau` (el peer de cliente agota el tiempo
// de espera; ver docs/runtime-defects.md). Si esto deja de responder, el
// bloqueo es EXTERNO, no del juego.

const mcp = require("./mcp");

const PROBE = `
local out = {}
local ok, RoundService = pcall(require, game.ServerScriptService.Services.RoundService)

if not ok then
    return { error = "require fallo: " .. tostring(RoundService) }
end

local Players = game:GetService("Players")

local function safe(fn, fallback)
    local o, r = pcall(fn)
    if o and r ~= nil then return r end
    return fallback
end

local now = os.clock()
local endsAt = RoundService._stateEndsAt

table.insert(out, {
    state = safe(function() return RoundService.GetState() end, "?"),
    remaining = safe(function() return math.floor((RoundService.GetTimeRemaining() or 0) * 10) / 10 end, -1),
    -- Delta SIN recortar: GetTimeRemaining usa math.max(0, ...) y por eso
    -- un plazo vencido se ve como 0 aunque el hilo siga durmiendo.
    rawDelta = (endsAt and math.floor((endsAt - now) * 10) / 10) or -1,
    duration = safe(function() return RoundService.GetDuration(RoundService.GetState()) end, -1),
    heartbeat = RoundService._loopHeartbeat,
    iteration = RoundService._loopHeartbeat,
    round = safe(function() return RoundService.GetRoundNumber() end, -1),
    alive = safe(function() return RoundService.GetAliveCount() end, -1),
    players = #Players:GetPlayers(),
    listeners = safe(function() return RoundService.GetListenerCount() end, -1),
    stateAlive = RoundService.State ~= nil and RoundService.State:IsRunning(),
    initialized = RoundService.IsInitialized,
    hasThread = RoundService._loopThread ~= nil,
    history = safe(function() return table.concat(RoundService.State:GetHistory(), ">") end, "?"),
    -- Estado REAL del hilo del ciclo. Es la unica manera de separar
    -- "muerto" de "suspendido": ambos se ven como heartbeat congelado.
    threadStatus = safe(function()
        return coroutine.status(RoundService._loopThread)
    end, "?"),
    threadStack = safe(function()
        local info = debug.info(RoundService._loopThread, "s")
        if type(info) ~= "table" then return "n/a" end
        return table.concat(info, " | ")
    end, "?"),
    broadcasterThread = nil,
    clock = math.floor(now * 10) / 10,
})

return out
`;

// EXPERIMENTO DEL P0.
//
// Hipotesis concreta y COMPROBABLE, no una suposicion:
//
//   El bucle duerme `task.wait(remaining)` con el `remaining` que calculo
//   AL ENTRAR en el estado. Si OTRO hilo cambia el estado (por ejemplo
//   `PlayerService` llamando a `Transition(RoundEnding)` al morir el ultimo
//   vivo), la maquina de estados cambia pero el bucle sigue dormido con el
//   plazo del estado ANTERIOR.
//
//   Sintoma esperado, identico al reportado: estado = RoundEnding,
//   `remaining` = 0 (el plazo ya vencio) y heartbeat congelado, sin un solo
//   error en el Output.
//
// Si la hipotesis es correcta, tras forzar la transicion el estado cambia
// de inmediato y el heartbeat NO avanza durante lo que queda del plazo
// anterior. Si fuese falsa, el bucle se despertaria y avanzaria.

const INTERRUPT = `
local RoundService = require(game.ServerScriptService.Services.RoundService)
local before = {
    state = RoundService.GetState(),
    heartbeat = RoundService._loopHeartbeat,
    rawDelta = RoundService._stateEndsAt and (RoundService._stateEndsAt - os.clock()) or -1,
}
local accepted, err = RoundService.Transition("RoundEnding")
return {
    before = before,
    accepted = accepted,
    err = err,
    after = {
        state = RoundService.GetState(),
        heartbeat = RoundService._loopHeartbeat,
    },
}
`;

function formatRow(i, r) {
    if (!r || r.error) return String(i).padEnd(4) + " ERROR " + (r && r.error);
    return [
        String(i).padEnd(4),
        String(r.state).padEnd(15),
        String(r.remaining).padEnd(7),
        String(r.rawDelta).padEnd(6),
        String(r.duration).padEnd(5),
        String(r.heartbeat).padEnd(6),
        String(r.round).padEnd(4),
        String(r.alive).padEnd(6),
        String(r.players).padEnd(3),
        String(r.listeners).padEnd(4),
        String(r.threadStatus).padEnd(10),
        String(r.hasThread),
    ].join(" ");
}

async function main() {
    const args = process.argv.slice(2);

    await mcp.init();

    const isInterrupt = args[0] === "--interrupt";
    const samples = isInterrupt ? 5 : Number(args[0] || 6);
    const gapMs = isInterrupt ? 1000 : Number(args[1] || 1000);

    const rows = [];
    let interruptResult = null;

    if (isInterrupt) {
        const res = await mcp.serverLuau(INTERRUPT);
        interruptResult = Array.isArray(res) ? res[0] : res;
        const b = interruptResult;
        console.log("");
        console.log("EXPERIMENTO: transicion externa a RoundEnding");
        console.log(
            "  antes   : estado=" + b.before.state + "  hb=" + b.before.heartbeat +
                "  raw=" + Math.round((b.before.rawDelta || 0) * 10) / 10
        );
        console.log("  aceptada: " + b.accepted + (b.err ? "  (" + b.err + ")" : ""));
        console.log("  despues : estado=" + b.after.state + "  hb=" + b.after.heartbeat);
        console.log("");
        console.log("  La maquina de estados AVANZO. La pregunta: Â¿el BUCLE se dio cuenta?");
    }

    for (let i = 0; i < samples; i++) {
        let res;
        try {
            res = await mcp.serverLuau(PROBE);
        } catch (err) {
            console.log("MCP ERROR: " + err.message);
            process.exitCode = 2;
            return;
        }
        rows.push(Array.isArray(res) ? res[0] : res);
        if (i < samples - 1) await new Promise((r) => setTimeout(r, gapMs));
    }

    console.log("");
    console.log(
        "idx  state           rem     raw    dur  hb     rnd  alive  pl  lis  status     thr"
    );
    rows.forEach((r, i) => {
        console.log(formatRow(i, r));
        if (i === 0 && r.history) console.log("     historial: " + r.history);
    });

    // DIAGNOSTICO DEL LATIDO.
    //
    // OJO con la interpretacion, porque aqui es facil mentir: el bucle duerme
    // el PLAZO ENTERO del estado actual, asi que el heartbeat avanza UNA VEZ
    // POR ESTADO, no por segundo. Un latido congelado durante un `Playing` de
    // 180 s es NORMAL y no es ningun fallo.
    //
    // Solo es sospechoso cuando el plazo del estado YA VENCIO (`raw < 0`): ahi
    // el bucle deberia haber transicionado y no hay forma honesta de que no lo
    // haya hecho. Esa es exactamente la firma del P0.
    const valid = rows.filter((r) => r && !r.error);
    const beats = valid.map((r) => r.heartbeat);
    const overdue = valid.filter((r) => r.rawDelta < 0).length;

    console.log("");
    if (beats.length < 2) {
        console.log("DIAGNOSTICO: sin muestras suficientes.");
    } else if (overdue === valid.length) {
        console.log(
            "DIAGNOSTICO: PLAZO VENCIDO en todas las muestras (raw < 0) y el heartbeat " +
                "NO avanza. Eso NO es el bucle durmiendo bien: con el plazo cumplido " +
                "deberia haber transicionado. El hilo esta suspendido dentro de un " +
                "`task.wait(remaining)` calculado para un estado ANTERIOR."
        );
    } else if (beats[beats.length - 1] > beats[0]) {
        console.log(
            `DIAGNOSTICO: latido AVANZA (${beats[0]} -> ${beats[beats.length - 1]}). ` +
                "El bucle esta vivo. Recuerda: avanza una vez por ESTADO, porque duerme " +
                "el plazo entero del estado actual."
        );
    } else {
        console.log(
            `DIAGNOSTICO: latido congelado (${beats[0]}) con plazo aun vigente. ` +
                "Consistente con el bucle durmiendo lo que le queda del estado."
        );
    }

    if (interruptResult) {
        const frozen = valid.every((r) => r.heartbeat === interruptResult.after.heartbeat);
        console.log("");
        if (frozen) {
            console.log("  HIPOTESIS CONFIRMADA: el estado cambio pero el bucle NO se despierta.");
            console.log(
                "  `task.wait` NO es la causa raiz: es la consecuencia de que el plazo " +
                    "dormido\n  no se recalcule al cambiar el estado desde otro hilo."
            );
        } else {
            console.log(
                "  HIPOTESIS NO CONFIRMADA: el bucle si reacciona a la transicion externa."
            );
        }
    }
}


main();
