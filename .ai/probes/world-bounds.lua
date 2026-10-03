local out = {}
local W = game:GetService("Workspace")
local worlds = W:FindFirstChild("Worlds")
if worlds then
	for _, wd in ipairs(worlds:GetChildren()) do
		local minv, maxv
		local parts, zones, interact = 0, {}, 0
		for _, d in ipairs(wd:GetDescendants()) do
			if d:IsA("BasePart") then
				parts += 1
				local c = d.Position
				if d.Anchored then
					if not minv then
						minv = c
						maxv = c
					else
						minv = Vector3.new(math.min(minv.X, c.X), math.min(minv.Y, c.Y), math.min(minv.Z, c.Z))
						maxv = Vector3.new(math.max(maxv.X, c.X), math.max(maxv.Y, c.Y), math.max(maxv.Z, c.Z))
					end
				end
			end
			if d:IsA("Model") then
				local attrs = d:GetAttributes()
				if attrs.Zone or attrs.zone then
					zones[#zones + 1] = d.Name
				end
			end
			if d:IsA("ClickDetector") or d:IsA("ProximityPrompt") then
				interact += 1
			end
		end
		local entry = { parts = parts, zones = #zones, interactives = interact }
		if minv then
			entry.min = { math.floor(minv.X), math.floor(minv.Y), math.floor(minv.Z) }
			entry.max = { math.floor(maxv.X), math.floor(maxv.Y), math.floor(maxv.Z) }
			entry.size = { math.floor(maxv.X - minv.X), math.floor(maxv.Y - minv.Y), math.floor(maxv.Z - minv.Z) }
		end
		local kids = {}
		for _, c in ipairs(wd:GetChildren()) do
			kids[#kids + 1] = c.Name .. "[" .. c.ClassName .. "]"
		end
		entry.top = kids
		out[wd.Name] = entry
	end
end

-- Lobby bounds
local lobby = W:FindFirstChild("Lobby")
if lobby then
	local minv, maxv
	local n = 0
	for _, d in ipairs(lobby:GetDescendants()) do
		if d:IsA("BasePart") and d.Anchored then
			n += 1
			local c = d.Position
			if not minv then
				minv = c
				maxv = c
			else
				minv = Vector3.new(math.min(minv.X, c.X), math.min(minv.Y, c.Y), math.min(minv.Z, c.Z))
				maxv = Vector3.new(math.max(maxv.X, c.X), math.max(maxv.Y, c.Y), math.max(maxv.Z, c.Z))
			end
		end
	end
	out.Lobby = { parts = n, min = { math.floor(minv.X), math.floor(minv.Y), math.floor(minv.Z) }, max = { math.floor(maxv.X), math.floor(maxv.Y), math.floor(maxv.Z) } }
end

return out