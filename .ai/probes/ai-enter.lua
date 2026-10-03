-- Coloca al jugador en el umbral del portal de Forest.
--
-- SOLO mueve el personaje: entrar por el portal se dispara DESDE EL CLIENTE
-- con `PortalAction:FireServer`, porque un `FireServer` desde el servidor es
-- un error de Roblox ("can only be called from the client"). La parte de
-- moverlo se hace aqui para que la prueba del portal use la MISMA distancia
-- que tendria un jugador que camina hasta el umbral.
local Players = game:GetService("Players")
local player = Players:GetPlayers()[1]

if not player or not player.Character then
	return { error = "sin jugador" }
end

local root = player.Character:FindFirstChild("HumanoidRootPart")
if not root then
	return { error = "sin raiz" }
end

-- Posicion del UMBRAL del portal de Forest, medida en el mapa (x = -32).
root.CFrame = CFrame.new(-32, 6, -34)
root.AssemblyLinearVelocity = Vector3.zero

return {
	moved = tostring(root.Position),
	player = player.Name,
	world = player:GetAttribute("World"),
	level = player:GetAttribute("Level"),
}