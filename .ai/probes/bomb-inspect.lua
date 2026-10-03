-- MEDICION DE LA BOMBA CON FUSIBLE LARGO, SOLO PARA INSPECCION.
--
-- No se toca `GameConfig`: la bomba se construye calling the visual builder
-- with the fuse attribute raised, purely so the CLIENT probe has time to
-- arrive before the 3 s real fuse ends. Lo que se mide (partes, colores,
-- tamano, cartel, aro, particulas) es EXACTAMENTE el modelo de juego.
local Players = game:GetService("Players")
local services = game:GetService("ServerScriptService").Services
local visualKit = require(game:GetService("ReplicatedStorage").Shared.Libraries.VisualKit)

local player = Players:GetPlayers()[1]

if not player or not player.Character then
	return { error = "sin jugador" }
end

local root = player.Character:FindFirstChild("HumanoidRootPart")

if not root then
	return { error = "sin raiz" }
end

local bomb = visualKit.BuildBomb("Forest", root.Position + Vector3.new(6, 0, 0), 24)
local folder = workspace:FindFirstChild("Bombs")

if not bomb or not folder then
	return { error = "sin modelo" }
end

bomb.Name = "Bomb_INSPECCION"
bomb.Parent = folder

-- 90 s de mecha: tiempo de sobra para que llegue la sonda del cliente.
bomb:SetAttribute("FuseRemaining", 90)
task.delay(90, function()
	if bomb.Parent then
		bomb:Destroy()
	end
end)

return {
	nombre = bomb.Name,
	partes = #bomb:GetChildren(),
	pos = tostring(bomb.PrimaryPart and bomb.PrimaryPart.Position or "NIL"),
}