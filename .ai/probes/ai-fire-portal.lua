-- Dispara la peticion de portal REAL desde el cliente.
--
-- Va por `FireServer` y no por una llamada directa al servicio: es el mismo
-- camino que recorre el jugador, con la misma validacion de nivel, distancia
-- al umbral, estado de ronda y cooldown. Un teleport hecho a mano probaria
-- el `PivotTo` y no la validacion, que es justo lo que hay que comprobar.
local remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
local portal = remotes:FindFirstChild("PortalAction")

if not portal then
	return { error = "PortalAction no existe" }
end

portal:FireServer("Enter", "Forest")

return { fired = true }