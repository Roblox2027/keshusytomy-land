local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local lobby = Workspace:FindFirstChild("Lobby")
local out = {
	lobbyChildren = {},
	core = {},
	portals = {},
	lighting = {},
	counts = {},
}

for _, child in ipairs(lobby:GetChildren()) do
	table.insert(out.lobbyChildren, child.Name .. ":" .. child.ClassName)
end
table.sort(out.lobbyChildren)

local core = lobby:FindFirstChild("KeshusyCore")
if core then
	for _, child in ipairs(core:GetChildren()) do
		table.insert(out.core, child.Name)
	end
end

local portals = lobby:FindFirstChild("Portals")
if portals then
	for _, portal in ipairs(portals:GetChildren()) do
		local kids = {}
		local colors = {}
		for _, piece in ipairs(portal:GetChildren()) do
			table.insert(kids, piece.Name)
			if piece:IsA("BasePart") then
				table.insert(
					colors,
					string.format(
						"%s=%d/%d/%d/%s",
						piece.Name,
						math.round(piece.Color.R * 255),
						math.round(piece.Color.G * 255),
						math.round(piece.Color.B * 255),
						piece.Material.Name
					)
				)
			end
		end
		table.sort(kids)
		table.sort(colors)
		table.insert(out.portals, portal.Name .. " {" .. table.concat(kids, ",") .. "}")
		table.insert(out.portals, "   " .. table.concat(colors, " "))
	end
end

out.lighting = {
	clockTime = Lighting.ClockTime,
	brightness = Lighting.Brightness,
	ambient = tostring(Lighting.Ambient),
	hasAtmosphere = Lighting:FindFirstChildOfClass("Atmosphere") ~= nil,
	hasBloom = Lighting:FindFirstChildOfClass("BloomEffect") ~= nil,
}

local total, collidable, neon, transparent = 0, 0, 0, 0
for _, node in ipairs(Workspace:GetDescendants()) do
	if node:IsA("BasePart") then
		total += 1
		if node.CanCollide then
			collidable += 1
		end
		if node.Material == Enum.Material.Neon then
			neon += 1
		end
		if node.Transparency > 0 then
			transparent += 1
		end
	end
end

out.counts = {
	totalParts = total,
	collidable = collidable,
	neon = neon,
	translucent = transparent,
}

return out