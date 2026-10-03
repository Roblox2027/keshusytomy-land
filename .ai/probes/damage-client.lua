-- Comprueba el feedback de DANO desde el cliente.
--
-- El dano lo aplica el `Humanoid` (la vida la lleva el servidor), pero la
-- MEDICION se hace aqui, en el cliente: numeros flotantes y borde rojo. Lo que
-- importa no es que la vida baje, sino que el jugador VE algo.
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local out = {}

local gui = player:WaitForChild("PlayerGui"):WaitForChild("KeshusyHUD")
local numeros = gui:WaitForChild("DamageNumbers")
local borde = gui:WaitForChild("DamageVignette")

local function contar()
	local total = 0
	local ultimo = nil

	for _, child in ipairs(numeros:GetChildren()) do
		if child:IsA("TextLabel") then
			total += 1
			ultimo = child.Text
		end
	end

	return total, ultimo
end

out.antes = (contar())
out.bordeExiste = borde ~= nil

local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")

if humanoid then
	local antes = math.ceil(humanoid.Health)
	humanoid:TakeDamage(35)
	out.hpAntes = antes
	out.hpDespues = tostring(math.ceil(humanoid.Health))
end

-- El numero aparece en el MISMO instante que el dano: se leen varios frames.
for _ = 1, 12 do
	task.wait(0.05)

	local total, ultimo = contar()

	if total > 0 then
		out.vistos = total
		out.texto = ultimo
		break
	end
end

return out