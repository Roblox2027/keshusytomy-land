-- qa-bombplace.lua
-- Coloca una bomba con la posicion REAL del jugador y mide el resultado.
local Players = game:GetService("Players")
local Bomb = require(game.ServerScriptService.Services.BombService)

local plr = Players:GetPlayers()[1]
if not plr then
	return "sin jugadores"
end

local char = plr.Character
local root = char and char:FindFirstChild("HumanoidRootPart")
if not root then
	return "sin HumanoidRootPart"
end

local out = {}
table.insert(out, "pos real = " .. tostring(root.Position))
table.insert(out, "bombas antes = " .. tostring(Bomb.GetPlayerBombCount(plr.UserId)))

local ok, reason = Bomb.TryPlaceBomb(plr, root.Position)
table.insert(out, "TryPlaceBomb -> " .. tostring(ok) .. " motivo=" .. tostring(reason))
table.insert(out, "bombas despues = " .. tostring(Bomb.GetPlayerBombCount(plr.UserId)))

local folder = workspace:FindFirstChild("Bombs")
if folder then
	table.insert(out, "Bombs partes = " .. tostring(#folder:GetDescendants()))
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(out, "   parte " .. d.Name .. " en " .. tostring(d.Position))
		end
	end
end

return table.concat(out, "\n")