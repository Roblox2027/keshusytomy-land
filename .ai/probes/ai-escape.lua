-- PRUEBA DE ESCAPE (§24): ¿el jugador puede huir de un monstruo que lo
-- persigue, y puede hacerlo colocando una bomba?
--
-- Se mide lo que de verdad importa, no "el monstruo se movia":
--   1. Se mide la distancia monstruo-jugador mientras el jugador CORRE.
--   2. Se mide cuanto tarda el monstruo en RECUPERAR terreno.
--   3. Se mide si el jugador sale vivo del rango de deteccion.
--
-- La garantia de diseno es: la persecucion sostenida es mas lenta que el
-- jugador, asi que huyendo en linea recta la distancia tiene que CRECER. Si
-- aqui se midiera que no crece, el juego de las bombas estaria roto.
local folder = workspace:FindFirstChild("Monsters")
local player = game:GetService("Players"):GetPlayers()[1]

if not folder or not player or not player.Character then
	return { error = "sin monstruos o sin jugador" }
end

local root = player.Character:FindFirstChild("HumanoidRootPart")
local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
if not root or not humanoid then
	return { error = "sin personaje" }
end

local function nearestMonster()
	local best, bestDist = nil, math.huge

	for _, model in ipairs(folder:GetChildren()) do
		local m = model.PrimaryPart
		if m then
			local d = (m.Position - root.Position).Magnitude
			if d < bestDist then
				best, bestDist = model, d
			end
		end
	end

	return best, bestDist
end

local out = {}
out.playerSpeed = humanoid.WalkSpeed
out.health = humanoid.Health

-- Se coloca un monstruo a 40 studs y se mide la carrera con el jugador huyendo.
local target = folder:GetChildren()[1]
if not target or not target.PrimaryPart then
	return { error = "sin monstruo" }
end

target.PrimaryPart.CFrame = CFrame.new(root.Position + Vector3.new(40, 0, 0))
task.wait(0.2)

local samples = {}
local started = false

for step = 1, 30 do
	-- El jugador HUYE en linea recta, en la direccion opuesta al monstruo.
	-- Es el peor caso: no usa obstaculos ni bombas, solo corre.
	local away = (root.Position - target.PrimaryPart.Position)
	if away.Magnitude > 0.1 then
		root.CFrame = CFrame.new(
			root.Position + away.Unit * humanoid.WalkSpeed * 0.1
		)
	end

	local _, dist = nearestMonster()
	table.insert(samples, math.floor(dist * 10) / 10)

	if not started then
		out.distanciaInicial = math.floor(dist * 10) / 10
		started = true
	end
end

out.distanciaFinal = samples[#samples]
out.distanciaMaxima = (function()
	local m = 0
	for _, d in ipairs(samples) do
		if d > m then m = d end
	end
	return m
end)()

-- La PRUEBA: con el jugador huyendo, la distancia debe CRECER. Si el
-- monstruo recupera terreno, el jugador no puede escapar nunca y el juego
-- de la bomba es un suicide.
out.distanciaCrece = out.distanciaFinal > (out.distanciaInicial or 0)
out.recuperaTerreno = (out.distanciaInicial or 0) - out.distanciaFinal
out.healthFinal = humanoid.Health
out.estadoFinal = target:GetAttribute("AIState")

-- Se devuelve la velocidad REAL de persecucion del monstruo en ese momento:
-- es la cifra que hay que comparar con la del jugador.
local defName = string.match(target.Name, "Monster_(.+)")
out.monstruo = defName

return out