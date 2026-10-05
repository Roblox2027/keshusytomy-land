-- b1-boot.lua (SERVIDOR)
-- BLOQUE 1: estado inicial. SIN ESPERAS. Debe caber en el timeout del puente.
local Players = game:GetService("Players")
local out = {}
local function say(f, ...) table.insert(out, string.format(f, ...)) end

local p = Players:GetPlayers()[1]
say("player = %s", tostring(p and p.Name))
if not p then return table.concat(out, "\n") end

say("character = %s", tostring(p.Character))
local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
say("humanoid = %s health = %s", tostring(hum), tostring(hum and hum.Health))

say("Lobby = %s", tostring(workspace:FindFirstChild("Lobby") ~= nil))
say("SpawnLocations = %d", #workspace:FindFirstChild("SpawnLocations"):GetChildren())

local portals = workspace.Lobby:FindFirstChild("Portals")
say("Portals = %s", tostring(portals ~= nil))
if portals then
	local n = #portals:GetChildren()
	say("portales en el mapa = %d", n)
	for _, c in ipairs(portals:GetChildren()) do
		say("  %s", c.Name)
	end
	say("Portal_Forest = %s", tostring(portals:FindFirstChild("Portal_Forest") ~= nil))
end

local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
say("pos = %s", root and ("(%.0f, %.0f, %.0f)"):format(
	root.Position.X, root.Position.Y, root.Position.Z) or "-")
say("World attr = %s", tostring(p:GetAttribute("World")))

return table.concat(out, "\n")