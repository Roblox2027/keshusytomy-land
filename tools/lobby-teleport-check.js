// lobby-teleport-check.js
// Comprueba, paso a paso, si el teleport de diagnostico al Lobby funciona y
// si el jugador SE QUEDA alli.
//
// POR QUE EXISTE
// --------------
// `tools/client-probe.js lobby` informaba FAIL con `Lobby 0/98` visibles.
// Hay dos explicaciones muy distintas:
//
//   a) el cliente no ve el Lobby porque no lo tiene (fallo real), o
//   b) el jugador sigue en la Arena, a 500 studs, y el Lobby esta fuera de
//      rango de vision (NO es un fallo: `StreamingEnabled = false` no
//      significa "visible a distancia").
//
// El informe anterior mezclaba las dos. Aqui se mide el paso intermedio,
// que es el que decide: si el personaje llega al Lobby y se queda.
//
// Uso:  node tools/lobby-teleport-check.js

const mcp = require("./mcp");

const WHERE = `
local p = game:GetService("Players"):GetPlayers()[1]
if not p or not p.Character then return "sin jugador" end
local root = p.Character:FindFirstChild("HumanoidRootPart")
return root and string.format("%.0f,%.0f,%.0f", root.Position.X, root.Position.Y, root.Position.Z)
	or "sin HumanoidRootPart"
`;

const MOVE = `
local p = game:GetService("Players"):GetPlayers()[1]
if not p or not p.Character then return "sin jugador" end
local folder = workspace:FindFirstChild("SpawnLocations")
local best, bestDist = nil, math.huge
for _, d in ipairs(folder:GetDescendants()) do
	if d:IsA("SpawnLocation") then
		local dist = d.Position.Magnitude
		if dist < bestDist then
			bestDist, best = dist, d
		end
	end
end
if not best then return "sin SpawnLocation" end
local target = best.Position + Vector3.new(0, 3, 0)
p.Character:PivotTo(CFrame.lookAt(target, Vector3.new(0, target.Y, 0)))
return "movido a " .. best.Name
`;

(async () => {
	const before = await mcp.toolJson("eval_server_runtime", { code: WHERE });
	console.log("ANTES  :", before);

	const moved = await mcp.toolJson("eval_server_runtime", { code: MOVE });
	console.log("SALIDA :", moved);

	// Se muestrea varias veces: el ciclo de ronda revierte el traslado, asi
	// que un unico instante despues del teleport diria siempre que funciona.
	for (const wait of [500, 1500, 3000, 5000]) {
		await new Promise((r) => setTimeout(r, wait));
		const now = await mcp.toolJson("eval_server_runtime", { code: WHERE });
		console.log(`+"${wait}ms"`.padEnd(8), ":", now);
	}
})();