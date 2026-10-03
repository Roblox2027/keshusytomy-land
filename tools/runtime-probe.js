// runtime-probe.js
// Instantanea del SERVIDOR EN EJECUCION (sesion de Play) via MCP.
//
// Uso:
//   node tools/runtime-probe.js           una foto del estado actual
//   node tools/runtime-probe.js --trace   sigue los traslados en el tiempo
//
// Por que existe: el lugar abierto y el servidor corriendo son dos cosas
// distintas. Los servicios de ServerScriptService solo se instancian dentro
// de una sesion de Play. Este archivo pregunta al servidor real, no a los
// archivos del repositorio.
//
// El modulo `mcp.js` se usa en vez de la CLI `studio-mcp.js` porque PowerShell
// mutila las comillas del Luau y produce errores de compilacion falsos que
// parecen defectos del juego.
const fs = require("fs");
const path = require("path");
const mcp = require("./mcp");

/** Luau de la instantanea. Vive en un .lua aparte, no en una cadena JS. */
const SNAPSHOT_LUA = fs.readFileSync(
	path.join(__dirname, "probes", "snapshot.lua"),
	"utf8"
);

/** Luau del alcance de una explosion, para diagnosing destruccion. */
const REACH_LUA = fs.readFileSync(
	path.join(__dirname, "probes", "explosion-reach.lua"),
	"utf8"
);

/** Luau que coloca una bomba en la posicion real del personaje. */
const PLACE_LUA = fs.readFileSync(
	path.join(__dirname, "probes", "place-bomb.lua"),
	"utf8"
);

/** Luau de solo conteo tras detonar. */
const AFTER_LUA = fs.readFileSync(
	path.join(__dirname, "probes", "after-bomb.lua"),
	"utf8"
);

/** Instantanea: quien esta conectado, donde, y en que estado esta cada sistema. */
async function probe() {
	await mcp.init();

	console.log(await mcp.serverLuau(SNAPSHOT_LUA));

	// Alcance de la explosion: por que una bomba puede DETONAR y aun asi no
	// tocar ningun bloque.
	console.log("--- ALCANCE DE LA EXPLOSION ---");
	console.log(JSON.stringify(await mcp.serverLuau(REACH_LUA), null, 2));

	const placed = await mcp.serverLuau(PLACE_LUA);
	if (typeof placed === "string" && placed.startsWith("colocada=true")) {
		console.log("--- BOMBA COLOCADA, esperando la mecha ---");
		await new Promise((r) => setTimeout(r, 5000));
		console.log("--- DESPUES ---");
		console.log(JSON.stringify(await mcp.serverLuau(AFTER_LUA), null, 2));
	} else {
		console.log("no se pudo colocar: " + placed);
	}
}

/**
 * Seguimiento de traslados en el tiempo.
 *
 * POR QUE: el sintoma "el jugador esta en el lobby durante la ronda" tiene dos
 * explicaciones incompatibles: "nadie lo movio a la arena" o "lo movieron y
 * luego lo devolvieron". Leer el codigo no las separa: hay que ver las
 * llamadas REALES. Este gancho es de solo observacion; no cambia el juego.
 */
async function trace() {
	await mcp.init();

	const hook = `
local Round = require(game.ServerScriptService.Services.RoundService)
local Match = require(game.ServerScriptService.Services.MatchService)
local Players = game:GetService("Players")

if Match.__traza then return "ya enganchado" end
Match.__traza = {}

local function pos(p)
	local root = p and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	if not root then return "-" end
	return string.format("(%.0f,%.0f,%.0f)", root.Position.X, root.Position.Y, root.Position.Z)
end

table.insert(Round._listeners, function(from, to)
	local p = Players:GetPlayers()[1]
	table.insert(Match.__traza, string.format("%s -> %s | char=%s | pos=%s",
		from, to, p and p.Character and "si" or "no", pos(p)))
end)

local original = Match.MovePlayer
Match.MovePlayer = function(player, key)
	local ok, res = original(player, key)
	table.insert(Match.__traza, string.format("    MovePlayer(%s) ok=%s pos=%s",
		key, tostring(res), pos(player)))
	return ok, res
end

return "enganchado"
	`;

	console.log("gancho: " + JSON.stringify(await mcp.serverLuau(hook)));

	let seen = 0;
	for (let i = 0; i < 20; i++) {
		await new Promise((r) => setTimeout(r, 4000));
		const out = await mcp.serverLuau(
			'local M = require(game.ServerScriptService.Services.MatchService) return table.concat(M.__traza or {}, "\\n")'
		);
		const entries = out ? out.split("\n").filter(Boolean) : [];
		if (entries.length > seen) {
			console.log("--- t+" + (i + 1) * 4 + "s ---");
			for (const e of entries.slice(seen)) console.log(e);
			seen = entries.length;
		}
	}
}

const main = process.argv.includes("--trace") ? trace : probe;
main().catch((e) => {
	console.error("ERROR: " + e.message);
	process.exit(1);
});
