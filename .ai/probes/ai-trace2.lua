-- Traza la maquina de estados DESDE EL NACIMIENTO del monstruo.
--
-- El intento anterior empezo 6 s despues de entrar al portal, y para entonces
-- los monstruos ya habian pasado `Detect` y `Warning`: no es que falten, es
-- que se habian perdido de vista. Aqui se ESPERA a que aparezca el primer
-- monstruo y se empieza a muestrear en ese instante.
--
-- Se mide DURANTE la partida real, con el jugador quieto: la unica forma
-- sabia de saber si un estado es alcanzable de verdad.
local folder = workspace:FindFirstChild("Monsters")

if not folder then
	return { error = "sin carpeta Monsters" }
end

local AI = require(game:GetService("ReplicatedStorage").Shared.Libraries.AIService)

-- 1. Espera a que haya monstruos (maximo 25 s).
local waited = 0
while #folder:GetChildren() == 0 and waited < 25 do
	task.wait(0.25)
	waited += 0.25
end

if #folder:GetChildren() == 0 then
	return { error = "no aparecieron monstruos en 25s" }
end

-- 2. Traza. Se usa el indice del modelo, no su nombre: puede haber dos
-- monstruos del mismo tipo y con el nombre se pisarian.
local traces = {}
local alive = {}

for step = 1, 60 do
	task.wait(0.1)

	local index = 0

	for _, model in ipairs(folder:GetChildren()) do
		index += 1
		local key = ("%s#%d"):format(model.Name, index)
		local state = tostring(model:GetAttribute("AIState"))

		traces[key] = traces[key] or {}
		local list = traces[key]

		if list[#list] ~= state then
			table.insert(list, state)
		end

		alive[key] = model:GetAttribute("AIState")
	end
end

-- 3. Resumen: que estados ha visto CADA monstruo.
local summary = {}
local allStates = {}

for key, list in pairs(traces) do
	local seen = {}
	for _, state in ipairs(list) do
		seen[state] = true
		allStates[state] = true
	end

	summary[key] = {
		states = list,
		final = alive[key],
		patrol = seen["Patrol"] == true,
		detect = seen["Detect"] == true,
		warning = seen["Warning"] == true,
		chase = seen["Chase"] == true,
		attack = seen["Attack"] == true,
		recovery = seen["Recovery"] == true,
	}
end

local reached = {}
for state in pairs(allStates) do
	reached[#reached + 1] = state
end
table.sort(reached)

return { resumen = summary, estadosVistos = reached, muestras = #folder:GetChildren() }