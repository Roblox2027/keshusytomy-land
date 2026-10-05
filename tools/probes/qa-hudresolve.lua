-- qa-hudresolve.lua
-- Comprueba que CADA ruta de COMPONENTS exista de verdad en el HUD.
local plr = game:GetService("Players").LocalPlayer
local pg = plr:WaitForChild("PlayerGui")
local hud = pg:WaitForChild("KeshusyHUD")

local PATHS = {
	{ "World", { "Root", "TopBar", "Bar", "PlayerInfo", "World" } },
	{ "Level", { "Root", "TopBar", "Bar", "PlayerInfo", "Level" } },
	{ "PlayerInfo", { "Root", "TopBar", "Bar", "PlayerInfo" } },
	{ "Currency", { "Root", "TopBar", "Bar", "Currency" } },
	{ "Mission", { "Root", "LeftPanel", "Mission" } },
	{ "MissionBody", { "Root", "LeftPanel", "Mission", "Body" } },
	{ "MissionToggle", { "Root", "LeftPanel", "Mission", "Toggle" } },
	{ "Objective", { "Root", "RightPanel", "Objective" } },
	{ "ActiveBombs", { "Root", "RightPanel", "ActiveBombs" } },
	{ "BombStats", { "Root", "BottomBar", "ContextActions", "BombStats" } },
	{ "PowerupRow", { "Root", "BottomBar", "ContextActions", "PowerupRow" } },
	{ "BombAction", { "Root", "BottomBar", "BombAction" } },
	{ "Notifications", { "Root", "CenterFeedback", "Notifications" } },
	{ "DamageNumbers", { "Root", "CenterFeedback", "DamageNumbers" } },
	{ "Timer", { "Root", "Overlays", "Timer" } },
	{ "BossBar", { "Root", "Overlays", "BossBar" } },
	{ "DamageVignette", { "Root", "Overlays", "DamageVignette" } },
}

local out = {}
local faltan = 0
for _, entry in ipairs(PATHS) do
	local key, path = entry[1], entry[2]
	local node = hud
	local where = table.concat(path, ".")
	for _, step in ipairs(path) do
		if typeof(node) == "Instance" then
			node = node:FindFirstChild(step)
		else
			node = nil
		end
		if node == nil then
			break
		end
	end
	if node then
		table.insert(out, string.format("OK   %-16s %s [%s]", key, where, node.ClassName))
	else
		faltan += 1
		table.insert(out, string.format("FALTA %-15s %s", key, where))
	end
end
table.insert(out, "faltantes = " .. faltan)
return table.concat(out, "\n")