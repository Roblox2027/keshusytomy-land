// studio-ascii-check-tmp.js
// Comprueba que Studio recibe el fuente tal cual, sin caracteres de mas.
//
// POR QUE ESTA SONDA Y NO UN RECUENTO DE INSTANCIAS
// -------------------------------------------------
// El defecto medido no cambia ni una sola instancia del arbol: `set_script_source`
// de MCP escribe UN byte mas delante de cada caracter de doble ancho. El arbol
// queda igual, los nombres igual, y un verificador estructural dira PASS.
//
// Solo comparando el TEXTO se ve. Aqui se mide, sobre todos los scripts, cuantos
// caracteres no ASCII tienen: si el fuente del repositorio es ASCII puro y en
// Studio tambien lo es, el transporte esta limpio.
const mcp = require("./mcp");

const CODE = [
	'local out = {}',
	'local total = 0',
	'local bad = 0',
	'',
	'local function scan(node, path, depth)',
	'\tif depth > 6 then return end',
	'\tfor _, c in ipairs(node:GetChildren()) do',
	'\t\tif c:IsA("LuaSourceContainer") then',
	'\t\t\ttotal += 1',
	'\t\t\tlocal n = 0',
	'\t\t\tfor ch in string.gmatch(c.Source, "[^\\x00-\\x7F]") do',
	'\t\t\t\tn += 1',
	'\t\t\tend',
	'\t\t\tif n > 0 then',
	'\t\t\t\tbad += 1',
	'\t\t\t\ttable.insert(out, path .. "." .. c.Name .. " -> " .. n)',
	'\t\t\tend',
	'\t\telse',
	'\t\t\tscan(c, path .. "." .. c.Name, depth + 1)',
	'\t\tend',
	'\tend',
	'end',
	'',
	'scan(game:GetService("ReplicatedStorage"), "ReplicatedStorage", 0)',
	'scan(game:GetService("ServerScriptService"), "ServerScriptService", 0)',
	'local sps = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")',
	'if sps then scan(sps, "StarterPlayerScripts", 0) end',
	'scan(game:GetService("StarterGui"), "StarterGui", 0)',
	'',
	'table.sort(out)',
	'return "scripts=" .. total .. " conNoAscii=" .. bad .. "::" .. table.concat(out, " | ")',
].join("\n");

async function main() {
	await mcp.init();
	const res = await mcp.toolJson("execute_luau", { code: CODE });
	if (!res || res.returnValue === undefined) {
		console.error("SIN RESULTADO:", JSON.stringify(res));
		process.exit(1);
	}
	console.log(String(res.returnValue));
}

main().catch((e) => {
	console.error("FALLO:", e.message);
	process.exit(1);
});