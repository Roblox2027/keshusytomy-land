local Players = game:GetService("Players")
local portalService = require(
	game:GetService("ServerScriptService").Services:WaitForChild("PortalService")
)

local player = Players:GetPlayers()[1]
local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")

-- MEDIDO: el portal de Forest NO esta en (0, y, -34) sino en (-32, 4.75,
-- -34). Los cinco paneles se reparten en X y cada uno pertenece a un mundo.
-- Colocar al jugador en el centro del lobby y esperar que el portal de
-- Forest funcione falla SIEMPRE por distancia, y eso no es un portal roto:
-- es estar en el portal equivocado.
if root then
	local portal = portalService.GetPortal("Forest")
	local target = if portal then portal.Position else Vector3.new(-32, 5, -34)
	root.CFrame = CFrame.new(target.X, target.Y + 1, target.Z + 2)
end

local ok, reason = portalService.TryEnter(player, "Forest")
return {
	ok = ok,
	reason = reason,
	pos = if root then tostring(root.Position) else "NONE",
	world = player:GetAttribute("World"),
}