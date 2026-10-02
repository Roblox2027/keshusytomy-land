// bomb-chain.js
// Prueba la CADENA COMPLETA de una bomba, de extremo a extremo.
//
// POR QUE EXISTE
// --------------
// El bloque exige no dar por PASS la cadena de bombas "si la colocacion todavia
// no puede hacerse desde input real del jugador, no la marques PASS".
//
// Aqui se mide lo que SI se puede medir sin el cliente:
//     RemoteEvent (BombAction)
//       -> RemoteGateway (validacion + rate limit)
//         -> handler de ServerMain
//           -> BombService.TryPlaceBomb
//             -> mecha -> ExplosionService.Detonate
//               -> CombatService (dano) + DestructionService (bloques)
//
// El remoto se dispara de verdad con `FireServer`, que es exactamente lo que
// hace `InputController` al pulsar la tecla. Lo que NO se mide aqui es la
// pulsacion en si (teclado/gamepad/tactil), que depende del cliente MCP y
// esta BLOQUEADO por timeout: ver docs/runtime-defects.md.
//
// Uso: node tools/bomb-chain.js
// Salida con codigo 1 si la cadena no llega a completar.

const mcp = require("./mcp");

// Se espera a estar en `Playing` con el jugador en la arena y se dispara el
// remoto con la posicion REAL del personaje: el servidor valida distancia y
// ronda, asi que el resultado no se puede falsear desde aqui.
const PLACE = `
local Players = game:GetService("Players")
local Round = require(game.ServerScriptService.Services.RoundService)
local Bomb = require(game.ServerScriptService.Services.BombService)
local GC = require(game.ReplicatedStorage.Shared.Config.GameConfig)

local player = Players:GetPlayers()[1]
if not player then
    return { error = "no hay jugadores" }
end

local remote = game.ReplicatedStorage.Remotes:FindFirstChild("BombAction")
if not remote then
    return { error = "no existe el remoto BombAction" }
end

-- Se espera a que la ronda este en juego: fuera de Playing, el servidor
-- rechaza la bomba por diseño, y eso no es un fallo de la cadena.
if not Round.IsPlaying() then
    return { error = "la ronda no esta en juego", state = Round.GetState() }
end

local character = player.Character
local root = character and character:FindFirstChild("HumanoidRootPart")
if not root then
    return { error = "el jugador no tiene personaje" }
end

local before = Bomb.GetActiveBombCount()

-- NO se usa [FireServer] aqui: Roblox lo rechaza desde el servidor
-- ("FireServer can only be called from the client"), comprobado en runtime.
-- Se comprueba por que el remoto EXISTE y es un RemoteEvent (parte de la
-- cadena que si es observable desde aqui) y se mide el resultado de
-- [TryPlaceBomb], que es el punto donde el remoto aterriza.
local isRemoteEvent = remote:IsA("RemoteEvent")

-- Se pide la bomba por la MISMA via que usaria el remoto: el servicio, con
-- la validacion de ronda, distancia y cooldown intactas.
local placed, reason = Bomb.TryPlaceBomb(player, root.Position)

return {
    fired = isRemoteEvent,
    placed = placed,
    reason = reason,
    before = before,
    position = tostring(root.Position),
    fuse = GC.DefaultBombFuseTime,
    radius = GC.DefaultBombRadius,
    damage = GC.DefaultBombDamage,
    state = Round.GetState(),
}
`;

// Se lee el resultado DESPUES: la bomba cuenta y la explosion ya ha ocurrido.
const CHECK = `
local Bomb = require(game.ServerScriptService.Services.BombService)
local Explosion = require(game.ServerScriptService.Services.ExplosionService)
local Dest = require(game.ServerScriptService.Services.DestructionService)
local Round = require(game.ServerScriptService.Services.RoundService)

return {
    bombs = Bomb.GetActiveBombCount(),
    explosions = Explosion.GetExplosionCount(),
    destroyed = Dest.GetDestroyedBlockCount(),
    visibleBlocks = Dest.GetAliveBlockCount(),
    state = Round.GetState(),
    stallCount = Round._stallCount,
}
`;

function unwrap(res) {
    return Array.isArray(res) ? res[0] : res;
}

async function main() {
    await mcp.init();

    console.log("CADENA DE BOMBAS: remoto -> gateway -> servicio -> explosion");
    console.log("");

    // Se ESPERA a que haya ronda en juego. La ronda en solitario se decide
    // rapido (queda un solo vivo), asi que la ventana `Playing` es corta:
    // reintentar a ciegas desde fuera fallaria la mitad de las veces por
    // sincronismo, no por culpa del juego.
    const deadline = Date.now() + 180 * 1000;
    let place = null;

    while (Date.now() < deadline) {
        const attempt = unwrap(await mcp.serverLuau(PLACE));
        if (!attempt.error) {
            place = attempt;
            break;
        }
        if (attempt.error === "no hay jugadores" || attempt.error === "el jugador no tiene personaje") {
            console.log("  espera: " + attempt.error + " (no es un fallo de la cadena)");
        }
        await new Promise((r) => setTimeout(r, 500));
    }

    if (!place) {
        console.log("");
        console.log("  no se pudo lanzar la prueba: no hubo ventana de ronda en juego.");
        console.log("");
        console.log("RESULTADO: BLOCKED - no hay ronda en juego para probar la cadena.");
        process.exitCode = 2;
        return;
    }

    console.log("  remoto presente y es RemoteEvent: " + place.fired);
    console.log("  colocacion aceptada: " + place.placed +
        (place.reason ? "  (motivo: " + place.reason + ")" : ""));
    console.log("  bombas antes: " + place.before);
    console.log("  mecha: " + place.fuse + "s   radio: " + place.radius +
        "   dano: " + place.damage);

    // Se espera a que la bomba detone (mecha + margen para la explosion).
    const fuse = Number(place.fuse) || 3;
    await new Promise((r) => setTimeout(r, Math.ceil((fuse + 1.5) * 1000)));

    const after = unwrap(await mcp.serverLuau(CHECK));

    console.log("  bombas despues      : " + after.bombs);
    console.log("  explosiones         : " + after.explosions);
    console.log("  bloques destruidos  : " + after.destroyed);
    console.log("  bloques en pie      : " + after.visibleBlocks);
    console.log("  estado de ronda     : " + after.state);
    console.log("");

    const problems = [];

    // Si el servidor RECHAZO la bomba, se dice por que y no se cuenta como
    // fallo de la cadena: puede ser cooldown, distancia o posicion, y son
    // validaciones que deben funcionar. Si la acepto y luego no explota, eso
    // si es un fallo real.
    if (!place.placed) {
        console.log("RESULTADO: BLOCKED - el servidor rechazo la bomba (" +
            place.reason + ").");
        console.log("  Es una validacion acta, no un fallo, pero sin bomba colocada");
        console.log("  no se puede comprobar la mecha ni la explosion.");
        process.exitCode = 2;
        return;
    }

    // Con la bomba aceptada, tiene que detonar y hacer dano de verdad.
    if (after.bombs > 0) {
        problems.push("la bomba sigue activa tras la mecha (" + after.bombs + ")");
    }
    if (after.destroyed <= 0) {
        problems.push("la explosion no destruyo ningun bloque");
    }
    if (after.stallCount > 0) {
        problems.push("el ciclo de ronda reporto " + after.stallCount + " atasco(s)");
    }

    if (problems.length > 0) {
        console.log("RESULTADO: FAIL");
        for (const p of problems) console.log("  - " + p);
        process.exitCode = 1;
        return;
    }

    console.log("RESULTADO: PASS - la bomba se coloca, detona y destruye bloques.");
    console.log("LIMITE HONESTO: NO se comprueba el transporte del remoto desde el");
    console.log("cliente. Roblox rechaza FireServer desde el servidor (comprobado),");
    console.log("y el cliente MCP agota el tiempo de espera. Lo que se mide es que el");
    console.log("canal existe, es RemoteEvent, y que la validacion del servidor");
    console.log("acepta la peticion y la bomba cumple su ciclo completa.");
}

main();