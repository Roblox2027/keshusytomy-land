-- qa-hudtree.lua
-- Por que no existe KeshusyHUD en el cliente en ejecucion.
local out = {}
table.insert(out, "StarterGui children: ")

local function dump(container, prefix, depth)
	if depth > 3 then
		return
	end
	for _, child in ipairs(container:GetChildren()) do
		local n = #out
		out[n + 1] = string.format("%s%s [%s]", prefix, child.Name, child.ClassName)
		if child:IsA("GuiObject") or child:IsA("Folder") then
			dump(child, prefix .. "  ", depth + 1)
		end
	end
end

local plr = game:GetService("Players").LocalPlayer
dump(plr:WaitForChild("StarterGui"), "  ", 0)

local pg = plr:WaitForChild("PlayerGui")
table.insert(out, "PlayerGui children:")
dump(pg, "  ", 0)

table.insert(out, "PlayerScripts: ")
dump(plr:WaitForChild("PlayerScripts"), "  ", 0)

return table.concat(out, "\n")