return (function()
	local o = {}
	local services = {
		"Workspace", "ReplicatedStorage", "ServerScriptService", "StarterGui",
		"StarterPlayer", "ServerStorage", "Lighting", "SoundService", "Teams",
	}
	for _, s in ipairs(services) do
		local ok, svc = pcall(function() return game:GetService(s) end)
		if ok and svc then
			local kids = {}
			for _, c in ipairs(svc:GetChildren()) do
				table.insert(kids, c.Name .. "(" .. c.ClassName .. ")")
			end
			table.sort(kids)
			o[s] = "[" .. #kids .. "] " .. table.concat(kids, ", ")
		else
			o[s] = "<error>"
		end
	end
	return o
end)()
