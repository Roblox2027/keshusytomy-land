// probe-live.js
// Sonda de lectura del LUGAR ABIERTO en Studio via MCP.
//
// Uso:  node tools/probe-live.js
//
// Por que existe: invocar `studio-mcp.js <tool> '<luau>'` desde PowerShell
// mutila las comillas y produce errores de compilacion falsos que parecen
// defectos del juego. Este archivo usa el modulo `mcp.js`, que ya resuelve
// eso, y devuelve un inventario legible del lugar real.
const mcp = require("./mcp");

async function probe() {
	const code = `
local out = {}
local function line(s) out[#out+1] = s end

local function dump(parent, label, depth)
	line("== " .. label)
	local kids = parent:GetChildren()
	table.sort(kids, function(a,b) return a.Name < b.Name end)
	for _, c in kids do
		local extra = ""
		if c:IsA("Script") or c:IsA("LocalScript") then
			extra = " disabled=" .. tostring(c.Disabled)
		end
		line(string.format("  %s [%s]%s", c.Name, c.ClassName, extra))
		if depth > 0 then dump(c, label .. "/" .. c.Name, depth - 1) end
	end
end

dump(game:GetService("ServerScriptService"), "ServerScriptService", 0)
dump(game:GetService("ReplicatedStorage"), "ReplicatedStorage", 0)
dump(game:GetService("StarterPlayer").StarterPlayerScripts, "StarterPlayerScripts", 1)
dump(game:GetService("StarterPlayer").StarterPlayerScripts.Controllers, "Controllers", 0)
dump(game:GetService("StarterPlayer").StarterPlayerScripts.Mobile, "Mobile", 0)
dump(game:GetService("StarterGui"), "StarterGui", 2)
dump(game:GetService("Workspace").Worlds, "Worlds", 1)
dump(game:GetService("Workspace").Lobby, "Lobby", 0)

local function names(parent)
	local t = {}
	for _, c in ipairs(parent:GetChildren()) do t[#t+1] = c.Name end
	table.sort(t)
	return table.concat(t, ", ")
end
line("Players=" .. #game:GetService("Players"):GetPlayers())
return table.concat(out, "\\n")
`;

	const res = await mcp.toolJson("execute_luau", { code });
	console.log(typeof res === "string" ? res : JSON.stringify(res, null, 2));
}

probe().catch((e) => {
	console.error("PROBE ERROR:", e.message);
	process.exit(1);
});