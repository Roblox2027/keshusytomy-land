-- qa-playerstate.lua
-- Donde esta el jugador y por que el servidor rechaza la bomba.
local Players = game:GetService("Players")
local out = {}

local function r(v)
	return math.floor(v * 10) / 10
end

for _, plr in ipairs(Players:GetPlayers()) do
	local char = plr.Character
	table.insert(out, "== " .. plr.Name)
	table.insert(out, "   attr World=" .. tostring(plr:GetAttribute("World")))
	if not char then
		table.insert(out, "   sin Character todavia")
		continue
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	if root then
		local p = root.Position
		table.insert(out, string.format("   pos = (%.1f, %.1f, %.1f)", r(p.X), r(p.Y), r(p.Z)))
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		table.insert(out, string.format("   vida = %.0f  FloorMaterial=%s", hum.Health, tostring(hum.FloorMaterial)))
	end
	-- SpawnLocation real
	local sp = workspace:FindFirstChild("SpawnLocations")
	if sp then
		for _, s in ipairs(sp:GetChildren()) do
			if s:IsA("SpawnLocation") then
				local p = s.Position
				table.insert(out, string.format("   spawn %s = (%.1f, %.1f, %.1f)", s.Name, r(p.X), r(p.Y), r(p.Z)))
			end
		end
	end
end

return table.concat(out, "\n")