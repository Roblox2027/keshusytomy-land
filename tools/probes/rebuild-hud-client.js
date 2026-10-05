// rebuild-hud-client.js
// Reconstruye el HUD VIVO (la copia de `PlayerGui`) desde el generador.
//
// POR QUE EXISTE
// --------------
// `sync-hud.js` escribe en `StarterGui`, que es la instancia de EDICION. El HUD
// que ve el JUGADOR es una COPIA que se creo en `PlayerGui` al entrar, asi que
// regenerar `StarterGui` NO cambia lo que ya esta en pantalla: la sesion sigue
// mostrando el arbol viejo. MEDIDO: tras regenerar, `Base` seguia en 118 px y
// `State` seguia en el rango 146..164, o sea el fix del generador todavia no
// se estaba viendo.
//
// Aqui se reconstruye la copia viva con el MISMO generador (`tools/hud.js`),
// de modo que lo que se mide en PLAY es lo que el codigo dice.
//
// Uso:
//   node tools/probes/rebuild-hud-client.js          # reconstruye y mide
//   node tools/probes/rebuild-hud-client.js --dry    # solo mide, no toca nada
const mcp = require("../mcp");
const { buildHud } = require("../hud");

/**
 * Propiedades cuyo valor es un ENUM. La conversion la decide el NOMBRE y no
 * el tipo del valor: Rojo serializa los enums como CADENA y un `Text` tambien
 * lo es, asi que escribirlos como texto deja el HUD entero en blanco.
 */
const ENUM_PROPS = {
	ZIndexBehavior: "Enum.ZIndexBehavior",
	Font: "Enum.Font",
	SortOrder: "Enum.SortOrder",
	FillDirection: "Enum.FillDirection",
	HorizontalAlignment: "Enum.HorizontalAlignment",
	VerticalAlignment: "Enum.VerticalAlignment",
	TextXAlignment: "Enum.TextXAlignment",
	TextYAlignment: "Enum.TextYAlignment",
};

/** Convierte un valor del generador a Luau, decidiendo por el NOMBRE. */
function value(name, v) {
	if (v && typeof v === "object" && !Array.isArray(v)) {
		if (v.UDim2) {
			const [x, y] = v.UDim2;
			return `UDim2.new(${x[0]}, ${x[1]}, ${y[0]}, ${y[1]})`;
		}
		if (v.UDim) return `UDim.new(${v.UDim[0]}, ${v.UDim[1]})`;
		return "nil";
	}
	if (name === "AnchorPoint" && Array.isArray(v)) return `Vector2.new(${v[0]}, ${v[1]})`;
	if (Array.isArray(v)) return `Color3.fromRGB(${v.map((c) => Math.round(c * 255)).join(", ")})`;
	if (typeof v === "string") {
		const e = ENUM_PROPS[name];
		return e ? `${e}.${v}` : JSON.stringify(v);
	}
	if (typeof v === "boolean") return v ? "true" : "false";
	if (typeof v === "number") return `${v}`;
	return "nil";
}

/**
 * Emite un nodo y sus hijos.
 *
 * El NOMBRE no siempre viene en `node.name`: en la raiz lo pone el envoltorio
 * que devuelve `buildHud()` y en los HIJOS lo pone la CLAVE bajo la que cuelgan,
 * porque Rojo usa el nombre de la clave como nombre de la instancia. Por eso
 * el nombre viaja como parametro.
 */
function emit(node, parentExpr, out, depth, name) {
	const pad = "\t".repeat(depth);
	const v = `n${depth}`;
	out.push(`${pad}do`);
	out.push(`${pad}\tlocal ${v} = Instance.new(${JSON.stringify(node.$className)})`);
	out.push(`${pad}\t${v}.Name = ${JSON.stringify(name)}`);
	for (const [k, val] of Object.entries(node.$properties || {})) {
		out.push(`${pad}\t${v}.${k} = ${value(k, val)}`);
	}
	// `UICorner` y `UIStroke` son hijos declarados aparte del mapa de
	// propiedades, y se parentan a `v` justo despues de crearse.
	for (const [, child] of Object.entries(node)) {
		if (child && child.$className === "UICorner") {
			out.push(`${pad}\tlocal c${depth} = Instance.new("UICorner")`);
			out.push(`${pad}\tc${depth}.CornerRadius = ${value("CornerRadius", child.$properties.CornerRadius)}`);
			out.push(`${pad}\tc${depth}.Parent = ${v}`);
		} else if (child && child.$className === "UIStroke") {
			out.push(`${pad}\tlocal s${depth} = Instance.new("UIStroke")`);
			out.push(`${pad}\ts${depth}.Color = ${value("Color", child.$properties.Color)}`);
			out.push(`${pad}\ts${depth}.Thickness = ${child.$properties.Thickness}`);
			out.push(`${pad}\ts${depth}.Transparency = ${child.$properties.Transparency}`);
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

/**
 * Luau que MIDE la bomba viva. Cada linea es un hecho comprobable, no una
 * opinion: caja, centrado, numero de etiquetas y si el texto cae dentro del
 * boton y encima de su placa.
 */
const MEASURE = `
local Players = game:GetService("Players")
local player = Players.LocalPlayer
if not player then return "sin jugador local" end
local gui = player:FindFirstChildOfClass("PlayerGui")
if not gui then return "sin PlayerGui" end
local hud = gui:FindFirstChild("KeshusyHUD")
if not hud then return "KeshusyHUD NO esta en PlayerGui" end
local bb = hud:FindFirstChild("Root") and hud.Root:FindFirstChild("BottomBar")
		and hud.Root.BottomBar:FindFirstChild("BombAction")
if not bb then return "BombAction no encontrado" end

local out = {}
local cam = workspace.CurrentCamera
out[#out + 1] = ("VIEWPORT %dx%d"):format(cam.ViewportSize.X, cam.ViewportSize.Y)
local sc = bb:FindFirstChildOfClass("UIScale")
out[#out + 1] = "UISCALE " .. (sc and string.format("%.4f", sc.Scale) or "nil")

local function box(g)
	local p, s = g.AbsolutePosition, g.AbsoluteSize
	return ("x=[%.0f..%.0f] y=[%.0f..%.0f] (%.0fx%.0f)")
		:format(p.X, p.X + s.X, p.Y, p.Y + s.Y, s.X, s.Y)
end

out[#out + 1] = "BombAction " .. box(bb)
local centro = bb.AbsolutePosition.X + bb.AbsoluteSize.X / 2
out[#out + 1] = ("  centro x=%.1f  centroDePantalla=%.1f  DESVIO=%.1f")
	:format(centro, cam.ViewportSize.X / 2, centro - cam.ViewportSize.X / 2)

-- Un texto duplicado SERIA dos "State": se cuentan, no se buscan.
local states, hints = 0, 0
for _, c in ipairs(bb:GetChildren()) do
	if c:IsA("GuiObject") then
		if c.Name == "State" then states = states + 1 end
		if c.Name == "KeyHint" then hints = hints + 1 end
	end
end
out[#out + 1] = ("INSTANCIAS: State x%d  KeyHint x%d  -> %s")
	:format(states, hints,
		(states == 1 and hints == 1) and "OK sin duplicados" or "DUPLICADO")

for _, c in ipairs(bb:GetChildren()) do
	if not c:IsA("GuiObject") then continue end
	local line = ("  %s [%s] z=%d vis=%s %s")
		:format(c.Name, c.ClassName, c.ZIndex, tostring(c.Visible), box(c))
	local b = c.BackgroundColor3
	line = line .. (" bg=(%d,%d,%d) bgT=%.2f"):format(
		math.round(b.R * 255), math.round(b.G * 255), math.round(b.B * 255),
		c.BackgroundTransparency)
	if c:IsA("TextLabel") then
		local col = c.TextColor3
		line = line .. (" text=%q ts=%d color=(%d,%d,%d)")
			:format(c.Text, c.TextSize, math.round(col.R * 255),
				math.round(col.G * 255), math.round(col.B * 255))
	end
	out[#out + 1] = line
end

-- ¿El texto cae DENTRO de la caja del boton y ENCIMA de su placa?
local cap = bb:FindFirstChild("Caption")
local by, bh = bb.AbsolutePosition.Y, bb.AbsoluteSize.Y
for _, name in ipairs({ "KeyHint", "State" }) do
	local g = bb:FindFirstChild(name)
	if g then
		local dentro = g.AbsolutePosition.Y >= by - 0.5
			and (g.AbsolutePosition.Y + g.AbsoluteSize.Y) <= by + bh + 0.5
		local sobre = false
		if cap then
			local cp, cs = cap.AbsolutePosition, cap.AbsoluteSize
			sobre = g.AbsolutePosition.X >= cp.X - 0.5
				and (g.AbsolutePosition.X + g.AbsoluteSize.X) <= cp.X + cs.X + 0.5
				and g.AbsolutePosition.Y >= cp.Y - 0.5
				and (g.AbsolutePosition.Y + g.AbsoluteSize.Y) <= cp.Y + cs.Y + 0.5
		end
		out[#out + 1] = ("  %s dentroDelBoton=%s sobrePlaca=%s")
			:format(name, tostring(dentro), tostring(sobre))
	end
end
return table.concat(out, "\\n")
`;

async function main() {
	const dry = process.argv.includes("--dry");

	if (!dry) {
		const hud = buildHud();
		const out = [
			'local Players = game:GetService("Players")',
			"local player = Players.LocalPlayer",
			'if not player then return "sin jugador local" end',
			'local gui = player:FindFirstChildOfClass("PlayerGui")',
			'if not gui then return "sin PlayerGui" end',
			// Se borra la copia VIVA entera: si no, el HUD nuevo se apila
			// encima del viejo y aparecen dos bombas, dos "LISTO" y dos
			//plicas. Es el mismo motivo por el que `sync-hud` destruye la
			// anterior: el generador es la unica fuente del arbol.
			'local old = gui:FindFirstChild("KeshusyHUD")',
			"if old then old:Destroy() end",
		];
		emit(hud.node, "gui", out, 0, hud.name || "KeshusyHUD");
		const res = await mcp.toolJson("eval_client_runtime", { code: out.join("\n") });
		console.log("REBUILD: " + (typeof res === "string" ? res : JSON.stringify(res)));
	} else {
		console.log("modo --dry: no se toca el arbol");
	}

	const m = await mcp.toolJson("eval_client_runtime", { code: MEASURE });
	console.log(typeof m === "string" ? m : JSON.stringify(m, null, 2));
}

main().catch((e) => {
	console.error("ERROR: " + e.message);
	process.exit(1);
});