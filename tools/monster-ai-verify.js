// monster-ai-verify.js
// Prueba en runtime de la CADENA COMPLETA del PvE:
//
//   SPAWN -> DETECCION -> PERSECUCION -> ALCANCE -> ATAQUE -> DANO
//
// POR QUE HAY QUE PROBARLA Y NO SEGUIR EL RECUENTO
// --------------------------------------------------
// `round-pve.js` informa "monstruos 4" durante `Playing` y eso NO demuestra que
// se muevan: `MonsterService.Spawn` puede devolver un id valido y dejar el NPC
// clavado en el sitio si el Heartbeat nunca corre o si la deteccion falla.
//
// Se mide el DESPLAZAMIENTO y la VIDA del jugador en instantes separados por un
// intervalo real. Si la distancia baja, la IA persigue; si la vida baja, ataca.
//
// NOTA SOBRE LA RUTA DE LLAMADA
// -----------------------------
// Se usa `mcp.serverLuau` y NO una llamada suelta a `eval_server_runtime`. La
// llamada suelta devuelve "Requested module experienced an error while loading"
// cuando el servidor esta ocupado, y ese texto se puede leer como "el folder no
// existe": una sonda que miente es peor que una sonda que no existe.
//
// El folder `Monsters` NO se mira en `workspace`: se pregunta al SERVICIO con
// `GetAliveCount()`, que es su unica verdad. Que el folder este vacio en
// Workspace y el servicio con 4 monstruos registrados seria una segunda copia
// del arbol, que es exactamente lo que `dedupe-modules.js` evita.
const mcp = require("./mcp");

const SAMPLE = `
local Players = game:GetService("Players")
local Monster = require(game.ServerScriptService.Services.MonsterService)
local Round = require(game.ServerScriptService.Services.RoundService)

local player = Players:GetPlayers()[1]
if not player then return "SIN JUGADOR" end

local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
if not root or not hum then return "SIN PERSONAJE" end

local alive = Monster.GetAliveCount()
if alive <= 0 then return "estado=" .. Round.GetState() .. " monstruos=0" end

-- Se mide el MAS CERCANO de entre todos los vivos, no el de id mas bajo: el
-- mas cercano es el que esta dentro del rango de deteccion y el unico que
-- puede moverse.
local bestId, bestPos, bestD
for _, id in ipairs(Monster.GetAliveIds()) do
	local m = Monster.GetMonster(id)
	if m and m.Position then
		local d = (m.Position - root.Position).Magnitude
		if not bestD or d < bestD then
			bestId, bestPos, bestD = id, m.Position, d
		end
	end
end

return table.concat({
	"estado=" .. Round.GetState(),
	"vivos=" .. alive,
	"id=" .. tostring(bestId),
	"pos=" .. string.format("%.1f,%.1f,%.1f", bestPos.X, bestPos.Y, bestPos.Z),
	"jugador=" .. string.format("%.1f,%.1f,%.1f", root.Position.X, root.Position.Y, root.Position.Z),
	"distancia=" .. string.format("%.1f", bestD),
	"vida=" .. string.format("%.0f", hum.Health),
}, " ")
`;

const WAIT_SECONDS = 3;
const SAMPLES = 4;

async function main() {
	await mcp.init();

	// Se espera a que haya ronda EN CURSO: `ClearAll` borra la poblacion al
	// terminar, asi que medir fuera de `Playing` daria "monstruos=0" sin decir
	// NADA sobre la IA.
	console.log("esperando poblacion de monstruos...");
	let found = false;

	for (let i = 0; i < 90; i++) {
		const r = await mcp.serverLuau(SAMPLE);
		if (typeof r === "string" && r.includes("vivos=") && !r.includes("vivos=0")) {
			console.log(`poblacion presente tras ${((i * 2) / 60).toFixed(1)} min`);
			found = true;
			break;
		}
		await new Promise((res) => setTimeout(res, 2000));
	}

	if (!found) {
		console.error("no aparecio poblacion de monstruos en 3 min");
		process.exit(1);
	}

	const samples = [];

	for (let i = 0; i < SAMPLES; i++) {
		const r = await mcp.serverLuau(SAMPLE);
		console.log(`T${i}: ${typeof r === "string" ? r : JSON.stringify(r)}`);
		if (typeof r === "string") {
			const d = /distancia=([\d.]+)/.exec(r);
			const h = /vida=([\d.]+)/.exec(r);
			if (d && h) samples.push({ distancia: Number(d[1]), vida: Number(h[1]) });
		}
		// El intervalo tiene que ser REAL: leer dos veces seguidas mediria el
		// mismo frame, y una distancia identica es indistinguible de "la IA no
		// se mueve".
		await new Promise((res) => setTimeout(res, WAIT_SECONDS * 1000));
	}

	if (samples.length < 2) {
		console.error("no se pudieron tomar dos muestras comparables");
		process.exit(1);
	}

	const primera = samples[0];
	const ultima = samples[samples.length - 1];

	console.log("");
	console.log(`distancia inicial: ${primera.distancia}  final: ${ultima.distancia}`);
	console.log(`vida inicial:      ${primera.vida}      final: ${ultima.vida}`);

	const persigue = ultima.distancia < primera.distancia;
	const golpeo = ultima.vida < primera.vida;

	console.log(`PERSEGUCION: ${persigue ? "SI" : "NO"}`);
	console.log(`ATAQUE:      ${golpeo ? "SI" : "NO"}`);

	if (!persigue) {
		console.error("PVE FAIL - los monstruos no se acercan al jugador.");
		process.exitCode = 1;
	} else if (!golpeo) {
		// Perseguir sin golpear puede ser correcto si el jugador se mantiene
		// lejos del alcance de ataque durante toda la muestra, asi que se
		// informa sin marcar FAIL.
		console.log("AVISO: persigue pero no alcanzo a golpear en la ventana medida.");
		console.log("RESULTADO: PARTIAL");
	} else {
		console.log("RESULTADO: PASS - cadena PvE completa (spawn, persigue, golpea).");
	}
}

main().catch((e) => {
	console.error("FALLO:", e.message);
	process.exit(1);
});