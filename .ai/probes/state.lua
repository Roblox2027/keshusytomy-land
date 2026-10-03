local players = game:GetService("Players")
local out = {}
out.name = game.Name
out.players = #players:GetPlayers()
for _, p in ipairs(players:GetPlayers()) do
	local c = p.Character
	table.insert(out, {
		name = p.Name,
		userId = p.UserId,
		world = p:GetAttribute("World"),
		level = p:GetAttribute("Level"),
		hp = p:GetAttribute("Health"),
		char = c and c.Name or "nil",
		pos = c and string.format("%.0f,%.1f,%.0f", c.HumanoidRootPart.Position.X, c.HumanoidRootPart.Position.Y, c.HumanoidRootPart.Position.Z) or "-",
	})
end
out.workspaceChildren = {}
for _, child in ipairs(workspace:GetChildren()) do
	table.insert(out.workspaceChildren, child.Name .. " (" .. child.ClassName .. ") children=" .. #child:GetChildren())
end
return out