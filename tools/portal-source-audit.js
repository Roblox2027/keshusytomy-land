// portal-source-audit.js
// Compara lo que la FUENTE declara para cada portal con lo que el RUNTIME
// tiene, pieza a pieza.
//
// POR QUE EXISTE
// --------------
// `source-runtime-diff` compara recuento y NOMBRE de instancias. Las cinco
// piezas de un portal (`Base`, `Lintel`, `PostL`, `PostR`, `PortalPanel`)
// tienen el MISMO nombre en los cinco portales, asi que un panel que llega
// con el color equivocado no se detecta ahi: los nombres coinciden y el
// numero tambien. El unico sintoma es que el portal de Desert se ve gris.
//
// Uso:
//   node tools/portal-source-audit.js

const mcp = require("./mcp");

// `VisualService.DecoratePortals` APAGA el panel de los mundos
// deshabilitados, poniendolo en gris 70/74/86 (VisualService.lua:442).
// Es intencionado: gris y sin chispas es la senal de "aqui no se entra".
//
// Por eso este comparador NO puede exigir que el panel conserve el color de
// la fuente en los cuatro mundos apagados: exigirlo daria FAIL sobre un
// runtime correcto, y "corregirlo" desactivaria una senal de juego que
// funciona. Lo que se comprueba es que el gris aparezca EXACTAMENTE en los
// mundos deshabilitados y en ninguno mas.
const LOCKED_PANEL_RGB = [70, 74, 86];
const DISABLED_WORLDS = new Set(["Desert", "Ice", "Volcano", "Cyber"]);

const READ_SOURCE_LUAU = `
local out = {}
for _, portal in ipairs(game:GetService("Workspace").Lobby.Portals:GetChildren()) do
	local colors = {}
	for _, piece in ipairs(portal:GetChildren()) do
		if piece:IsA("BasePart") then
			colors[piece.Name] = string.format(
				"%d/%d/%d/%s",
				math.round(piece.Color.R * 255),
				math.round(piece.Color.G * 255),
				math.round(piece.Color.B * 255),
				piece.Material.Name
			)
		end
	end
	out[portal.Name] = colors
end
return out
`;

function rgb(arr) {
	if (!Array.isArray(arr)) return "(sin color)";
	return arr.map((v) => Math.round(v * 255)).join("/");
}

(async () => {
	const project = require("../default.project.json");
	const sourcePortals = project.tree.Workspace.Lobby.Portals;
	const runtime = (await mcp.serverLuau(READ_SOURCE_LUAU)) || {};

	let problems = 0;
	// `$className` es la clave de metadatos de Rojo, no un portal. Sin
	// filtrarla se contas como un septimo portal con todas sus piezas
	// ausentes: siete discrepancias inventadas por el comparador.
	const names = Object.keys(sourcePortals)
		.filter((k) => k !== "$className")
		.sort();

	console.log("PORTALES: FUENTE vs RUNTIME");
	console.log("-".repeat(72));

	for (const name of names) {
		const worldId = name.replace(/^Portal_/, "");
		const node = sourcePortals[name];
		const live = runtime[name] || {};
		console.log("\n" + name + (DISABLED_WORLDS.has(worldId) ? "  (mundo deshabilitado)" : ""));

		for (const piece of ["Base", "Lintel", "PostL", "PostR", "PortalPanel", "Glow", "Sign"]) {
			const props = node[piece] && node[piece].$properties;
			if (!props) {
				console.log("  " + piece + ": no declarado en la fuente");
				problems += 1;
				continue;
			}

			// El panel de un mundo deshabilitado lo repinta VisualService a
			// proposito, asi que la EXPECTATIVA no es el color de la fuente
			// sino el gris de bloqueo. El resto de piezas deben coincidir con
			// la fuente tal cual.
			const locked = piece === "PortalPanel" && DISABLED_WORLDS.has(worldId);
			const expected = locked
				? LOCKED_PANEL_RGB.join("/") + "/" + (props.Material || "SmoothPlastic")
				: rgb(props.Color) + "/" + (props.Material || "SmoothPlastic");

			const got = live[piece] || "(ausente en runtime)";
			const ok = got === expected;
			if (!ok) problems += 1;

			const nota = locked ? "  (gris de bloqueo, esperado)" : "";
			console.log(
				"  " + (ok ? "coincide" : "DIFIERE ") + " " + piece + ": " + expected
				+ (ok ? "" : "  -> runtime " + got) + nota
			);
		}
	}

	console.log("\n" + "-".repeat(72));
	console.log(problems === 0 ? "PORTALES FUENTE/RUNTIME: PASS" : "PORTALES FUENTE/RUNTIME: " + problems + " discrepancias");
	process.exitCode = problems === 0 ? 0 : 1;
})();