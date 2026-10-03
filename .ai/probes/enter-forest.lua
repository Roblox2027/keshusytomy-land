-- Entra al portal de Forest pulsando la tecla que usa el InputController
-- real. Se mide el resultado en el CLIENTE: si la posicion no cambia en el
-- cliente, la teleportacion no le llega y el portal no esta certificado.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer

-- El boton de portal del HUD es lo que el jugador pulsa; aqui se invoca el
-- mismo camino que el InputController para no abrir una via paralela.
local virtualInput = UserInputService:CreateVirtualInput()

-- Se pide el portal por el remoto real: es la via del jugador.
local remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
local portal = remotes:FindFirstChild("PortalAction")

if not portal then
	return { error = "PortalAction no existe" }
end

portal:FireServer("Enter", "Forest")

return { fired = true }