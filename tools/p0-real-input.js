// p0-real-input.js
// CERTIFICACION E2E DEL P0 DE LA BOMBA, en una sesion de Play real.
//
// Que mide y por que desde el SERVIDOR
// ------------------------------------
// La pregunta del P0 es "el jugador VE la bomba", asi que lo que se mira es
// la carpeta Workspace.Bombs del mundo real, muestreada cada 50 ms. Asi no se
// pierde un pico de dos bombas que dure menos que el sondeo.
//
// Las peticiones salen del CLIENTE por el remoto real (BombAction:Place), que
// es exactamente lo que hace la tecla F. Se usa el remoto y no el atajo de
// la sonda porque el atajo se saltaria el gateway, el filtro de red y
// BombService: son justo las etapas que se están diagnosticando.
//
// La ronda SOLO arranca con un jugador DENTRO de una arena, asi que el guion
// es: entrar por el portal, esperar a Playing, y entonces pedir las bombas.
// Pedirlas en el lobby mide el estado de ronda, que no es lo que se busca.

const mcp = require("./mcp");

function log(...args) {
	console.log(...args);
}

// --- Sondas Luau --------------------------------------------------------
//
// Nota de estilo: estos bloques NO llevan acentos en los comentarios. Van
// dentro de plantillas de JavaScript y una tilde invertida o un caracter no
// ASCII rompe el archivo entero con un error que no señala la linea real.

const ENTRAR = `
local Players = game:GetService("Players")
local Portal = require(game.ServerScriptService.Services.PortalService)
local player = Players:GetPlayers()[1]
if not player or not player.Character then return "sin jugador" end

local p = Portal.GetPortal("Forest")
if not p then return "sin portal Forest" end

-- El portal se consulta ANTES de mover a nadie.
--
-- MEDIDO: la primera version colocaba al jugador junto al portal y luego
-- llamaba a TryEnter. Si el portal estaba ocupado ("hay una ronda en
-- curso"), el desplazamiento ya habia ocurrido y el jugador se quedaba en el
-- LOBBY con el atributo World diciendo Forest. Eso produce un informe
-- contradictorio que parece un fallo del mapa y es un fallo de la sonda.
local permitido, motivo = Portal.CanTravel(player, "Forest")

if not permitido then
	return ("CanTravel = false (%s); el jugador NO se mueve"):format(tostring(motivo))
end

player.Character:PivotTo(CFrame.new(p.Position + Vector3.new(0, 4, 0)))
local ok, motivo2 = Portal.TryEnter(player, "Forest")

return ("TryEnter -> %s (%s), mundo=%s"):format(tostring(ok), tostring(motivo2),
	tostring(player:GetAttribute("World")))
`;

const ESPERAR_RONDA = `
local Round = require(game.ServerScriptService.Services.RoundService)
for _ = 1, 60 do
	if Round.IsPlaying() then
		return "Playing"
	end
	task.wait(0.5)
end
return "la ronda NO llego a Playing (estado " .. tostring(Round.GetState()) .. ")"
`;

const PEDIR_UNA = `
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
local remoto = RS:WaitForChild("Remotes"):FindFirstChild("BombAction")
if not root or not remoto then return "sin root o sin remoto" end
remoto:FireServer("Place", root.Position)
return "una peticion desde " .. player.Name
`;

const PEDIR_DOS = `
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
local remoto = RS:WaitForChild("Remotes"):FindFirstChild("BombAction")
if not root or not remoto then return "sin root o sin remoto" end

-- Dos puntos DISTINTOS y separados: si compartieran posicion, la prueba de
-- "son independientes" no valdria nada.
local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
local side = Vector3.new(-look.Z, 0, look.X)

remoto:FireServer("Place", root.Position + look * 9)
remoto:FireServer("Place", root.Position + look * 9 + side * 9)
return "dos peticiones desde " .. player.Name
`;

// Muestrea Workspace.Bombs durante una ventana y devuelve el HISTORIAL de
// como cambia el numero de bombas. Se muestrea en vez de leer una foto porque
// dos bombas que coexisten menos de medio segundo se perderian en una foto.
const OBSERVADOR = (ventana) => `
local Players = game:GetService("Players")
local Bomb = require(game.ServerScriptService.Services.BombService)
local Round = require(game.ServerScriptService.Services.RoundService)
local player = Players:GetPlayers()[1]
local folder = Bomb._bombFolder
local out = {}

local function fila(t, lista)
	local nombres = {}
	for _, m in ipairs(lista) do
		local p = m.PrimaryPart
		local solidas = 0
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") and d.Transparency < 1 then
				solidas += 1
			end
		end
		table.insert(nombres, ("id=%s en (%s) visibles=%d"):format(
			tostring(m:GetAttribute("BombId")),
			p and string.format("%.0f,%.0f,%.0f", p.Position.X, p.Position.Y, p.Position.Z) or "?",
			solidas))
	end
	table.insert(out, ("  t=%5.2fs  bombas=%d  [%s]"):format(t, #lista, table.concat(nombres, "  ")))
end

local actual = folder:GetChildren()
fila(0, actual)

local limite = ${ventana}
local paso = 0.05
local t = 0
local maximo = #actual

while t < limite do
	task.wait(paso)
	t += paso
	local ahora = folder:GetChildren()

	if #ahora ~= #actual then
		fila(t, ahora)
		maximo = math.max(maximo, #ahora)
	end

	actual = ahora
end

local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
local mundo = player:GetAttribute("World")

table.insert(out, "")
table.insert(out, ("Ronda=%s mundo=%s capacidad=%d"):format(
	tostring(Round.GetState()), tostring(mundo), Bomb.GetPlayerCapacity(player.UserId)))
table.insert(out, ("Jugador en (%s)"):format(root and string.format("%.0f,%.0f,%.0f",
	root.Position.X, root.Position.Y, root.Position.Z) or "?"))
table.insert(out, ("BombRejection=%s Bombs=%s"):format(
	tostring(player:GetAttribute("BombRejection")), tostring(player:GetAttribute("Bombs"))))
table.insert(out, ("MAXIMO DE BOMBAS SIMULTANEAS = %d"):format(maximo))

return table.concat(out, "\\n")
`;

async function observar(ventana) {
	const r = await mcp.serverLuau(OBSERVADOR(ventana));
	return typeof r === "string" ? r : JSON.stringify(r);
}

async function enServidor(codigo) {
	const r = await mcp.serverLuau(codigo);
	return typeof r === "string" ? r : JSON.stringify(r);
}

async function enCliente(codigo) {
	const r = await mcp.clientLuau(codigo);
	return typeof r === "string" ? r : JSON.stringify(r);
}

async function main() {
	await mcp.init();

	log("=== P0: LA BOMBA, DE PRINCIPIO A FIN ===\n");

	log("--- 1. Entrar en Forest por el portal real ---");
	log(await enServidor(ENTRAR));
	log(await enServidor(ESPERAR_RONDA));

	log("\n--- 2. Una peticion (ventana de 4 s, la mecha son 3) ---");
	log(await enCliente(PEDIR_UNA));
	log(await observar(4));

	log("\n--- 3. Dos peticiones A LA VEZ (ventana de 2.5 s) ---");
	log(await enCliente(PEDIR_DOS));
	log(await observar(2.5));
}

main().catch((e) => {
	console.error("FALLO: " + e.message);
	process.exit(1);
});
