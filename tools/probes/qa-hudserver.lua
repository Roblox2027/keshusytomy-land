-- qa-hudserver.lua
-- El cliente MCP da timeout; el servidor si responde. El HUD se lee desde
-- StarterGui (plantilla que se clona a PlayerGui) y desde el PlayerGui real.
local Players = game:GetService("Players")

local out = {}

local function dump(container, prefix, depth)
	if depth > 4 then
		return
	end
	for _, child in ipairs(container:GetChildren()) do
		table.insert(out, string.format("%s%s [%s]", prefix, child.Name, child.ClassName))
		if child:IsA("GuiObject") or child:IsA("Folder") then
			dump(child, prefix .. "  ", depth + 1)
		end
	end
end

table.insert(out, "== StarterGui ==")
dump(game:GetService("StarterGui"), "  ", 0)

for _, plr in ipairs(Players:GetPlayers()) do
	table.insert(out, "== PlayerGui de " .. plr.Name .. " ==")
	local pg = plr:FindFirstChildOfClass("PlayerGui")
	if pg then
		dump(pg, "  ", 0)
	else
		table.insert(out, "  (sin PlayerGui)")
	end
	table.insert(out, "== StarterGui clonado en " .. plr.Name .. " ==")
	local sg = plr:FindFirstChild("StarterGui")
	if sg then
		dump(sg, "  ", 0)
	else
		table.insert(out, "  (sin StarterGui en el jugador)")
	end
end

return table.concat(out, "\n")