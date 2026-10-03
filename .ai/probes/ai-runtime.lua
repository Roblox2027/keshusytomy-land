local out = {}
local folder = workspace:FindFirstChild("Monsters")
out.exists = folder ~= nil
out.count = 0
out.states = {}
out.speeds = {}

if folder then
	for _, model in ipairs(folder:GetChildren()) do
		out.count += 1
		local state = tostring(model:GetAttribute("AIState"))
		out.states[state] = (out.states[state] or 0) + 1

		local hum = model:FindFirstChildOfClass("Humanoid")
		if hum then
			out.speeds[math.floor(hum.WalkSpeed * 10) / 10] = true
		end

		if out.count <= 3 then
			local label = model:FindFirstChild("NameTag", true)
				and model:FindFirstChild("NameTag", true):FindFirstChild("StateLabel")
			local glow = model:FindFirstChild("TelegraphGlow", true)
			out[("m%d"):format(out.count)] = {
				state = state,
				label = label and label.Text or "nil",
				labelVisible = label and label.Visible or nil,
				glow = glow and glow.Transparency or nil,
				health = hum and hum.Health or nil,
				primaryPart = model.PrimaryPart and model.PrimaryPart.Name or nil,
			}
		end
	end
end

-- El jugador: referencia para comparar velocidades.
local pl = game:GetService("Players"):GetPlayers()[1]
if pl and pl.Character then
	local hum = pl.Character:FindFirstChildOfClass("Humanoid")
	out.playerSpeed = hum and hum.WalkSpeed
	local root = pl.Character:FindFirstChild("HumanoidRootPart")
	if root then
		out.playerPos = tostring(root.Position)
	end

	-- Distancia al monstruo mas cercano: con esto se mide la carrera.
	if folder then
		local best = math.huge
		for _, model in ipairs(folder:GetChildren()) do
			local m = model.PrimaryPart
			if m then
				local d = (m.Position - root.Position).Magnitude
				if d < best then best = d end
			end
		end
		out.nearestMonster = best
	end
end

return out