-- Muestra al ESPECTADOR de la maquina de estados: cada monstruo avanza su
-- `TimeInState` como haria `StepAI` y se registra la secuencia de estados.
--
-- Se mide DURANTE la partida, con el jugador quieto en la arena y los
-- monstruos a 30 studs: es exactamente la distancia de deteccion de un
-- Slime, asi que se debe ver la cadena completa
-- Patrol -> Detect -> Warning -> Chase.
--
-- Si un estado NO aparece, ese estado es inalcanzable en el juego real, por
-- muy correcto que sea el codigo. Por eso se mide en vez de deducirse.
local folder = workspace:FindFirstChild("Monsters")
if not folder then
	return { error = "sin carpeta Monsters" }
end

local player = game:GetService("Players"):GetPlayers()[1]
if not player or not player.Character then
	return { error = "sin jugador" }
end

local root = player.Character:FindFirstChild("HumanoidRootPart")
if not root then
	return { error = "sin raiz" }
end

-- El jugador se queda QUIETO en el centro de la arena: asi los monstruos se
-- acercan por su cuenta y se puede ver el ciclo entero sin que el jugador
-- lo altere huyendo.
local AI = require(game:GetService("ReplicatedStorage").Shared.Libraries.AIService)

local samples = {}
local startPos = {}

for _, model in ipairs(folder:GetChildren()) do
	local m = model.PrimaryPart
	if m then
		startPos[model] = m.Position
		model:SetAttribute("ProbeStartX", m.Position.X)
		model:SetAttribute("ProbeStartZ", m.Position.Z)
	end
end

for step = 1, 40 do
	task.wait(0.25)

	for _, model in ipairs(folder:GetChildren()) do
		local state = tostring(model:GetAttribute("AIState"))
		local hum = model:FindFirstChildOfClass("Humanoid")

		samples[model.Name] = samples[model.Name] or {}
		local list = samples[model.Name]

		local last = list[#list]
		if not last or last.state ~= state then
			table.insert(list, ("%d: %s (v=%.1f, d=%.1f)"):format(
				step,
				state,
				hum and hum.WalkSpeed or -1,
				model.PrimaryPart and (model.PrimaryPart.Position - root.Position).Magnitude or -1
			))
		end
	end
end

-- Se mide cuanto se ha movido cada monstruo en 10 s de reloj: eso dice si
-- patrulla de verdad o si esta clavado.
local moved = {}
for _, model in ipairs(folder:GetChildren()) do
	local m = model.PrimaryPart
	local sx = model:GetAttribute("ProbeStartX")
	local sz = model:GetAttribute("ProbeStartZ")
	if m and sx and sz then
		moved[model.Name] = math.floor(
			math.sqrt((m.Position.X - sx) ^ 2 + (m.Position.Z - sz) ^ 2)
		)
	end
end

return { samples = samples, moved = moved }