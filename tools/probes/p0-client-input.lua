-- p0-client-input.lua (CLIENTE)
-- Reproduce el camino REAL del jugador: F -> InputController ->
-- BombController -> Remote -> Servidor. Y mira lo que llega al cliente.
--
-- Este es el P0 de verdad: no llama a `BombService` por la puerta de atras,
-- llama a la MISMA funcion a la que llama el teclado.

local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts")
local UIS = game:GetService("UserInputService")

local out = {}
local function say(fmt, ...) table.insert(out, string.format(fmt, ...)) end

local player = Players.LocalPlayer
local character = player.Character
local root = character and character:FindFirstChild("HumanoidRootPart")

say("=== CLIENTE: camino real de entrada ===")
say("Personaje = %s", tostring(character ~= nil))

if not root then
	return table.concat(out, "\n") .. "\nsin HumanoidRootPart"
end

say("Posicion = (%.0f, %.0f, %.0f)", root.Position.X, root.Position.Y, root.Position.Z)
say("Mundo = %s", tostring(player:GetAttribute("World")))

-- CARGAR LOS CONTROLLERS por la MISMA ruta que usa ClientMain.
local function cargar(nombre)
	local scriptObj = StarterPlayer:WaitForChild("Controllers"):FindFirstChild(nombre)
	if not scriptObj then return nil, "no existe" end
	local ok, mod = pcall(require, scriptObj)
	if not ok then return nil, tostring(mod) end
	return mod, nil
end

local BombController, errB = cargar("BombController")
local InputController, errI = cargar("InputController")

say("BombController cargado = %s (%s)", tostring(BombController ~= nil), tostring(errB))
say("InputController cargado = %s (%s)", tostring(InputController ~= nil), tostring(errI))

if not BombController then
	return table.concat(out, "\n")
end

local antes = BombController.GetState()
say("")
say("BombController ANTES: activo=%s puedePedir=%s enfriamiento=%.2f enviado=%d suprimido=%d enVolo=%s",
	tostring(antes.Active), tostring(antes.CanRequest), antes.CooldownRemaining,
	antes.RequestsSent, antes.RequestsSuppressed,
	tostring(BombController.HasPendingRequest()))

-- Ver el HUD que ve el jugador de verdad.
local pgui = player:WaitForChild("PlayerGui")
local raiz = pgui:FindFirstChildWhichIsA("ScreenGui", true)
say("ScreenGui en el cliente = %s", tostring(raiz and raiz.Name))

local function ruta(root0, nombres)
	local actual = root0
	for _, n in ipairs(nombres) do
		if not actual then return nil end
		actual = actual:FindFirstChild(n)
	end
	return actual
end

local bombAction = raiz and ruta(raiz, { "Root", "BottomBar", "BombAction" })
say("Ruta HUD Root/BottomBar/BombAction = %s", tostring(bombAction ~= nil))

-- EL INPUT REAL: se llama a la MISMA funcion a la que llama la tecla F,
-- que es `InputController.RequestBombPlacement`. No se inventa una via
-- paralela: `UIS.InputBegan` no se puede disparar a mano desde una sonda
-- (`Fire` no es miembro valido de `RBXScriptSignal`), y el atajo de teclado
-- real se mide con la herramienta de simulacion de entrada del MCP.
local entradaReal = nil

if InputController then
	entradaReal = InputController.RequestBombPlacement
end

if type(entradaReal) ~= "function" then
	say("InputController no expone RequestBombPlacement; no se puede pulsar.")
	return table.concat(out, "\n")
end

say("")
say("Llamando a InputController.RequestBombPlacement (lo que hace la tecla F)...")
local enviada = entradaReal()
say("Devuelve enviada = %s", tostring(enviada))

task.wait(0.6)

local despues = BombController.GetState()
say("BombController DESPUES: enviado=%d suprimido=%d enVolo=%s puedePedir=%s",
	despues.RequestsSent, despues.RequestsSuppressed,
	tostring(BombController.HasPendingRequest()), tostring(despues.CanRequest))
say("Peticion EN VOLO tras la pulsacion = %s", tostring(BombController.HasPendingRequest()))
say("Enfriamiento restante = %.2f s", despues.CooldownRemaining)

-- ¿LLEGO AL SERVIDOR Y SE VIO EN EL CLIENTE?
local folder = workspace:FindFirstChild("Bombs")
local n = folder and #folder:GetChildren() or 0
say("")
say("Bombas visibles en Workspace.Bombs del cliente = %d", n)
say("BombRejection = %s", tostring(player:GetAttribute("BombRejection")))

-- EL P0 DEL "SOLO UNA BOMBA": si quedo una peticion en vuelo que nunca se
-- limpia, el siguiente toque se suprime para siempre.
if BombController.HasPendingRequest() then
	say("")
	say(">>> FALLO P0 CONFIRMADO: peticion en vuelo sin resolver.")
	say(">>> CanRequest sera false para siempre: el jugador solo puede")
	say(">>> colocar UNA bomba en toda la sesion.")
end

return table.concat(out, "\n")
