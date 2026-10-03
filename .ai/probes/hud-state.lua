-- Estado del HUD tal y como lo ve el jugador: que paneles existen, cuales
-- estan visibles y que dicen.
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("KeshusyHUD")

local out = { paneles = {} }

local function leer(panel, hijo, sub)
	local frame = gui:FindFirstChild(panel)
	if not frame then
		return { visible = false, texto = "SIN PANEL" }
	end

	local target = frame
	if hijo then
		target = frame:FindFirstChild(hijo)
		if sub and target then
			target = target:FindFirstChild(sub)
		end
	end

	local texto = "-"
	if target and target:IsA("TextLabel") then
		texto = target.Text
	elseif target and target:IsA("GuiObject") then
		local fill = target:FindFirstChild("Fill")
		if fill and fill:IsA("GuiObject") then
			texto = string.format("relleno=%.2f", fill.Size.X.Scale)
		end
	end

	return { visible = tostring(frame.Visible), texto = texto }
end

out.mundo = leer("TopBar", "World")
out.vida = leer("PlayerStats", "HPBar")
out.xp = leer("PlayerStats", "XPBar")
out.bombas = leer("BombStats", "Bombs", "Value")
out.activas = leer("ActiveBombs", "Value")
out.efectos = leer("PowerupRow", "Text")
out.objetivo = leer("Objective", "Text")
out.mision = leer("Mission", "Text")
out.tiempo = leer("Timer", "Time")
out.monedas = leer("Currency", "Coins", "Value")

return out