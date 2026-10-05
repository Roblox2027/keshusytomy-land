-- qa-edit-hud.lua
-- El DataModel de EDICION: por que el StarterGui no trae KeshusyHUD.
local out = {}
local function names(c)
	local t = {}
	for _, x in ipairs(c:GetChildren()) do
		table.insert(t, x.Name .. "[" .. x.ClassName .. "]")
	end
	return table.concat(t, ", ")
end

table.insert(out, "StarterGui: " .. names(game:GetService("StarterGui")))
table.insert(out, "StarterPlayerScripts: " .. names(game:GetService("StarterPlayer").StarterPlayerScripts))
table.insert(out, "Workspace: " .. names(workspace))
local worlds = workspace:FindFirstChild("Worlds")
if worlds then
	for _, w in ipairs(worlds:GetChildren()) do
		table.insert(out, "  World " .. w.Name .. ": " .. tostring(#w:GetChildren()) .. " hijos")
	end
end
local lobby = workspace:FindFirstChild("Lobby")
table.insert(out, "Lobby: " .. tostring(lobby and #lobby:GetChildren()))
table.insert(out, "Lighting: " .. names(game:GetService("Lighting")))

return table.concat(out, "\n")