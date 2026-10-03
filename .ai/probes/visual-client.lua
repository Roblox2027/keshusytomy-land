local Players = game:GetService("Players")
local pl = Players.LocalPlayer
local out = {}
out.player = pl and pl.Name or "NONE"
if pl then
	local char = pl.Character
	out.character = char and char:GetFullName() or "NONE"
	if char then
		local hum = char:FindFirstChildOfClass("Humanoid")
		out.hp = hum and hum.Health or -1
		local root = char:FindFirstChild("HumanoidRootPart")
		out.pos = root and tostring(root.Position) or "NONE"
		out.world = pl:GetAttribute("World")
		-- partes visibles del personaje
		local vis = {}
		for _, d in char:GetDescendants() do
			if d:IsA("BasePart") then
				vis[#vis + 1] = d.Name .. " t=" .. tostring(d.Transparency) .. " s=" .. tostring(d.Size)
			end
		end
		out.charParts = #vis
		out.charSample = vis
	end
	out.playerGui = {}
	for _, g in pl.PlayerGui:GetChildren() do
		out.playerGui[#out.playerGui + 1] = g.Name .. (g:IsA("GuiObject") and (" vis=" .. tostring(g.Enabled)) or "")
	end
end

local function scan(container, label)
	local res = { count = 0, detail = {} }
	if not container then
		res.count = -1
		return res
	end
	for _, d in container:GetDescendants() do
		if d:IsA("BasePart") then
			res.count = res.count + 1
			if #res.detail < 12 then
				res.detail[#res.detail + 1] = d:GetFullName() .. " t=" .. tostring(d.Transparency) .. " s=" .. tostring(d.Size)
					.. " anc=" .. tostring(d.Anchored)
			end
		end
	end
	return res
end

out.bombsFolder = workspace:FindFirstChild("Bombs")
out.bombs = scan(workspace:FindFirstChild("Bombs"), "bombs")
out.monsters = {}
for _, name in ipairs({ "Monsters", "Enemies" }) do
	if workspace:FindFirstChild(name) then
		local f = workspace[name]
		local n = 0
		local d = {}
		for _, m in ipairs(f:GetChildren()) do
			if m:IsA("Model") then
				n = n + 1
				if #d < 8 then
					local hum = m:FindFirstChildOfClass("Humanoid")
					d[#d + 1] = m:GetFullName() .. " parts=" .. tostring(#m:GetChildren())
						.. " pp=" .. tostring(m.PrimaryPart ~= nil)
						.. " hp=" .. tostring(hum and hum.Health)
				end
			end
		end
		out.monsters[name] = { models = n, detail = d }
	end
end
out.workspaceChildren = {}
for _, c in ipairs(workspace:GetChildren()) do
	out.workspaceChildren[#out.workspaceChildren + 1] = c.Name .. " [" .. c.ClassName .. "]"
end
out.camera = workspace.CurrentCamera and tostring(workspace.CurrentCamera.CameraType) or "NONE"

return out