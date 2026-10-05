"use strict";

// qa-play.js
// Verificacion de la cadena de juego CONTRA EL SERVIDOR Y EL CLIENTE REALES
// de la sesion de Play, no contra el source.
//
// Por que `execute_luau` no sirve aqui: corre en el DataModel de EDICION, donde
// no hay jugadores ni ronda. Todo lo que afirma sobre PLAY tiene que salir de
// `eval_server_runtime` / `eval_client_runtime`.
//
// Uso:  node tools/qa-play.js

const fs = require("fs");
const path = require("path");
const mcp = require("./mcp");

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** Mete al jugador en una arena para que la ronda pueda arrancar. */
const MOVE = `
local Match = require(game.ServerScriptService.Services.MatchService)
local Players = game:GetService("Players")
local p = Players:GetPlayers()[1]
if not p then return "sin jugadores" end
local keys = {}
for k in pairs(Match._destinations or {}) do table.insert(keys, k) end
table.sort(keys)
local moved = Match.MovePlayer(p, "Arena_Forest")
return string.format("destinos=[%s] movido=%s World=%s", table.concat(keys, ","), tostring(moved), tostring(p:GetAttribute("World")))
`;

/** Estado de ronda + bomba + bloques. */
const STATE = `
local Round = require(game.ServerScriptService.Services.RoundService)
local Bomb = require(game.ServerScriptService.Services.BombService)
local Destruction = require(game.ServerScriptService.Services.DestructionService)
return {
	state = Round.GetState(),
	playing = Round.IsPlaying(),
	round = Round.GetRoundNumber(),
	bombs = Bomb.GetActiveBombCount(),
	alive = Destruction.GetAliveBlockCount(),
	destroyed = Destruction.GetDestroyedBlockCount(),
}
`;

/** Coloca una bomba junto al jugador y devuelve la cuenta de bombas. */
const PLACE = `
local Players = game:GetService("Players")
local Round = require(game.ServerScriptService.Services.RoundService)
local Bomb = require(game.ServerScriptService.Services.BombService)
local p = Players:GetPlayers()[1]
if not p or not p.Character then return "sin jugador" end
if not Round.IsPlaying() then return "no_jugando:" .. tostring(Round.GetState()) end
local root = p.Character:FindFirstChild("HumanoidRootPart")
local ok, reason = Bomb.TryPlaceBomb(p, root.Position + Vector3.new(0, 0, -8))
return string.format("puesta=%s motivo=%s bombas=%d", tostring(ok), tostring(reason), Bomb.GetActiveBombCount())
`;

/** Escala REAL de los monstruos vivos, medida en PLAY. */
const MONSTERS = `
local Players = game:GetService("Players")
local p = Players:GetPlayers()[1]
local out = {}
local playerH = 0
if p and p.Character then
	local _, s = p.Character:GetBoundingBox()
	playerH = s.Y
end
table.insert(out, string.format("PLAYER alto=%.2f", playerH))
local models = workspace:FindFirstChild("Monsters")
if models then
	for _, m in ipairs(models:GetChildren()) do
		if m:IsA("Model") then
			local _, s = m:GetBoundingBox()
			local root = nil
			for _, c in ipairs(m:GetChildren()) do
				if c:IsA("BasePart") and c.Name:lower():find("root") then root = c break end
			end
			table.insert(out, string.format("   %s alto=%.2f x%.2f VS=%s HS=%s VH=%s HH=%s hitboxY=%s",
				m.Name, s.Y, s.Y / playerH,
				tostring(m:GetAttribute("VisualScale")), tostring(m:GetAttribute("HitboxScale")),
				tostring(m:GetAttribute("VisualHeight")), tostring(m:GetAttribute("HitboxHeight")),
				root and string.format("%.2f", root.Size.Y) or "n/d"))
		end
	end
end
return table.concat(out, "\\n")
`;

/**
 * Rompe VARIOS bloques de verdad y registra el instante de reaparicion de cada
 * uno. Es la unica forma de comprobar que el azar del respawn es POR BLOQUE y
 * no un unico timer compartido.
 */
const BREAK = `
local Destruction = require(game.ServerScriptService.Services.DestructionService)
local Players = game:GetService("Players")

-- Se eligen los bloques del mundo activo mas cercanos al jugador.
local p = Players:GetPlayers()[1]
local origin = p and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
origin = origin and origin.Position or Vector3.zero

local picked = {}
for b in pairs(Destruction._blocks or {}) do
	if b:IsA("BasePart") and Destruction.IsDestructibleBlock(b) then
		table.insert(picked, b)
	end
end
table.sort(picked, function(a, b) return (a.Position - origin).Magnitude < (b.Position - origin).Magnitude end)

local chosen = {}
for i = 1, math.min(6, #picked) do table.insert(chosen, picked[i]) end

local before = {}
for _, b in ipairs(chosen) do
	before[b:GetFullName()] = string.format("vida=%.0f", Destruction.GetBlockHealth(b))
	-- Dos bombas por bloque es el contrato del balance (60 de dano cada una).
	Destruction.ApplyDamage(b, 60)
	Destruction.ApplyDamage(b, 60)
end

task.wait(0.5)

local after = {}
for _, b in ipairs(chosen) do
	local reg = (Destruction._records or {})[b]
	after[#after + 1] = string.format("%s vida=%.0f readyAt=%s", b.Name, Destruction.GetBlockHealth(b),
		reg and tostring(reg.ReadyAt) or "n/d")
end

return string.format("vivos=%d destruidos=%d\\nANTES:\\n%s\\nDESPUES:\\n%s\\nauditoria=%s",
	Destruction.GetAliveBlockCount(), Destruction.GetDestroyedBlockCount(),
	table.concat((function() local t = {} for k, v in pairs(before) do table.insert(t, k .. " " .. v) end table.sort(t) return t end)(), "\\n"),
	table.concat(after, "\\n"),
	table.concat(Destruction.AuditDuplicates(), " | "))
`;

/** Tras la espera: cuantos bloques han vuelto y con cuantos duplicados. */
const RESPAWN = `
local Destruction = require(game.ServerScriptService.Services.DestructionService)
local BlockRespawn = require(game.ReplicatedStorage.Shared.Libraries.BlockRespawnRules)

local rows = {}
local byReady = {}
local now = os.clock()
local pendientes = 0
local explicados = {}

for block, reg in pairs(Destruction._records or {}) do
	if reg.State == BlockRespawn.State.Destroyed or reg.ReadyAt > 0 then
		pendientes += 1
		local alive = block:GetAttribute("IsDestroyed") == false
		if not alive then
			local allowed, reason = BlockRespawn.CanRespawn(reg, now, {
				generation = reg.Generation,
				worldActive = Destruction._worldActive,
				hasActiveCopy = false,
				hasBlockingEntity = Destruction.hasBlockingEntity(block),
			})
			table.insert(explicados, string.format("%s faltan=%.1fs vivo=%s pode=%s motivo=%s gen=%d",
				block.Name, reg.ReadyAt - now, tostring(alive), tostring(allowed), tostring(reason), reg.Generation))
		end
	end
	table.insert(rows, string.format("%s vida=%.0f readyAt=%s", block.Name, Destruction.GetBlockHealth(block), tostring(reg.ReadyAt)))
	local key = reg.ReadyAt
	byReady[tostring(key)] = (byReady[tostring(key)] or 0) + 1
end
local distintos = 0
for _ in pairs(byReady) do distintos += 1 end
table.sort(rows)
return string.format("AHORA=%.1f vivos=%d destruidos=%d registros=%d ReadyAt DISTINTOS=%d pendientes=%d duplicados=[%s]\\nPENDIENTES:\\n%s",
	now, Destruction.GetAliveBlockCount(), Destruction.GetDestroyedBlockCount(), #rows, distintos, pendientes,
	table.concat(Destruction.AuditDuplicates(), " | "), table.concat(explicados, "\\n"))
`;

/** UI del cliente: existe el boton de bomba? es un Frame dibujado o un TextButton rojo? */
const HUD = `
local Players = game:GetService("Players")
local p = Players:GetPlayers()[1]
if not p then return "sin jugador" end
local out = {}

-- 1. ARBOL COMPLETO DEL BOTON DE BOMBA (lo que el jugador VE de verdad).
local bombBtn = nil
for _, d in ipairs(p.PlayerGui:GetDescendants()) do
	if d.Name == "BombButton" then bombBtn = d break end
end
if bombBtn then
	table.insert(out, "BombButton [" .. bombBtn.ClassName .. "] visible=" .. tostring(bombBtn.Visible)
		.. " transparency=" .. tostring(bombBtn.BackgroundTransparency)
		.. " pos=" .. tostring(bombBtn.AbsolutePosition) .. " size=" .. tostring(bombBtn.AbsoluteSize))
	for _, c in ipairs(bombBtn:GetChildren()) do
		local extra = ""
		if c:IsA("GuiObject") then
			extra = string.format(" pos=%s size=%s vis=%s", tostring(c.AbsolutePosition), tostring(c.AbsoluteSize), tostring(c.Visible))
		elseif c:IsA("TextLabel") or c:IsA("TextButton") then
			extra = string.format(" text=%q color=%s", c.Text, tostring(c.TextColor3))
		end
		table.insert(out, "   - " .. c.Name .. " [" .. c.ClassName .. "]" .. extra)
	end
	local textos = {}
	for _, d in ipairs(bombBtn:GetDescendants()) do
		if d:IsA("TextLabel") or d:IsA("TextButton") then table.insert(textos, d.Name .. "=" .. string.format("%q", d.Text)) end
	end
	table.insert(out, "   textos: " .. table.concat(textos, " ; "))
	local legacy = false
	for _, d in ipairs(bombBtn:GetDescendants()) do
		if d:IsA("TextLabel") or d:IsA("TextButton") then
			if string.upper(d.Text) == "BOMBA" then legacy = true end
		end
	end
	table.insert(out, "   TEXTO 'BOMBA' PRESENTE: " .. tostring(legacy))
else
	table.insert(out, "BombButton: NO EXISTE")
end

-- 2. MONSTRUOS: alto real del personaje vs alto real de cada bicho.
local char = p.Character
local playerH = 0
if char then
	local _, s = char:GetBoundingBox()
	playerH = s.Y
end
table.insert(out, string.format("PLAYER alto=%.2f", playerH))
local models = workspace:FindFirstChild("Monsters")
if models then
	for _, m in ipairs(models:GetChildren()) do
		if m:IsA("Model") then
			local _, s = m:GetBoundingBox()
			local r2 = m:FindFirstChild("HumanoidRootPart")
			table.insert(out, string.format("   %s alto=%.2f x%.2f VS=%s HS=%s hitboxY=%s",
				m.Name, s.Y, s.Y / playerH,
				tostring(m:GetAttribute("VisualScale")), tostring(m:GetAttribute("HitboxScale")),
				r2 and string.format("%.2f", r2.Size.Y) or "n/d"))
		end
	end
end
return table.concat(out, "\\n")
`;

/** Rompe 6 bloques y devuelve sus nombres. */
const BREAK6 = `
local Destruction = require(game.ServerScriptService.Services.DestructionService)
local Players = game:GetService("Players")
local p = Players:GetPlayers()[1]
local origin = p and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
origin = origin and origin.Position or Vector3.zero

local picked = {}
for b in pairs(Destruction._blocks or {}) do
	if b:IsA("BasePart") and Destruction.IsDestructibleBlock(b) then table.insert(picked, b) end
end
table.sort(picked, function(a, b) return (a.Position - origin).Magnitude < (b.Position - origin).Magnitude end)

local out = {}
for i = 1, math.min(6, #picked) do
	local b = picked[i]
	Destruction.ApplyDamage(b, 60)
	Destruction.ApplyDamage(b, 60)
	table.insert(out, b.Name)
end
return "rotos: " .. table.concat(out, " ")
`;

/** Estado real de los bloques con respawn pendiente (sonda en tools/probes). */
const SAMPLE6 = fs.readFileSync(path.join(__dirname, "probes", "qa-respawn-state.lua"), "utf8");


/**
 * Rompe 6 bloques y sondea cada 2 s hasta que todos vuelven.
 * Comprueba lo que el enunciado exige: tiempos DISTINTOS, no todos a la vez,
 * cero duplicados y cero bloques perdidos.
 */
async function verificarRespawn() {
	// Rompe 6 bloques y sondea cada 2 s hasta que todos vuelven.
	//
	// IMPORTANTE: el respawn SOLO ocurre con el mundo activo. Si la ronda
	// termina durante la espera, `CanRespawn` responde "mundo inactivo" y el
	// bloque no vuelve hasta `RestoreAll` de la ronda siguiente. Por eso el
	// sondeo se detiene en cuanto el mundo se apaga: medir despues daria un
	// falso negativo que no es un defecto del respawn.
	console.log("== rompiendo 6 bloques ==");
	console.log(await mcp.serverLuau(BREAK6));

	let todosVueltos = false;
	const hitos = [];

	for (let i = 0; i < 25; i += 1) {
		await sleep(2000);
		const r = await mcp.serverLuau(SAMPLE6);
		const line = typeof r === "string" ? r : JSON.stringify(r);
		// La sonda solo lista los bloques PENDIENTES: los que ya volvieron
		// desaparecen de la lista. Por eso "cuantos faltan" es lo que dice si
		// la subida fue escalonada, y no "cuantos hay en pie".
		const ausentes = (line.match(/faltan/g) || []).length;
		console.log(`  ${line.slice(0, 400)}`);

		if (line.indexOf("mundoActivo=false") !== -1) {
			console.log("  (el mundo se apago: la ronda termino; la medicion se detiene aqui)");
			break;
		}

		if (ausentes < 6) hitos.push(`${ausentes} ausentes de 6`);
		if (ausentes === 0) {
			todosVueltos = true;
			break;
		}
	}

	console.log(`\n  TODOS DE VUELTA: ${todosVueltos}`);
	console.log(`  SUBIDA ESCALONADA: ${hitos.length > 1 ? "SI" : "NO"} (${hitos.length} hito(s))`);
	if (hitos.length) console.log(`  hitos: ${hitos.join(" -> ")}`);

	console.log("\n== auditoria final ==");
	console.log(await mcp.serverLuau(AUDIT));
}

/** Auditoria corta: vivos, destruidos y duplicados. */
const AUDIT = `
local Destruction = require(game.ServerScriptService.Services.DestructionService)
return string.format("vivos=%d destruidos=%d duplicados=[%s]",
	Destruction.GetAliveBlockCount(), Destruction.GetDestroyedBlockCount(),
	table.concat(Destruction.AuditDuplicates(), " | "))
`;

async function mainCompleto() {
	await mcp.init();

	console.log("== mover a arena ==");
	console.log(await mcp.serverLuau(MOVE));

	console.log("\n== esperando ronda ==");
	let state = null;
	for (let i = 0; i < 40; i += 1) {
		state = await mcp.serverLuau(STATE);
		console.log(`  ${state.state} ronda=${state.round} bombas=${state.bombs} bloques=${state.alive}`);
		if (state.playing) break;
		await sleep(3000);
	}

	if (!state || !state.playing) {
		console.log("LA RONDA NO ARRANCO");
		return;
	}

	console.log("\n== colocar bomba ==");
	console.log(await mcp.serverLuau(PLACE));

	console.log("\n== monstruos en PLAY ==");
	console.log(await mcp.serverLuau(MONSTERS));

	console.log("\n== HUD del cliente ==");
	console.log(await mcp.clientLuau(HUD));

	await verificarRespawn();
}

async function main() {
	await mainCompleto();
}

main().catch((e) => {
	console.error("FALLO: " + e.message);
	process.exit(1);
});
