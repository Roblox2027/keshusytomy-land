-- Estado crudo del jugador en el servidor: sin transformaciones.
local Players = game:GetService("Players")
local out = {}

for _, p in ipairs(Players:GetPlayers()) do
	local char = p.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")

	out[p.Name] = {
		character = char and char:GetFullName() or "NINGUNO",
		root = if root then tostring(root.Position) else "NINGUNO",
		humanoid = if hum then tostring(hum.Health) else "NINGUNO",
		world = tostring(p:GetAttribute("World")),
		bombs = tostring(p:GetAttribute("Bombs")),
	}
end

out.total = #Players:GetPlayers()
return out