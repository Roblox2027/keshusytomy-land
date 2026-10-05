-- qa-bomb-records.lua
-- Aísla POR QUÉ la bomba no detona: compara el registro interno
-- (`_activeBombs`) con lo que hay dibujado en `Workspace.Bombs`.
--
-- LO QUE SE HA VISTO
-- ------------------
-- `qa-bomb-timer` muestra la mecha bajando 2.60 -> 0.00 y la bomba sigue en
-- pantalla cuatro segundos despues, con `explosiones` clavado. Eso descarta
-- "la mecha no corre" y deja tres posibilidades:
--   A) el registro se perdio y `detonateBomb` sale por su primera linea;
--   B) el `task.delay` nunca venció;
--   C) la bomba se coloco en una copia distinta del servicio.
-- Esta sonda imprime las CUATRA señales de cada tick (registro, modelo, mecha,
-- explosiones) para que la causa se vea en la salida y no se suponga.
local Players = game:GetService("Players")
local Bomb = require(game.ServerScriptService.Services.BombService)
local Explosion = require(game.ServerScriptService.Services.ExplosionService)

local out = {}
local player = Players:GetPlayers()[1]

--- Cuenta claves de una tabla cualquiera.
local function countKeys(map)
	local n = 0

	for _ in pairs(map) do
		n += 1
	end

	return n
end

--- Cuenta los modelos de bomba dibujados en la carpeta.
local function countModels(container)
	if container == nil then
		return 0
	end

	local n = 0

	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Model") then
			n += 1
		end
	end

	return n
end

--- Busca el modelo de la bomba con un id concreto.
local function findModel(container, bombId)
	if container == nil or bombId == nil then
		return nil
	end

	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("BombId") == bombId then
			return child
		end
	end

	return nil
end

--- Modelos en pantalla SIN registro: huella de bombas que se limpiaron por
--- una via que no paso por `detonateBomb`.
local function orphans(container, records)
	if container == nil then
		return 0
	end

	local n = 0

	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Model") then
			local bombId = child:GetAttribute("BombId")

			if bombId == nil or records[bombId] == nil then
				n += 1
			end
		end
	end

	return n
end

if not player or not player.Character then return "sin jugador" end

local rootPart = player.Character:FindFirstChild("HumanoidRootPart")

if not rootPart then return "sin HumanoidRootPart" end

-- Posicion valida: junto al jugador, no encima de un bloque.
local origin = rootPart.Position + rootPart.CFrame.LookVector * 6
local folder = Bomb._bombFolder
local explot0 = Explosion.GetExplosionCount()

out[#out + 1] = ("servicio: folder=%s registros=%d modelos=%d explosiones=%d"):format(
	if folder then folder:GetFullName() else "nil",
	countKeys(Bomb._activeBombs),
	countModels(folder),
	explot0)

local placed, reason = Bomb.TryPlaceBomb(player, origin)
out[#out + 1] = ("puesta=%s motivo=%s"):format(tostring(placed), tostring(reason))

if not placed then
	return table.concat(out, "\n")
end

-- Snapshot del estado interno inmediatamente despues de colocar: es el
-- punto donde se decide si el registro se escribio bien.
local ids = {}

for id in pairs(Bomb._activeBombs) do
	table.insert(ids, tostring(id))
end

table.sort(ids)
out[#out + 1] = ("registros tras colocar: [%s]"):format(table.concat(ids, " "))

local mine = nil

for id, record in pairs(Bomb._activeBombs) do
	if record.Position.Magnitude == origin.Magnitude then
		mine = id
	end
end

out[#out + 1] = ("registro de esta bomba: id=%s"):format(tostring(mine))

for tick = 1, 10 do
	task.wait(0.5)

	local registered = mine ~= nil and Bomb._activeBombs[mine] ~= nil
	local model = findModel(folder, mine)
	local fuse = if model then model:GetAttribute("FuseRemaining") else nil

	out[#out + 1] = ("t=%.1f | registro=%s modelo=%s mecha=%s | explosiones=%d (+%d) registros=%d"):format(
		tick * 0.5,
		tostring(registered),
		if model then "si" else "no",
		if fuse then ("%.2f"):format(fuse) else "-",
		Explosion.GetExplosionCount(),
		Explosion.GetExplosionCount() - explot0,
		countKeys(Bomb._activeBombs))
end

out[#out + 1] = ("modelos huerfanos en la carpeta: %d (existen sin registro)"):format(
	orphans(folder, Bomb._activeBombs))

-- IDENTIDAD DE DEPENDENCIAS: la pregunta que explica el sintoma.
--
-- El registro desaparece a los 3 s (o sea, `detonateBomb` SI corre y hace su
-- primera linea) pero el contador de explosiones no se mueve. Eso apunta a
-- `Service._explosionService == nil`: sin el, `detonateBomb` borra el registro
-- y el modelo, y se salta la explosion entera.
--
-- Y que el modelo siga en pantalla sugiere algo peor: que la tabla que lee esta
-- sonda no sea la misma que usa el juego. Se compara la IDENTIDAD de los
-- modulos, no su contenido.
local injected = Bomb._explosionService
local required = require(game.ServerScriptService.Services.ExplosionService)

out[#out + 1] = ("BombService._explosionService = %s"):format(tostring(injected))
out[#out + 1] = ("inyectado es el modulo requerido = %s"):format(
	tostring(injected == required))
out[#out + 1] = ("BombService._roundService = %s | _questService = %s"):format(
	tostring(Bomb._roundService), tostring(Bomb._questService))

-- Modelos duplicados por id: si hay dos modelos con el MISMO `BombId`, la
-- carpeta tiene bombas de dos Copies distintas del servicio a la vez.
local byId = {}

if folder then
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") then
			local bombId = tostring(child:GetAttribute("BombId"))
			byId[bombId] = (byId[bombId] or 0) + 1
		end
	end
end

local repes = {}

for bombId, n in pairs(byId) do
	if n > 1 then
		table.insert(repes, ("%s x%d"):format(bombId, n))
	end
end

table.sort(repes)

local repesTexto = if #repes == 0 then "ninguno" else table.concat(repes, " ")

out[#out + 1] = ("modelos por id: [%s] repetidos=[%s]"):format(
	table.concat(byId, " "), repesTexto)

-- COPIAS DEL SERVICIO: si `BombService` esta instanciado DOS veces en el
-- DataModel, cada copia tiene su propio `_nextBombId`, su propia carpeta y sus
-- propias bombas. Eso explica el sintoma completo: la copia que llama a la
-- sonda borra SU registro, y la bomba que se ve en pantalla es de la otra.
local copies = {}

for _, instance in ipairs(game:GetDescendants()) do
	if instance:IsA("ModuleScript") then
		if instance.Name == "BombService" or instance.Name == "ExplosionService" then
			table.insert(copies, ("%s [%s]"):format(
				instance:GetFullName(),
				if instance == Bomb then "<esta>" else ""))
		end
	end
end

table.sort(copies)
out[#out + 1] = ("copias del servicio en el DataModel: %d"):format(#copies)

for _, path in ipairs(copies) do
	out[#out + 1] = "  " .. path
end

out[#out + 1] = ("_nextBombId=%d (el contador de ESTA copia)"):format(Bomb._nextBombId)

-- IDENTIDAD DE LA CARPETA: la contradiccion que quedo abierta.
--
-- En la MISMA llamada el recuento de modelos da 13 y, dos lineas despues, el
-- mismo `folder:GetChildren()` no devuelve NINGUN modelo. Un `Folder` no puede
-- vaciarse solo. Solo hay dos explicaciones: la carpeta fue destruida (y
-- `_bombFolder` sigue apuntando a un objeto muerto) o `folder` no es la carpeta
-- que se esta contando.
out[#out + 1] = ("folder vivo=%s | hijos=%d | es Workspace.Bombs=%s"):format(
	tostring(folder and folder.Parent ~= nil),
	if folder then #folder:GetChildren() else -1,
	tostring(folder == workspace:FindFirstChild("Bombs")))

local live = workspace:FindFirstChild("Bombs")

if live then
	local n = 0

	for _, child in ipairs(live:GetChildren()) do
		n += 1
	end

	out[#out + 1] = ("Workspace.Bombs vivo=%s | hijos=%d"):format(
		tostring(live.Parent ~= nil), n)
end

out[#out + 1] = ("BombService: inicializado=%s"):format(tostring(Bomb.IsInitialized))

return table.concat(out, "\n")