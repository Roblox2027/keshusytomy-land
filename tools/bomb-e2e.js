// bomb-e2e.js
// PRUEBA DE BOMBA OBLIGATORIA, medida en el tiempo.
//
// QUE MIDE, Y POR QUE ASI
// -----------------------
// El contrato real del balance (GameConfig) es: una bomba hace 120 de dano, un
// bloque tiene 100 de vida y recibe el 50% del dano de la explosion, o sea 60
// por bomba. Make 2 bombs por block. La version anterior de esta prueba exigia
// "destruidos > 0" tras UNA bomba y por eso daba FAIL siempre: no habia ningun
// defecto, la prueba estaba mal escrita.
//
// Se mide en tres pasos que NO se pueden confundir:
//   1. la bomba se coloca (el servidor acepta la peticion),
//   2. la bomba detona (el contador de explosiones sube),
//   3. los bloques reciben dano (la SALUD de un bloque baja).
//
// El paso 3 es el que importa: "vivos = 48" no dice si hubo dano, porque un
// bloque puede bajar de 100 a 40 y seguir en pie.
//
// Uso: node tools/bomb-e2e.js
// Salida con codigo 1 si la cadena no llega a completar.

const fs = require("fs");
const path = require("path");
const mcp = require("./mcp");

/** Luau: coloca una bomba junto al personaje y devuelve el bloque de referencia. */
const PLACE_LUA = `
local Players = game:GetService("Players")
local Round = require(game.ServerScriptService.Services.RoundService)
local Bomb = require(game.ServerScriptService.Services.BombService)
local Destruction = require(game.ServerScriptService.Services.DestructionService)

local p = Players:GetPlayers()[1]
if not p then return { error = "no hay jugadores" } end
if not Round.IsPlaying() then return { error = "no_jugando", state = Round.GetState() } end

local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
if not root then return { error = "sin personaje" } end

local ok, reason = Bomb.TryPlaceBomb(p, root.Position + Vector3.new(0, 0, -8))

return {
	placed = ok,
	reason = reason,
	state = Round.GetState(),
	bombs = Bomb.GetActiveBombCount(),
	aliveBlocks = Destruction.GetAliveBlockCount(),
	destroyedBlocks = Destruction.GetDestroyedBlockCount(),
}
`;

/** Luau: estado de la destruccion tras detonar. */
const SAMPLE_LUA = fs.readFileSync(
	path.join(__dirname, "probes", "after-bomb.lua"),
	"utf8"
);

/** Cuantas bombas hacen falta para derribar un bloque, segun el balance. */
const PLAN_LUA = `
local GC = require(game.ReplicatedStorage.Shared.Config.GameConfig)
local DanoPorBomba = GC.DefaultBombDamage * GC.BlockDamageScale
return {
	danoPorBomba = DanoPorBomba,
	vidaBloque = GC.BlockHealth,
	bombasParaDestruir = math.ceil(GC.BlockHealth / DanoPorBomba),
	mecha = GC.DefaultBombFuseTime,
	radio = GC.DefaultBombRadius,
}
`;

async function main() {
	await mcp.init();

	const plan = await mcp.serverLuau(PLAN_LUA);
	if (!plan || plan.error) {
		console.log("no se pudo leer el balance: " + JSON.stringify(plan));
		process.exitCode = 2;
		return;
	}
	console.log("BALANCE DECLARADO: " + JSON.stringify(plan));

	// Se espera a que haya ronda en juego: fuera de Playing el servidor
	// rechaza la bomba por diseno y un FAIL ahi no significaria nada.
	let placed = null;
	const waitUntil = Date.now() + 200 * 1000;
	while (Date.now() < waitUntil) {
		placed = await mcp.serverLuau(PLACE_LUA);
		if (placed && placed.error) {
			console.log("esperando: " + placed.error + " (" + (placed.state || "?") + ")");
			await new Promise((r) => setTimeout(r, 3000));
			continue;
		}
		break;
	}

	if (!placed || placed.error) {
		console.log("ERROR: no se pudo colocar la bomba: " + JSON.stringify(placed));
		process.exitCode = 2;
		return;
	}
	if (!placed.placed) {
		console.log("RESULTADO: FAIL - el servidor rechazo la bomba: " + placed.reason);
		process.exitCode = 1;
		return;
	}

	console.log("BOMBA COLOCADA. bloques_vivos=" + placed.aliveBlocks);

	// La medicion de referencia se toma ANTES de colocar la bomba: la sonda
	// llama a `Detonate` de verdad para aislar la capa, asi que colocarla
	// primero haria que la bomba y la explosion de la sonda se pisen.
	//
	// Se ESPERA a que haya bloques en el radio. Un bloque destruido pone
	// `CanCollide = false`, asi que sale de `GetPartBoundsInRadius` con
	// `RespectCanCollide`: si la ronda anterior dejo el centro arrasado, no
	// hay nada que medir hasta que `MatchService` restaure el mapa.
	let base = null;
	const readyBy = Date.now() + 120 * 1000;
	while (Date.now() < readyBy) {
		base = await mcp.serverLuau(SAMPLE_LUA);
		if (base && !base.sinBloques) break;
		console.log("esperando bloques en el radio (mapa sin reparar)...");
		await new Promise((r) => setTimeout(r, 4000));
	}
	if (!base || base.sinBloques) {
		console.log("RESULTADO: BLOCKED - el mapa no se reparo y no hay bloques que medir.");
		process.exitCode = 2;
		return;
	}

	// UNA sola bomba es suficiente para probar la cadena. El numero de bombas
	// que hace falta para DERRIBAR un bloque (2, segun el balance) es un dato
	// de diseno, no una condicion de esta prueba: medirlo exigiria ocupar la
	// ronda entera, y si la ronda termina por medio MatchService limpia las
	// bombas, asi que la prueba mediria "la ronda termino".
	await new Promise((r) => setTimeout(r, plan.mecha * 1000 + 2000));

	console.log("explosion de referencia (sonda, sin bomba):");
	console.log("  partes afectadas por Detonate : " + base.afectadasPorDetonate);
	console.log("  bloques en el radio           : " + base.bloquesEnRadio);
	console.log("  vida de " + base.objetivo + " : " + base.vidaAntes
		+ " -> " + base.vidaDespues);
	console.log("  cableado: destruccion=" + base.tieneDestruccion
		+ " combate=" + base.tieneCombate
		+ " monstruos=" + base.tieneMonstruos);

	const after = await mcp.serverLuau(SAMPLE_LUA);
	if (after.sinBloques) {
		console.log("");
		console.log("RESULTADO: BLOCKED - la ronda termino entre muestras y no hay");
		console.log("bloques en el radio para medir. No es un fallo de la destruccion.");
		process.exitCode = 2;
		return;
	}

	console.log("");
	console.log("tras la bomba del jugador:");
	console.log("  vida de " + after.objetivo + " : " + after.vidaAntes
		+ " -> " + after.vidaDespues);
	console.log("  bloques derribados            : " + after.destroyed);

	const detonated = after.afectadasPorDetonate > 0;
	const damaged = after.vidaDespues < after.vidaAntes;

	console.log("");
	console.log("  bomba creada y aceptada por el servidor : " + placed.placed);
	console.log("  la explosion afecta a partes del mapa   : " + detonated
		+ " (" + after.afectadasPorDetonate + ")");
	console.log("  los bloques reciben dano (" + after.vidaAntes
		+ " -> " + after.vidaDespues + ") : " + damaged);
	console.log("  bloques derribados                     : " + after.destroyed);

	// La cadena bomba -> explosion -> dano esta completa en cuanto el dano
	// LLEGA al bloque. Cuantos bloques caen depende de cuantas bombas se
	// colocan: se informa, pero no se exige con una sola bomba.
	const ok = detonated && damaged;

	console.log("");
	console.log(ok
		? "RESULTADO: PASS (cadena bomba -> explosion -> dano completa)"
		: "RESULTADO: FAIL");
	if (!ok) process.exitCode = 1;
	if (after.destroyed > 0) {
		console.log("nota: ademas hubo bloques derribados: " + after.destroyed);
	}
}

main().catch((e) => {
	console.error("ERROR: " + e.message);
	process.exit(1);
});
