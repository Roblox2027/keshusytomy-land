-- qa-hudpaths.lua
-- Rutas REALES del HUD en el cliente, para comparar con COMPONENTS.
local plr = game:GetService("Players").LocalPlayer
local pg = plr:WaitForChild("PlayerGui")
local hud = pg:FindFirstChild("KeshusyHUD")

if not hud then
	return "KeshusyHUD no esta en PlayerGui"
end

local out = {}
local function walk(node, prefix, depth)
	if depth > 5 then
		return
	end
	for _, child in ipairs(node:GetChildren()) do
		local line = string.format("%s%s [%s]", prefix, child.Name, child.ClassName)
		if child:IsA("GuiButton") then
			line = line .. "  <-- GUI BUTTON"
		end
		table.insert(out, line)
		walk(child, prefix .. "  ", depth + 1)
	end
end

walk(hud, "", 0)
return table.concat(out, "\n")