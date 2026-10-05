// hud-bomb-audit.js
// AUDITORIA RUNTIME DEL HUD Y DE LA BOMBA (P0/P1).
//
// QUE MIDE Y POR QUE NO SUPONE
// ----------------------------
// El sintoma reportado es "el HUD esta desordenado y la bomba desaparecio".
// La causa puede ser CUALQUIERA de una lista larga (no se crea, invisible,
// transparency=1, fuera de viewport, tapado, size=0, destruido, duplicado), y
// por eso esta sonda NO decide nada: recorre el arbol REAL y escribe las
// MEDIDAS con las que se puede decidir despues.
//
// Uso: node tools/hud-bomb-audit.js

const mcp = require("./mcp");

const CODE = `
local Players = game:GetService("Players")
local player = Players.LocalPlayer
if not player then return "sin jugador local" end

local out = {}
local function line(s) out[#out + 1] = tostring(s) end

local cam = workspace.CurrentCamera
local vp = cam and cam.ViewportSize or Vector2.new(0, 0)
line(("VIEWPORT %.0fx%.0f"):format(vp.X, vp.Y))
line("")

local playerGui = player:FindFirstChildOfClass("PlayerGui")
local hud = playerGui and playerGui:FindFirstChild("KeshusyHUD")
if not hud then return "KeshusyHUD NO ESTA EN PlayerGui" end
line(("HUD enabled=%s order=%s inset=%s z=%s")
	:format(tostring(hud.Enabled), tostring(hud.DisplayOrder), tostring(hud.IgnoreGuiInset), tostring(hud.ZIndexBehavior)))
line("")

local function rect(g)
	local p, s = g.AbsolutePosition, g.AbsoluteSize
	return { x = p.X, y = p.Y, w = s.X, h = s.Y }
end
local function overlaps(a, b)
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

-- Recorrido completo del HUD. Se imprime TODO a proposito: el fallo anterior
-- se produjo por suprimir datos, no por dibujarlos de otra manera.
local function walk(inst, depth, budget)
	if depth > budget then return end
	local pad = string.rep("  ", depth)
	if inst:IsA("GuiObject") then
		local r = rect(inst)
		local extra = ""
		if inst:IsA("TextLabel") or inst:IsA("TextButton") then
			extra = (" text=%q ts=%d"):format(inst.Text or "", inst.TextSize or 0)
		else
			extra = (" bgT=%.2f"):format(inst.BackgroundTransparency or 0)
		end
		local off = (r.x + r.w < 0) or (r.y + r.h < 0) or (r.x > vp.X) or (r.y > vp.Y)
		line(("%s%s [%s] z=%d vis=%s box=[%.0f,%.0f %.0fx%.0f]%s%s")
			:format(pad, inst.Name, inst.ClassName, inst.ZIndex, tostring(inst.Visible),
				r.x, r.y, r.w, r.h, extra, off and "  <-- FUERA DE PANTALLA" or ""))
	end
	for _, c in ipairs(inst:GetChildren()) do
		walk(c, depth + 1, budget)
	end
end
local root = hud:FindFirstChild("Root")
if not root then
	line("Root NO EXISTE: el HUD esta vacio")
	return table.concat(out, "\\n")
end

-- 1) ZONAS: caja ABSOLUTA medida de cada zona declarada.
line("== ZONAS (caja absoluta medida)")
local ZONES = { "TopBar", "LeftPanel", "RightPanel", "BottomBar", "CenterFeedback", "Overlays" }
local boxes = {}
for _, name in ipairs(ZONES) do
	local z = root:FindFirstChild(name)
	if not z then
		line(("  %-15s FALTA"):format(name))
	else
		local r = rect(z)
		boxes[name] = r
		local sc = z:FindFirstChildOfClass("UIScale")
		line(("  %-15s box=[%.0f,%.0f %.0fx%.0f] vis=%s z=%d scale=%s")
			:format(name, r.x, r.y, r.w, r.h, tostring(z.Visible), z.ZIndex,
				sc and ("%.2f"):format(sc.Scale) or "-"))
	end
end
line("")

-- 2) SOLAPES MEDIDOS.
--
-- Se mide lo que el jugador VE, no los rectangulos de las zonas. Overlays y
-- CenterFeedback ocupan la pantalla ENTERA a proposito (guardan overlays
-- temporales y numeros de dano sobre el impacto) y no se pintan: compararlos
-- con las demas zonas daria solapes en TODAS las resoluciones y el aviso no
-- diria nada. Lo que se mide son las TARJETAS pintadas, que es donde un
-- solape es de verdad un defecto visual.
line("== SOLAPES entre CARTAS pintadas (medidos)")
local PAINTED = {
	{ name = "TopBar/Bar", path = { "TopBar", "Bar" } },
	{ name = "LeftPanel/Mission", path = { "LeftPanel", "Mission" } },
	{ name = "RightPanel/Objective", path = { "RightPanel", "Objective" } },
	{ name = "BottomBar/BombAction", path = { "BottomBar", "BombAction" } },
	{ name = "BottomBar/ContextActions", path = { "BottomBar", "ContextActions" } },
}

local paintedBoxes = {}
for _, entry in ipairs(PAINTED) do
	local node: any = root
	for _, step in ipairs(entry.path) do
		node = node and node:FindFirstChild(step)
	end
	if node and node:IsA("GuiObject") then
		paintedBoxes[#paintedBoxes + 1] = { name = entry.name, r = rect(node) }
		local r = paintedBoxes[#paintedBoxes].r
		local onScreen = r.x >= -0.5 and r.y >= -0.5 and r.x + r.w <= vp.X + 0.5 and r.y + r.h <= vp.Y + 0.5
		line(("  %-24s box=[%.0f,%.0f %.0fx%.0f] enPantalla=%s")
			:format(entry.name, r.x, r.y, r.w, r.h, tostring(onScreen)))
		if not onScreen then
			line(("    ATENCION: %s se sale de la pantalla"):format(entry.name))
		end
	else
		line(("  %s NO EXISTE"):format(entry.name))
	end
end

line("")
line("== SOLAPES entre cartas (medidos)")
local anyOverlap = false
for i = 1, #paintedBoxes do
	for j = i + 1, #paintedBoxes do
		local a, b = paintedBoxes[i], paintedBoxes[j]
		if overlaps(a.r, b.r) then
			anyOverlap = true
			line(("  %s SE SOLAPA CON %s"):format(a.name, b.name))
		end
	end
end
if not anyOverlap then line("  ninguno") end
line("")

-- 2b) BANDA CENTRAL LIBRE.
--
-- El centro de la pantalla es del GAMEPLAY. "No hay solapes" no basta: una
-- tarjeta pegada al centro puede no solaparse con nada y aun asi tapar el
-- combate. Se mide el hueco que queda entre las tarjetas de arriba y las de
-- abajo, en el ancho central de la pantalla.
local topEdge = 0
local bottomEdge = vp.Y

for _, p in ipairs(paintedBoxes) do
	local r = p.r
	if r.y < vp.Y * 0.5 then
		topEdge = math.max(topEdge, r.y + r.h)
	else
		bottomEdge = math.min(bottomEdge, r.y)
	end
end

local bandW = math.floor(vp.X * 0.34)
local bandX = (vp.X - bandW) / 2
local bandFree = bottomEdge - topEdge
line(("BANDA CENTRAL libre: %.0f px de alto (x=%.0f..%.0f, y=%.0f..%.0f)")
	:format(bandFree, bandX, bandX + bandW, topEdge, bottomEdge))
if bandFree < vp.Y * 0.30 then
	line(("  ATENCION: la banda central es solo el %.0f%% de la pantalla")
		:format((bandFree / vp.Y) * 100))
else
	line("  correcto: la banda central deja ver el gameplay")
end
line("")

-- 3) LA BOMBA: un sintoma por linea. Nada se infiere del nombre.
line("== BOMBA (sintoma por sintoma)")
local bottom = root:FindFirstChild("BottomBar")
local bb = bottom and bottom:FindFirstChild("BombAction")
if not bb then
	line("  BombAction NO EXISTE en Root/BottomBar")
else
	local r = rect(bb)
	line(("  BombAction [%s] box=[%.0f,%.0f %.0fx%.0f] vis=%s z=%d bgT=%.2f")
		:format(bb.ClassName, r.x, r.y, r.w, r.h, tostring(bb.Visible), bb.ZIndex, bb.BackgroundTransparency))
	local onScreen = (r.x >= 0 and r.y >= 0 and r.x + r.w <= vp.X and r.y + r.h <= vp.Y)
	line(("  en pantalla=%s  por encima de paneles(z>=20)=%s")
		:format(tostring(onScreen), tostring(bb.ZIndex >= 20)))

	local visual = bb:FindFirstChild("BombVisual")
	if not visual then
		line("  BombVisual FALTA (no hay marco donde dibujar)")
	else
		local vr = rect(visual)
		line(("  BombVisual box=[%.0f,%.0f %.0fx%.0f] vis=%s"):format(vr.x, vr.y, vr.w, vr.h, tostring(visual.Visible)))
		local parts = visual:GetChildren()
		line(("  piezas dibujadas: %d"):format(#parts))
		for _, p in ipairs(parts) do
			local pr = rect(p)
			line(("    %-12s [%s] box=[%.0f,%.0f %.0fx%.0f] vis=%s bgT=%.2f")
				:format(p.Name, p.ClassName, pr.x, pr.y, pr.w, pr.h, tostring(p.Visible),
					p:IsA("GuiObject") and p.BackgroundTransparency or -1))
		end
	end

	for _, name in ipairs({ "State", "KeyHint", "Cooldown", "Base" }) do
		local n = bb:FindFirstChild(name)
		if not n then
			line(("  %s FALTA"):format(name))
		elseif n:IsA("GuiObject") then
			local nr = rect(n)
			line(("  %-9s box=[%.0f,%.0f %.0fx%.0f] vis=%s%s")
				:format(name, nr.x, nr.y, nr.w, nr.h, tostring(n.Visible),
					n:IsA("TextLabel") and (" text=%q"):format(n.Text or "") or ""))
		end
	end
end

line("")

-- 4) DUPLICADOS: dos sistemas de bomba se verian aqui.
line("== DUPLICADOS DE BOMBA")
local found = 0
for _, d in ipairs(playerGui:GetChildren()) do
	if d:IsA("ScreenGui") then
		for _, c in ipairs(d:GetDescendants()) do
			if c.Name == "BombAction" or c.Name == "BombButton" or c.Name == "BombVisual" then
				found += 1
				line(("  %s/%s"):format(d.Name, c:GetFullName()))
			end
		end
	end
end
if found == 0 then line("  ninguno") end
line("")

-- 5) ARBOL COMPLETO del HUD, para composicion y legibilidad.
line("== ARBOL COMPLETO DEL HUD")
walk(root, 1, 6)

-- 6) BOMBA 3D EN EL MUNDO.
--
-- El HUD y la bomba del mundo son DOS COSAS DISTINTAS (requisito 6): que el
-- boton se vea no dice nada de que la bomba aparezca en el mundo. Se mide la
-- instancia de verdad: si existe, que tiene descendientes, que es visible de
-- verdad y que NO esta enterrada ni dentro del jugador.
local bombs = workspace:FindFirstChild("Bombs")
line("")
line("== BOMBA 3D (Workspace.Bombs)")

if not bombs then
	line("  Workspace.Bombs NO EXISTE")
else
	line(("  Bombs: %d hijo(s)"):format(#bombs:GetChildren()))

	for _, bomb in ipairs(bombs:GetChildren()) do
		local head = nil
		for _, c in ipairs(bomb:GetChildren()) do
			if c:IsA("BasePart") then head = c break end
		end
		local pos = head and head.Position or Vector3.zero
		line(("  BOMBA '%s' [%s]"):format(bomb.Name, bomb.ClassName))
		if not head then
			line("    SIN PARTES: el modelo no tiene ninguna BasePart, no se ve")
		else
			line(("    anclaje pos=(%.1f, %.1f, %.1f)"):format(pos.X, pos.Y, pos.Z))
		end

		-- Se mide CADA parte. El Root de anclaje es transparente a proposito,
		-- asi que mirar solo la primera parte daria "transparency = 1" y
		-- concluiria que la bomba es invisible cuando lo invisible es el ancla.
		local invisible = {}
		for _, c in ipairs(bomb:GetDescendants()) do
			if c:IsA("BasePart") then
				local s = c.Size
				local note = ""
				if c.Name ~= "Root" and c.Transparency >= 1 then
					table.insert(invisible, c.Name)
					note = "  <-- INVISIBLE"
				end
				if s.Magnitude < 0.5 then note = note .. "  <-- TAMANO CERO" end
				line(("    %-16s transp=%.2f size=(%.2f, %.2f, %.2f) material=%s%s")
					:format(c.Name, c.Transparency, s.X, s.Y, s.Z,
						tostring(c.Material), note))
			end
		end

		if #invisible == 0 then
			line("    todas las piezas con forma son VISIBLES")
		else
			line(("    PIEZAS INVISIBLES: %s"):format(table.concat(invisible, ", ")))
		end

		local player = Players.LocalPlayer
		local char = player and player.Character
		-- Estar DENTRO del personaje hace que la bomba no se vea sin que nada
		-- parezca roto, asi que se mide explicitamente.
		if char and head then
			line(("    dentro del personaje=%s")
				:format(tostring(head:IsDescendantOf(char))))
		end

		local names = {}
		for _, c in ipairs(bomb:GetDescendants()) do
			if c:IsA("BasePart") then table.insert(names, c.Name) end
		end
		table.sort(names)
		line(("    partes: %s"):format(#names > 0 and table.concat(names, ", ") or "NINGUNA"))
	end
end

return table.concat(out, "\\n")
`;

async function main() {
	await mcp.init();

	// Si se pasan resoluciones, se recorre cada una REDIMENSIONANDO el viewport
	// de verdad: `HudLayout` es logica pura y decir "responde bien" mirando el
	// source no certifica nada. El motor es quien coloca las zonas.
	const sizes = process.argv.slice(2);
	if (sizes.length > 0) {
		for (const size of sizes) {
			const [w, h] = size.split("x").map(Number);
			// El rol del cliente es "client-1", no "client": el nombre lo elige
			// Studio al conectar el peer.
			const set = await mcp.toolJson("execute_luau", {
				target: "client-1",
				code: `
				local cam = workspace.CurrentCamera
				if not cam then return "sin camara" end
				-- ViewportSize es de SOLO LECTURA mientras la ventana de
				-- Studio manda: en una sesion de Play con ventana fija, asignarla
				-- lanza error. Se COMPRUEBA y se avisa en vez de seguir como si
				-- nada.
				local ok, err = pcall(function()
					cam.ViewportSize = Vector2.new(${w}, ${h})
				end)
				return string.format("%s|%s|%s",
					tostring(ok), tostring(cam.ViewportSize.X), tostring(err))
				`,
			});

			// Si el viewport NO se ha cambiado, NO se mide: medir la resolucion
			// anterior y llamarlo "responsive en 375x667" es un PASS FALSO, que
			// es justo lo que esta auditoria existe para evitar.
			const raw = String(set?.returnValue ?? set?.output?.[0]?.text ?? "");
			const [okFlag, gotW] = raw.split("|");
			if (okFlag !== "true" || Math.abs(Number(gotW) - w) > 2) {
				console.log(
					`\n########## ${size} ##########\n` +
					`  NO SE PUDO CERTIFICAR: el viewport sigue en ${raw}.\n` +
					`  Motivo: ${set?.error ?? set?.message ?? "ViewportSize de solo lectura"}.\n` +
					`  Se omite en vez de reportar la resolucion anterior como si fuera esta.`
				);
				continue;
			}
			// Un frame para que el motor aplique el nuevo viewport.
			await new Promise((r) => setTimeout(r, 350));
			console.log(`\n########## ${size} ##########`);
			const res = await mcp.clientLuau(CODE);
			console.log(typeof res === "string" ? res : JSON.stringify(res, null, 2));
		}
		return;
	}

	const res = await mcp.clientLuau(CODE);
	console.log(typeof res === "string" ? res : JSON.stringify(res, null, 2));
}

// El Luau se EXPORTA para que otra sonda pueda reutilizarlo sin copiarlo. Dos
// copias de la misma pregunta acabarían divergiendo, y la que se queda vieja
// es la que sigue dando el PASS.
module.exports = { CODE };

// La sonda solo corre si este archivo es el script PRINCIPAL. Sin este
// `require.main`, importar el modulo desde otra sonda Lanzaria la auditoria
// entera como efecto secundario.
if (require.main === module) {
	main().catch((e) => {
		console.error("AUDIT ERROR: " + e.message);
		process.exit(1);
	});
}
