local out = {}
local player = game:GetService("Players").LocalPlayer
local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")

out.playerPos = if root then tostring(root.Position) else "NONE"
out.world = player:GetAttribute("World")
out.level = player:GetAttribute("Level")
out.portals = {}

-- Se recorren las PARTES, no los hijos directos: los portales pueden estar
-- dentro de un `Model` por mundo y `GetChildren` de la carpeta no los ve.
for _, part in ipairs(workspace:GetDescendants()) do
	if part:IsA("BasePart") then
		local name = part.Name

		if string.find(name, "Portal", 1, true) or string.find(name, "Panel", 1, true) then
			table.insert(out.portals, name .. " @ "
				.. tostring(math.floor(part.Position.X)) .. ", "
				.. tostring(math.floor(part.Position.Y)) .. ", "
				.. tostring(math.floor(part.Position.Z))
				.. " size=" .. tostring(part.Size))
		end
	end
end

return out