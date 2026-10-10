// world-contract-verify.js
// Verifica el CONTRATO de cada arena contra el RUNTIME real de Studio.
//
// POR QUE EXISTE
// --------------
// Un Folder llamado Hazards que no tiene hijos es un PASS de estructura y un
// FAIL de juego: el servicio lo recorre, no encuentra nada y el jugador nunca
// recibe dano. Este script NO cuenta nombres: cuenta PIEZAS reales y ademas
// comprueba que el spawn sea UTILIZABLE.
//
// Distingue tres cosas, que no son lo mismo:
//   STRUCTURE = la ruta existe
//   CONTENT   = hay al menos una pieza real
//   USABLE    = la pieza cumple la condicion funcional (spawn habilitado,
//               solido y sin obstaculos encima)
//
// Uso:  node tools/world-contract-verify.js

const mcp = require("./mcp");

const WORLD_IDS = ["Forest", "Desert", "Ice", "Volcano", "Cyber"];

const CONTRACT = [
	"SpawnPoints",
	"Arena",
	"DestructibleBlocks",
	"IndestructibleBlocks",
	"Hazards",
	"MonsterSpawns",
	"PowerupSpawns",
	"BrainrotSpawns",
	"ChestSpawns",
	"BossSpawn",
	"Exit",
];

// El Luau viaja en un template literal: por eso los comentarios de aqui
// llevan el nombre de la carpeta como texto plano y SIN comillas invertidas.
const AUDIT_LUAU = `
return (function()
local Workspace = game:GetService("Workspace")
local worldsFolder = Workspace:FindFirstChild("Worlds")

local out = { worlds = {}, errors = {} }
if not worldsFolder then
	table.insert(out.errors, "Workspace.Worlds no existe")
	return out
end

local COUNT_KEYS = { "SpawnPoints", "Arena", "DestructibleBlocks",
	"IndestructibleBlocks", "Hazards", "MonsterSpawns", "PowerupSpawns",
	"BossSpawn", "Exit" }

local function countParts(inst)
	if not inst then return 0 end
	if inst:IsA("BasePart") then return 1 end
	local n = 0
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then n += 1 end
	end
	return n
end

-- Un spawn es USABLE si esta habilitado, es solido, y nada solido le invade
-- el volumen donde aparece el personaje.
--
-- OJO con el suelo. Comparar el CENTRO de cada pieza con el punto de
-- aparicion daba positivo en los cinco mundos: la losa que SOSTIENE el spawn
-- no es un obstaculo, es la base. Se mide por tanto el VERTICE SUPERIOR de
-- cada pieza, y solo cuenta como bloqueo lo que llega por encima de la cara
-- superior del spawn y dentro de los 5 studs donde se levanta el jugador.
local function spawnIsUsable(spawn)
	if not spawn:IsA("SpawnLocation") then return false, "no es SpawnLocation" end
	if not spawn.Enabled then return false, "spawn deshabilitado" end
	if not spawn.CanCollide then return false, "spawn sin colision" end

	local standingY = spawn.Position.Y + spawn.Size.Y / 2
	local origin = Vector3.new(spawn.Position.X, standingY, spawn.Position.Z)
	local overlap, blocker = 0, nil

	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("BasePart") and d ~= spawn and d.CanCollide then
			local half = d.Size / 2
			local topY = d.Position.Y + half.Y
			local rel = d.CFrame:PointToObjectSpace(origin)
			if math.abs(rel.X) <= half.X + 3
				and math.abs(rel.Z) <= half.Z + 3
				and topY > standingY + 0.5
				and topY <= standingY + 5 then
				overlap += 1
				blocker = blocker or d:GetFullName()
			end
		end
	end

	if overlap > 0 then
		return false, ("%d pieza(s) solida(s) encima, ej. %s"):format(overlap, tostring(blocker))
	end
	return true, "libre"
end
for _, worldId in ipairs({ "Forest", "Desert", "Ice", "Volcano", "Cyber" }) do
	local wf = worldsFolder:FindFirstChild(worldId)
	local w = { id = worldId, exists = wf ~= nil, entries = {}, totalParts = 0 }
	if not wf then
		out.worlds[worldId] = w
		continue
	end

	for _, d in ipairs(wf:GetDescendants()) do
		if d:IsA("BasePart") then w.totalParts += 1 end
	end

	-- Arena aparece como carpeta en unos mundos y como suelo suelto en otros.
	-- El contrato es "hay suelo real", no "esta en un sitio concreto".
	local arenaFolder = wf:FindFirstChild("Arena")
	if arenaFolder then
		local n = countParts(arenaFolder)
		w.entries["Arena"] = {
			structure = true, content = n > 0, parts = n, note = "carpeta Arena",
		}
	else
		local floor = wf:FindFirstChild("ArenaFloor")
		w.entries["Arena"] = {
			structure = floor ~= nil, content = floor ~= nil,
			parts = countParts(floor), note = "ArenaFloor en la raiz",
		}
	end

	for _, key in ipairs(COUNT_KEYS) do
		if key ~= "Arena" then
			-- Se resuelve por el CONTRATO REAL que leen los servicios y no
			-- por una carpeta homonima: DestructionService lee los bloques
			-- por el prefijo Block_, y el boss y la salida son PIEZAS con
			-- nombre en la raiz (BossSpawn_<Id>, Exit_<Id>). Un orden que
			-- buscara primero FindFirstChild marcaria FALTA en los cuatro
			-- mundos que SI tienen boss: el falso negativo que este script
			-- existe para no introducir.
			if key == "DestructibleBlocks" then
				-- OJO: string.match, NO string.find con plain=true.
				-- El cuarto argumento de find es plain: con el a true el
				-- patron se compara LITERALMENTE, asi que "^Block_" no es un
				-- ancla sino la cadena literal "^Block_", y el recuento daba
				-- CERO bloques en los cinco mundos. Un verificador con un fallo
				-- asi declara FALTA donde todo funciona, que es peor que no
				-- verificar: hace desconfiar del mapa en vez del verificador.
				local n = 0
				for _, d in ipairs(wf:GetDescendants()) do
					if d:IsA("BasePart") and string.match(d.Name, "^Block_") then
						n += 1
					end
				end
				w.entries[key] = {
					structure = true, content = n > 0, parts = n,
					note = "piezas Block_ (contrato DestructionService)",
				}
			elseif key == "BossSpawn" or key == "Exit" then
				local named = wf:FindFirstChild(key .. "_" .. worldId)
				local n = countParts(named)
				w.entries[key] = {
					structure = named ~= nil, content = n > 0, parts = n,
					note = "pieza con nombre en la raiz del mundo",
				}
			elseif key == "SpawnPoints" then
				local n, usable, why = 0, false, "sin SpawnLocation"
				for _, d in ipairs(wf:GetDescendants()) do
					if d:IsA("SpawnLocation") then
						n += 1
						if not usable then usable, why = spawnIsUsable(d) end
					end
				end
				w.entries[key] = {
					structure = n > 0, content = n > 0, parts = n,
					usable = usable, note = why,
				}
			elseif key == "IndestructibleBlocks" then
				local n = 0
				for _, d in ipairs(wf:GetDescendants()) do
					if d:IsA("BasePart") and d.CanCollide
						and string.match(d.Name, "^Block_") == nil
						and d.Name ~= "ArenaFloor" then
						n += 1
					end
				end
				w.entries[key] = {
					structure = true, content = n > 0, parts = n,
					note = "solidas sin prefijo Block_",
				}
			else
				-- El resto (Hazards, MonsterSpawns, PowerupSpawns) SI son
				-- carpetas, y una carpeta vacia es un FAIL, no un PASS.
				local inst = wf:FindFirstChild(key)
				local n = countParts(inst)
				w.entries[key] = {
					structure = inst ~= nil, content = n > 0, parts = n,
					note = "carpeta del mundo",
				}
			end
		end
	end

	out.worlds[worldId] = w
end

return out
end)()
`;
/**
 * El puente devuelve el valor serializado en `returnValue`, no como objeto.
 * Sin esta capa el informe compararia `undefined` y declararia FALTA en los
 * cinco mundos: el fallo opuesto, porque un verificador que siempre falla
 * tampoco verifica nada.
 */
function parseResult(raw) {
	let v = raw;
	if (v && typeof v === "object" && v.returnValue !== undefined) v = v.returnValue;
	if (v && typeof v === "object" && v.result !== undefined) v = v.result;
	if (typeof v !== "string") return v;
	try {
		return JSON.parse(v);
	} catch {
		return null;
	}
}

/**
 * Una celda por entrada del contrato. Distingue los tres fallos que se
 * confundian como uno solo: no existe, existe vacia, y existe pero el spawn
 * es inutilizable.
 */
function cell(e, key) {
	if (!e || !e.structure) return "  FALTA    ";
	if (key === "SpawnPoints") {
		if (!e.content) return "  SIN      ";
		if (e.usable === false) return "  MAL      ";
		return "  " + String(e.parts).padEnd(8);
	}
	if (!e.content) return "  VACIA    ";
	return "  " + String(e.parts).padEnd(8);
}

async function main() {
	const inst = await mcp.toolJson("get_connected_instances", {});
	const live = !!(inst && inst.instances && inst.instances.some((i) => i.peers && i.peers.server));

	const data = parseResult(await mcp.tool("execute_luau", { code: AUDIT_LUAU }));
	if (!data || typeof data !== "object" || !data.worlds) {
		console.log("No se pudo auditar el runtime: " + JSON.stringify(data));
		process.exitCode = 2;
		return;
	}
	if (data.errors && data.errors.length) data.errors.forEach((e) => console.log("ERROR " + e));

	console.log("CONTRATO DE MUNDOS (runtime de Studio)");
	console.log("servidor en vivo: " + (live ? "SI" : "NO"));
	console.log("---------------------------------------------------------------");
	console.log("mundo      partes  " + CONTRACT.map((c) => c.slice(0, 10).padEnd(11)).join(""));

	const problems = [];
	for (const id of WORLD_IDS) {
		const w = data.worlds[id];
		if (!w || !w.exists) {
			console.log(id.padEnd(10) + "AUSENTE");
			problems.push(id + ": el mundo no existe en Workspace.Worlds");
			continue;
		}
		const cells = CONTRACT.map((k) => cell(w.entries[k], k));
		console.log(id.padEnd(10) + String(w.totalParts).padEnd(8) + cells.join(""));

		for (const k of CONTRACT) {
			const e = w.entries[k];
			if (!e || !e.structure) problems.push(`${id}.${k}: no existe`);
			else if (!e.content) problems.push(`${id}.${k}: existe pero VACIA`);
			else if (k === "SpawnPoints" && e.usable === false) problems.push(`${id}.${k}: no utilizable (${e.note})`);
		}
	}

	console.log("");
	if (problems.length) {
		console.log("PROBLEMAS REALES (carpeta vacia o spawn inutil NO cuentan como PASS):");
		problems.forEach((p) => console.log("  - " + p));
		process.exitCode = 1;
	} else {
		console.log("CONTRATO DE MUNDOS: PASS");
	}
}

main().catch((e) => {
	console.error("FALLO: " + e.message);
	process.exitCode = 2;
});