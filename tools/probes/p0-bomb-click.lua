-- p0-bomb-click.lua
-- Reproduce la CADENA REAL de la bomba desde el cliente: pulsa el boton que ve
-- el jugador y observa que pasa en Workspace.Bombs.
--
-- Por que pulsa el BOTON y no el remoto: el enunciado pide comprobar la cadena
-- completa (INPUT -> REMOTE -> SERVIDOR -> Workspace.Bombs). Llamar a
-- `BombController.RequestPlace` desde una sonda saltaria el paso del input, que
-- es justo donde antes se rompia.
--
-- No modifica el source: solo hace lo que haria el jugador.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local player = Players.LocalPlayer

if not player then
	return { error = "sin LocalPlayer" }
end

local playerGui = player:FindFirstChildOfClass("PlayerGui")
local touch = playerGui and playerGui:FindFirstChild("TouchControls")
local button = touch and touch:FindFirstChild("BombButton")

local out = {
	buttonFound = button ~= nil,
	buttonVisible = button and button.Visible or false,
}

if not button then
	return out
end

-- Estado del mundo ANTES de pulsar.
local bombsFolder = Workspace:FindFirstChild("Bombs")
out.bombsBefore = bombsFolder and #bombsFolder:GetChildren() or -1

-- El centro del boton, en pixeles de pantalla: lo que usa la herramienta
-- `simulate_mouse_input` del MCP para hacer clic como un jugador real.
--
-- Por que NO se usa `button:Activate()`: esa via saltaria el sistema de
-- entrada del motor. El clic tiene que entrar por el raton, que es lo que
-- hace el usuario, para que la prueba signifique algo.
out.clickX = math.floor(button.AbsolutePosition.X + button.AbsoluteSize.X / 2)
out.clickY = math.floor(button.AbsolutePosition.Y + button.AbsoluteSize.Y / 2)

-- Atributos publicados por el servidor sobre el jugador: la unica prueba
-- desde el cliente de si el servidor ACEPTO la peticion.
out.serverBombs = player:GetAttribute("Bombs")
out.roundState = player:GetAttribute("RoundState")
out.world = player:GetAttribute("World")

return out