-- p0-bomb-watch.lua
-- SONDA de espera: mira Workspace.Bombs durante unos segundos y avisa si
-- aparece una bomba real, con su detalle.
--
-- Se ejecuta DESPUES de que el driver pulse el boton con el raton. La bomba la
-- crea el SERVIDOR, asi que su aparicion es la prueba de que la peticion fue
-- aceptada de extremo a extremo.

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local seconds = 5
local folder = Workspace:FindFirstChild("Bombs")

if not folder then
	return { error = "Workspace.Bombs no existe" }
end

local before = #folder:GetChildren()
local deadline = os.clock() + seconds
local appearedAt = nil

while os.clock() < deadline do
	if #folder:GetChildren() > before then
		appearedAt = os.clock()
		break
	end
	task.wait(0.05)
end

local detail = {}

for _, child in ipairs(folder:GetChildren()) do
	local pos = nil
	local parts = {}

	if child:IsA("Model") then
		pos = child:GetPivot().Position
		for _, p in ipairs(child:GetDescendants()) do
			if p:IsA("BasePart") then
				table.insert(parts, {
					name = p.Name,
					size = tostring(p.Size),
					transparency = p.Transparency,
					visible = p.Visible,
					anchored = p.Anchored,
					canCollide = p.CanCollide,
				})
			end
		end
	elseif child:IsA("BasePart") then
		pos = child.Position
	end

	table.insert(detail, {
		name = child.Name,
		class = child.ClassName,
		owner = child:GetAttribute("OwnerUserId"),
		world = child:GetAttribute("World"),
		fuse = child:GetAttribute("FuseRemaining"),
		visualRadius = child:GetAttribute("VisualRadius"),
		position = pos and string.format("%.1f, %.1f, %.1f", pos.X, pos.Y, pos.Z) or "n/d",
		parts = parts,
	})
end

local player = Players.LocalPlayer or Players:GetPlayers()[1]

return {
	before = before,
	after = #folder:GetChildren(),
	appeared = appearedAt ~= nil,
	detail = detail,
	playerBombs = player and player:GetAttribute("Bombs") or nil,
	playerWorld = player and player:GetAttribute("World") or nil,
	playerRound = player and player:GetAttribute("RoundState") or nil,
}