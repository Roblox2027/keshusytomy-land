// Sonda temporal:Studio esta vivo? Que dice el arbol REAL de la bomba?
const mcp = require("../mcp");
const { buildHud } = require("../hud");

/**
 * Emite el generador como Luau, igual que `sync-hud.js`, pero apuntando a un
 * padre que se le pase. `sync-hud` escribe en `StarterGui` (tiempo de
 * edicion); el HUD que ve el JUGADOR es una COPIA en `PlayerGui` que se hizo
 * al entrar, asi que cambiar el generador no cambia lo que ya esta en juego.
 */
function emit(node, parentExpr, out, depth, name) {
	const pad = "\t".repeat(depth);
	const cls = node.$className;
	const v = `n${depth}`;
	out.push(`${pad}do`);
	out.push(`${pad}\tlocal ${v} = Instance.new(${JSON.stringify(cls)})`);
	out.push(`${pad}\t${v}.Name = ${JSON.stringify(name)}`);
	for (const [k, val] of Object.entries(node.$properties || {})) {
		if (["AnchorPoint", "Position", "Size", "CornerRadius"].includes(k)) {
			const toU = (u) => {
				const [a, b] = u.UDim2;
				return `UDim2.new(${a[0]}, ${a[1]}, ${b[0]}, ${b[1]})`;
			};
			if (k === "AnchorPoint") {
				out.push(`${pad}\t${v}.${k} = Vector2.new(${val[0]}, ${val[1]})`);
				continue;
			}
			out.push(`${pad}\t${v}.${k} = ${toU(val)}`);
			continue;
		}
		if (k === "UICorner" || k === "UIStroke") continue;
		if (Array.isArray(val)) {
			const c = val.map((v2) => Math.round(v2 * 255)).join(", ");
			out.push(`${pad}\t${v}.${k} = Color3.fromRGB(${c})`);
			continue;
		}
		if (typeof val === "string") {
			if (k === "ZIndexBehavior") out.push(`${pad}\t${v}.${k} = Enum.ZIndexBehavior.${val}`);
			else if (k === "Font") out.push(`${pad}\t${v}.${k} = Enum.Font.${val}`);
			else if (k === "TextXAlignment" || k === "TextYAlignment")
				out.push(`${pad}\t${v}.${k} = Enum.${k}.${val}`);
			else out.push(`${pad}\t${v}.${k} = ${JSON.stringify(val)}`);
			continue;
		}
		if (typeof val === "boolean") {
			out.push(`${pad}\t${v}.${k} = ${val}`);
			continue;
		}
		if (typeof val === "number") out.push(`${pad}\t${v}.${k} = ${val}`);
	}
	// Bordes redondeados: `card` y las barras los declaran aparte.
	for (const [k, child] of Object.entries(node)) {
		if (k === "$properties") continue;
		if (child && child.$className === "UICorner") {
			const r = child.$properties.CornerRadius.UDim;
			out.push(`${pad}\tlocal c${depth} = Instance.new("UICorner")`);
			out.push(`${pad}\tc${depth}.CornerRadius = UDim.new(${r[0]}, ${r[1]})`);
			out.push(`${pad}\tc${depth}.Parent = ${v}`);
		} else if (child && child.$className === "UIStroke") {
			const p = child.$properties;
			const c = p.Color.map((x) => Math.round(x * 255)).join(", ");
			out.push(`${pad}\tlocal s${depth} = Instance.new("UIStroke")`);
			out.push(`${pad}\ts${depth}.Color = Color3.fromRGB(${c})`);
			out.push(`${pad}\ts${depth}.Thickness = ${p.Thickness}`);
			out.push(`${pad}\ts${depth}.Transparency = ${p.Transparency}`);
			out.push(`${pad}\ts${depth}.Parent = ${v}`);
		}
	}
	for (const [k, child] of Object.entries(node)) {
		if (k === "$properties") continue;
		if (Array.isArray(child)) {
			child.forEach((c) => emit(c, v, out, depth + 1, c.name || k));
		} else if (child && typeof child === "object" && child.$className) {
			emit(child, v, out, depth + 1, child.name || k);
		}
	}
	out.push(`${pad}\t${v}.Parent = ${parentExpr}`);
	out.push(`${pad}end`);
}

const CODE = `
local Players = game:GetService("Players")
local player = Players.LocalPlayer
if not player then return "sin jugador local" end
local gui = player:FindFirstChildOfClass("PlayerGui")
if not gui then return "sin PlayerGui" end
local old = gui:FindFirstChild("KeshusyHUD")
if old then old:Destroy() end
local starter = game:GetService("StarterGui"):FindFirstChild("KeshusyHUD")
${""}
`;

const CODE = `
local Players = game:GetService("Players")
local player = Players.LocalPlayer
if not player then return "sin jugador local (sesion de edicion)" end
local gui = player:FindFirstChildOfClass("PlayerGui")
local hud = gui and gui:FindFirstChild("KeshusyHUD")
local out = {}
if not hud then return "KeshusyHUD no esta en PlayerGui" end
local bb = hud:FindFirstChild("Root") and hud.Root:FindFirstChild("BottomBar")
		and hud.Root.BottomBar:FindFirstChild("BombAction")
if not bb then return "BombAction no encontrado" end
local function dump(g)
	local ap = g.AnchorPoint
	local p, s = g.Position, g.Size
	local function f(u)
		return ("s%.2f o%.1f / s%.2f o%.1f")
			:format(u.X.Scale, u.X.Offset, u.Y.Scale, u.Y.Offset)
	end
	local lines = {}
	table.insert(lines, ("%s [%s] z=%d vis=%s")
		:format(g.Name, g.ClassName, g.ZIndex, tostring(g.Visible)))
	table.insert(lines, ("   anchor=(%.2f,%.2f) pos=(%s) size=(%s)")
		:format(ap.X, ap.Y, f(p), f(s)))
	table.insert(lines, ("   abs=(%.1f,%.1f) size=(%.1f,%.1f)")
		:format(g.AbsolutePosition.X, g.AbsolutePosition.Y,
			g.AbsoluteSize.X, g.AbsoluteSize.Y))
	if g:IsA("TextLabel") or g:IsA("TextButton") then
		local c = g.TextColor3
		table.insert(lines, ("   text=%q ts=%d color=(%d,%d,%d)")
			:format(g.Text, g.TextSize, math.round(c.R * 255),
				math.round(c.G * 255), math.round(c.B * 255)))
	end
	if g:IsA("GuiObject") and not (g:IsA("TextLabel")) then
		local b = g.BackgroundColor3
		table.insert(lines, ("   bg=(%d,%d,%d) bgT=%.2f")
			:format(math.round(b.R * 255), math.round(b.G * 255),
				math.round(b.B * 255), g.BackgroundTransparency))
	end
	return table.concat(lines, "\\n")
end

table.insert(out, dump(bb))
for _, child in ipairs(bb:GetChildren()) do
	if not child:IsA("GuiObject") then continue end
	table.insert(out, dump(child))
	if child.Name == "BombVisual" then
		for _, p in ipairs(child:GetChildren()) do
			if p:IsA("GuiObject") then
				table.insert(out, "    " .. dump(p))
			end
		end
	end
end
local cam = workspace.CurrentCamera
out[#out + 1] = ("VIEWPORT %dx%d"):format(cam.ViewportSize.X, cam.ViewportSize.Y)
local sc = bb:FindFirstChildOfClass("UIScale")
out[#out + 1] = "UISCALE " .. (sc and tostring(sc.Scale) or "nil")
return table.concat(out, "\\n")
`;

mcp.init()
	.then(() => mcp.toolJson("eval_client_runtime", { code: CODE }))
	.then((r) => console.log(typeof r === "string" ? r : JSON.stringify(r, null, 2)))
	.catch((e) => console.log("MCP ERROR: " + e.message));