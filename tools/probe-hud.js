// probe-hud.js
// Sonda del HUD REAL en el cliente en marcha: por que BombStats muestra solo
// las letras de icono y no las cifras.
//
// Uso:  node tools/probe-hud.js
//
// MEDIDO en shot-04: el panel `BombStats` pinta "B" y "P" (los hijos `Icon`)
// pero NO la cifra, que deberia ir en el propio TextLabel de la fila. Este
// script no supone nada: lee Text, AbsoluteSize, Visible y ZIndex de cada
// descendiente y lo imprime, para separar "el texto no llega" de "el texto
// llega pero no se ve".

const mcp = require("./mcp");

const CODE = `
local Players = game:GetService("Players")
local player = Players.LocalPlayer
if not player then return "sin jugador local" end

local out = {}
local function line(s) out[#out + 1] = s end

local gui = player:WaitForChild("PlayerGui"):FindFirstChild("KeshusyHUD")
if not gui then return "KeshusyHUD no esta en PlayerGui" end

line(("GUI Enabled=%s ZIndex=%s"):format(tostring(gui.Enabled), tostring(gui.ZIndexBehavior)))

local function dump(inst, depth)
	local info
	if inst:IsA("GuiObject") then
		local pos = inst.AbsolutePosition
		local size = inst.AbsoluteSize
		info = ("%s [%s] pos=(%.0f,%.0f) size=(%.0f,%.0f) vis=%s z=%s")
			:format(
				inst.Name,
				inst.ClassName,
				pos.X, pos.Y, size.X, size.Y,
				tostring(inst.Visible),
				tostring(inst.ZIndex)
			)
	else
		info = ("%s [%s]"):format(inst.Name, inst.ClassName)
	end
	if inst:IsA("TextLabel") then
		info ..= (" text=%q size=%d wrap=%s scaled=%s transp=%.2f color=%s")
			:format(
				inst.Text,
				inst.TextSize,
				tostring(inst.TextWrapped),
				tostring(inst.TextScaled),
				inst.TextTransparency,
				tostring(inst.TextColor3)
			)
	end
	line(string.rep("  ", depth) .. info)
	for _, c in ipairs(inst:GetChildren()) do
		dump(c, depth + 1)
	end
end

local targets = { "BombStats", "Currency", "PlayerStats" }
for _, name in ipairs(targets) do
	local panel = gui:FindFirstChild(name)
	if not panel then
		line("FALTA panel " .. name)
	else
		line("== " .. name)
		dump(panel, 1)
	end
end

-- Atributos que el controller lee para esas filas.
for _, attr in ipairs({ "Bombs", "CoreState", "CoreCharge", "Coins", "Gems", "XP", "World" }) do
	local v = player:GetAttribute(attr)
	line(("attr %-11s = %s (%s)"):format(attr, tostring(v), typeof(v)))
end

return table.concat(out, "\\n")
`;

async function main() {
	await mcp.init();
	const res = await mcp.clientLuau(CODE);
	console.log(typeof res === "string" ? res : JSON.stringify(res, null, 2));
}

main().catch((e) => {
	console.error("PROBE ERROR: " + e.message);
	process.exit(1);
});
