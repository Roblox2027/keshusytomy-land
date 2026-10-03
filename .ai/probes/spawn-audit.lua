-- spawn-audit.lua: donde aparece el jugador y que hay alrededor.
local Players = game:GetService("Players")
local p = Players:GetPlayers()[1]
local out = {}
if not p then return "no hay jugador" end
out[#out+1] = "pos jugador = " .. tostring(p.Character and p.Character:FindFirstChild("HumanoidRootPart").Position)
out[#out+1] = "--- SpawnLocations ---"
for _, d in ipairs(workspace:GetDescendants()) do
	if d:IsA("SpawnLocation") then
		out[#out+1] = string.format("%s en (%.0f,%.0f,%.0f) neutral=%s enabled=%s dur=%s",
			d:GetFullName(), d.Position.X, d.Position.Y, d.Position.Z,
			tostring(d.Neutral), tostring(d.Enabled), tostring(d.Duration))
	end
end
out[#out+1] = "--- piezas del Core ---"
local core = workspace.Lobby and workspace.Lobby:FindFirstChild("KeshusyCore")
if core then
	for _, c in ipairs(core:GetChildren()) do
		if c:IsA("BasePart") then
			out[#out+1] = string.format("%s (%.0f,%.0f,%.0f) collide=%s trans=%s mat=%s",
				c.Name, c.Position.X, c.Position.Y, c.Position.Z,
				tostring(c.CanCollide), tostring(c.Transparency), tostring(c.Material))
		end
	end
end
return table.concat(out, "\n")